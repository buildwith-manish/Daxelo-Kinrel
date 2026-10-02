// lib/core/theme/theme_provider.dart
//
// DAXELO KINREL — Theme Provider (Riverpod)
//
// Manages theme mode (light/dark), font scaling, and high-contrast mode.
// Supports both light and dark themes per stitch.zip design reference.
//
// Usage:
// ```dart
// ProviderScope(
//   child: Consumer(
//     builder: (context, ref, _) {
//       final themeMode = ref.watch(themeModeProvider);
//       final theme = ref.watch(appThemeProvider);
//       return MaterialApp(themeMode: themeMode, theme: light, darkTheme: dark, ...);
//     },
//   ),
// )
// ```

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_theme.dart';
import '../utils/device_tier.dart';

/// Theme mode toggle: light, dark, or system.
/// Defaults to dark mode for backward compatibility.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

/// Locale provider — reads saved language preference from SecureStorage.
/// Defaults to system locale (null).
final localeProvider = StateProvider<Locale?>((ref) => null);

/// Font scale factor applied on top of base text sizes.
/// 1.0 = default, 1.15 = large, 1.3 = extra-large.
///
/// v3 (Tier 3 accessibility): This provider now defaults to the SYSTEM
/// text scale (MediaQuery.textScaler) instead of a hardcoded 1.0. This
/// means users who have "Large text" enabled in their OS settings will
/// see larger text in the app automatically — critical for older users
/// (the core Indian-family-app demographic).
///
/// Grandparent Mode overrides this with an even larger scale (1.3).
/// Users can also override it manually from Settings > Accessibility.
final fontScaleProvider = StateProvider<double>((ref) => 1.0);

/// Returns the effective font scale, respecting:
///   1. The user's in-app override (fontScaleProvider) if set
///   2. The system text scale (from MediaQuery)
///   3. Grandparent Mode (forces 1.3 minimum)
///
/// Use this in MediaQuery overrides to ensure text scales correctly
/// across the app. Call from a widget that has BuildContext (reads
/// MediaQuery).
double effectiveFontScale(BuildContext context, WidgetRef ref, {bool grandparentMode = false}) {
  final inAppScale = ref.watch(fontScaleProvider);
  final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
  // Grandparent Mode forces a minimum 1.3× scale for readability.
  if (grandparentMode) return math.max(1.3, inAppScale);
  // If the user set an in-app override, use it.
  if (inAppScale != 1.0) return inAppScale;
  // Otherwise, respect the system text scale.
  return systemScale;
}

/// High-contrast mode toggle for accessibility.
/// When true, increases contrast ratios across the theme.
final highContrastProvider = StateProvider<bool>((ref) => false);

/// Computed [ThemeData] that respects the current theme mode
/// with font scale and high-contrast settings.
final appThemeProvider = Provider<ThemeData>((ref) {
  final themeMode = ref.watch(themeModeProvider);
  final fontScale = ref.watch(fontScaleProvider);
  final highContrast = ref.watch(highContrastProvider);

  // Determine brightness from theme mode
  final Brightness brightness;
  switch (themeMode) {
    case ThemeMode.light:
      brightness = Brightness.light;
    case ThemeMode.dark:
      brightness = Brightness.dark;
    case ThemeMode.system:
      // For system mode, default to dark since we can't access
      // platform brightness in a provider. MaterialApp will handle
      // the actual system brightness resolution.
      brightness = Brightness.dark;
  }

  final tier = ref.watch(deviceTierProvider);
  var theme = getAppTheme(brightness, deviceTier: tier);

  // Apply font scaling
  if (fontScale != 1.0) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontSizeFactor: fontScale),
      primaryTextTheme: theme.primaryTextTheme.apply(fontSizeFactor: fontScale),
    );
  }

  // Apply high-contrast adjustments
  if (highContrast) {
    final colorScheme = theme.colorScheme;
    final isDark = brightness == Brightness.dark;
    theme = theme.copyWith(
      colorScheme: colorScheme.copyWith(
        surface: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        onSurface: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
        onSurfaceVariant: isDark
            ? const Color(0xFFE0E0E0)
            : const Color(0xFF1A1A1A),
        outline: isDark ? const Color(0xFFBBBBBB) : const Color(0xFF444444),
      ),
      dividerTheme: theme.dividerTheme.copyWith(
        color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
      ),
    );
  }

  return theme;
});

/// Light theme only — used for MaterialApp.theme parameter
final lightThemeProvider = Provider<ThemeData>((ref) {
  final fontScale = ref.watch(fontScaleProvider);
  final tier = ref.watch(deviceTierProvider);
  var theme = getAppTheme(Brightness.light, deviceTier: tier);

  if (fontScale != 1.0) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontSizeFactor: fontScale),
      primaryTextTheme: theme.primaryTextTheme.apply(fontSizeFactor: fontScale),
    );
  }

  return theme;
});

/// Dark theme only — used for MaterialApp.darkTheme parameter
final darkThemeProvider = Provider<ThemeData>((ref) {
  final fontScale = ref.watch(fontScaleProvider);
  final highContrast = ref.watch(highContrastProvider);
  final tier = ref.watch(deviceTierProvider);

  var theme = getAppTheme(Brightness.dark, deviceTier: tier);

  if (fontScale != 1.0) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontSizeFactor: fontScale),
      primaryTextTheme: theme.primaryTextTheme.apply(fontSizeFactor: fontScale),
    );
  }

  if (highContrast) {
    final colorScheme = theme.colorScheme;
    theme = theme.copyWith(
      colorScheme: colorScheme.copyWith(
        surface: const Color(0xFF000000),
        onSurface: const Color(0xFFFFFFFF),
        onSurfaceVariant: const Color(0xFFE0E0E0),
        outline: const Color(0xFFBBBBBB),
      ),
      dividerTheme: theme.dividerTheme.copyWith(color: const Color(0xFF888888)),
    );
  }

  return theme;
});
