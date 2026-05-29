import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import 'app_database.dart';

// Import + Export all collection data classes (now plain Dart classes)
import 'collections/cached_family.dart';
import 'collections/cached_person.dart';
import 'collections/cached_relationship.dart';
import 'collections/cached_profile.dart';
import 'collections/search_history_entry.dart';
import 'collections/recently_viewed_profile.dart';
import 'collections/app_settings_entry.dart';
import 'collections/pending_operation.dart';
import 'collections/api_cache_entry.dart';

export 'collections/cached_family.dart';
export 'collections/cached_person.dart';
export 'collections/cached_relationship.dart';
export 'collections/cached_profile.dart';
export 'collections/search_history_entry.dart';
export 'collections/recently_viewed_profile.dart';
export 'collections/app_settings_entry.dart';
export 'collections/pending_operation.dart';
export 'collections/api_cache_entry.dart';

/// Database initialization and management service.
/// Provides a singleton AppDatabase instance (migrated from Isar to Drift).
class IsarDatabase {
  static AppDatabase? _instance;

  /// Get the AppDatabase instance. Throws if not initialized.
  static AppDatabase get instance {
    if (_instance == null) {
      throw StateError(
        'IsarDatabase not initialized. Call IsarDatabase.initialize() first.',
      );
    }
    return _instance!;
  }

  /// Check if the database has been initialized.
  static bool get isInitialized => _instance != null;

  /// Initialize the database with all tables.
  /// Must be called before any database operations.
  /// Should be called in main() before runApp().
  static Future<void> initialize() async {
    if (_instance != null) {
      debugPrint('🔧 Database already initialized, skipping...');
      return;
    }

    debugPrint('🔧 Initializing Drift database...');

    _instance = AppDatabase();

    debugPrint('✅ Drift database initialized successfully');
  }

  /// Close the database instance.
  /// Should be called when the app is shutting down.
  static Future<void> close() async {
    if (_instance != null) {
      await _instance!.close();
      _instance = null;
      debugPrint('🔧 Database closed');
    }
  }

  /// Clear all cached data (useful for logout).
  /// Keeps pending operations so they can be synced later.
  static Future<void> clearCache({bool includePendingOps = false}) async {
    if (_instance == null) return;

    await _instance!.clearAllCache();
    if (includePendingOps) {
      await _instance!.clearPendingOperations();
    }

    debugPrint('🔧 Database cache cleared');
  }

  /// Clear all data including pending operations (full reset).
  static Future<void> clearAll() async {
    await _instance!.clearAll();
  }

  /// Get cache statistics for debugging.
  static Future<Map<String, int>> getStats() async {
    if (_instance == null) return {};
    return _instance!.getStats();
  }

  /// Prevent instantiation
  IsarDatabase._();
}

/// Riverpod provider for the AppDatabase instance.
final isarProvider = Provider<AppDatabase>((ref) {
  return IsarDatabase.instance;
});

/// Provider that checks if the database is initialized.
final isIsarInitializedProvider = Provider<bool>((ref) {
  return IsarDatabase.isInitialized;
});
