// lib/features/games/twotruths/twotruths_game_logic.dart
//
// Pure Two Truths and a Lie logic — no Flutter deps, testable.
// Scoring: correct guess = 1pt for guesser. Each fooled player = 1pt for submitter.

/// Validate that 3 statements are non-empty.
String? validateStatements(String s1, String s2, String s3) {
  if (s1.trim().isEmpty) return 'Statement 1 is empty';
  if (s2.trim().isEmpty) return 'Statement 2 is empty';
  if (s3.trim().isEmpty) return 'Statement 3 is empty';
  return null;
}

/// The result of scoring a round.
class RoundScoreResult {
  RoundScoreResult({required this.guesserScores, required this.submitterScore});
  /// Map of guesserId → points earned this round (0 or 1).
  final Map<String, int> guesserScores;
  /// Points earned by the submitter (1 per fooled player).
  final int submitterScore;
}

/// Score a round: given all guesses and the actual lie index, compute points.
///
/// [guesses] — map of guesserId → guessed lie index (1/2/3)
/// [actualLieIndex] — the actual lie index (1/2/3)
/// [guesserIds] — all player IDs who are guessing (excludes submitter)
/// [submitterId] — the submitting player's ID
RoundScoreResult scoreRound({
  required Map<String, int> guesses,
  required int actualLieIndex,
  required List<String> guesserIds,
  required String submitterId,
}) {
  final guesserScores = <String, int>{};
  int fooledCount = 0;

  for (final guesserId in guesserIds) {
    final guessed = guesses[guesserId];
    if (guessed != null && guessed == actualLieIndex) {
      guesserScores[guesserId] = 1; // correct guess
    } else {
      guesserScores[guesserId] = 0; // wrong or no guess
      fooledCount++; // submitter fooled this player
    }
  }

  return RoundScoreResult(
    guesserScores: guesserScores,
    submitterScore: fooledCount,
  );
}

/// Determine the next submitter in turn order.
String nextSubmitterId({
  required List<String> playerIdsInOrder,
  required int roundNumber,
}) {
  if (playerIdsInOrder.isEmpty) return '';
  final index = (roundNumber - 1) % playerIdsInOrder.length;
  return playerIdsInOrder[index];
}

/// Compute final scores and winners (including ties).
class FinalResult {
  FinalResult({required this.finalScores, required this.winnerIds});
  final Map<String, int> finalScores;
  final List<String> winnerIds;
}

FinalResult computeFinalScores(Map<String, int> playerTotalScores) {
  if (playerTotalScores.isEmpty) return FinalResult(finalScores: {}, winnerIds: []);
  final maxScore = playerTotalScores.values.reduce((a, b) => a > b ? a : b);
  final winners = playerTotalScores.entries.where((e) => e.value == maxScore).map((e) => e.key).toList();
  return FinalResult(finalScores: Map.from(playerTotalScores), winnerIds: winners);
}

/// Fallback AI lie generator (templated, no external API needed).
/// In AI-lie mode, if no LLM API is configured, this generates a plausible
/// statement based on the two true statements.
String generateFallbackAiLie(String truth1, String truth2) {
  final templates = [
    'I once met someone famous while traveling.',
    'I have a hidden talent that most people don\'t know about.',
    'I once won a competition in something unexpected.',
    'I have a phobia that might surprise you.',
    'I once accidentally did something that went viral.',
    'I have a unusual hobby I don\'t talk about much.',
    'I once made a bet with a friend and lost in a funny way.',
    'I have a memorable story from my childhood that sounds made up.',
  ];
  final rng = DateTime.now().millisecondsSinceEpoch;
  return templates[rng % templates.length];
}
