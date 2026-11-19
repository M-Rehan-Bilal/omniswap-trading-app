import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

class ProfileService {
  ProfileService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const String avatarBucket = 'item-images';

  final SupabaseClient _client;

  String get _currentUserId {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Not signed in.');
    }
    return user.id;
  }

  Future<UserProfile> fetchMyProfile() async {
    final row = await _client
        .from('users')
        .select()
        .eq('id', _currentUserId)
        .maybeSingle();

    if (row == null) {
      throw Exception('Profile not found.');
    }
    return UserProfile.fromJson(row);
  }

  /// Only the columns granted to `authenticated` can be sent here.
  Future<UserProfile> updateMyProfile({
    required String displayName,
    required String whatsappNumber,
    required String country,
    required String city,
    required String area,
  }) async {
    final row = await _client
        .from('users')
        .update({
      'display_name': displayName,
      'whatsapp_number': whatsappNumber,
      'country': country,
      'city': city,
      'area': area,
    })
        .eq('id', _currentUserId)
        .select()
        .single();

    return UserProfile.fromJson(row);
  }

  /// Uploads a JPEG avatar, replaces the previous one, and saves the URL.
  /// Returns the updated profile.
  Future<UserProfile> uploadAvatar(Uint8List jpegBytes) async {
    final userId = _currentUserId;
    final path = '$userId/avatar.jpg';
    final storage = _client.storage.from(avatarBucket);

    // upsert: true overwrites the existing avatar at the same path.
    await storage.uploadBinary(
      path,
      jpegBytes,
      fileOptions: const FileOptions(
        contentType: 'image/jpeg',
        upsert: true,
      ),
    );

    // The timestamp busts image caches so the new photo shows right away.
    final url =
        '${storage.getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';

    final row = await _client
        .from('users')
        .update({'avatar_url': url})
        .eq('id', userId)
        .select()
        .single();

    return UserProfile.fromJson(row);
  }
}