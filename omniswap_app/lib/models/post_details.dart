import 'item_condition.dart';

/// One item inside a post.
class PostDetailItem {
  const PostDetailItem({
    required this.id,
    required this.title,
    required this.description,
    required this.condition,
    required this.manufactureYear,
    required this.photoUrls,
  });

  final String id;
  final String title;
  final String description;
  final ItemCondition condition;
  final int? manufactureYear;

  /// Signed URLs of all photos, in display order. Empty if none could be loaded.
  final List<String> photoUrls;

  /// The first photo. Used as the cover on the bundle page.
  String? get coverUrl => photoUrls.isEmpty ? null : photoUrls.first;

  int get photoCount => photoUrls.length;
}

/// The public details of the post owner. No WhatsApp number or email.
class PostOwner {
  const PostOwner({
    required this.name,
    required this.avatarUrl,
    required this.rating,
    required this.area,
    required this.city,
  });

  final String name;
  final String? avatarUrl;
  final double rating;
  final String area;
  final String city;

  String get location => '$area, $city';
}

/// A post with everything the detail screens need.
class PostDetails {
  const PostDetails({
    required this.postId,
    required this.ownerId,
    required this.owner,
    required this.acceptsOutsideWants,
    required this.items,
    required this.wants,
  });

  final String postId;
  final String ownerId;
  final PostOwner owner;
  final bool acceptsOutsideWants;

  /// Sorted by title. The first item is the cover of the whole post.
  final List<PostDetailItem> items;

  /// Wanted model names, sorted by name.
  final List<String> wants;

  bool get isBundle => items.length > 1;

  /// The heading for the cover at [coverIndex]. For example, "Halwa + 2 more"
  /// when the second item is showing, or just the name for a single item.
  String titleFor(int coverIndex) {
    final cover = items[coverIndex];
    return isBundle ? '${cover.title} + ${items.length - 1} more' : cover.title;
  }

  /// "Good to Like New" when the items differ, or "Good" when they match.
  String get conditionSummary {
    final conditions = [for (final item in items) item.condition];
    // The enum is ordered best to worst: new, like_new, good, fair, poor.
    final best = conditions.reduce((a, b) => a.index <= b.index ? a : b);
    final worst = conditions.reduce((a, b) => a.index >= b.index ? a : b);
    return best == worst ? best.label : '${worst.label} to ${best.label}';
  }
}