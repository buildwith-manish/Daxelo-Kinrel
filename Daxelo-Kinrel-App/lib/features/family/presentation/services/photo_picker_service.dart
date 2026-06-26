// lib/features/family/presentation/services/photo_picker_service.dart
//
// DAXELO KINREL — Avatar Photo Picker (Step 5).
//
// Picks an avatar from camera or gallery (image_picker) and uploads it to the
// Supabase `avatars` bucket, returning a public URL. Mirrors the proven upload
// pattern in create_family_screen.dart. Gated by kEnablePhotoPicker at call
// sites. (Crop is intentionally omitted — image_cropper was removed in BUG-03.)

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Picks and uploads person avatar photos.
class PhotoPickerService {
  const PhotoPickerService._();

  /// Picks an image from [source], downscaled for avatars. Returns null if the
  /// user cancels.
  static Future<XFile?> pick(ImageSource source) {
    final picker = ImagePicker();
    return picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
  }

  /// Shows a Camera / Gallery chooser sheet and returns the picked file, or
  /// null if dismissed.
  static Future<XFile?> pickWithSheet(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) return null;
    return pick(source);
  }

  /// Uploads [file] to Supabase storage and returns its public URL, or null on
  /// failure (caller should fall back to initials — never crash on upload).
  static Future<String?> uploadAvatar(
    XFile file, {
    String bucket = 'avatars',
    String pathPrefix = 'person-avatars',
  }) async {
    try {
      final supabase = Supabase.instance.client;
      final bytes = await file.readAsBytes();
      final ext = file.path.contains('.')
          ? file.path.split('.').last.toLowerCase()
          : 'jpg';
      final safeExt =
          const <String>['jpg', 'jpeg', 'png', 'webp'].contains(ext)
              ? ext
              : 'jpg';
      final path =
          '$pathPrefix/${DateTime.now().millisecondsSinceEpoch}.$safeExt';

      await supabase.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$safeExt',
              upsert: true,
            ),
          );
      return supabase.storage.from(bucket).getPublicUrl(path);
    } on StorageException catch (e) {
      debugPrint('⚠️ Avatar upload failed: ${e.message}. Continuing without photo.');
      return null;
    } catch (e) {
      debugPrint('⚠️ Avatar upload unexpected error: $e');
      return null;
    }
  }
}
