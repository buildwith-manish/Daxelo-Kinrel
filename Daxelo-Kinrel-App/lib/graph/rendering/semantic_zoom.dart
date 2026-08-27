// lib/graph/rendering/semantic_zoom.dart
//
// DAXELO KINREL — Semantic Zoom Presentation Tiers (Phase 3 + v5.111)
//
// Upgrades the existing performance-oriented LOD (_Lod enum in
// family_graph_engine_view.dart) into product-level semantic zoom.
//
// The graph reveals different INFORMATION according to zoom level:
//
//   FAR    — dot/cluster representation, no names, no shadows
//   MICRO  — colored circle + accent ring (no letter, no name)
//   MINI   — circle + border + initial letter (no name)
//   COMPACT— full premium node, relation label faded, name visible
//   NEAR   — full premium node + full name + kinship label + 2.5D depth
//
// v5.111 (SEMANTIC ZOOM OVERHAUL):
// The original 3-tier system degraded too aggressively — at zoom 0.72 the
// node dropped from a 72dp premium medallion to an 8px chip (a 9× shrink
// in one step). The new 5-tier system degrades GRADUALLY:
//   • NEAR    (≥ 0.85): full 72dp GraphNode, all 10 layers
//   • COMPACT (≥ 0.50): same 72dp GraphNode, relation label faded
//   • MINI    (≥ 0.28): circle + border + initial, 22px screen-space
//   • MICRO   (≥ 0.16): colored circle + ring, 16px screen-space
//   • FAR     (< 0.16): single painter, 14px normal / 20px emphasized
//
// HYSTERESIS prevents visual flicker around zoom thresholds. Each tier
// has an ENTER threshold (zoom rising) and a LEAVE threshold (zoom
// falling) with a margin between them.
//
// FOCUS/SELECTION OVERRIDE: focused + selected nodes remain
// discoverable at FAR zoom via a distinct marker (larger dot, accent
// ring). Active relationship paths remain discoverable via highlighted
// edges.

import 'package:flutter/foundation.dart' show immutable;

/// Semantic presentation tiers for the graph.
///
/// v5.111: Expanded from 3 to 5 tiers for gradual detail degradation.
enum SemanticTier {
  /// FAR — dot/cluster-level representation.
  /// • Single painter, no widgets
  /// • 14px normal dot, 20px emphasized dot
  /// • No text, no shadows, no specular
  /// • Focused/selected/path nodes get larger dot + accent ring
  far,

  /// MICRO — colored circle + accent ring, no letter.
  /// • Single painter (like FAR, but bigger)
  /// • 16px screen-space (clamped — does NOT shrink with zoom)
  /// • Emphasized nodes get accent ring + 22px size
  /// v5.111: NEW tier.
  micro,

  /// MINI — circle + border + initial letter.
  /// • Single painter (still cheap — one CustomPaint call)
  /// • 22px screen-space (clamped — does NOT shrink with zoom)
  /// • Initial letter preserved for identification
  /// • Emphasized nodes get accent ring + 30px size
  /// v5.111: NEW tier.
  mini,

  /// COMPACT — full premium node with simplified rendering.
  /// • Full 72dp GraphNode widget (geometric scaling)
  /// • Relation label faded out (opacity 0)
  /// • Name still visible (smaller font via FittedBox)
  /// • Premium effects (shadow, specular, glow) retained but smaller
  /// v5.111: NEW tier between NEAR and the old MEDIUM.
  compact,

  /// NEAR — full premium node rendering.
  /// • Full 72dp GraphNode widget
  /// • Full display name + kinship label
  /// • Full 2.5D/3D visual depth (all 10 layers)
  /// • Full edge quality (physical 3-pass threads)
  near,

  /// MEDIUM — legacy tier kept for backward compatibility with focus mode.
  /// v5.111: DEPRECATED — mapped to COMPACT in the new system. Focus mode
  /// now floors at COMPACT (which renders the full GraphNode, so the
  /// focused subgraph remains legible). The enum value is retained so
  /// existing callers (focusActive flooring, etc.) compile unchanged.
  medium,
}

/// Hysteresis thresholds for semantic tier transitions.
///
/// v5.111: Now defines 5 tiers (NEAR, COMPACT, MINI, MICRO, FAR) instead
/// of the original 3 (NEAR, MEDIUM, FAR). Each tier has an ENTER zoom
/// (rising) and a LEAVE zoom (falling) with a margin between them to
/// prevent flapping when the zoom oscillates near a threshold.
///
/// Default thresholds (small family, < 100 members):
///   • NEAR:    enter ≥ 0.85, leave < 0.78
///   • COMPACT: enter ≥ 0.50, leave < 0.45
///   • MINI:    enter ≥ 0.28, leave < 0.24
///   • MICRO:   enter ≥ 0.16, leave < 0.13
///   • FAR:     below 0.13
///
/// Camera range is 0.2–5.0, so the user can reach FAR only if minZoom
/// is lowered (large families automatically lower the thresholds via
/// [thresholdsForMemberCount] so the graph degrades gracefully).
@immutable
class SemanticZoomThresholds {
  const SemanticZoomThresholds({
    this.nearEnter = 0.85,
    this.nearLeave = 0.78,
    this.compactEnter = 0.50,
    this.compactLeave = 0.45,
    this.miniEnter = 0.28,
    this.miniLeave = 0.24,
    this.microEnter = 0.16,
    this.microLeave = 0.13,
  });

  /// Zoom at which NEAR tier is entered (rising). Above this → NEAR.
  final double nearEnter;

  /// Zoom below which NEAR tier is left (falling). Below this → COMPACT.
  final double nearLeave;

  /// Zoom at which COMPACT tier is entered (rising). Above this → COMPACT
  /// (or NEAR if also above nearEnter).
  final double compactEnter;

  /// Zoom below which COMPACT tier is left (falling). Below this → MINI.
  final double compactLeave;

  /// Zoom at which MINI tier is entered (rising).
  final double miniEnter;

  /// Zoom below which MINI tier is left (falling). Below this → MICRO.
  final double miniLeave;

  /// Zoom at which MICRO tier is entered (rising).
  final double microEnter;

  /// Zoom below which MICRO tier is left (falling). Below this → FAR.
  final double microLeave;

  /// Hysteresis margins.
  double get nearHysteresis => nearEnter - nearLeave;
  double get compactHysteresis => compactEnter - compactLeave;
  double get miniHysteresis => miniEnter - miniLeave;
  double get microHysteresis => microEnter - microLeave;
}

/// Default thresholds calibrated for small families (< 100 members).
const defaultThresholds = SemanticZoomThresholds();

/// v5.108 / v5.111: Returns thresholds scaled by member count. Large
/// families need lower thresholds because the user zooms out further
/// to see the whole tree.
///
/// Scaling rules (v5.111 — adjusted for 5-tier system):
///   <100 members: default (near=0.85, compact=0.50, mini=0.28, micro=0.16)
///   100-500: lower by 0.05 (compact=0.45, mini=0.23, micro=0.13)
///   500-2000: lower by 0.10 (compact=0.40, mini=0.20, micro=0.11)
///   2000+: lower by 0.15 (compact=0.35, mini=0.16, micro=0.09)
///
/// The MINI and MICRO screen-space sizes (22px and 16px) are NOT scaled —
/// they are hard minimums below which nodes never shrink regardless of
/// family size. Only the TRANSITION POINTS shift so large families spend
/// more time in the cheaper MINI/MICRO/DOT tiers.
SemanticZoomThresholds thresholdsForMemberCount(int memberCount) {
  if (memberCount < 100) return defaultThresholds;
  if (memberCount < 500) {
    return const SemanticZoomThresholds(
      nearEnter: 0.80,
      nearLeave: 0.73,
      compactEnter: 0.45,
      compactLeave: 0.40,
      miniEnter: 0.23,
      miniLeave: 0.20,
      microEnter: 0.13,
      microLeave: 0.10,
    );
  }
  if (memberCount < 2000) {
    return const SemanticZoomThresholds(
      nearEnter: 0.75,
      nearLeave: 0.68,
      compactEnter: 0.40,
      compactLeave: 0.35,
      miniEnter: 0.20,
      miniLeave: 0.17,
      microEnter: 0.11,
      microLeave: 0.09,
    );
  }
  // 2000+ members — very low thresholds so the graph stays readable
  // even at extreme zoom-out. MINI/MICRO screen-space sizes remain
  // clamped at 22px/16px so nodes never become anonymous dots.
  return const SemanticZoomThresholds(
    nearEnter: 0.70,
    nearLeave: 0.63,
    compactEnter: 0.35,
    compactLeave: 0.30,
    miniEnter: 0.16,
    miniLeave: 0.13,
    microEnter: 0.09,
    microLeave: 0.07,
  );
}

/// Computes the semantic presentation tier with hysteresis.
///
/// The [currentTier] is the tier the graph is CURRENTLY in (for
/// hysteresis memory). The [zoom] is the current camera zoom level.
/// The [thresholds] define the enter/leave boundaries. When [thresholds]
/// is omitted and [memberCount] is provided, the thresholds are derived
/// from [thresholdsForMemberCount] so large families degrade at lower
/// zoom (v5.108/v5.111 intent — previously the caller had to pass the
/// scaled thresholds explicitly, and callers/tests that only passed
/// `memberCount` silently got the small-family defaults).
///
/// [memberCount] (optional) — when below 30 (small-family bypass),
/// the tier is PINNED to [SemanticTier.near] regardless of zoom.
///
/// [focusActive] (optional) — when true, the tier is pinned to at least
/// [SemanticTier.compact] so the focus subgraph remains legible.
///
/// v5.111: The old `medium` tier is mapped to `compact`. Existing callers
/// that pass `focusActive: true` will floor at COMPACT (full GraphNode
/// with relation label faded) instead of the old MEDIUM (chip). This is
/// a strict improvement — the focused subgraph now renders as full
/// premium nodes, not as 8px chips.
SemanticTier computeSemanticTier(
  double zoom, {
  SemanticTier? currentTier,
  SemanticZoomThresholds? thresholds,
  int? memberCount,
  bool focusActive = false,
}) {
  // v5.123: Derive member-count-scaled thresholds when the caller did
  // not pass an explicit set. Explicit thresholds are used as-is
  // (backward compatible — the engine view passes its own pre-scaled
  // set computed from _currentMemberCount).
  final effectiveThresholds = thresholds ??
      (memberCount != null
          ? thresholdsForMemberCount(memberCount)
          : defaultThresholds);

  // Small-family bypass: graphs under 30 members never degrade below
  // NEAR. The 30 threshold matches `branch_collapse_state.dart`'s
  // small-family bypass convention.
  if (memberCount != null && memberCount > 0 && memberCount < 30) {
    return SemanticTier.near;
  }

  // P2.3 / v5.111: Focus-mode override — when focus is active, the tier
  // is pinned to at least COMPACT so the focus subgraph remains legible.
  // The user can still zoom out, but the graph won't degrade to MINI/
  // MICRO/FAR (no names, no full nodes) while a person is focused.
  if (focusActive) {
    final tier = _computeTierRaw(zoom, currentTier, effectiveThresholds);
    // Floor at COMPACT — never below during focus.
    if (tier == SemanticTier.far ||
        tier == SemanticTier.micro ||
        tier == SemanticTier.mini ||
        tier == SemanticTier.medium) {
      return SemanticTier.compact;
    }
    return tier;
  }

  return _computeTierRaw(zoom, currentTier, effectiveThresholds);
}

/// Internal: raw tier computation without focus override.
SemanticTier _computeTierRaw(
  double zoom,
  SemanticTier? currentTier,
  SemanticZoomThresholds thresholds,
) {
  if (currentTier == null) {
    // Initial computation — no hysteresis memory.
    if (zoom >= thresholds.nearEnter) return SemanticTier.near;
    if (zoom >= thresholds.compactEnter) return SemanticTier.compact;
    if (zoom >= thresholds.miniEnter) return SemanticTier.mini;
    if (zoom >= thresholds.microEnter) return SemanticTier.micro;
    return SemanticTier.far;
  }

  switch (currentTier) {
    case SemanticTier.near:
      // Stay NEAR until zoom drops below nearLeave.
      if (zoom >= thresholds.nearLeave) return SemanticTier.near;
      // Fall through to lower tiers.
      if (zoom >= thresholds.compactLeave) return SemanticTier.compact;
      if (zoom >= thresholds.miniLeave) return SemanticTier.mini;
      if (zoom >= thresholds.microLeave) return SemanticTier.micro;
      return SemanticTier.far;

    case SemanticTier.compact:
      // Upgrade to NEAR if zoom rises above nearEnter.
      if (zoom >= thresholds.nearEnter) return SemanticTier.near;
      // Stay COMPACT until zoom drops below compactLeave.
      if (zoom >= thresholds.compactLeave) return SemanticTier.compact;
      // Fall through to lower tiers.
      if (zoom >= thresholds.miniLeave) return SemanticTier.mini;
      if (zoom >= thresholds.microLeave) return SemanticTier.micro;
      return SemanticTier.far;

    case SemanticTier.mini:
      // Upgrade to COMPACT if zoom rises above compactEnter.
      if (zoom >= thresholds.compactEnter) return SemanticTier.compact;
      if (zoom >= thresholds.nearEnter) return SemanticTier.near;
      // Stay MINI until zoom drops below miniLeave.
      if (zoom >= thresholds.miniLeave) return SemanticTier.mini;
      // Fall through to MICRO.
      if (zoom >= thresholds.microLeave) return SemanticTier.micro;
      return SemanticTier.far;

    case SemanticTier.micro:
      // Upgrade to MINI if zoom rises above miniEnter.
      if (zoom >= thresholds.miniEnter) return SemanticTier.mini;
      if (zoom >= thresholds.compactEnter) return SemanticTier.compact;
      if (zoom >= thresholds.nearEnter) return SemanticTier.near;
      // Stay MICRO until zoom drops below microLeave.
      if (zoom >= thresholds.microLeave) return SemanticTier.micro;
      return SemanticTier.far;

    case SemanticTier.far:
      // Upgrade to MICRO if zoom rises above microEnter.
      if (zoom >= thresholds.microEnter) return SemanticTier.micro;
      if (zoom >= thresholds.miniEnter) return SemanticTier.mini;
      if (zoom >= thresholds.compactEnter) return SemanticTier.compact;
      if (zoom >= thresholds.nearEnter) return SemanticTier.near;
      return SemanticTier.far;

    case SemanticTier.medium:
      // v5.111: Legacy medium tier — treated as compact in the new system.
      // Should not normally be reached; if it is, fall through to compact
      // logic so the next call converges to a real tier.
      if (zoom >= thresholds.nearEnter) return SemanticTier.near;
      if (zoom >= thresholds.compactLeave) return SemanticTier.compact;
      if (zoom >= thresholds.miniLeave) return SemanticTier.mini;
      if (zoom >= thresholds.microLeave) return SemanticTier.micro;
      return SemanticTier.far;
  }
}

/// Maps a [SemanticTier] to the existing `_Lod` enum value.
///
/// v5.111: Maps the 5 active tiers + legacy medium to Lod values:
///   • NEAR    → Lod.full (premium GraphNode widgets)
///   • COMPACT → Lod.compact (full GraphNode, label faded)
///   • MINI    → Lod.mini (circle + border + initial painter)
///   • MICRO   → Lod.micro (colored circle + ring painter)
///   • FAR     → Lod.dot (single painter, no widgets)
///   • MEDIUM  → Lod.chip (legacy — kept for backward compat)
String semanticTierToLodName(SemanticTier tier) {
  switch (tier) {
    case SemanticTier.near:
      return 'full';
    case SemanticTier.compact:
      return 'compact';
    case SemanticTier.mini:
      return 'mini';
    case SemanticTier.micro:
      return 'micro';
    case SemanticTier.medium:
      return 'chip';
    case SemanticTier.far:
      return 'overview';
  }
}

/// Returns true when a node should be rendered with focus/selection
/// emphasis EVEN at FAR zoom.
///
/// At FAR (dot) zoom, the focused node and selected node would
/// normally be indistinguishable from other dots. This override
/// makes them discoverable by drawing a larger dot + accent ring.
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
/// v5.111: Raised from 10.0/14.0 to 14.0/20.0 for better visibility.
/// Normal nodes: 14.0px (28px diameter).
/// Focused/selected/path nodes: 20.0px (40px diameter, ~43% larger).
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
    return 20.0; // v5.111: raised from 14.0
  }
  return 14.0; // v5.111: raised from 10.0
}

/// v5.111: Returns the MICRO-tier radius for a node, accounting for
/// emphasis. Screen-space clamped — does NOT shrink with zoom.
/// Normal: 8.0px radius (16px diameter).
/// Emphasised: 11.0px radius (22px diameter).
double microTierRadius({required bool isEmphasised}) {
  return isEmphasised ? 11.0 : 8.0;
}

/// v5.111: Returns the MINI-tier radius for a node, accounting for
/// emphasis. Screen-space clamped — does NOT shrink with zoom.
/// Normal: 11.0px radius (22px diameter).
/// Emphasised: 15.0px radius (30px diameter).
double miniTierRadius({required bool isEmphasised}) {
  return isEmphasised ? 15.0 : 11.0;
}

/// Returns true when the FAR tier should EXCLUDE premium visual
/// effects (shadows, specular highlights, 3D depth).
///
/// v5.111: Now also returns true for MICRO (no premium effects below
/// COMPACT). MINI keeps a subtle border + initial but no shadow/specular.
bool farTierExcludesPremiumEffects(SemanticTier tier) {
  return tier == SemanticTier.far ||
      tier == SemanticTier.micro ||
      tier == SemanticTier.mini ||
      tier == SemanticTier.medium;
}

/// Returns true when text labels should be rendered at this tier.
///
/// v5.111: Updated for 5-tier system:
///   • NEAR    → full name + kinship label
///   • COMPACT → full name only (relation label faded separately)
///   • MINI    → initial letter only (painted, not Text widget)
///   • MICRO   → no text
///   • FAR     → no text
bool shouldRenderText(SemanticTier tier) {
  switch (tier) {
    case SemanticTier.near:
      return true;
    case SemanticTier.compact:
      return true; // full name only
    case SemanticTier.mini:
      return false; // initial painted, not a Text widget
    case SemanticTier.micro:
      return false;
    case SemanticTier.medium:
      return true; // legacy — first name only
    case SemanticTier.far:
      return false;
  }
}
