// lib/features/chat/data/wallpaper_picker.dart
//
// DAXELO KINREL — Wallpaper Picker Utility (cross-platform)
//
// Picks an image from the device gallery and returns a path/URI that can
// be persisted and rendered later.
//
// ── Platform behaviour ──────────────────────────────────────────────
//
// **Native (Android / iOS):**
//   Delegates to wallpaper_picker_native.dart — copies the picked file
//   into the app's documents directory and returns the absolute path.
//
// **Web:**
//   Delegates to wallpaper_picker_web.dart — reads the picked image
//   bytes and returns a "data:image/...;base64,..." URI string.
//
// The conditional import ensures dart:io is never compiled on web,
// avoiding dart2js compilation failures.

import 'package:flutter/material.dart';

// Conditional import: on web, use the web implementation; on native,
// use the dart:io implementation.
import 'wallpaper_picker_web.dart' if (dart.library.io) 'wallpaper_picker_native.dart'
    as platform;

class WallpaperPicker {
  WallpaperPicker._();

  /// Opens the device gallery, lets the user pick an image, and returns
  /// a persistable path/URI.
  ///
  /// - On native: returns an absolute file path.
  /// - On web: returns a "data:image/...;base64,..." URI string.
  ///
  /// Returns null if the user cancels or an error occurs (a SnackBar is
  /// shown on error).
  static Future<String?> pickFromGallery(BuildContext context) async {
    try {
      final result = await platform.pickWallpaperFromGalleryNative(context);
      if (result == null && context.mounted) {
        // Only show error if it wasn't a user cancel — we can't
        // distinguish, so we stay silent (user cancel is the common
        // null case). The native/web impls return null on both cancel
        // and error; the SnackBar is shown inside the impls on error.
      }
      return result;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load image. Please try a different photo.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    }
  }
}
