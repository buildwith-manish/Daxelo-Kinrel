// lib/features/games/dotsboxes/dotsboxes_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import 'dotsboxes_game_logic.dart';
import 'dotsboxes_models.dart';

class DbState {
  const DbState({this.game, this.players = const [], this.lines = const [], this.boxes = const [], this.isLoading = false, this.isSubmitting = false, this.error, this.lastCapture});
  final DbGame? game; final List<DbPlayer> players; final List<DbLineRecord> lines; final List<DbBoxRecord> boxes;
  final bool isLoading; final bool isSubmitting; final String? error; final List<(int,int)>? lastCapture;
  bool get isWaiting => game?.isWaiting ?? false; bool get isInProgress => game?.isInProgress ?? false; bool get isCompleted => game?.isCompleted ?? false; bool get hasGame => game != null;

  Set<String> get drawnLineKeys => lines.map((l) => l.toDotsLine().key).toSet();

  DbState copyWith({DbGame? game, List<DbPlayer>? players, List<DbLineRecord>? lines, List<DbBoxRecord>? boxes, bool? isLoading, bool? isSubmitting, String? error, bool clearError = false, List<(int,int)>? lastCapture, bool clearCapture = false}) =>
    DbState(game: game ?? this.game, players: players ?? this.players, lines: lines ?? this.lines, boxes: boxes ?? this.boxes, isLoading: isLoading ?? this.isLoading, isSubmitting: isSubmitting ?? this.isSubmitting, error: clearError ? null : (error ?? this.error), lastCapture: clearCapture ? null : (lastCapture ?? this.lastCapture));
}

class DbNotifier extends StateNotifier<DbState> {
  DbNotifier(this._ref, this.familyId) : super(const DbState());
  final Ref _ref; final String familyId;
  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName => _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';
  RealtimeChannel? _channel; String? _gameId;

  Future<String?> createGame({int gridSize = 5}) async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return null; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final resp = await client.from('dotsboxes_games').insert({'familyId': familyId, 'hostUserId': myId, 'hostUserName': _myName, 'status': 'waiting', 'gridSize': gridSize, 'bonusTurn': false}).select().single();
      final game = DbGame.fromJson(resp as Map<String, dynamic>); _gameId = game.id;
      await client.from('dotsboxes_players').insert({'gameId': game.id, 'userId': myId, 'userName': _myName, 'turnOrder': 0, 'playerColor': 0, 'boxesCaptured': 0});
      // Pre-create all boxes
      final boxRows = <Map<String, dynamic>>[];
      for (int r = 0; r < gridSize; r++) for (int c = 0; c < gridSize; c++) boxRows.add({'gameId': game.id, 'boxRow': r, 'boxCol': c});
      await client.from('dotsboxes_boxes').insert(boxRows);
      state = state.copyWith(game: game, isLoading: false); _subscribeToRealtime(game.id); await _refreshPlayers(game.id); await _refreshLines(game.id); await _refreshBoxes(game.id);
      return game.id;
    } catch (e) { debugPrint('[DB] createGame error: $e'); state = state.copyWith(isLoading: false, error: '$e'); return null; }
  }

  Future<bool> joinGame(String gameId) async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return false; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final gameResp = await client.from('dotsboxes_games').select().eq('id', gameId).single();
      final game = DbGame.fromJson(gameResp as Map<String, dynamic>); _gameId = gameId;
      final playersResp = await client.from('dotsboxes_players').select().eq('gameId', gameId).order('turnOrder', ascending: true);
      final existing = playersResp.map((p) => DbPlayer.fromJson(p as Map<String, dynamic>)).toList();
      if (existing.length >= 4) { state = state.copyWith(isLoading: false, error: 'Game is full'); return false; }
      if (!existing.any((p) => p.userId == myId)) await client.from('dotsboxes_players').upsert({'gameId': gameId, 'userId': myId, 'userName': _myName, 'turnOrder': existing.length, 'playerColor': existing.length, 'boxesCaptured': 0}, onConflict: 'gameId,userId');
      state = state.copyWith(game: game, isLoading: false); _subscribeToRealtime(gameId); await _refreshPlayers(gameId); await _refreshLines(gameId); await _refreshBoxes(gameId);
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
    } catch (e) { debugPrint('[DB] joinGame error: $e'); state = state.copyWith(isLoading: false, error: '$e'); return false; }
  }

  Future<void> startGame() async {
    final client = _client; final gameId = _gameId; final game = state.game;
    if (client == null || gameId == null || game == null) return;
    if (state.players.length < 2) { state = state.copyWith(error: 'Need 2+ players'); return; }
    final firstPlayer = state.players.first.userId;
    await client.from('dotsboxes_games').update({'status': 'in_progress', 'currentTurnPlayerId': firstPlayer, 'startedAt': DateTime.now().toIso8601String()}).eq('id', gameId);
  }

  Future<bool> drawLine(LineType type, int row, int col) async {
    final client = _client; final gameId = _gameId; final game = state.game; final myId = _myId;
    if (client == null || gameId == null || game == null || myId == null) return false;
    if (game.currentTurnPlayerId != myId) return false;
    final line = DotsLine(type: type, row: row, col: col);
    if (isLineDrawn(state.drawnLineKeys, line)) { GameMotionTokens.error(); return false; }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      // Insert the line
      await client.from('dotsboxes_lines').insert({'gameId': gameId, 'lineType': type.name, 'row': row, 'col': col, 'drawnByPlayerId': myId, 'drawnByPlayerName': _myName});

      // Evaluate captures
      final newDrawn = Set<String>.from(state.drawnLineKeys)..add(line.key);
      final result = evaluateLineDraw(drawnLines: newDrawn, line: line, gridSize: game.gridSize);

      // Capture boxes
      for (final (br, bc) in result.capturedBoxes) {
        await client.from('dotsboxes_boxes').update({'capturedByPlayerId': myId, 'capturedByPlayerName': _myName, 'capturedAt': DateTime.now().toIso8601String()}).eq('gameId', gameId).eq('boxRow', br).eq('boxCol', bc);
      }

      // Update player score
      if (result.capturedBoxes.isNotEmpty) {
        final myPlayer = state.players.firstWhere((p) => p.userId == myId);
        await client.from('dotsboxes_players').update({'boxesCaptured': myPlayer.boxesCaptured + result.capturedBoxes.length}).eq('id', myPlayer.id);
      }

      // Determine next turn
      String nextPlayerId;
      bool bonusTurn = false;
      if (result.continuesTurn) {
        nextPlayerId = myId; bonusTurn = true;
        GameMotionTokens.celebrate();
      } else {
        final sorted = List<DbPlayer>.from(state.players)..sort((a, b) => a.turnOrder.compareTo(b.turnOrder));
        nextPlayerId = nextPlayerId_(sorted.map((p) => p.userId).toList(), myId);
        GameMotionTokens.tap();
      }

      // Check game over
      final isOver = isGameOver(newDrawn, game.gridSize);
      if (isOver) {
        // Fetch updated scores and determine winners
        final updatedPlayers = await client.from('dotsboxes_players').select().eq('gameId', gameId).order('turnOrder', ascending: true);
        final players = updatedPlayers.map((p) => DbPlayer.fromJson(p as Map<String, dynamic>)).toList();
        final scores = players.map((p) => p.boxesCaptured).toList();
        final winnerIndices = getWinners(scores);
        final winnerIds = winnerIndices.map((i) => players[i].userId).toList();
        final winnerNames = winnerIndices.map((i) => players[i].userName).toList();
        await client.from('dotsboxes_games').update({'status': 'completed', 'completedAt': DateTime.now().toIso8601String(), 'currentTurnPlayerId': nextPlayerId, 'bonusTurn': false, 'winnerUserIds': winnerIds, 'winnerNames': winnerNames}).eq('id', gameId);
        GameMotionTokens.celebrate();
      } else {
        await client.from('dotsboxes_games').update({'currentTurnPlayerId': nextPlayerId, 'bonusTurn': bonusTurn}).eq('id', gameId);
      }

      state = state.copyWith(isSubmitting: false, lastCapture: result.capturedBoxes.isNotEmpty ? result.capturedBoxes : null);
      return true;
    } catch (e) { debugPrint('[DB] drawLine error: $e'); state = state.copyWith(isSubmitting: false, error: '$e'); return false; }
  }

  // Helper to avoid name clash with the logic function
  String nextPlayerId_(List<String> ids, String current) => nextPlayerId(ids, current);

  void leaveGame() { _channel?.unsubscribe(); _channel = null; _gameId = null; }

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe(); final client = _client; if (client == null) return;
    _channel = client.channel('db_game:$gameId')
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'dotsboxes_games', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId),
        callback: (payload) { final updated = DbGame.fromJson(payload.newRecord); if (updated.isCompleted) GameMotionTokens.celebrate(); state = state.copyWith(game: updated); })
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'dotsboxes_players', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) { final updated = DbPlayer.fromJson(payload.newRecord); final next = state.players.map((p) => p.userId == updated.userId ? updated : p).toList(); state = state.copyWith(players: next); })
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'dotsboxes_players', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) { final p = DbPlayer.fromJson(payload.newRecord); if (!state.players.any((x) => x.userId == p.userId)) state = state.copyWith(players: [...state.players, p]); })
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'dotsboxes_lines', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) { final l = DbLineRecord.fromJson(payload.newRecord); if (!state.lines.any((x) => x.id == l.id)) state = state.copyWith(lines: [...state.lines, l]); })
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'dotsboxes_boxes', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId),
        callback: (payload) { final updated = DbBoxRecord.fromJson(payload.newRecord); final next = state.boxes.map((b) => b.id == updated.id ? updated : b).toList(); state = state.copyWith(boxes: next); })
      .subscribe();
  }

  Future<void> _refreshPlayers(String gameId) async {
    final client = _client; if (client == null) return;
    try { final resp = await client.from('dotsboxes_players').select().eq('gameId', gameId).order('turnOrder', ascending: true); state = state.copyWith(players: resp.map((p) => DbPlayer.fromJson(p as Map<String, dynamic>)).toList()); } catch (e) { debugPrint('[DB] refreshPlayers error: $e'); }
  }

  Future<void> _refreshLines(String gameId) async {
    final client = _client; if (client == null) return;
    try { final resp = await client.from('dotsboxes_lines').select().eq('gameId', gameId); state = state.copyWith(lines: resp.map((l) => DbLineRecord.fromJson(l as Map<String, dynamic>)).toList()); } catch (e) { debugPrint('[DB] refreshLines error: $e'); }
  }

  Future<void> _refreshBoxes(String gameId) async {
    final client = _client; if (client == null) return;
    try { final resp = await client.from('dotsboxes_boxes').select().eq('gameId', gameId); state = state.copyWith(boxes: resp.map((b) => DbBoxRecord.fromJson(b as Map<String, dynamic>)).toList()); } catch (e) { debugPrint('[DB] refreshBoxes error: $e'); }
  }

  @override
  void dispose() { _channel?.unsubscribe(); super.dispose(); }
}

final dbProvider = StateNotifierProvider.autoDispose.family<DbNotifier, DbState, String>((ref, familyId) => DbNotifier(ref, familyId));
