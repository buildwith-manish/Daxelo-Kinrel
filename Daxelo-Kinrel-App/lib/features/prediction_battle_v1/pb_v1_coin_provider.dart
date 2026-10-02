// lib/features/prediction_battle_v1/pb_v1_coin_provider.dart
//
// Riverpod provider for the coin economy Flutter UI. Fetches the
// user's balance + history in a single load() call (two parallel
// RPCs) and caches the result via LocalCacheService — same pattern
// as pb_v1_provider and pb_v1_history_provider.
//
// The coin provider does NOT subscribe to realtime. Balance changes
// happen on the 9 PM IST reveal tick (server-side), and the Flutter
// client refreshes on screen open. The cost of one extra RPC per
// screen open is negligible compared to holding a WS subscription.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/storage/local_cache.dart';
import 'pb_v1_coin_models.dart';

class PBv1CoinNotifier extends StateNotifier<PBv1CoinState> {
  PBv1CoinNotifier(this._ref, this.familyId) : super(const PBv1CoinState());
  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;

  static const _cacheKeyPrefix = 'pb_v1_coin_v1_';

  /// Load balance + history in parallel (two RPCs at once — saves a
  /// round-trip vs. sequential awaits). Cache-first via
  /// LocalCacheService, same pattern as pb_v1_provider.
  Future<void> load({bool forceRefresh = false}) async {
    if (!forceRefresh && state.loadedOnce) return;

    // 1. Cache-first render
    if (!forceRefresh) {
      final cached = await _readCache();
      if (cached != null) {
        state = state.copyWith(history: cached, isLoading: false, loadedOnce: true);
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
      // Fire both RPCs in parallel — saves ~150ms vs sequential.
      final results = await Future.wait([
        client.rpc('fn_get_coin_balance', params: {
          'p_user_id': myId,
          'p_family_id': familyId,
        }),
        client.rpc('fn_get_coin_history', params: {
          'p_user_id': myId,
          'p_family_id': familyId,
          'p_limit': 50,
          'p_offset': 0,
        }),
      ]);

      final balanceResp = results[0] is Map ? Map<String, dynamic>.from(results[0] as Map) : <String, dynamic>{};
      final historyResp = results[1] is Map ? Map<String, dynamic>.from(results[1] as Map) : <String, dynamic>{};

      if (balanceResp['ok'] == true && historyResp['ok'] == true) {
        final balance = PBv1CoinBalance.fromJson(balanceResp);
        final history = PBv1CoinHistory(
          balance: balance,
          rows: (historyResp['rows'] as List? ?? const [])
              .whereType<Map>()
              .map((r) => PBv1CoinHistoryEntry.fromJson(Map<String, dynamic>.from(r)))
              .toList(),
          cachedAt: DateTime.now().toUtc().toIso8601String(),
        );
        state = state.copyWith(history: history, isLoading: false, loadedOnce: true);
        await _writeCache(history);
        return;
      }
      state = state.copyWith(isLoading: false, loadedOnce: true);
    } catch (e) {
      debugPrint('[PBv1Coin] load error: $e');
      state = state.copyWith(isLoading: false, error: '$e', loadedOnce: true);
    }
  }

  Future<void> refresh() => load(forceRefresh: true);

  // ── Cache ──────────────────────────────────────────────────────────

  Future<PBv1CoinHistory?> _readCache() async {
    try {
      final cache = _ref.read(localCacheProvider);
      final raw = await cache.getPreference<Map<String, dynamic>>(_cacheKeyPrefix + familyId);
      if (raw == null) return null;
      return PBv1CoinHistory.fromJson(raw);
    } catch (e) {
      debugPrint('[PBv1Coin] cache read error: $e');
      return null;
    }
  }

  Future<void> _writeCache(PBv1CoinHistory history) async {
    try {
      final cache = _ref.read(localCacheProvider);
      await cache.setPreference(_cacheKeyPrefix + familyId, history.toJson());
    } catch (e) {
      debugPrint('[PBv1Coin] cache write error: $e');
    }
  }
}

class PBv1CoinState {
  const PBv1CoinState({
    this.history,
    this.isLoading = false,
    this.loadedOnce = false,
    this.error,
  });

  final PBv1CoinHistory? history;
  final bool isLoading;
  final bool loadedOnce;
  final String? error;

  PBv1CoinState copyWith({
    PBv1CoinHistory? history,
    bool? isLoading,
    bool? loadedOnce,
    bool clearError = false,
    String? error,
  }) => PBv1CoinState(
    history: history ?? this.history,
    isLoading: isLoading ?? this.isLoading,
    loadedOnce: loadedOnce ?? this.loadedOnce,
    error: clearError ? null : (error ?? this.error),
  );
}

final pbV1CoinProvider =
    StateNotifierProvider.autoDispose.family<PBv1CoinNotifier, PBv1CoinState, String>(
  (ref, familyId) => PBv1CoinNotifier(ref, familyId),
);
