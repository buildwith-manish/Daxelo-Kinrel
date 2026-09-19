// lib/features/games/checkers/checkers_provider.dart
//
// Checkers — Riverpod state + Supabase Realtime for live move sync.
//
// Architecture:
//   • Supabase stores games + moves
//   • Game logic (validation, captures, multi-jump, king promotion) runs
//     client-side via checkers_game_logic.dart — same logic runs on both
//     players' devices, ensuring consistency
//   • Supabase Realtime broadcasts board state updates + new moves
//   • The current player applies a move locally (validation + state update),
//     then persists the new board state + move record to Supabase

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import '../shared/services/room_presence_heartbeat.dart';
import '../shared/services/temporary_room_service.dart';
import 'checkers_game_logic.dart';
import 'checkers_models.dart';

class CheckersState {
  const CheckersState({
    this.game,
    this.moves = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.selectedRow,
    this.selectedCol,
    this.legalMoves = const [],
    this.lastMove,
    this.lastCapture,
    this.lastKingPromotion,
  });

  final CheckersGame? game;
  final List<CheckersMoveRecord> moves;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  // Selection state (UI-only, not persisted)
  final int? selectedRow;
  final int? selectedCol;
  final List<CheckersMove> legalMoves;

  // Animation triggers (UI-only)
  final CheckersMove? lastMove;
  final CheckersMove? lastCapture;
  final (int, int)? lastKingPromotion; // (row, col) of the promoted piece

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  CheckersState copyWith({
    CheckersGame? game,
    List<CheckersMoveRecord>? moves,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
    int? selectedRow,
    int? selectedCol,
    bool clearSelection = false,
    List<CheckersMove>? legalMoves,
    CheckersMove? lastMove,
    CheckersMove? lastCapture,
    (int, int)? lastKingPromotion,
    bool clearAnimTriggers = false,
  }) =>
      CheckersState(
        game: game ?? this.game,
        moves: moves ?? this.moves,
        isLoading: isLoading ?? this.isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        selectedRow: clearSelection ? null : (selectedRow ?? this.selectedRow),
        selectedCol: clearSelection ? null : (selectedCol ?? this.selectedCol),
        legalMoves: legalMoves ?? this.legalMoves,
        lastMove: clearAnimTriggers ? null : (lastMove ?? this.lastMove),
        lastCapture:
            clearAnimTriggers ? null : (lastCapture ?? this.lastCapture),
        lastKingPromotion: clearAnimTriggers
            ? null
            : (lastKingPromotion ?? this.lastKingPromotion),
      );
}

class CheckersNotifier extends StateNotifier<CheckersState> {
  CheckersNotifier(this._ref, this.familyId) : super(const CheckersState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;

  /// DB presence heartbeat — keeps the players' game_participants rows
  /// fresh so the disconnect reaper never hard-deletes a live room.
  RoomPresenceHeartbeat? _heartbeat;
  String? _gameId;
  Timer? _cleanupTimer;

  // ── Public API ───────────────────────────────────────────────────

  /// Host: create a new room (Create Room flow).
  ///
  /// The room is created immediately with ONLY the host attached
  /// (Player One, red) and status 'waiting' — no opponent is picked up
  /// front. The first family member to join takes Player Two (black)
  /// automatically via [joinRoom].
  Future<String?> createRoom({required bool spectatorsEnabled}) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      final resp = await client.from('checkers_games').insert({
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'playerOneId': myId,
        'playerOneName': _myName,
        // playerTwoId stays NULL until an opponent joins the room.
        'currentTurnPlayerId': myId, // red moves first
        'boardState': boardToJson(createInitialBoard()),
        'status': 'waiting',
        'mandatoryCapturePending': false,
        'playerOneCaptured': 0,
        'playerTwoCaptured': 0,
        'spectatorsEnabled': spectatorsEnabled,
        'hostReady': true,
        'autoCloseDeadline': deadline.toIso8601String(),
      }).select().single();
      final game = CheckersGame.fromJson(resp);
      _gameId = game.id;

      // Register the host in the shared room bookkeeping (roster +
      // 'join' lobby event + ecosystem archive).
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'checkers_games',
        'p_game_id': game.id,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': 'host',
      });

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[Checkers] createRoom error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  /// Non-host: join an existing room.
  ///
  /// • Room closed / deleted → friendly error (create a new room).
  /// • Waiting + Player Two's slot free → take it (first member to
  ///   join wins the slot — no manual side picking).
  /// • Waiting + slot taken → 'Game is full' (1v1).
  /// • Match already running → spectate read-only.
  Future<bool> joinRoom(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var gameResp = await client
          .from('checkers_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (isRoomRowClosed(gameResp)) {
        state = state.copyWith(isLoading: false, error: kRoomClosedMessage);
        return false;
      }
      var game = CheckersGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      final alreadyPlayer =
          game.playerOneId == myId || game.playerTwoId == myId;

      if (!alreadyPlayer) {
        if (game.isWaiting) {
          if (!game.needsOpponent) {
            state = state.copyWith(
                isLoading: false, error: 'Game is full');
            return false;
          }
          // Take the opponent slot.
          await client.from('checkers_games').update({
            'playerTwoId': myId,
            'playerTwoName': _myName,
          }).eq('id', gameId);
          await client.rpc('fn_record_room_join', params: {
            'p_game_table': 'checkers_games',
            'p_game_id': gameId,
            'p_family_id': familyId,
            'p_user_id': myId,
            'p_user_name': _myName,
            'p_role': 'player',
          });
          await _ref.read(temporaryRoomServiceProvider).touchActivity(
                gameTable: 'checkers_games',
                gameId: gameId,
              );
          // Re-fetch so the local state carries the filled slot.
          gameResp = await client
              .from('checkers_games')
              .select()
              .eq('id', gameId)
              .maybeSingle();
          if (gameResp != null) {
            game = CheckersGame.fromJson(gameResp);
          }
        } else if (game.isInProgress) {
          // Match already running — watch from the sidelines.
          await client.rpc('fn_spectate_game', params: {
            'p_game_table': 'checkers_games',
            'p_game_id': gameId,
            'p_family_id': familyId,
            'p_user_id': myId,
            'p_user_name': _myName,
          });
        }
      }

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      // Keep the persistent game-invite chat card in sync. Best-effort.
      final playerCount = 1 + (game.needsOpponent ? 0 : 1);
      unawaited(
        syncGameInviteChatCards(
          client: client,
          gameId: gameId,
          currentPlayers: playerCount,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[Checkers] joinRoom error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Host: start the match from the waiting room. Returns a
  /// user-readable error message, or null on success.
  Future<String?> startMatch() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    final myId = _myId;
    if (client == null || gameId == null || game == null) {
      return 'No active room';
    }
    if (game.hostUserId != null && game.hostUserId != myId) {
      return 'Only the host can start';
    }
    if (game.needsOpponent) {
      return 'Waiting for an opponent to join';
    }
    try {
      await client.from('checkers_games').update({
        'status': 'in_progress',
        'startedAt': DateTime.now().toIso8601String(),
      }).eq('id', gameId);
      // Lobby chat log entry — same event the room framework posts.
      try {
        await client.from('game_room_events').insert({
          'gameTable': 'checkers_games',
          'gameId': gameId,
          'familyId': familyId,
          'userId': myId,
          'userName': _myName,
          'eventType': 'match_start',
          'payload': {},
        });
      } catch (_) {}
      return null;
    } catch (e) {
      debugPrint('[Checkers] startMatch error: $e');
      return 'Could not start the match';
    }
  }

  /// Leave the waiting room. Host → the room is closed and deleted for
  /// everyone; guest → their slot is freed for another family member.
  Future<void> leaveRoom() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final game = state.game;
    if (client == null || gameId == null || myId == null) {
      _reset();
      return;
    }
    try {
      if (game != null && game.isWaiting) {
        if (game.hostUserId == myId) {
          await _ref.read(temporaryRoomServiceProvider).cancelWaitingRoom(
                gameTable: 'checkers_games',
                gameId: gameId,
              );
        } else {
          await client.rpc('fn_leave_game_room', params: {
            'p_game_table': 'checkers_games',
            'p_game_id': gameId,
            'p_user_id': myId,
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
    state = const CheckersState();
  }

  /// Join an existing game (load state for the board screen).
  Future<bool> loadGame(String gameId) async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // maybeSingle → a deleted (closed) room returns null instead of
      // throwing, so we can show a friendly "room closed" message and
      // send the user back to create a new room.
      final gameResp = await client
          .from('checkers_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (isRoomRowClosed(gameResp)) {
        state = const CheckersState(error: kRoomClosedMessage);
        return false;
      }
      final game = CheckersGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      final movesResp = await client
          .from('checkers_moves')
          .select()
          .eq('gameId', gameId)
          .order('moveNumber', ascending: true);
      final moves = movesResp
          .map((m) => CheckersMoveRecord.fromJson(m))
          .toList();

      state = state.copyWith(game: game, moves: moves, isLoading: false);
      _subscribeToRealtime(gameId);
      return true;
    } catch (e) {
      debugPrint('[Checkers] loadGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Select a piece at (row, col). Updates legal moves for that piece.
  void selectPiece(int row, int col) {
    final game = state.game;
    if (game == null || !game.isInProgress) return;
    final myId = _myId;
    if (myId == null) return;

    // Can only select your own pieces on your turn
    final piece = game.boardState[row][col];
    if (piece == null) return;
    if (piece.player != game.playerNumberFor(myId)) return;
    if (game.currentTurnPlayerId != myId) return;

    final legalMoves = getLegalMovesForPiece(
      game.boardState,
      row,
      col,
      forcedPieceRow: game.multiJumpPieceRow,
      forcedPieceCol: game.multiJumpPieceCol,
    );

    state = state.copyWith(
      selectedRow: row,
      selectedCol: col,
      legalMoves: legalMoves,
    );
    GameMotionTokens.tap();
  }

  /// Clear the current selection.
  void clearSelection() {
    state = state.copyWith(clearSelection: true, legalMoves: const []);
  }

  /// Attempt to move the selected piece to (toRow, toCol).
  Future<bool> makeMove(int toRow, int toCol) async {
    // Double-tap guard — a second tap while the first move's DB writes
    // are still in flight must be a no-op (a stale selection can
    // null-assert in applyMove and corrupt the board).
    if (state.isSubmitting) return false;
    final game = state.game;
    final client = _client;
    final myId = _myId;
    if (game == null || client == null || myId == null) return false;
    // Re-check turn + status against the CURRENT state — a realtime
    // update may have flipped the turn since the piece was selected.
    if (!game.isInProgress || game.currentTurnPlayerId != myId) {
      return false;
    }
    if (state.selectedRow == null || state.selectedCol == null) return false;

    final fromRow = state.selectedRow!;
    final fromCol = state.selectedCol!;

    // Find the matching legal move
    final move = state.legalMoves
        .where((m) => m.toRow == toRow && m.toCol == toCol)
        .firstOrNull;
    if (move == null) {
      GameMotionTokens.error();
      return false;
    }

    // Re-validate against the CURRENT board — state.legalMoves was
    // computed at selection time and may be stale.
    final myPlayerNumber = game.playerNumberFor(myId);
    if (myPlayerNumber == null) return false;
    final validationError = validateMove(
      board: game.boardState,
      playerId: myPlayerNumber,
      move: move,
      forcedPieceRow: game.multiJumpPieceRow,
      forcedPieceCol: game.multiJumpPieceCol,
    );
    if (validationError != null) {
      GameMotionTokens.error();
      state = state.copyWith(clearSelection: true, legalMoves: const []);
      return false;
    }

    // Lock submissions + drop the selection synchronously BEFORE any
    // await, so a racing second tap can never re-enter with stale state.
    state = state.copyWith(
      isSubmitting: true,
      clearError: true,
      clearSelection: true,
      legalMoves: const [],
    );
    try {
      // Apply the move locally
      final result = applyMove(game.boardState, move);
      final opponentPlayerNumber = myPlayerNumber == 1 ? 2 : 1;

      // Update captured count
      int newPlayerOneCaptured = game.playerOneCaptured;
      int newPlayerTwoCaptured = game.playerTwoCaptured;
      if (move.isCapture) {
        if (myPlayerNumber == 1) {
          newPlayerOneCaptured++;
        } else {
          newPlayerTwoCaptured++;
        }
      }

      // Determine if multi-jump continues
      final continuesCapture = result.canContinueCapture;

      // Determine next turn player
      String nextTurnPlayerId;
      bool newMandatoryCapturePending = false;
      int? newMultiJumpRow;
      int? newMultiJumpCol;

      if (continuesCapture) {
        // Same player continues
        nextTurnPlayerId = myId;
        newMandatoryCapturePending = true;
        newMultiJumpRow = move.toRow;
        newMultiJumpCol = move.toCol;
      } else {
        // Switch turns
        nextTurnPlayerId = game.idForPlayer(opponentPlayerNumber)!;
        newMandatoryCapturePending = false;
        newMultiJumpRow = null;
        newMultiJumpCol = null;
      }

      // Check game over
      final nextPlayerNumber = continuesCapture
          ? myPlayerNumber
          : opponentPlayerNumber;
      final winner = checkGameOver(result.board, nextPlayerNumber);

      // Build update
      final updateBody = <String, dynamic>{
        'boardState': boardToJson(result.board),
        'currentTurnPlayerId': nextTurnPlayerId,
        'mandatoryCapturePending': newMandatoryCapturePending,
        'multiJumpPieceRow': newMultiJumpRow,
        'multiJumpPieceCol': newMultiJumpCol,
        'playerOneCaptured': newPlayerOneCaptured,
        'playerTwoCaptured': newPlayerTwoCaptured,
      };

      if (winner != null) {
        updateBody['status'] = 'completed';
        updateBody['completedAt'] = DateTime.now().toIso8601String();
        updateBody['lastActivityAt'] = DateTime.now().toIso8601String();
        updateBody['winnerId'] = game.idForPlayer(winner);
        updateBody['winnerName'] = game.nameForPlayer(winner);
      }

      // Insert move record
      final moveNumber = state.moves.length + 1;
      await client.from('checkers_moves').insert({
        'gameId': game.id,
        'playerId': myId,
        'playerName': _myName,
        'fromRow': fromRow,
        'fromCol': fromCol,
        'toRow': toRow,
        'toCol': toCol,
        'wasCapture': move.isCapture,
        'capturedRow': move.capturedRow,
        'capturedCol': move.capturedCol,
        'becameKing': result.becameKing,
        'moveNumber': moveNumber,
      });

      // Update game state
      await client
          .from('checkers_games')
          .update(updateBody)
          .eq('id', game.id);

      // Schedule the temporary room (and all temporary player associations)
      // for deletion 30s after the game ends. Pattern A games have no
      // lobby/waiting phase, so this is the only cleanup hook we need.
      // The hourly pg_cron job is the safety net if the user closes the
      // app before this fires.
      if (winner != null) {
        _scheduleRoomCleanup(game.id);
      }

      // Update local state immediately for responsive UI
      final updatedGame = CheckersGame(
        id: game.id,
        familyId: game.familyId,
        playerOneId: game.playerOneId,
        playerOneName: game.playerOneName,
        playerTwoId: game.playerTwoId,
        playerTwoName: game.playerTwoName,
        currentTurnPlayerId: nextTurnPlayerId,
        boardState: result.board,
        status: winner != null
            ? CheckersStatus.completed
            : CheckersStatus.inProgress,
        winnerId: winner != null ? game.idForPlayer(winner) : null,
        winnerName: winner != null ? game.nameForPlayer(winner) : null,
        mandatoryCapturePending: newMandatoryCapturePending,
        multiJumpPieceRow: newMultiJumpRow,
        multiJumpPieceCol: newMultiJumpCol,
        playerOneCaptured: newPlayerOneCaptured,
        playerTwoCaptured: newPlayerTwoCaptured,
        startedAt: game.startedAt,
        completedAt: winner != null ? DateTime.now() : null,
        createdAt: game.createdAt,
      );

      // Haptics
      if (winner != null) {
        GameMotionTokens.celebrate();
      } else if (move.isCapture) {
        GameMotionTokens.success();
      } else {
        GameMotionTokens.tap();
      }

      state = state.copyWith(
        game: updatedGame,
        isSubmitting: false,
        clearSelection: true,
        legalMoves: const [],
        lastMove: move,
        lastCapture: move.isCapture ? move : null,
        lastKingPromotion:
            result.becameKing ? (move.toRow, move.toCol) : null,
      );

      return true;
    } catch (e) {
      debugPrint('[Checkers] makeMove error: $e');
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }

  /// Leave the game (manual exit).
  void leaveGame() {
    _channel?.unsubscribe();
    _channel = null;
    _gameId = null;
  }

  /// Schedule the temporary room (and all temporary player associations)
  /// for deletion 30s after the game ends. The hourly pg_cron job is the
  /// safety net if the user closes the app before this fires.
  void _scheduleRoomCleanup(String gameId) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'checkers_games',
            gameId: gameId,
          );
    });
  }

  // ── Realtime subscription ────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    // Keep the participant row fresh while this screen owns the room.
    final myId = _myId;
    if (myId != null) {
      _heartbeat?.stop();
      _heartbeat = RoomPresenceHeartbeat('checkers_games')
        ..start(client, gameId, myId);
    }

    _channel = client
        .channel('checkers_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'checkers_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated = CheckersGame.fromJson(payload.newRecord);
            state = state.copyWith(game: updated);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'checkers_moves',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final move = CheckersMoveRecord.fromJson(payload.newRecord);
            if (!state.moves.any((m) => m.id == move.id)) {
              state = state.copyWith(moves: [...state.moves, move]);
            }
          },
        )
        // ── Game row DELETE = the room was closed by the host (or the
        //    opponent left) → fn_end_game hard-deleted it. Show a friendly
        //    "room closed" state instead of hanging on a dead board.
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'checkers_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            debugPrint('[Checkers] game row deleted — room closed');
            _channel?.unsubscribe();
            _channel = null;
            _gameId = null;
            // Completed games are archived + deleted server-side right
            // after the results screen renders — keep the in-memory
            // state so the results view survives the cleanup delete.
            if (state.game?.isCompleted ?? false) return;
            state = const CheckersState(error: kRoomClosedMessage);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _heartbeat?.stop();
    _cleanupTimer?.cancel();
    super.dispose();
  }
}

final checkersProvider = StateNotifierProvider.autoDispose
    .family<CheckersNotifier, CheckersState, String>(
  (ref, familyId) => CheckersNotifier(ref, familyId),
);
