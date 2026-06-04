// Migrated from Hive to Drift — LocalCacheService now uses AppDatabase
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/isar_database.dart';

/// Local cache service using Drift (AppDatabase) for non-sensitive data
/// Replaces Hive boxes with UserSettings table for key-value storage
class LocalCacheService {
  Future<void> init() async {
    // Drift database is initialized via IsarDatabase.initialize() in main()
    // No additional setup needed
  }

  // ── Kinship Cache ───────────────────────────────────────────
  Future<void> cacheKinshipTerm(
    String key,
    String language,
    String term,
  ) async {
    if (!IsarDatabase.isInitialized) return;
    await IsarDatabase.instance.setSetting('kinship_${key}_$language', term);
  }

  String? getCachedKinshipTerm(String key, String language) {
    // Synchronous getter not available in Drift — return null, callers should use async version
    return null;
  }

  Future<String?> getCachedKinshipTermAsync(String key, String language) async {
    if (!IsarDatabase.isInitialized) return null;
    return IsarDatabase.instance.getSetting('kinship_${key}_$language');
  }

  // ── Preferences ─────────────────────────────────────────────
  Future<void> setPreference(String key, dynamic value) async {
    if (!IsarDatabase.isInitialized) return;
    await IsarDatabase.instance.setSetting('pref_$key', jsonEncode(value));
  }

  Future<T?> getPreference<T>(String key) async {
    if (!IsarDatabase.isInitialized) return null;
    final raw = await IsarDatabase.instance.getSetting('pref_$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as T?;
    } catch (_) {
      return raw as T?;
    }
  }

  // ── Family Cache ────────────────────────────────────────────
  Future<void> cacheFamilyData(
    String familyId,
    Map<String, dynamic> data,
  ) async {
    if (!IsarDatabase.isInitialized) return;
    await IsarDatabase.instance.setSetting('family_$familyId', jsonEncode(data));
  }

  Future<Map<String, dynamic>?> getCachedFamilyData(String familyId) async {
    if (!IsarDatabase.isInitialized) return null;
    final raw = await IsarDatabase.instance.getSetting('family_$familyId');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearFamilyCache() async {
    // Would need a custom query to delete settings by prefix
    // For now, clear all cache via IsarDatabase
    await IsarDatabase.clearCache();
  }

  // ── Search Cache ───────────────────────────────────────────
  Future<void> saveRecentSearch(String query) async {
    if (!IsarDatabase.isInitialized) return;
    final raw = await IsarDatabase.instance.getSetting('recent_searches');
    final List<String> searches = raw != null
        ? List<String>.from(jsonDecode(raw) as List)
        : <String>[];
    searches.remove(query);
    searches.insert(0, query);
    if (searches.length > 5) {
      searches.removeRange(5, searches.length);
    }
    await IsarDatabase.instance.setSetting('recent_searches', jsonEncode(searches));
  }

  Future<List<String>> getRecentSearches() async {
    if (!IsarDatabase.isInitialized) return [];
    final raw = await IsarDatabase.instance.getSetting('recent_searches');
    if (raw == null) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  Future<void> removeRecentSearch(String query) async {
    if (!IsarDatabase.isInitialized) return;
    final raw = await IsarDatabase.instance.getSetting('recent_searches');
    final List<String> searches = raw != null
        ? List<String>.from(jsonDecode(raw) as List)
        : <String>[];
    searches.remove(query);
    await IsarDatabase.instance.setSetting('recent_searches', jsonEncode(searches));
  }

  Future<void> clearRecentSearches() async {
    if (!IsarDatabase.isInitialized) return;
    await IsarDatabase.instance.setSetting('recent_searches', jsonEncode(<String>[]));
  }

  // ── Clear All ───────────────────────────────────────────────
  Future<void> clearAll() async {
    await IsarDatabase.clearCache();
  }
}

final localCacheProvider = Provider<LocalCacheService>((ref) {
  return LocalCacheService();
});
