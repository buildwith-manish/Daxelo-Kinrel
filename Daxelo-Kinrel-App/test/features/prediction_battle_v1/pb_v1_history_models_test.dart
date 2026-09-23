// test/features/prediction_battle_v1/pb_v1_history_models_test.dart
//
// Unit tests for the history models. Verifies fromJson/toJson round-
// trips preserve all fields, including the edge cases the cache
// layer depends on:
//   - empty streak (no row in pb_v1_win_streaks yet)
//   - null myGuess (user missed the round)
//   - i_won flag (single winner vs tied winner list)

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/prediction_battle_v1/pb_v1_history_models.dart';

void main() {
  group('PBv1Streak', () {
    test('fromJson accepts both camelCase and snake_case keys', () {
      final fromCamel = PBv1Streak.fromJson({
        'currentStreak': 3,
        'bestStreak': 7,
        'updatedAt': '2026-09-23T15:30:00.000Z',
      });
      expect(fromCamel.currentStreak, 3);
      expect(fromCamel.bestStreak, 7);
      expect(fromCamel.updatedAt, isNotNull);

      final fromSnake = PBv1Streak.fromJson({
        'current_streak': 5,
        'best_streak': 12,
        'updated_at': '2026-09-23T15:30:00.000Z',
      });
      expect(fromSnake.currentStreak, 5);
      expect(fromSnake.bestStreak, 12);
    });

    test('fromJson defaults to 0/0/null when fields missing', () {
      final s = PBv1Streak.fromJson({});
      expect(s.currentStreak, 0);
      expect(s.bestStreak, 0);
      expect(s.updatedAt, isNull);
    });

    test('empty constant equals a zero-streak streak', () {
      expect(PBv1Streak.empty.currentStreak, 0);
      expect(PBv1Streak.empty.bestStreak, 0);
    });

    test('toJson round-trips through fromJson', () {
      final original = PBv1Streak(
        currentStreak: 4,
        bestStreak: 9,
        updatedAt: DateTime.utc(2026, 9, 23, 15, 30),
      );
      final json = original.toJson();
      final back = PBv1Streak.fromJson(json);
      expect(back.currentStreak, 4);
      expect(back.bestStreak, 9);
      expect(back.updatedAt?.toUtc(), original.updatedAt!.toUtc());
    });
  });

  group('PBv1HistoryGuess', () {
    test('fromJson handles snake_case keys', () {
      final g = PBv1HistoryGuess.fromJson({
        'guess_value': 42,
        'distance': 8,
      });
      expect(g.guessValue, 42);
      expect(g.distance, 8);
    });

    test('fromJson handles camelCase keys', () {
      final g = PBv1HistoryGuess.fromJson({
        'guessValue': 42.5,
        'distance': 0.5,
      });
      expect(g.guessValue, 42.5);
      expect(g.distance, 0.5);
    });

    test('toJson round-trips', () {
      final g = PBv1HistoryGuess(guessValue: 100, distance: 5);
      final back = PBv1HistoryGuess.fromJson(g.toJson());
      expect(back.guessValue, 100);
      expect(back.distance, 5);
    });
  });

  group('PBv1HistoryRound', () {
    final baseRoundJson = {
      'round_id': 'r-1',
      'question_id': 'pq-001',
      'opens_at': '2026-09-22T02:30:00.000Z',
      'reveal_at': '2026-09-22T15:30:00.000Z',
      'status': 'revealed',
      'question_text': 'How many X?',
      'correct_answer': 42,
      'unit_label': 'units',
      'category': 'general',
      'fun_fact_text': 'A fun fact',
      'winner_user_ids': ['u-1', 'u-2'],
      'total_guesses': 5,
      'i_won': true,
      'my_guess': {'guess_value': 42, 'distance': 0},
    };

    test('fromJson parses all fields correctly', () {
      final r = PBv1HistoryRound.fromJson(baseRoundJson);
      expect(r.roundId, 'r-1');
      expect(r.questionId, 'pq-001');
      expect(r.status, 'revealed');
      expect(r.questionText, 'How many X?');
      expect(r.correctAnswer, 42);
      expect(r.unitLabel, 'units');
      expect(r.category, 'general');
      expect(r.funFactText, 'A fun fact');
      expect(r.winnerUserIds, ['u-1', 'u-2']);
      expect(r.totalGuesses, 5);
      expect(r.iWon, isTrue);
      expect(r.myGuess, isNotNull);
      expect(r.myGuess!.guessValue, 42);
      expect(r.myGuess!.distance, 0);
    });

    test('missed getter returns true when myGuess is null', () {
      final json = Map<String, dynamic>.from(baseRoundJson);
      json['my_guess'] = null;
      final r = PBv1HistoryRound.fromJson(json);
      expect(r.missed, isTrue);
      expect(r.won, isFalse); // i_won also false in JSON, but missed takes precedence in display
    });

    test('won getter returns the i_won flag', () {
      final r = PBv1HistoryRound.fromJson(baseRoundJson);
      expect(r.won, isTrue);
    });

    test('handles empty winner_user_ids', () {
      final json = Map<String, dynamic>.from(baseRoundJson);
      json['winner_user_ids'] = <String>[];
      final r = PBv1HistoryRound.fromJson(json);
      expect(r.winnerUserIds, isEmpty);
    });

    test('toJson round-trips through fromJson', () {
      final original = PBv1HistoryRound.fromJson(baseRoundJson);
      final json = original.toJson();
      final back = PBv1HistoryRound.fromJson(json);
      expect(back.roundId, original.roundId);
      expect(back.questionText, original.questionText);
      expect(back.correctAnswer, original.correctAnswer);
      expect(back.winnerUserIds, original.winnerUserIds);
      expect(back.iWon, original.iWon);
      expect(back.myGuess?.guessValue, original.myGuess?.guessValue);
      expect(back.totalGuesses, original.totalGuesses);
    });
  });

  group('PBv1History', () {
    test('parses full RPC response shape', () {
      final json = {
        'ok': true,
        'streak': {
          'current_streak': 3,
          'best_streak': 7,
          'updated_at': '2026-09-23T15:30:00.000Z',
        },
        'rounds': [
          {
            'round_id': 'r-1',
            'question_id': 'pq-001',
            'opens_at': '2026-09-22T02:30:00.000Z',
            'reveal_at': '2026-09-22T15:30:00.000Z',
            'status': 'revealed',
            'question_text': 'Q1',
            'correct_answer': 10,
            'unit_label': 'u',
            'category': 'c',
            'fun_fact_text': '',
            'winner_user_ids': ['u-1'],
            'total_guesses': 3,
            'i_won': true,
            'my_guess': {'guess_value': 10, 'distance': 0},
          },
          {
            'round_id': 'r-2',
            'question_id': 'pq-002',
            'opens_at': '2026-09-21T02:30:00.000Z',
            'reveal_at': '2026-09-21T15:30:00.000Z',
            'status': 'revealed',
            'question_text': 'Q2',
            'correct_answer': 20,
            'unit_label': 'u',
            'category': 'c',
            'fun_fact_text': '',
            'winner_user_ids': ['u-2'],
            'total_guesses': 4,
            'i_won': false,
            'my_guess': null,
          },
        ],
        'cachedAt': '2026-09-23T16:00:00.000Z',
      };

      final h = PBv1History.fromJson(json);
      expect(h.streak.currentStreak, 3);
      expect(h.streak.bestStreak, 7);
      expect(h.rounds.length, 2);
      expect(h.rounds[0].roundId, 'r-1');
      expect(h.rounds[1].roundId, 'r-2');
    });

    test('quick stats compute correctly', () {
      final h = PBv1History(
        streak: const PBv1Streak(currentStreak: 2, bestStreak: 5),
        rounds: [
          PBv1HistoryRound(
            roundId: 'r-1',
            questionId: 'pq-001',
            opensAt: DateTime.utc(2026, 9, 22),
            revealAt: DateTime.utc(2026, 9, 22, 15, 30),
            status: 'revealed',
            questionText: 'Q1',
            correctAnswer: 10,
            unitLabel: 'u',
            category: 'c',
            funFactText: '',
            winnerUserIds: const ['u-me'],
            totalGuesses: 3,
            iWon: true,
            myGuess: const PBv1HistoryGuess(guessValue: 10, distance: 0),
          ),
          PBv1HistoryRound(
            roundId: 'r-2',
            questionId: 'pq-002',
            opensAt: DateTime.utc(2026, 9, 21),
            revealAt: DateTime.utc(2026, 9, 21, 15, 30),
            status: 'revealed',
            questionText: 'Q2',
            correctAnswer: 20,
            unitLabel: 'u',
            category: 'c',
            funFactText: '',
            winnerUserIds: const ['u-other'],
            totalGuesses: 4,
            iWon: false,
            myGuess: const PBv1HistoryGuess(guessValue: 22, distance: 2),
          ),
          PBv1HistoryRound(
            roundId: 'r-3',
            questionId: 'pq-003',
            opensAt: DateTime.utc(2026, 9, 20),
            revealAt: DateTime.utc(2026, 9, 20, 15, 30),
            status: 'revealed',
            questionText: 'Q3',
            correctAnswer: 30,
            unitLabel: 'u',
            category: 'c',
            funFactText: '',
            winnerUserIds: const ['u-other2'],
            totalGuesses: 2,
            iWon: false,
            myGuess: null, // missed
          ),
        ],
        cachedAt: '2026-09-23T16:00:00.000Z',
      );
      expect(h.winsCount, 1);
      expect(h.participatedCount, 2);
      expect(h.totalRounds, 3);
    });

    test('handles empty rounds array', () {
      final json = {
        'ok': true,
        'streak': {'current_streak': 0, 'best_streak': 0},
        'rounds': <Map<String, dynamic>>[],
        'cachedAt': '',
      };
      final h = PBv1History.fromJson(json);
      expect(h.rounds, isEmpty);
      expect(h.totalRounds, 0);
      expect(h.winsCount, 0);
      expect(h.participatedCount, 0);
    });

    test('toJson round-trips through fromJson', () {
      final original = PBv1History(
        streak: const PBv1Streak(currentStreak: 5, bestStreak: 10),
        rounds: [
          PBv1HistoryRound(
            roundId: 'r-1',
            questionId: 'pq-001',
            opensAt: DateTime.utc(2026, 9, 22),
            revealAt: DateTime.utc(2026, 9, 22, 15, 30),
            status: 'revealed',
            questionText: 'Q1',
            correctAnswer: 10,
            unitLabel: 'u',
            category: 'c',
            funFactText: '',
            winnerUserIds: const ['u-1'],
            totalGuesses: 3,
            iWon: true,
            myGuess: const PBv1HistoryGuess(guessValue: 10, distance: 0),
          ),
        ],
        cachedAt: '2026-09-23T16:00:00.000Z',
      );
      final back = PBv1History.fromJson(original.toJson());
      expect(back.streak.currentStreak, 5);
      expect(back.streak.bestStreak, 10);
      expect(back.rounds.length, 1);
      expect(back.rounds[0].roundId, 'r-1');
      expect(back.cachedAt, '2026-09-23T16:00:00.000Z');
    });
  });
}
