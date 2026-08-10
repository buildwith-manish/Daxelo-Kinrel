// lib/features/chat/data/chat_wallpaper_provider.dart
//
// DAXELO KINREL — Chat Wallpaper Provider
//
// Manages per-chat custom wallpaper image paths. Each chat (family group
// chat or 1:1 DM) can have its own wallpaper independently. A global
// "default" wallpaper applies to any chat that hasn't been customised.
//
// Wallpaper paths persist across sessions via shared_preferences, keyed
// "kinrel_wallpaper_$chatId".
//
// ── Stored value format ─────────────────────────────────────────────
//
// - **Web:** the stored value is a "data:image/...;base64,..." URI
//   string (produced by WallpaperPicker on web). No filesystem access.
//
// - **Native:** the stored value is an absolute file path (the image
//   copied into the app's documents directory by WallpaperPicker). On
//   load, paths pointing to non-existent files are filtered out so the
//   UI doesn't try to render a deleted file.
//
// Chat ID conventions:
//   - Family group chat → the family ID (e.g. "fam_abc123")
//   - 1:1 DM → "dm_<otherUserId>" (prefixed to avoid collisions)
//   - Global default → "default"

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// StateNotifier holding a map of chatId → wallpaper path/URI (or null).
class ChatWallpaperNotifier extends StateNotifier<Map<String, String?>> {
  ChatWallpaperNotifier() : super({}) {
    _loadAll();
  }

  static const _prefsKeyPrefix = 'kinrel_wallpaper_';

  /// Loads all persisted wallpaper entries from shared_preferences into
  /// state on init. On native, filters out paths whose files no longer
  /// exist (stale entries from cleared app data).
  Future<void> _loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final wallpaperKeys = keys.where((k) => k.startsWith(_prefsKeyPrefix));
      final map = <String, String?>{};
      for (final k in wallpaperKeys) {
        final chatId = k.substring(_prefsKeyPrefix.length);
        final path = prefs.getString(k);
        if (path == null || path.isEmpty) continue;

        // On native, validate the file still exists. Data URIs (web) are
        // always considered valid.
        if (!kIsWeb && !path.startsWith('data:')) {
          final file = File(path);
          if (!file.existsSync()) {
            // Stale entry — the wallpaper file was deleted. Remove it
            // from prefs so it doesn't keep failing silently.
            await prefs.remove(k);
            continue;
          }
        }

        map[chatId] = path;
      }
      if (mounted) state = map;
    } catch (e) {
      // Best-effort — if prefs fails, start with empty state.
      debugPrint('[ChatWallpaperProvider] Error loading wallpapers: $e');
    }
  }

  /// Saves the wallpaper [filePath] for [chatId] to shared_preferences
  /// and updates state. On native, validates the file exists before
  /// saving.
  Future<void> setWallpaper(String chatId, String filePath) async {
    try {
      // On native, validate the file exists before persisting.
      if (!kIsWeb && !filePath.startsWith('data:')) {
        final file = File(filePath);
        if (!file.existsSync()) {
          debugPrint(
              '[ChatWallpaperProvider] setWallpaper: file does not exist at '
              '$filePath — not saving.');
          return;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefsKeyPrefix$chatId', filePath);
      if (mounted) {
        state = {...state, chatId: filePath};
      }
      debugPrint(
          '[ChatWallpaperProvider] setWallpaper: saved for chatId="$chatId", '
          'path length=${filePath.length}');
    } catch (e) {
      debugPrint('[ChatWallpaperProvider] setWallpaper error: $e');
    }
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
      debugPrint(
          '[ChatWallpaperProvider] clearWallpaper: removed chatId="$chatId"');
    } catch (e) {
      debugPrint('[ChatWallpaperProvider] clearWallpaper error: $e');
    }
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
