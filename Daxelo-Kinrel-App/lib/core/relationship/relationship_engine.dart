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
import '../kinship/kinship_edge_style.dart';
import '../kinship/kinship_service.dart';
import '../kinship/structural_kinship_classifier.dart';
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

  /// v66: Cache for full classifications (category + label + key).
  /// Used by resolveClassification() so we don't recompute the structural
  /// classifier on every call.
  final Map<String, StructuralClassification> _classificationCache = {};

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
    // v66: Delegate to resolveClassification and return just the key.
    // This ensures every caller benefits from the structural fallback.
    final classification = resolveClassification(
      viewerPersonId: viewerPersonId,
      targetPersonId: targetPersonId,
      persons: persons,
      relationships: relationships,
    );
    return classification?.key;
  }

  /// v66: Returns the FULL classification (category + label + key) from
  /// the viewer's perspective to the target.
  ///
  /// This is the primary API. It NEVER returns null for a reachable
  /// target — if the kinship chain rules can't resolve the path, the
  /// structural classifier provides a guaranteed fallback that routes
  /// to the correct KinshipEdgeCategory based on path structure alone.
  ///
  /// Returns null ONLY when:
  /// - viewerPersonId == targetPersonId (self — UI shows "You")
  /// - no path exists between viewer and target
  StructuralClassification? resolveClassification({
    required String? viewerPersonId,
    required String targetPersonId,
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
  }) {
    // Self — no classification needed (UI shows "You")
    if (viewerPersonId == targetPersonId) return null;

    final cacheKey = '${viewerPersonId}_$targetPersonId';
    if (_classificationCache.containsKey(cacheKey)) {
      return _classificationCache[cacheKey];
    }

    // No viewer — use structural classifier on the stored edge.
    if (viewerPersonId == null) {
      final storedKey = _getStoredKey(targetPersonId, persons, relationships);
      if (storedKey == null) return null;
      final target = persons.where((p) => p.id == targetPersonId).firstOrNull;
      final classification = StructuralKinshipClassifier.classify(
        path: [storedKey],
        targetGender: target?.gender,
      );
      _classificationCache[cacheKey] = classification;
      return classification;
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
      // No path — can't classify. Return null (node will show no label).
      return null;
    }

    // Extract the relationship types from the path steps.
    // CRITICAL: BFS path types represent the VIEWER's relationship TO each
    // step — e.g. if the stored edge is (Geetha → Yakshitha, 'mother'),
    // BFS from Yakshitha to Geetha produces step type 'child' (inverse of
    // 'mother'), meaning "viewer (Yakshitha) is a child of target (Geetha)".
    // To classify the TARGET's relationship to the viewer, we must INVERT
    // each path type so the classifier sees "Geetha is a parent of Yakshitha"
    // → returns 'Mother' instead of 'Daughter'.
    final pathTypes = pathResult.path.map((step) {
      return inverseType(step.type) ?? step.type;
    }).toList();

    // v66: Try the kinship chain rules first (high accuracy for known
    // compounds), then fall back to the structural classifier which
    // works for ANY path structure.
    final target = persons.where((p) => p.id == targetPersonId).firstOrNull;
    final viewer = persons.where((p) => p.id == viewerPersonId).firstOrNull;
    final viewerGender = (viewer?.gender?.toLowerCase() == 'female') ? 'female' : 'male';

    // Step 1: Try chain-rule composition (existing logic).
    final composedKey = _composeKey(pathTypes, viewerPersonId, targetPersonId, persons);

    // Step 2: If the composed key resolves to a known kinship
    // relationship, use it. Otherwise, use the structural classifier.
    StructuralClassification? classification;
    if (composedKey != null && composedKey.isNotEmpty) {
      final kinship = KinshipService.instance;
      final known = kinship.isLoaded ? kinship.getRelationship(composedKey) : null;
      if (known != null) {
        // The composed key is a real kinship term — classify it.
        classification = StructuralKinshipClassifier.classify(
          path: [composedKey],
          targetGender: target?.gender,
          viewerGender: viewerGender,
        );
      }
    }

    // Step 3: Structural fallback — works for ANY path, guaranteed.
    classification ??= StructuralKinshipClassifier.classify(
      path: pathTypes,
      targetGender: target?.gender,
      viewerGender: viewerGender,
    );

    _classificationCache[cacheKey] = classification;
    return classification;
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

    // Multi-step path — try resolveChainPath first (96-97% accuracy)
    // resolveChainPath composes chainRules at runtime for arbitrary depth.
    try {
      final kinship = KinshipService.instance;
      if (kinship.isLoaded) {
        // 1. Try runtime chain traversal (new — highest accuracy)
        final traversed = kinship.resolveChainPath(
          pathTypes,
          viewerGender: _getViewerGender(viewerPersonId, persons),
        );
        if (traversed != null && kinship.getRelationship(traversed) != null) {
          return traversed;
        }

        // 2. Try direct path key lookup (old — works for exact compound keys)
        final resolved = kinship.resolvePathToKey(pathTypes);
        if (resolved != null) {
          return resolved.relationshipKey;
        }
      }
    } catch (e) {
      debugPrint('⚠️ RelationshipEngine: kinship resolve failed: $e');
    }

    // v67 (BUG-7 FIX): Removed the pluralize fallback that produced
    // invalid keys like 'fathers_sibling'. The structural classifier
    // (called by resolveClassification) now handles ALL path structures
    // via generation-delta analysis, so this fallback is dead code that
    // only wasted cycles and produced keys that don't exist in the
    // kinship dataset.
    //
    // If neither chain rules nor the structural classifier can resolve
    // the path, return null — resolveClassification() will handle it.
    return null;
  }

  /// Returns the viewer's gender for use in gendered chain resolution.
  /// Defaults to 'male' if the viewer's person is not found or has no gender.
  String _getViewerGender(
    String? viewerPersonId,
    List<GraphPerson> persons,
  ) {
    if (viewerPersonId == null) return 'male';
    final viewer =
        persons.where((p) => p.id == viewerPersonId).firstOrNull;
    final gender = viewer?.gender?.toLowerCase();
    if (gender == 'female' || gender == 'f') return 'female';
    return 'male';
  }

  /// Resolves a single-step relationship type to a gender-specific key.
  ///
  /// "parent" → "father" or "mother" (based on target's gender)
  /// "child" → "son" or "daughter"
  /// "sibling" → "brother" or "sister"
  /// "spouse" → "husband" or "wife"
  ///
  /// Also resolves the gender-neutral intermediate inverse terms produced
  /// by [inverseTypeMap] in `graph_service.dart` (e.g. "sibling_child",
  /// "parent_sibling", "child_in_law") to their gendered final keys.
  String? _resolveSingleStepKey(
    String type,
    String targetPersonId,
    List<GraphPerson> persons,
  ) {
    final target = persons.where((p) => p.id == targetPersonId).firstOrNull;
    final gender = target?.gender?.toLowerCase();
    final isFemale = gender == 'female' || gender == 'f';

    switch (type) {
      // Standard single-step — resolve by target gender
      case 'parent':
      case 'father':
      case 'mother':
        return isFemale ? 'mother' : 'father';

      case 'child':
      case 'son':
      case 'daughter':
        return isFemale ? 'daughter' : 'son';

      case 'sibling':
      case 'brother':
      case 'sister':
        return isFemale ? 'sister' : 'brother';

      case 'spouse':
      case 'husband':
      case 'wife':
        return isFemale ? 'wife' : 'husband';

      case 'grandparent':
      case 'grandfather':
      case 'grandmother':
        return isFemale ? 'maternal_grandmother' : 'paternal_grandfather';

      case 'grandchild':
      case 'grandson':
      case 'granddaughter':
        return isFemale ? 'granddaughter' : 'grandson';

      // Intermediate inverse terms from inverseTypeMap
      case 'sibling_child':
        // uncle/aunt's perspective on nephews/nieces
        return isFemale ? 'niece' : 'nephew';

      case 'parent_sibling':
        // nephew/niece's perspective on uncles/aunts
        return isFemale ? 'aunt' : 'uncle';

      case 'child_in_law':
        return isFemale ? 'daughter_in_law' : 'son_in_law';

      case 'parent_in_law':
        return isFemale ? 'mother_in_law' : 'father_in_law';

      case 'sibling_in_law':
        return isFemale ? 'sister_in_law' : 'brother_in_law';

      case 'step_parent':
        return isFemale ? 'step_mother' : 'step_father';

      case 'step_child':
        return isFemale ? 'step_daughter' : 'step_son';

      case 'step_sibling':
        return isFemale ? 'step_sister' : 'step_brother';

      default:
        // Return the type as-is — may be a compound key already in KinshipService
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
  ///
  /// v67 (BUG-2 FIX): The previous version returned the key for ANY edge
  /// involving the target — without considering the anchor's perspective.
  /// This caused every node to get the INVERSE key (e.g. a father node
  /// got 'child' instead of 'father').
  ///
  /// The stored relationship `from: A, to: B, key: 'X'` means "A IS the X
  /// of B". From B's perspective, A IS 'X' (the stored key IS B's
  /// perspective on A). So:
  ///   - If `to == target`: the stored key IS the target's perspective
  ///     on `from`. Return the key DIRECTLY.
  ///   - If `from == target`: the target's perspective on `to` is the
  ///     INVERSE. Return the inverse key.
  String? _getStoredKey(
    String targetPersonId,
    List<GraphPerson> persons,
    List<({String fromId, String toId, String type})> relationships,
  ) {
    for (final rel in relationships) {
      // Edge points TO target: stored key IS target's perspective on `from`.
      if (rel.toId == targetPersonId) {
        return rel.type;
      }
      // Edge points FROM target: target's perspective is the INVERSE.
      if (rel.fromId == targetPersonId) {
        return _inverseKey(rel.type);
      }
    }
    return null;
  }

  /// Returns the inverse of a relationship key.
  ///
  /// v67 (BUG-3 FIX): Expanded from 11 entries to cover ALL common
  /// relationship types including grandparents, aunts/uncles, cousins,
  /// in-laws, and step relations. Previously, missing keys returned the
  /// key unchanged — causing wrong colors for siblings, cousins,
  /// grandparents, and in-laws in the no-viewer fallback path.
  String? _inverseKey(String key) {
    const inverseMap = <String, String>{
      // Core parent/child
      'father': 'child',
      'mother': 'child',
      'parent': 'child',
      'child': 'parent',
      'son': 'parent',
      'daughter': 'parent',

      // Siblings
      'brother': 'sibling',
      'sister': 'sibling',
      'sibling': 'sibling',
      'elder_brother': 'younger_sibling',
      'younger_brother': 'elder_sibling',
      'elder_sister': 'younger_sibling',
      'younger_sister': 'elder_sibling',
      'half_brother': 'half_brother',
      'half_sister': 'half_sister',

      // Spouses
      'spouse': 'spouse',
      'husband': 'wife',
      'wife': 'husband',
      'partner': 'partner',

      // Grandparents / grandchildren
      'grandfather': 'grandchild',
      'grandmother': 'grandchild',
      'grandparent': 'grandchild',
      'grandchild': 'grandparent',
      'grandson': 'grandparent',
      'granddaughter': 'grandparent',
      'paternal_grandfather': 'grandchild',
      'paternal_grandmother': 'grandchild',
      'maternal_grandfather': 'grandchild',
      'maternal_grandmother': 'grandchild',

      // Great-grandparents
      'great_grandfather': 'great_grandchild',
      'great_grandmother': 'great_grandchild',
      'great_grandparent': 'great_grandchild',
      'great_grandchild': 'great_grandparent',
      'great_grandson': 'great_grandparent',
      'great_granddaughter': 'great_grandparent',

      // Aunt/Uncle ↔ Nephew/Niece
      'uncle': 'nephew',
      'aunt': 'niece',
      'nephew': 'uncle',
      'niece': 'aunt',
      'paternal_uncle': 'nephew',
      'paternal_aunt': 'niece',
      'maternal_uncle': 'nephew',
      'maternal_aunt': 'niece',

      // Cousins (symmetric)
      'cousin': 'cousin',
      'cousin_brother': 'cousin_brother',
      'cousin_sister': 'cousin_sister',

      // In-laws
      'father_in_law': 'child_in_law',
      'mother_in_law': 'child_in_law',
      'son_in_law': 'parent_in_law',
      'daughter_in_law': 'parent_in_law',
      'brother_in_law': 'sibling_in_law',
      'sister_in_law': 'sibling_in_law',
      'parent_in_law': 'child_in_law',
      'child_in_law': 'parent_in_law',
      'sibling_in_law': 'sibling_in_law',

      // Step relations
      'step_father': 'step_child',
      'step_mother': 'step_child',
      'step_son': 'step_parent',
      'step_daughter': 'step_parent',
      'step_brother': 'step_sibling',
      'step_sister': 'step_sibling',
      'step_parent': 'step_child',
      'step_child': 'step_parent',
      'step_sibling': 'step_sibling',
      'stepfather': 'stepchild',
      'stepmother': 'stepchild',
      'stepson': 'stepfather',
      'stepdaughter': 'stepfather',
      'stepbrother': 'stepbrother',
      'stepsister': 'stepsister',

      // Compound Indian kinship (common compounds)
      'fathers_brother': 'nephew',
      'fathers_sister': 'niece',
      'fathers_elder_brother': 'nephew',
      'fathers_younger_brother': 'nephew',
      'mothers_brother': 'nephew',
      'mothers_sister': 'niece',
      'fathers_brothers_son': 'cousin',
      'fathers_brothers_daughter': 'cousin',
      'fathers_sisters_son': 'cousin',
      'fathers_sisters_daughter': 'cousin',
      'mothers_brothers_son': 'cousin',
      'mothers_brothers_daughter': 'cousin',
      'mothers_sisters_son': 'cousin',
      'mothers_sisters_daughter': 'cousin',
      'brothers_son': 'uncle',
      'brothers_daughter': 'uncle',
      'sisters_son': 'uncle',
      'sisters_daughter': 'uncle',
      'sons_wife': 'father_in_law',
      'daughters_husband': 'father_in_law',
      'wifes_father': 'son_in_law',
      'wifes_mother': 'son_in_law',
      'husbands_father': 'son_in_law',
      'husbands_mother': 'son_in_law',
      'wifes_brother': 'brother_in_law',
      'wifes_sister': 'sister_in_law',
      'husbands_brother': 'brother_in_law',
      'husbands_sister': 'sister_in_law',
    };
    return inverseMap[key] ?? key;
  }

  /// Invalidates all cached results.
  void invalidateCache() {
    _keyCache.clear();
    _pathCache.clear();
    _classificationCache.clear();
  }

  /// Invalidates cached results for a specific viewer.
  void invalidateViewer(String viewerPersonId) {
    _keyCache.removeWhere((key, _) => key.startsWith('${viewerPersonId}_'));
    _pathCache.removeWhere((key, _) => key.startsWith('${viewerPersonId}_'));
    _classificationCache.removeWhere((key, _) => key.startsWith('${viewerPersonId}_'));
  }
}
