import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/countries.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.service});

  /// Optional, so tests or other DI setups can inject a fake service.
  final ProfileService? service;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final ProfileService _service;

  final _nameController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _countryController = TextEditingController();
  final _cityController = TextEditingController();
  final _areaController = TextEditingController();

  CountryInfo? _country;
  UserProfile? _original;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _avatarChanged = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProfileService();

    for (final c in _controllers) {
      c.addListener(_onFieldChanged);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<TextEditingController> get _controllers => [
    _nameController,
    _whatsappController,
    _countryController,
    _cityController,
    _areaController,
  ];

  void _onFieldChanged() => setState(() {});

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final profile = await _service.fetchMyProfile();
      _original = profile;

      _nameController.text = profile.displayName;
      _whatsappController.text = profile.whatsappNumber;
      _countryController.text = profile.country;
      _cityController.text = profile.city;
      _areaController.text = profile.area;
      _country = _findCountry(profile.country);
    } catch (_) {
      _loadError = 'Could not load your profile. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  CountryInfo? _findCountry(String name) {
    for (final country in kCountries) {
      if (country.name == name) return country;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_validateCountryCity()) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final whatsapp = _normalizedWhatsapp();
    if (whatsapp == null) return;

    setState(() => _saving = true);

    try {
      final updated = await _service.updateMyProfile(
        displayName: _nameController.text.trim(),
        whatsappNumber: whatsapp,
        country: _countryController.text.trim(),
        city: _cityController.text.trim(),
        area: _areaController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      Navigator.of(context).pop(updated);
    } on PostgrestException catch (e) {
      // 23505 = unique_violation (WhatsApp number already used by another account)
      final message = e.code == '23505'
          ? 'This WhatsApp number is already used by another account.'
          : 'Could not save your profile. Please try again.';
      _showError(message);
    } catch (_) {
      _showError('Could not save your profile. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Avatar
  // ---------------------------------------------------------------------------

  Future<void> _changeAvatar() async {
    if (_uploadingAvatar || _saving) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      // Resize and compress here so uploads stay small.
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      await _uploadAvatar(bytes);
    } catch (_) {
      _showError('Could not get that photo. Please try again.');
    }
  }

  Future<void> _uploadAvatar(Uint8List bytes) async {
    setState(() => _uploadingAvatar = true);

    try {
      final updated = await _service.uploadAvatar(bytes);
      if (!mounted) return;
      setState(() {
        _original = updated;
        _avatarChanged = true;
      });
    } catch (_) {
      _showError('Could not upload your photo. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Dirty tracking and unsaved-changes guard
  // ---------------------------------------------------------------------------

  bool get _isDirty {
    final o = _original;
    if (o == null) return false;
    return _nameController.text.trim() != o.displayName ||
        (_normalizedWhatsapp() ?? _whatsappController.text.trim()) !=
            o.whatsappNumber ||
        _countryController.text.trim() != o.country ||
        _cityController.text.trim() != o.city ||
        _areaController.text.trim() != o.area;
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  void _onCountrySelected(CountryInfo? value) {
    setState(() {
      _country = value;
      // A city from the previous country isn't valid for this one.
      _cityController.clear();
    });
  }

  /// DropdownMenu isn't a FormField, so Form.validate() doesn't check it.
  /// This runs the same checks as sign-in. Shows an error and returns false if invalid.
  bool _validateCountryCity() {
    final country = _country;
    if (country == null || _countryController.text.trim() != country.name) {
      _showError('Select your country from the list.');
      return false;
    }

    final city = _cityController.text.trim();
    final cities = country.cities;
    if (city.isEmpty) {
      _showError(cities == null
          ? 'Enter your city.'
          : 'Select your city from the list.');
      return false;
    }
    if (cities != null && !cities.contains(city)) {
      _showError('Select your city from the list.');
      return false;
    }
    if (city.length > 100) {
      _showError('City name is too long.');
      return false;
    }
    return true;
  }

  /// Same rules as sign-in: accepts 03001234567 or +923001234567 for the
  /// selected country. Returns the international format, or null if invalid.
  String? _normalizedWhatsapp() =>
      _country?.normalizePhone(_whatsappController.text);

  String? _validateName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Name is required';
    if (v.length < 2) return 'Name must be at least 2 characters';
    if (v.length > 60) return 'Name must be 60 characters or fewer';
    return null;
  }

  String? _validateWhatsapp(String? value) {
    final country = _country;
    if (country == null) return 'Select your country first';
    if ((value ?? '').trim().isEmpty) return 'WhatsApp number is required';
    if (country.normalizePhone(value ?? '') == null) {
      return country.phoneError;
    }
    return null;
  }

  String? _validateLocation(String? value, String label) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '$label is required';
    if (v.length > 100) return '$label must be 100 characters or fewer';
    return null;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final canSave = !_loading && !_saving && _isDirty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_isDirty) {
          final discard = await _confirmDiscard();
          if (!discard || !mounted) return;
        }
        if (!mounted) return;
        // Return the profile if the avatar changed, so the caller can refresh.
        Navigator.of(context).pop(_avatarChanged ? _original : null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit profile'),
          actions: [
            TextButton(
              onPressed: canSave ? _save : null,
              child: _saving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Text('Save'),
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final profile = _original!;

    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(child: _buildAvatar(profile)),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Tap photo to change',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '★ ${profile.rating.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 24),

            _sectionTitle('Personal'),
            TextFormField(
              controller: _nameController,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Display name',
                border: OutlineInputBorder(),
              ),
              validator: _validateName,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: profile.email,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                helperText: 'Managed by your Google account',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _whatsappController,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                LengthLimitingTextInputFormatter(18),
              ],
              decoration: InputDecoration(
                labelText: 'WhatsApp number',
                hintText: _country?.phoneHint ?? 'Select a country first',
                helperText: 'Traders contact you here.',
                border: const OutlineInputBorder(),
              ),
              validator: _validateWhatsapp,
            ),

            const SizedBox(height: 24),
            _sectionTitle('Location'),
            _buildCountryField(),
            const SizedBox(height: 12),
            _buildCityField(),
            const SizedBox(height: 12),
            TextFormField(
              controller: _areaController,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Area',
                helperText: 'Neighbourhood or district',
                border: OutlineInputBorder(),
              ),
              validator: (v) => _validateLocation(v, 'Area'),
            ),

            const SizedBox(height: 32),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: (_isDirty && !_saving) ? _save : null,
                child: _saving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Text('Save changes'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCountryField() {
    return DropdownMenu<CountryInfo>(
      controller: _countryController,
      enabled: !_saving,
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
    final enabled = country != null && !_saving;
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

  Widget _buildAvatar(UserProfile profile) {
    final initials = profile.displayName.trim().isNotEmpty
        ? profile.displayName.trim()[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: _changeAvatar,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            radius: 48,
            backgroundImage: profile.avatarUrl != null
                ? NetworkImage(profile.avatarUrl!)
                : null,
            child: profile.avatarUrl == null
                ? Text(initials, style: const TextStyle(fontSize: 32))
                : null,
          ),
          if (_uploadingAvatar)
            const CircleAvatar(
              radius: 48,
              backgroundColor: Colors.black38,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: CircleAvatar(
              radius: 14,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(
                Icons.edit,
                size: 14,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}