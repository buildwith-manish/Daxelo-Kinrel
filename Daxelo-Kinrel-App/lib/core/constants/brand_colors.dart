import 'package:flutter/material.dart';

/// KINREL Brand Color System — Premium Purple & Gold
/// Based on stitch.zip design reference analysis
class KinrelColors {
  KinrelColors._();

  // ── Primary Brand Colors ───────────────────────────────────────
  static const Color purple = const Color(0xFF5D5FEF);        // Primary CTA (light)
  static const Color deepPurple = const Color(0xFF4B3F8A);     // Primary CTA (dark)
  static const Color violet = const Color(0xFF8A2BE2);         // Interactive highlights
  static const Color brightViolet = const Color(0xFF8B5CF6);   // Badges, borders (dark)

  static const Color gold = const Color(0xFFD4AF37);           // Premium accent
  static const Color brightGold = const Color(0xFFFFD700);     // Celebration particles

  static const Color coral = const Color(0xFFFF6B6B);          // Secondary accent
  static const Color orange = const Color(0xFFF97316);         // Active nav, alt CTA
  static const Color blue = const Color(0xFF3B82F6);           // Tree nodes, dashboard accent
  static const Color red = const Color(0xFFEF4444);            // Destructive actions

  // ── Dark Theme ────────────────────────────────────────────────
  static const Color darkBackground = const Color(0xFF121212);
  static const Color darkCard = const Color(0xFF1E1E1E);
  static const Color darkElevated = const Color(0xFF2A2A3E);
  static const Color darkSurface = const Color(0xFF2A1F4A);

  // ── Light Theme ───────────────────────────────────────────────
  static const Color lightBackground = const Color(0xFFF5F7FA);
  static const Color lightCard = const Color(0xFFFFFFFF);
  static const Color lightElevated = const Color(0xFFF2F2F7);
  static const Color lightSurface = const Color(0xFFE8E8ED);

  // ── Warm/Gold Theme ───────────────────────────────────────────
  static const Color warmBackground = const Color(0xFFF8F5F0);
  static const Color warmCard = const Color(0xFFFFFFFF);
  static const Color warmElevated = const Color(0xFFF5F1E8);

  // ── Text Colors ──────────────────────────────────────────────
  static const Color textWhite = const Color(0xFFFFFFFF);
  static const Color textDark = const Color(0xFF2D3748);
  static const Color textSilver = const Color(0xFFC9B4A8);
  static const Color textDim = const Color(0xFF8A7A72);
  static const Color textMutedDark = const Color(0xFF6B6B6B);
  static const Color textSecondaryLight = const Color(0xFF8E8E93);
  static const Color textSecondaryDark = const Color(0xFFB0B0B0);

  // ── Semantic ──────────────────────────────────────────────────
  static const Color error = const Color(0xFFEF4444);
  static const Color success = const Color(0xFF4CAF7A);
  static const Color warning = const Color(0xFFF5A623);
  static const Color info = const Color(0xFF60A5FA);

  // ── Glow Effects ──────────────────────────────────────────────
  static const Color purpleGlow = const Color(0x475D5FEF);
  static const Color goldGlow = const Color(0x47D4AF37);
  static const Color violetGlow = const Color(0x478A2BE2);

  // ── Festival Palettes ─────────────────────────────────────────
  static const Color diwaliGold = const Color(0xFFFFD700);
  static const Color holiPink = const Color(0xFFFF69B4);
  static const Color eidGreen = const Color(0xFF2E8B57);
  static const Color navratriRed = const Color(0xFFDC143C);
  static const Color onamYellow = const Color(0xFFFFC107);
  static const Color baisakhiOrange = const Color(0xFFFF8C00);
  static const Color pongalBrown = const Color(0xFF8B4513);
  static const Color durgaPurple = const Color(0xFF8B008B);

  // ── Backward Compat Aliases (dark mode defaults) ──────────────
  static const Color card = darkCard;
  static const Color bg = darkBackground;
  static const Color elevated = darkElevated;
  static const Color surface = darkSurface;
  static const Color border = const Color(0xFF5A5A8A);
  static const Color accent = gold;
  static const Color accentLight = brightGold;
  static const Color accentDark = const Color(0xFFB8960C);
  static const Color textPrimary = textWhite;
  static const Color textSecondary = textSecondaryDark;

  // Light mode aliases
  static const Color lightBg = lightBackground;
  static const Color lightTextPrimary = textDark;
  static const Color lightTextSecondary = textSecondaryLight;
  static const Color lightTextDim = const Color(0xFF9A8A82);
  static const Color lightBorder = const Color(0xFFD1D1D6);

  // ── Backward Compat: Orange/Amber/Ember aliases ──────────────
  // These map old orange names to the new purple/gold system
  // so existing code referencing these still compiles
  static const Color amber = const Color(0xFFF59240);
  static const Color ember = const Color(0xFFC44A18);
  static const Color orangeGlow = const Color(0x47E8612A);

  // ── Utility ───────────────────────────────────────────────────
  static Color withAlpha(Color color, double alpha) =>
      color.withValues(alpha: alpha);

  static bool isLightTheme(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static bool isDarkTheme(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}

/// KINREL Brand Gradients — Premium Purple & Gold
class KinrelGradients {
  KinrelGradients._();

  static const LinearGradient splashGradient = const LinearGradient(
    colors: [const Color(0xFF6A11CB), Color(0xFFFF6B6B)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient splashGradientDark = const LinearGradient(
    colors: [const Color(0xFF5D5DFF), Color(0xFFFF5D5D)],
    begin: Alignment.center,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient darkBgGradient = const LinearGradient(
    colors: [const Color(0xFF2A2A3E), Color(0xFF3A3A5E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient igniteGradient = const LinearGradient(
    colors: [KinrelColors.purple, KinrelColors.coral],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heritageGradient = const LinearGradient(
    colors: [KinrelColors.purple, KinrelColors.deepPurple],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient wordmarkGradient = const LinearGradient(
    colors: [Colors.white, KinrelColors.purple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = const LinearGradient(
    colors: [KinrelColors.darkCard, KinrelColors.darkElevated],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient iconGlowGradient = const LinearGradient(
    colors: [KinrelColors.purpleGlow, Colors.transparent],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient ctaGradient = const LinearGradient(
    colors: [KinrelColors.coral, KinrelColors.violet],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient searchBarGradient = const LinearGradient(
    colors: [const Color(0xFF1E3A8A), Color(0xFF7C3AED)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient shareCardGradient = const LinearGradient(
    colors: [const Color(0xFFB565A7), Color(0xFFF9C74F)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient signOutGradient = const LinearGradient(
    colors: [const Color(0xFFE53935), Color(0xFF6A1B9A)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient signOutGradientDark = const LinearGradient(
    colors: [const Color(0xFF6A0DAD), Color(0xFFFF6347)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Backward compat aliases
  static const LinearGradient ignite = igniteGradient;
  static const LinearGradient heritage = heritageGradient;
}
