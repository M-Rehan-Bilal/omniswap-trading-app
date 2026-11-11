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

  /// Creates or updates the logged-in user's row with their WhatsApp number.
  /// [whatsappNumber] must be in international format, e.g. +923001234567.
  Future<void> saveProfile({required String whatsappNumber}) async {
    final User user;
    try {
      // Confirms with the server that this login still exists.
      final response = await _client.auth.getUser();
      user = response.user!;
    } on AuthException {
      await _clearStaleSession();
      throw SessionExpiredException();
    }

    final meta = user.userMetadata ?? {};
    final email = user.email!;
    final displayName =
    (meta['full_name'] ?? meta['name'] ?? email.split('@').first) as String;
    final avatarUrl = meta['avatar_url'] ?? meta['picture'];

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
        });
      } else {
        // Row exists: update only the columns the policies allow.
        await _client.from('users').update({
          'display_name': displayName,
          'avatar_url': avatarUrl,
          'whatsapp_number': whatsappNumber,
        }).eq('id', user.id);
      }
    } on PostgrestException catch (e) {
      debugPrint('Postgrest error: code=${e.code}, message=${e.message}, '
          'details=${e.details}, hint=${e.hint}');

      if (e.code == '23503') {
        await _clearStaleSession();
        throw SessionExpiredException();
      }
      if (e.code == '23505') {
        throw Exception('This WhatsApp number is already registered.');
      }
      throw Exception('Could not save your profile. Please try again.');
    }
  }

  /// Signs out on this device only, without contacting the server.
  Future<void> _clearStaleSession() async {
    await _client.auth.signOut(scope: SignOutScope.local);
  }
}