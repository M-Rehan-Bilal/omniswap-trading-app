import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/user_service.dart';
import 'home_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with WidgetsBindingObserver {
  final _numberController = TextEditingController();
  final _auth = AuthService();
  final _users = UserService();
  bool _loading = false;

  // The Google account shown in the badge. Stored in state so it survives
  // rebuilds and is refreshed explicitly, instead of relying on a rebuild.
  User? _user;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _user = _auth.currentUser;

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      debugPrint('Auth event: ${data.event}, '
          'session user: ${data.session?.user.email}');
      _syncUser(data.session?.user);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The Google login happens in the browser. When the app comes back to
    // the foreground, check again for a signed-in user.
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed, current user: ${_auth.currentUser?.email}');
      _syncUser();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _numberController.dispose();
    super.dispose();
  }

  /// Updates the badge from the given user, or from the current session.
  void _syncUser([User? fromEvent]) {
    final user = fromEvent ?? _auth.currentUser;
    if (!mounted) return;
    if (user?.id != _user?.id) {
      setState(() => _user = user);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addGmail() async {
    try {
      await _auth.signInWithGoogle();
      // Returns once the browser opens. The user may not be signed in yet,
      // so this is only a best-effort refresh.
      _syncUser();
    } catch (e) {
      _showError('Google sign-in failed: $e');
    }
  }

  Future<void> _createAccount() async {
    final digits = _numberController.text.replaceAll(RegExp(r'\D'), '');

    if (digits.length != 10 || !digits.startsWith('3')) {
      _showError('Enter a valid number, e.g. 300 1234567');
      return;
    }

    // Check the live session, not the cached _user field.
    final user = _auth.currentUser;
    if (user == null) {
      _showError('Please add your Gmail first');
      return;
    }
    _syncUser(user);

    setState(() => _loading = true);
    try {
      await _users.saveProfile(whatsappNumber: '+92$digits');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
            (_) => false,
      );
    } catch (e) {
      debugPrint('Save profile error: $e');
      _showError('Could not save: $e');
      // The session may have been cleared (stale login). Refresh the badge.
      _syncUser();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const CircleAvatar(
                radius: 40,
                child: Icon(Icons.swap_horiz, size: 40),
              ),
              const SizedBox(height: 12),
              const Text('OmniSwap',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const Text('Trade what you have for what you want',
                  textAlign: TextAlign.center),
              const Divider(height: 40),

              const Text('Create your account',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),

              // Button before Google sign-in, badge after
              if (user == null)
                OutlinedButton.icon(
                  onPressed: _loading ? null : _addGmail,
                  icon: const Icon(Icons.g_mobiledata),
                  label: const Text('Add Gmail'),
                )
              else
                _GmailBadge(
                  name: (user.userMetadata?['full_name'] ??
                      user.userMetadata?['name'] ??
                      '') as String,
                  email: user.email ?? '',
                  avatarUrl: (user.userMetadata?['avatar_url'] ??
                      user.userMetadata?['picture']) as String?,
                  onTap: _loading ? null : _addGmail,
                ),
              const SizedBox(height: 24),

              const Text('Your WhatsApp number'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('🇵🇰 +92'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _numberController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: '300 1234567',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _loading ? null : _createAccount,
                child: _loading
                    ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create Account'),
              ),

              const Divider(height: 48),
              const Text('Already have an account?',
                  textAlign: TextAlign.center),
              TextButton(
                onPressed: _loading ? null : _addGmail,
                child: const Text('Sign in with Google'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the signed-in Google account. Tapping it lets the user pick another.
class _GmailBadge extends StatelessWidget {
  final String name;
  final String email;
  final String? avatarUrl;
  final VoidCallback? onTap;

  const _GmailBadge({
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final source = name.isNotEmpty ? name : email;
    final initial =
    source.isNotEmpty ? source.characters.first.toUpperCase() : '?';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.green.shade600),
          borderRadius: BorderRadius.circular(12),
          color: Colors.green.shade50,
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundImage:
              avatarUrl != null ? NetworkImage(avatarUrl!) : null,
              child: avatarUrl == null ? Text(initial) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name.isNotEmpty)
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(email, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            const Icon(Icons.edit, size: 18),
          ],
        ),
      ),
    );
  }
}