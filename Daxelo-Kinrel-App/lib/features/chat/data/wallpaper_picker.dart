// lib/features/chat/data/wallpaper_picker.dart
//
// DAXELO KINREL — Wallpaper Picker Utility
//
// Picks an image from the device gallery and copies it into the app's
// documents directory so the path remains valid across reboots (Android
// gallery content URIs can become stale after a reboot).
//
// Used by the chat screens (group + DM) and the wallpaper settings screen
// to set a custom chat wallpaper.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class WallpaperPicker {
  WallpaperPicker._();

  /// Opens the device gallery, lets the user pick an image, copies it
  /// into the app's documents directory under "kinrel_wallpapers/", and
  /// returns the copied file's absolute path.
  ///
  /// Returns null if the user cancels or an error occurs (a SnackBar is
  /// shown on error).
  static Future<String?> pickFromGallery(BuildContext context) async {
    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      // User cancelled.
      if (xFile == null) return null;

      // Copy into the app documents directory so the path persists.
      final appDir = await getApplicationDocumentsDirectory();
      final wallpapersDir = Directory('${appDir.path}/kinrel_wallpapers');
      if (!wallpapersDir.existsSync()) {
        wallpapersDir.createSync(recursive: true);
      }

      final filename =
          'wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final destPath = '${wallpapersDir.path}/$filename';

      final sourceFile = File(xFile.path);
      await sourceFile.copy(destPath);

      return destPath;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load image'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    }
  }
}
