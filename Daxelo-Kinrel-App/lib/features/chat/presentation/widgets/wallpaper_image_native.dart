// lib/features/chat/presentation/widgets/wallpaper_image_native.dart
//
// Native implementation: renders a wallpaper from a file path via
// Image.file. Validates the file exists before rendering.

import 'dart:io';

import 'package:flutter/material.dart';

/// Renders a wallpaper image from a file path (native only).
/// Returns null if the file does not exist (caller should fall back).
Widget? buildWallpaperImageFromFile(
  String path, {
  double? width,
  double? height,
  Widget? fallback,
}) {
  final file = File(path);
  if (!file.existsSync()) return fallback ?? const SizedBox.shrink();
  return Image.file(
    file,
    fit: BoxFit.cover,
    width: width,
    height: height,
    errorBuilder: (_, __, ___) => fallback ?? const SizedBox.shrink(),
  );
}

/// Checks whether a wallpaper path points to an existing file (native).
/// Data URIs are always considered valid.
bool wallpaperPathIsValid(String path) {
  if (path.startsWith('data:')) return true;
  return File(path).existsSync();
}
