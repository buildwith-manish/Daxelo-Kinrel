// =============================================================================
// node_colors.dart — V2.1 K-Graph Blueprint §11: Relationship Node Color System
// =============================================================================
//
// Maps each [RelationshipType] to a [NodeColorSet] containing:
//   - ring:       Border ring color (full opacity)
//   - background: Node background tint (low opacity for subtle fill)
//   - glow:       Outer glow color (medium opacity for halo effect)
//
// Color values are sourced from the V2.1 K-Graph Blueprint specification
// and align with the node color constants defined in [KinrelColors].
//
// Usage:
//   final colors = getNodeColors(RelationshipType.parent);
//   container Decoration = BoxDecoration(
//     border: Border.all(color: colors.ring, width: 2),
//     color: colors.background,
//     boxShadow: [BoxShadow(color: colors.glow, blurRadius: 16)],
//   );
// =============================================================================

import 'package:flutter/material.dart';
import '../../core/constants/brand_colors.dart';

// ── Relationship Type Enum ──────────────────────────────────────────────────

/// Categorizes family relationship types for the K-Graph node color system.
///
/// Each value corresponds to a distinct visual treatment in the graph canvas,
/// ensuring users can quickly identify relationship categories by color.
enum RelationshipType {
  /// The ego / self node — the person whose graph is being viewed.
  self,

  /// Parent generation — mother, father.
  parent,

  /// Spouse / partner relationship.
  spouse,

  /// Sibling relationship — brother, sister.
  sibling,

  /// Child generation — son, daughter.
  child,

  /// Grandparent generation — grandmother, grandfather.
  grandparent,

  /// Aunt / uncle — siblings of parents.
  auntUncle,

  /// Cousin — children of aunts/uncles.
  cousin,

  /// In-law relationships — through marriage.
  inLaw,

  /// Extended family — any relationship not covered above.
  extended,
}

// ── Node Color Set ──────────────────────────────────────────────────────────

/// An immutable triplet of colors that define the visual appearance of a
/// K-Graph node for a given [RelationshipType].
///
/// * [ring]       — The full-opacity border ring color drawn around the node.
/// * [background] — A low-opacity tint applied to the node's background fill,
///                   providing a subtle wash without overwhelming the avatar.
/// * [glow]       — A medium-opacity color used for the outer glow / halo
///                   effect that pulses on the selected or hovered node.
class NodeColorSet {
  /// Full-opacity border ring color.
  final Color ring;

  /// Low-opacity node background tint.
  final Color background;

  /// Medium-opacity outer glow / halo color.
  final Color glow;

  /// Creates a const [NodeColorSet].
  const NodeColorSet({
    required this.ring,
    required this.background,
    required this.glow,
  });
}

// ── Color Lookup ────────────────────────────────────────────────────────────

/// Returns the [NodeColorSet] for the given [RelationshipType].
///
/// The color values follow the V2.1 K-Graph Blueprint §11 specification:
///
/// | Type        | Ring     | BG Alpha | Glow Alpha |
/// |-------------|----------|----------|------------|
/// | self        | #0D9488  |  8 %     | 35 %       |
/// | parent      | #3B82F6  |  6 %     | 30 %       |
/// | spouse      | #F97316  |  6 %     | 30 %       |
/// | sibling     | #8B5CF6  |  6 %     | 30 %       |
/// | child       | #EC4899  |  6 %     | 30 %       |
/// | grandparent | #6366F1  |  6 %     | 30 %       |
/// | auntUncle   | #06B6D4  |  6 %     | 30 %       |
/// | cousin      | #10B981  |  6 %     | 30 %       |
/// | inLaw       | #F59E0B  |  6 %     | 30 %       |
/// | extended    | #64748B  |  6 %     | 30 %       |
NodeColorSet getNodeColors(RelationshipType type) {
  switch (type) {
    case RelationshipType.self:
      return NodeColorSet(
        ring: KinrelColors.nodeSelf,
        background: KinrelColors.nodeSelf.withValues(alpha: 0.08),
        glow: KinrelColors.nodeSelf.withValues(alpha: 0.35),
      );

    case RelationshipType.parent:
      return NodeColorSet(
        ring: KinrelColors.nodeParent,
        background: KinrelColors.nodeParent.withValues(alpha: 0.06),
        glow: KinrelColors.nodeParent.withValues(alpha: 0.30),
      );

    case RelationshipType.spouse:
      return NodeColorSet(
        ring: KinrelColors.nodeSpouse,
        background: KinrelColors.nodeSpouse.withValues(alpha: 0.06),
        glow: KinrelColors.nodeSpouse.withValues(alpha: 0.30),
      );

    case RelationshipType.sibling:
      return NodeColorSet(
        ring: KinrelColors.nodeSibling,
        background: KinrelColors.nodeSibling.withValues(alpha: 0.06),
        glow: KinrelColors.nodeSibling.withValues(alpha: 0.30),
      );

    case RelationshipType.child:
      return NodeColorSet(
        ring: KinrelColors.nodeChild,
        background: KinrelColors.nodeChild.withValues(alpha: 0.06),
        glow: KinrelColors.nodeChild.withValues(alpha: 0.30),
      );

    case RelationshipType.grandparent:
      return NodeColorSet(
        ring: KinrelColors.nodeGrandparent,
        background: KinrelColors.nodeGrandparent.withValues(alpha: 0.06),
        glow: KinrelColors.nodeGrandparent.withValues(alpha: 0.30),
      );

    case RelationshipType.auntUncle:
      return NodeColorSet(
        ring: KinrelColors.nodeAuntUncle,
        background: KinrelColors.nodeAuntUncle.withValues(alpha: 0.06),
        glow: KinrelColors.nodeAuntUncle.withValues(alpha: 0.30),
      );

    case RelationshipType.cousin:
      return NodeColorSet(
        ring: KinrelColors.nodeCousin,
        background: KinrelColors.nodeCousin.withValues(alpha: 0.06),
        glow: KinrelColors.nodeCousin.withValues(alpha: 0.30),
      );

    case RelationshipType.inLaw:
      return NodeColorSet(
        ring: KinrelColors.nodeInLaw,
        background: KinrelColors.nodeInLaw.withValues(alpha: 0.06),
        glow: KinrelColors.nodeInLaw.withValues(alpha: 0.30),
      );

    case RelationshipType.extended:
      return NodeColorSet(
        ring: KinrelColors.nodeExtended,
        background: KinrelColors.nodeExtended.withValues(alpha: 0.06),
        glow: KinrelColors.nodeExtended.withValues(alpha: 0.30),
      );
  }
}

// ── Key-to-Enum Helper ──────────────────────────────────────────────────────

/// Maps common relationship key strings to their [RelationshipType] enum values.
///
/// Supports standard English kinship keys used in the kinship data layer,
/// including both singular and role-specific variants:
///
/// - **parent**: `father`, `mother`, `dad`, `mom`, `papa`, `mama`
/// - **spouse**: `husband`, `wife`, `spouse`, `partner`
/// - **sibling**: `brother`, `sister`, `sibling`
/// - **child**: `son`, `daughter`, `child`
/// - **grandparent**: `grandfather`, `grandmother`, `grandpa`, `grandma`,
///   `paternal_grandfather`, `paternal_grandmother`,
///   `maternal_grandfather`, `maternal_grandmother`
/// - **auntUncle**: `uncle`, `aunt`, `paternal_uncle`, `paternal_aunt`,
///   `maternal_uncle`, `maternal_aunt`
/// - **cousin**: `cousin`, `male_cousin`, `female_cousin`
/// - **inLaw**: `father_in_law`, `mother_in_law`, `brother_in_law`,
///   `sister_in_law`, `son_in_law`, `daughter_in_law`
/// - **extended**: `great_grandfather`, `great_grandmother`,
///   `great_uncle`, `great_aunt`, `second_cousin`, `godfather`, `godmother`
///
/// Returns `null` if [key] does not match any known relationship string.
RelationshipType? relationshipTypeFromKey(String key) {
  // Normalize to lowercase for case-insensitive matching.
  final k = key.toLowerCase().trim();

  switch (k) {
    // ── Self ───────────────────────────────────────────────────────
    case 'self':
    case 'ego':
      return RelationshipType.self;

    // ── Parent ─────────────────────────────────────────────────────
    case 'father':
    case 'mother':
    case 'dad':
    case 'mom':
    case 'papa':
    case 'mama':
    case 'parent':
      return RelationshipType.parent;

    // ── Spouse ─────────────────────────────────────────────────────
    case 'husband':
    case 'wife':
    case 'spouse':
    case 'partner':
      return RelationshipType.spouse;

    // ── Sibling ────────────────────────────────────────────────────
    case 'brother':
    case 'sister':
    case 'sibling':
      return RelationshipType.sibling;

    // ── Child ──────────────────────────────────────────────────────
    case 'son':
    case 'daughter':
    case 'child':
      return RelationshipType.child;

    // ── Grandparent ────────────────────────────────────────────────
    case 'grandfather':
    case 'grandmother':
    case 'grandpa':
    case 'grandma':
    case 'paternal_grandfather':
    case 'paternal_grandmother':
    case 'maternal_grandfather':
    case 'maternal_grandmother':
    case 'grandparent':
      return RelationshipType.grandparent;

    // ── Aunt / Uncle ───────────────────────────────────────────────
    case 'uncle':
    case 'aunt':
    case 'paternal_uncle':
    case 'paternal_aunt':
    case 'maternal_uncle':
    case 'maternal_aunt':
    case 'aunt_uncle':
      return RelationshipType.auntUncle;

    // ── Cousin ─────────────────────────────────────────────────────
    case 'cousin':
    case 'male_cousin':
    case 'female_cousin':
      return RelationshipType.cousin;

    // ── In-Law ─────────────────────────────────────────────────────
    case 'father_in_law':
    case 'mother_in_law':
    case 'brother_in_law':
    case 'sister_in_law':
    case 'son_in_law':
    case 'daughter_in_law':
    case 'in_law':
      return RelationshipType.inLaw;

    // ── Extended ───────────────────────────────────────────────────
    case 'great_grandfather':
    case 'great_grandmother':
    case 'great_uncle':
    case 'great_aunt':
    case 'second_cousin':
    case 'godfather':
    case 'godmother':
    case 'extended':
      return RelationshipType.extended;

    default:
      return null;
  }
}
