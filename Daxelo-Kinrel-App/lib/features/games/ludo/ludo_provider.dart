// lib/features/games/ludo/ludo_provider.dart
//
// Ludo — Riverpod state + Supabase Realtime + Edge Function dice rolls.
//
// Architecture:
//   • Supabase stores games, players, tokens, moves
//   • Supabase Realtime broadcasts all changes for live sync
//   • The ludo-roll-dice Edge Function generates server-authoritative
//     dice rolls (clients NEVER generate their own rolls)
//   • Game logic (legal moves, captures, home column) runs client-side
//     via ludo_game_logic.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import 'ludo_game_logic.dart';
import 'ludo_models.dart';

class LudoState {
  const LudoState({
    this.game,
    this.players = const [],
    this.tokens = const [],
    this.moves = const [],
    this.isLoading = false,
    this.isRolling = false,
    this.isMoving = false,
    this.error,
    this.lastRollResult,
    this.lastCapture,
  });

  final LudoGame? game;
  final List<LudoPlayer> players;
  final List<LudoTokenModel> tokens;
  final List<LudoMoveRecord> moves;
  final bool isLoading;
  final bool isRolling;
  final bool isMoving;
  final String? error;
  final int? lastRollResult;
  final String? lastCapture; // player name whose token was captured

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  /// Get my tokens (as logic-layer LudoToken).
  List<LudoToken> getMyTokens(String? myUserId) {
    if (myUserId == null) return const [];
    return tokens
        .where((t) => t.playerId == myUserId)
        .map((t) => t.toLogicToken())
        .toList();
  }

  /// Get all tokens as logic-layer LudoToken (with colors from players).
  List<LudoToken> get allLogicTokens {
    return tokens.map((t) {
      final player = players.where((p) => p.userId == t.playerId).firstOrNull;
      return LudoToken(
        id: t.id,
        playerId: t.playerId,
        tokenIndex: t.tokenIndex,
        position: t.position,
        color: player?.color ?? LudoColor.red,
      );
    }).toList();
  }

  /// Get the legal tokens I can move with the current dice roll.
  List<LudoToken> getLegalTokensForMe(String? myUserId) {
    if (myUserId == null || game?.lastDiceRoll == null) return const [];
    if (game!.currentTurnPlayerId != myUserId) return const [];
    final myTokens = getMyTokens(myUserId);
    return getLegalTokens(myTokens, game!.lastDiceRoll!);
  }

  LudoState copyWith({
    LudoGame? game,
    List<LudoPlayer>? players,
    List<LudoTokenModel>? tokens,
    List<LudoMoveRecord>? moves,
    bool? isLoading,
    bool? isRolling,
    bool? isMoving,
    String? error,
    bool clearError = false,
    int? lastRollResult,
    String? lastCapture,
    bool clearRollResult = false,
    bool clearCapture = false,
  }) =>
      LudoState(
        game: game ?? this.game,
        players: players ?? this.players,
        tokens: tokens ?? this.tokens,
        moves: moves ?? this.moves,
        isLoading: isLoading ?? this.isLoading,
        isRolling: isRolling ?? this.isRolling,
        isMoving: isMoving ?? this.isMoving,
        error: clearError ? null : (error ?? this.error),
        lastRollResult: clearRollResult
            ? null
            : (lastRollResult ?? this.lastRollResult),
        lastCapture: clearCapture ? null : (lastCapture ?? this.lastCapture),
      );
}

class LudoNotifier extends StateNotifier<LudoState> {
  LudoNotifier(this._ref, this.familyId) : super(const LudoState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  String? _gameId;

  // ── Public API ───────────────────────────────────────────────────

  /// Host: create a new game.
  Future<String?> createGame({required int playerCount}) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final body = {
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'status': 'waiting',
        'playerCount': playerCount,
        'consecutiveSixes': 0,
        'extraTurnPending': false,
      };
      final resp = await client
          .from('ludo_games')
          .insert(body)
          .select()
          .single();
      final game = LudoGame.fromJson(resp as Map<String, dynamic>);
      _gameId = game.id;

      // Insert host as first player (Red)
      await client.from('ludo_players').insert({
        'gameId': game.id,
        'userId': myId,
        'userName': _myName,
        'color': LudoColor.red.name,
        'turnOrder': 0,
        'tokensFinished': 0,
      });

      // Create 4 tokens for the host
      for (int i = 0; i < 4; i++) {
        await client.from('ludo_tokens').insert({
          'gameId': game.id,
          'playerId': myId,
          'tokenIndex': i,
          'position': -1, // in home base
        });
      }

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      await _refreshPlayers(game.id);
      await _refreshTokens(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[Ludo] createGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  /// Non-host: join an existing game.
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
          .from('ludo_games')
          .select()
          .eq('id', gameId)
          .single();
      final game = LudoGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      // Fetch existing players
      final playersResp = await client
          .from('ludo_players')
          .select()
          .eq('gameId', gameId)
          .order('turnOrder', ascending: true);
      final existingPlayers = playersResp
          .map((p) => LudoPlayer.fromJson(p as Map<String, dynamic>))
          .toList();

      if (existingPlayers.length >= game.playerCount) {
        state = state.copyWith(
          isLoading: false,
          error: 'Game is full',
        );
        return false;
      }

      // Check if already joined
      final alreadyJoined = existingPlayers.any((p) => p.userId == myId);
      if (!alreadyJoined) {
        // Assign color and turn order
        final turnOrder = existingPlayers.length;
        final colors = [LudoColor.red, LudoColor.blue, LudoColor.green, LudoColor.yellow];
        final myColor = colors[turnOrder];

        await client.from('ludo_players').upsert({
          'gameId': gameId,
          'userId': myId,
          'userName': _myName,
          'color': myColor.name,
          'turnOrder': turnOrder,
          'tokensFinished': 0,
        }, onConflict: 'gameId,userId');

        // Create 4 tokens
        for (int i = 0; i < 4; i++) {
          await client.from('ludo_tokens').insert({
            'gameId': gameId,
            'playerId': myId,
            'tokenIndex': i,
            'position': -1,
          });
        }
      }

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshPlayers(gameId);
      await _refreshTokens(gameId);
      await _refreshMoves(gameId);
      // Keep the persistent game-invite chat card in the family thread in
      // sync with the new player count ("2/4 players" / "Full") for every
      // family member via realtime. Best-effort, never affects the join.
      unawaited(
        syncGameInviteChatCards(
          client: client,
          gameId: gameId,
          currentPlayers: state.players.length,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[Ludo] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Host: start the game.
  Future<void> startGame() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    if (client == null || gameId == null || game == null) return;

    if (state.players.length < 2) {
      state = state.copyWith(error: 'Need at least 2 players to start');
      return;
    }

    try {
      // First player (turnOrder 0) goes first
      final firstPlayer = state.players
          .where((p) => p.turnOrder == 0)
          .firstOrNull;
      if (firstPlayer == null) return;

      await client.from('ludo_games').update({
        'status': 'in_progress',
        'currentTurnPlayerId': firstPlayer.userId,
        'startedAt': DateTime.now().toIso8601String(),
      }).eq('id', gameId);
    } catch (e) {
      debugPrint('[Ludo] startGame error: $e');
      state = state.copyWith(error: '$e');
    }
  }

  /// Current player: roll the dice via the Edge Function.
  Future<bool> rollDice() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final game = state.game;
    if (client == null || gameId == null || myId == null || game == null) {
      return false;
    }
    if (game.currentTurnPlayerId != myId) return false;
    if (game.lastDiceRoll != null) return false; // already rolled, must move

    state = state.copyWith(isRolling: true, clearError: true);
    try {
      final response = await client.functions.invoke(
        'ludo-roll-dice',
        body: {'gameId': gameId, 'playerId': myId},
      );

      final data = response.data as Map<String, dynamic>;
      final diceValue = data['diceValue'] as int;
      final forfeited = data['forfeited'] as bool? ?? false;

      GameMotionTokens.tap();

      if (forfeited) {
        // Three sixes — turn forfeited, next player's turn
        GameMotionTokens.error();
        state = state.copyWith(
          isRolling: false,
          lastRollResult: diceValue,
          error: 'Three 6s in a row — turn forfeited!',
        );
        // Clear error after 3s
        Timer(const Duration(seconds: 3), () {
          if (mounted) state = state.copyWith(clearError: true);
        });
      } else {
        state = state.copyWith(
          isRolling: false,
          lastRollResult: diceValue,
        );
      }
      return true;
    } catch (e) {
      debugPrint('[Ludo] rollDice error: $e');
      state = state.copyWith(isRolling: false, error: '$e');
      return false;
    }
  }

  /// Current player: move a token.
  Future<bool> moveToken(String tokenId) async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final game = state.game;
    if (client == null || gameId == null || myId == null || game == null) {
      return false;
    }
    if (game.lastDiceRoll == null) return false; // must roll first
    if (game.currentTurnPlayerId != myId) return false;

    final diceValue = game.lastDiceRoll!;
    final token = state.tokens.where((t) => t.id == tokenId).firstOrNull;
    if (token == null) return false;

    // Get the player's color
    final player = state.players
        .where((p) => p.userId == token.playerId)
        .firstOrNull;
    if (player == null) return false;

    final logicToken = LudoToken(
      id: token.id,
      playerId: token.playerId,
      tokenIndex: token.tokenIndex,
      position: token.position,
      color: player.color,
    );

    // Validate the move
    if (!canMoveToken(logicToken, diceValue)) {
      GameMotionTokens.error();
      state = state.copyWith(error: 'That token cannot move with a $diceValue');
      return false;
    }

    state = state.copyWith(isMoving: true, clearError: true);
    try {
      final allLogicTokens = state.allLogicTokens;
      final result = applyTokenMove(
        token: logicToken,
        diceValue: diceValue,
        allTokens: allLogicTokens,
      );

      // Update the moved token
      await client.from('ludo_tokens').update({
        'position': result.newPosition,
        'updatedAt': DateTime.now().toIso8601String(),
      }).eq('id', tokenId);

      // If captured, send the opponent's token home
      if (result.capturedToken != null) {
        await client.from('ludo_tokens').update({
          'position': -1,
          'updatedAt': DateTime.now().toIso8601String(),
        }).eq('id', result.capturedToken!.id);

        // Get captured player name
        final capturedPlayer = state.players
            .where((p) => p.userId == result.capturedToken!.playerId)
            .firstOrNull;
        state = state.copyWith(
          lastCapture: capturedPlayer?.userName,
        );
        GameMotionTokens.celebrate();
        // Clear capture feedback after 2s
        Timer(const Duration(seconds: 2), () {
          if (mounted) state = state.copyWith(clearCapture: true);
        });
      }

      // Insert move record
      final moveNumber = state.moves.length + 1;
      await client.from('ludo_moves').insert({
        'gameId': gameId,
        'playerId': myId,
        'playerName': _myName,
        'tokenId': tokenId,
        'tokenIndex': token.tokenIndex,
        'diceValue': diceValue,
        'fromPosition': token.position,
        'toPosition': result.newPosition,
        'capturedTokenId': result.capturedToken?.id,
        'capturedPlayerName': result.capturedToken != null
            ? state.players
                  .where((p) => p.userId == result.capturedToken!.playerId)
                  .firstOrNull
                  ?.userName
            : null,
        'moveNumber': moveNumber,
      });

      // Check for win
      final myTokens = state.tokens
          .where((t) => t.playerId == myId)
          .map((t) => t.copyWith(position: t.id == tokenId ? result.newPosition : t.position))
          .toList();
      final myLogicTokens = myTokens.map((t) {
        final p = state.players.where((x) => x.userId == t.playerId).firstOrNull;
        return LudoToken(
          id: t.id,
          playerId: t.playerId,
          tokenIndex: t.tokenIndex,
          position: t.position,
          color: p?.color ?? LudoColor.red,
        );
      }).toList();
      final won = hasPlayerWon(myLogicTokens);

      // Determine next turn
      final extraTurn = getsExtraTurn(diceValue: diceValue, moveResult: result);
      String nextTurnPlayerId;
      int newConsecutiveSixes = game.consecutiveSixes;

      if (won) {
        // Game over — this player wins
        await client.from('ludo_games').update({
          'status': 'completed',
          'winnerId': myId,
          'winnerName': _myName,
          'completedAt': DateTime.now().toIso8601String(),
          'lastDiceRoll': null,
          'consecutiveSixes': 0,
          'extraTurnPending': false,
        }).eq('id', gameId);
        GameMotionTokens.celebrate();
      } else if (extraTurn) {
        // Same player goes again
        nextTurnPlayerId = myId;
        await client.from('ludo_games').update({
          'lastDiceRoll': null,
          'currentTurnPlayerId': nextTurnPlayerId,
        }).eq('id', gameId);
      } else {
        // Pass to next player
        final sortedPlayers = List<LudoPlayer>.from(state.players)
          ..sort((a, b) => a.turnOrder.compareTo(b.turnOrder));
        final currentIdx = sortedPlayers.indexWhere((p) => p.userId == myId);
        final nextIdx = (currentIdx + 1) % sortedPlayers.length;
        nextTurnPlayerId = sortedPlayers[nextIdx].userId;
        await client.from('ludo_games').update({
          'lastDiceRoll': null,
          'consecutiveSixes': 0,
          'extraTurnPending': false,
          'currentTurnPlayerId': nextTurnPlayerId,
        }).eq('id', gameId);
      }

      state = state.copyWith(
        isMoving: false,
        clearRollResult: true,
      );
      return true;
    } catch (e) {
      debugPrint('[Ludo] moveToken error: $e');
      state = state.copyWith(isMoving: false, error: '$e');
      return false;
    }
  }

  /// Leave the game.
  void leaveGame() {
    _channel?.unsubscribe();
    _channel = null;
    _gameId = null;
  }

  // ── Realtime subscription ────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    _channel = client
        .channel('ludo_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ludo_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated = LudoGame.fromJson(payload.newRecord);
            if (updated.isCompleted) {
              GameMotionTokens.celebrate();
            }
            state = state.copyWith(game: updated);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ludo_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final player = LudoPlayer.fromJson(payload.newRecord);
            if (!state.players.any((p) => p.userId == player.userId)) {
              state = state.copyWith(players: [...state.players, player]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ludo_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final updated = LudoPlayer.fromJson(payload.newRecord);
            final next = state.players
                .map((p) => p.userId == updated.userId ? updated : p)
                .toList();
            state = state.copyWith(players: next);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ludo_tokens',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final tokenId = payload.newRecord['id'] as String?;
            final newPosition = payload.newRecord['position'] as int?;
            if (tokenId == null) return;
            final next = state.tokens.map((t) {
              if (t.id == tokenId && newPosition != null) {
                return t.copyWith(position: newPosition);
              }
              return t;
            }).toList();
            state = state.copyWith(tokens: next);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ludo_tokens',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final playerId = payload.newRecord['playerId'] as String?;
            final tokenIndex = payload.newRecord['tokenIndex'] as int?;
            if (playerId == null || tokenIndex == null) return;
            // Find color from players
            final player = state.players
                .where((p) => p.userId == playerId)
                .firstOrNull;
            final token = LudoTokenModel(
              id: payload.newRecord['id'] ?? '',
              gameId: gameId,
              playerId: playerId,
              tokenIndex: tokenIndex,
              position: payload.newRecord['position'] ?? -1,
              color: player?.color ?? LudoColor.red,
            );
            if (!state.tokens.any((t) => t.id == token.id)) {
              state = state.copyWith(tokens: [...state.tokens, token]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ludo_moves',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final move = LudoMoveRecord.fromJson(payload.newRecord);
            if (!state.moves.any((m) => m.id == move.id)) {
              state = state.copyWith(moves: [...state.moves, move]);
            }
          },
        )
        .subscribe();
  }

  Future<void> _refreshPlayers(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('ludo_players')
          .select()
          .eq('gameId', gameId)
          .order('turnOrder', ascending: true);
      final players = resp
          .map((p) => LudoPlayer.fromJson(p as Map<String, dynamic>))
          .toList();
      state = state.copyWith(players: players);
    } catch (e) {
      debugPrint('[Ludo] refreshPlayers error: $e');
    }
  }

  Future<void> _refreshTokens(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('ludo_tokens')
          .select()
          .eq('gameId', gameId);
      final tokens = resp
          .map((t) {
            final playerId = t['playerId'] as String? ?? '';
            final player = state.players
                .where((p) => p.userId == playerId)
                .firstOrNull;
            return LudoTokenModel(
              id: t['id'] ?? '',
              gameId: gameId,
              playerId: playerId,
              tokenIndex: t['tokenIndex'] ?? 0,
              position: t['position'] ?? -1,
              color: player?.color ?? LudoColor.red,
            );
          })
          .toList();
      state = state.copyWith(tokens: tokens);
    } catch (e) {
      debugPrint('[Ludo] refreshTokens error: $e');
    }
  }

  Future<void> _refreshMoves(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('ludo_moves')
          .select()
          .eq('gameId', gameId)
          .order('moveNumber', ascending: true);
      final moves = resp
          .map((m) => LudoMoveRecord.fromJson(m as Map<String, dynamic>))
          .toList();
      state = state.copyWith(moves: moves);
    } catch (e) {
      debugPrint('[Ludo] refreshMoves error: $e');
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

final ludoProvider = StateNotifierProvider.autoDispose
    .family<LudoNotifier, LudoState, String>(
  (ref, familyId) => LudoNotifier(ref, familyId),
);
