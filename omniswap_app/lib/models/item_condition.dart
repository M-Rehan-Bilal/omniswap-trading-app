/// Matches the item_condition enum in the database.
enum ItemCondition {
  newItem('new', 'New'),
  likeNew('like_new', 'Like New'),
  good('good', 'Good'),
  fair('fair', 'Fair'),
  poor('poor', 'Poor');

  const ItemCondition(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static ItemCondition fromDb(String value) {
    return ItemCondition.values.firstWhere(
          (condition) => condition.dbValue == value,
      orElse: () => throw ArgumentError('Unknown item condition: $value'),
    );
  }
}