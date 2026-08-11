// lib/features/chat/data/wallpaper_picker_native.dart
//
// Native (Android/iOS) implementation of the wallpaper picker.
// Uses dart:io to copy the picked image into the app's documents
// directory so the path persists across reboots.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Native implementation: picks an image and copies it into the app's
/// documents directory. Returns the copied file's absolute path, or
/// null on cancel/error.
Future<String?> pickWallpaperFromGalleryNative(BuildContext context) async {
  try {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );

    if (xFile == null) return null;

    final appDir = await getApplicationDocumentsDirectory();
    final wallpapersDir = Directory('${appDir.path}/kinrel_wallpapers');
    if (!wallpapersDir.existsSync()) {
      wallpapersDir.createSync(recursive: true);
    }

    final originalExt = xFile.name.split('.').last.toLowerCase();
    final ext = _normalizeExtension(originalExt);
    final filename =
        'wallpaper_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final destPath = '${wallpapersDir.path}/$filename';

    final sourceFile = File(xFile.path);
    await sourceFile.copy(destPath);

    // Validate the copied file exists + has content.
    final destFile = File(destPath);
    if (!destFile.existsSync()) {
      return null;
    }
    final fileSize = await destFile.length();
    if (fileSize == 0) {
      await destFile.delete();
      return null;
    }

    return destPath;
  } catch (_) {
    return null;
  }
}

String _normalizeExtension(String ext) {
  switch (ext) {
    case 'png':
    case 'webp':
    case 'gif':
    case 'jpg':
    case 'jpeg':
      return ext;
    default:
      return 'jpg';
  }
}
