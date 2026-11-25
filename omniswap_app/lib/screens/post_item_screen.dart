import 'package:flutter/material.dart';

import '../config/app_limits.dart';
import '../models/inventory_item.dart';
import '../services/item_service.dart';
import '../services/post_service.dart';
import '../services/trade_service.dart' show normalizeModelKey;
import '../widgets/item_photo.dart';
import '../widgets/item_picker_sheet.dart';
import 'home_screen.dart'; // kOmniYellow, kOmniInk, kOmniMuted, kOmniBg

class PostItemScreen extends StatefulWidget {
  const PostItemScreen({super.key});

  @override
  State<PostItemScreen> createState() => _PostItemScreenState();
}

class _PostItemScreenState extends State<PostItemScreen> {
  final ItemService _itemService = ItemService();
  final PostService _postService = PostService();
  final TextEditingController _wantController = TextEditingController();

  /// Every available item in the inventory, posted or not.
  List<InventoryItem> _inventory = [];

  /// Chosen item ids, in the order they were added.
  final List<String> _selectedIds = [];

  /// Wanted items as the user typed them. Unique by model key.
  final List<String> _wants = [];

  bool _acceptsOutside = false;
  bool _loading = true;
  bool _submitting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  @override
  void dispose() {
    _wantController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  InventoryItem? _itemById(String id) {
    for (final item in _inventory) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<InventoryItem> get _selectedItems {
    final result = <InventoryItem>[];
    for (final id in _selectedIds) {
      final item = _itemById(id);
      if (item != null) result.add(item);
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  Future<void> _loadInventory() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _syncInventory();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load your inventory.';
      });
    }
  }

  /// Reloads the inventory and drops selected items that can no longer be
  /// posted, for example because they were posted elsewhere in the meantime.
  Future<void> _syncInventory() async {
    final items = await _itemService.fetchMyInventory();
    if (!mounted) return;

    final postable = {for (final item in items) if (!item.isPosted) item.id};
    final removed = _selectedIds.where((id) => !postable.contains(id)).length;

    setState(() {
      _inventory = items;
      _selectedIds.removeWhere((id) => !postable.contains(id));
    });

    if (removed > 0) {
      _showMessage(
        '$removed selected item(s) can no longer be posted and were removed.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------------

  Future<void> _openItemPicker() async {
    if (_submitting) return;

    final chosen = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ItemPickerSheet(
        items: _inventory,
        initialSelected: List<String>.of(_selectedIds),
        maxItems: kMaxItemsPerPost,
      ),
    );

    if (chosen == null || !mounted) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(chosen);
    });
  }

  void _removeSelected(String id) {
    setState(() => _selectedIds.remove(id));
  }

  // ---------------------------------------------------------------------------
  // Wants
  // ---------------------------------------------------------------------------

  /// Adds a typed want. Returns true if nothing is left to fix (added, or
  /// the text was blank). Returns false and shows a message otherwise.
  bool _addWant(String raw) {
    final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return true;

    if (text.length > kMaxWantLength) {
      _showMessage('Keep each wanted item under $kMaxWantLength characters.');
      return false;
    }
    final key = normalizeModelKey(text);
    if (key.isEmpty) {
      _showMessage('Wanted items need at least one letter or number.');
      return false;
    }
    if (_wants.any((w) => normalizeModelKey(w) == key)) {
      _showMessage('"$text" is already in your list.');
      return false;
    }
    if (_wants.length >= kMaxWantsPerPost) {
      _showMessage('You can add up to $kMaxWantsPerPost wanted items.');
      return false;
    }

    setState(() => _wants.add(text));
    return true;
  }

  void _onWantSubmitted(String value) {
    if (_addWant(value)) _wantController.clear();
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (_submitting) return;

    // A want typed but not yet added is validated and added first.
    if (!_addWant(_wantController.text)) return;
    _wantController.clear();

    if (_selectedIds.isEmpty) {
      _showMessage('Choose at least one item to post.');
      return;
    }
    if (_wants.isEmpty && !_acceptsOutside) {
      _showMessage(
        'Add a wanted item, or turn on "Also accept outside wants".',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await _postService.createPost(
        itemIds: List<String>.of(_selectedIds),
        acceptsOutsideWants: _acceptsOutside,
        wants: List<String>.of(_wants),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostException catch (e) {
      _showMessage(e.message);
      // Refresh so the user sees which items are still available.
      try {
        await _syncInventory();
      } catch (_) {}
    } catch (_) {
      _showMessage('Could not create the post. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Don't let the user leave while the post is being created.
      canPop: !_submitting,
      child: Scaffold(
        backgroundColor: kOmniBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: kOmniInk),
          title: const Text(
            'Post an Item',
            style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
          ),
        ),
        body: SafeArea(child: _buildBody()),
        bottomNavigationBar:
        _loading || _loadError != null ? null : _buildSubmitBar(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!, style: const TextStyle(color: kOmniMuted)),
            TextButton(onPressed: _loadInventory, child: const Text('Retry')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildItemsSection(),
          const SizedBox(height: 24),
          _buildWantsSection(),
          const SizedBox(height: 12),
          _buildOutsideToggle(),
        ],
      ),
    );
  }

  Widget _buildItemsSection() {
    final selected = _selectedItems;
    final full = _selectedIds.length >= kMaxItemsPerPost;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel('Items in this post'),
            const Spacer(),
            Text(
              '${_selectedIds.length}/$kMaxItemsPerPost',
              style: const TextStyle(color: kOmniMuted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _openItemPicker,
          icon: const Icon(Icons.add, size: 18),
          label: Text(_selectedIds.isEmpty ? 'Add item' : 'Change items'),
          style: OutlinedButton.styleFrom(
            foregroundColor: kOmniInk,
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFD9E0EA)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (selected.isEmpty)
          const _HintBox(
            text: 'No items yet. Tap Add item to choose from your inventory.',
          ),
        for (final item in selected)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SelectedItemTile(
              item: item,
              onRemove: _submitting ? null : () => _removeSelected(item.id),
            ),
          ),
        if (full)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'A post can hold up to $kMaxItemsPerPost items.',
              style: TextStyle(color: kOmniMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildWantsSection() {
    final full = _wants.length >= kMaxWantsPerPost;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel('What I want in return (optional)'),
            const Spacer(),
            Text(
              '${_wants.length}/$kMaxWantsPerPost',
              style: const TextStyle(color: kOmniMuted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD9E0EA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_wants.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final want in _wants)
                      InputChip(
                        label: Text(want),
                        onDeleted: _submitting
                            ? null
                            : () => setState(() => _wants.remove(want)),
                        backgroundColor: const Color(0xFFDDE6F2),
                        side: BorderSide.none,
                      ),
                  ],
                ),
              if (_wants.isNotEmpty) const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _wantController,
                      enabled: !_submitting && !full,
                      textInputAction: TextInputAction.done,
                      textCapitalization: TextCapitalization.words,
                      onSubmitted: _onWantSubmitted,
                      decoration: InputDecoration(
                        hintText: full
                            ? 'Limit reached'
                            : 'e.g. iPhone 15',
                        isDense: true,
                        filled: true,
                        fillColor: kOmniBg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add',
                    onPressed: _submitting || full
                        ? null
                        : () => _onWantSubmitted(_wantController.text),
                    icon: const Icon(Icons.add_circle, color: kOmniInk),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOutsideToggle() {
    final needsWantOrToggle = _wants.isEmpty && !_acceptsOutside;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD9E0EA)),
          ),
          child: SwitchListTile(
            value: _acceptsOutside,
            onChanged: _submitting
                ? null
                : (value) => setState(() => _acceptsOutside = value),
            title: const Text(
              'Also accept outside wants',
              style: TextStyle(fontWeight: FontWeight.w700, color: kOmniInk),
            ),
            subtitle: const Text(
              'Allow offers for items not listed above',
              style: TextStyle(color: kOmniMuted, fontSize: 13),
            ),
          ),
        ),
        if (needsWantOrToggle)
          const Padding(
            padding: EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'Add a wanted item, or turn this on, so people can make offers.',
              style: TextStyle(color: kOmniMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildSubmitBar() {
    final count = _selectedIds.length;
    final label = count == 0
        ? 'Post items'
        : 'Post $count ${count == 1 ? 'item' : 'items'}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kOmniYellow,
              foregroundColor: kOmniInk,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: kOmniInk,
              ),
            )
                : Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Small widgets
// -----------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: kOmniInk,
      ),
    );
  }
}

class _HintBox extends StatelessWidget {
  const _HintBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD9E0EA)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: kOmniMuted, fontSize: 13),
      ),
    );
  }
}

class _SelectedItemTile extends StatelessWidget {
  const _SelectedItemTile({required this.item, required this.onRemove});

  final InventoryItem item;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ItemPhoto(url: item.coverUrl, iconSize: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  item.condition.label,
                  style: const TextStyle(color: kOmniMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove from post',
            onPressed: onRemove,
            icon: const Icon(Icons.close, color: kOmniMuted),
          ),
        ],
      ),
    );
  }
}