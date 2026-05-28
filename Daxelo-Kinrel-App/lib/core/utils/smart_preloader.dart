// lib/core/utils/smart_preloader.dart
//
// DAXELO KINREL — Smart Preloader
//
// Instagram-style preloading utilities for instant navigation feel.
// All methods are fire-and-forget and silently ignore errors.

import 'package:flutter/material.dart';

/// Smart preloading utilities for Instagram-style instant navigation.
class SmartPreloader {
  /// Preload images for the next [count] items in a list.
  /// Call from a scroll controller listener.
  static void precacheUpcomingImages({
    required BuildContext context,
    required ScrollController scrollController,
    required List<String?> imageUrls,
    required double itemHeight,
    int preloadCount = 3,
  }) {
    if (!scrollController.hasClients) return;

    final offset = scrollController.offset;
    final startIndex = (offset / itemHeight).floor();

    for (int i = startIndex; i < startIndex + preloadCount && i < imageUrls.length; i++) {
      final url = imageUrls[i];
      if (url != null && url.isNotEmpty) {
        // Fire-and-forget precache
        precacheImage(
          NetworkImage(url),
          context,
          onError: (_, __) {}, // Silently ignore errors
        );
      }
    }
  }

  /// Preload a single image by URL.
  static void precacheSingleImage({
    required BuildContext context,
    required String? imageUrl,
  }) {
    if (imageUrl == null || imageUrl.isEmpty) return;
    precacheImage(
      NetworkImage(imageUrl),
      context,
      onError: (_, __) {},
    );
  }
}
