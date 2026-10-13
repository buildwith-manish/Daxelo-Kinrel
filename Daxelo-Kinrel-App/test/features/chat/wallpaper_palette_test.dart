// test/features/chat/wallpaper_palette_test.dart
//
// DAXELO KINREL — TASK 7 — Pure Dart tests for the wallpaper system.
//
// Tests:
//   tintWallColor: null tint returns the base; for each kinship color
//   the lightness of the result is within 0.02 of the base lightness
//   and the alpha is opaque.
//   ChatBackgroundTheme.fromStoredValue: constellation, branches,
//   kolam, contours, ember, ink and an unknown id (falls back).
//   WallpaperPalette equality.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/chat/presentation/widgets/wallpaper_palette.dart';
import 'package:kinrel/features/chat/presentation/widgets/chat_background_theme.dart';

void main() {
  group('tintWallColor', () {
    final base = const Color(0xFF0F111A); // ChatUi.chatBackground

    test('null tint returns the base exactly', () {
      expect(tintWallColor(base, null), base);
    });

    test('result is always opaque (alpha = 1.0)', () {
      const kinshipColors = [
        Color(0xFF3B82F6), // parent (blue)
        Color(0xFF8B5CF6), // sibling (purple)
        Color(0xFFEC4899), // child (pink)
        Color(0xFF6366F1), // grandparent (indigo)
        Color(0xFF06B6D4), // aunt/uncle (cyan)
        Color(0xFF10B981), // cousin (emerald)
        Color(0xFFF59E0B), // in-law (amber)
        Color(0xFFF97316), // spouse (orange)
        Color(0xFFFFC94A), // self (gold)
        Color(0xFF64748B), // extended (slate)
      ];
      for (final tint in kinshipColors) {
        final result = tintWallColor(base, tint);
        expect(result.alpha, 255, reason: 'alpha should be opaque for tint $tint');
      }
    });

    test('result lightness is within 0.02 of base lightness', () {
      final baseHsl = HSLColor.fromColor(base);
      const kinshipColors = [
        Color(0xFF3B82F6),
        Color(0xFF8B5CF6),
        Color(0xFFEC4899),
        Color(0xFF6366F1),
        Color(0xFF06B6D4),
        Color(0xFF10B981),
        Color(0xFFF59E0B),
        Color(0xFFF97316),
        Color(0xFFFFC94A),
        Color(0xFF64748B),
      ];
      for (final tint in kinshipColors) {
        final result = tintWallColor(base, tint);
        final resultHsl = HSLColor.fromColor(result);
        expect(
          (resultHsl.lightness - baseHsl.lightness).abs(),
          lessThan(0.02),
          reason: 'lightness should be within 0.02 for tint $tint',
        );
      }
    });

    test('result hue matches tint hue', () {
      const tint = Color(0xFF3B82F6); // parent blue
      final result = tintWallColor(base, tint);
      final tintHsl = HSLColor.fromColor(tint);
      final resultHsl = HSLColor.fromColor(result);
      expect(
        (resultHsl.hue - tintHsl.hue).abs(),
        lessThan(1.0),
        reason: 'hue should match the tint hue',
      );
    });

    test('result saturation is capped at 0.55', () {
      const tint = Color(0xFFFF0000); // pure red, high saturation
      final result = tintWallColor(base, tint);
      final resultHsl = HSLColor.fromColor(result);
      expect(resultHsl.saturation, lessThanOrEqualTo(0.55));
    });
  });

  group('ChatBackgroundTheme.fromStoredValue', () {
    test('constellation', () {
      final t = ChatBackgroundTheme.fromStoredValue('theme:constellation');
      expect(t.id, 'constellation');
    });

    test('branches', () {
      final t = ChatBackgroundTheme.fromStoredValue('theme:branches');
      expect(t.id, 'branches');
    });

    test('kolam', () {
      final t = ChatBackgroundTheme.fromStoredValue('theme:kolam');
      expect(t.id, 'kolam');
    });

    test('contours', () {
      final t = ChatBackgroundTheme.fromStoredValue('theme:contours');
      expect(t.id, 'contours');
    });

    test('ember', () {
      final t = ChatBackgroundTheme.fromStoredValue('theme:ember');
      expect(t.id, 'ember');
    });

    test('ink', () {
      final t = ChatBackgroundTheme.fromStoredValue('theme:ink');
      expect(t.id, 'ink');
    });

    test('unknown id falls back to default (constellation)', () {
      final t = ChatBackgroundTheme.fromStoredValue('theme:nonexistent');
      expect(t.id, ChatBackgroundTheme.defaultTheme.id);
    });

    test('null value falls back to default', () {
      final t = ChatBackgroundTheme.fromStoredValue(null);
      expect(t.id, ChatBackgroundTheme.defaultTheme.id);
    });

    test('non-theme value (image path) falls back to default', () {
      final t = ChatBackgroundTheme.fromStoredValue('/data/image.png');
      expect(t.id, ChatBackgroundTheme.defaultTheme.id);
    });

    test('hasPattern is true for pattern themes', () {
      expect(ChatBackgroundTheme.constellation.hasPattern, isTrue);
      expect(ChatBackgroundTheme.branches.hasPattern, isTrue);
      expect(ChatBackgroundTheme.kolam.hasPattern, isTrue);
      expect(ChatBackgroundTheme.contours.hasPattern, isTrue);
    });

    test('hasPattern is false for solid themes', () {
      expect(ChatBackgroundTheme.ember.hasPattern, isFalse);
      expect(ChatBackgroundTheme.ink.hasPattern, isFalse);
      expect(ChatBackgroundTheme.midnight.hasPattern, isFalse);
    });
  });

  group('WallpaperPalette equality', () {
    test('identical palettes are equal', () {
      const a = WallpaperPalette.standard;
      const b = WallpaperPalette.standard;
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });

    test('different alphas are not equal', () {
      const a = WallpaperPalette.standard;
      const b = WallpaperPalette.subtle;
      expect(a == b, isFalse);
    });

    test('tinted palette is not equal to neutral', () {
      final neutral = WallpaperPalette.resolve(
        intensity: WallpaperIntensity.standard,
        tint: null,
      );
      final tinted = WallpaperPalette.resolve(
        intensity: WallpaperIntensity.standard,
        tint: const Color(0xFF3B82F6),
      );
      expect(neutral == tinted, isFalse);
    });

    test('same tint produces equal palettes', () {
      final a = WallpaperPalette.resolve(
        intensity: WallpaperIntensity.standard,
        tint: const Color(0xFF3B82F6),
      );
      final b = WallpaperPalette.resolve(
        intensity: WallpaperIntensity.standard,
        tint: const Color(0xFF3B82F6),
      );
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });
  });
}
