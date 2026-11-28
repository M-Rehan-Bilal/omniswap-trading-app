import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../models/post_details.dart';
import '../services/item_service.dart';
import '../services/trade_service.dart' show normalizeModelKey;
import '../theme/omni_colors.dart';
import '../widgets/detail_widgets.dart' show SectionLabel;
import '../widgets/item_photo.dart';
import 'review_offer_screen.dart';

/// Step 1 of making an offer: pick the items from your inventory that you
/// want to give for [post]. Offers always cover the whole post.
///
/// If the post owner is not open to other offers, EVERY offered item must
/// match something on their "wants" list. Anything else disables Continue.
class MakeOfferScreen extends StatefulWidget {
  const MakeOfferScreen({super.key, required this.post, this.service});

  /// The post being offered for.
  final PostDetails post;

  /// Optional, so tests can inject a fake service.
  final ItemService? service;

  @override
  State<MakeOfferScreen> createState() => _MakeOfferScreenState();
}

class _MakeOfferScreenState extends State<MakeOfferScreen> {
  late final ItemService _service;

  List<InventoryItem> _inventory = [];

  /// Chosen item ids, in the order they were ticked.
  final List<String> _selectedIds = [];

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ItemService();
    _load();
  }

  // ---------------------------------------------------------------------------
  // Offer rules
  // ---------------------------------------------------------------------------

  /// Wanted model keys, e.g. "iPhone 15" -> "iphone15".
  late final Set<String> _wantKeys = {
    for (final want in widget.post.wants) normalizeModelKey(want),
  };

  bool get _openToOthers => widget.post.acceptsOutsideWants;

  bool _isWanted(InventoryItem item) =>
      _wantKeys.contains(normalizeModelKey(item.title));

  /// Wanted keys that the current selection satisfies.
  Set<String> get _matchedKeys => {
    for (final item in _selectedItems)
      if (_isWanted(item)) normalizeModelKey(item.title),
  };

  /// Selected items that are NOT on the owner's wants list.
  List<InventoryItem> get _unwantedSelected => [
    for (final item in _selectedItems)
      if (!_isWanted(item)) item,
  ];

  /// True if this selected item breaks the owner's "only these items" rule.
  bool _isRejected(InventoryItem item) =>
      !_openToOthers && _selectedIds.contains(item.id) && !_isWanted(item);

  /// Rules:
  ///  - Something must be selected.
  ///  - If the owner is open to other offers, anything goes.
  ///  - Otherwise every selected item must be on the wants list.
  bool get _isAcceptable {
    if (_selectedIds.isEmpty) return false;
    if (_openToOthers) return true;
    return _unwantedSelected.isEmpty;
  }

  /// Only shown after the user has picked something.
  bool get _showRejection => _selectedIds.isNotEmpty && !_isAcceptable;

  String? get _errorText {
    if (!_showRejection) return null;
    final owner = widget.post.owner.name;
    final names = _unwantedSelected.map((i) => i.title).join(', ');
    return '$owner only accepts the items they listed. '
        'Remove $names to continue.';
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchMyInventory();
      if (!mounted) return;
      final offerable = {
        for (final item in items)
          if (!item.isPosted) item.id,
      };
      setState(() {
        _inventory = items;
        // Drop selections that can no longer be offered.
        _selectedIds.removeWhere((id) => !offerable.contains(id));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your inventory.';
        _loading = false;
      });
    }
  }

  void _toggle(InventoryItem item) {
    if (item.isPosted) return;
    setState(() {
      if (!_selectedIds.remove(item.id)) _selectedIds.add(item.id);
    });
  }

  List<InventoryItem> get _selectedItems {
    final byId = {for (final item in _inventory) item.id: item};
    return [
      for (final id in _selectedIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// Opens the inventory so the user can add an item, then reloads.
  Future<void> _openInventory() async {
    await Navigator.pushNamed(context, '/inventory');
    if (mounted) _load();
  }

  void _continue() {
    final items = _selectedItems;
    if (items.isEmpty || !_isAcceptable) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewOfferScreen(
          post: widget.post,
          offeredItems: items,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kOmniBg,
      appBar: AppBar(
        backgroundColor: kOmniSurface,
        elevation: 0,
        iconTheme: const IconThemeData(color: kOmniInk),
        title: const Text(
          'Make an Offer',
          style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _ContinueBar(
        enabled: _isAcceptable,
        errorText: _errorText,
        onPressed: _continue,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _CenteredMessage(
        text: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _OfferingForCard(post: widget.post),
          const SizedBox(height: 16),
          _WantsCard(
            wants: widget.post.wants,
            openToOthers: _openToOthers,
            matchedKeys: _matchedKeys,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Select from Inventory',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kOmniInk,
                  ),
                ),
              ),
              Text(
                '${_selectedIds.length} selected',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kOmniBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_inventory.isEmpty)
            const _EmptyInventory()
          else
            for (final item in _inventory)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _InventoryTile(
                  item: item,
                  selected: _selectedIds.contains(item.id),
                  wanted: _isWanted(item),
                  rejected: _isRejected(item),
                  onTap: () => _toggle(item),
                ),
              ),
          const SizedBox(height: 2),
          OutlinedButton.icon(
            onPressed: _openInventory,
            icon: const Icon(Icons.add, size: 18),
            label: const Text(
              'Add more item',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: kOmniInk,
              backgroundColor: kOmniSurface,
              side: const BorderSide(color: kOmniBorder),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Widgets
// -----------------------------------------------------------------------------

/// Everything the post is offering, one row per item.
class _OfferingForCard extends StatelessWidget {
  const _OfferingForCard({required this.post});

  final PostDetails post;

  @override
  Widget build(BuildContext context) {
    final count = post.items.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kOmniSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOmniBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Offering for',
                  style: TextStyle(color: kOmniMuted, fontSize: 12),
                ),
              ),
              Text(
                '$count ${count == 1 ? 'item' : 'items'}',
                style: const TextStyle(color: kOmniMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _OfferedItemRow(item: post.items[i]),
          ],
        ],
      ),
    );
  }
}

class _OfferedItemRow extends StatelessWidget {
  const _OfferedItemRow({required this.item});

  final PostDetailItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
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
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
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
      ],
    );
  }
}

/// What the owner wants in return, and whether other offers are welcome.
/// Wanted items that the current selection satisfies are highlighted.
class _WantsCard extends StatelessWidget {
  const _WantsCard({
    required this.wants,
    required this.openToOthers,
    required this.matchedKeys,
  });

  final List<String> wants;
  final bool openToOthers;
  final Set<String> matchedKeys;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kOmniSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOmniBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('WANTS IN RETURN'),
          const SizedBox(height: 8),
          if (wants.isEmpty)
            Text(
              openToOthers ? 'Open to any item' : 'No wants listed',
              style: const TextStyle(color: kOmniMuted, fontSize: 13),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final want in wants)
                  _WantChip(
                    label: want,
                    matched: matchedKeys.contains(normalizeModelKey(want)),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: kOmniMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  openToOthers
                      ? 'Also open to other offers'
                      : 'Only accepting the items listed above',
                  style: const TextStyle(color: kOmniMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WantChip extends StatelessWidget {
  const _WantChip({required this.label, required this.matched});

  final String label;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: matched ? kOmniSelectedBg : kOmniSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: matched ? kOmniBlue : kOmniBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (matched) ...[
            const Icon(Icons.check, size: 14, color: kOmniBlue),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(color: kOmniInk, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// One inventory item. Selected items get a blue border and tinted fill.
/// A selected item the owner does not want gets a red border and a
/// "Not wanted" tag. Items already in a post are greyed out.
class _InventoryTile extends StatelessWidget {
  const _InventoryTile({
    required this.item,
    required this.selected,
    required this.wanted,
    required this.rejected,
    required this.onTap,
  });

  final InventoryItem item;
  final bool selected;

  /// True if the post owner listed this item as a want.
  final bool wanted;

  /// True if this item is selected but the owner does not accept it.
  final bool rejected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = !item.isPosted;

    final Color fill = rejected
        ? kOmniErrorBg
        : selected
        ? kOmniSelectedBg
        : kOmniSurface;
    final Color border = rejected
        ? kOmniError
        : selected
        ? kOmniBlue
        : kOmniBorder;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: fill,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: enabled ? (_) => onTap() : null,
                  activeColor: rejected ? kOmniError : kOmniBlue,
                  checkColor: kOmniSurface,
                  side: const BorderSide(color: kOmniMuted, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                SizedBox(
                  width: 72,
                  height: 72,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ItemPhoto(url: item.coverUrl, iconSize: 28),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kOmniInk,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              enabled
                                  ? item.condition.label
                                  : 'Already in a post',
                              style: const TextStyle(
                                color: kOmniMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (wanted && enabled) ...[
                            const SizedBox(width: 8),
                            _Tag(label: 'Wanted', color: kOmniYellow),
                          ],
                          if (rejected) ...[
                            const SizedBox(width: 8),
                            _Tag(label: 'Not wanted', color: kOmniError),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final onDark = color == kOmniError;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: onDark ? Colors.white : kOmniInk,
        ),
      ),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  const _EmptyInventory();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kOmniSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kOmniBorder),
      ),
      child: const Text(
        'Your inventory is empty. Add an item to make an offer.',
        textAlign: TextAlign.center,
        style: TextStyle(color: kOmniMuted, fontSize: 13),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: kOmniMuted)),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

/// The yellow Continue button pinned to the bottom. When the owner would
/// reject the current selection, the reason is shown just above it and the
/// button is disabled.
class _ContinueBar extends StatelessWidget {
  const _ContinueBar({
    required this.enabled,
    required this.onPressed,
    this.errorText,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final error = errorText;

    return Container(
      color: kOmniSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kOmniErrorBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kOmniError),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: kOmniError,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error,
                          style: const TextStyle(
                            color: kOmniInk,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kOmniYellow,
                    foregroundColor: kOmniInk,
                    disabledBackgroundColor: kOmniYellow.withOpacity(0.45),
                    disabledForegroundColor: kOmniInk.withOpacity(0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: enabled ? onPressed : null,
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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