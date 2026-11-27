import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_listing.dart';

/// Mirrors the database's model_key expression:
/// regexp_replace(lower(model_name), '[^a-z0-9]', '', 'g')
String normalizeModelKey(String input) =>
    input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

class TradeService {
  TradeService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _imageBucket = 'item-images';
  static const int _signedUrlSeconds = 60 * 60;

  /// Embeds each item's photo paths so the cover photo can be signed.
  static const String _postSelect =
      'id, owner_id, accepts_outside_wants, '
      'items(id, title, model_name, model_key, item_condition, '
      'item_images(position, storage_key)), '
      'wants(model_name, model_key)';

  String get currentUserId {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in user.');
    }
    return user.id;
  }

  /// The current user's active posts, newest first.
  Future<List<PostListing>> fetchMyActivePosts() async {
    final rows = await _client
        .from('posts')
        .select(_postSelect)
        .eq('owner_id', currentUserId)
        .eq('status', 'active')
        .order('created_at', ascending: false);

    return [
      for (final row in rows) PostListing.fromRow(row as Map<String, dynamic>),
    ];
  }

  /// Direct trades: active posts from other users that hold an item matching
  /// [wantText] and either want one of [haveModelKeys] or accept outside wants.
  Future<List<PostListing>> findDirectTrades({
    required Set<String> haveModelKeys,
    required String wantText,
  }) async {
    final wantKey = normalizeModelKey(wantText);
    if (wantKey.isEmpty) return [];
    final me = currentUserId;

    // Step 1: find the posts that hold a matching item.
    // Filtering the embedded items here would also trim each post's bundle.
    final itemRows = await _client
        .from('items')
        .select('post_id')
        .not('post_id', 'is', null)
        .neq('owner_id', me)
        .ilike('model_key', '%$wantKey%')
        .limit(200);

    final postIds = {
      for (final row in itemRows) row['post_id'] as String,
    }.toList();
    if (postIds.isEmpty) return [];

    // Step 2: load those posts in full, keeping only active ones.
    final postRows = await _client
        .from('posts')
        .select(_postSelect)
        .inFilter('id', postIds)
        .eq('status', 'active')
        .neq('owner_id', me)
        .limit(50);

    final posts = [
      for (final row in postRows)
        PostListing.fromRow(row as Map<String, dynamic>),
    ];

    // Keep a post if it accepts any outside item, or if it wants one of
    // the items in the user's post.
    return posts
        .where((p) =>
    p.acceptsOutsideWants ||
        p.wantKeys.any((key) => haveModelKeys.contains(key)))
        .toList();
  }

  /// Active posts from other users that want any of [modelKeys].
  /// Returned as a map: wanted model_key -> posts that want it.
  Future<Map<String, List<PostListing>>> fetchPostsWantingModels(
      Set<String> modelKeys,
      ) async {
    if (modelKeys.isEmpty) return {};

    final rows = await _client
        .from('wants')
        .select('model_key, posts!inner($_postSelect)')
        .inFilter('model_key', modelKeys.toList())
        .eq('posts.status', 'active')
        .neq('posts.owner_id', currentUserId);

    final result = <String, List<PostListing>>{};
    for (final row in rows) {
      final wantKey = row['model_key'] as String;
      final post = PostListing.fromRow(row['posts'] as Map<String, dynamic>);
      result.putIfAbsent(wantKey, () => []).add(post);
    }
    return result;
  }

  /// "Offers for you": active posts from other users that accept outside
  /// wants, so they will take items that are not on their wanted list.
  Future<List<PostListing>> fetchOffersForYou({int limit = 20}) async {
    final rows = await _client
        .from('posts')
        .select(_postSelect)
        .eq('status', 'active')
        .eq('accepts_outside_wants', true)
        .neq('owner_id', currentUserId)
        .order('created_at', ascending: false)
        .limit(limit);

    return [
      for (final row in rows) PostListing.fromRow(row as Map<String, dynamic>),
    ];
  }

  /// Creates a signed URL for each private photo path.
  /// Paths that fail are left out, and the card shows a placeholder.
  Future<Map<String, String>> signPaths(Iterable<String> paths) async {
    final storage = _client.storage.from(_imageBucket);
    final urls = <String, String>{};

    await Future.wait(paths.toSet().map((path) async {
      try {
        urls[path] = await storage.createSignedUrl(path, _signedUrlSeconds);
      } catch (_) {
        // Skip this photo.
      }
    }));

    return urls;
  }
}