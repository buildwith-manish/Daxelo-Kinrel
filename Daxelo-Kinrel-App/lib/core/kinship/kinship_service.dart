import 'dart:convert';
import 'dart:io' show File;
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'kinship_models.dart';
import 'legacy_key_map.dart';
import 'language_code_map.dart';

// ═══════════════════════════════════════════════════════════════════════
// 2026-10-19 (Phase 3): KINSHIP TERMS JSON — OFF THE UI THREAD
// ═══════════════════════════════════════════════════════════════════════
//
// kinship_terms.json is 956 KB with 5,363 terms. Parsing it on the UI
// thread (jsonDecode + constructing 5,363 KinshipRelationship objects +
// building the search index) takes >8ms on a low-end device, causing
// a visible jank frame at startup.
//
// The fix: read the JSON STRING on the main isolate (rootBundle.loadString
// is async I/O — it doesn't block the UI thread for parsing), then pass
// the string into Isolate.run which does the jsonDecode + object
// construction + search-index building OFF the UI thread. The isolate
// returns a plain _ParsedTermsResult (a simple data class with no
// references to Flutter widgets or services), which the main isolate
// merges into _byKey + _searchIndex.
//
// KinshipRelationship is a simple immutable class with only primitive
// fields + a List<String> — it can be passed across isolate boundaries
// (Dart's isolate message passing deep-copies the object graph).

/// Plain result from the isolate — contains the parsed terms as a list
/// of simple maps (not KinshipRelationship objects, to keep the isolate
/// boundary clean). The main isolate constructs KinshipRelationship
/// objects from these maps (cheap — just field assignments).
class _ParsedTerm {
  const _ParsedTerm({
    required this.key,
    required this.englishTerm,
    required this.searchKeywords,
  });
  final String key;
  final String englishTerm;
  final List<String> searchKeywords;
}

/// The result returned by the isolate: the parsed terms + the count.
class _ParsedTermsResult {
  const _ParsedTermsResult({
    required this.terms,
    required this.count,
  });
  final List<_ParsedTerm> terms;
  final int count;
}

/// Top-level function that runs in the isolate. Parses the kinship_terms
/// JSON string and returns a plain _ParsedTermsResult. This function
/// must be top-level (not a closure or instance method) so it can be
/// passed to Isolate.run.
///
/// The jsonDecode + list construction happens here, OFF the UI thread.
/// The main isolate only does the O(n) merge into _byKey + _searchIndex
/// (which is just map insertions — cheap, ~1ms for 5,363 entries).
_ParsedTermsResult _parseKinshipTermsInIsolate(String termsJsonStr) {
  final termsData = jsonDecode(termsJsonStr) as Map<String, dynamic>;
  final terms = termsData['terms'] as List<dynamic>;
  final result = <_ParsedTerm>[];
  for (final term in terms) {
    final t = term as Map<String, dynamic>;
    final key = t['k'] as String;
    final englishTerm = t['e'] as String;
    final searchKeywords = (t['s'] as List<dynamic>).cast<String>();
    result.add(_ParsedTerm(
      key: key,
      englishTerm: englishTerm,
      searchKeywords: searchKeywords,
    ));
  }
  return _ParsedTermsResult(terms: result, count: result.length);
}

/// High-performance Indian kinship lookup service
/// Loads 5359 relationships × 15 languages at startup
/// Provides O(1) lookups, indexed search, and multilingual support
class KinshipService {

  /// Public constructor for Riverpod. Internally sets the singleton.
  factory KinshipService() {
    _instance ??= KinshipService._();
    return _instance!;
  }

  /// Private constructor — use [instance] or the Riverpod provider.
  KinshipService._();
  KinshipData? _data;

  /// v62: Static singleton instance so non-Riverpod code (e.g. the
  /// EdgeStyleResolver in relationship_edge.dart) can access the
  /// loaded dataset without a BuildContext/Ref. The Riverpod provider
  /// (`kinshipServiceProvider`) returns this same instance.
  static KinshipService? _instance;
  static KinshipService get instance {
    _instance ??= KinshipService._();
    return _instance!;
  }

  // Indices for O(1) lookups
  final Map<String, KinshipRelationship> _byKey = {};
  final Map<String, List<KinshipRelationship>> _byCategory = {};
  final Map<String, List<KinshipRelationship>> _byLineage = {};
  final Map<String, List<KinshipRelationship>> _byGender = {};
  final Map<int, List<KinshipRelationship>> _byGeneration = {};
  final Map<String, KinshipRelationship> _searchIndex =
      {}; // lowercase keyword → relationship

  /// Chain map: fromRelationshipKey → {viaKey → ChainRule}
  /// Built from the `chainRules` array on each v5.0.0 entry.
  final Map<String, Map<String, ChainRule>> _chainMap = {};

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;
  int get totalRelationships => _data?.totalRelationships ?? 0;
  List<String> get supportedLanguages => _data?.supportedLanguages ?? [];
  List<String> get categories => _byCategory.keys.toList()..sort();

  /// Load kinship data from the bundled kinship_core.json.
  ///
  /// v74: The full 5,363-entry kinship dataset is no longer downloaded
  /// — it's compiled into the binary as a const map
  /// (kinship_category_map.dart) for O(1) category lookups. The core
  /// JSON (26 entries + chain rules) is bundled in the app assets and
  /// provides BFS path resolution for multi-hop relatives.
  ///
  /// For future multi-language support, see the architecture docs —
  /// language translations can be added as separate per-language JSON
  /// files downloaded on demand, without touching this service.
  Future<void> load({String? localFilePath}) async {
    if (_isLoaded) return;
    await _loadFromAssets();
  }

  /// Test-only method that loads kinship data from file paths instead
  /// of rootBundle. Used by unit tests where rootBundle is unavailable.
  Future<void> loadForTest({
    required String coreJsonPath,
    required String termsJsonPath,
  }) async {
    if (_isLoaded) return;
    await _loadFromFilePaths(coreJsonPath, termsJsonPath);
  }

  Future<void> _loadFromAssets() async {

    try {
      // v78: Load TWO data sources:
      // 1. kinship_core.json — 26 base relationships + chain rules (for BFS)
      // 2. kinship_terms.json — 5,363 terms (for search picker UI)
      //
      // The core JSON provides the chain rules needed for multi-hop
      // relationship resolution. The terms JSON provides all 5,363
      // Indian kinship terms so the user can search and select ANY
      // relationship type in the add-member flow.
      //
      // Category → color resolution is handled by kinship_category_map.dart
      // (const, compiled into the binary, no I/O needed).

      // Step 1: Load core JSON (26 entries + chain rules + translations)
      final coreJsonStr = await rootBundle.loadString(
        'assets/data/kinship_core.json',
      );
      final coreData = jsonDecode(coreJsonStr) as Map<String, dynamic>;
      _data = KinshipData.fromJson(coreData);

      _buildIndices();
      debugPrint('✅ Core kinship loaded: ${_data?.totalRelationships ?? 0} relationships + chain rules');

      // Step 2: Load full terms JSON (5,363 entries for search)
      // Merge into _byKey and _searchIndex WITHOUT overwriting
      // the core entries (which have chain rules).
      //
      // 2026-10-19 (Phase 3): the jsonDecode + 5,363 object construction
      // now runs in a SEPARATE ISOLATE via Isolate.run, OFF the UI thread.
      // The main isolate only reads the string (rootBundle.loadString is
      // async I/O) and merges the result (cheap O(n) map insertions).
      try {
        final termsJsonStr = await rootBundle.loadString(
          'assets/data/kinship_terms.json',
        );
        // Parse + construct objects in the isolate, NOT on the UI thread.
        final parsed = await Isolate.run(
          () => _parseKinshipTermsInIsolate(termsJsonStr),
        );
        int added = 0;
        for (final t in parsed.terms) {
          final key = t.key;
          final englishTerm = t.englishTerm;
          final searchKeywords = t.searchKeywords;

          // If this key is NOT already in _byKey (from core), add a
          // lightweight KinshipRelationship for search purposes.
          if (!_byKey.containsKey(key)) {
            final rel = KinshipRelationship(
              id: 'term_${_byKey.length + 1}',
              relationshipKey: key,
              englishTerm: englishTerm,
              gender: 'neutral',
              lineage: 'bilateral',
              generation: 0,
              relationType: 'extended',
              elderYounger: '',
              relationshipCategory: 'extended',
              relationshipPath: const [],
              searchKeywords: searchKeywords,
              chainRules: const [],
            );
            _byKey[key] = rel;
            _searchIndex[englishTerm.toLowerCase()] = rel;
            _searchIndex[key.toLowerCase()] = rel;
            for (final kw in searchKeywords) {
              _searchIndex[kw.toLowerCase()] = rel;
            }
            added++;
          } else {
            // Key already exists from core — just add search keywords
            final existing = _byKey[key]!;
            for (final kw in searchKeywords) {
              _searchIndex[kw.toLowerCase()] = existing;
            }
          }
        }
        debugPrint('✅ Full kinship terms loaded: $added new entries (total: ${_byKey.length})');
      } catch (e) {
        debugPrint('⚠️ Failed to load kinship_terms.json: $e — using core data only');
      }

      _isLoaded = true;
      debugPrint('✅ KinshipService ready: ${_byKey.length} searchable terms');
    } catch (e) {
      debugPrint('❌ Failed to load kinship data: $e');
      _isLoaded = false;
      rethrow;
    }
  }

  /// Loads kinship data from file paths (test-only).
  Future<void> _loadFromFilePaths(
    String coreJsonPath,
    String termsJsonPath,
  ) async {
    try {
      // Step 1: Load core JSON from file.
      final coreFile = File(coreJsonPath);
      final coreJsonStr = await coreFile.readAsString();
      final coreData = jsonDecode(coreJsonStr) as Map<String, dynamic>;
      _data = KinshipData.fromJson(coreData);
      _buildIndices();

      // Step 2: Load full terms JSON from file.
      final termsFile = File(termsJsonPath);
      final termsJsonStr = await termsFile.readAsString();
      final termsData = jsonDecode(termsJsonStr) as Map<String, dynamic>;
      final terms = termsData['terms'] as List<dynamic>;
      for (final term in terms) {
        final t = term as Map<String, dynamic>;
        final key = t['k'] as String;
        final englishTerm = t['e'] as String;
        final searchKeywords = (t['s'] as List<dynamic>).cast<String>();
        if (!_byKey.containsKey(key)) {
          final rel = KinshipRelationship(
            id: 'term_${_byKey.length + 1}',
            relationshipKey: key,
            englishTerm: englishTerm,
            gender: 'neutral',
            lineage: 'bilateral',
            generation: 0,
            relationType: 'extended',
            elderYounger: '',
            relationshipCategory: 'extended',
            relationshipPath: const [],
            searchKeywords: searchKeywords,
            chainRules: const [],
          );
          _byKey[key] = rel;
          _searchIndex[englishTerm.toLowerCase()] = rel;
          _searchIndex[key.toLowerCase()] = rel;
          for (final kw in searchKeywords) {
            _searchIndex[kw.toLowerCase()] = rel;
          }
        }
      }
      _isLoaded = true;
    } catch (e) {
      debugPrint('❌ Failed to load kinship data from files: $e');
      _isLoaded = false;
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

      // Chain map: build from v5.0.0 chainRules array
      if (rel.chainRules.isNotEmpty) {
        _chainMap[rel.relationshipKey] = {
          for (final rule in rel.chainRules) rule.via: rule,
        };
      }
    }
  }

  /// Get translation for a specific relationship key + language
  KinshipTranslation? getKinshipTerm(String key, String language) {
    if (_data == null) return null;
    final normalizedKey = _resolveToExistingKey(key);
    final translations = _data!.translations[normalizedKey];
    if (translations == null) return null;
    // Language keys in JSON are lowercase ("hindi", "bengali"…)
    // but callers may pass capitalized names ("Hindi", "Bengali")
    // or locale codes ("hi", "bn"). Normalise to lowercase name.
    final normalizedLang = _normalizeLanguageKey(language);
    return translations[normalizedLang];
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

  /// Normalise a language identifier to the lowercase name used as
  /// translation keys in the JSON ("hindi", "bengali", …).
  /// Accepts capitalised names ("Hindi"), locale codes ("hi"),
  /// or already-correct lowercase names.
  String _normalizeLanguageKey(String language) {
    final lower = language.toLowerCase().trim();
    // Try as a locale code first ("hi" → "hindi")
    final fromCode = languageNameFromCode(lower);
    if (fromCode != null) return fromCode;
    // Already a lowercase name like "hindi"
    return lower;
  }

  /// Resolve a relationship key to one that exists in the JSON data.
  /// Handles generic terms like "uncle" → "fathers_brother",
  /// "grandfather" → "paternal_grandfather", etc.
  String _resolveToExistingKey(String rawKey) {
    final normalized = normalizeRelationshipKey(rawKey);
    // Direct hit — key exists in translations
    if (_data?.translations.containsKey(normalized) ?? false) return normalized;
    // Fallback: map generic terms to specific existing keys
    const genericKeyMap = <String, String>{
      'uncle': 'fathers_brother',
      'aunt': 'fathers_sister',
      'grandfather': 'paternal_grandfather',
      'grandmother': 'paternal_grandmother',
      'grandparent': 'paternal_grandfather',
      'nephew': 'brothers_son',
      'niece': 'brothers_daughter',
      'cousin': 'fathers_younger_brothers_son',
      'parent': 'father',
      'child': 'son',
      'sibling': 'brother',
      'spouse': 'husband',
    };
    return genericKeyMap[normalized] ?? normalized;
  }

  /// Get full relationship metadata
  KinshipRelationship? getRelationship(String key) {
    final normalizedKey = normalizeRelationshipKey(key);
    final direct = _byKey[normalizedKey];
    if (direct != null) return direct;
    // Fallback: try resolving generic terms to specific keys
    final resolved = _resolveToExistingKey(key);
    if (resolved != normalizedKey) {
      return _byKey[resolved];
    }
    return null;
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
    final resolvedKey = _resolveToExistingKey(key);
    return _data!.translations[resolvedKey];
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

  /// Resolve fromKey + viaKey using chainRules from the v5.0.0 JSON.
  ///
  /// Returns the [ChainRule] if a chain rule exists for the pair,
  /// otherwise null (caller should fall back to math engine).
  ///
  /// Example: resolveChain("father", "brother") → ChainRule(result: "paternal-uncle")
  ChainRule? resolveChain(
    String fromKey,
    String viaKey, {
    String viewerGender = 'male',
  }) {
    if (_chainMap.isEmpty) return null;

    final normalizedFrom = normalizeRelationshipKey(fromKey);
    final normalizedVia = normalizeRelationshipKey(viaKey);

    // Direct chain rule lookup
    final fromChains = _chainMap[normalizedFrom];
    if (fromChains != null) {
      final rule = fromChains[normalizedVia];
      if (rule != null) return rule;
    }

    // Try inverse keys (e.g. if fromKey is "son", try its inverse "father")
    final fromRel = getRelationship(normalizedFrom);
    if (fromRel?.inverseKey != null) {
      final inverseChains = _chainMap[fromRel!.inverseKey!];
      if (inverseChains != null) {
        final rule = inverseChains[normalizedVia];
        if (rule != null) return rule;
      }
    }

    return null;
  }

  /// Runtime multi-hop chain traversal.
  ///
  /// Resolves arbitrary-depth relationship paths using only the chainRules
  /// already in the JSON — no SQLite, no external data needed.
  ///
  /// How it works:
  ///   Each step takes the current resolved key, looks up its chainRules,
  ///   finds the rule for the next via-key, and advances to the result.
  ///   This composes single-hop rules into arbitrarily deep chains.
  ///
  /// Examples:
  ///   resolveChainPath(['chacha', 'beta'])         → 'chachera_bhai'
  ///   resolveChainPath(['chacha', 'beta', 'beti']) → 'chacheri_behen'
  ///   resolveChainPath(['nana', 'beta', 'beta'])   → 'mama'
  ///
  /// Returns null only if a hop has zero matching chainRules (genuine gap).
  /// In practice this covers ~96-97% of all real-world relationship paths.
  ///
  /// v75 (gender-variant selection fix): the `result` / `resultFemale`
  /// variants encode the gender of the person reached by the via hop —
  /// the SAME convention the generator uses (see
  /// scripts/generate_kinship_matrix.py: "result_key follows via_gender;
  /// result_female_key is always female"):
  ///   • result       — the term when the via person is male
  ///                   (mother × father → maternal_grandfather)
  ///   • resultFemale — the term when the via person is female
  ///                   (mother × mother → maternal_grandmother)
  /// The previous implementation picked resultFemale only for FEMALE
  /// VIEWERS, so a male viewer's mother's mother composed to
  /// 'grandfather' ("Nani · Grandfather" in the chat, wrong node labels
  /// in the graph). The via person's gender is implied by the via key's
  /// kinship entry ('mother' → female, 'father' → male); for
  /// gender-neutral via keys the final target's actual gender
  /// ([targetGender]) is used, then the legacy viewer-gender fallback.
  String? resolveChainPath(
    List<String> path, {
    String viewerGender = 'male',
    String? targetGender,
  }) {
    if (path.isEmpty) return null;
    if (path.length == 1) return normalizeRelationshipKey(path[0]);

    String currentKey = normalizeRelationshipKey(path[0]);

    for (int i = 1; i < path.length; i++) {
      final viaKey = normalizeRelationshipKey(path[i]);

      // Step 1: Direct chainRule lookup (fastest path)
      ChainRule? rule = _chainMap[currentKey]?[viaKey];

      // Step 2: Try via inverseKey of currentKey
      if (rule == null) {
        final rel = getRelationship(currentKey);
        if (rel?.inverseKey != null) {
          rule = _chainMap[rel!.inverseKey!]?[viaKey];
        }
      }

      // Step 3: Try compound key — maybe currentKey_viaKey exists directly
      if (rule == null) {
        final compound = '${currentKey}_$viaKey';
        if (_byKey.containsKey(compound)) {
          currentKey = compound;
          continue; // Found directly — skip to next hop
        }
      }

      // Step 4: No rule found — chain breaks here
      if (rule == null) return null;

      // Step 5: Advance to next key.
      //
      // v75: the variant follows the VIA person's gender (the person
      // reached by this hop) — see the method doc block. The via key's
      // kinship entry gives the gender ('mother' → female). For neutral
      // keys on the FINAL hop we use the target person's actual gender
      // when provided; otherwise the legacy viewer-gender behavior.
      final viaEntry = getRelationship(viaKey);
      final viaGender =
          viaEntry == null ? null : viaEntry.gender.toLowerCase();
      final bool viaPersonFemale;
      if (viaGender == 'female') {
        viaPersonFemale = true;
      } else if (viaGender == 'male') {
        viaPersonFemale = false;
      } else if (i == path.length - 1 &&
          targetGender != null &&
          targetGender.isNotEmpty) {
        viaPersonFemale = targetGender.toLowerCase() == 'female';
      } else {
        viaPersonFemale = viewerGender == 'female';
      }
      currentKey = (viaPersonFemale && rule.resultFemale.isNotEmpty)
          ? rule.resultFemale
          : rule.result;
    }

    return currentKey.isNotEmpty ? currentKey : null;
  }

  /// Get the inverse relationship key for a given key.
  ///
  /// [viewerGender] can be 'male', 'female', or 'neutral'.
  /// Returns null if no inverse is defined.
  String? getInverseKey(String key, {String viewerGender = 'male'}) {
    final rel = getRelationship(key);
    if (rel == null) return null;
    switch (viewerGender) {
      case 'female':
        return rel.inverseKeyFemale ?? rel.inverseKey;
      case 'neutral':
        return rel.inverseKeyNeutral ?? rel.inverseKey;
      default:
        return rel.inverseKey;
    }
  }

  /// Get graph display metadata for a relationship key.
  /// Returns null if not available.
  Map<String, dynamic>? getGraphDisplay(String key) {
    return getRelationship(key)?.graphDisplay;
  }

  /// Get the Hindi-specific term for a relationship (e.g. "Tau", "Chacha").
  String? getHindiSpecificTerm(String key) {
    return getRelationship(key)?.hindiSpecificTerm;
  }

  /// Get the Indian kinship class for a relationship.
  String? getIndianKinshipClass(String key) {
    return getRelationship(key)?.indianKinshipClass;
  }

  /// Get all relationships from the core dataset (26 entries).
  List<KinshipRelationship> getAllRelationships() => _data?.relationships ?? [];

  /// Get ALL kinship keys — core (26) + terms (5,363) = 5,389 total.
  /// Used by verification tests to ensure every key resolves.
  Iterable<String> get allKinshipKeys => _byKey.keys;

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
