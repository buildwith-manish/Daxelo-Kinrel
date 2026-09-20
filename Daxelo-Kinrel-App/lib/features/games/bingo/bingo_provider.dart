// lib/features/games/bingo/bingo_provider.dart
//
// Bingo — Riverpod state + Supabase Realtime + server-authoritative RPCs.
//
// Architecture (v2 — 2026-09-19 sync repair):
//   • Supabase stores games, cards, claims
//   • Supabase Realtime broadcasts called numbers + winner
//     (bingo_games/bingo_cards/bingo_claims are REPLICA IDENTITY FULL,
//      so update payloads always carry every column)
//   • fn_bingo_tick advances the number sequence server-side — clients
//     run a 1 s watchdog while the game is in progress; the server
//     serializes ticks and only advances when callIntervalSeconds have
//     elapsed. A */15 s cron safety-net covers rooms whose clients all
//     vanished (numbers keep flowing → draw auto-completes at 75).
//   • fn_bingo_claim validates BINGO claims server-side (auth.uid()-
//     based) and completes the game in one round-trip.
//   • fn_bingo_start enforces host + ≥2 players with server timestamps.
//   • Card generation happens client-side (random) but the card is
//     persisted to Supabase so the server can verify wins against it.
//   • Reconnection: the realtime channel re-fetches game + cards when it
//     re-subscribes after a drop, and a 10 s safety poll covers any
//     missed event while in progress.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
import '../shared/services/temporary_room_service.dart';
import 'bingo_models.dart';

class BingoState {
  const BingoState({
    this.game,
    this.myCard,
    this.allCards = const [],
    this.claims = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.isClaiming = false,
    this.amSpectator = false,
    this.error,
    this.lastClaimValid,
    this.lastClaimReason,
  });

  final BingoGame? game;
  final BingoCard? myCard;
  final List<BingoCard> allCards;
  final List<BingoClaim> claims;
  final bool isLoading;
  final bool isSubmitting;
  final bool isClaiming;
  final bool amSpectator;
  final String? error;
  final bool? lastClaimValid;
  final String? lastClaimReason;

  bool get isWaiting => game?.isWaiting ?? false;
  bool get isInProgress => game?.isInProgress ?? false;
  bool get isCompleted => game?.isCompleted ?? false;
  bool get hasGame => game != null;
  bool get hasCard => myCard != null;

  /// Numbers that have been called AND are on my card (candidate for marking).
  List<int> get myCalledNumbers {
    if (myCard == null || game == null) return const [];
    return game!.numbersCalled
        .where((n) => myCard!.hasNumber(n))
        .toList();
  }

  /// Has the player potentially won? (Client-side hint only — actual
  /// verification is server-side.)
  bool get canClaimBingo {
    if (myCard == null || game == null) return false;
    return _checkWinPattern(myCard!, game!.numbersCalled, game!.winPattern);
  }

  /// How many marks I'm still missing on called numbers (UX nudge).
  int get unmarkedCalledCount {
    if (myCard == null || game == null) return 0;
    return myCalledNumbers
        .where((n) => !myCard!.isMarked(n))
        .length;
  }

  /// Check if the player's marked numbers (filtered to called numbers)
  /// satisfy the win pattern. This is a CLIENT-SIDE HINT for the UI —
  /// the actual win verification happens server-side via fn_bingo_claim.
  static bool _checkWinPattern(
    BingoCard card,
    List<int> calledNumbers,
    BingoWinPattern pattern,
  ) {
    // Filter marked to only those actually called
    final validMarked = card.markedNumbers
        .where((n) => calledNumbers.contains(n))
        .toSet();

    bool isCellMarked(int row, int col) {
      if (row == 2 && col == 2) return true; // free center
      final v = card.cardNumbers[row][col];
      return v != null && validMarked.contains(v);
    }

    if (pattern == BingoWinPattern.fullCard) {
      for (int r = 0; r < 5; r++) {
        for (int c = 0; c < 5; c++) {
          if (r == 2 && c == 2) continue;
          if (!isCellMarked(r, c)) return false;
        }
      }
      return true;
    }

    // Line pattern: check rows, columns, diagonals
    // Rows
    for (int r = 0; r < 5; r++) {
      bool complete = true;
      for (int c = 0; c < 5; c++) {
        if (!isCellMarked(r, c)) {
          complete = false;
          break;
        }
      }
      if (complete) return true;
    }
    // Columns
    for (int c = 0; c < 5; c++) {
      bool complete = true;
      for (int r = 0; r < 5; r++) {
        if (!isCellMarked(r, c)) {
          complete = false;
          break;
        }
      }
      if (complete) return true;
    }
    // Diagonal 1 (top-left to bottom-right)
    bool d1 = true;
    for (int i = 0; i < 5; i++) {
      if (i == 2) continue;
      if (!isCellMarked(i, i)) {
        d1 = false;
        break;
      }
    }
    if (d1) return true;
    // Diagonal 2 (top-right to bottom-left)
    bool d2 = true;
    for (int i = 0; i < 5; i++) {
      if (i == 2) continue;
      if (!isCellMarked(i, 4 - i)) {
        d2 = false;
        break;
      }
    }
    return d2;
  }

  BingoState copyWith({
    BingoGame? game,
    BingoCard? myCard,
    List<BingoCard>? allCards,
    List<BingoClaim>? claims,
    bool? isLoading,
    bool? isSubmitting,
    bool? isClaiming,
    bool? amSpectator,
    String? error,
    bool clearError = false,
    bool? lastClaimValid,
    String? lastClaimReason,
    bool clearClaim = false,
    bool clearCard = false,
  }) =>
      BingoState(
        game: game ?? this.game,
        myCard: clearCard ? null : (myCard ?? this.myCard),
        allCards: allCards ?? this.allCards,
        claims: claims ?? this.claims,
        isLoading: isLoading ?? this.isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        isClaiming: isClaiming ?? this.isClaiming,
        amSpectator: amSpectator ?? this.amSpectator,
        error: clearError ? null : (error ?? this.error),
        lastClaimValid: clearClaim ? null : (lastClaimValid ?? this.lastClaimValid),
        lastClaimReason: clearClaim ? null : (lastClaimReason ?? this.lastClaimReason),
      );
}

class BingoNotifier extends StateNotifier<BingoState> {
  BingoNotifier(this._ref, this.familyId) : super(const BingoState());

  final Ref _ref;
  final String familyId;

  SupabaseClient? get _client => _ref.read(supabaseProvider);
  String? get _myId => _client?.auth.currentUser?.id;
  String get _myName =>
      _client?.auth.currentUser?.userMetadata?['name'] as String? ?? 'Player';

  RealtimeChannel? _channel;
  String? _gameId;
  Timer? _tickTimer;
  Timer? _safetyPollTimer;
  bool _disposed = false;

  // ── Public API ───────────────────────────────────────────────────

  /// Host: create a new game.
  Future<String?> createGame({
    required BingoWinPattern winPattern,
    int callIntervalSeconds = 5,
    int maxPlayers = 30,
  }) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return null;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final body = {
        'familyId': familyId,
        'hostUserId': myId,
        'hostUserName': _myName,
        'status': 'waiting',
        'winPattern': winPattern.short,
        'callIntervalSeconds': callIntervalSeconds,
        'maxPlayers': maxPlayers,
        'numbersCalled': [],
      };
      final resp = await client
          .from('bingo_games')
          .insert(body)
          .select()
          .single();
      final game = BingoGame.fromJson(resp);
      _gameId = game.id;

      // Generate a card for the host immediately
      await _generateAndInsertCard(game.id, myId, _myName);
      // Record the participant (archive + invite flows read these rows).
      await _recordJoin(game.id, myId, role: 'host');

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(game.id);
      await _refreshCards(game.id);
      return game.id;
    } catch (e) {
      debugPrint('[Bingo] createGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return null;
    }
  }

  /// Join an existing game — or, when the match is already underway and
  /// the caller holds no card, seamlessly become a SPECTATOR instead of
  /// dealing a mid-game card.
  Future<bool> joinGame(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) {
      state = state.copyWith(error: 'Not signed in');
      return false;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // maybeSingle → a deleted (closed) room returns null instead of
      // throwing, so we can show a friendly message and prompt the user
      // to create a new room instead of joining a ghost room.
      final gameResp = await client
          .from('bingo_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (isRoomRowClosed(gameResp)) {
        state = state.copyWith(
          isLoading: false,
          error: kRoomClosedMessage,
        );
        return false;
      }
      final game = BingoGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      final cardsResp = await client
          .from('bingo_cards')
          .select()
          .eq('gameId', gameId);
      final cards = cardsResp.map(BingoCard.fromJson).toList();
      final myCard =
          cards.where((c) => c.playerId == myId).firstOrNull;

      if (game.isInProgress && myCard == null) {
        // Mid-game arrival → spectate (no card, full realtime sync).
        await _spectate(game.id);
        state = state.copyWith(
            game: game,
            allCards: cards,
            myCard: null,
            amSpectator: true,
            isLoading: false);
        _subscribeToRealtime(game.id);
        _startWatchdogs();
        return true;
      }

      if (game.isCompleted && myCard == null) {
        // Finished game, no card → also spectate-style viewing (results).
        await _spectate(game.id);
        state = state.copyWith(
            game: game,
            allCards: cards,
            amSpectator: true,
            isLoading: false);
        _subscribeToRealtime(game.id);
        return true;
      }

      // Check max players (only blocks new cards)
      if (myCard == null) {
        if (cards.length >= game.maxPlayers) {
          state = state.copyWith(
            isLoading: false,
            error: 'Game is full (${game.maxPlayers} players)',
          );
          return false;
        }
        await _generateAndInsertCard(game.id, myId, _myName);
      }

      await _recordJoin(game.id, myId,
          role: game.hostUserId == myId ? 'host' : 'player');

      state = state.copyWith(
          game: game, isLoading: false, amSpectator: false);
      _subscribeToRealtime(game.id);
      await _refreshCards(game.id);
      if (game.isInProgress) _startWatchdogs();
      // Keep the persistent game-invite chat card in the family thread in
      // sync with the new player count ("2/4 players" / "Full") for every
      // family member via realtime. Best-effort, never affects the join.
      unawaited(
        syncGameInviteChatCards(
          client: client,
          gameId: gameId,
          currentPlayers: state.allCards.length,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[Bingo] joinGame error: $e');
      state = state.copyWith(isLoading: false, error: '$e');
      return false;
    }
  }

  Future<void> _spectate(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null || myId == null) return;
    try {
      await client.rpc('fn_spectate_game', params: {
        'p_game_table': 'bingo_games',
        'p_game_id': gameId,
        'p_family_id': familyId,
        'p_user_id': myId,
        'p_user_name': _myName,
      });
    } catch (e) {
      debugPrint('[Bingo] spectate error: $e');
    }
  }

  Future<void> _recordJoin(String gameId, String userId,
      {String role = 'player'}) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.rpc('fn_record_room_join', params: {
        'p_game_table': 'bingo_games',
        'p_game_id': gameId,
        'p_family_id': familyId,
        'p_user_id': userId,
        'p_user_name': _myName,
        'p_role': role,
      });
    } catch (e) {
      debugPrint('[Bingo] recordJoin error: $e');
    }
  }

  Future<void> _generateAndInsertCard(
    String gameId,
    String playerId,
    String playerName,
  ) async {
    final client = _client;
    if (client == null) return;
    final cardNumbers = generateBingoCard();
    final jsonGrid = cardNumbers
        .map((row) => row.map((cell) => cell).toList())
        .toList();
    await client.from('bingo_cards').insert({
      'gameId': gameId,
      'playerId': playerId,
      'playerName': playerName,
      'cardNumbers': jsonGrid,
      'markedNumbers': [],
      'hasClaimed': false,
    });
  }

  /// Host: start the game. Server validates host + ≥2 players and stamps
  /// server-side timestamps; the first number drops on the next tick.
  Future<void> startGame() async {
    final client = _client;
    final gameId = _gameId;
    if (client == null || gameId == null) return;

    try {
      final res = await client.rpc('fn_bingo_start', params: {
        'p_game_id': gameId,
      });
      final data = (res as Map?)?.cast<String, dynamic>();
      final ok = data?['ok'] == true;
      if (!ok) {
        final reason = data?['reason'] ?? 'unknown';
        var friendly = 'Couldn\'t start the game';
        switch (reason) {
          case 'need_two_players':
            friendly = 'Need at least 2 players to start';
            break;
          case 'not_host':
            friendly = 'Only the host can start';
            break;
          case 'already_started':
            friendly = 'Game already started';
            break;
        }
        state = state.copyWith(error: friendly);
        return;
      }
      // Realtime will deliver the in_progress transition; optimistically
      // refresh so the host sees it instantly.
      await refreshGame();
    } catch (e) {
      debugPrint('[Bingo] startGame error: $e');
      state = state.copyWith(error: '$e');
    }
  }

  /// Player: toggle a number's marked state on their card.
  /// Only allows marking numbers that have actually been called.
  Future<void> toggleMark(int number) async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final card = state.myCard;
    final game = state.game;
    if (client == null || gameId == null || myId == null || card == null || game == null) {
      return;
    }

    // Only allow marking if the number has been called
    if (!game.numbersCalled.contains(number)) {
      GameMotionTokens.error();
      return;
    }

    // Only allow if the number is on my card
    if (!card.hasNumber(number)) {
      GameMotionTokens.error();
      return;
    }

    final newMarked = List<int>.from(card.markedNumbers);
    if (newMarked.contains(number)) {
      newMarked.remove(number);
    } else {
      newMarked.add(number);
      GameMotionTokens.tap();
    }

    // Optimistic local update
    final updatedCard = BingoCard(
      id: card.id,
      gameId: card.gameId,
      playerId: card.playerId,
      playerName: card.playerName,
      cardNumbers: card.cardNumbers,
      markedNumbers: newMarked,
      hasClaimed: card.hasClaimed,
      createdAt: card.createdAt,
    );
    state = state.copyWith(myCard: updatedCard);

    // Persist to Supabase
    try {
      await client.from('bingo_cards').update({
        'markedNumbers': newMarked,
      }).eq('id', card.id);
    } catch (e) {
      debugPrint('[Bingo] toggleMark error: $e');
      // Revert on failure
      state = state.copyWith(myCard: card);
    }
  }

  /// Player: claim BINGO! Server-side verification + completion in one
  /// RPC (fn_bingo_claim) — identity comes from auth.uid(), never the
  /// payload.
  Future<bool> claimBingo() async {
    final client = _client;
    final gameId = _gameId;
    if (client == null || gameId == null) return false;

    state = state.copyWith(isClaiming: true, clearClaim: true);
    try {
      final res = await client.rpc('fn_bingo_claim', params: {
        'p_game_id': gameId,
      });
      final data = (res as Map).cast<String, dynamic>();
      final isValid = data['valid'] == true;
      final reason = data['reason'] as String?;

      if (isValid) {
        GameMotionTokens.celebrate();
        state = state.copyWith(
          isClaiming: false,
          lastClaimValid: true,
        );
        return true;
      } else {
        GameMotionTokens.error();
        state = state.copyWith(
          isClaiming: false,
          lastClaimValid: false,
          lastClaimReason: reason,
        );
        // Clear the invalid claim feedback after 2.5s
        Timer(const Duration(milliseconds: 2500), () {
          if (mounted) state = state.copyWith(clearClaim: true);
        });
        return false;
      }
    } catch (e) {
      debugPrint('[Bingo] claimBingo error: $e');
      state = state.copyWith(
        isClaiming: false,
        lastClaimValid: false,
        lastClaimReason: 'Failed to verify claim: $e',
      );
      return false;
    }
  }

  /// Leave the game. If the user is the host AND the game is still in
  /// `waiting` status, the entire room is deleted (cascade to child
  /// tables + invites) via the temporary-room service. Otherwise the
  /// player's own row is deleted (bingo uses `bingo_cards` as the
  /// per-player table). Mid-game rooms are NEVER torn down by a single
  /// player leaving — the server-side caller keeps the match alive.
  Future<void> leaveGame() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    final game = state.game;
    _stopWatchdogs();
    _channel?.unsubscribe();
    _channel = null;
    if (state.amSpectator && client != null && gameId != null && myId != null) {
      try {
        await client.rpc('fn_leave_spectator', params: {
          'p_game_table': 'bingo_games',
          'p_game_id': gameId,
          'p_user_id': myId,
        });
      } catch (_) {}
    }
    if (client == null || gameId == null || myId == null) {
      _gameId = null;
      return;
    }
    try {
      if (game != null && game.isWaiting && game.hostUserId == myId) {
        await _ref.read(temporaryRoomServiceProvider).cancelWaitingRoom(
              gameTable: 'bingo_games',
              gameId: gameId,
            );
      } else {
        await client
            .from('bingo_cards')
            .delete()
            .eq('gameId', gameId)
            .eq('playerId', myId);
      }
    } catch (_) {}
    _gameId = null;
  }

  /// Re-fetch the authoritative game row + cards (reconnection, post-
  /// RPC refresh, safety poll).
  Future<void> refreshGame() async {
    final client = _client;
    final gameId = _gameId;
    if (client == null || gameId == null) return;
    try {
      final gameResp = await client
          .from('bingo_games')
          .select()
          .eq('id', gameId)
          .maybeSingle();
      if (gameResp == null) return; // room gone — realtime handles it
      final game = BingoGame.fromJson(gameResp);
      state = state.copyWith(game: game);
      await _refreshCards(gameId);
      if (game.isInProgress) {
        _startWatchdogs();
      } else {
        _stopWatchdogs();
      }
    } catch (e) {
      debugPrint('[Bingo] refreshGame error: $e');
    }
  }

  /// Schedule the temporary room (and all temporary player associations)
  /// for deletion 30s after the game ends. The hourly pg_cron job is
  /// the safety net if the user closes the app before this fires.
  void _scheduleRoomCleanup(String gameId) {
    Timer(const Duration(seconds: 30), () {
      _ref.read(temporaryRoomServiceProvider).endGame(
            gameTable: 'bingo_games',
            gameId: gameId,
          );
    });
  }

  // ── Watchdogs ────────────────────────────────────────────────────

  /// While in progress: drive the server-side caller every second (the
  /// server only advances when the interval elapses). The 10-second
  /// `_safetyPollTimer` was removed in v111 — the Postgres Changes
  /// listeners on `bingo_games` + `bingo_cards` (set up in
  /// `_subscribeToRealtime`) already deliver every state change in
  /// real time. The 10s poll was a redundant DB READ. See worklog
  /// Task 2-stickman-heist (bundled zero-risk Category B cleanups).
  void _startWatchdogs() {
    _tickTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || !state.isInProgress) {
        _stopWatchdogs();
        return;
      }
      _tick();
    });
    // NOTE: `_safetyPollTimer` removed — was a 10s DB READ on
    // `bingo_games` + `bingo_cards`, duplicating the existing
    // Postgres Changes listeners. Field kept for backward-compat
    // with `_stopWatchdogs()` but never set.
  }

  void _stopWatchdogs() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _safetyPollTimer?.cancel();
    _safetyPollTimer = null;
  }

  Future<void> _tick() async {
    final client = _client;
    final gameId = _gameId;
    if (client == null || gameId == null) return;
    try {
      final res = await client.rpc('fn_bingo_tick', params: {
        'p_game_id': gameId,
      });
      final data = (res as Map?)?.cast<String, dynamic>();
      if (data == null) return;
      // Merge the authoritative numbersCalled + lastCallAt straight in —
      // the realtime echo may arrive before/after, both carry full rows.
      final calledList = (data['numbersCalled'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          state.game?.numbersCalled;
      final rawLastCall = data['lastCallAt'];
      final lastCallAt = rawLastCall is String
          ? DateTime.tryParse(rawLastCall)
          : state.game?.lastCallAt;
      final status = data['status'] as String?;
      final game = state.game;
      if (game != null && calledList != null) {
        final nextGame = BingoGame(
          id: game.id,
          familyId: game.familyId,
          hostUserId: game.hostUserId,
          hostUserName: game.hostUserName,
          status: BingoStatusX.fromString(status),
          winPattern: game.winPattern,
          callIntervalSeconds: game.callIntervalSeconds,
          numbersCalled: calledList,
          winnerPlayerId: game.winnerPlayerId,
          winnerPlayerName: game.winnerPlayerName,
          maxPlayers: game.maxPlayers,
          lastCallAt: lastCallAt ?? game.lastCallAt,
          startedAt: game.startedAt,
          completedAt: game.completedAt,
          createdAt: game.createdAt,
        );
        final grew = calledList.length > game.numbersCalled.length;
        final completed = nextGame.isCompleted && !game.isCompleted;
        state = state.copyWith(game: nextGame);
        if (grew) GameMotionTokens.success();
        if (completed) {
          _stopWatchdogs();
          _scheduleRoomCleanup(game.id);
          // Winner info arrives via realtime; also refetch to be sure.
          unawaited(refreshGame());
        }
      }
    } catch (e) {
      // Transient network errors are fine — the 10 s poll covers them.
      debugPrint('[Bingo] tick error: $e');
    }
  }

  // ── Realtime subscription ────────────────────────────────────────

  void _subscribeToRealtime(String gameId) {
    _channel?.unsubscribe();
    final client = _client;
    if (client == null) return;

    _channel = client
        .channel('bingo_game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bingo_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            final updated = BingoGame.fromJson(payload.newRecord);
            // Detect new number called
            final oldNumbers = state.game?.numbersCalled ?? const [];
            if (updated.numbersCalled.length > oldNumbers.length) {
              GameMotionTokens.success();
            }
            // Detect transition to completed — schedule temporary-room
            // cleanup 30s later. fn_bingo_claim is authoritative for
            // marking the game completed; we just hook the realtime
            // transition to fire the cleanup Timer.
            final wasCompleted = state.game?.isCompleted ?? false;
            if (updated.isCompleted && !wasCompleted) {
              _stopWatchdogs();
              _scheduleRoomCleanup(updated.id);
            }
            state = state.copyWith(game: updated);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bingo_cards',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final updated = BingoCard.fromJson(payload.newRecord);
            final myId = _myId;
            // Update my card if it's mine
            if (updated.playerId == myId) {
              state = state.copyWith(myCard: updated);
            }
            // Update allCards list
            final next = state.allCards
                .map((c) => c.playerId == updated.playerId ? updated : c)
                .toList();
            state = state.copyWith(allCards: next);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'bingo_cards',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final newCard = BingoCard.fromJson(payload.newRecord);
            if (!state.allCards.any((c) => c.playerId == newCard.playerId)) {
              state = state.copyWith(allCards: [...state.allCards, newCard]);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'bingo_cards',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final oldRecord = payload.oldRecord;
            final playerId = oldRecord['playerId'] as String?;
            if (playerId == null) return;
            state = state.copyWith(
              allCards: state.allCards
                  .where((c) => c.playerId != playerId)
                  .toList(),
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'bingo_claims',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'gameId',
            value: gameId,
          ),
          callback: (payload) {
            final claim = BingoClaim.fromJson(payload.newRecord);
            state = state.copyWith(claims: [...state.claims, claim]);
          },
        )
        .subscribe((status, err) {
          // Reconnection: whenever the channel (re-)subscribes after the
          // initial attach, do a full authoritative refresh so numbers
          // missed while the socket was down are recovered instantly.
          if (status == RealtimeSubscribeStatus.subscribed) {
            if (_hasSubscribedOnce) {
              debugPrint('[Bingo] realtime re-subscribed → refetch');
              refreshGame();
            }
            _hasSubscribedOnce = true;
          } else if (status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            debugPrint('[Bingo] realtime dropped: $status');
          }
        });
  }

  bool _hasSubscribedOnce = false;

  Future<void> _refreshCards(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null) return;
    try {
      final resp = await client
          .from('bingo_cards')
          .select()
          .eq('gameId', gameId);
      final cards = resp.map(BingoCard.fromJson).toList();
      final myCard = cards.where((c) => c.playerId == myId).firstOrNull;
      state = state.copyWith(
        allCards: cards,
        myCard: myCard,
        // If I genuinely have no card mid-game I'm a spectator.
        amSpectator: myCard == null && state.game?.isInProgress == true
            ? true
            : (myCard == null ? state.amSpectator : false),
      );
    } catch (e) {
      debugPrint('[Bingo] refreshCards error: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopWatchdogs();
    _channel?.unsubscribe();
    super.dispose();
  }
}

final bingoProvider = StateNotifierProvider.autoDispose
    .family<BingoNotifier, BingoState, String>(
  (ref, familyId) => BingoNotifier(ref, familyId),
);
