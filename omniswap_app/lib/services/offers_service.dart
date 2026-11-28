import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/item_condition.dart';
import '../models/offer_summary.dart';
import 'offer_service.dart' show OfferException;

/// Reads and updates the signed-in user's offers (sent and received).
/// Creating an offer lives in OfferService.
class OffersService {
  OffersService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _imageBucket = 'item-images';
  static const int _signedUrlSeconds = 60 * 60;

  static const String _offerSelect =
      'id, offerer_id, target_post_id, target_owner_id, status, created_at, '
      'offer_items(item_id)';

  String get currentUserId {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('No signed-in user.');
    return user.id;
  }

  /// Every offer I sent or received, newest first.
  /// Row level security already limits the rows to my own offers.
  Future<List<OfferSummary>> fetchOffers() async {
    final response = await _client
        .from('offers')
        .select(_offerSelect)
        .order('created_at', ascending: false);

    return _summarize(response as List);
  }

  /// Pending and accepted offers made on one post, newest first.
  /// Row level security shows the post owner every offer made to the post,
  /// and anyone else only the offers they made themselves.
  /// Declined and cancelled offers are left out, because their items are
  /// no longer visible to the parties.
  Future<List<OfferSummary>> fetchOffersForPost(String postId) async {
    final response = await _client
        .from('offers')
        .select(_offerSelect)
        .eq('target_post_id', postId)
        .inFilter('status', ['pending', 'accepted'])
        .order('created_at', ascending: false);

    return _summarize(response as List);
  }

  /// I made this offer and now take it back.
  Future<void> cancelOffer(String offerId) =>
      _closeOffer(offerId, 'cancelled');

  /// Someone made this offer to me and I turn it down.
  Future<void> declineOffer(String offerId) =>
      _closeOffer(offerId, 'declined');

  Future<void> _closeOffer(String offerId, String status) async {
    final rows = await _client
        .from('offers')
        .update({
      'status': status,
      'responded_at': DateTime.now().toUtc().toIso8601String(),
    })
        .eq('id', offerId)
        .eq('status', 'pending')
        .select('id');

    // Row level security matches nothing if the offer is no longer pending.
    if (rows.isEmpty) {
      throw const OfferException('This offer can no longer be changed.');
    }
  }

  // ---------------------------------------------------------------------------
  // Shared mapping from offer rows to summaries
  // ---------------------------------------------------------------------------

  Future<List<OfferSummary>> _summarize(List<dynamic> response) async {
    final me = currentUserId;

    final rows = [
      for (final row in response) row as Map<String, dynamic>,
    ];
    if (rows.isEmpty) return [];

    final itemIds = <String>{};
    final postIds = <String>{};
    final userIds = <String>{};
    for (final row in rows) {
      for (final oi in (row['offer_items'] as List<dynamic>? ?? const [])) {
        itemIds.add((oi as Map<String, dynamic>)['item_id'] as String);
      }
      postIds.add(row['target_post_id'] as String);
      userIds.add(row['offerer_id'] == me
          ? row['target_owner_id'] as String
          : row['offerer_id'] as String);
    }

    final items = await _fetchItems(itemIds);
    final posts = await _fetchPostItems(postIds);
    final names = await _fetchNames(userIds);

    final paths = <String>{
      for (final i in items.values)
        if (i.coverPath != null) i.coverPath!,
      for (final list in posts.values)
        for (final i in list)
          if (i.coverPath != null) i.coverPath!,
    };
    final urls = await _signPaths(paths);

    OfferEntry entry(_RawItem raw) => OfferEntry(
      title: raw.title,
      url: raw.coverPath == null ? null : urls[raw.coverPath],
      conditionLabel: raw.conditionLabel,
    );

    final summaries = <OfferSummary>[];
    for (final row in rows) {
      final isSent = row['offerer_id'] == me;
      final postId = row['target_post_id'] as String;
      final otherId = isSent
          ? row['target_owner_id'] as String
          : row['offerer_id'] as String;

      final offered = <_RawItem>[];
      for (final oi in (row['offer_items'] as List<dynamic>? ?? const [])) {
        final itemId = (oi as Map<String, dynamic>)['item_id'] as String;
        final raw = items[itemId];
        if (raw != null) offered.add(raw);
      }
      offered.sort(
              (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      summaries.add(OfferSummary(
        id: row['id'] as String,
        postId: postId,
        status: OfferStatus.fromDb(row['status'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
        isSent: isSent,
        otherName: names[otherId] ?? 'Unknown user',
        offered: [for (final raw in offered) entry(raw)],
        postItems: [
          for (final raw in posts[postId] ?? const <_RawItem>[]) entry(raw),
        ],
      ));
    }
    return summaries;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, _RawItem>> _fetchItems(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client
        .from('items')
        .select('id, title, item_condition, item_images(position, storage_key)')
        .inFilter('id', ids.toList());

    return {
      for (final row in rows)
        row['id'] as String: _RawItem(
          row['title'] as String,
          _cover(row),
          _conditionLabel(row['item_condition']),
        ),
    };
  }

  /// The items of each target post. A post that was removed cannot be read,
  /// so it is missing from the result.
  Future<Map<String, List<_RawItem>>> _fetchPostItems(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client
        .from('posts')
        .select('id, items(id, title, item_condition, '
        'item_images(position, storage_key))')
        .inFilter('id', ids.toList());

    final result = <String, List<_RawItem>>{};
    for (final row in rows) {
      final items = [
        for (final raw in (row['items'] as List<dynamic>? ?? const []))
          _RawItem(
            (raw as Map<String, dynamic>)['title'] as String,
            _cover(raw),
            _conditionLabel(raw['item_condition']),
          ),
      ]..sort(
              (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      if (items.isNotEmpty) result[row['id'] as String] = items;
    }
    return result;
  }

  /// public_profiles hides phone numbers and emails.
  Future<Map<String, String>> _fetchNames(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _client
        .from('public_profiles')
        .select('id, display_name')
        .inFilter('id', ids.toList());

    return {
      for (final row in rows)
        row['id'] as String: row['display_name'] as String,
    };
  }

  Future<Map<String, String>> _signPaths(Set<String> paths) async {
    if (paths.isEmpty) return {};
    final storage = _client.storage.from(_imageBucket);
    final urls = <String, String>{};

    await Future.wait(paths.map((path) async {
      try {
        urls[path] = await storage.createSignedUrl(path, _signedUrlSeconds);
      } catch (_) {
        // Skip this photo. The tile shows a placeholder.
      }
    }));
    return urls;
  }

  static String? _cover(Map<String, dynamic> row) {
    final images = [
      for (final raw in (row['item_images'] as List<dynamic>? ?? const []))
        raw as Map<String, dynamic>,
    ]..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    return images.isEmpty ? null : images.first['storage_key'] as String;
  }

  static String? _conditionLabel(Object? value) =>
      value == null ? null : ItemCondition.fromDb(value as String).label;
}

class _RawItem {
  const _RawItem(this.title, this.coverPath, this.conditionLabel);

  final String title;
  final String? coverPath;
  final String? conditionLabel;
}