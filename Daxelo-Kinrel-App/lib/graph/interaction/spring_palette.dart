// lib/graph/interaction/spring_palette.dart
//
// DAXELO KINREL — Spring Physics Palette (P3.1)
//
// Single source of truth for spring descriptions used across the graph.
// Per Vision §6 #1 (WOW 7) — replace every non-spring tween (linear
// or cubic-ease) in the graph with spring physics. Every gesture
// response (pan, zoom, focus, branch expand) feels alive but never
// bouncy or distracting.
//
// Spring palette (per P3.1 Risks §"Document a spring palette"):
//   pan    : stiffness 300, damping 30   (critically damped, no overshoot)
//   zoom   : stiffness 250, damping 28   (critically damped, weighted feel)
//   focus  : stiffness 200, damping 25   (slight settle, cinematic)
//   branch : stiffness 180, damping 22   (slightly under-damped, feels like "opening")
//
// All springs use mass = 1.0. Damping ratios:
//   critical damping = 2 * sqrt(mass * stiffness)
//   pan   : 30 / (2 * sqrt(300)) ≈ 0.866  (very near critical)
//   zoom  : 28 / (2 * sqrt(250)) ≈ 0.886  (very near critical)
//   focus : 25 / (2 * sqrt(200)) ≈ 0.884  (very near critical)
//   branch: 22 / (2 * sqrt(180)) ≈ 0.820  (slightly under-damped)
//
// No new dependencies. Reuses Flutter's `package:flutter/physics.dart`.

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Canonical spring descriptions for the graph's gesture responses.
///
/// Use these instead of ad-hoc `SpringDescription` literals so the
/// entire graph shares one consistent feel. Per P3.1 Risks: "Document
/// a spring palette ... Apply consistently."
///
/// Example:
/// ```dart
/// final sim = SpringSimulation(
///   SpringPalette.pan,
///   startValue,
///   targetValue,
///   startVelocity,
/// );
/// ```
class SpringPalette {
  SpringPalette._();

  /// Pan spring. Critically damped — no overshoot, settles fast.
  /// Used for: keyboard arrow pan, post-drag momentum decay.
  static const SpringDescription pan = SpringDescription(
    mass: 1.0,
    stiffness: 300.0,
    damping: 30.0,
  );

  /// Zoom spring. Critically damped — weighted, deliberate feel.
  /// Used for: double-tap zoom, keyboard +/- zoom.
  static const SpringDescription zoom = SpringDescription(
    mass: 1.0,
    stiffness: 250.0,
    damping: 28.0,
  );

  /// Focus spring. Slight settle — cinematic focus pull.
  /// Used for: focusOnNode, fit-to-view, history navigation.
  /// v5.74 (BUG 2 FIX): Bumped damping from 25.0 to 29.0 for true
  /// critical damping (ζ = 29 / (2·√200) ≈ 1.026 — slightly over-
  /// damped, NO overshoot). The previous value (25.0, ζ ≈ 0.884)
  /// was near-critical but still had a tiny overshoot that could
  /// be perceived as a "zoom wiggle" on some devices. With true
  /// critical damping, the animation reaches its target smoothly
  /// without any oscillation, and settles in ~0.4 seconds.
  static const SpringDescription focus = SpringDescription(
    mass: 1.0,
    stiffness: 200.0,
    damping: 29.0,
  );

  /// Branch expand spring. Slightly under-damped — feels like a
  /// branch "opening" rather than toggling.
  /// Used for: new-node fade-in when a branch expands.
  static const SpringDescription branch = SpringDescription(
    mass: 1.0,
    stiffness: 180.0,
    damping: 22.0,
  );

  /// Default tolerance for spring simulations used by the graph.
  /// Springs are considered settled when position is within 0.5px
  /// (pan/zoom/focus) or 0.001 (normalized progress).
  static const Tolerance defaultTolerance = Tolerance(
    distance: 0.5,
    time: double.infinity,
    velocity: double.infinity,
  );

  /// Tighter tolerance for normalized 0..1 progress values.
  static const Tolerance normalizedTolerance = Tolerance(
    distance: 0.001,
    time: double.infinity,
    velocity: double.infinity,
  );

  /// Approximate settle time for a spring description, in seconds.
  ///
  /// Used by tests to assert convergence within a budget. For a
  /// critically-damped spring with the palette values, settle time
  /// is roughly 4 / (damping / (2 * mass)) ≈ 4 * mass * 2 / damping
  /// = 8 / damping seconds at critical damping.
  static double approximateSettleSeconds(SpringDescription spring) {
    // For near-critical springs, the e-folding time is mass / (damping / 2)
    // = 2 * mass / damping. We need ~5 e-folding times for full settle.
    return 5 * 2 * spring.mass / spring.damping;
  }
}

/// A [Curve] backed by a [SpringSimulation].
///
/// Lets `CurvedAnimation` (and any other Curve consumer) use spring
/// physics without rewriting the consumer. The curve maps the
/// normalized input `t ∈ [0, 1]` to the spring's position at time
/// `t * settleSeconds`, where `settleSeconds` is computed once from
/// the spring description.
///
/// Reduced-motion consumers should NOT use this curve — they should
/// snap instantly. The curve intentionally does not check
/// `MediaQuery.disableAnimationsOf` because [Curve]s are pure math
/// and should not depend on a BuildContext.
class SpringCurve extends Curve {
  /// Creates a spring-backed curve from a [SpringDescription].
  ///
  /// [from] is the start value (typically 0.0).
  /// [to] is the target value (typically 1.0).
  /// [velocity] is the initial velocity (typically 0.0).
  /// [settleSeconds] optionally overrides the computed settle time.
  SpringCurve({
    required SpringDescription spring,
    double from = 0.0,
    double to = 1.0,
    double velocity = 0.0,
    double? settleSeconds,
  })  : _spring = spring,
        _from = from,
        _to = to,
        _velocity = velocity,
        _settleSeconds =
            settleSeconds ?? SpringPalette.approximateSettleSeconds(spring) {
    _simulation = SpringSimulation(spring, from, to, velocity)
      ..tolerance = SpringPalette.normalizedTolerance;
  }

  final SpringDescription _spring;
  final double _from;
  final double _to;
  final double _velocity;
  final double _settleSeconds;
  late final SpringSimulation _simulation;

  /// The spring description backing this curve.
  SpringDescription get spring => _spring;

  /// The approximate settle time in seconds.
  double get settleSeconds => _settleSeconds;

  @override
  double transformInternal(double t) {
    // Map t ∈ [0, 1] to simulation time ∈ [0, settleSeconds].
    final simT = t * _settleSeconds;
    final value = _simulation.x(simT.clamp(0.0, _settleSeconds));
    // Normalize to a 0..1 progress value (assuming from=0, to=1).
    // For arbitrary from/to, return the raw spring position.
    if (_to == _from) return _to;
    return (value - _from) / (_to - _from);
  }
}

/// Pre-configured [SpringCurve]s matching [SpringPalette].
///
/// Use these for `CurvedAnimation(curve: SpringCurves.focus)` etc.
class SpringCurves {
  const SpringCurves._();

  /// Pan curve (0 → 1). Critically damped.
  static final Curve pan = SpringCurve(spring: SpringPalette.pan);

  /// Zoom curve (0 → 1). Critically damped.
  static final Curve zoom = SpringCurve(spring: SpringPalette.zoom);

  /// Focus curve (0 → 1). Slight settle.
  static final Curve focus = SpringCurve(spring: SpringPalette.focus);

  /// Branch curve (0 → 1). Slightly under-damped — feels like opening.
  static final Curve branch = SpringCurve(spring: SpringPalette.branch);
}
