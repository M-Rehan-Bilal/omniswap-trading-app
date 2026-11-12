import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_limits.dart';
import '../models/inventory_item.dart';
import '../models/item_condition.dart';

// Re-exported so screens that import this file can still use ItemCondition.
export '../models/item_condition.dart';

class ItemService {
  ItemService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const int maxPhotos = kMaxPhotosPerItem;
  static const String photoBucket = 'item-images';
  static const int signedUrlSeconds = 60 * 60;

  final SupabaseClient _client;

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No signed-in user.');
    }
    return userId;
  }

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
    final userId = _requireUserId();
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

  /// The signed-in user's items that are available, newest first.
  /// Items that are in a trade or already traded are hidden.
  Future<List<InventoryItem>> fetchMyInventory() async {
    final userId = _requireUserId();

    final response = await _client
        .from('items')
        .select(
      'id, title, description, item_condition, manufacture_year, '
          'item_images(storage_key, position)',
    )
        .eq('owner_id', userId)
        .eq('status', 'available')
        .order('created_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(response as List);
    final allPaths = [
      for (final row in rows) ...InventoryItem.photoPathsFrom(row),
    ];
    final urlByPath = await _signPaths(allPaths);

    return [for (final row in rows) InventoryItem.fromRow(row, urlByPath)];
  }

  /// Saves edits to the title, description, condition and year.
  /// The title is also written to model_name, since they are the same value.
  Future<void> updateItem({
    required String itemId,
    required String title,
    required String description,
    required ItemCondition condition,
    int? manufactureYear,
  }) async {
    await _client.from('items').update({
      'title': title,
      'model_name': title,
      'description': description,
      'item_condition': condition.dbValue,
      'manufacture_year': manufactureYear,
    }).eq('id', itemId);
  }

  /// Changes an item's photos.
  /// [keptPaths] are existing photos, in the order they should appear.
  /// [newPhotos] are added after them. [removedPaths] are deleted from the
  /// database and from storage.
  Future<void> updateItemPhotos({
    required String itemId,
    required List<String> keptPaths,
    required List<String> removedPaths,
    required List<Uint8List> newPhotos,
  }) async {
    final userId = _requireUserId();
    final total = keptPaths.length + newPhotos.length;
    if (total < 1 || total > maxPhotos) {
      throw ArgumentError('An item needs between 1 and $maxPhotos photos.');
    }

    final storage = _client.storage.from(photoBucket);
    final batch = DateTime.now().microsecondsSinceEpoch.toString();
    final uploadedPaths = <String>[];

    try {
      // 1. Upload the new photos first. If this fails, the database is unchanged.
      for (var i = 0; i < newPhotos.length; i++) {
        final path = '$userId/$batch/${i + 1}.jpg';
        await storage.uploadBinary(
          path,
          newPhotos[i],
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
        uploadedPaths.add(path);
      }

      // 2. Delete the rows for removed photos.
      for (final path in removedPaths) {
        await _client
            .from('item_images')
            .delete()
            .eq('item_id', itemId)
            .eq('storage_key', path);
      }

      // 3. Renumber the kept photos 1..n. Each kept photo's old position is at
      //    least its new position, and they are processed in order, so no
      //    position collides with one that has not moved yet.
      for (var i = 0; i < keptPaths.length; i++) {
        await _client
            .from('item_images')
            .update({'position': i + 1})
            .eq('item_id', itemId)
            .eq('storage_key', keptPaths[i]);
      }

      // 4. Add the new photos after the kept ones.
      if (uploadedPaths.isNotEmpty) {
        await _client.from('item_images').insert([
          for (var i = 0; i < uploadedPaths.length; i++)
            {
              'item_id': itemId,
              'position': keptPaths.length + i + 1,
              'storage_key': uploadedPaths[i],
            },
        ]);
      }
    } catch (_) {
      // Remove only the uploads from this call. The database may be partly changed.
      if (uploadedPaths.isNotEmpty) {
        try {
          await storage.remove(uploadedPaths);
        } catch (_) {}
      }
      rethrow;
    }

    // 5. Delete removed files from storage once the database has changed.
    //    If this fails, the files are only orphaned, not lost.
    if (removedPaths.isNotEmpty) {
      try {
        await storage.remove(removedPaths);
      } catch (_) {}
    }
  }

  /// Creates a signed URL for each private photo path.
  /// Returns a map of path to URL. Paths that fail are left out.
  Future<Map<String, String>> _signPaths(List<String> paths) async {
    if (paths.isEmpty) return {};

    final storage = _client.storage.from(photoBucket);
    final urls = <String, String>{};

    await Future.wait(paths.map((path) async {
      try {
        urls[path] = await storage.createSignedUrl(path, signedUrlSeconds);
      } catch (_) {
        // Skip this photo. The card will show a placeholder.
      }
    }));

    return urls;
  }
}