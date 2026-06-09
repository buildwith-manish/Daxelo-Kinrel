// lib/core/utils/image_cache_config.dart
//
// DAXELO KINREL — Image Cache Configuration
//
// Configures the global image cache settings for the app:
//   - 7-day stale time (images stay in disk cache for 7 days)
//   - 100MB max memory cache size
//   - Custom CacheManager (KinrelImageCacheManager) shared by all
//     CachedAvatar / CachedNetworkImage widgets
//
// Call [ImageCacheConfig.initialize()] once during app startup
// (in main.dart or app_startup.dart).

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// ════════════════════════════════════════════════════════════════════
// KINREL IMAGE CACHE MANAGER
// ════════════════════════════════════════════════════════════════════

/// Custom [CacheManager] for Kinrel avatar / profile images.
///
/// Configuration:
/// - **Stale period**: 7 days — images older than 7 days are re-downloaded
/// - **Max cache objects**: 200 — keeps the 200 most-recently-used images
/// - **Cache key**: `kinrel_image_cache` — isolated from other cache managers
///
/// Usage:
/// ```dart
/// CachedNetworkImage(
///   imageUrl: url,
///   cacheManager: KinrelImageCacheManager.instance,
/// )
/// ```
class KinrelImageCacheManager extends CacheManager {
  KinrelImageCacheManager._()
      : super(
          Config(
            'kinrel_image_cache',
            stalePeriod: const Duration(days: 7),
            maxNrOfCacheObjects: 200,
            repo: JsonCacheInfoRepository.new,
            fileService: HttpFileService(),
          ),
        );

  /// Singleton instance used across the app.
  static final KinrelImageCacheManager instance = KinrelImageCacheManager._();
}

// ════════════════════════════════════════════════════════════════════
// IMAGE CACHE CONFIG
// ════════════════════════════════════════════════════════════════════

/// Configures the global image cache settings.
///
/// Call [initialize] once during app startup, after
/// `WidgetsFlutterBinding.ensureInitialized()`:
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await ImageCacheConfig.initialize();
///   runApp(const KinrelApp());
/// }
/// ```
///
/// This sets:
/// - **100 MB** memory image cache limit (Flutter's [imageCache])
/// - The [KinrelImageCacheManager] as the shared disk cache manager
///   with a 7-day stale period
class ImageCacheConfig {
  ImageCacheConfig._();

  /// Maximum in-memory image cache size in bytes (100 MB).
  static const int _maxMemoryCacheBytes = 100 * 1024 * 1024;

  /// Whether the cache has been initialized.
  static bool _initialized = false;

  /// Initialize the image cache with optimized settings.
  ///
  /// - Sets the Flutter [imageCache] maximum size to 100 MB
  /// - Warms up the [KinrelImageCacheManager] singleton so it is
  ///   ready when the first [CachedNetworkImage] is built
  /// - Safe to call multiple times (subsequent calls are no-ops)
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 1. Set memory cache limits for Flutter's in-memory image cache.
      //    This controls how many decoded images are kept in RAM.
      PaintingBinding.instance.imageCache.maximumSizeBytes =
          _maxMemoryCacheBytes;

      // 2. Warm up the KinrelImageCacheManager singleton so that
      //    the first CachedNetworkImage doesn't block on lazy init.
      //    Accessing .instance triggers the constructor.
      KinrelImageCacheManager.instance;

      _initialized = true;
      debugPrint(
        '✅ ImageCacheConfig: Initialized — '
        '7-day disk cache, 100MB memory limit',
      );
    } catch (e) {
      debugPrint('⚠️ ImageCacheConfig: Could not configure cache: $e');
    }
  }

  /// Clears all cached images (both memory and disk).
  ///
  /// Useful when the user signs out or wants to free storage.
  static Future<void> clearAll() async {
    try {
      // Clear memory cache
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // Clear disk cache
      await KinrelImageCacheManager.instance.emptyCache();

      debugPrint('✅ ImageCacheConfig: All caches cleared');
    } catch (e) {
      debugPrint('⚠️ ImageCacheConfig: Could not clear caches: $e');
    }
  }

  /// Returns the current cache statistics for debugging.
  ///
  /// Includes memory cache count and size, and the disk cache
  /// configuration.
  static Map<String, dynamic> getStats() {
    final imageCache = PaintingBinding.instance.imageCache;

    return {
      'memoryCurrentSize': imageCache.currentSizeBytes,
      'memoryMaxSize': imageCache.maximumSizeBytes,
      'memoryCachedCount': imageCache.currentSize,
      'memoryPendingCount': imageCache.pendingImageCount,
      'diskCacheKey': 'kinrel_image_cache',
      'diskStalePeriodDays': 7,
      'diskMaxObjects': 200,
    };
  }
}
