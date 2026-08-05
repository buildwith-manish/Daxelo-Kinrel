// lib/graph/rendering/relationship_label_opacity.dart
//
// DAXELO KINREL — Relationship Label Zoom-Fade (v104)
//
// Computes a smooth opacity for the secondary relationship label
// ("Husband", "Wife", "Father", "You", …) based on the current
// camera zoom level. Replaces the old hard on/off `shouldShowLabel`
// threshold with a continuous fade so labels do not disappear
// abruptly when the user zooms out and do not flicker near the
// threshold.
//
// Design goals:
//   1. Labels stay FULLY VISIBLE while zooming — they do not
//      disappear immediately when the user starts to zoom out.
//   2. Labels fade out ONLY when the zoom becomes too small for
//      them to be readable (text would be cramped / clipped).
//   3. The fade is smooth and continuous — no flicker, no sudden
//      changes, no hysteresis needed (opacity is a pure function
//      of zoom).
//   4. Small families (< 30 members) and focus mode keep labels
//      fully visible at ALL zoom levels — the graph is pinned to
//      NEAR (full detail) in those cases (see computeSemanticTier),
//      so hiding the labels would be inconsistent.
//
// Performance: this function is called per visible GraphNode on
// every camera tick (via an AnimatedBuilder inside the node). It is
// O(1) — a couple of comparisons + a linear interpolation + a clamp.

/// The zoom at or above which the relationship label is FULLY VISIBLE
/// (opacity = 1.0).
///
/// Set just BELOW the old hard threshold of 1.0 so that a user
/// starting at zoom 1.0 and zooming out sees the label remain fully
/// visible for a noticeable range before the fade begins — the label
/// does not "disappear immediately when zooming out".
const double kLabelFullyVisibleZoom = 0.85;

/// The zoom at or below which the relationship label is FULLY HIDDEN
/// (opacity = 0.0).
///
/// Set to 0.55 so the fade completes BEFORE the graph degrades to
/// the DOT tier (which starts at zoom 0.65 per defaultThresholds).
/// This guarantees no flicker at the NEAR→MEDIUM→FAR tier boundary:
/// by the time the node itself becomes a dot (which has no label
/// slot), the label has already smoothly faded to zero.
const double kLabelFullyHiddenZoom = 0.55;

/// Computes the relationship-label opacity for the given [zoom].
///
/// Returns a value in [0.0, 1.0]:
///   • zoom >= [kLabelFullyVisibleZoom] → 1.0 (fully visible)
///   • zoom <= [kLabelFullyHiddenZoom]  → 0.0 (fully hidden)
///   • between → linear fade
///
/// Pass [memberCount] and [focusActive] so small families and focus
/// mode can keep labels fully visible at all zoom levels (they are
/// pinned to NEAR detail by computeSemanticTier, so the label slot
/// is always rendered and readable). When [memberCount] is omitted
/// the small-family bypass is NOT applied.
///
/// This is a PURE function of its inputs — no hysteresis is needed
/// because the output is continuous. A zoom value oscillating near a
/// threshold produces a smoothly oscillating opacity, never a flap.
double relationLabelOpacityFor({
  required double zoom,
  int? memberCount,
  bool focusActive = false,
}) {
  // Guard against NaN / infinite / non-positive zoom (defensive — the
  // camera clamps to 0.2–5.0, but a malformed value should never
  // produce a NaN opacity).
  final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;

  // Small-family bypass: graphs under 30 members are pinned to NEAR
  // (full detail) at every zoom level by computeSemanticTier, so the
  // label slot is always rendered and readable. Hiding the label
  // would be inconsistent with the always-full-detail node. The 30
  // threshold matches computeSemanticTier's small-family bypass.
  if (memberCount != null && memberCount > 0 && memberCount < 30) {
    return 1.0;
  }

  // Focus-mode bypass: when a person is focused, the tier is floored
  // at MEDIUM (chip with name) and the focused subgraph stays legible.
  // Keep labels fully visible to match.
  if (focusActive) {
    return 1.0;
  }

  // Above the fully-visible threshold → 1.0.
  if (safeZoom >= kLabelFullyVisibleZoom) return 1.0;
  // Below the fully-hidden threshold → 0.0.
  if (safeZoom <= kLabelFullyHiddenZoom) return 0.0;

  // Linear fade between the two thresholds.
  final span = kLabelFullyVisibleZoom - kLabelFullyHiddenZoom;
  final t = (safeZoom - kLabelFullyHiddenZoom) / span;
  // Clamp to [0, 1] to guard against tiny floating-point excursions.
  return t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
}

/// Returns true when the relationship label is meaningfully visible
/// at [zoom] (opacity > 0). Used by callers that want to skip
/// building the label widget entirely when it would be invisible —
/// this is a rendering optimisation, not a visibility policy.
///
/// The opacity value itself should still come from
/// [relationLabelOpacityFor] so the fade is smooth.
bool relationLabelVisibleAt({
  required double zoom,
  int? memberCount,
  bool focusActive = false,
}) {
  return relationLabelOpacityFor(
        zoom: zoom,
        memberCount: memberCount,
        focusActive: focusActive,
      ) >
      0.0;
}
