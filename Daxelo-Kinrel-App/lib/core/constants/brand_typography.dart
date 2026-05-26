import 'package:flutter/material.dart';

/// KINREL Typography System
///
/// Font Families:
///   - Outfit   → Display font (headlines, hero text, app name)
///   - DM Sans  → Body font (body text, descriptions, UI labels)
///   - DM Mono  → Mono font (labels, tags, technical info, relationship paths)
///
/// Rules:
///   - Never use DM Sans below 11px — use DM Mono for anything smaller
///   - Warm white (#F5F0EE) for primary text on dark — never pure #FFFFFF
///   - Silver (#C9B4A8) for secondary/body text
///   - Orange (#E8612A) for accent text
///   - Numbers in relationship counts should use Outfit Bold
///   - "KINREL" always in Outfit ExtraBold with tracking +0.14em minimum
class KinrelTypography {
  KinrelTypography._();

  // ── Font Families ───────────────────────────────────────────
  static const String displayFont = 'Outfit';
  static const String bodyFont = 'DMSans';
  static const String monoFont = 'DMMono';

  // ── Text Color Tokens ───────────────────────────────────────
  /// Warm white for primary text on dark backgrounds — never pure #FFFFFF
  static const Color textPrimary = Color(0xFFF5F0EE);

  /// Silver for secondary / body text
  static const Color textSecondary = Color(0xFFC9B4A8);

  /// Orange for accent text
  static const Color textAccent = Color(0xFFE8612A);

  // ── Type Scale (Material 3 compatible) ──────────────────────

  // ── Display ─────────────────────────────────────────────────

  /// Outfit 800 · 32px · tracking +0.16em (5.12) · height 1.1 (35.2)
  static const TextStyle displayLarge = TextStyle(
    fontFamily: displayFont,
    fontSize: 32.0,
    fontWeight: FontWeight.w800,
    letterSpacing: 5.12,
    height: 1.1,
  );

  /// Outfit 700 · 28px · tracking +0.12em (3.36) · height 1.15 (32.2)
  static const TextStyle displayMedium = TextStyle(
    fontFamily: displayFont,
    fontSize: 28.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 3.36,
    height: 1.15,
  );

  /// Outfit 700 · 24px · tracking +0.10em (2.4) · height 1.2 (28.8)
  static const TextStyle displaySmall = TextStyle(
    fontFamily: displayFont,
    fontSize: 24.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.4,
    height: 1.2,
  );

  // ── Headline ────────────────────────────────────────────────

  /// DM Sans 700 · 22px · tracking +0.02em (0.44) · height 1.25 (27.5)
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: bodyFont,
    fontSize: 22.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.44,
    height: 1.25,
  );

  /// DM Sans 700 · 18px · tracking +0.01em (0.18) · height 1.3 (23.4)
  static const TextStyle headlineMedium = TextStyle(
    fontFamily: bodyFont,
    fontSize: 18.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.18,
    height: 1.3,
  );

  /// DM Sans 600 · 16px · tracking +0.005em (0.08) · height 1.35 (21.6)
  static const TextStyle headlineSmall = TextStyle(
    fontFamily: bodyFont,
    fontSize: 16.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.08,
    height: 1.35,
  );

  // ── Body ────────────────────────────────────────────────────

  /// DM Sans 400 · 16px · tracking 0 · height 1.6 (25.6)
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: bodyFont,
    fontSize: 16.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.6,
  );

  /// DM Sans 400 · 14px · tracking 0 · height 1.55 (21.7)
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: bodyFont,
    fontSize: 14.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.55,
  );

  /// DM Sans 400 · 12px · tracking 0 · height 1.5 (18.0)
  static const TextStyle bodySmall = TextStyle(
    fontFamily: bodyFont,
    fontSize: 12.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  // ── Label ───────────────────────────────────────────────────

  /// DM Sans 500 · 14px · tracking 0 · height 1.4
  static const TextStyle labelLarge = TextStyle(
    fontFamily: bodyFont,
    fontSize: 14.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.4,
  );

  /// DM Sans 500 · 12px · tracking 0 · height 1.4
  static const TextStyle labelMedium = TextStyle(
    fontFamily: bodyFont,
    fontSize: 12.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.4,
  );

  /// DM Sans 500 · 11px · tracking +0.03em (0.33) · height 1.4
  static const TextStyle labelSmall = TextStyle(
    fontFamily: bodyFont,
    fontSize: 11.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.33,
    height: 1.4,
  );

  // ── Caption ─────────────────────────────────────────────────

  /// DM Sans 500 · 11px · tracking +0.03em (0.33) · height 1.4
  static const TextStyle caption = TextStyle(
    fontFamily: bodyFont,
    fontSize: 11.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.33,
    height: 1.4,
  );

  // ── Overline ────────────────────────────────────────────────

  /// DM Mono 500 · 10px · tracking +0.25em (2.5) · height 1.3 · UPPERCASE
  static const TextStyle overline = TextStyle(
    fontFamily: monoFont,
    fontSize: 10.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 2.5,
    height: 1.3,
  );

  // ── Micro ───────────────────────────────────────────────────

  /// DM Mono 400 · 9px · tracking +0.20em (1.8) · height 1.2 · UPPERCASE
  static const TextStyle micro = TextStyle(
    fontFamily: monoFont,
    fontSize: 9.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 1.8,
    height: 1.2,
  );

  // ── Brand-specific Styles ──────────────────────────────────

  /// "KINREL" app name — Outfit ExtraBold with +0.14em minimum tracking
  static const TextStyle appName = TextStyle(
    fontFamily: displayFont,
    fontSize: 32.0,
    fontWeight: FontWeight.w800,
    letterSpacing: 4.48, // 32 * 0.14
    height: 1.1,
  );

  /// Relationship count numbers — Outfit Bold
  static const TextStyle relationCount = TextStyle(
    fontFamily: displayFont,
    fontSize: 24.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    height: 1.2,
  );

  // ── Font Scale Factors ──────────────────────────────────────
  static const double scaleSmall = 0.85;
  static const double scaleMedium = 1.0;
  static const double scaleLarge = 1.15;
  static const double scaleExtraLarge = 1.3;

  // ── Legacy / Backward-compat Aliases ────────────────────────
  // These map old property names to their closest new equivalent
  // so that existing code continues to compile.

  /// @deprecated Use [displayLarge] instead.
  static const TextStyle displayHero = displayLarge;

  /// @deprecated Use [headlineMedium] instead.
  static const TextStyle sectionHeader = headlineMedium;

  /// @deprecated Use [headlineSmall] instead.
  static const TextStyle titleLarge = headlineSmall;

  /// @deprecated Use [labelLarge] instead.
  static const TextStyle titleMedium = labelLarge;

  /// @deprecated Use [labelMedium] instead.
  static const TextStyle titleSmall = labelMedium;

  /// @deprecated Use [micro] or [overline] instead.
  static const TextStyle monoBody = TextStyle(
    fontFamily: monoFont,
    fontSize: 13.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  /// @deprecated Use [bylineDaxelo] tracking value via style instead.
  static const double bylineDaxelo = 0.15;

  // ── Convenience: Build a ThemeData TextTheme ────────────────

  /// Returns a [TextTheme] populated with every style in the scale.
  /// Useful for `ThemeData(textTheme: KinrelTypography.textTheme)`.
  static TextTheme get textTheme => TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        displaySmall: displaySmall,
        headlineLarge: headlineLarge,
        headlineMedium: headlineMedium,
        headlineSmall: headlineSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      );
}
