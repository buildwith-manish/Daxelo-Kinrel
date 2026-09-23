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

  // ── toJson / fromJson round-trip tests ─────────────────────────────
  //
  // These verify that the cache layer's serialization preserves all
  // fields. If a new field is added to a model and not included in
  // toJson, the corresponding round-trip test will fail with a
  // mismatch.

  group('PBv1Question toJson/fromJson round-trip', () {
    test('preserves all fields', () {
      final q = PBv1Question(
        id: 'pq-001',
        questionText: 'How many?',
        correctAnswer: 42,
        unitLabel: 'units',
        category: 'general',
        funFactText: 'A fact',
        minBound: 10,
        maxBound: 100,
        isActive: true,
      );
      final json = q.toJson();
      final back = PBv1Question.fromJson(json);
      expect(back.id, q.id);
      expect(back.questionText, q.questionText);
      expect(back.correctAnswer, q.correctAnswer);
      expect(back.unitLabel, q.unitLabel);
      expect(back.category, q.category);
      expect(back.funFactText, q.funFactText);
      expect(back.minBound, q.minBound);
      expect(back.maxBound, q.maxBound);
      expect(back.isActive, q.isActive);
    });

    test('preserves nullable bounds as null', () {
      final q = PBv1Question(
        id: 'pq-002',
        questionText: '?',
        correctAnswer: 0,
        unitLabel: '',
        category: 'general',
      );
      final json = q.toJson();
      final back = PBv1Question.fromJson(json);
      expect(back.minBound, isNull);
      expect(back.maxBound, isNull);
    });
  });

  group('PBv1Round toJson/fromJson round-trip', () {
    test('preserves all fields', () {
      final r = PBv1Round(
        id: 'r-1',
        familyId: 'fam-1',
        questionId: 'q-1',
        opensAt: DateTime.utc(2026, 9, 22, 2, 30),
        revealAt: DateTime.utc(2026, 9, 22, 15, 30),
        status: 'open',
        createdAt: DateTime.utc(2026, 9, 22, 2, 30),
      );
      final json = r.toJson();
      final back = PBv1Round.fromJson(json);
      expect(back.id, r.id);
      expect(back.familyId, r.familyId);
      expect(back.questionId, r.questionId);
      expect(back.opensAt.toUtc(), r.opensAt.toUtc());
      expect(back.revealAt.toUtc(), r.revealAt.toUtc());
      expect(back.status, r.status);
      expect(back.createdAt.toUtc(), r.createdAt.toUtc());
    });
  });

  group('PBv1Guess toJson/fromJson round-trip', () {
    test('preserves required fields (distance omitted)', () {
      final g = PBv1Guess(
        userId: 'u-1',
        guessValue: 42.5,
        submittedAt: DateTime.utc(2026, 9, 22, 12, 0),
      );
      final json = g.toJson();
      final back = PBv1Guess.fromJson(json);
      expect(back.userId, g.userId);
      expect(back.guessValue, g.guessValue);
      expect(back.submittedAt.toUtc(), g.submittedAt.toUtc());
      expect(back.distance, isNull);
    });

    test('preserves optional distance', () {
      final g = PBv1Guess(
        userId: 'u-1',
        guessValue: 42,
        submittedAt: DateTime.utc(2026, 9, 22, 12, 0),
        distance: 5.5,
      );
      final json = g.toJson();
      final back = PBv1Guess.fromJson(json);
      expect(back.distance, 5.5);
    });
  });
}
