import 'item_condition.dart';

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.title,
    required this.description,
    required this.condition,
    required this.manufactureYear,
    required this.photoPaths,
    required this.urlByPath,
  });

  final String id;
  final String title;
  final String description;
  final ItemCondition condition;
  final int? manufactureYear;

  /// Storage paths in display order. The first one is the cover.
  final List<String> photoPaths;

  /// Signed URL for each path that could be signed. Paths that failed are missing.
  final Map<String, String> urlByPath;

  String? get coverUrl =>
      photoPaths.isEmpty ? null : urlByPath[photoPaths.first];

  /// Storage paths for one item row from Supabase, sorted by position.
  static List<String> photoPathsFrom(Map<String, dynamic> row) {
    final images = [
      for (final image in (row['item_images'] as List<dynamic>? ?? const []))
        image as Map<String, dynamic>,
    ]..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));

    return [for (final image in images) image['storage_key'] as String];
  }

  factory InventoryItem.fromRow(
      Map<String, dynamic> row,
      Map<String, String> urlByPath,
      ) {
    return InventoryItem(
      id: row['id'] as String,
      title: row['title'] as String,
      description: row['description'] as String,
      condition: ItemCondition.fromDb(row['item_condition'] as String),
      manufactureYear: row['manufacture_year'] as int?,
      photoPaths: photoPathsFrom(row),
      urlByPath: urlByPath,
    );
  }
}