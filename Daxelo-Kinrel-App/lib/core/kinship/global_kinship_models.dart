/// Global Kinship Models — Unified data structures for cross-cultural kinship data
///
/// These models provide a common interface over the different JSON formats
/// used by Japanese (humble/honorific), Arabic (masculine/feminine formal/colloquial),
/// Chinese (dialects with native/latin), Korean (male/female speaker, formal/polite/informal),
/// Vietnamese (formal/colloquial with quoc_ngu), and Russian (masculine/feminine, formal/colloquial with cases).
library;

/// Metadata about a culture/language in the global kinship registry
class GlobalCultureInfo {
  const GlobalCultureInfo({
    required this.cultureKey,
    required this.name,
    required this.nativeName,
    required this.languageFamily,
    required this.region,
    required this.flagEmoji,
    required this.totalRelationships,
    required this.dialects,
    this.isRTL = false,
    this.hasDataFile = false,
    this.dataAssetPath,
  });

  /// Unique key for this culture (e.g., 'japanese', 'chinese_mandarin')
  final String cultureKey;

  /// English name of the culture/language
  final String name;

  /// Native name in the culture's own script
  final String nativeName;

  /// Linguistic language family (e.g., 'Japonic', 'Sino-Tibetan')
  final String languageFamily;

  /// Geographic region (e.g., 'East Asia', 'Middle East')
  final String region;

  /// Flag emoji for visual representation
  final String flagEmoji;

  /// Total number of kinship relationships in the data file
  final int totalRelationships;

  /// List of dialects/variants available
  final List<String> dialects;

  /// Whether this language is written right-to-left
  final bool isRTL;

  /// Whether a full data file exists (vs metadata-only "Coming Soon")
  final bool hasDataFile;

  /// Path to the JSON asset file (null for metadata-only cultures)
  final String? dataAssetPath;

  /// Whether this culture has full data loaded
  bool get isAvailable => hasDataFile;

  /// Display name with flag
  String get displayName => '$flagEmoji $name';

  /// Region color code for cross-cultural comparison
  String get regionColorCode {
    switch (region) {
      case 'East Asia':
        return '#E8612A';
      case 'South Asia':
        return '#F59240';
      case 'Middle East':
        return '#D4AF37';
      case 'Europe':
        return '#3B82F6';
      case 'Southeast Asia':
        return '#4CAF7A';
      case 'Africa':
        return '#C44A18';
      case 'Central Asia':
        return '#FF6B6B';
      case 'Northern Europe':
        return '#60A5FA';
      case 'Eastern Europe':
        return '#8B5CF6';
      default:
        return '#8A7A72';
    }
  }
}

/// A single dialect-specific term within a GlobalKinshipTerm
class DialectTerm {
  const DialectTerm({
    required this.dialect,
    required this.native,
    this.latin = '',
    this.romaji = '',
    this.translit = '',
    this.formality = 'neutral',
    this.genderForm = 'neutral',
    this.ipa = '',
  });

  /// Dialect/variant name (e.g., 'standard_japanese', 'mandarin', 'MSA')
  final String dialect;

  /// Term in native script
  final String native;

  /// Latin/romanized form
  final String latin;

  /// Romaji (Japanese-specific)
  final String romaji;

  /// Transliteration (Russian/Cyrillic-specific)
  final String translit;

  /// IPA pronunciation
  final String ipa;

  /// Formality level: 'formal', 'polite', 'informal', 'colloquial', 'humble', 'honorific', 'neutral'
  final String formality;

  /// Gender form: 'masculine', 'feminine', 'neutral', 'male_speaker', 'female_speaker'
  final String genderForm;

  /// Primary romanization (tries latin, then romaji, then translit)
  String get romanization =>
      latin.isNotEmpty ? latin : (romaji.isNotEmpty ? romaji : translit);

  /// Display label for formality
  String get formalityLabel {
    switch (formality) {
      case 'formal':
        return 'Formal';
      case 'polite':
        return 'Polite';
      case 'informal':
        return 'Informal';
      case 'colloquial':
        return 'Colloquial';
      case 'humble':
        return 'Humble';
      case 'honorific':
        return 'Honorific';
      default:
        return '';
    }
  }

  /// Display label for gender form
  String get genderLabel {
    switch (genderForm) {
      case 'masculine':
        return '♂';
      case 'feminine':
        return '♀';
      case 'male_speaker':
        return '♂ Speaker';
      case 'female_speaker':
        return '♀ Speaker';
      default:
        return '';
    }
  }
}

/// A unified kinship term across dialects and formality levels for one culture
class GlobalKinshipTerm {
  const GlobalKinshipTerm({
    required this.relationshipKey,
    required this.cultureKey,
    this.englishTerm = '',
    this.dialectNote = '',
    this.culturalNote = '',
    this.relationType = '',
    this.gender = '',
    this.islamicNote,
    this.dialectTerms = const [],
  });

  /// The canonical relationship key (e.g., 'father', 'mothers_brother')
  final String relationshipKey;

  /// The culture this term belongs to
  final String cultureKey;

  /// English equivalent term
  final String englishTerm;

  /// Note about dialect differences
  final String dialectNote;

  /// Cultural context note
  final String culturalNote;

  /// Type of relationship (blood, marriage, social, etc.)
  final String relationType;

  /// Gender specificity
  final String gender;

  /// Islamic-specific note (Arabic only)
  final String? islamicNote;

  /// All dialect-specific terms
  final List<DialectTerm> dialectTerms;

  /// Primary (standard/formal) term for quick display
  DialectTerm? get primaryTerm {
    // Try to find standard dialect first
    for (final t in dialectTerms) {
      if (t.dialect.startsWith('standard') && t.formality == 'formal') return t;
    }
    for (final t in dialectTerms) {
      if (t.dialect.startsWith('standard') && t.formality == 'neutral') {
        return t;
      }
    }
    for (final t in dialectTerms) {
      if (t.dialect.startsWith('standard')) return t;
    }
    // Fall back to first formal term
    for (final t in dialectTerms) {
      if (t.formality == 'formal') return t;
    }
    // Fall back to first term
    return dialectTerms.isNotEmpty ? dialectTerms.first : null;
  }

  /// Get terms for a specific dialect
  List<DialectTerm> termsForDialect(String dialect) =>
      dialectTerms.where((t) => t.dialect == dialect).toList();
}

/// Loaded kinship data for a specific culture
class GlobalKinshipData {
  const GlobalKinshipData({
    required this.cultureInfo,
    required this.terms,
    this.version = '',
    this.generatedAt = '',
  });

  /// Culture metadata
  final GlobalCultureInfo cultureInfo;

  /// Map of relationshipKey → GlobalKinshipTerm
  final Map<String, GlobalKinshipTerm> terms;

  /// Data version
  final String version;

  /// Generation timestamp
  final String generatedAt;

  /// All relationship keys in this culture
  List<String> get relationshipKeys => terms.keys.toList();

  /// Search terms by query
  List<GlobalKinshipTerm> search(String query) {
    if (query.isEmpty) return terms.values.toList();
    final q = query.toLowerCase();
    return terms.values.where((term) {
      if (term.relationshipKey.toLowerCase().contains(q)) return true;
      if (term.englishTerm.toLowerCase().contains(q)) {
        return true;
      }
      if (term.dialectTerms.any((d) => d.native.toLowerCase().contains(q))) {
        return true;
      }
      if (term.dialectTerms.any(
        (d) => d.romanization.toLowerCase().contains(q),
      )) {
        return true;
      }
      return false;
    }).toList();
  }
}

/// A comparison of a single relationship key across multiple cultures
class CrossCulturalComparison {
  const CrossCulturalComparison({
    required this.relationshipKey,
    required this.englishTerm,
    required this.entries,
  });

  /// The relationship key being compared
  final String relationshipKey;

  /// English term for the relationship
  final String englishTerm;

  /// List of culture-specific entries
  final List<CrossCulturalEntry> entries;

  /// Get entries grouped by region
  Map<String, List<CrossCulturalEntry>> get byRegion {
    final map = <String, List<CrossCulturalEntry>>{};
    for (final entry in entries) {
      (map[entry.region] ??= []).add(entry);
    }
    return map;
  }

  /// Get unique regions represented
  List<String> get regions => byRegion.keys.toList();
}

/// A single culture's entry in a cross-cultural comparison
class CrossCulturalEntry {
  const CrossCulturalEntry({
    required this.cultureKey,
    required this.cultureName,
    required this.flagEmoji,
    required this.region,
    required this.nativeTerm,
    this.romanization = '',
    this.formality = '',
    this.dialect = '',
    this.genderForm = '',
    this.notes = '',
    this.isRTL = false,
  });

  /// Culture key
  final String cultureKey;

  /// Culture display name
  final String cultureName;

  /// Flag emoji
  final String flagEmoji;

  /// Geographic region
  final String region;

  /// Term in native script
  final String nativeTerm;

  /// Romanized form
  final String romanization;

  /// Formality level
  final String formality;

  /// Dialect name
  final String dialect;

  /// Gender form
  final String genderForm;

  /// Additional notes
  final String notes;

  /// Whether this culture uses RTL writing
  final bool isRTL;
}
