// lib/features/games/truthordare/truthordare_provider.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import 'truthordare_models.dart';
import 'truthordare_selection_logic.dart';

class TodState {
  const TodState({this.game, this.players = const [], this.rounds = const [], this.prompts = const [], this.myPrompts = const [], this.pendingPrompts = const [], this.isLoading = false, this.isSubmitting = false, this.isSpinning = false, this.error, this.currentRound, this.usedPromptIds = const {}, this.approvedPromptIds = const []});
  final TodGame? game; final List<TodPlayer> players; final List<TodRound> rounds; final List<TodPrompt> prompts; final List<TodPrompt> myPrompts; final List<TodPrompt> pendingPrompts;
  final bool isLoading; final bool isSubmitting; final bool isSpinning; final String? error;
  final TodRound? currentRound; final Set<String> usedPromptIds; final List<String> approvedPromptIds;
  bool get isWaiting => game?.isWaiting ?? false; bool get isInProgress => game?.isInProgress ?? false; bool get isCompleted => game?.isCompleted ?? false; bool get hasGame => game != null;

  TodState copyWith({TodGame? game, List<TodPlayer>? players, List<TodRound>? rounds, List<TodPrompt>? prompts, List<TodPrompt>? myPrompts, List<TodPrompt>? pendingPrompts, bool? isLoading, bool? isSubmitting, bool? isSpinning, String? error, bool clearError = false, TodRound? currentRound, Set<String>? usedPromptIds, List<String>? approvedPromptIds}) =>
    TodState(game: game ?? this.game, players: players ?? this.players, rounds: rounds ?? this.rounds, prompts: prompts ?? this.prompts, myPrompts: myPrompts ?? this.myPrompts, pendingPrompts: pendingPrompts ?? this.pendingPrompts, isLoading: isLoading ?? this.isLoading, isSubmitting: isSubmitting ?? this.isSubmitting, isSpinning: isSpinning ?? this.isSpinning, error: clearError ? null : (error ?? this.error), currentRound: currentRound ?? this.currentRound, usedPromptIds: usedPromptIds ?? this.usedPromptIds, approvedPromptIds: approvedPromptIds ?? this.approvedPromptIds);
}

class TodNotifier extends StateNotifier<TodState> {
  TodNotifier(this._ref, this.familyId) : super(const TodState());
  final Ref _ref; final String familyId;
  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName => _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';
  RealtimeChannel? _channel; String? _gameId;

  Future<String?> createGame() async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return null; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // Seed prompts if none exist
      await _seedPromptsIfNeeded(client);
      final resp = await client.from('truthordare_games').insert({'familyId': familyId, 'hostUserId': myId, 'hostUserName': _myName, 'status': 'waiting', 'roundNumber': 0}).select().single();
      final game = TodGame.fromJson(resp as Map<String, dynamic>); _gameId = game.id;
      await client.from('truthordare_players').insert({'gameId': game.id, 'userId': myId, 'userName': _myName, 'seatPosition': 0, 'timesSelected': 0});
      state = state.copyWith(game: game, isLoading: false); _subscribeToRealtime(game.id);
      await _refreshPlayers(game.id); await _refreshApprovedPrompts();
      return game.id;
    } catch (e) { debugPrint('[Tod] createGame error: $e'); state = state.copyWith(isLoading: false, error: '$e'); return null; }
  }

  Future<bool> joinGame(String gameId) async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return false; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final gameResp = await client.from('truthordare_games').select().eq('id', gameId).single();
      final game = TodGame.fromJson(gameResp as Map<String, dynamic>); _gameId = gameId;
      final playersResp = await client.from('truthordare_players').select().eq('gameId', gameId).order('seatPosition', ascending: true);
      final existing = playersResp.map((p) => TodPlayer.fromJson(p as Map<String, dynamic>)).toList();
      if (existing.length >= 12) { state = state.copyWith(isLoading: false, error: 'Game is full'); return false; }
      if (!existing.any((p) => p.userId == myId)) {
        await client.from('truthordare_players').upsert({'gameId': gameId, 'userId': myId, 'userName': _myName, 'seatPosition': existing.length, 'timesSelected': 0}, onConflict: 'gameId,userId');
      }
      state = state.copyWith(game: game, isLoading: false); _subscribeToRealtime(gameId);
      await _refreshPlayers(gameId); await _refreshRounds(gameId); await _refreshApprovedPrompts();
      return true;
    } catch (e) { debugPrint('[Tod] joinGame error: $e'); state = state.copyWith(isLoading: false, error: '$e'); return false; }
  }

  Future<void> startGame() async {
    final client = _client; final gameId = _gameId; final game = state.game;
    if (client == null || gameId == null || game == null) return;
    if (state.players.length < 4) { state = state.copyWith(error: 'Need 4+ players'); return; }
    final firstSpinner = state.players.first.userId;
    await client.from('truthordare_games').update({'status': 'in_progress', 'currentSpinnerId': firstSpinner, 'roundNumber': 1, 'startedAt': DateTime.now().toIso8601String()}).eq('id', gameId);
  }

  /// Spinner: spin the bottle. Host-authoritative selection.
  Future<void> spinBottle() async {
    final client = _client; final gameId = _gameId; final game = state.game;
    if (client == null || gameId == null || game == null) return;
    if (game.currentSpinnerId != _myId) return;
    state = state.copyWith(isSpinning: true, clearError: true);
    try {
      final players = state.players.map((p) => (userId: p.userId, timesSelected: p.timesSelected)).toList();
      final selectedId = selectPlayer(players: players, spinnerId: game.currentSpinnerId!);
      if (selectedId == null) { state = state.copyWith(isSpinning: false, error: 'No players to select'); return; }
      final selectedPlayer = state.players.firstWhere((p) => p.userId == selectedId);
      final spinner = state.players.firstWhere((p) => p.userId == game.currentSpinnerId);
      // Insert round
      await client.from('truthordare_rounds').insert({'gameId': gameId, 'roundNumber': game.roundNumber, 'spinnerId': spinner.userId, 'spinnerName': spinner.userName, 'selectedPlayerId': selectedId, 'selectedPlayerName': selectedPlayer.userName});
      // Increment timesSelected
      await client.from('truthordare_players').update({'timesSelected': selectedPlayer.timesSelected + 1}).eq('id', selectedPlayer.id);
      GameMotionTokens.celebrate();
      state = state.copyWith(isSpinning: false);
    } catch (e) { debugPrint('[Tod] spinBottle error: $e'); state = state.copyWith(isSpinning: false, error: '$e'); }
  }

  /// Selected player: choose Truth or Dare
  Future<void> chooseTruthOrDare(String choice) async {
    final client = _client; final gameId = _gameId; final game = state.game;
    if (client == null || gameId == null || game == null) return;
    try {
      // Get current round
      final roundResp = await client.from('truthordare_rounds').select().eq('gameId', gameId).eq('roundNumber', game.roundNumber).single();
      final roundId = roundResp['id'] as String;
      // Select a prompt
      final promptId = selectPrompt(promptIds: state.approvedPromptIds, usedPromptIds: state.usedPromptIds);
      String? promptText;
      if (promptId != null) {
        final pResp = await client.from('truthordare_prompts').select().eq('id', promptId).single();
        promptText = pResp['promptText'] as String;
      }
      await client.from('truthordare_rounds').update({'choice': choice, 'promptId': promptId, 'promptText': promptText}).eq('id', roundId);
      // Track used prompt
      final newUsed = Set<String>.from(state.usedPromptIds);
      if (promptId != null) newUsed.add(promptId);
      state = state.copyWith(usedPromptIds: newUsed);
      GameMotionTokens.tap();
    } catch (e) { debugPrint('[Tod] chooseTruthOrDare error: $e'); state = state.copyWith(error: '$e'); }
  }

  /// Mark the current round as completed and advance.
  Future<void> completeRound() async {
    final client = _client; final gameId = _gameId; final game = state.game;
    if (client == null || gameId == null || game == null) return;
    try {
      final roundResp = await client.from('truthordare_rounds').select().eq('gameId', gameId).eq('roundNumber', game.roundNumber).single();
      final roundId = roundResp['id'] as String;
      await client.from('truthordare_rounds').update({'completed': true}).eq('id', roundId);
      // Next round — advance spinner to next player in seat order
      final sortedPlayers = List<TodPlayer>.from(state.players)..sort((a, b) => a.seatPosition.compareTo(b.seatPosition));
      final currentIdx = sortedPlayers.indexWhere((p) => p.userId == game.currentSpinnerId);
      final nextIdx = (currentIdx + 1) % sortedPlayers.length;
      final nextSpinner = sortedPlayers[nextIdx];
      await client.from('truthordare_games').update({'roundNumber': game.roundNumber + 1, 'currentSpinnerId': nextSpinner.userId}).eq('id', gameId);
      GameMotionTokens.success();
    } catch (e) { debugPrint('[Tod] completeRound error: $e'); }
  }

  // ── Prompt submission ────────────────────────────────────────────

  Future<bool> submitPrompt(String text, String category) async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final flagged = flagPrompt(text);
      await client.from('truthordare_prompts').insert({'familyId': familyId, 'category': category, 'promptText': text.trim(), 'submittedById': myId, 'submittedByName': _myName, 'status': 'pending', 'flaggedByFilter': flagged});
      state = state.copyWith(isSubmitting: false);
      GameMotionTokens.tap();
      return true;
    } catch (e) { debugPrint('[Tod] submitPrompt error: $e'); state = state.copyWith(isSubmitting: false, error: '$e'); return false; }
  }

  Future<void> reviewPrompt(String promptId, bool approve) async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) return;
    try {
      await client.from('truthordare_prompts').update({'status': approve ? 'approved' : 'rejected', 'reviewedById': myId, 'reviewedByName': _myName, 'reviewedAt': DateTime.now().toIso8601String()}).eq('id', promptId);
      await _refreshPendingPrompts();
      await _refreshApprovedPrompts();
      GameMotionTokens.tap();
    } catch (e) { debugPrint('[Tod] reviewPrompt error: $e'); }
  }

  Future<void> loadMyPrompts() async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) return;
    try {
      final resp = await client.from('truthordare_prompts').select().eq('familyId', familyId).eq('submittedById', myId).order('createdAt', ascending: false);
      state = state.copyWith(myPrompts: resp.map((p) => TodPrompt.fromJson(p as Map<String, dynamic>)).toList());
    } catch (e) { debugPrint('[Tod] loadMyPrompts error: $e'); }
  }

  Future<void> loadPendingPrompts() async {
    await _refreshPendingPrompts();
  }

  // ── Helpers ──────────────────────────────────────────────────────

  Future<void> _seedPromptsIfNeeded(SupabaseClient client) async {
    final existing = await client.from('truthordare_prompts').select().eq('familyId', familyId).limit(1);
    if (existing.isNotEmpty) return;
    final rows = seedPrompts.map((p) => {'familyId': familyId, 'category': p.category, 'promptText': p.text, 'submittedById': _myId!, 'submittedByName': _myName, 'status': 'approved', 'flaggedByFilter': false}).toList();
    await client.from('truthordare_prompts').insert(rows);
  }

  Future<void> _refreshApprovedPrompts() async {
    final client = _client; if (client == null) return;
    try {
      final resp = await client.from('truthordare_prompts').select().eq('familyId', familyId).eq('status', 'approved');
      final prompts = resp.map((p) => TodPrompt.fromJson(p as Map<String, dynamic>)).toList();
      state = state.copyWith(prompts: prompts, approvedPromptIds: prompts.map((p) => p.id).toList());
    } catch (e) { debugPrint('[Tod] refreshApprovedPrompts error: $e'); }
  }

  Future<void> _refreshPendingPrompts() async {
    final client = _client; if (client == null) return;
    try {
      final resp = await client.from('truthordare_prompts').select().eq('familyId', familyId).eq('status', 'pending').order('createdAt', ascending: true);
      state = state.copyWith(pendingPrompts: resp.map((p) => TodPrompt.fromJson(p as Map<String, dynamic>)).toList());
    } catch (e) { debugPrint('[Tod] refreshPendingPrompts error: $e'); }
  }

  Future<void> _refreshPlayers(String gameId) async {
    final client = _client; if (client == null) return;
    try { final resp = await client.from('truthordare_players').select().eq('gameId', gameId).order('seatPosition', ascending: true); state = state.copyWith(players: resp.map((p) => TodPlayer.fromJson(p as Map<String, dynamic>)).toList()); } catch (e) { debugPrint('[Tod] refreshPlayers error: $e'); }
  }

  Future<void> _refreshRounds(String gameId) async {
    final client = _client; if (client == null) return;
    try { final resp = await client.from('truthordare_rounds').select().eq('gameId', gameId).order('roundNumber', ascending: true); final rounds = resp.map((r) => TodRound.fromJson(r as Map<String, dynamic>)).toList(); state = state.copyWith(rounds: rounds, currentRound: rounds.isEmpty ? null : rounds.last); } catch (e) { debugPrint('[Tod] refreshRounds error: $e'); }
  }

  void leaveGame() { _channel?.unsubscribe(); _channel = null; _gameId = null; }

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe(); final client = _client; if (client == null) return;
    _channel = client.channel('tod_game:$gameId')
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'truthordare_games', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
        callback: (payload) { state = state.copyWith(game: TodGame.fromJson(payload.newRecord)); })
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'truthordare_players', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) { final p = TodPlayer.fromJson(payload.newRecord); if (!state.players.any((x) => x.userId == p.userId)) state = state.copyWith(players: [...state.players, p]); })
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'truthordare_players', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) { final updated = TodPlayer.fromJson(payload.newRecord); final next = state.players.map((p) => p.userId == updated.userId ? updated : p).toList(); state = state.copyWith(players: next); })
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'truthordare_rounds', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) { final r = TodRound.fromJson(payload.newRecord); if (!state.rounds.any((x) => x.id == r.id)) state = state.copyWith(rounds: [...state.rounds, r], currentRound: r); })
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'truthordare_rounds', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) { final updated = TodRound.fromJson(payload.newRecord); final next = state.rounds.map((r) => r.id == updated.id ? updated : r).toList(); state = state.copyWith(rounds: next, currentRound: updated); })
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'truthordare_prompts', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'familyId', value: familyId),
        callback: (_) { _refreshApprovedPrompts(); _refreshPendingPrompts(); })
      .subscribe();
  }

  @override
  void dispose() { _channel?.unsubscribe(); super.dispose(); }
}

final todProvider = StateNotifierProvider.autoDispose.family<TodNotifier, TodState, String>((ref, familyId) => TodNotifier(ref, familyId));
