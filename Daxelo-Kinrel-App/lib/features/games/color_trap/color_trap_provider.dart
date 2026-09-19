// lib/features/games/color_trap/color_trap_provider.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/services/temporary_room_service.dart';
import 'color_trap_engine.dart';
import 'color_trap_models.dart';

class ColorTrapState {
  const ColorTrapState({this.game, this.players = const [], this.isLoading = false, this.isStarting = false, this.isLeaving = false, this.error, this.amSpectator = false});
  final ColorTrapGame? game; final List<ColorTrapPlayerWire> players;
  final bool isLoading; final bool isStarting; final bool isLeaving; final String? error; final bool amSpectator;
  bool get isWaiting => game?.isWaiting ?? false; bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false; bool get hasGame => game != null;
  ColorTrapPlayerWire? playerFor(String? userId) { if (userId == null) return null; for (final p in players) { if (p.userId == userId) return p; } return null; }
  ColorTrapState copyWith({ColorTrapGame? game, List<ColorTrapPlayerWire>? players, bool? isLoading, bool? isStarting, bool? isLeaving, bool clearError = false, String? error, bool? amSpectator}) => ColorTrapState(
    game: game ?? this.game, players: players ?? this.players, isLoading: isLoading ?? this.isLoading,
    isStarting: isStarting ?? this.isStarting, isLeaving: isLeaving ?? this.isLeaving,
    error: clearError ? null : (error ?? this.error), amSpectator: amSpectator ?? this.amSpectator);
}

class ColorTrapNotifier extends StateNotifier<ColorTrapState> {
  ColorTrapNotifier(this._ref, this.familyId) : super(const ColorTrapState());
  final Ref _ref; final String familyId;
  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName => _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';
  RealtimeChannel? _channel; String? _gameId; Timer? _watchdogTimer; Timer? _cleanupTimer;

  Future<String?> createGame({required int maxPlayers, required ColorTrapDifficulty difficulty, String? roomName, bool spectatorsEnabled = true}) async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return null; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final body = <String, dynamic>{'familyId': familyId, 'hostUserId': myId, 'hostUserName': _myName, 'status': 'waiting', 'maxPlayers': maxPlayers, 'spectatorsEnabled': spectatorsEnabled, 'difficulty': difficulty.wire, 'autoCloseDeadline': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(), if (roomName != null && roomName.trim().isNotEmpty) 'roomName': roomName.trim()};
      final resp = await client.from('color_trap_games').insert(body).select().single();
      final game = ColorTrapGame.fromJson(resp); _gameId = game.id;
      await client.from('color_trap_players').insert({'gameId': game.id, 'userId': myId, 'userName': _myName});
      await client.rpc('fn_record_room_join', params: {'p_game_table': 'color_trap_games', 'p_game_id': game.id, 'p_family_id': familyId, 'p_user_id': myId, 'p_user_name': _myName, 'p_role': 'host'});
      state = state.copyWith(game: game, isLoading: false); _subscribeToRealtime(game.id); await _refreshPlayers(game.id); return game.id;
    } catch (e) { debugPrint('[ColorTrap] createGame error: $e'); state = state.copyWith(isLoading: false, error: '$e'); return null; }
  }

  Future<bool> joinGame(String gameId) async {
    final client = _client; final myId = _myId;
    if (client == null || myId == null) { state = state.copyWith(error: 'Not signed in'); return false; }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final gameResp = await client.from('color_trap_games').select().eq('id', gameId).maybeSingle();
      if (gameResp == null) { state = state.copyWith(isLoading: false, error: 'Game not found'); return false; }
      final game = ColorTrapGame.fromJson(gameResp); _gameId = gameId;
      if (game.isInProgress || game.isCompleted) {
        await client.rpc('fn_join_spectator', params: {'p_game_table': 'color_trap_games', 'p_game_id': gameId, 'p_user_id': myId, 'p_user_name': _myName});
        state = state.copyWith(game: game, isLoading: false, amSpectator: true); _subscribeToRealtime(gameId); await _refreshPlayers(gameId); return true;
      }
      final existing = await client.from('color_trap_players').select().eq('gameId', gameId).eq('userId', myId).maybeSingle();
      if (existing == null) {
        final activeCount = await _countActivePlayers(gameId);
        if (activeCount >= game.maxPlayers) { state = state.copyWith(isLoading: false, error: 'Room is full'); return false; }
        await client.from('color_trap_players').insert({'gameId': gameId, 'userId': myId, 'userName': _myName});
        await client.rpc('fn_record_room_join', params: {'p_game_table': 'color_trap_games', 'p_game_id': gameId, 'p_family_id': familyId, 'p_user_id': myId, 'p_user_name': _myName, 'p_role': 'player'});
      } else if (existing['leftAt'] != null) { await client.from('color_trap_players').update({'leftAt': null, 'isReady': false}).eq('id', existing['id']); }
      state = state.copyWith(game: game, isLoading: false); _subscribeToRealtime(gameId); await _refreshPlayers(gameId); _loadGame(gameId); return true;
    } catch (e) { debugPrint('[ColorTrap] joinGame error: $e'); state = state.copyWith(isLoading: false, error: '$e'); return false; }
  }

  Future<int> _countActivePlayers(String gameId) async { final client = _client; if (client == null) return 0; final resp = await client.from('color_trap_players').select('userId').eq('gameId', gameId).isFilter('leftAt', null); return resp.length; }

  Future<void> toggleReady(bool isReady) async {
    final gameId = _gameId; if (gameId == null) return;
    await _ref.read(temporaryRoomServiceProvider).toggleReady(gameTable: 'color_trap_games', gameId: gameId, isReady: isReady);
    final myId = _myId; if (myId != null) { final next = state.players.map((p) => p.userId == myId ? ColorTrapPlayerWire(id: p.id, gameId: p.gameId, userId: p.userId, userName: p.userName, joinedAt: p.joinedAt, isReady: isReady, leftAt: p.leftAt) : p).toList(); state = state.copyWith(players: next); }
  }

  Future<String?> startGame() async {
    final gameId = _gameId; if (gameId == null) return null;
    final active = state.players.where((p) => p.isActive).length;
    if (active < 2) return 'Color Trap needs at least 2 players';
    state = state.copyWith(isStarting: true, clearError: true);
    try {
      final client = _client; if (client == null) return null;
      final result = await client.rpc('fn_colortrap_start', params: {'p_game_id': gameId});
      final map = (result is Map<String, dynamic>) ? result : Map<String, dynamic>.from(result as Map);
      state = state.copyWith(isStarting: false);
      if (map['ok'] == true) { GameMotionTokens.celebrate(); return null; }
      return switch (map['reason']) { 'not_enough_players' => 'Needs at least 2 players', 'not_host' => 'Only the host can start', 'already_started' => null, _ => 'Could not start the game' };
    } catch (e) { debugPrint('[ColorTrap] startGame error: $e'); state = state.copyWith(isStarting: false, error: '$e'); return 'Could not start the game'; }
  }

  Future<void> movePlayer(int newRow, int newCol) async {
    final gameId = _gameId; if (gameId == null) return;
    try { final client = _client; if (client == null) return;
      await client.rpc('fn_colortrap_move', params: {'p_game_id': gameId, 'p_row': newRow, 'p_col': newCol});
    } catch (e) { debugPrint('[ColorTrap] move error: $e'); }
  }

  Future<void> advancePhase() async {
    final gameId = _gameId; if (gameId == null) return;
    try { final client = _client; if (client == null) return;
      await client.rpc('fn_colortrap_advance', params: {'p_game_id': gameId});
    } catch (e) { debugPrint('[ColorTrap] advance error: $e'); }
  }

  Future<void> leaveGame() async {
    final client = _client; final gameId = _gameId; final myId = _myId; final game = state.game;
    if (client == null || gameId == null || myId == null) { _cleanup(); return; }
    state = state.copyWith(isLeaving: true);
    try {
      if (game != null && game.isWaiting && game.hostUserId == myId) { await _ref.read(temporaryRoomServiceProvider).cancelWaitingRoom(gameTable: 'color_trap_games', gameId: gameId); }
      else if (state.amSpectator) { await client.rpc('fn_leave_spectator', params: {'p_game_table': 'color_trap_games', 'p_game_id': gameId, 'p_user_id': myId}); }
      else { await _tryRpc('fn_colortrap_leave', {'p_game_id': gameId}); }
    } catch (_) {}
    _cleanup();
  }

  Future<String?> rematch() async {
    final client = _client; final game = state.game; final myId = _myId;
    if (client == null || game == null || myId == null) return null;
    final roster = List<ColorTrapPlayerWire>.from(state.players);
    final newGameId = await createGame(maxPlayers: game.maxPlayers, difficulty: game.difficulty, roomName: game.roomName, spectatorsEnabled: game.spectatorsEnabled);
    if (newGameId == null) return null;
    try {
      final others = roster.where((p) => p.userId != myId).toList();
      if (others.isNotEmpty) {
        await client.from('color_trap_players').upsert(others.map((p) => {'gameId': newGameId, 'userId': p.userId, 'userName': p.userName}).toList(), onConflict: 'gameId,userId');
        for (final p in others) { if (p.userId.isEmpty) continue; try { await client.rpc('fn_record_room_join', params: {'p_game_table': 'color_trap_games', 'p_game_id': newGameId, 'p_family_id': familyId, 'p_user_id': p.userId, 'p_user_name': p.userName, 'p_role': 'player'}); } catch (_) {} }
      }
      final roomCode = newGameId.replaceAll('-', '').substring(0, 6).toUpperCase();
      final invites = roster.where((p) => p.userId != myId && p.userId.isNotEmpty).map((p) => {'gameTable': 'color_trap_games', 'gameId': newGameId, 'gameType': 'color-trap', 'familyId': familyId, 'roomCode': roomCode, 'invitedUserId': p.userId, 'invitedByUserId': myId, 'invitedByName': _myName, 'maxPlayers': game.maxPlayers, 'currentPlayers': 1, 'message': '$_myName wants a Color Trap rematch!', 'status': 'pending', 'sourceGameId': game.id}).toList();
      if (invites.isNotEmpty) { try { await client.from('game_invites').insert(invites); } catch (_) {} }
    } catch (e) { debugPrint('[ColorTrap] rematch error: $e'); }
    return newGameId;
  }

  Future<void> loadGame(String gameId) async { await _loadGame(gameId); await _refreshPlayers(gameId); _subscribeToRealtime(gameId); }
  Future<void> _loadGame(String gameId) async { final client = _client; if (client == null) return; try { final resp = await client.from('color_trap_games').select().eq('id', gameId).maybeSingle(); if (resp == null) return; _gameId = gameId; _applyGameRow(ColorTrapGame.fromJson(resp)); } catch (e) { debugPrint('[ColorTrap] loadGame error: $e'); } }

  void _applyGameRow(ColorTrapGame game) {
    final previous = state.game;
    state = state.copyWith(game: game);
    if (game.isInProgress && _watchdogTimer == null) { _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) { _tryRpc('fn_colortrap_tick', {'p_game_id': game.id}); }); }
    else if (!game.isInProgress && _watchdogTimer != null) { _watchdogTimer?.cancel(); _watchdogTimer = null; }
    if (game.isCompleted && (previous?.isInProgress ?? false)) { GameMotionTokens.celebrate(); _scheduleRoomCleanup(game.id); }
  }

  Future<void> _refreshPlayers(String gameId) async { final client = _client; if (client == null) return; try { final resp = await client.from('color_trap_players').select().eq('gameId', gameId).order('joinedAt', ascending: true); state = state.copyWith(players: resp.map((p) => ColorTrapPlayerWire.fromJson(p)).toList()); } catch (e) { debugPrint('[ColorTrap] refreshPlayers error: $e'); } }

  Future<bool> _tryRpc(String fn, Map<String, dynamic> params) async { final client = _client; if (client == null) return false; try { await client.rpc(fn, params: params); return true; } catch (e) { debugPrint('[ColorTrap] $fn error: $e'); return false; } }

  void _scheduleRoomCleanup(String gameId) { _cleanupTimer?.cancel(); _cleanupTimer = Timer(const Duration(seconds: 30), () { _ref.read(temporaryRoomServiceProvider).endGame(gameTable: 'color_trap_games', gameId: gameId); }); }

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe(); final client = _client; if (client == null) return;
    _channel = client.channel('colortrap_game:$gameId')
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'color_trap_games', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: gameId), callback: (payload) => _applyGameRow(ColorTrapGame.fromJson(payload.newRecord)))
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'color_trap_players', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId), callback: (payload) { final player = ColorTrapPlayerWire.fromJson(payload.newRecord); if (!state.players.any((p) => p.userId == player.userId)) state = state.copyWith(players: [...state.players, player]); })
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'color_trap_players', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId), callback: (payload) { final updated = ColorTrapPlayerWire.fromJson(payload.newRecord); state = state.copyWith(players: state.players.map((p) => p.userId == updated.userId ? updated : p).toList()); })
      .onPostgresChanges(event: PostgresChangeEvent.delete, schema: 'public', table: 'color_trap_players', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'gameId', value: gameId), callback: (payload) { final goneId = payload.oldRecord['userId'] as String?; if (goneId == null) return; state = state.copyWith(players: state.players.where((p) => p.userId != goneId).toList()); })
      .subscribe();
  }

  void _cleanup() { _channel?.unsubscribe(); _channel = null; _watchdogTimer?.cancel(); _watchdogTimer = null; _cleanupTimer?.cancel(); _cleanupTimer = null; _gameId = null; state = const ColorTrapState(); }
  @override void dispose() { _watchdogTimer?.cancel(); _cleanupTimer?.cancel(); _channel?.unsubscribe(); super.dispose(); }
}

final colorTrapProvider = StateNotifierProvider.autoDispose.family<ColorTrapNotifier, ColorTrapState, String>((ref, familyId) => ColorTrapNotifier(ref, familyId));
