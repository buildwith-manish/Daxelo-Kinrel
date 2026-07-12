// lib/graph/rendering/semantic_zoom.dart
//
// DAXELO KINREL — Semantic Zoom Presentation Tiers (Phase 3)
//
// Upgrades the existing performance-oriented LOD (_Lod enum in
// family_graph_engine_view.dart) into product-level semantic zoom.
//
// The graph reveals different INFORMATION according to zoom level:
//
//   FAR    — dot/cluster representation, no names, no shadows
//   MEDIUM — photo/initials + first name + simplified edges
//   NEAR   — full premium node + full name + kinship label + 2.5D depth
//
// HYSTERESIS prevents visual flicker around zoom thresholds. Each tier
// has an ENTER threshold (zoom rising) and a LEAVE threshold (zoom
// falling) with a margin between them. A zoom oscillating around the
// threshold will NOT flap between tiers.
//
// FOCUS/SELECTION OVERRIDE: focused + selected nodes remain
// discoverable at FAR zoom via a distinct marker (larger dot, accent
// ring). Active relationship paths remain discoverable via highlighted
// edges. This does NOT upgrade the entire graph to NEAR detail.
//
// This file does NOT replace the existing _Lod enum — it provides a
// semantic presentation tier that MAPS to _Lod and adds hysteresis +
// overrides. The existing _Lod, _NodeDotPainter, _buildChipNode, and
// _buildFullNode are preserved.

import 'package:flutter/foundation.dart' show immutable;

/// Semantic presentation tiers for the graph.
///
/// These map to the existing `_Lod` enum but add a semantic meaning:
/// what INFORMATION does the graph reveal at this zoom level?
enum SemanticTier {
  /// FAR — dot/cluster-level representation.
  /// • No full names
  /// • No expensive node shadows
  /// • No specular effects
  /// • Focused/selected person remains discoverable via marker
  /// • Path edges remain discoverable
  far,

  /// MEDIUM — photo or initials + first/display name.
  /// • Simplified node depth
  /// • Simplified edges (reduced shadow/ridge)
  /// • Primary relationship label where space permits
  medium,

  /// NEAR — full premium node rendering.
  /// • Full display name
  /// • Kinship label
  /// • Full 2.5D/3D visual depth
  /// • Full edge quality (physical 3-pass threads)
  near,
}

/// Hysteresis thresholds for semantic tier transitions.
///
/// Each tier has an ENTER zoom (rising) and a LEAVE zoom (falling).
/// The margin between them prevents flapping when the zoom oscillates
/// near a threshold.
///
/// Current values are calibrated for the v93 camera range (0.8–2.5):
///   • NEAR:  enter ≥ 1.0,  leave < 0.92
///   • MEDIUM: enter ≥ 0.72, leave < 0.65
///   • FAR:   enter < 0.65, leave ≥ 0.72 (inverse)
///
/// With minZoom=0.8, the graph starts at NEAR (1.0 ≥ 1.0) and can
/// transition to MEDIUM when the user zooms out to 0.72. FAR is
/// reachable only if minZoom is lowered (e.g. for large graphs).
@immutable
class SemanticZoomThresholds {
  const SemanticZoomThresholds({
    this.nearEnter = 1.0,
    this.nearLeave = 0.92,
    this.mediumEnter = 0.72,
    this.mediumLeave = 0.65,
  });

  /// Zoom at which NEAR tier is entered (rising). Above this → NEAR.
  final double nearEnter;

  /// Zoom below which NEAR tier is left (falling). Below this → MEDIUM.
  final double nearLeave;

  /// Zoom at which MEDIUM tier is entered (rising). Above this → MEDIUM
  /// (or NEAR if also above nearEnter).
  final double mediumEnter;

  /// Zoom below which MEDIUM tier is left (falling). Below this → FAR.
  final double mediumLeave;

  /// Hysteresis margin for NEAR↔MEDIUM transition.
  double get nearHysteresis => nearEnter - nearLeave; // 0.08

  /// Hysteresis margin for MEDIUM↔FAR transition.
  double get mediumHysteresis => mediumEnter - mediumLeave; // 0.07
}

/// Default thresholds calibrated for the v93 camera range.
const defaultThresholds = SemanticZoomThresholds();

/// Computes the semantic presentation tier with hysteresis.
///
/// The [currentTier] is the tier the graph is CURRENTLY in (for
/// hysteresis memory). The [zoom] is the current camera zoom level.
/// The [thresholds] define the enter/leave boundaries.
///
/// [memberCount] (optional) is the total number of family members in
/// the current graph. When provided and below the small-family
/// threshold (30 — matching `branch_collapse_state.dart`'s convention),
/// the tier is PINNED to [SemanticTier.near] regardless of zoom. This
/// prevents small families (4 people, 2 links) from degrading to
/// unlabeled dots when the user pinch-zooms out — there is no
/// legibility or performance benefit to collapsing a 4-node graph,
/// and the dot tier strips away the colored ring, initials circle,
/// relationship label, and spouse heart marker that make the graph
/// readable.
///
/// Returns the tier the graph SHOULD be in, accounting for hysteresis:
///   • If currently NEAR and zoom ≥ nearLeave → stay NEAR
///   • If currently NEAR and zoom < nearLeave → switch to MEDIUM
///   • If currently MEDIUM and zoom ≥ nearEnter → switch to NEAR
///   • If currently MEDIUM and zoom ≥ mediumLeave → stay MEDIUM
///   • If currently MEDIUM and zoom < mediumLeave → switch to FAR
///   • If currently FAR and zoom ≥ mediumEnter → switch to MEDIUM
///   • If currently FAR and zoom < mediumEnter → stay FAR
///
/// For the initial call (no current tier), pass [currentTier] as null
/// — the tier is computed purely from zoom without hysteresis.
SemanticTier computeSemanticTier(
  double zoom, {
  SemanticTier? currentTier,
  SemanticZoomThresholds thresholds = defaultThresholds,
  int? memberCount,
}) {
  // Small-family bypass: graphs under 30 members never degrade below
  // NEAR. The semantic zoom tiers (MEDIUM/FAR) exist to keep LARGE
  // trees legible at low zoom — they should never apply to a 4-person
  // family. The 30 threshold matches `branch_collapse_state.dart`'s
  // `familyMemberCount < 30` small-family bypass convention.
  if (memberCount != null && memberCount > 0 && memberCount < 30) {
    return SemanticTier.near;
  }

  if (currentTier == null) {
    // Initial computation — no hysteresis memory.
    if (zoom >= thresholds.nearEnter) return SemanticTier.near;
    if (zoom >= thresholds.mediumEnter) return SemanticTier.medium;
    return SemanticTier.far;
  }

  switch (currentTier) {
    case SemanticTier.near:
      // Stay NEAR until zoom drops below nearLeave.
      if (zoom >= thresholds.nearLeave) return SemanticTier.near;
      // Fall through to MEDIUM check.
      if (zoom >= thresholds.mediumLeave) return SemanticTier.medium;
      return SemanticTier.far;

    case SemanticTier.medium:
      // Upgrade to NEAR if zoom rises above nearEnter.
      if (zoom >= thresholds.nearEnter) return SemanticTier.near;
      // Stay MEDIUM until zoom drops below mediumLeave.
      if (zoom >= thresholds.mediumLeave) return SemanticTier.medium;
      return SemanticTier.far;

    case SemanticTier.far:
      // Upgrade to MEDIUM if zoom rises above mediumEnter.
      if (zoom >= thresholds.mediumEnter) return SemanticTier.medium;
      // Also upgrade to NEAR if zoom is very high.
      if (zoom >= thresholds.nearEnter) return SemanticTier.near;
      return SemanticTier.far;
  }
}

/// Maps a [SemanticTier] to the existing `_Lod` enum value.
///
/// This preserves the existing LOD architecture (FULL/CHIP/DOT) while
/// layering semantic meaning on top:
///   • NEAR   → _Lod.full (premium GraphNode widgets)
///   • MEDIUM → _Lod.chip (lightweight dot + name)
///   • FAR    → _Lod.dot (single painter, no widgets)
///
/// The caller (family_graph_engine_view.dart) uses this to drive the
/// existing _buildNodeLayer / _edgeQualityFor without duplicating
/// the LOD infrastructure.
String semanticTierToLodName(SemanticTier tier) {
  switch (tier) {
    case SemanticTier.near:
      return 'full';
    case SemanticTier.medium:
      return 'chip';
    case SemanticTier.far:
      return 'dot';
  }
}

/// Returns true when a node should be rendered with focus/selection
/// emphasis EVEN at FAR zoom.
///
/// At FAR (dot) zoom, the focused node and selected node would
/// normally be indistinguishable from other dots. This override
/// makes them discoverable by:
///   • Drawing a larger dot (e.g. 9px instead of 6px)
///   • Drawing an accent ring around the dot
///   • Using the relationship accent colour
///
/// This does NOT upgrade the node to full widget rendering — it
/// only makes the dot visually distinct in the _NodeDotPainter.
bool shouldOverrideFarTier({
  required String nodeId,
  required String? focusedPersonId,
  required String? selectedPersonId,
  required Set<String>? pathNodeIds,
}) {
  if (nodeId == focusedPersonId) return true;
  if (nodeId == selectedPersonId) return true;
  if (pathNodeIds != null && pathNodeIds.contains(nodeId)) return true;
  return false;
}

/// Returns the dot radius for a node at FAR zoom, accounting for
/// focus/selection overrides.
///
/// Normal nodes: 6.0px (the existing _NodeDotPainter radius).
/// Focused/selected/path nodes: 9.0px (50% larger, discoverable).
double farTierDotRadius({
  required String nodeId,
  required String? focusedPersonId,
  required String? selectedPersonId,
  required Set<String>? pathNodeIds,
}) {
  if (shouldOverrideFarTier(
    nodeId: nodeId,
    focusedPersonId: focusedPersonId,
    selectedPersonId: selectedPersonId,
    pathNodeIds: pathNodeIds,
  )) {
    return 9.0; // 50% larger for discoverability
  }
  return 6.0; // standard dot radius
}

/// Returns true when the FAR tier should EXCLUDE premium visual
/// effects (shadows, specular highlights, 3D depth).
///
/// This is always true at FAR — the whole point of FAR is to be
/// cheap. The function exists so painters can query it uniformly.
bool farTierExcludesPremiumEffects(SemanticTier tier) {
  return tier == SemanticTier.far;
}

/// Returns true when text labels should be rendered at this tier.
///
///   • NEAR   → full name + kinship label
///   • MEDIUM → first name only (truncated)
///   • FAR    → no text (unreadable at this scale)
bool shouldRenderText(SemanticTier tier) {
  switch (tier) {
    case SemanticTier.near:
      return true;
    case SemanticTier.medium:
      return true; // first name only
    case SemanticTier.far:
      return false; // no text at far zoom
  }
}
