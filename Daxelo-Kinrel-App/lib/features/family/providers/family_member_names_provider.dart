// lib/features/family/providers/family_member_names_provider.dart
//
// Shared family-member-names provider — caches a userId → display
// name map per family in LocalCacheService. Used by the prediction
// reveal screen, the prediction history screen, and the moments
// feed screen so they all share the same lookup + cache.
//
// Why this exists (Phase 3.20)
//   Before: each of the three prediction screens independently called
//   `client.from('FamilyMember').select('userId, user:User(name)')
//   .eq('familyId', familyId)` in their initState. On a slow network,
//   the lookup would still be in-flight when the screen rendered, so
//   the ranked-guess list showed UUID prefixes ("a1b2c3d4") instead
//   of names. The user would see "🥇 a1b2c3d4" for ~500ms before the
//   names loaded.
//
//   After: the provider fetches the names once + caches them. The
//   three screens read from the provider's state, which is pre-
//   populated from the cache on cold open (sub-frame). The first
//   screen to open triggers the refresh; subsequent screens see the
//   cached names immediately.
//
// Cache invalidation
//   The cache is keyed by `family_member_names_<familyId>`. There's
//   no explicit invalidation — the names are stable enough that a
//   stale cache is fine for the screen's lifetime. If a family
//   member changes their name, the next app restart picks it up
//   (the cache is overwritten on the next load()). For a more
//   aggressive invalidation, we could subscribe to FamilyMember
//   realtime changes — but that's overkill for this use case.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/storage/local_cache.dart';

class FamilyMemberNamesNotifier extends StateNotifier<FamilyMemberNamesState> {
  FamilyMemberNamesNotifier(this._ref, this.familyId)
      : super(const FamilyMemberNamesState());
  final Ref _ref;
  final String familyId;

  static const _cacheKeyPrefix = 'family_member_names_';

  /// Load the name map. Cache-first — if the cache has data, populate
  /// the state immediately, then refresh from the server in the
  /// background. If the cache is empty, show loading + fetch.
  Future<void> load({bool forceRefresh = false}) async {
    if (!forceRefresh && state.loadedOnce) return;

    // 1. Cache-first
    if (!forceRefresh) {
      final cached = await _readCache();
      if (cached != null) {
        state = FamilyMemberNamesState(names: cached, loadedOnce: true);
        // Fall through — still refresh from server below.
      }
    }

    final client = _ref.read(supabaseProvider);
    if (client == null) return;
    try {
      final rows = await client
          .from('FamilyMember')
          .select('userId, user:User(name)')
          .eq('familyId', familyId);
      final map = <String, String>{};
      for (final r in (rows as List)) {
        final row = r as Map<String, dynamic>;
        final uid = (row['userId'] ?? '') as String;
        if (uid.isEmpty) continue;
        final user = row['user'];
        String name = uid.substring(0, 8); // fallback to UUID prefix
        if (user is Map && user['name'] is String && (user['name'] as String).isNotEmpty) {
          name = user['name'] as String;
        }
        map[uid] = name;
      }
      state = FamilyMemberNamesState(names: map, loadedOnce: true);
      await _writeCache(map);
    } catch (e) {
      debugPrint('[FamilyMemberNames] load error: $e');
      // Don't clear the cache on error — the stale cache is better
      // than nothing. Just mark loadedOnce so we don't retry on
      // every rebuild.
      if (!state.loadedOnce) {
        state = const FamilyMemberNamesState(loadedOnce: true);
      }
    }
  }

  /// Get a name for a userId, with a UUID-prefix fallback if the map
  /// doesn't have it (e.g., a family member who joined after the
  /// last cache).
  String nameFor(String userId) {
    return state.names[userId] ?? userId.substring(0, 8);
  }

  Future<Map<String, String>?> _readCache() async {
    try {
      final cache = _ref.read(localCacheProvider);
      final raw = await cache.getPreference<Map<String, dynamic>>(
        _cacheKeyPrefix + familyId,
      );
      if (raw == null) return null;
      // The cache stores the map as a JSON object — convert back.
      return raw.map((k, v) => MapEntry(k, v as String));
    } catch (e) {
      debugPrint('[FamilyMemberNames] cache read error: $e');
      return null;
    }
  }

  Future<void> _writeCache(Map<String, String> names) async {
    try {
      final cache = _ref.read(localCacheProvider);
      // LocalCacheService.setPreference stores the value as JSON via
      // jsonEncode. A Map<String,String> serializes cleanly.
      await cache.setPreference(_cacheKeyPrefix + familyId, names);
    } catch (e) {
      debugPrint('[FamilyMemberNames] cache write error: $e');
    }
  }
}

class FamilyMemberNamesState {
  const FamilyMemberNamesState({
    this.names = const {},
    this.loadedOnce = false,
  });
  final Map<String, String> names;
  final bool loadedOnce;
}

final familyMemberNamesProvider = StateNotifierProvider.autoDispose
    .family<FamilyMemberNamesNotifier, FamilyMemberNamesState, String>(
  (ref, familyId) => FamilyMemberNamesNotifier(ref, familyId),
);
