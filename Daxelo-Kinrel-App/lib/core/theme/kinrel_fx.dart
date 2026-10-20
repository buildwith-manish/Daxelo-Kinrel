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

// ═══════════════════════════════════════════════════════════════════════
// 2026-10-19 (Phase 4): KinrelGlass — reusable frosted-glass widget
// ═══════════════════════════════════════════════════════════════════════
//
// A reusable widget that renders a frosted-glass surface on high-end
// devices (real BackdropFilter, sigma <= 12, bounded area, inside its
// own RepaintBoundary) and a solid translucent fill on mid/low devices
// or when over a scrolling area.
//
// Usage:
//   KinrelGlass(
//     tint: Colors.black.withValues(alpha: 0.3),
//     borderRadius: BorderRadius.circular(16),
//     child: myContent,
//   )
//
// The widget automatically:
//   • Wraps itself in a RepaintBoundary (isolates raster cost)
//   • Uses BackdropFilter only when KinrelFx.rich == true AND
//     !inScrollingArea (sigma clamped to 12)
//   • Falls back to a solid translucent fill + 1px border on mid/low
//     tier or when inside a scrolling area
//   • Applies the borderRadius via ClipRRect in both modes

/// A reusable frosted-glass surface widget.
///
/// On high-end devices (`KinrelFx.rich == true`) AND when NOT inside a
/// scrolling area, renders a real [BackdropFilter] with sigma clamped
/// to 12. On mid/low devices or inside scroll, renders a solid
/// translucent fill with the same tint + a 1px border (no blur, no
/// saveLayer — cheap).
///
/// Always wraps in a [RepaintBoundary] to isolate raster cost.
class KinrelGlass extends StatelessWidget {
  const KinrelGlass({
    super.key,
    required this.child,
    this.tint = const Color(0x66000000),
    this.sigma = 12.0,
    this.borderRadius,
    this.inScrollingArea = false,
    this.border = const BorderSide(
      color: Color(0x22FFFFFF),
      width: 1.0,
    ),
  });

  /// The content rendered inside the glass surface.
  final Widget child;

  /// The tint color. On high tier: applied as the child's background
  /// over the blurred backdrop. On low tier: applied as a solid fill.
  final Color tint;

  /// The blur sigma. Clamped to 12.0 max (higher sigmas are expensive
  /// on the GPU and rarely visually distinguishable above 12).
  final double sigma;

  /// Optional border radius. Applied via ClipRRect in both modes.
  final BorderRadius? borderRadius;

  /// Set to true when this glass surface is inside a scrolling area
  /// (e.g. a ListView child, a sliver). When true, the widget ALWAYS
  /// uses the solid fallback (never BackdropFilter) — BackdropFilter
  /// inside a scroll causes per-frame saveLayer which is the #1 source
  /// of raster jank on low-end devices.
  final bool inScrollingArea;

  /// The border. On high tier: 1px hairline. On low tier: 1px hairline
  /// (same — the border is cheap and gives the surface definition).
  final BorderSide border;

  @override
  Widget build(BuildContext context) {
    // Clamp sigma to 12 — higher values are expensive + indistinguishable.
    final effectiveSigma = sigma.clamp(0.0, 12.0);

    // Decide: real blur or solid fallback?
    final useRealBlur = KinrelFx.rich && !inScrollingArea;

    Widget content;
    if (useRealBlur) {
      // High tier + non-scroll: real BackdropFilter.
      content = ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: effectiveSigma,
            sigmaY: effectiveSigma,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tint,
              border: Border(top: border, left: border, right: border, bottom: border),
            ),
            child: child,
          ),
        ),
      );
    } else {
      // Low/mid tier OR scrolling: solid translucent fill, no blur.
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: tint,
          borderRadius: borderRadius,
          border: Border(top: border, left: border, right: border, bottom: border),
        ),
        child: child,
      );
    }

    // Always wrap in RepaintBoundary to isolate the raster cost.
    return RepaintBoundary(child: content);
  }
}
