import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/item_service.dart';
import 'home_screen.dart'; // kOmniYellow, kOmniInk, kOmniMuted, kOmniBg

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final ItemService _service = ItemService();
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();

  final List<Uint8List> _photos = [];
  ItemCondition? _condition;
  bool _saving = false;

  bool get _canAddPhoto => _photos.length < ItemService.maxPhotos;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------------------
  // Photos
  // ---------------------------------------------------------------------------

  void _openPhotoSheet() {
    if (!_canAddPhoto) {
      _showMessage('You can add up to ${ItemService.maxPhotos} photos.');
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: kOmniInk),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: kOmniInk),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80, // smaller uploads
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return; // user cancelled

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _photos.add(bytes));
    } catch (_) {
      final source_ = source == ImageSource.camera ? 'camera' : 'gallery';
      _showMessage('Could not open the $source_. Check the app permissions.');
    }
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final yearText = _yearController.text.trim();

    if (_photos.isEmpty) {
      _showMessage('Add at least one photo.');
      return;
    }
    if (title.isEmpty) {
      _showMessage('Enter a title.');
      return;
    }
    if (_condition == null) {
      _showMessage('Choose a condition.');
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

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final itemId = await _service.addItemToInventory(
        title: title,
        description: description,
        condition: _condition!,
        manufactureYear: year,
        photos: List.unmodifiable(_photos),
      );
      if (!mounted) return;
      Navigator.pop(context, itemId); // Inventory shows this item in its banner
    } catch (_) {
      _showMessage('Could not save the item. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
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
          'Add Item',
          style: TextStyle(fontWeight: FontWeight.w800, color: kOmniInk),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPhotoSection(),
              const SizedBox(height: 20),
              const _Label('Title'),
              const SizedBox(height: 6),
              TextField(
                controller: _titleController,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                decoration: _inputDecoration(hint: 'e.g. PlayStation 5'),
              ),
              const SizedBox(height: 20),
              const _Label('Condition'),
              const SizedBox(height: 8),
              _buildConditionChips(),
              const SizedBox(height: 20),
              const _Label('Description'),
              const SizedBox(height: 6),
              TextField(
                controller: _descriptionController,
                enabled: !_saving,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: _inputDecoration(hint: 'Add a description'),
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
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: _inputDecoration(hint: 'e.g. 2021'),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
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
                  onPressed: _saving ? null : _save,
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
                    'Add to Inventory',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    final tileCount = _photos.length + (_canAddPhoto ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const _Label('Photos (up to 5)'),
            Text(
              '${_photos.length}/${ItemService.maxPhotos}',
              style: const TextStyle(color: kOmniMuted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tileCount,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == _photos.length) {
                return _AddPhotoTile(onTap: _saving ? null : _openPhotoSheet);
              }
              return _PhotoTile(
                bytes: _photos[index],
                onRemove: _saving ? null : () => _removePhoto(index),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildConditionChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final condition in ItemCondition.values)
          ChoiceChip(
            label: Text(condition.label),
            selected: _condition == condition,
            onSelected: _saving
                ? null
                : (_) => setState(() => _condition = condition),
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
}

// -----------------------------------------------------------------------------
// Small widgets and helpers
// -----------------------------------------------------------------------------

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

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback? onTap;

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

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.bytes, required this.onRemove});

  final Uint8List bytes;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
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

InputDecoration _inputDecoration({required String hint}) => InputDecoration(
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