// lib/features/chat/data/chat_wallpaper_provider.dart
//
// DAXELO KINREL — Chat Wallpaper Provider
//
// Manages per-chat custom wallpaper image paths. Each chat (family group
// chat or 1:1 DM) can have its own wallpaper independently. A global
// "default" wallpaper applies to any chat that hasn't been customised.
//
// Wallpaper paths are absolute local file paths (copied into the app's
// documents directory by WallpaperPicker). They persist across sessions
// via shared_preferences, keyed "kinrel_wallpaper_$chatId".
//
// Chat ID conventions:
//   - Family group chat → the family ID (e.g. "fam_abc123")
//   - 1:1 DM → "dm_<otherUserId>" (prefixed to avoid collisions)
//   - Global default → "default"

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// StateNotifier holding a map of chatId → wallpaper file path (or null).
class ChatWallpaperNotifier extends StateNotifier<Map<String, String?>> {
  ChatWallpaperNotifier() : super({}) {
    _loadAll();
  }

  static const _prefsKeyPrefix = 'kinrel_wallpaper_';

  /// Loads all persisted wallpaper entries from shared_preferences into
  /// state on init.
  Future<void> _loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final wallpaperKeys = keys.where((k) => k.startsWith(_prefsKeyPrefix));
      final map = <String, String?>{};
      for (final k in wallpaperKeys) {
        final chatId = k.substring(_prefsKeyPrefix.length);
        final path = prefs.getString(k);
        if (path != null && path.isNotEmpty) {
          map[chatId] = path;
        }
      }
      if (mounted) state = map;
    } catch (_) {
      // Best-effort — if prefs fails, start with empty state.
    }
  }

  /// Saves the wallpaper [filePath] for [chatId] to shared_preferences
  /// and updates state.
  Future<void> setWallpaper(String chatId, String filePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsKeyPrefix$chatId', filePath);
      if (mounted) {
        state = {...state, chatId: filePath};
      }
    } catch (_) {}
  }

  /// Removes the wallpaper for [chatId] from shared_preferences and sets
  /// the state value to null.
  Future<void> clearWallpaper(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefsKeyPrefix$chatId');
      if (mounted) {
        final newMap = Map<String, String?>.from(state);
        newMap.remove(chatId);
        state = newMap;
      }
    } catch (_) {}
  }

  /// Returns the wallpaper path for [chatId], falling back to the global
  /// default if no per-chat wallpaper is set. Returns null if neither
  /// exists.
  String? getWallpaper(String chatId) {
    return state[chatId] ?? state['default'];
  }
}

/// Riverpod provider for the wallpaper state map.
final chatWallpaperProvider =
    StateNotifierProvider<ChatWallpaperNotifier, Map<String, String?>>((ref) {
  return ChatWallpaperNotifier();
});

/// Convenience provider that returns the effective wallpaper path for a
/// given [chatId] — the per-chat wallpaper if set, otherwise the global
/// default, otherwise null.
///
/// Usage:
///   final path = ref.watch(wallpaperPathProvider(chatId));
final wallpaperPathProvider = Provider.family<String?, String>((ref, chatId) {
  final map = ref.watch(chatWallpaperProvider);
  return map[chatId] ?? map['default'];
});
