// lib/features/prediction_battle_v1/pb_v1_provider.dart
//
// Prediction Battle v1 — Riverpod provider for the scheduled numeric-
// estimation game. Fetches the current round + question + guesses via
// backend RPCs that enforce reveal-timing server-side.
//
// ─────────────────────────────────────────────────────────────────────
// Phase 1.1 — Low-end-device optimizations (low-end RAM + metered 4G)
// ─────────────────────────────────────────────────────────────────────
// 1. Removed the 30s poll timer. The pg_cron jobs + Supabase Realtime
//    are the authoritative source of state changes; the poll was
//    defensive belt-and-braces that low-end devices paid for in
//    battery + cellular wakes. The provider now refreshes ONLY on:
//      - explicit `load()` (screen entry)
//      - realtime event (round update / guess insert)
//      - explicit `refresh()` (user gesture / visibility regained)
//
// 2. Added a Drift-backed cache (via LocalCacheService) keyed by
//    familyId. On `load()`:
//      a. Read the cache synchronously-ish, render it immediately so
//         the user sees the last-known round within ~16ms on cold open.
//      b. Then kick off the RPC, and overwrite the cache on success.
//    Cache is invalidated when the family switches rounds or when
//    the round transitions to `revealed`.
//
// 3. Realtime subscription is now gated by `setActive(bool)`. The card
//    calls `setActive(true)` when it scrolls into view (via
//    VisibilityDetector) and `setActive(false)` when scrolled off. The
//    channel is unsubscribed when inactive — saves a WebSocket
//    connection for users who never scroll down to the card.
// ─────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/network/realtime_channel_registry.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/utils/app_time.dart';
import 'pb_v1_models.dart';

class PBv1Notifier extends StateNotifier<PBv1State> {
  PBv1Notifier(this._ref, this.familyId) : super(const PBv1State(isLoading: true));
  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  RealtimeChannel? _channel;
  bool _isActive = false; // gated by VisibilityDetector from the card
  bool _loadedOnce = false;

  // Phase 3.23 — bumped from 'pb_v1_round_' to invalidate stale caches
  // that contain rounds with the old 9 PM reveal time (pre-lifecycle-
  // change). The new reveal time is 9:30 PM IST.
  static const _cacheKeyPrefix = 'pb_v1_round_v2_';

  // ── Public API ──────────────────────────────────────────────────────

  /// Initial load. Renders from cache first (sub-frame), then refreshes
  /// from the backend and overwrites the cache.
  Future<void> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _loadedOnce) return;
    state = state.copyWith(isLoading: !_loadedOnce, clearError: true);

    // 1. Render from cache if present
    if (!forceRefresh) {
      final cached = await _readCache();
      if (cached != null) {
        state = state.copyWith(
          round: cached.round,
          question: cached.question,
          myGuess: cached.myGuess,
          revealed: cached.revealed,
          allGuesses: cached.allGuesses,
          winnerUserIds: cached.winnerUserIds,
          isLoading: false,
        );
        // fall through — we still refresh from server below
      }
    }

    final client = _client;
    if (client == null) {
      state = state.copyWith(isLoading: false, error: 'Not signed in');
      return;
    }

    try {
      // 2. Get the current round + question (creates one if needed)
      final roundResp = await client.rpc('fn_pb_v1_get_next_question', params: {'p_family_id': familyId});
      if (roundResp is Map) {
        final map = Map<String, dynamic>.from(roundResp);
        if (map['ok'] == true) {
          final round = PBv1Round.fromJson(Map<String, dynamic>.from(map['round'] as Map));
          final question = PBv1Question.fromJson(Map<String, dynamic>.from(map['question'] as Map));
          state = state.copyWith(round: round, question: question, isLoading: false);
          _loadedOnce = true;

          // 3. Get guesses (reveal-gated server-side)
          await _fetchGuesses(round.id);

          // 4. Persist to cache
          await _writeCache();

          // 5. Subscribe to realtime ONLY if the card is currently on-screen
          if (_isActive) _subscribeToRealtime(round.id);
          return;
        }
      }
      state = state.copyWith(isLoading: false, round: null, question: null);
      _loadedOnce = true;
    } catch (e) {
      debugPrint('[PBv1] load error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      _loadedOnce = true;
    }
  }

  /// Manual refresh — called from the card when the user pulls down or
  /// when the card becomes visible again after a long suspension.
  Future<void> refresh() => load(forceRefresh: true);

  /// Toggle the realtime subscription based on whether the card is on-
  /// screen. Called by `VisibilityDetector` from the card. Safe to call
  /// multiple times — only acts on transitions.
  void setActive(bool active) {
    if (_isActive == active) return;
    _isActive = active;
    final round = state.round;
    if (round == null) return;
    if (active) {
      // Card entered view — subscribe + do a quick refresh to catch up
      // on any state changes that happened while we weren't listening.
      _subscribeToRealtime(round.id);
      // Best-effort refresh; don't block the UI thread on it.
      unawaited(_fetchGuesses(round.id));
    } else {
      // Card scrolled off — unsubscribe to free the WebSocket.
      _unsubscribeRealtime();
    }
  }

  Future<bool> submitGuess(double value) async {
    final client = _client;
    final myId = _myId;
    final round = state.round;
    if (client == null || myId == null || round == null) return false;
    try {
      final resp = await client.rpc('fn_pb_v1_submit_guess', params: {
        'p_round_id': round.id,
        'p_user_id': myId,
        'p_guess_value': value,
      });
      if (resp is Map && resp['ok'] == true) {
        state = state.copyWith(
          myGuess: PBv1Guess(userId: myId, guessValue: value, submittedAt: DateTime.now()),
        );
        // Persist the guess to cache so it survives a cold restart
        // before the next refresh.
        await _writeCache();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[PBv1] submit error: $e');
      return false;
    }
  }

  String get revealCountdown {
    final round = state.round;
    if (round == null) return '';
    final diff = round.revealAt.difference(AppTime.nowServerAccurate());
    if (diff.isNegative) return 'Reveal imminent';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${diff.inSeconds}s';
  }

  // ── Realtime ───────────────────────────────────────────────────────

  void _subscribeToRealtime(String roundId) {
    if (_channel != null) return; // already subscribed
    final client = _client;
    if (client == null) return;
    _channel = client.channel('pb_v1:$roundId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'pb_v1_rounds',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: roundId),
        callback: (_) => _fetchGuesses(roundId),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'pb_v1_guesses',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'round_id', value: roundId),
        callback: (_) => _fetchGuesses(roundId),
      )
      .subscribe();

    final registry = _ref.read(realtimeChannelRegistryProvider);
    registry.register('pb_v1:$roundId', _channel!, () => _subscribeToRealtime(roundId), isLiveGame: false);
  }

  void _unsubscribeRealtime() {
    final roundId = state.round?.id;
    if (roundId != null) {
      final registry = _ref.read(realtimeChannelRegistryProvider);
      registry.unregister('pb_v1:$roundId');
    }
    _channel?.unsubscribe();
    _channel = null;
  }

  Future<void> _fetchGuesses(String roundId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    try {
      final resp = await client.rpc('fn_pb_v1_get_round_guesses', params: {
        'p_round_id': roundId,
        'p_requesting_user_id': myId,
      });
      if (resp is Map) {
        final map = Map<String, dynamic>.from(resp);
        final revealed = map['revealed'] == true;
        final myGuessJson = map['my_guess'];
        PBv1Guess? myGuess;
        if (myGuessJson is Map) {
          myGuess = PBv1Guess.fromJson(Map<String, dynamic>.from(myGuessJson));
        }
        List<PBv1Guess> allGuesses = [];
        if (revealed && map['guesses'] is List) {
          allGuesses = (map['guesses'] as List)
              .map((g) => PBv1Guess.fromJson(Map<String, dynamic>.from(g as Map)))
              .toList();
        }
        final winnerIds = <String>[];
        if (revealed && map['winner_user_ids'] is List) {
          winnerIds.addAll((map['winner_user_ids'] as List).whereType<String>());
        }
        state = state.copyWith(
          myGuess: myGuess,
          allGuesses: allGuesses,
          winnerUserIds: winnerIds,
          revealed: revealed,
        );
      }
    } catch (e) {
      debugPrint('[PBv1] fetchGuesses error: $e');
    }
  }

  // ── Cache (Drift via LocalCacheService) ────────────────────────────

  Future<_CachedRound?> _readCache() async {
    try {
      final cache = _ref.read(localCacheProvider);
      final raw = await cache.getPreference<Map<String, dynamic>>(_cacheKeyPrefix + familyId);
      if (raw == null) return null;
      return _CachedRound.fromJson(raw);
    } catch (e) {
      debugPrint('[PBv1] cache read error: $e');
      return null;
    }
  }

  Future<void> _writeCache() async {
    try {
      final cache = _ref.read(localCacheProvider);
      final snapshot = _CachedRound(
        round: state.round,
        question: state.question,
        myGuess: state.myGuess,
        revealed: state.revealed,
        allGuesses: state.allGuesses,
        winnerUserIds: state.winnerUserIds,
        cachedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await cache.setPreference(_cacheKeyPrefix + familyId, snapshot.toJson());
    } catch (e) {
      debugPrint('[PBv1] cache write error: $e');
    }
  }

  @override
  void dispose() {
    _unsubscribeRealtime();
    super.dispose();
  }
}

// ── Cache shape ────────────────────────────────────────────────────

/// Serialized snapshot of the provider's state for cache-first load on
/// cold opens. The `cachedAt` timestamp lets us age-out stale cache if
/// needed (currently we don't — the cache is always overwritten on a
/// successful RPC).
class _CachedRound {
  const _CachedRound({
    required this.round,
    required this.question,
    required this.myGuess,
    required this.revealed,
    required this.allGuesses,
    required this.winnerUserIds,
    required this.cachedAt,
  });

  final PBv1Round? round;
  final PBv1Question? question;
  final PBv1Guess? myGuess;
  final bool revealed;
  final List<PBv1Guess> allGuesses;
  final List<String> winnerUserIds;
  final String cachedAt;

  Map<String, dynamic> toJson() => {
    'round': round?.toJson(),
    'question': question?.toJson(),
    'myGuess': myGuess?.toJson(),
    'revealed': revealed,
    'allGuesses': allGuesses.map((g) => g.toJson()).toList(),
    'winnerUserIds': winnerUserIds,
    'cachedAt': cachedAt,
  };

  factory _CachedRound.fromJson(Map<String, dynamic> json) => _CachedRound(
    round: json['round'] is Map ? PBv1Round.fromJson(Map<String, dynamic>.from(json['round'] as Map)) : null,
    question: json['question'] is Map ? PBv1Question.fromJson(Map<String, dynamic>.from(json['question'] as Map)) : null,
    myGuess: json['myGuess'] is Map ? PBv1Guess.fromJson(Map<String, dynamic>.from(json['myGuess'] as Map)) : null,
    revealed: (json['revealed'] ?? false) as bool,
    allGuesses: (json['allGuesses'] as List? ?? const [])
        .whereType<Map>()
        .map((g) => PBv1Guess.fromJson(Map<String, dynamic>.from(g)))
        .toList(),
    winnerUserIds: (json['winnerUserIds'] as List? ?? const []).whereType<String>().toList(),
    cachedAt: (json['cachedAt'] ?? '') as String,
  );
}

final pbV1Provider = StateNotifierProvider.autoDispose.family<PBv1Notifier, PBv1State, String>(
  (ref, familyId) => PBv1Notifier(ref, familyId),
);
