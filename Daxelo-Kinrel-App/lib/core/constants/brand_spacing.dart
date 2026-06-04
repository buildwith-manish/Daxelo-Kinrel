// lib/core/constants/brand_spacing.dart
//
// DAXELO KINREL — Brand Spacing & Layout Tokens
//
// Spacing, radius, elevation, motion, and logo-size tokens
// for the KINREL design system.
//
// Brand spec: stitch.zip design reference — Premium Purple & Gold
//
// 8 px grid system

import 'package:flutter/material.dart';

/// ── Spacing Tokens ───────────────────────────────────────────────────
class KinrelSpacing {
  KinrelSpacing._();

  // ── Base Spacing (8 px grid) ──────────────────────────────────────
  static const double xs = 4.0; // Tight padding, icon gaps
  static const double sm = 8.0; // Between related elements
  static const double md = 12.0; // Standard inner padding
  static const double base = 16.0; // Default padding, margins
  static const double lg = 20.0; // Section inner padding
  static const double xl = 24.0; // Card padding
  static const double xxl = 32.0; // Section gaps (2xl)
  static const double xxxl = 40.0; // Major section separation (3xl)
  static const double huge = 48.0; // Page top/bottom padding (4xl)
  static const double massive = 64.0; // Hero sections (5xl)

  // ── Semantic Spacing ──────────────────────────────────────────────
  static const double screenHorizontal = lg;
  static const double screenVertical = xl;
  static const double cardPadding = xl;
  static const double cardInnerGap = md;
  static const double sectionGap = xxl;
  static const double listItemGap = sm;
  static const double formFieldGap = md;
  static const double chipGap = xs;
  static const double avatarSize = 40;
  static const double avatarSizeLarge = 64;
  static const double iconButtonSize = 48;

  // ── Radius Convenience Aliases (mirrors KinrelRadius) ─────────────
  static const double radiusSm = 6.0;
  static const double radiusMd = 10.0;
  static const double radiusLg = 14.0;
  static const double radiusXl = 18.0;
  static const double radiusXXl = 22.0;

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
  static const double xs = 4.0; // Tags, small chips
  static const double sm = 6.0; // Buttons, inputs (compact)
  static const double md = 10.0; // Standard cards, modals
  static const double lg = 14.0; // Feature cards, images
  static const double xl = 18.0; // Large cards, sheets
  static const double xxl = 22.0; // App icon shape, hero cards
  static const double full = 9999.0; // Pills, avatars, FABs

  // ── Semantic Radius (backward compat) ────────────────────────────
  static const double button = 12.0; // (backward compat)
  static const double card = 14.0; // (backward compat)
  static const double input = 10.0; // (backward compat)
  static const double chip = 9999.0; // (backward compat)
  static const double dialog = 18.0; // (backward compat)
  static const double bottomSheet = 22.0; // (backward compat)
  static const double fab = full; // 9999
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
