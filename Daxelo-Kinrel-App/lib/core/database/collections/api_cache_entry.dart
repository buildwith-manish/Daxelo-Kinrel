/// Data class for caching API responses.
/// Provides a generic key-value cache with TTL support for any API endpoint.
class ApiCacheEntry {
  int? isarId;

  /// Cache key (typically the API endpoint path + query params)
  late String key;

  /// Cached response body as JSON string
  late String responseBody;

  /// When this cache entry was created
  late String cachedAt;

  /// Time-to-live in seconds (how long this cache entry is considered fresh)
  late int ttlSeconds;

  /// ETag or version identifier for cache validation
  String? eTag;

  /// Whether this cache entry is still considered fresh
  bool get isFresh {
    final cachedTime = DateTime.tryParse(cachedAt);
    if (cachedTime == null) return false;
    final expiresAt = cachedTime.add(Duration(seconds: ttlSeconds));
    return DateTime.now().isBefore(expiresAt);
  }

  /// Create a new API cache entry
  static ApiCacheEntry create({
    required String key,
    required String responseBody,
    int ttlSeconds = 300, // Default 5 minutes
    String? eTag,
  }) {
    return ApiCacheEntry()
      ..key = key
      ..responseBody = responseBody
      ..cachedAt = DateTime.now().toIso8601String()
      ..ttlSeconds = ttlSeconds
      ..eTag = eTag;
  }
}
