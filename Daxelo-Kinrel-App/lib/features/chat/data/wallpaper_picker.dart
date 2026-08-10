// lib/features/chat/data/wallpaper_picker.dart
//
// DAXELO KINREL — Wallpaper Picker Utility
//
// Picks an image from the device gallery and returns a path/URI that can
// be persisted and rendered later.
//
// ── Platform behaviour ──────────────────────────────────────────────
//
// **Native (Android / iOS):**
//   1. ImagePicker picks the image.
//   2. The picked file is copied into the app's documents directory
//      under "kinrel_wallpapers/" so the path survives reboots (Android
//      gallery content URIs can become stale after a reboot).
//   3. Returns the copied file's absolute path.
//   4. Verifies the copied file exists + has non-zero size before
//      returning.
//
// **Web:**
//   1. ImagePicker picks the image (returns an XFile backed by a Blob).
//   2. Reads the bytes and base64-encodes them into a data: URI.
//   3. Returns the data: URI string (which Image.network can render).
//   dart:io File operations do NOT work on web, so we never touch the
//   filesystem — the data: URI is stored directly in shared_preferences.
//
// Used by the chat screens (group + DM) and the wallpaper settings
// screen to set a custom chat wallpaper.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class WallpaperPicker {
  WallpaperPicker._();

  /// Opens the device gallery, lets the user pick an image, and returns
  /// a persistable path/URI.
  ///
  /// - On native: returns an absolute file path (image copied into the
  ///   app's documents directory).
  /// - On web: returns a "data:image/...;base64,..." URI string.
  ///
  /// Returns null if the user cancels or an error occurs (a SnackBar is
  /// shown on error).
  static Future<String?> pickFromGallery(BuildContext context) async {
    try {
      debugPrint('[WallpaperPicker] Opening gallery picker…');
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      // User cancelled.
      if (xFile == null) {
        debugPrint('[WallpaperPicker] User cancelled — no image picked.');
        return null;
      }

      debugPrint('[WallpaperPicker] Picked image path: ${xFile.path}');

      // ── Web: read bytes → base64 data URI ──────────────────────
      if (kIsWeb) {
        final bytes = await xFile.readAsBytes();
        if (bytes.isEmpty) {
          debugPrint('[WallpaperPicker] Web: picked image has 0 bytes.');
          _showErrorSnackBar(context, 'Selected image is empty.');
          return null;
        }
        // Determine mime type from the file extension.
        final ext = xFile.name.split('.').last.toLowerCase();
        final mime = _mimeTypeForExtension(ext);
        final b64 = base64Encode(bytes);
        final dataUri = 'data:$mime;base64,$b64';
        debugPrint(
            '[WallpaperPicker] Web: encoded ${bytes.length} bytes → '
            'data URI of length ${dataUri.length}.');
        return dataUri;
      }

      // ── Native: copy file into app documents directory ──────────
      final appDir = await getApplicationDocumentsDirectory();
      final wallpapersDir = Directory('${appDir.path}/kinrel_wallpapers');
      if (!wallpapersDir.existsSync()) {
        wallpapersDir.createSync(recursive: true);
      }

      // Preserve the original extension so JPG/PNG/WEBP all work.
      final originalExt = xFile.name.split('.').last.toLowerCase();
      final ext = _normalizeExtension(originalExt);
      final filename =
          'wallpaper_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final destPath = '${wallpapersDir.path}/$filename';

      debugPrint('[WallpaperPicker] Native: copying to $destPath');
      final sourceFile = File(xFile.path);
      await sourceFile.copy(destPath);

      // ── Validate the copied file exists + has content ──────────
      final destFile = File(destPath);
      if (!destFile.existsSync()) {
        debugPrint(
            '[WallpaperPicker] Native: copied file does not exist at $destPath');
        _showErrorSnackBar(context, 'Could not save image. Please try again.');
        return null;
      }
      final fileSize = await destFile.length();
      if (fileSize == 0) {
        debugPrint(
            '[WallpaperPicker] Native: copied file is 0 bytes at $destPath');
        await destFile.delete();
        _showErrorSnackBar(context, 'Selected image is empty.');
        return null;
      }

      debugPrint(
          '[WallpaperPicker] Native: wallpaper saved successfully ($fileSize bytes) at $destPath');
      return destPath;
    } catch (e, stackTrace) {
      debugPrint('[WallpaperPicker] ERROR picking image: $e');
      debugPrint('[WallpaperPicker] Stack trace: $stackTrace');
      _showErrorSnackBar(context, 'Could not load image. Please try a different photo.');
      return null;
    }
  }

  /// Shows an error SnackBar.
  static void _showErrorSnackBar(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Maps a file extension to a MIME type for the data URI.
  static String _mimeTypeForExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  /// Normalises the file extension for the saved wallpaper filename.
  static String _normalizeExtension(String ext) {
    switch (ext) {
      case 'png':
      case 'webp':
      case 'gif':
      case 'jpg':
      case 'jpeg':
        return ext;
      default:
        return 'jpg'; // safe default
    }
  }
}
