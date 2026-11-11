import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.omniswap://login-callback/',
      queryParams: {'prompt': 'select_account'},
    );
  }

  Future<void> signOut() => _client.auth.signOut();
}