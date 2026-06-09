// lib/core/services/image_cache_manager.dart
//
// DAXELO KINREL — Custom Image Cache Manager
//
// Configures CachedNetworkImage with:
// - 7-day disk cache expiration (stale files auto-cleaned)
// - 100MB maximum disk cache size
// - Custom cache key for namespace isolation

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Custom cache manager for avatar and image caching.
/// 7-day stale file timeout, 100MB max cache size.
class KinrelImageCacheManager extends CacheManager {
  static const key = 'kinrel_images';

  KinrelImageCacheManager()
      : super(Config(
          key,
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 200,
          repo: JsonCacheInfoRepository(databaseName: key),
          fileSystem: IOFileSystem(key),
          fileService: HttpFileService(),
        ));

  /// Singleton instance.
  static KinrelImageCacheManager? _instance;
  static KinrelImageCacheManager get instance =>
      _instance ??= KinrelImageCacheManager();

  /// Clear all cached images (useful for sign-out or storage cleanup).
  Future<void> clearAll() async {
    await emptyCache();
  }

  /// Get current cache size in bytes.
  Future<int> getCacheSize() async {
    try {
      return await store.getCacheSize();
    } catch (_) {
      return 0;
    }
  }

  /// Check if cache exceeds 100MB and clean if needed.
  Future<void> enforceMaxSize() async {
    const maxBytes = 100 * 1024 * 1024; // 100MB
    final size = await getCacheSize();
    if (size > maxBytes) {
      await emptyCache();
    }
  }
}
