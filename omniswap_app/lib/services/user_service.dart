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

    try {
      await _client.from('users').upsert({
        'id': user.id,
        'google_subject': (meta['sub'] ?? user.id) as String,
        'email': email,
        'display_name': displayName,
        'avatar_url': meta['avatar_url'] ?? meta['picture'],
        'whatsapp_number': whatsappNumber,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        // Foreign key failed: the login no longer exists on the server.
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