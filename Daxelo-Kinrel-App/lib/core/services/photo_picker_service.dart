// lib/core/services/photo_picker_service.dart
//
// DAXELO KINREL — Photo Picker Service
//
// Handles avatar photo selection from camera or gallery.
// Gated behind kEnablePhotoPicker feature flag.
// Does NOT use image_cropper (removed due to Android crash).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PhotoPickerService {
  PhotoPickerService._();

  static final _picker = ImagePicker();

  /// Shows a bottom sheet to choose camera or gallery.
  /// Returns the selected image file, or null if cancelled.
  static Future<File?> pickImage(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return null;

    try {
      final xfile = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (xfile == null) return null;
      return File(xfile.path);
    } catch (e) {
      debugPrint('PhotoPickerService: pickImage failed: $e');
      return null;
    }
  }

  /// Picks an image and returns its path as a string.
  static Future<String?> pickImagePath(BuildContext context) async {
    final file = await pickImage(context);
    return file?.path;
  }
}
