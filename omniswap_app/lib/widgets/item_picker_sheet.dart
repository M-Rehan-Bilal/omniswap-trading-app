import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../screens/home_screen.dart'; // kOmniYellow, kOmniInk, kOmniMuted
import 'item_photo.dart';

/// Lets the user pick items from their inventory for a post.
/// Returns the chosen item ids in order, or null if the sheet is dismissed.
class ItemPickerSheet extends StatefulWidget {
  const ItemPickerSheet({
    super.key,
    required this.items,
    required this.initialSelected,
    required this.maxItems,
  });

  final List<InventoryItem> items;
  final List<String> initialSelected;
  final int maxItems;

  @override
  State<ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<ItemPickerSheet> {
  late final List<String> _selected = List.of(widget.initialSelected);

  bool get _limitReached => _selected.length >= widget.maxItems;

  void _toggle(InventoryItem item) {
    // Deselecting is always allowed, even for items that are now posted.
    if (_selected.contains(item.id)) {
      setState(() => _selected.remove(item.id));
      return;
    }
    if (item.isPosted || _limitReached) return;
    setState(() => _selected.add(item.id));
  }

  String get _helperText {
    if (_limitReached) {
      return 'A post holds up to ${widget.maxItems} items. '
          'Deselect one to choose another.';
    }
    return 'Items already in another post are greyed out. '
        'Remove that post to free them.';
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.75;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose items',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: kOmniInk,
                      ),
                    ),
                  ),
                  Text(
                    '${_selected.length}/${widget.maxItems} selected',
                    style: const TextStyle(color: kOmniMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                _helperText,
                style: const TextStyle(color: kOmniMuted, fontSize: 12),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.items.isEmpty
                  ? const Center(
                child: Text(
                  'Your inventory is empty. Add an item first.',
                  style: TextStyle(color: kOmniMuted),
                ),
              )
                  : ListView.builder(
                itemCount: widget.items.length,
                itemBuilder: (_, index) =>
                    _buildRow(widget.items[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kOmniYellow,
                    foregroundColor: kOmniInk,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () =>
                      Navigator.pop(context, List<String>.of(_selected)),
                  child: Text(
                    _selected.isEmpty ? 'Done' : 'Done (${_selected.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(InventoryItem item) {
    final posted = item.isPosted;
    final selected = _selected.contains(item.id);
    // A selected item stays tappable so it can be deselected.
    final enabled = selected || (!posted && !_limitReached);

    return ListTile(
      enabled: enabled,
      onTap: enabled ? () => _toggle(item) : null,
      leading: SizedBox(
        width: 48,
        height: 48,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ItemPhoto(url: item.coverUrl, iconSize: 20),
        ),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, color: kOmniInk),
      ),
      subtitle: Text(
        posted ? 'Already in a post' : item.condition.label,
        style: const TextStyle(color: kOmniMuted, fontSize: 12),
      ),
      trailing: Checkbox(
        value: selected,
        onChanged: enabled ? (_) => _toggle(item) : null,
        activeColor: kOmniInk,
      ),
    );
  }
}