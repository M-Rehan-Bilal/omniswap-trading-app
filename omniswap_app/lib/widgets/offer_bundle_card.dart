import 'package:flutter/material.dart';

import '../models/offer_summary.dart';
import '../theme/omni_colors.dart';
import 'item_photo.dart';

/// Small pill showing Pending / Accepted / Declined / Cancelled.
class OfferStatusBadge extends StatelessWidget {
  const OfferStatusBadge(this.status, {super.key});

  final OfferStatus status;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final IconData icon;

    switch (status) {
      case OfferStatus.pending:
        bg = kOmniYellow;
        fg = kOmniInk;
        icon = Icons.schedule;
        break;
      case OfferStatus.accepted:
        bg = const Color(0xFFD9F2E3);
        fg = const Color(0xFF1E7A46);
        icon = Icons.check_circle_outline;
        break;
      case OfferStatus.declined:
        bg = kOmniErrorBg;
        fg = kOmniError;
        icon = Icons.cancel_outlined;
        break;
      case OfferStatus.cancelled:
        bg = kOmniChipBg;
        fg = kOmniMuted;
        icon = Icons.remove_circle_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// A card with a heading, big photo tiles joined by "+", and one combined
/// title underneath, e.g. "PS5 + Android".
class OfferBundleCard extends StatelessWidget {
  const OfferBundleCard({
    super.key,
    required this.title,
    required this.entries,
    this.subtitle,
    this.emptyText = 'Nothing to show.',
  });

  final String title;
  final String? subtitle;
  final List<OfferEntry> entries;

  /// Shown instead of tiles when [entries] is empty.
  final String emptyText;

  static const double _tile = 104;
  static const Color _tileBg = Color(0xFFDDEAF8);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kOmniSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kOmniBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: kOmniInk,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kOmniMuted, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            Text(
              emptyText,
              style: const TextStyle(color: kOmniMuted, fontSize: 13),
            )
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '+',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: kOmniMuted,
                          ),
                        ),
                      ),
                    Container(
                      width: _tile,
                      height: _tile,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _tileBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: ItemPhoto(url: entries[i].url, iconSize: 32),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              entries.map((e) => e.title).join(' + '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: kOmniInk,
              ),
            ),
          ],
        ],
      ),
    );
  }
}