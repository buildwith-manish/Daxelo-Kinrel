// lib/core/kinship/v3/kinship_signature.dart
//
// DAXELO KINREL — Deterministic Kinship Engine v3.0
// KinshipSignature — runtime-only structured data representing the
// relationship between two persons. NEVER stored. NEVER persisted.
//
// A signature is built from the BFS traversal path between Person A
// and Person B using only fundamental edge primitives:
//   UP_PARENT, DOWN_CHILD, SPOUSE, UP_ADOPTIVE_PARENT, UP_STEP_PARENT

/// The traversal primitives used by the engine. These are the ONLY
/// allowed edge types — derived relationships (brother, uncle, etc.)
/// are NEVER traversal primitives.
enum TraversePrimitive {
  upParent,        // child → parent (stored: parent A→B, traversed B→A)
  downChild,       // parent → child (stored: parent A→B, traversed A→B)
  spouse,          // bidirectional (stored: spouse A→B)
  upAdoptiveParent, // child → adoptive parent
  upStepParent,    // child → step-parent
}

/// Consanguinity type — determines whether the relationship is blood,
/// half, step, adoptive, or through marriage.
enum Consanguinity {
  blood,
  half,
  step,
  adoptive,
  inLaw,
}

/// Which side of the family the relationship belongs to.
enum FamilySide {
  paternal,
  maternal,
  none, // pure spouse traversal or no parent branch
}

/// A runtime-only structured representation of the kinship between
/// two persons. Built from the BFS path, consumed by the Vocabulary
/// Mapper. NEVER stored in the database.
class KinshipSignature {
  const KinshipSignature({
    required this.generationDelta,
    required this.pathPattern,
    required this.side,
    required this.consanguinity,
    required this.genderAnchor,
    required this.seniority,
    required this.removal,
    required this.doubleKinship,
  });

  /// Generation difference: negative = ancestor, positive = descendant,
  /// 0 = same generation. Range: -8 to +8.
  final int generationDelta;

  /// The canonical path pattern, e.g. "UP_PARENT_UP_PARENT" for
  /// grandparent. Built by joining TraversePrimitive names with _.
  final String pathPattern;

  /// Which side of the family (paternal/maternal/none).
  final FamilySide side;

  /// Blood / half / step / adoptive / inLaw.
  final Consanguinity consanguinity;

  /// Gender of the target person (male/female/neutral).
  final String genderAnchor;

  /// Birth order: elder / younger / twin / none.
  final String seniority;

  /// Removal count for "once removed" cousins.
  final int removal;

  /// True for double first cousins, etc.
  final bool doubleKinship;

  /// Builds the path pattern string from a list of primitives.
  static String buildPattern(List<TraversePrimitive> path) {
    if (path.isEmpty) return '';
    return path.map(_primitiveName).join('_');
  }

  static String _primitiveName(TraversePrimitive p) {
    switch (p) {
      case TraversePrimitive.upParent: return 'UP_PARENT';
      case TraversePrimitive.downChild: return 'DOWN_CHILD';
      case TraversePrimitive.spouse: return 'SPOUSE';
      case TraversePrimitive.upAdoptiveParent: return 'UP_ADOPTIVE_PARENT';
      case TraversePrimitive.upStepParent: return 'UP_STEP_PARENT';
    }
  }

  @override
  String toString() =>
      'KinshipSignature(gen=$generationDelta, pattern=$pathPattern, '
      'side=$side, consang=$consanguinity, gender=$genderAnchor, '
      'senior=$seniority, removal=$removal, double=$doubleKinship)';
}
