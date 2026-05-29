import 'package:flutter/foundation.dart';

import '../isar_database.dart';

/// Smart cache invalidation strategies.
/// Provides fine-grained cache invalidation to avoid stale data
/// while minimizing unnecessary data refetches.
class CacheInvalidation {
  static get _db => IsarDatabase.instance;

  /// Invalidate all cached data for a specific family.
  /// Called when a family, its members, or relationships are modified.
  static Future<void> invalidateFamily(String familyId) async {
    if (!IsarDatabase.isInitialized) return;

    // Delete the cached family
    await _db.deleteFamiliesByFamily(familyId);

    // Delete all cached persons in this family
    await _db.deletePersonsByFamily(familyId);

    // Delete all cached relationships in this family
    await _db.deleteRelationshipsByFamily(familyId);

    // Invalidate any API cache entries related to this family
    final apiEntries = await _db.getAllApiCacheEntries();
    for (final entry in apiEntries) {
      if (entry.key.contains(familyId)) {
        await _db.deleteApiCacheEntry(entry.id);
      }
    }

    debugPrint('🗑️ Invalidated cache for family: $familyId');
  }

  /// Invalidate the cached profile for a specific user.
  static Future<void> invalidateProfile(String userId) async {
    if (!IsarDatabase.isInitialized) return;

    await (IsarDatabase.instance.deletePerson(userId));

    // Invalidate API cache entries related to the user
    final apiEntries = await _db.getAllApiCacheEntries();
    for (final entry in apiEntries) {
      if (entry.key.contains('/users/me') ||
          entry.key.contains(userId)) {
        await _db.deleteApiCacheEntry(entry.id);
      }
    }

    debugPrint('🗑️ Invalidated cache for profile: $userId');
  }

  /// Invalidate the entire family list cache.
  /// Called when a new family is created or the user joins/leaves a family.
  static Future<void> invalidateFamilyList() async {
    if (!IsarDatabase.isInitialized) return;

    await _db.clearFamilies();

    // Invalidate the family list API cache
    final apiEntries = await _db.getAllApiCacheEntries();
    for (final entry in apiEntries) {
      if (entry.key.contains('/families') || entry.key.contains('family_list')) {
        await _db.deleteApiCacheEntry(entry.id);
      }
    }

    debugPrint('🗑️ Invalidated family list cache');
  }

  /// Invalidate a specific API cache entry by key pattern.
  static Future<void> invalidateApiCache(String keyPattern) async {
    if (!IsarDatabase.isInitialized) return;

    final apiEntries = await _db.getAllApiCacheEntries();
    for (final entry in apiEntries) {
      if (entry.key.contains(keyPattern)) {
        await _db.deleteApiCacheEntry(entry.id);
      }
    }

    debugPrint('🗑️ Invalidated API cache matching: $keyPattern');
  }

  /// Invalidate all cache entries older than the specified duration.
  static Future<void> invalidateStaleEntries({
    Duration familyTtl = const Duration(hours: 1),
    Duration personTtl = const Duration(hours: 1),
    Duration profileTtl = const Duration(minutes: 30),
    Duration apiTtl = const Duration(minutes: 5),
  }) async {
    if (!IsarDatabase.isInitialized) return;

    final now = DateTime.now();
    int removedCount = 0;

    // Check families
    final families = await _db.getAllFamilies();
    for (final f in families) {
      final cachedAt = DateTime.tryParse(f.cachedAt);
      if (cachedAt != null && now.difference(cachedAt) > familyTtl) {
        await (IsarDatabase.instance.deletePerson(f.id));
        removedCount++;
      }
    }

    // Check persons
    // Note: with the Drift schema, persons are stored by familyId
    // Stale entry cleanup is handled by the API cache TTL

    if (removedCount > 0) {
      debugPrint('🗑️ Removed $removedCount stale cache entries');
    }
  }
}
