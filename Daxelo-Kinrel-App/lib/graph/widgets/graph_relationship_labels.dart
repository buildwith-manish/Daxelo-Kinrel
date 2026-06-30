// lib/graph/widgets/graph_relationship_labels.dart
//
// Extracted from family_graph.dart (v31 refactor).
//
// Pure-logic helpers for resolving relationship labels between persons
// in the family graph. Has no Flutter widget dependencies — safe to
// unit-test in isolation and reusable by both the graph widget and
// the info-card / detail screens.
//
// Web + mobile compatible: no dart:io, no Platform checks, no isolates.

import '../data/family_graph_repository.dart' show GraphEdgeData;

/// Immutable data holder for a person's graph-rendering metadata.
///
/// Extracted from family_graph.dart's private `_GraphPersonData` so it
/// can be shared across the graph widget, the quick-actions sheet, and
/// the relationship-label resolver without making them all part of the
/// same library.
class GraphPersonData {
  final String id;
  final String name;
  final String? gender;
  final int generationIndex;
  final bool isAnchor;
  final String? photoUrl;
  final bool isDeceased;
  final String? relationshipKey;
  final int disclosureLevel;

  const GraphPersonData({
    required this.id,
    required this.name,
    this.gender,
    this.generationIndex = 0,
    this.isAnchor = false,
    this.photoUrl,
    this.isDeceased = false,
    this.relationshipKey,
    this.disclosureLevel = 1,
  });

  factory GraphPersonData.empty() => const GraphPersonData(
        id: '',
        name: '',
      );
}

/// Static helper that resolves relationship labels and inverse keys.
///
/// All methods are stateless and side-effect-free, making them trivial
/// to unit-test. The inverse-key map covers the full kinship vocabulary
/// used by the Indian family-relationship engine.
class GraphRelationshipLabels {
  GraphRelationshipLabels._();

  /// Returns the display label for [person] relative to the anchor.
  ///
  /// Returns 'You' if [person] is the anchor.
  /// Returns '' if no anchor exists in [personMap] or no edge connects
  /// the person to the anchor.
  ///
  /// v65 (CRITICAL FIX): Same directionality fix as [getRelationshipKey] —
  /// the two branches were swapped, returning the inverse label.
  static String getRelationLabel(
    GraphPersonData person,
    Map<String, GraphPersonData> personMap,
    List<GraphEdgeData> edges,
  ) {
    if (person.isAnchor) return 'You';

    final anchors = personMap.values.where((p) => p.isAnchor).toList();
    if (anchors.isEmpty) return '';
    final anchor = anchors.first;
    if (anchor.id == person.id) return 'You';

    for (final edge in edges) {
      // Edge points TO the anchor: stored key IS the anchor's perspective.
      if (edge.targetId == anchor.id && edge.sourceId == person.id) {
        return formatKey(edge.relationshipKey);
      }
      // Edge points FROM the anchor: anchor's perspective is the inverse.
      if (edge.sourceId == anchor.id && edge.targetId == person.id) {
        return formatKey(getInverseKey(edge.relationshipKey));
      }
    }

    return '';
  }

  /// Returns the relationship key for [personId] FROM THE ANCHOR'S
  /// perspective, or null if no direct edge connects them.
  ///
  /// v65 (CRITICAL FIX): The two branches were SWAPPED, causing every
  /// direct-edge lookup to return the INVERSE key. This made every
  /// non-self node render with the wrong color (e.g. a father node
  /// colored pink/child instead of blue/parent).
  ///
  /// Stored edge semantics: `from: A, to: B, key: 'X'` means
  /// "A is the X of B". So:
  ///
  ///   - Edge points TO anchor (`to == anchor`): the stored key IS the
  ///     anchor's perspective on `from`. Example:
  ///       from: Rajesh, to: anchor, key: 'father'
  ///       → "Rajesh is the father of the anchor"
  ///       → From anchor's perspective, Rajesh = 'father' (the stored key)
  ///     Return the stored key DIRECTLY (no inversion).
  ///
  ///   - Edge points FROM anchor (`from == anchor`): the stored key is
  ///     the anchor's relationship TO `to`, not the anchor's perspective
  ///     ON `to`. The anchor's perspective on `to` is the INVERSE.
  ///     Example:
  ///       from: anchor, to: Rajesh, key: 'son'
  ///       → "The anchor is the son of Rajesh"
  ///       → From anchor's perspective, Rajesh = 'father' (inverse of 'son')
  ///     Return the INVERSE of the stored key.
  static String? getRelationshipKey(
    String personId,
    Map<String, GraphPersonData> personMap,
    List<GraphEdgeData> edges,
  ) {
    final anchor = personMap.values.firstWhere(
      (p) => p.isAnchor,
      orElse: () => GraphPersonData.empty(),
    );
    if (anchor.id.isEmpty) return null;

    for (final edge in edges) {
      // Edge points TO the anchor: stored key IS the anchor's perspective.
      if (edge.targetId == anchor.id && edge.sourceId == personId) {
        return edge.relationshipKey;
      }
      // Edge points FROM the anchor: anchor's perspective is the inverse.
      if (edge.sourceId == anchor.id && edge.targetId == personId) {
        return getInverseKey(edge.relationshipKey);
      }
    }
    return null;
  }

  /// Formats a relationship key like 'father_in_law' → 'Father In Law'.
  static String formatKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Returns the inverse relationship key.
  ///
  /// For example, 'father' → 'son', 'wife' → 'husband'.
  /// If the key has no known inverse, returns the key unchanged.
  static String getInverseKey(String key) {
    return _inverseMap[key] ?? key;
  }

  /// Compares two Sets by value (not reference).
  static bool setsEqual<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }

  /// The full kinship inverse map. Covers core parent/child, sibling,
  /// spouse, grandparent/grandchild, uncle/aunt/nephew/niece, cousin,
  /// in-law, and step relationships.
  static const Map<String, String> _inverseMap = {
    // Core parent/child
    'father': 'son',
    'mother': 'daughter',
    'son': 'father',
    'daughter': 'mother',
    'parent': 'child',
    'child': 'parent',
    // Sibling
    'brother': 'brother',
    'sister': 'sister',
    'sibling': 'sibling',
    'elder_brother': 'younger_brother',
    'younger_brother': 'elder_brother',
    'elder_sister': 'younger_sister',
    'younger_sister': 'elder_sister',
    'half_brother': 'half_brother',
    'half_sister': 'half_sister',
    // Spouse
    'husband': 'wife',
    'wife': 'husband',
    'spouse': 'spouse',
    'partner': 'partner',
    // Grandparent / grandchild
    'grandfather': 'grandson',
    'grandmother': 'granddaughter',
    'grandson': 'grandfather',
    'granddaughter': 'grandmother',
    'grandparent': 'grandchild',
    'grandchild': 'grandparent',
    'paternal_grandfather': 'grandson',
    'paternal_grandmother': 'granddaughter',
    'maternal_grandfather': 'grandson',
    'maternal_grandmother': 'granddaughter',
    // Uncle / aunt / nephew / niece
    'uncle': 'nephew',
    'aunt': 'niece',
    'nephew': 'uncle',
    'niece': 'aunt',
    'paternal_uncle': 'nephew',
    'paternal_aunt': 'niece',
    'maternal_uncle': 'nephew',
    'maternal_aunt': 'niece',
    // Cousin
    'cousin': 'cousin',
    'cousin_brother': 'cousin_sister',
    'cousin_sister': 'cousin_brother',
    // In-law
    'father_in_law': 'son_in_law',
    'mother_in_law': 'daughter_in_law',
    'son_in_law': 'father_in_law',
    'daughter_in_law': 'mother_in_law',
    'brother_in_law': 'sister_in_law',
    'sister_in_law': 'brother_in_law',
    // Step
    'stepfather': 'stepson',
    'stepmother': 'stepdaughter',
    'stepson': 'stepfather',
    'stepdaughter': 'stepmother',
    'stepbrother': 'stepbrother',
    'stepsister': 'stepsister',
  };
}
