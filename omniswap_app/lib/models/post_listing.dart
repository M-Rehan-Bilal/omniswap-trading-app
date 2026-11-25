/// One item inside a post.
class PostedItem {
  const PostedItem({
    required this.id,
    required this.title,
    required this.modelName,
    required this.modelKey,
    required this.condition,
  });

  final String id;
  final String title;
  final String modelName;
  final String modelKey;
  final String condition; // new | like_new | good | fair | poor

  factory PostedItem.fromRow(Map<String, dynamic> row) {
    return PostedItem(
      id: row['id'] as String,
      title: row['title'] as String,
      modelName: row['model_name'] as String,
      modelKey: row['model_key'] as String,
      condition: row['item_condition'] as String,
    );
  }
}

/// A post with its bundle of items and the items it wants.
class PostListing {
  const PostListing({
    required this.postId,
    required this.ownerId,
    required this.acceptsOutsideWants,
    required this.items,
    required this.wantNames,
    required this.wantKeys,
  });

  final String postId;
  final String ownerId;
  final bool acceptsOutsideWants;

  /// Items in this post, sorted by title.
  final List<PostedItem> items;

  /// What the poster wants in return, sorted by name.
  final List<String> wantNames;
  final List<String> wantKeys;

  Set<String> get itemKeys => {for (final item in items) item.modelKey};

  /// The first item, used for the icon and for single-item screens.
  PostedItem? get cover => items.isEmpty ? null : items.first;

  /// "PS5" for one item, "PS5 + 2 more" for a bundle.
  String get displayTitle {
    if (items.isEmpty) return 'Empty post';
    if (items.length == 1) return items.first.title;
    return '${items.first.title} + ${items.length - 1} more';
  }

  // Compatibility getters for screens that still expect a single item.
  // Prefer [items] in new code.
  String get itemId => cover?.id ?? '';
  String get title => displayTitle;
  String get modelName => cover?.modelName ?? '';
  String get modelKey => cover?.modelKey ?? '';
  String get condition => cover?.condition ?? '';

  /// Builds a post from a `posts` row that embeds `items` and `wants`.
  factory PostListing.fromRow(Map<String, dynamic> row) {
    final rawItems = (row['items'] as List<dynamic>?) ?? const <dynamic>[];
    final items = [
      for (final raw in rawItems)
        PostedItem.fromRow(raw as Map<String, dynamic>),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    final rawWants = (row['wants'] as List<dynamic>?) ?? const <dynamic>[];
    final wantRows = [
      for (final raw in rawWants) raw as Map<String, dynamic>,
    ]..sort((a, b) => (a['model_name'] as String)
        .toLowerCase()
        .compareTo((b['model_name'] as String).toLowerCase()));

    return PostListing(
      postId: row['id'] as String,
      ownerId: row['owner_id'] as String,
      acceptsOutsideWants: row['accepts_outside_wants'] as bool? ?? false,
      items: items,
      wantNames: [for (final w in wantRows) w['model_name'] as String],
      wantKeys: [for (final w in wantRows) w['model_key'] as String],
    );
  }
}