// lib/features/chat/presentation/widgets/wallpaper_palette.dart
//
// DAXELO KINREL — Wallpaper Palette + Tint (TASK 1)
//
// Centralizes all wallpaper color/size/alpha values so painters stay
// consistent. The approved Constellation values are the "standard"
// intensity baseline; "subtle" dims everything for a quieter look.
//
// tintWallColor is a pure function that shifts the hue of a base color
// toward a relationship color WITHOUT changing its lightness — so the
// contrast against message bubbles stays the same regardless of tint.

import 'package:flutter/material.dart';

import '../chat_ui_tokens.dart';

/// Intensity preset for wallpaper patterns.
enum WallpaperIntensity { standard, subtle }

/// Pattern alpha factor — multiplies both line and dot alphas.
/// Constellation = 1.0 (full intensity), others are lower.
enum WallpaperPattern {
  constellation(1.0),
  branches(0.7),
  contours(0.6),
  kolam(0.6);

  const WallpaperPattern(this.alphaFactor);
  final double alphaFactor;
}

/// Immutable palette of line/dot colors, alphas, and sizes for a
/// wallpaper pattern. Implements == and hashCode so painters can
/// compare palettes cheaply in shouldRepaint.
class WallpaperPalette {
  const WallpaperPalette({
    required this.lineColor,
    required this.dotColor,
    required this.lineAlpha,
    required this.dotAlpha,
    required this.strokeWidth,
    required this.dotRadius,
  });

  /// Opaque base colors (before alpha). These are the tinted versions
  /// of ChatUi.wallLine / ChatUi.wallDot.
  final Color lineColor;
  final Color dotColor;

  /// Alpha multipliers (0.0–1.0) applied to lineColor/dotColor.
  final double lineAlpha;
  final double dotAlpha;

  /// Line stroke width in logical pixels.
  final double strokeWidth;

  /// Dot radius in logical pixels.
  final double dotRadius;

  /// The approved "standard" Constellation palette (neutral, no tint).
  static const standard = WallpaperPalette(
    lineColor: ChatUi.wallLine,
    dotColor: ChatUi.wallDot,
    lineAlpha: 0.8,
    dotAlpha: 0.9,
    strokeWidth: 1.6,
    dotRadius: 2.5,
  );

  /// The "subtle" palette — quieter alphas and thinner strokes.
  static const subtle = WallpaperPalette(
    lineColor: ChatUi.wallLine,
    dotColor: ChatUi.wallDot,
    lineAlpha: 0.5,
    dotAlpha: 0.6,
    strokeWidth: 1.2,
    dotRadius: 2.0,
  );

  /// Resolve a palette from intensity, tint, and pattern.
  ///
  /// [intensity] selects standard vs subtle alphas/strokes.
  /// [tint] (nullable) shifts the hue of both lineColor and dotColor
  ///   toward the relationship color. Null = neutral (no shift).
  /// [pattern] scales the alphas by its patternFactor.
  factory WallpaperPalette.resolve({
    required WallpaperIntensity intensity,
    Color? tint,
    WallpaperPattern pattern = WallpaperPattern.constellation,
  }) {
    final base = intensity == WallpaperIntensity.subtle ? subtle : standard;
    final af = pattern.alphaFactor;
    final tintedLine = tintWallColor(base.lineColor, tint);
    final tintedDot = tintWallColor(base.dotColor, tint);
    return WallpaperPalette(
      lineColor: tintedLine,
      dotColor: tintedDot,
      lineAlpha: (base.lineAlpha * af).clamp(0.0, 1.0),
      dotAlpha: (base.dotAlpha * af).clamp(0.0, 1.0),
      strokeWidth: base.strokeWidth,
      dotRadius: base.dotRadius,
    );
  }

  /// Convenience: the resolved line paint color (base × alpha).
  Color get resolvedLineColor => lineColor.withValues(alpha: lineAlpha);

  /// Convenience: the resolved dot paint color (base × alpha).
  Color get resolvedDotColor => dotColor.withValues(alpha: dotAlpha);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WallpaperPalette &&
          lineColor == other.lineColor &&
          dotColor == other.dotColor &&
          lineAlpha == other.lineAlpha &&
          dotAlpha == other.dotAlpha &&
          strokeWidth == other.strokeWidth &&
          dotRadius == other.dotRadius;

  @override
  int get hashCode => Object.hash(
        lineColor,
        dotColor,
        lineAlpha,
        dotAlpha,
        strokeWidth,
        dotRadius,
      );
}

/// Pure function: tints a [base] color toward [tint]'s hue without
/// changing the base's lightness.
///
/// Converts both to HSL, then returns a color with:
///   hue = tint's hue
///   saturation = min(tint's saturation, 0.55)
///   lightness = base's lightness (so brightness/contrast stays)
///   alpha = 1.0 (opaque)
///
/// [tint] null returns [base] exactly.
Color tintWallColor(Color base, Color? tint) {
  if (tint == null) return base;

  final baseHsl = HSLColor.fromColor(base);
  final tintHsl = HSLColor.fromColor(tint);

  return HSLColor.fromAHSL(
    1.0,
    tintHsl.hue,
    tintHsl.saturation.clamp(0.0, 0.55),
    baseHsl.lightness,
  ).toColor();
}
