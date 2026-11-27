import 'package:flutter/material.dart';

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
  if (key.contains('iphone') || key.contains('phone') || key.contains('galaxy')) {
    return Icons.phone_iphone;
  }
  if (key.contains('ipad') || key.contains('tablet')) return Icons.tablet_mac;
  if (key.contains('laptop') || key.contains('macbook')) {
    return Icons.laptop_mac;
  }
  return Icons.inventory_2_outlined;
}

/// One listing: cover photo, title, and what the poster wants.
/// Used by the home rows and by the See all page.
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

  String get _wantsLine {
    if (post.wantNames.isEmpty) {
      return post.acceptsOutsideWants ? 'Open to any item' : 'No wants listed';
    }
    final extra = post.wantNames.length - 1;
    return extra > 0
        ? 'wants ${post.wantNames.first} +$extra'
        : 'wants ${post.wantNames.first}';
  }

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
                child: _PhotoArea(
                  url: imageUrl,
                  icon: iconForModel(post.modelName),
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
                      post.title,
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
                      _wantsLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: kOmniMuted,
                      ),
                    ),
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