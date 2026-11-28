import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../models/post_listing.dart';
import '../services/trade_service.dart' show normalizeModelKey;
import '../theme/omni_colors.dart';

/// A fallback icon for an item with no photo, chosen from its model name.
IconData iconForModel(String modelName) {
  final key = normalizeModelKey(modelName);
  if (RegExp(r'^ps\d|playstation|xbox|nintendo|^switch$').hasMatch(key)) {
    return Icons.sports_esports_outlined;
  }
  if (key.contains('watch')) return Icons.watch_outlined;
  if (key.contains('iphone') ||
      key.contains('phone') ||
      key.contains('galaxy')) {
    return Icons.phone_iphone;
  }
  if (key.contains('ipad') || key.contains('tablet')) return Icons.tablet_mac;
  if (key.contains('laptop') || key.contains('macbook')) {
    return Icons.laptop_mac;
  }
  return Icons.inventory_2_outlined;
}

/// The one card frame used across the app. Every listing card (posts on
/// Home and Browse, and items in My Inventory) is built on this, so the
/// look stays consistent and can be changed in one place.
class ListingFrame extends StatelessWidget {
  const ListingFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.icon,
    required this.onTap,
    this.width,
    this.topLeft,
    this.topRight,
    this.footer,
  });

  final String title;
  final String subtitle;

  /// Signed URL of the photo, or null while loading or if none exists.
  final String? imageUrl;

  /// Shown on the placeholder when there is no photo.
  final IconData icon;
  final VoidCallback onTap;

  /// Fixed width for horizontal rows. Null lets a grid size the card.
  final double? width;

  /// Optional badge in the top-left corner of the photo.
  final Widget? topLeft;

  /// Optional badge in the top-right corner of the photo.
  final Widget? topRight;

  /// Optional widget under the subtitle, such as a button.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kOmniBlue, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: kOmniBlue.withOpacity(0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _PhotoArea(url: imageUrl, icon: icon),
                    ),
                    if (topLeft != null)
                      Positioned(top: 6, left: 6, child: topLeft!),
                    if (topRight != null)
                      Positioned(top: 6, right: 6, child: topRight!),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kOmniInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: kOmniMuted,
                      ),
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: 8),
                      footer!,
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );

    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// A listing card for a post, used on Home and Browse.
/// Shows the post's cover photo, title, and what the poster wants.
class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.post,
    required this.imageUrl,
    required this.onTap,
    this.width,
  });

  final PostListing post;

  /// Signed URL of the cover photo, or null while loading or if none exists.
  final String? imageUrl;
  final VoidCallback onTap;

  /// Fixed width for horizontal rows. Null lets a grid size the card.
  final double? width;

  /// "wants PS5 + Controller", or "wants iPhone 15 +2".
  String get _wantsLine {
    if (post.wants.isEmpty) {
      return post.acceptsOutsideWants ? 'Open to any item' : 'No wants listed';
    }
    final first = post.wants.first.label;
    final extra = post.wants.length - 1;
    return extra > 0 ? 'wants $first +$extra' : 'wants $first';
  }

  @override
  Widget build(BuildContext context) {
    return ListingFrame(
      title: post.title,
      subtitle: _wantsLine,
      imageUrl: imageUrl,
      icon: iconForModel(post.modelName),
      onTap: onTap,
      width: width,
    );
  }
}

/// A listing card for one inventory item, used on My Inventory.
/// The condition shows as a badge. A "Post item" button appears under
/// unposted items, and a "Posted" badge marks items already in a post.
class ItemListingCard extends StatelessWidget {
  const ItemListingCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onPost,
  });

  final InventoryItem item;
  final VoidCallback onTap;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    final posted = item.isPosted;

    return ListingFrame(
      title: item.title,
      subtitle: posted ? 'In a post' : 'Not posted yet',
      imageUrl: item.coverUrl,
      icon: iconForModel(item.title),
      onTap: onTap,
      topLeft: ListingBadge(label: item.condition.label),
      topRight: posted
          ? const ListingBadge(label: 'Posted', background: kOmniYellow)
          : null,
      footer: posted
          ? null
          : SizedBox(
        width: double.infinity,
        height: 34,
        child: FilledButton.icon(
          onPressed: onPost,
          icon: const Icon(Icons.storefront_outlined, size: 16),
          label: const Text('Post item'),
          style: FilledButton.styleFrom(
            backgroundColor: kOmniYellow,
            foregroundColor: kOmniInk,
            padding: EdgeInsets.zero,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small pill used on card photos.
class ListingBadge extends StatelessWidget {
  const ListingBadge({
    super.key,
    required this.label,
    this.background = Colors.white,
  });

  final String label;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: kOmniInk,
        ),
      ),
    );
  }
}

/// The photo area. Shows the cover photo, or a blue-to-gold placeholder with
/// an icon while the photo loads or when there is none.
class _PhotoArea extends StatelessWidget {
  const _PhotoArea({required this.url, required this.icon});

  final String? url;
  final IconData icon;

  Widget _placeholder() => Center(
    child: Icon(icon, size: 44, color: Colors.white.withOpacity(0.95)),
  );

  @override
  Widget build(BuildContext context) {
    final photo = url;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              kOmniBlue.withOpacity(0.55),
              kOmniGold.withOpacity(0.85),
            ],
          ),
        ),
        child: photo == null
            ? _placeholder()
            : Image.network(
          photo,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, progress) =>
          progress == null ? child : _placeholder(),
          errorBuilder: (context, error, stackTrace) => _placeholder(),
        ),
      ),
    );
  }
}