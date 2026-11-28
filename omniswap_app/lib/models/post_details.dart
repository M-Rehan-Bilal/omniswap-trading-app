import '../models/item_condition.dart';

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

/// The public details of the post owner, plus the phone number used to
/// contact them. The phone is null if it could not be loaded.
class PostOwner {
  const PostOwner({
    required this.name,
    required this.avatarUrl,
    required this.rating,
    required this.area,
    required this.city,
    required this.country,
    required this.phone,
  });

  final String name;
  final String? avatarUrl;
  final double rating;
  final String area;
  final String city;
  final String country;

  /// WhatsApp number in international format, e.g. +923001234567.
  final String? phone;

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
    required this.wantGroups,
  });

  final String postId;
  final String ownerId;
  final PostOwner owner;
  final bool acceptsOutsideWants;

  /// Sorted by title. The first item is the cover of the whole post.
  final List<PostDetailItem> items;

  /// Labels for display, one per wanted entry, e.g. "PS5" or "PS5 + Controller".
  final List<String> wants;

  /// Each wanted entry as its item names, in the same order as [wants].
  /// A bundle has two or more names and counts only when every name is offered.
  final List<List<String>> wantGroups;

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