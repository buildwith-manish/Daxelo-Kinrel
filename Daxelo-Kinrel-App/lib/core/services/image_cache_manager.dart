// lib/core/services/image_cache_manager.dart
//
// DAXELO KINREL — Image Cache Manager (CONSOLIDATED)
//
// This file re-exports the canonical KinrelImageCacheManager from
// utils/image_cache_config.dart. Previously there were TWO competing
// cache manager classes with different cache keys:
//   - services/image_cache_manager.dart (key: 'kinrel_images')
//   - utils/image_cache_config.dart (key: 'kinrel_image_cache')
//
// This caused the same avatar URL to be downloaded + cached TWICE —
// once for CachedAvatar (which used the utils version) and again for
// feed_post_card / message_bubble / etc. (which used the services
// version). Doubled disk usage, halved cache hit rate.
//
// Now all 25+ call sites that import from services/image_cache_manager.dart
// get the SAME singleton (cache key: 'kinrel_image_cache') as CachedAvatar.
// The old 'kinrel_images' cache key is orphaned — existing cached files
// will expire via the 7-day stale period and be garbage-collected.
//
// The canonical class lives in utils/image_cache_config.dart because it
// also contains the tier-aware memory limit logic (100MB/60MB/40MB by
// device tier) which is valuable and worth keeping in one place.

export '../utils/image_cache_config.dart' show KinrelImageCacheManager;
