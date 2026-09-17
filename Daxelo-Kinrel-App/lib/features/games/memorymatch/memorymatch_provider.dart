// lib/features/games/memorymatch/memorymatch_provider.dart
//
// Memory Match — Riverpod state + Supabase Realtime + server-authoritative
// card flips.
//
// Architecture:
//   • Supabase stores the game row (deck, owners, scores, turn, reveal
//     window) and the player roster. Every mutation goes through RPCs:
//       – fn_memorymatch_flip    — the ONLY way a card flips. Validates the
//                                   caller IS the current player, the turn is
//                                   live, and the card is flippable. Evaluates
//                                   pairs server-side.
//       – fn_memorymatch_advance — applies the reveal outcome after the timed
//                                   window and passes turns on timeout.
//       – fn_memorymatch_tick    — 2 s watchdog every client runs (also
//                                   refreshes the caller's heartbeat so the
//                                   shared reaper never kills a live room).
//   • Clients render from the realtime game row; the flipper additionally
//     optimistically flips its own card for <100 ms perceived latency and
//     reconciles when the authoritative row arrives.
//   • The current player's client schedules a precise advance at
//     revealEndsAt; everyone's 2 s tick is the backstop.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import '../shared/services/temporary_room_service.dart';
import 'memorymatch_models.dart';

class MemoryMatchState {
  const MemoryMatchState({
    this.game,
    this.players = const [],
    this.isLoading = false,
    this.isStarting = false,
    this.isLeaving = false,
    this.error,
    this.amSpectator = false,
    this.optimisticFlips = const [],
  });

  final MemoryMatchGame? game;
  final List<MemoryMatchPlayer> players;
  final bool isLoading;
  final bool isStarting;
  final bool isLeaving;
  final String? error;
  final bool amSpectator;

  /// Card indices the local player just tapped (instant flip feedback).
  /// Reconciled away as soon as the authoritative row covers them.
  final List<int> optimisticFlips;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;

  MemoryMatchPlayer? playerFor(String? userId) {
    if (userId == null) return null;
    for (final p in players) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  /// The cards that should render face-up right now: authoritative flips +
  /// matched owners + optimistic local taps.
  bool isFaceUp(MemoryMatchCard card) =>
      card.isMatched ||
      game?.flippedCardIds.contains(card.index) == true ||
      optimisticFlips.contains(card.index);

  bool get canFlip {
    final g = game;
    if (g == null || !g.isInProgress || g.isReveal || amSpectator) return false;
    return true;
  }

  MemoryMatchState copyWith({
    MemoryMatchGame? game,
    List<MemoryMatchPlayer>? players,
    bool? isLoading,
    bool? isStarting,
    bool? isLeaving,
    bool clearError = false,
    String? error,
    bool? amSpectator,
    List<int>? optimisticFlips,
  }) =>
      MemoryMatchState(
        game: game ?? this.game,
        players: players ?? this.players,
        isLoading: isLoading ?? this.isLoading,
        isStarting: isStarting ?? this.isStarting,
        isLeaving: isLeaving ?? this.isLeaving,
        error: clearError ? null : (error ?? this.error),
        amSpectator: amSpectator ?? this.amSpectator,
        optimisticFlips: optimisticFlips ?? this.optimisticFlips,
      );
}

class MemoryMatchNotifier extends StateNotifier<MemoryMatchState> {
  MemoryMatchNotifier(this._ref, this.familyId)
      : super(const MemoryMatchState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  String? _gameId;
  Timer? _watchdogTimer;
  Timer? _cleanupTimer;
  Timer? _revealTimer;

  bool _advanceInFlight = false;

  // ── Public API ───────────────────────────────────────────────────

  /// Host: create a new room with the chosen settings.
  Future<String?> createGame({
    required MemoryMatchDifficulty difficulty,
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
        'difficulty': difficulty.wire,
        'maxPlayers': 4,
        'spectatorsEnabled': spectatorsEnabled,
        'autoCloseDeadline':
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
        if (roomName != null && roomName.trim().isNotEmpty)
          'roomName': roomName.trim(),
      };
      final resp =
          await client.from('memorymatch_games').insert(body).select().single();
      final game = MemoryMatchGame.fromJson(resp);
      _gameId = game.id;

      await client.from('memorymatch_players').insert({
        'gameId': game.id,
        'userId': myId,
        'userName': _myName,
      });

      // Register in the shared room bookkeeping so the ecosystem archive
      // sees this participant (same path RoomController uses).
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'memorymatch_games',
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
      debugPrint('[MemoryMatch] createGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  /// Join an existing room. Falls back to spectating once the match is
  /// already running (spectator mode is part of the game's design).
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
          .from('memorymatch_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (isRoomRowClosed(gameResp)) {
        state = state.copyWith(isLoading: false, error: kRoomClosedMessage);
        return false;
      }
      final game =
          MemoryMatchGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      final playersResp = await client
          .from('memorymatch_players')
          .select()
          .eq('gameId', gameId)
          .order('joinedAt', ascending: true);
      final existing =
          playersResp.map((p) => MemoryMatchPlayer.fromJson(p)).toList();
      final alreadyJoined = existing.any((p) => p.userId == myId);

      if (!alreadyJoined && game.isWaiting) {
        if (existing.where((p) => p.isActive).length >= game.maxPlayers) {
          state = state.copyWith(isLoading: false, error: 'Game is full');
          return false;
        }
        await client.from('memorymatch_players').upsert({
          'gameId': gameId,
          'userId': myId,
          'userName': _myName,
        }, onConflict: 'gameId,userId');
        await client.rpc('fn_record_room_join', params: {
          'p_game_table': 'memorymatch_games',
          'p_game_id': gameId,
          'p_family_id': familyId,
          'p_user_id': myId,
          'p_user_name': _myName,
          'p_role': 'player',
        });
        await _ref.read(temporaryRoomServiceProvider).touchActivity(
              gameTable: 'memorymatch_games',
              gameId: gameId,
            );
      } else if (!alreadyJoined) {
        // Match already running — watch from the sidelines.
        await _spectate(gameId);
      }

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshPlayers(gameId);
      unawaited(
        syncGameInviteChatCards(
          client: client,
          gameId: gameId,
          currentPlayers: state.players.length,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[MemoryMatch] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  /// Spectate a room (read-only + emoji reactions).
  Future<void> spectate(String gameId) async {
    await _spectate(gameId);
    await _loadGame(gameId);
    await _refreshPlayers(gameId);
    _subscribeToRealtime(gameId);
  }

  Future<void> _spectate(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    _gameId = gameId;
    state = state.copyWith(amSpectator: true);
    try {
      await client.rpc('fn_spectate_game', params: {
        'p_game_table': 'memorymatch_games',
        'p_game_id': gameId,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
      });
    } catch (e) {
      debugPrint('[MemoryMatch] spectate error: $e');
    }
  }

  /// Toggle the ready flag in the waiting lobby.
  Future<void> toggleReady(bool isReady) async {
    final gameId = _gameId;
    if (gameId == null) return;
    await _ref.read(temporaryRoomServiceProvider).toggleReady(
          gameTable: 'memorymatch_games',
          gameId: gameId,
          isReady: isReady,
        );
    final myId = _myId;
    if (myId != null) {
      final next = state.players
          .map((p) => p.userId == myId
              ? MemoryMatchPlayer(
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

  /// Host: start the match. The RPC validates 2–4 players and deals the
  /// deck (auto difficulty scales with the player count).
  Future<String?> startGame() async {
    final gameId = _gameId;
    if (gameId == null) return null;
    final active =
        state.players.where((p) => p.isActive).length;
    if (active < 2) return 'Memory Match needs at least 2 players';
    state = state.copyWith(isStarting: true, clearError: true);
    try {
      final client = _client;
      if (client == null) return null;
      final result =
          await client.rpc('fn_memorymatch_start', params: {
        'p_game_id': gameId,
      });
      final map = (result is Map<String, dynamic>)
          ? result
          : Map<String, dynamic>.from(result as Map);
      state = state.copyWith(isStarting: false);
      if (map['ok'] == true) {
        GameMotionTokens.celebrate();
        return null;
      }
      return switch (map['reason']) {
        'not_enough_players' => 'Memory Match needs at least 2 players',
        'too_many_players' => 'Memory Match supports up to 4 players',
        'not_host' => 'Only the host can start',
        'already_started' => null,
        _ => 'Could not start the game',
      };
    } catch (e) {
      debugPrint('[MemoryMatch] startGame error: $e');
      state = state.copyWith(isStarting: false, error: '$e');
      return 'Could not start the game';
    }
  }

  /// The ONLY client action during play: flip a card. Server-authoritative;
  /// the optimistic flip gives instant feedback and is reconciled when the
  /// realtime row arrives.
  Future<void> flipCard(int cardIndex) async {
    final gameId = _gameId;
    final game = state.game;
    final myId = _myId;
    if (gameId == null || game == null || myId == null) return;
    if (!state.canFlip || game.currentPlayerId != myId) return;

    final card = game.cards.length > cardIndex ? game.cards[cardIndex] : null;
    if (card == null || card.isMatched) return;
    if (game.flippedCardIds.contains(cardIndex)) return;
    if (state.optimisticFlips.contains(cardIndex)) return;
    if (game.flippedCardIds.length + state.optimisticFlips.length >= 2) {
      return;
    }

    // Optimistic: flip instantly, reconcile via realtime.
    state = state.copyWith(
      optimisticFlips: [...state.optimisticFlips, cardIndex],
    );
    GameMotionTokens.tap();

    try {
      final client = _client;
      if (client == null) return;
      final result = await client.rpc('fn_memorymatch_flip', params: {
        'p_game_id': gameId,
        'p_card_index': cardIndex,
      });
      final map = (result is Map<String, dynamic>)
          ? result
          : (result is Map ? Map<String, dynamic>.from(result) : null);
      if (map == null || map['ok'] != true) {
        _dropOptimistic(cardIndex);
      } else if (map['isMatch'] == true) {
        GameMotionTokens.success();
      }
    } catch (e) {
      debugPrint('[MemoryMatch] flip error: $e');
      _dropOptimistic(cardIndex);
    }
  }

  void _dropOptimistic(int cardIndex) {
    state = state.copyWith(
      optimisticFlips:
          state.optimisticFlips.where((i) => i != cardIndex).toList(),
    );
  }

  /// Apply the reveal outcome / expire the turn. Idempotent; the server
  /// only acts once the timed reveal window has elapsed.
  Future<void> advance() async {
    final gameId = _gameId;
    if (gameId == null || _advanceInFlight) return;
    _advanceInFlight = true;
    try {
      await _tryRpc('fn_memorymatch_advance', {'p_game_id': gameId});
    } finally {
      _advanceInFlight = false;
    }
  }

  /// Leave the game. Host in the waiting room closes the whole room
  /// (shared temporary-room semantics, same as Ludo / Tug of War).
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
        await _ref.read(temporaryRoomServiceProvider).cancelWaitingRoom(
              gameTable: 'memorymatch_games',
              gameId: gameId,
            );
      } else if (state.amSpectator) {
        await client.rpc('fn_leave_spectator', params: {
          'p_game_table': 'memorymatch_games',
          'p_game_id': gameId,
          'p_user_id': myId,
        });
      } else {
        await _tryRpc('fn_memorymatch_leave', {'p_game_id': gameId});
      }
    } catch (_) {}
    _cleanup();
  }

  /// Host: one-tap rematch. Creates a fresh room with the same settings and
  /// carries the roster over.
  Future<String?> rematch() async {
    final client = _client;
    final game = state.game;
    final myId = _myId;
    if (client == null || game == null || myId == null) return null;

    final roster = List<MemoryMatchPlayer>.from(state.players);

    final newGameId = await createGame(
      difficulty: game.difficulty,
      roomName: game.roomName,
      spectatorsEnabled: game.spectatorsEnabled,
    );
    if (newGameId == null) return null;

    try {
      final others = roster.where((p) => p.userId != myId).toList();
      if (others.isNotEmpty) {
        await client.from('memorymatch_players').upsert(
          others
              .map((p) => {
                    'gameId': newGameId,
                    'userId': p.userId,
                    'userName': p.userName,
                  })
              .toList(),
          onConflict: 'gameId,userId',
        );
        // Record them in the shared room bookkeeping too — joinGame skips
        // fn_record_room_join for players whose rows already exist, so
        // without this the ecosystem archive would miss rematch players.
        for (final p in others) {
          if (p.userId.isEmpty) continue;
          try {
            await client.rpc('fn_record_room_join', params: {
              'p_game_table': 'memorymatch_games',
              'p_game_id': newGameId,
              'p_family_id': familyId,
              'p_user_id': p.userId,
              'p_user_name': p.userName,
              'p_role': 'player',
            });
          } catch (_) {}
        }
      }
      // Fresh ids for the rematch invites.
      final roomCode =
          newGameId.replaceAll('-', '').substring(0, 6).toUpperCase();
      final invites = roster
          .where((p) => p.userId != myId && p.userId.isNotEmpty)
          .map((p) => {
                'gameTable': 'memorymatch_games',
                'gameId': newGameId,
                'gameType': 'memory-match',
                'familyId': familyId,
                'roomCode': roomCode,
                'invitedUserId': p.userId,
                'invitedByUserId': myId,
                'invitedByName': _myName,
                'maxPlayers': game.maxPlayers,
                'currentPlayers': 1,
                'message':
                    '$_myName wants a Memory Match rematch — sharper mind this time?',
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
      debugPrint('[MemoryMatch] rematch error: $e');
    }
    return newGameId;
  }

  // ── Data loading ─────────────────────────────────────────────────

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
          .from('memorymatch_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (resp == null) return;
      _gameId = gameId;
      _applyGameRow(MemoryMatchGame.fromJson(resp));
    } catch (e) {
      debugPrint('[MemoryMatch] loadGame error: $e');
    }
  }

  void _applyGameRow(MemoryMatchGame game) {
    final previous = state.game;
    final wasCurrentMe = previous?.currentPlayerId == _myId;
    final isCurrentMe = game.currentPlayerId == _myId;
    state = state.copyWith(game: game);

    // Reconcile optimistic flips away once the authoritative row covers
    // them (or the state moved on).
    if (state.optimisticFlips.isNotEmpty) {
      final stale = state.optimisticFlips
          .where((i) =>
              game.flippedCardIds.contains(i) ||
              (game.cards.length > i && game.cards[i].isMatched) ||
              !game.isInProgress ||
              game.currentPlayerId != _myId)
          .toList();
      if (stale.isNotEmpty) {
        state = state.copyWith(
          optimisticFlips: state.optimisticFlips
              .where((i) => !stale.contains(i))
              .toList(),
        );
      }
    }

    // Watchdog: while the match runs, ping the server every 2 s so turns
    // expire and reveals resolve even if the current player stalls.
    if (game.isInProgress && _watchdogTimer == null) {
      _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _tryRpc('fn_memorymatch_tick', {'p_game_id': game.id});
      });
    } else if (!game.isInProgress && _watchdogTimer != null) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
    }

    // Precise reveal resolution: the CURRENT player's client schedules the
    // advance exactly when the reveal window closes (everyone's 2 s tick
    // is the backstop).
    _revealTimer?.cancel();
    _revealTimer = null;
    if (game.isInProgress && game.isReveal && game.revealEndsAt != null) {
      final delay = game.revealEndsAt!.difference(DateTime.now()) +
          const Duration(milliseconds: 150);
      _revealTimer = Timer(
        delay.isNegative ? const Duration(milliseconds: 150) : delay,
        () => advance(),
      );
    }

    // Turn passed TO me → gentle haptic cue.
    if (game.isInProgress && isCurrentMe && !wasCurrentMe) {
      GameMotionTokens.tap();
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
          .from('memorymatch_players')
          .select()
          .eq('gameId', gameId)
          .order('joinedAt', ascending: true);
      final players =
          resp.map((p) => MemoryMatchPlayer.fromJson(p)).toList();
      state = state.copyWith(players: players);
    } catch (e) {
      debugPrint('[MemoryMatch] refreshPlayers error: $e');
    }
  }

  Future<bool> _tryRpc(String fn, Map<String, dynamic> params) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.rpc(fn, params: params);
      return true;
    } catch (e) {
      debugPrint('[MemoryMatch] $fn error: $e');
      return false;
    }
  }

  void _scheduleRoomCleanup(String gameId) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'memorymatch_games',
            gameId: gameId,
          );
    });
  }

  // ── Realtime subscription ────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    _channel = client
        .channel('memorymatch_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'memorymatch_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated =
                MemoryMatchGame.fromJson(payload.newRecord);
            _applyGameRow(updated);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'memorymatch_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final player = MemoryMatchPlayer.fromJson(payload.newRecord);
            if (!state.players.any((p) => p.userId == player.userId)) {
              state = state.copyWith(players: [...state.players, player]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'memorymatch_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final updated = MemoryMatchPlayer.fromJson(payload.newRecord);
            final next = state.players
                .map((p) => p.userId == updated.userId ? updated : p)
                .toList();
            state = state.copyWith(players: next);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'memorymatch_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final goneId = payload.oldRecord['userId'] as String?;
            if (goneId == null) return;
            state = state.copyWith(
              players:
                  state.players.where((p) => p.userId != goneId).toList(),
            );
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
    _revealTimer?.cancel();
    _revealTimer = null;
    _gameId = null;
    state = const MemoryMatchState();
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _cleanupTimer?.cancel();
    _revealTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}

final memoryMatchProvider = StateNotifierProvider.autoDispose
    .family<MemoryMatchNotifier, MemoryMatchState, String>(
  (ref, familyId) => MemoryMatchNotifier(ref, familyId),
);
