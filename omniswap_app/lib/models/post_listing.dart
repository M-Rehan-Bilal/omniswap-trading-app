/// One wanted entry: a single item, or a bundle of items wanted together.
/// Order does not matter, so the entry is compared by its sorted keys.
class WantBundle {
  const WantBundle({required this.names, required this.keys});

  /// Display names, sorted by name.
  final List<String> names;

  /// Normalised keys, in the same order as [names].
  final List<String> keys;

  bool get isBundle => names.length > 1;

  /// "PS5 + Controller" for a bundle, or "PS5" for a single item.
  String get label => names.join(' + ');

  /// True when the other side holds every item in this entry.
  bool isCoveredBy(Set<String> haveKeys) => keys.every(haveKeys.contains);

  /// Builds entries from rows of the `wants` table. Rows that share a
  /// group_id form one entry. Needs model_name, model_key and group_id.
  static List<WantBundle> fromRows(List<Map<String, dynamic>> rows) {
    final byGroup = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      byGroup.putIfAbsent(row['group_id'] as String, () => []).add(row);
    }

    final bundles = <WantBundle>[];
    for (final group in byGroup.values) {
      final sorted = [...group]
        ..sort((a, b) => (a['model_name'] as String)
            .toLowerCase()
            .compareTo((b['model_name'] as String).toLowerCase()));

      bundles.add(WantBundle(
        names: [for (final row in sorted) row['model_name'] as String],
        keys: [for (final row in sorted) row['model_key'] as String],
      ));
    }

    bundles.sort((a, b) =>
        a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return bundles;
  }
}

/// One item inside a post, with its photo storage paths in display order.
class PostedItem {
  const PostedItem({
    required this.id,
    required this.title,
    required this.modelName,
    required this.modelKey,
    required this.condition,
    required this.photos,
  });

  final String id;
  final String title;
  final String modelName;
  final String modelKey;
  final String condition; // new | like_new | good | fair | poor

  /// Storage paths of the item's photos. The first one is the cover.
  final List<String> photos;

  factory PostedItem.fromRow(Map<String, dynamic> row) {
    final images = [
      for (final raw
      in (row['item_images'] as List<dynamic>? ?? const <dynamic>[]))
        raw as Map<String, dynamic>,
    ]..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));

    return PostedItem(
      id: row['id'] as String,
      title: row['title'] as String,
      modelName: row['model_name'] as String,
      modelKey: row['model_key'] as String,
      condition: row['item_condition'] as String,
      photos: [for (final image in images) image['storage_key'] as String],
    );
  }
}

/// A post with its items and the entries it wants.
class PostListing {
  const PostListing({
    required this.postId,
    required this.ownerId,
    required this.acceptsOutsideWants,
    required this.items,
    required this.wants,
  });

  final String postId;
  final String ownerId;
  final bool acceptsOutsideWants;

  /// Items in this post, sorted by title.
  final List<PostedItem> items;

  /// What the poster wants in return: single items and bundles, sorted by label.
  final List<WantBundle> wants;

  Set<String> get itemKeys => {for (final item in items) item.modelKey};

  /// True when one wanted entry is fully covered by [haveKeys].
  /// A bundle needs every one of its items.
  bool wantsCoveredBy(Set<String> haveKeys) =>
      wants.any((want) => want.isCoveredBy(haveKeys));

  /// The first item. Used for the cover photo and the icon.
  PostedItem? get cover => items.isEmpty ? null : items.first;

  /// Storage path of the cover item's first photo, or null if it has none.
  String? get coverPath {
    final first = cover;
    if (first == null || first.photos.isEmpty) return null;
    return first.photos.first;
  }

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

    return PostListing(
      postId: row['id'] as String,
      ownerId: row['owner_id'] as String,
      acceptsOutsideWants: row['accepts_outside_wants'] as bool? ?? false,
      items: items,
      wants: WantBundle.fromRows([
        for (final raw in rawWants) raw as Map<String, dynamic>,
      ]),
    );
  }
}