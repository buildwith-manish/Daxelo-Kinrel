// lib/features/chat/presentation/widgets/wallpaper_image_web.dart
//
// Web implementation: renders a wallpaper from a data: URI via
// Image.network. No dart:io needed.
//
// PERF PASS STEP 3 — INTENTIONALLY SKIPPED:
// This file is web-only and the path it receives is always a `data:`
// URI (base64 in-memory), never an HTTP URL. CachedNetworkImage uses
// an HTTP client (HttpFileService) under the hood and cannot fetch
// `data:` URIs — converting this call would silently break wallpaper
// rendering on web (errorWidget would always fire). Web also doesn't
// benefit from CachedNetworkImage's on-disk cache (the data URI is
// already in memory). Leave Image.network as-is.

import 'package:flutter/material.dart';

/// Renders a wallpaper image from a data: URI (web only).
/// On web, all wallpaper paths are data: URIs, so this always works.
Widget? buildWallpaperImageFromFile(
  String path, {
  double? width,
  double? height,
  Widget? fallback,
}) {
  return Image.network(
    path,
    fit: BoxFit.cover,
    width: width,
    height: height,
    errorBuilder: (_, __, ___) => fallback ?? const SizedBox.shrink(),
  );
}

/// On web, data: URIs are always valid (they're in-memory strings).
bool wallpaperPathIsValid(String path) {
  return path.startsWith('data:');
}
