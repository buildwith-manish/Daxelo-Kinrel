// lib/features/games/nameplace/nameplace_game_logic.dart
//
// Pure Name-Place-Animal-Thing game logic — no Flutter deps, testable.
//
// Scoring per category per round:
//   • Unique answer (no other player gave the same normalized answer): 10 pts
//   • Duplicate answer (one+ other player gave the same): 5 pts each (all matching players get 5)
//   • Dash ("-"): 0 pts
// Round score = sum across categories; game score = sum across rounds.

/// A single player's answer for one category in one round.
class NameplaceAnswer {
  NameplaceAnswer({
    required this.playerId,
    required this.playerName,
    required this.category,
    required this.answerText,
    this.pointsAwarded,
  });

  final String playerId;
  final String playerName;
  final String category;
  final String answerText;
  int? pointsAwarded;

  bool get isDash => answerText.trim() == '-';

  /// Normalized answer for comparison (lowercase, trimmed).
  String get normalized => answerText.trim().toLowerCase();

  NameplaceAnswer copyWith({int? pointsAwarded}) => NameplaceAnswer(
    playerId: playerId,
    playerName: playerName,
    category: category,
    answerText: answerText,
    pointsAwarded: pointsAwarded ?? this.pointsAwarded,
  );
}

/// The result of scoring a single round.
class RoundScoreResult {
  RoundScoreResult({
    required this.scoredAnswers,
    required this.playerRoundScores,
  });

  /// All answers with pointsAwarded populated.
  final List<NameplaceAnswer> scoredAnswers;

  /// Map of playerId → round score.
  final Map<String, int> playerRoundScores;
}

/// Score a round: given all answers for all categories, compute points.
///
/// For each category:
///   1. Group non-dash answers by normalized text
///   2. Groups of size 1 → 10 points
///   3. Groups of size 2+ → 5 points each
///   4. Dashes → 0 points
RoundScoreResult scoreRound({
  required List<NameplaceAnswer> answers,
  required List<String> categories,
}) {
  final scored = <NameplaceAnswer>[];
  final playerScores = <String, int>{};

  for (final category in categories) {
    // Get all answers for this category
    final categoryAnswers = answers.where((a) => a.category == category).toList();

    // Group non-dash answers by normalized text
    final groups = <String, List<NameplaceAnswer>>{};
    for (final answer in categoryAnswers) {
      if (answer.isDash) {
        // Dashes get 0 — don't group them
        scored.add(answer.copyWith(pointsAwarded: 0));
        continue;
      }
      final key = answer.normalized;
      groups.putIfAbsent(key, () => []).add(answer);
    }

    // Score each group
    for (final entry in groups.entries) {
      final groupAnswers = entry.value;
      final points = groupAnswers.length == 1 ? 10 : 5;
      for (final answer in groupAnswers) {
        scored.add(answer.copyWith(pointsAwarded: points));
        playerScores[answer.playerId] =
            (playerScores[answer.playerId] ?? 0) + points;
      }
    }
  }

  // Ensure all players have a score entry (even if 0)
  for (final answer in answers) {
    playerScores.putIfAbsent(answer.playerId, 0);
  }

  return RoundScoreResult(
    scoredAnswers: scored,
    playerRoundScores: playerScores,
  );
}

/// Validate that all categories have either an answer or a dash.
/// Returns null if valid, or an error message.
String? validateAnswers({
  required Map<String, String> answersByCategory,
  required List<String> categories,
}) {
  for (final category in categories) {
    final answer = answersByCategory[category];
    if (answer == null || answer.trim().isEmpty) {
      return 'Please fill in "$category" or enter a dash (-)';
    }
  }
  return null;
}

/// Determine the next letter chooser.
/// Rotates in turn order: round 1 → player 0, round 2 → player 1, etc.
String nextLetterChooserId({
  required List<String> playerIdsInOrder,
  required int roundNumber,
}) {
  if (playerIdsInOrder.isEmpty) return '';
  final index = (roundNumber - 1) % playerIdsInOrder.length;
  return playerIdsInOrder[index];
}

/// Aggregate final scores and determine winners (including ties).
class FinalResult {
  FinalResult({
    required this.finalScores,
    required this.winnerIds,
  });

  /// Map of playerId → total score.
  final Map<String, int> finalScores;

  /// List of player IDs with the highest score (may be multiple if tied).
  final List<String> winnerIds;
}

FinalResult computeFinalScores({
  required Map<String, int> playerTotalScores,
}) {
  if (playerTotalScores.isEmpty) {
    return FinalResult(finalScores: {}, winnerIds: []);
  }

  final maxScore = playerTotalScores.values.reduce((a, b) => a > b ? a : b);
  final winners = playerTotalScores.entries
      .where((e) => e.value == maxScore)
      .map((e) => e.key)
      .toList();

  return FinalResult(
    finalScores: Map.from(playerTotalScores),
    winnerIds: winners,
  );
}

/// Default categories (configurable in game creation).
const List<String> defaultCategories = ['Name', 'Place', 'Animal', 'Thing', 'Movie'];

/// All valid letters for the letter-chooser to pick from.
const List<String> validLetters = [
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
];
