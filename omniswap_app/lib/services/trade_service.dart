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

  static const String _postSelect =
      'id, owner_id, accepts_outside_wants, '
      'items(id, title, model_name, model_key, item_condition), '
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
  /// [wantText] and either want [haveModelKey] or accept outside wants.
  Future<List<PostListing>> findDirectTrades({
    required String haveModelKey,
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
      for (final row in postRows) PostListing.fromRow(row as Map<String, dynamic>),
    ];

    return posts
        .where((p) =>
    p.acceptsOutsideWants || p.wantKeys.contains(haveModelKey))
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
        .select('model_key, posts!inner(id, owner_id, accepts_outside_wants, '
        'items(id, title, model_name, model_key, item_condition), '
        'wants(model_name, model_key))')
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
}