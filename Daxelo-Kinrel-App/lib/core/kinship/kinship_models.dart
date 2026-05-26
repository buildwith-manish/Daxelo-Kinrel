/// Translation for a relationship in a specific language
class KinshipTranslation {
  const KinshipTranslation({
    required this.native,
    required this.latin,
  });

  factory KinshipTranslation.fromJson(Map<String, dynamic> json) {
    return KinshipTranslation(
      native: json['native']?.toString() ?? '',
      latin: json['latin']?.toString() ?? '',
    );
  }

  final String native;
  final String latin;


  Map<String, dynamic> toJson() => {'native': native, 'latin': latin};
}

/// Full relationship record with metadata
class KinshipRelationship {
  const KinshipRelationship({
    required this.id,
    required this.relationshipKey,
    required this.englishTerm,
    required this.gender,
    required this.lineage,
    required this.generation,
    required this.relationType,
    required this.elderYounger,
    required this.relationshipCategory,
    this.cousinType,
    required this.relationshipPath,
    this.notes,
    required this.searchKeywords,
  });

  factory KinshipRelationship.fromJson(Map<String, dynamic> json) {
    return KinshipRelationship(
      id: json['id']?.toString() ?? '',
      relationshipKey: json['relationshipKey'] as String? ?? '',
      englishTerm: json['englishTerm'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      lineage: json['lineage'] as String? ?? '',
      generation: json['generation'] as int? ?? 0,
      relationType: json['relationType'] as String? ?? '',
      elderYounger: json['elderYounger'] as String? ?? '',
      relationshipCategory: json['relationshipCategory'] as String? ?? '',
      cousinType: json['cousinType'] as String?,
      relationshipPath: (json['relationshipPath'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      notes: json['notes'] as String?,
      searchKeywords: (json['searchKeywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  final String id;
  final String relationshipKey;
  final String englishTerm;
  final String gender;
  final String lineage;
  final int generation;
  final String relationType;
  final String elderYounger;
  final String relationshipCategory;
  final String? cousinType;
  final List<String> relationshipPath;
  final String? notes;
  final List<String> searchKeywords;

}

/// Root JSON structure
class KinshipData {
  const KinshipData({
    required this.version,
    required this.generatedAt,
    required this.totalRelationships,
    required this.supportedLanguages,
    required this.translations,
    required this.relationships,
  });

  factory KinshipData.fromJson(Map<String, dynamic> json) {
    // Parse translations: { "fathers_sister": { "hindi": { "native": "...", "latin": "..." }, ... }, ... }
    final translationsRaw = json['translations'] as Map<String, dynamic>? ?? {};
    final translations = <String, Map<String, KinshipTranslation>>{};
    for (final entry in translationsRaw.entries) {
      final langMap = <String, KinshipTranslation>{};
      final langData = entry.value as Map<String, dynamic>? ?? {};
      for (final langEntry in langData.entries) {
        langMap[langEntry.key] = KinshipTranslation.fromJson(
          langEntry.value as Map<String, dynamic>,
        );
      }
      translations[entry.key] = langMap;
    }

    return KinshipData(
      version: json['version'] as String? ?? '',
      generatedAt: json['generatedAt'] as String? ?? '',
      totalRelationships: json['totalRelationships'] as int? ?? 0,
      supportedLanguages: (json['supportedLanguages'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      translations: translations,
      relationships: (json['relationships'] as List<dynamic>?)
              ?.map((e) =>
                  KinshipRelationship.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  final String version;
  final String generatedAt;
  final int totalRelationships;
  final List<String> supportedLanguages;
  final Map<String, Map<String, KinshipTranslation>> translations;
  final List<KinshipRelationship> relationships;
}

/// Lightweight search result
class KinshipSearchResult {
  const KinshipSearchResult({
    required this.relationship,
    required this.score,
    required this.matchedField,
  });

  final KinshipRelationship relationship;
  final double score;
  final String matchedField;

}
