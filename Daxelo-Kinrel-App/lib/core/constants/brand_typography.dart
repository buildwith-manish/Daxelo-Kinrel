import 'package:flutter/material.dart';

/// KINREL Typography System
/// Display: Outfit (headlines, titles)
/// Body: DM Sans (paragraphs, labels)
/// Mono: DM Mono (code, technical)
class KinrelTypography {
  KinrelTypography._();

  // ── Font Families ───────────────────────────────────────────
  static const String displayFont = 'Outfit';
  static const String bodyFont = 'DMSans';
  static const String monoFont = 'DMMono';

  // ── Type Scale (Material 3 compatible) ──────────────────────
  static const TextStyle displayHero = TextStyle(
    fontFamily: displayFont,
    fontSize: 48,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -1.0,
  );

  static const TextStyle displayLarge = TextStyle(
    fontFamily: displayFont,
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: displayFont,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
  );

  static const TextStyle displaySmall = TextStyle(
    fontFamily: displayFont,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontFamily: displayFont,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: displayFont,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontFamily: displayFont,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle sectionHeader = TextStyle(
    fontFamily: displayFont,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.35,
    letterSpacing: -0.2,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: displayFont,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.15,
  );

  static const TextStyle titleSmall = TextStyle(
    fontFamily: bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.1,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: bodyFont,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle labelLarge = TextStyle(
    fontFamily: bodyFont,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0.1,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: bodyFont,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: 0.5,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: bodyFont,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: 0.5,
  );

  static const TextStyle monoBody = TextStyle(
    fontFamily: monoFont,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // ── Font Scale Factors ──────────────────────────────────────
  static const double scaleSmall = 0.85;
  static const double scaleMedium = 1.0;
  static const double scaleLarge = 1.15;
  static const double scaleExtraLarge = 1.3;

  // ── Brand-specific Styles ──────────────────────────────────
  /// Letter spacing for "by Daxelo" byline text (relative to font size)
  static const double bylineDaxelo = 0.15;
}
