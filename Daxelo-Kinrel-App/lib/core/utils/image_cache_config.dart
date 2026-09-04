// lib/core/utils/image_cache_config.dart
//
// DAXELO KINREL — Image Cache Configuration
//
// Configures the global image cache settings for the app:
//   - 7-day stale time (images stay in disk cache for 7 days)
//   - Tier-aware max memory cache size (100MB high / 60MB mid / 40MB low)
//   - Custom CacheManager (KinrelImageCacheManager) shared by all
//     CachedAvatar / CachedNetworkImage widgets
//
// Call [ImageCacheConfig.initialize()] once during app startup
// (in main.dart or app_startup.dart).

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'device_tier.dart' show DeviceTier, DeviceTierCache;

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
            repo: JsonCacheInfoRepository(databaseName: 'kinrel_image_cache'),
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

  /// v5.141 (LOW-END PERF): Default maximum in-memory image cache size
  /// in bytes for high-end devices (100 MB). Mid-range devices use 60
  /// MB, low-end devices use 40 MB. The actual limit is computed in
  /// [initialize] from [DeviceTierCache].
  static const int _maxMemoryCacheBytesHigh = 100 * 1024 * 1024;
  static const int _maxMemoryCacheBytesMid = 60 * 1024 * 1024;
  static const int _maxMemoryCacheBytesLow = 40 * 1024 * 1024;

  /// Whether the cache has been initialized.
  static bool _initialized = false;

  /// Returns the tier-appropriate memory cache limit in bytes.
  /// Falls back to the mid-range value if the device tier hasn't been
  /// initialized yet (e.g. web before first frame).
  static int _tierAppropriateCacheLimit() {
    switch (DeviceTierCache.instance.tier) {
      case DeviceTier.high:
        return _maxMemoryCacheBytesHigh;
      case DeviceTier.mid:
        return _maxMemoryCacheBytesMid;
      case DeviceTier.low:
        return _maxMemoryCacheBytesLow;
    }
  }

  /// Initialize the image cache with optimized settings.
  ///
  /// - Sets the Flutter [imageCache] maximum size based on device tier
  ///   (100 MB high / 60 MB mid / 40 MB low)
  /// - Warms up the [KinrelImageCacheManager] singleton so it is
  ///   ready when the first [CachedNetworkImage] is built
  /// - Safe to call multiple times (subsequent calls are no-ops)
  static Future<void> initialize() async {
    if (_initialized) return;

    final maxBytes = _tierAppropriateCacheLimit();

    // WEB: Skip disk cache initialization on web — flutter_cache_manager
    // uses sqflite + path_provider which don't work on web. The in-memory
    // image cache (PaintingBinding) works fine on web, so we still set
    // that up. CachedNetworkImage will fall back to network-only mode
    // (no disk caching) on web, which is acceptable.
    if (kIsWeb) {
      try {
        PaintingBinding.instance.imageCache.maximumSizeBytes = maxBytes;
        _initialized = true;
        debugPrint('✅ ImageCacheConfig: Web mode — memory cache only '
            '(${(maxBytes / (1024 * 1024)).round()} MB, tier=${DeviceTierCache.instance.tier})');
      } catch (e) {
        debugPrint('⚠️ ImageCacheConfig: Web memory cache setup failed: $e');
      }
      return;
    }

    try {
      // 1. Set memory cache limits for Flutter's in-memory image cache.
      //    This controls how many decoded images are kept in RAM.
      //    v5.141: Tier-aware — low-end devices get 40 MB to avoid GC
      //    pressure on 2–4 GB RAM devices.
      PaintingBinding.instance.imageCache.maximumSizeBytes = maxBytes;

      // 2. Warm up the KinrelImageCacheManager singleton so that
      //    the first CachedNetworkImage doesn't block on lazy init.
      //    Accessing .instance triggers the constructor.
      KinrelImageCacheManager.instance;

      _initialized = true;
      debugPrint(
        '✅ ImageCacheConfig: Initialized — '
        '7-day disk cache, ${(maxBytes / (1024 * 1024)).round()} MB memory limit '
        '(tier=${DeviceTierCache.instance.tier})',
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
