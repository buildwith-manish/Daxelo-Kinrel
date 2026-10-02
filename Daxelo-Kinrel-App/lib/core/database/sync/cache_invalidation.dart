import 'package:flutter/foundation.dart';
import 'package:kinrel/core/database/app_database.dart';

import '../isar_database.dart';

/// Smart cache invalidation strategies.
/// Provides fine-grained cache invalidation to avoid stale data
/// while minimizing unnecessary data refetches.
class CacheInvalidation {
  static AppDatabase get _db => IsarDatabase.instance;

  /// Invalidate all cached data for a specific family.
  /// Called when a family, its members, or relationships are modified.
  static Future<void> invalidateFamily(String familyId) async {
    if (!IsarDatabase.isInitialized) return;

    // Delete the cached family
    await _db.deleteFamily(familyId);

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

    await _db.deleteProfile(userId);

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
}
