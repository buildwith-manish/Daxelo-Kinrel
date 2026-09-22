// test/features/prediction_battle_v1/pb_v1_scoring_test.dart
//
// Unit tests for the Prediction Battle v1 scoring engine.
// Verifies:
//   - Percentage-based distance for correct_answer > 1000
//   - Absolute distance for correct_answer <= 1000
//   - Tie handling (equal distances = tied rank)
//   - rankGuesses sorts by distance (closest first)

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/prediction_battle_v1/pb_v1_models.dart';

void main() {
  group('PBv1Scoring.distance', () {
    test('uses absolute distance for correct_answer <= 1000', () {
      expect(PBv1Scoring.distance(100, 150), 50);
      expect(PBv1Scoring.distance(200, 150), 50);
      expect(PBv1Scoring.distance(0, 500), 500);
      expect(PBv1Scoring.distance(500, 500), 0);
    });

    test('uses percentage distance for correct_answer > 1000', () {
      expect(PBv1Scoring.distance(90000, 100000), closeTo(10.0, 0.01));
      expect(PBv1Scoring.distance(110000, 100000), closeTo(10.0, 0.01));
      expect(PBv1Scoring.distance(50000, 50000), 0);
    });

    test('handles boundary at exactly 1000', () {
      // At 1000, absolute distance is used
      expect(PBv1Scoring.distance(900, 1000), 100);
      // At 1001, percentage distance is used: |900 - 1001| / 1001 * 100
      expect(PBv1Scoring.distance(900, 1001), closeTo(10.0899, 0.01));
    });
  });

  group('PBv1Scoring.rankGuesses', () {
    test('sorts by distance (closest first)', () {
      final guesses = [
        PBv1Guess(userId: 'a', guessValue: 200, submittedAt: DateTime.now()),
        PBv1Guess(userId: 'b', guessValue: 150, submittedAt: DateTime.now()),
        PBv1Guess(userId: 'c', guessValue: 170, submittedAt: DateTime.now()),
      ];
      final ranked = PBv1Scoring.rankGuesses(guesses, 160);
      expect((ranked[0]['guess'] as PBv1Guess).userId, 'b');
      expect((ranked[1]['guess'] as PBv1Guess).userId, 'c');
      expect((ranked[2]['guess'] as PBv1Guess).userId, 'a');
    });

    test('handles ties (equal distances)', () {
      final guesses = [
        PBv1Guess(userId: 'a', guessValue: 150, submittedAt: DateTime.now()),
        PBv1Guess(userId: 'b', guessValue: 170, submittedAt: DateTime.now()),
      ];
      final ranked = PBv1Scoring.rankGuesses(guesses, 160);
      expect((ranked[0]['distance'] as double), 10);
      expect((ranked[1]['distance'] as double), 10);
    });

    test('works with percentage-based scoring for large numbers', () {
      final guesses = [
        PBv1Guess(userId: 'a', guessValue: 90000, submittedAt: DateTime.now()),
        PBv1Guess(userId: 'b', guessValue: 110000, submittedAt: DateTime.now()),
        PBv1Guess(userId: 'c', guessValue: 95000, submittedAt: DateTime.now()),
      ];
      final ranked = PBv1Scoring.rankGuesses(guesses, 100000);
      expect((ranked[0]['guess'] as PBv1Guess).userId, 'c');
      expect((ranked[0]['distance'] as double), closeTo(5.0, 0.01));
    });

    test('empty list returns empty', () {
      final ranked = PBv1Scoring.rankGuesses([], 100);
      expect(ranked, isEmpty);
    });
  });
}
