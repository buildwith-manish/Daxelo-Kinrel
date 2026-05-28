import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:dio/dio.dart';

import '../isar_database.dart';
import '../collections/cached_profile.dart';
import '../collections/search_history_entry.dart';
import '../collections/api_cache_entry.dart';
import '../sync/connectivity_service.dart';
import '../sync/offline_queue.dart';
import '../../../features/profile/data/profile_provider.dart';
import '../../networking/dio_client.dart';
import '../../services/supabase_service.dart';

/// Offline-first repository for profile data.
///
/// Strategy:
/// - **Read**: Check Isar cache first. If fresh, return immediately.
///   Then silently refresh from API in the background.
/// - **Write**: Write to API first (if online). If offline, queue
///   the operation for later sync and write optimistically to Isar.
class OfflineProfileRepository {
  final Ref _ref;

  OfflineProfileRepository(this._ref);

  Isar get _isar => _ref.read(isarProvider);
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

    final cached = await _isar.cachedProfiles
        .where()
        .filter()
        .idEqualTo(userId)
        .findFirst();

    if (cached == null) return null;
    return ProfileModel.fromJson(cached.toJson());
  }

  Future<ProfileModel?> _fetchProfileFromNetwork() async {
    try {
      final response = await _dio.get('/api/users/me');
      final profile = ProfileModel.fromJson(
        response.data as Map<String, dynamic>,
      );

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

    await _isar.writeTxn(() async {
      final cached = CachedProfile.fromJson(profile.toJson());
      await _isar.cachedProfiles.put(cached);
    });
  }

  /// Update the user's profile with offline support.
  Future<bool> updateProfile(Map<String, dynamic> data) async {
    if (_isOnline) {
      try {
        final response = await _dio.patch('/api/users/me', data: data);
        final profile = ProfileModel.fromJson(
          response.data as Map<String, dynamic>,
        );
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

    // Update cache optimistically
    final cached = await _getCachedProfile();
    if (cached != null) {
      final updatedJson = cached.toJson()..addAll(data);
      final updatedProfile = ProfileModel.fromJson(updatedJson);
      await _cacheProfile(updatedProfile);
    }

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
    final cachedEntry = await _isar.apiCacheEntrys
        .where()
        .keyEqualTo('/api/users/me/stats')
        .findFirst();

    if (cachedEntry != null && cachedEntry.isFresh) {
      if (_isOnline) {
        _refreshStatsInBackground();
      }
      try {
        return UserStatsModel.fromJson(
          jsonDecode(cachedEntry.responseBody) as Map<String, dynamic>,
        );
      } catch (_) {}
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
        await _isar.writeTxn(() async {
          final entry = ApiCacheEntry.create(
            key: '/api/users/me/stats',
            responseBody: jsonEncode(response.data),
            ttlSeconds: 300, // 5 minutes
          );
          await _isar.apiCacheEntrys.put(entry);
        });
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

    await _isar.writeTxn(() async {
      // Remove duplicate entries
      final existing = await _isar.searchHistoryEntrys
          .where()
          .filter()
          .queryEqualTo(query)
          .findAll();
      for (final e in existing) {
        await _isar.searchHistoryEntrys.delete(e.isarId);
      }

      // Add new entry
      final entry = SearchHistoryEntry.create(
        query: query,
        filterType: filterType,
        resultCount: resultCount,
      );
      await _isar.searchHistoryEntrys.put(entry);

      // Keep only the last 50 entries
      final all = await _isar.searchHistoryEntrys
          .where()
          .sortBySearchedAtDesc()
          .findAll();
      if (all.length > 50) {
        for (int i = 50; i < all.length; i++) {
          await _isar.searchHistoryEntrys.delete(all[i].isarId);
        }
      }
    });
  }

  /// Get recent search history.
  Future<List<String>> getSearchHistory({int limit = 10}) async {
    if (!IsarDatabase.isInitialized) return [];

    final entries = await _isar.searchHistoryEntrys
        .where()
        .sortBySearchedAtDesc()
        .limit(limit)
        .findAll();

    return entries.map((e) => e.query).toList();
  }

  /// Clear all search history.
  Future<void> clearSearchHistory() async {
    if (!IsarDatabase.isInitialized) return;

    await _isar.writeTxn(() async {
      await _isar.searchHistoryEntrys.clear();
    });
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
