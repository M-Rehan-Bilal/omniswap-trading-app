import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../services/item_service.dart';
import '../services/post_service.dart';
import '../widgets/item_photo.dart';
import '../widgets/omni_bottom_bar.dart';
import 'home_screen.dart'; // kOmniYellow, kOmniInk, kOmniMuted, kOmniBg
import 'item_details_screen.dart';
import 'add_item_screen.dart';
import 'post_item_screen.dart';

enum _ItemAction { details, removePost }

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final ItemService _service = ItemService();
  final PostService _postService = PostService();

  List<InventoryItem> _items = [];
  bool _loading = true;
  String? _error;

  String? _bannerTitle;
  String? _bannerSubtitle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _service.fetchMyInventory();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your inventory.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InventoryItem? _itemById(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _showBanner({required String title, required String subtitle}) {
    if (!mounted) return;
    setState(() {
      _bannerTitle = title;
      _bannerSubtitle = subtitle;
    });
  }

  void _clearBanner() {
    if (_bannerTitle == null) return;
    setState(() {
      _bannerTitle = null;
      _bannerSubtitle = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _openAddItem() async {
    final addedId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const AddItemScreen()),
    );
    if (addedId == null || !mounted) return;

    await _load();
    final added = _itemById(addedId);
    if (added != null) {
      _showBanner(title: added.title, subtitle: 'Added to your inventory');
    }
  }

  Future<void> _openPost() async {
    _clearBanner();
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PostItemScreen()),
    );
    if (posted != true || !mounted) return;

    await _load();
    _showBanner(
      title: 'Post created',
      subtitle: 'Other traders can now see it on Home',
    );
  }

  Future<void> _openDetails(InventoryItem item) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ItemDetailsScreen(item: item)),
    );
    if (changed == true) _load();
  }

  Future<void> _onItemTap(InventoryItem item) async {
    _clearBanner();

    if (!item.isPosted) {
      await _openDetails(item);
      return;
    }

    final action = await showModalBottomSheet<_ItemAction>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: kOmniInk,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: kOmniInk),
              title: const Text('View details'),
              onTap: () => Navigator.pop(sheetContext, _ItemAction.details),
            ),
            ListTile(
              leading: Icon(
                Icons.remove_circle_outline,
                color: Colors.red.shade700,
              ),
              title: Text(
                'Remove post',
                style: TextStyle(color: Colors.red.shade700),
              ),
              onTap: () =>
                  Navigator.pop(sheetContext, _ItemAction.removePost),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case _ItemAction.details:
        await _openDetails(item);
        break;
      case _ItemAction.removePost:
        await _confirmRemovePost(item);
        break;
    }
  }

  Future<void> _confirmRemovePost(InventoryItem item) async {
    final postId = item.postId;
    if (postId == null) return;

    final count = _items.where((i) => i.postId == postId).length;
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

    try {
      await _postService.removePost(postId);
      await _load();
      _showBanner(
        title: 'Post removed',
        subtitle: 'Its items are available to post again',
      );
    } on PostException catch (e) {
      _showMessage(e.message);
      await _load();
    } catch (_) {
      _showMessage('Could not remove the post. Please try again.');
    }
  }

  void _onTab(OmniTab tab) {
    switch (tab) {
      case OmniTab.home:
        Navigator.pop(context);
        break;
      case OmniTab.browse:
        Navigator.pushNamed(context, '/browse');
        break;
      case OmniTab.inventory:
        break;
      case OmniTab.trades:
        Navigator.pushNamed(context, '/trades');
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kOmniBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: kOmniInk),
        title: const Text(
          'My Inventory',
          style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: _openAddItem,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kOmniInk,
                side: const BorderSide(color: Color(0xFFD9E0EA)),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(child: _buildHeader()),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _buildGrid(),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              sliver: SliverToBoxAdapter(child: _buildInfoNote()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: _buildPostButton()),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kOmniYellow,
        elevation: 2,
        onPressed: _openAddItem,
        child: const Icon(Icons.add, color: kOmniInk, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: OmniBottomBar(
        selected: OmniTab.inventory,
        onSelect: _onTab,
      ),
    );
  }

  Widget _buildHeader() {
    final count = _items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_bannerTitle != null) ...[
          _AddedBanner(
            title: _bannerTitle!,
            subtitle: _bannerSubtitle ?? '',
            onClose: _clearBanner,
          ),
          const SizedBox(height: 16),
        ],
        Text(
          '$count ${count == 1 ? 'item' : 'items'}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: kOmniInk,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildGrid() {
    if (_loading && _items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: kOmniMuted)),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return SliverGrid.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.82,
      children: [
        for (final item in _items)
          _ItemCard(item: item, onTap: () => _onItemTap(item)),
        _AddItemTile(onTap: _openAddItem),
      ],
    );
  }

  Widget _buildInfoNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E0EA)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: kOmniMuted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'An item can be in only one post at a time. '
                  'Remove its post to post it again.',
              style: TextStyle(color: kOmniMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: _openPost,
        style: OutlinedButton.styleFrom(
          foregroundColor: kOmniInk,
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFD9E0EA)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          '+ Post',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.onTap});

  final InventoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: ItemPhoto(url: item.coverUrl)),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _TagBadge(
                      label: item.condition.label,
                      background: Colors.white,
                    ),
                  ),
                  if (item.isPosted)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _TagBadge(
                        label: 'Posted',
                        background: kOmniYellow,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: kOmniInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagBadge extends StatelessWidget {
  const _TagBadge({required this.label, required this.background});

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

class _AddItemTile extends StatelessWidget {
  const _AddItemTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFB8C4D6), width: 1.5),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 28, color: kOmniMuted),
              SizedBox(height: 6),
              Text(
                'Add item',
                style: TextStyle(color: kOmniMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddedBanner extends StatelessWidget {
  const _AddedBanner({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: kOmniBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: kOmniInk, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kOmniInk,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: const TextStyle(color: kOmniMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, color: kOmniMuted),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}