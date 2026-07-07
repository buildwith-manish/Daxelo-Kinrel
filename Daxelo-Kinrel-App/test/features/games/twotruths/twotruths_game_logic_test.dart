// test/features/games/twotruths/twotruths_game_logic_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/twotruths/twotruths_game_logic.dart';

void main() {
  group('validateStatements', () {
    test('returns null when all 3 non-empty', () {
      expect(validateStatements('a', 'b', 'c'), isNull);
    });
    test('returns error when one is empty', () {
      expect(validateStatements('a', '', 'c'), isNotNull);
      expect(validateStatements('', 'b', 'c'), isNotNull);
      expect(validateStatements('a', 'b', ''), isNotNull);
    });
  });

  group('scoreRound — player-authored mode', () {
    test('all guessers correct: each gets 1pt, submitter gets 0', () {
      final result = scoreRound(guesses: {'p2': 2, 'p3': 2, 'p4': 2}, actualLieIndex: 2, guesserIds: ['p2', 'p3', 'p4'], submitterId: 'p1');
      expect(result.guesserScores['p2'], 1);
      expect(result.guesserScores['p3'], 1);
      expect(result.guesserScores['p4'], 1);
      expect(result.submitterScore, 0); // nobody fooled
    });

    test('all guessers wrong: each gets 0pt, submitter gets 3pt', () {
      final result = scoreRound(guesses: {'p2': 1, 'p3': 1, 'p4': 3}, actualLieIndex: 2, guesserIds: ['p2', 'p3', 'p4'], submitterId: 'p1');
      expect(result.guesserScores['p2'], 0);
      expect(result.guesserScores['p3'], 0);
      expect(result.guesserScores['p4'], 0);
      expect(result.submitterScore, 3); // fooled all 3
    });

    test('mixed: 1 correct, 2 wrong', () {
      final result = scoreRound(guesses: {'p2': 2, 'p3': 1, 'p4': 3}, actualLieIndex: 2, guesserIds: ['p2', 'p3', 'p4'], submitterId: 'p1');
      expect(result.guesserScores['p2'], 1); // correct
      expect(result.guesserScores['p3'], 0); // wrong
      expect(result.guesserScores['p4'], 0); // wrong
      expect(result.submitterScore, 2); // fooled 2
    });

    test('guesser with no guess counts as wrong (fooled)', () {
      final result = scoreRound(guesses: {'p2': 2}, actualLieIndex: 2, guesserIds: ['p2', 'p3', 'p4'], submitterId: 'p1');
      expect(result.guesserScores['p2'], 1); // correct
      expect(result.guesserScores['p3'], 0); // no guess = wrong
      expect(result.guesserScores['p4'], 0); // no guess = wrong
      expect(result.submitterScore, 2); // fooled 2 who didn't guess
    });
  });

  group('scoreRound — AI-lie mode (lie is always index 3)', () {
    test('same scoring logic applies', () {
      final result = scoreRound(guesses: {'p2': 3, 'p3': 1, 'p4': 2}, actualLieIndex: 3, guesserIds: ['p2', 'p3', 'p4'], submitterId: 'p1');
      expect(result.guesserScores['p2'], 1); // correct (guessed 3)
      expect(result.guesserScores['p3'], 0); // wrong
      expect(result.guesserScores['p4'], 0); // wrong
      expect(result.submitterScore, 2);
    });
  });

  group('nextSubmitterId', () {
    test('rotates through players', () {
      final ids = ['p1', 'p2', 'p3', 'p4'];
      expect(nextSubmitterId(playerIdsInOrder: ids, roundNumber: 1), 'p1');
      expect(nextSubmitterId(playerIdsInOrder: ids, roundNumber: 2), 'p2');
      expect(nextSubmitterId(playerIdsInOrder: ids, roundNumber: 3), 'p3');
      expect(nextSubmitterId(playerIdsInOrder: ids, roundNumber: 4), 'p4');
      expect(nextSubmitterId(playerIdsInOrder: ids, roundNumber: 5), 'p1'); // wraps
    });
  });

  group('computeFinalScores', () {
    test('single winner', () {
      final result = computeFinalScores({'p1': 5, 'p2': 3, 'p3': 4});
      expect(result.winnerIds, ['p1']);
    });
    test('tied winners', () {
      final result = computeFinalScores({'p1': 4, 'p2': 4, 'p3': 3});
      expect(result.winnerIds.length, 2);
      expect(result.winnerIds.contains('p1'), true);
      expect(result.winnerIds.contains('p2'), true);
    });
  });

  group('generateFallbackAiLie', () {
    test('returns a non-empty string', () {
      final lie = generateFallbackAiLie('I love pizza', 'I have a dog');
      expect(lie.isNotEmpty, true);
    });
  });

  group('blind-guess integrity', () {
    // This is enforced by RLS (guesses only visible to own guesser until resolved)
    // Here we verify the scoring logic doesn't depend on seeing others' guesses
    test('scoring works with only own guess visible', () {
      // Simulate: I only know my own guess (p2 guessed 2). The actual lie is 2.
      // The scoring function receives ALL guesses but the client doesn't see them.
      final result = scoreRound(guesses: {'p2': 2}, actualLieIndex: 2, guesserIds: ['p2', 'p3', 'p4'], submitterId: 'p1');
      expect(result.guesserScores['p2'], 1); // I was correct
      // p3 and p4 didn't guess (their guesses aren't in the map) → they're wrong
      expect(result.guesserScores['p3'], 0);
      expect(result.guesserScores['p4'], 0);
    });
  });
}
