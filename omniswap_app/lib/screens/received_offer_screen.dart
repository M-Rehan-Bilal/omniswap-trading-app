import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/offer_summary.dart';
import '../services/offers_service.dart';
import '../services/trade_action_service.dart';
import '../theme/omni_colors.dart';
import '../widgets/item_photo.dart';
import 'offer_details_screen.dart' show closeOfferWithConfirm;
import 'trade_screen.dart';

/// Screen for an offer someone made to me.
/// Shows what I give and what I get, with Reject and Accept buttons.
class ReceivedOfferScreen extends StatefulWidget {
  const ReceivedOfferScreen({super.key, required this.offer, this.service});

  final OfferSummary offer;

  /// Optional, so tests can inject a fake service.
  final OffersService? service;

  @override
  State<ReceivedOfferScreen> createState() => _ReceivedOfferScreenState();
}

class _ReceivedOfferScreenState extends State<ReceivedOfferScreen> {
  late final OffersService _service;
  final TradeActionService _trades = TradeActionService();

  double? _rating;
  String? _avatarUrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? OffersService();
    _loadProfile();
  }

  /// Loads the offerer's photo and rating. The screen still works without them.
  Future<void> _loadProfile() async {
    try {
      final row = await Supabase.instance.client
          .from('public_profiles')
          .select('avatar_url, rating')
          .eq('id', widget.offer.otherUserId)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() {
        _avatarUrl = row['avatar_url'] as String?;
        _rating = (row['rating'] as num).toDouble();
      });
    } catch (_) {
      // Keep the default avatar and hide the rating.
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    final done = await closeOfferWithConfirm(context, widget.offer, _service);
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) Navigator.pop(context, true);
  }

  /// Creates the trade, then opens it. When the trade screen closes,
  /// this screen closes too, so My Offers reloads.
  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final tradeId = await _trades.acceptOffer(widget.offer.id);
      if (!mounted) return;
      await navigator.push(
        MaterialPageRoute(builder: (_) => TradeScreen(tradeId: tradeId)),
      );
      navigator.pop(true);
    } on TradeActionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _viewProfile() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile page is coming soon.')),
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
          'Review and accept',
          style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Offer from ${offer.otherName}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: kOmniInk,
            ),
          ),
          const SizedBox(height: 16),
          _buildProfileCard(),
          const SizedBox(height: 16),
          _OfferSide(title: 'You give', entries: offer.offered),
          const SizedBox(height: 16),
          _OfferSide(title: 'You get', entries: offer.postItems),
        ],
      ),
      bottomNavigationBar: offer.isPending ? _buildActions() : null,
    );
  }

  Widget _buildProfileCard() {
    final rating = _rating;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardBox,
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: kOmniSelectedBg,
            backgroundImage:
            _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
            child: _avatarUrl == null
                ? Text(
              _initial(widget.offer.otherName),
              style: const TextStyle(
                color: kOmniBlue,
                fontWeight: FontWeight.w700,
              ),
            )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.offer.otherName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kOmniInk,
                  ),
                ),
                if (rating != null)
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 14, color: kOmniGold),
                      const SizedBox(width: 2),
                      Text(
                        '${rating.toStringAsFixed(1)} stars',
                        style: const TextStyle(
                          color: kOmniMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: _viewProfile,
            style: OutlinedButton.styleFrom(
              foregroundColor: kOmniBlue,
              side: const BorderSide(color: kOmniBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Profile'),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      color: kOmniSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kOmniInk,
                    side: const BorderSide(color: kOmniBorder),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Reject',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ),
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
                  child: _busy
                      ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: kOmniInk,
                    ),
                  )
                      : const Text(
                    'Accept Offer',
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

  static String _initial(String name) =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
}

const BoxDecoration _cardBox = BoxDecoration(
  color: kOmniSurface,
  borderRadius: BorderRadius.all(Radius.circular(16)),
  border: Border.fromBorderSide(BorderSide(color: kOmniBorder)),
);

/// A card with a small heading and the items side by side.
class _OfferSide extends StatelessWidget {
  const _OfferSide({required this.title, required this.entries});

  final String title;
  final List<OfferEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardBox,
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kOmniBlue,
            ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Text(
              'No longer available.',
              style: TextStyle(color: kOmniMuted, fontSize: 13),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in entries) _ItemTile(entry: entry),
              ],
            ),
        ],
      ),
    );
  }
}

/// One item: photo on a light blue tile, title below it.
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.entry});

  final OfferEntry entry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        children: [
          Container(
            width: 140,
            height: 100,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: kOmniSelectedBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: ItemPhoto(url: entry.url, iconSize: 28),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: kOmniInk,
            ),
          ),
        ],
      ),
    );
  }
}