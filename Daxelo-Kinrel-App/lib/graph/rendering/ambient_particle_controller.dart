// lib/graph/rendering/ambient_particle_controller.dart
//
// DAXELO KINREL — Ambient Particle Controller (P3.5)
//
// Per Vision §6 #6 (WOW 7) — subtle gold motes drift slowly around
// the anchor node. This provider exposes the shared AnimationController
// (6-second loop) that drives the drift.
//
// Only the anchor's particle layer watches this provider — non-anchor
// nodes don't. So the cost is 1 repaint per frame on ONE CustomPaint
// (25 circles), negligible.
//
// Reduced motion: the consumer checks `MediaQuery.disableAnimationsOf`
// and, when true, passes `reducedMotion: true` to the painter (which
// draws static motes). The controller still runs so it's ready if the
// user toggles reduced motion off mid-session.

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart' show Ticker, TickerCallback, TickerProvider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A silent [TickerProvider] for the ambient particle [AnimationController].
class _AmbientParticleTickerProvider implements TickerProvider {
  const _AmbientParticleTickerProvider();
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// Provides the shared ambient-particle [Animation<double>] (0..1, 6s loop).
///
/// The consumer passes `animation.value` as `t` to [AmbientParticlePainter].
/// One full cycle (0 → 1 → 0 → 1 ...) takes 6 seconds, matching the spec's
/// "6-second period" drift.
final ambientParticleProvider = Provider<Animation<double>>((ref) {
  final controller = AnimationController(
    duration: const Duration(seconds: 6),
    vsync: const _AmbientParticleTickerProvider(),
  )..repeat();
  // No curve — the painter applies its own sine curves per mote.
  ref.onDispose(controller.dispose);
  return controller;
});
