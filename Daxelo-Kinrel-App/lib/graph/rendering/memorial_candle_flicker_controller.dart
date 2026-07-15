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
// renders a static candle). The controller still runs so it's ready
// if the user toggles reduced motion off mid-session.
//
// Performance: only deceased nodes (typically 2-10 in a family) watch
// this provider. Negligible cost.

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
/// The controller runs at 1.0s duration with `repeat()` (no reverse),
/// so the curve sees t ∈ [0, 1] over 1 second. At 2Hz, that's 2 full
/// cycles per second; at 3Hz, 3 cycles. The sum creates an irregular
/// but bounded flicker.
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

/// Provides the shared memorial-candle flicker [Animation<double>] (0..1).
///
/// All deceased nodes watch this animation to drive their candle
/// flicker in sync. Non-deceased nodes do NOT watch this provider.
///
/// The flicker runs at ~3Hz (fast sine) modulated by a 2Hz slow sine
/// and a 0.5Hz drift — a flame-like, non-mechanical pattern.
final memorialCandleFlickerProvider = Provider<Animation<double>>((ref) {
  final controller = AnimationController(
    duration: const Duration(seconds: 1),
    vsync: const _MemorialCandleTickerProvider(),
  )..repeat();
  final animation = CurvedAnimation(
    parent: controller,
    curve: const _FlameFlickerCurve(),
  );
  ref.onDispose(controller.dispose);
  return animation;
});
