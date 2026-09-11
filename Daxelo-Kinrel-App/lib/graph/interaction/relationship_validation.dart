// lib/graph/interaction/relationship_validation.dart
//
// DAXELO KINREL — Safe Relationship Editing and Undo (Phase 7)
//
// Validates relationship mutations before persistence and provides a
// bounded undo stack for supported graph edits.
//
// VALIDATION separates ERRORS (cannot save) from WARNINGS (user may
// confirm). It does NOT reject legitimate unusual family structures
// merely because they are uncommon.
//
// UNDO supports: add relationship, remove relationship, change
// relationship. Each undo command contains enough canonical
// information to perform the inverse operation.

import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Severity of a validation result.
enum ValidationSeverity {
  /// Validation passed — no issues found. The mutation is allowed.
  ok,

  /// Cannot save — blocks the mutation entirely.
  error,

  /// User may confirm — the mutation is suspicious but not impossible.
  warning,
}

/// v102 (BUG-3 FIX): A typed exception carrying both the human-readable
/// [message] AND the machine-readable [code] from a
/// [RelationshipValidationResult].
///
/// Previously, `createRelationship` in `family_provider.dart` threw a
/// plain `Exception(validation.message)` and then tried to detect
/// validation errors in the catch block by string-matching
/// `e.toString().contains('self_relationship')` etc. But
/// `e.toString()` returns the MESSAGE (e.g. "A person cannot have a
/// relationship with themselves."), not the CODE — so the code-slug
/// check could NEVER match, and every validation error silently fell
/// through to the non-blocking debugPrint path. The relationship write
/// proceeded even when validation correctly flagged it as invalid.
///
/// This typed exception fixes the bug structurally: the catch block
/// now does a TYPE CHECK (`e is RelationshipValidationException`)
/// instead of a fragile string match. The [code] is preserved for
/// callers that want to handle specific error types differently
/// (e.g. show a different UI for self-relationship vs duplicate).
class RelationshipValidationException implements Exception {
  const RelationshipValidationException(this.message, this.code);

  /// Human-readable error message (e.g. "A person cannot have a
  /// relationship with themselves.").
  final String message;

  /// Machine-readable error code (e.g. 'self_relationship',
  /// 'duplicate_relationship', 'circular_parentage', 'duplicate_parent').
  final String code;

  @override
  String toString() => message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelationshipValidationException &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}

/// The result of validating a relationship mutation.
@immutable
class RelationshipValidationResult {
  const RelationshipValidationResult({
    required this.severity,
    required this.message,
    this.code,
  });

  final ValidationSeverity severity;
  final String message;
  final String? code;

  bool get isError => severity == ValidationSeverity.error;
  bool get isWarning => severity == ValidationSeverity.warning;
  bool get isOk => severity == ValidationSeverity.ok;

  /// A passing validation result (no issues found).
  static const ok = RelationshipValidationResult(
    severity: ValidationSeverity.ok,
    message: '',
  );

  @override
  String toString() =>
      'RelationshipValidationResult($severity, "$message", code=$code)';
}

/// Validates a proposed relationship between [fromPersonId] and
/// [toPersonId] with [relationshipKey].
///
/// [existingEdges] — all current canonical edges as (fromId, toId,
/// edgeId, relationshipKey) tuples. Used to detect duplicates +
/// cycles.
/// [ancestorMap] — optional map of personId → set of ancestor IDs.
/// Used for circular parent ancestry detection AND for the
/// spouse-ancestor-conflict check. If null, both checks are skipped
/// (the caller should build this from BFS if available).
/// [personNames] — optional map of personId → display name, used to
/// build human-readable conflict messages. If null, IDs are used
/// instead of names.
RelationshipValidationResult validateRelationship({
  required String fromPersonId,
  required String toPersonId,
  required String relationshipKey,
  required List<({String fromId, String toId, String edgeId, String relationshipKey, String labelAtoB, String labelBtoA, String direction})> existingEdges,
  Map<String, Set<String>>? ancestorMap,
  Map<String, String>? personNames,
}) {
  // ── ERROR: Self-relationship ──
  if (fromPersonId == toPersonId) {
    return const RelationshipValidationResult(
      severity: ValidationSeverity.error,
      message: 'A person cannot have a relationship with themselves.',
      code: 'self_relationship',
    );
  }

  // ── ERROR: Duplicate relationship ──
  // v5.0: Canonicalized duplicate detection — checks both the SAME
  // key and its INVERSE on the same pair. e.g. if A→B "father" exists,
  // then B→A "child" is also a duplicate (same canonical relationship).
  // Without this, the user could "create" the same family link twice
  // by selecting the inverse direction in the picker.
  final pair = [fromPersonId, toPersonId]..sort();
  final canonicalPair = '${pair[0]}|${pair[1]}';
  final key = relationshipKey.toLowerCase();
  // v5.0: Fundamental-key family groups. Keys within the same group
  // represent the SAME edge from a different perspective — they are
  // duplicates of each other when applied to the same pair.
  const parentFamily = {'father', 'mother', 'parent'};
  const childFamily = {'son', 'daughter', 'child'};
  const spouseFamily = {'husband', 'wife', 'spouse'};
  const siblingFamily = {'brother', 'sister', 'sibling'};

  bool sameFamily(String a, String b) {
    if (a == b) return true;
    if (parentFamily.contains(a) && parentFamily.contains(b)) return false;
    if (childFamily.contains(a) && childFamily.contains(b)) return false;
    if (spouseFamily.contains(a) && spouseFamily.contains(b)) return false;
    if (siblingFamily.contains(a) && siblingFamily.contains(b)) return false;
    // Parent ↔ Child are inverses (same canonical edge)
    if (parentFamily.contains(a) && childFamily.contains(b)) return true;
    if (childFamily.contains(a) && parentFamily.contains(b)) return true;
    return false;
  }

  for (final e in existingEdges) {
    final existingPair = [e.fromId, e.toId]..sort();
    if ('${existingPair[0]}|${existingPair[1]}' == canonicalPair) {
      // Same pair — check if it's the same key (or inverse key).
      // v5.203: Use labelAtoB (the specific label) instead of
      // relationshipKey (the fundamental key 'parent'). Without this,
      // sameFamily('parent', 'father') returns false (because both are
      // in parentFamily → line 153 returns false), so genuine duplicates
      // like 'father' + 'father' on the same pair would NOT be caught.
      final existingLabel = (e.labelAtoB.isNotEmpty
          ? e.labelAtoB
          : e.relationshipKey).toLowerCase();
      if (sameFamily(existingLabel, key)) {
        return const RelationshipValidationResult(
          severity: ValidationSeverity.error,
          message: 'This relationship already exists.',
          code: 'duplicate_relationship',
        );
      }
      // Different family on same pair — that's OK (e.g. parent + spouse
      // between the same two people, which is unusual but not
      // impossible in extended families).
    }
  }

  // ── ERROR: Circular parent ancestry ──
  // If the relationship is a parent→child edge, check that the child
  // is not an ancestor of the parent (which would create a cycle).
  // v5.0: `key` is already declared above (in the duplicate check).
  const parentKeys = {'father', 'mother', 'parent'};
  const childKeys = {'son', 'daughter', 'child'};

  if (ancestorMap != null) {
    if (parentKeys.contains(key)) {
      // from IS the parent, to IS the child.
      // Check: is fromPersonId a descendant of toPersonId?
      // (i.e. does toPersonId's ancestor set contain fromPersonId?)
      final ancestorsOfTo = ancestorMap[toPersonId] ?? {};
      if (ancestorsOfTo.contains(fromPersonId)) {
        return const RelationshipValidationResult(
          severity: ValidationSeverity.error,
          message: 'This would create a circular ancestry — a person '
              'cannot be their own ancestor.',
          code: 'circular_parentage',
        );
      }
    } else if (childKeys.contains(key)) {
      // from IS the child, to IS the parent.
      // Check: is toPersonId a descendant of fromPersonId?
      final ancestorsOfFrom = ancestorMap[fromPersonId] ?? {};
      if (ancestorsOfFrom.contains(toPersonId)) {
        return const RelationshipValidationResult(
          severity: ValidationSeverity.error,
          message: 'This would create a circular ancestry — a person '
              'cannot be their own ancestor.',
          code: 'circular_parentage',
        );
      }
    }
  }

  // ── ERROR: Duplicate parent relationship ──
  // v5.203 (CRITICAL FIX): The previous check used `e.relationshipKey`
  // to detect existing parents — but `relationshipKey` is ALWAYS 'parent'
  // for ALL non-spouse edges (father, mother, son, daughter, brother,
  // sister, grandfather, uncle, etc.) due to the DB's
  // relationship_fundamental_edge_check constraint. This caused a FALSE
  // "This person already has a parent" error whenever ANY parent/child/
  // sibling edge existed — even a single child or sibling edge would
  // trigger the false positive.
  //
  // The fix: use `e.labelAtoB` (the SPECIFIC label like 'father',
  // 'son', 'brother') instead of `e.relationshipKey` (the fundamental
  // key 'parent'). This correctly distinguishes:
  //   - 'father'/'mother' (actual parent edges) → block duplicates
  //   - 'son'/'daughter'/'child' (child edges) → do NOT block
  //   - 'brother'/'sister'/'sibling' (sibling edges) → do NOT block
  //   - 'grandfather'/'grandmother' (grandparent edges) → do NOT block
  //
  // The canonical convention: `from=A, to=B, labelAtoB='father'`
  // → "B is A's father" → A is the CHILD, B is the PARENT.
  if (key == 'father' || key == 'mother' || key == 'parent') {
    // Forward direction: from=A (child), to=B (parent).
    final childId = fromPersonId;
    for (final e in existingEdges) {
      // v5.203: Use labelAtoB (the specific label) instead of
      // relationshipKey (the fundamental key 'parent'). This is the
      // SAME fix pattern already applied in:
      //   - relationship_quick_pick_sheet.dart (_shouldHideCategory)
      //   - radial_layout.dart
      //   - hierarchical_layout.dart
      //   - graph_data_models.dart
      final existingLabel = (e.labelAtoB.isNotEmpty
          ? e.labelAtoB
          : e.relationshipKey).toLowerCase();
      // Case (a): existing forward parent-edge where A is the child.
      // Only block if the existing edge's label is a PARENT label
      // (father/mother/parent), NOT a child or sibling label.
      if (e.fromId == childId &&
          (existingLabel == 'father' || existingLabel == 'mother' || existingLabel == 'parent')) {
        final sameGender = existingLabel == key;
        final bothNeutral = key == 'parent' && existingLabel == 'parent';
        if (sameGender || bothNeutral) {
          return RelationshipValidationResult(
            severity: ValidationSeverity.error,
            message: 'This person already has a $key. Remove the existing '
                'one before adding a new one.',
            code: 'duplicate_parent',
          );
        }
      }
      // Case (b): existing inverse child-edge where A is the child.
      // The inverse edge has from=A, to=B, labelAtoB='child'/'son'/
      // 'daughter' (the inverse label describing B's role relative
      // to A). Check labelBtoA for the parent label — but since
      // the inverse edge's labelBtoA is the forward label (e.g.
      // 'father'), we check labelBtoA.
      if (e.toId == childId) {
        final inverseLabel = (e.labelBtoA.isNotEmpty
            ? e.labelBtoA
            : '').toLowerCase();
        if (inverseLabel == 'father' || inverseLabel == 'mother' || inverseLabel == 'parent') {
          final sameGender = inverseLabel == key;
          final bothNeutral = key == 'parent' && inverseLabel == 'parent';
          if (sameGender || bothNeutral) {
            return RelationshipValidationResult(
              severity: ValidationSeverity.error,
              message: 'This person already has a $key. Remove the existing '
                  'one before adding a new one.',
              code: 'duplicate_parent',
            );
          }
        }
      }
    }
  } else if (key == 'son' || key == 'daughter' || key == 'child') {
    // Inverse direction: from=A (parent), to=B (child).
    final childId = toPersonId;
    for (final e in existingEdges) {
      final existingLabel = (e.labelAtoB.isNotEmpty
          ? e.labelAtoB
          : e.relationshipKey).toLowerCase();
      // Case (a): existing forward parent-edge where B is the child.
      if (e.fromId == childId &&
          (existingLabel == 'father' || existingLabel == 'mother' || existingLabel == 'parent')) {
        final sameGender = existingLabel == key;
        final bothNeutral = key == 'child' && existingLabel == 'parent';
        if (sameGender || bothNeutral) {
          return RelationshipValidationResult(
            severity: ValidationSeverity.error,
            message: 'This person already has a parent. Remove the existing '
                'one before adding a new one.',
            code: 'duplicate_parent',
          );
        }
      }
      // Case (b): existing inverse child-edge where B is the child.
      if (e.toId == childId) {
        final inverseLabel = (e.labelBtoA.isNotEmpty
            ? e.labelBtoA
            : '').toLowerCase();
        if (inverseLabel == 'father' || inverseLabel == 'mother' || inverseLabel == 'parent') {
          final sameGender = inverseLabel == key;
          final bothNeutral = key == 'child' && inverseLabel == 'parent';
          if (sameGender || bothNeutral) {
            return RelationshipValidationResult(
              severity: ValidationSeverity.error,
              message: 'This person already has a parent. Remove the existing '
                  'one before adding a new one.',
              code: 'duplicate_parent',
            );
          }
        }
      }
    }
  }

  // ── WARNING: Incompatible inverse relationship ──
  // If A is already B's father, adding A as B's son is incompatible.
  final inverseMap = <String, String>{
    'father': 'child',
    'mother': 'child',
    'parent': 'child',
    'child': 'parent',
    'son': 'parent',
    'daughter': 'parent',
    'husband': 'wife',
    'wife': 'husband',
    'spouse': 'spouse',
    'brother': 'sibling',
    'sister': 'sibling',
    'sibling': 'sibling',
  };

  final expectedInverse = inverseMap[key];
  if (expectedInverse != null) {
    for (final e in existingEdges) {
      if (e.fromId == toPersonId && e.toId == fromPersonId) {
        // v5.203: Use labelAtoB (specific label) instead of
        // relationshipKey (fundamental key 'parent').
        final existingLabel = (e.labelAtoB.isNotEmpty
            ? e.labelAtoB
            : e.relationshipKey).toLowerCase();
        final existingInverse = inverseMap[existingLabel];
        // If the existing edge's inverse doesn't match the new key,
        // there may be an incompatibility.
        if (existingInverse != null && existingInverse != key && expectedInverse != existingLabel) {
          return RelationshipValidationResult(
            severity: ValidationSeverity.warning,
            message: 'An existing relationship between these members '
                'may be incompatible with the new one. Please verify.',
            code: 'incompatible_inverse',
          );
        }
      }
    }
  }

  // ── ERROR: Spouse-ancestor conflict (v5.70) ──
  // A person cannot simultaneously be:
  //   (a) the spouse of person X, AND
  //   (b) a parent/child (at any generational distance) of someone
  //       who is ALSO a parent/child of person X.
  //
  // Concrete example: JD and HD are married. JD is Manish's father.
  // If the user tries to set HD's relationship to Manish as "daughter"
  // — this is BLOCKED, because it would mean HD is simultaneously
  // Manish's daughter AND married to Manish's father (JD), which is
  // logically impossible (HD would be her own father's spouse).
  //
  // This check uses the ancestorMap (the same BFS-built ancestor set
  // used for circular-parentage detection). It checks:
  //   - For a proposed parent/child edge between A and B:
  //     Does A have a spouse S who is an ancestor of B (or a descendant
  //     of B)? Does B have a spouse S who is an ancestor of A (or a
  //     descendant of A)?
  //   - For a proposed spouse edge between A and B:
  //     Does A have an ancestor/descendant who is B's spouse? Does B
  //     have an ancestor/descendant who is A's spouse?
  //
  // The check only applies when ancestorMap is available AND the
  // proposed relationship is either a parent/child edge or a spouse
  // edge. Sibling/extended/in-law edges are NOT checked (they don't
  // create the impossible structure).
  if (ancestorMap != null) {
    final spouseConflict = _checkSpouseAncestorConflict(
      fromPersonId: fromPersonId,
      toPersonId: toPersonId,
      relationshipKey: key,
      existingEdges: existingEdges,
      ancestorMap: ancestorMap,
      personNames: personNames,
    );
    if (spouseConflict != null) {
      return spouseConflict;
    }
  }

  // ── All checks passed ──
  return RelationshipValidationResult.ok;
}

/// v5.81 (CO-PARENTING FIX): Rewritten to ONLY block TRUE incest cycles,
/// not normal co-parenting (two married spouses both being parents of
/// the same child).
///
/// The previous logic (v5.70) blocked ANY case where a parent's spouse
/// was an ancestor of the child — which incorrectly blocked the most
/// common family structure: mother + father, married to each other,
/// both parents of the same child.
///
/// The corrected rule blocks only when the proposed relationship would
/// create a CYCLE through spouse edges:
///   - Setting A as parent of B, where B's SPOUSE is an ANCESTOR of A.
///     This creates a cycle: A → B → (spouse) → B's spouse → ... → A.
///     Example: Setting Manish as HD's parent, where HD is married to
///     JD, and JD is Manish's father → Manish becomes the parent of
///     his own father's wife → incest.
///
/// It does NOT block:
///   - Setting A as parent of B, where A's spouse is an ancestor of B.
///     This is just co-parenting: A and A's spouse are both ancestors
///     of B. Example: Setting JD as Manish's father, where JD is
///     married to HD, and HD is Manish's mother → normal family.
RelationshipValidationResult? _checkSpouseAncestorConflict({
  required String fromPersonId,
  required String toPersonId,
  required String relationshipKey,
  required List<({String fromId, String toId, String edgeId, String relationshipKey})> existingEdges,
  required Map<String, Set<String>> ancestorMap,
  Map<String, String>? personNames,
}) {
  String nameOf(String id) => personNames?[id] ?? id;
  Set<String> ancestorsOf(String id) => ancestorMap[id] ?? <String>{};

  Set<String> spousesOf(String personId) {
    final spouses = <String>{};
    const spouseKeys = {'husband', 'wife', 'spouse'};
    for (final e in existingEdges) {
      final k = e.relationshipKey.toLowerCase();
      if (!spouseKeys.contains(k)) continue;
      if (e.fromId == personId) {
        spouses.add(e.toId);
      } else if (e.toId == personId) {
        spouses.add(e.fromId);
      }
    }
    return spouses;
  }

  const parentKeys = {'father', 'mother', 'parent'};
  const childKeys = {'son', 'daughter', 'child'};
  const spouseKeys = {'husband', 'wife', 'spouse'};

  // ── Case 1: Proposed PARENT/CHILD edge ──
  if (parentKeys.contains(relationshipKey) ||
      childKeys.contains(relationshipKey)) {
    final String childId;
    final String parentId;
    if (parentKeys.contains(relationshipKey)) {
      childId = fromPersonId;
      parentId = toPersonId;
    } else {
      childId = toPersonId;
      parentId = fromPersonId;
    }

    // v5.81: ONLY check if the CHILD's spouse is an ANCESTOR of the
    // PARENT. This catches the true incest cycle:
    //   parentId → childId → (spouse) → childId's spouse → ... → parentId
    //
    // We do NOT check if the PARENT's spouse is an ancestor of the
    // child — that's normal co-parenting (A and A's spouse are both
    // ancestors of the child).
    final childSpouses = spousesOf(childId);
    for (final spouse in childSpouses) {
      if (spouse == parentId) continue;
      // Is the child's spouse an ancestor of the parent?
      // Cycle: parentId → childId → (spouse) → spouse → ... → parentId
      if (ancestorsOf(parentId).contains(spouse)) {
        return RelationshipValidationResult(
          severity: ValidationSeverity.error,
          message: 'This would make ${nameOf(parentId)} the parent of '
              '${nameOf(childId)}, but ${nameOf(childId)} is married to '
              '${nameOf(spouse)} who is an ancestor of '
              '${nameOf(parentId)}. This would create a circular family '
              'structure — ${nameOf(parentId)} cannot be both the parent '
              'of ${nameOf(childId)} and a descendant of '
              "${nameOf(childId)}'s spouse.",
          code: 'spouse_ancestor_conflict',
        );
      }
    }
  }

  // ── Case 2: Proposed SPOUSE edge ──
  // Block if either person is already an ancestor/descendant of the
  // other (via existing parent chains). This catches: A ↔ B (spouse,
  // proposed) where A → ... → B (ancestor, existing) → A is both
  // spouse and ancestor of B → incest.
  if (spouseKeys.contains(relationshipKey)) {
    final aAncestors = ancestorsOf(fromPersonId);
    final bAncestors = ancestorsOf(toPersonId);

    // Is B an ancestor of A? (A would marry their own ancestor)
    if (aAncestors.contains(toPersonId)) {
      return RelationshipValidationResult(
        severity: ValidationSeverity.error,
        message: 'This would make ${nameOf(fromPersonId)} and '
            '${nameOf(toPersonId)} spouses, but ${nameOf(toPersonId)} '
            'is already an ancestor of ${nameOf(fromPersonId)}. '
            'A person cannot marry their own ancestor.',
        code: 'spouse_ancestor_conflict',
      );
    }
    // Is A an ancestor of B? (A would marry their own descendant)
    if (bAncestors.contains(fromPersonId)) {
      return RelationshipValidationResult(
        severity: ValidationSeverity.error,
        message: 'This would make ${nameOf(fromPersonId)} and '
            '${nameOf(toPersonId)} spouses, but ${nameOf(fromPersonId)} '
            'is already an ancestor of ${nameOf(toPersonId)}. '
            'A person cannot marry their own descendant.',
        code: 'spouse_ancestor_conflict',
      );
    }
  }

  return null; // No conflict found.
}

// ═══════════════════════════════════════════════════════════════════════
// v5.70: ANCESTOR MAP BUILDER + FAMILY-WIDE CONFLICT AUDIT
// ═══════════════════════════════════════════════════════════════════════

/// Builds an ancestor map from a list of existing edges.
///
/// Returns a map of personId → set of ancestor IDs (all persons the
/// key person descends from, at any generational distance).
///
/// An edge from=A, to=B, key in {father, mother, parent} means
/// "B is A's parent" → B is an ancestor of A.
/// An edge from=A, to=B, key in {son, daughter, child} means
/// "B is A's child" → A is an ancestor of B.
///
/// Uses BFS to traverse the parent chain transitively (grandparents,
/// great-grandparents, etc. are all included).
Map<String, Set<String>> buildAncestorMap(
  List<({String fromId, String toId, String edgeId, String relationshipKey, String labelAtoB, String labelBtoA, String direction})> existingEdges,
) {
  // Step 1: Build a direct-parent adjacency map.
  // parentOf[childId] = {parentId1, parentId2, ...}
  final parentOf = <String, Set<String>>{};
  const parentKeys = {'father', 'mother', 'parent'};
  const childKeys = {'son', 'daughter', 'child'};

  // v5.203: Use labelAtoB (the specific label) instead of
  // relationshipKey (the fundamental key 'parent'). The
  // relationshipKey is ALWAYS 'parent' for ALL non-spouse edges,
  // so using it would treat sibling edges, grandparent edges, etc.
  // as parent-child edges — producing false ancestry cycles.
  // Now we use labelAtoB to correctly identify ONLY actual parent
  // and child edges.
  for (final e in existingEdges) {
    final k = (e.labelAtoB.isNotEmpty ? e.labelAtoB : e.relationshipKey).toLowerCase();
    if (parentKeys.contains(k)) {
      // from=A (child), to=B (parent) → B is parent of A
      parentOf.putIfAbsent(e.fromId, () => <String>{}).add(e.toId);
    } else if (childKeys.contains(k)) {
      // from=A (parent), to=B (child) → A is parent of B
      parentOf.putIfAbsent(e.toId, () => <String>{}).add(e.fromId);
    }
  }

  // Step 2: BFS to compute the transitive ancestor set for each person.
  final ancestorMap = <String, Set<String>>{};
  for (final personId in parentOf.keys) {
    final ancestors = <String>{};
    final queue = <String>[...parentOf[personId] ?? <String>{}];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (ancestors.contains(current)) continue; // already visited
      ancestors.add(current);
      // Add this ancestor's own parents to the queue.
      queue.addAll(parentOf[current] ?? <String>{});
    }
    ancestorMap[personId] = ancestors;
  }

  return ancestorMap;
}

/// v5.70: Audit result for a single conflict detected in existing data.
@immutable
class RelationshipConflict {
  const RelationshipConflict({
    required this.personA,
    required this.personB,
    required this.personC,
    required this.description,
  });

  /// The person who is caught in the conflicting structure.
  final String personA;

  /// The spouse of personA.
  final String personB;

  /// The ancestor/descendant of personA who is also personA's
  /// parent/child.
  final String personC;

  /// Human-readable description of the conflict.
  final String description;

  @override
  String toString() => 'RelationshipConflict($description)';
}

/// v5.70: Audits ALL existing relationships in a family for the
/// spouse-ancestor conflict.
///
/// Returns a list of [RelationshipConflict]s, one per detected
/// inconsistency. Returns an empty list if no conflicts are found.
///
/// This is used to surface existing data corruption (from earlier
/// failed update attempts) to the family admin so they can manually
/// resolve it. The validation check only runs on NEW/CHANGED
/// relationships — this audit catches problems that already exist
/// in the DB.
///
/// [existingEdges] — all current canonical edges.
/// [personNames] — optional map of personId → display name, used to
/// build human-readable conflict descriptions.
List<RelationshipConflict> auditFamilyRelationshipConflicts({
  required List<({String fromId, String toId, String edgeId, String relationshipKey, String labelAtoB, String labelBtoA, String direction})> existingEdges,
  Map<String, String>? personNames,
}) {
  final conflicts = <RelationshipConflict>[];
  final ancestorMap = buildAncestorMap(existingEdges);

  String nameOf(String id) => personNames?[id] ?? id;

  // Helper: find all spouses of a person.
  Set<String> spousesOf(String personId) {
    final spouses = <String>{};
    const spouseKeys = {'husband', 'wife', 'spouse'};
    for (final e in existingEdges) {
      // v5.203: Use labelAtoB (specific label) instead of
      // relationshipKey (fundamental key 'parent'/'spouse').
      final k = (e.labelAtoB.isNotEmpty ? e.labelAtoB : e.relationshipKey).toLowerCase();
      if (!spouseKeys.contains(k)) continue;
      if (e.fromId == personId) {
        spouses.add(e.toId);
      } else if (e.toId == personId) {
        spouses.add(e.fromId);
      }
    }
    return spouses;
  }

  // Check each parent/child edge for the conflict.
  const parentKeys = {'father', 'mother', 'parent'};
  const childKeys = {'son', 'daughter', 'child'};
  final checkedPairs = <String>{};

  for (final e in existingEdges) {
    // v5.203: Use labelAtoB (specific label) instead of
    // relationshipKey (fundamental key 'parent').
    final k = (e.labelAtoB.isNotEmpty ? e.labelAtoB : e.relationshipKey).toLowerCase();
    if (!parentKeys.contains(k) && !childKeys.contains(k)) continue;

    final String childId;
    final String parentId;
    if (parentKeys.contains(k)) {
      childId = e.fromId;
      parentId = e.toId;
    } else {
      childId = e.toId;
      parentId = e.fromId;
    }

    // Dedup: only check each (parent, child) pair once.
    final pairKey = [parentId, childId]..sort();
    final pairKeyStr = '${pairKey[0]}|${pairKey[1]}';
    if (checkedPairs.contains(pairKeyStr)) continue;
    checkedPairs.add(pairKeyStr);

    // Check: does the parent have a spouse who is an ancestor of the
    // child?
    final parentSpouses = spousesOf(parentId);
    for (final spouse in parentSpouses) {
      if (spouse == childId) continue;
      final childAncestors = ancestorMap[childId] ?? <String>{};
      if (childAncestors.contains(spouse)) {
        conflicts.add(RelationshipConflict(
          personA: parentId,
          personB: spouse,
          personC: childId,
          description: '${nameOf(parentId)} is the parent of '
              '${nameOf(childId)}, but is also married to ${nameOf(spouse)} '
              'who is an ancestor of ${nameOf(childId)}.',
        ));
      }
    }
  }

  return conflicts;
}

// ═══════════════════════════════════════════════════════════════════════
// UNDO STACK
// ═══════════════════════════════════════════════════════════════════════

/// The type of graph edit operation that can be undone.
enum GraphEditType {
  addRelationship,
  removeRelationship,
  changeRelationship,
}

/// A single undoable graph edit command.
///
/// Contains enough canonical information to perform the inverse
/// operation without re-deriving anything from the graph.
@immutable
class GraphEditCommand {
  const GraphEditCommand({
    required this.type,
    required this.familyId,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
    this.previousRelationshipKey,
    this.edgeId,
    this.description,
  });

  final GraphEditType type;
  final String familyId;
  final String fromPersonId;
  final String toPersonId;
  final String relationshipKey;
  final String? previousRelationshipKey;
  final String? edgeId;
  final String? description;

  /// Returns a human-readable description for the undo snackbar.
  String get undoDescription {
    switch (type) {
      case GraphEditType.addRelationship:
        return 'Undo: remove $relationshipKey relationship';
      case GraphEditType.removeRelationship:
        return 'Undo: restore $relationshipKey relationship';
      case GraphEditType.changeRelationship:
        return 'Undo: restore $previousRelationshipKey relationship';
    }
  }

  @override
  String toString() =>
      'GraphEditCommand($type, $fromPersonId → $toPersonId, '
      'key=$relationshipKey, prevKey=$previousRelationshipKey)';
}

/// The state of the undo stack.
@immutable
class GraphUndoState {
  const GraphUndoState({
    this.commands = const <GraphEditCommand>[],
    this.revision = 0,
  });

  /// Bounded undo stack (most recent last). Max 20 entries.
  final List<GraphEditCommand> commands;

  /// Bumped whenever the stack changes.
  final int revision;

  /// True if there are commands that can be undone.
  bool get canUndo => commands.isNotEmpty;

  /// The most recent command, or null if the stack is empty.
  GraphEditCommand? get lastCommand =>
      commands.isEmpty ? null : commands.last;

  static const GraphUndoState empty = GraphUndoState();

  GraphUndoState copyWith({
    List<GraphEditCommand>? commands,
    int? revision,
  }) {
    return GraphUndoState(
      commands: commands ?? this.commands,
      revision: revision ?? this.revision,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphUndoState && other.revision == revision;

  @override
  int get hashCode => revision.hashCode;
}

/// StateNotifier that owns the undo stack.
class GraphUndoNotifier extends StateNotifier<GraphUndoState> {
  GraphUndoNotifier() : super(GraphUndoState.empty);

  static const int _maxStack = 20;

  /// Push a new edit command onto the undo stack.
  void push(GraphEditCommand command) {
    final newCommands = [...state.commands, command];
    // Bound to _maxStack (keep the most recent).
    if (newCommands.length > _maxStack) {
      newCommands.removeRange(0, newCommands.length - _maxStack);
    }
    state = GraphUndoState(
      commands: newCommands,
      revision: state.revision + 1,
    );
  }

  /// Pop the most recent command (for undo). Returns the command to
  /// undo, or null if the stack is empty.
  GraphEditCommand? pop() {
    if (state.commands.isEmpty) return null;
    final newCommands = List<GraphEditCommand>.from(state.commands);
    final command = newCommands.removeLast();
    state = GraphUndoState(
      commands: newCommands,
      revision: state.revision + 1,
    );
    return command;
  }

  /// Clear the undo stack (e.g. on family switch).
  void clearAll() {
    if (state == GraphUndoState.empty) return;
    state = GraphUndoState.empty;
  }
}

/// Riverpod provider for the graph edit undo stack.
final graphUndoProvider =
    StateNotifierProvider<GraphUndoNotifier, GraphUndoState>(
  (ref) => GraphUndoNotifier(),
);
