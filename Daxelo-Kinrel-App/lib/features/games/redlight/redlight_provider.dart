// lib/features/games/redlight/redlight_provider.dart
//
// Freeze & Dash — Riverpod state + Socket.IO + Supabase Realtime.
//
// Architecture (Build Prompt §1):
//   • Socket.IO on the /redlight namespace drives all phase transitions,
//     progress ticks, power-ups, and "caught" events.
//   • Supabase Realtime is used only for lobby membership (players
//     joining/leaving). Once the game starts, the socket is authoritative.
//   • Local progress ticks fire at ~20fps during GREEN so the server can
//     re-validate with weather modifiers and rate limiting.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env_config.dart';
import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import 'redlight_models.dart';

class RedlightState {
  const RedlightState({
    this.round,
    this.players = const [],
    this.liveLeaderboard = const [],
    this.phase = RedlightPhase.waiting,
    this.phaseRemainingMs,
    this.isLoading = false,
    this.isConnected = false,
    this.error,
    this.activePowerups = const [],
    this.results = const [],
    this.countdownSeconds = 0,
    this.myCaughtPenalty,
  });

  final RedlightRound? round;
  final List<RedlightPlayer> players; // lobby (Supabase Realtime)
  final List<RedlightLeaderboardEntry> liveLeaderboard; // in-game (socket)
  final RedlightPhase phase;
  final int? phaseRemainingMs;
  final bool isLoading;
  final bool isConnected;
  final String? error;
  final List<SpawnedPowerup> activePowerups;
  final List<RedlightLeaderboardEntry> results;
  final int countdownSeconds;
  final RedlightPenalty? myCaughtPenalty;

  bool get isLobby => round?.isLobby ?? false;
  bool get isCountdown => round?.isCountdown ?? false;
  bool get isActive => round?.isActive ?? false;
  bool get isFinished => round?.isFinished ?? false;

  RedlightState copyWith({
    RedlightRound? round,
    List<RedlightPlayer>? players,
    List<RedlightLeaderboardEntry>? liveLeaderboard,
    RedlightPhase? phase,
    int? phaseRemainingMs,
    bool? isLoading,
    bool? isConnected,
    String? error,
    bool clearError = false,
    List<SpawnedPowerup>? activePowerups,
    List<RedlightLeaderboardEntry>? results,
    int? countdownSeconds,
    RedlightPenalty? myCaughtPenalty,
    bool clearCaught = false,
  }) =>
      RedlightState(
        round: round ?? this.round,
        players: players ?? this.players,
        liveLeaderboard: liveLeaderboard ?? this.liveLeaderboard,
        phase: phase ?? this.phase,
        phaseRemainingMs: phaseRemainingMs ?? this.phaseRemainingMs,
        isLoading: isLoading ?? this.isLoading,
        isConnected: isConnected ?? this.isConnected,
        error: clearError ? null : (error ?? this.error),
        activePowerups: activePowerups ?? this.activePowerups,
        results: results ?? this.results,
        countdownSeconds: countdownSeconds ?? this.countdownSeconds,
        myCaughtPenalty:
            clearCaught ? null : (myCaughtPenalty ?? this.myCaughtPenalty),
      );
}

class RedlightNotifier extends StateNotifier<RedlightState> {
  RedlightNotifier(this._ref, this.familyId)
    : super(const RedlightState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  io.Socket? _socket;
  RealtimeChannel? _lobbyChannel;
  Timer? _localProgressTimer;
  Timer? _phaseCountdownTimer;
  String? _roundId;

  // ── Socket lifecycle ─────────────────────────────────────────────────

  String _resolveSocketUrl() {
    final apiBaseUrl = EnvConfig.apiBaseUrl;
    String base;
    if (apiBaseUrl.startsWith('https://')) {
      base = 'wss://${apiBaseUrl.substring(8)}';
    } else if (apiBaseUrl.startsWith('http://')) {
      base = 'ws://${apiBaseUrl.substring(7)}';
    } else {
      base = 'wss://$apiBaseUrl';
    }
    // Strip any trailing slash, then append the /redlight namespace.
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return '$base/redlight';
  }

  String? _currentToken() {
    try {
      return _client?.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  void _connectSocket() {
    if (_socket != null) return;
    final token = _currentToken();
    if (token == null) {
      state = state.copyWith(error: 'Not signed in');
      return;
    }
    final url = _resolveSocketUrl();
    debugPrint('[Redlight] Connecting socket to $url');
    _socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setReconnectionAttempts(999)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setTimeout(10000)
          .disableForceNew()
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[Redlight] socket connected');
      state = state.copyWith(isConnected: true, clearError: true);
      // If we already have a round, (re)join
      final rid = _roundId;
      if (rid != null) {
        _socket!.emit('redlight:join', {
          'roundId': rid,
          'userId': _myId,
          'userName': _myName,
        });
      }
    });

    _socket!.onDisconnect((_) {
      debugPrint('[Redlight] socket disconnected');
      state = state.copyWith(isConnected: false);
    });

    _socket!.onConnectError((e) {
      debugPrint('[Redlight] socket connect error: $e');
      state = state.copyWith(error: 'Connection failed');
    });

    _registerSocketHandlers();
    _socket!.connect();
  }

  void _disconnectSocket() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void _registerSocketHandlers() {
    _socket?.on('redlight:phase_change', (data) {
      final d = (data as Map?)?.cast<String, dynamic>() ?? {};
      final phaseStr = d['phase'] as String? ?? 'green';
      final durationMs = (d['durationMs'] as num?)?.toInt() ?? 0;
      final phase = phaseStr == 'red' ? RedlightPhase.red : RedlightPhase.green;
      state = state.copyWith(phase: phase, phaseRemainingMs: durationMs);
      // Haptic: green = success, red = error
      if (phase == RedlightPhase.green) {
        GameMotionTokens.success();
      } else {
        GameMotionTokens.error();
      }
      _startPhaseCountdown(durationMs);
    });

    _socket?.on('redlight:player_joined', (data) {
      // We rely on Supabase Realtime for the canonical lobby list,
      // but a join can also nudge a refresh.
    });

    _socket?.on('redlight:player_left', (data) {
      final d = (data as Map?)?.cast<String, dynamic>() ?? {};
      final userId = d['userId'] as String?;
      if (userId == null) return;
      state = state.copyWith(
        players: state.players.where((p) => p.userId != userId).toList(),
      );
    });

    _socket?.on('redlight:countdown', (data) {
      final d = (data as Map?)?.cast<String, dynamic>() ?? {};
      final seconds = (d['secondsLeft'] as num?)?.toInt() ?? 0;
      state = state.copyWith(countdownSeconds: seconds);
      GameMotionTokens.tap();
    });

    _socket?.on('redlight:game_started', (data) {
      final d = (data as Map?)?.cast<String, dynamic>() ?? {};
      final round = state.round;
      if (round == null) return;
      // Mark round as active locally (Supabase will be updated by server)
      final updatedRound = RedlightRound(
        id: round.id,
        familyId: round.familyId,
        hostUserId: round.hostUserId,
        hostUserName: round.hostUserName,
        callerCharacter: round.callerCharacter,
        mapTheme: round.mapTheme,
        weatherModifier: WeatherModifierX.fromString(
          d['weatherModifier'] as String?,
        ),
        teamMode: round.teamMode,
        eliminationMode: round.eliminationMode,
        status: 'active',
        winnerUserId: round.winnerUserId,
        winnerUserName: round.winnerUserName,
        startedAt: DateTime.now(),
        finishedAt: round.finishedAt,
        createdAt: round.createdAt,
      );
      state = state.copyWith(round: updatedRound, countdownSeconds: 0);
    });

    _socket?.on('redlight:leaderboard', (data) {
      final d = (data as Map?)?.cast<String, dynamic>() ?? {};
      final raw = d['players'] as List? ?? [];
      final entries = raw
          .map(
            (e) => RedlightLeaderboardEntry.fromJson(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList();
      state = state.copyWith(liveLeaderboard: entries);
    });

    _socket?.on('redlight:caught', (data) {
      final d = (data as Map?)?.cast<String, dynamic>() ?? {};
      final userId = d['userId'] as String?;
      final penaltyStr = d['penalty'] as String? ?? 'knockback';
      final penalty = penaltyStr == 'eliminated'
          ? RedlightPenalty.eliminated
          : penaltyStr == 'shield_absorbed'
          ? RedlightPenalty.shieldAbsorbed
          : RedlightPenalty.knockback;
      if (userId == _myId) {
        state = state.copyWith(myCaughtPenalty: penalty);
        GameMotionTokens.celebrate();
        // Clear caught indicator after 1.2s
        Timer(const Duration(milliseconds: 1200), () {
          if (mounted) state = state.copyWith(clearCaught: true);
        });
      }
    });

    _socket?.on('redlight:powerup_spawned', (data) {
      final d = (data as Map?)?.cast<String, dynamic>() ?? {};
      final pu = SpawnedPowerup.fromJson(d);
      state = state.copyWith(activePowerups: [...state.activePowerups, pu]);
    });

    _socket?.on('redlight:game_finished', (data) {
      final d = (data as Map?)?.cast<String, dynamic>() ?? {};
      final rawPlacements = d['placements'] as List? ?? [];
      final placements = rawPlacements
          .map(
            (e) => RedlightLeaderboardEntry.fromJson(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList();
      _localProgressTimer?.cancel();
      _phaseCountdownTimer?.cancel();
      state = state.copyWith(
        results: placements,
        phase: RedlightPhase.waiting,
      );
      // Win/lose haptic
      final winnerId = d['winnerId'] as String?;
      if (winnerId == _myId) {
        GameMotionTokens.celebrate();
      } else {
        GameMotionTokens.error();
      }
      // Mark round as finished
      final round = state.round;
      if (round != null) {
        final finishedRound = RedlightRound(
          id: round.id,
          familyId: round.familyId,
          hostUserId: round.hostUserId,
          hostUserName: round.hostUserName,
          callerCharacter: round.callerCharacter,
          mapTheme: round.mapTheme,
          weatherModifier: round.weatherModifier,
          teamMode: round.teamMode,
          eliminationMode: round.eliminationMode,
          status: 'finished',
          winnerUserId: d['winnerId'] as String?,
          winnerUserName: d['winnerName'] as String?,
          startedAt: round.startedAt,
          finishedAt: DateTime.now(),
          createdAt: round.createdAt,
        );
        state = state.copyWith(round: finishedRound);
      }
    });

    _socket?.on('redlight:error', (data) {
      final d = (data as Map?)?.cast<String, dynamic>() ?? {};
      final message = d['message'] as String? ?? 'Unknown error';
      debugPrint('[Redlight] server error: $message');
      state = state.copyWith(error: message);
    });
  }

  void _startPhaseCountdown(int durationMs) {
    _phaseCountdownTimer?.cancel();
    if (durationMs <= 0) return;
    final tickMs = 100;
    var remaining = durationMs;
    _phaseCountdownTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (t) {
        remaining -= tickMs;
        if (remaining <= 0) {
          t.cancel();
          state = state.copyWith(phaseRemainingMs: 0);
        } else {
          state = state.copyWith(phaseRemainingMs: remaining);
        }
      },
    );
  }

  // ── Supabase Realtime (lobby only) ───────────────────────────────────

  void _subscribeLobby(String roundId) {
    _lobbyChannel?.unsubscribe();
    final client = _client;
    if (client == null) return;
    _lobbyChannel = client
        .channel('redlight_lobby:$roundId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'redlight_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'roundId',
            value: roundId,
          ),
          callback: (payload) {
            final p = RedlightPlayer.fromJson(payload.newRecord);
            if (!state.players.any((x) => x.userId == p.userId)) {
              state = state.copyWith(players: [...state.players, p]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'redlight_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'roundId',
            value: roundId,
          ),
          callback: (payload) {
            final updated = RedlightPlayer.fromJson(payload.newRecord);
            final next = state.players
                .map((p) => p.userId == updated.userId ? updated : p)
                .toList();
            state = state.copyWith(players: next);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'redlight_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'roundId',
            value: roundId,
          ),
          callback: (payload) {
            final oldRecord = payload.oldRecord;
            final userId = oldRecord['userId'] as String?;
            if (userId == null) return;
            state = state.copyWith(
              players:
                  state.players.where((p) => p.userId != userId).toList(),
            );
          },
        )
        .subscribe();
  }

  /// Fetch the current lobby roster from Supabase (initial load).
  Future<void> _refreshLobbyFromSupabase(String roundId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('redlight_players')
          .select()
          .eq('roundId', roundId)
          .order('joinedAt', ascending: true);
      final players = resp
          .map((p) => RedlightPlayer.fromJson(p as Map<String, dynamic>))
          .toList();
      state = state.copyWith(players: players);
    } catch (e) {
      debugPrint('[Redlight] lobby fetch error: $e');
    }
  }

  // ── Public API ───────────────────────────────────────────────────────

  /// Host: create a new round with the given settings.
  /// Returns the roundId on success, null on error.
  Future<String?> createRound({
    required CallerCharacter callerCharacter,
    required MapTheme mapTheme,
    WeatherModifier? weatherModifier,
    bool teamMode = false,
    bool eliminationMode = false,
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final myName = _myName;
      final body = {
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': myName,
        'callerCharacter': callerCharacter.name,
        'mapTheme': mapTheme.name,
        'weatherModifier': weatherModifier?.name,
        'teamMode': teamMode,
        'eliminationMode': eliminationMode,
        'status': 'lobby',
      };
      final resp = await client
          .from('redlight_rounds')
          .insert(body)
          .select()
          .single();
      final round = RedlightRound.fromJson(resp as Map<String, dynamic>);
      _roundId = round.id;

      // Insert self into redlight_players
      await client.from('redlight_players').insert({
        'roundId': round.id,
        'userId': myId,
        'userName': myName,
        'teamId': null,
        'progress': 0,
        'alive': true,
      });

      state = state.copyWith(round: round, isLoading: false);
      _subscribeLobby(round.id);
      _refreshLobbyFromSupabase(round.id);
      _connectSocket();
      return round.id;
    } catch (e) {
      debugPrint('[Redlight] createRound error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  /// Non-host: join an existing round by id.
  Future<bool> joinRound(String roundId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // Fetch the round row
      final roundResp = await client
          .from('redlight_rounds')
          .select()
          .eq('id', roundId)
          .single();
      final round = RedlightRound.fromJson(
        roundResp as Map<String, dynamic>,
      );
      _roundId = round.id;

      // Upsert self into redlight_players
      await client.from('redlight_players').upsert({
        'roundId': roundId,
        'userId': myId,
        'userName': _myName,
        'teamId': null,
        'progress': 0,
        'alive': true,
      }, onConflict: 'roundId,userId');

      state = state.copyWith(round: round, isLoading: false);
      _subscribeLobby(roundId);
      _refreshLobbyFromSupabase(roundId);
      _connectSocket();
      return true;
    } catch (e) {
      debugPrint('[Redlight] joinRound error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Host only: begin countdown → active.
  void startGame() {
    final rid = _roundId;
    if (rid == null) return;
    _socket?.emit('redlight:start', {'roundId': rid});
  }

  /// Local player pressed the Run button.
  void onRunButtonDown() {
    final rid = _roundId;
    final myId = _myId;
    if (rid == null || myId == null) return;
    // Optimistic: only allow during GREEN
    if (state.phase == RedlightPhase.red) return;
    _socket?.emit('redlight:run_start', {'roundId': rid, 'userId': myId});
    _startLocalProgressTimer();
  }

  /// Local player released the Run button.
  void onRunButtonUp() {
    final rid = _roundId;
    final myId = _myId;
    if (rid == null || myId == null) return;
    _stopLocalProgressTimer();
    _socket?.emit('redlight:run_stop', {'roundId': rid, 'userId': myId});
  }

  /// Fire progress ticks at ~20fps while the Run button is held.
  /// The server re-validates and applies weather modifiers.
  void _startLocalProgressTimer() {
    _localProgressTimer?.cancel();
    const tickMs = 50; // 20fps
    const baseDelta = 0.8; // per tick
    _localProgressTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) {
        final rid = _roundId;
        final myId = _myId;
        if (rid == null || myId == null) return;
        // Stop ticking if we're no longer in GREEN
        if (state.phase != RedlightPhase.green) return;
        _socket?.emit('redlight:progress_tick', {
          'roundId': rid,
          'userId': myId,
          'delta': baseDelta,
        });
      },
    );
  }

  void _stopLocalProgressTimer() {
    _localProgressTimer?.cancel();
    _localProgressTimer = null;
  }

  /// Player tapped a power-up to collect it.
  void collectPowerup(String powerupId, PowerupType type) {
    final rid = _roundId;
    final myId = _myId;
    if (rid == null || myId == null) return;
    _socket?.emit('redlight:powerup_collect', {
      'roundId': rid,
      'userId': myId,
      'powerupId': powerupId,
      'powerupType': type.name,
    });
    // Optimistically remove from local list
    state = state.copyWith(
      activePowerups:
          state.activePowerups.where((p) => p.powerupId != powerupId).toList(),
    );
  }

  /// Leave the round (manual exit).
  Future<void> leaveRound() async {
    final rid = _roundId;
    final myId = _myId;
    if (rid != null && myId != null) {
      _socket?.emit('redlight:leave', {'roundId': rid, 'userId': myId});
      final client = _client;
      if (client != null) {
        try {
          await client
              .from('redlight_players')
              .delete()
              .eq('roundId', rid)
              .eq('userId', myId);
        } catch (_) {}
      }
    }
    _cleanup();
  }

  void _cleanup() {
    _stopLocalProgressTimer();
    _phaseCountdownTimer?.cancel();
    _lobbyChannel?.unsubscribe();
    _lobbyChannel = null;
    _disconnectSocket();
    _roundId = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

final redlightProvider = StateNotifierProvider.autoDispose
    .family<RedlightNotifier, RedlightState, String>(
  (ref, familyId) => RedlightNotifier(ref, familyId),
);
