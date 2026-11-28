/// Matches the offer_status enum in the database.
enum OfferStatus {
  pending('Pending'),
  accepted('Accepted'),
  declined('Declined'),
  cancelled('Cancelled');

  const OfferStatus(this.label);

  final String label;

  static OfferStatus fromDb(String value) => OfferStatus.values.firstWhere(
        (s) => s.name == value,
    orElse: () => OfferStatus.pending,
  );
}

/// One item shown in an offer: its title, a signed cover-photo URL and
/// its condition, e.g. "Like New".
class OfferEntry {
  const OfferEntry({
    required this.title,
    required this.url,
    this.conditionLabel,
  });

  final String title;
  final String? url;
  final String? conditionLabel;
}

/// One offer, ready to show in the My Offers list.
///
/// Left side of an offer = what the offerer gives ([offered]).
/// Right side = the items in the post they want ([postItems]).
class OfferSummary {
  const OfferSummary({
    required this.id,
    required this.postId,
    required this.status,
    required this.createdAt,
    required this.isSent,
    required this.otherUserId,
    required this.otherName,
    required this.offered,
    required this.postItems,
  });

  final String id;
  final String postId;
  final OfferStatus status;
  final DateTime createdAt;

  /// True if I made this offer. False if it was made to me.
  final bool isSent;

  /// The other person's user id (used to load their profile).
  final String otherUserId;

  /// The other person: the post owner (sent) or the offerer (received).
  final String otherName;

  final List<OfferEntry> offered;

  /// Empty if the post was removed and can no longer be read.
  final List<OfferEntry> postItems;

  bool get isPending => status == OfferStatus.pending;
  bool get postAvailable => postItems.isNotEmpty;

  String get offeredTitle => offered.map((e) => e.title).join(' + ');

  String get postTitle => postAvailable
      ? postItems.map((e) => e.title).join(' + ')
      : 'Post no longer available';

  /// e.g. "PS5 + Android → Laptop"
  String get summaryLine => '$offeredTitle → $postTitle';

  String get createdLabel {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = createdAt.toLocal();
    return '${d.day} ${months[d.month - 1]}';
  }
}