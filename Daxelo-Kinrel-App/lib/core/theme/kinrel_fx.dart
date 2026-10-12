// lib/core/theme/kinrel_fx.dart
//
// DAXELO KINREL — Flat UI master switch.
//
// Single source of truth for whether the app renders the original
// decorated look (gradients, shadows, blur, glow loops) or the flat
// look (solid colors, hairline borders, no offscreen layers).
//
// Default is FLAT (rich == false). Pass `--dart-define=RICH_FX=true`
// at build time to restore the original decorated look.
//
// ── Why a single switch? ────────────────────────────────────────────
// The flat conversion touched dozens of files. A future designer who
// wants to A/B compare against the old look would otherwise have to
// revert dozens of commits. With KinrelFx, one build define restores
// every decorated branch.
//
// ── How to use ─────────────────────────────────────────────────────
//   // BoxShadow list:
//   boxShadow: KinrelFx.shadows(const [BoxShadow(color: Colors.black54, blurRadius: 8)]),
//
//   // BackdropFilter frosted-glass with solid fallback:
//   child: KinrelFx.glass(
//     fallbackColor: KinrelColors.darkCard.withValues(alpha: 0.92),
//     child: content,
//   ),
//
//   // Gradient (kept ONLY on primary orange CTAs + KINREL logo):
//   gradient: KinrelFx.gradient(KinrelGradients.igniteGradient),
//
//   // Generic boolean:
//   if (KinrelFx.rich) { /* decorated branch */ } else { /* flat branch */ }
//

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Single switch for the entire app's decoration level.
///
/// When `rich == false` (the default), every helper returns the flat
/// equivalent. When `rich == true` (passed at build time via
/// `--dart-define=RICH_FX=true`), every helper returns the original
/// decorated value.
class KinrelFx {
  KinrelFx._();

  /// Compile-time flag. Defaults to `false` (flat).
  /// Set to `true` with `--dart-define=RICH_FX=true`.
  static const bool rich = bool.fromEnvironment('RICH_FX', defaultValue: false);

  // ── BoxShadow ────────────────────────────────────────────────────

  /// Returns the shadows unchanged when [rich] is true; returns the
  /// empty const list when [rich] is false (flat = no shadows).
  ///
  /// Use anywhere a `boxShadow:` argument would otherwise be passed.
  ///   boxShadow: KinrelFx.shadows(const [BoxShadow(blurRadius: 8, ...)]),
  ///
  /// The `shadows` argument is a const list literal so the original
  /// allocation is free; the helper simply discards it in flat mode.
  static List<BoxShadow> shadows(List<BoxShadow> shadows) {
    return rich ? shadows : const <BoxShadow>[];
  }

  // ── BackdropFilter / frosted glass ───────────────────────────────

  /// Returns a [BackdropFilter] with the given [sigma] wrapping [child]
  /// when [rich] is true; returns a solid-color [Container] with
  /// [fallbackColor] when [rich] is false (flat = no blur).
  ///
  /// Use wherever a frosted-glass panel previously wrapped a child.
  ///   child: KinrelFx.glass(
  ///     fallbackColor: KinrelColors.darkCard.withValues(alpha: 0.92),
  ///     sigma: 16,
  ///     borderRadius: BorderRadius.circular(12),
  ///     child: content,
  ///   ),
  ///
  /// In flat mode the [child] is wrapped in a [DecoratedBox] with the
  /// solid [fallbackColor] (no blur, no saveLayer). The optional
  /// [borderRadius] is applied via [ClipRRect] in both modes so the
  /// rounded corner shape is preserved.
  static Widget glass({
    required Color fallbackColor,
    required Widget child,
    double sigma = 16.0,
    BorderRadius? borderRadius,
  }) {
    if (!rich) {
      // Flat: solid color, no blur. Still clip to the rounded shape
      // so the caller's borderRadius contract is preserved.
      if (borderRadius == null) {
        return DecoratedBox(
          decoration: BoxDecoration(color: fallbackColor),
          child: child,
        );
      }
      return ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(color: fallbackColor),
          child: child,
        ),
      );
    }
    // Rich: original BackdropFilter frosted glass.
    if (borderRadius == null) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      );
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }

  // ── Gradient ──────────────────────────────────────────────────────

  /// Returns the [gradient] unchanged when [rich] is true; returns
  /// `null` when [rich] is false so the caller's BoxDecoration falls
  /// back to its solid `color:` argument.
  ///
  /// Use ONLY for gradients that should be flattened in flat mode.
  /// Primary orange CTA buttons + KINREL logo keep their gradients
  /// unconditionally — do NOT route those through this helper.
  ///
  ///   gradient: KinrelFx.gradient(myLinearGradient),
  ///   color: KinrelColors.darkSurface,  // ← used in flat mode
  ///
  static Gradient? gradient(Gradient gradient) {
    return rich ? gradient : null;
  }

  // ── Opacity ──────────────────────────────────────────────────────

  /// Returns the [opacity] value unchanged when [rich] is true;
  /// returns `1.0` when [rich] is false so the caller can use a
  /// solid color with pre-multiplied alpha instead of an [Opacity]
  /// widget (which creates an offscreen layer).
  ///
  /// Use ONLY for decorative Opacity widgets (e.g. faded backgrounds,
  /// ambient overlays). State-indicator Opacity widgets (typing dots,
  /// recording dots, presence dots) should NOT use this — those are
  /// short-lived state signals, not decoration.
  ///
  /// Caller pattern:
  ///   // Before: Opacity(opacity: 0.5, child: Container(color: Colors.red))
  ///   // After:
  ///   Container(color: Colors.red.withValues(alpha: KinrelFx.opacity(0.5)))
  ///
  static double opacity(double opacity) {
    return rich ? opacity : 1.0;
  }

  // ── Booleans for ad-hoc branching ─────────────────────────────────

  /// True when decorative looping animations should run.
  /// Always false in flat mode.
  ///
  ///   if (KinrelFx.decorativeAnimation) { _controller.repeat(); }
  ///
  static bool get decorativeAnimation => rich;

  /// True when glow/halo effects should render.
  /// Always false in flat mode.
  static bool get glow => rich;

  /// True when 3D / pseudo-3D node decorations should render.
  /// Always false in flat mode.
  static bool get pseudo3d => rich;

  /// True when ambient particles should be visible.
  /// Always false in flat mode.
  static bool get ambientParticles => rich;
}
