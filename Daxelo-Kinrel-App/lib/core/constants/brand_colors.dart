import 'package:flutter/material.dart';

/// KINREL Brand Color System — Next-Gen Violet Intelligence
/// Redesigned for #1 global family relationship intelligence app
///
/// Color Philosophy:
///   Primary Violet (#6C47FF) → Trust, intelligence, connection
///   Secondary Lavender (#A78BFA) → Warmth, approachability
///   Accent Purple (#7C3AED) → Depth, premium feel
///   Deep Dark BG → Cinematic, immersive, focus-driven
///
/// Dark mode is the default experience.
/// Light mode is the accessible alternative.
class KinrelColors {
  KinrelColors._();

  // ── Primary Brand Colors ───────────────────────────────────────
  static const Color purple = Color(0xFF6C47FF);        // Primary CTA (light mode)
  static const Color deepPurple = Color(0xFF7C3AED);     // Primary CTA (dark mode) / Accent
  static const Color violet = Color(0xFF8B5CF6);         // Interactive highlights
  static const Color brightViolet = Color(0xFFA78BFA);   // Secondary — badges, borders, chips

  static const Color gold = Color(0xFFD4AF37);           // Premium accent (retained)
  static const Color brightGold = Color(0xFFFFD700);     // Celebration particles

  static const Color coral = Color(0xFFFF6B6B);          // Secondary accent (retained)
  static const Color orange = Color(0xFFF97316);         // Active nav, alt CTA
  static const Color blue = Color(0xFF3B82F6);           // Tree nodes, dashboard accent
  static const Color red = Color(0xFFEF4444);            // Destructive actions

  // ── Dark Theme ────────────────────────────────────────────────
  /// Deep cinematic dark — #0A0A0F (near-black with violet undertone)
  static const Color darkBackground = Color(0xFF0A0A0F);
  /// Dark card surface — #1C1C28 (elevated violet-dark)
  static const Color darkCard = Color(0xFF1C1C28);
  /// Elevated surface — #2A2A3D (subtle lift)
  static const Color darkElevated = Color(0xFF2A2A3D);
  /// Dark surface — #13131A (between BG and Card)
  static const Color darkSurface = Color(0xFF13131A);

  // ── Light Theme ───────────────────────────────────────────────
  /// Light violet-white — #F8F7FF (warm paper with violet hint)
  static const Color lightBackground = Color(0xFFF8F7FF);
  /// Light card — #F1EFFE (soft lavender white)
  static const Color lightCard = Color(0xFFF1EFFE);
  /// Light elevated — #EDEAFE (visible lift from card)
  static const Color lightElevated = Color(0xFFEDEAFE);
  /// Light surface — #FFFFFF (pure white for contrast elements)
  static const Color lightSurface = Color(0xFFFFFFFF);

  // ── Warm/Gold Theme ───────────────────────────────────────────
  static const Color warmBackground = Color(0xFFF8F5F0);
  static const Color warmCard = Color(0xFFFFFFFF);
  static const Color warmElevated = Color(0xFFF5F1E8);

  // ── Text Colors ──────────────────────────────────────────────
  // Dark mode text
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF1A1A2E);          // Light mode primary text
  static const Color textSilver = Color(0xFFC4B5FD);         // Violet-tinted silver
  static const Color textDim = Color(0xFF6B6B80);            // Dimmed/de-emphasized
  static const Color textMutedDark = Color(0xFF4A4A5E);      // Very muted dark
  static const Color textSecondaryLight = Color(0xFF6B6B80); // Light mode secondary
  static const Color textSecondaryDark = Color(0xFF8B8BA7);  // Dark mode secondary

  // ── Semantic ──────────────────────────────────────────────────
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);            // Emerald green
  static const Color warning = Color(0xFFF59E0B);            // Amber
  static const Color info = Color(0xFF60A5FA);

  // ── Glow Effects (Violet-tinted) ─────────────────────────────
  static const Color purpleGlow = Color(0x476C47FF);         // Primary violet glow
  static const Color goldGlow = Color(0x47D4AF37);
  static const Color violetGlow = Color(0x478B5CF6);         // Bright violet glow

  // ── Festival Palettes ─────────────────────────────────────────
  static const Color diwaliGold = Color(0xFFFFD700);
  static const Color holiPink = Color(0xFFFF69B4);
  static const Color eidGreen = Color(0xFF2E8B57);
  static const Color navratriRed = Color(0xFFDC143C);
  static const Color onamYellow = Color(0xFFFFC107);
  static const Color baisakhiOrange = Color(0xFFFF8C00);
  static const Color pongalBrown = Color(0xFF8B4513);
  static const Color durgaPurple = Color(0xFF8B008B);

  // ── Backward Compat Aliases (dark mode defaults) ──────────────
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
  static const Color lightTextDim = Color(0xFF9A8AB0);
  static const Color lightBorder = Color(0xFFE0D9FF);         // Lavender border

  // ── Backward Compat: Orange/Amber/Ember aliases ──────────────
  // These map old orange names to the new violet system
  // so existing code referencing these still compiles
  static const Color amber = Color(0xFFF59240);
  static const Color ember = Color(0xFFC44A18);
  static const Color orangeGlow = Color(0x47E8612A);

  // ── Utility ───────────────────────────────────────────────────
  static Color withAlpha(Color color, double alpha) =>
      color.withValues(alpha: alpha);

  static bool isLightTheme(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static bool isDarkTheme(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}

/// KINREL Brand Gradients — Next-Gen Violet Intelligence
/// Updated to use the new #6C47FF / #7C3AED / #A78BFA palette
class KinrelGradients {
  KinrelGradients._();

  static const LinearGradient splashGradient = LinearGradient(
    colors: [Color(0xFF6C47FF), Color(0xFF7C3AED)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient splashGradientDark = LinearGradient(
    colors: [Color(0xFF6C47FF), Color(0xFF5B21B6)],
    begin: Alignment.center,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient darkBgGradient = LinearGradient(
    colors: [Color(0xFF0A0A0F), Color(0xFF13131A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient igniteGradient = LinearGradient(
    colors: [KinrelColors.purple, KinrelColors.brightViolet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heritageGradient = LinearGradient(
    colors: [KinrelColors.purple, KinrelColors.deepPurple],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient wordmarkGradient = LinearGradient(
    colors: [Colors.white, KinrelColors.brightViolet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [KinrelColors.darkCard, KinrelColors.darkElevated],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient iconGlowGradient = LinearGradient(
    colors: [KinrelColors.purpleGlow, Colors.transparent],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient ctaGradient = LinearGradient(
    colors: [KinrelColors.purple, KinrelColors.deepPurple],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient searchBarGradient = LinearGradient(
    colors: [Color(0xFF6C47FF), Color(0xFF7C3AED)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient shareCardGradient = LinearGradient(
    colors: [Color(0xFFA78BFA), Color(0xFFD4AF37)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient signOutGradient = LinearGradient(
    colors: [Color(0xFFEF4444), Color(0xFF7C3AED)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient signOutGradientDark = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFFEF4444)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Backward compat aliases
  static const LinearGradient ignite = igniteGradient;
  static const LinearGradient heritage = heritageGradient;
}
