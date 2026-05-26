// lib/core/constants/brand_spacing.dart
//
// DAXELO KINREL — Brand Spacing & Layout Tokens
//
// Spacing, radius, elevation, motion, and logo-size tokens
// for the KINREL design system.
//
// Brand spec: stitch.zip design reference — Premium Purple & Gold

import 'package:flutter/material.dart';

/// ── Spacing Tokens ───────────────────────────────────────────────────
class KinrelSpacing {
  KinrelSpacing._();

  // ── Base Spacing ──────────────────────────────────────────────────
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
  static const double base = lg; // Base screen padding (16)

  // ── Semantic Spacing ──────────────────────────────────────────────
  static const double screenHorizontal = lg;
  static const double screenVertical = xl;
  static const double cardPadding = lg;
  static const double cardInnerGap = md;
  static const double sectionGap = xxl;
  static const double listItemGap = sm;
  static const double formFieldGap = md;
  static const double chipGap = xs;
  static const double avatarSize = 40;
  static const double avatarSizeLarge = 64;
  static const double iconButtonSize = 48;

  // ── Radius Convenience Aliases ────────────────────────────────────
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusXXl = 24;

  // ── Logo Sizes ────────────────────────────────────────────────────
  static const double logoXs = 28;
  static const double logoSm = 36;
  static const double logoMd = 48;
  static const double logoLg = 64;
  static const double logoXl = 96;

  // ── Logo Font Scale ───────────────────────────────────────────────
  static const double logoScaleXs = 0.6;
  static const double logoScaleSm = 0.8;
  static const double logoScaleMd = 1.0;
  static const double logoScaleLg = 1.4;
  static const double logoScaleXl = 2.0;
}

/// ── Radius Tokens ────────────────────────────────────────────────────
class KinrelRadius {
  KinrelRadius._();

  static const double none = 0;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double full = 9999;

  // ── Semantic Radius ───────────────────────────────────────────────
  static const double card = lg;      // 16
  static const double button = md;    // 12 (was 8)
  static const double input = md;     // 12 (was 8)
  static const double dialog = xxl;   // 24 (was 28)
  static const double bottomSheet = xxl; // 24 (was 28)
  static const double chip = xs;      // 4
  static const double fab = full;     // 9999
}

/// ── Elevation Tokens ─────────────────────────────────────────────────
class KinrelElevation {
  KinrelElevation._();

  static const double none = 0;
  static const double sm = 1;
  static const double md = 3;
  static const double lg = 6;
  static const double xl = 12;

  // ── Shadow definitions (dark mode) ────────────────────────────────
  static List<BoxShadow> shadowSm(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.05),
          offset: const Offset(0, 1),
          blurRadius: 2,
        ),
      ];

  static List<BoxShadow> shadowMd(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.1),
          offset: const Offset(0, 4),
          blurRadius: 6,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.1),
          offset: const Offset(0, 2),
          blurRadius: 4,
          spreadRadius: -2,
        ),
      ];

  static List<BoxShadow> shadowLg(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.1),
          offset: const Offset(0, 10),
          blurRadius: 15,
          spreadRadius: -3,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.1),
          offset: const Offset(0, 4),
          blurRadius: 6,
          spreadRadius: -4,
        ),
      ];

  static List<BoxShadow> shadowXl(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.1),
          offset: const Offset(0, 20),
          blurRadius: 25,
          spreadRadius: -5,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.1),
          offset: const Offset(0, 8),
          blurRadius: 10,
          spreadRadius: -6,
        ),
      ];
}

/// ── Motion Tokens ────────────────────────────────────────────────────
class KinrelMotion {
  KinrelMotion._();

  static const Duration instant = Duration(milliseconds: 50);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration deliberate = Duration(milliseconds: 800);
  static const Duration ceremonial = Duration(milliseconds: 1200);

  // ── Curves ────────────────────────────────────────────────────────
  static const Curve easeOut = Cubic(0.33, 1.0, 0.68, 1.0);
  static const Curve easeIn = Cubic(0.32, 0.0, 0.67, 0.0);
  static const Curve spring = Cubic(0.68, -0.6, 0.32, 1.6);
  static const Curve decelerate = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Curve accelerate = Cubic(0.4, 0.0, 1.0, 1.0);
}

/// ── Opacity Tokens ───────────────────────────────────────────────────
class KinrelOpacity {
  KinrelOpacity._();

  static const double disabled = 0.38;
  static const double hint = 0.60;
  static const double secondary = 0.70;
  static const double primary = 1.00;
  static const double scrim = 0.32;
  static const double hover = 0.08;
  static const double focus = 0.12;
  static const double pressed = 0.12;
  static const double dragged = 0.16;
}

/// ── Breakpoint Tokens ────────────────────────────────────────────────
class KinrelBreakpoints {
  KinrelBreakpoints._();

  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;
  static const double large = 1600;
}
