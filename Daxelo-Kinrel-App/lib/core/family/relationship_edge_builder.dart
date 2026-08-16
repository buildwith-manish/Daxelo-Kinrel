// lib/core/family/relationship_edge_builder.dart
//
// DAXELO KINREL — Shared Relationship Edge Construction (v5.19)
//
// Pure functions for constructing and resolving relationship edges
// according to the canonical convention (v5.17+):
//
//   labelAtoB = "toPerson is fromPerson's <labelAtoB>"
//
// These functions are shared between add_person_sheet.dart and
// relationship_picker_flow.dart to ensure both flows produce
// IDENTICAL edges for the same semantic input. They are also used
// by tests to verify cross-flow consistency without mocking I/O.

/// Input for createRelationship() — constructed by
/// [buildCanonicalRelationshipEdge] and passed to createRelationship.
class RelationshipEdgeInput {
  const RelationshipEdgeInput({
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
    required this.specificLabelAtoB,
    required this.fromPersonGender,
    required this.toPersonGender,
  });

  /// The "from" person (reference point). Canonical: labelAtoB describes
  /// toPerson's role relative to this person.
  final String fromPersonId;

  /// The "to" person (being described). Canonical: "toPerson is
  /// fromPerson's <labelAtoB>".
  final String toPersonId;

  /// The fundamental DB edge type ('parent', 'spouse', etc.).
  /// Must be one of the values allowed by the
  /// relationship_fundamental_edge_check constraint.
  final String relationshipKey;

  /// The specific kinship label (e.g. 'father', 'brother', 'wife').
  /// Stored in the labelAtoB column; used by the viewer-aware RPC.
  final String specificLabelAtoB;

  /// Gender of the fromPerson (for gender-aware inverse key).
  final String? fromPersonGender;

  /// Gender of the toPerson (for gender-aware inverse key).
  final String? toPersonGender;
}

/// Builds a canonical relationship edge input from the user's selection.
///
/// Both add_person_sheet.dart and relationship_picker_flow.dart call this
/// to ensure they produce IDENTICAL edges for the same semantic input.
///
/// Parameters:
/// - [referencePersonId] — the "anchor"/"source" person (the reference
///   point). This becomes fromPersonId.
/// - [describedPersonId] — the new/selected person (being described).
///   This becomes toPersonId.
/// - [pickedRelationshipKey] — the user's answer to "How is
///   [describedPerson] related to [referencePerson]?" (e.g. 'father'
///   means describedPerson IS referencePerson's father).
/// - [referencePersonGender] — gender of the reference person.
/// - [describedPersonGender] — gender of the described person.
///
/// Returns a [RelationshipEdgeInput] with:
/// - fromPersonId = referencePersonId
/// - toPersonId = describedPersonId
/// - relationshipKey = fundamental edge type (mapped from pickedRelationshipKey)
/// - specificLabelAtoB = pickedRelationshipKey
/// - fromPersonGender = referencePersonGender
/// - toPersonGender = describedPersonGender
///
/// Canonical convention:
///   labelAtoB = "toPerson is fromPerson's <labelAtoB>"
///   Example: from=Alice, to=Bob, labelAtoB='father' → "Bob is Alice's father"
RelationshipEdgeInput buildCanonicalRelationshipEdge({
  required String referencePersonId,
  required String describedPersonId,
  required String pickedRelationshipKey,
  String? referencePersonGender,
  String? describedPersonGender,
}) {
  return RelationshipEdgeInput(
    fromPersonId: referencePersonId,
    toPersonId: describedPersonId,
    relationshipKey: mapToFundamentalEdge(pickedRelationshipKey),
    specificLabelAtoB: pickedRelationshipKey,
    fromPersonGender: referencePersonGender,
    toPersonGender: describedPersonGender,
  );
}

/// Maps a specific kinship key (e.g. 'father', 'brother', 'wife') to the
/// fundamental edge type required by the DB constraint
/// (relationship_fundamental_edge_check: only 'parent', 'spouse',
/// 'adoptive_parent', 'step_parent' are allowed in the relationshipKey
/// column).
///
/// This is the SINGLE source of truth for this mapping — both
/// add_person_sheet.dart and relationship_picker_flow.dart use it
/// via [buildCanonicalRelationshipEdge].
String mapToFundamentalEdge(String? specificKey) {
  if (specificKey == null || specificKey.isEmpty) return 'parent';
  final k = specificKey.toLowerCase().trim();
  if (k == 'husband' || k == 'wife' || k == 'spouse') return 'spouse';
  if (k == 'step_father' || k == 'step_mother' ||
      k == 'stepfather' || k == 'stepmother' ||
      k == 'step_parent') return 'step_parent';
  if (k == 'adoptive_father' || k == 'adoptive_mother' ||
      k == 'adoptive_parent') return 'adoptive_parent';
  // Everything else (father, mother, parent, son, daughter, child,
  // brother, sister, sibling, grandfather, etc.) → 'parent'
  return 'parent';
}

/// Resolves the display label for a viewer looking at a relationship edge.
///
/// This mirrors the get_viewer_family_graph RPC's CASE statement:
///   WHEN r.fromPersonId = p_viewer_id THEN r.labelAtoB
///   WHEN r.toPersonId = p_viewer_id THEN r.labelBtoA
///
/// Parameters:
/// - [viewerId] — the Person ID of the viewer (the logged-in user's
///   linked Person).
/// - [fromPersonId] — the fromPersonId of the relationship row.
/// - [toPersonId] — the toPersonId of the relationship row.
/// - [labelAtoB] — the labelAtoB value (toPerson's role relative to
///   fromPerson).
/// - [labelBtoA] — the labelBtoA value (fromPerson's role relative to
///   toPerson). If null, the inverse of labelAtoB is computed using
///   [getGenderAwareInverseKey].
/// - [fromPersonGender] — needed for computing labelBtoA when it's null.
///
/// Returns the label the viewer should see, or null if the viewer is
/// not involved in this edge.
String? resolveEdgeLabelForViewer({
  required String viewerId,
  required String fromPersonId,
  required String toPersonId,
  required String labelAtoB,
  String? labelBtoA,
  String? fromPersonGender,
}) {
  // Mirror the RPC's CASE statement exactly:
  //   WHEN r.fromPersonId = p_viewer_id THEN r.labelAtoB
  if (fromPersonId == viewerId) {
    return labelAtoB;
  }
  //   WHEN r.toPersonId = p_viewer_id THEN r.labelBtoA
  if (toPersonId == viewerId) {
    if (labelBtoA != null) return labelBtoA;
    // Compute the inverse if not provided
    // getGenderAwareInverseKey(labelAtoB, fromPersonGender) — the
    // fromPersonGender is the gender of the person who will be the
    // toPerson in the inverse direction (i.e. the original fromPerson).
    return _computeInverseLabel(labelAtoB, fromPersonGender);
  }
  return null;
}

/// Computes the inverse label using the same logic as
/// getGenderAwareInverseKey in family_provider.dart.
/// This is a local copy to avoid circular imports — it must be kept
/// in sync with the original. Tests verify this.
String _computeInverseLabel(String labelAtoB, String? fromPersonGender) {
  final key = labelAtoB.toLowerCase().trim();
  final gender = fromPersonGender?.toLowerCase();

  if (key == 'father' || key == 'mother' || key == 'parent') {
    if (gender == 'female') return 'daughter';
    if (gender == 'male') return 'son';
    return 'child';
  }
  if (key == 'son' || key == 'daughter' || key == 'child') {
    if (gender == 'female') return 'mother';
    if (gender == 'male') return 'father';
    return 'parent';
  }
  if (key == 'husband') return 'wife';
  if (key == 'wife') return 'husband';
  if (key == 'spouse') return 'spouse';
  if (key == 'brother' || key == 'sister' || key == 'sibling') {
    if (gender == 'female') return 'sister';
    if (gender == 'male') return 'brother';
    return 'sibling';
  }
  if (key == 'grandfather' || key == 'grandmother' || key == 'grandparent') {
    if (gender == 'female') return 'granddaughter';
    if (gender == 'male') return 'grandson';
    return 'grandchild';
  }
  if (key == 'uncle' || key == 'aunt') {
    if (gender == 'female') return 'niece';
    if (gender == 'male') return 'nephew';
    return 'nephew_or_niece';
  }
  // Fallback: return the same label (symmetric relationships)
  return key;
}
