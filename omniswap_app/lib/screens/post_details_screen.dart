import 'package:flutter/material.dart';

import '../models/post_details.dart';
import '../services/post_details_service.dart';
import '../widgets/detail_widgets.dart';
import '../widgets/item_photo.dart';
import 'home_screen.dart'; // kOmniInk, kOmniMuted, kOmniBg
import 'item_detail_screen.dart';
import 'make_offer_screen.dart';

/// The bundle page: a summary of the whole post. Tapping an item opens
/// that item's own page.
class PostDetailsScreen extends StatefulWidget {
  const PostDetailsScreen({super.key, required this.postId});

  /// The screen loads the rest of the post itself.
  final String postId;

  @override
  State<PostDetailsScreen> createState() => _PostDetailsScreenState();
}

class _PostDetailsScreenState extends State<PostDetailsScreen> {
  final PostDetailsService _service = PostDetailsService();

  PostDetails? _post;
  bool _loading = true;
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
      if (!mounted) return;
      setState(() => _post = post);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load this item.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openItem(PostDetails post, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(post: post, index: index),
      ),
    );
  }

  /// Opens the Make an Offer screen for the whole post.
  void _makeOffer(PostDetails post) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MakeOfferScreen(post: post)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final isOwner = post != null && post.ownerId == _service.currentUserId;

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
      body: _buildBody(post),
      bottomNavigationBar: post != null && !isOwner
          ? MakeOfferBar(
        itemCount: post.items.length,
        onPressed: () => _makeOffer(post),
      )
          : null,
    );
  }

  Widget _buildBody(PostDetails? post) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
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
          _SellerCard(owner: post.owner),
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
          const SizedBox(height: 8),
          const SectionLabel('WANTS IN RETURN'),
          const SizedBox(height: 8),
          _buildWants(post),
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
// Rows and cards
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

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.owner});

  final PostOwner owner;

  @override
  Widget build(BuildContext context) {
    final initial = owner.name.isEmpty ? '?' : owner.name[0].toUpperCase();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFCFE3FA),
            backgroundImage: owner.avatarUrl != null
                ? NetworkImage(owner.avatarUrl!)
                : null,
            child: owner.avatarUrl == null
                ? Text(
              initial,
              style: const TextStyle(
                color: kOmniInk,
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        owner.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: kOmniInk,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.star_rounded,
                        size: 16, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(
                      owner.rating.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 13, color: kOmniInk),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  owner.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kOmniMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
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
        border: Border.all(color: const Color(0xFF9FB0C8)),
      ),
      child: Text(
        label,
        style: const TextStyle(color: kOmniInk, fontSize: 13),
      ),
    );
  }
}