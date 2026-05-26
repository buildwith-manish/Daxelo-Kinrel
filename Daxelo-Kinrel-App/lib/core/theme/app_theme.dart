// lib/core/theme/app_theme.dart
//
// DAXELO KINREL — Material 3 Theme (LIGHT + DARK)
//
// Comprehensive Material 3 theme with both light and dark modes
// using the KINREL brand system — Premium Purple & Gold.
//
// Dark theme:
//   Primary: DeepPurple #4B3F8A
//   Secondary: Gold #D4AF37
//   Background: #121212
//   Card: #1E1E1E
//   Elevated: #2A2A3E
//   Surface: #2A1F4A
//   Text primary: #FFFFFF
//   Text secondary: #B0B0B0
//
// Light theme:
//   Primary: Purple #5D5FEF
//   Secondary: Gold #D4AF37
//   Background: #F5F7FA
//   Card: #FFFFFF
//   Elevated: #F2F2F7
//   Surface: #E8E8ED
//   Text primary: #2D3748
//   Text secondary: #8E8E93
//
// Fonts: Outfit (display), DMSans (body), DMMono (mono)

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../constants/brand_colors.dart';
import '../constants/brand_typography.dart';
import '../constants/brand_spacing.dart';

// ── Theme Extension ───────────────────────────────────────────────────

/// Custom brand-specific theme properties accessible via
/// `Theme.of(context).extension<KinrelThemeExtension>()`.
@immutable
class KinrelThemeExtension extends ThemeExtension<KinrelThemeExtension> {
  const KinrelThemeExtension({
    // Legacy
    required this.brandOrange,
    required this.brandAmber,
    required this.brandEmber,
    required this.brandGlow,
    // New
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

  // ── Legacy orange aliases (backward compat) ────────────────────
  final Color brandOrange;
  final Color brandAmber;
  final Color brandEmber;
  final Color brandGlow;

  // ── New purple/gold properties ─────────────────────────────────
  final Color brandPurple;
  final Color brandDeepPurple;
  final Color brandGold;
  final Color brandViolet;
  final Color brandCoral;
  final Color brandPurpleGlow;
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
  KinrelThemeExtension lerp(
    covariant KinrelThemeExtension? other,
    double t,
  ) {
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
      brandTextPrimary:
          Color.lerp(brandTextPrimary, other.brandTextPrimary, t)!,
      brandTextSecondary:
          Color.lerp(brandTextSecondary, other.brandTextSecondary, t)!,
      brandTextDim: Color.lerp(brandTextDim, other.brandTextDim, t)!,
      brandCardBg: Color.lerp(brandCardBg, other.brandCardBg, t)!,
      brandElevatedBg: Color.lerp(brandElevatedBg, other.brandElevatedBg, t)!,
      brandBorder: Color.lerp(brandBorder, other.brandBorder, t)!,
      brandBackground: Color.lerp(brandBackground, other.brandBackground, t)!,
      brandIgniteGradient: Gradient.lerp(
          brandIgniteGradient, other.brandIgniteGradient, t)!,
      brandHeritageGradient: Gradient.lerp(
          brandHeritageGradient, other.brandHeritageGradient, t)!,
      brandWordmarkGradient: Gradient.lerp(
          brandWordmarkGradient, other.brandWordmarkGradient, t)!,
      brandCardRadius:
          lerpDouble(brandCardRadius, other.brandCardRadius, t)!,
      brandButtonRadius:
          lerpDouble(brandButtonRadius, other.brandButtonRadius, t)!,
      brandInputRadius:
          lerpDouble(brandInputRadius, other.brandInputRadius, t)!,
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
    primary: KinrelColors.deepPurple,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF3A2D6E),
    onPrimaryContainer: KinrelColors.brightViolet,
    secondary: KinrelColors.gold,
    onSecondary: Color(0xFF1C1917),
    secondaryContainer: Color(0xFF3D3520),
    onSecondaryContainer: KinrelColors.brightGold,
    tertiary: KinrelColors.violet,
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFF3A2D6E),
    onTertiaryContainer: KinrelColors.brightViolet,
    error: KinrelColors.error,
    onError: Colors.white,
    errorContainer: Color(0xFF5C1A0A),
    onErrorContainer: Color(0xFFF87171),
    surface: KinrelColors.darkBackground,
    onSurface: KinrelColors.textWhite,
    surfaceContainerLowest: Color(0xFF0A0A0A),
    surfaceContainerLow: KinrelColors.darkCard,
    surfaceContainer: KinrelColors.darkElevated,
    surfaceContainerHigh: KinrelColors.darkSurface,
    surfaceContainerHighest: Color(0xFF3A3A5E),
    onSurfaceVariant: KinrelColors.textSecondaryDark,
    outline: Color(0xFF78716C),
    outlineVariant: Color(0xFF44403C),
    inverseSurface: Color(0xFFF5F5F4),
    onInverseSurface: Color(0xFF1C1917),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );
}

// ── Light ColorScheme ─────────────────────────────────────────────────

ColorScheme _lightColorScheme() {
  return const ColorScheme.light(
    primary: KinrelColors.purple,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE0E0FF),
    onPrimaryContainer: Color(0xFF1A1A4E),
    secondary: KinrelColors.gold,
    onSecondary: Color(0xFF1C1917),
    secondaryContainer: Color(0xFFF5EDD0),
    onSecondaryContainer: Color(0xFF3D3520),
    tertiary: KinrelColors.violet,
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE8D5FF),
    onTertiaryContainer: Color(0xFF2D1A4E),
    error: KinrelColors.error,
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: KinrelColors.lightBackground,
    onSurface: KinrelColors.textDark,
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: KinrelColors.lightCard,
    surfaceContainer: KinrelColors.lightElevated,
    surfaceContainerHigh: KinrelColors.lightSurface,
    surfaceContainerHighest: Color(0xFFD1D1D6),
    onSurfaceVariant: KinrelColors.textSecondaryLight,
    outline: Color(0xFF8E8E93),
    outlineVariant: Color(0xFFC7C7CC),
    inverseSurface: Color(0xFF2D3748),
    onInverseSurface: Color(0xFFF5F5F4),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );
}

// ── Text Theme ────────────────────────────────────────────────────────

TextTheme _buildTextTheme(Brightness brightness) {
  final baseColor =
      brightness == Brightness.dark ? KinrelColors.textWhite : KinrelColors.textDark;
  final secondaryColor =
      brightness == Brightness.dark ? KinrelColors.textSecondaryDark : KinrelColors.textSecondaryLight;

  return TextTheme(
    // Display
    displayLarge: KinrelTypography.displayLarge.copyWith(color: baseColor),
    displayMedium: KinrelTypography.displayMedium.copyWith(color: baseColor),
    displaySmall: KinrelTypography.displaySmall.copyWith(color: baseColor),
    // Headline
    headlineLarge: KinrelTypography.headlineLarge.copyWith(color: baseColor),
    headlineMedium:
        KinrelTypography.headlineMedium.copyWith(color: baseColor),
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
      ? const Color(0xB3121212) // darkBackground with 0.70 alpha
      : const Color(0xCCF5F7FA); // lightBackground with 0.80 alpha
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
    surfaceTintColor: Colors.transparent,
  );
}

CardThemeData _cardTheme(Brightness brightness) {
  final cardColor = brightness == Brightness.dark
      ? KinrelColors.darkCard
      : KinrelColors.lightCard;
  final borderColor = brightness == Brightness.dark
      ? KinrelColors.border
      : KinrelColors.lightBorder;

  return CardThemeData(
    elevation: 0,
    color: cardColor,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.card),
      side: BorderSide(
        color: borderColor,
        width: 1,
      ),
    ),
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
  );
}

ElevatedButtonThemeData _elevatedButtonTheme(Brightness brightness) {
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors.deepPurple
      : KinrelColors.purple;
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
      ? KinrelColors.deepPurple
      : KinrelColors.purple;
  final disabledFg = brightness == Brightness.dark
      ? KinrelColors.textDim
      : KinrelColors.textSecondaryLight;

  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: primaryColor,
      disabledForegroundColor: disabledFg,
      side: BorderSide(
        color: primaryColor.withValues(alpha: 0.5),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.xl,
        vertical: KinrelSpacing.md,
      ),
      minimumSize: const Size(0, 48),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.button),
      ),
      textStyle: KinrelTypography.labelLarge,
    ),
  );
}

TextButtonThemeData _textButtonTheme(Brightness brightness) {
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors.deepPurple
      : KinrelColors.purple;
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
      ? KinrelColors.deepPurple
      : KinrelColors.purple;
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
      ? const Color(0xCC1E1E1E) // darkCard semi-transparent
      : const Color(0xCCFFFFFF); // lightCard semi-transparent
  final selectedItemColor = brightness == Brightness.dark
      ? KinrelColors.purple
      : KinrelColors.purple;
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
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors.purple
      : KinrelColors.purple;
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
      ? KinrelColors.border
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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.dialog),
      side: BorderSide(
        color: borderColor,
        width: 1,
      ),
    ),
    titleTextStyle: KinrelTypography.headlineSmall.copyWith(
      color: textPrimary,
    ),
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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KinrelRadius.bottomSheet),
      ),
    ),
    showDragHandle: true,
    dragHandleColor: dragColor,
    constraints: const BoxConstraints(maxWidth: 640),
  );
}

ChipThemeData _chipTheme(Brightness brightness) {
  final elevatedBg = brightness == Brightness.dark
      ? KinrelColors.darkElevated
      : KinrelColors.lightElevated;
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors.deepPurple
      : KinrelColors.purple;
  final textPrimary = brightness == Brightness.dark
      ? KinrelColors.textWhite
      : KinrelColors.textDark;
  final borderColor = brightness == Brightness.dark
      ? KinrelColors.border
      : KinrelColors.lightBorder;

  return ChipThemeData(
    backgroundColor: elevatedBg,
    selectedColor: primaryColor.withValues(alpha: 0.2),
    disabledColor: elevatedBg.withValues(alpha: 0.5),
    deleteIconColor: brightness == Brightness.dark
        ? KinrelColors.textSecondaryDark
        : KinrelColors.textSecondaryLight,
    labelStyle: KinrelTypography.labelMedium.copyWith(
      color: textPrimary,
    ),
    secondaryLabelStyle: KinrelTypography.labelMedium.copyWith(
      color: primaryColor,
    ),
    side: BorderSide(
      color: borderColor,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.chip),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: KinrelSpacing.md,
      vertical: KinrelSpacing.xs,
    ),
  );
}

FloatingActionButtonThemeData _fabTheme(Brightness brightness) {
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors.deepPurple
      : KinrelColors.purple;

  return FloatingActionButtonThemeData(
    backgroundColor: primaryColor,
    foregroundColor: Colors.white,
    disabledElevation: 0,
    elevation: 2,
    highlightElevation: 4,
    shape: const CircleBorder(),
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
  final actionColor = brightness == Brightness.dark
      ? KinrelColors.gold
      : KinrelColors.purple;

  return SnackBarThemeData(
    backgroundColor: bgColor,
    contentTextStyle: KinrelTypography.bodyMedium.copyWith(
      color: textPrimary,
    ),
    actionTextColor: actionColor,
    shape: const RoundedRectangleBorder(
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

  return DividerThemeData(
    color: color,
    thickness: 1,
    space: 1,
  );
}

SwitchThemeData _switchTheme(Brightness brightness) {
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors.deepPurple
      : KinrelColors.purple;
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
  final primaryColor = brightness == Brightness.dark
      ? KinrelColors.deepPurple
      : KinrelColors.purple;
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
    brandOrange: KinrelColors.orange,
    brandAmber: KinrelColors.amber,
    brandEmber: KinrelColors.ember,
    brandGlow: KinrelColors.purpleGlow,
    brandPurple: KinrelColors.deepPurple,
    brandDeepPurple: KinrelColors.deepPurple,
    brandGold: KinrelColors.gold,
    brandViolet: KinrelColors.violet,
    brandCoral: KinrelColors.coral,
    brandPurpleGlow: KinrelColors.purpleGlow,
    brandGoldGlow: KinrelColors.goldGlow,
    brandTextPrimary: KinrelColors.textWhite,
    brandTextSecondary: KinrelColors.textSecondaryDark,
    brandTextDim: KinrelColors.textDim,
    brandCardBg: KinrelColors.darkCard,
    brandElevatedBg: KinrelColors.darkElevated,
    brandBorder: KinrelColors.border,
    brandBackground: KinrelColors.darkBackground,
    brandIgniteGradient: KinrelGradients.ignite,
    brandHeritageGradient: KinrelGradients.heritage,
    brandWordmarkGradient: KinrelGradients.wordmarkGradient,
    brandCardRadius: KinrelRadius.card,
    brandButtonRadius: KinrelRadius.button,
    brandInputRadius: KinrelRadius.input,
  );
}

KinrelThemeExtension _lightExtension() {
  return const KinrelThemeExtension(
    brandOrange: KinrelColors.orange,
    brandAmber: KinrelColors.amber,
    brandEmber: KinrelColors.ember,
    brandGlow: KinrelColors.purpleGlow,
    brandPurple: KinrelColors.purple,
    brandDeepPurple: KinrelColors.deepPurple,
    brandGold: KinrelColors.gold,
    brandViolet: KinrelColors.violet,
    brandCoral: KinrelColors.coral,
    brandPurpleGlow: KinrelColors.purpleGlow,
    brandGoldGlow: KinrelColors.goldGlow,
    brandTextPrimary: KinrelColors.textDark,
    brandTextSecondary: KinrelColors.textSecondaryLight,
    brandTextDim: KinrelColors.textSecondaryLight,
    brandCardBg: KinrelColors.lightCard,
    brandElevatedBg: KinrelColors.lightElevated,
    brandBorder: KinrelColors.lightBorder,
    brandBackground: KinrelColors.lightBackground,
    brandIgniteGradient: KinrelGradients.ignite,
    brandHeritageGradient: KinrelGradients.heritage,
    brandWordmarkGradient: KinrelGradients.wordmarkGradient,
    brandCardRadius: KinrelRadius.card,
    brandButtonRadius: KinrelRadius.button,
    brandInputRadius: KinrelRadius.input,
  );
}

// ── Main Theme Builder ────────────────────────────────────────────────

/// Returns a complete [ThemeData] for the given [brightness].
/// Supports both [Brightness.dark] and [Brightness.light].
ThemeData getAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final colorScheme =
      isDark ? _darkColorScheme() : _lightColorScheme();

  // Primary color for icon themes etc.
  final primaryColor = isDark ? KinrelColors.deepPurple : KinrelColors.purple;
  final textSecondary =
      isDark ? KinrelColors.textSecondaryDark : KinrelColors.textSecondaryLight;

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
    iconTheme: IconThemeData(
      color: textSecondary,
      size: 24,
    ),
    primaryIconTheme: IconThemeData(
      color: primaryColor,
      size: 24,
    ),

    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.lg,
        vertical: KinrelSpacing.xs,
      ),
      textColor: isDark ? KinrelColors.textWhite : KinrelColors.textDark,
      iconColor: textSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
      ),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? KinrelColors.darkElevated : KinrelColors.lightElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        border: Border.all(
          color: isDark ? KinrelColors.border : KinrelColors.lightBorder,
        ),
      ),
      textStyle: KinrelTypography.bodySmall.copyWith(
        color: isDark ? KinrelColors.textWhite : KinrelColors.textDark,
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? KinrelColors.darkCard : KinrelColors.lightCard,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        side: BorderSide(
          color: isDark ? KinrelColors.border : KinrelColors.lightBorder,
        ),
      ),
      textStyle: KinrelTypography.bodyMedium.copyWith(
        color: isDark ? KinrelColors.textWhite : KinrelColors.textDark,
      ),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: isDark ? KinrelColors.darkCard : KinrelColors.lightCard,
      indicatorColor: primaryColor.withValues(alpha: 0.15),
      selectedIconTheme: IconThemeData(
        color: primaryColor,
        size: 24,
      ),
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
          ? const Color(0xCC1E1E1E) // semi-transparent dark
          : const Color(0xCCFFFFFF), // semi-transparent light
      indicatorColor: primaryColor.withValues(alpha: 0.15),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(
            color: primaryColor,
          );
        }
        return IconThemeData(
          color: isDark ? KinrelColors.textDim : KinrelColors.textSecondaryLight,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return KinrelTypography.labelSmall.copyWith(
            color: primaryColor,
          );
        }
        return KinrelTypography.labelSmall.copyWith(
          color: isDark ? KinrelColors.textDim : KinrelColors.textSecondaryLight,
        );
      }),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: primaryColor,
      inactiveTrackColor: isDark ? KinrelColors.darkElevated : KinrelColors.lightElevated,
      thumbColor: primaryColor,
      overlayColor: primaryColor.withValues(alpha: 0.12),
      trackHeight: 4,
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return (isDark ? KinrelColors.darkElevated : KinrelColors.lightElevated)
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
      shape: const RoundedRectangleBorder(
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

    // ── Page transitions ──────────────────────────────────────────
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),

    // ── Visual density ────────────────────────────────────────────
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
