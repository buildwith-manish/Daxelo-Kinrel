// lib/features/games/antakshari/antakshari_provider.dart
//
// Antakshari — Riverpod state + Supabase Realtime + host-driven timer.
//
// Architecture:
//   • Supabase stores games, players, turns, challenges
//   • Supabase Realtime broadcasts all changes (turns, challenges, game state)
//   • The host's client runs a periodic timer that:
//     - Detects turn timeout (30s elapsed, no turn submitted) → eliminate
//     - Detects challenge window expiry (10s after turn submit) → rule
//   • Any player can submit their own turn (ending letter)
//   • Any non-current player can challenge during the 10s window
//   • 3+ challenges = turn invalid → player eliminated

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import 'antakshari_models.dart';

class AntakshariState {
  const AntakshariState({
    this.game,
    this.players = const [],
    this.turns = const [],
    this.challenges = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
  });

  final AntakshariGame? game;
  final List<AntakshariPlayer> players;
  final List<AntakshariTurn> turns;
  final List<AntakshariChallenge> challenges;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  /// Get the current turn (most recent turn for this game).
  AntakshariTurn? get currentTurn =>
      turns.isEmpty ? null : turns.last;

  /// Get challenges for the current turn.
  List<AntakshariChallenge> get currentTurnChallenges {
    final ct = currentTurn;
    if (ct == null) return const [];
    return challenges.where((c) => c.turnId == ct.id).toList();
  }

  /// Get active (non-eliminated) players.
  List<AntakshariPlayer> get activePlayers =>
      players.where((p) => !p.isEliminated).toList();

  /// Is it my turn?
  bool isMyTurn(String? myUserId) =>
      game?.currentTurnPlayerId != null &&
      game!.currentTurnPlayerId == myUserId;

  /// Seconds remaining in the current turn (or challenge window).
  int get turnSecondsRemaining {
    final g = game;
    if (g == null || g.turnStartedAt == null) return 0;
    final ct = currentTurn;
    if (ct != null && ct.challengeResult == AntakshariChallengeResult.pending) {
      // In challenge window — count down from challengeWindowEndsAt
      if (ct.challengeWindowEndsAt != null) {
        final remaining =
            ct.challengeWindowEndsAt!.difference(DateTime.now()).inSeconds;
        return remaining > 0 ? remaining : 0;
      }
      return 0;
    }
    // In singing phase — count down from turnStartedAt + timerSeconds
    final deadline = g.turnStartedAt!.add(
      Duration(seconds: g.turnTimerSeconds),
    );
    final remaining = deadline.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Are we in the challenge window (turn submitted, awaiting ruling)?
  bool get isInChallengeWindow {
    final ct = currentTurn;
    return ct != null &&
        ct.challengeResult == AntakshariChallengeResult.pending &&
        ct.letterEndedWith != null;
  }

  AntakshariState copyWith({
    AntakshariGame? game,
    List<AntakshariPlayer>? players,
    List<AntakshariTurn>? turns,
    List<AntakshariChallenge>? challenges,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) =>
      AntakshariState(
        game: game ?? this.game,
        players: players ?? this.players,
        turns: turns ?? this.turns,
        challenges: challenges ?? this.challenges,
        isLoading: isLoading ?? this.isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
      );
}

class AntakshariNotifier extends StateNotifier<AntakshariState> {
  AntakshariNotifier(this._ref, this.familyId)
    : super(const AntakshariState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  Timer? _hostTimer; // host-only periodic check
  String? _gameId;

  static const _challengeThreshold = 3;
  static const _challengeWindowSeconds = 10;

  // ── Public API ───────────────────────────────────────────────────

  /// Host: create a new game.
  Future<String?> createGame({
    required AntakshariGameMode mode,
    int maxPlayers = 12,
    int turnTimerSeconds = 30,
    int? roundLimit,
  }) async {
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
        'gameMode': mode.name,
        'turnTimerSeconds': turnTimerSeconds,
        'maxPlayers': maxPlayers,
        'roundLimit': roundLimit,
        'currentTurnNumber': 0,
        'currentRound': 0,
      };
      final resp = await client
          .from('antakshari_games')
          .insert(body)
          .select()
          .single();
      final game = AntakshariGame.fromJson(resp as Map<String, dynamic>);
      _gameId = game.id;

      // Insert host as first player
      await client.from('antakshari_players').insert({
        'gameId': game.id,
        'userId': myId,
        'userName': _myName,
        'turnOrder': 0,
        'isEliminated': false,
      });

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      await _refreshPlayers(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[Antakshari] createGame error: $e');
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
          .from('antakshari_games')
          .select()
          .eq('id', gameId)
          .single();
      final game = AntakshariGame.fromJson(
        gameResp as Map<String, dynamic>,
      );
      _gameId = game.id;

      // Check max players
      final playersResp = await client
          .from('antakshari_players')
          .select()
          .eq('gameId', gameId)
          .order('turnOrder', ascending: true);
      final existingPlayers = playersResp
          .map((p) => AntakshariPlayer.fromJson(p as Map<String, dynamic>))
          .toList();
      if (existingPlayers.length >= game.maxPlayers) {
        state = state.copyWith(
          isLoading: false,
          error: 'Game is full (${game.maxPlayers} players)',
        );
        return false;
      }

      // Compute my turn order
      final existingOrders = existingPlayers
          .map((p) => p.turnOrder)
          .toSet();
      int myTurnOrder = 0;
      while (existingOrders.contains(myTurnOrder)) {
        myTurnOrder++;
      }

      await client.from('antakshari_players').upsert({
        'gameId': gameId,
        'userId': myId,
        'userName': _myName,
        'turnOrder': myTurnOrder,
        'isEliminated': false,
      }, onConflict: 'gameId,userId');

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshPlayers(gameId);
      await _refreshTurns(gameId);
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
      debugPrint('[Antakshari] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Host: start the game. Randomizes turn order, sets first required letter.
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
      // Randomize turn order
      final shuffled = List<AntakshariPlayer>.from(state.players)..shuffle();
      for (int i = 0; i < shuffled.length; i++) {
        await client.from('antakshari_players').update({
          'turnOrder': i,
        }).eq('id', shuffled[i].id);
      }

      // Pick random first letter (A-Z)
      final rand = Random();
      final firstLetter = String.fromCharCode(65 + rand.nextInt(26));

      // First player is the one with turnOrder 0
      final firstPlayer = shuffled.first;

      // Update game state
      await client.from('antakshari_games').update({
        'status': 'in_progress',
        'currentTurnPlayerId': firstPlayer.userId,
        'currentRequiredLetter': firstLetter,
        'currentTurnNumber': 1,
        'currentRound': 1,
        'turnStartedAt': DateTime.now().toIso8601String(),
        'startedAt': DateTime.now().toIso8601String(),
      }).eq('id', gameId);

      // Start host timer
      _startHostTimer();
    } catch (e) {
      debugPrint('[Antakshari] startGame error: $e');
      state = state.copyWith(error: '$e');
    }
  }

  /// Current player: submit their ending letter.
  Future<bool> submitEndingLetter(String letter) async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final game = state.game;
    if (client == null || gameId == null || myId == null || game == null) {
      return false;
    }

    // Validate it's my turn
    if (game.currentTurnPlayerId != myId) {
      state = state.copyWith(error: "It's not your turn");
      return false;
    }

    // Validate single letter
    final upper = letter.toUpperCase().trim();
    if (upper.length != 1 || !RegExp(r'[A-Z]').hasMatch(upper)) {
      state = state.copyWith(error: 'Enter a single letter A-Z');
      return false;
    }

    // Check if already submitted (current turn pending)
    final ct = state.currentTurn;
    if (ct != null &&
        ct.playerId == myId &&
        ct.letterEndedWith != null) {
      state = state.copyWith(error: 'You already submitted this turn');
      return false;
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final challengeWindowEnds = DateTime.now().add(
        const Duration(seconds: _challengeWindowSeconds),
      );

      // If there's already a turn row for this turn number (shouldn't be, but check)
      if (ct != null && ct.turnNumber == game.currentTurnNumber) {
        // Update existing turn
        await client.from('antakshari_turns').update({
          'letterEndedWith': upper,
          'challengeWindowEndsAt': challengeWindowEnds.toIso8601String(),
        }).eq('id', ct.id);
      } else {
        // Insert new turn
        await client.from('antakshari_turns').insert({
          'gameId': gameId,
          'playerId': myId,
          'playerName': _myName,
          'letterStartedWith': game.currentRequiredLetter ?? '',
          'letterEndedWith': upper,
          'turnNumber': game.currentTurnNumber,
          'wasChallenged': false,
          'challengeResult': 'pending',
          'challengeWindowEndsAt': challengeWindowEnds.toIso8601String(),
        });
      }

      GameMotionTokens.success();
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e) {
      debugPrint('[Antakshari] submitEndingLetter error: $e');
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }

  /// Non-current player: challenge the current turn.
  Future<bool> challengeCurrentTurn() async {
    final client = _client;
    final myId = _myId;
    final game = state.game;
    final ct = state.currentTurn;
    if (client == null || myId == null || game == null || ct == null) {
      return false;
    }

    // Can't challenge your own turn
    if (ct.playerId == myId) {
      state = state.copyWith(error: "You can't challenge your own turn");
      return false;
    }

    // Must be in challenge window
    if (ct.challengeResult != AntakshariChallengeResult.pending ||
        ct.letterEndedWith == null) {
      state = state.copyWith(error: 'No active turn to challenge');
      return false;
    }

    // Check not already challenged
    if (state.challenges.any(
      (c) => c.turnId == ct.id && c.challengerId == myId,
    )) {
      state = state.copyWith(error: 'You already challenged this turn');
      return false;
    }

    try {
      await client.from('antakshari_challenges').insert({
        'turnId': ct.id,
        'challengerId': myId,
        'challengerName': _myName,
      });

      // Mark the turn as challenged
      await client.from('antakshari_turns').update({
        'wasChallenged': true,
      }).eq('id', ct.id);

      GameMotionTokens.tap();
      return true;
    } catch (e) {
      debugPrint('[Antakshari] challengeCurrentTurn error: $e');
      state = state.copyWith(error: '$e');
      return false;
    }
  }

  /// Leave the game.
  Future<void> leaveGame() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    _stopHostTimer();
    if (client == null || gameId == null || myId == null) {
      _cleanup();
      return;
    }
    try {
      await client
          .from('antakshari_players')
          .delete()
          .eq('gameId', gameId)
          .eq('userId', myId);
    } catch (_) {}
    _cleanup();
  }

  void _cleanup() {
    _stopHostTimer();
    _channel?.unsubscribe();
    _channel = null;
    _gameId = null;
  }

  // ── Host timer — runs every 1s to detect timeouts / challenge expiry ──

  void _startHostTimer() {
    _stopHostTimer();
    final myId = _myId;
    final game = state.game;
    if (game == null || myId == null) return;

    // Only the host runs the timer
    if (game.hostUserId != myId) return;

    _hostTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _hostTimerTick();
    });
  }

  void _stopHostTimer() {
    _hostTimer?.cancel();
    _hostTimer = null;
  }

  Future<void> _hostTimerTick() async {
    final game = state.game;
    if (game == null || !game.isInProgress) return;

    final ct = state.currentTurn;
    final now = DateTime.now();

    if (ct == null) {
      // No turn row yet — check if turn timer expired (player didn't sing in time)
      if (game.turnStartedAt != null) {
        final deadline = game.turnStartedAt!.add(
          Duration(seconds: game.turnTimerSeconds),
        );
        if (now.isAfter(deadline)) {
          await _eliminateCurrentPlayer(reason: 'timed_out');
        }
      }
      return;
    }

    // Turn exists — check if in challenge window
    if (ct.challengeResult == AntakshariChallengeResult.pending) {
      if (ct.letterEndedWith == null) {
        // Still singing — check turn timer
        if (game.turnStartedAt != null) {
          final deadline = game.turnStartedAt!.add(
            Duration(seconds: game.turnTimerSeconds),
          );
          if (now.isAfter(deadline)) {
            // Timed out — mark turn as timed_out and eliminate
            await _client!.from('antakshari_turns').update({
              'challengeResult': 'timed_out',
            }).eq('id', ct.id);
            await _eliminateCurrentPlayer(reason: 'timed_out');
          }
        }
      } else {
        // In challenge window — check if window expired
        if (ct.challengeWindowEndsAt != null &&
            now.isAfter(ct.challengeWindowEndsAt!)) {
          // Window expired — rule on the turn
          final challengeCount = state.currentTurnChallenges.length;
          if (challengeCount >= _challengeThreshold) {
            // Turn invalid — eliminate player
            await _client!.from('antakshari_turns').update({
              'challengeResult': 'invalid',
            }).eq('id', ct.id);
            await _eliminateCurrentPlayer(reason: 'challenged');
          } else {
            // Turn valid — advance to next player
            await _client!.from('antakshari_turns').update({
              'challengeResult': 'valid',
            }).eq('id', ct.id);
            await _advanceToNextPlayer(
              endingLetter: ct.letterEndedWith!,
            );
          }
        }
      }
    }
  }

  Future<void> _eliminateCurrentPlayer({required String reason}) async {
    final game = state.game;
    final gameId = _gameId;
    if (game == null || gameId == null || game.currentTurnPlayerId == null) {
      return;
    }

    // Eliminate the player
    await _client!.from('antakshari_players').update({
      'isEliminated': true,
      'eliminatedAt': DateTime.now().toIso8601String(),
    }).eq('gameId', gameId).eq('userId', game.currentTurnPlayerId!);

    // Advance to next player (same required letter — the eliminated player
    // didn't complete their turn, so the chain letter doesn't change)
    await _advanceToNextPlayer(
      endingLetter: game.currentRequiredLetter ?? 'A',
    );
  }

  Future<void> _advanceToNextPlayer({
    required String endingLetter,
  }) async {
    final game = state.game;
    final gameId = _gameId;
    if (game == null || gameId == null) return;

    // Get active players sorted by turn order
    final active = state.activePlayers;
    if (active.isEmpty) {
      // No active players — shouldn't happen, but finish the game
      await _finishGame([], []);
      return;
    }

    // Find the current player's turn order
    final currentPlayerId = game.currentTurnPlayerId;
    final currentPlayer = state.players
        .where((p) => p.userId == currentPlayerId)
        .firstOrNull;

    // Sort active players by turn order for consistent lookup
    final sortedActive = List<AntakshariPlayer>.from(active)
      ..sort((a, b) => a.turnOrder.compareTo(b.turnOrder));

    // Find next active player after current
    AntakshariPlayer? nextPlayer;
    if (currentPlayer != null) {
      // Find players with higher turn order who are still active
      final afterCurrent = sortedActive
          .where((p) => p.turnOrder > currentPlayer.turnOrder)
          .toList();
      if (afterCurrent.isNotEmpty) {
        nextPlayer = afterCurrent.first;
      } else {
        // Wrap around to the first active player (new round)
        nextPlayer = sortedActive.first;
      }
    } else {
      nextPlayer = sortedActive.first;
    }

    if (nextPlayer == null) {
      await _finishGame([], []);
      return;
    }

    // Check win conditions
    if (active.length == 1 && game.gameMode == AntakshariGameMode.standard) {
      // Last player standing wins
      await _finishGame([nextPlayer.userId], [nextPlayer.userName]);
      return;
    }

    // Check round limit
    int newRound = game.currentRound;
    // If we're wrapping around (next player's turnOrder is lower than current's),
    // it's a new round
    if (currentPlayer != null && nextPlayer.turnOrder < currentPlayer.turnOrder) {
      newRound++;
    }

    if (game.gameMode == AntakshariGameMode.roundLimited &&
        game.roundLimit != null &&
        newRound > game.roundLimit!) {
      // Round limit reached — all active players are joint winners
      await _finishGame(
        sortedActive.map((p) => p.userId).toList(),
        sortedActive.map((p) => p.userName).toList(),
      );
      return;
    }

    // Advance to next player
    await _client!.from('antakshari_games').update({
      'currentTurnPlayerId': nextPlayer.userId,
      'currentRequiredLetter': endingLetter,
      'currentTurnNumber': game.currentTurnNumber + 1,
      'currentRound': newRound,
      'turnStartedAt': DateTime.now().toIso8601String(),
    }).eq('id', gameId);
  }

  Future<void> _finishGame(
    List<String> winnerIds,
    List<String> winnerNames,
  ) async {
    final gameId = _gameId;
    if (gameId == null) return;
    await _client!.from('antakshari_games').update({
      'status': 'completed',
      'completedAt': DateTime.now().toIso8601String(),
      'winnerUserIds': winnerIds,
      'winnerNames': winnerNames,
    }).eq('id', gameId);
    _stopHostTimer();
  }

  // ── Realtime subscription ────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    _channel = client
        .channel('antakshari_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'antakshari_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated = AntakshariGame.fromJson(payload.newRecord);
            state = state.copyWith(game: updated);
            // If game just started and I'm the host, start the timer
            if (updated.isInProgress &&
                updated.hostUserId == _myId &&
                _hostTimer == null) {
              _startHostTimer();
            }
            if (updated.isCompleted) {
              _stopHostTimer();
              GameMotionTokens.celebrate();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'antakshari_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final player = AntakshariPlayer.fromJson(payload.newRecord);
            if (!state.players.any((p) => p.userId == player.userId)) {
              state = state.copyWith(players: [...state.players, player]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'antakshari_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final updated = AntakshariPlayer.fromJson(payload.newRecord);
            final next = state.players
                .map((p) => p.userId == updated.userId ? updated : p)
                .toList();
            state = state.copyWith(players: next);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'antakshari_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
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
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'antakshari_turns',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final turn = AntakshariTurn.fromJson(payload.newRecord);
            state = state.copyWith(turns: [...state.turns, turn]);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'antakshari_turns',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final updated = AntakshariTurn.fromJson(payload.newRecord);
            final next = state.turns
                .map((t) => t.id == updated.id ? updated : t)
                .toList();
            state = state.copyWith(turns: next);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'antakshari_challenges',
          callback: (payload) {
            // Challenges don't have a gameId column — we filter client-side
            final challenge = AntakshariChallenge.fromJson(payload.newRecord);
            // Only add if it's for a turn in this game
            if (state.turns.any((t) => t.id == challenge.turnId)) {
              state = state.copyWith(
                challenges: [...state.challenges, challenge],
              );
              GameMotionTokens.error();
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
          .from('antakshari_players')
          .select()
          .eq('gameId', gameId)
          .order('turnOrder', ascending: true);
      final players = resp
          .map((p) => AntakshariPlayer.fromJson(p as Map<String, dynamic>))
          .toList();
      state = state.copyWith(players: players);
    } catch (e) {
      debugPrint('[Antakshari] refreshPlayers error: $e');
    }
  }

  Future<void> _refreshTurns(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final turnsResp = await client
          .from('antakshari_turns')
          .select()
          .eq('gameId', gameId)
          .order('turnNumber', ascending: true);
      final turns = turnsResp
          .map((t) => AntakshariTurn.fromJson(t as Map<String, dynamic>))
          .toList();
      state = state.copyWith(turns: turns);

      // Fetch challenges for all turn IDs
      if (turns.isNotEmpty) {
        final turnIds = turns.map((t) => t.id).toList();
        final challengesResp = await client
            .from('antakshari_challenges')
            .select()
            .inFilter('turnId', turnIds)
            .order('createdAt', ascending: true);
        final challenges = challengesResp
            .map((c) =>
                AntakshariChallenge.fromJson(c as Map<String, dynamic>))
            .toList();
        state = state.copyWith(challenges: challenges);
      }
    } catch (e) {
      debugPrint('[Antakshari] refreshTurns error: $e');
    }
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

final antakshariProvider = StateNotifierProvider.autoDispose
    .family<AntakshariNotifier, AntakshariState, String>(
  (ref, familyId) => AntakshariNotifier(ref, familyId),
);
