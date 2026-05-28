// lib/core/theme/app_theme.dart
//
// DAXELO KINREL — Material 3 Theme (LIGHT + DARK)
//
// Comprehensive Material 3 theme with both light and dark modes
// using the KINREL brand system — Orange K-Graph DNA.
//
// Dark theme:
//   Primary: Orange #E8612A
//   Secondary: Gold #D4AF37
//   Background: #131416
//   Card: #191B2C
//   Elevated: #202338
//   Surface: #13141E
//   Text primary: #F5F0EE (warm white)
//   Text secondary: #C9B4A8
//
// Light theme:
//   Primary: Ember #C44A18
//   Secondary: Gold #D4AF37
//   Background: #FFFAF8
//   Card: #FFFFFF
//   Elevated: #F5F0EE
//   Surface: #E8E8ED
//   Text primary: #1A0A00
//   Text secondary: #745040
//
// Fonts: Outfit (display), DMSans (body), DMMono (mono)

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../constants/brand_colors.dart';
import '../constants/brand_typography.dart';
import '../constants/brand_spacing.dart';
import '../utils/device_tier.dart';

// ── Theme Extension ───────────────────────────────────────────────────

/// Custom brand-specific theme properties accessible via
/// `Theme.of(context).extension<KinrelThemeExtension>()`.
@immutable
class KinrelThemeExtension extends ThemeExtension<KinrelThemeExtension> {
  const KinrelThemeExtension({
    // Core orange palette
    required this.brandOrange,
    required this.brandAmber,
    required this.brandEmber,
    required this.brandGlow,
    // Brand legacy aliases
    required this.brandPurple,
    required this.brandDeepPurple,
    required this.brandGold,
    required this.brandViolet,
    required this.brandCoral,
    required this.brandPurpleGlow,
    required this.brandGoldGlow,
    // Text
    required this.brandTextPrimary,
    required this.brandTextSecondary,
    required this.brandTextDim,
    // Surface
    required this.brandCardBg,
    required this.brandElevatedBg,
    required this.brandBorder,
    required this.brandBackground,
    // Gradients
    required this.brandIgniteGradient,
    required this.brandHeritageGradient,
    required this.brandWordmarkGradient,
    // Radii
    required this.brandCardRadius,
    required this.brandButtonRadius,
    required this.brandInputRadius,
  });

  // ── Core orange palette ──────────────────────────────────────────
  /// Kinrel Orange — #E8612A
  final Color brandOrange;

  /// Warm Amber — #F59240
  final Color brandAmber;

  /// Burnt Ember — #C44A18
  final Color brandEmber;

  /// Orange glow — 0x33E8612A (20% alpha)
  final Color brandGlow;

  // ── Brand legacy aliases (backward compat) ──────────────────────
  /// Primary brand color — orange in dark, ember in light
  final Color brandPurple;

  /// Deep brand color — #C44A18 (ember)
  final Color brandDeepPurple;

  /// Gold accent — #D4AF37
  final Color brandGold;

  /// Violet alias — now maps to orange
  final Color brandViolet;

  /// Coral accent — #FF6B6B
  final Color brandCoral;

  /// Purple glow alias — now orange glow
  final Color brandPurpleGlow;

  /// Gold glow — 0x47D4AF37
  final Color brandGoldGlow;

  // ── Text colors ────────────────────────────────────────────────
  final Color brandTextPrimary;
  final Color brandTextSecondary;
  final Color brandTextDim;

  // ── Surface colors ─────────────────────────────────────────────
  final Color brandCardBg;
  final Color brandElevatedBg;
  final Color brandBorder;
  final Color brandBackground;

  // ── Gradients ──────────────────────────────────────────────────
  final Gradient brandIgniteGradient;
  final Gradient brandHeritageGradient;
  final Gradient brandWordmarkGradient;

  // ── Radii ──────────────────────────────────────────────────────
  final double brandCardRadius;
  final double brandButtonRadius;
  final double brandInputRadius;

  @override
  KinrelThemeExtension copyWith({
    Color? brandOrange,
    Color? brandAmber,
    Color? brandEmber,
    Color? brandGlow,
    Color? brandPurple,
    Color? brandDeepPurple,
    Color? brandGold,
    Color? brandViolet,
    Color? brandCoral,
    Color? brandPurpleGlow,
    Color? brandGoldGlow,
    Color? brandTextPrimary,
    Color? brandTextSecondary,
    Color? brandTextDim,
    Color? brandCardBg,
    Color? brandElevatedBg,
    Color? brandBorder,
    Color? brandBackground,
    Gradient? brandIgniteGradient,
    Gradient? brandHeritageGradient,
    Gradient? brandWordmarkGradient,
    double? brandCardRadius,
    double? brandButtonRadius,
    double? brandInputRadius,
  }) {
    return KinrelThemeExtension(
      brandOrange: brandOrange ?? this.brandOrange,
      brandAmber: brandAmber ?? this.brandAmber,
      brandEmber: brandEmber ?? this.brandEmber,
      brandGlow: brandGlow ?? this.brandGlow,
      brandPurple: brandPurple ?? this.brandPurple,
      brandDeepPurple: brandDeepPurple ?? this.brandDeepPurple,
      brandGold: brandGold ?? this.brandGold,
      brandViolet: brandViolet ?? this.brandViolet,
      brandCoral: brandCoral ?? this.brandCoral,
      brandPurpleGlow: brandPurpleGlow ?? this.brandPurpleGlow,
      brandGoldGlow: brandGoldGlow ?? this.brandGoldGlow,
      brandTextPrimary: brandTextPrimary ?? this.brandTextPrimary,
      brandTextSecondary: brandTextSecondary ?? this.brandTextSecondary,
      brandTextDim: brandTextDim ?? this.brandTextDim,
      brandCardBg: brandCardBg ?? this.brandCardBg,
      brandElevatedBg: brandElevatedBg ?? this.brandElevatedBg,
      brandBorder: brandBorder ?? this.brandBorder,
      brandBackground: brandBackground ?? this.brandBackground,
      brandIgniteGradient: brandIgniteGradient ?? this.brandIgniteGradient,
      brandHeritageGradient:
          brandHeritageGradient ?? this.brandHeritageGradient,
      brandWordmarkGradient:
          brandWordmarkGradient ?? this.brandWordmarkGradient,
      brandCardRadius: brandCardRadius ?? this.brandCardRadius,
      brandButtonRadius: brandButtonRadius ?? this.brandButtonRadius,
      brandInputRadius: brandInputRadius ?? this.brandInputRadius,
    );
  }

  @override
  KinrelThemeExtension lerp(covariant KinrelThemeExtension? other, double t) {
    if (other == null) return this;
    return KinrelThemeExtension(
      brandOrange: Color.lerp(brandOrange, other.brandOrange, t)!,
      brandAmber: Color.lerp(brandAmber, other.brandAmber, t)!,
      brandEmber: Color.lerp(brandEmber, other.brandEmber, t)!,
      brandGlow: Color.lerp(brandGlow, other.brandGlow, t)!,
      brandPurple: Color.lerp(brandPurple, other.brandPurple, t)!,
      brandDeepPurple: Color.lerp(brandDeepPurple, other.brandDeepPurple, t)!,
      brandGold: Color.lerp(brandGold, other.brandGold, t)!,
      brandViolet: Color.lerp(brandViolet, other.brandViolet, t)!,
      brandCoral: Color.lerp(brandCoral, other.brandCoral, t)!,
      brandPurpleGlow: Color.lerp(brandPurpleGlow, other.brandPurpleGlow, t)!,
      brandGoldGlow: Color.lerp(brandGoldGlow, other.brandGoldGlow, t)!,
      brandTextPrimary: Color.lerp(
        brandTextPrimary,
        other.brandTextPrimary,
        t,
      )!,
      brandTextSecondary: Color.lerp(
        brandTextSecondary,
        other.brandTextSecondary,
        t,
      )!,
      brandTextDim: Color.lerp(brandTextDim, other.brandTextDim, t)!,
      brandCardBg: Color.lerp(brandCardBg, other.brandCardBg, t)!,
      brandElevatedBg: Color.lerp(brandElevatedBg, other.brandElevatedBg, t)!,
      brandBorder: Color.lerp(brandBorder, other.brandBorder, t)!,
      brandBackground: Color.lerp(brandBackground, other.brandBackground, t)!,
      brandIgniteGradient: Gradient.lerp(
        brandIgniteGradient,
        other.brandIgniteGradient,
        t,
      )!,
      brandHeritageGradient: Gradient.lerp(
        brandHeritageGradient,
        other.brandHeritageGradient,
        t,
      )!,
      brandWordmarkGradient: Gradient.lerp(
        brandWordmarkGradient,
        other.brandWordmarkGradient,
        t,
      )!,
      brandCardRadius: lerpDouble(brandCardRadius, other.brandCardRadius, t)!,
      brandButtonRadius: lerpDouble(
        brandButtonRadius,
        other.brandButtonRadius,
        t,
      )!,
      brandInputRadius: lerpDouble(
        brandInputRadius,
        other.brandInputRadius,
        t,
      )!,
    );
  }
}

// ── Helper: lerpDouble (exposed by Flutter) ───────────────────────────
double? lerpDouble(num? a, num? b, double t) {
  if (a == null && b == null) return null;
  a ??= 0;
  b ??= 0;
  return a + (b - a) * t;
}

// ── Dark ColorScheme ──────────────────────────────────────────────────

ColorScheme _darkColorScheme() {
  return const ColorScheme.dark(
    primary: KinrelColors.purple, // #E8612A — Kinrel Orange
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF3A2D1E), // warm dark orange tint
    onPrimaryContainer: KinrelColors.brightViolet, // #F59240 — Warm Amber
    secondary: KinrelColors.gold, // #D4AF37
    onSecondary: Color(0xFF1C1917),
    secondaryContainer: Color(0xFF3D3520),
    onSecondaryContainer: KinrelColors.brightGold, // #FFD700
    tertiary: KinrelColors.brightViolet, // #F59240 — Warm Amber
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFF3A2D1E), // warm dark orange tint
    onTertiaryContainer: KinrelColors.brightViolet, // #F59240
    error: KinrelColors.error, // #F04E2A
    onError: Colors.white,
    errorContainer: Color(0xFF5C1A0A),
    onErrorContainer: Color(0xFFF87171),
    surface: KinrelColors.darkBackground, // #131416
    onSurface: KinrelColors.textWhite, // #F5F0EE warm white
    surfaceContainerLowest: Color(0xFF0A0A0E),
    surfaceContainerLow: KinrelColors.darkCard, // #191B2C
    surfaceContainer: KinrelColors.darkElevated, // #202338
    surfaceContainerHigh: KinrelColors.darkSurface, // #13141E
    surfaceContainerHighest: Color(0xFF282B44),
    onSurfaceVariant: KinrelColors.textSecondaryDark, // #C9B4A8
    outline: KinrelColors.textDim, // #8A7A72
    outlineVariant: KinrelColors.border, // #2A2A3D
    inverseSurface: Color(0xFFF5F0EE),
    onInverseSurface: Color(0xFF1C1917),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );
}

// ── Light ColorScheme ─────────────────────────────────────────────────

ColorScheme _lightColorScheme() {
  return const ColorScheme.light(
    primary: KinrelColors.deepPurple, // #C44A18 — Ember (darker for light bg)
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFFFE0CC), // light orange tint
    onPrimaryContainer: Color(0xFF3A1500),
    secondary: KinrelColors.gold, // #D4AF37
    onSecondary: Color(0xFF1C1917),
    secondaryContainer: Color(0xFFF5EDD0),
    onSecondaryContainer: Color(0xFF3D3520),
    tertiary: KinrelColors.purple, // #E8612A — Orange
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFE0CC),
    onTertiaryContainer: Color(0xFF3A1500),
    error: KinrelColors.error, // #F04E2A
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: KinrelColors.lightBackground, // #FFFAF8
    onSurface: KinrelColors.textDark, // #1A0A00
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: KinrelColors.lightCard, // #FFFFFF
    surfaceContainer: KinrelColors.lightElevated, // #F5F0EE
    surfaceContainerHigh: KinrelColors.lightSurface, // #E8E8ED
    surfaceContainerHighest: Color(0xFFD1D1D6),
    onSurfaceVariant: KinrelColors.textSecondaryLight, // #745040
    outline: Color(0xFF8E8E93),
    outlineVariant: Color(0xFFC7C7CC),
    inverseSurface: Color(0xFF1A0A00),
    onInverseSurface: Color(0xFFF5F0EE),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );
}

// ── Text Theme ────────────────────────────────────────────────────────

TextTheme _buildTextTheme(Brightness brightness) {
  final baseColor = brightness == Brightness.dark
      ? KinrelColors.textWhite
      : KinrelColors.textDark;
  final secondaryColor = brightness == Brightness.dark
      ? KinrelColors.textSecondaryDark
      : KinrelColors.textSecondaryLight;

  return TextTheme(
    // Display
    displayLarge: KinrelTypography.displayLarge.copyWith(color: baseColor),
    displayMedium: KinrelTypography.displayMedium.copyWith(color: baseColor),
    displaySmall: KinrelTypography.displaySmall.copyWith(color: baseColor),
    // Headline
    headlineLarge: KinrelTypography.headlineLarge.copyWith(color: baseColor),
    headlineMedium: KinrelTypography.headlineMedium.copyWith(color: baseColor),
    headlineSmall: KinrelTypography.headlineSmall.copyWith(color: baseColor),
    // Title
    titleLarge: KinrelTypography.titleLarge.copyWith(color: baseColor),
    titleMedium: KinrelTypography.titleMedium.copyWith(color: secondaryColor),
    titleSmall: KinrelTypography.titleSmall.copyWith(color: secondaryColor),
    // Body
    bodyLarge: KinrelTypography.bodyLarge.copyWith(color: baseColor),
    bodyMedium: KinrelTypography.bodyMedium.copyWith(color: secondaryColor),
    bodySmall: KinrelTypography.bodySmall.copyWith(color: secondaryColor),
    // Label
    labelLarge: KinrelTypography.labelLarge.copyWith(color: baseColor),
    labelMedium: KinrelTypography.labelMedium.copyWith(color: secondaryColor),
    labelSmall: KinrelTypography.labelSmall.copyWith(color: secondaryColor),
  );
}

// ── Component Themes ──────────────────────────────────────────────────

AppBarTheme _appBarTheme(Brightness brightness) {
  final bgColor = brightness == Brightness.dark
      ? const Color(0xB3131416) // darkBackground with 0.70 alpha
      : const Color(0xCCFFFAF8); // lightBackground with 0.80 alpha
  final fgColor = brightness == Brightness.dark
      ? KinrelColors.textWhite
      : KinrelColors.textDark;

  return AppBarTheme(
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: bgColor,
    foregroundColor: fgColor,
    titleTextStyle: TextStyle(
      fontFamily: KinrelTypography.displayFont,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: fgColor,
    ),
    // Orange tint on scroll
    surfaceTintColor: KinrelColors.orange.withValues(alpha: 0.08),
  );
}

CardThemeData _cardTheme(Brightness brightness) {
  final cardColor = brightness == Brightness.dark
      ? KinrelColors
            .darkCard // #191B2C
      : KinrelColors.lightCard; // #FFFFFF
  final borderColor = brightness == Brightness.dark
      ? const Color(0x1AFFFFFF) // rgba(255,255,255,0.10)
      : KinrelColors.lightBorder;

  return CardThemeData(
    elevation: 0,
    color: cardColor,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.card),
      side: BorderSide(color: borderColor, width: 1),
    ),
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
  );
}

ElevatedButtonThemeData _elevatedButtonTheme(Brightness brightness) {
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors
            .purple // #E8612A — orange primary
      : KinrelColors.deepPurple; // #C44A18 — ember for light bg
  final disabledBg = brightness == Brightness.dark
      ? KinrelColors.darkElevated
      : KinrelColors.lightElevated;
  final disabledFg = brightness == Brightness.dark
      ? KinrelColors.textDim
      : KinrelColors.textSecondaryLight;

  return ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      disabledBackgroundColor: disabledBg,
      disabledForegroundColor: disabledFg,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      padding: EdgeInsets.symmetric(
        horizontal: KinrelSpacing.xl,
        vertical: KinrelSpacing.md,
      ),
      minimumSize: Size(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.button),
      ),
      textStyle: KinrelTypography.labelLarge,
    ),
  );
}

OutlinedButtonThemeData _outlinedButtonTheme(Brightness brightness) {
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors
            .purple // #E8612A — orange
      : KinrelColors.deepPurple; // #C44A18 — ember
  final disabledFg = brightness == Brightness.dark
      ? KinrelColors.textDim
      : KinrelColors.textSecondaryLight;

  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: primaryColor,
      disabledForegroundColor: disabledFg,
      side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
      padding: EdgeInsets.symmetric(
        horizontal: KinrelSpacing.xl,
        vertical: KinrelSpacing.md,
      ),
      minimumSize: Size(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.button),
      ),
      textStyle: KinrelTypography.labelLarge,
    ),
  );
}

TextButtonThemeData _textButtonTheme(Brightness brightness) {
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors
            .purple // #E8612A — orange
      : KinrelColors.deepPurple; // #C44A18 — ember
  final disabledFg = brightness == Brightness.dark
      ? KinrelColors.textDim
      : KinrelColors.textSecondaryLight;

  return TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: primaryColor,
      disabledForegroundColor: disabledFg,
      padding: EdgeInsets.symmetric(
        horizontal: KinrelSpacing.lg,
        vertical: KinrelSpacing.sm,
      ),
      minimumSize: Size(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.button),
      ),
      textStyle: KinrelTypography.labelLarge,
    ),
  );
}

InputDecorationTheme _inputDecorationTheme(Brightness brightness) {
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors
            .purple // #E8612A — orange focus
      : KinrelColors.deepPurple; // #C44A18 — ember focus
  final fillColor = brightness == Brightness.dark
      ? KinrelColors.darkElevated
      : KinrelColors.lightElevated;
  final borderColor = brightness == Brightness.dark
      ? KinrelColors.textDim.withValues(alpha: 0.3)
      : KinrelColors.textSecondaryLight.withValues(alpha: 0.3);
  final enabledBorderColor = brightness == Brightness.dark
      ? KinrelColors.border
      : KinrelColors.lightBorder;
  final hintColor = brightness == Brightness.dark
      ? KinrelColors.textDim
      : KinrelColors.textSecondaryLight;
  final labelColor = brightness == Brightness.dark
      ? KinrelColors.textSecondaryDark
      : KinrelColors.textSecondaryLight;

  return InputDecorationTheme(
    filled: true,
    fillColor: fillColor,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: KinrelSpacing.lg,
      vertical: KinrelSpacing.md,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.input),
      borderSide: BorderSide(color: borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.input),
      borderSide: BorderSide(color: enabledBorderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.input),
      borderSide: BorderSide(color: primaryColor, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.input),
      borderSide: BorderSide(color: KinrelColors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.input),
      borderSide: BorderSide(color: KinrelColors.error, width: 2),
    ),
    hintStyle: TextStyle(
      fontFamily: KinrelTypography.bodyFont,
      color: hintColor,
      fontSize: 14,
    ),
    labelStyle: TextStyle(
      fontFamily: KinrelTypography.bodyFont,
      color: labelColor,
      fontSize: 14,
    ),
    floatingLabelStyle: TextStyle(
      fontFamily: KinrelTypography.bodyFont,
      color: primaryColor,
      fontSize: 12,
    ),
  );
}

BottomNavigationBarThemeData _bottomNavigationBarTheme(Brightness brightness) {
  final bgColor = brightness == Brightness.dark
      ? const Color(0xCC191B2C) // darkCard semi-transparent
      : const Color(0xCCFFFFFF); // lightCard semi-transparent
  final selectedItemColor = KinrelColors.purple; // #E8612A — orange active
  final unselectedItemColor = brightness == Brightness.dark
      ? KinrelColors.textDim
      : KinrelColors.textSecondaryLight;

  return BottomNavigationBarThemeData(
    backgroundColor: bgColor,
    selectedItemColor: selectedItemColor,
    unselectedItemColor: unselectedItemColor,
    type: BottomNavigationBarType.fixed,
    elevation: 0,
    selectedLabelStyle: KinrelTypography.labelSmall,
    unselectedLabelStyle: KinrelTypography.labelSmall,
  );
}

TabBarThemeData _tabBarTheme(Brightness brightness) {
  final primaryColor = KinrelColors.purple; // #E8612A — orange indicator
  final unselectedColor = brightness == Brightness.dark
      ? KinrelColors.textDim
      : KinrelColors.textSecondaryLight;
  final dividerColor = brightness == Brightness.dark
      ? KinrelColors.border
      : KinrelColors.lightBorder;

  return TabBarThemeData(
    labelColor: primaryColor,
    unselectedLabelColor: unselectedColor,
    indicatorColor: primaryColor,
    indicatorSize: TabBarIndicatorSize.label,
    labelStyle: KinrelTypography.labelLarge,
    unselectedLabelStyle: KinrelTypography.labelLarge,
    dividerColor: dividerColor,
  );
}

DialogThemeData _dialogTheme(Brightness brightness) {
  final cardColor = brightness == Brightness.dark
      ? KinrelColors.darkCard
      : KinrelColors.lightCard;
  final borderColor = brightness == Brightness.dark
      ? const Color(0x1AFFFFFF) // rgba(255,255,255,0.10)
      : KinrelColors.lightBorder;
  final textPrimary = brightness == Brightness.dark
      ? KinrelColors.textWhite
      : KinrelColors.textDark;
  final textSecondary = brightness == Brightness.dark
      ? KinrelColors.textSecondaryDark
      : KinrelColors.textSecondaryLight;

  return DialogThemeData(
    backgroundColor: cardColor,
    elevation: 4,
    shadowColor: Colors.black26,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.dialog),
      side: BorderSide(color: borderColor, width: 1),
    ),
    titleTextStyle: KinrelTypography.headlineSmall.copyWith(color: textPrimary),
    contentTextStyle: KinrelTypography.bodyMedium.copyWith(
      color: textSecondary,
    ),
  );
}

BottomSheetThemeData _bottomSheetTheme(Brightness brightness) {
  final cardColor = brightness == Brightness.dark
      ? KinrelColors.darkCard
      : KinrelColors.lightCard;
  final dragColor = brightness == Brightness.dark
      ? const Color(0x4D8A7A72)
      : const Color(0x4D8E8E93);

  return BottomSheetThemeData(
    backgroundColor: cardColor,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KinrelRadius.bottomSheet),
      ),
    ),
    showDragHandle: true,
    dragHandleColor: dragColor,
    constraints: BoxConstraints(maxWidth: 640),
  );
}

ChipThemeData _chipTheme(Brightness brightness) {
  final elevatedBg = brightness == Brightness.dark
      ? KinrelColors.darkElevated
      : KinrelColors.lightElevated;
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors
            .purple // #E8612A — orange tint when selected
      : KinrelColors.deepPurple; // #C44A18 — ember
  final textPrimary = brightness == Brightness.dark
      ? KinrelColors.textWhite
      : KinrelColors.textDark;
  final borderColor = brightness == Brightness.dark
      ? const Color(0x1AFFFFFF) // rgba(255,255,255,0.10)
      : KinrelColors.lightBorder;

  return ChipThemeData(
    backgroundColor: elevatedBg,
    selectedColor: primaryColor.withValues(alpha: 0.2),
    disabledColor: elevatedBg.withValues(alpha: 0.5),
    deleteIconColor: brightness == Brightness.dark
        ? KinrelColors.textSecondaryDark
        : KinrelColors.textSecondaryLight,
    labelStyle: KinrelTypography.labelMedium.copyWith(color: textPrimary),
    secondaryLabelStyle: KinrelTypography.labelMedium.copyWith(
      color: primaryColor,
    ),
    side: BorderSide(color: borderColor),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.chip),
    ),
    padding: EdgeInsets.symmetric(
      horizontal: KinrelSpacing.md,
      vertical: KinrelSpacing.xs,
    ),
  );
}

FloatingActionButtonThemeData _fabTheme(Brightness brightness) {
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors
            .purple // #E8612A — orange FAB
      : KinrelColors.deepPurple; // #C44A18 — ember FAB

  return FloatingActionButtonThemeData(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    disabledElevation: 0,
    elevation: 2,
    highlightElevation: 4,
    shape: CircleBorder(),
    extendedTextStyle: KinrelTypography.labelLarge,
  );
}

SnackBarThemeData _snackbarTheme(Brightness brightness) {
  final bgColor = brightness == Brightness.dark
      ? KinrelColors.darkElevated
      : KinrelColors.lightElevated;
  final textPrimary = brightness == Brightness.dark
      ? KinrelColors.textWhite
      : KinrelColors.textDark;
  final actionColor = KinrelColors.purple; // #E8612A — orange action

  return SnackBarThemeData(
    backgroundColor: bgColor,
    contentTextStyle: KinrelTypography.bodyMedium.copyWith(color: textPrimary),
    actionTextColor: actionColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.sm),
    ),
    behavior: SnackBarBehavior.floating,
    elevation: 2,
  );
}

DividerThemeData _dividerTheme(Brightness brightness) {
  final color = brightness == Brightness.dark
      ? KinrelColors.border
      : KinrelColors.lightBorder;

  return DividerThemeData(color: color, thickness: 1, space: 1);
}

SwitchThemeData _switchTheme(Brightness brightness) {
  final primaryColor = KinrelColors.purple; // #E8612A — orange active
  final elevatedBg = brightness == Brightness.dark
      ? KinrelColors.darkElevated
      : KinrelColors.lightElevated;
  final surfaceColor = brightness == Brightness.dark
      ? KinrelColors.darkSurface
      : KinrelColors.lightSurface;
  final dimColor = brightness == Brightness.dark
      ? KinrelColors.textDim
      : KinrelColors.textSecondaryLight;
  final secondaryColor = brightness == Brightness.dark
      ? KinrelColors.textSecondaryDark
      : KinrelColors.textSecondaryLight;

  return SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return dimColor.withValues(alpha: 0.5);
      }
      if (states.contains(WidgetState.selected)) {
        return Colors.white;
      }
      return secondaryColor;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return elevatedBg.withValues(alpha: 0.5);
      }
      if (states.contains(WidgetState.selected)) {
        return primaryColor;
      }
      return surfaceColor;
    }),
    trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
  );
}

ProgressIndicatorThemeData _progressBarTheme(Brightness brightness) {
  final primaryColor = KinrelColors.purple; // #E8612A — orange progress
  final trackColor = brightness == Brightness.dark
      ? KinrelColors.darkElevated
      : KinrelColors.lightElevated;

  return ProgressIndicatorThemeData(
    color: primaryColor,
    linearTrackColor: trackColor,
    circularTrackColor: trackColor,
    linearMinHeight: 4,
    borderRadius: BorderRadius.circular(2),
  );
}

// ── Brand Theme Extension Builders ────────────────────────────────────

KinrelThemeExtension _darkExtension() {
  return const KinrelThemeExtension(
    // Core orange palette
    brandOrange: KinrelColors.orange, // #E8612A
    brandAmber: KinrelColors.amber, // #F59240
    brandEmber: KinrelColors.ember, // #C44A18
    brandGlow: KinrelColors.orangeGlow, // Color(0x33E8612A)
    // Brand legacy aliases
    brandPurple: KinrelColors.purple, // #E8612A (now orange)
    brandDeepPurple: KinrelColors.deepPurple, // #C44A18 (now ember)
    brandGold: KinrelColors.gold, // #D4AF37
    brandViolet: KinrelColors.violet, // #E8612A (now orange)
    brandCoral: KinrelColors.coral, // #FF6B6B
    brandPurpleGlow:
        KinrelColors.purpleGlow, // Color(0x33E8612A) (now orange glow)
    brandGoldGlow: KinrelColors.goldGlow, // Color(0x47D4AF37)
    // Text
    brandTextPrimary: KinrelColors.textWhite, // #F5F0EE warm white
    brandTextSecondary: KinrelColors.textSecondaryDark, // #C9B4A8
    brandTextDim: KinrelColors.textDim, // #8A7A72
    // Surface
    brandCardBg: KinrelColors.darkCard, // #191B2C
    brandElevatedBg: KinrelColors.darkElevated, // #202338
    brandBorder: Color(0x1AFFFFFF), // rgba(255,255,255,0.10)
    brandBackground: KinrelColors.darkBackground, // #131416
    // Gradients
    brandIgniteGradient: KinrelGradients.ignite,
    brandHeritageGradient: KinrelGradients.heritage,
    brandWordmarkGradient: KinrelGradients.wordmarkGradient,
    // Radii
    brandCardRadius: KinrelRadius.card,
    brandButtonRadius: KinrelRadius.button,
    brandInputRadius: KinrelRadius.input,
  );
}

KinrelThemeExtension _lightExtension() {
  return const KinrelThemeExtension(
    // Core orange palette
    brandOrange: KinrelColors.orange, // #E8612A
    brandAmber: KinrelColors.amber, // #F59240
    brandEmber: KinrelColors.ember, // #C44A18
    brandGlow: KinrelColors.orangeGlow, // Color(0x33E8612A)
    // Brand legacy aliases
    brandPurple: KinrelColors.deepPurple, // #C44A18 (ember for light bg)
    brandDeepPurple: KinrelColors.deepPurple, // #C44A18
    brandGold: KinrelColors.gold, // #D4AF37
    brandViolet: KinrelColors.purple, // #E8612A (orange)
    brandCoral: KinrelColors.coral, // #FF6B6B
    brandPurpleGlow:
        KinrelColors.purpleGlow, // Color(0x33E8612A) (now orange glow)
    brandGoldGlow: KinrelColors.goldGlow, // Color(0x47D4AF37)
    // Text
    brandTextPrimary: KinrelColors.textDark, // #1A0A00
    brandTextSecondary: KinrelColors.textSecondaryLight, // #745040
    brandTextDim: KinrelColors.textSecondaryLight, // #745040
    // Surface
    brandCardBg: KinrelColors.lightCard, // #FFFFFF
    brandElevatedBg: KinrelColors.lightElevated, // #F5F0EE
    brandBorder: KinrelColors.lightBorder, // Color(0x14000000)
    brandBackground: KinrelColors.lightBackground, // #FFFAF8
    // Gradients
    brandIgniteGradient: KinrelGradients.ignite,
    brandHeritageGradient: KinrelGradients.heritage,
    brandWordmarkGradient: KinrelGradients.wordmarkGradient,
    // Radii
    brandCardRadius: KinrelRadius.card,
    brandButtonRadius: KinrelRadius.button,
    brandInputRadius: KinrelRadius.input,
  );
}

// ── Main Theme Builder ────────────────────────────────────────────────

/// Returns a complete [ThemeData] for the given [brightness] and [deviceTier].
/// Supports both [Brightness.dark] and [Brightness.light].
/// Page transitions adapt to device tier:
///   low:  FadeUpwardsPageTransitionsBuilder (lightweight)
///   mid:  ZoomPageTransitionsBuilder (default)
///   high: ZoomPageTransitionsBuilder (default)
ThemeData getAppTheme(Brightness brightness, {DeviceTier deviceTier = DeviceTier.mid}) {
  final isDark = brightness == Brightness.dark;
  final colorScheme = isDark ? _darkColorScheme() : _lightColorScheme();

  // Primary color for icon themes etc.
  final primaryColor = isDark ? KinrelColors.purple : KinrelColors.deepPurple;
  final textSecondary = isDark
      ? KinrelColors.textSecondaryDark
      : KinrelColors.textSecondaryLight;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,

    // ── Typography ────────────────────────────────────────────────
    textTheme: _buildTextTheme(brightness),
    primaryTextTheme: _buildTextTheme(brightness),

    // ── Component Themes ──────────────────────────────────────────
    appBarTheme: _appBarTheme(brightness),
    cardTheme: _cardTheme(brightness),
    elevatedButtonTheme: _elevatedButtonTheme(brightness),
    outlinedButtonTheme: _outlinedButtonTheme(brightness),
    textButtonTheme: _textButtonTheme(brightness),
    inputDecorationTheme: _inputDecorationTheme(brightness),
    bottomNavigationBarTheme: _bottomNavigationBarTheme(brightness),
    tabBarTheme: _tabBarTheme(brightness),
    dialogTheme: _dialogTheme(brightness),
    bottomSheetTheme: _bottomSheetTheme(brightness),
    chipTheme: _chipTheme(brightness),
    floatingActionButtonTheme: _fabTheme(brightness),
    snackBarTheme: _snackbarTheme(brightness),
    dividerTheme: _dividerTheme(brightness),
    switchTheme: _switchTheme(brightness),
    progressIndicatorTheme: _progressBarTheme(brightness),

    // ── Additional Component Themes ───────────────────────────────
    iconTheme: IconThemeData(color: textSecondary, size: 24),
    primaryIconTheme: IconThemeData(color: primaryColor, size: 24),

    listTileTheme: ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(
        horizontal: KinrelSpacing.lg,
        vertical: KinrelSpacing.xs,
      ),
      textColor: isDark ? KinrelColors.textWhite : KinrelColors.textDark,
      iconColor: textSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
      ),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? KinrelColors.darkElevated : KinrelColors.lightElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        border: Border.all(
          color: isDark ? const Color(0x1AFFFFFF) : KinrelColors.lightBorder,
        ),
      ),
      textStyle: KinrelTypography.bodySmall.copyWith(
        color: isDark ? KinrelColors.textWhite : KinrelColors.textDark,
      ),
      waitDuration: Duration(milliseconds: 500),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? KinrelColors.darkCard : KinrelColors.lightCard,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        side: BorderSide(
          color: isDark ? const Color(0x1AFFFFFF) : KinrelColors.lightBorder,
        ),
      ),
      textStyle: KinrelTypography.bodyMedium.copyWith(
        color: isDark ? KinrelColors.textWhite : KinrelColors.textDark,
      ),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: isDark ? KinrelColors.darkCard : KinrelColors.lightCard,
      indicatorColor: primaryColor.withValues(alpha: 0.15),
      selectedIconTheme: IconThemeData(color: primaryColor, size: 24),
      unselectedIconTheme: IconThemeData(
        color: isDark ? KinrelColors.textDim : KinrelColors.textSecondaryLight,
        size: 24,
      ),
      selectedLabelTextStyle: KinrelTypography.labelSmall.copyWith(
        color: primaryColor,
      ),
      unselectedLabelTextStyle: KinrelTypography.labelSmall.copyWith(
        color: isDark ? KinrelColors.textDim : KinrelColors.textSecondaryLight,
      ),
      elevation: 0,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark
          ? const Color(0xCC191B2C) // semi-transparent darkCard
          : const Color(0xCCFFFFFF), // semi-transparent lightCard
      indicatorColor: primaryColor.withValues(alpha: 0.15),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: primaryColor);
        }
        return IconThemeData(
          color: isDark
              ? KinrelColors.textDim
              : KinrelColors.textSecondaryLight,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return KinrelTypography.labelSmall.copyWith(color: primaryColor);
        }
        return KinrelTypography.labelSmall.copyWith(
          color: isDark
              ? KinrelColors.textDim
              : KinrelColors.textSecondaryLight,
        );
      }),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: primaryColor,
      inactiveTrackColor: isDark
          ? KinrelColors.darkElevated
          : KinrelColors.lightElevated,
      thumbColor: primaryColor,
      overlayColor: primaryColor.withValues(alpha: 0.12),
      trackHeight: 4,
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return (isDark
                  ? KinrelColors.darkElevated
                  : KinrelColors.lightElevated)
              .withValues(alpha: 0.5);
        }
        if (states.contains(WidgetState.selected)) {
          return primaryColor;
        }
        return Colors.transparent;
      }),
      side: BorderSide(
        color: (isDark ? KinrelColors.textDim : KinrelColors.textSecondaryLight)
            .withValues(alpha: 0.5),
        width: 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.xs),
      ),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryColor;
        }
        return isDark ? KinrelColors.textDim : KinrelColors.textSecondaryLight;
      }),
    ),

    // ── Extensions ────────────────────────────────────────────────
    extensions: <ThemeExtension<dynamic>>[
      isDark ? _darkExtension() : _lightExtension(),
    ],

    // ── Page transitions (adapted to device tier) ─────────────────
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        TargetPlatform.android: deviceTier == DeviceTier.low
            ? const FadeUpwardsPageTransitionsBuilder()
            : const ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: deviceTier == DeviceTier.low
            ? const FadeUpwardsPageTransitionsBuilder()
            : const ZoomPageTransitionsBuilder(),
        TargetPlatform.macOS: deviceTier == DeviceTier.low
            ? const FadeUpwardsPageTransitionsBuilder()
            : const ZoomPageTransitionsBuilder(),
      },
    ),

    // ── Visual density ────────────────────────────────────────────
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
