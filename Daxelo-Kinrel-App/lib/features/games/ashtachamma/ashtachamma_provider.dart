// lib/features/games/ashtachamma/ashtachamma_provider.dart
//
// Ashta Chamma — Riverpod state + Supabase Realtime + server-authoritative
// dice rolls + moves.
//
// Architecture mirrors memorymatch_provider.dart exactly:
//   • Supabase stores the game row (boardState JSONB, current player,
//     dice value, phase, scores, placements) + the player roster.
//   • Every mutation goes through RPCs:
//       – fn_ashtachamma_start  — host starts; validates 2–4 players;
//                                 initializes boardState with all pieces
//                                 in base.
//       – fn_ashtachamma_roll   — current player rolls; server generates
//                                 the cowrie-shell throw (deterministic
//                                 per move), stores lastDiceValue, sets
//                                 phase='move'. If no legal moves exist,
//                                 passes the turn automatically.
//       – fn_ashtachamma_move   — current player moves a piece; server
//                                 applies the move via the same logic as
//                                 AshtaChammaEngine.movePiece, resolves
//                                 captures, checks for a winner, advances
//                                 the turn (or retains if dice was 4/8).
//       – fn_ashtachamma_tick   — 2 s watchdog: expires turns, refreshes
//                                 heartbeat.
//       – fn_ashtachamma_leave  — mid-game departure.
//       – fn_ashtachamma_finish — compute placements + winners, set
//                                 status='completed' (fires the archive
//                                 trigger).
//   • Clients render from the realtime game row; the current player's
//     client optimistically shows the dice roll / piece move for <100 ms
//     perceived latency and reconciles when the authoritative row arrives.
//   • The current player's client schedules a precise turn expiry via
//     the watchdog; everyone's 2 s tick is the backstop.
//
// Only the minimal state is synced: currentPlayerId, lastDiceValue,
// phase, boardState (pieces + move history). All animations are
// client-side. The engine is deterministic — every client independently
// derives the same board from the same move history.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/services/temporary_room_service.dart';
import 'ashtachamma_engine.dart';
import 'ashtachamma_models.dart';

class AshtaChammaState {
  const AshtaChammaState({
    this.game,
    this.players = const [],
    this.isLoading = false,
    this.isStarting = false,
    this.isLeaving = false,
    this.error,
    this.amSpectator = false,
    this.optimisticDice,
    this.optimisticMovePieceIndex,
  });

  final AshtaChammaGame? game;
  final List<AshtaChammaPlayer> players;
  final bool isLoading;
  final bool isStarting;
  final bool isLeaving;
  final String? error;
  final bool amSpectator;

  /// The dice value the local player just rolled (instant feedback).
  /// Reconciled away as soon as the authoritative row arrives.
  final int? optimisticDice;

  /// The piece index the local player just tapped (instant move feedback).
  final int? optimisticMovePieceIndex;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  AshtaChammaPlayer? playerFor(String? userId) {
    if (userId == null) return null;
    for (final p in players) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  bool get canRoll {
    final g = game;
    if (g == null || !g.isInProgress || amSpectator) return false;
    if (g.phase != AshtaChammaPhase.roll) return false;
    return g.currentPlayerId == _currentUserId;
  }

  bool get canMove {
    final g = game;
    if (g == null || !g.isInProgress || amSpectator) return false;
    if (g.phase != AshtaChammaPhase.move) return false;
    return g.currentPlayerId == _currentUserId;
  }

  /// The current user's id (static field set by the provider). This is a
  /// workaround for the state class being immutable + not having a ref.
  /// The provider sets this before each state emission.
  static String? _currentUserId;

  AshtaChammaState copyWith({
    AshtaChammaGame? game,
    List<AshtaChammaPlayer>? players,
    bool? isLoading,
    bool? isStarting,
    bool? isLeaving,
    bool clearError = false,
    String? error,
    bool? amSpectator,
    int? optimisticDice,
    int? optimisticMovePieceIndex,
    bool clearOptimisticDice = false,
    bool clearOptimisticMove = false,
  }) =>
      AshtaChammaState(
        game: game ?? this.game,
        players: players ?? this.players,
        isLoading: isLoading ?? this.isLoading,
        isStarting: isStarting ?? this.isStarting,
        isLeaving: isLeaving ?? this.isLeaving,
        error: clearError ? null : (error ?? this.error),
        amSpectator: amSpectator ?? this.amSpectator,
        optimisticDice: clearOptimisticDice ? null : (optimisticDice ?? this.optimisticDice),
        optimisticMovePieceIndex: clearOptimisticMove ? null : (optimisticMovePieceIndex ?? this.optimisticMovePieceIndex),
      );
}

class AshtaChammaNotifier extends StateNotifier<AshtaChammaState> {
  AshtaChammaNotifier(this._ref, this.familyId)
      : super(const AshtaChammaState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  String? _gameId;
  Timer? _watchdogTimer;
  Timer? _cleanupTimer;
  Timer? _turnTimer;

  bool _tickInFlight = false;

  // ── Public API ───────────────────────────────────────────────────

  /// Host: create a new room with the chosen settings.
  Future<String?> createGame({
    required int maxPlayers,
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
        'phase': 'roll',
        'lastDiceValue': 0,
        'autoCloseDeadline':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        if (roomName != null && roomName.trim().isNotEmpty)
          'roomName': roomName.trim(),
      };
      final resp =
          await client.from('ashta_chamma_games').insert(body).select().single();
      final game = AshtaChammaGame.fromJson(resp);
      _gameId = game.id;

      await client.from('ashta_chamma_players').insert({
        'gameId': game.id,
        'userId': myId,
        'userName': _myName,
        'turnOrder': 0,
      });

      // Register in the shared room bookkeeping so the ecosystem archive
      // sees this participant (same path RoomController uses).
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'ashta_chamma_games',
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
      debugPrint('[AshtaChamma] createGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  /// Join an existing room. Falls back to spectating once the match is
  /// already running.
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
          .from('ashta_chamma_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (gameResp == null) {
        state = state.copyWith(isLoading: false, error: 'Game not found');
        return false;
      }
      final game = AshtaChammaGame.fromJson(gameResp);
      _gameId = gameId;

      // If the game is already in progress, join as spectator.
      if (game.isInProgress || game.isCompleted) {
        final activeCount = await _countActivePlayers(gameId);
        if (activeCount >= game.maxPlayers) {
          await client.rpc('fn_join_spectator', params: {
            'p_game_table': 'ashta_chamma_games',
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
      }

      // Insert or update the player row.
      final existing = await client
          .from('ashta_chamma_players')
          .select()
          .eq('gameId', gameId)
          .eq('userId', myId)
          .maybeSingle();
      if (existing == null) {
        final activeCount = await _countActivePlayers(gameId);
        if (activeCount >= game.maxPlayers) {
          state = state.copyWith(
              isLoading: false, error: 'Room is full');
          return false;
        }
        await client.from('ashta_chamma_players').insert({
          'gameId': gameId,
          'userId': myId,
          'userName': _myName,
          'turnOrder': activeCount,
        });
        await client.rpc('fn_record_room_join', params: {
          'p_game_table': 'ashta_chamma_games',
          'p_game_id': gameId,
          'p_family_id': familyId,
          'p_user_id': myId,
          'p_user_name': _myName,
          'p_role': 'player',
        });
      } else if (existing['leftAt'] != null) {
        // Re-join after leaving.
        await client.from('ashta_chamma_players').update({
          'leftAt': null,
          'isReady': false,
        }).eq('id', existing['id']);
      }

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshPlayers(gameId);
      _loadGame(gameId);
      return true;
    } catch (e) {
      debugPrint('[AshtaChamma] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  Future<int> _countActivePlayers(String gameId) async {
    final client = _client;
    if (client == null) return 0;
    final resp = await client
        .from('ashta_chamma_players')
        .select('userId')
        .eq('gameId', gameId)
        .isFilter('leftAt', null);
    return resp.length;
  }

  /// Toggle ready state (waiting room).
  Future<void> toggleReady(bool isReady) async {
    final gameId = _gameId;
    if (gameId == null) return;
    await _ref.read(temporaryRoomServiceProvider).toggleReady(
          gameTable: 'ashta_chamma_games',
          gameId: gameId,
          isReady: isReady,
        );
    final myId = _myId;
    if (myId != null) {
      final next = state.players
          .map((p) => p.userId == myId
              ? AshtaChammaPlayer(
                  id: p.id,
                  gameId: p.gameId,
                  userId: p.userId,
                  userName: p.userName,
                  joinedAt: p.joinedAt,
                  turnOrder: p.turnOrder,
                  isReady: isReady,
                  leftAt: p.leftAt,
                )
              : p)
          .toList();
      state = state.copyWith(players: next);
    }
  }

  /// Host: start the match. The RPC validates 2–4 players and
  /// initializes the board state with all pieces in base.
  Future<String?> startGame() async {
    final gameId = _gameId;
    if (gameId == null) return null;
    final active = state.players.where((p) => p.isActive).length;
    if (active < 2) return 'Ashta Chamma needs at least 2 players';
    state = state.copyWith(isStarting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return null;
      final result = await client.rpc('fn_ashtachamma_start', params: {
        'p_game_id': gameId,
      });
      final map = (result is Map<String, dynamic>)
          ? result
          : Map<String, dynamic>.from(result as Map);
      state = state.copyWith(isStarting: false);
      if (map['ok'] == true) {
        GameMotionTokens.celebrate();
        return null;
      }
      return switch (map['reason']) {
        'not_enough_players' => 'Ashta Chamma needs at least 2 players',
        'too_many_players' => 'Ashta Chamma supports up to 4 players',
        'not_host' => 'Only the host can start',
        'already_started' => null,
        _ => 'Could not start the game',
      };
    } catch (e) {
      debugPrint('[AshtaChamma] startGame error: $e');
      state = state.copyWith(isStarting: false, error: '$e');
      return 'Could not start the game';
    }
  }

  /// The current player rolls the cowrie shells. Server-authoritative;
  /// the optimistic dice value gives instant feedback and is reconciled
  /// when the realtime row arrives.
  Future<void> rollDice() async {
    final gameId = _gameId;
    final game = state.game;
    final myId = _myId;
    if (gameId == null || game == null || myId == null) return;
    if (!state.canRoll) return;

    // Optimistic: show a random preview roll, reconcile via realtime.
    final preview = AshtaChammaDice.random().value;
    state = state.copyWith(optimisticDice: preview);
    GameMotionTokens.tap();

    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_ashtachamma_roll', params: {
        'p_game_id': gameId,
      });
      // The realtime update will deliver the authoritative dice value.
    } catch (e) {
      debugPrint('[AshtaChamma] roll error: $e');
      state = state.copyWith(clearOptimisticDice: true);
    }
  }

  /// The current player moves a piece. Server-authoritative.
  Future<void> movePiece(int pieceIndex) async {
    final gameId = _gameId;
    final game = state.game;
    final myId = _myId;
    if (gameId == null || game == null || myId == null) return;
    if (!state.canMove) return;

    // Optimistic: highlight the tapped piece, reconcile via realtime.
    state = state.copyWith(optimisticMovePieceIndex: pieceIndex);
    GameMotionTokens.tap();

    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_ashtachamma_move', params: {
        'p_game_id': gameId,
        'p_piece_index': pieceIndex,
      });
      // The realtime update will deliver the authoritative board state.
    } catch (e) {
      debugPrint('[AshtaChamma] move error: $e');
      state = state.copyWith(clearOptimisticMove: true);
    }
  }

  /// Leave the game. Host in the waiting room closes the whole room.
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
        await _ref.read(temporaryRoomServiceProvider).cancelWaitingRoom(
              gameTable: 'ashta_chamma_games',
              gameId: gameId,
            );
      } else if (state.amSpectator) {
        await client.rpc('fn_leave_spectator', params: {
          'p_game_table': 'ashta_chamma_games',
          'p_game_id': gameId,
          'p_user_id': myId,
        });
      } else {
        await _tryRpc('fn_ashtachamma_leave', {'p_game_id': gameId});
      }
    } catch (_) {}
    _cleanup();
  }

  /// Host: one-tap rematch. Creates a fresh room with the same settings
  /// and carries the roster over.
  Future<String?> rematch() async {
    final client = _client;
    final game = state.game;
    final myId = _myId;
    if (client == null || game == null || myId == null) return null;

    final roster = List<AshtaChammaPlayer>.from(state.players);

    final newGameId = await createGame(
      maxPlayers: game.maxPlayers,
      roomName: game.roomName,
      spectatorsEnabled: game.spectatorsEnabled,
    );
    if (newGameId == null) return null;

    try {
      final others = roster.where((p) => p.userId != myId).toList();
      if (others.isNotEmpty) {
        await client.from('ashta_chamma_players').upsert(
          others
              .map((p) => {
                    'gameId': newGameId,
                    'userId': p.userId,
                    'userName': p.userName,
                    'turnOrder': p.turnOrder,
                  })
              .toList(),
          onConflict: 'gameId,userId',
        );
        for (final p in others) {
          if (p.userId.isEmpty) continue;
          try {
            await client.rpc('fn_record_room_join', params: {
              'p_game_table': 'ashta_chamma_games',
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
                'gameTable': 'ashta_chamma_games',
                'gameId': newGameId,
                'gameType': 'ashta-chamma',
                'familyId': familyId,
                'roomCode': roomCode,
                'invitedUserId': p.userId,
                'invitedByUserId': myId,
                'invitedByName': _myName,
                'maxPlayers': game.maxPlayers,
                'currentPlayers': 1,
                'message':
                    '$_myName wants an Ashta Chamma rematch — bring your strategy!',
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
      debugPrint('[AshtaChamma] rematch error: $e');
    }
    return newGameId;
  }

  // ── Data loading ─────────────────────────────────────────────────

  Future<void> loadGame(String gameId) async {
    await _loadGame(gameId);
    await _refreshPlayers(gameId);
    _subscribeToRealtime(gameId);
  }

  Future<void> _loadGame(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('ashta_chamma_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (resp == null) return;
      _gameId = gameId;
      _applyGameRow(AshtaChammaGame.fromJson(resp));
    } catch (e) {
      debugPrint('[AshtaChamma] loadGame error: $e');
    }
  }

  void _applyGameRow(AshtaChammaGame game) {
    final previous = state.game;
    final wasCurrentMe = previous?.currentPlayerId == _myId;
    final isCurrentMe = game.currentPlayerId == _myId;

    // Update the static current-user-id so the state's canRoll/canMove
    // getters work.
    AshtaChammaState._currentUserId = _myId;
    state = state.copyWith(game: game);

    // Reconcile optimistic dice/move away once the authoritative row
    // arrives.
    if (state.optimisticDice != null &&
        (game.lastDiceValue != 0 || game.phase != AshtaChammaPhase.move)) {
      state = state.copyWith(clearOptimisticDice: true);
    }
    if (state.optimisticMovePieceIndex != null) {
      // Clear once the board state has advanced (current player changed
      // or phase went back to roll).
      if (game.phase == AshtaChammaPhase.roll ||
          previous?.boardState?.moveHistory.length !=
              game.boardState?.moveHistory.length) {
        state = state.copyWith(clearOptimisticMove: true);
      }
    }

    // Watchdog: while the match runs, ping the server every 2 s so turns
    // expire even if the current player stalls.
    if (game.isInProgress && _watchdogTimer == null) {
      _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _tryRpc('fn_ashtachamma_tick', {'p_game_id': game.id});
      });
    } else if (!game.isInProgress && _watchdogTimer != null) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
    }

    // Turn passed TO me → gentle haptic cue.
    if (game.isInProgress && isCurrentMe && !wasCurrentMe) {
      GameMotionTokens.tap();
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
          .from('ashta_chamma_players')
          .select()
          .eq('gameId', gameId)
          .order('joinedAt', ascending: true);
      final players =
          resp.map((p) => AshtaChammaPlayer.fromJson(p)).toList();
      state = state.copyWith(players: players);
    } catch (e) {
      debugPrint('[AshtaChamma] refreshPlayers error: $e');
    }
  }

  Future<bool> _tryRpc(String fn, Map<String, dynamic> params) async {
    if (_tickInFlight && fn == 'fn_ashtachamma_tick') return false;
    final client = _client;
    if (client == null) return false;
    try {
      if (fn == 'fn_ashtachamma_tick') _tickInFlight = true;
      await client.rpc(fn, params: params);
      return true;
    } catch (e) {
      debugPrint('[AshtaChamma] $fn error: $e');
      return false;
    } finally {
      if (fn == 'fn_ashtachamma_tick') _tickInFlight = false;
    }
  }

  void _scheduleRoomCleanup(String gameId) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'ashta_chamma_games',
            gameId: gameId,
          );
    });
  }

  // ── Realtime subscription ────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    _channel = client
        .channel('ashtachamma_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ashta_chamma_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated = AshtaChammaGame.fromJson(payload.newRecord);
            _applyGameRow(updated);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ashta_chamma_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final player = AshtaChammaPlayer.fromJson(payload.newRecord);
            if (!state.players.any((p) => p.userId == player.userId)) {
              state = state.copyWith(players: [...state.players, player]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ashta_chamma_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final updated = AshtaChammaPlayer.fromJson(payload.newRecord);
            final next = state.players
                .map((p) => p.userId == updated.userId ? updated : p)
                .toList();
            state = state.copyWith(players: next);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'ashta_chamma_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final goneId = payload.oldRecord['userId'] as String?;
            if (goneId == null) return;
            state = state.copyWith(
              players:
                  state.players.where((p) => p.userId != goneId).toList(),
            );
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
    _turnTimer?.cancel();
    _turnTimer = null;
    _gameId = null;
    state = const AshtaChammaState();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _cleanupTimer?.cancel();
    _turnTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}

final ashtaChammaProvider = StateNotifierProvider.autoDispose
    .family<AshtaChammaNotifier, AshtaChammaState, String>(
  (ref, familyId) => AshtaChammaNotifier(ref, familyId),
);
