import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/add_item_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/home_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/my_offers_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/user_service.dart';

/// Lets code outside the widget tree (AuthGate) manage the app's routes.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

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
  // If the device is offline or anything else fails, keep the session so
  // the user is not signed out.
  final auth = Supabase.instance.client.auth;
  if (auth.currentSession != null) {
    try {
      await auth.getUser();
    } on AuthRetryableFetchException {
      // Offline or server unreachable: keep the local session.
    } on AuthException {
      await auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Unexpected error: keep the local session rather than crash at startup.
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
      navigatorKey: appNavigatorKey,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeOnlyPageTransitionsBuilder(),
            TargetPlatform.iOS: FadeOnlyPageTransitionsBuilder(),
          },
        ),
      ),
      home: const AuthGate(),
      onGenerateRoute: _onGenerateRoute,
    );
  }
}

/// Google sign-in returns the PKCE code as a query string on the route,
/// e.g. "/?code=660f0f3f-...". Supabase reads the code itself, so the route
/// only needs to show AuthGate.
bool _isAuthCallback(String? name) {
  if (name == null) return false;
  return name.contains('code=') ||
      name.contains('login-callback') ||
      name.contains('access_token=');
}

/// Maps every named route to a screen. Routes whose screens are not built
/// yet get a placeholder, so tapping them never crashes the app.
Route<dynamic> _onGenerateRoute(RouteSettings settings) {
  // Remove this line once the sign-in flow works.
  debugPrint('onGenerateRoute name: ${settings.name}');

  final Widget page;

  if (_isAuthCallback(settings.name)) {
    // Returning from Google sign-in. AuthGate checks the session and
    // shows Home or the sign-in form, and then removes itself.
    page = const AuthGate();
  } else {
    switch (settings.name) {
      case '/add-item':
        page = const AddItemScreen();
        break;
      case '/browse':
        page = const BrowseScreen();
        break;
      case '/inventory':
        page = const InventoryScreen();
        break;
      case '/profile':
        page = const EditProfileScreen();
        break;
      case '/trades':
      // The Trades tab is My Offers (Sent and Received).
        page = const MyOffersScreen();
        break;
      case '/notifications':
        page = const _ComingSoonScreen(title: 'Notifications');
        break;
      case '/make-offer':
      // Offers are made from the post pages, which push MakeOfferScreen
      // directly. This named route is kept only as a placeholder.
        page = const _ComingSoonScreen(title: 'Make an Offer');
        break;
      default:
        page = const _ComingSoonScreen(title: 'Page not found');
    }
  }

  return MaterialPageRoute(
    settings: settings,
    builder: (_) => page,
  );
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

    // If this AuthGate was pushed by the sign-in redirect, remove it so
    // the root AuthGate (which now shows Home) is visible again.
    if (result == true) {
      appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
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

/// Shown for routes whose screens are not built yet.
class _ComingSoonScreen extends StatelessWidget {
  const _ComingSoonScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          '$title is coming soon.',
          style: const TextStyle(color: Colors.grey),
        ),
      ),
    );
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

/// Fades pages in and out without sliding them.
/// Because this does not extend the platform's Cupertino transition,
/// the iOS edge-swipe drag is also disabled.
class FadeOnlyPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeOnlyPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
      ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }
}