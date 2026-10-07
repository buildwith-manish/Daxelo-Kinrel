// lib/core/utils/perf_lab.dart
//
// DAXELO KINREL — Hidden Performance Test Lab (PERF_LAB)
//
// A compile-time-gated set of ValueNotifier<bool> switches used ONLY to
// measure which part of the chat screen costs raster (GPU) time on a
// physical device. The lab is opt-in via the PERF_LAB dart-define:
//
//   flutter build apk --profile --dart-define=PERF_LAB=true
//
// STRICT RULE:
//   • With PERF_LAB off (default, and every release build), the app
//     must behave and look EXACTLY as on main. No code path that reads
//     a switch may add a rebuild, a listener, or any runtime cost when
//     [enabled] is false.
//   • With PERF_LAB on AND every switch off, the app must also render
//     exactly as main. The switches are toggled manually from the lab
//     panel (see lib/main.dart) to bisect the raster cost.
//
// Why a const bool:
//   [enabled] is a `static const bool` driven by `bool.fromEnvironment`.
//   When PERF_LAB is not defined at compile time, [enabled] is the
//   constant `false`. Every call site guards with
//   `if (PerfLab.enabled && PerfLab.<switch>.value)` — the `&&`
//   short-circuits on the const-false left operand so the right operand
//   is never evaluated at runtime, AND the Dart AOT compiler tree-shakes
//   the entire branch (no ValueNotifier field is ever touched, no
//   ValueListenableBuilder is ever constructed, no listener is ever
//   registered). This is what makes the lab zero-cost in release builds.
//
// Never print or store tokens or secrets. This file intentionally has no
// imports beyond Flutter material widgets (material.dart re-exports the
// foundation symbols we need — ValueNotifier, ValueListenableBuilder,
// StatelessWidget, BuildContext, Widget — so a separate
// `import 'package:flutter/foundation.dart';` would be redundant and
// trigger the analyzer's `unnecessary_import` lint).

import 'package:flutter/material.dart';

/// Compile-time gate for the entire performance lab.
///
/// `bool.fromEnvironment` evaluates to a compile-time constant, so
/// `PerfLab.enabled` is `const false` when PERF_LAB is not passed via
/// `--dart-define=PERF_LAB=true`. This is what makes every call site
/// that guards on `PerfLab.enabled` zero-cost when the lab is disabled.
///
/// Note: `bool.fromEnvironment` requires `const` to be a compile-time
/// constant; declaring the field `static const` makes it usable as a
/// const expression in `if`-conditions, which the Dart AOT compiler
/// uses to tree-shake dead branches.

/// Container for the five lab switches and the compile-time [enabled] gate.
///
/// Every switch is a [ValueNotifier<bool>] defaulting to `false` so that
/// with PERF_LAB on but no switch toggled, the app renders exactly as
/// main. The switches are intended to be toggled at runtime from the lab
/// panel (a small semi-transparent "LAB" chip rendered by the
/// MaterialApp builder when [enabled] is true — see lib/main.dart).
///
/// The five switches:
///   • [plainBackground]    — chat background becomes a flat solid color
///     (theme background), skipping all gradients, wallpaper and blur.
///   • [flatBubbles]        — message bubble decoration uses the first
///     gradient color as a solid fill with no BoxShadow, no glow and no
///     gradient. Radius, padding and border are preserved.
///   • [plainInviteCards]   — game-invite card collapses to a simple
///     container with content text only: no game icon image, no chips,
///     no gradients.
///   • [hideChrome]         — chat header, input bar and floating
///     family nav are replaced with SizedBox.shrink so the layout does
///     not crash but all the chrome is removed.
///   • [pauseAnimations]    — the entire app content is wrapped in
///     `TickerMode(enabled: false)` to disable all tickers (animation,
///     shimmer, transitions) without changing widget structure.
class PerfLab {
  PerfLab._();

  /// Compile-time gate. `true` only when built with
  /// `--dart-define=PERF_LAB=true`. When `false`, every call site that
  /// guards on this flag is tree-shaken by the Dart AOT compiler.
  static const bool enabled = bool.fromEnvironment('PERF_LAB');

  /// Switch: replace the multi-layer chat background with a flat solid
  /// color (the theme's scaffold background).
  ///
  /// Only read when [enabled] is true. The static field is lazily
  /// initialized by the Dart runtime — when [enabled] is false no call
  /// site ever touches this field, so the ValueNotifier is never even
  /// constructed in release builds.
  static final ValueNotifier<bool> plainBackground =
      ValueNotifier<bool>(false);

  /// Switch: collapse message-bubble decoration to a solid-fill single
  /// color (the first gradient color) with no BoxShadow, no glow and no
  /// gradient. Radius, padding and border are preserved.
  static final ValueNotifier<bool> flatBubbles = ValueNotifier<bool>(false);

  /// Switch: collapse game-invite cards to a simple container with the
  /// content text only. No game icon image, no chips, no gradients.
  static final ValueNotifier<bool> plainInviteCards =
      ValueNotifier<bool>(false);

  /// Switch: hide the chat header (AppBar), the chat input bar and the
  /// floating family nav. Each is replaced with a SizedBox.shrink (or an
  /// empty box of the same approximate size) so the layout doesn't crash.
  static final ValueNotifier<bool> hideChrome = ValueNotifier<bool>(false);

  /// Switch: wrap the entire app content in `TickerMode(enabled: false)`
  /// to disable all animation tickers without altering widget structure.
  /// Useful for measuring raster cost when animations are paused.
  static final ValueNotifier<bool> pauseAnimations =
      ValueNotifier<bool>(false);

  /// Reset all five switches to `false`. Called by the "Reset" button in
  /// the lab panel. Only meaningful when [enabled] is true; call sites
  /// that invoke this are themselves guarded by [enabled], so when the
  /// lab is disabled this method is never invoked (and the notifiers are
  /// never constructed).
  static void reset() {
    plainBackground.value = false;
    flatBubbles.value = false;
    plainInviteCards.value = false;
    hideChrome.value = false;
    pauseAnimations.value = false;
  }
}

/// A small helper widget that subscribes to a PerfLab [ValueNotifier<bool>]
/// switch when [PerfLab.enabled] is true, returning [child] unchanged
/// otherwise.
///
/// When PERF_LAB is off (compile-time const false):
///   • `if (!PerfLab.enabled) return child;` is the only branch taken.
///   • The [ValueListenableBuilder] constructor is never invoked, so no
///     listener is ever registered and no rebuild can ever fire.
///   • The Dart AOT compiler tree-shakes the ValueListenableBuilder
///     branch entirely.
///
/// When PERF_LAB is on:
///   • [child] is wrapped in [ValueListenableBuilder] listening to
///     [notifier]. The subtree rebuilds whenever the switch toggles.
///     Downstream widgets can read `notifier.value` directly inside
///     their own build methods to branch on the current switch state.
///
/// Use this to opt a subtree into rebuilding on a PerfLab switch without
/// paying any listener cost in release builds.
///
/// Example:
/// ```dart
/// return PerfLabSwitch(
///   notifier: PerfLab.plainBackground,
///   child: _buildDefaultTree(context, ref),
/// );
/// ```
class PerfLabSwitch extends StatelessWidget {
  const PerfLabSwitch({
    super.key,
    required this.notifier,
    required this.child,
  });

  /// The PerfLab switch to listen to. Only listened to when
  /// [PerfLab.enabled] is true.
  final ValueNotifier<bool> notifier;

  /// The subtree to return. When [PerfLab.enabled] is false this is
  /// returned unchanged with zero overhead.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // PERF_LAB compile-time gate. When `enabled` is const false, the
    // `!enabled` is const true and the `return child;` is the only
    // branch compiled. The ValueListenableBuilder below is dead code
    // and is tree-shaken by the AOT compiler — no listener is ever
    // registered, no rebuild can fire.
    if (!PerfLab.enabled) return child;

    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      // The builder returns `child` unchanged; the value is ignored
      // because the only purpose of this wrapper is to force the
      // subtree to rebuild when the switch toggles. Downstream widgets
      // read `notifier.value` directly inside their own build methods.
      builder: (context, value, child) => child!,
      child: child,
    );
  }
}
