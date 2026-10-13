// lib/features/chat/data/wallpaper_settings_provider.dart
//
// DAXELO KINREL — Wallpaper Settings Provider (TASK 5)
//
// Two global preferences in SharedPreferences:
//   wallpaper_match_relationship (bool, default true)
//   wallpaper_contrast (standard or subtle, default standard)
//
// Follows the pattern of chat_wallpaper_provider.dart.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../presentation/widgets/wallpaper_palette.dart';

/// State for the two wallpaper settings.
class WallpaperSettings {
  const WallpaperSettings({
    this.matchRelationship = true,
    this.intensity = WallpaperIntensity.standard,
  });

  final bool matchRelationship;
  final WallpaperIntensity intensity;

  WallpaperSettings copyWith({
    bool? matchRelationship,
    WallpaperIntensity? intensity,
  }) {
    return WallpaperSettings(
      matchRelationship: matchRelationship ?? this.matchRelationship,
      intensity: intensity ?? this.intensity,
    );
  }
}

class WallpaperSettingsNotifier extends StateNotifier<WallpaperSettings> {
  WallpaperSettingsNotifier() : super(const WallpaperSettings()) {
    _load();
  }

  static const _keyMatch = 'wallpaper_match_relationship';
  static const _keyContrast = 'wallpaper_contrast';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final match = prefs.getBool(_keyMatch) ?? true;
      final contrastStr = prefs.getString(_keyContrast) ?? 'standard';
      final intensity = contrastStr == 'subtle'
          ? WallpaperIntensity.subtle
          : WallpaperIntensity.standard;
      if (mounted) {
        state = WallpaperSettings(
          matchRelationship: match,
          intensity: intensity,
        );
      }
    } catch (_) {}
  }

  Future<void> setMatchRelationship(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyMatch, value);
      if (mounted) {
        state = state.copyWith(matchRelationship: value);
      }
    } catch (_) {}
  }

  Future<void> setIntensity(WallpaperIntensity value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _keyContrast,
        value == WallpaperIntensity.subtle ? 'subtle' : 'standard',
      );
      if (mounted) {
        state = state.copyWith(intensity: value);
      }
    } catch (_) {}
  }
}

final wallpaperSettingsProvider =
    StateNotifierProvider<WallpaperSettingsNotifier, WallpaperSettings>(
  (ref) => WallpaperSettingsNotifier(),
);
