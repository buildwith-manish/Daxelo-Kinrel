import 'package:hive/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local cache service using Hive for non-sensitive data
class LocalCacheService {
  late Box _kinshipBox;
  late Box _preferencesBox;
  late Box _familyBox;
  late Box _searchBox;

  Future<void> init() async {
    _kinshipBox = await Hive.openBox('kinship_cache');
    _preferencesBox = await Hive.openBox('preferences');
    _familyBox = await Hive.openBox('family_cache');
    _searchBox = await Hive.openBox('search_cache');
  }

  // ── Kinship Cache ───────────────────────────────────────────
  Future<void> cacheKinshipTerm(
    String key,
    String language,
    String term,
  ) async {
    await _kinshipBox.put('${key}_$language', term);
  }

  String? getCachedKinshipTerm(String key, String language) {
    return _kinshipBox.get('${key}_$language') as String?;
  }

  // ── Preferences ─────────────────────────────────────────────
  Future<void> setPreference(String key, dynamic value) async {
    await _preferencesBox.put(key, value);
  }

  T? getPreference<T>(String key) {
    return _preferencesBox.get(key) as T?;
  }

  // ── Family Cache ────────────────────────────────────────────
  Future<void> cacheFamilyData(
    String familyId,
    Map<String, dynamic> data,
  ) async {
    await _familyBox.put(familyId, data);
  }

  Map<String, dynamic>? getCachedFamilyData(String familyId) {
    return _familyBox.get(familyId) as Map<String, dynamic>?;
  }

  Future<void> clearFamilyCache() async {
    await _familyBox.clear();
  }

  // ── Search Cache ───────────────────────────────────────────
  Future<void> saveRecentSearch(String query) async {
    final List<String> searches = List<String>.from(
      _searchBox.get('recent_searches', defaultValue: []) as List,
    );
    searches.remove(query);
    searches.insert(0, query);
    if (searches.length > 5) {
      searches.removeRange(5, searches.length);
    }
    await _searchBox.put('recent_searches', searches);
  }

  List<String> getRecentSearches() {
    return List<String>.from(
      _searchBox.get('recent_searches', defaultValue: []) as List,
    );
  }

  Future<void> removeRecentSearch(String query) async {
    final List<String> searches = List<String>.from(
      _searchBox.get('recent_searches', defaultValue: []) as List,
    );
    searches.remove(query);
    await _searchBox.put('recent_searches', searches);
  }

  Future<void> clearRecentSearches() async {
    await _searchBox.put('recent_searches', <String>[]);
  }

  // ── Clear All ───────────────────────────────────────────────
  Future<void> clearAll() async {
    await _kinshipBox.clear();
    await _preferencesBox.clear();
    await _familyBox.clear();
    await _searchBox.clear();
  }
}

final localCacheProvider = Provider<LocalCacheService>((ref) {
  return LocalCacheService();
});
