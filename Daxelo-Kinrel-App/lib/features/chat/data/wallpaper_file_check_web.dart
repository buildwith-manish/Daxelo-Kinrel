// lib/features/chat/data/wallpaper_file_check_web.dart
//
// Web implementation: data: URIs are always valid (in-memory strings).
// No dart:io needed.

/// On web, all wallpaper values are data: URIs — always valid.
bool wallpaperFileExists(String path) {
  return path.startsWith('data:');
}

/// No-op on web — data: URIs are in-memory and don't need deletion.
Future<void> deleteWallpaperFile(String path) async {}
