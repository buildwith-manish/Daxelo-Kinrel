// lib/features/games/truthordare/truthordare_selection_logic.dart
//
// Pure Dart logic for Truth or Dare — spin selection, anti-repeat weighting,
// prompt selection. No Flutter deps, fully testable.

import 'dart:math' as math;

/// Select a player for the bottle to land on.
/// Never selects the spinner. Uses anti-repeat weighting: players who've been
/// selected more times get a lower probability.
///
/// [players] — list of (userId, timesSelected) for all players in the game
/// [spinnerId] — the current spinner (excluded from selection)
/// [random] — injectable for testing
///
/// Returns the selected userId, or null if no valid players.
String? selectPlayer({
  required List<({String userId, int timesSelected})> players,
  required String spinnerId,
  math.Random? random,
}) {
  final rng = random ?? math.Random();

  // Exclude the spinner
  final candidates = players.where((p) => p.userId != spinnerId).toList();
  if (candidates.isEmpty) return null;

  // Weight: players with fewer selections get higher weight
  // weight = (maxTimesSelected + 1) - timesSelected
  // This ensures a player with 0 selections has the highest weight,
  // and a player with max selections has weight 1 (still possible, just less likely)
  final maxTimes = candidates.fold<int>(0, (max, p) => p.timesSelected > max ? p.timesSelected : max);
  final weights = candidates.map((p) => (maxTimes + 1 - p.timesSelected).toDouble()).toList();
  final totalWeight = weights.reduce((a, b) => a + b);

  // Weighted random selection
  final roll = rng.nextDouble() * totalWeight;
  double cumulative = 0;
  for (int i = 0; i < candidates.length; i++) {
    cumulative += weights[i];
    if (roll <= cumulative) {
      return candidates[i].userId;
    }
  }
  return candidates.last.userId; // fallback
}

/// Select a random approved prompt, avoiding repeats within the session.
///
/// [prompts] — list of prompt IDs that are approved
/// [usedPromptIds] — set of prompt IDs already used this session
/// [random] — injectable for testing
///
/// Returns a prompt ID, or null if the approved pool is empty.
/// If all prompts have been used, the pool resets (allows repeats).
String? selectPrompt({
  required List<String> promptIds,
  required Set<String> usedPromptIds,
  math.Random? random,
}) {
  if (promptIds.isEmpty) return null;
  final rng = random ?? math.Random();

  // Filter out used prompts
  var available = promptIds.where((id) => !usedPromptIds.contains(id)).toList();

  // If all used, reset the pool (allow repeats)
  if (available.isEmpty) {
    available = List<String>.from(promptIds);
  }

  return available[rng.nextInt(available.length)];
}

/// Simple profanity filter — flags prompts containing known bad words.
/// Returns true if the prompt should be flagged for review attention.
/// Does NOT auto-reject; the admin makes the final call.
bool flagPrompt(String text) {
  final lower = text.toLowerCase();
  const badWords = [
    'fuck', 'shit', 'bitch', 'asshole', 'dick', 'pussy', 'cunt', 'bastard',
    'slut', 'whore', 'nigger', 'faggot', 'retard', 'rape', 'molest',
  ];
  for (final word in badWords) {
    if (lower.contains(word)) return true;
  }
  return false;
}

/// Seed prompts for a new family — family-friendly starter set.
/// These are pre-approved so the game is playable immediately.
const List<({String category, String text})> seedPrompts = [
  (category: 'truth', text: 'What is your most embarrassing childhood memory?'),
  (category: 'truth', text: 'What is a secret talent nobody here knows about?'),
  (category: 'truth', text: 'What is the nicest thing someone has done for you?'),
  (category: 'truth', text: 'If you could swap lives with anyone here for a day, who would it be?'),
  (category: 'truth', text: 'What is your biggest fear?'),
  (category: 'truth', text: 'What is the most adventurous thing you have ever done?'),
  (category: 'dare', text: 'Sing the chorus of your favorite song.'),
  (category: 'dare', text: 'Do your best impression of someone in the room.'),
  (category: 'dare', text: 'Speak in an accent for the next 3 rounds.'),
  (category: 'dare', text: 'Tell a joke. If nobody laughs, do 5 squats.'),
  (category: 'dare', text: 'Do a dance move for 10 seconds.'),
  (category: 'dare', text: 'Compliment everyone in the room genuinely.'),
];
