// =============================================================================
// animation_constants.dart — V2.1 K-Graph Blueprint: Animation Durations & Curves
// =============================================================================
//
// Centralises every animation duration and curve used by the K-Graph canvas,
// ensuring consistent timing across node entries, pulses, edge transitions,
// info-card animations, and ambient orb effects.
//
// All values are `const` and the class has a private constructor to prevent
// instantiation — access members directly via `GraphAnimations.xxx`.
// =============================================================================

import 'package:flutter/animation.dart';

/// Animation durations and curves for the K-Graph canvas.
///
/// Organised by feature area:
/// - **Entry animations** — how nodes appear when the graph loads or expands.
/// - **Pulse animations** — the breathing / heartbeat effects on nodes.
/// - **Rotating ring** — the decorative spinning ring around the self node.
/// - **Edge transitions** — fade / opacity changes on relationship edges.
/// - **Info card** — the slide-up detail card when a node is tapped.
/// - **Ambient orbs** — the slow-drifting background orbs for atmosphere.
/// - **Dimming** — opacity transition when the canvas dims non-selected nodes.
/// - **Curves** — easing curves shared across the above animations.
class GraphAnimations {
  GraphAnimations._();

  // ── Entry Animations ─────────────────────────────────────────────────────

  /// Duration of a single node's entry animation (fade + scale).
  static const Duration nodeEntryDuration = Duration(milliseconds: 600);

  /// Stagger delay between generations during the entry sequence.
  ///
  /// Each generation begins its entry [nodeEntryStaggerMs] milliseconds after
  /// the previous one, creating a cascading reveal from grandparents → self.
  static const int nodeEntryStaggerMs = 120;

  // ── Pulse Animations ─────────────────────────────────────────────────────

  /// Full cycle duration of the self-node pulse animation.
  ///
  /// The self node gently pulses to indicate "this is you".
  static const Duration selfPulseDuration = Duration(milliseconds: 3000);

  /// Full cycle duration of the selected-node glow pulse.
  ///
  /// When a node is selected, its outer glow oscillates at this rate.
  static const Duration selectedGlowPulseDuration = Duration(milliseconds: 2500);

  // ── Rotating Ring ────────────────────────────────────────────────────────

  /// Duration for one full rotation of the decorative ring around the self
  /// node.
  static const Duration rotatingRingDuration = Duration(seconds: 8);

  // ── Edge Transitions ─────────────────────────────────────────────────────

  /// Duration of the opacity transition when an edge appears, disappears, or
  /// changes state (e.g. highlighted ↔ dimmed).
  static const Duration edgeOpacityTransition = Duration(milliseconds: 350);

  // ── Info Card ────────────────────────────────────────────────────────────

  /// Duration of the info-card entry animation (slide + fade).
  static const Duration infoCardEntry = Duration(milliseconds: 400);

  // ── Ambient Orbs ─────────────────────────────────────────────────────────

  /// Full cycle duration of ambient orb 1 (the primary drift).
  static const Duration orb1Duration = Duration(seconds: 8);

  /// Full cycle duration of ambient orb 2 (secondary drift).
  static const Duration orb2Duration = Duration(seconds: 10);

  /// Full cycle duration of ambient orb 3 (tertiary drift).
  static const Duration orb3Duration = Duration(seconds: 7);

  /// Delay before ambient orb 2 begins its animation cycle.
  static const Duration orb2Delay = Duration(seconds: 2);

  /// Delay before ambient orb 3 begins its animation cycle.
  static const Duration orb3Delay = Duration(seconds: 4);

  // ── Dimming ──────────────────────────────────────────────────────────────

  /// Duration of the opacity transition used when dimming non-selected nodes
  /// to highlight the selected node's sub-graph.
  static const Duration dimOpacityDuration = Duration(milliseconds: 400);

  // ── Curves ───────────────────────────────────────────────────────────────

  /// Custom spring-like curve for node entry animations.
  ///
  /// Control points `(0.22, 1.0, 0.36, 1.0)` produce a snappy overshoot
  /// that settles quickly — ideal for the "pop-in" effect.
  static const Curve entryCurve = Cubic(0.22, 1.0, 0.36, 1.0);

  /// Standard ease-in-out curve for pulse and breathing animations.
  static const Curve pulseCurve = Curves.easeInOut;

  /// Elastic-out curve for the info-card entry — gives a playful bounce.
  static const Curve infoCardCurve = Curves.elasticOut;
}
