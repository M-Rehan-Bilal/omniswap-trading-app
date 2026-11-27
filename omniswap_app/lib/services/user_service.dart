import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionExpiredException implements Exception {
  @override
  String toString() => 'Your Google session has expired. Tap Add Gmail again.';
}

class UserService {
  final SupabaseClient _client = Supabase.instance.client;

  /// True if the logged-in user already has a row in `users`.
  Future<bool> hasProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    final row = await _client
        .from('users')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();
    return row != null;
  }

  /// Creates or updates the logged-in user's profile.
  /// [whatsappNumber] must be in international format, e.g. +923001234567.
  /// [country], [city] and [area] are required, and each must be 1 to 100 characters.
  Future<void> saveProfile({
    required String whatsappNumber,
    required String country,
    required String city,
    required String area,
  }) async {
    final user = await _confirmedUser();

    final meta = user.userMetadata ?? {};
    final email = user.email!;
    final fullName = (meta['full_name'] ?? meta['name'] ?? '').toString().trim();
    final displayName = fullName.isNotEmpty ? fullName : email.split('@').first;
    final avatarUrl = meta['avatar_url'] ?? meta['picture'];

    final location = {
      'country': country.trim(),
      'city': city.trim(),
      'area': area.trim(),
    };

    try {
      final existing = await _client
          .from('users')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (existing == null) {
        // First time: insert the full row.
        await _client.from('users').insert({
          'id': user.id,
          'google_subject': (meta['sub'] ?? user.id) as String,
          'email': email,
          'display_name': displayName,
          'avatar_url': avatarUrl,
          'whatsapp_number': whatsappNumber,
          ...location,
        });
      } else {
        // Row exists: update only the columns the policies allow.
        await _client.from('users').update({
          'whatsapp_number': whatsappNumber,
          ...location,
        }).eq('id', user.id);
      }
    } on PostgrestException catch (e) {
      debugPrint('Postgrest error: code=${e.code}, message=${e.message}, '
          'details=${e.details}, hint=${e.hint}');

      if (e.code == '23503') {
        // The user row points to a login that no longer exists.
        await _clearStaleSession();
        throw SessionExpiredException();
      }
      if (e.code == '23505') {
        throw Exception('This WhatsApp number is already registered.');
      }
      if (e.code == '23514') {
        throw Exception('Please check your country, city and area.');
      }
      throw Exception('Could not save your profile. Please try again.');
    }
  }

  /// Confirms with the server that the current login still exists.
  Future<User> _confirmedUser() async {
    try {
      final response = await _client.auth.getUser();
      final user = response.user;
      if (user == null) {
        await _clearStaleSession();
        throw SessionExpiredException();
      }
      return user;
    } on AuthRetryableFetchException {
      // Offline: keep the session and let the user retry.
      rethrow;
    } on AuthException {
      await _clearStaleSession();
      throw SessionExpiredException();
    }
  }

  /// Signs out on this device only, without contacting the server.
  Future<void> _clearStaleSession() async {
    await _client.auth.signOut(scope: SignOutScope.local);
  }
}