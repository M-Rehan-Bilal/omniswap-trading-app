import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_listing.dart';

class BrowseService {
  BrowseService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _imageBucket = 'item-images';
  static const int _signedUrlSeconds = 60 * 60;

  /// Same fields as the home screen's post select, so PostListing.fromRow
  /// can read every row. Keep this in step with TradeService.
  static const String _select =
      'id, owner_id, accepts_outside_wants, '
      'items(id, title, model_name, model_key, item_condition, '
      'item_images(position, storage_key)), '
      'wants(model_name, model_key)';

  /// Active posts from other users. Items are sorted by PostListing.fromRow.
  Future<List<PostListing>> fetchPosts({
    String search = '',
    bool newestFirst = true,
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return [];

    final rows = await _client
        .from('posts')
        .select(_select)
        .eq('status', 'active')
        .neq('owner_id', me)
        .order('created_at', ascending: !newestFirst);

    final query = search.trim().toLowerCase();
    final posts = <PostListing>[];

    for (final row in rows as List) {
      final post = PostListing.fromRow(row as Map<String, dynamic>);
      if (post.items.isEmpty) continue;

      // Search every item in the bundle and every wanted model.
      if (query.isNotEmpty) {
        final haystack = [
          for (final item in post.items) ...[
            item.title.toLowerCase(),
            item.modelName.toLowerCase(),
          ],
          for (final name in post.wantNames) name.toLowerCase(),
        ];
        if (!haystack.any((text) => text.contains(query))) continue;
      }

      posts.add(post);
    }

    return posts;
  }

  /// Creates a signed URL for each cover photo, keyed by storage path.
  /// Paths that fail are left out, and the card shows a placeholder.
  Future<Map<String, String>> signCovers(Iterable<PostListing> posts) async {
    final paths = {
      for (final post in posts)
        if (post.coverPath != null) post.coverPath!,
    };
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