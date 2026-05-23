// lib/core/theme/app_theme.dart
//
// DAXELO KINREL — Material 3 Theme
//
// Comprehensive Material 3 theme for both dark and light modes
// using the KINREL brand system. Includes full ColorScheme,
// component themes, and a custom ThemeExtension.
//
// Dark theme (default):
//   Primary: Orange #E8612A
//   Background: #13141E
//   Card: #191B2C
//   Elevated: #202338
//   Surface: #2A2D45
//   Text primary: #F5F0EE
//   Text secondary: #C9B4A8
//   Text dim: #8A7A72
//
// Light theme:
//   Primary: Ember #C44A18
//   Background: #FFFAF8
//   Card: #FFFFFF
//   Text primary: #1A0A00
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
  final Color brandOrange;
  final Color brandAmber;
  final Color brandEmber;
  final Color brandGlow;
  final Color brandTextPrimary;
  final Color brandTextSecondary;
  final Color brandTextDim;
  final Color brandCardBg;
  final Color brandElevatedBg;
  final Color brandBorder;
  final Gradient brandIgniteGradient;
  final Gradient brandHeritageGradient;
  final Gradient brandWordmarkGradient;
  final double brandCardRadius;
  final double brandButtonRadius;
  final double brandInputRadius;

  const KinrelThemeExtension({
    required this.brandOrange,
    required this.brandAmber,
    required this.brandEmber,
    required this.brandGlow,
    required this.brandTextPrimary,
    required this.brandTextSecondary,
    required this.brandTextDim,
    required this.brandCardBg,
    required this.brandElevatedBg,
    required this.brandBorder,
    required this.brandIgniteGradient,
    required this.brandHeritageGradient,
    required this.brandWordmarkGradient,
    required this.brandCardRadius,
    required this.brandButtonRadius,
    required this.brandInputRadius,
  });

  @override
  KinrelThemeExtension copyWith({
    Color? brandOrange,
    Color? brandAmber,
    Color? brandEmber,
    Color? brandGlow,
    Color? brandTextPrimary,
    Color? brandTextSecondary,
    Color? brandTextDim,
    Color? brandCardBg,
    Color? brandElevatedBg,
    Color? brandBorder,
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
      brandTextPrimary: brandTextPrimary ?? this.brandTextPrimary,
      brandTextSecondary: brandTextSecondary ?? this.brandTextSecondary,
      brandTextDim: brandTextDim ?? this.brandTextDim,
      brandCardBg: brandCardBg ?? this.brandCardBg,
      brandElevatedBg: brandElevatedBg ?? this.brandElevatedBg,
      brandBorder: brandBorder ?? this.brandBorder,
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
      brandTextPrimary:
          Color.lerp(brandTextPrimary, other.brandTextPrimary, t)!,
      brandTextSecondary:
          Color.lerp(brandTextSecondary, other.brandTextSecondary, t)!,
      brandTextDim: Color.lerp(brandTextDim, other.brandTextDim, t)!,
      brandCardBg: Color.lerp(brandCardBg, other.brandCardBg, t)!,
      brandElevatedBg: Color.lerp(brandElevatedBg, other.brandElevatedBg, t)!,
      brandBorder: Color.lerp(brandBorder, other.brandBorder, t)!,
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
    primary: KinrelColors.orange,
    onPrimary: Color(0xFF1C1917),
    primaryContainer: Color(0xFF431407),
    onPrimaryContainer: KinrelColors.amber,
    secondary: KinrelColors.accent,
    onSecondary: Color(0xFF1C1917),
    secondaryContainer: Color(0xFF134E4A),
    onSecondaryContainer: KinrelColors.accentLight,
    tertiary: KinrelColors.amber,
    onTertiary: Color(0xFF1C1917),
    tertiaryContainer: Color(0xFF431407),
    onTertiaryContainer: KinrelColors.amber,
    error: KinrelColors.error,
    onError: Colors.white,
    errorContainer: Color(0xFF5C1A0A),
    onErrorContainer: Color(0xFFF87171),
    surface: KinrelColors.bg,
    onSurface: KinrelColors.textPrimary,
    surfaceContainerLowest: Color(0xFF0E0F18),
    surfaceContainerLow: KinrelColors.card,
    surfaceContainer: KinrelColors.elevated,
    surfaceContainerHigh: KinrelColors.surface,
    surfaceContainerHighest: Color(0xFF34375A),
    onSurfaceVariant: KinrelColors.textSecondary,
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
    primary: KinrelColors.ember,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFFF7ED),
    onPrimaryContainer: Color(0xFF7C2D12),
    secondary: KinrelColors.accentDark,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFCCFBF1),
    onSecondaryContainer: Color(0xFF134E4A),
    tertiary: KinrelColors.orange,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFFFF7ED),
    onTertiaryContainer: Color(0xFF7C2D12),
    error: Color(0xFFEF4444),
    onError: Colors.white,
    errorContainer: Color(0xFFFFE0E6),
    onErrorContainer: Color(0xFF5C1A0A),
    surface: KinrelColors.lightBg,
    onSurface: KinrelColors.lightTextPrimary,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFFFFBFE),
    surfaceContainer: KinrelColors.lightCard,
    surfaceContainerHigh: KinrelColors.lightElevated,
    surfaceContainerHighest: Color(0xFFF0E8E2),
    onSurfaceVariant: KinrelColors.lightTextSecondary,
    outline: Color(0xFFA8A29E),
    outlineVariant: Color(0xFFD6D3D1),
    inverseSurface: Color(0xFF292524),
    onInverseSurface: Color(0xFFF5F5F4),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );
}

// ── Text Theme ────────────────────────────────────────────────────────

TextTheme _buildTextTheme(Brightness brightness) {
  final baseColor =
      brightness == Brightness.dark
          ? KinrelColors.textPrimary
          : KinrelColors.lightTextPrimary;
  final secondaryColor =
      brightness == Brightness.dark
          ? KinrelColors.textSecondary
          : KinrelColors.lightTextSecondary;

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
  return AppBarTheme(
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 1,
    backgroundColor:
        brightness == Brightness.dark
            ? KinrelColors.bg.withValues(alpha: 0.85)
            : KinrelColors.lightBg.withValues(alpha: 0.85),
    foregroundColor:
        brightness == Brightness.dark
            ? KinrelColors.textPrimary
            : KinrelColors.lightTextPrimary,
    titleTextStyle: KinrelTypography.titleLarge.copyWith(
      color:
          brightness == Brightness.dark
              ? KinrelColors.textPrimary
              : KinrelColors.lightTextPrimary,
    ),
    surfaceTintColor: Colors.transparent,
  );
}

CardThemeData _cardTheme(Brightness brightness) {
  return CardThemeData(
    elevation: 0,
    color:
        brightness == Brightness.dark ? KinrelColors.card : Colors.white,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.card),
      side: BorderSide(
        color:
            brightness == Brightness.dark
                ? KinrelColors.border
                : KinrelColors.lightBorder,
        width: 1,
      ),
    ),
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
  );
}

ElevatedButtonThemeData _elevatedButtonTheme(Brightness brightness) {
  return ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor:
          brightness == Brightness.dark
              ? KinrelColors.orange
              : KinrelColors.ember,
      foregroundColor:
          brightness == Brightness.dark ? Colors.white : Colors.white,
      disabledBackgroundColor:
          brightness == Brightness.dark
              ? KinrelColors.elevated
              : KinrelColors.lightElevated,
      disabledForegroundColor:
          brightness == Brightness.dark
              ? KinrelColors.textDim
              : KinrelColors.lightTextDim,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.xl,
        vertical: KinrelSpacing.md,
      ),
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.button),
      ),
      textStyle: KinrelTypography.labelLarge,
    ),
  );
}

OutlinedButtonThemeData _outlinedButtonTheme(Brightness brightness) {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor:
          brightness == Brightness.dark
              ? KinrelColors.orange
              : KinrelColors.ember,
      disabledForegroundColor:
          brightness == Brightness.dark
              ? KinrelColors.textDim
              : KinrelColors.lightTextDim,
      side: BorderSide(
        color:
            brightness == Brightness.dark
                ? KinrelColors.orange.withValues(alpha: 0.5)
                : KinrelColors.ember.withValues(alpha: 0.5),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.xl,
        vertical: KinrelSpacing.md,
      ),
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.button),
      ),
      textStyle: KinrelTypography.labelLarge,
    ),
  );
}

TextButtonThemeData _textButtonTheme(Brightness brightness) {
  return TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor:
          brightness == Brightness.dark
              ? KinrelColors.orange
              : KinrelColors.ember,
      disabledForegroundColor:
          brightness == Brightness.dark
              ? KinrelColors.textDim
              : KinrelColors.lightTextDim,
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.lg,
        vertical: KinrelSpacing.sm,
      ),
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.button),
      ),
      textStyle: KinrelTypography.labelLarge,
    ),
  );
}

InputDecorationTheme _inputDecorationTheme(Brightness brightness) {
  final borderColor =
      brightness == Brightness.dark
          ? KinrelColors.textDim.withValues(alpha: 0.3)
          : KinrelColors.lightTextDim.withValues(alpha: 0.3);
  final enabledBorderColor =
      brightness == Brightness.dark
          ? KinrelColors.border
          : KinrelColors.lightBorder;
  final focusedBorderColor =
      brightness == Brightness.dark ? KinrelColors.orange : KinrelColors.ember;

  return InputDecorationTheme(
    filled: true,
    fillColor:
        brightness == Brightness.dark
            ? KinrelColors.elevated
            : KinrelColors.lightElevated,
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
      borderSide: BorderSide(color: focusedBorderColor, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.input),
      borderSide: const BorderSide(color: KinrelColors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.input),
      borderSide: const BorderSide(color: KinrelColors.error, width: 2),
    ),
    hintStyle: TextStyle(
      fontFamily: KinrelTypography.bodyFont,
      color:
          brightness == Brightness.dark
              ? KinrelColors.textDim
              : KinrelColors.lightTextDim,
      fontSize: 14,
    ),
    labelStyle: TextStyle(
      fontFamily: KinrelTypography.bodyFont,
      color:
          brightness == Brightness.dark
              ? KinrelColors.textSecondary
              : KinrelColors.lightTextSecondary,
      fontSize: 14,
    ),
    floatingLabelStyle: TextStyle(
      fontFamily: KinrelTypography.bodyFont,
      color:
          brightness == Brightness.dark ? KinrelColors.orange : KinrelColors.ember,
      fontSize: 12,
    ),
  );
}

BottomNavigationBarThemeData _bottomNavigationBarTheme(Brightness brightness) {
  return BottomNavigationBarThemeData(
    backgroundColor:
        brightness == Brightness.dark ? KinrelColors.card : Colors.white,
    selectedItemColor:
        brightness == Brightness.dark ? KinrelColors.orange : KinrelColors.ember,
    unselectedItemColor:
        brightness == Brightness.dark
            ? KinrelColors.textDim
            : KinrelColors.lightTextDim,
    type: BottomNavigationBarType.fixed,
    elevation: 0,
    selectedLabelStyle: KinrelTypography.labelSmall,
    unselectedLabelStyle: KinrelTypography.labelSmall,
  );
}

TabBarThemeData _tabBarTheme(Brightness brightness) {
  return TabBarThemeData(
    labelColor:
        brightness == Brightness.dark ? KinrelColors.orange : KinrelColors.ember,
    unselectedLabelColor:
        brightness == Brightness.dark
            ? KinrelColors.textDim
            : KinrelColors.lightTextDim,
    indicatorColor:
        brightness == Brightness.dark ? KinrelColors.orange : KinrelColors.ember,
    indicatorSize: TabBarIndicatorSize.label,
    labelStyle: KinrelTypography.labelLarge,
    unselectedLabelStyle: KinrelTypography.labelLarge,
    dividerColor:
        brightness == Brightness.dark
            ? KinrelColors.border
            : KinrelColors.lightBorder,
  );
}

DialogThemeData _dialogTheme(Brightness brightness) {
  return DialogThemeData(
    backgroundColor:
        brightness == Brightness.dark ? KinrelColors.card : Colors.white,
    elevation: 4,
    shadowColor: Colors.black26,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.dialog),
      side: BorderSide(
        color:
            brightness == Brightness.dark
                ? KinrelColors.border
                : KinrelColors.lightBorder,
        width: 1,
      ),
    ),
    titleTextStyle: KinrelTypography.headlineSmall.copyWith(
      color:
          brightness == Brightness.dark
              ? KinrelColors.textPrimary
              : KinrelColors.lightTextPrimary,
    ),
    contentTextStyle: KinrelTypography.bodyMedium.copyWith(
      color:
          brightness == Brightness.dark
              ? KinrelColors.textSecondary
              : KinrelColors.lightTextSecondary,
    ),
  );
}

BottomSheetThemeData _bottomSheetTheme(Brightness brightness) {
  return BottomSheetThemeData(
    backgroundColor:
        brightness == Brightness.dark ? KinrelColors.card : Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KinrelRadius.bottomSheet),
      ),
    ),
    showDragHandle: true,
    dragHandleColor:
        brightness == Brightness.dark
            ? KinrelColors.textDim.withValues(alpha: 0.3)
            : KinrelColors.lightTextDim.withValues(alpha: 0.3),
    constraints: const BoxConstraints(maxWidth: 640),
  );
}

ChipThemeData _chipTheme(Brightness brightness) {
  return ChipThemeData(
    backgroundColor:
        brightness == Brightness.dark ? KinrelColors.elevated : KinrelColors.lightElevated,
    selectedColor:
        brightness == Brightness.dark
            ? KinrelColors.orange.withValues(alpha: 0.2)
            : KinrelColors.ember.withValues(alpha: 0.15),
    disabledColor:
        brightness == Brightness.dark
            ? KinrelColors.elevated.withValues(alpha: 0.5)
            : KinrelColors.lightElevated.withValues(alpha: 0.5),
    deleteIconColor:
        brightness == Brightness.dark
            ? KinrelColors.textSecondary
            : KinrelColors.lightTextSecondary,
    labelStyle: KinrelTypography.labelMedium.copyWith(
      color:
          brightness == Brightness.dark
              ? KinrelColors.textPrimary
              : KinrelColors.lightTextPrimary,
    ),
    secondaryLabelStyle: KinrelTypography.labelMedium.copyWith(
      color:
          brightness == Brightness.dark ? KinrelColors.orange : KinrelColors.ember,
    ),
    side: BorderSide(
      color:
          brightness == Brightness.dark
              ? KinrelColors.border
              : KinrelColors.lightBorder,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.chip),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: KinrelSpacing.md,
      vertical: KinrelSpacing.xs,
    ),
  );
}

FloatingActionButtonThemeData _fabTheme(Brightness brightness) {
  return FloatingActionButtonThemeData(
    backgroundColor:
        brightness == Brightness.dark ? KinrelColors.orange : KinrelColors.ember,
    foregroundColor: Colors.white,
    disabledElevation: 0,
    elevation: 2,
    highlightElevation: 4,
    shape: const CircleBorder(),
    extendedTextStyle: KinrelTypography.labelLarge,
  );
}

SnackBarThemeData _snackbarTheme(Brightness brightness) {
  return SnackBarThemeData(
    backgroundColor:
        brightness == Brightness.dark ? KinrelColors.elevated : KinrelColors.lightElevated,
    contentTextStyle: KinrelTypography.bodyMedium.copyWith(
      color:
          brightness == Brightness.dark
              ? KinrelColors.textPrimary
              : KinrelColors.lightTextPrimary,
    ),
    actionTextColor:
        brightness == Brightness.dark ? KinrelColors.amber : KinrelColors.orange,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.sm),
    ),
    behavior: SnackBarBehavior.floating,
    elevation: 2,
  );
}

DividerThemeData _dividerTheme(Brightness brightness) {
  return DividerThemeData(
    color:
        brightness == Brightness.dark
            ? KinrelColors.border
            : KinrelColors.lightBorder,
    thickness: 1,
    space: 1,
  );
}

SwitchThemeData _switchTheme(Brightness brightness) {
  return SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return (brightness == Brightness.dark ? KinrelColors.textDim : KinrelColors.lightTextDim)
            .withValues(alpha: 0.5);
      }
      if (states.contains(WidgetState.selected)) {
        return Colors.white;
      }
      return brightness == Brightness.dark
          ? KinrelColors.textSecondary
          : KinrelColors.lightTextSecondary;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return (brightness == Brightness.dark ? KinrelColors.elevated : KinrelColors.lightElevated)
            .withValues(alpha: 0.5);
      }
      if (states.contains(WidgetState.selected)) {
        return brightness == Brightness.dark
            ? KinrelColors.orange
            : KinrelColors.ember;
      }
      return brightness == Brightness.dark
          ? KinrelColors.surface
          : KinrelColors.lightElevated;
    }),
    trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
  );
}

ProgressIndicatorThemeData _progressBarTheme(Brightness brightness) {
  return ProgressIndicatorThemeData(
    color:
        brightness == Brightness.dark ? KinrelColors.orange : KinrelColors.ember,
    linearTrackColor:
        brightness == Brightness.dark ? KinrelColors.elevated : KinrelColors.lightElevated,
    circularTrackColor:
        brightness == Brightness.dark ? KinrelColors.elevated : KinrelColors.lightElevated,
    linearMinHeight: 4,
    borderRadius: BorderRadius.circular(2),
  );
}

// ── Brand Theme Extension Builders ────────────────────────────────────

KinrelThemeExtension _darkExtension() {
  return KinrelThemeExtension(
    brandOrange: KinrelColors.orange,
    brandAmber: KinrelColors.amber,
    brandEmber: KinrelColors.ember,
    brandGlow: KinrelColors.orangeGlow,
    brandTextPrimary: KinrelColors.textPrimary,
    brandTextSecondary: KinrelColors.textSecondary,
    brandTextDim: KinrelColors.textDim,
    brandCardBg: KinrelColors.card,
    brandElevatedBg: KinrelColors.elevated,
    brandBorder: KinrelColors.border,
    brandIgniteGradient: KinrelGradients.ignite,
    brandHeritageGradient: KinrelGradients.heritage,
    brandWordmarkGradient: KinrelGradients.wordmarkGradient,
    brandCardRadius: KinrelRadius.card,
    brandButtonRadius: KinrelRadius.button,
    brandInputRadius: KinrelRadius.input,
  );
}

KinrelThemeExtension _lightExtension() {
  return KinrelThemeExtension(
    brandOrange: KinrelColors.ember,
    brandAmber: KinrelColors.orange,
    brandEmber: KinrelColors.ember,
    brandGlow: KinrelColors.orangeGlow,
    brandTextPrimary: KinrelColors.lightTextPrimary,
    brandTextSecondary: KinrelColors.lightTextSecondary,
    brandTextDim: KinrelColors.lightTextDim,
    brandCardBg: Colors.white,
    brandElevatedBg: KinrelColors.lightElevated,
    brandBorder: KinrelColors.lightBorder,
    brandIgniteGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [KinrelColors.ember, KinrelColors.orange],
    ),
    brandHeritageGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [KinrelColors.ember, Color(0xFF8B3410)],
    ),
    brandWordmarkGradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [KinrelColors.lightTextPrimary, KinrelColors.ember],
    ),
    brandCardRadius: KinrelRadius.card,
    brandButtonRadius: KinrelRadius.button,
    brandInputRadius: KinrelRadius.input,
  );
}

// ── Main Theme Builder ────────────────────────────────────────────────

/// Returns a complete [ThemeData] for the given [brightness].
///
/// Usage:
/// ```dart
/// MaterialApp(
///   theme: getAppTheme(Brightness.light),
///   darkTheme: getAppTheme(Brightness.dark),
///   themeMode: ThemeMode.dark,
/// )
/// ```
ThemeData getAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final colorScheme =
      isDark ? _darkColorScheme() : _lightColorScheme();

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
      color: isDark ? KinrelColors.textSecondary : KinrelColors.lightTextSecondary,
      size: 24,
    ),
    primaryIconTheme: IconThemeData(
      color: isDark ? KinrelColors.orange : KinrelColors.ember,
      size: 24,
    ),

    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.lg,
        vertical: KinrelSpacing.xs,
      ),
      textColor: isDark ? KinrelColors.textPrimary : KinrelColors.lightTextPrimary,
      iconColor: isDark ? KinrelColors.textSecondary : KinrelColors.lightTextSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
      ),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? KinrelColors.elevated : KinrelColors.lightElevated,
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        border: Border.all(
          color: isDark ? KinrelColors.border : KinrelColors.lightBorder,
        ),
      ),
      textStyle: KinrelTypography.bodySmall.copyWith(
        color: isDark ? KinrelColors.textPrimary : KinrelColors.lightTextPrimary,
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? KinrelColors.card : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        side: BorderSide(
          color: isDark ? KinrelColors.border : KinrelColors.lightBorder,
        ),
      ),
      textStyle: KinrelTypography.bodyMedium.copyWith(
        color: isDark ? KinrelColors.textPrimary : KinrelColors.lightTextPrimary,
      ),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: isDark ? KinrelColors.card : Colors.white,
      indicatorColor:
          isDark ? KinrelColors.orange.withValues(alpha: 0.15) : KinrelColors.ember.withValues(alpha: 0.12),
      selectedIconTheme: IconThemeData(
        color: isDark ? KinrelColors.orange : KinrelColors.ember,
        size: 24,
      ),
      unselectedIconTheme: IconThemeData(
        color: isDark ? KinrelColors.textDim : KinrelColors.lightTextDim,
        size: 24,
      ),
      selectedLabelTextStyle: KinrelTypography.labelSmall.copyWith(
        color: isDark ? KinrelColors.orange : KinrelColors.ember,
      ),
      unselectedLabelTextStyle: KinrelTypography.labelSmall.copyWith(
        color: isDark ? KinrelColors.textDim : KinrelColors.lightTextDim,
      ),
      elevation: 0,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? KinrelColors.card : Colors.white,
      indicatorColor:
          isDark ? KinrelColors.orange.withValues(alpha: 0.15) : KinrelColors.ember.withValues(alpha: 0.12),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(
            color: isDark ? KinrelColors.orange : KinrelColors.ember,
          );
        }
        return IconThemeData(
          color: isDark ? KinrelColors.textDim : KinrelColors.lightTextDim,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return KinrelTypography.labelSmall.copyWith(
            color: isDark ? KinrelColors.orange : KinrelColors.ember,
          );
        }
        return KinrelTypography.labelSmall.copyWith(
          color: isDark ? KinrelColors.textDim : KinrelColors.lightTextDim,
        );
      }),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: isDark ? KinrelColors.orange : KinrelColors.ember,
      inactiveTrackColor:
          isDark ? KinrelColors.elevated : KinrelColors.lightElevated,
      thumbColor: isDark ? KinrelColors.orange : KinrelColors.ember,
      overlayColor:
          (isDark ? KinrelColors.orange : KinrelColors.ember)
              .withValues(alpha: 0.12),
      trackHeight: 4,
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return (isDark ? KinrelColors.elevated : KinrelColors.lightElevated)
              .withValues(alpha: 0.5);
        }
        if (states.contains(WidgetState.selected)) {
          return isDark ? KinrelColors.orange : KinrelColors.ember;
        }
        return Colors.transparent;
      }),
      side: BorderSide(
        color: isDark
            ? KinrelColors.textDim.withValues(alpha: 0.5)
            : KinrelColors.lightTextDim.withValues(alpha: 0.5),
        width: 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.xs),
      ),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return isDark ? KinrelColors.orange : KinrelColors.ember;
        }
        return isDark ? KinrelColors.textDim : KinrelColors.lightTextDim;
      }),
    ),

    // ── Extensions ────────────────────────────────────────────────
    extensions: <ThemeExtension<dynamic>>[
      isDark ? _darkExtension() : _lightExtension(),
    ],

    // ── Page transitions ──────────────────────────────────────────
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        TargetPlatform.android: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
      },
    ),

    // ── Visual density ────────────────────────────────────────────
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
