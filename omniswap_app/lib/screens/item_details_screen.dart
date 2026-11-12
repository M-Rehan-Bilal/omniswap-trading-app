import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_limits.dart';
import '../models/inventory_item.dart';
import '../models/item_condition.dart';
import '../services/item_service.dart';
import '../widgets/item_photo.dart';
import '../widgets/photo_picker.dart';
import 'home_screen.dart'; // kOmniYellow, kOmniInk, kOmniMuted, kOmniBg

/// One photo on the details screen. An existing photo has a storage path.
/// A photo picked in this session has only bytes until save uploads it.
class _PhotoDraft {
  _PhotoDraft.existing({required this.path, required this.url}) : bytes = null;

  _PhotoDraft.added(this.bytes)
      : path = null,
        url = null;

  final String? path;
  final String? url;
  final Uint8List? bytes;

  bool get isNew => bytes != null;
}

class ItemDetailsScreen extends StatefulWidget {
  const ItemDetailsScreen({super.key, required this.item});

  final InventoryItem item;

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  final ItemService _service = ItemService();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _yearController;
  late ItemCondition _condition;
  late List<_PhotoDraft> _photos;

  int _photoIndex = 0;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _yearController = TextEditingController();
    _fillFromItem();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  void _fillFromItem() {
    final item = widget.item;
    _titleController.text = item.title;
    _descriptionController.text = item.description;
    _yearController.text = item.manufactureYear?.toString() ?? '';
    _condition = item.condition;
    _photos = [
      for (final path in item.photoPaths)
        _PhotoDraft.existing(path: path, url: item.urlByPath[path]),
    ];
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _startEditing() => setState(() => _editing = true);

  void _cancelEditing() {
    setState(() {
      _fillFromItem();
      _photoIndex = 0;
      _editing = false;
    });
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= kMaxPhotosPerItem) {
      _showMessage('You can add up to $kMaxPhotosPerItem photos.');
      return;
    }
    final bytes = await pickPhotoBytes(context);
    if (bytes == null || !mounted) return;
    setState(() => _photos.add(_PhotoDraft.added(bytes)));
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final yearText = _yearController.text.trim();

    if (_photos.isEmpty) {
      _showMessage('Keep at least one photo.');
      return;
    }
    if (title.isEmpty) {
      _showMessage('Enter a title.');
      return;
    }

    int? year;
    if (yearText.isNotEmpty) {
      year = int.tryParse(yearText);
      if (year == null || year < 1900 || year > 2100) {
        _showMessage('Enter a manufacture year between 1900 and 2100.');
        return;
      }
    }

    final keptPaths = [for (final photo in _photos) if (!photo.isNew) photo.path!];
    final newPhotos = [for (final photo in _photos) if (photo.isNew) photo.bytes!];
    final removedPaths = [
      for (final path in widget.item.photoPaths)
        if (!keptPaths.contains(path)) path,
    ];

    setState(() => _saving = true);
    try {
      // Details first. Saving them again on a retry is harmless.
      await _service.updateItem(
        itemId: widget.item.id,
        title: title,
        description: _descriptionController.text.trim(),
        condition: _condition,
        manufactureYear: year,
      );

      if (removedPaths.isNotEmpty || newPhotos.isNotEmpty) {
        await _service.updateItemPhotos(
          itemId: widget.item.id,
          keptPaths: keptPaths,
          removedPaths: removedPaths,
          newPhotos: newPhotos,
        );
      }

      if (!mounted) return;
      Navigator.pop(context, true); // Inventory reloads when it sees true
    } catch (_) {
      _showMessage('Could not save changes. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _editing && !_saving;

    return Scaffold(
      backgroundColor: kOmniBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: kOmniInk),
        title: Text(
          _editing ? 'Edit Item' : 'Item Details',
          style: const TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
        actions: [
          if (!_editing)
            TextButton(
              onPressed: _startEditing,
              child: const Text(
                'Edit',
                style: TextStyle(color: kOmniInk, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPhotos(canEdit),
              const SizedBox(height: 20),
              const _Label('Title'),
              const SizedBox(height: 6),
              TextField(
                controller: _titleController,
                enabled: canEdit,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration(hint: 'Item title'),
              ),
              const SizedBox(height: 20),
              const _Label('Condition'),
              const SizedBox(height: 8),
              _buildConditionChips(canEdit),
              const SizedBox(height: 20),
              const _Label('Description'),
              const SizedBox(height: 6),
              TextField(
                controller: _descriptionController,
                enabled: canEdit,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration(hint: 'Add a description'),
              ),
              const SizedBox(height: 20),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Label('Manufacture year'),
                  Text(
                    'Optional',
                    style: TextStyle(color: kOmniMuted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _yearController,
                enabled: canEdit,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: _decoration(hint: 'e.g. 2021'),
              ),
              if (_editing) ...[
                const SizedBox(height: 32),
                _buildActionButtons(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotos(bool canEdit) {
    return _editing ? _buildPhotoEditor(canEdit) : _buildCarousel();
  }

  /// View mode: a large swipeable carousel.
  Widget _buildCarousel() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 260,
            width: double.infinity,
            child: _photos.isEmpty
                ? const ItemPhoto(url: null, iconSize: 56)
                : PageView.builder(
              itemCount: _photos.length,
              onPageChanged: (index) =>
                  setState(() => _photoIndex = index),
              itemBuilder: (_, index) =>
                  ItemPhoto(url: _photos[index].url, iconSize: 56),
            ),
          ),
        ),
        if (_photos.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_photoIndex + 1}/${_photos.length}',
              style: const TextStyle(color: kOmniMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }

  /// Edit mode: a strip with a remove button on each photo and an add tile.
  Widget _buildPhotoEditor(bool canEdit) {
    final canAdd = canEdit && _photos.length < kMaxPhotosPerItem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _Label('Photos'),
            Text(
              '${_photos.length}/$kMaxPhotosPerItem',
              style: const TextStyle(color: kOmniMuted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 6, right: 6),
            itemCount: _photos.length + (canAdd ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == _photos.length) {
                return _AddPhotoTile(onTap: _addPhoto);
              }
              return _EditPhotoTile(
                draft: _photos[index],
                onRemove: canEdit ? () => _removePhoto(index) : null,
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'The first photo is the cover.',
          style: TextStyle(color: kOmniMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildConditionChips(bool canEdit) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final condition in ItemCondition.values)
          ChoiceChip(
            label: Text(condition.label),
            selected: _condition == condition,
            onSelected: canEdit
                ? (_) => setState(() => _condition = condition)
                : null,
            showCheckmark: false,
            selectedColor: kOmniYellow,
            backgroundColor: Colors.white,
            side: BorderSide(
              color: _condition == condition
                  ? kOmniYellow
                  : const Color(0xFFD9E0EA),
            ),
            labelStyle: TextStyle(
              color: kOmniInk,
              fontWeight: _condition == condition
                  ? FontWeight.w700
                  : FontWeight.w400,
            ),
          ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : _cancelEditing,
            style: OutlinedButton.styleFrom(
              foregroundColor: kOmniInk,
              side: const BorderSide(color: Color(0xFFD9E0EA)),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: kOmniYellow,
              foregroundColor: kOmniInk,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _saving
                ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: kOmniInk,
              ),
            )
                : const Text(
              'Save changes',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _decoration({required String hint}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD9E0EA)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD9E0EA)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kOmniInk, width: 1.2),
    ),
  );
}

class _EditPhotoTile extends StatelessWidget {
  const _EditPhotoTile({required this.draft, required this.onRemove});

  final _PhotoDraft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final image = draft.isNew
        ? Image.memory(draft.bytes!, fit: BoxFit.cover)
        : ItemPhoto(url: draft.url, iconSize: 20);

    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: image,
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: const CircleAvatar(
                radius: 11,
                backgroundColor: kOmniInk,
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFB8C4D6), width: 1.5),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: kOmniInk),
            SizedBox(height: 4),
            Text(
              'Add photo',
              style: TextStyle(fontSize: 11, color: kOmniMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

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