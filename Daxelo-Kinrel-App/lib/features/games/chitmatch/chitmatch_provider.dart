// lib/features/games/chitmatch/chitmatch_provider.dart
//
// TripleMatch — Riverpod + Supabase Realtime.
// Host is authoritative for round resolution.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import 'chitmatch_game_logic.dart';
import 'chitmatch_models.dart';

class ChitmatchState {
  const ChitmatchState({
    this.game,
    this.players = const [],
    this.myHand = const [],
    this.mySelectedIndex,
    this.passes = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.isResolving = false,
    this.error,
    this.myWord,
    this.lastRoundResult,
    this.secondsRemaining,
  });

  final ChitmatchGame? game;
  final List<ChitmatchPlayerModel> players;
  final List<String> myHand;
  final int? mySelectedIndex;
  final List<ChitmatchPassRecord> passes;
  final bool isLoading;
  final bool isSubmitting;
  final bool isResolving;
  final String? error;
  final String? myWord;
  final RoundResolution? lastRoundResult;
  final int? secondsRemaining;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isSetup => game?.isSetup ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;
  bool get iHaveWon => game?.winnerUserIds != null && game!.winnerUserIds!.isNotEmpty;

  ChitmatchState copyWith({
    ChitmatchGame? game,
    List<ChitmatchPlayerModel>? players,
    List<String>? myHand,
    int? mySelectedIndex,
    bool clearSelection = false,
    List<ChitmatchPassRecord>? passes,
    bool? isLoading,
    bool? isSubmitting,
    bool? isResolving,
    String? error,
    bool clearError = false,
    String? myWord,
    RoundResolution? lastRoundResult,
    int? secondsRemaining,
    bool clearTimer = false,
  }) => ChitmatchState(
    game: game ?? this.game,
    players: players ?? this.players,
    myHand: myHand ?? this.myHand,
    mySelectedIndex: clearSelection ? null : (mySelectedIndex ?? this.mySelectedIndex),
    passes: passes ?? this.passes,
    isLoading: isLoading ?? this.isLoading,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    isResolving: isResolving ?? this.isResolving,
    error: clearError ? null : (error ?? this.error),
    myWord: myWord ?? this.myWord,
    lastRoundResult: lastRoundResult ?? this.lastRoundResult,
    secondsRemaining: clearTimer ? null : (secondsRemaining ?? this.secondsRemaining),
  );
}

class ChitmatchNotifier extends StateNotifier<ChitmatchState> {
  ChitmatchNotifier(this._ref, this.familyId) : super(const ChitmatchState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName => _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  Timer? _roundTimer;
  Timer? _hostResolveTimer;
  String? _gameId;

  // ── Public API ───────────────────────────────────────────────────

  Future<String?> createGame({int playerCount = 4, int roundTimerSeconds = 20}) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final resp = await client.from('chitmatch_games').insert({
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'status': 'waiting',
        'playerCount': playerCount,
        'roundNumber': 0,
        'roundTimerSeconds': roundTimerSeconds,
        'setupPhase': 'joining',
        'allPassesCollected': false,
      }).select().single();
      final game = ChitmatchGame.fromJson(resp as Map<String, dynamic>);
      _gameId = game.id;

      // Insert host as first player
      await client.from('chitmatch_players').insert({
        'gameId': game.id,
        'userId': myId,
        'userName': _myName,
        'turnOrder': 0,
        'currentHand': [],
        'hasWon': false,
      });

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      await _refreshPlayers(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[Chitmatch] createGame error: $e');
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
      final gameResp = await client.from('chitmatch_games').select().eq('id', gameId).single();
      final game = ChitmatchGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = gameId;

      final playersResp = await client.from('chitmatch_players').select().eq('gameId', gameId).order('turnOrder', ascending: true);
      final existingPlayers = playersResp.map((p) => ChitmatchPlayerModel.fromJson(p as Map<String, dynamic>)).toList();

      if (existingPlayers.length >= game.playerCount) {
        state = state.copyWith(isLoading: false, error: 'Game is full');
        return false;
      }

      final alreadyJoined = existingPlayers.any((p) => p.userId == myId);
      if (!alreadyJoined) {
        final turnOrder = existingPlayers.length;
        await client.from('chitmatch_players').upsert({
          'gameId': gameId,
          'userId': myId,
          'userName': _myName,
          'turnOrder': turnOrder,
          'currentHand': [],
          'hasWon': false,
        }, onConflict: 'gameId,userId');
      }

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshPlayers(gameId);
      await _refreshMyHand(gameId);
      return true;
    } catch (e) {
      debugPrint('[Chitmatch] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Submit a word during the setup phase.
  Future<void> submitWord(String word) async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    if (client == null || gameId == null || myId == null) return;

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await client.from('chitmatch_players').update({
        'submittedWord': word.trim(),
      }).eq('gameId', gameId).eq('userId', myId);

      state = state.copyWith(isSubmitting: false, myWord: word.trim());
      GameMotionTokens.tap();
    } catch (e) {
      debugPrint('[Chitmatch] submitWord error: $e');
      state = state.copyWith(isSubmitting: false, error: '$e');
    }
  }

  /// Host: start the game (transition to setup → submitting words).
  Future<void> startSetup() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    if (client == null || gameId == null || game == null) return;

    if (state.players.length < 4) {
      state = state.copyWith(error: 'Need at least 4 players to start');
      return;
    }

    try {
      await client.from('chitmatch_games').update({
        'status': 'setup',
        'setupPhase': 'submitting_words',
        'startedAt': DateTime.now().toIso8601String(),
      }).eq('id', gameId);
    } catch (e) {
      debugPrint('[Chitmatch] startSetup error: $e');
      state = state.copyWith(error: '$e');
    }
  }

  /// Host: deal chits and start the first round.
  /// Called when all players have submitted their words.
  Future<void> dealAndStartGame() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    if (client == null || gameId == null || game == null) return;

    final players = state.players;
    if (players.any((p) => p.submittedWord == null || p.submittedWord!.isEmpty)) {
      state = state.copyWith(error: 'Not all players have submitted a word');
      return;
    }

    state = state.copyWith(isResolving: true);
    try {
      // Build logic players
      final logicPlayers = players.map((p) => ChitmatchPlayer(
        userId: p.userId,
        userName: p.userName,
        turnOrder: p.turnOrder,
        submittedWord: p.submittedWord,
        hand: [],
      )).toList();

      // Generate + shuffle + deal
      final chits = generateChits(logicPlayers);
      dealChits(logicPlayers, chits);

      // Insert chit records
      final chitRows = <Map<String, dynamic>>[];
      for (final p in logicPlayers) {
        for (int i = 0; i < 3; i++) {
          chitRows.add({
            'gameId': gameId,
            'word': p.submittedWord!,
            'originalOwnerPlayerId': p.userId,
            'chitCopyIndex': i,
          });
        }
      }
      await client.from('chitmatch_chits').insert(chitRows);

      // Update each player's hand
      for (final p in logicPlayers) {
        await client.from('chitmatch_players').update({
          'currentHand': p.hand,
        }).eq('gameId', gameId).eq('userId', p.userId);
      }

      // Start round 1
      final roundEnds = DateTime.now().add(Duration(seconds: game.roundTimerSeconds));
      await client.from('chitmatch_games').update({
        'status': 'in_progress',
        'setupPhase': 'ready',
        'roundNumber': 1,
        'roundEndsAt': roundEnds.toIso8601String(),
        'allPassesCollected': false,
      }).eq('id', gameId);

      state = state.copyWith(isResolving: false);
      _startRoundTimer();
    } catch (e) {
      debugPrint('[Chitmatch] dealAndStartGame error: $e');
      state = state.copyWith(isResolving: false, error: '$e');
    }
  }

  /// Player: select a chit to pass this round.
  Future<void> selectChit(int index) async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    if (client == null || gameId == null || myId == null) return;

    try {
      await client.from('chitmatch_players').update({
        'selectedChitIndex': index,
      }).eq('gameId', gameId).eq('userId', myId);

      state = state.copyWith(mySelectedIndex: index);
      GameMotionTokens.tap();

      // Check if all players have selected — host resolves
      _maybeHostResolve();
    } catch (e) {
      debugPrint('[Chitmatch] selectChit error: $e');
    }
  }

  /// Check if all players have selected, and if so, host resolves the round.
  void _maybeHostResolve() {
    final game = state.game;
    if (game == null || !game.isInProgress) return;
    if (game.hostUserId != _myId) return; // only host resolves

    final allSelected = state.players.every((p) => p.selectedChitIndex != null);
    if (allSelected && !state.isResolving) {
      _resolveRound();
    }
  }

  /// Host: resolve the current round.
  Future<void> _resolveRound() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    if (client == null || gameId == null || game == null) return;

    _stopRoundTimer();
    state = state.copyWith(isResolving: true);

    try {
      final players = state.players;

      // Auto-select for any player who hasn't selected
      final logicPlayers = players.map((p) => ChitmatchPlayer(
        userId: p.userId,
        userName: p.userName,
        turnOrder: p.turnOrder,
        submittedWord: p.submittedWord,
        hand: List<String>.from(p.currentHand),
        selectedChitIndex: p.selectedChitIndex,
      )).toList();

      autoSelectUnselected(logicPlayers);

      // Resolve
      final resolution = resolveRound(logicPlayers);

      // Update all players' hands
      for (final p in resolution.updatedPlayers) {
        await client.from('chitmatch_players').update({
          'currentHand': p.hand,
          'selectedChitIndex': null,
          'hasWon': p.hasWon,
        }).eq('gameId', gameId).eq('userId', p.userId);
      }

      // Insert pass records
      final passRows = resolution.passes.map((pass) {
        final fromPlayer = players.firstWhere((p) => p.userId == pass.fromUserId);
        final toPlayer = players.firstWhere((p) => p.userId == pass.toUserId);
        return {
          'gameId': gameId,
          'roundNumber': game.roundNumber,
          'fromPlayerId': pass.fromUserId,
          'fromPlayerName': fromPlayer.userName,
          'toPlayerId': pass.toUserId,
          'toPlayerName': toPlayer.userName,
          'chitPassed': pass.chitWord,
        };
      }).toList();
      await client.from('chitmatch_round_passes').insert(passRows);

      // Check for winners
      if (resolution.winners.isNotEmpty) {
        final winnerIds = resolution.winners.map((p) => p.userId).toList();
        final winnerNames = resolution.winners.map((p) => p.userName).toList();

        await client.from('chitmatch_games').update({
          'status': 'completed',
          'completedAt': DateTime.now().toIso8601String(),
          'winnerUserIds': winnerIds,
          'winnerNames': winnerNames,
        }).eq('id', gameId);

        GameMotionTokens.celebrate();
        state = state.copyWith(isResolving: false, lastRoundResult: resolution);
      } else {
        // Next round
        final roundEnds = DateTime.now().add(Duration(seconds: game.roundTimerSeconds));
        await client.from('chitmatch_games').update({
          'roundNumber': game.roundNumber + 1,
          'roundEndsAt': roundEnds.toIso8601String(),
          'allPassesCollected': false,
        }).eq('id', gameId);

        state = state.copyWith(
          isResolving: false,
          lastRoundResult: resolution,
          clearSelection: true,
        );
        _startRoundTimer();
      }
    } catch (e) {
      debugPrint('[Chitmatch] resolveRound error: $e');
      state = state.copyWith(isResolving: false, error: '$e');
    }
  }

  void _startRoundTimer() {
    _stopRoundTimer();
    final game = state.game;
    if (game == null || !game.isInProgress) return;

    // Only host runs the auto-resolve timer
    if (game.hostUserId != _myId) return;

    _roundTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final endsAt = state.game?.roundEndsAt;
      if (endsAt == null) {
        t.cancel();
        return;
      }
      final remaining = endsAt.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        t.cancel();
        if (!state.isResolving) {
          _resolveRound();
        }
      }
    });
  }

  void _stopRoundTimer() {
    _roundTimer?.cancel();
    _roundTimer = null;
  }

  void leaveGame() {
    _stopRoundTimer();
    _channel?.unsubscribe();
    _channel = null;
    _gameId = null;
  }

  // ── Realtime ─────────────────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    _channel = client
      .channel('chitmatch_game:$gameId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'chitmatch_games',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
        callback: (payload) {
          final updated = ChitmatchGame.fromJson(payload.newRecord);
          if (updated.isCompleted) {
            GameMotionTokens.celebrate();
          }
          if (updated.isInProgress && !state.isInProgress) {
            _startRoundTimer();
          }
          state = state.copyWith(game: updated);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chitmatch_players',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) {
          final player = ChitmatchPlayerModel.fromJson(payload.newRecord);
          if (!state.players.any((p) => p.userId == player.userId)) {
            state = state.copyWith(players: [...state.players, player]);
          }
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'chitmatch_players',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) async {
          final updated = ChitmatchPlayerModel.fromJson(payload.newRecord);
          final next = state.players.map((p) => p.userId == updated.userId ? updated : p).toList();
          state = state.copyWith(players: next);

          // If this is my player row, update my hand
          final myId = _myId;
          if (myId != null && updated.userId == myId) {
            state = state.copyWith(myHand: updated.currentHand, mySelectedIndex: updated.selectedChitIndex);
          }

          // Host: check if all selected
          _maybeHostResolve();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chitmatch_round_passes',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) {
          final pass = ChitmatchPassRecord.fromJson(payload.newRecord);
          if (!state.passes.any((p) => p.id == pass.id)) {
            state = state.copyWith(passes: [...state.passes, pass]);
          }
        },
      )
      .subscribe();
  }

  Future<void> _refreshPlayers(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client.from('chitmatch_players').select().eq('gameId', gameId).order('turnOrder', ascending: true);
      final players = resp.map((p) => ChitmatchPlayerModel.fromJson(p as Map<String, dynamic>)).toList();
      state = state.copyWith(players: players);
      await _refreshMyHand(gameId);
    } catch (e) {
      debugPrint('[Chitmatch] refreshPlayers error: $e');
    }
  }

  Future<void> _refreshMyHand(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    try {
      final resp = await client.from('chitmatch_players')
        .select('currentHand, selectedChitIndex, submittedWord')
        .eq('gameId', gameId).eq('userId', myId).single();
      state = state.copyWith(
        myHand: (resp['currentHand'] as List? ?? []).map((e) => e.toString()).toList(),
        mySelectedIndex: resp['selectedChitIndex'] as int?,
        myWord: resp['submittedWord'] as String?,
      );
    } catch (e) {
      debugPrint('[Chitmatch] refreshMyHand error: $e');
    }
  }

  @override
  void dispose() {
    _stopRoundTimer();
    _channel?.unsubscribe();
    super.dispose();
  }
}

final chitmatchProvider = StateNotifierProvider.autoDispose
    .family<ChitmatchNotifier, ChitmatchState, String>(
  (ref, familyId) => ChitmatchNotifier(ref, familyId),
);
