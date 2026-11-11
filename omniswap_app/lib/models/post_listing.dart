class PostListing {
  const PostListing({
    required this.postId,
    required this.ownerId,
    required this.acceptsOutsideWants,
    required this.itemId,
    required this.title,
    required this.modelName,
    required this.modelKey,
    required this.condition,
    required this.wantNames,
    required this.wantKeys,
  });

  final String postId;
  final String ownerId;
  final bool acceptsOutsideWants;

  // The inventory item being posted
  final String itemId;
  final String title;
  final String modelName;
  final String modelKey;
  final String condition; // new | like_new | good | fair | poor

  // What the poster is looking for in return
  final List<String> wantNames;
  final List<String> wantKeys;

  /// Builds a listing from a `posts` row that embeds `items` and `wants`.
  factory PostListing.fromRow(Map<String, dynamic> row) {
    final item = row['items'] as Map<String, dynamic>;
    final wants = (row['wants'] as List<dynamic>?) ?? const <dynamic>[];
    final wantMaps = wants.cast<Map<String, dynamic>>();

    return PostListing(
      postId: row['id'] as String,
      ownerId: row['owner_id'] as String,
      acceptsOutsideWants: row['accepts_outside_wants'] as bool? ?? false,
      itemId: item['id'] as String,
      title: item['title'] as String,
      modelName: item['model_name'] as String,
      modelKey: item['model_key'] as String,
      condition: item['item_condition'] as String,
      wantNames: wantMaps.map((w) => w['model_name'] as String).toList(),
      wantKeys: wantMaps.map((w) => w['model_key'] as String).toList(),
    );
  }
}