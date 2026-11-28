import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_listing.dart';

/// The posts for one browse page, plus the signed URL of each cover photo.
class BrowsePage {
  const BrowsePage({required this.posts, required this.urlByPath});

  final List<PostListing> posts;

  /// Signed URL for each cover photo path. Missing paths show a placeholder.
  final Map<String, String> urlByPath;
}

class BrowseService {
  BrowseService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _imageBucket = 'item-images';
  static const int _signedUrlSeconds = 60 * 60;

  static const String _select = 'id, owner_id, accepts_outside_wants, '
      'items(id, title, model_name, model_key, item_condition, '
      'item_images(position, storage_key)), '
      'wants(group_id, model_name, model_key)';

  /// Active posts from other users, optionally filtered by [search].
  Future<BrowsePage> fetchPage({
    String search = '',
    bool newestFirst = true,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return const BrowsePage(posts: [], urlByPath: {});

    final rows = await _client
        .from('posts')
        .select(_select)
        .eq('status', 'active')
        .neq('owner_id', me)
        .order('created_at', ascending: !newestFirst);

    var posts = [
      for (final row in rows as List)
        PostListing.fromRow(row as Map<String, dynamic>),
    ].where((post) => post.items.isNotEmpty).toList();

    final query = search.trim().toLowerCase();
    if (query.isNotEmpty) {
      posts = posts.where((post) => _matches(post, query)).toList();
    }

    final paths = {
      for (final post in posts)
        if (post.coverPath != null) post.coverPath!,
    };
    final urls = await _signPaths(paths);

    return BrowsePage(posts: posts, urlByPath: urls);
  }

  /// Searches every item's title and model, and every name in every
  /// wanted entry, so a bundle can be found by any of its items.
  static bool _matches(PostListing post, String query) {
    for (final item in post.items) {
      if (item.title.toLowerCase().contains(query)) return true;
      if (item.modelName.toLowerCase().contains(query)) return true;
    }
    for (final want in post.wants) {
      for (final name in want.names) {
        if (name.toLowerCase().contains(query)) return true;
      }
    }
    return false;
  }

  /// Creates a signed URL for each private photo path. Paths that fail are
  /// left out, and the card shows a placeholder.
  Future<Map<String, String>> _signPaths(Set<String> paths) async {
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