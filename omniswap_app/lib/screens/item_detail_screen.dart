import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_details.dart';
import '../widgets/detail_widgets.dart';
import '../widgets/item_photo.dart';
import 'home_screen.dart'; // kOmniInk, kOmniMuted, kOmniBg
import 'make_offer_screen.dart';

/// One item's page: all of its photos and details.
/// The whole post is passed in, so moving between items needs no new request.
class ItemDetailScreen extends StatefulWidget {
  const ItemDetailScreen({super.key, required this.post, required this.index});

  final PostDetails post;

  /// Position of the item to show in [post.items].
  final int index;

  @override
  State<ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<ItemDetailScreen> {
  int _photoIndex = 0;

  PostDetailItem get _item => widget.post.items[widget.index];

  bool get _isOwner =>
      widget.post.ownerId == Supabase.instance.client.auth.currentUser?.id;

  /// Replaces this page with another item of the same post.
  /// Back still goes to the bundle page.
  void _openItem(int index) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ItemDetailScreen(post: widget.post, index: index),
      ),
    );
  }

  void _openViewer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PhotoViewerScreen(
          urls: _item.photoUrls,
          initialIndex: _photoIndex,
        ),
      ),
    );
  }

  void _makeOffer() {
    // Offers always cover the whole post, even when the user opened one item.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MakeOfferScreen(post: widget.post)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final item = _item;

    return Scaffold(
      backgroundColor: kOmniBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: kOmniInk),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
        actions: [
          if (post.isBundle)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${widget.index + 1} of ${post.items.length}',
                  style: const TextStyle(color: kOmniMuted, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPhotos(item),
            if (item.photoCount > 1) ...[
              const SizedBox(height: 8),
              PageDots(count: item.photoCount, index: _photoIndex),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: kOmniInk,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ConditionChip(item.condition.label),
              ],
            ),
            if (item.manufactureYear != null) ...[
              const SizedBox(height: 4),
              Text(
                'Manufactured ${item.manufactureYear}',
                style: const TextStyle(color: kOmniMuted, fontSize: 14),
              ),
            ],
            const SizedBox(height: 20),
            const SectionLabel('ABOUT THIS ITEM'),
            const SizedBox(height: 8),
            Text(
              item.description.trim().isEmpty
                  ? 'No description added.'
                  : item.description,
              style: const TextStyle(
                color: kOmniInk,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            if (post.isBundle) ...[
              const SizedBox(height: 24),
              const SectionLabel('OTHER ITEMS IN THIS BUNDLE'),
              const SizedBox(height: 8),
              _buildOtherItems(post),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _isOwner
          ? null
          : MakeOfferBar(itemCount: post.items.length, onPressed: _makeOffer),
    );
  }

  /// The photo strip. Swipe to see every photo. Tap a photo, or the
  /// counter, to open it full screen.
  Widget _buildPhotos(PostDetailItem item) {
    final urls = item.photoUrls;
    final hasPhotos = urls.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 300,
        width: double.infinity,
        child: Stack(
          children: [
            PageView.builder(
              itemCount: hasPhotos ? urls.length : 1,
              onPageChanged: (i) => setState(() => _photoIndex = i),
              itemBuilder: (_, i) => GestureDetector(
                onTap: hasPhotos ? _openViewer : null,
                child: ItemPhoto(
                  url: hasPhotos ? urls[i] : null,
                  iconSize: 56,
                ),
              ),
            ),
            if (hasPhotos)
              Positioned(
                bottom: 12,
                right: 12,
                child: _PhotoCounter(
                  current: _photoIndex + 1,
                  total: urls.length,
                  onTap: _openViewer,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Thumbnails of the other items in the bundle. The current item is left out.
  Widget _buildOtherItems(PostDetails post) {
    final otherIndexes = [
      for (var i = 0; i < post.items.length; i++)
        if (i != widget.index) i,
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final i in otherIndexes)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _OtherItemTile(
                item: post.items[i],
                onTap: () => _openItem(i),
              ),
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Small widgets
// -----------------------------------------------------------------------------

class _PhotoCounter extends StatelessWidget {
  const _PhotoCounter({
    required this.current,
    required this.total,
    required this.onTap,
  });

  final int current;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$current/$total',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kOmniInk,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_full, size: 14, color: kOmniInk),
          ],
        ),
      ),
    );
  }
}

class _OtherItemTile extends StatelessWidget {
  const _OtherItemTile({required this.item, required this.onTap});

  final PostDetailItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD9E0EA)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: ItemPhoto(url: item.coverUrl, iconSize: 22),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kOmniInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen photo viewer. Swipe between photos, pinch to zoom.
class _PhotoViewerScreen extends StatefulWidget {
  const _PhotoViewerScreen({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  State<_PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<_PhotoViewerScreen> {
  late final PageController _pages =
  PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text('${_index + 1}/${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Image.network(
            widget.urls[i],
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}