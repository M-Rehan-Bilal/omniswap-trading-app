import 'package:flutter/material.dart';

import '../config/app_limits.dart';
import '../models/inventory_item.dart';
import '../services/item_service.dart';
import '../services/post_service.dart';
import '../services/trade_service.dart' show normalizeModelKey;
import '../theme/app_colors.dart';
import '../widgets/item_photo.dart';
import '../widgets/item_picker_sheet.dart';
import 'home_screen.dart'; // kOmniInk, kOmniMuted, kOmniBg

/// Whether the entry being added is a single item or a bundle.
enum _WantMode { single, bundle }

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

  /// Saved wanted entries. Each inner list is one entry: one name for a
  /// single item, or two or more names for a bundle. Order does not matter.
  final List<List<String>> _wants = [];

  /// Names of the bundle being built. Not saved until the user saves it.
  final List<String> _pendingBundle = [];

  _WantMode _mode = _WantMode.single;
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
  // Wanted entries
  // ---------------------------------------------------------------------------

  /// Trims and collapses spaces, as the database does.
  static String _tidy(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Returns a message if [text] cannot be a wanted item, otherwise null.
  String? _checkName(String text) {
    if (text.length > kMaxWantLength) {
      return 'Keep each wanted item under $kMaxWantLength characters.';
    }
    if (normalizeModelKey(text).isEmpty) {
      return 'Wanted items need at least one letter or number.';
    }
    return null;
  }

  /// True if a new entry with these names may be added to the list.
  bool _canAddEntry(List<String> names) {
    if (_wants.length >= kMaxWantsPerPost) {
      _showMessage('You can add up to $kMaxWantsPerPost wanted items or bundles.');
      return false;
    }
    final signature = _signatureOf(names);
    if (_wants.any((entry) => _signatureOf(entry) == signature)) {
      _showMessage('That wanted item is already in your list.');
      return false;
    }
    return true;
  }

  /// Same idea as the database signature: sorted keys joined by "|".
  static String _signatureOf(Iterable<String> names) =>
      (names.map(normalizeModelKey).toList()..sort()).join('|');

  /// Adds the text in the field. In single mode it becomes its own entry.
  /// In bundle mode it joins the bundle being built. Returns false when
  /// something was wrong and a message was shown.
  bool _addFromField() {
    final text = _tidy(_wantController.text);
    if (text.isEmpty) return true;

    final problem = _checkName(text);
    if (problem != null) {
      _showMessage(problem);
      return false;
    }

    if (_mode == _WantMode.single) {
      if (!_canAddEntry([text])) return false;
      setState(() => _wants.add([text]));
    } else {
      final key = normalizeModelKey(text);
      if (_pendingBundle.any((name) => normalizeModelKey(name) == key)) {
        _showMessage('"$text" is already in this bundle.');
        return false;
      }
      if (_pendingBundle.length >= kMaxItemsPerWantBundle) {
        _showMessage('A bundle can hold up to $kMaxItemsPerWantBundle items.');
        return false;
      }
      setState(() => _pendingBundle.add(text));
    }

    _wantController.clear();
    return true;
  }

  /// Saves the bundle being built as one entry. Needs at least two items.
  /// Returns true when nothing is pending or the bundle was saved.
  bool _saveBundle() {
    if (_pendingBundle.isEmpty) return true;

    if (_pendingBundle.length < 2) {
      _showMessage('A bundle needs at least 2 items. Add another, or clear it.');
      return false;
    }
    if (!_canAddEntry(_pendingBundle)) return false;

    setState(() {
      _wants.add(List<String>.of(_pendingBundle));
      _pendingBundle.clear();
    });
    return true;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (_submitting) return;

    // Anything typed or still being built is added first.
    if (!_addFromField() || !_saveBundle()) return;

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
        wantGroups: [for (final entry in _wants) List<String>.of(entry)],
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
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
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
          const SizedBox(height: 28),
          _buildWantsSection(),
          const SizedBox(height: 16),
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
            foregroundColor: AppColors.primary,
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
    final enabled = !_submitting && !full;

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
        const SizedBox(height: 4),
        const Text(
          'Ask for a single item, or a bundle of items you want together.',
          style: TextStyle(color: kOmniMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_WantMode>(
            segments: const [
              ButtonSegment(
                value: _WantMode.single,
                label: Text('Single item'),
                icon: Icon(Icons.sell_outlined, size: 18),
              ),
              ButtonSegment(
                value: _WantMode.bundle,
                label: Text('Bundle'),
                icon: Icon(Icons.layers_rounded, size: 18),
              ),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: _submitting
                ? null
                : (selection) => setState(() => _mode = selection.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: kOmniInk,
              selectedBackgroundColor: AppColors.primary,
              selectedForegroundColor: AppColors.onPrimary,
              side: BorderSide(color: AppColors.primary.withOpacity(0.25)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildComposer(enabled: enabled),
        if (full)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'You have reached the limit of $kMaxWantsPerPost wanted items.',
              style: TextStyle(color: kOmniMuted, fontSize: 12),
            ),
          ),
        const SizedBox(height: 14),
        _buildSavedWants(),
      ],
    );
  }

  /// The input for the current mode, plus the bundle controls in bundle mode.
  Widget _buildComposer({required bool enabled}) {
    final isBundle = _mode == _WantMode.bundle;
    final canSaveBundle = enabled && _pendingBundle.length >= 2;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _wantController,
                  enabled: enabled,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) {
                    _addFromField();
                  },
                  decoration: InputDecoration(
                    hintText: isBundle
                        ? 'Add an item to the bundle'
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
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: isBundle ? 'Add to bundle' : 'Add',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.3),
                ),
                onPressed: enabled
                    ? () {
                  _addFromField();
                }
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          if (isBundle) ...[
            const SizedBox(height: 12),
            if (_pendingBundle.isEmpty)
              const Text(
                'Add at least 2 items. Order does not matter.',
                style: TextStyle(color: kOmniMuted, fontSize: 12),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in _pendingBundle)
                    InputChip(
                      label: Text(name),
                      onDeleted: enabled
                          ? () => setState(() => _pendingBundle.remove(name))
                          : null,
                      deleteIconColor: AppColors.primary,
                      backgroundColor: AppColors.primary.withOpacity(0.08),
                      side: BorderSide.none,
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: enabled && _pendingBundle.isNotEmpty
                        ? () => setState(() => _pendingBundle.clear())
                        : null,
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: canSaveBundle
                        ? () {
                      if (_addFromField()) _saveBundle();
                    }
                        : null,
                    icon: const Icon(Icons.layers_rounded, size: 18),
                    label: Text('Save bundle (${_pendingBundle.length})'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The saved entries. Single items show one name, bundles show all names.
  Widget _buildSavedWants() {
    if (_wants.isEmpty) {
      return const _HintBox(
        text: 'Nothing listed yet. Add what you would like in return, '
            'or turn on outside wants below.',
      );
    }

    return Column(
      children: [
        for (final entry in _wants)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _WantTile(
              names: entry,
              onRemove: _submitting
                  ? null
                  : () => setState(() => _wants.remove(entry)),
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
          decoration: _boxDecoration(),
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
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.onPrimary,
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

  BoxDecoration _boxDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFFD9E0EA)),
  );
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

/// One saved wanted entry. A single item shows one name, a bundle shows
/// every name as a chip, with the item count above them.
class _WantTile extends StatelessWidget {
  const _WantTile({required this.names, required this.onRemove});

  final List<String> names;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final isBundle = names.length > 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isBundle ? Icons.layers_rounded : Icons.sell_outlined,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBundle ? 'Bundle · ${names.length} items' : 'Single item',
                  style: const TextStyle(
                    color: kOmniMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in names)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: kOmniInk,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, color: kOmniMuted),
          ),
        ],
      ),
    );
  }
}