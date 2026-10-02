// lib/graph/rendering/visual_circle_center.dart
//
// EDGE-ANCHOR FIX (PART 3 — zoom-aware visual circle center).
//
// The user reported that edges look correctly centered when zoomed OUT
// but become visibly offset when zoomed IN. The root cause: the
// GraphNode widget's visual circle is at the TOP of its Column (with
// name + relation label below it), so the visual circle's CENTER is
// offset from the Positioned BOX center. The offset varies by node
// type (different diameters + extraPad):
//   standard (72px circle, 12px extraPad):       offset = -22
//   "You"/anchor (90px circle, 20px extraPad):   offset = -9
//   immediate family (80.64px circle, 12px):     offset = -17.68
//
// At zoom-OUT, the offset is small in screen pixels (barely
// noticeable). At zoom-IN, the offset is amplified (very noticeable).
//
// This file provides PUBLIC helpers to compute the per-node visual
// circle center Y offset, so that:
//   1. canvas_mixin.dart can apply the offset to the edge painter's
//      positions map (anchoring edges at the visual circle center
//      when the GraphNode widget is rendered at FULL/COMPACT LOD).
//   2. Tests can verify the offset math without accessing private
//      state.
//
// The helpers mirror the GraphNode widget's actual rendered diameter
// and extraPad (see graph_node.dart _buildCircleNode lines 1076-1111).

import '../../core/kinship/kinship_edge_style.dart'
    show KinshipEdgeCategory;

/// The Padding(24) inside the Positioned box (GraphNode widget layout).
const double kNodePadding = 24.0;

/// The default visual circle diameter (GraphNode.nodeSize default = 72).
const double kBaseCircleDiameter = 72.0;

/// Multiplier for the "You"/anchor node's visual circle diameter.
/// GraphNode._buildCircleNode line 1077: `(diameter * 1.25)`.
const double kAnchorDiameterMultiplier = 1.25;

/// Multiplier for immediate-family nodes' visual circle diameter.
/// GraphNode._buildCircleNode line 1079: `(diameter * 1.12)`.
const double kImmediateFamilyDiameterMultiplier = 1.12;

/// Extra padding around the circle for the standard / immediate-family
/// SizedBox. GraphNode._buildCircleNode line 1111: `widget.isAnchor
/// ? 20.0 : 12.0`.
const double kStandardExtraPad = 12.0;

/// Extra padding around the circle for the "You"/anchor node's
/// SizedBox (larger to accommodate the gold glow).
const double kAnchorExtraPad = 20.0;

/// Computes the per-node visual circle center Y offset from the
/// box center, based on the node's actual rendered diameter and
/// extraPad (which vary by node type: standard / "You" anchor /
/// immediate family).
///
/// This is the EDGE-ANCHOR FIX (PART 3) — the user reported that
/// edges look correctly centered when zoomed OUT but become visibly
/// offset when zoomed IN. The root cause is that the GraphNode
/// widget's visual circle is at the TOP of its Column (with name +
/// relation label below it), so the visual circle's CENTER is offset
/// from the Positioned BOX center. The offset varies by node type
/// (different diameters + extraPad).
///
/// Parameters:
/// - [isAnchor]: true if this node is the viewer's own node ("You").
/// - [isImmediateFamily]: true if this node's category is parent /
///   child / spouse / sibling (and not anchor).
///
/// Returns the Y offset to ADD to the box center Y to get the visual
/// circle center Y. Negative = visual circle is ABOVE the box center
/// (because the circle is at the top of the Column).
///
/// Math:
///   effectiveDiameter = isAnchor ? base * 1.25
///                   : isImmediateFamily ? base * 1.12
///                   : base
///   extraPad = isAnchor ? 20 : 12
///   offset = -padding + (effectiveDiameter + extraPad) / 2
///
/// Computed values:
///   standard (72, 12):        -64 + 42    = -22.0
///   anchor (90, 20):           -64 + 55    = -9.0
///   immediate family (80.64, 12): -64 + 46.32 = -17.68
double visualCircleCenterYOffset({
  required bool isAnchor,
  required bool isImmediateFamily,
}) {
  final double effectiveDiameter = isAnchor
      ? kBaseCircleDiameter * kAnchorDiameterMultiplier
      : isImmediateFamily
          ? kBaseCircleDiameter * kImmediateFamilyDiameterMultiplier
          : kBaseCircleDiameter;
  final double extraPad = isAnchor ? kAnchorExtraPad : kStandardExtraPad;
  return -kNodePadding + (effectiveDiameter + extraPad) / 2.0;
}

/// Returns true if [category] is an "immediate family" category
/// (parent / child / spouse / sibling). Mirrors
/// GraphNode._isImmediateFamilyCategory (graph_node.dart line 578).
/// Used by the edge anchor offset computation to apply the correct
/// per-node visual circle center Y offset.
bool isImmediateFamilyCategory(KinshipEdgeCategory? category) {
  if (category == null) return false;
  return category == KinshipEdgeCategory.parent ||
      category == KinshipEdgeCategory.child ||
      category == KinshipEdgeCategory.spouse ||
      category == KinshipEdgeCategory.sibling;
}
