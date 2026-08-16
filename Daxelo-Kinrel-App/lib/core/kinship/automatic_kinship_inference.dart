// lib/core/kinship/automatic_kinship_inference.dart
//
// DAXELO KINREL — Automatic Kinship Inference Engine (v5.11)
//
// When a new relationship edge is created (e.g. "Alice is Bob's sister"),
// this engine derives all IMPLICIT relationships that follow from standard
// kinship rules (e.g. Alice should also be connected to Bob's parents as
// their daughter, to Bob's grandparents as their granddaughter, etc.).
//
// DESIGN DOC — INFERENCE RULE SET AND HOP-LIMIT:
//
// RULES (bounded to 2 hops from the newly-connected pair):
//
//   1. SIBLING PROPAGATION:
//      If A-B are siblings, and A has parent P, then B should also have
//      parent P. (BUT: if A has child C, B is C's aunt/uncle — NOT C's
//      parent. Sibling's children are NOT your children.)
//      Also: A's grandparents → B's grandparents.
//
//   2. SPOUSE PROPAGATION (IN-LAWS):
//      If A-B are spouses, and A has parent P, then P is B's parent-in-law
//      (NOT B's parent — in-law relationships stay distinct from blood).
//      A's siblings → B's siblings-in-law.
//
//   3. PARENT-CHILD TRANSITIVITY (GRANDPARENTS):
//      If A is parent of B, and B has child C, then A is grandparent of C.
//      If A is parent of B, and A has parent P, then P is grandparent of B.
//
//   4. CHILD → PARENT'S OTHER CHILDREN ARE SIBLINGS:
//      If A is now child of B, and B already has another child C,
//      then A and C are siblings.
//
// HOP LIMIT: 2 hops. This covers:
//   - Sibling → Parents (1 hop up)
//   - Sibling → Grandparents (2 hops up)
//   - Spouse → Parents-in-law (1 hop up)
//   - Spouse → Siblings-in-law (1 hop sideways)
//   - Parent → Grandchildren (1 hop down)
//   - Child → Siblings (1 hop sideways via shared parent)
// It does NOT chain through cousins, great-grandparents, or second
// cousins — those are too speculative for automatic inference.
//
// CONFLICT HANDLING:
//   The engine returns inferred edges but does NOT check for conflicts.
//   The caller must use filterExistingEdges() to remove pairs that
//   already have a relationship — never overwrite a human-entered
//   relationship with an inferred guess.

import '../family/family_provider.dart' show Person, FamilyRelationship;

/// An inferred relationship edge (not yet persisted).
class InferredEdge {
  const InferredEdge({
    required this.fromPersonId,
    required this.toPersonId,
    required this.labelAtoB,
    required this.reason,
  });

  final String fromPersonId;
  final String toPersonId;
  final String labelAtoB;
  final String reason;

  @override
  String toString() =>
      'InferredEdge($fromPersonId → $toPersonId, label=$labelAtoB, reason=$reason)';
}

/// Infers implicit relationships from a newly-created edge.
///
/// See the file-level comment for the full rule set and hop limits.
List<InferredEdge> inferKinshipEdges({
  required String newFromPersonId,
  required String newToPersonId,
  required String newLabelAtoB,
  required List<Person> persons,
  required List<FamilyRelationship> existingRelationships,
}) {
  final inferred = <InferredEdge>[];
  final label = newLabelAtoB.toLowerCase().trim();

  final personById = <String, Person>{};
  for (final p in persons) {
    personById[p.id] = p;
  }

  // Helper: get all parents of a person
  Set<String> getParents(String personId) {
    final parents = <String>{};
    for (final r in existingRelationships) {
      if (!r.isActive) continue;
      final key = r.relationshipKey.toLowerCase();
      final labelA = (r.labelAtoB ?? r.relationshipKey).toLowerCase();
      if (r.toPersonId == personId &&
          (key == 'parent' || labelA == 'father' || labelA == 'mother' || labelA == 'parent')) {
        parents.add(r.fromPersonId);
      }
    }
    return parents;
  }

  // Helper: get all children of a person
  Set<String> getChildren(String personId) {
    final children = <String>{};
    for (final r in existingRelationships) {
      if (!r.isActive) continue;
      final key = r.relationshipKey.toLowerCase();
      final labelA = (r.labelAtoB ?? r.relationshipKey).toLowerCase();
      if (r.fromPersonId == personId &&
          (key == 'parent' || labelA == 'father' || labelA == 'mother' || labelA == 'parent')) {
        children.add(r.toPersonId);
      }
    }
    return children;
  }

  // Helper: get all siblings of a person
  Set<String> getSiblings(String personId) {
    final siblings = <String>{};
    for (final r in existingRelationships) {
      if (!r.isActive) continue;
      final labelA = (r.labelAtoB ?? r.relationshipKey).toLowerCase();
      if (labelA == 'brother' || labelA == 'sister' || labelA == 'sibling' ||
          labelA == 'elder_brother' || labelA == 'elder_sister' ||
          labelA == 'younger_brother' || labelA == 'younger_sister') {
        if (r.fromPersonId == personId) siblings.add(r.toPersonId);
        if (r.toPersonId == personId) siblings.add(r.fromPersonId);
      }
    }
    return siblings;
  }

  String parentLabel(String? gender) {
    if (gender == 'female') return 'mother';
    if (gender == 'male') return 'father';
    return 'parent';
  }

  String grandchildLabel(String? gender) {
    if (gender == 'female') return 'granddaughter';
    if (gender == 'male') return 'grandson';
    return 'grandchild';
  }

  // ── RULE 1: SIBLING PROPAGATION ──
  if (label == 'brother' || label == 'sister' || label == 'sibling' ||
      label == 'elder_brother' || label == 'elder_sister' ||
      label == 'younger_brother' || label == 'younger_sister') {
    final aParents = getParents(newFromPersonId);
    for (final parentId in aParents) {
      inferred.add(InferredEdge(
        fromPersonId: newToPersonId,
        toPersonId: parentId,
        labelAtoB: parentLabel(personById[newToPersonId]?.gender),
        reason: 'Sibling → shares parent',
      ));
    }
    final bParents = getParents(newToPersonId);
    for (final parentId in bParents) {
      inferred.add(InferredEdge(
        fromPersonId: newFromPersonId,
        toPersonId: parentId,
        labelAtoB: parentLabel(personById[newFromPersonId]?.gender),
        reason: 'Sibling → shares parent',
      ));
    }
    // Grandparents
    for (final parentId in aParents) {
      for (final gpId in getParents(parentId)) {
        inferred.add(InferredEdge(
          fromPersonId: newToPersonId,
          toPersonId: gpId,
          labelAtoB: grandchildLabel(personById[newToPersonId]?.gender),
          reason: 'Sibling → shares grandparent',
        ));
      }
    }
    for (final parentId in bParents) {
      for (final gpId in getParents(parentId)) {
        inferred.add(InferredEdge(
          fromPersonId: newFromPersonId,
          toPersonId: gpId,
          labelAtoB: grandchildLabel(personById[newFromPersonId]?.gender),
          reason: 'Sibling → shares grandparent',
        ));
      }
    }
  }

  // ── RULE 2: SPOUSE PROPAGATION (IN-LAWS) ──
  if (label == 'husband' || label == 'wife' || label == 'spouse') {
    final aParents = getParents(newFromPersonId);
    for (final parentId in aParents) {
      final pGender = personById[parentId]?.gender;
      inferred.add(InferredEdge(
        fromPersonId: parentId,
        toPersonId: newToPersonId,
        labelAtoB: pGender == 'female' ? 'mother_in_law' : 'father_in_law',
        reason: 'Spouse → parent-in-law',
      ));
    }
    final bParents = getParents(newToPersonId);
    for (final parentId in bParents) {
      final pGender = personById[parentId]?.gender;
      inferred.add(InferredEdge(
        fromPersonId: parentId,
        toPersonId: newFromPersonId,
        labelAtoB: pGender == 'female' ? 'mother_in_law' : 'father_in_law',
        reason: 'Spouse → parent-in-law',
      ));
    }
    final aSiblings = getSiblings(newFromPersonId);
    for (final sibId in aSiblings) {
      final sGender = personById[sibId]?.gender;
      inferred.add(InferredEdge(
        fromPersonId: sibId,
        toPersonId: newToPersonId,
        labelAtoB: sGender == 'female' ? 'sister_in_law' : 'brother_in_law',
        reason: 'Spouse → sibling-in-law',
      ));
    }
    final bSiblings = getSiblings(newToPersonId);
    for (final sibId in bSiblings) {
      final sGender = personById[sibId]?.gender;
      inferred.add(InferredEdge(
        fromPersonId: sibId,
        toPersonId: newFromPersonId,
        labelAtoB: sGender == 'female' ? 'sister_in_law' : 'brother_in_law',
        reason: 'Spouse → sibling-in-law',
      ));
    }
  }

  // ── RULE 3: PARENT → GRANDCHILDREN ──
  if (label == 'father' || label == 'mother' || label == 'parent') {
    final bChildren = getChildren(newToPersonId);
    for (final childId in bChildren) {
      inferred.add(InferredEdge(
        fromPersonId: newFromPersonId,
        toPersonId: childId,
        labelAtoB: grandchildLabel(personById[childId]?.gender),
        reason: 'Parent → grandparent of their child',
      ));
    }
    final aParents = getParents(newFromPersonId);
    for (final parentId in aParents) {
      inferred.add(InferredEdge(
        fromPersonId: parentId,
        toPersonId: newToPersonId,
        labelAtoB: grandchildLabel(personById[newToPersonId]?.gender),
        reason: 'Parent → grandparent',
      ));
    }
  }

  // ── RULE 4: CHILD → SIBLINGS (via shared parent) ──
  if (label == 'son' || label == 'daughter' || label == 'child') {
    final bChildren = getChildren(newToPersonId);
    for (final otherChildId in bChildren) {
      if (otherChildId == newFromPersonId) continue;
      final aGender = personById[newFromPersonId]?.gender;
      inferred.add(InferredEdge(
        fromPersonId: newFromPersonId,
        toPersonId: otherChildId,
        labelAtoB: aGender == 'female' ? 'sister' : 'brother',
        reason: 'Child → sibling (shared parent)',
      ));
    }
  }

  // Deduplicate
  final seen = <String>{};
  final unique = <InferredEdge>[];
  for (final e in inferred) {
    if (e.fromPersonId == newFromPersonId && e.toPersonId == newToPersonId) continue;
    final key = '${e.fromPersonId}|${e.toPersonId}';
    if (seen.contains(key)) continue;
    seen.add(key);
    unique.add(e);
  }

  return unique;
}

/// Filters out inferred edges that already exist in the database.
List<InferredEdge> filterExistingEdges({
  required List<InferredEdge> inferred,
  required List<FamilyRelationship> existing,
}) {
  final existingPairs = <String>{};
  for (final r in existing) {
    if (!r.isActive) continue;
    final pair = [r.fromPersonId, r.toPersonId]..sort();
    existingPairs.add('${pair[0]}|${pair[1]}');
  }

  return inferred.where((e) {
    final pair = [e.fromPersonId, e.toPersonId]..sort();
    return !existingPairs.contains('${pair[0]}|${pair[1]}');
  }).toList();
}
