// lib/features/games/nameplace/nameplace_provider.dart
//
// Name-Place-Animal-Thing — Riverpod + Supabase Realtime.
// Host is authoritative for round transitions and scoring.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import 'nameplace_game_logic.dart';
import 'nameplace_models.dart';

class NameplaceState {
  const NameplaceState({
    this.game,
    this.players = const [],
    this.rounds = const [],
    this.answers = const [],
    this.myAnswers = const {},
    this.isLoading = false,
    this.isSubmitting = false,
    this.isResolving = false,
    this.error,
    this.secondsRemaining,
  });

  final NameplaceGame? game;
  final List<NameplacePlayer> players;
  final List<NameplaceRound> rounds;
  final List<NameplaceAnswerModel> answers;
  final Map<String, String> myAnswers; // category → answer
  final bool isLoading;
  final bool isSubmitting;
  final bool isResolving;
  final String? error;
  final int? secondsRemaining;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  NameplaceState copyWith({
    NameplaceGame? game,
    List<NameplacePlayer>? players,
    List<NameplaceRound>? rounds,
    List<NameplaceAnswerModel>? answers,
    Map<String, String>? myAnswers,
    bool? isLoading,
    bool? isSubmitting,
    bool? isResolving,
    String? error,
    bool clearError = false,
    int? secondsRemaining,
    bool clearTimer = false,
  }) => NameplaceState(
    game: game ?? this.game,
    players: players ?? this.players,
    rounds: rounds ?? this.rounds,
    answers: answers ?? this.answers,
    myAnswers: myAnswers ?? this.myAnswers,
    isLoading: isLoading ?? this.isLoading,
    isSubmitting: isSubmitting ?? this.isSubmitting,
    isResolving: isResolving ?? this.isResolving,
    error: clearError ? null : (error ?? this.error),
    secondsRemaining: clearTimer ? null : (secondsRemaining ?? this.secondsRemaining),
  );
}

class NameplaceNotifier extends StateNotifier<NameplaceState> {
  NameplaceNotifier(this._ref, this.familyId) : super(const NameplaceState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName => _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  Timer? _roundTimer;
  String? _gameId;

  Future<String?> createGame({int totalRounds = 5, int roundTimerSeconds = 60}) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return null; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final resp = await client.from('nameplace_games').insert({
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'status': 'waiting',
        'categories': defaultCategories,
        'roundTimerSeconds': roundTimerSeconds,
        'totalRounds': totalRounds,
        'currentRound': 0,
        'allAnswersSubmitted': false,
        'roundScoringDone': false,
      }).select().single();
      final game = NameplaceGame.fromJson(resp as Map<String, dynamic>);
      _gameId = game.id;
      await client.from('nameplace_players').insert({
        'gameId': game.id, 'userId': myId, 'userName': _myName, 'turnOrder': 0, 'totalScore': 0, 'hasSubmitted': false,
      });
      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      await _refreshPlayers(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[Nameplace] createGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  Future<bool> joinGame(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return false; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final gameResp = await client.from('nameplace_games').select().eq('id', gameId).single();
      final game = NameplaceGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = gameId;
      final playersResp = await client.from('nameplace_players').select().eq('gameId', gameId).order('turnOrder', ascending: true);
      final existing = playersResp.map((p) => NameplacePlayer.fromJson(p as Map<String, dynamic>)).toList();
      if (existing.length >= 20) { state = state.copyWith(isLoading: false, error: 'Game is full'); return false; }
      if (!existing.any((p) => p.userId == myId)) {
        await client.from('nameplace_players').upsert({
          'gameId': gameId, 'userId': myId, 'userName': _myName, 'turnOrder': existing.length, 'totalScore': 0, 'hasSubmitted': false,
        }, onConflict: 'gameId,userId');
      }
      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshPlayers(gameId);
      await _refreshRounds(gameId);
      return true;
    } catch (e) {
      debugPrint('[Nameplace] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  Future<void> startGame() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    if (client == null || gameId == null || game == null) return;
    if (state.players.length < 2) { state = state.copyWith(error: 'Need 2+ players'); return; }
    try {
      await _startRound(1);
    } catch (e) {
      debugPrint('[Nameplace] startGame error: $e');
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> _startRound(int roundNumber) async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    if (client == null || gameId == null || game == null) return;

    final sortedPlayers = List<NameplacePlayer>.from(state.players)..sort((a, b) => a.turnOrder.compareTo(b.turnOrder));
    final playerIds = sortedPlayers.map((p) => p.userId).toList();
    final chooserId = nextLetterChooserId(playerIdsInOrder: playerIds, roundNumber: roundNumber);
    final chooser = sortedPlayers.firstWhere((p) => p.userId == chooserId);

    await client.from('nameplace_games').update({
      'status': 'in_progress',
      'currentRound': roundNumber,
      'currentLetterChooserId': chooserId,
      'currentLetter': null,
      'roundEndsAt': null,
      'allAnswersSubmitted': false,
      'roundScoringDone': false,
      'startedAt': roundNumber == 1 ? DateTime.now().toIso8601String() : null,
    }).eq('id', gameId);

    // Reset hasSubmitted for all players
    for (final p in state.players) {
      await client.from('nameplace_players').update({'hasSubmitted': false}).eq('id', p.id);
    }
  }

  /// Letter chooser: pick a letter.
  Future<void> pickLetter(String letter) async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    if (client == null || gameId == null || game == null) return;

    final roundEnds = DateTime.now().add(Duration(seconds: game.roundTimerSeconds));
    await client.from('nameplace_games').update({
      'currentLetter': letter,
      'roundEndsAt': roundEnds.toIso8601String(),
    }).eq('id', gameId);

    // Insert round record
    final chooser = state.players.firstWhere((p) => p.userId == game.currentLetterChooserId);
    await client.from('nameplace_rounds').insert({
      'gameId': gameId,
      'roundNumber': game.currentRound,
      'letter': letter,
      'letterChooserId': game.currentLetterChooserId!,
      'letterChooserName': chooser.userName,
    });

    GameMotionTokens.success();
    _startRoundTimer();
  }

  /// Player: update an answer for a category (local state only until submit).
  void updateAnswer(String category, String answer) {
    final updated = Map<String, String>.from(state.myAnswers);
    updated[category] = answer;
    state = state.copyWith(myAnswers: updated);
  }

  /// Player: submit all answers.
  Future<bool> submitAnswers() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final game = state.game;
    if (client == null || gameId == null || myId == null || game == null) return false;

    // Validate
    final error = validateAnswers(answersByCategory: state.myAnswers, categories: game.categories);
    if (error != null) {
      state = state.copyWith(error: error);
      return false;
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      // Get the current round ID
      final roundResp = await client.from('nameplace_rounds').select().eq('gameId', gameId).eq('roundNumber', game.currentRound).single();
      final roundId = roundResp['id'] as String;

      // Insert answers
      final rows = game.categories.map((cat) => {
        'roundId': roundId,
        'gameId': gameId,
        'playerId': myId,
        'playerName': _myName,
        'category': cat,
        'answerText': state.myAnswers[cat] ?? '-',
      }).toList();
      await client.from('nameplace_answers').insert(rows);

      // Mark as submitted
      await client.from('nameplace_players').update({'hasSubmitted': true}).eq('gameId', gameId).eq('userId', myId);

      state = state.copyWith(isSubmitting: false);
      GameMotionTokens.tap();

      // Check if all submitted → host resolves
      _maybeHostResolve();
      return true;
    } catch (e) {
      debugPrint('[Nameplace] submitAnswers error: $e');
      state = state.copyWith(isSubmitting: false, error: '$e');
      return false;
    }
  }

  void _maybeHostResolve() {
    final game = state.game;
    if (game == null || !game.isInProgress) return;
    if (game.hostUserId != _myId) return;
    if (game.currentLetter == null) return; // letter not picked yet

    final allSubmitted = state.players.every((p) => p.hasSubmitted);
    if (allSubmitted && !state.isResolving) {
      _resolveRound();
    }
  }

  Future<void> _resolveRound() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    if (client == null || gameId == null || game == null) return;

    _stopRoundTimer();
    state = state.copyWith(isResolving: true);

    try {
      // Fetch all answers for this round
      final roundResp = await client.from('nameplace_rounds').select().eq('gameId', gameId).eq('roundNumber', game.currentRound).single();
      final roundId = roundResp['id'] as String;

      final answersResp = await client.from('nameplace_answers').select().eq('roundId', roundId);
      final answers = answersResp.map((a) => NameplaceAnswerModel.fromJson(a as Map<String, dynamic>)).toList();

      // Convert to logic-layer answers
      final logicAnswers = answers.map((a) => NameplaceAnswer(
        playerId: a.playerId,
        playerName: a.playerName,
        category: a.category,
        answerText: a.answerText,
      )).toList();

      // Score
      final result = scoreRound(answers: logicAnswers, categories: game.categories);

      // Update answers with points
      for (final scored in result.scoredAnswers) {
        await client.from('nameplace_answers').update({
          'pointsAwarded': scored.pointsAwarded,
        }).eq('roundId', roundId).eq('playerId', scored.playerId).eq('category', scored.category);
      }

      // Update player total scores
      for (final entry in result.playerRoundScores.entries) {
        final player = state.players.firstWhere((p) => p.userId == entry.key);
        await client.from('nameplace_players').update({
          'totalScore': player.totalScore + entry.value,
        }).eq('id', player.id);
      }

      // Mark round as scored
      await client.from('nameplace_games').update({
        'roundScoringDone': true,
      }).eq('id', gameId);

      GameMotionTokens.celebrate();
      state = state.copyWith(isResolving: false);

      // Wait a moment for results to be viewed, then advance
      Timer(const Duration(seconds: 1), () {
        _advanceOrEnd();
      });
    } catch (e) {
      debugPrint('[Nameplace] resolveRound error: $e');
      state = state.copyWith(isResolving: false, error: '$e');
    }
  }

  Future<void> _advanceOrEnd() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    if (client == null || gameId == null || game == null) return;

    if (game.currentRound >= game.totalRounds) {
      // Game over — compute winners
      final updatedPlayers = await client.from('nameplace_players').select().eq('gameId', gameId).order('turnOrder', ascending: true);
      final players = updatedPlayers.map((p) => NameplacePlayer.fromJson(p as Map<String, dynamic>)).toList();
      final scores = {for (final p in players) p.userId: p.totalScore};
      final finalResult = computeFinalScores(playerTotalScores: scores);

      final winnerNames = players.where((p) => finalResult.winnerIds.contains(p.userId)).map((p) => p.userName).toList();

      await client.from('nameplace_games').update({
        'status': 'completed',
        'completedAt': DateTime.now().toIso8601String(),
        'winnerUserIds': finalResult.winnerIds,
        'winnerNames': winnerNames,
      }).eq('id', gameId);

      GameMotionTokens.celebrate();
    } else {
      // Next round
      await _startRound(game.currentRound + 1);
    }
  }

  void _startRoundTimer() {
    _stopRoundTimer();
    final game = state.game;
    if (game == null || !game.isInProgress) return;
    if (game.hostUserId != _myId) return; // only host runs timer

    _roundTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final endsAt = state.game?.roundEndsAt;
      if (endsAt == null) { t.cancel(); return; }
      final remaining = endsAt.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        t.cancel();
        if (!state.isResolving) _resolveRound();
      }
    });
  }

  void _stopRoundTimer() { _roundTimer?.cancel(); _roundTimer = null; }

  void leaveGame() {
    _stopRoundTimer();
    _channel?.unsubscribe();
    _channel = null;
    _gameId = null;
  }

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    _channel = client.channel('nameplace_game:$gameId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public', table: 'nameplace_games',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
        callback: (payload) {
          final updated = NameplaceGame.fromJson(payload.newRecord);
          if (updated.isCompleted) GameMotionTokens.celebrate();
          if (updated.currentLetter != null && state.game?.currentLetter == null) {
            GameMotionTokens.success();
            _startRoundTimer();
          }
          state = state.copyWith(game: updated);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public', table: 'nameplace_players',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) {
          final player = NameplacePlayer.fromJson(payload.newRecord);
          if (!state.players.any((p) => p.userId == player.userId)) {
            state = state.copyWith(players: [...state.players, player]);
          }
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public', table: 'nameplace_players',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) {
          final updated = NameplacePlayer.fromJson(payload.newRecord);
          final next = state.players.map((p) => p.userId == updated.userId ? updated : p).toList();
          state = state.copyWith(players: next);
          _maybeHostResolve();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public', table: 'nameplace_rounds',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) {
          final round = NameplaceRound.fromJson(payload.newRecord);
          if (!state.rounds.any((r) => r.id == round.id)) {
            state = state.copyWith(rounds: [...state.rounds, round]);
          }
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public', table: 'nameplace_answers',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) async {
          // Only load answers when roundScoringDone is true (privacy)
          if (state.game?.roundScoringDone == true) {
            await _refreshAnswers(gameId);
          }
        },
      )
      .subscribe();
  }

  Future<void> _refreshPlayers(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client.from('nameplace_players').select().eq('gameId', gameId).order('turnOrder', ascending: true);
      state = state.copyWith(players: resp.map((p) => NameplacePlayer.fromJson(p as Map<String, dynamic>)).toList());
    } catch (e) { debugPrint('[Nameplace] refreshPlayers error: $e'); }
  }

  Future<void> _refreshRounds(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client.from('nameplace_rounds').select().eq('gameId', gameId).order('roundNumber', ascending: true);
      state = state.copyWith(rounds: resp.map((r) => NameplaceRound.fromJson(r as Map<String, dynamic>)).toList());
    } catch (e) { debugPrint('[Nameplace] refreshRounds error: $e'); }
  }

  Future<void> _refreshAnswers(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client.from('nameplace_answers').select().eq('gameId', gameId).order('category', ascending: true);
      state = state.copyWith(answers: resp.map((a) => NameplaceAnswerModel.fromJson(a as Map<String, dynamic>)).toList());
    } catch (e) { debugPrint('[Nameplace] refreshAnswers error: $e'); }
  }

  @override
  void dispose() {
    _stopRoundTimer();
    _channel?.unsubscribe();
    super.dispose();
  }
}

final nameplaceProvider = StateNotifierProvider.autoDispose
    .family<NameplaceNotifier, NameplaceState, String>(
  (ref, familyId) => NameplaceNotifier(ref, familyId),
);
