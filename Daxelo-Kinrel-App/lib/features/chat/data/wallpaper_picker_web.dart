// lib/features/chat/data/wallpaper_picker_web.dart
//
// Web implementation of the wallpaper picker. Reads the picked image
// bytes and returns a data: URI string — no dart:io needed.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Web implementation: picks an image and returns a base64 data: URI
/// string, or null on cancel/error.
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

    final bytes = await xFile.readAsBytes();
    if (bytes.isEmpty) return null;

    final ext = xFile.name.split('.').last.toLowerCase();
    final mime = _mimeTypeForExtension(ext);
    final b64 = base64Encode(bytes);
    return 'data:$mime;base64,$b64';
  } catch (_) {
    return null;
  }
}

String _mimeTypeForExtension(String ext) {
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
