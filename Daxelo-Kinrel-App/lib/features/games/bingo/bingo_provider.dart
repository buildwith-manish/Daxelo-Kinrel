// lib/features/games/bingo/bingo_provider.dart
//
// Bingo — Riverpod state + Supabase Realtime + Edge Function calls.
//
// Architecture:
//   • Supabase stores games, cards, claims
//   • Supabase Realtime broadcasts called numbers + winner
//   • The bingo-caller Edge Function (cron-triggered) advances the
//     number sequence server-side — clients NEVER call numbers themselves
//   • The bingo-verify-claim Edge Function validates BINGO claims
//     server-side — clients NEVER decide if a claim is valid
//   • Card generation happens client-side (random) but the card is
//     persisted to Supabase so the server can verify wins against it

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env_config.dart';
import '../../../core/services/supabase_service.dart';
import '../game_motion_tokens.dart';
import '../shared/data/game_invite_chat_sync.dart';
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

  /// Check if the player's marked numbers (filtered to called numbers)
  /// satisfy the win pattern. This is a CLIENT-SIDE HINT for the UI —
  /// the actual win verification happens server-side via the Edge Function.
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
    String? error,
    bool clearError = false,
    bool? lastClaimValid,
    String? lastClaimReason,
    bool clearClaim = false,
  }) =>
      BingoState(
        game: game ?? this.game,
        myCard: myCard ?? this.myCard,
        allCards: allCards ?? this.allCards,
        claims: claims ?? this.claims,
        isLoading: isLoading ?? this.isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        isClaiming: isClaiming ?? this.isClaiming,
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
      final game = BingoGame.fromJson(resp as Map<String, dynamic>);
      _gameId = game.id;

      // Generate a card for the host immediately
      await _generateAndInsertCard(game.id, myId, _myName);

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

  /// Non-host: join an existing game.
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
          .from('bingo_games')
          .select()
          .eq('id', gameId)
          .single();
      final game = BingoGame.fromJson(gameResp as Map<String, dynamic>);
      _gameId = game.id;

      // Check max players
      final cardsResp = await client
          .from('bingo_cards')
          .select()
          .eq('gameId', gameId);
      if (cardsResp.length >= game.maxPlayers) {
        state = state.copyWith(
          isLoading: false,
          error: 'Game is full (${game.maxPlayers} players)',
        );
        return false;
      }

      // Generate a card for the new player (or fetch existing if re-joining)
      final existingCard = cardsResp
          .where((c) => c['playerId'] == myId)
          .firstOrNull;
      if (existingCard == null) {
        await _generateAndInsertCard(game.id, myId, _myName);
      }

      state = state.copyWith(game: game, isLoading: false);
      _subscribeToRealtime(gameId);
      await _refreshCards(gameId);
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

  Future<void> _generateAndInsertCard(
    String gameId,
    String playerId,
    String playerName,
  ) async {
    final client = _client;
    if (client == null) return;
    final cardNumbers = generateBingoCard();
    // Convert to JSON-friendly format (List<List<int?>>, null for free space)
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

  /// Host: start the game. Transitions to in_progress, which triggers
  /// the bingo-caller Edge Function to start calling numbers.
  Future<void> startGame() async {
    final client = _client;
    final gameId = _gameId;
    final game = state.game;
    if (client == null || gameId == null || game == null) return;

    if (state.allCards.length < 2) {
      state = state.copyWith(error: 'Need at least 2 players to start');
      return;
    }

    try {
      await client.from('bingo_games').update({
        'status': 'in_progress',
        'startedAt': DateTime.now().toIso8601String(),
        'lastCallAt': DateTime.now().toIso8601String(),
      }).eq('id', gameId);
      // The bingo-caller cron will pick this up and start calling numbers
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

  /// Player: claim BINGO! Triggers server-side verification.
  Future<bool> claimBingo() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    if (client == null || gameId == null || myId == null) return false;

    state = state.copyWith(isClaiming: true, clearClaim: true);
    try {
      // Call the bingo-verify-claim Edge Function
      final functionUrl =
          '${EnvConfig.apiBaseUrl}/functions/v1/bingo-verify-claim';
      final token = client.auth.currentSession?.accessToken;
      final response = await client.functions.invoke(
        'bingo-verify-claim',
        body: {
          'gameId': gameId,
          'playerId': myId,
        },
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      );

      final data = response.data as Map<String, dynamic>;
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

  /// Leave the game.
  Future<void> leaveGame() async {
    final client = _client;
    final gameId = _gameId;
    final myId = _myId;
    _channel?.unsubscribe();
    _channel = null;
    if (client == null || gameId == null || myId == null) {
      _gameId = null;
      return;
    }
    try {
      await client
          .from('bingo_cards')
          .delete()
          .eq('gameId', gameId)
          .eq('playerId', myId);
    } catch (_) {}
    _gameId = null;
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
        .subscribe();
  }

  Future<void> _refreshCards(String gameId) async {
    final client = _client;
    final myId = _myId;
    if (client == null) return;
    try {
      final resp = await client
          .from('bingo_cards')
          .select()
          .eq('gameId', gameId);
      final cards = resp
          .map((c) => BingoCard.fromJson(c as Map<String, dynamic>))
          .toList();
      final myCard = cards.where((c) => c.playerId == myId).firstOrNull;
      state = state.copyWith(allCards: cards, myCard: myCard);
    } catch (e) {
      debugPrint('[Bingo] refreshCards error: $e');
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

final bingoProvider = StateNotifierProvider.autoDispose
    .family<BingoNotifier, BingoState, String>(
  (ref, familyId) => BingoNotifier(ref, familyId),
);
