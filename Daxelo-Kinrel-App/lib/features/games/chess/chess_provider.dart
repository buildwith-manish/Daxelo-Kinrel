// lib/features/games/chess/chess_provider.dart
//
// Chess — Riverpod state + Supabase Realtime + chess.dart logic engine.
//
// Architecture:
//   • Supabase stores games + moves
//   • Supabase Realtime broadcasts board state + new moves
//   • The chess.dart package (MIT+BSD) handles all rules: move validation,
//     check/checkmate/stalemate, castling, en passant, promotion, FEN, SAN
//   • The current player applies a move locally (validated by chess.dart),
//     then persists the new FEN + move record to Supabase
//
// License attribution: chess.dart is MIT licensed (David Kopec) + BSD-2
// (Jeff Hlywa's chess.js). All UI is original to Kinrel.

import 'dart:async';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import '../shared/services/room_presence_heartbeat.dart';
import '../shared/services/temporary_room_service.dart';
import 'chess_models.dart';

class ChessState {
  const ChessState({
    this.game,
    this.moves = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.selectedSquare,
    this.legalDestinations = const [],
    this.lastMove,
    this.inCheck = false,
    this.isCheckmate = false,
    this.isStalemate = false,
  });

  final ChessGame? game;
  final List<ChessMoveRecord> moves;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  // Selection state (UI-only)
  final String? selectedSquare; // e.g. 'e2'
  final List<String> legalDestinations; // e.g. ['e3', 'e4']

  // Animation trigger
  final (String, String)? lastMove; // (from, to)

  // Game state flags (derived from chess.dart)
  final bool inCheck;
  final bool isCheckmate;
  final bool isStalemate;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  ChessState copyWith({
    ChessGame? game,
    List<ChessMoveRecord>? moves,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
    String? selectedSquare,
    bool clearSelection = false,
    List<String>? legalDestinations,
    (String, String)? lastMove,
    bool? inCheck,
    bool? isCheckmate,
    bool? isStalemate,
  }) =>
      ChessState(
        game: game ?? this.game,
        moves: moves ?? this.moves,
        isLoading: isLoading ?? this.isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        selectedSquare:
            clearSelection ? null : (selectedSquare ?? this.selectedSquare),
        legalDestinations: legalDestinations ?? this.legalDestinations,
        lastMove: lastMove ?? this.lastMove,
        inCheck: inCheck ?? this.inCheck,
        isCheckmate: isCheckmate ?? this.isCheckmate,
        isStalemate: isStalemate ?? this.isStalemate,
      );
}

class ChessNotifier extends StateNotifier<ChessState> {
  ChessNotifier(this._ref, this.familyId) : super(const ChessState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;

  /// DB presence heartbeat — keeps the host/opponent's
  /// game_participants row fresh so the room framework's disconnect
  /// reaper never hard-deletes a live match (see RoomPresenceHeartbeat).
  RoomPresenceHeartbeat? _heartbeat;
  String? _gameId;
  chess.Chess? _logic;

  // ── Public API ───────────────────────────────────────────────────

  /// Host: create a new room (Create Room flow).
  ///
  /// The room is created immediately with ONLY the host attached
  /// (White) and status 'waiting' — no opponent is picked up front.
  /// The host lands in the shared waiting room, invites family members
  /// (or shares the room code), and the FIRST member to join takes the
  /// Black side automatically via [joinRoom].
  Future<String?> createRoom({required bool spectatorsEnabled}) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    // Rematch guard — drop the previous game's local state (moves /
    // lastMove / game) entirely. The board screen skips loadGame when
    // state.game != null, so stale history must never survive into the
    // new room (wrong move list, moveNumber continuing from old count).
    _reset();
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      final resp = await client.from('chess_games').insert({
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'playerWhiteId': myId,
        'playerWhiteName': _myName,
        // playerBlackId stays NULL until an opponent joins the room.
        'currentTurnColor': 'white',
        'boardState': initialFen,
        'status': 'waiting',
        'spectatorsEnabled': spectatorsEnabled,
        'hostReady': true,
        'autoCloseDeadline': deadline.toIso8601String(),
      }).select().single();
      final game = ChessGame.fromJson(resp as Map<String, dynamic>);
      _gameId = game.id;
      _logic = chess.Chess.fromFEN(game.boardState);

      // Register the host in the shared room bookkeeping — the lobby
      // roster (game_participants), the 'join' lobby event and the
      // gaming-ecosystem archive all flow from this one row.
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'chess_games',
        'p_game_id': game.id,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': 'host',
      });

      state = state.copyWith(
        game: game,
        isLoading: false,
        inCheck: _logic!.in_check,
        isCheckmate: _logic!.in_checkmate,
        isStalemate: _logic!.in_stalemate,
      );
      _subscribeToRealtime(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[Chess] createRoom error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  /// Non-host: join an existing room.
  ///
  /// • Room closed / deleted → friendly error (create a new room).
  /// • Waiting + Black's slot free → take the Black side (first member
  ///   to join wins the slot — no manual side picking).
  /// • Waiting + slot taken → 'Game is full' (1v1).
  /// • Match already running → spectate read-only.
  Future<bool> joinRoom(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }
    // Same rematch leak guard as createRoom — joining a fresh room must
    // not carry the previous game's moves/lastMove into the new board.
    _reset();
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      var gameResp = await client
          .from('chess_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (isRoomRowClosed(gameResp)) {
        state = state.copyWith(isLoading: false, error: kRoomClosedMessage);
        return false;
      }
      var game = ChessGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      final alreadyPlayer =
          game.playerWhiteId == myId || game.playerBlackId == myId;

      if (!alreadyPlayer) {
        if (game.isWaiting) {
          if (!game.needsOpponent) {
            state = state.copyWith(
                isLoading: false, error: 'Game is full');
            return false;
          }
          // Take the opponent slot — the room framework records the
          // join + posts the 'join' lobby event for the roster.
          await client.from('chess_games').update({
            'playerBlackId': myId,
            'playerBlackName': _myName,
          }).eq('id', gameId);
          await client.rpc('fn_record_room_join', params: {
            'p_game_table': 'chess_games',
            'p_game_id': gameId,
            'p_family_id': familyId,
            'p_user_id': myId,
            'p_user_name': _myName,
            'p_role': 'player',
          });
          await _ref.read(temporaryRoomServiceProvider).touchActivity(
                gameTable: 'chess_games',
                gameId: gameId,
              );
          // Re-fetch so the local state carries the filled slot.
          gameResp = await client
              .from('chess_games')
              .select()
              .eq('id', gameId)
              .maybeSingle();
          if (gameResp != null) {
            game = ChessGame.fromJson(gameResp);
          }
        } else if (game.isInProgress) {
          // Match already running — watch from the sidelines.
          await client.rpc('fn_spectate_game', params: {
            'p_game_table': 'chess_games',
            'p_game_id': gameId,
            'p_family_id': familyId,
            'p_user_id': myId,
            'p_user_name': _myName,
          });
        }
      }

      _logic = chess.Chess.fromFEN(game.boardState);
      state = state.copyWith(
        game: game,
        isLoading: false,
        inCheck: _logic!.in_check,
        isCheckmate: _logic!.in_checkmate,
        isStalemate: _logic!.in_stalemate,
      );
      _subscribeToRealtime(gameId);
      // Keep the persistent game-invite chat card in the family thread
      // in sync with the new player count. Best-effort.
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
      debugPrint('[Chess] joinRoom error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Host: start the match from the waiting room.
  ///
  /// Validates that an opponent has joined; flips the room to
  /// in_progress (every client's realtime subscription then navigates
  /// to the board together). Returns a user-readable error message, or
  /// null on success.
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
      await client.from('chess_games').update({
        'status': 'in_progress',
        'startedAt': DateTime.now().toIso8601String(),
      }).eq('id', gameId);
      // Lobby chat log entry — same event the room framework posts.
      try {
        await client.from('game_room_events').insert({
          'gameTable': 'chess_games',
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
      debugPrint('[Chess] startMatch error: $e');
      return 'Could not start the match';
    }
  }

  /// Leave the waiting room.
  ///
  /// • Host leaves → the room is closed and hard-deleted for everyone
  ///   (fn_cancel_waiting_room — extended to chess_games).
  /// • Guest leaves → their slot is freed (fn_leave_game_room clears
  ///   playerBlackId + the participant row), so another family member
  ///   can join instead.
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
                gameTable: 'chess_games',
                gameId: gameId,
              );
        } else {
          await client.rpc('fn_leave_game_room', params: {
            'p_game_table': 'chess_games',
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
    _logic = null;
    state = const ChessState();
  }

  /// Load an existing game (for the board screen).
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
          .from('chess_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (isRoomRowClosed(gameResp)) {
        state = const ChessState(error: kRoomClosedMessage);
        return false;
      }
      final game = ChessGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;
      _logic = chess.Chess.fromFEN(game.boardState);

      final movesResp = await client
          .from('chess_moves')
          .select()
          .eq('gameId', gameId)
          .order('moveNumber', ascending: true);
      final moves = movesResp
          .map((m) => ChessMoveRecord.fromJson(m as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        game: game,
        moves: moves,
        isLoading: false,
        inCheck: _logic!.in_check,
        isCheckmate: _logic!.in_checkmate,
        isStalemate: _logic!.in_stalemate,
      );
      await _subscribeToRealtime(gameId);
      return true;
    } catch (e) {
      debugPrint('[Chess] loadGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Select a piece at the given square (e.g. 'e2').
  /// Updates legal destinations for that piece.
  void selectSquare(String square) {
    final game = state.game;
    if (game == null || !game.isInProgress) return;
    final myId = _myId;
    if (myId == null) return;
    if (!game.isMyTurn(myId)) return;

    final logic = _logic;
    if (logic == null) return;

    // Check there's a piece at this square and it's the current player's
    final piece = logic.get(square);
    if (piece == null) return;

    // chess.dart uses 'w'/'b' for color; our ChessColor uses white/black
    final pieceColor = piece.color == chess.Color.WHITE
        ? ChessColor.white
        : ChessColor.black;
    if (pieceColor != game.currentTurnColor) return;

    // Get legal moves FROM this square
    final legalMoves = logic.generate_moves({
      'from': square,
    });
    final destinations = legalMoves.map((m) => m.toAlgebraic).toList();

    state = state.copyWith(
      selectedSquare: square,
      legalDestinations: destinations,
    );
    GameMotionTokens.tap();
  }

  /// Clear the current selection.
  void clearSelection() {
    state = state.copyWith(clearSelection: true, legalDestinations: const []);
  }

  /// Attempt to move from [from] to [to].
  /// Handles promotion (defaults to Queen).
  Future<bool> makeMove(String from, String to, {String? promotion}) async {
    // Double-tap guard — a second tap while the first move's DB writes
    // are still in flight must be a no-op.
    if (state.isSubmitting) return false;
    final game = state.game;
    final client = _client;
    final myId = _myId;
    final logic = _logic;
    if (game == null || client == null || myId == null || logic == null) {
      return false;
    }
    if (!game.isMyTurn(myId)) return false;

    // Build the move
    final moveObj = <String, dynamic>{
      'from': from,
      'to': to,
    };

    // Check if promotion is needed
    final piece = logic.get(from);
    if (piece != null && piece.type == chess.PieceType.PAWN) {
      // Check if this is a promotion move (pawn reaching last rank)
      final toRank = to[1];
      if ((piece.color == chess.Color.WHITE && toRank == '8') ||
          (piece.color == chess.Color.BLACK && toRank == '1')) {
        moveObj['promotion'] = promotion ?? 'q'; // default to queen
      }
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      // In chess.dart 0.8.1, move() returns bool, not a Move object.
      // Find the matching Move from generate_moves() first to get details.
      final candidates = logic.generate_moves({
        'from': from,
        'to': to,
      });

      // Find the matching move (handle promotion)
      chess.Move? matchedMove;
      for (final m in candidates) {
        if (m.toAlgebraic == to && m.fromAlgebraic == from) {
          // If promotion, match the promotion piece; otherwise take first match
          if (moveObj.containsKey('promotion')) {
            final promoStr = moveObj['promotion'] as String;
            final promoPiece = promoStr == 'q'
                ? chess.PieceType.QUEEN
                : promoStr == 'r'
                    ? chess.PieceType.ROOK
                    : promoStr == 'b'
                        ? chess.PieceType.BISHOP
                        : chess.PieceType.KNIGHT;
            if (m.promotion == promoPiece) {
              matchedMove = m;
              break;
            }
          } else {
            matchedMove = m;
            break;
          }
        }
      }

      if (matchedMove == null) {
        GameMotionTokens.error();
        state = state.copyWith(
          isSubmitting: false,
          error: 'Illegal move',
          clearSelection: true,
          legalDestinations: const [],
        );
        return false;
      }

      // Extract move details from the Move object
      final fromSquare = matchedMove.fromAlgebraic;
      final toSquare = matchedMove.toAlgebraic;
      final pieceMoved = matchedMove.piece.toString().toUpperCase();
      final capturedPiece = matchedMove.captured != null
          ? matchedMove.captured.toString()
          : null;
      final promotedTo = matchedMove.promotion != null
          ? matchedMove.promotion.toString().toUpperCase()
          : null;

      // Determine special move type by examining the move
      // chess.dart 0.8.1 Move class doesn't expose a 'flag' property,
      // so we infer the special move type from the move details.
      String? specialMove;
      // Castling: king moves 2 columns
      if (matchedMove.piece == chess.PieceType.KING) {
        final fromCol = from[0];
        final toCol = to[0];
        if ((toCol.codeUnitAt(0) - fromCol.codeUnitAt(0)).abs() == 2) {
          specialMove = toCol.compareTo(fromCol) > 0 ? 'castle_kingside' : 'castle_queenside';
        }
      }
      // En passant: captured exists but destination square was empty before
      if (specialMove == null &&
          matchedMove.captured != null &&
          matchedMove.piece == chess.PieceType.PAWN) {
        // Check if the destination square was empty (en passant)
        final destPiece = logic.get(to);
        if (destPiece == null) {
          specialMove = 'en_passant';
        }
      }
      // Promotion
      if (specialMove == null && matchedMove.promotion != null) {
        specialMove = 'promotion';
      }

      // SAN notation — must be computed BEFORE applying the move
      // (move_to_san reads the current position for disambiguation).
      // NOTE: chess.dart 0.8.1's `history` is a List<State> of position
      // objects, NOT SAN strings — `history.last` was a State instance
      // and json-encoding the move row threw "Converting object to an
      // encodable object failed", silently rolling back every
      // chess_moves INSERT (the opponent's realtime never fired).
      final notation = logic.move_to_san(matchedMove);

      // Apply the move (returns bool in chess.dart 0.8.1)
      final success = logic.move(moveObj);
      if (!success) {
        GameMotionTokens.error();
        state = state.copyWith(
          isSubmitting: false,
          error: 'Move failed',
          clearSelection: true,
          legalDestinations: const [],
        );
        return false;
      }

      // Get the new FEN
      final newFen = logic.fen;

      // Determine game result
      String? result;
      String? winnerId;
      String? winnerName;
      bool gameEnded = false;

      if (logic.in_checkmate) {
        // Checkmate — the side to move AFTER this move is checkmated and
        // loses. The winner is therefore the player who just moved
        // (game.currentTurnColor = the mover's color) — NOT the opposite.
        final winnerColor = game.currentTurnColor;
        result = winnerColor == ChessColor.white
            ? 'white_win'
            : 'black_win';
        winnerId = game.playerIdForColor(winnerColor);
        winnerName = winnerColor == ChessColor.white
            ? game.playerWhiteName
            : game.playerBlackName;
        gameEnded = true;
        GameMotionTokens.celebrate();
      } else if (logic.in_stalemate) {
        result = 'stalemate';
        gameEnded = true;
        GameMotionTokens.error();
      } else if (logic.in_draw) {
        result = 'draw';
        gameEnded = true;
        GameMotionTokens.tap();
      } else {
        // Normal move — haptic
        if (capturedPiece != null) {
          GameMotionTokens.success();
        } else {
          GameMotionTokens.tap();
        }
      }

      // Build update
      final updateBody = <String, dynamic>{
        'boardState': newFen,
        'currentTurnColor':
            game.currentTurnColor == ChessColor.white ? 'black' : 'white',
        'lastMoveAt': DateTime.now().toIso8601String(),
      };

      if (gameEnded) {
        updateBody['status'] = 'completed';
        updateBody['completedAt'] = DateTime.now().toIso8601String();
        updateBody['lastActivityAt'] = DateTime.now().toIso8601String();
        updateBody['result'] = result;
        updateBody['winnerId'] = winnerId;
        updateBody['winnerName'] = winnerName;
      }

      // Update game
      await client.from('chess_games').update(updateBody).eq('id', game.id);

      // Schedule the temporary room (and all temporary player associations)
      // for deletion 30s after the game ends. Pattern A games have no
      // lobby/waiting phase, so this is the only cleanup hook we need.
      // The hourly pg_cron job is the safety net if the user closes the
      // app before this fires.
      if (gameEnded) {
        _scheduleRoomCleanup(game.id);
      }

      // Insert move record
      final moveNumber = state.moves.length + 1;
      await client.from('chess_moves').insert({
        'gameId': game.id,
        'playerId': myId,
        'playerName': _myName,
        'fromSquare': fromSquare,
        'toSquare': toSquare,
        'pieceMoved': pieceMoved,
        'capturedPiece': capturedPiece,
        'specialMove': specialMove,
        'promotedTo': promotedTo,
        'moveNumber': moveNumber,
        'notation': notation,
      });

      // Update local state
      final updatedGame = ChessGame(
        id: game.id,
        familyId: game.familyId,
        playerWhiteId: game.playerWhiteId,
        playerWhiteName: game.playerWhiteName,
        playerBlackId: game.playerBlackId,
        playerBlackName: game.playerBlackName,
        currentTurnColor: game.currentTurnColor == ChessColor.white
            ? ChessColor.black
            : ChessColor.white,
        boardState: newFen,
        status: gameEnded ? ChessStatus.completed : ChessStatus.inProgress,
        result: ChessResultX.fromString(result),
        winnerId: winnerId,
        winnerName: winnerName,
        lastMoveAt: DateTime.now(),
        startedAt: game.startedAt,
        completedAt: gameEnded ? DateTime.now() : null,
        createdAt: game.createdAt,
      );

      state = state.copyWith(
        game: updatedGame,
        isSubmitting: false,
        clearSelection: true,
        legalDestinations: const [],
        lastMove: (fromSquare, toSquare),
        inCheck: logic.in_check,
        isCheckmate: logic.in_checkmate,
        isStalemate: logic.in_stalemate,
      );

      return true;
    } catch (e) {
      debugPrint('[Chess] makeMove error: $e');
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }

  /// Leave the game.
  void leaveGame() {
    _channel?.unsubscribe();
    _channel = null;
    _gameId = null;
    _logic = null;
  }

  /// Schedule the temporary room (and all temporary player associations)
  /// for deletion 30s after the game ends. The hourly pg_cron job is the
  /// safety net if the user closes the app before this fires.
  void _scheduleRoomCleanup(String gameId) {
    Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'chess_games',
            gameId: gameId,
          );
    });
  }

  // ── Realtime subscription ────────────────────────────────────────

  Future<void> _subscribeToRealtime(String gameId) async {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    // Keep the participant row fresh while this screen owns the room
    // (players only — spectators have no participant row and the RPC
    // is a harmless no-op for them).
    final myId = _myId;
    if (myId != null) {
      _heartbeat?.stop();
      _heartbeat = RoomPresenceHeartbeat('chess_games')
        ..start(client, gameId, myId);
    }

    // Belt & braces: the socket-level access token is normally set by
    // supabase's own auth listener, but a channel's join payload
    // captures socket.accessToken at subscribe() time — re-asserting
    // it here guarantees postgres_changes RLS doesn't silently drop
    // every event when the join raced an auth refresh. (Same pattern
    // as GameInviteListener's TOKEN RACE FIX.)
    final token = client.auth.currentSession?.accessToken;
    if (token != null) {
      try {
        await client.realtime.setAuth(token);
      } catch (_) {}
    }

    _channel = client
        .channel('chess_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chess_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            debugPrint('[Chess] realtime UPDATE event (turn='
                '${payload.newRecord['currentTurnColor']})');
            final updated = ChessGame.fromJson(payload.newRecord);
            // Rebuild the logic engine from the new FEN
            _logic = chess.Chess.fromFEN(updated.boardState);
            if (updated.isCompleted) {
              GameMotionTokens.celebrate();
            }
            state = state.copyWith(
              game: updated,
              inCheck: _logic!.in_check,
              isCheckmate: _logic!.in_checkmate,
              isStalemate: _logic!.in_stalemate,
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chess_moves',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            debugPrint('[Chess] realtime MOVE event '
                '(${payload.newRecord['notation']})');
            final move = ChessMoveRecord.fromJson(payload.newRecord);
            if (!state.moves.any((m) => m.id == move.id)) {
              state = state.copyWith(
                moves: [...state.moves, move],
                lastMove: (move.fromSquare, move.toSquare),
              );
            }
          },
        )
        // ── Game row DELETE = the room was closed by the host (or the
        //    opponent left) → fn_end_game hard-deleted it. Show a friendly
        //    "room closed" state instead of hanging on a dead board.
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'chess_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            debugPrint('[Chess] game row deleted — room closed');
            _channel?.unsubscribe();
            _channel = null;
            _gameId = null;
            _logic = null;
            // A COMPLETED game is archived + cleaned up server-side
            // shortly after the results screen renders — that delete is
            // EXPECTED and must not clobber the results view (it reads
            // the in-memory game state). Only a live room being closed
            // (host left / cancelled) shows the room-closed error.
            if (state.game?.isCompleted ?? false) return;
            state = const ChessState(error: kRoomClosedMessage);
          },
        )
        .subscribe((status, [error]) {
          debugPrint('[Chess] channel status: $status'
              '${error != null ? " err=$error" : ""}');
        });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _heartbeat?.stop();
    super.dispose();
  }
}

final chessProvider = StateNotifierProvider.autoDispose
    .family<ChessNotifier, ChessState, String>(
  (ref, familyId) => ChessNotifier(ref, familyId),
);
