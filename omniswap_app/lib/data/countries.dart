/// A country that users can sign up from, with its phone rules and cities.
class CountryInfo {
  const CountryInfo({
    required this.name,
    required this.flag,
    required this.dialCode,
    required this.nationalNumberPattern,
    required this.phoneHint,
    required this.phoneError,
    this.trunkPrefix,
    this.cities,
  });

  /// Saved to the database as-is.
  final String name;
  final String flag;

  /// Country calling code without the plus sign, e.g. "92".
  final String dialCode;

  /// Regex the national number must match, after the country code and
  /// trunk prefix have been removed.
  final String nationalNumberPattern;

  /// Example number shown in the phone field.
  final String phoneHint;

  /// Message shown when the number doesn't match [nationalNumberPattern].
  final String phoneError;

  /// Prefix dialled inside the country, e.g. "0" in Pakistan (03001234567).
  final String? trunkPrefix;

  /// Cities for the city dropdown. Null means the user types the city.
  final List<String>? cities;

  /// Returns the number in international format (e.g. +923001234567),
  /// or null if it is not valid for this country.
  String? normalizePhone(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    final pattern = RegExp(nationalNumberPattern);

    // The user typed the country code, e.g. 923001234567.
    if (digits.startsWith(dialCode) &&
        pattern.hasMatch(digits.substring(dialCode.length))) {
      digits = digits.substring(dialCode.length);
    }

    // The user typed the local trunk prefix, e.g. 03001234567.
    final trunk = trunkPrefix;
    if (trunk != null && digits.startsWith(trunk)) {
      digits = digits.substring(trunk.length);
    }

    if (!pattern.hasMatch(digits)) return null;
    return '+$dialCode$digits';
  }
}

/// The countries available at sign-up. Keep names identical to the database values.
const List<CountryInfo> kCountries = [
  CountryInfo(
    name: 'Pakistan',
    flag: '🇵🇰',
    dialCode: '92',
    trunkPrefix: '0',
    nationalNumberPattern: r'^3[0-9]{9}$',
    phoneHint: '300 1234567',
    phoneError: 'Enter a valid Pakistani mobile number, e.g. 300 1234567.',
    cities: [
      'Abbottabad',
      'Bahawalpur',
      'Faisalabad',
      'Gujranwala',
      'Hyderabad',
      'Islamabad',
      'Karachi',
      'Lahore',
      'Multan',
      'Peshawar',
      'Quetta',
      'Rawalpindi',
      'Sialkot',
      'Sukkur',
    ],
  ),
  CountryInfo(
    name: 'Saudi Arabia',
    flag: '🇸🇦',
    dialCode: '966',
    trunkPrefix: '0',
    nationalNumberPattern: r'^5[0-9]{8}$',
    phoneHint: '50 123 4567',
    phoneError: 'Enter a valid Saudi mobile number, e.g. 50 123 4567.',
    cities: [
      'Dammam',
      'Jeddah',
      'Madinah',
      'Makkah',
      'Riyadh',
    ],
  ),
  CountryInfo(
    name: 'United States',
    flag: '🇺🇸',
    dialCode: '1',
    nationalNumberPattern: r'^[2-9][0-9]{2}[2-9][0-9]{6}$',
    phoneHint: '202 555 0143',
    phoneError: 'Enter a valid US phone number, e.g. 202 555 0143.',
    cities: [
      'Chicago',
      'Dallas',
      'Houston',
      'Los Angeles',
      'New York',
      'San Francisco',
      'Washington',
    ],
  ),
];