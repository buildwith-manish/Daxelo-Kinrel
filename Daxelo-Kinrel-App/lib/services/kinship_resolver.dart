// lib/services/kinship_resolver.dart
//
// DAXELO KINREL — Kinship Resolver
//
// Main entry point for kinship chain resolution.
// Uses chainRules from the v5.0.0 JSON (O(1) lookup, 95-98% accuracy)
// with a pure-Dart math fallback (~85% accuracy) for cases not covered
// by chain rules.
//
// Resolution order:
//   1. KinshipService chainRules (from JSON, O(1)) → 95-98% accuracy
//   2. Math fallback → 85% accuracy
//   3. 'relative' fallback → always returns something

import '../core/kinship/kinship_service.dart';
import '../core/kinship/kinship_models.dart';
import 'kinship_math_fallback.dart';

/// Which resolution engine produced the result.
enum ResolutionSource {
  chainRule, // From JSON chainRules (highest accuracy)
  math, // From pure-Dart math fallback
  fallback, // Generic 'relative' fallback
}

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

/// Main resolver — combines chainRules + math fallback.
///
/// No SQLite database needed. All resolution is done in-memory using
/// the chainRules array from the loaded JSON.
class KinshipResolver {
  final KinshipMathFallback _fallback = KinshipMathFallback();

  /// Whether the KinshipService has loaded data (either core or full JSON).
  bool get isReady => KinshipService.instance.isLoaded;

  /// Resolve a kinship chain: given (fromKey, viaKey), return the result.
  ///
  /// [viewerGender] can be 'male' or 'female' to get the appropriate result.
  ResolvedKinship resolve(
    String fromKey,
    String viaKey, {
    String viewerGender = 'male',
  }) {
    final kinship = KinshipService.instance;

    // 1. Try chainRules from JSON (O(1) lookup, highest accuracy)
    if (kinship.isLoaded) {
      final rule = kinship.resolveChain(
        fromKey,
        viaKey,
        viewerGender: viewerGender,
      );
      if (rule != null) {
        return ResolvedKinship(
          resultKey: viewerGender == 'female'
              ? rule.resultFemale
              : rule.result,
          resultFemaleKey: rule.resultFemale,
          source: ResolutionSource.chainRule,
        );
      }
    }

    // 2. Math fallback (~85% accuracy)
    final math = _fallback.resolve(fromKey, viaKey);
    if (math.resultKey != 'distant-relative') {
      return ResolvedKinship(
        resultKey: viewerGender == 'female'
            ? math.resultFemaleKey
            : math.resultKey,
        resultFemaleKey: math.resultFemaleKey,
        source: ResolutionSource.math,
      );
    }

    // 3. Generic fallback — never return null
    return const ResolvedKinship(
      resultKey: 'relative',
      resultFemaleKey: 'relative',
      source: ResolutionSource.fallback,
    );
  }

  /// Batch resolve multiple (from, via) pairs at once.
  ///
  /// Returns a map keyed by "$fromKey:$viaKey" → ResolvedKinship.
  Map<String, ResolvedKinship> resolveBatch(
    List<(String, String)> pairs, {
    String viewerGender = 'male',
  }) {
    return {
      for (final (from, via) in pairs)
        '$from:$via': resolve(from, via, viewerGender: viewerGender),
    };
  }

  /// Get the display name for a relationship key in the specified language.
  /// Uses KinshipService translations.
  String getDisplayName(String key, String language) {
    final kinship = KinshipService.instance;
    if (!kinship.isLoaded) return key;
    final translation = kinship.getKinshipTerm(key, language);
    return translation?.native ?? key;
  }

  /// Get the display name by locale code (e.g. 'hi' → Hindi name).
  String getDisplayNameByLocale(String key, String localeCode) {
    final kinship = KinshipService.instance;
    if (!kinship.isLoaded) return key;
    return kinship.getKinshipTermByLocale(key, localeCode) ?? key;
  }

  /// Get the inverse key for a relationship.
  String? getInverseKey(String key, {String viewerGender = 'male'}) {
    return KinshipService.instance.getInverseKey(
      key,
      viewerGender: viewerGender,
    );
  }

  /// Get graph display metadata for a relationship.
  Map<String, dynamic>? getGraphDisplay(String key) {
    return KinshipService.instance.getGraphDisplay(key);
  }

  /// Get the Hindi-specific term (e.g. "Tau", "Chacha").
  String? getHindiSpecificTerm(String key) {
    return KinshipService.instance.getHindiSpecificTerm(key);
  }
}
