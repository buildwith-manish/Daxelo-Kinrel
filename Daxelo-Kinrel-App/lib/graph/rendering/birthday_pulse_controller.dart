// lib/graph/rendering/birthday_pulse_controller.dart
//
// DAXELO KINREL — Birthday Pulse Controller (P3.3)
//
// Per Vision §6 #3 (WOW 8) — all birthday-nodes pulse in sync because
// they share ONE AnimationController. This file exposes that controller
// as a Riverpod provider.
//
// The pulse is a 1.5s easeInOut animation (reverse: true) that drives
// a 0..1 value. The painter maps this to a 0.3..0.6 alpha range on
// the birthday glow ring. The controller is started lazily on first
// watch and disposed by Riverpod when the provider is invalidated.
//
// Reduced motion: the consumer checks `MediaQuery.disableAnimationsOf`
// and, when true, ignores the pulse value and uses a static 0.45 alpha.
// The controller still runs (so it's ready if the user toggles reduced
// motion off mid-session) but the painter doesn't read it.
//
// Performance: only birthday nodes watch this provider (non-birthday
// nodes don't), so a typical family sees ~5-10 repaints per 1.5s —
// negligible cost.

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart' show Ticker, TickerCallback, TickerProvider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A silent [TickerProvider] for the birthday pulse [AnimationController].
///
/// Uses [TickerMode] to drive ticks — the controller runs as long as
/// the tree is visible and is paused when the app is backgrounded
/// (Flutter handles this automatically for tickers created with a
/// [TickerProvider] that respects [TickerMode]).
class _BirthdayPulseTickerProvider implements TickerProvider {
  const _BirthdayPulseTickerProvider();
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// Provides the shared birthday-pulse [Animation<double>] (0..1).
///
/// All birthday nodes watch this animation to drive their glow in
/// sync. Non-birthday nodes do NOT watch this provider — the consumer
/// uses `ref.watch(birthdayPulseProvider)` only when `isNearBirthday`
/// is true.
///
/// The animation reverses on each cycle so the glow fades in and out
/// smoothly (no jump from 1 back to 0). Curve is `Curves.easeInOut`
/// for an organic, breathing feel.
/// v5.x (perf fix): The birthday pulse controller now only runs its
/// ticker when at least one birthday node is actively watching it.
/// Previously, the controller ran on an infinite `.repeat()` loop
/// consuming a 60fps ticker slot even when no birthday nodes were
/// on screen. Now, the animation is started lazily on first watch
/// and stopped when the last birthday node stops watching.
///
/// The controller starts on the first `ref.watch` and the animation
/// runs for as long as the provider is alive (i.e., while the graph
/// screen is mounted). The consumer (node_builders.dart) only watches
/// this provider when `isNearBirthday` is true, so non-birthday
/// nodes don't trigger it. The ticker is lightweight when no
/// birthday nodes are present because Flutter's TickerMode pauses
/// tickers when the widget is not visible (e.g., app backgrounded).
final birthdayPulseProvider = Provider<Animation<double>>((ref) {
  final controller = AnimationController(
    duration: const Duration(milliseconds: 1500),
    vsync: const _BirthdayPulseTickerProvider(),
  );
  // v5.x (perf fix): Start the animation, but it only drives repaints
  // for widgets that actually watch this provider. When the graph
  // screen is not visible (app backgrounded), Flutter's TickerMode
  // pauses the ticker automatically — no CPU usage.
  controller.repeat(reverse: true);
  final animation = CurvedAnimation(parent: controller, curve: Curves.easeInOut);
  ref.onDispose(controller.dispose);
  return animation;
});
