import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/countries.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

const Color kSummerBlue = Color(0xFF0A27C8);
const Color kSummerYellow = Color(0xFFFCF300);

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.onProfileSaved});

  /// Called after the profile is saved. The parent decides what to show next.
  final Future<void> Function()? onProfileSaved;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with WidgetsBindingObserver {
  final _countryController = TextEditingController();
  final _cityController = TextEditingController();
  final _areaController = TextEditingController();
  final _numberController = TextEditingController();

  final _auth = AuthService();
  final _users = UserService();
  bool _loading = false;

  /// The country the user picked. It sets the city list and the phone code.
  CountryInfo? _country;

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
    _countryController.dispose();
    _cityController.dispose();
    _areaController.dispose();
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

  void _onCountrySelected(CountryInfo? value) {
    setState(() {
      _country = value;
      // A city from the previous country isn't valid for this one.
      _cityController.clear();
    });
  }

  /// Checks every field. Returns the cleaned values, or shows an error and returns null.
  _FormData? _validateForm() {
    final country = _country;
    if (country == null || _countryController.text.trim() != country.name) {
      _showError('Select your country from the list.');
      return null;
    }

    final city = _cityController.text.trim();
    final cities = country.cities;
    if (city.isEmpty) {
      _showError(cities == null
          ? 'Enter your city.'
          : 'Select your city from the list.');
      return null;
    }
    if (cities != null && !cities.contains(city)) {
      _showError('Select your city from the list.');
      return null;
    }
    if (city.length > 100) {
      _showError('City name is too long.');
      return null;
    }

    final area = _areaController.text.trim();
    if (area.isEmpty) {
      _showError('Enter your area.');
      return null;
    }
    if (area.length > 100) {
      _showError('Area name is too long.');
      return null;
    }

    final whatsappNumber = country.normalizePhone(_numberController.text);
    if (whatsappNumber == null) {
      _showError(country.phoneError);
      return null;
    }

    return _FormData(
      whatsappNumber: whatsappNumber,
      country: country.name,
      city: city,
      area: area,
    );
  }

  Future<void> _createAccount() async {
    final form = _validateForm();
    if (form == null) return;

    // Check the live session, not the cached _user field.
    final user = _auth.currentUser;
    if (user == null) {
      _showError('Please add your Gmail first');
      return;
    }
    _syncUser(user);

    setState(() => _loading = true);
    try {
      await _users.saveProfile(
        whatsappNumber: form.whatsappNumber,
        country: form.country,
        city: form.city,
        area: form.area,
      );
      await _users.saveProfile(
        whatsappNumber: form.whatsappNumber,
        country: form.country,
        city: form.city,
        area: form.area,
      );
      if (!mounted) return;
      await widget.onProfileSaved?.call();
    } catch (e) {
      debugPrint('Save profile error: $e');
      _showError('Could not save: $e');
      // The session may have been cleared (stale login). Refresh the badge.
      _syncUser();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildCountryField() {
    return DropdownMenu<CountryInfo>(
      controller: _countryController,
      enabled: !_loading,
      enableFilter: true,
      enableSearch: true,
      requestFocusOnTap: true,
      expandedInsets: EdgeInsets.zero,
      label: const Text('Country'),
      hintText: 'Search your country',
      dropdownMenuEntries: [
        for (final country in kCountries)
          DropdownMenuEntry<CountryInfo>(value: country, label: country.name),
      ],
      onSelected: _onCountrySelected,
    );
  }

  Widget _buildCityField() {
    final country = _country;
    final enabled = country != null && !_loading;
    final cities = country?.cities;

    // Countries without a city list get a plain text field.
    if (country == null || cities == null) {
      return TextField(
        controller: _cityController,
        enabled: enabled,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: 'City',
          hintText: enabled ? 'Enter your city' : 'Select a country first',
          border: const OutlineInputBorder(),
        ),
      );
    }

    // The key makes the dropdown start fresh when the country changes.
    return DropdownMenu<String>(
      key: ValueKey('city-${country.name}'),
      controller: _cityController,
      enabled: enabled,
      enableFilter: true,
      enableSearch: true,
      requestFocusOnTap: true,
      expandedInsets: EdgeInsets.zero,
      label: const Text('City'),
      hintText: 'Search your city',
      dropdownMenuEntries: [
        for (final city in cities)
          DropdownMenuEntry<String>(value: city, label: city),
      ],
    );
  }

  Widget _buildPhoneRow() {
    final country = _country;
    final enabled = country != null && !_loading;

    return Row(
      children: [
        // Shows the flag and dial code of the selected country.
        Container(
          constraints: const BoxConstraints(minWidth: 96),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            country == null ? '+ --' : '${country.flag} +${country.dialCode}',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _numberController,
            enabled: enabled,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
              LengthLimitingTextInputFormatter(15),
            ],
            decoration: InputDecoration(
              hintText: country?.phoneHint ?? 'Select a country first',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Blue header: from the top of the screen down to the divider line.
            Container(
              color: kSummerBlue,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 40),
                      const CircleAvatar(
                        radius: 40,
                        backgroundColor: kSummerYellow,
                        child: Icon(
                          Icons.swap_horiz,
                          size: 40,
                          color: kSummerBlue,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'OmniSwap',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Text(
                        'Trade what you have for what you want',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 40),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // White form section below the blue header.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),

                    const Text('Create your account',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600)),
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

                    const Text('Your location'),
                    const SizedBox(height: 8),
                    _buildCountryField(),
                    const SizedBox(height: 12),
                    _buildCityField(),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _areaController,
                      enabled: !_loading,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Area',
                        hintText: 'e.g. DHA Phase 5, Gulberg',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    const Text('Your WhatsApp number'),
                    const SizedBox(height: 8),
                    _buildPhoneRow(),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: _loading ? null : _createAccount,
                      child: _loading
                          ? const SizedBox(
                          height: 20,
                          width: 20,
                          child:
                          CircularProgressIndicator(strokeWidth: 2))
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
          ],
        ),
      ),
    );
  }
}

/// The validated values from the form.
class _FormData {
  const _FormData({
    required this.whatsappNumber,
    required this.country,
    required this.city,
    required this.area,
  });

  final String whatsappNumber;
  final String country;
  final String city;
  final String area;
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