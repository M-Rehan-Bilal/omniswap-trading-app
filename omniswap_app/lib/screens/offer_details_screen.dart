import 'package:flutter/material.dart';

import '../models/offer_summary.dart';
import '../services/offer_service.dart' show OfferException;
import '../services/offers_service.dart';
import '../theme/omni_colors.dart';
import '../widgets/offer_bundle_card.dart';

/// Asks for confirmation, then cancels (my own offer) or declines (an offer
/// made to me). Returns true if the offer was changed.
/// Used by both the My Offers list and the details screen.
Future<bool> closeOfferWithConfirm(
    BuildContext context,
    OfferSummary offer,
    OffersService service,
    ) async {
  final cancelling = offer.isSent;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(cancelling ? 'Cancel this offer?' : 'Decline this offer?'),
      content: Text(
        cancelling
            ? 'Your offer to ${offer.otherName} will be withdrawn.'
            : '${offer.otherName} will see that you declined.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelling ? 'Keep offer' : 'Back'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            cancelling ? 'Cancel offer' : 'Decline',
            style: TextStyle(color: Colors.red.shade700),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  try {
    if (cancelling) {
      await service.cancelOffer(offer.id);
    } else {
      await service.declineOffer(offer.id);
    }
    messenger.showSnackBar(
      SnackBar(content: Text(cancelling ? 'Offer cancelled' : 'Offer declined')),
    );
    return true;
  } on OfferException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Something went wrong. Please try again.')),
    );
    return false;
  }
}

/// One offer in full. Pops with true if the offer was changed here.
class OfferDetailsScreen extends StatefulWidget {
  const OfferDetailsScreen({super.key, required this.offer, this.service});

  final OfferSummary offer;

  /// Optional, so tests can inject a fake service.
  final OffersService? service;

  @override
  State<OfferDetailsScreen> createState() => _OfferDetailsScreenState();
}

class _OfferDetailsScreenState extends State<OfferDetailsScreen> {
  late final OffersService _service;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? OffersService();
  }

  Future<void> _closeOffer() async {
    if (_busy) return;
    setState(() => _busy = true);
    final done = await closeOfferWithConfirm(context, widget.offer, _service);
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) Navigator.pop(context, true);
  }

  void _accept() {
    // Accepting needs the accept_offer() database function, built next.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Accepting offers is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;

    return Scaffold(
      backgroundColor: kOmniBg,
      appBar: AppBar(
        backgroundColor: kOmniSurface,
        elevation: 0,
        iconTheme: const IconThemeData(color: kOmniInk),
        title: const Text(
          'Offer',
          style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.isSent
                      ? 'To: ${offer.otherName}'
                      : 'From: ${offer.otherName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kOmniInk,
                  ),
                ),
              ),
              OfferStatusBadge(offer.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sent ${offer.createdLabel}',
            style: const TextStyle(color: kOmniMuted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          OfferBundleCard(
            title: offer.isSent ? 'You give' : '${offer.otherName} gives',
            entries: offer.offered,
            emptyText: 'These items are no longer available.',
          ),
          const SizedBox(height: 16),
          OfferBundleCard(
            title: offer.isSent ? 'You get' : 'You give',
            subtitle: offer.isSent ? 'from ${offer.otherName}' : null,
            entries: offer.postItems,
            emptyText: 'This post is no longer available.',
          ),
        ],
      ),
      bottomNavigationBar: offer.isPending ? _buildActions() : null,
    );
  }

  Widget _buildActions() {
    final offer = widget.offer;

    final closeButton = OutlinedButton(
      onPressed: _busy ? null : _closeOffer,
      style: OutlinedButton.styleFrom(
        foregroundColor: kOmniInk,
        side: const BorderSide(color: kOmniBorder),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        offer.isSent ? 'Cancel Offer' : 'Decline',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );

    return Container(
      color: kOmniSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: offer.isSent
              ? closeButton
              : Row(
            children: [
              Expanded(child: closeButton),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : _accept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kOmniYellow,
                    foregroundColor: kOmniInk,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}