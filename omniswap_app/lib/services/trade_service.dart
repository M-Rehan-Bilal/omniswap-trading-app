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
      'items!inner(id, title, model_name, model_key, item_condition), '
      'wants(model_name, model_key)';

  String get currentUserId {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in user.');
    }
    return user.id;
  }

  /// The current user's active posts. Used for the "I HAVE" dropdown
  /// and for "Matches for my listings".
  Future<List<PostListing>> fetchMyActivePosts() async {
    final rows = await _client
        .from('posts')
        .select(_postSelect)
        .eq('owner_id', currentUserId)
        .eq('status', 'active')
        .order('created_at', ascending: false);

    return rows.map(PostListing.fromRow).toList();
  }

  /// Direct trades: other users' active posts whose item matches [wantText]
  /// AND who either want [haveModelKey] or accept any item.
  Future<List<PostListing>> findDirectTrades({
    required String haveModelKey,
    required String wantText,
  }) async {
    final wantKey = normalizeModelKey(wantText);
    if (wantKey.isEmpty) return [];

    final rows = await _client
        .from('posts')
        .select(_postSelect)
        .eq('status', 'active')
        .neq('owner_id', currentUserId)
        .ilike('items.model_key', '%$wantKey%')
        .limit(50);

    final posts = rows.map(PostListing.fromRow);
    return posts
        .where((p) =>
    p.acceptsOutsideWants || p.wantKeys.contains(haveModelKey))
        .toList();
  }

  /// Active posts from other users that want any of the given model keys.
  /// Returned as a map: wanted model_key -> posts that want it.
  Future<Map<String, List<PostListing>>> fetchPostsWantingModels(
      Set<String> modelKeys,
      ) async {
    if (modelKeys.isEmpty) return {};

    final rows = await _client
        .from('wants')
        .select('model_key, posts!inner(id, owner_id, accepts_outside_wants, '
        'items!inner(id, title, model_name, model_key, item_condition), '
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