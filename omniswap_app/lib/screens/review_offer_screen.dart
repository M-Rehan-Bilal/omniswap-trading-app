import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../models/post_details.dart';
import '../services/offer_service.dart';
import '../theme/omni_colors.dart';
import '../widgets/item_photo.dart';

/// Step 2 of making an offer: shows what you give and what you get,
/// then sends the offer.
class ReviewOfferScreen extends StatefulWidget {
  const ReviewOfferScreen({
    super.key,
    required this.post,
    required this.offeredItems,
    this.service,
  });

  /// The post being offered for. Everything in it is what you get.
  final PostDetails post;

  /// The items from your inventory that you give.
  final List<InventoryItem> offeredItems;

  /// Optional, so tests can inject a fake service.
  final OfferService? service;

  @override
  State<ReviewOfferScreen> createState() => _ReviewOfferScreenState();
}

class _ReviewOfferScreenState extends State<ReviewOfferScreen> {
  late final OfferService _service;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? OfferService();
  }

  Future<void> _send() async {
    if (_sending) return;

    // Taken first, because this screen is gone after a successful send.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _sending = true);
    try {
      await _service.createOffer(
        postId: widget.post.postId,
        itemIds: [for (final item in widget.offeredItems) item.id],
      );
      messenger.showSnackBar(const SnackBar(content: Text('Offer sent')));

      // My Offers lives under the Trades tab. Go back to the root screen,
      // then open it.
      navigator.popUntil((route) => route.isFirst);
      navigator.pushNamed('/trades');
    } on OfferException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not send the offer. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final give = [
      for (final item in widget.offeredItems)
        _Entry(title: item.title, url: item.coverUrl),
    ];
    final get = [
      for (final item in widget.post.items)
        _Entry(title: item.title, url: item.coverUrl),
    ];

    return PopScope(
      // Don't let the user leave while the offer is being sent.
      canPop: !_sending,
      child: Scaffold(
        backgroundColor: kOmniBg,
        appBar: AppBar(
          backgroundColor: kOmniSurface,
          elevation: 0,
          iconTheme: const IconThemeData(color: kOmniInk),
          title: const Text(
            'Review Offer',
            style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _BundleCard(title: 'You give', entries: give),
            const SizedBox(height: 16),
            _BundleCard(
              title: 'You get',
              subtitle: 'from ${widget.post.owner.name}',
              entries: get,
            ),
          ],
        ),
        bottomNavigationBar: _SendBar(sending: _sending, onPressed: _send),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Widgets
// -----------------------------------------------------------------------------

class _Entry {
  const _Entry({required this.title, required this.url});

  final String title;
  final String? url;
}

/// A card with a heading, big photo tiles joined by "+", and one combined
/// title underneath, e.g. "PS5 + Android".
class _BundleCard extends StatelessWidget {
  const _BundleCard({
    required this.title,
    required this.entries,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<_Entry> entries;

  static const double _tile = 104;
  static const Color _tileBg = Color(0xFFDDEAF8);

  String get _combinedTitle => entries.map((e) => e.title).join(' + ');

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

          // Tiles in one row. Scrolls sideways if there are many items.
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
                  _PhotoTile(url: entries[i].url, size: _tile, bg: _tileBg),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),
          Text(
            _combinedTitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: kOmniInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.url, required this.size, required this.bg});

  final String? url;
  final double size;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: ItemPhoto(url: url, iconSize: 32),
      ),
    );
  }
}

/// The yellow Send Offer button pinned to the bottom.
class _SendBar extends StatelessWidget {
  const _SendBar({required this.sending, required this.onPressed});

  final bool sending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kOmniSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kOmniYellow,
                foregroundColor: kOmniInk,
                disabledBackgroundColor: kOmniYellow.withOpacity(0.45),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: sending ? null : onPressed,
              child: sending
                  ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: kOmniInk,
                ),
              )
                  : const Text(
                'Send Offer',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}