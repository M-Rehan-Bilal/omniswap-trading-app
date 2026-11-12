import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Matches the item_condition enum in the database.
enum ItemCondition {
  newItem('new', 'New'),
  likeNew('like_new', 'Like New'),
  good('good', 'Good'),
  fair('fair', 'Fair'),
  poor('poor', 'Poor');

  const ItemCondition(this.dbValue, this.label);

  final String dbValue;
  final String label;
}

class ItemService {
  ItemService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const int maxPhotos = 5;
  static const String photoBucket = 'item-images';

  final SupabaseClient _client;

  /// Adds an item to the signed-in user's inventory. It is not posted yet.
  /// Photos are uploaded first, then the item row, then the image rows.
  /// Returns the new item id.
  Future<String> addItemToInventory({
    required String title,
    required String description,
    required ItemCondition condition,
    required List<Uint8List> photos,
    int? manufactureYear,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No signed-in user.');
    }
    if (photos.isEmpty || photos.length > maxPhotos) {
      throw ArgumentError('Add between 1 and $maxPhotos photos.');
    }

    final storage = _client.storage.from(photoBucket);
    final batch = DateTime.now().microsecondsSinceEpoch.toString();
    final uploadedPaths = <String>[];

    try {
      // 1. Upload photos. The first folder must be the user's id (see storage policies).
      for (var i = 0; i < photos.length; i++) {
        final path = '$userId/$batch/${i + 1}.jpg';
        await storage.uploadBinary(
          path,
          photos[i],
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
        uploadedPaths.add(path);
      }

      // 2. Create the item. Title and model name hold the same value.
      final item = await _client
          .from('items')
          .insert({
        'owner_id': userId,
        'title': title,
        'model_name': title,
        'description': description,
        'item_condition': condition.dbValue,
        'manufacture_year': manufactureYear,
      })
          .select('id')
          .single();
      final itemId = item['id'] as String;

      // 3. Link the photos to the item, in order.
      await _client.from('item_images').insert([
        for (var i = 0; i < uploadedPaths.length; i++)
          {
            'item_id': itemId,
            'position': i + 1,
            'storage_key': uploadedPaths[i],
          },
      ]);

      return itemId;
    } catch (_) {
      // Remove any photos already uploaded so storage has no orphans.
      if (uploadedPaths.isNotEmpty) {
        try {
          await storage.remove(uploadedPaths);
        } catch (_) {}
      }
      rethrow;
    }
  }
}