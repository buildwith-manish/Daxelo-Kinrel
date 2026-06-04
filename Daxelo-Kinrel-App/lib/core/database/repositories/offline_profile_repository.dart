import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../isar_database.dart';
import '../app_database.dart';
import '../sync/connectivity_service.dart';
import '../sync/offline_queue.dart';
import '../../../features/profile/data/profile_provider.dart';
import '../../networking/dio_client.dart';
import '../../services/supabase_service.dart';

/// Offline-first repository for profile data.
///
/// Strategy:
/// - **Read**: Check Drift cache first. If fresh, return immediately.
///   Then silently refresh from API in the background.
/// - **Write**: Write to API first (if online). If offline, queue
///   the operation for later sync and write optimistically to Drift.
class OfflineProfileRepository {
  final Ref _ref;

  OfflineProfileRepository(this._ref);

  AppDatabase get _db => _ref.read(isarProvider);
  Dio get _dio => _ref.read(dioProvider);
  bool get _isOnline => _ref.read(connectivityServiceProvider).isOnline;

  // ── Profile ─────────────────────────────────────────────────────

  /// Get the current user's profile.
  /// Returns cached data immediately if available, then refreshes in background.
  Future<ProfileModel?> getProfile() async {
    if (!IsarDatabase.isInitialized) return _fetchProfileFromNetwork();

    // Try cache first
    final cached = await _getCachedProfile();
    if (cached != null) {
      // Return cached data immediately, refresh in background
      if (_isOnline) {
        _refreshProfileInBackground();
      }
      return cached;
    }

    // No cache — must fetch from network
    return _fetchProfileFromNetwork();
  }

  Future<ProfileModel?> _getCachedProfile() async {
    final userId = _getCurrentUserId();
    if (userId == null) return null;

    final row = await _db.getProfile(userId);
    if (row == null) return null;
    final data = jsonDecode(row.data) as Map<String, dynamic>;
    return ProfileModel.fromJson(data);
  }

  Future<ProfileModel?> _fetchProfileFromNetwork() async {
    try {
      final response = await _dio.get('/api/users/me');
      final data = response.data as Map<String, dynamic>;
      // Backend returns { "user": { ... } }, unwrap the user object
      final userData = data.containsKey('user') && data['user'] is Map
          ? (data['user'] as Map).cast<String, dynamic>()
          : data;
      final profile = ProfileModel.fromJson(userData);

      // Cache the result
      await _cacheProfile(profile);

      return profile;
    } on DioException catch (e) {
      debugPrint('⚠️ fetchProfile network error: ${e.message}');

      // If offline, try cache as fallback
      if (!_isOnline) {
        return _getCachedProfile();
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ fetchProfile error: $e');
      return null;
    }
  }

  void _refreshProfileInBackground() {
    _fetchProfileFromNetwork().catchError((e) {
      debugPrint('⚠️ Background profile refresh failed: $e');
      return null;
    });
  }

  Future<void> _cacheProfile(ProfileModel profile) async {
    if (!IsarDatabase.isInitialized) return;

    await _db.upsertProfile(CachedProfilesCompanion(
      id: Value(profile.id),
      familyId: const Value(''),
      data: Value(jsonEncode(profile.toJson())),
      cachedAt: Value(DateTime.now()),
    ));
  }

  /// Update the user's profile with offline support.
  Future<bool> updateProfile(Map<String, dynamic> data) async {
    if (_isOnline) {
      try {
        final response = await _dio.patch('/api/users/me', data: data);
        final respData = response.data as Map<String, dynamic>;
        // Backend returns { "user": { ... } }, unwrap the user object
        final userData = respData.containsKey('user') && respData['user'] is Map
            ? (respData['user'] as Map).cast<String, dynamic>()
            : respData;
        final profile = ProfileModel.fromJson(userData);
        await _cacheProfile(profile);
        return true;
      } on DioException catch (e) {
        if (_isNetworkError(e.toString())) {
          // Queue for later sync + update cache optimistically
          await _updateProfileOffline(data);
          return true;
        }
        debugPrint('⚠️ updateProfile error: ${e.message}');
        return false;
      }
    } else {
      // Offline — update cache optimistically and queue
      return _updateProfileOffline(data);
    }
  }

  Future<bool> _updateProfileOffline(Map<String, dynamic> data) async {
    final userId = _getCurrentUserId();
    if (userId == null) return false;

    // Queue for sync
    await _ref.read(offlineQueueProvider).enqueue(
          operationType: 'update',
          collection: 'User',
          recordId: userId,
          payload: data,
          priority: 0, // High priority — profile updates are important
        );

    return true;
  }

  // ── Stats ───────────────────────────────────────────────────────

  /// Get user stats with caching.
  Future<UserStatsModel?> getStats() async {
    if (!IsarDatabase.isInitialized) return _fetchStatsFromNetwork();

    // Try API cache first
    final cachedEntry = await _db.getApiCacheEntry('/api/users/me/stats');

    if (cachedEntry != null) {
      final cachedTime = cachedEntry.cachedAt;
      final expiresAt = cachedTime.add(Duration(seconds: cachedEntry.ttlSeconds));
      final isFresh = DateTime.now().isBefore(expiresAt);

      if (isFresh) {
        if (_isOnline) {
          _refreshStatsInBackground();
        }
        try {
          return UserStatsModel.fromJson(
            jsonDecode(cachedEntry.responseBody) as Map<String, dynamic>,
          );
        } catch (_) {}
      }
    }

    return _fetchStatsFromNetwork();
  }

  Future<UserStatsModel?> _fetchStatsFromNetwork() async {
    try {
      final response = await _dio.get('/api/users/me/stats');
      final stats = UserStatsModel.fromJson(
        response.data as Map<String, dynamic>,
      );

      // Cache the result
      if (IsarDatabase.isInitialized) {
        await _db.upsertApiCacheEntry(ApiCacheEntriesCompanion(
          key: const Value('/api/users/me/stats'),
          responseBody: Value(jsonEncode(response.data)),
          cachedAt: Value(DateTime.now()),
          ttlSeconds: const Value(300), // 5 minutes
        ));
      }

      return stats;
    } catch (e) {
      debugPrint('⚠️ getStats error: $e');

      // Try Supabase fallback
      return _loadStatsFromSupabase();
    }
  }

  void _refreshStatsInBackground() {
    _fetchStatsFromNetwork().catchError((e) {
      debugPrint('⚠️ Background stats refresh failed: $e');
      return null;
    });
  }

  Future<UserStatsModel?> _loadStatsFromSupabase() async {
    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return null;

      final userId = client.auth.currentUser?.id;
      if (userId == null) return null;

      final familyMembers = await client
          .from('FamilyMember')
          .select('id')
          .eq('userId', userId);

      int personCount = 0;
      int relationshipCount = 0;

      try {
        final familyIds = (familyMembers as List)
            .map((row) => row['familyId'] as String)
            .toSet();
        if (familyIds.isNotEmpty) {
          final persons = await client
              .from('Person')
              .select('id')
              .inFilter('familyId', familyIds.toList());
          personCount = (persons as List).length;

          final relationships = await client
              .from('Relationship')
              .select('id')
              .inFilter('familyId', familyIds.toList());
          relationshipCount = (relationships as List).length;
        }
      } catch (e) {
        debugPrint('⚠️ Supabase stats fallback error: $e');
      }

      return UserStatsModel(
        familyTrees: (familyMembers as List).length,
        membersAdded: personCount,
        relations: relationshipCount,
      );
    } catch (e) {
      debugPrint('⚠️ loadStatsFromSupabase error: $e');
      return null;
    }
  }

  // ── Search History ──────────────────────────────────────────────

  /// Save a search query to history.
  Future<void> saveSearchHistory({
    required String query,
    String filterType = 'all',
    int resultCount = 0,
  }) async {
    if (!IsarDatabase.isInitialized) return;

    // Remove duplicate entries
    await _db.deleteSearchHistoryByQuery(query);

    // Add new entry
    await _db.upsertSearchHistory(SearchHistoryEntriesCompanion(
      query: Value(query),
      searchedAt: Value(DateTime.now()),
      filterType: Value(filterType),
      resultCount: Value(resultCount),
    ));
  }

  /// Get recent search history.
  Future<List<String>> getSearchHistory({int limit = 10}) async {
    if (!IsarDatabase.isInitialized) return [];

    final entries = await _db.getSearchHistory(limit: limit);

    return entries.map((e) => e.query).toList();
  }

  /// Clear all search history.
  Future<void> clearSearchHistory() async {
    if (!IsarDatabase.isInitialized) return;

    await _db.clearSearchHistory();
  }

  // ── Helpers ─────────────────────────────────────────────────────

  String? _getCurrentUserId() {
    try {
      final client = _ref.read(supabaseProvider);
      return client?.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  bool _isNetworkError(String errStr) {
    return errStr.contains('SocketException') ||
        errStr.contains('Failed host lookup') ||
        errStr.contains('Connection refused') ||
        errStr.contains('Network is unreachable') ||
        errStr.contains('Connection timed out') ||
        errStr.contains('TimeoutException');
  }
}

/// Riverpod provider for the OfflineProfileRepository.
final offlineProfileRepositoryProvider =
    Provider<OfflineProfileRepository>((ref) {
  return OfflineProfileRepository(ref);
});
