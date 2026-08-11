// lib/features/chat/data/wallpaper_file_check_native.dart
//
// Native implementation: checks whether a wallpaper path points to an
// existing file. Uses dart:io.

import 'dart:io';

/// Returns true if [path] points to an existing file.
/// Data URIs are always considered valid (they're in-memory strings).
bool wallpaperFileExists(String path) {
  if (path.startsWith('data:')) return true;
  return File(path).existsSync();
}

/// Deletes a wallpaper file from the filesystem (best-effort, used
/// when cleaning up stale entries).
Future<void> deleteWallpaperFile(String path) async {
  if (path.startsWith('data:')) return;
  try {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  } catch (_) {}
}
