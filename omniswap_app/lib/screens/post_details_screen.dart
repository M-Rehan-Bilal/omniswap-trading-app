import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/offer_summary.dart';
import '../models/post_details.dart';
import '../services/offers_service.dart';
import '../services/post_details_service.dart';
import '../services/post_service.dart';
import '../theme/app_colors.dart';
import '../widgets/detail_widgets.dart';
import '../widgets/item_photo.dart';
import '../widgets/offer_bundle_card.dart';
import 'home_screen.dart'; // kOmniInk, kOmniMuted, kOmniBg
import 'item_detail_screen.dart';
import 'make_offer_screen.dart';
import 'offer_details_screen.dart';

/// The bundle page: a summary of the whole post. Tapping an item opens
/// that item's own page. Offers on the post are listed below the wants.
class PostDetailsScreen extends StatefulWidget {
  const PostDetailsScreen({super.key, required this.postId});

  /// The screen loads the rest of the post itself.
  final String postId;

  @override
  State<PostDetailsScreen> createState() => _PostDetailsScreenState();
}

class _PostDetailsScreenState extends State<PostDetailsScreen> {
  final PostDetailsService _service = PostDetailsService();
  final PostService _postService = PostService();
  final OffersService _offersService = OffersService();

  PostDetails? _post;

  /// Pending and accepted offers on this post. The owner sees all of them,
  /// and anyone else sees only the offers they made.
  List<OfferSummary> _offers = [];

  bool _loading = true;
  bool _removing = false;
  String? _error;

  /// Which cover is showing in the carousel. The heading follows it.
  int _coverIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await _service.fetchPost(widget.postId);
      final offers = await _fetchOffers();
      if (!mounted) return;
      setState(() {
        _post = post;
        _offers = offers;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load this item.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Offers are secondary, so a failure here leaves the list empty
  /// instead of hiding the whole post.
  Future<List<OfferSummary>> _fetchOffers() async {
    try {
      return await _offersService.fetchOffersForPost(widget.postId);
    } catch (e) {
      debugPrint('Post offers load failed: $e');
      return const [];
    }
  }

  Future<void> _reloadOffers() async {
    final offers = await _fetchOffers();
    if (!mounted) return;
    setState(() => _offers = offers);
  }

  bool get _isOwner {
    final post = _post;
    return post != null && post.ownerId == _service.currentUserId;
  }

  void _openItem(PostDetails post, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(post: post, index: index),
      ),
    );
  }

  void _makeOffer(PostDetails post) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MakeOfferScreen(post: post)),
    );
  }

  /// Opens one offer. If it was declined or cancelled there, reload the list.
  Future<void> _openOffer(OfferSummary offer) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OfferDetailsScreen(
          offer: offer,
          service: _offersService,
        ),
      ),
    );
    if (changed == true) await _reloadOffers();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Owner only. Asks first, then removes the post and goes back.
  /// Pops with true so the Inventory screen reloads.
  Future<void> _confirmRemove(PostDetails post) async {
    final count = post.items.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this post?'),
        content: Text(
          'The post holds $count ${count == 1 ? 'item' : 'items'}. '
              'They become available again, and any pending offers on this '
              'post are cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep post'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Remove',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removing = true);
    try {
      await _postService.removePost(post.postId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostException catch (e) {
      _showSnack(e.message);
    } catch (_) {
      _showSnack('Could not remove the post. Please try again.');
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final isOwner = _isOwner;

    return Scaffold(
      backgroundColor: kOmniBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: kOmniInk),
        title: Text(
          post != null && post.isBundle ? 'Bundle' : 'Item',
          style: const TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
      ),
      body: _buildBody(post, isOwner),
      bottomNavigationBar: post == null
          ? null
          : isOwner
          ? _OwnerBar(
        removing: _removing,
        onRemove: () => _confirmRemove(post),
      )
          : MakeOfferBar(
        itemCount: post.items.length,
        onPressed: () => _makeOffer(post),
      ),
    );
  }

  Widget _buildBody(PostDetails? post, bool isOwner) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (_error != null) {
      return CenteredMessage(text: _error!, onRetry: _load);
    }
    if (post == null) {
      return const CenteredMessage(
        text: 'This post is no longer available.',
      );
    }

    final count = post.items.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOwner) ...[
            const _OwnerBanner(),
            const SizedBox(height: 16),
          ],
          _CoverCarousel(
            items: post.items,
            onTap: (index) => _openItem(post, index),
            onPageChanged: (index) => setState(() => _coverIndex = index),
          ),
          const SizedBox(height: 16),
          Text(
            post.titleFor(_coverIndex),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: kOmniInk,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count ${count == 1 ? 'item' : 'items'} · ${post.conditionSummary}',
            style: const TextStyle(color: kOmniMuted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          _SellerCard(owner: post.owner, showContact: !isOwner),
          const SizedBox(height: 24),
          SectionLabel(post.isBundle ? 'IN THIS BUNDLE' : 'ITEM'),
          const SizedBox(height: 8),
          for (var i = 0; i < count; i++) ...[
            _BundleItemRow(
              item: post.items[i],
              onTap: () => _openItem(post, i),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          const SectionLabel('WANTS IN RETURN'),
          const SizedBox(height: 8),
          _buildWants(post),
          const SizedBox(height: 24),
          _buildOffers(isOwner),
        ],
      ),
    );
  }

  Widget _buildWants(PostDetails post) {
    if (post.wants.isEmpty) {
      return Text(
        post.acceptsOutsideWants ? 'Open to any item' : 'No wants listed',
        style: const TextStyle(color: kOmniMuted, fontSize: 13),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final want in post.wants) _WantChip(label: want),
          ],
        ),
        if (post.acceptsOutsideWants) ...[
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: kOmniMuted),
              SizedBox(width: 6),
              Text(
                'Also open to other offers',
                style: TextStyle(color: kOmniMuted, fontSize: 13),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The offers on this post. The owner sees every offer made to it.
  /// Anyone else sees only the offers they made.
  Widget _buildOffers(bool isOwner) {
    final count = _offers.length;
    final heading = isOwner ? 'OFFERS ($count)' : 'YOUR OFFERS ($count)';

    if (_offers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(heading),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isOwner
                  ? 'No offers on this post yet.'
                  : "You haven't made an offer on this post.",
              style: const TextStyle(color: kOmniMuted, fontSize: 13),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(heading),
        const SizedBox(height: 8),
        for (final offer in _offers) ...[
          _OfferCard(offer: offer, onTap: () => _openOffer(offer)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Cover carousel: one page per item, showing its cover photo.
// Tapping a cover opens that item's page.
// -----------------------------------------------------------------------------

class _CoverCarousel extends StatefulWidget {
  const _CoverCarousel({
    required this.items,
    required this.onTap,
    required this.onPageChanged,
  });

  final List<PostDetailItem> items;
  final ValueChanged<int> onTap;

  /// Tells the parent which cover is showing, so it can update the heading.
  final ValueChanged<int> onPageChanged;

  @override
  State<_CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends State<_CoverCarousel> {
  int _index = 0;

  void _onPageChanged(int index) {
    setState(() => _index = index);
    widget.onPageChanged(index);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final current = items[_index];

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 240,
            width: double.infinity,
            child: Stack(
              children: [
                PageView.builder(
                  itemCount: items.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => widget.onTap(i),
                    child: ItemPhoto(url: items[i].coverUrl, iconSize: 56),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: _OverlayLabel(current.condition.label),
                ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: _OverlayLabel(current.title),
                ),
              ],
            ),
          ),
        ),
        if (items.length > 1) ...[
          const SizedBox(height: 8),
          PageDots(count: items.length, index: _index),
          const SizedBox(height: 4),
          Text(
            '${_index + 1}/${items.length}',
            style: const TextStyle(color: kOmniMuted, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Seller card: name, rating and location, then the contact section.
// -----------------------------------------------------------------------------

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.owner, required this.showContact});

  final PostOwner owner;

  /// False when the viewer owns the post, so they never see their own contact.
  final bool showContact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SellerHeader(owner: owner),
          if (showContact) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: Color(0xFFE6EAF1)),
            const SizedBox(height: 18),
            const SectionLabel('CONTACT SELLER'),
            const SizedBox(height: 12),
            _ContactSection(phone: owner.phone),
          ],
        ],
      ),
    );
  }
}

class _SellerHeader extends StatelessWidget {
  const _SellerHeader({required this.owner});

  final PostOwner owner;

  @override
  Widget build(BuildContext context) {
    final initial = owner.name.isEmpty ? '?' : owner.name[0].toUpperCase();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Yellow ring around the avatar, matching the profile screen.
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            backgroundImage:
            owner.avatarUrl != null ? NetworkImage(owner.avatarUrl!) : null,
            child: owner.avatarUrl == null
                ? Text(
              initial,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            )
                : null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                owner.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: kOmniInk,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.place_rounded, size: 14, color: kOmniMuted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      owner.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kOmniMuted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _RatingChip(rating: owner.rating),
      ],
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Contact: phone number with copy, then Call and WhatsApp buttons.
// -----------------------------------------------------------------------------

class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.phone});

  final String? phone;

  /// "+923001234567" becomes "+92 300 1234567". Other numbers are shown as-is.
  static String _format(String number) {
    final match = RegExp(r'^\+92(\d{3})(\d{7})$').firstMatch(number);
    return match == null ? number : '+92 ${match[1]} ${match[2]}';
  }

  void _showSnack(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Text(
            text,
            style: const TextStyle(color: AppColors.onPrimary),
          ),
        ),
      );
  }

  Future<void> _copy(BuildContext context, String number) async {
    await Clipboard.setData(ClipboardData(text: number));
    await HapticFeedback.lightImpact();
    if (!context.mounted) return;
    _showSnack(context, 'Phone number copied');
  }

  Future<void> _call(BuildContext context, String number) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok && context.mounted) {
      _showSnack(context, 'Could not open the dialer.');
    }
  }

  Future<void> _whatsApp(BuildContext context, String number) async {
    // wa.me expects the number without the plus sign.
    final uri = Uri.parse('https://wa.me/${number.replaceAll('+', '')}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      _showSnack(context, 'Could not open WhatsApp.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final number = phone;

    if (number == null || number.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6FA),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 18, color: kOmniMuted),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Contact details are not available right now.',
                style: TextStyle(color: kOmniMuted, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Phone number row. Tapping it copies the number.
        Material(
          color: AppColors.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _copy(context, number),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.phone_rounded,
                      size: 20,
                      color: AppColors.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _format(number),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: kOmniInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'WhatsApp number · Tap to copy',
                          style: TextStyle(color: kOmniMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy number',
                    onPressed: () => _copy(context, number),
                    icon: const Icon(
                      Icons.copy_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Action buttons.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _call(context, number),
                icon: const Icon(Icons.call_rounded, size: 18),
                label: const Text('Call'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.5),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () => _whatsApp(context, number),
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('Message on WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Offers on this post
// -----------------------------------------------------------------------------

/// One offer: who it is from or to, its status, and the items offered with
/// each item's photo, title and condition. Tapping opens the full offer.
class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.onTap});

  final OfferSummary offer;
  final VoidCallback onTap;

  /// Items shown in full. Any more are counted in a line below.
  static const int _maxRows = 3;

  @override
  Widget build(BuildContext context) {
    final shown = offer.offered.take(_maxRows).toList();
    final hidden = offer.offered.length - shown.length;
    final who = offer.isSent
        ? 'Your offer to ${offer.otherName}'
        : 'From ${offer.otherName}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      who,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kOmniInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OfferStatusBadge(offer.status),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Sent ${offer.createdLabel}',
                style: const TextStyle(color: kOmniMuted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              if (offer.offered.isEmpty)
                const Text(
                  'These items are no longer available.',
                  style: TextStyle(color: kOmniMuted, fontSize: 13),
                )
              else ...[
                for (final entry in shown) ...[
                  _OfferedItemLine(entry: entry),
                  const SizedBox(height: 8),
                ],
                if (hidden > 0)
                  Text(
                    '+ $hidden more ${hidden == 1 ? 'item' : 'items'}',
                    style: const TextStyle(color: kOmniMuted, fontSize: 12),
                  ),
              ],
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'View offer',
                  style: TextStyle(
                    color: kOmniMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

/// One offered item: photo, title and condition.
class _OfferedItemLine extends StatelessWidget {
  const _OfferedItemLine({required this.entry});

  final OfferEntry entry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ItemPhoto(url: entry.url, iconSize: 18),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: kOmniInk,
                ),
              ),
              if (entry.conditionLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  entry.conditionLabel!,
                  style: const TextStyle(color: kOmniMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Rows, chips and labels
// -----------------------------------------------------------------------------

/// One item in the bundle: cover, title, condition, photo count, and an arrow.
class _BundleItemRow extends StatelessWidget {
  const _BundleItemRow({required this.item, required this.onTap});

  final PostDetailItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ItemPhoto(url: item.coverUrl, iconSize: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kOmniInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.photoCount} ${item.photoCount == 1 ? 'photo' : 'photos'}',
                      style: const TextStyle(color: kOmniMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              ConditionChip(item.condition.label),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: kOmniMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayLabel extends StatelessWidget {
  const _OverlayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    // Taps pass through to the photo underneath.
    return IgnorePointer(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kOmniInk,
            ),
          ),
        ),
      ),
    );
  }
}

class _WantChip extends StatelessWidget {
  const _WantChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: kOmniInk, fontSize: 13),
      ),
    );
  }
}

/// Shown at the top of the post page when the viewer owns the post.
class _OwnerBanner extends StatelessWidget {
  const _OwnerBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kOmniYellow, width: 1.5),
      ),
      child: const Row(
        children: [
          Icon(Icons.visibility_outlined, color: kOmniInk, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This is your post. This is how other traders see it.',
              style: TextStyle(color: kOmniInk, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom bar for the owner. Replaces "Make an Offer".
class _OwnerBar extends StatelessWidget {
  const _OwnerBar({required this.removing, required this.onRemove});

  final bool removing;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final red = Colors.red.shade700;

    return Container(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: removing ? null : onRemove,
              icon: removing
                  ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.remove_circle_outline),
              label: const Text(
                'Remove post',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: red,
                side: BorderSide(color: red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}