// lib/features/games/tictactoe/tictactoe_provider.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import '../shared/services/room_presence_heartbeat.dart';
import '../shared/services/temporary_room_service.dart';
import 'tictactoe_game_logic.dart';
import 'tictactoe_models.dart';

class TttState {
  const TttState({this.game, this.rounds = const [], this.moves = const [], this.isLoading = false, this.isSubmitting = false, this.error, this.winningLine});
  final TttGame? game; final List<TttRound> rounds; final List<TttMoveRecord> moves;
  final bool isLoading; final bool isSubmitting; final String? error; final List<int>? winningLine;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  TttRound? get currentRound => rounds.isEmpty ? null : rounds.last;
  List<String?> get currentBoard => currentRound?.boardState ?? createEmptyBoard();

  TttState copyWith({TttGame? game, List<TttRound>? rounds, List<TttMoveRecord>? moves, bool? isLoading, bool? isSubmitting, String? error, bool clearError = false, List<int>? winningLine, bool clearWinningLine = false}) =>
    TttState(game: game ?? this.game, rounds: rounds ?? this.rounds, moves: moves ?? this.moves, isLoading: isLoading ?? this.isLoading, isSubmitting: isSubmitting ?? this.isSubmitting, error: clearError ? null : (error ?? this.error), winningLine: clearWinningLine ? null : (winningLine ?? this.winningLine));
}

class TttNotifier extends StateNotifier<TttState> {
  TttNotifier(this._ref, this.familyId) : super(const TttState());
  final Ref _ref; final String familyId;
  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName => _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';
  RealtimeChannel? _channel; String? _gameId;

  /// DB presence heartbeat — keeps the players' game_participants rows
  /// fresh so the disconnect reaper never hard-deletes a live room.
  RoomPresenceHeartbeat? _heartbeat;

  /// Host: create a new room (Create Room flow).
  ///
  /// The room is created immediately with ONLY the host attached (X)
  /// and status 'waiting' — no opponent is picked up front. The first
  /// family member to join takes O automatically via [joinRoom].
  Future<String?> createRoom({required bool spectatorsEnabled, int bestOf = 1}) async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return null; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      final resp = await client.from('tictactoe_games').insert({
        'familyId': familyId, 'hostUserId': myId, 'hostUserName': _myName,
        'playerXId': myId, 'playerXName': _myName,
        // playerOId stays NULL until an opponent joins the room.
        'currentTurnPlayerId': myId, 'bestOf': bestOf, 'roundsWonX': 0, 'roundsWonO': 0, 'currentRound': 1,
        'status': 'waiting',
        'spectatorsEnabled': spectatorsEnabled, 'hostReady': true,
        'autoCloseDeadline': deadline.toIso8601String(),
      }).select().single();
      final game = TttGame.fromJson(resp as Map<String, dynamic>);
      _gameId = game.id;
      // Create round 1 (kept empty while the room waits for a joiner).
      await client.from('tictactoe_rounds').insert({'gameId': game.id, 'roundNumber': 1, 'boardState': createEmptyBoard()});

      // Register the host in the shared room bookkeeping (roster +
      // 'join' lobby event + ecosystem archive).
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'tictactoe_games',
        'p_game_id': game.id,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': 'host',
      });

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      await _refreshRounds(game.id);
      return game.id;
    } catch (e) { debugPrint('[TTT] createRoom error: $e'); state = state.copyWith(isLoading: false, error: '$e'); return null; }
  }

  /// Non-host: join an existing room.
  ///
  /// • Room closed / deleted → friendly error (create a new room).
  /// • Waiting + O's slot free → take it (first member to join wins
  ///   the slot — no manual side picking).
  /// • Waiting + slot taken → 'Game is full' (1v1).
  /// • Match already running → spectate read-only.
  Future<bool> joinRoom(String gameId) async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return false; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var gameResp = await client.from('tictactoe_games').select().eq('id', gameId).maybeSingle();
      if (isRoomRowClosed(gameResp)) { state = state.copyWith(isLoading: false, error: kRoomClosedMessage); return false; }
      var game = TttGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = gameId;

      final alreadyPlayer = game.playerXId == myId || game.playerOId == myId;

      if (!alreadyPlayer) {
        if (game.isWaiting) {
          if (game.needsOpponent) {
            // Take the opponent slot.
            await client.from('tictactoe_games').update({
              'playerOId': myId, 'playerOName': _myName,
            }).eq('id', gameId);
            await client.rpc('fn_record_room_join', params: {
              'p_game_table': 'tictactoe_games',
              'p_game_id': gameId,
              'p_family_id': familyId,
              'p_user_id': myId,
              'p_user_name': _myName,
              'p_role': 'player',
            });
            await _ref.read(temporaryRoomServiceProvider).touchActivity(
                  gameTable: 'tictactoe_games', gameId: gameId);
            // Re-fetch so the local state carries the filled slot.
            gameResp = await client.from('tictactoe_games').select().eq('id', gameId).maybeSingle();
            if (gameResp != null) { game = TttGame.fromJson(gameResp); }
          } else {
            state = state.copyWith(isLoading: false, error: 'Game is full');
            return false;
          }
        } else if (game.isInProgress) {
          // Match already running — watch from the sidelines.
          await client.rpc('fn_spectate_game', params: {
            'p_game_table': 'tictactoe_games',
            'p_game_id': gameId,
            'p_family_id': familyId,
            'p_user_id': myId,
            'p_user_name': _myName,
          });
        }
      }

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshRounds(gameId);
      // Keep the persistent game-invite chat card in sync. Best-effort.
      final playerCount = 1 + (game.needsOpponent ? 0 : 1);
      unawaited(syncGameInviteChatCards(client: client, gameId: gameId, currentPlayers: playerCount));
      return true;
    } catch (e) { debugPrint('[TTT] joinRoom error: $e'); state = state.copyWith(isLoading: false, error: '$e'); return false; }
  }

  /// Host: start the match from the waiting room. Returns a
  /// user-readable error message, or null on success.
  Future<String?> startMatch() async {
    final client = _client; final gameId = _gameId; final game = state.game; final myId = _myId;
    if (client == null || gameId == null || game == null) return 'No active room';
    if (game.hostUserId != null && game.hostUserId != myId) return 'Only the host can start';
    if (game.needsOpponent) return 'Waiting for an opponent to join';
    try {
      await client.from('tictactoe_games').update({
        'status': 'in_progress', 'startedAt': DateTime.now().toIso8601String(),
      }).eq('id', gameId);
      // Lobby chat log entry — same event the room framework posts.
      try {
        await client.from('game_room_events').insert({
          'gameTable': 'tictactoe_games', 'gameId': gameId, 'familyId': familyId,
          'userId': myId, 'userName': _myName, 'eventType': 'match_start', 'payload': {},
        });
      } catch (_) {}
      return null;
    } catch (e) { debugPrint('[TTT] startMatch error: $e'); return 'Could not start the match'; }
  }

  /// Leave the waiting room. Host → the room is closed and deleted for
  /// everyone; guest → their slot is freed for another family member.
  Future<void> leaveRoom() async {
    final client = _client; final gameId = _gameId; final myId = _myId; final game = state.game;
    if (client == null || gameId == null || myId == null) { _reset(); return; }
    try {
      if (game != null && game.isWaiting) {
        if (game.hostUserId == myId) {
          await _ref.read(temporaryRoomServiceProvider).cancelWaitingRoom(
                gameTable: 'tictactoe_games', gameId: gameId);
        } else {
          await client.rpc('fn_leave_game_room', params: {
            'p_game_table': 'tictactoe_games', 'p_game_id': gameId, 'p_user_id': myId,
          });
        }
      }
    } catch (_) {}
    _reset();
  }

  /// Drop all local room state (after leave/close) so the lobby falls
  /// back to the fresh setup screen — a closed room can never reappear.
  void _reset() {
    _channel?.unsubscribe();
    _channel = null;
    _heartbeat?.stop();
    _heartbeat = null;
    _gameId = null;
    state = const TttState();
  }

  Future<bool> loadGame(String gameId) async {
    final client = _client;
    if (client == null) { state = state.copyWith(error: 'Not signed in'); return false; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // maybeSingle → a deleted (closed) room returns null instead of
      // throwing, so we can show a friendly "room closed" message and
      // send the user back to create a new room.
      final gameResp = await client.from('tictactoe_games').select().eq('id', gameId).maybeSingle();
      if (isRoomRowClosed(gameResp)) { state = const TttState(error: kRoomClosedMessage); return false; }
      final game = TttGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = gameId;
      final roundsResp = await client.from('tictactoe_rounds').select().eq('gameId', gameId).order('roundNumber', ascending: true);
      final rounds = roundsResp.map((r) => TttRound.fromJson(r as Map<String, dynamic>)).toList();
      final movesResp = await client.from('tictactoe_moves').select().eq('roundId', rounds.last.id).order('moveNumber', ascending: true);
      final moves = movesResp.map((m) => TttMoveRecord.fromJson(m as Map<String, dynamic>)).toList();
      // Check for winning line
      List<int>? winLine;
      if (rounds.last.result != null && rounds.last.result != RoundResult.draw && rounds.last.result != RoundResult.ongoing) {
        winLine = checkWinner(rounds.last.boardState);
      }
      state = state.copyWith(game: game, rounds: rounds, moves: moves, isLoading: false, winningLine: winLine);
      _subscribeToRealtime(gameId);
      return true;
    } catch (e) { debugPrint('[TTT] loadGame error: $e'); state = state.copyWith(isLoading: false, error: '$e'); return false; }
  }

  Future<bool> placeMark(int cellIndex) async {
    final client = _client; final gameId = _gameId; final myId = _myId; final game = state.game;
    if (client == null || gameId == null || myId == null || game == null) return false;
    if (!game.isMyTurn(myId)) return false;
    final myMark = game.markForPlayer(myId);
    if (myMark == null) return false;
    final board = state.currentBoard;
    final error = validateMove(board: board, cellIndex: cellIndex, mark: myMark, expectedMark: myMark);
    if (error != null) { GameMotionTokens.error(); state = state.copyWith(error: error); return false; }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final currentRound = state.currentRound!;
      final moveNumber = state.moves.length + 1;
      // Insert move
      await client.from('tictactoe_moves').insert({'roundId': currentRound.id, 'playerId': myId, 'playerName': _myName, 'cellIndex': cellIndex, 'mark': myMark.name, 'moveNumber': moveNumber});
      // Update board
      final newBoard = List<String?>.from(board); newBoard[cellIndex] = myMark.name;
      await client.from('tictactoe_rounds').update({'boardState': newBoard}).eq('id', currentRound.id);

      // Check round result
      final result = getRoundResult(newBoard);
      final opponentId = game.idForMark(myMark.opposite)!;

      if (result == RoundResult.ongoing) {
        // Next turn
        await client.from('tictactoe_games').update({'currentTurnPlayerId': opponentId}).eq('id', gameId);
        GameMotionTokens.tap();
      } else {
        // Round over
        await client.from('tictactoe_rounds').update({'result': result.name, 'completedAt': DateTime.now().toIso8601String()}).eq('id', currentRound.id);

        int newRoundsWonX = game.roundsWonX;
        int newRoundsWonO = game.roundsWonO;
        if (result == RoundResult.xWin) newRoundsWonX++;
        if (result == RoundResult.oWin) newRoundsWonO++;

        final matchWinner = getMatchWinner(newRoundsWonX, newRoundsWonO, game.bestOf);
        if (matchWinner != null) {
          // Match over
          final winnerId = game.idForMark(matchWinner)!;
          final winnerName = game.nameForMark(matchWinner);
          await client.from('tictactoe_games').update({
            'status': 'completed', 'completedAt': DateTime.now().toIso8601String(),
            'lastActivityAt': DateTime.now().toIso8601String(),
            'roundsWonX': newRoundsWonX, 'roundsWonO': newRoundsWonO, 'overallWinnerId': winnerId, 'overallWinnerName': winnerName,
          }).eq('id', gameId);
          GameMotionTokens.celebrate();
          _scheduleRoomCleanup(gameId);
        } else {
          // Next round
          await client.from('tictactoe_games').update({'roundsWonX': newRoundsWonX, 'roundsWonO': newRoundsWonO, 'currentRound': game.currentRound + 1, 'currentTurnPlayerId': game.playerXId}).eq('id', gameId);
          await client.from('tictactoe_rounds').insert({'gameId': gameId, 'roundNumber': game.currentRound + 1, 'boardState': createEmptyBoard()});
          // Winner of the round goes first next round? Or always X? Standard: X always goes first.
          if (result == RoundResult.xWin || result == RoundResult.oWin) {
            GameMotionTokens.celebrate();
          } else {
            GameMotionTokens.tap();
          }
        }
        // Show winning line
        final winLine = checkWinner(newBoard);
        state = state.copyWith(isSubmitting: false, winningLine: winLine);
        return true;
      }

      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e) { debugPrint('[TTT] placeMark error: $e'); state = state.copyWith(isSubmitting: false, error: '$e'); return false; }
  }

  void leaveGame() { _channel?.unsubscribe(); _channel = null; _heartbeat?.stop(); _heartbeat = null; _gameId = null; }

  /// Schedule the temporary room (and all temporary player associations)
  /// for deletion 30s after the game ends. The hourly pg_cron job is the
  /// safety net if the user closes the app before this fires.
  void _scheduleRoomCleanup(String gameId) {
    Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'tictactoe_games',
            gameId: gameId,
          );
    });
  }

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client; if (client == null) return;
    // Keep the participant row fresh while this screen owns the room.
    final hbId = _myId;
    if (hbId != null) {
      _heartbeat?.stop();
      _heartbeat = RoomPresenceHeartbeat('tictactoe_games')..start(client, gameId, hbId);
    }
    _channel = client.channel('ttt_game:$gameId')
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'tictactoe_games',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
        callback: (payload) { final updated = TttGame.fromJson(payload.newRecord); if (updated.isCompleted) GameMotionTokens.celebrate(); state = state.copyWith(game: updated); })
      // ── Game row DELETE = the room was closed by the host (or the
      //    opponent left) → fn_end_game hard-deleted it. Show a friendly
      //    "room closed" state instead of hanging on a dead board.
      .onPostgresChanges(event: PostgresChangeEvent.delete, schema: 'public', table: 'tictactoe_games',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
        callback: (payload) {
          debugPrint('[TTT] game row deleted — room closed');
          _channel?.unsubscribe(); _channel = null; _gameId = null;
          // Completed games are archived + deleted server-side right
          // after the results screen renders — keep the in-memory
          // state so the results view survives the cleanup delete.
          if (state.game?.isCompleted ?? false) return;
          state = const TttState(error: kRoomClosedMessage);
        })
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'tictactoe_rounds',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) async {
          final updated = TttRound.fromJson(payload.newRecord);
          final next = state.rounds.map((r) => r.id == updated.id ? updated : r).toList();
          if (!next.any((r) => r.id == updated.id)) next.add(updated);
          // Check for winning line
          List<int>? winLine;
          if (updated.result != null && updated.result != RoundResult.draw && updated.result != RoundResult.ongoing) {
            winLine = checkWinner(updated.boardState);
          }
          state = state.copyWith(rounds: next, winningLine: winLine, clearWinningLine: winLine != null ? false : true);
        })
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'tictactoe_rounds',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) {
          final round = TttRound.fromJson(payload.newRecord);
          if (!state.rounds.any((r) => r.id == round.id)) { state = state.copyWith(rounds: [...state.rounds, round], winningLine: null); }
        })
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'tictactoe_moves',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'roundId', value: state.currentRound?.id ?? ''),
        callback: (payload) {
          final move = TttMoveRecord.fromJson(payload.newRecord);
          if (!state.moves.any((m) => m.id == move.id)) { state = state.copyWith(moves: [...state.moves, move]); }
        })
      .subscribe();
  }

  Future<void> _refreshRounds(String gameId) async {
    final client = _client; if (client == null) return;
    try {
      final resp = await client.from('tictactoe_rounds').select().eq('gameId', gameId).order('roundNumber', ascending: true);
      state = state.copyWith(rounds: resp.map((r) => TttRound.fromJson(r as Map<String, dynamic>)).toList());
    } catch (e) { debugPrint('[TTT] refreshRounds error: $e'); }
  }

  @override
  void dispose() { _channel?.unsubscribe(); _heartbeat?.stop(); super.dispose(); }
}

final tttProvider = StateNotifierProvider.autoDispose.family<TttNotifier, TttState, String>((ref, familyId) => TttNotifier(ref, familyId));
