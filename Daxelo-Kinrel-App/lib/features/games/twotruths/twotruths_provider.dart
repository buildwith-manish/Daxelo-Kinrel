// lib/features/games/twotruths/twotruths_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import 'twotruths_game_logic.dart';
import 'twotruths_models.dart';

class TtState {
  const TtState({this.game, this.players = const [], this.rounds = const [], this.guesses = const [], this.isLoading = false, this.isSubmitting = false, this.isResolving = false, this.error, this.myGuess});
  final TtGame? game; final List<TtPlayer> players; final List<TtRound> rounds; final List<TtGuess> guesses;
  final bool isLoading; final bool isSubmitting; final bool isResolving; final String? error; final int? myGuess;
  bool get isWaiting => game?.isWaiting ?? false; bool get isInProgress => game?.isInProgress ?? false; bool get isCompleted => game?.isCompleted ?? false; bool get hasGame => game != null;
  TtRound? get currentRound => rounds.isEmpty ? null : rounds.last;

  TtState copyWith({TtGame? game, List<TtPlayer>? players, List<TtRound>? rounds, List<TtGuess>? guesses, bool? isLoading, bool? isSubmitting, bool? isResolving, String? error, bool clearError = false, int? myGuess, bool clearGuess = false}) =>
    TtState(game: game ?? this.game, players: players ?? this.players, rounds: rounds ?? this.rounds, guesses: guesses ?? this.guesses, isLoading: isLoading ?? this.isLoading, isSubmitting: isSubmitting ?? this.isSubmitting, isResolving: isResolving ?? this.isResolving, error: clearError ? null : (error ?? this.error), myGuess: clearGuess ? null : (myGuess ?? this.myGuess));
}

class TtNotifier extends StateNotifier<TtState> {
  TtNotifier(this._ref, this.familyId) : super(const TtState());
  final Ref _ref; final String familyId;
  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName => _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';
  RealtimeChannel? _channel; Timer? _roundTimer; String? _gameId;

  Future<String?> createGame({TtMode mode = TtMode.playerAuthored, int totalRounds = 3, int roundTimerSeconds = 30}) async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return null; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final resp = await client.from('twotruths_games').insert({'familyId': familyId, 'hostUserId': myId, 'hostUserName': _myName, 'status': 'waiting', 'mode': mode.name, 'totalRounds': totalRounds, 'roundTimerSeconds': roundTimerSeconds, 'currentRound': 0, 'allGuessesSubmitted': false, 'roundResolved': false}).select().single();
      final game = TtGame.fromJson(resp as Map<String, dynamic>); _gameId = game.id;
      await client.from('twotruths_players').insert({'gameId': game.id, 'userId': myId, 'userName': _myName, 'turnOrder': 0, 'totalScore': 0, 'hasGuessed': false});
      state = state.copyWith(game: game, isLoading: false); _subscribeToRealtime(game.id); await _refreshPlayers(game.id);
      return game.id;
    } catch (e) { debugPrint('[TT] createGame error: $e'); state = state.copyWith(isLoading: false, error: '$e'); return null; }
  }

  Future<bool> joinGame(String gameId) async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return false; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final gameResp = await client.from('twotruths_games').select().eq('id', gameId).single();
      final game = TtGame.fromJson(gameResp as Map<String, dynamic>); _gameId = gameId;
      final playersResp = await client.from('twotruths_players').select().eq('gameId', gameId).order('turnOrder', ascending: true);
      final existing = playersResp.map((p) => TtPlayer.fromJson(p as Map<String, dynamic>)).toList();
      if (existing.length >= 12) { state = state.copyWith(isLoading: false, error: 'Game is full'); return false; }
      if (!existing.any((p) => p.userId == myId)) await client.from('twotruths_players').upsert({'gameId': gameId, 'userId': myId, 'userName': _myName, 'turnOrder': existing.length, 'totalScore': 0, 'hasGuessed': false}, onConflict: 'gameId,userId');
      state = state.copyWith(game: game, isLoading: false); _subscribeToRealtime(gameId); await _refreshPlayers(gameId); await _refreshRounds(gameId);
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
    } catch (e) { debugPrint('[TT] joinGame error: $e'); state = state.copyWith(isLoading: false, error: '$e'); return false; }
  }

  Future<void> startGame() async {
    final client = _client; final gameId = _gameId; final game = state.game;
    if (client == null || gameId == null || game == null) return;
    if (state.players.length < 4) { state = state.copyWith(error: 'Need 4+ players'); return; }
    await _startRound(1);
  }

  Future<void> _startRound(int roundNumber) async {
    final client = _client; final gameId = _gameId; final game = state.game;
    if (client == null || gameId == null || game == null) return;
    final sorted = List<TtPlayer>.from(state.players)..sort((a, b) => a.turnOrder.compareTo(b.turnOrder));
    final playerIds = sorted.map((p) => p.userId).toList();
    final submitterId = nextSubmitterId(playerIdsInOrder: playerIds, roundNumber: roundNumber);
    await client.from('twotruths_games').update({'status': 'in_progress', 'currentRound': roundNumber, 'currentSubmitterId': submitterId, 'roundEndsAt': null, 'allGuessesSubmitted': false, 'roundResolved': false, 'startedAt': roundNumber == 1 ? DateTime.now().toIso8601String() : null}).eq('id', gameId);
    for (final p in state.players) await client.from('twotruths_players').update({'hasGuessed': false}).eq('id', p.id);
  }

  /// Submitter: submit 3 statements (or 2 + AI lie).
  Future<bool> submitStatements(String s1, String s2, String s3, int lieIndex) async {
    final client = _client; final gameId = _gameId; final game = state.game; final myId = _myId;
    if (client == null || gameId == null || game == null || myId == null) return false;
    final error = validateStatements(s1, s2, s3);
    if (error != null) { state = state.copyWith(error: error); return false; }
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final submitter = state.players.firstWhere((p) => p.userId == myId);
      // In AI-lie mode, lieIndex is always 3 (the AI-generated statement)
      final actualLieIndex = game.mode == TtMode.aiLie ? 3 : lieIndex;
      await client.from('twotruths_rounds').insert({'gameId': gameId, 'roundNumber': game.currentRound, 'submitterId': myId, 'submitterName': submitter.userName, 'statement1': s1.trim(), 'statement2': s2.trim(), 'statement3': s3.trim(), 'lieIndex': actualLieIndex});
      final roundEnds = DateTime.now().add(Duration(seconds: game.roundTimerSeconds));
      await client.from('twotruths_games').update({'roundEndsAt': roundEnds.toIso8601String()}).eq('id', gameId);
      state = state.copyWith(isSubmitting: false); _startRoundTimer(); return true;
    } catch (e) { debugPrint('[TT] submitStatements error: $e'); state = state.copyWith(isSubmitting: false, error: '$e'); return false; }
  }

  /// Guesser: submit a guess.
  Future<bool> submitGuess(int guessedLieIndex) async {
    final client = _client; final gameId = _gameId; final myId = _myId; final game = state.game;
    if (client == null || gameId == null || myId == null || game == null) return false;
    if (game.currentSubmitterId == myId) return false; // submitter can't guess
    try {
      final round = state.currentRound; if (round == null) return false;
      await client.from('twotruths_guesses').upsert({'roundId': round.id, 'gameId': gameId, 'guesserId': myId, 'guesserName': _myName, 'guessedLieIndex': guessedLieIndex}, onConflict: 'roundId,guesserId');
      await client.from('twotruths_players').update({'hasGuessed': true}).eq('gameId', gameId).eq('userId', myId);
      state = state.copyWith(myGuess: guessedLieIndex); GameMotionTokens.tap();
      _maybeHostResolve(); return true;
    } catch (e) { debugPrint('[TT] submitGuess error: $e'); return false; }
  }

  void _maybeHostResolve() {
    final game = state.game; if (game == null || !game.isInProgress) return;
    if (game.hostUserId != _myId) return;
    if (game.currentSubmitterId == null || game.roundEndsAt == null) return;
    final guessers = state.players.where((p) => p.userId != game.currentSubmitterId).toList();
    final allGuessed = guessers.every((p) => p.hasGuessed);
    if (allGuessed && !state.isResolving) _resolveRound();
  }

  Future<void> _resolveRound() async {
    final client = _client; final gameId = _gameId; final game = state.game;
    if (client == null || gameId == null || game == null) return;
    _stopRoundTimer(); state = state.copyWith(isResolving: true);
    try {
      final round = state.currentRound; if (round == null) { state = state.copyWith(isResolving: false); return; }
      // Fetch all guesses
      final guessesResp = await client.from('twotruths_guesses').select().eq('roundId', round.id);
      final guesses = <String, int>{}; // guesserId → guessedLieIndex
      for (final g in guessesResp) { final guess = TtGuess.fromJson(g as Map<String, dynamic>); guesses[guess.guesserId] = guess.guessedLieIndex; }
      // Score
      final guesserIds = state.players.where((p) => p.userId != round.submitterId).map((p) => p.userId).toList();
      final result = scoreRound(guesses: guesses, actualLieIndex: round.lieIndex, guesserIds: guesserIds, submitterId: round.submitterId);
      // Update guesses with isCorrect
      for (final entry in result.guesserScores.entries) {
        final isCorrect = entry.value == 1;
        await client.from('twotruths_guesses').update({'isCorrect': isCorrect}).eq('roundId', round.id).eq('guesserId', entry.key);
      }
      // Update player scores
      for (final p in state.players) {
        int delta = 0;
        if (p.userId == round.submitterId) delta = result.submitterScore;
        else delta = result.guesserScores[p.userId] ?? 0;
        if (delta > 0) await client.from('twotruths_players').update({'totalScore': p.totalScore + delta}).eq('id', p.id);
      }
      // Mark round resolved
      await client.from('twotruths_games').update({'roundResolved': true}).eq('id', gameId);
      GameMotionTokens.celebrate(); state = state.copyWith(isResolving: false);
    } catch (e) { debugPrint('[TT] resolveRound error: $e'); state = state.copyWith(isResolving: false, error: '$e'); }
  }

  /// Host: advance to next round or end game.
  Future<void> advanceOrEnd() async {
    final client = _client; final gameId = _gameId; final game = state.game;
    if (client == null || gameId == null || game == null) return;
    if (game.currentRound >= game.totalRounds) {
      // Game over
      final updatedPlayers = await client.from('twotruths_players').select().eq('gameId', gameId).order('turnOrder', ascending: true);
      final players = updatedPlayers.map((p) => TtPlayer.fromJson(p as Map<String, dynamic>)).toList();
      final scores = {for (final p in players) p.userId: p.totalScore};
      final finalResult = computeFinalScores(scores);
      final winnerNames = players.where((p) => finalResult.winnerIds.contains(p.userId)).map((p) => p.userName).toList();
      await client.from('twotruths_games').update({'status': 'completed', 'completedAt': DateTime.now().toIso8601String(), 'winnerUserIds': finalResult.winnerIds, 'winnerNames': winnerNames}).eq('id', gameId);
      GameMotionTokens.celebrate();
    } else {
      await _startRound(game.currentRound + 1);
      state = state.copyWith(clearGuess: true);
    }
  }

  void _startRoundTimer() {
    _stopRoundTimer(); final game = state.game; if (game == null || !game.isInProgress) return;
    if (game.hostUserId != _myId) return;
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final endsAt = state.game?.roundEndsAt; if (endsAt == null) { t.cancel(); return; }
      if (endsAt.difference(DateTime.now()).inSeconds <= 0) { t.cancel(); if (!state.isResolving) _resolveRound(); }
    });
  }

  void _stopRoundTimer() { _roundTimer?.cancel(); _roundTimer = null; }
  void leaveGame() { _stopRoundTimer(); _channel?.unsubscribe(); _channel = null; _gameId = null; }

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe(); final client = _client; if (client == null) return;
    _channel = client.channel('tt_game:$gameId')
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'twotruths_games', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
        callback: (payload) {
          final updated = TtGame.fromJson(payload.newRecord);
          if (updated.roundResolved && !state.game!.roundResolved) { GameMotionTokens.celebrate(); _refreshGuesses(gameId); }
          if (updated.roundEndsAt != null && state.game?.roundEndsAt == null) _startRoundTimer();
          state = state.copyWith(game: updated);
        })
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'twotruths_players', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) { final p = TtPlayer.fromJson(payload.newRecord); if (!state.players.any((x) => x.userId == p.userId)) state = state.copyWith(players: [...state.players, p]); })
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'twotruths_players', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) { final updated = TtPlayer.fromJson(payload.newRecord); final next = state.players.map((p) => p.userId == updated.userId ? updated : p).toList(); state = state.copyWith(players: next); _maybeHostResolve(); })
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'twotruths_rounds', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) { final r = TtRound.fromJson(payload.newRecord); if (!state.rounds.any((x) => x.id == r.id)) state = state.copyWith(rounds: [...state.rounds, r]); })
      .subscribe();
  }

  Future<void> _refreshPlayers(String gameId) async {
    final client = _client; if (client == null) return;
    try { final resp = await client.from('twotruths_players').select().eq('gameId', gameId).order('turnOrder', ascending: true); state = state.copyWith(players: resp.map((p) => TtPlayer.fromJson(p as Map<String, dynamic>)).toList()); } catch (e) { debugPrint('[TT] refreshPlayers error: $e'); }
  }

  Future<void> _refreshRounds(String gameId) async {
    final client = _client; if (client == null) return;
    try { final resp = await client.from('twotruths_rounds').select().eq('gameId', gameId).order('roundNumber', ascending: true); state = state.copyWith(rounds: resp.map((r) => TtRound.fromJson(r as Map<String, dynamic>)).toList()); } catch (e) { debugPrint('[TT] refreshRounds error: $e'); }
  }

  Future<void> _refreshGuesses(String gameId) async {
    final client = _client; if (client == null) return;
    try {
      final round = state.currentRound; if (round == null) return;
      final resp = await client.from('twotruths_guesses').select().eq('roundId', round.id);
      state = state.copyWith(guesses: resp.map((g) => TtGuess.fromJson(g as Map<String, dynamic>)).toList());
    } catch (e) { debugPrint('[TT] refreshGuesses error: $e'); }
  }

  @override
  void dispose() { _stopRoundTimer(); _channel?.unsubscribe(); super.dispose(); }
}

final ttProvider = StateNotifierProvider.autoDispose.family<TtNotifier, TtState, String>((ref, familyId) => TtNotifier(ref, familyId));
