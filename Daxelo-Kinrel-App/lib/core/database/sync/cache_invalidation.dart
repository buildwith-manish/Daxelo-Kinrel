import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import '../isar_database.dart';
import '../collections/cached_family.dart';
import '../collections/cached_person.dart';
import '../collections/cached_relationship.dart';
import '../collections/cached_profile.dart';
import '../collections/api_cache_entry.dart';

/// Smart cache invalidation strategies.
/// Provides fine-grained cache invalidation to avoid stale data
/// while minimizing unnecessary data refetches.
class CacheInvalidation {
  static Isar get _isar => IsarDatabase.instance;

  /// Invalidate all cached data for a specific family.
  /// Called when a family, its members, or relationships are modified.
  static Future<void> invalidateFamily(String familyId) async {
    if (!IsarDatabase.isInitialized) return;

    await _isar.writeTxn(() async {
      // Delete the cached family
      final family = await _isar.cachedFamilys
          .where()
          .filter()
          .idEqualTo(familyId)
          .findFirst();
      if (family != null) {
        await _isar.cachedFamilys.delete(family.isarId);
      }

      // Delete all cached persons in this family
      final persons = await _isar.cachedPersons
          .where()
          .filter()
          .familyIdEqualTo(familyId)
          .findAll();
      for (final person in persons) {
        await _isar.cachedPersons.delete(person.isarId);
      }

      // Delete all cached relationships in this family
      final relationships = await _isar.cachedRelationships
          .where()
          .filter()
          .familyIdEqualTo(familyId)
          .findAll();
      for (final rel in relationships) {
        await _isar.cachedRelationships.delete(rel.isarId);
      }

      // Invalidate any API cache entries related to this family
      final apiEntries = await _isar.apiCacheEntrys.where().findAll();
      for (final entry in apiEntries) {
        if (entry.key.contains(familyId)) {
          await _isar.apiCacheEntrys.delete(entry.isarId);
        }
      }
    });

    debugPrint('🗑️ Invalidated cache for family: $familyId');
  }

  /// Invalidate the cached profile for a specific user.
  static Future<void> invalidateProfile(String userId) async {
    if (!IsarDatabase.isInitialized) return;

    await _isar.writeTxn(() async {
      final profile = await _isar.cachedProfiles
          .where()
          .filter()
          .idEqualTo(userId)
          .findFirst();
      if (profile != null) {
        await _isar.cachedProfiles.delete(profile.isarId);
      }

      // Invalidate API cache entries related to the user
      final apiEntries = await _isar.apiCacheEntrys.where().findAll();
      for (final entry in apiEntries) {
        if (entry.key.contains('/users/me') ||
            entry.key.contains(userId)) {
          await _isar.apiCacheEntrys.delete(entry.isarId);
        }
      }
    });

    debugPrint('🗑️ Invalidated cache for profile: $userId');
  }

  /// Invalidate the entire family list cache.
  /// Called when a new family is created or the user joins/leaves a family.
  static Future<void> invalidateFamilyList() async {
    if (!IsarDatabase.isInitialized) return;

    await _isar.writeTxn(() async {
      await _isar.cachedFamilys.clear();

      // Invalidate the family list API cache
      final apiEntries = await _isar.apiCacheEntrys.where().findAll();
      for (final entry in apiEntries) {
        if (entry.key.contains('/families') || entry.key.contains('family_list')) {
          await _isar.apiCacheEntrys.delete(entry.isarId);
        }
      }
    });

    debugPrint('🗑️ Invalidated family list cache');
  }

  /// Invalidate a specific API cache entry by key pattern.
  static Future<void> invalidateApiCache(String keyPattern) async {
    if (!IsarDatabase.isInitialized) return;

    await _isar.writeTxn(() async {
      final apiEntries = await _isar.apiCacheEntrys.where().findAll();
      for (final entry in apiEntries) {
        if (entry.key.contains(keyPattern)) {
          await _isar.apiCacheEntrys.delete(entry.isarId);
        }
      }
    });

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

    await _isar.writeTxn(() async {
      // Check families
      final families = await _isar.cachedFamilys.where().findAll();
      for (final f in families) {
        final cachedAt = DateTime.tryParse(f.cachedAt);
        if (cachedAt != null && now.difference(cachedAt) > familyTtl) {
          await _isar.cachedFamilys.delete(f.isarId);
          removedCount++;
        }
      }

      // Check persons
      final persons = await _isar.cachedPersons.where().findAll();
      for (final p in persons) {
        final cachedAt = DateTime.tryParse(p.cachedAt);
        if (cachedAt != null && now.difference(cachedAt) > personTtl) {
          await _isar.cachedPersons.delete(p.isarId);
          removedCount++;
        }
      }

      // Check profiles
      final profiles = await _isar.cachedProfiles.where().findAll();
      for (final p in profiles) {
        final cachedAt = DateTime.tryParse(p.cachedAt);
        if (cachedAt != null && now.difference(cachedAt) > profileTtl) {
          await _isar.cachedProfiles.delete(p.isarId);
          removedCount++;
        }
      }
    });

    if (removedCount > 0) {
      debugPrint('🗑️ Removed $removedCount stale cache entries');
    }
  }
}
