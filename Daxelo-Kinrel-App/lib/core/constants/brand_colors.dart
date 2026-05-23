import 'package:flutter/material.dart';

/// KINREL Brand Color System
/// Orange: #E8612A (primary CTA)
/// Amber:  #F59240 (highlights)
/// Ember:  #C44A18 (depth)
class KinrelColors {
  KinrelColors._();

  // ── Primary Brand ───────────────────────────────────────────
  static const Color orange = Color(0xFFE8612A);
  static const Color amber = Color(0xFFF59240);
  static const Color ember = Color(0xFFC44A18);
  
  static const LinearGradient igniteGradient = LinearGradient(
    colors: [orange, amber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient heritageGradient = LinearGradient(
    colors: [orange, ember],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  
  static const LinearGradient wordmarkGradient = LinearGradient(
    colors: [Colors.white, orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Dark Theme (default) ────────────────────────────────────
  static const Color darkBackground = Color(0xFF13141E);
  static const Color darkCard = Color(0xFF191B2C);
  static const Color darkElevated = Color(0xFF202338);
  static const Color darkSurface = Color(0xFF2A2D45);

  // ── Light Theme ─────────────────────────────────────────────
  static const Color lightBackground = Color(0xFFFFFAF8);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightElevated = Color(0xFFF5F0EE);
  static const Color lightSurface = Color(0xFFF0EBE8);

  // ── Text Colors ─────────────────────────────────────────────
  static const Color textWhite = Color(0xFFF5F0EE); // 14.5:1 on dark bg
  static const Color textSilver = Color(0xFFC9B4A8); // 5.1:1 on dark bg
  static const Color textDim = Color(0xFF8A7A72);
  static const Color textDark = Color(0xFF1A0A00); // Light mode primary
  static const Color textMuted = Color(0xFF6B5B52);

  // ── Semantic ────────────────────────────────────────────────
  static const Color error = Color(0xFFF04E2A);
  static const Color success = Color(0xFF4CAF7A);
  static const Color warning = Color(0xFFF5A623);
  static const Color info = Color(0xFF60A5FA);

  // ── Glow ────────────────────────────────────────────────────
  static const Color orangeGlow = Color(0x47E8612A); // 28% opacity
  
  // ── Festival Palettes ───────────────────────────────────────
  static const Color diwaliGold = Color(0xFFFFD700);
  static const Color holiPink = Color(0xFFFF69B4);
  static const Color eidGreen = Color(0xFF2E8B57);
  static const Color navratriRed = Color(0xFFDC143C);
  static const Color onamYellow = Color(0xFFFFC107);
  static const Color baisakhiOrange = Color(0xFFFF8C00);
  static const Color pongalBrown = Color(0xFF8B4513);
  static const Color durgaPurple = Color(0xFF8B008B);

  // ── Convenience Aliases (used by app_theme.dart) ────────────
  static const Color card = darkCard;
  static const Color bg = darkBackground;
  static const Color elevated = darkElevated;
  static const Color surface = darkSurface;
  static const Color border = darkSurface;
  static const Color accent = amber;
  static const Color accentLight = Color(0xFFF5C842);
  static const Color accentDark = ember;
  static const Color textPrimary = textWhite;
  static const Color textSecondary = textSilver;

  // Light mode aliases
  static const Color lightBg = lightBackground;
  static const Color lightTextPrimary = textDark;
  static const Color lightTextSecondary = Color(0xFF6B5B52);
  static const Color lightTextDim = Color(0xFF9A8A82);
  static const Color lightBorder = Color(0xFFE0D8D2);

  // ── Utility ─────────────────────────────────────────────────
  static Color withAlpha(Color color, double alpha) =>
    color.withValues(alpha: alpha);
    
  static bool isLightTheme(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light;
}

/// KINREL Brand Gradients
/// Reusable gradient definitions for the design system
class KinrelGradients {
  KinrelGradients._();

  static const LinearGradient igniteGradient = LinearGradient(
    colors: [KinrelColors.orange, KinrelColors.amber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heritageGradient = LinearGradient(
    colors: [KinrelColors.orange, KinrelColors.ember],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Aliases used by app_theme.dart
  static const LinearGradient ignite = igniteGradient;
  static const LinearGradient heritage = heritageGradient;

  static const LinearGradient wordmarkGradient = LinearGradient(
    colors: [Colors.white, KinrelColors.orange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [KinrelColors.darkCard, KinrelColors.darkElevated],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient iconGlowGradient = LinearGradient(
    colors: [KinrelColors.orangeGlow, Colors.transparent],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
