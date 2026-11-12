import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/add_item_screen.dart';
import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/user_service.dart';
import 'screens/inventory_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // If the saved login was deleted on the server, clear it now.
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) {
    try {
      await auth.getUser();
    } on AuthException {
      await auth.signOut(scope: SignOutScope.local);
    }
  }

  runApp(const OmniSwapApp());
}

class OmniSwapApp extends StatelessWidget {
  const OmniSwapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OmniSwap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const AuthGate(),
      routes: {
        '/add-item': (_) => const AddItemScreen(),
        '/inventory': (_) => const InventoryScreen(),
      },
    );
  }
}

/// Decides between the sign-in screen and Home.
///
/// Home is shown only when the user is logged in AND has a row in `users`.
/// Otherwise SignInScreen stays on screen, so the Gmail badge and any typed
/// WhatsApp number are not lost during the login round trip.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // null = still checking, true = has profile, false = show sign-in
  bool? _hasProfile;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _checkProfile();
    _authSub = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => _checkProfile());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _checkProfile() async {
    bool result;
    try {
      result = await UserService().hasProfile();
    } catch (_) {
      result = false;
    }
    if (mounted) setState(() => _hasProfile = result);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasProfile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _hasProfile! ? const HomeScreen() : const SignInScreen();
  }
}