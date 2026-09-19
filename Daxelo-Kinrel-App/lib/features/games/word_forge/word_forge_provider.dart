// lib/features/games/word_forge/word_forge_provider.dart
//
// Word Forge — Riverpod state + Supabase Realtime orchestration.
//
// Architecture (mirrors mind_match_provider + secret_heist_provider):
//   • Supabase stores games + players + (hidden) definitions + (hidden) votes
//   • Supabase Realtime broadcasts board state changes
//   • RLS on word_forge_definitions hides other players' definitions until
//     the resolve RPC publishes them into boardState.definitions
//   • RLS on word_forge_votes hides other players' votes until the resolve
//     RPC publishes them into boardState.rounds[].pointsAwarded
//   • A pg_cron-driven watchdog enforces the writing/voting timer

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/services/temporary_room_service.dart';
import 'word_forge_engine.dart';
import 'word_forge_models.dart';

class WordForgeState_ {
  const WordForgeState_({
    this.game,
    this.players = const [],
    this.myDefinition,
    this.myVote,
    this.isLoading = false,
    this.isStarting = false,
    this.isLeaving = false,
    this.isSubmitting = false,
    this.error,
    this.amSpectator = false,
  });

  final WordForgeGame? game;
  final List<WordForgePlayerWire> players;
  final WordForgeDefinitionWire? myDefinition;
  final WordForgeVoteWire? myVote;
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

  WordForgePlayerWire? playerFor(String? userId) {
    if (userId == null) return null;
    for (final p in players) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  WordForgeState_ copyWith({
    WordForgeGame? game,
    List<WordForgePlayerWire>? players,
    WordForgeDefinitionWire? myDefinition,
    bool clearMyDefinition = false,
    WordForgeVoteWire? myVote,
    bool clearMyVote = false,
    bool? isLoading,
    bool? isStarting,
    bool? isLeaving,
    bool? isSubmitting,
    bool clearError = false,
    String? error,
    bool? amSpectator,
  }) =>
      WordForgeState_(
        game: game ?? this.game,
        players: players ?? this.players,
        myDefinition: clearMyDefinition
            ? null
            : (myDefinition ?? this.myDefinition),
        myVote: clearMyVote ? null : (myVote ?? this.myVote),
        isLoading: isLoading ?? this.isLoading,
        isStarting: isStarting ?? this.isStarting,
        isLeaving: isLeaving ?? this.isLeaving,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        amSpectator: amSpectator ?? this.amSpectator,
      );
}

class WordForgeNotifier extends StateNotifier<WordForgeState_> {
  WordForgeNotifier(this._ref, this.familyId)
      : super(const WordForgeState_());

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
    required int totalRounds,
    required int answerSeconds,
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
      final body = <String, dynamic>{
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'status': 'waiting',
        'maxPlayers': maxPlayers,
        'spectatorsEnabled': spectatorsEnabled,
        'totalRounds': totalRounds,
        'answerSeconds': answerSeconds,
        'autoCloseDeadline':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        if (roomName != null && roomName.trim().isNotEmpty)
          'roomName': roomName.trim(),
      };
      final resp = await client
          .from('word_forge_games')
          .insert(body)
          .select()
          .single();
      final game = WordForgeGame.fromJson(resp);
      _gameId = game.id;
      await client.from('word_forge_players').insert({
        'gameId': game.id,
        'userId': myId,
        'userName': _myName,
      });
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'word_forge_games',
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
      debugPrint('[WordForge] createGame error: $e');
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
          .from('word_forge_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (gameResp == null) {
        state = state.copyWith(isLoading: false, error: 'Game not found');
        return false;
      }
      final game = WordForgeGame.fromJson(gameResp);
      _gameId = gameId;
      if (game.isInProgress || game.isCompleted) {
        await client.rpc('fn_join_spectator', params: {
          'p_game_table': 'word_forge_games',
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
          .from('word_forge_players')
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
        await client.from('word_forge_players').insert({
          'gameId': gameId,
          'userId': myId,
          'userName': _myName,
        });
        await client.rpc('fn_record_room_join', params: {
          'p_game_table': 'word_forge_games',
          'p_game_id': gameId,
          'p_family_id': familyId,
          'p_user_id': myId,
          'p_user_name': _myName,
          'p_role': 'player',
        });
      } else if (existing['leftAt'] != null) {
        await client
            .from('word_forge_players')
            .update({'leftAt': null, 'isReady': false}).eq('id', existing['id']);
      }
      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshPlayers(gameId);
      _loadGame(gameId);
      return true;
    } catch (e) {
      debugPrint('[WordForge] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  Future<int> _countActivePlayers(String gameId) async {
    final client = _client;
    if (client == null) return 0;
    final resp = await client
        .from('word_forge_players')
        .select('userId')
        .eq('gameId', gameId)
        .isFilter('leftAt', null);
    return resp.length;
  }

  Future<void> toggleReady(bool isReady) async {
    final gameId = _gameId;
    if (gameId == null) return;
    await _ref.read(temporaryRoomServiceProvider).toggleReady(
          gameTable: 'word_forge_games',
          gameId: gameId,
          isReady: isReady,
        );
    final myId = _myId;
    if (myId != null) {
      final next = state.players
          .map((p) => p.userId == myId
              ? WordForgePlayerWire(
                  id: p.id,
                  gameId: p.gameId,
                  userId: p.userId,
                  userName: p.userName,
                  joinedAt: p.joinedAt,
                  isReady: isReady,
                  leftAt: p.leftAt,
                )
              : p)
          .toList();
      state = state.copyWith(players: next);
    }
  }

  Future<String?> startGame() async {
    final gameId = _gameId;
    if (gameId == null) return null;
    final active = state.players.where((p) => p.isActive).length;
    if (active < kWordForgeMinPlayers) {
      return 'Word Forge needs at least $kWordForgeMinPlayers players';
    }
    state = state.copyWith(isStarting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return null;
      final result = await client.rpc('fn_wordforge_start',
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
          'Needs at least $kWordForgeMinPlayers players',
        'not_host' => 'Only the host can start',
        'already_started' => null,
        'no_words_available' => 'No words available',
        _ => 'Could not start the game',
      };
    } catch (e) {
      debugPrint('[WordForge] startGame error: $e');
      state = state.copyWith(isStarting: false, error: '$e');
      return 'Could not start the game';
    }
  }

  /// Submit (or update) the player's fake definition for the current round.
  Future<void> submitDefinition(String definition) async {
    final gameId = _gameId;
    if (gameId == null) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_wordforge_submit_definition', params: {
        'p_game_id': gameId,
        'p_definition': definition,
      });
      await _refreshMyDefinition(gameId);
      GameMotionTokens.tap();
    } catch (e) {
      debugPrint('[WordForge] submitDefinition error: $e');
      state = state.copyWith(error: '$e');
    } finally {
      state = state.copyWith(isSubmitting: false);
    }
  }

  /// Vote for which definition the player thinks is real.
  /// `targetUserId` is the userId whose definition you're voting for.
  /// Pass empty string to vote for the real definition.
  Future<void> vote(String targetUserId) async {
    final gameId = _gameId;
    if (gameId == null) return;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_wordforge_vote', params: {
        'p_game_id': gameId,
        'p_voted_for_user_id': targetUserId,
      });
      await _refreshMyVote(gameId);
      GameMotionTokens.tap();
    } catch (e) {
      debugPrint('[WordForge] vote error: $e');
      state = state.copyWith(error: '$e');
    } finally {
      state = state.copyWith(isSubmitting: false);
    }
  }

  /// Advance phase — used by the "Reveal" / "See Results" / "Next Round" button.
  Future<void> advancePhase() async {
    final gameId = _gameId;
    if (gameId == null) return;
    try {
      final client = _client;
      if (client == null) return;
      await client.rpc('fn_wordforge_advance',
          params: {'p_game_id': gameId});
    } catch (e) {
      debugPrint('[WordForge] advance error: $e');
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
              gameTable: 'word_forge_games',
              gameId: gameId,
            );
      } else if (state.amSpectator) {
        await client.rpc('fn_leave_spectator', params: {
          'p_game_table': 'word_forge_games',
          'p_game_id': gameId,
          'p_user_id': myId,
        });
      } else {
        await _tryRpc('fn_wordforge_leave', {'p_game_id': gameId});
      }
    } catch (_) {}
    _cleanup();
  }

  Future<String?> rematch() async {
    final client = _client;
    final game = state.game;
    final myId = _myId;
    if (client == null || game == null || myId == null) return null;
    final roster = List<WordForgePlayerWire>.from(state.players);
    final newGameId = await createGame(
      maxPlayers: game.maxPlayers,
      totalRounds: game.totalRounds,
      answerSeconds: game.answerSeconds,
      roomName: game.roomName,
      spectatorsEnabled: game.spectatorsEnabled,
    );
    if (newGameId == null) return null;
    try {
      final others = roster.where((p) => p.userId != myId).toList();
      if (others.isNotEmpty) {
        await client.from('word_forge_players').upsert(
          others
              .map((p) => {
                    'gameId': newGameId,
                    'userId': p.userId,
                    'userName': p.userName,
                  })
              .toList(),
          onConflict: 'gameId,userId',
        );
        for (final p in others) {
          if (p.userId.isEmpty) continue;
          try {
            await client.rpc('fn_record_room_join', params: {
              'p_game_table': 'word_forge_games',
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
                'gameTable': 'word_forge_games',
                'gameId': newGameId,
                'gameType': 'word-forge',
                'familyId': familyId,
                'roomCode': roomCode,
                'invitedUserId': p.userId,
                'invitedByUserId': myId,
                'invitedByName': _myName,
                'maxPlayers': game.maxPlayers,
                'currentPlayers': 1,
                'message': '$_myName wants a Word Forge rematch!',
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
      debugPrint('[WordForge] rematch error: $e');
    }
    return newGameId;
  }

  Future<void> loadGame(String gameId) async {
    await _loadGame(gameId);
    await _refreshPlayers(gameId);
    await _refreshMyDefinition(gameId);
    await _refreshMyVote(gameId);
    _subscribeToRealtime(gameId);
  }

  Future<void> _loadGame(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('word_forge_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (resp == null) return;
      _gameId = gameId;
      _applyGameRow(WordForgeGame.fromJson(resp));
    } catch (e) {
      debugPrint('[WordForge] loadGame error: $e');
    }
  }

  void _applyGameRow(WordForgeGame game) {
    final previous = state.game;
    state = state.copyWith(game: game);
    if (game.isInProgress && _watchdogTimer == null) {
      _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _tryRpc('fn_wordforge_tick', {'p_game_id': game.id});
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
          .from('word_forge_players')
          .select()
          .eq('gameId', gameId)
          .order('joinedAt', ascending: true);
      state = state.copyWith(
          players: resp
              .map((p) => WordForgePlayerWire.fromJson(p))
              .toList());
    } catch (e) {
      debugPrint('[WordForge] refreshPlayers error: $e');
    }
  }

  Future<void> _refreshMyDefinition(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    try {
      final board = state.game?.boardState;
      final round = board?.currentRoundNumber ?? 1;
      final resp = await client
          .from('word_forge_definitions')
          .select()
          .eq('gameId', gameId)
          .eq('userId', myId)
          .eq('roundNumber', round)
          .order('submittedAt', ascending: false)
          .limit(1)
          .maybeSingle();
      if (resp == null) {
        state = state.copyWith(clearMyDefinition: true);
      } else {
        state = state.copyWith(
            myDefinition:
                WordForgeDefinitionWire.fromJson(resp));
      }
    } catch (e) {
      debugPrint('[WordForge] refreshMyDefinition error: $e');
    }
  }

  Future<void> _refreshMyVote(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    try {
      final board = state.game?.boardState;
      final round = board?.currentRoundNumber ?? 1;
      final resp = await client
          .from('word_forge_votes')
          .select()
          .eq('gameId', gameId)
          .eq('voterUserId', myId)
          .eq('roundNumber', round)
          .maybeSingle();
      if (resp == null) {
        state = state.copyWith(clearMyVote: true);
      } else {
        state = state.copyWith(
            myVote: WordForgeVoteWire.fromJson(resp));
      }
    } catch (e) {
      debugPrint('[WordForge] refreshMyVote error: $e');
    }
  }

  Future<bool> _tryRpc(String fn, Map<String, dynamic> params) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.rpc(fn, params: params);
      return true;
    } catch (e) {
      debugPrint('[WordForge] $fn error: $e');
      return false;
    }
  }

  void _scheduleRoomCleanup(String gameId) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'word_forge_games',
            gameId: gameId,
          );
    });
  }

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;
    _channel = client
        .channel('wordforge_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'word_forge_games',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: gameId),
          callback: (payload) =>
              _applyGameRow(WordForgeGame.fromJson(payload.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'word_forge_players',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'gameId',
              value: gameId),
          callback: (payload) {
            final player = WordForgePlayerWire.fromJson(payload.newRecord);
            if (!state.players.any((p) => p.userId == player.userId)) {
              state = state.copyWith(players: [...state.players, player]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'word_forge_players',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'gameId',
              value: gameId),
          callback: (payload) {
            final updated = WordForgePlayerWire.fromJson(payload.newRecord);
            state = state.copyWith(
                players: state.players
                    .map((p) => p.userId == updated.userId ? updated : p)
                    .toList());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'word_forge_players',
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
        // My own definition row changes (RLS lets me see only my own row).
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'word_forge_definitions',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'userId',
              value: _myId ?? ''),
          callback: (payload) {
            state = state.copyWith(
                myDefinition:
                    WordForgeDefinitionWire.fromJson(payload.newRecord));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'word_forge_definitions',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'userId',
              value: _myId ?? ''),
          callback: (payload) {
            state = state.copyWith(
                myDefinition:
                    WordForgeDefinitionWire.fromJson(payload.newRecord));
          },
        )
        // My own vote row changes (RLS lets me see only my own row).
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'word_forge_votes',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'voterUserId',
              value: _myId ?? ''),
          callback: (payload) {
            state = state.copyWith(
                myVote: WordForgeVoteWire.fromJson(payload.newRecord));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'word_forge_votes',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'voterUserId',
              value: _myId ?? ''),
          callback: (payload) {
            state = state.copyWith(
                myVote: WordForgeVoteWire.fromJson(payload.newRecord));
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
    state = const WordForgeState_();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _cleanupTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}

final wordForgeProvider = StateNotifierProvider.autoDispose
    .family<WordForgeNotifier, WordForgeState_, String>(
        (ref, familyId) => WordForgeNotifier(ref, familyId));
