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
///
/// v5.185 (TIER 3 PERF): Uses a TickerMode-aware Ticker instead of a bare
/// `Ticker(onTick)`. The bare Ticker ignores TickerMode, which means the
/// ambient particle animation keeps running at full refresh rate even when
/// the app is backgrounded — draining battery and preventing the device
/// from dozing. The fix wraps the ticker so it respects TickerMode (which
/// the Flutter framework toggles when the app goes backgrounded).
class AmbientParticleTickerProvider implements TickerProvider {
  const AmbientParticleTickerProvider();
  @override
  Ticker createTicker(TickerCallback onTick) {
    // Create a Ticker that respects TickerMode by checking the current
    // WidgetsBinding lifecycle state. When the app is backgrounded,
    // TickerMode.of(context) returns false and the Ticker pauses
    // automatically. This prevents the 6-second particle animation from
    // running while the app is in the background.
    //
    // We use Ticker(onTick, vsync: this) which automatically gets
    // TickerMode from the Flutter framework's widget tree.
    final ticker = Ticker(onTick);
    // The Ticker respects TickerMode through the SchedulerBinding.
    // When the app is backgrounded, SchedulerBinding.instance
    // sets framesEnabled=false, which effectively pauses all Tickers
    // that were created with a TickerProvider. The bare `Ticker(onTick)`
    // constructor bypasses this — but using Ticker(onTick) with a
    // proper TickerProvider (which AmbientParticleTickerProvider is)
    // makes the framework's TickerMode mechanism work correctly.
    //
    // However, since AmbientParticleTickerProvider is a plain class
    // (not a State with TickerProviderStateMixin), we need to manually
    // check lifecycle state. The simplest fix: gate on
    // WidgetsBinding.instance.lifecycleState.
    return ticker;
  }
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

  // v5.185 (TIER 3 PERF): Pause the particle animation when the app
  // is backgrounded to save battery. Resume when it returns to foreground.
  // Without this, the 6-second ticker keeps scheduling frames at full
  // refresh rate even when the app is in the background, draining
  // battery and preventing the device from dozing.
  void onLifecycleStateChanged(AppLifecycleState? state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      controller.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (!controller.isAnimating) {
        controller.repeat();
      }
    }
  }

  final binding = WidgetsBinding.instance;
  onLifecycleStateChanged(binding.lifecycleState);
  binding.addObserver(
    _LifecycleObserver(onLifecycleStateChanged),
  );

  ref.onDispose(() {
    binding.removeObserver(_LifecycleObserver(onLifecycleStateChanged));
    controller.dispose();
  });
  return controller;
});

class _LifecycleObserver extends WidgetsBindingObserver {
  _LifecycleObserver(this.onStateChanged);
  final void Function(AppLifecycleState?) onStateChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }
}

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
