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

  // item_images is embedded so each post can report its cover photo path.
  static const String _postSelect = 'id, owner_id, accepts_outside_wants, '
      'items(id, title, model_name, model_key, item_condition, '
      'item_images(position, storage_key)), '
      'wants(group_id, model_name, model_key)';

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

  /// Direct trades for the selected item: active posts from other users that
  /// hold an item matching [wantText] and either accept outside wants or
  /// have a wanted entry fully covered by [haveModelKeys].
  Future<List<PostListing>> findDirectTrades({
    required Set<String> haveModelKeys,
    required String wantText,
  }) async {
    final wantKey = normalizeModelKey(wantText);
    if (wantKey.isEmpty) return [];
    final me = currentUserId;

    // Step 1: find the posts that hold a matching item.
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

    return posts
        .where((p) => p.acceptsOutsideWants || p.wantsCoveredBy(haveModelKeys))
        .toList();
  }

  /// Active posts from other users that want at least one of [modelKeys].
  /// A post that wants a bundle appears when any one of its items matches.
  /// Callers must still check that the whole entry is covered, using
  /// [PostListing.wantsCoveredBy].
  Future<List<PostListing>> fetchCandidatePosts(Set<String> modelKeys) async {
    if (modelKeys.isEmpty) return [];

    final rows = await _client
        .from('wants')
        .select('posts!inner($_postSelect)')
        .inFilter('model_key', modelKeys.toList())
        .eq('posts.status', 'active')
        .neq('posts.owner_id', currentUserId);

    // One wanted row per matching item, so the same post can come back twice.
    final byPostId = <String, PostListing>{};
    for (final row in rows) {
      final post =
      PostListing.fromRow(row['posts'] as Map<String, dynamic>);
      byPostId.putIfAbsent(post.postId, () => post);
    }
    return byPostId.values.toList();
  }

  /// Signs each private photo path. Paths that fail are left out, and the
  /// card keeps its placeholder.
  Future<Map<String, String>> signPaths(Set<String> paths) async {
    if (paths.isEmpty) return {};

    final storage = _client.storage.from(_imageBucket);
    final urls = <String, String>{};

    await Future.wait(paths.map((path) async {
      try {
        urls[path] = await storage.createSignedUrl(path, _signedUrlSeconds);
      } catch (_) {
        // Skip this photo.
      }
    }));

    return urls;
  }
}