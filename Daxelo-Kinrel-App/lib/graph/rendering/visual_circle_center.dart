// lib/graph/rendering/visual_circle_center.dart
//
// EDGE-ANCHOR FIX (PART 4 — node-positioned visual circle center).
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
// PART 3 (reverted) tried to apply this offset to the edge painter's
// positions map. That approach had issues with build timing and LOD
// conditional application.
//
// PART 4 (this file) takes a different approach: offset the node
// widget's Positioned BOX so the visual circle center IS at the
// layout position. This way:
//   - Edges anchor at the layout position = visual circle center
//   - No positions map changes needed
//   - No LOD dependency (the offset is in the node widget's layout)
//   - No cache issues (the edge path cache uses the unchanged positions)
//   - Works at ALL zoom levels (the offset is part of the content
//     that's scaled by the camera Transform)
//
// The helpers mirror the GraphNode widget's actual rendered diameter
// and extraPad (see graph_node.dart _buildCircleNode lines 1076-1111).

import '../../core/kinship/kinship_edge_style.dart'
    show KinshipEdgeCategory;

/// The Positioned box height (GraphNode widget layout: _kNodeSize = 140×176).
/// Used to compute the visual circle center offset from the BOX CENTER.
const double kNodeBoxHeight = 176.0;

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
/// BOX CENTER, based on the node's actual rendered diameter and
/// extraPad (which vary by node type: standard / "You" anchor /
/// immediate family).
///
/// Returns a NEGATIVE value (the visual circle is ABOVE the box
/// center, because the circle is at the top of the Column with
/// name + relation label below it).
///
/// Layout (per GraphNode._buildCircleNode + _buildNodeContent):
///   Positioned box: 140×176, centered at `pos`
///   Padding(24): inner area = 92×128
///   Column (top-aligned in Padding): top at pos.dy - 64
///   SizedBox (circle layer): top at Column top = pos.dy - 64
///   Visual circle center = SizedBox center = pos.dy - 64 + (effDiam + extraPad)/2
///
/// Offset from box center (pos.dy):
///   = [pos.dy - 64 + (effDiam + extraPad)/2] - pos.dy
///   = -64 + (effDiam + extraPad)/2
///   = padding + (effDiam + extraPad)/2 - boxHeight/2
///   (since -64 = padding - boxHeight/2 = 24 - 88 = -64)
///
/// Math:
///   effectiveDiameter = isAnchor ? base * 1.25
///                   : isImmediateFamily ? base * 1.12
///                   : base
///   extraPad = isAnchor ? 20 : 12
///   offset = kNodePadding + (effectiveDiameter + extraPad) / 2
///            - kNodeBoxHeight / 2
///
/// Computed values:
///   standard (72, 12):              24 + 42 - 88    = -22.0
///   anchor (90, 20):                24 + 55 - 88    = -9.0
///   immediate family (80.64, 12):   24 + 46.32 - 88 = -17.68
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
  return kNodePadding +
      (effectiveDiameter + extraPad) / 2.0 -
      kNodeBoxHeight / 2.0;
}

/// Returns true if [category] is an "immediate family" category
/// (parent / child / spouse / sibling). Mirrors
/// GraphNode._isImmediateFamilyCategory (graph_node.dart line 578).
bool isImmediateFamilyCategory(KinshipEdgeCategory? category) {
  if (category == null) return false;
  return category == KinshipEdgeCategory.parent ||
      category == KinshipEdgeCategory.child ||
      category == KinshipEdgeCategory.spouse ||
      category == KinshipEdgeCategory.sibling;
}
