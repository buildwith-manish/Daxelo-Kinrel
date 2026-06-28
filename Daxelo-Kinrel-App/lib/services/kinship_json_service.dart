// lib/services/kinship_json_service.dart
//
// DAXELO KINREL — Kinship JSON Service
//
// Loads and queries indian_kinship.json (downloaded from GitHub Releases).
// Provides access to translations, display names, graph metadata, and inverse keys.

import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';

/// Loaded kinship relationship entry.
class KinshipEntry {
  final String relationshipKey;
  final String englishTerm;
  final String gender;
  final String lineage;
  final int generation;
  final String? hindiSpecificTerm;
  final Map<String, String> regionSpecific;
  final Map<String, dynamic> graphDisplay;
  final String? inverseKey;
  final String? inverseKeyFemale;
  final String? inverseKeyNeutral;

  const KinshipEntry({
    required this.relationshipKey,
    required this.englishTerm,
    required this.gender,
    required this.lineage,
    required this.generation,
    this.hindiSpecificTerm,
    required this.regionSpecific,
    required this.graphDisplay,
    this.inverseKey,
    this.inverseKeyFemale,
    this.inverseKeyNeutral,
  });

  factory KinshipEntry.fromJson(Map<String, dynamic> json) {
    return KinshipEntry(
      relationshipKey: json['relationshipKey'] as String,
      englishTerm: json['englishTerm'] as String? ?? '',
      gender: json['gender'] as String? ?? 'neutral',
      lineage: json['lineage'] as String? ?? 'bilateral',
      generation: (json['generation'] as num?)?.toInt() ?? 0,
      hindiSpecificTerm: json['hindiSpecificTerm'] as String?,
      regionSpecific: (json['regionSpecific'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
      graphDisplay: (json['graphDisplay'] as Map<String, dynamic>?) ?? {},
      inverseKey: json['inverseKey'] as String?,
      inverseKeyFemale: json['inverseKeyFemale'] as String?,
      inverseKeyNeutral: json['inverseKeyNeutral'] as String?,
    );
  }
}

/// Loads and queries indian_kinship.json from the downloaded file.
class KinshipJsonService {
  Map<String, dynamic>? _data;
  final Map<String, KinshipEntry> _byKey = {};
  final _logger = Logger();

  /// Load JSON from the downloaded file path.
  Future<void> initialize(String jsonPath) async {
    try {
      final file = File(jsonPath);
      if (!file.existsSync()) {
        throw Exception('JSON file not found: $jsonPath');
      }

      final jsonString = await file.readAsString();
      _data = json.decode(jsonString) as Map<String, dynamic>;

      // Index all relationships by key for O(1) lookup
      final relationships = _data!['relationships'] as List<dynamic>;
      for (final rel in relationships) {
        final entry = KinshipEntry.fromJson(rel as Map<String, dynamic>);
        _byKey[entry.relationshipKey] = entry;
      }

      _logger.i(
          'KinshipJsonService loaded: ${_byKey.length} relationships from $jsonPath');
    } catch (e) {
      _logger.e('Failed to load kinship JSON: $e');
      rethrow;
    }
  }

  /// Whether the JSON data is loaded and ready.
  bool get isReady => _data != null && _byKey.isNotEmpty;

  /// Get the full relationship entry by key.
  KinshipEntry? getRelationship(String key) {
    return _byKey[key];
  }

  /// Get display name for a relationship key in the specified language.
  ///
  /// Falls back to English term if the language is not found.
  String getDisplayName(String key, String language) {
    final entry = _byKey[key];
    if (entry == null) return key;

    // Try displayNames from the entry first (inline translations)
    // Then try the top-level translations object
    if (_data != null) {
      final translations = _data!['translations'] as Map<String, dynamic>?;
      if (translations != null && translations.containsKey(key)) {
        final langData = translations[key] as Map<String, dynamic>;
        if (langData.containsKey(language)) {
          final native = (langData[language] as Map<String, dynamic>)['native'];
          if (native is String && native.isNotEmpty) {
            return native;
          }
        }
      }
    }

    // Fall back to Hindi specific term, then English
    return entry.hindiSpecificTerm ?? entry.englishTerm;
  }

  /// Get graph display metadata for a relationship key.
  Map<String, dynamic>? getGraphDisplay(String key) {
    return _byKey[key]?.graphDisplay;
  }

  /// Get the inverse key for a relationship.
  ///
  /// [gender] can be 'male', 'female', or 'neutral'.
  String? getInverseKey(String key, {String gender = 'male'}) {
    final entry = _byKey[key];
    if (entry == null) return null;

    switch (gender) {
      case 'female':
        return entry.inverseKeyFemale ?? entry.inverseKey;
      case 'neutral':
        return entry.inverseKeyNeutral ?? entry.inverseKey;
      default:
        return entry.inverseKey;
    }
  }

  /// Get all relationships of a given category.
  List<KinshipEntry> getByCategory(String category) {
    return _byKey.values
        .where((e) => _getCategory(e) == category)
        .toList();
  }

  /// Get all relationships of a given lineage.
  List<KinshipEntry> getByLineage(String lineage) {
    return _byKey.values.where((e) => e.lineage == lineage).toList();
  }

  /// Get all relationships at a given generation.
  List<KinshipEntry> getByGeneration(int generation) {
    return _byKey.values.where((e) => e.generation == generation).toList();
  }

  /// Search relationships by keyword (matches key, englishTerm, or hindiSpecificTerm).
  List<KinshipEntry> search(String query, {int limit = 20}) {
    final q = query.toLowerCase();
    final results = <KinshipEntry>[];

    for (final entry in _byKey.values) {
      if (entry.relationshipKey.toLowerCase().contains(q) ||
          entry.englishTerm.toLowerCase().contains(q) ||
          (entry.hindiSpecificTerm?.toLowerCase().contains(q) ?? false)) {
        results.add(entry);
        if (results.length >= limit) break;
      }
    }

    return results;
  }

  /// Get the total number of loaded relationships.
  int get count => _byKey.length;

  /// Get all relationship keys.
  Iterable<String> get allKeys => _byKey.keys;

  String? _getCategory(KinshipEntry entry) {
    // The category is stored in the JSON but not parsed into KinshipEntry
    // for memory efficiency. Access it from the raw data if needed.
    if (_data == null) return null;
    final relationships = _data!['relationships'] as List<dynamic>?;
    if (relationships == null) return null;
    for (final rel in relationships) {
      final r = rel as Map<String, dynamic>;
      if (r['relationshipKey'] == entry.relationshipKey) {
        return r['relationshipCategory'] as String?;
      }
    }
    return null;
  }
}
