// lib/features/games/code_clues/code_clues_provider.dart
//
// Code Clues — Riverpod state + Supabase Realtime orchestration.
//
// Architecture (mirrors mind_match_provider + secret_heist_provider):
//   • Supabase stores games + players tables
//   • Supabase Realtime broadcasts board state changes
//   • RLS hides the board assignments from players who shouldn't see
//     them (the field agents) — but the assignments are stored in the
//     boardState JSONB and the client gates display by role
//   • A pg_cron-driven watchdog (fn_codeclues_tick) enforces the
//     clue + guess timers

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/services/temporary_room_service.dart';
import 'code_clues_models.dart';

class CodeCluesState_ {
  const CodeCluesState_({
    this.game,
    this.players = const [],
    this.isLoading = false,
    this.isStarting = false,
    this.isLeaving = false,
    this.isSubmitting = false,
    this.error,
    this.amSpectator = false,
  });

  final CodeCluesGame? game;
  final List<CodeCluesPlayerWire> players;
  final bool isLoading;
  final bool isStarting;
  final bool isLeaving;
  final bool isSubmitting;
  final String? error;
  final bool amSpectator;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  CodeCluesPlayerWire? playerFor(String? userId) {
    if (userId == null) return null;
    for (final p in players) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  CodeCluesState_ copyWith({
    CodeCluesGame? game,
    List<CodeCluesPlayerWire>? players,
    bool? isLoading,
    bool? isStarting,
    bool? isLeaving,
    bool? isSubmitting,
    bool clearError = false,
    String? error,
    bool? amSpectator,
  }) =>
      CodeCluesState_(
        game: game ?? this.game,
        players: players ?? this.players,
        isLoading: isLoading ?? this.isLoading,
        isStarting: isStarting ?? this.isStarting,
        isLeaving: isLeaving ?? this.isLeaving,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        amSpectator: amSpectator ?? this.amSpectator,
      );
}

class CodeCluesNotifier extends StateNotifier<CodeCluesState_> {
  CodeCluesNotifier(this._ref, this.familyId)
      : super(const CodeCluesState_());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ??
      'Player';

  RealtimeChannel? _channel;
  String? _gameId;
  Timer? _watchdogTimer;
  Timer? _cleanupTimer;

  // ── Public API ───────────────────────────────────────────────────

  Future<String?> createGame({
    required int maxPlayers,
    required int clueSeconds,
    required int guessSeconds,
    String? roomName,
    bool spectatorsEnabled = true,
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // Auto-assign team 1 to host (first player).
      final body = <String, dynamic>{
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'status': 'waiting',
        'maxPlayers': maxPlayers,
        'spectatorsEnabled': spectatorsEnabled,
        'clueSeconds': clueSeconds,
        'guessSeconds': guessSeconds,
        'autoCloseDeadline':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        if (roomName != null && roomName.trim().isNotEmpty)
          'roomName': roomName.trim(),
      };
      final resp = await client
          .from('code_clues_games')
          .insert(body)
          .select()
          .single();
      final game = CodeCluesGame.fromJson(resp);
      _gameId = game.id;
      await client.from('code_clues_players').insert({
        'gameId': game.id,
        'userId': myId,
        'userName': _myName,
        'team': 1,
        'isSpymaster': false,
      });
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'code_clues_games',
        'p_game_id': game.id,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
        'p_role': 'host',
      });
      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      await _refreshPlayers(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[CodeClues] createGame error: $e');
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
      final gameResp = await client
          .from('code_clues_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (gameResp == null) {
        state = state.copyWith(isLoading: false, error: 'Game not found');
        return false;
      }
      final game = CodeCluesGame.fromJson(gameResp);
      _gameId = gameId;
      if (game.isInProgress || game.isCompleted) {
        await client.rpc('fn_join_spectator', params: {
          'p_game_table': 'code_clues_games',
          'p_game_id': gameId,
          'p_user_id': myId,
          'p_user_name': _myName,
        });
        state = state.copyWith(
            game: game, isLoading: false, amSpectator: true);
        _subscribeToRealtime(gameId);
        await _refreshPlayers(gameId);
        return true;
      }
      final existing = await client
          .from('code_clues_players')
          .select()
          .eq('gameId', gameId)
          .eq('userId', myId)
          .maybeSingle();
      if (existing == null) {
        final activeCount = await _countActivePlayers(gameId);
        if (activeCount >= game.maxPlayers) {
          state = state.copyWith(isLoading: false, error: 'Room is full');
          return false;
        }
        // Auto-assign team: pick the smaller team.
        final team = await _pickSmallerTeam(gameId);
        await client.from('code_clues_players').insert({
          'gameId': gameId,
          'userId': myId,
          'userName': _myName,
          'team': team,
          'isSpymaster': false,
        });
        await client.rpc('fn_record_room_join', params: {
          'p_game_table': 'code_clues_games',
          'p_game_id': gameId,
          'p_family_id': familyId,
          'p_user_id': myId,
          'p_user_name': _myName,
          'p_role': 'player',
        });
      } else if (existing['leftAt'] != null) {
        await client.from('code_clues_players').update(
            {'leftAt': null, 'isReady': false}).eq('id', existing['id']);
      }
      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshPlayers(gameId);
      _loadGame(gameId);
      return true;
    } catch (e) {
      debugPrint('[CodeClues] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  Future<int> _countActivePlayers(String gameId) async {
    final client = _client;
    if (client == null) return 0;
    final resp = await client
        .from('code_clues_players')
        .select('userId')
        .eq('gameId', gameId)
        .isFilter('leftAt', null);
    return resp.length;
  }

  /// Pick the team with fewer active players; tie → team 1.
  Future<int> _pickSmallerTeam(String gameId) async {
    final client = _client;
    if (client == null) return 1;
    try {
      final resp = await client
          .from('code_clues_players')
          .select('team')
          .eq('gameId', gameId)
          .isFilter('leftAt', null);
      int t1 = 0, t2 = 0;
      for (final row in resp) {
        final t = (row['team'] as num?)?.toInt() ?? 1;
        if (t == 1) {
          t1++;
        } else {
          t2++;
        }
      }
      return t2 < t1 ? 2 : 1;
    } catch (_) {
      return 1;
    }
  }

  /// Update this player's team (1 or 2). Host-only enforced server-side
  /// via RLS (players can update only their own row).
  Future<void> setTeam(int team) async {
    final client = _client;
    final myId = _myId;
    final gameId = _gameId;
    if (client == null || myId == null || gameId == null) return;
    if (team != 1 && team != 2) return;
    state = state.copyWith(clearError: true);
    try {
      await client
          .from('code_clues_players')
          .update({'team': team}).eq('gameId', gameId).eq('userId', myId);
      // Optimistic local update.
      final next = state.players
          .map((p) => p.userId == myId ? p.copyWith(team: team) : p)
          .toList();
      state = state.copyWith(players: next);
      GameMotionTokens.tap();
    } catch (e) {
      debugPrint('[CodeClues] setTeam error: $e');
      state = state.copyWith(error: '$e');
    }
  }

  /// Toggle this player's spymaster flag for their current team.
  Future<void> toggleSpymaster() async {
    final client = _client;
    final myId = _myId;
    final gameId = _gameId;
    if (client == null || myId == null || gameId == null) return;
    final me = state.playerFor(myId);
    if (me == null) return;
    final next = !me.isSpymaster;
    state = state.copyWith(clearError: true);
    try {
      // If becoming spymaster, clear any existing spymaster on same team.
      if (next) {
        final sameTeamSpymaster = state.players.firstWhere(
          (p) =>
              p.userId != myId &&
              p.team == me.team &&
              p.isSpymaster &&
              p.isActive,
          orElse: () => me,
        );
        if (sameTeamSpymaster.userId != me.userId) {
          await client.from('code_clues_players').update(
              {'isSpymaster': false}).eq('id', sameTeamSpymaster.id);
        }
      }
      await client
          .from('code_clues_players')
          .update({'isSpymaster': next}).eq('id', me.id);
      final updated =
          state.players
              .map((p) {
                if (p.userId == me.userId) {
                  return p.copyWith(isSpymaster: next);
                }
                if (next && p.team == me.team && p.isSpymaster) {
                  return p.copyWith(isSpymaster: false);
                }
                return p;
              })
              .toList();
      state = state.copyWith(players: updated);
      GameMotionTokens.tap();
    } catch (e) {
      debugPrint('[CodeClues] toggleSpymaster error: $e');
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> toggleReady(bool isReady) async {
    final gameId = _gameId;
    if (gameId == null) return;
    await _ref.read(temporaryRoomServiceProvider).toggleReady(
          gameTable: 'code_clues_games',
          gameId: gameId,
          isReady: isReady,
        );
    // The shared service no-ops for tables not in kGamePlayerTableMap, so
    // also write directly to the players table for Code Clues.
    final client = _client;
    final myId = _myId;
    if (client != null && myId != null) {
      try {
        await client
            .from('code_clues_players')
            .update({'isReady': isReady})
            .eq('gameId', gameId)
            .eq('userId', myId);
      } catch (e) {
        debugPrint('[CodeClues] toggleReady direct write error: $e');
      }
    }
    if (myId != null) {
      final next = state.players
          .map((p) => p.userId == myId ? p.copyWith(isReady: isReady) : p)
          .toList();
      state = state.copyWith(players: next);
    }
  }

  Future<String?> startGame() async {
    final gameId = _gameId;
    if (gameId == null) return null;
    final active = state.players.where((p) => p.isActive).length;
    if (active < kCodeCluesMinPlayers) {
      return 'Code Clues needs at least $kCodeCluesMinPlayers players';
    }
    // Ensure each team has at least 2 players and a spymaster.
    final t1 = state.players
        .where((p) => p.isActive && p.team == 1)
        .toList();
    final t2 = state.players
        .where((p) => p.isActive && p.team == 2)
        .toList();
    if (t1.length < 2 || t2.length < 2) {
      return 'Each team needs at least 2 players';
    }
    if (!t1.any((p) => p.isSpymaster) || !t2.any((p) => p.isSpymaster)) {
      return 'Each team needs a Spymaster';
    }
    state = state.copyWith(isStarting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return null;
      final result = await client.rpc('fn_codeclues_start',
          params: {'p_game_id': gameId});
      final map = (result is Map<String, dynamic>)
          ? result
          : Map<String, dynamic>.from(result as Map);
      state = state.copyWith(isStarting: false);
      if (map['ok'] == true) {
        GameMotionTokens.celebrate();
        return null;
      }
      return switch (map['reason']) {
        'not_enough_players' =>
          'Needs at least $kCodeCluesMinPlayers players',
        'not_host' => 'Only the host can start',
        'already_started' => null,
        'not_enough_words' => 'Word pool is empty',
        _ => 'Could not start the game',
      };
    } catch (e) {
      debugPrint('[CodeClues] startGame error: $e');
      state = state.copyWith(isStarting: false, error: '$e');
      return 'Could not start the game';
    }
  }

  /// Spymaster of the current turn team submits a clue + number.
  Future<void> giveClue(String clue, int number) async {
    final gameId = _gameId;
    if (gameId == null) return;
    final clueError = CodeCluesEngine.validateClue(clue);
    if (clueError != null) {
      state = state.copyWith(error: clueError);
      return;
    }
    final numError = CodeCluesEngine.validateClueNumber(number);
    if (numError != null) {
      state = state.copyWith(error: numError);
      return;
    }
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_codeclues_give_clue', params: {
        'p_game_id': gameId,
        'p_clue': clue.trim(),
        'p_number': number,
      });
      GameMotionTokens.tap();
    } catch (e) {
      debugPrint('[CodeClues] giveClue error: $e');
      state = state.copyWith(error: '$e');
    } finally {
      state = state.copyWith(isSubmitting: false);
    }
  }

  /// Field agent of the current turn team guesses a word.
  Future<void> guess(int wordIndex) async {
    final gameId = _gameId;
    if (gameId == null) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_codeclues_guess', params: {
        'p_game_id': gameId,
        'p_word_index': wordIndex,
      });
      GameMotionTokens.tap();
    } catch (e) {
      debugPrint('[CodeClues] guess error: $e');
      state = state.copyWith(error: '$e');
    } finally {
      state = state.copyWith(isSubmitting: false);
    }
  }

  /// End the current team's turn early (give up remaining guesses).
  Future<void> passTurn() async {
    final gameId = _gameId;
    if (gameId == null) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_codeclues_pass', params: {
        'p_game_id': gameId,
      });
      GameMotionTokens.tap();
    } catch (e) {
      debugPrint('[CodeClues] passTurn error: $e');
      state = state.copyWith(error: '$e');
    } finally {
      state = state.copyWith(isSubmitting: false);
    }
  }

  Future<void> leaveGame() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final game = state.game;
    if (client == null || gameId == null || myId == null) {
      _cleanup();
      return;
    }
    state = state.copyWith(isLeaving: true);
    try {
      if (game != null && game.isWaiting && game.hostUserId == myId) {
        await _ref
            .read(temporaryRoomServiceProvider)
            .cancelWaitingRoom(
              gameTable: 'code_clues_games',
              gameId: gameId,
            );
      } else if (state.amSpectator) {
        await client.rpc('fn_leave_spectator', params: {
          'p_game_table': 'code_clues_games',
          'p_game_id': gameId,
          'p_user_id': myId,
        });
      } else {
        await _tryRpc('fn_codeclues_leave', {'p_game_id': gameId});
      }
    } catch (_) {}
    _cleanup();
  }

  Future<String?> rematch() async {
    final client = _client;
    final game = state.game;
    final myId = _myId;
    if (client == null || game == null || myId == null) return null;
    final roster = List<CodeCluesPlayerWire>.from(state.players);
    final newGameId = await createGame(
      maxPlayers: game.maxPlayers,
      clueSeconds: game.clueSeconds,
      guessSeconds: game.guessSeconds,
      roomName: game.roomName,
      spectatorsEnabled: game.spectatorsEnabled,
    );
    if (newGameId == null) return null;
    try {
      final others = roster.where((p) => p.userId != myId).toList();
      if (others.isNotEmpty) {
        await client.from('code_clues_players').upsert(
          others
              .map((p) => {
                    'gameId': newGameId,
                    'userId': p.userId,
                    'userName': p.userName,
                    'team': p.team,
                    'isSpymaster': p.isSpymaster,
                  })
              .toList(),
          onConflict: 'gameId,userId',
        );
        for (final p in others) {
          if (p.userId.isEmpty) continue;
          try {
            await client.rpc('fn_record_room_join', params: {
              'p_game_table': 'code_clues_games',
              'p_game_id': newGameId,
              'p_family_id': familyId,
              'p_user_id': p.userId,
              'p_user_name': p.userName,
              'p_role': 'player',
            });
          } catch (_) {}
        }
      }
      final roomCode =
          newGameId.replaceAll('-', '').substring(0, 6).toUpperCase();
      final invites = roster
          .where((p) => p.userId != myId && p.userId.isNotEmpty)
          .map((p) => {
                'gameTable': 'code_clues_games',
                'gameId': newGameId,
                'gameType': 'code-clues',
                'familyId': familyId,
                'roomCode': roomCode,
                'invitedUserId': p.userId,
                'invitedByUserId': myId,
                'invitedByName': _myName,
                'maxPlayers': game.maxPlayers,
                'currentPlayers': 1,
                'message': '$_myName wants a Code Clues rematch!',
                'status': 'pending',
                'sourceGameId': game.id,
              })
          .toList();
      if (invites.isNotEmpty) {
        try {
          await client.from('game_invites').insert(invites);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[CodeClues] rematch error: $e');
    }
    return newGameId;
  }

  Future<void> loadGame(String gameId) async {
    await _loadGame(gameId);
    await _refreshPlayers(gameId);
    _subscribeToRealtime(gameId);
  }

  Future<void> _loadGame(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('code_clues_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (resp == null) return;
      _gameId = gameId;
      _applyGameRow(CodeCluesGame.fromJson(resp));
    } catch (e) {
      debugPrint('[CodeClues] loadGame error: $e');
    }
  }

  void _applyGameRow(CodeCluesGame game) {
    final previous = state.game;
    state = state.copyWith(game: game);
    if (game.isInProgress && _watchdogTimer == null) {
      _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _tryRpc('fn_codeclues_tick', {'p_game_id': game.id});
      });
    } else if (!game.isInProgress && _watchdogTimer != null) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
    }
    if (game.isCompleted && (previous?.isInProgress ?? false)) {
      GameMotionTokens.celebrate();
      _scheduleRoomCleanup(game.id);
    }
  }

  Future<void> _refreshPlayers(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('code_clues_players')
          .select()
          .eq('gameId', gameId)
          .order('joinedAt', ascending: true);
      state = state.copyWith(
          players: resp
              .map((p) => CodeCluesPlayerWire.fromJson(p))
              .toList());
    } catch (e) {
      debugPrint('[CodeClues] refreshPlayers error: $e');
    }
  }

  Future<bool> _tryRpc(String fn, Map<String, dynamic> params) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.rpc(fn, params: params);
      return true;
    } catch (e) {
      debugPrint('[CodeClues] $fn error: $e');
      return false;
    }
  }

  void _scheduleRoomCleanup(String gameId) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'code_clues_games',
            gameId: gameId,
          );
    });
  }

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;
    _channel = client
        .channel('codeclues_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'code_clues_games',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: gameId),
          callback: (payload) =>
              _applyGameRow(CodeCluesGame.fromJson(payload.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'code_clues_players',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'gameId',
              value: gameId),
          callback: (payload) {
            final player = CodeCluesPlayerWire.fromJson(payload.newRecord);
            if (!state.players.any((p) => p.userId == player.userId)) {
              state = state.copyWith(players: [...state.players, player]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'code_clues_players',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'gameId',
              value: gameId),
          callback: (payload) {
            final updated = CodeCluesPlayerWire.fromJson(payload.newRecord);
            state = state.copyWith(
                players: state.players
                    .map((p) => p.userId == updated.userId ? updated : p)
                    .toList());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'code_clues_players',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'gameId',
              value: gameId),
          callback: (payload) {
            final goneId = payload.oldRecord['userId'] as String?;
            if (goneId == null) return;
            state = state.copyWith(
                players: state.players
                    .where((p) => p.userId != goneId)
                    .toList());
          },
        )
        .subscribe();
  }

  void _cleanup() {
    _channel?.unsubscribe();
    _channel = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _gameId = null;
    state = const CodeCluesState_();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _cleanupTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}

final codeCluesProvider = StateNotifierProvider.autoDispose
    .family<CodeCluesNotifier, CodeCluesState_, String>(
        (ref, familyId) => CodeCluesNotifier(ref, familyId));
