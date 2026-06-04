/// Country Kinship Models — Country-first approach to global kinship
///
/// Maps countries to their cultures/languages, enabling users to
/// browse kinship terms by country. A country can have multiple
/// cultures/languages (e.g., India has Hindi, Bengali, Tamil, etc.).
library;

/// A country in the global kinship system.
///
/// Each country maps to one or more cultures/languages available
/// in the GlobalKinshipService registry. This provides a country-first
/// browsing experience where users select their country and then
/// see all available kinship terms in that country's languages.
class KinshipCountry {
  const KinshipCountry({
    required this.countryCode,
    required this.name,
    required this.nativeName,
    required this.flagEmoji,
    required this.region,
    required this.cultureKeys,
    this.continent = '',
  });

  /// ISO-like country code (e.g., 'IN', 'CN', 'JP')
  final String countryCode;

  /// English name of the country
  final String name;

  /// Native name in the country's primary script
  final String nativeName;

  /// Flag emoji
  final String flagEmoji;

  /// Geographic region for filtering
  final String region;

  /// Continent for top-level grouping
  final String continent;

  /// List of culture keys from GlobalKinshipService registry
  /// (e.g., ['hindi', 'bengali', 'tamil'] for India)
  final List<String> cultureKeys;

  /// Display name with flag
  String get displayName => '$flagEmoji $name';

  /// Total number of cultures/languages for this country
  int get totalCultures => cultureKeys.length;

  /// Whether this country has any cultures with full data files
  bool hasAvailableData(Set<String> availableCultureKeys) {
    return cultureKeys.any(availableCultureKeys.contains);
  }

  /// Number of cultures with full data
  int availableCultureCount(Set<String> availableCultureKeys) {
    return cultureKeys.where(availableCultureKeys.contains).length;
  }

  /// Get primary culture key (first in list, usually the most spoken language)
  String get primaryCultureKey => cultureKeys.first;
}

/// Continent definitions for grouping
class KinshipContinent {
  KinshipContinent._();

  static const String asia = 'Asia';
  static const String europe = 'Europe';
  static const String africa = 'Africa';
  static const String middleEast = 'Middle East & Central Asia';
  static const String americas = 'Americas';
  static const String oceania = 'Oceania';

  static const List<String> all = [
    asia,
    europe,
    africa,
    middleEast,
    americas,
    oceania,
  ];

  /// Get icon for continent
  static String getIcon(String continent) {
    switch (continent) {
      case asia:
        return '🌏';
      case europe:
        return '🌍';
      case africa:
        return '🌍';
      case middleEast:
        return '🕌';
      case americas:
        return '🌎';
      case oceania:
        return '🏝️';
      default:
        return '🌐';
    }
  }

  /// Get color code for continent (hex string)
  static String getColorCode(String continent) {
    switch (continent) {
      case asia:
        return '#E8612A';
      case europe:
        return '#3B82F6';
      case africa:
        return '#C44A18';
      case middleEast:
        return '#D4AF37';
      case americas:
        return '#4CAF7A';
      case oceania:
        return '#60A5FA';
      default:
        return '#8A7A72';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// COUNTRY REGISTRY — Maps countries to their culture keys
// ═══════════════════════════════════════════════════════════════════════
//
// Culture keys reference entries in GlobalKinshipService._cultureRegistry.
// When adding new cultures in the future, simply:
//   1. Add the culture to GlobalKinshipService._cultureRegistry
//   2. Add the cultureKey to the appropriate country here
//   3. Or add a new KinshipCountry entry
// ═══════════════════════════════════════════════════════════════════════

const List<KinshipCountry> countryRegistry = [
  // ── ASIA ──────────────────────────────────────────────────────────

  // South Asia
  KinshipCountry(
    countryCode: 'IN',
    name: 'India',
    nativeName: 'भारत',
    flagEmoji: '🇮🇳',
    region: 'South Asia',
    continent: KinshipContinent.asia,
    cultureKeys: [
      'hindi',
      'bengali',
      'telugu',
      'marathi',
      'tamil',
      'gujarati',
      'kannada',
      'malayalam',
      'punjabi',
      'odia',
      'assamese',
      'urdu',
    ],
  ),
  KinshipCountry(
    countryCode: 'LK',
    name: 'Sri Lanka',
    nativeName: 'ශ්‍රී ලංකාව',
    flagEmoji: '🇱🇰',
    region: 'South Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['sinhala'],
  ),
  KinshipCountry(
    countryCode: 'NP',
    name: 'Nepal',
    nativeName: 'नेपाल',
    flagEmoji: '🇳🇵',
    region: 'South Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['nepali'],
  ),

  // East Asia
  KinshipCountry(
    countryCode: 'CN',
    name: 'China',
    nativeName: '中国',
    flagEmoji: '🇨🇳',
    region: 'East Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['chinese'],
  ),
  KinshipCountry(
    countryCode: 'JP',
    name: 'Japan',
    nativeName: '日本',
    flagEmoji: '🇯🇵',
    region: 'East Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['japanese'],
  ),
  KinshipCountry(
    countryCode: 'KR',
    name: 'South Korea',
    nativeName: '대한민국',
    flagEmoji: '🇰🇷',
    region: 'East Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['korean'],
  ),
  KinshipCountry(
    countryCode: 'MN',
    name: 'Mongolia',
    nativeName: 'Монгол Улс',
    flagEmoji: '🇲🇳',
    region: 'East Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['mongolian'],
  ),

  // Southeast Asia
  KinshipCountry(
    countryCode: 'VN',
    name: 'Vietnam',
    nativeName: 'Việt Nam',
    flagEmoji: '🇻🇳',
    region: 'Southeast Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['vietnamese'],
  ),
  KinshipCountry(
    countryCode: 'TH',
    name: 'Thailand',
    nativeName: 'ประเทศไทย',
    flagEmoji: '🇹🇭',
    region: 'Southeast Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['thai'],
  ),
  KinshipCountry(
    countryCode: 'LA',
    name: 'Laos',
    nativeName: 'ປະເທດລາວ',
    flagEmoji: '🇱🇦',
    region: 'Southeast Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['lao'],
  ),
  KinshipCountry(
    countryCode: 'MM',
    name: 'Myanmar',
    nativeName: 'မြန်မာ',
    flagEmoji: '🇲🇲',
    region: 'Southeast Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['burmese'],
  ),
  KinshipCountry(
    countryCode: 'KH',
    name: 'Cambodia',
    nativeName: 'កម្ពុជា',
    flagEmoji: '🇰🇭',
    region: 'Southeast Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['khmer'],
  ),
  KinshipCountry(
    countryCode: 'ID',
    name: 'Indonesia',
    nativeName: 'Indonesia',
    flagEmoji: '🇮🇩',
    region: 'Southeast Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['indonesian'],
  ),
  KinshipCountry(
    countryCode: 'PH',
    name: 'Philippines',
    nativeName: 'Pilipinas',
    flagEmoji: '🇵🇭',
    region: 'Southeast Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['filipino'],
  ),
  KinshipCountry(
    countryCode: 'MY',
    name: 'Malaysia',
    nativeName: 'Malaysia',
    flagEmoji: '🇲🇾',
    region: 'Southeast Asia',
    continent: KinshipContinent.asia,
    cultureKeys: ['malay'],
  ),

  // ── MIDDLE EAST & CENTRAL ASIA ────────────────────────────────────
  KinshipCountry(
    countryCode: 'SA',
    name: 'Saudi Arabia',
    nativeName: 'المملكة العربية السعودية',
    flagEmoji: '🇸🇦',
    region: 'Middle East',
    continent: KinshipContinent.middleEast,
    cultureKeys: ['arabic'],
  ),
  KinshipCountry(
    countryCode: 'AE',
    name: 'UAE',
    nativeName: 'الإمارات',
    flagEmoji: '🇦🇪',
    region: 'Middle East',
    continent: KinshipContinent.middleEast,
    cultureKeys: ['arabic'],
  ),
  KinshipCountry(
    countryCode: 'EG',
    name: 'Egypt',
    nativeName: 'مصر',
    flagEmoji: '🇪🇬',
    region: 'Middle East',
    continent: KinshipContinent.middleEast,
    cultureKeys: ['arabic'],
  ),
  KinshipCountry(
    countryCode: 'IQ',
    name: 'Iraq',
    nativeName: 'العراق',
    flagEmoji: '🇮🇶',
    region: 'Middle East',
    continent: KinshipContinent.middleEast,
    cultureKeys: ['arabic'],
  ),
  KinshipCountry(
    countryCode: 'TR',
    name: 'Turkey',
    nativeName: 'Türkiye',
    flagEmoji: '🇹🇷',
    region: 'Central Asia',
    continent: KinshipContinent.middleEast,
    cultureKeys: ['turkish'],
  ),
  KinshipCountry(
    countryCode: 'IR',
    name: 'Iran',
    nativeName: 'ایران',
    flagEmoji: '🇮🇷',
    region: 'Middle East',
    continent: KinshipContinent.middleEast,
    cultureKeys: ['persian'],
  ),
  KinshipCountry(
    countryCode: 'IL',
    name: 'Israel',
    nativeName: 'ישראל',
    flagEmoji: '🇮🇱',
    region: 'Middle East',
    continent: KinshipContinent.middleEast,
    cultureKeys: ['hebrew'],
  ),

  // ── EUROPE ────────────────────────────────────────────────────────

  // Eastern Europe
  KinshipCountry(
    countryCode: 'RU',
    name: 'Russia',
    nativeName: 'Россия',
    flagEmoji: '🇷🇺',
    region: 'Eastern Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['russian'],
  ),
  KinshipCountry(
    countryCode: 'PL',
    name: 'Poland',
    nativeName: 'Polska',
    flagEmoji: '🇵🇱',
    region: 'Eastern Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['polish'],
  ),
  KinshipCountry(
    countryCode: 'CZ',
    name: 'Czech Republic',
    nativeName: 'Česko',
    flagEmoji: '🇨🇿',
    region: 'Eastern Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['czech'],
  ),
  KinshipCountry(
    countryCode: 'RO',
    name: 'Romania',
    nativeName: 'România',
    flagEmoji: '🇷🇴',
    region: 'Eastern Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['romanian'],
  ),
  KinshipCountry(
    countryCode: 'HU',
    name: 'Hungary',
    nativeName: 'Magyarország',
    flagEmoji: '🇭🇺',
    region: 'Eastern Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['hungarian'],
  ),
  KinshipCountry(
    countryCode: 'GR',
    name: 'Greece',
    nativeName: 'Ελλάδα',
    flagEmoji: '🇬🇷',
    region: 'Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['greek'],
  ),

  // Northern Europe
  KinshipCountry(
    countryCode: 'FI',
    name: 'Finland',
    nativeName: 'Suomi',
    flagEmoji: '🇫🇮',
    region: 'Northern Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['finnish'],
  ),
  KinshipCountry(
    countryCode: 'SE',
    name: 'Sweden',
    nativeName: 'Sverige',
    flagEmoji: '🇸🇪',
    region: 'Northern Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['swedish'],
  ),
  KinshipCountry(
    countryCode: 'NO',
    name: 'Norway',
    nativeName: 'Norge',
    flagEmoji: '🇳🇴',
    region: 'Northern Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['norwegian'],
  ),
  KinshipCountry(
    countryCode: 'DK',
    name: 'Denmark',
    nativeName: 'Danmark',
    flagEmoji: '🇩🇰',
    region: 'Northern Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['danish'],
  ),

  // Western Europe
  KinshipCountry(
    countryCode: 'DE',
    name: 'Germany',
    nativeName: 'Deutschland',
    flagEmoji: '🇩🇪',
    region: 'Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['german'],
  ),
  KinshipCountry(
    countryCode: 'NL',
    name: 'Netherlands',
    nativeName: 'Nederland',
    flagEmoji: '🇳🇱',
    region: 'Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['dutch'],
  ),
  KinshipCountry(
    countryCode: 'FR',
    name: 'France',
    nativeName: 'France',
    flagEmoji: '🇫🇷',
    region: 'Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['french'],
  ),
  KinshipCountry(
    countryCode: 'IT',
    name: 'Italy',
    nativeName: 'Italia',
    flagEmoji: '🇮🇹',
    region: 'Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['italian'],
  ),
  KinshipCountry(
    countryCode: 'ES',
    name: 'Spain',
    nativeName: 'España',
    flagEmoji: '🇪🇸',
    region: 'Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['spanish'],
  ),
  KinshipCountry(
    countryCode: 'PT',
    name: 'Portugal',
    nativeName: 'Portugal',
    flagEmoji: '🇵🇹',
    region: 'Europe',
    continent: KinshipContinent.europe,
    cultureKeys: ['portuguese'],
  ),

  // ── AFRICA ────────────────────────────────────────────────────────
  KinshipCountry(
    countryCode: 'ET',
    name: 'Ethiopia',
    nativeName: 'ኢትዮጵያ',
    flagEmoji: '🇪🇹',
    region: 'Africa',
    continent: KinshipContinent.africa,
    cultureKeys: ['amharic'],
  ),
  KinshipCountry(
    countryCode: 'KE',
    name: 'Kenya',
    nativeName: 'Kenya',
    flagEmoji: '🇰🇪',
    region: 'Africa',
    continent: KinshipContinent.africa,
    cultureKeys: ['swahili'],
  ),
  KinshipCountry(
    countryCode: 'NG',
    name: 'Nigeria',
    nativeName: 'Nigeria',
    flagEmoji: '🇳🇬',
    region: 'Africa',
    continent: KinshipContinent.africa,
    cultureKeys: ['yoruba', 'igbo', 'hausa'],
  ),
  KinshipCountry(
    countryCode: 'ZA',
    name: 'South Africa',
    nativeName: 'South Africa',
    flagEmoji: '🇿🇦',
    region: 'Africa',
    continent: KinshipContinent.africa,
    cultureKeys: ['zulu'],
  ),
  KinshipCountry(
    countryCode: 'TZ',
    name: 'Tanzania',
    nativeName: 'Tanzania',
    flagEmoji: '🇹🇿',
    region: 'Africa',
    continent: KinshipContinent.africa,
    cultureKeys: ['swahili'],
  ),
];
