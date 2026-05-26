import 'package:flutter/material.dart';

/// KINREL Brand Color System — Orange K-Graph DNA
/// Redesigned for #1 global family relationship intelligence app
///
/// Color Philosophy:
///   Kinrel Orange (#E8612A) → Primary CTA, active states, brand moments
///   Warm Amber (#F59240)    → Highlights, glows, secondary accents
///   Burnt Ember (#C44A18)   → Depth, pressed states, tertiary accent
///   Deep Dark BG            → Cinematic, immersive, focus-driven
///
/// Dark mode is the default experience.
/// Light mode is the accessible alternative.
class KinrelColors {
  KinrelColors._();

  // ── Primary Accent Palette ──────────────────────────────────────
  /// Kinrel Orange — Primary CTA, active states, brand moments
  static const Color orange = Color(0xFFE8612A);

  /// Kinrel Orange (alias — backward compat, was purple)
  static const Color purple = Color(0xFFE8612A);

  /// Burnt Ember — Depth, pressed states, tertiary accent (was deepPurple)
  static const Color deepPurple = Color(0xFFC44A18);

  /// Kinrel Orange (alias — backward compat, was violet)
  static const Color violet = Color(0xFFE8612A);

  /// Warm Amber — Highlights, glows, secondary accents (was brightViolet)
  static const Color brightViolet = Color(0xFFF59240);

  /// Burnt Ember — pressed states, depth (alias)
  static const Color ember = Color(0xFFC44A18);

  /// Warm Amber — secondary accent (alias)
  static const Color amber = Color(0xFFF59240);

  // ── Retained Accent Colors ──────────────────────────────────────
  static const Color gold = Color(0xFFD4AF37);           // Premium accent (retained)
  static const Color brightGold = Color(0xFFFFD700);     // Celebration particles
  static const Color coral = Color(0xFFFF6B6B);          // Secondary accent (retained)
  static const Color blue = Color(0xFF3B82F6);           // Tree nodes, dashboard accent
  static const Color red = Color(0xFFEF4444);            // Destructive actions (legacy)

  // ── Dark Theme ─────────────────────────────────────────────────
  /// App Background — #131416 (cool blue-dark)
  static const Color darkBackground = Color(0xFF131416);
  /// Card Surface — #191B2C (elevated surface)
  static const Color darkCard = Color(0xFF191B2C);
  /// Elevated/Muted — #202338 (hover/muted)
  static const Color darkElevated = Color(0xFF202338);
  /// Dark surface — #13141E (between BG and Card)
  static const Color darkSurface = Color(0xFF13141E);

  // ── Light Theme ────────────────────────────────────────────────
  /// Background — #FFFAF8 (warm off-white)
  static const Color lightBackground = Color(0xFFFFFAF8);
  /// Card — #FFFFFF (pure white)
  static const Color lightCard = Color(0xFFFFFFFF);
  /// Light elevated — #F5F0EE (warm white)
  static const Color lightElevated = Color(0xFFF5F0EE);
  /// Light surface — #E8E8ED (neutral grey)
  static const Color lightSurface = Color(0xFFE8E8ED);

  // ── Warm/Gold Theme ────────────────────────────────────────────
  static const Color warmBackground = Color(0xFFF8F5F0);
  static const Color warmCard = Color(0xFFFFFFFF);
  static const Color warmElevated = Color(0xFFF5F1E8);

  // ── Text Colors (WCAG AA Compliant) ────────────────────────────
  /// Primary Text — #F5F0EE (warm white, main content)
  static const Color textWhite = Color(0xFFF5F0EE);
  /// Primary Text (light mode) — #1A0A00 (near-black warm)
  static const Color textDark = Color(0xFF1A0A00);
  /// Secondary Text — #C9B4A8 (silver, subtitles/body)
  static const Color textSilver = Color(0xFFC9B4A8);
  /// Disabled/Hint — #8A7A72 (dim, placeholders only)
  static const Color textDim = Color(0xFF8A7A72);
  /// Very muted dark text
  static const Color textMutedDark = Color(0xFF4A4A5E);
  /// Dark mode secondary text — #C9B4A8 (same as silver)
  static const Color textSecondaryDark = Color(0xFFC9B4A8);
  /// Light mode secondary text — #745040 (warm brown)
  static const Color textSecondaryLight = Color(0xFF745040);

  // ── Semantic Colors ─────────────────────────────────────────────
  /// Error/Delete — #F04E2A
  static const Color error = Color(0xFFF04E2A);
  /// Success/Done — #4CAF7A
  static const Color success = Color(0xFF4CAF7A);
  /// Warning/Alert — #F5A623
  static const Color warning = Color(0xFFF5A623);
  /// Info/Link — #60A5FA
  static const Color info = Color(0xFF60A5FA);

  // ── Glow Effects (Orange-tinted) ───────────────────────────────
  /// Subtle orange glow — 12% alpha
  static const Color orangeGlowSubtle = Color(0x1FE8612A);
  /// Medium orange glow — 20% alpha
  static const Color orangeGlow = Color(0x33E8612A);
  /// Intense orange glow — 35% alpha
  static const Color orangeGlowIntense = Color(0x59E8612A);

  // Legacy glow aliases (backward compat)
  static const Color purpleGlow = Color(0x33E8612A);     // Now orange glow
  static const Color goldGlow = Color(0x47D4AF37);       // Retained
  static const Color violetGlow = Color(0x33E8612A);     // Now orange glow

  // ── Elevation System (Dark Mode) ────────────────────────────────
  /// Level 0 — #13141E (page bg)
  static const Color elevation0 = Color(0xFF13141E);
  /// Level 1 — #191B2C (cards)
  static const Color elevation1 = Color(0xFF191B2C);
  /// Level 2 — #202338 (elevated cards, dropdowns, bottom sheets)
  static const Color elevation2 = Color(0xFF202338);
  /// Level 3 — #282B44 (modals, dialogs)
  static const Color elevation3 = Color(0xFF282B44);
  /// Level 4 — #303450 (floating elements, tooltips)
  static const Color elevation4 = Color(0xFF303450);

  // ── Festival Palettes ───────────────────────────────────────────
  static const Color diwaliGold = Color(0xFFFFD700);
  static const Color holiPink = Color(0xFFFF69B4);
  static const Color eidGreen = Color(0xFF2E8B57);
  static const Color navratriRed = Color(0xFFDC143C);
  static const Color onamYellow = Color(0xFFFFC107);
  static const Color baisakhiOrange = Color(0xFFFF8C00);
  static const Color pongalBrown = Color(0xFF8B4513);
  static const Color durgaPurple = Color(0xFF8B008B);

  // ── Backward Compat Aliases (dark mode defaults) ────────────────
  static const Color card = darkCard;
  static const Color bg = darkBackground;
  static const Color elevated = darkElevated;
  static const Color surface = darkSurface;
  static const Color border = Color(0xFF2A2A3D);              // Dark border
  static const Color accent = gold;
  static const Color accentLight = brightGold;
  static const Color accentDark = Color(0xFFB8960C);
  static const Color textPrimary = textWhite;
  static const Color textSecondary = textSecondaryDark;

  // Light mode aliases
  static const Color lightBg = lightBackground;
  static const Color lightTextPrimary = textDark;
  static const Color lightTextSecondary = textSecondaryLight;
  static const Color lightTextDim = Color(0xFF8A7A72);
  static const Color lightBorder = Color(0x14000000);         // rgba(0,0,0,0.08)

  // ── Utility ─────────────────────────────────────────────────────
  static Color withAlpha(Color color, double alpha) =>
      color.withValues(alpha: alpha);

  static bool isLightTheme(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static bool isDarkTheme(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}

/// KINREL Brand Gradients — Orange K-Graph DNA
/// Updated to use the #E8612A / #F59240 / #C44A18 palette
class KinrelGradients {
  KinrelGradients._();

  // ── Splash & Background Gradients ───────────────────────────────
  /// Splash gradient — dark bg gradient #13141E → #191B2C
  static const LinearGradient splashGradient = LinearGradient(
    colors: [Color(0xFF13141E), Color(0xFF191B2C)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Splash gradient dark — same as splash
  static const LinearGradient splashGradientDark = LinearGradient(
    colors: [Color(0xFF13141E), Color(0xFF191B2C)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Dark background gradient — #13141E → #202338
  static const LinearGradient darkBgGradient = LinearGradient(
    colors: [Color(0xFF13141E), Color(0xFF202338)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Brand Action Gradients ──────────────────────────────────────
  /// Ignite — #E8612A → #F59240 (135deg, primary CTA)
  static const LinearGradient igniteGradient = LinearGradient(
    colors: [Color(0xFFE8612A), Color(0xFFF59240)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Heritage — #E8612A → #C44A18 (135deg, deep accent)
  static const LinearGradient heritageGradient = LinearGradient(
    colors: [Color(0xFFE8612A), Color(0xFFC44A18)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// CTA Gradient — #E8612A → #F59240 (centerLeft → centerRight)
  static const LinearGradient ctaGradient = LinearGradient(
    colors: [Color(0xFFE8612A), Color(0xFFF59240)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ── UI Element Gradients ────────────────────────────────────────
  /// Wordmark — white → orange (#E8612A) → amber (#F59240)
  static const LinearGradient wordmarkGradient = LinearGradient(
    colors: [Colors.white, Color(0xFFE8612A), Color(0xFFF59240)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Card gradient — darkCard → darkElevated
  static const LinearGradient cardGradient = LinearGradient(
    colors: [KinrelColors.darkCard, KinrelColors.darkElevated],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Icon glow — orangeGlow → transparent
  static const LinearGradient iconGlowGradient = LinearGradient(
    colors: [KinrelColors.orangeGlow, Colors.transparent],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Search bar — #202338 solid → #E8612A search icon
  static const LinearGradient searchBarGradient = LinearGradient(
    colors: [Color(0xFF202338), Color(0xFFE8612A)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Share card — #E8612A → #D4AF37 (top → bottom)
  static const LinearGradient shareCardGradient = LinearGradient(
    colors: [Color(0xFFE8612A), Color(0xFFD4AF37)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Sign out — #F04E2A → #C44A18 (left → right)
  static const LinearGradient signOutGradient = LinearGradient(
    colors: [Color(0xFFF04E2A), Color(0xFFC44A18)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient signOutGradientDark = LinearGradient(
    colors: [Color(0xFFC44A18), Color(0xFFF04E2A)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ── Additional Brand Gradients (from KINREL Global Top 1 Prompt) ─
  /// Sunrise — #C44A18 → #F59240 (135deg, warm glow)
  static const LinearGradient sunriseGradient = LinearGradient(
    colors: [Color(0xFFC44A18), Color(0xFFF59240)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Deep Fire — #13141E → #202338 → #E8612A (hero backgrounds)
  static const LinearGradient deepFireGradient = LinearGradient(
    colors: [Color(0xFF13141E), Color(0xFF202338), Color(0xFFE8612A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomRight,
  );

  /// Glow Core — radial gradient (circle at 30% 30%, rgba(232,97,42,0.28), #13141E)
  /// Note: RadialGradient can't be const with this pattern, use factory method.
  static RadialGradient glowCoreGradient({double opacity = 0.28}) {
    return RadialGradient(
      center: Alignment(-0.4, -0.4), // 30% 30%
      radius: 0.7,
      colors: [
        Color(0xFFE8612A).withValues(alpha: opacity),
        Color(0xFF13141E),
      ],
    );
  }

  /// Chat sent message — subtle orange tint
  static const LinearGradient chatSentGradient = LinearGradient(
    colors: [Color(0xFF2A1A14), Color(0xFF1E1520)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Timeline line — orange accent
  static const LinearGradient timelineGradient = LinearGradient(
    colors: [Color(0xFFE8612A), Color(0xFFF59240)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Achievement badge — gold → amber
  static const LinearGradient achievementGradient = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFF59240), Color(0xFFE8612A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Backward Compat Aliases ─────────────────────────────────────
  static const LinearGradient ignite = igniteGradient;
  static const LinearGradient heritage = heritageGradient;
  static const LinearGradient sunrise = sunriseGradient;
  static const LinearGradient deepFire = deepFireGradient;
}
