// lib/core/constants/kinrel_high_contrast_colors.dart
//
// DAXELO KINREL — High-Contrast Color Theme (P4.6)
//
// Per Vision §11 HP-7 + §5 Layer 3 + WCAG 2.1.1 (Contrast Enhanced) —
// a high-contrast variant of KinrelColors for users who need enhanced
// contrast. All text/background pairs meet WCAG AAA (7:1).
//
// The theme is opt-in via a Riverpod provider. When active, the graph
// widgets read from KinrelColorsHighContrast instead of KinrelColors.
//
// High-contrast adjustments:
//   - Background: pure black (#000000) for maximum text contrast
//   - Card: near-black (#0A0A0A)
//   - Elevated: #141414
//   - Text: pure white (#FFFFFF)
//   - Text dim: #E0E0E0 (still ≥ 15:1 on black)
//   - Border: #FFFFFF (visible against black)
//   - Accent colors: brighter variants for visibility

import 'package:flutter/material.dart';

/// High-contrast variant of [KinrelColors]. All color pairs meet WCAG
/// AAA (7:1 contrast ratio). Used when the user enables high-contrast
/// mode in settings.
class KinrelColorsHighContrast {
  KinrelColorsHighContrast._();

  // ── Backgrounds ────────────────────────────────────────────────
  /// Pure black background — maximum text contrast.
  static const Color darkBackground = Color(0xFF000000);

  /// Near-black card background.
  static const Color darkCard = Color(0xFF0A0A0A);

  /// Elevated surface.
  static const Color darkElevated = Color(0xFF141414);

  // ── Text ───────────────────────────────────────────────────────
  /// Pure white text — 21:1 on black (maximum contrast).
  static const Color textWhite = Color(0xFFFFFFFF);

  /// Bright grey text — 15:1 on black (still AAA).
  static const Color textDim = Color(0xFFE0E0E0);

  /// Secondary text (alias for textDim in high-contrast).
  static const Color textSecondaryDark = Color(0xFFE0E0E0);

  // ── Borders ────────────────────────────────────────────────────
  /// White border — fully visible against black.
  static const Color border = Color(0xFFFFFFFF);

  // ── Accents (brighter for visibility) ──────────────────────────
  static const Color orange = Color(0xFFFF6B35);
  static const Color amber = Color(0xFFFFB347);
  static const Color tealAccent = Color(0xFF5EEAD4);
  static const Color extendedPurple = Color(0xFFA78BFA);
  static const Color gold = Color(0xFFFFD700);
  static const Color coral = Color(0xFFFF8A8A);
  static const Color blue = Color(0xFF60A5FA);
  static const Color red = Color(0xFFFF6B6B);

  // ── Node colors (brighter) ─────────────────────────────────────
  static const Color nodeSelf = Color(0xFF2DD4BF);
  static const Color nodeParent = Color(0xFF60A5FA);
  static const Color nodeSibling = Color(0xFFA78BFA);
  static const Color nodeChild = Color(0xFFF472B6);
  static const Color nodeSpouse = Color(0xFFFB923C);
  static const Color nodeGrandparent = Color(0xFF818CF8);
  static const Color nodeAuntUncle = Color(0xFF22D3EE);
  static const Color nodeCousin = Color(0xFF34D399);
  static const Color nodeInLaw = Color(0xFFFBBF24);
  static const Color nodeExtended = Color(0xFF94A3B8);

  // ── P3.3 Birthday glow (brighter) ──────────────────────────────
  /// Ember glow for living birthdays — brighter in high-contrast.
  static const Color birthdayEmber = Color(0xFFFF6B35);

  /// Amber glow for deceased birthdays — brighter.
  static const Color birthdayAmber = Color(0xFFFFB347);

  // ── P3.4 Memorial candle (brighter) ────────────────────────────
  /// Amber candle for deceased nodes — brighter in high-contrast.
  static const Color candleAmber = Color(0xFFFFB347);

  // ── P3.5 Ambient particles (brighter) ──────────────────────────
  /// Gold motes — brighter in high-contrast.
  static const Color moteGold = Color(0xFFFFD700);

  // ── P3.6 Sepia wash (stronger) ─────────────────────────────────
  /// Full sepia matrix — stronger contrast.
  static const List<double> fullSepiaMatrix = [
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0,     0,     0,     1, 0,
  ];
}
