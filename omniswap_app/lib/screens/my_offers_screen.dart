import 'package:flutter/material.dart';

import '../models/offer_summary.dart';
import '../services/offers_service.dart';
import '../theme/omni_colors.dart';
import '../widgets/item_photo.dart';
import '../widgets/offer_bundle_card.dart';
import '../widgets/omni_bottom_bar.dart';
import 'offer_details_screen.dart';
import 'received_offer_screen.dart';

/// The Trades tab: offers I sent and offers I received.
class MyOffersScreen extends StatefulWidget {
  const MyOffersScreen({super.key, this.service});

  /// Optional, so tests can inject a fake service.
  final OffersService? service;

  @override
  State<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends State<MyOffersScreen> {
  late final OffersService _service;

  List<OfferSummary> _offers = [];
  bool _loading = true;
  String? _error;

  /// The offer whose Cancel / Decline is running.
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? OffersService();
    _load();
  }

  List<OfferSummary> get _sent => [for (final o in _offers) if (o.isSent) o];
  List<OfferSummary> get _received =>
      [for (final o in _offers) if (!o.isSent) o];

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _loading = true);
    try {
      final offers = await _service.fetchOffers();
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('My offers load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your offers.';
        _loading = false;
      });
    }
  }

  Future<void> _openDetails(OfferSummary offer) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => offer.isSent
            ? OfferDetailsScreen(offer: offer, service: _service)
            : ReceivedOfferScreen(offer: offer, service: _service),
      ),
    );
    if (changed == true) _load(showSpinner: false);
  }

  Future<void> _closeOffer(OfferSummary offer) async {
    if (_busyId != null) return;
    setState(() => _busyId = offer.id);
    final done = await closeOfferWithConfirm(context, offer, _service);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (done) _load(showSpinner: false);
  }

  void _onTab(OmniTab tab) {
    switch (tab) {
      case OmniTab.home:
        Navigator.popUntil(context, (route) => route.isFirst);
        break;
      case OmniTab.browse:
        Navigator.pushReplacementNamed(context, '/browse');
        break;
      case OmniTab.inventory:
        Navigator.pushReplacementNamed(context, '/inventory');
        break;
      case OmniTab.trades:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: kOmniBg,
        appBar: AppBar(
          backgroundColor: kOmniSurface,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: const Text(
            'My Offers',
            style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
          ),
          bottom: TabBar(
            labelColor: kOmniInk,
            unselectedLabelColor: kOmniMuted,
            indicatorColor: kOmniBlue,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'Sent (${_sent.length})'),
              Tab(text: 'Received (${_received.length})'),
            ],
          ),
        ),
        body: _buildBody(),
        floatingActionButton: FloatingActionButton(
          backgroundColor: kOmniYellow,
          elevation: 2,
          onPressed: () => Navigator.pushNamed(context, '/add-item'),
          child: const Icon(Icons.add, color: kOmniInk, size: 30),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: OmniBottomBar(
          selected: OmniTab.trades,
          onSelect: _onTab,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _offers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _offers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: kOmniMuted)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return TabBarView(
      children: [
        _OfferList(
          offers: _sent,
          emptyText: "You haven't sent any offers yet.",
          busyId: _busyId,
          onRefresh: () => _load(showSpinner: false),
          onView: _openDetails,
          onClose: _closeOffer,
        ),
        _OfferList(
          offers: _received,
          emptyText: 'Offers sent to you will appear here.',
          busyId: _busyId,
          onRefresh: () => _load(showSpinner: false),
          onView: _openDetails,
          onClose: _closeOffer,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// List and card
// -----------------------------------------------------------------------------

class _OfferList extends StatelessWidget {
  const _OfferList({
    required this.offers,
    required this.emptyText,
    required this.busyId,
    required this.onRefresh,
    required this.onView,
    required this.onClose,
  });

  final List<OfferSummary> offers;
  final String emptyText;
  final String? busyId;
  final Future<void> Function() onRefresh;
  final ValueChanged<OfferSummary> onView;
  final ValueChanged<OfferSummary> onClose;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: offers.isEmpty
          ? ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.inbox_outlined, size: 40, color: kOmniMuted),
          const SizedBox(height: 8),
          Text(
            emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kOmniMuted),
          ),
        ],
      )
          : ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        itemCount: offers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final offer = offers[i];
          return _OfferCard(
            offer: offer,
            busy: busyId == offer.id,
            onView: () => onView(offer),
            onClose: () => onClose(offer),
          );
        },
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.busy,
    required this.onView,
    required this.onClose,
  });

  final OfferSummary offer;
  final bool busy;
  final VoidCallback onView;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              Expanded(
                child: Text(
                  offer.isSent
                      ? 'To: ${offer.otherName}'
                      : 'From: ${offer.otherName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kOmniInk,
                  ),
                ),
              ),
              OfferStatusBadge(offer.status),
            ],
          ),
          const SizedBox(height: 12),
          _ThumbRow(offer: offer),
          const SizedBox(height: 10),
          Text(
            offer.summaryLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kOmniMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onView,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kOmniYellow,
                    foregroundColor: kOmniInk,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'View Offer',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (offer.isPending) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onClose,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kOmniInk,
                      side: const BorderSide(color: kOmniBorder),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: busy
                        ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Text(
                      offer.isSent ? 'Cancel Offer' : 'Decline',
                      style:
                      const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Small tiles: offered items, an arrow, then the items in the post.
class _ThumbRow extends StatelessWidget {
  const _ThumbRow({required this.offer});

  final OfferSummary offer;

  static const double _size = 60;

  Widget _tile(OfferEntry entry) => Container(
    width: _size,
    height: _size,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: const Color(0xFFDDEAF8),
      borderRadius: BorderRadius.circular(10),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ItemPhoto(url: entry.url, iconSize: 20),
    ),
  );

  @override
  Widget build(BuildContext context) {
    const plus = Padding(
      padding: EdgeInsets.symmetric(horizontal: 6),
      child: Text('+', style: TextStyle(color: kOmniMuted)),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < offer.offered.length; i++) ...[
            if (i > 0) plus,
            _tile(offer.offered[i]),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.arrow_forward, size: 18, color: kOmniBlue),
          ),
          if (offer.postItems.isEmpty)
            const Text(
              'Post unavailable',
              style: TextStyle(color: kOmniMuted, fontSize: 12),
            )
          else
            for (var i = 0; i < offer.postItems.length; i++) ...[
              if (i > 0) plus,
              _tile(offer.postItems[i]),
            ],
        ],
      ),
    );
  }
}