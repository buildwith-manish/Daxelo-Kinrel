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
// draws static motes) and does NOT watch the animation — with
// autoDispose that means the ticker is fully stopped.
//
// v5.x (PERF FIX — idle frame-rate saturation):
//   • The provider is now `autoDispose`: when the graph screen is
//     closed (the particle layer stops watching), Riverpod disposes
//     the controller and the ticker STOPS. Previously this was a
//     plain Provider, so after the user visited the graph ONCE the
//     6-second `.repeat()` ticker kept scheduling frames at the
//     device's full refresh rate FOREVER (even on other screens,
//     even with the app backgrounded) — permanently saturating the
//     UI/raster threads and draining battery.
//   • The controller is exposed directly so the engine view can
//     PAUSE the animation during pan/zoom gestures (see
//     interaction_mixin.dart `_onScaleStart`/`_onScaleEnd`): the
//     gesture gets the full frame budget, and the motes resume
//     drifting on release.
//   • NOTE: the old custom `_AmbientParticleTickerProvider` created
//     bare `Ticker`s that do NOT respect TickerMode — they kept
//     ticking even when the app was backgrounded. autoDispose +
//     gesture pausing removes that class of leak entirely.

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart' show Ticker, TickerCallback, TickerProvider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A silent [TickerProvider] for the ambient particle [AnimationController].
class AmbientParticleTickerProvider implements TickerProvider {
  const AmbientParticleTickerProvider();
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// Provides the shared ambient-particle [AnimationController]
/// (0..1, 6s loop, auto-disposed).
///
/// The controller is exposed so the graph engine can pause/resume it
/// around gestures. While the particle layer is mounted it watches
/// [ambientParticleProvider] (which watches this provider), keeping
/// the controller alive; when the graph screen closes the whole chain
/// auto-disposes and the ticker stops.
final ambientParticleControllerProvider =
    Provider.autoDispose<AnimationController>((ref) {
  final controller = AnimationController(
    duration: const Duration(seconds: 6),
    vsync: const AmbientParticleTickerProvider(),
  )..repeat();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Provides the shared ambient-particle [Animation<double>] (0..1, 6s loop).
///
/// The consumer passes `animation.value` as `t` to [AmbientParticlePainter].
/// One full cycle (0 → 1 → 0 → 1 ...) takes 6 seconds, matching the spec's
/// "6-second period" drift.
///
/// v5.x (PERF FIX): `autoDispose` — the animation only lives while the
/// graph's particle layer is actually watching it.
final ambientParticleProvider = Provider.autoDispose<Animation<double>>(
  (ref) => ref.watch(ambientParticleControllerProvider),
);
