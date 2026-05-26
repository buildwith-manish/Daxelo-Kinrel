// lib/core/theme/app_theme.dart
//
// DAXELO KINREL — Material 3 Theme (DARK ONLY)
//
// Comprehensive Material 3 dark-only theme
// using the KINREL brand system. Includes full ColorScheme,
// component themes, and a custom ThemeExtension.
//
// Dark theme (ONLY mode — KINREL brand requirement):
//   Primary: Orange #E8612A
//   Background: #13141E
//   Card: #191B2C
//   Elevated: #202338
//   Surface: #2A2D45
//   Text primary: #F5F0EE
//   Text secondary: #C9B4A8
//   Text dim: #8A7A72
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

// ── Dark ColorScheme (ONLY) ──────────────────────────────────────────

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

// ── Text Theme ────────────────────────────────────────────────────────

TextTheme _buildTextTheme() {
  const baseColor = KinrelColors.textPrimary;
  const secondaryColor = KinrelColors.textSecondary;

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

AppBarTheme _appBarTheme() {
  return const AppBarTheme(
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 1,
    backgroundColor: Color(0xB313141E), // bg with 0.85 alpha
    foregroundColor: KinrelColors.textPrimary,
    titleTextStyle: TextStyle(
      fontFamily: KinrelTypography.displayFont,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: KinrelColors.textPrimary,
    ),
    surfaceTintColor: Colors.transparent,
  );
}

CardThemeData _cardTheme() {
  return CardThemeData(
    elevation: 0,
    color: KinrelColors.card,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.card),
      side: const BorderSide(
        color: KinrelColors.border,
        width: 1,
      ),
    ),
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
  );
}

ElevatedButtonThemeData _elevatedButtonTheme() {
  return ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: KinrelColors.orange,
      foregroundColor: Colors.white,
      disabledBackgroundColor: KinrelColors.elevated,
      disabledForegroundColor: KinrelColors.textDim,
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

OutlinedButtonThemeData _outlinedButtonTheme() {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: KinrelColors.orange,
      disabledForegroundColor: KinrelColors.textDim,
      side: BorderSide(
        color: KinrelColors.orange.withValues(alpha: 0.5),
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

TextButtonThemeData _textButtonTheme() {
  return TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: KinrelColors.orange,
      disabledForegroundColor: KinrelColors.textDim,
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

InputDecorationTheme _inputDecorationTheme() {
  final borderColor = KinrelColors.textDim.withValues(alpha: 0.3);
  final enabledBorderColor = KinrelColors.border;
  const focusedBorderColor = KinrelColors.orange;

  return InputDecorationTheme(
    filled: true,
    fillColor: KinrelColors.elevated,
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
      borderSide: const BorderSide(color: focusedBorderColor, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.input),
      borderSide: const BorderSide(color: KinrelColors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.input),
      borderSide: const BorderSide(color: KinrelColors.error, width: 2),
    ),
    hintStyle: const TextStyle(
      fontFamily: KinrelTypography.bodyFont,
      color: KinrelColors.textDim,
      fontSize: 14,
    ),
    labelStyle: const TextStyle(
      fontFamily: KinrelTypography.bodyFont,
      color: KinrelColors.textSecondary,
      fontSize: 14,
    ),
    floatingLabelStyle: const TextStyle(
      fontFamily: KinrelTypography.bodyFont,
      color: KinrelColors.orange,
      fontSize: 12,
    ),
  );
}

BottomNavigationBarThemeData _bottomNavigationBarTheme() {
  return const BottomNavigationBarThemeData(
    backgroundColor: KinrelColors.card,
    selectedItemColor: KinrelColors.orange,
    unselectedItemColor: KinrelColors.textDim,
    type: BottomNavigationBarType.fixed,
    elevation: 0,
    selectedLabelStyle: KinrelTypography.labelSmall,
    unselectedLabelStyle: KinrelTypography.labelSmall,
  );
}

TabBarThemeData _tabBarTheme() {
  return const TabBarThemeData(
    labelColor: KinrelColors.orange,
    unselectedLabelColor: KinrelColors.textDim,
    indicatorColor: KinrelColors.orange,
    indicatorSize: TabBarIndicatorSize.label,
    labelStyle: KinrelTypography.labelLarge,
    unselectedLabelStyle: KinrelTypography.labelLarge,
    dividerColor: KinrelColors.border,
  );
}

DialogThemeData _dialogTheme() {
  return DialogThemeData(
    backgroundColor: KinrelColors.card,
    elevation: 4,
    shadowColor: Colors.black26,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.dialog),
      side: const BorderSide(
        color: KinrelColors.border,
        width: 1,
      ),
    ),
    titleTextStyle: KinrelTypography.headlineSmall.copyWith(
      color: KinrelColors.textPrimary,
    ),
    contentTextStyle: KinrelTypography.bodyMedium.copyWith(
      color: KinrelColors.textSecondary,
    ),
  );
}

BottomSheetThemeData _bottomSheetTheme() {
  return const BottomSheetThemeData(
    backgroundColor: KinrelColors.card,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KinrelRadius.bottomSheet),
      ),
    ),
    showDragHandle: true,
    dragHandleColor: Color(0x4D8A7A72), // textDim with 0.3 alpha
    constraints: BoxConstraints(maxWidth: 640),
  );
}

ChipThemeData _chipTheme() {
  return ChipThemeData(
    backgroundColor: KinrelColors.elevated,
    selectedColor: KinrelColors.orange.withValues(alpha: 0.2),
    disabledColor: KinrelColors.elevated.withValues(alpha: 0.5),
    deleteIconColor: KinrelColors.textSecondary,
    labelStyle: KinrelTypography.labelMedium.copyWith(
      color: KinrelColors.textPrimary,
    ),
    secondaryLabelStyle: KinrelTypography.labelMedium.copyWith(
      color: KinrelColors.orange,
    ),
    side: const BorderSide(
      color: KinrelColors.border,
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

FloatingActionButtonThemeData _fabTheme() {
  return const FloatingActionButtonThemeData(
    backgroundColor: KinrelColors.orange,
    foregroundColor: Colors.white,
    disabledElevation: 0,
    elevation: 2,
    highlightElevation: 4,
    shape: CircleBorder(),
    extendedTextStyle: KinrelTypography.labelLarge,
  );
}

SnackBarThemeData _snackbarTheme() {
  return SnackBarThemeData(
    backgroundColor: KinrelColors.elevated,
    contentTextStyle: KinrelTypography.bodyMedium.copyWith(
      color: KinrelColors.textPrimary,
    ),
    actionTextColor: KinrelColors.amber,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(KinrelRadius.sm),
    ),
    behavior: SnackBarBehavior.floating,
    elevation: 2,
  );
}

DividerThemeData _dividerTheme() {
  return const DividerThemeData(
    color: KinrelColors.border,
    thickness: 1,
    space: 1,
  );
}

SwitchThemeData _switchTheme() {
  return SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return KinrelColors.textDim.withValues(alpha: 0.5);
      }
      if (states.contains(WidgetState.selected)) {
        return Colors.white;
      }
      return KinrelColors.textSecondary;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return KinrelColors.elevated.withValues(alpha: 0.5);
      }
      if (states.contains(WidgetState.selected)) {
        return KinrelColors.orange;
      }
      return KinrelColors.surface;
    }),
    trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
  );
}

ProgressIndicatorThemeData _progressBarTheme() {
  return ProgressIndicatorThemeData(
    color: KinrelColors.orange,
    linearTrackColor: KinrelColors.elevated,
    circularTrackColor: KinrelColors.elevated,
    linearMinHeight: 4,
    borderRadius: BorderRadius.circular(2),
  );
}

// ── Brand Theme Extension Builder ────────────────────────────────────

KinrelThemeExtension _darkExtension() {
  return const KinrelThemeExtension(
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

// ── Main Theme Builder ────────────────────────────────────────────────

/// Returns a complete dark [ThemeData].
/// KINREL brand requires dark mode only — light theme is not supported.
ThemeData getAppTheme(Brightness brightness) {
  // Always use dark theme regardless of the brightness parameter
  final colorScheme = _darkColorScheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,

    // ── Typography ────────────────────────────────────────────────
    textTheme: _buildTextTheme(),
    primaryTextTheme: _buildTextTheme(),

    // ── Component Themes ──────────────────────────────────────────
    appBarTheme: _appBarTheme(),
    cardTheme: _cardTheme(),
    elevatedButtonTheme: _elevatedButtonTheme(),
    outlinedButtonTheme: _outlinedButtonTheme(),
    textButtonTheme: _textButtonTheme(),
    inputDecorationTheme: _inputDecorationTheme(),
    bottomNavigationBarTheme: _bottomNavigationBarTheme(),
    tabBarTheme: _tabBarTheme(),
    dialogTheme: _dialogTheme(),
    bottomSheetTheme: _bottomSheetTheme(),
    chipTheme: _chipTheme(),
    floatingActionButtonTheme: _fabTheme(),
    snackBarTheme: _snackbarTheme(),
    dividerTheme: _dividerTheme(),
    switchTheme: _switchTheme(),
    progressIndicatorTheme: _progressBarTheme(),

    // ── Additional Component Themes ───────────────────────────────
    iconTheme: const IconThemeData(
      color: KinrelColors.textSecondary,
      size: 24,
    ),
    primaryIconTheme: const IconThemeData(
      color: KinrelColors.orange,
      size: 24,
    ),

    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.lg,
        vertical: KinrelSpacing.xs,
      ),
      textColor: KinrelColors.textPrimary,
      iconColor: KinrelColors.textSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
      ),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: KinrelColors.elevated,
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        border: Border.all(
          color: KinrelColors.border,
        ),
      ),
      textStyle: KinrelTypography.bodySmall.copyWith(
        color: KinrelColors.textPrimary,
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: KinrelColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        side: const BorderSide(
          color: KinrelColors.border,
        ),
      ),
      textStyle: KinrelTypography.bodyMedium.copyWith(
        color: KinrelColors.textPrimary,
      ),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: KinrelColors.card,
      indicatorColor: const Color(0x26E8612A), // orange with 0.15 alpha
      selectedIconTheme: const IconThemeData(
        color: KinrelColors.orange,
        size: 24,
      ),
      unselectedIconTheme: const IconThemeData(
        color: KinrelColors.textDim,
        size: 24,
      ),
      selectedLabelTextStyle: KinrelTypography.labelSmall.copyWith(
        color: KinrelColors.orange,
      ),
      unselectedLabelTextStyle: KinrelTypography.labelSmall.copyWith(
        color: KinrelColors.textDim,
      ),
      elevation: 0,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: KinrelColors.card,
      indicatorColor: KinrelColors.orange.withValues(alpha: 0.15),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(
            color: KinrelColors.orange,
          );
        }
        return const IconThemeData(
          color: KinrelColors.textDim,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return KinrelTypography.labelSmall.copyWith(
            color: KinrelColors.orange,
          );
        }
        return KinrelTypography.labelSmall.copyWith(
          color: KinrelColors.textDim,
        );
      }),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),

    sliderTheme: const SliderThemeData(
      activeTrackColor: KinrelColors.orange,
      inactiveTrackColor: KinrelColors.elevated,
      thumbColor: KinrelColors.orange,
      overlayColor: Color(0x1EE8612A), // orange with 0.12 alpha
      trackHeight: 4,
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return KinrelColors.elevated.withValues(alpha: 0.5);
        }
        if (states.contains(WidgetState.selected)) {
          return KinrelColors.orange;
        }
        return Colors.transparent;
      }),
      side: BorderSide(
        color: KinrelColors.textDim.withValues(alpha: 0.5),
        width: 2,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.xs),
      ),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return KinrelColors.orange;
        }
        return KinrelColors.textDim;
      }),
    ),

    // ── Extensions ────────────────────────────────────────────────
    extensions: <ThemeExtension<dynamic>>[
      _darkExtension(),
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
