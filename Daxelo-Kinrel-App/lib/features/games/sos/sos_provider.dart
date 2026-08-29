// lib/features/games/sos/sos_provider.dart
//
// SOS Game — Riverpod state + Supabase Realtime for live move sync.
//
// Architecture:
//   • Supabase stores games, players, moves, scores
//   • Supabase Realtime broadcasts new moves + player changes
//   • Game logic runs client-side (sequence detection, turn rotation)
//     — same logic runs on all clients, ensuring consistency because
//     moves are validated and applied in playedAt order.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import 'sos_connection_status.dart';
import 'sos_game_logic.dart';
import 'sos_models.dart';

class SosState {
  const SosState({
    this.game,
    this.players = const [],
    this.moves = const [],
    this.sequences = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.friendlyError,
    this.myTeam,
    this.myUserId,
    this.connectionStatus = SosConnectionStatus.idle,
  });

  final SosGame? game;
  final List<SosPlayer> players;
  final List<SosMove> moves;
  final List<SosSequence> sequences;
  final bool isLoading;
  final bool isSubmitting;

  /// Raw error string (for debugging only). May contain Postgres / Realtime
  /// internals — never render this directly in the UI. Use [friendlyError]
  /// instead, which is the safe, user-facing message.
  final String? error;

  /// User-facing error message. Always prefer this over [error] in widgets.
  /// Mapped from [error] via [friendlySosError] when the notifier sets it.
  final String? friendlyError;

  final SosTeam? myTeam;

  /// The current Supabase auth user id of the local player.
  ///
  /// Set by the notifier when state is first built in `createGame` /
  /// `joinGame`, and preserved across subsequent `copyWith` calls. Used
  /// by `isMyTurn` to compare against the current turn player's userId.
  final String? myUserId;

  /// Coarse-grained realtime channel state. Drives the
  /// "Reconnecting…" / "Connection lost" banner in the lobby and board
  /// screens. Updated by the notifier from the channel's `onStatus`
  /// callback — never set directly by the UI.
  final SosConnectionStatus connectionStatus;

  bool get isLobby => game?.isLobby ?? false;
  bool get isActive => game?.isActive ?? false;
  bool get isFinished => game?.isFinished ?? false;
  bool get hasGame => game != null;

  /// Build a 2D grid from moves for rendering.
  List<List<String?>> get grid {
    final size = game?.gridSize ?? 7;
    return buildGrid(gridSize: size, moves: moves);
  }

  /// Get the current player whose turn it is.
  SosPlayer? get currentPlayer {
    if (game == null || players.isEmpty) return null;
    final sorted = List<SosPlayer>.from(players)
      ..sort((a, b) => a.turnOrder.compareTo(b.turnOrder));
    final idx = game!.currentTurnOrder;
    if (idx < 0 || idx >= sorted.length) return null;
    return sorted[idx];
  }

  /// Is it my turn?
  bool get isMyTurn =>
      currentPlayer != null && myUserId == currentPlayer!.userId;

  /// Get the team scores (4-player mode) or player scores (2-player mode).
  Map<SosTeam, int> get teamScores {
    final result = <SosTeam, int>{SosTeam.s: 0, SosTeam.o: 0};
    for (final p in players) {
      if (p.team != null) {
        result[p.team!] = result[p.team!]! + p.score;
      }
    }
    return result;
  }

  SosState copyWith({
    SosGame? game,
    List<SosPlayer>? players,
    List<SosMove>? moves,
    List<SosSequence>? sequences,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
    String? friendlyError,
    bool clearFriendlyError = false,
    SosTeam? myTeam,
    String? myUserId,
    SosConnectionStatus? connectionStatus,
  }) =>
      SosState(
        game: game ?? this.game,
        players: players ?? this.players,
        moves: moves ?? this.moves,
        sequences: sequences ?? this.sequences,
        isLoading: isLoading ?? this.isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        friendlyError:
            clearFriendlyError ? null : (friendlyError ?? this.friendlyError),
        myTeam: myTeam ?? this.myTeam,
        myUserId: myUserId ?? this.myUserId,
        connectionStatus: connectionStatus ?? this.connectionStatus,
      );
}

class SosNotifier extends StateNotifier<SosState> {
  SosNotifier(this._ref, this.familyId) : super(const SosState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  String? _gameId;

  /// Fallback poll timer — fires every 5s while in the lobby, refetching
  /// the game row directly from `sos_games`. This is a safety net for the
  /// lobby→active transition: if the realtime channel drops at the exact
  /// moment the host taps Start, the non-host clients would otherwise miss
  /// the status change and stay stuck on the lobby screen. The poll catches
  /// it within 5 seconds and triggers the normal navigation.
  ///
  /// Cancelled on `leaveGame` / `dispose` / once the game becomes active.
  Timer? _lobbyPollTimer;

  // ── Error helpers ─────────────────────────────────────────────

  /// Set both the raw error (for debugging) and a friendly, user-facing
  /// message (for the UI). All error paths in this notifier should go
  /// through here so the UI never has to look at raw Postgres / Realtime
  /// internals.
  void _setError(Object? e, {String? fallback}) {
    final raw = e == null ? null : '$e';
    final friendly = friendlySosError(e, fallback: fallback);
    state = state.copyWith(
      error: raw,
      friendlyError: friendly,
    );
  }

  /// Clear any existing error.
  void _clearError() {
    state = state.copyWith(clearError: true, clearFriendlyError: true);
  }

  // ── Public API ───────────────────────────────────────────────────

  /// Host: create a new game with the given mode and (for 4-player) team
  /// assignments.
  Future<String?> createGame({
    required SosMode mode,
    int gridSize = 7,
    List<String>? teamPlayerUserIds, // for 4-player mode
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      _setError('Not signed in',
          fallback: 'You need to sign in to play. Restart the app and try again.');
      return null;
    }
    // Inject the real auth user id into state so `isMyTurn` can compare
    // against the current turn player. Once set here, `copyWith` preserves
    // it across all subsequent realtime-driven state mutations.
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearFriendlyError: true,
      myUserId: myId,
      connectionStatus: SosConnectionStatus.connecting,
    );
    try {
      final body = {
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'mode': mode.name,
        'gridSize': gridSize,
        'status': 'lobby',
        'currentTurnOrder': 0,
      };
      final resp = await client
          .from('sos_games')
          .insert(body)
          .select()
          .single();
      final game = SosGame.fromJson(resp as Map<String, dynamic>);
      _gameId = game.id;

      // Insert host as first player
      SosTeam? hostTeam;
      int hostTurnOrder = 0;
      if (mode == SosMode.fourPlayerTeams) {
        hostTeam = SosTeam.s; // host is always on Team S, turnOrder 0
        hostTurnOrder = 0;
      }
      await client.from('sos_players').insert({
        'gameId': game.id,
        'userId': myId,
        'userName': _myName,
        'team': hostTeam?.name,
        'turnOrder': hostTurnOrder,
        'score': 0,
      });

      // Determine my team for state
      final myTeam = hostTeam;

      state = state.copyWith(
        game: game,
        isLoading: false,
        myTeam: myTeam,
        myUserId: myId,
      );
      _subscribeToRealtime(game.id);
      _startLobbyPoll(game.id);
      await _refreshPlayers(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[SOS] createGame error: $e');
      state = state.copyWith(
        isLoading: false,
        connectionStatus: SosConnectionStatus.error,
      );
      _setError(e, fallback: 'Couldn\'t create the game. Tap to try again.');
      return null;
    }
  }

  /// Non-host: join an existing game by id.
  Future<bool> joinGame(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      _setError('Not signed in',
          fallback: 'You need to sign in to play. Restart the app and try again.');
      return false;
    }
    // Inject the real auth user id into state so `isMyTurn` can compare
    // against the current turn player. Once set here, `copyWith` preserves
    // it across all subsequent realtime-driven state mutations.
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearFriendlyError: true,
      myUserId: myId,
      connectionStatus: SosConnectionStatus.connecting,
    );
    try {
      // Fetch the game
      final gameResp = await client
          .from('sos_games')
          .select()
          .eq('id', gameId)
          .single();
      final game = SosGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      // Fetch existing players to determine my turn order + team
      final playersResp = await client
          .from('sos_players')
          .select()
          .eq('gameId', gameId)
          .order('turnOrder', ascending: true);
      final existingPlayers = playersResp
          .map((p) => SosPlayer.fromJson(p as Map<String, dynamic>))
          .toList();

      // Compute my turn order (next available slot)
      final existingOrders = existingPlayers
          .map((p) => p.turnOrder)
          .toSet();
      int myTurnOrder = 0;
      while (existingOrders.contains(myTurnOrder)) {
        myTurnOrder++;
      }

      // Determine my team for 4-player mode
      SosTeam? myTeam;
      if (game.mode == SosMode.fourPlayerTeams) {
        // Team S has turnOrders 0, 2; Team O has turnOrders 1, 3
        myTeam = (myTurnOrder % 2 == 0) ? SosTeam.s : SosTeam.o;
      }

      // Insert myself as a player
      await client.from('sos_players').upsert({
        'gameId': gameId,
        'userId': myId,
        'userName': _myName,
        'team': myTeam?.name,
        'turnOrder': myTurnOrder,
        'score': 0,
      }, onConflict: 'gameId,userId');

      state = state.copyWith(
        game: game,
        isLoading: false,
        myTeam: myTeam,
        myUserId: myId,
      );
      _subscribeToRealtime(gameId);
      _startLobbyPoll(gameId);
      await _refreshPlayers(gameId);
      await _refreshMoves(gameId);

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
      debugPrint('[SOS] joinGame error: $e');
      state = state.copyWith(
        isLoading: false,
        connectionStatus: SosConnectionStatus.error,
      );
      _setError(e, fallback: 'Couldn\'t join the room. Tap to try again.');
      return false;
    }
  }

  /// Host: start the game (transition from lobby to active).
  Future<void> startGame() async {
    final client = _client;
    final gameId = _gameId;
    if (client == null || gameId == null) return;
    final game = state.game;
    if (game == null) return;

    // Validate player count
    if (state.players.length < game.mode.minPlayers) {
      _setError(
        'Need ${game.mode.minPlayers} players to start '
        '(currently ${state.players.length})',
        fallback: 'Need ${game.mode.minPlayers} players to start. '
            'Wait for more family members to join.',
      );
      return;
    }

    try {
      await client.from('sos_games').update({
        'status': 'active',
        'startedAt': DateTime.now().toIso8601String(),
      }).eq('id', gameId);

      // The game-invite chat card is no longer joinable — flip its status
      // so the card renders "Started" for every family member via realtime.
      unawaited(
        syncGameInviteChatCards(
          client: client,
          gameId: gameId,
          inviteStatus: 'accepted',
        ),
      );
    } catch (e) {
      debugPrint('[SOS] startGame error: $e');
      _setError(e, fallback: 'Couldn\'t start the game. Tap to try again.');
    }
  }

  /// Place a letter on the grid.
  Future<bool> placeLetter({
    required int row,
    required int col,
    required SosLetter letter,
  }) async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final game = state.game;
    if (client == null || gameId == null || myId == null || game == null) {
      return false;
    }

    // Validate
    final error = validateMove(
      game: game,
      players: state.players,
      moves: state.moves,
      userId: myId,
      row: row,
      col: col,
      letter: letter,
    );
    if (error != null) {
      _setError(error,
          fallback: 'That move isn\'t valid. Try a different cell.');
      GameMotionTokens.error();
      return false;
    }

    state = state.copyWith(
      isSubmitting: true,
      clearError: true,
      clearFriendlyError: true,
    );
    try {
      // Build the grid WITH the new move to check sequences
      final grid = buildGrid(
        gridSize: game.gridSize,
        moves: state.moves,
      );
      grid[row][col] = letter.char;

      final myPlayer = state.players.firstWhere((p) => p.userId == myId);
      final sequences = findCompletedSequences(
        grid: grid,
        gridSize: game.gridSize,
        row: row,
        col: col,
        letter: letter.char,
        team: myPlayer.team,
      );
      final scored = sequences.isNotEmpty;
      final sequenceCount = sequences.length;

      // Insert the move
      final moveResp = await client.from('sos_moves').insert({
        'gameId': gameId,
        'userId': myId,
        'userName': _myName,
        'rowIdx': row,
        'colIdx': col,
        'letter': letter.char,
        'team': myPlayer.team?.name,
        'sequenced': scored,
        'sequenceCount': sequenceCount,
      }).select().single();
      final move = SosMove.fromJson(moveResp as Map<String, dynamic>);

      // Update player score if scored
      if (scored) {
        final newScore = myPlayer.score + sequenceCount;
        await client.from('sos_players').update({
          'score': newScore,
        }).eq('gameId', gameId).eq('userId', myId);

        // Upsert team score (4-player mode) or player score (2-player)
        if (game.mode == SosMode.fourPlayerTeams && myPlayer.team != null) {
          await _upsertTeamScore(gameId, myPlayer.team!, newScore);
        }

        GameMotionTokens.celebrate();
      } else {
        GameMotionTokens.tap();
      }

      // Compute next turn order
      final nextOrder = nextTurnOrder(
        currentTurnOrder: game.currentTurnOrder,
        playerCount: state.players.length,
        scored: scored,
      );

      // Update game's current turn order
      await client.from('sos_games').update({
        'currentTurnOrder': nextOrder,
      }).eq('id', gameId);

      // Check if grid is full → finish the game
      final newMoves = [...state.moves, move];
      if (isGridFull(gridSize: game.gridSize, moves: newMoves)) {
        await _finishGame(game, newMoves);
      }

      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e) {
      debugPrint('[SOS] placeLetter error: $e');
      state = state.copyWith(isSubmitting: false);
      _setError(e,
          fallback: 'Couldn\'t place your letter. Tap to try again.');
      return false;
    }
  }

  Future<void> _upsertTeamScore(
    String gameId,
    SosTeam team,
    int teamScore,
  ) async {
    final client = _client;
    if (client == null) return;
    // Sum all players' scores on this team
    final teamPlayers = state.players.where((p) => p.team == team).toList();
    final totalScore = teamPlayers.fold<int>(
      0,
      (sum, p) => sum + p.score,
    );
    // Upsert the team score row
    final existing = await client
        .from('sos_scores')
        .select()
        .eq('gameId', gameId)
        .eq('team', team.name)
        .maybeSingle();
    if (existing != null) {
      await client.from('sos_scores').update({
        'score': totalScore,
        'updatedAt': DateTime.now().toIso8601String(),
      }).eq('id', existing['id']);
    } else {
      await client.from('sos_scores').insert({
        'gameId': gameId,
        'team': team.name,
        'score': totalScore,
      });
    }
  }

  Future<void> _finishGame(SosGame game, List<SosMove> moves) async {
    final client = _client;
    final gameId = _gameId;
    if (client == null || gameId == null) return;

    // Compute winner
    final winner = computeWinner(
      game: game,
      players: state.players,
      scores: const [],
    );

    await client.from('sos_games').update({
      'status': 'finished',
      'finishedAt': DateTime.now().toIso8601String(),
      'winnerTeam': winner.winnerTeam?.name,
      'winnerUserId': winner.winnerUserId,
    }).eq('id', gameId);

    // The game-invite chat card has run its course — flip its status so the
    // card renders "Ended" for every family member via realtime.
    unawaited(
      syncGameInviteChatCards(
        client: client,
        gameId: gameId,
        inviteStatus: 'expired',
      ),
    );
  }

  /// Leave the game (manual exit).
  Future<void> leaveGame() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    _stopLobbyPoll();
    if (client == null || gameId == null || myId == null) {
      _cleanup();
      return;
    }
    try {
      await client
          .from('sos_players')
          .delete()
          .eq('gameId', gameId)
          .eq('userId', myId);
    } catch (_) {}
    _cleanup();
  }

  void _cleanup() {
    _stopLobbyPoll();
    _channel?.unsubscribe();
    _channel = null;
    _gameId = null;
  }

  /// Manual retry entry point for the UI. Re-subscribes to the realtime
  /// channel for the current game (if any) and refreshes players + moves
  /// from the server. Safe to call from any state — if there's no current
  /// game, this is a no-op.
  ///
  /// Wired to the "Retry" button on connection-error states in the lobby
  /// and board screens.
  Future<void> retryConnection() async {
    final gameId = _gameId;
    if (gameId == null) return;
    _clearError();
    state = state.copyWith(connectionStatus: SosConnectionStatus.connecting);
    _subscribeToRealtime(gameId);
    await _refreshPlayers(gameId);
    await _refreshMoves(gameId);
    // If we're still in the lobby, keep the fallback poll running.
    if (state.isLobby) {
      _startLobbyPoll(gameId);
    }
  }

  // ── Realtime subscription ────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    // Mark as "connecting" while we wait for the SUBSCRIBED ack. The
    // .subscribe(onStatus:) callback below will flip it to "connected"
    // on success or "reconnecting"/"error" on failure.
    state = state.copyWith(connectionStatus: SosConnectionStatus.connecting);

    _channel = client
        .channel('sos_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sos_moves',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final move = SosMove.fromJson(payload.newRecord);
            state = state.copyWith(moves: [...state.moves, move]);
            // Recompute sequences for highlighting
            _recomputeSequences();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sos_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final player = SosPlayer.fromJson(payload.newRecord);
            if (!state.players.any((p) => p.userId == player.userId)) {
              state = state.copyWith(players: [...state.players, player]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'sos_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final updated = SosPlayer.fromJson(payload.newRecord);
            final next = state.players
                .map((p) => p.userId == updated.userId ? updated : p)
                .toList();
            state = state.copyWith(players: next);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'sos_players',
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
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'sos_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated = SosGame.fromJson(payload.newRecord);
            state = state.copyWith(game: updated);
            // Once the game becomes active, the lobby→board navigation
            // fires from the lobby screen's ref.listen. Stop the fallback
            // poll here — it's only needed while we're in the lobby.
            if (updated.isActive || updated.isFinished) {
              _stopLobbyPoll();
            }
          },
        )
        .subscribe(_onChannelStatus);
  }

  /// Channel status callback — drives [SosState.connectionStatus] and the
  /// "Reconnecting…" / "Connection lost" banner in the UI.
  ///
  /// Supabase Realtime statuses:
  ///   - [RealtimeSubscribeStatus.subscribed]   → channel is live, events flowing
  ///   - [RealtimeSubscribeStatus.channelError] → transient error, SDK auto-retries
  ///   - [RealtimeSubscribeStatus.timedOut]     → no ack within timeout, SDK auto-retries
  ///   - [RealtimeSubscribeStatus.closed]       → channel closed (server-side or explicit), no auto-retry
  void _onChannelStatus(RealtimeSubscribeStatus status, [Object? error]) {
    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        state = state.copyWith(
          connectionStatus: SosConnectionStatus.connected,
          clearError: true,
          clearFriendlyError: true,
        );
        break;
      case RealtimeSubscribeStatus.channelError:
      case RealtimeSubscribeStatus.timedOut:
        // SDK auto-retries — surface a non-blocking "Reconnecting…" banner.
        state = state.copyWith(
          connectionStatus: SosConnectionStatus.reconnecting,
        );
        debugPrint('[SOS] realtime channel $status: $error');
        break;
      case RealtimeSubscribeStatus.closed:
        // No auto-retry — needs explicit user action (tap Retry).
        state = state.copyWith(
          connectionStatus: SosConnectionStatus.error,
        );
        _setError(
          'Realtime channel closed',
          fallback: 'Lost connection to the room. Tap to try again.',
        );
        break;
    }
  }

  // ── Lobby fallback poll ──────────────────────────────────────────

  /// Start a 5-second poll that refetches the game row while we're in the
  /// lobby. Safety net for the lobby→active transition: if the realtime
  /// channel drops at the exact moment the host taps Start, the non-host
  /// clients would otherwise miss the status change. The poll catches it
  /// within 5 seconds and the realtime callback (or this poll) updates
  /// `state.game.status`, which the lobby screen's `ref.listen` reacts to.
  void _startLobbyPoll(String gameId) {
    _stopLobbyPoll();
    _lobbyPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollGameState(gameId),
    );
  }

  void _stopLobbyPoll() {
    _lobbyPollTimer?.cancel();
    _lobbyPollTimer = null;
  }

  Future<void> _pollGameState(String gameId) async {
    final client = _client;
    if (client == null) return;
    // Only poll while we're still in the lobby — once active, the realtime
    // channel is the source of truth and the poll is wasteful.
    if (!state.isLobby) {
      _stopLobbyPoll();
      return;
    }
    try {
      final resp = await client
          .from('sos_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (resp == null) {
        // Game row vanished — server-side delete or RLS revocation.
        _stopLobbyPoll();
        _setError(
          'Game not found',
          fallback: 'This game room no longer exists.',
        );
        return;
      }
      final updated = SosGame.fromJson(resp as Map<String, dynamic>);
      // Only update if status changed — avoids spurious rebuilds.
      if (updated.status != state.game?.status) {
        state = state.copyWith(game: updated);
        if (updated.isActive || updated.isFinished) {
          _stopLobbyPoll();
        }
      }
    } catch (e) {
      // Best-effort poll — never bubble up. The realtime channel is the
      // primary source of truth; the poll is just a safety net.
      debugPrint('[SOS] lobby poll error (non-fatal): $e');
    }
  }

  void _recomputeSequences() {
    final game = state.game;
    if (game == null) return;
    final grid = buildGrid(gridSize: game.gridSize, moves: state.moves);
    final allSequences = <SosSequence>[];
    // Re-derive all sequences from the grid (for highlighting)
    for (final move in state.moves) {
      if (move.sequenced) {
        final found = findCompletedSequences(
          grid: grid,
          gridSize: game.gridSize,
          row: move.rowIdx,
          col: move.colIdx,
          letter: move.letter.char,
          team: move.team,
          moveId: move.id,
        );
        allSequences.addAll(found);
      }
    }
    state = state.copyWith(sequences: allSequences);
  }

  Future<void> _refreshPlayers(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('sos_players')
          .select()
          .eq('gameId', gameId)
          .order('turnOrder', ascending: true);
      final players = resp
          .map((p) => SosPlayer.fromJson(p as Map<String, dynamic>))
          .toList();
      // Update my team if I'm in the player list
      final myId = _myId;
      SosTeam? myTeam;
      if (myId != null) {
        final me = players.where((p) => p.userId == myId).firstOrNull;
        if (me != null) myTeam = me.team;
      }
      state = state.copyWith(players: players, myTeam: myTeam ?? state.myTeam);
    } catch (e) {
      debugPrint('[SOS] refreshPlayers error: $e');
    }
  }

  Future<void> _refreshMoves(String gameId) async {
    final client = _client;
    if (client == null) return;
    try {
      final resp = await client
          .from('sos_moves')
          .select()
          .eq('gameId', gameId)
          .order('playedAt', ascending: true);
      final moves = resp
          .map((m) => SosMove.fromJson(m as Map<String, dynamic>))
          .toList();
      state = state.copyWith(moves: moves);
      _recomputeSequences();
    } catch (e) {
      debugPrint('[SOS] refreshMoves error: $e');
    }
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

final sosProvider = StateNotifierProvider.autoDispose
    .family<SosNotifier, SosState, String>(
  (ref, familyId) => SosNotifier(ref, familyId),
);
