import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  supabase.auth.onAuthStateChange.listen((data) {
    debugPrint('Auth event: ${data.event}');
  });

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

// ... rest of main.dart unchanged (MyApp, LoginScreen, HomeScreen)

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, _) {
          final signedIn = supabase.auth.currentSession != null;
          return signedIn ? const HomeScreen() : const LoginScreen();
        },
      ),
    );
  }
}

// Replace these with your real screens
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton.icon(
          onPressed: signInWithGoogle,
          icon: const Icon(Icons.login),
          label: const Text('Continue with Google'),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Signed in')));
  }
}