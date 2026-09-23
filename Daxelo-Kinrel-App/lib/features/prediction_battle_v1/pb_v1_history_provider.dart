// lib/features/prediction_battle_v1/pb_v1_history_provider.dart
//
// Riverpod provider for the Prediction Battle v1 History screen.
// Fetches the user's win streak + last N revealed rounds for the
// family in a single RPC round-trip (`fn_pb_v1_get_history`).
// Cache-first via LocalCacheService — same pattern as pb_v1_provider.
//
// The history provider does NOT subscribe to realtime. The history
// screen shows past rounds; the current round is on the family hub
// card + the reveal screen. When a new round transitions to
// 'revealed', the next time the user opens the history screen the
// cache will be invalidated by `load(forceRefresh: true)` and the
// new round will appear. The cost of one extra RPC call on screen
// open is negligible compared to the cost of holding a realtime WS
// subscription for the entire screen lifetime.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/storage/local_cache.dart';
import 'pb_v1_history_models.dart';

class PBv1HistoryNotifier extends StateNotifier<PBv1HistoryState> {
  PBv1HistoryNotifier(this._ref, this.familyId) : super(const PBv1HistoryState());
  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;

  static const _cacheKeyPrefix = 'pb_v1_history_v2_';
  // Phase 3.4 — bumped from `pb_v1_history_` to invalidate caches that
  // were written before the leaderboard field was added to the RPC
  // response. Old caches don't have `leaderboard` and would render
  // an empty leaderboard section until the refresh completes; bumping
  // the prefix makes the first load after this update fetch fresh
  // data immediately.

  /// Load history. Renders from cache first (sub-frame), then refreshes
  /// from the backend and overwrites the cache.
  Future<void> load({bool forceRefresh = false}) async {
    if (!forceRefresh && state.loadedOnce) return;

    // 1. Cache-first render
    if (!forceRefresh) {
      final cached = await _readCache();
      if (cached != null) {
        state = state.copyWith(history: cached, isLoading: false, loadedOnce: true);
        // Fall through — still refresh from server below
      } else {
        state = state.copyWith(isLoading: true, clearError: true);
      }
    } else {
      state = state.copyWith(isLoading: !state.loadedOnce, clearError: true);
    }

    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(isLoading: false, error: 'Not signed in');
      return;
    }

    try {
      final resp = await client.rpc('fn_pb_v1_get_history', params: {
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_limit': 30,
      });
      if (resp is Map) {
        final map = Map<String, dynamic>.from(resp);
        if (map['ok'] == true) {
          final history = PBv1History.fromJson({
            ...map,
            'cachedAt': DateTime.now().toUtc().toIso8601String(),
          });
          state = state.copyWith(history: history, isLoading: false, loadedOnce: true);
          await _writeCache(history);
          return;
        }
      }
      state = state.copyWith(isLoading: false, loadedOnce: true);
    } catch (e) {
      debugPrint('[PBv1History] load error: $e');
      state = state.copyWith(isLoading: false, error: '$e', loadedOnce: true);
    }
  }

  Future<void> refresh() => load(forceRefresh: true);

  // ── Cache ──────────────────────────────────────────────────────────

  Future<PBv1History?> _readCache() async {
    try {
      final cache = _ref.read(localCacheProvider);
      final raw = await cache.getPreference<Map<String, dynamic>>(_cacheKeyPrefix + familyId);
      if (raw == null) return null;
      return PBv1History.fromJson(raw);
    } catch (e) {
      debugPrint('[PBv1History] cache read error: $e');
      return null;
    }
  }

  Future<void> _writeCache(PBv1History history) async {
    try {
      final cache = _ref.read(localCacheProvider);
      await cache.setPreference(_cacheKeyPrefix + familyId, history.toJson());
    } catch (e) {
      debugPrint('[PBv1History] cache write error: $e');
    }
  }
}

class PBv1HistoryState {
  const PBv1HistoryState({
    this.history,
    this.isLoading = false,
    this.loadedOnce = false,
    this.error,
  });

  final PBv1History? history;
  final bool isLoading;
  final bool loadedOnce;
  final String? error;

  PBv1HistoryState copyWith({
    PBv1History? history,
    bool? isLoading,
    bool? loadedOnce,
    bool clearError = false,
    String? error,
  }) => PBv1HistoryState(
    history: history ?? this.history,
    isLoading: isLoading ?? this.isLoading,
    loadedOnce: loadedOnce ?? this.loadedOnce,
    error: clearError ? null : (error ?? this.error),
  );
}

final pbV1HistoryProvider =
    StateNotifierProvider.autoDispose.family<PBv1HistoryNotifier, PBv1HistoryState, String>(
  (ref, familyId) => PBv1HistoryNotifier(ref, familyId),
);
