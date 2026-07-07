// lib/features/games/chitmatch/chitmatch_game_logic.dart
//
// Pure TripleMatch game logic — no Flutter dependencies, fully testable.
//
// Rules:
//   • 4-12 players, each submits a word → 3 identical chits per word
//   • All chits shuffled, 3 dealt per player
//   • Each round: all players select 1 chit to pass clockwise
//   • Passes resolve simultaneously: player N → player N+1 (mod count)
//   • First player with 3-of-a-kind wins; joint winners if simultaneous

import 'dart:math' as math;

/// A player in the game (logic layer, no DB coupling).
class ChitmatchPlayer {
  ChitmatchPlayer({
    required this.userId,
    required this.userName,
    required this.turnOrder,
    this.submittedWord,
    List<String>? hand,
    this.selectedChitIndex,
    this.hasWon = false,
  });

  final String userId;
  final String userName;
  final int turnOrder;
  final String? submittedWord;
  List<String> hand = []; // exactly 3 chit values (words)
  int? selectedChitIndex; // 0/1/2, null = not yet selected
  bool hasWon;

  /// Check if this player's hand is a 3-of-a-kind.
  bool get hasThreeOfAKind {
    if (hand.length != 3) return false;
    return hand[0] == hand[1] && hand[1] == hand[2];
  }

  ChitmatchPlayer copy() => ChitmatchPlayer(
    userId: userId,
    userName: userName,
    turnOrder: turnOrder,
    submittedWord: submittedWord,
    hand: List<String>.from(hand),
    selectedChitIndex: selectedChitIndex,
    hasWon: hasWon,
  );
}

/// Generate all chits for the game: 3 copies per player's submitted word.
/// Returns a flat list of chit values (strings).
List<String> generateChits(List<ChitmatchPlayer> players) {
  final chits = <String>[];
  for (final player in players) {
    if (player.submittedWord == null || player.submittedWord!.isEmpty) {
      throw StateError(
        'Player ${player.userName} has not submitted a word',
      );
    }
    for (int i = 0; i < 3; i++) {
      chits.add(player.submittedWord!);
    }
  }
  return chits;
}

/// Shuffle chits and deal 3 per player.
/// Uses a provided random seed for testability.
void dealChits(
  List<ChitmatchPlayer> players,
  List<String> chits, {
  math.Random? random,
}) {
  final rng = random ?? math.Random();
  final shuffled = List<String>.from(chits)..shuffle(rng);

  for (int i = 0; i < players.length; i++) {
    final start = i * 3;
    players[i].hand = shuffled.sublist(start, start + 3);
    players[i].selectedChitIndex = null;
  }
}

/// Auto-select a random chit for players who haven't selected.
void autoSelectUnselected(List<ChitmatchPlayer> players, {math.Random? random}) {
  final rng = random ?? math.Random();
  for (final player in players) {
    if (player.selectedChitIndex == null) {
      player.selectedChitIndex = rng.nextInt(3);
    }
  }
}

/// The result of resolving a single round.
class RoundResolution {
  RoundResolution({
    required this.updatedPlayers,
    required this.passes,
    required this.winners,
  });

  /// Players with updated hands after the pass.
  final List<ChitmatchPlayer> updatedPlayers;

  /// List of (fromUserId, toUserId, chitWord) for audit/display.
  final List<({String fromUserId, String toUserId, String chitWord})> passes;

  /// Players who achieved 3-of-a-kind this round (may be empty, one, or multiple).
  final List<ChitmatchPlayer> winners;
}

/// Resolve a single round of simultaneous passing.
///
/// For each player:
///   1. Remove the selected chit from their hand
///   2. Receive the chit from the player before them in turn order
///   3. Add the received chit to their hand
///
/// Direction: clockwise = player N passes TO player N+1 (mod count).
/// So player N RECEIVES from player N-1 (mod count).
///
/// All passes happen simultaneously — we collect all outgoing chits first,
/// then distribute them, so no player sees their new chit before passing.
RoundResolution resolveRound(List<ChitmatchPlayer> players) {
  if (players.isEmpty) {
    return RoundResolution(
      updatedPlayers: [],
      passes: [],
      winners: [],
    );
  }

  // Sort by turn order to ensure correct pass direction
  final sorted = List<ChitmatchPlayer>.from(players)
    ..sort((a, b) => a.turnOrder.compareTo(b.turnOrder));
  final count = sorted.length;

  // Collect outgoing chits: each player's selected chit
  // outgoingChits[i] = the chit that player i is passing TO player (i+1) % count
  final outgoingChits = <String>[];
  final passes = <({String fromUserId, String toUserId, String chitWord})>[];

  for (int i = 0; i < count; i++) {
    final player = sorted[i];
    final selectedIndex = player.selectedChitIndex ?? 0;
    final chit = player.hand[selectedIndex];
    outgoingChits.add(chit);

    final toIndex = (i + 1) % count;
    passes.add((
      fromUserId: player.userId,
      toUserId: sorted[toIndex].userId,
      chitWord: chit,
    ));
  }

  // Create updated players: remove selected chit, add received chit
  final updated = <ChitmatchPlayer>[];
  final winners = <ChitmatchPlayer>[];

  for (int i = 0; i < count; i++) {
    final player = sorted[i].copy();

    // Remove the selected chit
    final selectedIndex = player.selectedChitIndex ?? 0;
    player.hand.removeAt(selectedIndex);

    // Add the chit received from player (i - 1 + count) % count
    final fromIndex = (i - 1 + count) % count;
    player.hand.add(outgoingChits[fromIndex]);

    // Reset selection for next round
    player.selectedChitIndex = null;

    // Check for win
    if (player.hasThreeOfAKind) {
      player.hasWon = true;
      winners.add(player);
    }

    updated.add(player);
  }

  // Re-sort back to original order (by userId matching input order)
  final userIdOrder = {for (int i = 0; i < players.length; i++) players[i].userId: i};
  updated.sort((a, b) =>
    (userIdOrder[a.userId] ?? 0).compareTo(userIdOrder[b.userId] ?? 0));

  return RoundResolution(
    updatedPlayers: updated,
    passes: passes,
    winners: winners,
  );
}

/// Check if the game has winners after a round.
bool hasWinners(RoundResolution resolution) {
  return resolution.winners.isNotEmpty;
}

/// Get the list of winner user IDs.
List<String> getWinnerIds(RoundResolution resolution) {
  return resolution.winners.map((p) => p.userId).toList();
}

/// Validate that all players have valid hands (exactly 3 chits).
bool validateHands(List<ChitmatchPlayer> players) {
  return players.every((p) => p.hand.length == 3);
}
