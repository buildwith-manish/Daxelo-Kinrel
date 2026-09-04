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

import 'package:flutter/widgets.dart';

/// The zoom at or above which the relationship label is FULLY VISIBLE
/// (opacity = 1.0).
///
/// v5.112 (USER FEEDBACK): Lowered from 0.9 to 0.5 so labels stay
/// fully visible across most of the zoom range. The user wants the
/// full graph node experience at every zoom level — labels should
/// only fade when the graph gets very small.
///
/// v5.130 (UX REVIEW): Lowered further from 0.5 → 0.45 so the labels
/// snap to full opacity slightly earlier when the user zooms in. This
/// reduces the "labels still look faint" perception in the 0.45–0.5
/// zoom band (a common resting zoom for medium graphs). The change is
/// presentation-only — the fade maths are unchanged.
const double kLabelFullyVisibleZoom = 0.45;

/// The zoom at or below which the relationship label is FULLY HIDDEN
/// (opacity = 0.0).
///
/// v5.112 (USER FEEDBACK): Lowered from 0.6 to 0.25 so labels remain
/// visible much longer. They only fully disappear at very low zoom
/// where the text would be unreadable anyway.
///
/// v5.130 (UX REVIEW): Lowered from 0.25 → 0.20 so labels persist a
/// little longer when zooming out — this gives the user extra time to
/// orient themselves in dense regions before labels fully fade. The
/// fade span stays at 0.25 (0.45 − 0.20), so the linear fade slope is
/// unchanged; only the band shifts down by 0.05. The smooth fade
/// maths are unchanged.
const double kLabelFullyHiddenZoom = 0.20;

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

// ─────────────────────────────────────────────────────────────────────
// v5.140 (PERF): Shared label-opacity InheritedWidget
// ─────────────────────────────────────────────────────────────────────
//
// Previously every visible GraphNode wrapped its relation label in its
// OWN `AnimatedBuilder(animation: cam, builder: ...)` to fade the label
// based on zoom. With 50–100 visible nodes that meant 50–100 per-frame
// subtree rebuilds on every camera tick (60–120 Hz during pan/zoom).
// Each rebuild allocated FittedBox + Text + TextStyle + Opacity widgets,
// ran Element diffing, and a layout pass on the FittedBox.
//
// This InheritedWidget lets the canvas host ONE AnimatedBuilder on the
// camera that publishes the precomputed label opacity to all nodes via
// the inherited value. Nodes read the inherited opacity with zero
// per-frame subscriptions — they only rebuild when the inherited value
// actually changes (which is itself throttled by the camera's existing
// 16ms Timer + culler threshold gate).
//
// Backward compatibility: if no `_RelationLabelOpacityScope` is found
// in the build context (e.g. unit tests, legacy callers), GraphNode
// falls back to computing the opacity directly from the camera. So
// callers that don't wrap the canvas in this scope still work — just
// without the perf benefit.

/// An InheritedWidget that publishes the current relationship-label
/// opacity to all descendant GraphNodes. Hosted at the canvas level
/// inside the camera's `AnimatedBuilder`.
class RelationLabelOpacityScope extends InheritedWidget {
  /// The precomputed opacity for relation labels at the current zoom
  /// level. Already accounts for small-family bypass and focus-mode
  /// bypass (i.e. it's the FINAL opacity — 1.0 means fully visible,
  /// 0.0 means fully hidden, in between means linear fade).
  final double opacity;

  const RelationLabelOpacityScope({
    super.key,
    required this.opacity,
    required super.child,
  });

  /// Returns the inherited opacity, or `null` if no scope is found
  /// (caller should compute the opacity itself as a fallback).
  static double? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RelationLabelOpacityScope>();
    return scope?.opacity;
  }

  @override
  bool updateShouldNotify(RelationLabelOpacityScope oldWidget) {
    // Avoid notifying descendants when the opacity hasn't changed by
    // more than a tiny epsilon — prevents rebuilds when the camera
    // ticks but the rounded opacity is unchanged.
    return (opacity - oldWidget.opacity).abs() > 0.005;
  }
}
