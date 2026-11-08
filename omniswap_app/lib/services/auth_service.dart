import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart' show supabase;

const _redirect = 'io.supabase.omniswap://login-callback/';

Future<void> signInWithGoogle() async {
  await supabase.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: _redirect,
  );
}

Future<void> signOut() => supabase.auth.signOut();

/// True if the signed-in user still has to enter a WhatsApp number.
Future<bool> needsWhatsapp() async {
  final uid = supabase.auth.currentUser!.id;
  final row = await supabase
      .from('users')
      .select('whatsapp_number')
      .eq('id', uid)
      .single();
  return row['whatsapp_number'] == null;
}

Future<void> saveWhatsapp(String number) async {
  final valid = RegExp(r'^\+[1-9][0-9]{1,14}$').hasMatch(number);
  if (!valid) {
    throw Exception('Use international format, for example +923001234567');
  }
  final uid = supabase.auth.currentUser!.id;
  await supabase.from('users').update({'whatsapp_number': number}).eq('id', uid);
}