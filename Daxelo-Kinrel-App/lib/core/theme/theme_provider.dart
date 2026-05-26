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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_theme.dart';

/// Theme mode toggle: light, dark, or system.
/// Defaults to dark mode for backward compatibility.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

/// Font scale factor applied on top of base text sizes.
/// 1.0 = default, 1.15 = large, 1.3 = extra-large.
final fontScaleProvider = StateProvider<double>((ref) => 1.0);

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

  var theme = getAppTheme(brightness);

  // Apply font scaling
  if (fontScale != 1.0) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontSizeFactor: fontScale),
      primaryTextTheme:
          theme.primaryTextTheme.apply(fontSizeFactor: fontScale),
    );
  }

  // Apply high-contrast adjustments
  if (highContrast) {
    final colorScheme = theme.colorScheme;
    final isDark = brightness == Brightness.dark;
    theme = theme.copyWith(
      colorScheme: colorScheme.copyWith(
        surface: isDark ? Color(0xFF000000) : Color(0xFFFFFFFF),
        onSurface: isDark ? Color(0xFFFFFFFF) : Color(0xFF000000),
        onSurfaceVariant: isDark
            ? const Color(0xFFE0E0E0)
            : const Color(0xFF1A1A1A),
        outline: isDark
            ? const Color(0xFFBBBBBB)
            : const Color(0xFF444444),
      ),
      dividerTheme: theme.dividerTheme.copyWith(
        color: isDark ? Color(0xFF888888) : Color(0xFF666666),
      ),
    );
  }

  return theme;
});

/// Light theme only — used for MaterialApp.theme parameter
final lightThemeProvider = Provider<ThemeData>((ref) {
  final fontScale = ref.watch(fontScaleProvider);
  var theme = getAppTheme(Brightness.light);

  if (fontScale != 1.0) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontSizeFactor: fontScale),
      primaryTextTheme:
          theme.primaryTextTheme.apply(fontSizeFactor: fontScale),
    );
  }

  return theme;
});

/// Dark theme only — used for MaterialApp.darkTheme parameter
final darkThemeProvider = Provider<ThemeData>((ref) {
  final fontScale = ref.watch(fontScaleProvider);
  final highContrast = ref.watch(highContrastProvider);

  var theme = getAppTheme(Brightness.dark);

  if (fontScale != 1.0) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontSizeFactor: fontScale),
      primaryTextTheme:
          theme.primaryTextTheme.apply(fontSizeFactor: fontScale),
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
      dividerTheme: theme.dividerTheme.copyWith(
        color: Color(0xFF888888),
      ),
    );
  }

  return theme;
});
