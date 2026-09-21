// test/features/prediction_battle/prediction_models_test.dart
//
// Tests for the PredictionRound embedded-question parsing added in
// the locked-in-expand commit. Verifies that:
//   - PredictionRound.fromJson correctly consumes the `prediction_questions`
//     Postgres join key as the embedded question.
//   - PredictionRound.fromJson correctly consumes the rewritten `question`
//     key (the provider rewrites `prediction_questions` → `question` before
//     calling fromJson).
//   - When neither key is present, the embedded question is null and the
//     rest of the round parses normally.
//   - PredictionLeaderboardEntry.displayName falls back to a truncated
//     userId when userName is null/empty.
//   - PredictionLeaderboardEntry.copyWithUserName preserves all the
//     other fields.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/prediction_battle/prediction_models.dart';

void main() {
  group('PredictionRound.fromJson — embedded question parsing', () {
    test('parses the prediction_questions join key as the embedded question', () {
      final json = <String, dynamic>{
        'id': 'round-1',
        'familyId': 'fam-1',
        'questionId': 'pq-001',
        'status': 'resolved',
        'lockAt': '2026-09-21T16:00:00+00:00',
        'revealAt': '2026-09-21T16:00:00+00:00',
        'resolvedAt': '2026-09-21T16:01:00+00:00',
        'actualAnswer': '163',
        'winnerUserIds': ['user-a'],
        'results': <Map<String, dynamic>>[],
        'isLegendary': false,
        'createdAt': '2026-09-21T04:00:00+00:00',
        'prediction_questions': {
          'id': 'pq-001',
          'question': 'How many floors are in Burj Khalifa?',
          'type': 'closest',
          'category': 'geography',
          'correctAnswer': '163',
          'optionA': null,
          'optionB': null,
          'isLegendary': false,
          'isActive': true,
          'qualityScore': 90,
          'createdAt': '2026-09-19T14:00:00+00:00',
        },
      };
      final round = PredictionRound.fromJson(json);
      expect(round.id, 'round-1');
      expect(round.questionId, 'pq-001');
      expect(round.status, PredictionStatus.resolved);
      expect(round.actualAnswer, '163');
      expect(round.question, isNotNull);
      expect(round.question!.id, 'pq-001');
      expect(round.question!.question, 'How many floors are in Burj Khalifa?');
      expect(round.question!.type, PredictionType.closest);
      expect(round.question!.category, 'geography');
      expect(round.question!.correctAnswer, '163');
    });

    test('parses the rewritten question key (provider-side rewrite)', () {
      // The provider's _fetchRecentResults rewrites the
      // `prediction_questions` key to `question` before calling
      // fromJson. Verify fromJson handles both keys.
      final json = <String, dynamic>{
        'id': 'round-2',
        'familyId': 'fam-1',
        'questionId': 'pq-002',
        'status': 'resolved',
        'lockAt': '2026-09-20T16:00:00+00:00',
        'revealAt': '2026-09-20T16:00:00+00:00',
        'resolvedAt': '2026-09-20T16:01:00+00:00',
        'actualAnswer': '46',
        'winnerUserIds': <String>[],
        'results': <Map<String, dynamic>>[],
        'isLegendary': false,
        'createdAt': '2026-09-20T04:00:00+00:00',
        'question': {
          'id': 'pq-002',
          'question': 'How many countries drive on the left?',
          'type': 'closest',
          'category': 'geography',
          'correctAnswer': '46',
        },
      };
      final round = PredictionRound.fromJson(json);
      expect(round.question, isNotNull);
      expect(round.question!.question, 'How many countries drive on the left?');
      expect(round.question!.correctAnswer, '46');
    });

    test('embedded question is null when neither key is present', () {
      // Active round from fn_prediction_get_active RPC — the question
      // is returned separately (as a sibling `question` key at the top
      // level of the RPC response, not nested inside the round JSON).
      // The round JSON itself has no question data.
      final json = <String, dynamic>{
        'id': 'round-active',
        'familyId': 'fam-1',
        'questionId': 'pq-active',
        'status': 'open',
        'lockAt': '2026-09-21T16:00:00+00:00',
        'revealAt': '2026-09-22T04:00:00+00:00',
        'winnerUserIds': <String>[],
        'results': <Map<String, dynamic>>[],
        'isLegendary': false,
        'createdAt': '2026-09-21T04:00:00+00:00',
      };
      final round = PredictionRound.fromJson(json);
      expect(round.id, 'round-active');
      expect(round.questionId, 'pq-active');
      expect(round.question, isNull);
    });

    test('results list parses correctly with the embedded question', () {
      final json = <String, dynamic>{
        'id': 'round-3',
        'familyId': 'fam-1',
        'questionId': 'pq-003',
        'status': 'resolved',
        'lockAt': '2026-09-19T16:00:00+00:00',
        'revealAt': '2026-09-19T16:00:00+00:00',
        'resolvedAt': '2026-09-19T16:01:00+00:00',
        'actualAnswer': '206',
        'winnerUserIds': ['user-b'],
        'isLegendary': false,
        'createdAt': '2026-09-19T04:00:00+00:00',
        'prediction_questions': {
          'id': 'pq-003',
          'question': 'How many bones are in the adult human body?',
          'type': 'closest',
          'category': 'science',
          'correctAnswer': '206',
        },
        'results': [
          {
            'userId': 'user-b',
            'prediction': '205',
            'confidence': 'high',
            'correct': false,
            'distance': 1.0,
            'points': 7,
            'rank': 1,
          },
          {
            'userId': 'user-a',
            'prediction': '300',
            'confidence': 'low',
            'correct': false,
            'distance': 94.0,
            'points': 0,
            'rank': 2,
          },
        ],
      };
      final round = PredictionRound.fromJson(json);
      expect(round.results.length, 2);
      expect(round.results[0].userId, 'user-b');
      expect(round.results[0].prediction, '205');
      expect(round.results[0].confidence, PredictionConfidence.high);
      expect(round.results[0].points, 7);
      expect(round.results[0].rank, 1);
      expect(round.results[1].userId, 'user-a');
      expect(round.results[1].distance, 94.0);
      expect(round.question!.question, 'How many bones are in the adult human body?');
    });
  });

  group('PredictionLeaderboardEntry — displayName + copyWithUserName', () {
    test('displayName returns userName when set', () {
      final entry = PredictionLeaderboardEntry(
        userId: 'abc-123-def-456',
        points: 100,
        wins: 5,
        correctPredictions: 7,
        totalPredictions: 10,
        currentStreak: 3,
        bestStreak: 5,
        userName: 'Manish',
      );
      expect(entry.displayName, 'Manish');
    });

    test('displayName falls back to truncated userId when userName is null', () {
      final entry = PredictionLeaderboardEntry(
        userId: 'abc-123-def-456',
        points: 100,
        wins: 5,
        correctPredictions: 7,
        totalPredictions: 10,
        currentStreak: 3,
        bestStreak: 5,
        userName: null,
      );
      expect(entry.displayName, 'abc-123-');
    });

    test('displayName falls back to truncated userId when userName is empty', () {
      final entry = PredictionLeaderboardEntry(
        userId: 'abc-123-def-456',
        points: 100,
        wins: 5,
        correctPredictions: 7,
        totalPredictions: 10,
        currentStreak: 3,
        bestStreak: 5,
        userName: '',
      );
      expect(entry.displayName, 'abc-123-');
    });

    test('displayName handles short userIds (less than 8 chars)', () {
      final entry = PredictionLeaderboardEntry(
        userId: 'abc',
        points: 50,
        wins: 2,
        correctPredictions: 3,
        totalPredictions: 5,
        currentStreak: 1,
        bestStreak: 2,
        userName: null,
      );
      expect(entry.displayName, 'abc');
    });

    test('copyWithUserName preserves all other fields', () {
      final entry = PredictionLeaderboardEntry(
        userId: 'abc-123-def-456',
        points: 100,
        wins: 5,
        correctPredictions: 7,
        totalPredictions: 10,
        currentStreak: 3,
        bestStreak: 5,
        userName: null,
      );
      final updated = entry.copyWithUserName('Manish');
      expect(updated.userId, entry.userId);
      expect(updated.points, entry.points);
      expect(updated.wins, entry.wins);
      expect(updated.correctPredictions, entry.correctPredictions);
      expect(updated.totalPredictions, entry.totalPredictions);
      expect(updated.currentStreak, entry.currentStreak);
      expect(updated.bestStreak, entry.bestStreak);
      expect(updated.userName, 'Manish');
      expect(updated.displayName, 'Manish');
    });

    test('accuracy getter computes correctly', () {
      final entry = PredictionLeaderboardEntry(
        userId: 'abc',
        points: 100,
        wins: 5,
        correctPredictions: 7,
        totalPredictions: 10,
        currentStreak: 3,
        bestStreak: 5,
      );
      expect(entry.accuracy, 0.7);
    });

    test('accuracy is 0 when totalPredictions is 0', () {
      final entry = PredictionLeaderboardEntry(
        userId: 'abc',
        points: 0,
        wins: 0,
        correctPredictions: 0,
        totalPredictions: 0,
        currentStreak: 0,
        bestStreak: 0,
      );
      expect(entry.accuracy, 0.0);
    });
  });
}
