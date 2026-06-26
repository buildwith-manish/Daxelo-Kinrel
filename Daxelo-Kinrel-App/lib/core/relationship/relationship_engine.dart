// lib/core/relationship/relationship_engine.dart
//
// DAXELO KINREL v2.2 — Viewer-Driven Relationship Engine
//
// Calculates relationship labels from the VIEWER's perspective.
// Accepts viewerPersonId + targetPersonId and returns the kinship key
// (e.g., "father", "mothers_brother", "paternal_grandfather").
//
// Architecture:
//   - Uses GraphService BFS for path finding (does NOT reimplement BFS)
//   - Uses KinshipService for key → display name translation
//   - Caches results per (viewerPersonId, targetPersonId) pair
//   - No UI logic, no localization — keys only
//
// The Graph Engine calls this to get edge labels. The UI calls this
// to get node relation labels. Neither computes kinship themselves.

import 'package:flutter/foundation.dart';

import '../graph/graph_service.dart';
import '../kinship/kinship_service.dart';
import '../services/graph_layout_service.dart' show GraphPerson;

/// Computes relationship keys from a viewer's perspective.
///
/// This is the single source of truth for all relationship labels.
/// The graph engine, node widgets, and info sheets all call this
/// engine — none compute kinship themselves.
class RelationshipEngine {
  RelationshipEngine._();
  static final RelationshipEngine instance = RelationshipEngine._();

  /// Cache: `(viewerPersonId, targetPersonId) → relationshipKey`
  final Map<String, String?> _keyCache = {};

  /// Cache: `(viewerPersonId, targetPersonId) → List<PathStep>`
  final Map<String, List<PathStep>?> _pathCache = {};

  /// Returns the relationship key from the viewer's perspective to the target.
  ///
  /// Example: viewerPersonId=Son, targetPersonId=Father → "father"
  ///
  /// Returns null if:
  /// - viewerPersonId == targetPersonId (self — UI shows "You")
  /// - No path exists between viewer and target
  /// - The path cannot be resolved to a kinship key
  String? resolveKey({
    required String? viewerPersonId,
    required String targetPersonId,
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
  }) {
    // Self — no relationship key needed (UI shows "You")
    if (viewerPersonId == targetPersonId) return null;

    if (viewerPersonId == null) {
      // No viewer — fall back to old behavior (use stored relationshipKey)
      return _getStoredKey(targetPersonId, persons, relationships);
    }

    final cacheKey = '${viewerPersonId}_$targetPersonId';
    if (_keyCache.containsKey(cacheKey)) {
      return _keyCache[cacheKey];
    }

    // Use GraphService BFS to find the path
    final graphService = GraphService(KinshipService.instance);
    final pathResult = graphService.findPath(
      persons: persons,
      relationships: relationships,
      fromPersonId: viewerPersonId,
      toPersonId: targetPersonId,
    );

    if (pathResult == null) {
      _keyCache[cacheKey] = null;
      return null;
    }

    // Extract the relationship types from the path steps
    final pathTypes = pathResult.path.map((step) => step.type).toList();

    // Try to compose a kinship key from the path
    final key = _composeKey(pathTypes, viewerPersonId, targetPersonId, persons);

    _keyCache[cacheKey] = key;
    _pathCache[cacheKey] = pathResult.path;

    return key;
  }

  /// Returns the path steps between viewer and target.
  List<PathStep>? resolvePath({
    required String? viewerPersonId,
    required String targetPersonId,
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
  }) {
    if (viewerPersonId == null || viewerPersonId == targetPersonId) {
      return null;
    }

    final cacheKey = '${viewerPersonId}_$targetPersonId';
    if (_pathCache.containsKey(cacheKey)) {
      return _pathCache[cacheKey];
    }

    final graphService = GraphService(KinshipService.instance);
    final pathResult = graphService.findPath(
      persons: persons,
      relationships: relationships,
      fromPersonId: viewerPersonId,
      toPersonId: targetPersonId,
    );

    _pathCache[cacheKey] = pathResult?.path;
    return pathResult?.path;
  }

  /// Composes a kinship key from a path of relationship types.
  ///
  /// Path examples:
  ///   ["father"] → "father"
  ///   ["father", "brother"] → "fathers_brother"
  ///   ["father", "father"] → "paternal_grandfather"
  ///   ["spouse"] → "wife" (resolved by gender)
  String? _composeKey(
    List<String> pathTypes,
    String viewerPersonId,
    String targetPersonId,
    List<GraphPerson> persons,
  ) {
    if (pathTypes.isEmpty) return null;

    // Single-step path — return the type directly
    if (pathTypes.length == 1) {
      return _resolveSingleStepKey(pathTypes.first, targetPersonId, persons);
    }

    // Multi-step path — try KinshipService.resolvePathToKey first
    try {
      final kinship = KinshipService.instance;
      if (kinship.isLoaded) {
        final resolved = kinship.resolvePathToKey(pathTypes);
        if (resolved != null) {
          return resolved.relationshipKey;
        }
      }
    } catch (e) {
      debugPrint('⚠️ RelationshipEngine: kinship resolve failed: $e');
    }

    // Fallback: compose a compound key (e.g., "fathers_brother")
    final parts = pathTypes.map((type) {
      // Convert direction-aware types to base form
      switch (type) {
        case 'father':
        case 'mother':
        case 'parent':
          return type;
        case 'son':
        case 'daughter':
        case 'child':
          return type;
        case 'brother':
        case 'sister':
        case 'sibling':
          return type;
        case 'husband':
        case 'wife':
        case 'spouse':
          return type;
        default:
          return type;
      }
    }).toList();

    // Join with underscores: ["father", "brother"] → "fathers_brother"
    // (pluralize the first part: "father" → "fathers")
    if (parts.length == 2) {
      final first = _pluralize(parts[0]);
      return '${first}_${parts[1]}';
    }

    // For longer paths, join all with underscores (pluralized except last)
    final result = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i < parts.length - 1) {
        result.write(_pluralize(parts[i]));
        result.write('_');
      } else {
        result.write(parts[i]);
      }
    }
    return result.toString();
  }

  /// Resolves a single-step relationship type to a gender-specific key.
  ///
  /// "parent" → "father" or "mother" (based on target's gender)
  /// "child" → "son" or "daughter"
  /// "sibling" → "brother" or "sister"
  /// "spouse" → "husband" or "wife"
  String? _resolveSingleStepKey(
    String type,
    String targetPersonId,
    List<GraphPerson> persons,
  ) {
    final target = persons.where((p) => p.id == targetPersonId).firstOrNull;
    final gender = target?.gender?.toLowerCase();

    switch (type) {
      case 'parent':
      case 'father':
      case 'mother':
        return gender == 'female' ? 'mother' : 'father';
      case 'child':
      case 'son':
      case 'daughter':
        return gender == 'female' ? 'daughter' : 'son';
      case 'sibling':
      case 'brother':
      case 'sister':
        return gender == 'female' ? 'sister' : 'brother';
      case 'spouse':
      case 'husband':
      case 'wife':
        return gender == 'female' ? 'wife' : 'husband';
      default:
        return type;
    }
  }

  /// Pluralizes a kinship term for compound keys.
  /// "father" → "fathers", "mother" → "mothers", "brother" → "brothers"
  String _pluralize(String term) {
    if (term.endsWith('s')) return term;
    if (term.endsWith('y') && !term.endsWith('ay')) {
      return '${term.substring(0, term.length - 1)}ies';
    }
    return '${term}s';
  }

  /// Returns the stored relationshipKey for a target person (legacy fallback).
  /// Used when no viewerPersonId is available.
  String? _getStoredKey(
    String targetPersonId,
    List<GraphPerson> persons,
    List<({String fromId, String toId, String type})> relationships,
  ) {
    // Find any relationship involving this person
    for (final rel in relationships) {
      if (rel.toId == targetPersonId) {
        return rel.type;
      }
      if (rel.fromId == targetPersonId) {
        // Return inverse
        return _inverseKey(rel.type);
      }
    }
    return null;
  }

  /// Returns the inverse of a relationship key.
  String? _inverseKey(String key) {
    const inverseMap = <String, String>{
      'father': 'child',
      'mother': 'child',
      'parent': 'child',
      'child': 'parent',
      'son': 'parent',
      'daughter': 'parent',
      'brother': 'sibling',
      'sister': 'sibling',
      'spouse': 'spouse',
      'husband': 'wife',
      'wife': 'husband',
    };
    return inverseMap[key] ?? key;
  }

  /// Invalidates all cached results.
  void invalidateCache() {
    _keyCache.clear();
    _pathCache.clear();
  }

  /// Invalidates cached results for a specific viewer.
  void invalidateViewer(String viewerPersonId) {
    _keyCache.removeWhere((key, _) => key.startsWith('${viewerPersonId}_'));
    _pathCache.removeWhere((key, _) => key.startsWith('${viewerPersonId}_'));
  }
}
