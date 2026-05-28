import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'collections/cached_family.dart';
import 'collections/cached_person.dart';
import 'collections/cached_relationship.dart';
import 'collections/cached_profile.dart';
import 'collections/search_history_entry.dart';
import 'collections/recently_viewed_profile.dart';
import 'collections/app_settings_entry.dart';
import 'collections/pending_operation.dart';
import 'collections/api_cache_entry.dart';

/// Isar database initialization and management service.
/// Provides a singleton Isar instance configured with all collections.
class IsarDatabase {
  static Isar? _instance;

  /// Get the Isar instance. Throws if not initialized.
  static Isar get instance {
    if (_instance == null) {
      throw StateError(
        'IsarDatabase not initialized. Call IsarDatabase.initialize() first.',
      );
    }
    return _instance!;
  }

  /// Check if Isar has been initialized.
  static bool get isInitialized => _instance != null;

  /// Initialize the Isar database with all collections.
  /// Must be called before any database operations.
  /// Should be called in main() before runApp().
  static Future<void> initialize() async {
    if (_instance != null) {
      debugPrint('🔧 Isar already initialized, skipping...');
      return;
    }

    debugPrint('🔧 Initializing Isar database...');

    final dir = await getApplicationDocumentsDirectory();

    _instance = await Isar.open(
      [
        CachedFamilySchema,
        CachedPersonSchema,
        CachedRelationshipSchema,
        CachedProfileSchema,
        SearchHistoryEntrySchema,
        RecentlyViewedProfileSchema,
        AppSettingsEntrySchema,
        PendingOperationSchema,
        ApiCacheEntrySchema,
      ],
      directory: dir.path,
      inspector: kDebugMode,
    );

    debugPrint('✅ Isar database initialized successfully');
  }

  /// Close the Isar database instance.
  /// Should be called when the app is shutting down.
  static Future<void> close() async {
    if (_instance != null) {
      await _instance!.close();
      _instance = null;
      debugPrint('🔧 Isar database closed');
    }
  }

  /// Clear all cached data (useful for logout).
  /// Keeps pending operations so they can be synced later.
  static Future<void> clearCache({bool includePendingOps = false}) async {
    if (_instance == null) return;

    await _instance!.writeTxn(() async {
      await _instance!.cachedFamilys.clear();
      await _instance!.cachedPersons.clear();
      await _instance!.cachedRelationships.clear();
      await _instance!.cachedProfiles.clear();
      await _instance!.searchHistoryEntrys.clear();
      await _instance!.recentlyViewedProfiles.clear();
      await _instance!.apiCacheEntrys.clear();
      if (includePendingOps) {
        await _instance!.pendingOperations.clear();
      }
    });

    debugPrint('🔧 Isar cache cleared');
  }

  /// Clear all data including pending operations (full reset).
  static Future<void> clearAll() async {
    await clearCache(includePendingOps: true);
    await _instance!.appSettingsEntrys.clear();
  }

  /// Get cache statistics for debugging.
  static Future<Map<String, int>> getStats() async {
    if (_instance == null) return {};

    return {
      'families': await _instance!.cachedFamilys.count(),
      'persons': await _instance!.cachedPersons.count(),
      'relationships': await _instance!.cachedRelationships.count(),
      'profiles': await _instance!.cachedProfiles.count(),
      'searchHistory': await _instance!.searchHistoryEntrys.count(),
      'recentlyViewed': await _instance!.recentlyViewedProfiles.count(),
      'pendingOps': await _instance!.pendingOperations.count(),
      'apiCache': await _instance!.apiCacheEntrys.count(),
      'settings': await _instance!.appSettingsEntrys.count(),
    };
  }

  /// Prevent instantiation
  IsarDatabase._();
}

/// Riverpod provider for the Isar instance.
final isarProvider = Provider<Isar>((ref) {
  return IsarDatabase.instance;
});

/// Provider that checks if Isar is initialized.
final isIsarInitializedProvider = Provider<bool>((ref) {
  return IsarDatabase.isInitialized;
});
