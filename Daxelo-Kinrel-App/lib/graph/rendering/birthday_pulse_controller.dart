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
// the birthday glow ring.
//
// Reduced motion: the consumer checks `MediaQuery.disableAnimationsOf`
// and, when true, ignores the pulse value and uses a static 0.45 alpha.
//
// v5.x (PERF FIX — dead ticker removal):
//   • The provider is now `autoDispose` (stops with the graph screen).
//   • The controller NO LONGER runs `.repeat(reverse: true)`. The
//     consumer (node_builders.dart) reads `.value` ONCE per node
//     BUILD — nodes only rebuild on cull/LOD changes (every ~80px of
//     pan), never per animation tick, so the "pulse" never actually
//     animated per-frame. The 60fps ticker was scheduling frames
//     around the clock for a visual that was, in practice, a random
//     snapshot value. Worse, the old custom TickerProvider created
//     bare Tickers that do NOT respect TickerMode, so the ticker kept
//     running even with the app backgrounded — and being a plain
//     (non-autoDispose) provider it kept running FOREVER after the
//     first graph visit, saturating the frame pipeline at full
//     refresh rate on every other screen too.
//   • The value is pinned to the mid-pulse (0.5 → 0.45 alpha), which
//     renders the same average glow the "pulse" produced. Birthday
//     nodes keep their warm ring — at zero continuous CPU cost.
//     This is the WhatsApp/Telegram-class approach: decorative
//     effects never keep the frame pipeline awake.
//
// Performance: non-birthday nodes never watch this provider
// (the consumer uses `ref.watch(birthdayPulseProvider)` only when
// `isNearBirthday` is true), so the provider is only alive while the
// graph screen is mounted AND at least one near-birthday node is on
// screen — and now costs nothing while alive.

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart' show Ticker, TickerCallback, TickerProvider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A silent [TickerProvider] for the birthday pulse [AnimationController].
class _BirthdayPulseTickerProvider implements TickerProvider {
  const _BirthdayPulseTickerProvider();
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

/// Provides the shared birthday-pulse [Animation<double>] (static 0.5).
///
/// All birthday nodes read this value to drive their glow in sync.
/// Non-birthday nodes do NOT watch this provider — the consumer
/// (node_builders.dart) only watches when `isNearBirthday` is true.
///
/// v5.x (PERF FIX): autoDispose + no `.repeat()` — see the file header.
/// The value is a constant mid-pulse (the painter renders it as the
/// steady warm glow it always averaged to in practice).
final birthdayPulseProvider = Provider.autoDispose<Animation<double>>((ref) {
  final controller = AnimationController(
    duration: const Duration(milliseconds: 1500),
    vsync: const _BirthdayPulseTickerProvider(),
    // v5.x (PERF FIX): static mid-pulse value — no ticking. See the
    // file header for why the ticker was pure wasted CPU.
    value: 0.5,
  );
  final animation = CurvedAnimation(parent: controller, curve: Curves.easeInOut);
  ref.onDispose(controller.dispose);
  return animation;
});
