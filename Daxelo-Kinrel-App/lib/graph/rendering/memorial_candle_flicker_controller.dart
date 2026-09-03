// lib/graph/rendering/memorial_candle_flicker_controller.dart
//
// DAXELO KINREL — Memorial Candle Flicker Controller (P3.4)
//
// Per Vision §6 #4 (WOW 8) — deceased nodes share ONE AnimationController
// so their candles flicker in sync, like a shared remembrance.
//
// The flicker is a sum of sines at 2Hz and 3Hz with a phase offset —
// this produces a flame-like, non-mechanical flicker (a pure sine
// would feel too regular, like a heartbeat). The Curve transforms
// the 0..1 controller value into a 0..1 flicker value.
//
// Reduced motion: the consumer checks `MediaQuery.disableAnimationsOf`
// and, when true, passes a negative sentinel to the painter (which
// renders a static candle).
//
// Performance: only deceased nodes (typically 2-10 in a family) watch
// this provider.
//
// v5.x (PERF FIX — dead ticker removal):
//   • The provider is now `autoDispose` (stops with the graph screen).
//   • The controller NO LONGER runs `.repeat()`. Same reasoning as
//     birthday_pulse_controller.dart: the consumer reads `.value`
//     only during node BUILDS (which happen on cull/LOD changes,
//     never per animation tick), so the flicker never actually
//     animated per-frame — the 1s `.repeat()` ticker was scheduling
//     frames around the clock for a random-snapshot visual. The old
//     bare-Ticker implementation also ignored TickerMode, so it kept
//     running with the app backgrounded, and being a plain
//     (non-autoDispose) provider it ran FOREVER after the first
//     graph visit — saturating the frame pipeline on every screen.
//   • The value is pinned to 0.5, which the [_FlameFlickerCurve]
//     maps to a steady mid-flame (alpha ≈ 0.75). Deceased nodes keep
//     their candle — at zero continuous CPU cost.

import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart' show Ticker, TickerCallback, TickerProvider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A silent [TickerProvider] for the flicker [AnimationController].
class _MemorialCandleTickerProvider implements TickerProvider {
  const _MemorialCandleTickerProvider();
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// A [Curve] that produces a flame-like flicker by summing two sines
/// (2Hz and 3Hz) with a phase offset, then normalizing to [0, 1].
///
/// Kept for API compatibility and unit tests. With the static-value
/// controller it evaluates once at t=0.5 (a steady mid-flame).
class _FlameFlickerCurve extends Curve {
  const _FlameFlickerCurve();

  @override
  double transformInternal(double t) {
    // Two sines at different frequencies + a slow drift. The result
    // is normalized to [0, 1] by mapping sin [-1, 1] → [0, 1].
    final fast = math.sin(2 * math.pi * 3 * t); // 3Hz
    final slow = math.sin(2 * math.pi * 2 * t + 0.7); // 2Hz, phase 0.7
    final drift = 0.3 * math.sin(2 * math.pi * 0.5 * t); // 0.5Hz drift
    final sum = 0.6 * fast + 0.4 * slow + drift;
    // Normalize: sum ranges roughly [-1.3, 1.3]. Map to [0, 1].
    return ((sum + 1.3) / 2.6).clamp(0.0, 1.0);
  }
}

/// Provides the shared memorial-candle flicker [Animation<double>]
/// (static mid-flame value).
///
/// All deceased nodes read this value to drive their candle in sync.
/// Non-deceased nodes do NOT watch this provider.
///
/// v5.x (PERF FIX): autoDispose + no `.repeat()` — see the file
/// header. The value is a constant mid-flame flicker.
final memorialCandleFlickerProvider = Provider.autoDispose<Animation<double>>((ref) {
  final controller = AnimationController(
    duration: const Duration(seconds: 1),
    vsync: const _MemorialCandleTickerProvider(),
    // v5.x (PERF FIX): static mid-flame value — no ticking.
    value: 0.5,
  );
  final animation = CurvedAnimation(
    parent: controller,
    curve: const _FlameFlickerCurve(),
  );
  ref.onDispose(controller.dispose);
  return animation;
});
