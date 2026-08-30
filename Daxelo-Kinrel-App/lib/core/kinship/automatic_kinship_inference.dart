// lib/core/kinship/automatic_kinship_inference.dart
//
// DAXELO KINREL — Automatic Kinship Inference Engine (v5.18)
//
// When a new relationship edge is created (e.g. "Alice is Bob's sister"),
// this engine derives all IMPLICIT relationships that follow from standard
// kinship rules (e.g. Alice should also be connected to Bob's parents as
// their daughter, to Bob's grandparents as their granddaughter, etc.).
//
// ═══════════════════════════════════════════════════════════════════════
// CANONICAL CONVENTION (v5.17+):
// ═══════════════════════════════════════════════════════════════════════
// labelAtoB = "toPerson is fromPerson's <labelAtoB>"
//
// Example: fromPersonId=Alice, toPersonId=Bob, labelAtoB='father'
//   → "Bob is Alice's father"
//
// The get_viewer_family_graph RPC uses:
//   WHEN r.fromPersonId = p_viewer_id THEN r.labelAtoB
//   WHEN r.toPersonId = p_viewer_id THEN r.labelBtoA
//
// TRUTH TABLE for parent-type edges (relationshipKey = 'parent'):
//
//   fromId==person? | toId==person? | labelAtoB type | Meaning
//   ─────────────────────────────────────────────────────────────────
//   YES             | NO            | parent-type    | toPerson IS personId's parent
//   NO              | YES           | parent-type    | personId IS fromPersonId's parent
//   YES             | NO            | child-type     | toPerson IS personId's child
//   NO              | YES           | child-type     | personId IS fromPersonId's child
//
// Therefore:
//   getParents(personId) =
//     {toPersonId} where fromId==personId AND labelAtoB ∈ {father,mother,parent}
//     ∪ {fromPersonId} where toId==personId AND labelAtoB ∈ {son,daughter,child}
//
//   getChildren(personId) =
//     {toPersonId} where fromId==personId AND labelAtoB ∈ {son,daughter,child}
//     ∪ {fromPersonId} where toId==personId AND labelAtoB ∈ {father,mother,parent}
//
// Sibling labels (brother/sister/sibling) are symmetric — the relationship
// is bidirectional. getSiblings() checks both directions.
// ═══════════════════════════════════════════════════════════════════════
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

  /// The "from" person. Canonical: labelAtoB describes toPerson's
  /// role relative to fromPerson.
  final String fromPersonId;

  /// The "to" person. Canonical: "toPerson is fromPerson's <labelAtoB>".
  final String toPersonId;

  /// The kinship label from fromPerson→toPerson.
  /// e.g. 'father' = toPerson is fromPerson's father.
  final String labelAtoB;

  /// Human-readable explanation of why this edge was inferred.
  final String reason;

  @override
  String toString() =>
      'InferredEdge($fromPersonId → $toPersonId, label=$labelAtoB, reason=$reason)';
}

// ── Parent/child label sets ──────────────────────────────────────────

const _parentLabels = {'father', 'mother', 'parent'};
const _childLabels = {'son', 'daughter', 'child'};

/// Infers implicit relationships from a newly-created edge.
///
/// See the file-level comment for the full rule set, hop limits, and
/// the canonical convention truth table.
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

  // ════════════════════════════════════════════════════════════════════
  // Helper functions — derived from the canonical convention truth table
  // ════════════════════════════════════════════════════════════════════

  /// Get all parents of [personId].
  ///
  /// Per the truth table:
  ///   - fromId==personId AND labelAtoB ∈ {father,mother,parent}
  ///     → toPersonId is personId's parent
  ///   - toId==personId AND labelAtoB ∈ {son,daughter,child}
  ///     → fromPersonId is personId's parent (personId is their child)
  Set<String> getParents(String personId) {
    final parents = <String>{};
    for (final r in existingRelationships) {
      if (!r.isActive) continue;
      final labelA = (r.labelAtoB ?? r.relationshipKey).toLowerCase();
      // Case 1: personId is fromPerson, labelAtoB is parent-type → toPerson is the parent
      if (r.fromPersonId == personId && _parentLabels.contains(labelA)) {
        parents.add(r.toPersonId);
      }
      // Case 2: personId is toPerson, labelAtoB is child-type → fromPerson is the parent
      if (r.toPersonId == personId && _childLabels.contains(labelA)) {
        parents.add(r.fromPersonId);
      }
    }
    return parents;
  }

  /// Get all children of [personId].
  ///
  /// Per the truth table:
  ///   - fromId==personId AND labelAtoB ∈ {son,daughter,child}
  ///     → toPersonId is personId's child
  ///   - toId==personId AND labelAtoB ∈ {father,mother,parent}
  ///     → fromPersonId is personId's child (personId is their parent)
  Set<String> getChildren(String personId) {
    final children = <String>{};
    for (final r in existingRelationships) {
      if (!r.isActive) continue;
      final labelA = (r.labelAtoB ?? r.relationshipKey).toLowerCase();
      // Case 3: personId is fromPerson, labelAtoB is child-type → toPerson is the child
      if (r.fromPersonId == personId && _childLabels.contains(labelA)) {
        children.add(r.toPersonId);
      }
      // Case 4: personId is toPerson, labelAtoB is parent-type → fromPerson is the child
      if (r.toPersonId == personId && _parentLabels.contains(labelA)) {
        children.add(r.fromPersonId);
      }
    }
    return children;
  }

  /// Get all siblings of [personId].
  /// Sibling labels are symmetric — check both directions.
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

  /// Returns the parent-type label for a person of the given gender.
  /// Canonical: this label means "toPerson is fromPerson's <label>".
  /// So if the PARENT has gender 'female', the label is 'mother'
  /// (toPerson is fromPerson's mother).
  String parentLabel(String? parentGender) {
    if (parentGender == 'female') return 'mother';
    if (parentGender == 'male') return 'father';
    return 'parent';
  }

  /// Returns the grandchild-type label for a person of the given gender.
  /// Canonical: "toPerson is fromPerson's <label>".
  /// So if the GRANDCHILD has gender 'female', the label is 'granddaughter'.
  String grandchildLabel(String? grandchildGender) {
    if (grandchildGender == 'female') return 'granddaughter';
    if (grandchildGender == 'male') return 'grandson';
    return 'grandchild';
  }

  // ════════════════════════════════════════════════════════════════════
  // INFERENCE RULES
  // ════════════════════════════════════════════════════════════════════

  // ── RULE 1: SIBLING PROPAGATION ──
  // New edge: newFromPersonId ↔ newToPersonId (siblings)
  // Canonical: labelAtoB='brother'/'sister' means toPerson is fromPerson's sibling.
  // If fromPerson has a parent P, then toPerson should also be connected to P
  // as P's child.
  //
  // New edge construction for "B is P's child":
  //   fromPersonId = P (parent, the reference point)
  //   toPersonId = B (the child being described)
  //   labelAtoB = child-label of B's gender (son/daughter/child)
  if (label == 'brother' || label == 'sister' || label == 'sibling' ||
      label == 'elder_brother' || label == 'elder_sister' ||
      label == 'younger_brother' || label == 'younger_sister') {
    // A's parents → B should also be their child
    final aParents = getParents(newFromPersonId);
    for (final parentId in aParents) {
      // B is the parent's child. Canonical: fromId=parent, toId=B, label=child-type
      final bGender = personById[newToPersonId]?.gender;
      inferred.add(InferredEdge(
        fromPersonId: parentId,
        toPersonId: newToPersonId,
        labelAtoB: bGender == 'female' ? 'daughter' : (bGender == 'male' ? 'son' : 'child'),
        reason: 'Sibling → shares parent',
      ));
    }
    // B's parents → A should also be their child
    final bParents = getParents(newToPersonId);
    for (final parentId in bParents) {
      final aGender = personById[newFromPersonId]?.gender;
      inferred.add(InferredEdge(
        fromPersonId: parentId,
        toPersonId: newFromPersonId,
        labelAtoB: aGender == 'female' ? 'daughter' : (aGender == 'male' ? 'son' : 'child'),
        reason: 'Sibling → shares parent',
      ));
    }
    // Grandparents: A's grandparents → B's grandparents
    for (final parentId in aParents) {
      for (final gpId in getParents(parentId)) {
        // B is grandparent's grandchild. Canonical: fromId=grandparent, toId=B
        inferred.add(InferredEdge(
          fromPersonId: gpId,
          toPersonId: newToPersonId,
          labelAtoB: grandchildLabel(personById[newToPersonId]?.gender),
          reason: 'Sibling → shares grandparent',
        ));
      }
    }
    for (final parentId in bParents) {
      for (final gpId in getParents(parentId)) {
        inferred.add(InferredEdge(
          fromPersonId: gpId,
          toPersonId: newFromPersonId,
          labelAtoB: grandchildLabel(personById[newFromPersonId]?.gender),
          reason: 'Sibling → shares grandparent',
        ));
      }
    }
  }

  // ── RULE 2: SPOUSE PROPAGATION (IN-LAWS) ──
  // New edge: newFromPersonId ↔ newToPersonId (spouses)
  // Canonical: labelAtoB='husband'/'wife' means toPerson is fromPerson's spouse.
  // If fromPerson has parent P, then P is toPerson's parent-in-law.
  //
  // New edge construction for "P is B's parent-in-law":
  //   fromPersonId = P (the parent, reference point)
  //   toPersonId = B (the spouse, being described)
  //   labelAtoB = parent-in-law type based on P's gender
  if (label == 'husband' || label == 'wife' || label == 'spouse') {
    // A's parents → B's parents-in-law
    final aParents = getParents(newFromPersonId);
    for (final parentId in aParents) {
      final pGender = personById[parentId]?.gender;
      // "B is P's child-in-law" → fromId=P, toId=B, label=parent-in-law
      // Canonical: toPerson(B) is fromPerson(P)'s child_in_law
      // But we want "P is B's parent-in-law" — so we describe from P's
      // perspective: B is P's child_in_law.
      // Actually, the label should describe toPerson's role relative to fromPerson.
      // If fromId=P, toId=B, then labelAtoB should be 'child_in_law'
      // (B is P's child-in-law). But we could also flip: fromId=B, toId=P,
      // labelAtoB='father_in_law' (P is B's father-in-law).
      // We use the latter because the original code used parent-in-law labels.
      // Canonical: fromId=B, toId=P, labelAtoB='father_in_law'/'mother_in_law'
      inferred.add(InferredEdge(
        fromPersonId: newToPersonId,
        toPersonId: parentId,
        labelAtoB: pGender == 'female' ? 'mother_in_law' : 'father_in_law',
        reason: 'Spouse → parent-in-law',
      ));
    }
    // B's parents → A's parents-in-law
    final bParents = getParents(newToPersonId);
    for (final parentId in bParents) {
      final pGender = personById[parentId]?.gender;
      inferred.add(InferredEdge(
        fromPersonId: newFromPersonId,
        toPersonId: parentId,
        labelAtoB: pGender == 'female' ? 'mother_in_law' : 'father_in_law',
        reason: 'Spouse → parent-in-law',
      ));
    }
    // A's siblings → B's siblings-in-law
    final aSiblings = getSiblings(newFromPersonId);
    for (final sibId in aSiblings) {
      final sGender = personById[sibId]?.gender;
      // "S is B's sibling-in-law" → fromId=B, toId=S, label=sibling-in-law type
      inferred.add(InferredEdge(
        fromPersonId: newToPersonId,
        toPersonId: sibId,
        labelAtoB: sGender == 'female' ? 'sister_in_law' : 'brother_in_law',
        reason: 'Spouse → sibling-in-law',
      ));
    }
    // B's siblings → A's siblings-in-law
    final bSiblings = getSiblings(newToPersonId);
    for (final sibId in bSiblings) {
      final sGender = personById[sibId]?.gender;
      inferred.add(InferredEdge(
        fromPersonId: newFromPersonId,
        toPersonId: sibId,
        labelAtoB: sGender == 'female' ? 'sister_in_law' : 'brother_in_law',
        reason: 'Spouse → sibling-in-law',
      ));
    }
  }

  // ── RULE 3: PARENT → GRANDCHILDREN ──
  // New edge: newFromPersonId → newToPersonId where labelAtoB is parent-type
  // Canonical: "toPerson is fromPerson's parent" (e.g. 'father')
  // So toPerson is the PARENT, fromPerson is the CHILD.
  // If toPerson (the parent) has other children, fromPerson (the new child)
  // and those other children are siblings.
  // If fromPerson (the child) has parents already, those parents are
  // toPerson's co-parents... no, that's not right.
  //
  // Actually: if toPerson is fromPerson's parent, and toPerson has a child C
  // (another child of toPerson), then fromPerson and C are siblings.
  // And if fromPerson already has a DIFFERENT parent P (co-parent),
  // then P is also toPerson's... no. Let's re-derive:
  //
  // New edge: toPerson(newToPersonId) is fromPerson(newFromPersonId)'s father.
  // → toPerson is the parent, fromPerson is the child.
  // → toPerson's other children = fromPerson's siblings.
  // → fromPerson's other parents = toPerson's co-parents (spouse of toPerson).
  //
  // The original rule was "parent→grandchild" but under the canonical
  // convention, the label 'father' means toPerson IS the father, so
  // toPerson's children are fromPerson's SIBLINGS, not grandchildren.
  //
  // Grandparent transitivity: if fromPerson has a parent P (existing),
  // and toPerson is also fromPerson's parent (new edge), then P is
  // toPerson's... co-parent, not grandparent. Grandparent would be
  // fromPerson's parent's parent.
  //
  // Let me re-derive Rule 3 properly:
  // If the new edge says "toPerson is fromPerson's parent":
  //   - toPerson's children (other than fromPerson) → fromPerson's siblings
  //   - fromPerson's existing parents → those parents' parents are
  //     fromPerson's grandparents (already known, no new inference needed)
  //   - toPerson's parents → fromPerson's grandparents
  //
  // So Rule 3 should infer:
  //   1. Siblings: fromPerson ↔ toPerson's other children
  //   2. Grandparents: toPerson's parents → fromPerson's grandparents
  if (label == 'father' || label == 'mother' || label == 'parent') {
    // toPerson is the parent, fromPerson is the child
    // toPerson's other children → fromPerson's siblings
    final toPersonChildren = getChildren(newToPersonId);
    for (final otherChildId in toPersonChildren) {
      if (otherChildId == newFromPersonId) continue;
      // fromPerson and otherChild are siblings
      // Canonical: fromId=fromPerson, toId=otherChild, label=sibling-type
      final fromGender = personById[newFromPersonId]?.gender;
      inferred.add(InferredEdge(
        fromPersonId: newFromPersonId,
        toPersonId: otherChildId,
        labelAtoB: fromGender == 'female' ? 'sister' : 'brother',
        reason: 'Parent edge → sibling (shared parent)',
      ));
    }
    // toPerson's parents → fromPerson's grandparents
    final toPersonParents = getParents(newToPersonId);
    for (final gpId in toPersonParents) {
      // fromPerson is grandparent's grandchild
      // Canonical: fromId=grandparent, toId=fromPerson, label=grandchild-type
      inferred.add(InferredEdge(
        fromPersonId: gpId,
        toPersonId: newFromPersonId,
        labelAtoB: grandchildLabel(personById[newFromPersonId]?.gender),
        reason: 'Parent edge → grandparent',
      ));
    }
  }

  // ── RULE 4: CHILD → SIBLINGS (via shared parent) ──
  // New edge: labelAtoB is child-type ('son'/'daughter'/'child')
  // Canonical: "toPerson is fromPerson's child" → fromPerson is the parent
  // If fromPerson (the parent) has other children, then toPerson (the new
  // child) and those other children are siblings.
  //
  // v5.123 (SYMMETRY FIX): Rule 3 (parent-type new edge) infers
  // grandparents via the new parent's parents. The MIRROR case was
  // missing here: when a child-type edge is added, the parent's
  // existing parents are the NEW CHILD's grandparents. Without this,
  // adding "Y is my son" inferred nothing for Y's grandparents while
  // adding "X is my father" did — asymmetric and wrong.
  if (label == 'son' || label == 'daughter' || label == 'child') {
    // fromPerson is the parent, toPerson is the child
    final fromPersonChildren = getChildren(newFromPersonId);
    for (final otherChildId in fromPersonChildren) {
      if (otherChildId == newToPersonId) continue;
      // toPerson and otherChild are siblings
      // Canonical: fromId=toPerson, toId=otherChild, label=sibling-type
      final toGender = personById[newToPersonId]?.gender;
      inferred.add(InferredEdge(
        fromPersonId: newToPersonId,
        toPersonId: otherChildId,
        labelAtoB: toGender == 'female' ? 'sister' : 'brother',
        reason: 'Child edge → sibling (shared parent)',
      ));
    }
    // fromPerson's (the parent's) parents → toPerson's grandparents.
    // Canonical: fromId=grandparent, toId=toPerson(the new child),
    // label=grandchild-type of the new child's gender.
    final fromPersonParents = getParents(newFromPersonId);
    for (final gpId in fromPersonParents) {
      inferred.add(InferredEdge(
        fromPersonId: gpId,
        toPersonId: newToPersonId,
        labelAtoB: grandchildLabel(personById[newToPersonId]?.gender),
        reason: 'Child edge → grandparent',
      ));
    }
  }

  // Deduplicate: remove edges that duplicate the new edge itself
  // or duplicate each other
  final seen = <String>{};
  final unique = <InferredEdge>[];
  for (final e in inferred) {
    // Skip if this is the same as the new edge (either direction)
    if (e.fromPersonId == newFromPersonId && e.toPersonId == newToPersonId) continue;
    if (e.fromPersonId == newToPersonId && e.toPersonId == newFromPersonId) continue;
    // Dedupe by (from, to) pair — keep first
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
