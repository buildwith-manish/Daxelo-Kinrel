// lib/services/kinship_resolver.dart
//
// DAXELO KINREL — Kinship Resolver
//
// Main entry point for kinship chain resolution.
// Combines SQLite (full accuracy) + JSON (metadata) + math fallback (offline).
//
// Resolution order:
//   1. SQLite (local, O(1), 100% accuracy) → return if found
//   2. Math fallback if SQLite not ready
//   3. Never returns null

import 'package:logger/logger.dart';
import 'kinship_sqlite_service.dart';
import 'kinship_json_service.dart';
import 'kinship_math_fallback.dart';

/// A resolved kinship result with metadata about which engine was used.
class ResolvedKinship {
  final String resultKey;
  final String resultFemaleKey;
  final ResolutionSource source;

  const ResolvedKinship({
    required this.resultKey,
    required this.resultFemaleKey,
    required this.source,
  });

  @override
  String toString() =>
      'ResolvedKinship(resultKey: $resultKey, resultFemaleKey: $resultFemaleKey, source: $source)';
}

/// Which resolution engine produced the result.
enum ResolutionSource {
  sqlite, // From the downloaded SQLite database (100% accuracy)
  mathFallback, // From the pure-Dart math engine (~85% accuracy)
  json, // From the JSON metadata (for inverse lookups)
}

/// Main resolver — combines SQLite + JSON + fallback.
class KinshipResolver {
  final KinshipSqliteService _sqlite;
  final KinshipJsonService _json;
  final KinshipMathFallback _fallback = KinshipMathFallback();
  final _logger = Logger();

  KinshipResolver({
    KinshipSqliteService? sqlite,
    KinshipJsonService? json,
  })  : _sqlite = sqlite ?? KinshipSqliteService(),
        _json = json ?? KinshipJsonService();

  /// Initialize the SQLite service with the downloaded DB path.
  Future<void> initializeSqlite(String dbPath) async {
    await _sqlite.initialize(dbPath);
  }

  /// Initialize the JSON service with the downloaded JSON path.
  Future<void> initializeJson(String jsonPath) async {
    await _json.initialize(jsonPath);
  }

  /// Whether both SQLite and JSON are loaded.
  bool get isFullyReady => _sqlite.isReady && _json.isReady;

  /// Whether the SQLite DB is ready (full accuracy mode).
  bool get isSqliteReady => _sqlite.isReady;

  /// Whether the JSON is loaded (metadata available).
  bool get isJsonReady => _json.isReady;

  /// Resolve a kinship chain: given (fromKey, viaKey), return the result.
  ///
  /// [viewerGender] can be 'male' or 'female' to get the appropriate result.
  Future<ResolvedKinship> resolve(
    String fromKey,
    String viaKey, {
    String viewerGender = 'male',
  }) async {
    // 1. Try SQLite first (full accuracy)
    if (_sqlite.isReady) {
      final result = await _sqlite.queryChain(fromKey, viaKey);
      if (result != null) {
        return ResolvedKinship(
          resultKey: viewerGender == 'female'
              ? result.resultFemaleKey
              : result.resultKey,
          resultFemaleKey: result.resultFemaleKey,
          source: ResolutionSource.sqlite,
        );
      }
    }

    // 2. Fall back to math engine
    final mathResult = _fallback.resolve(fromKey, viaKey);
    return ResolvedKinship(
      resultKey: viewerGender == 'female'
          ? mathResult.resultFemaleKey
          : mathResult.resultKey,
      resultFemaleKey: mathResult.resultFemaleKey,
      source: ResolutionSource.mathFallback,
    );
  }

  /// Batch resolve multiple (from, via) pairs at once.
  ///
  /// Returns a map keyed by "$fromKey:$viaKey" → ResolvedKinship.
  Future<Map<String, ResolvedKinship>> resolveBatch(
    List<(String, String)> pairs, {
    String viewerGender = 'male',
  }) async {
    final results = <String, ResolvedKinship>{};

    // Try SQLite batch first
    if (_sqlite.isReady) {
      final sqliteResults = await _sqlite.queryBatch(pairs);
      for (final entry in sqliteResults.entries) {
        final parts = entry.key.split(':');
        if (parts.length >= 2) {
          results[entry.key] = ResolvedKinship(
            resultKey: viewerGender == 'female'
                ? entry.value.resultFemaleKey
                : entry.value.resultKey,
            resultFemaleKey: entry.value.resultFemaleKey,
            source: ResolutionSource.sqlite,
          );
        }
      }
    }

    // Fill in missing pairs with math fallback
    for (final (fromKey, viaKey) in pairs) {
      final key = '$fromKey:$viaKey';
      if (!results.containsKey(key)) {
        final mathResult = _fallback.resolve(fromKey, viaKey);
        results[key] = ResolvedKinship(
          resultKey: viewerGender == 'female'
              ? mathResult.resultFemaleKey
              : mathResult.resultKey,
          resultFemaleKey: mathResult.resultFemaleKey,
          source: ResolutionSource.mathFallback,
        );
      }
    }

    return results;
  }

  /// Get the display name for a relationship key in the specified language.
  /// Requires JSON to be loaded.
  String getDisplayName(String key, String language) {
    if (_json.isReady) {
      return _json.getDisplayName(key, language);
    }
    return key;
  }

  /// Get the inverse key for a relationship.
  String? getInverseKey(String key, {String gender = 'male'}) {
    if (_json.isReady) {
      return _json.getInverseKey(key, gender: gender);
    }
    return null;
  }

  /// Get graph display metadata for a relationship.
  Map<String, dynamic>? getGraphDisplay(String key) {
    if (_json.isReady) {
      return _json.getGraphDisplay(key);
    }
    return null;
  }

  /// Close all resources.
  Future<void> dispose() async {
    await _sqlite.close();
  }
}
