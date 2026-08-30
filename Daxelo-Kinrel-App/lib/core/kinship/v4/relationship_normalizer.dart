// lib/core/kinship/v4/relationship_normalizer.dart
//
// DAXELO-KINREL — v4.0 Relationship Normalizer (Phase 5)
//
// Converts user-selected kinship terms into fundamental graph edges.
// Only normalized edges may be stored in the database.
//
// Example: User selects "Father" → Normalizer returns ('parent', fromId, toId)
//          User selects "Grandfather" → Normalizer returns null (DERIVED — ask
//          user for the missing fundamental edge instead).

import '../v3/canonical_id.dart';

class RelationshipNormalizer {
  RelationshipNormalizer._();

  /// Normalizes a user-input term to a fundamental edge.
  ///
  /// Returns a tuple of (edgeType, isInverse) or null if the term
  /// is derived (grandfather, uncle, etc.) and cannot be stored directly.
  ///
  /// [isInverse] = true means the edge direction should be reversed:
  ///   "son" → parent edge, but from child→parent (inverse of "father")
  ///   "daughter" → parent edge, inverse
  static ({String edgeType, bool isInverse})? normalize(String term) {
    final canonical = CanonicalIdMapper.normalize(term);

    switch (canonical) {
      case CanonicalId.parent:
        // Check if it's a child term (inverse direction)
        final lower = term.toLowerCase().replaceAll(' ', '_');
        final isInverse = lower == 'son' || lower == 'daughter' ||
            lower == 'child' || lower == 'beta' || lower == 'beti' ||
            lower == 'putra' || lower == 'putri';
        return (edgeType: 'parent', isInverse: isInverse);

      case CanonicalId.spouse:
        return (edgeType: 'spouse', isInverse: false);

      case CanonicalId.adoptiveParent:
        return (edgeType: 'adoptive_parent', isInverse: false);

      case CanonicalId.stepParent:
        return (edgeType: 'step_parent', isInverse: false);

      case CanonicalId.derived:
        // Derived term — cannot be stored directly.
        // The caller should ask the user for the fundamental edge.
        return null;
    }
  }

  /// Returns the list of fundamental edge types that the user can choose
  /// from when auto-detection fails. Only these 4 options are valid.
  static List<({String label, String edgeType, bool isInverse})> fundamentalOptions() {
    return const [
      (label: 'Parent (Father/Mother)', edgeType: 'parent', isInverse: false),
      (label: 'Child (Son/Daughter)', edgeType: 'parent', isInverse: true),
      (label: 'Spouse (Husband/Wife)', edgeType: 'spouse', isInverse: false),
      (label: 'Adoptive Parent', edgeType: 'adoptive_parent', isInverse: false),
      (label: 'Step Parent', edgeType: 'step_parent', isInverse: false),
    ];
  }
}
