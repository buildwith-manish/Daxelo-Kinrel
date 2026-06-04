import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'kinship_models.dart';
import 'legacy_key_map.dart';
import 'language_code_map.dart';

/// High-performance Indian kinship lookup service
/// Loads 5359 relationships × 15 languages at startup
/// Provides O(1) lookups, indexed search, and multilingual support
class KinshipService {
  KinshipData? _data;

  // Indices for O(1) lookups
  final Map<String, KinshipRelationship> _byKey = {};
  final Map<String, List<KinshipRelationship>> _byCategory = {};
  final Map<String, List<KinshipRelationship>> _byLineage = {};
  final Map<String, List<KinshipRelationship>> _byGender = {};
  final Map<int, List<KinshipRelationship>> _byGeneration = {};
  final Map<String, KinshipRelationship> _searchIndex =
      {}; // lowercase keyword → relationship

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;
  int get totalRelationships => _data?.totalRelationships ?? 0;
  List<String> get supportedLanguages => _data?.supportedLanguages ?? [];
  List<String> get categories => _byCategory.keys.toList()..sort();

  /// Load kinship data from JSON asset
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      final jsonStr = await rootBundle.loadString(
        'assets/data/indian_kinship.json',
      );
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      _data = KinshipData.fromJson(jsonData);

      _buildIndices();
      _isLoaded = true;
    } catch (e) {
      // Log the error but don't throw — allow the app to continue
      // with an empty dataset rather than crashing
      debugPrint('❌ Failed to load kinship data: $e');
      _isLoaded = false;
      // Re-throw so the UI can show an error state
      rethrow;
    }
  }

  void _buildIndices() {
    if (_data == null) return;

    for (final rel in _data!.relationships) {
      // By key
      _byKey[rel.relationshipKey] = rel;
      _byKey[rel.id] = rel; // Also index by id

      // By category
      (_byCategory[rel.relationshipCategory] ??= []).add(rel);

      // By lineage
      (_byLineage[rel.lineage] ??= []).add(rel);

      // By gender
      (_byGender[rel.gender] ??= []).add(rel);

      // By generation
      (_byGeneration[rel.generation] ??= []).add(rel);

      // Search index: english term, keywords, relationship key
      _searchIndex[rel.englishTerm.toLowerCase()] = rel;
      _searchIndex[rel.relationshipKey.toLowerCase()] = rel;
      for (final kw in rel.searchKeywords) {
        _searchIndex[kw.toLowerCase()] = rel;
      }
    }
  }

  /// Get translation for a specific relationship key + language
  KinshipTranslation? getKinshipTerm(String key, String language) {
    if (_data == null) return null;
    final normalizedKey = normalizeRelationshipKey(key);
    final translations = _data!.translations[normalizedKey];
    if (translations == null) return null;
    return translations[language];
  }

  /// Get translation by locale code (e.g., 'hi' → hindi)
  String? getKinshipTermByLocale(String key, String localeCode) {
    final language = languageNameFromCode(localeCode);
    if (language == null || language == 'english') {
      final rel = getRelationship(key);
      return rel?.englishTerm;
    }
    final translation = getKinshipTerm(key, language);
    return translation?.native;
  }

  /// Get full relationship metadata
  KinshipRelationship? getRelationship(String key) {
    final normalizedKey = normalizeRelationshipKey(key);
    return _byKey[normalizedKey];
  }

  /// Get all relationships in a category
  List<KinshipRelationship> getByCategory(String category) =>
      _byCategory[category] ?? [];

  /// Get all relationships by lineage
  List<KinshipRelationship> getByLineage(String lineage) =>
      _byLineage[lineage] ?? [];

  /// Get all relationships by gender
  List<KinshipRelationship> getByGender(String gender) =>
      _byGender[gender] ?? [];

  /// Get all relationships by generation
  List<KinshipRelationship> getByGeneration(int generation) =>
      _byGeneration[generation] ?? [];

  /// Get all translations for a relationship across all languages
  Map<String, KinshipTranslation>? getAllTranslations(String key) {
    if (_data == null) return null;
    final normalizedKey = normalizeRelationshipKey(key);
    return _data!.translations[normalizedKey];
  }

  /// Search relationships by query string
  /// Searches englishTerm, searchKeywords, relationshipKey
  /// Returns results sorted by relevance score
  List<KinshipSearchResult> search(String query) {
    if (query.isEmpty || _data == null) return [];

    final q = query.toLowerCase().trim();
    final results = <String, KinshipSearchResult>{};

    for (final rel in _data!.relationships) {
      double score = 0;
      String matchedField = '';

      // Exact key match (highest priority)
      if (rel.relationshipKey.toLowerCase() == q) {
        results[rel.relationshipKey] = KinshipSearchResult(
          relationship: rel,
          score: 100,
          matchedField: 'relationshipKey',
        );
        continue;
      }

      // English term contains query
      if (rel.englishTerm.toLowerCase().contains(q)) {
        final s = q.length / rel.englishTerm.length * 80;
        if (s > score) {
          score = s;
          matchedField = 'englishTerm';
        }
      }

      // Keywords match
      for (final kw in rel.searchKeywords) {
        if (kw.toLowerCase().contains(q)) {
          final s = q.length / kw.length * 60;
          if (s > score) {
            score = s;
            matchedField = 'searchKeyword';
          }
          break;
        }
      }

      // Key contains query
      if (rel.relationshipKey.toLowerCase().contains(q)) {
        final s = q.length / rel.relationshipKey.length * 40;
        if (s > score) {
          score = s;
          matchedField = 'relationshipKey';
        }
      }

      if (score > 0) {
        final existing = results[rel.relationshipKey];
        if (existing == null || existing.score < score) {
          results[rel.relationshipKey] = KinshipSearchResult(
            relationship: rel,
            score: score,
            matchedField: matchedField,
          );
        }
      }
    }

    final list = results.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  /// Resolve a path of relationships to a compound term
  /// e.g., ["father", "sister"] → fathers_sister
  KinshipRelationship? resolvePathToKey(List<String> path) {
    if (path.isEmpty || _data == null) return null;
    final pathKey = path.join('_');
    return _byKey[pathKey];
  }

  /// Get all relationships
  List<KinshipRelationship> getAllRelationships() => _data?.relationships ?? [];

  /// Get meta information about the kinship database
  Map<String, dynamic> getMeta() {
    if (_data == null) return {};
    return {
      'version': _data!.version,
      'generatedAt': _data!.generatedAt,
      'totalRelationships': _data!.totalRelationships,
      'supportedLanguages': _data!.supportedLanguages,
      'categories': categories,
    };
  }
}
