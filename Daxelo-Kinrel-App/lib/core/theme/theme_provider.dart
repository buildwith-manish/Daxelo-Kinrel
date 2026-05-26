// lib/core/theme/theme_provider.dart
//
// DAXELO KINREL — Theme Provider (Riverpod)
//
// Manages font scaling and high-contrast mode.
// Theme is ALWAYS dark per KINREL brand guidelines.
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

/// Font scale factor applied on top of base text sizes.
/// 1.0 = default, 1.15 = large, 1.3 = extra-large.
final fontScaleProvider = StateProvider<double>((ref) => 1.0);

/// High-contrast mode toggle for accessibility.
/// When true, increases contrast ratios across the theme.
final highContrastProvider = StateProvider<bool>((ref) => false);

/// Computed [ThemeData] that always uses dark mode with font scale
/// and high-contrast settings.
final appThemeProvider = Provider<ThemeData>((ref) {
  final fontScale = ref.watch(fontScaleProvider);
  final highContrast = ref.watch(highContrastProvider);

  // Always dark — KINREL brand requirement
  const brightness = Brightness.dark;

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
        surface: const Color(0xFF000000),
        onSurface: const Color(0xFFFFFFFF),
        onSurfaceVariant: const Color(0xFFE0E0E0),
        outline: const Color(0xFFBBBBBB),
      ),
      dividerTheme: theme.dividerTheme.copyWith(
        color: const Color(0xFF888888),
      ),
    );
  }

  return theme;
});
