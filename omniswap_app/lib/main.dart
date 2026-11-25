import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/add_item_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/user_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final url = dotenv.env['SUPABASE_URL'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
  if (url == null || url.isEmpty || anonKey == null || anonKey.isEmpty) {
    throw StateError('SUPABASE_URL and SUPABASE_ANON_KEY must be set in .env');
  }

  await Supabase.initialize(url: url, anonKey: anonKey);

  // Clear the saved login only if the server says it is no longer valid.
  // If the device is offline, keep the session so the user is not signed out.
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) {
    try {
      await auth.getUser();
    } on AuthRetryableFetchException {
      // Offline or server unreachable: keep the local session.
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
        '/profile': (_) => const EditProfileScreen(),
      },
    );
  }
}

/// Decides between the sign-in screen and Home.
///
/// Home is shown only when the user is signed in AND has a row in `users`.
/// Screens are swapped here instead of pushed, so this widget stays alive
/// and keeps listening for auth changes (such as sign-out).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final UserService _users = UserService();

  /// null = not known yet, true = profile exists, false = show sign-in.
  bool? _hasProfile;

  /// True when the first check failed and nothing is known yet.
  bool _checkFailed = false;

  /// Lets a late, older check be ignored.
  int _checkCount = 0;

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
    final check = ++_checkCount;
    bool? result;
    try {
      result = await _users.hasProfile();
    } catch (_) {
      result = null;
    }
    if (!mounted || check != _checkCount) return;

    setState(() {
      if (result == null) {
        // Keep the last known answer. Show a retry only if there is none.
        _checkFailed = _hasProfile == null;
      } else {
        _hasProfile = result;
        _checkFailed = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasProfile = _hasProfile;

    if (hasProfile == null) {
      if (_checkFailed) {
        return _CheckFailed(
          onRetry: () {
            setState(() => _checkFailed = false);
            _checkProfile();
          },
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (hasProfile) return const HomeScreen();
    return SignInScreen(onProfileSaved: _checkProfile);
  }
}

class _CheckFailed extends StatelessWidget {
  const _CheckFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Could not check your account. Check your connection.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}