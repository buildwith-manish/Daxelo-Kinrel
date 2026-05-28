import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'global_kinship_models.dart';

/// Global Kinship Service — Loads and manages cross-cultural kinship data
///
/// Features:
///   - Registry of 50+ cultures (6 with full data, 44+ metadata-only)
///   - Lazy loading per culture with caching
///   - Unified search across all loaded cultures
///   - Cross-cultural comparison for a given relationship key
///   - Maps different JSON formats into unified GlobalKinshipTerm model
class GlobalKinshipService {
  // Cache of loaded culture data
  final Map<String, GlobalKinshipData> _loadedData = {};

  // Loading state tracking
  final Set<String> _loading = {};
  final Set<String> _loadErrors = {};

  /// Get all registered cultures (50+)
  List<GlobalCultureInfo> get allCultures => _cultureRegistry;

  /// Get cultures that have full data files
  List<GlobalCultureInfo> get availableCultures =>
      _cultureRegistry.where((c) => c.hasDataFile).toList();

  /// Get cultures that are metadata-only (Coming Soon)
  List<GlobalCultureInfo> get comingSoonCultures =>
      _cultureRegistry.where((c) => !c.hasDataFile).toList();

  /// Check if a culture's data is loaded
  bool isLoaded(String cultureKey) => _loadedData.containsKey(cultureKey);

  /// Check if a culture is currently loading
  bool isLoading(String cultureKey) => _loading.contains(cultureKey);

  /// Check if a culture had a load error
  bool hasError(String cultureKey) => _loadErrors.contains(cultureKey);

  /// Get loaded data for a culture (returns null if not loaded)
  GlobalKinshipData? getCultureData(String cultureKey) =>
      _loadedData[cultureKey];

  /// Get culture info by key
  GlobalCultureInfo? getCultureInfo(String cultureKey) {
    for (final c in _cultureRegistry) {
      if (c.cultureKey == cultureKey) return c;
    }
    return null;
  }

  /// Load a specific culture's kinship data (lazy loading with caching)
  Future<GlobalKinshipData?> loadCulture(String cultureKey) async {
    // Return cached data
    if (_loadedData.containsKey(cultureKey)) {
      return _loadedData[cultureKey]!;
    }

    // Already loading
    if (_loading.contains(cultureKey)) return null;

    final info = getCultureInfo(cultureKey);
    if (info == null || !info.hasDataFile || info.dataAssetPath == null) {
      return null;
    }

    _loading.add(cultureKey);

    try {
      final jsonStr = await rootBundle.loadString(info.dataAssetPath!);
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      final data = _parseCultureData(cultureKey, jsonData);
      _loadedData[cultureKey] = data;
      _loading.remove(cultureKey);
      return data;
    } catch (e) {
      debugPrint('❌ Failed to load global kinship data for $cultureKey: $e');
      _loading.remove(cultureKey);
      _loadErrors.add(cultureKey);
      return null;
    }
  }

  /// Load all available cultures
  Future<void> loadAllAvailable() async {
    final futures = <Future<GlobalKinshipData?>>[];
    for (final culture in availableCultures) {
      if (!_loadedData.containsKey(culture.cultureKey)) {
        futures.add(loadCulture(culture.cultureKey));
      }
    }
    await Future.wait(futures);
  }

  /// Search across all loaded cultures
  List<GlobalKinshipTerm> searchGlobally(String query) {
    if (query.isEmpty) return [];
    final results = <GlobalKinshipTerm>[];
    for (final data in _loadedData.values) {
      results.addAll(data.search(query));
    }
    return results;
  }

  /// Cross-cultural comparison: get how a relationship key is expressed across all loaded cultures
  CrossCulturalComparison? compareCrossCulturally(String relationshipKey) {
    final entries = <CrossCulturalEntry>[];
    String englishTerm = relationshipKey
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) {
          if (w.isEmpty) return '';
          return w[0].toUpperCase() + w.substring(1);
        })
        .join(' ');

    for (final data in _loadedData.values) {
      final term = data.terms[relationshipKey];
      if (term == null) continue;

      if (term.englishTerm.isNotEmpty) {
        englishTerm = term.englishTerm;
      }

      final primary = term.primaryTerm;
      final info = data.cultureInfo;

      entries.add(
        CrossCulturalEntry(
          cultureKey: info.cultureKey,
          cultureName: info.name,
          flagEmoji: info.flagEmoji,
          region: info.region,
          nativeTerm: primary?.native ?? '—',
          romanization: primary?.romanization ?? '',
          formality: primary?.formalityLabel ?? '',
          dialect:
              primary?.dialect
                  .replaceAll('_', ' ')
                  .split(' ')
                  .map((w) {
                    if (w.isEmpty) return '';
                    return w[0].toUpperCase() + w.substring(1);
                  })
                  .join(' ') ??
              '',
          notes: term.dialectNote,
          isRTL: info.isRTL,
        ),
      );
    }

    if (entries.isEmpty) return null;

    return CrossCulturalComparison(
      relationshipKey: relationshipKey,
      englishTerm: englishTerm,
      entries: entries,
    );
  }

  /// Get all relationship keys that exist in at least 2 loaded cultures (for comparison)
  List<String> getComparableRelationshipKeys() {
    final keyCounts = <String, int>{};
    for (final data in _loadedData.values) {
      for (final key in data.terms.keys) {
        keyCounts[key] = (keyCounts[key] ?? 0) + 1;
      }
    }
    return keyCounts.entries
        .where((e) => e.value >= 2)
        .map((e) => e.key)
        .toList()
      ..sort();
  }

  /// Get common relationship keys (those in ALL loaded cultures)
  List<String> getCommonRelationshipKeys() {
    if (_loadedData.isEmpty) return [];
    final allKeys = _loadedData.values
        .map((d) => d.terms.keys.toSet())
        .toList();
    if (allKeys.isEmpty) return [];
    var common = allKeys.first;
    for (final keys in allKeys) {
      common = common.intersection(keys);
    }
    return common.toList()..sort();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // JSON Parsing — Maps different formats into unified GlobalKinshipTerm
  // ═══════════════════════════════════════════════════════════════════════

  GlobalKinshipData _parseCultureData(
    String cultureKey,
    Map<String, dynamic> json,
  ) {
    final info = getCultureInfo(cultureKey)!;
    final terms = <String, GlobalKinshipTerm>{};

    // The top-level `translations` map: { relationshipKey: { dialectNote, dialect1: {...}, ... } }
    final translations = json['translations'] as Map<String, dynamic>? ?? {};

    for (final entry in translations.entries) {
      final relKey = entry.key;
      final transData = entry.value as Map<String, dynamic>? ?? {};
      terms[relKey] = _parseTranslationEntry(cultureKey, relKey, transData);
    }

    return GlobalKinshipData(
      cultureInfo: info,
      terms: terms,
      version: json['version']?.toString() ?? '',
      generatedAt: json['generatedAt']?.toString() ?? '',
    );
  }

  GlobalKinshipTerm _parseTranslationEntry(
    String cultureKey,
    String relationshipKey,
    Map<String, dynamic> data,
  ) {
    final dialectTerms = <DialectTerm>[];
    final dialectNote = data['dialectNote']?.toString() ?? '';
    final englishTerm = data['englishTerm']?.toString() ?? '';
    final relationType = data['relationType']?.toString() ?? '';
    final islamicNote = data['islamicNote']?.toString();

    // Remove non-dialect keys
    final knownMetaKeys = {
      'dialectNote',
      'englishTerm',
      'relationType',
      'islamicNote',
      'kunya_pattern',
      'confucianNote',
      'xungHo',
      'chonsu',
    };

    for (final entry in data.entries) {
      if (knownMetaKeys.contains(entry.key)) continue;
      final dialectData = entry.value;
      if (dialectData is! Map<String, dynamic>) continue;

      _parseDialectEntries(cultureKey, entry.key, dialectData, dialectTerms);
    }

    return GlobalKinshipTerm(
      relationshipKey: relationshipKey,
      cultureKey: cultureKey,
      englishTerm: englishTerm,
      dialectNote: dialectNote,
      relationType: relationType,
      islamicNote: islamicNote,
      dialectTerms: dialectTerms,
    );
  }

  void _parseDialectEntries(
    String cultureKey,
    String dialect,
    Map<String, dynamic> data,
    List<DialectTerm> terms,
  ) {
    // Dispatch based on culture-specific structure
    switch (cultureKey) {
      case 'japanese':
        _parseJapaneseDialect(dialect, data, terms);
        break;
      case 'korean':
        _parseKoreanDialect(dialect, data, terms);
        break;
      case 'chinese':
        _parseChineseDialect(dialect, data, terms);
        break;
      case 'arabic':
        _parseArabicDialect(dialect, data, terms);
        break;
      case 'vietnamese':
        _parseVietnameseDialect(dialect, data, terms);
        break;
      case 'russian':
        _parseRussianDialect(dialect, data, terms);
        break;
      default:
        // Generic fallback: try {native, latin} structure
        _parseGenericDialect(dialect, data, terms);
    }
  }

  /// Japanese: { humble: {native, romaji}, honorific: {native, romaji} }
  void _parseJapaneseDialect(
    String dialect,
    Map<String, dynamic> data,
    List<DialectTerm> terms,
  ) {
    for (final formEntry in data.entries) {
      final formKey = formEntry.key; // 'humble' or 'honorific'
      final formData = formEntry.value;
      if (formData is! Map<String, dynamic>) continue;

      terms.add(
        DialectTerm(
          dialect: dialect,
          native: formData['native']?.toString() ?? '',
          romaji: formData['romaji']?.toString() ?? '',
          formality: formKey, // 'humble' or 'honorific'
        ),
      );
    }
  }

  /// Korean: { male_speaker: {formal: {native, romaji}, polite: {...}, informal: {...}}, female_speaker: {...} }
  void _parseKoreanDialect(
    String dialect,
    Map<String, dynamic> data,
    List<DialectTerm> terms,
  ) {
    for (final speakerEntry in data.entries) {
      final speakerKey = speakerEntry.key; // 'male_speaker' or 'female_speaker'
      final speakerData = speakerEntry.value;
      if (speakerData is! Map<String, dynamic>) continue;

      for (final formEntry in speakerData.entries) {
        final formKey = formEntry.key; // 'formal', 'polite', 'informal'
        final formData = formEntry.value;
        if (formData is! Map<String, dynamic>) continue;

        terms.add(
          DialectTerm(
            dialect: dialect,
            native: formData['native']?.toString() ?? '',
            romaji: formData['romaji']?.toString() ?? '',
            formality: formKey,
            genderForm: speakerKey,
          ),
        );
      }
    }
  }

  /// Chinese: { native: "...", latin: "..." }
  void _parseChineseDialect(
    String dialect,
    Map<String, dynamic> data,
    List<DialectTerm> terms,
  ) {
    // Chinese dialects have a simple flat structure
    if (data.containsKey('native')) {
      terms.add(
        DialectTerm(
          dialect: dialect,
          native: data['native']?.toString() ?? '',
          latin: data['latin']?.toString() ?? '',
          formality: 'neutral',
        ),
      );
      return;
    }

    // Fallback for nested structures
    for (final entry in data.entries) {
      if (entry.value is Map<String, dynamic>) {
        final m = entry.value as Map<String, dynamic>;
        terms.add(
          DialectTerm(
            dialect: dialect,
            native: m['native']?.toString() ?? '',
            latin: m['latin']?.toString() ?? '',
            formality: entry.key,
          ),
        );
      }
    }
  }

  /// Arabic: { masculine: {formal: {native, latin}, colloquial: {...}}, feminine: {...} }
  void _parseArabicDialect(
    String dialect,
    Map<String, dynamic> data,
    List<DialectTerm> terms,
  ) {
    for (final genderEntry in data.entries) {
      final genderKey = genderEntry.key; // 'masculine' or 'feminine'
      final genderData = genderEntry.value;
      if (genderData is! Map<String, dynamic>) continue;

      for (final formEntry in genderData.entries) {
        final formKey = formEntry.key; // 'formal' or 'colloquial'
        final formData = formEntry.value;
        if (formData is! Map<String, dynamic>) continue;

        terms.add(
          DialectTerm(
            dialect: dialect,
            native: formData['native']?.toString() ?? '',
            latin: formData['latin']?.toString() ?? '',
            formality: formKey,
            genderForm: genderKey,
          ),
        );
      }
    }
  }

  /// Vietnamese: { formal: {quoc_ngu, latin}, colloquial: {...} }
  void _parseVietnameseDialect(
    String dialect,
    Map<String, dynamic> data,
    List<DialectTerm> terms,
  ) {
    for (final formEntry in data.entries) {
      final formKey = formEntry.key;
      final formData = formEntry.value;
      if (formData is! Map<String, dynamic>) continue;

      // Vietnamese uses quoc_ngu instead of native
      final native =
          formData['quoc_ngu']?.toString() ??
          formData['native']?.toString() ??
          '';
      final latin = formData['latin']?.toString() ?? '';

      terms.add(
        DialectTerm(
          dialect: dialect,
          native: native,
          latin: latin,
          formality: formKey, // 'formal' or 'colloquial'
        ),
      );
    }
  }

  /// Russian: { masculine: {formal: {native, translit, ipa}, colloquial: {...}}, feminine: {...} }
  void _parseRussianDialect(
    String dialect,
    Map<String, dynamic> data,
    List<DialectTerm> terms,
  ) {
    for (final genderEntry in data.entries) {
      final genderKey = genderEntry.key; // 'masculine' or 'feminine'
      final genderData = genderEntry.value;
      if (genderData is! Map<String, dynamic>) continue;

      for (final formEntry in genderData.entries) {
        final formKey = formEntry.key; // 'formal' or 'colloquial'
        final formData = formEntry.value;
        if (formData is! Map<String, dynamic>) continue;

        terms.add(
          DialectTerm(
            dialect: dialect,
            native: formData['native']?.toString() ?? '',
            translit: formData['translit']?.toString() ?? '',
            ipa: formData['ipa']?.toString() ?? '',
            formality: formKey,
            genderForm: genderKey,
          ),
        );
      }
    }
  }

  /// Generic fallback: tries {native, latin}
  void _parseGenericDialect(
    String dialect,
    Map<String, dynamic> data,
    List<DialectTerm> terms,
  ) {
    if (data.containsKey('native')) {
      terms.add(
        DialectTerm(
          dialect: dialect,
          native: data['native']?.toString() ?? '',
          latin: data['latin']?.toString() ?? '',
          formality: 'neutral',
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CULTURE REGISTRY — 50+ cultures
  // ═══════════════════════════════════════════════════════════════════════

  static final List<GlobalCultureInfo> _cultureRegistry = [
    // ── CULTURES WITH FULL DATA ──────────────────────────────────────
    const GlobalCultureInfo(
      cultureKey: 'japanese',
      name: 'Japanese',
      nativeName: '日本語',
      languageFamily: 'Japonic',
      region: 'East Asia',
      flagEmoji: '🇯🇵',
      totalRelationships: 4509,
      dialects: [
        'Standard Japanese',
        'Kansai',
        'Kyushu',
        'Okinawan',
        'Tohoku',
        'Classical',
      ],
      isRTL: false,
      hasDataFile: true,
      dataAssetPath: 'assets/data/global/japanese_kinship_production.json',
    ),
    const GlobalCultureInfo(
      cultureKey: 'korean',
      name: 'Korean',
      nativeName: '한국어',
      languageFamily: 'Koreanic',
      region: 'East Asia',
      flagEmoji: '🇰🇷',
      totalRelationships: 4500,
      dialects: [
        'Standard Korean',
        'Gyeongsang',
        'Jeolla',
        'Jeju',
        'Hamgyong',
        'Classical',
      ],
      isRTL: false,
      hasDataFile: true,
      dataAssetPath: 'assets/data/global/korean_kinship_production.json',
    ),
    const GlobalCultureInfo(
      cultureKey: 'chinese',
      name: 'Chinese',
      nativeName: '中文',
      languageFamily: 'Sino-Tibetan',
      region: 'East Asia',
      flagEmoji: '🇨🇳',
      totalRelationships: 5358,
      dialects: [
        'Mandarin',
        'Cantonese',
        'Hokkien',
        'Hakka',
        'Shanghainese',
        'Sichuanese',
        'Classical',
      ],
      isRTL: false,
      hasDataFile: true,
      dataAssetPath: 'assets/data/global/chinese_kinship_production.json',
    ),
    const GlobalCultureInfo(
      cultureKey: 'arabic',
      name: 'Arabic',
      nativeName: 'العربية',
      languageFamily: 'Semitic',
      region: 'Middle East',
      flagEmoji: '🇸🇦',
      totalRelationships: 5314,
      dialects: [
        'MSA',
        'Egyptian',
        'Levantine',
        'Gulf',
        'Moroccan',
        'Iraqi',
        'Yemeni',
        'Classical',
      ],
      isRTL: true,
      hasDataFile: true,
      dataAssetPath: 'assets/data/global/arabic_kinship_production.json',
    ),
    const GlobalCultureInfo(
      cultureKey: 'vietnamese',
      name: 'Vietnamese',
      nativeName: 'Tiếng Việt',
      languageFamily: 'Austroasiatic',
      region: 'Southeast Asia',
      flagEmoji: '🇻🇳',
      totalRelationships: 5000,
      dialects: [
        'Standard',
        'Northern',
        'Central',
        'Southern',
        'Huế',
        'Hà Tĩnh',
        'Classical',
      ],
      isRTL: false,
      hasDataFile: true,
      dataAssetPath: 'assets/data/global/vietnamese_kinship_production_v2.json',
    ),
    const GlobalCultureInfo(
      cultureKey: 'russian',
      name: 'Russian',
      nativeName: 'Русский',
      languageFamily: 'Indo-European (Slavic)',
      region: 'Eastern Europe',
      flagEmoji: '🇷🇺',
      totalRelationships: 5200,
      dialects: [
        'Standard Russian',
        'Northern Archangel',
        'Southern Rostov',
        'Siberian',
        'Ural',
        'Pomor',
        'Old Russian',
      ],
      isRTL: false,
      hasDataFile: true,
      dataAssetPath:
          'assets/data/global/russian_kinship_production_v2 (1).json',
    ),

    // ── METADATA-ONLY CULTURES (Coming Soon) ─────────────────────────
    // South Asia
    const GlobalCultureInfo(
      cultureKey: 'hindi',
      name: 'Hindi',
      nativeName: 'हिन्दी',
      languageFamily: 'Indo-European (Indic)',
      region: 'South Asia',
      flagEmoji: '🇮🇳',
      totalRelationships: 5359,
      dialects: ['Khari Boli', 'Awadhi', 'Bhojpuri', 'Braj'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'bengali',
      name: 'Bengali',
      nativeName: 'বাংলা',
      languageFamily: 'Indo-European (Indic)',
      region: 'South Asia',
      flagEmoji: '🇧🇩',
      totalRelationships: 4800,
      dialects: ['Standard', 'Rarhi', 'Varendri', 'Manbhumi'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'telugu',
      name: 'Telugu',
      nativeName: 'తెలుగు',
      languageFamily: 'Dravidian',
      region: 'South Asia',
      flagEmoji: '🇮🇳',
      totalRelationships: 4200,
      dialects: ['Standard', 'Telangana', 'Andhra', 'Rayalaseema'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'marathi',
      name: 'Marathi',
      nativeName: 'मराठी',
      languageFamily: 'Indo-European (Indic)',
      region: 'South Asia',
      flagEmoji: '🇮🇳',
      totalRelationships: 4000,
      dialects: ['Standard', 'Varhadi', 'Konkani', 'Ahirani'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'tamil',
      name: 'Tamil',
      nativeName: 'தமிழ்',
      languageFamily: 'Dravidian',
      region: 'South Asia',
      flagEmoji: '🇮🇳',
      totalRelationships: 4600,
      dialects: ['Standard', 'Madurai', 'Coimbatore', 'Jaffna'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'gujarati',
      name: 'Gujarati',
      nativeName: 'ગુજરાતી',
      languageFamily: 'Indo-European (Indic)',
      region: 'South Asia',
      flagEmoji: '🇮🇳',
      totalRelationships: 3800,
      dialects: ['Standard', 'Surti', 'Kathiyawadi', 'Kutchi'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'kannada',
      name: 'Kannada',
      nativeName: 'ಕನ್ನಡ',
      languageFamily: 'Dravidian',
      region: 'South Asia',
      flagEmoji: '🇮🇳',
      totalRelationships: 3900,
      dialects: ['Standard', 'Mysuru', 'Dharwad', 'Mangaluru'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'malayalam',
      name: 'Malayalam',
      nativeName: 'മലയാളം',
      languageFamily: 'Dravidian',
      region: 'South Asia',
      flagEmoji: '🇮🇳',
      totalRelationships: 3700,
      dialects: ['Standard', 'Travancore', 'Malabar', 'Palakkad'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'punjabi',
      name: 'Punjabi',
      nativeName: 'ਪੰਜਾਬੀ',
      languageFamily: 'Indo-European (Indic)',
      region: 'South Asia',
      flagEmoji: '🇮🇳',
      totalRelationships: 4100,
      dialects: ['Standard', 'Majhi', 'Doabi', 'Malwai'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'odia',
      name: 'Odia',
      nativeName: 'ଓଡ଼ିଆ',
      languageFamily: 'Indo-European (Indic)',
      region: 'South Asia',
      flagEmoji: '🇮🇳',
      totalRelationships: 3200,
      dialects: ['Standard', 'Sambalpuri', 'Baleswari', 'Ganjami'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'assamese',
      name: 'Assamese',
      nativeName: 'অসমীয়া',
      languageFamily: 'Indo-European (Indic)',
      region: 'South Asia',
      flagEmoji: '🇮🇳',
      totalRelationships: 3000,
      dialects: ['Standard', 'Kamrupi', 'Goalpariya', 'Upper Assam'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'urdu',
      name: 'Urdu',
      nativeName: 'اردو',
      languageFamily: 'Indo-European (Indic)',
      region: 'South Asia',
      flagEmoji: '🇵🇰',
      totalRelationships: 4500,
      dialects: ['Standard', 'Dakhni', 'Rekhta'],
      isRTL: true,
    ),
    const GlobalCultureInfo(
      cultureKey: 'sinhala',
      name: 'Sinhala',
      nativeName: 'සිංහල',
      languageFamily: 'Indo-European (Indic)',
      region: 'South Asia',
      flagEmoji: '🇱🇰',
      totalRelationships: 2800,
      dialects: ['Standard', 'Southern', 'Central', 'Sabaragamuwa'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'nepali',
      name: 'Nepali',
      nativeName: 'नेपाली',
      languageFamily: 'Indo-European (Indic)',
      region: 'South Asia',
      flagEmoji: '🇳🇵',
      totalRelationships: 2900,
      dialects: ['Standard', 'Eastern', 'Western', 'Doteli'],
      isRTL: false,
    ),

    // East & Southeast Asia
    const GlobalCultureInfo(
      cultureKey: 'tibetan',
      name: 'Tibetan',
      nativeName: 'བོད་སྐད',
      languageFamily: 'Sino-Tibetan',
      region: 'East Asia',
      flagEmoji: '🏔️',
      totalRelationships: 2500,
      dialects: ['Lhasa', 'Amdo', 'Kham', 'Classical'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'thai',
      name: 'Thai',
      nativeName: 'ไทย',
      languageFamily: 'Kra-Dai',
      region: 'Southeast Asia',
      flagEmoji: '🇹🇭',
      totalRelationships: 3100,
      dialects: ['Standard', 'Isan', 'Northern', 'Southern'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'lao',
      name: 'Lao',
      nativeName: 'ລາວ',
      languageFamily: 'Kra-Dai',
      region: 'Southeast Asia',
      flagEmoji: '🇱🇦',
      totalRelationships: 2800,
      dialects: ['Standard', 'Northern', 'Southern', 'Eastern'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'burmese',
      name: 'Burmese',
      nativeName: 'မြန်မာ',
      languageFamily: 'Sino-Tibetan',
      region: 'Southeast Asia',
      flagEmoji: '🇲🇲',
      totalRelationships: 2900,
      dialects: ['Standard', 'Arakanese', 'Tavoyan', 'Intha'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'khmer',
      name: 'Khmer',
      nativeName: 'ខ្មែរ',
      languageFamily: 'Austroasiatic',
      region: 'Southeast Asia',
      flagEmoji: '🇰🇭',
      totalRelationships: 2700,
      dialects: ['Standard', 'Battambang', 'Surin', 'Cardamom'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'indonesian',
      name: 'Indonesian',
      nativeName: 'Bahasa Indonesia',
      languageFamily: 'Austronesian',
      region: 'Southeast Asia',
      flagEmoji: '🇮🇩',
      totalRelationships: 2600,
      dialects: ['Standard', 'Javanese', 'Sundanese', 'Betawi'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'filipino',
      name: 'Filipino',
      nativeName: 'Filipino',
      languageFamily: 'Austronesian',
      region: 'Southeast Asia',
      flagEmoji: '🇵🇭',
      totalRelationships: 2500,
      dialects: ['Tagalog', 'Cebuano', 'Ilocano', 'Hiligaynon'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'malay',
      name: 'Malay',
      nativeName: 'Bahasa Melayu',
      languageFamily: 'Austronesian',
      region: 'Southeast Asia',
      flagEmoji: '🇲🇾',
      totalRelationships: 2400,
      dialects: ['Standard', 'Kelantanese', 'Johor', 'Kedah'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'mongolian',
      name: 'Mongolian',
      nativeName: 'Монгол',
      languageFamily: 'Mongolic',
      region: 'East Asia',
      flagEmoji: '🇲🇳',
      totalRelationships: 2200,
      dialects: ['Khalkha', 'Buryat', 'Oirat', 'Classical'],
      isRTL: false,
    ),

    // Middle East & Central Asia
    const GlobalCultureInfo(
      cultureKey: 'turkish',
      name: 'Turkish',
      nativeName: 'Türkçe',
      languageFamily: 'Turkic',
      region: 'Central Asia',
      flagEmoji: '🇹🇷',
      totalRelationships: 3400,
      dialects: ['Standard', 'Anatolian', 'Rumelian', 'Black Sea'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'persian',
      name: 'Persian',
      nativeName: 'فارسی',
      languageFamily: 'Indo-European (Iranian)',
      region: 'Middle East',
      flagEmoji: '🇮🇷',
      totalRelationships: 3600,
      dialects: ['Standard', 'Dari', 'Tajik', 'Classical'],
      isRTL: true,
    ),
    const GlobalCultureInfo(
      cultureKey: 'hebrew',
      name: 'Hebrew',
      nativeName: 'עברית',
      languageFamily: 'Semitic',
      region: 'Middle East',
      flagEmoji: '🇮🇱',
      totalRelationships: 2800,
      dialects: ['Modern', 'Biblical', 'Mishnaic'],
      isRTL: true,
    ),

    // Africa
    const GlobalCultureInfo(
      cultureKey: 'amharic',
      name: 'Amharic',
      nativeName: 'አማርኛ',
      languageFamily: 'Afroasiatic (Semitic)',
      region: 'Africa',
      flagEmoji: '🇪🇹',
      totalRelationships: 2400,
      dialects: ['Standard', 'Gondar', 'Gojjam', 'Wollo'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'swahili',
      name: 'Swahili',
      nativeName: 'Kiswahili',
      languageFamily: 'Niger-Congo (Bantu)',
      region: 'Africa',
      flagEmoji: '🇰🇪',
      totalRelationships: 2100,
      dialects: ['Standard', 'Kiunguja', 'Kiamu', 'Kimvita'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'yoruba',
      name: 'Yoruba',
      nativeName: 'Yorùbá',
      languageFamily: 'Niger-Congo',
      region: 'Africa',
      flagEmoji: '🇳🇬',
      totalRelationships: 2000,
      dialects: ['Standard', 'Oyo', 'Egba', 'Ijebu'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'zulu',
      name: 'Zulu',
      nativeName: 'isiZulu',
      languageFamily: 'Niger-Congo (Bantu)',
      region: 'Africa',
      flagEmoji: '🇿🇦',
      totalRelationships: 1900,
      dialects: ['Standard', 'KwaZulu', 'Natal'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'igbo',
      name: 'Igbo',
      nativeName: 'Igbo',
      languageFamily: 'Niger-Congo',
      region: 'Africa',
      flagEmoji: '🇳🇬',
      totalRelationships: 1800,
      dialects: ['Standard', 'Owerri', 'Onitsha', 'Umuahia'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'hausa',
      name: 'Hausa',
      nativeName: 'Hausa',
      languageFamily: 'Afroasiatic (Chadic)',
      region: 'Africa',
      flagEmoji: '🇳🇬',
      totalRelationships: 2200,
      dialects: ['Standard', 'Kano', 'Sokoto', 'Zazzau'],
      isRTL: false,
    ),

    // Northern Europe
    const GlobalCultureInfo(
      cultureKey: 'finnish',
      name: 'Finnish',
      nativeName: 'Suomi',
      languageFamily: 'Uralic',
      region: 'Northern Europe',
      flagEmoji: '🇫🇮',
      totalRelationships: 2000,
      dialects: ['Standard', 'Savo', 'Häme', 'Pohjanmaa'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'swedish',
      name: 'Swedish',
      nativeName: 'Svenska',
      languageFamily: 'Indo-European (Germanic)',
      region: 'Northern Europe',
      flagEmoji: '🇸🇪',
      totalRelationships: 2200,
      dialects: ['Standard', 'Göta', 'Svea', 'Norrländska'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'norwegian',
      name: 'Norwegian',
      nativeName: 'Norsk',
      languageFamily: 'Indo-European (Germanic)',
      region: 'Northern Europe',
      flagEmoji: '🇳🇴',
      totalRelationships: 2100,
      dialects: ['Bokmål', 'Nynorsk', 'Urban Eastern', 'Bergensk'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'danish',
      name: 'Danish',
      nativeName: 'Dansk',
      languageFamily: 'Indo-European (Germanic)',
      region: 'Northern Europe',
      flagEmoji: '🇩🇰',
      totalRelationships: 2000,
      dialects: ['Standard', 'Jutlandic', 'Funen', 'Bornholm'],
      isRTL: false,
    ),

    // Western Europe
    const GlobalCultureInfo(
      cultureKey: 'german',
      name: 'German',
      nativeName: 'Deutsch',
      languageFamily: 'Indo-European (Germanic)',
      region: 'Europe',
      flagEmoji: '🇩🇪',
      totalRelationships: 2600,
      dialects: ['Standard', 'Bavarian', 'Swabian', 'Plattdeutsch'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'dutch',
      name: 'Dutch',
      nativeName: 'Nederlands',
      languageFamily: 'Indo-European (Germanic)',
      region: 'Europe',
      flagEmoji: '🇳🇱',
      totalRelationships: 2300,
      dialects: ['Standard', 'Flemish', 'Brabantic', 'Limburgish'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'french',
      name: 'French',
      nativeName: 'Français',
      languageFamily: 'Indo-European (Romance)',
      region: 'Europe',
      flagEmoji: '🇫🇷',
      totalRelationships: 2500,
      dialects: ['Standard', 'Québécois', 'Provençal', 'Classical'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'italian',
      name: 'Italian',
      nativeName: 'Italiano',
      languageFamily: 'Indo-European (Romance)',
      region: 'Europe',
      flagEmoji: '🇮🇹',
      totalRelationships: 2400,
      dialects: ['Standard', 'Neapolitan', 'Sicilian', 'Venetian'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'spanish',
      name: 'Spanish',
      nativeName: 'Español',
      languageFamily: 'Indo-European (Romance)',
      region: 'Europe',
      flagEmoji: '🇪🇸',
      totalRelationships: 2700,
      dialects: ['Castilian', 'Andalusian', 'Rioplatense', 'Classical'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'portuguese',
      name: 'Portuguese',
      nativeName: 'Português',
      languageFamily: 'Indo-European (Romance)',
      region: 'Europe',
      flagEmoji: '🇵🇹',
      totalRelationships: 2500,
      dialects: ['European', 'Brazilian', 'African', 'Classical'],
      isRTL: false,
    ),

    // Eastern Europe
    const GlobalCultureInfo(
      cultureKey: 'polish',
      name: 'Polish',
      nativeName: 'Polski',
      languageFamily: 'Indo-European (Slavic)',
      region: 'Eastern Europe',
      flagEmoji: '🇵🇱',
      totalRelationships: 2400,
      dialects: ['Standard', 'Greater Polish', 'Lesser Polish', 'Silesian'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'czech',
      name: 'Czech',
      nativeName: 'Čeština',
      languageFamily: 'Indo-European (Slavic)',
      region: 'Eastern Europe',
      flagEmoji: '🇨🇿',
      totalRelationships: 2200,
      dialects: ['Standard', 'Bohemian', 'Moravian', 'Silesian'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'greek',
      name: 'Greek',
      nativeName: 'Ελληνικά',
      languageFamily: 'Indo-European (Hellenic)',
      region: 'Europe',
      flagEmoji: '🇬🇷',
      totalRelationships: 2300,
      dialects: ['Standard', 'Cypriot', 'Pontic', 'Classical'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'romanian',
      name: 'Romanian',
      nativeName: 'Română',
      languageFamily: 'Indo-European (Romance)',
      region: 'Eastern Europe',
      flagEmoji: '🇷🇴',
      totalRelationships: 2200,
      dialects: ['Standard', 'Moldovan', 'Transylvanian', 'Oltenian'],
      isRTL: false,
    ),
    const GlobalCultureInfo(
      cultureKey: 'hungarian',
      name: 'Hungarian',
      nativeName: 'Magyar',
      languageFamily: 'Uralic',
      region: 'Eastern Europe',
      flagEmoji: '🇭🇺',
      totalRelationships: 2100,
      dialects: ['Standard', 'Transylvanian', 'Székely', 'Csángó'],
      isRTL: false,
    ),
  ];
}
