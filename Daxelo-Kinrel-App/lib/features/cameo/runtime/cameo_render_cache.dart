// lib/features/cameo/runtime/cameo_render_cache.dart
//
// KINREL CAMEO — Render Cache
//
// V2 §47 — Portrait Cache and Invalidation.
// LRU cache for derived PNG portraits. Keyed by:
//   personId + definitionHash + lod + state + ageContext + assetPackVersion
//
// Cache hit: < 8ms (memory read + decode).
// Cache miss: 200-500ms (renderer.renderPortrait() on mid-tier).
//
// The cache is pure Dart — no renderer dependency. It stores Uint8List
// (PNG bytes) keyed by a composite string. The PortraitRenderPipeline
// uses this cache to avoid re-rendering unchanged portraits.

import 'dart:collection';
import 'dart:typed_data';

/// Cache key for a derived portrait.
///
/// Same person + same definition + same LOD + same state + same age
/// context + same asset pack → same key → cache hit.
class CameoPortraitCacheKey {
  CameoPortraitCacheKey({
    required this.personId,
    required this.definitionHash,
    required this.lod,
    required this.stateId,
    required this.ageContext,
    required this.assetPackVersion,
  });

  final String personId;
  final String definitionHash;
  final int lod; // 0, 1, 2, 3
  final String stateId; // expression + event state
  final String ageContext; // 'current', 'timeline:1985', etc.
  final String assetPackVersion;

  String get key =>
      '$personId|$definitionHash|lod$lod|$stateId|$ageContext|apv$assetPackVersion';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameoPortraitCacheKey && key == other.key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'CameoPortraitCacheKey($key)';
}

/// LRU cache for derived Cameo portraits.
///
/// Stores PNG bytes in memory. Max entries configurable.
/// When capacity is exceeded, the least-recently-used entry is evicted.
///
/// Thread safety: This cache is NOT thread-safe. It must be accessed
/// from the main isolate only. Portrait rendering happens on a
/// background isolate; the result is posted back to the main isolate
/// and inserted into this cache.
class CameoRenderCache {
  CameoRenderCache({this.maxEntries = 200});

  final int maxEntries;

  // LinkedHashMap with access order = LRU.
  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();

  /// Total number of cached portraits.
  int get size => _cache.length;

  /// Total memory used (approximate, in bytes).
  int get memoryUsageBytes =>
      _cache.values.fold(0, (sum, e) => sum + e.bytes.length);

  /// Retrieves a cached portrait. Returns null on miss.
  Uint8List? get(CameoPortraitCacheKey key) {
    final entry = _cache[key.key];
    if (entry == null) return null;

    // Move to end (most recently used).
    _cache.remove(key.key);
    _cache[key.key] = entry;
    return entry.bytes;
  }

  /// Stores a portrait in the cache. Evicts LRU if at capacity.
  void put(CameoPortraitCacheKey key, Uint8List bytes) {
    if (_cache.containsKey(key.key)) {
      _cache.remove(key.key);
    } else if (_cache.length >= maxEntries) {
      // Evict least recently used (first entry).
      _cache.remove(_cache.keys.first);
    }
    _cache[key.key] = _CacheEntry(bytes: bytes, cachedAt: DateTime.now());
  }

  /// Invalidates all cached portraits for a specific person.
  /// Called when the person's Cameo definition changes.
  void invalidatePerson(String personId) {
    _cache.removeWhere((key, _) => key.startsWith('$personId|'));
  }

  /// Invalidates all cached portraits for a specific asset pack version.
  /// Called when GLB assets are updated.
  void invalidateAssetPack(String assetPackVersion) {
    _cache.removeWhere((key, _) => key.endsWith('apv$assetPackVersion'));
  }

  /// Clears the entire cache.
  void clear() {
    _cache.clear();
  }

  /// Returns cache statistics for diagnostics.
  Map<String, dynamic> get stats => {
    'size': size,
    'maxEntries': maxEntries,
    'memoryUsageBytes': memoryUsageBytes,
    'memoryUsageMB': (memoryUsageBytes / 1024 / 1024).toStringAsFixed(2),
  };
}

class _CacheEntry {
  const _CacheEntry({required this.bytes, required this.cachedAt});

  final Uint8List bytes;
  final DateTime cachedAt;
}
