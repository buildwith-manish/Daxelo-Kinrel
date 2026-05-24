// lib/core/theme/theme_provider.dart
//
// DAXELO KINREL — Theme Provider (Riverpod)
//
// Manages theme mode, font scaling, and high-contrast mode.
// Combines all three into a single [ThemeData] provider.
//
// Usage:
// ```dart
// ProviderScope(
//   child: Consumer(
//     builder: (context, ref, _) {
//       final theme = ref.watch(appThemeProvider);
//       return MaterialApp(theme: theme, ...);
//     },
//   ),
// )
// ```

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_theme.dart';

/// Current theme mode (dark, light, system).
/// Defaults to [ThemeMode.dark] per KINREL brand guidelines.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

/// Font scale factor applied on top of base text sizes.
/// 1.0 = default, 1.15 = large, 1.3 = extra-large.
final fontScaleProvider = StateProvider<double>((ref) => 1.0);

/// High-contrast mode toggle for accessibility.
/// When true, increases contrast ratios across the theme.
final highContrastProvider = StateProvider<bool>((ref) => false);

/// Computed [ThemeData] that combines theme mode, font scale,
/// and high-contrast settings into a single coherent theme.
final appThemeProvider = Provider<ThemeData>((ref) {
  final mode = ref.watch(themeModeProvider);
  final fontScale = ref.watch(fontScaleProvider);
  final highContrast = ref.watch(highContrastProvider);

  // Resolve brightness from theme mode
  final brightness = mode == ThemeMode.dark
      ? Brightness.dark
      : mode == ThemeMode.light
          ? Brightness.light
          : WidgetsBinding.instance.platformDispatcher.platformBrightness;

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
    theme = theme.copyWith(
      colorScheme: colorScheme.copyWith(
        // Boost surface contrast
        surface: brightness == Brightness.dark
            ? const Color(0xFF000000)
            : const Color(0xFFFFFFFF),
        onSurface: brightness == Brightness.dark
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000),
        onSurfaceVariant: brightness == Brightness.dark
            ? const Color(0xFFE0E0E0)
            : const Color(0xFF1A1A1A),
        outline: brightness == Brightness.dark
            ? const Color(0xFFBBBBBB)
            : const Color(0xFF444444),
      ),
      dividerTheme: theme.dividerTheme.copyWith(
        color: brightness == Brightness.dark
            ? const Color(0xFF888888)
            : const Color(0xFF666666),
      ),
    );
  }

  return theme;
});
