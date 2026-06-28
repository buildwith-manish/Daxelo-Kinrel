/// Translation for a relationship in a specific language
class KinshipTranslation {
  const KinshipTranslation({required this.native, required this.latin});

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

/// A chain rule defines what relationship results when the current
/// relationship is combined with another (via).
///
/// Example: for "father" + via "brother" → result "paternal-uncle".
/// Stored in the v5.0.0 JSON under the `chainRules` array on each entry.
class ChainRule {
  const ChainRule({
    required this.via,
    required this.result,
    required this.resultFemale,
  });

  factory ChainRule.fromJson(Map<String, dynamic> json) {
    return ChainRule(
      via: json['via'] as String? ?? '',
      result: json['result'] as String? ?? '',
      resultFemale:
          json['resultFemale'] as String? ?? json['result'] as String? ?? '',
    );
  }

  final String via;
  final String result;
  final String resultFemale;

  Map<String, dynamic> toJson() =>
      {'via': via, 'result': result, 'resultFemale': resultFemale};
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
    this.chainRules = const [],
    this.inverseKey,
    this.inverseKeyFemale,
    this.inverseKeyNeutral,
    this.depth = 1,
    this.bloodRelation = true,
    this.legalRelation = false,
    this.ceremonialRelation = false,
    this.graphDisplay,
    this.indianKinshipClass,
    this.hindiSpecificTerm,
    this.distinguishesFromMaternal = false,
    this.elderYoungerDistinction = false,
    this.regionSpecific,
    this.displayNames,
    this.culturalNotes,
    this.searchableText,
    this.inversePath,
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
      relationshipPath:
          (json['relationshipPath'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      notes: json['notes'] as String?,
      searchKeywords:
          (json['searchKeywords'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      // v5.0.0 fields
      chainRules:
          (json['chainRules'] as List<dynamic>?)
              ?.map((e) => ChainRule.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      inverseKey: json['inverseKey'] as String?,
      inverseKeyFemale: json['inverseKeyFemale'] as String?,
      inverseKeyNeutral: json['inverseKeyNeutral'] as String?,
      depth: json['depth'] as int? ?? 1,
      bloodRelation: json['bloodRelation'] as bool? ?? true,
      legalRelation: json['legalRelation'] as bool? ?? false,
      ceremonialRelation: json['ceremonialRelation'] as bool? ?? false,
      graphDisplay: json['graphDisplay'] as Map<String, dynamic>?,
      indianKinshipClass: json['indianKinshipClass'] as String?,
      hindiSpecificTerm: json['hindiSpecificTerm'] as String?,
      distinguishesFromMaternal:
          json['distinguishesFromMaternal'] as bool? ?? false,
      elderYoungerDistinction:
          json['elderYoungerDistinction'] as bool? ?? false,
      regionSpecific: json['regionSpecific'] as Map<String, dynamic>?,
      displayNames: json['displayNames'] as Map<String, dynamic>?,
      culturalNotes: json['culturalNotes'] as String?,
      searchableText: json['searchableText'] as String?,
      inversePath:
          (json['inversePath'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(),
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

  // v5.0.0 fields
  final List<ChainRule> chainRules;
  final String? inverseKey;
  final String? inverseKeyFemale;
  final String? inverseKeyNeutral;
  final int depth;
  final bool bloodRelation;
  final bool legalRelation;
  final bool ceremonialRelation;
  final Map<String, dynamic>? graphDisplay;
  final String? indianKinshipClass;
  final String? hindiSpecificTerm;
  final bool distinguishesFromMaternal;
  final bool elderYoungerDistinction;
  final Map<String, dynamic>? regionSpecific;
  final Map<String, dynamic>? displayNames;
  final String? culturalNotes;
  final String? searchableText;
  final List<String>? inversePath;
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
      supportedLanguages:
          (json['supportedLanguages'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      translations: translations,
      relationships:
          (json['relationships'] as List<dynamic>?)
              ?.map(
                (e) => KinshipRelationship.fromJson(e as Map<String, dynamic>),
              )
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
