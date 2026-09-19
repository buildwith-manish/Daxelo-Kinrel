// lib/features/games/night_falls/night_falls_provider.dart
//
// Night Falls — Riverpod state + Supabase Realtime orchestration.
//
// Architecture (mirrors impostor_provider + secret_heist_provider):
//   • Supabase stores games + players + (hidden) actions
//   • Supabase Realtime broadcasts board state changes
//   • RLS on night_falls_actions hides other players' choices until
//     the resolution RPC publishes them into boardState
//   • The `role` column on night_falls_players is hidden via column-level
//     GRANT; the caller's own role is fetched via fn_nightfalls_my_role
//   • A pg_cron-driven watchdog enforces phase timers (via
//     fn_nightfalls_tick, called by this provider's _watchdog timer)

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/services/temporary_room_service.dart';
import 'night_falls_models.dart';

class NightFallsState {
  const NightFallsState({
    this.game,
    this.players = const [],
    this.myRole,
    this.fellowWolves = const [],
    this.myActions = const [],
    this.isLoading = false,
    this.isStarting = false,
    this.isLeaving = false,
    this.isSubmitting = false,
    this.error,
    this.amSpectator = false,
  });

  final NightFallsGame? game;
  final List<NightFallsPlayerWire> players;
  /// The caller's own role. Fetched via fn_nightfalls_my_role.
  final NightFallsRole? myRole;
  /// User IDs of fellow werewolves (only populated if the caller is a
  /// werewolf). Fetched via fn_nightfalls_my_role.
  final List<String> fellowWolves;
  /// The caller's own action history (from night_falls_actions).
  /// Includes seer investigation results.
  final List<NightFallsActionWire> myActions;
  final bool isLoading;
  final bool isStarting;
  final bool isLeaving;
  final bool isSubmitting;
  final String? error;
  final bool amSpectator;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  /// True if the caller is a werewolf.
  bool get amWolf => myRole == NightFallsRole.werewolf;

  NightFallsPlayerWire? playerFor(String? userId) {
    if (userId == null) return null;
    for (final p in players) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  /// The caller's seer investigation history (round → verdict).
  /// Only populated if the caller is the seer.
  List<NightFallsActionWire> get seerResults =>
      myActions.where((a) => a.isSeerResult).toList();

  NightFallsState copyWith({
    NightFallsGame? game,
    List<NightFallsPlayerWire>? players,
    NightFallsRole? myRole,
    bool clearMyRole = false,
    List<String>? fellowWolves,
    bool clearFellowWolves = false,
    List<NightFallsActionWire>? myActions,
    bool? isLoading,
    bool? isStarting,
    bool? isLeaving,
    bool? isSubmitting,
    bool clearError = false,
    String? error,
    bool? amSpectator,
  }) =>
      NightFallsState(
        game: game ?? this.game,
        players: players ?? this.players,
        myRole: clearMyRole ? null : (myRole ?? this.myRole),
        fellowWolves:
            clearFellowWolves ? const [] : (fellowWolves ?? this.fellowWolves),
        myActions: myActions ?? this.myActions,
        isLoading: isLoading ?? this.isLoading,
        isStarting: isStarting ?? this.isStarting,
        isLeaving: isLeaving ?? this.isLeaving,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        amSpectator: amSpectator ?? this.amSpectator,
      );
}

class NightFallsNotifier extends StateNotifier<NightFallsState> {
  NightFallsNotifier(this._ref, this.familyId)
      : super(const NightFallsState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ??
      'Player';

  RealtimeChannel? _channel;
  String? _gameId;
  Timer? _watchdogTimer;
  Timer? _cleanupTimer;

  // ── Public API ───────────────────────────────────────────────────

  Future<String?> createGame({
    required int maxPlayers,
    required int nightSeconds,
    required int daySeconds,
    required int voteSeconds,
    String? roomName,
    bool spectatorsEnabled = true,
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final body = <String, dynamic>{
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'status': 'waiting',
        'maxPlayers': maxPlayers,
        'spectatorsEnabled': spectatorsEnabled,
        'nightSeconds': nightSeconds,
        'daySeconds': daySeconds,
        'voteSeconds': voteSeconds,
        'roleRevealSeconds': kNightFallsDefaultRoleRevealSeconds,
        'autoCloseDeadline':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        if (roomName != null && roomName.trim().isNotEmpty)
          'roomName': roomName.trim(),
      };
      final resp = await client
          .from('night_falls_games')
          .insert(body)
          .select()
          .single();
      final game = NightFallsGame.fromJson(resp);
      _gameId = game.id;
      await client.from('night_falls_players').insert({
        'gameId': game.id,
        'userId': myId,
        'userName': _myName,
      });
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'night_falls_games',
        'p_game_id': game.id,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': 'host',
      });
      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      await _refreshPlayers(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[NightFalls] createGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  Future<bool> joinGame(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final gameResp = await client
          .from('night_falls_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (gameResp == null) {
        state = state.copyWith(isLoading: false, error: 'Game not found');
        return false;
      }
      final game = NightFallsGame.fromJson(gameResp);
      _gameId = gameId;
      if (game.isInProgress || game.isCompleted) {
        await client.rpc('fn_join_spectator', params: {
          'p_game_table': 'night_falls_games',
          'p_game_id': gameId,
          'p_user_id': myId,
          'p_user_name': _myName,
        });
        state = state.copyWith(
            game: game, isLoading: false, amSpectator: true);
        _subscribeToRealtime(gameId);
        await _refreshPlayers(gameId);
        return true;
      }
      final existing = await client
          .from('night_falls_players')
          .select()
          .eq('gameId', gameId)
          .eq('userId', myId)
          .maybeSingle();
      if (existing == null) {
        final activeCount = await _countActivePlayers(gameId);
        if (activeCount >= game.maxPlayers) {
          state = state.copyWith(isLoading: false, error: 'Room is full');
          return false;
        }
        await client.from('night_falls_players').insert({
          'gameId': gameId,
          'userId': myId,
          'userName': _myName,
        });
        await client.rpc('fn_record_room_join', params: {
          'p_game_table': 'night_falls_games',
          'p_game_id': gameId,
          'p_family_id': familyId,
          'p_user_id': myId,
          'p_user_name': _myName,
          'p_role': 'player',
        });
      } else if (existing['leftAt'] != null) {
        await client
            .from('night_falls_players')
            .update({'leftAt': null, 'isReady': false}).eq('id', existing['id']);
      }
      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshPlayers(gameId);
      _loadGame(gameId);
      return true;
    } catch (e) {
      debugPrint('[NightFalls] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  Future<int> _countActivePlayers(String gameId) async {
    final client = _client;
    if (client == null) return 0;
    final resp = await client
        .from('night_falls_players')
        .select('userId')
        .eq('gameId', gameId)
        .isFilter('leftAt', null);
    return resp.length;
  }

  Future<void> toggleReady(bool isReady) async {
    final gameId = _gameId;
    if (gameId == null) return;
    await _ref.read(temporaryRoomServiceProvider).toggleReady(
          gameTable: 'night_falls_games',
          gameId: gameId,
          isReady: isReady,
        );
    final myId = _myId;
    if (myId != null) {
      final next = state.players
          .map((p) => p.userId == myId
              ? NightFallsPlayerWire(
                  id: p.id,
                  gameId: p.gameId,
                  userId: p.userId,
                  userName: p.userName,
                  joinedAt: p.joinedAt,
                  isAlive: p.isAlive,
                  isReady: isReady,
                  leftAt: p.leftAt,
                  role: p.role,
                )
              : p)
          .toList();
      state = state.copyWith(players: next);
    }
  }

  Future<String?> startGame() async {
    final gameId = _gameId;
    if (gameId == null) return null;
    final active = state.players.where((p) => p.isActive).length;
    if (active < kNightFallsMinPlayers) {
      return 'Night Falls needs at least $kNightFallsMinPlayers players';
    }
    state = state.copyWith(isStarting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return null;
      final result = await client.rpc('fn_nightfalls_start',
          params: {'p_game_id': gameId});
      final map = (result is Map<String, dynamic>)
          ? result
          : Map<String, dynamic>.from(result as Map);
      state = state.copyWith(isStarting: false);
      if (map['ok'] == true) {
        GameMotionTokens.celebrate();
        // Fetch my role immediately after start
        await _refreshMyRole(gameId);
        return null;
      }
      return switch (map['reason']) {
        'not_enough_players' =>
          'Needs at least $kNightFallsMinPlayers players',
        'not_host' => 'Only the host can start',
        'already_started' => null,
        _ => 'Could not start the game',
      };
    } catch (e) {
      debugPrint('[NightFalls] startGame error: $e');
      state = state.copyWith(isStarting: false, error: '$e');
      return 'Could not start the game';
    }
  }

  /// Submit (or update) a night action.
  Future<void> submitNightAction(
      String targetUserId, NightFallsActionType actionType) async {
    final gameId = _gameId;
    if (gameId == null) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_nightfalls_submit_night_action', params: {
        'p_game_id': gameId,
        'p_action_type': actionType.wire,
        'p_target_user_id': targetUserId,
      });
      await _refreshMyActions(gameId);
      GameMotionTokens.tap();
    } catch (e) {
      debugPrint('[NightFalls] submitNightAction error: $e');
      state = state.copyWith(error: '$e');
    } finally {
      state = state.copyWith(isSubmitting: false);
    }
  }

  /// Cast a vote to eliminate a player.
  Future<void> vote(String targetUserId) async {
    final gameId = _gameId;
    if (gameId == null) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_nightfalls_vote', params: {
        'p_game_id': gameId,
        'p_target_user_id': targetUserId,
      });
      await _refreshMyActions(gameId);
      GameMotionTokens.tap();
    } catch (e) {
      debugPrint('[NightFalls] vote error: $e');
      state = state.copyWith(error: '$e');
    } finally {
      state = state.copyWith(isSubmitting: false);
    }
  }

  /// Hunter's revenge — take one player down when eliminated.
  Future<void> hunterRevenge(String targetUserId) async {
    final gameId = _gameId;
    if (gameId == null) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_nightfalls_hunter_revenge', params: {
        'p_game_id': gameId,
        'p_target_user_id': targetUserId,
      });
      GameMotionTokens.tap();
    } catch (e) {
      debugPrint('[NightFalls] hunterRevenge error: $e');
      state = state.copyWith(error: '$e');
    } finally {
      state = state.copyWith(isSubmitting: false);
    }
  }

  /// Advance phase — role_reveal→night, day→vote, result→night (next round).
  Future<void> advancePhase() async {
    final gameId = _gameId;
    if (gameId == null) return;
    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_nightfalls_advance',
          params: {'p_game_id': gameId});
    } catch (e) {
      debugPrint('[NightFalls] advance error: $e');
    }
  }

  Future<void> leaveGame() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final game = state.game;
    if (client == null || gameId == null || myId == null) {
      _cleanup();
      return;
    }
    state = state.copyWith(isLeaving: true);
    try {
      if (game != null && game.isWaiting && game.hostUserId == myId) {
        await _ref
            .read(temporaryRoomServiceProvider)
            .cancelWaitingRoom(
              gameTable: 'night_falls_games',
              gameId: gameId,
            );
      } else if (state.amSpectator) {
        await client.rpc('fn_leave_spectator', params: {
          'p_game_table': 'night_falls_games',
          'p_game_id': gameId,
          'p_user_id': myId,
        });
      } else {
        await _tryRpc('fn_nightfalls_leave', {'p_game_id': gameId});
      }
    } catch (_) {}
    _cleanup();
  }

  Future<String?> rematch() async {
    final client = _client;
    final game = state.game;
    final myId = _myId;
    if (client == null || game == null || myId == null) return null;
    final roster = List<NightFallsPlayerWire>.from(state.players);
    final newGameId = await createGame(
      maxPlayers: game.maxPlayers,
      nightSeconds: game.nightSeconds,
      daySeconds: game.daySeconds,
      voteSeconds: game.voteSeconds,
      roomName: game.roomName,
      spectatorsEnabled: game.spectatorsEnabled,
    );
    if (newGameId == null) return null;
    try {
      final others = roster.where((p) => p.userId != myId).toList();
      if (others.isNotEmpty) {
        await client.from('night_falls_players').upsert(
          others
              .map((p) => {
                    'gameId': newGameId,
                    'userId': p.userId,
                    'userName': p.userName,
                  })
              .toList(),
          onConflict: 'gameId,userId',
        );
        for (final p in others) {
          if (p.userId.isEmpty) continue;
          try {
            await client.rpc('fn_record_room_join', params: {
              'p_game_table': 'night_falls_games',
              'p_game_id': newGameId,
              'p_family_id': familyId,
              'p_user_id': p.userId,
              'p_user_name': p.userName,
              'p_role': 'player',
            });
          } catch (_) {}
        }
      }
      final roomCode =
          newGameId.replaceAll('-', '').substring(0, 6).toUpperCase();
      final invites = roster
          .where((p) => p.userId != myId && p.userId.isNotEmpty)
          .map((p) => {
                'gameTable': 'night_falls_games',
                'gameId': newGameId,
                'gameType': 'night-falls',
                'familyId': familyId,
                'roomCode': roomCode,
                'invitedUserId': p.userId,
                'invitedByUserId': myId,
                'invitedByName': _myName,
                'maxPlayers': game.maxPlayers,
                'currentPlayers': 1,
                'message': '$_myName wants a Night Falls rematch!',
                'status': 'pending',
                'sourceGameId': game.id,
              })
          .toList();
      if (invites.isNotEmpty) {
        try {
          await client.from('game_invites').insert(invites);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[NightFalls] rematch error: $e');
    }
    return newGameId;
  }

  Future<void> loadGame(String gameId) async {
    await _loadGame(gameId);
    await _refreshPlayers(gameId);
    await _refreshMyRole(gameId);
    await _refreshMyActions(gameId);
    _subscribeToRealtime(gameId);
  }

  Future<void> _loadGame(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('night_falls_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (resp == null) return;
      _gameId = gameId;
      _applyGameRow(NightFallsGame.fromJson(resp));
    } catch (e) {
      debugPrint('[NightFalls] loadGame error: $e');
    }
  }

  void _applyGameRow(NightFallsGame game) {
    final previous = state.game;
    final previousPhase = previous?.boardState?.currentRound?.phase;
    final newPhase = game.boardState?.currentRound?.phase;
    state = state.copyWith(game: game);
    if (game.isInProgress && _watchdogTimer == null) {
      _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _tryRpc('fn_nightfalls_tick', {'p_game_id': game.id});
      });
    } else if (!game.isInProgress && _watchdogTimer != null) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
    }
    // When the night phase resolves (night → day), refresh my actions
    // so the seer's result is fetched immediately.
    if (previousPhase == NightFallsPhase.night &&
        newPhase == NightFallsPhase.day) {
      _refreshMyActions(game.id);
    }
    if (game.isCompleted && (previous?.isInProgress ?? false)) {
      GameMotionTokens.celebrate();
      _scheduleRoomCleanup(game.id);
    }
  }

  Future<void> _refreshPlayers(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('night_falls_players')
          .select()
          .eq('gameId', gameId)
          .order('joinedAt', ascending: true);
      state = state.copyWith(
          players: resp
              .map((p) => NightFallsPlayerWire.fromJson(p))
              .toList());
    } catch (e) {
      debugPrint('[NightFalls] refreshPlayers error: $e');
    }
  }

  Future<void> _refreshMyRole(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    try {
      final result = await client.rpc('fn_nightfalls_my_role', params: {
        'p_game_id': gameId,
      });
      if (result == null) {
        state = state.copyWith(clearMyRole: true, clearFellowWolves: true);
      } else {
        final map = result is Map<String, dynamic>
            ? result
            : Map<String, dynamic>.from(result as Map);
        final role = NightFallsRoleX.fromString(map['role']?.toString());
        final rawWolves = map['fellowWolves'];
        final wolves = <String>[];
        if (rawWolves is List) {
          wolves.addAll(rawWolves.whereType<String>());
        }
        state = state.copyWith(myRole: role, fellowWolves: wolves);
      }
    } catch (e) {
      debugPrint('[NightFalls] refreshMyRole error: $e');
    }
  }

  Future<void> _refreshMyActions(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    try {
      final resp = await client
          .from('night_falls_actions')
          .select()
          .eq('gameId', gameId)
          .eq('userId', myId)
          .order('roundNumber', ascending: true);
      state = state.copyWith(
          myActions: resp
              .map((a) => NightFallsActionWire.fromJson(a))
              .toList());
    } catch (e) {
      debugPrint('[NightFalls] refreshMyActions error: $e');
    }
  }

  Future<bool> _tryRpc(String fn, Map<String, dynamic> params) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.rpc(fn, params: params);
      return true;
    } catch (e) {
      debugPrint('[NightFalls] $fn error: $e');
      return false;
    }
  }

  void _scheduleRoomCleanup(String gameId) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'night_falls_games',
            gameId: gameId,
          );
    });
  }

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;
    _channel = client
        .channel('nightfalls_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'night_falls_games',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: gameId),
          callback: (payload) =>
              _applyGameRow(NightFallsGame.fromJson(payload.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'night_falls_players',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'gameId',
              value: gameId),
          callback: (payload) {
            final player = NightFallsPlayerWire.fromJson(payload.newRecord);
            if (!state.players.any((p) => p.userId == player.userId)) {
              state = state.copyWith(players: [...state.players, player]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'night_falls_players',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'gameId',
              value: gameId),
          callback: (payload) {
            final updated = NightFallsPlayerWire.fromJson(payload.newRecord);
            state = state.copyWith(
                players: state.players
                    .map((p) => p.userId == updated.userId ? updated : p)
                    .toList());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'night_falls_players',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'gameId',
              value: gameId),
          callback: (payload) {
            final goneId = payload.oldRecord['userId'] as String?;
            if (goneId == null) return;
            state = state.copyWith(
                players: state.players
                    .where((p) => p.userId != goneId)
                    .toList());
          },
        )
        // My own action rows (RLS lets me see only my own rows).
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'night_falls_actions',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'userId',
              value: _myId ?? ''),
          callback: (payload) {
            final action = NightFallsActionWire.fromJson(payload.newRecord);
            if (!state.myActions.any((a) => a.id == action.id)) {
              state = state.copyWith(myActions: [...state.myActions, action]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'night_falls_actions',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'userId',
              value: _myId ?? ''),
          callback: (payload) {
            final updated = NightFallsActionWire.fromJson(payload.newRecord);
            state = state.copyWith(
                myActions: state.myActions
                    .map((a) => a.id == updated.id ? updated : a)
                    .toList());
          },
        )
        .subscribe();
  }

  void _cleanup() {
    _channel?.unsubscribe();
    _channel = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _gameId = null;
    state = const NightFallsState();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _cleanupTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}

final nightFallsProvider = StateNotifierProvider.autoDispose
    .family<NightFallsNotifier, NightFallsState, String>(
        (ref, familyId) => NightFallsNotifier(ref, familyId));
