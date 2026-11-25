import 'package:supabase_flutter/supabase_flutter.dart';

class BrowsePost {
  const BrowsePost({
    required this.postId,
    required this.itemTitle,
    required this.modelName,
    required this.imageUrl,
    required this.wants,
    required this.createdAt,
  });

  final String postId;

  /// "PS5" for one item, "PS5 + 2 more" for a bundle.
  final String itemTitle;

  /// Model of the cover item.
  final String modelName;

  final String? imageUrl;
  final List<String> wants;
  final DateTime createdAt;
}

class BrowseService {
  BrowseService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String _imageBucket = 'item-images';
  static const int _signedUrlSeconds = 60 * 60;

  // `items` is a list, because one post holds up to 5 items.
  // Each item embeds its photos, so the cover photo can be found.
  static const String _select =
      'id, owner_id, created_at, '
      'items(id, title, model_name, item_images(position, storage_key)), '
      'wants(model_name)';

  Future<List<BrowsePost>> fetchPosts({
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
    final candidates = <_Candidate>[];

    for (final row in rows as List) {
      final post = row as Map<String, dynamic>;

      final items = _asMaps(post['items'])..sort(_byTitle);
      if (items.isEmpty) continue;

      final wants = _asMaps(post['wants'])
        ..sort((a, b) => _lower(a['model_name']).compareTo(
          _lower(b['model_name']),
        ));
      final wantNames = [for (final w in wants) w['model_name'] as String];

      // Search every item in the bundle and every wanted model.
      if (query.isNotEmpty) {
        final haystack = [
          for (final item in items) ...[
            _lower(item['title']),
            _lower(item['model_name']),
          ],
          for (final name in wantNames) name.toLowerCase(),
        ];
        if (!haystack.any((text) => text.contains(query))) continue;
      }

      candidates.add(_Candidate(
        postId: post['id'] as String,
        items: items,
        wants: wantNames,
        createdAt: DateTime.parse(post['created_at'] as String),
      ));
    }

    // Sign only the cover photos that are shown.
    final coverPaths = [
      for (final c in candidates)
        if (c.coverPath != null) c.coverPath!,
    ];
    final urlByPath = await _signPaths(coverPaths);

    return [
      for (final c in candidates)
        BrowsePost(
          postId: c.postId,
          itemTitle: c.title,
          modelName: c.cover['model_name'] as String,
          imageUrl: urlByPath[c.coverPath ?? ''],
          wants: c.wants,
          createdAt: c.createdAt,
        ),
    ];
  }

  /// Creates a signed URL for each private photo path.
  /// Paths that fail are left out, and the card shows a placeholder.
  Future<Map<String, String>> _signPaths(List<String> paths) async {
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

/// A post that passed the search filter, with its items sorted by title.
class _Candidate {
  _Candidate({
    required this.postId,
    required this.items,
    required this.wants,
    required this.createdAt,
  });

  final String postId;
  final List<Map<String, dynamic>> items;
  final List<String> wants;
  final DateTime createdAt;

  Map<String, dynamic> get cover => items.first;

  String get title => items.length == 1
      ? cover['title'] as String
      : '${cover['title']} + ${items.length - 1} more';

  String? get coverPath {
    final images = _asMaps(cover['item_images'])
      ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    return images.isEmpty ? null : images.first['storage_key'] as String;
  }
}

List<Map<String, dynamic>> _asMaps(Object? value) => [
  for (final e in (value as List<dynamic>? ?? const <dynamic>[]))
    e as Map<String, dynamic>,
];

int _byTitle(Map<String, dynamic> a, Map<String, dynamic> b) =>
    _lower(a['title']).compareTo(_lower(b['title']));

String _lower(Object? value) => (value as String).toLowerCase();