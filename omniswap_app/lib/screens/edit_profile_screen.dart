import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/countries.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../theme/app_colors.dart';

// Shared field styling. Neutral greys are used for borders and fills, and
// the palette is used for focus, labels, and accents.
const Color _fieldBorder = Color(0xFFD5DBE5);
const Color _fieldFillDisabled = Color(0xFFF1F3F7);
const double _fieldRadius = 14;

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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: _fieldBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const _SheetIcon(Icons.photo_camera_rounded),
                title: const Text('Take photo'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const _SheetIcon(Icons.photo_library_rounded),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
            ],
          ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Discard changes?'),
        content: const Text('You have unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
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

  /// The area field stops at 100 characters (maxLength), so only blank is checked.
  String? _validateArea(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Area is required';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Styling helpers
  // ---------------------------------------------------------------------------

  /// One decoration for every text field, so all inputs look the same.
  InputDecoration _decoration({
    required String label,
    String? hint,
    String? helper,
    IconData? icon,
    Widget? suffix,
    bool enabled = true,
  }) {
    final radius = BorderRadius.circular(_fieldRadius);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: const TextStyle(color: Color(0xFF6B7385)),
      floatingLabelStyle: const TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: icon == null
          ? null
          : Icon(
        icon,
        color: enabled ? AppColors.primary : const Color(0xFF9AA3B2),
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: enabled ? Colors.white : _fieldFillDisabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: _fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: _fieldBorder),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: Color(0xFFE6EAF1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  /// Same look as [_decoration], for the DropdownMenu fields.
  InputDecorationTheme get _dropdownInputTheme => InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    labelStyle: const TextStyle(color: Color(0xFF6B7385)),
    floatingLabelStyle: const TextStyle(
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_fieldRadius),
      borderSide: const BorderSide(color: _fieldBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_fieldRadius),
      borderSide: const BorderSide(color: _fieldBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(_fieldRadius),
      borderSide: const BorderSide(color: AppColors.primary, width: 2),
    ),
  );

  ButtonStyle get _primaryButtonStyle => ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.onPrimary,
    disabledBackgroundColor: AppColors.primary.withOpacity(0.35),
    disabledForegroundColor: AppColors.onPrimary.withOpacity(0.9),
    elevation: 0,
    minimumSize: const Size.fromHeight(54),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    textStyle: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    ),
  );

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
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          title: const Text(
            'Edit profile',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: AppColors.onPrimary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: canSave ? _save : null,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                disabledForegroundColor: AppColors.accent.withOpacity(0.4),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _saving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              )
                  : const Text('Save'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar:
        _loading || _loadError != null ? null : _buildSaveBar(canSave),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: AppColors.primary,
              ),
              const SizedBox(height: 12),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6B7385)),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 140,
                child: ElevatedButton(
                  onPressed: _load,
                  style: _primaryButtonStyle.copyWith(
                    minimumSize: WidgetStateProperty.all(
                      const Size.fromHeight(46),
                    ),
                  ),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final profile = _original!;

    return SafeArea(
      bottom: false,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _buildHeaderCard(profile),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.person_rounded,
              title: 'Personal',
              children: [
                TextFormField(
                  controller: _nameController,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 60,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  decoration: _decoration(
                    label: 'Display name',
                    icon: Icons.badge_outlined,
                  ),
                  validator: _validateName,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: profile.email,
                  enabled: false,
                  decoration: _decoration(
                    label: 'Email',
                    helper: 'Managed by your Google account',
                    icon: Icons.mail_outline_rounded,
                    enabled: false,
                    suffix: const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: Color(0xFF9AA3B2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _whatsappController,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    LengthLimitingTextInputFormatter(18),
                  ],
                  decoration: _decoration(
                    label: 'WhatsApp number',
                    hint: _country?.phoneHint ?? 'Select a country first',
                    helper: 'Traders contact you here.',
                    icon: Icons.chat_outlined,
                  ),
                  validator: _validateWhatsapp,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.place_rounded,
              title: 'Location',
              children: [
                _buildCountryField(),
                const SizedBox(height: 14),
                _buildCityField(),
                const SizedBox(height: 14),
                // Matches the database: area is 1 to 100 characters.
                // The counter shows n/100 under the field.
                TextFormField(
                  controller: _areaController,
                  enabled: !_saving,
                  maxLength: 100,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textCapitalization: TextCapitalization.words,
                  decoration: _decoration(
                    label: 'Area',
                    hint: 'e.g. DHA Phase 5, Gulberg',
                    helper: 'Neighbourhood or district',
                    icon: Icons.map_outlined,
                  ),
                  validator: _validateArea,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(UserProfile profile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildAvatar(profile),
          const SizedBox(height: 14),
          Text(
            profile.displayName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B2433),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      profile.rating.toStringAsFixed(2),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Tap the photo to change it',
            style: TextStyle(fontSize: 12, color: Color(0xFF8A94A6)),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(UserProfile profile) {
    final initials = profile.displayName.trim().isNotEmpty
        ? profile.displayName.trim()[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: _changeAvatar,
      child: SizedBox(
        width: 116,
        height: 116,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Yellow ring around the photo.
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: CircleAvatar(
                radius: 52,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                backgroundImage: profile.avatarUrl != null
                    ? NetworkImage(profile.avatarUrl!)
                    : null,
                child: profile.avatarUrl == null
                    ? Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                )
                    : null,
              ),
            ),
            if (_uploadingAvatar)
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: Colors.black38,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 16,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountryField() {
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: _dropdownInputTheme,
      ),
      child: DropdownMenu<CountryInfo>(
        controller: _countryController,
        enabled: !_saving,
        enableFilter: true,
        enableSearch: true,
        requestFocusOnTap: true,
        expandedInsets: EdgeInsets.zero,
        label: const Text('Country'),
        hintText: 'Search your country',
        leadingIcon: const Icon(Icons.public_rounded, color: AppColors.primary),
        trailingIcon: const Icon(Icons.keyboard_arrow_down_rounded),
        selectedTrailingIcon: const Icon(
          Icons.keyboard_arrow_up_rounded,
          color: AppColors.primary,
        ),
        menuStyle: _menuStyle,
        dropdownMenuEntries: [
          for (final country in kCountries)
            DropdownMenuEntry<CountryInfo>(
              value: country,
              label: country.name,
              leadingIcon: Text(country.flag),
            ),
        ],
        onSelected: _onCountrySelected,
      ),
    );
  }

  Widget _buildCityField() {
    final country = _country;
    final enabled = country != null && !_saving;
    final cities = country?.cities;

    // Countries without a city list get a plain text field.
    if (country == null || cities == null) {
      return TextFormField(
        controller: _cityController,
        enabled: enabled,
        textCapitalization: TextCapitalization.words,
        decoration: _decoration(
          label: 'City',
          hint: enabled ? 'Enter your city' : 'Select a country first',
          icon: Icons.location_city_rounded,
          enabled: enabled,
        ),
      );
    }

    // The key makes the dropdown start fresh when the country changes.
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: _dropdownInputTheme,
      ),
      child: DropdownMenu<String>(
        key: ValueKey('city-${country.name}'),
        controller: _cityController,
        enabled: enabled,
        enableFilter: true,
        enableSearch: true,
        requestFocusOnTap: true,
        expandedInsets: EdgeInsets.zero,
        label: const Text('City'),
        hintText: 'Search your city',
        leadingIcon: const Icon(
          Icons.location_city_rounded,
          color: AppColors.primary,
        ),
        trailingIcon: const Icon(Icons.keyboard_arrow_down_rounded),
        selectedTrailingIcon: const Icon(
          Icons.keyboard_arrow_up_rounded,
          color: AppColors.primary,
        ),
        menuStyle: _menuStyle,
        dropdownMenuEntries: [
          for (final city in cities)
            DropdownMenuEntry<String>(value: city, label: city),
        ],
      ),
    );
  }

  MenuStyle get _menuStyle => MenuStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.white),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(6),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );

  Widget _buildSaveBar(bool canSave) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canSave ? _save : null,
              style: _primaryButtonStyle,
              child: _saving
                  ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.onPrimary,
                ),
              )
                  : const Text('Save changes'),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Small widgets
// -----------------------------------------------------------------------------

/// A white rounded card with a titled section inside.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B2433),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

/// Icon used in the avatar bottom sheet.
class _SheetIcon extends StatelessWidget {
  const _SheetIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.primary),
    );
  }
}