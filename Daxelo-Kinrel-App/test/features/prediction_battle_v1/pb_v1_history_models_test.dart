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

  // ── Phase 3.4 — Leaderboard tests ────────────────────────────────

  group('PBv1LeaderboardEntry', () {
    test('fromJson accepts snake_case keys', () {
      final e = PBv1LeaderboardEntry.fromJson({
        'user_id': 'u-1',
        'current_streak': 5,
        'best_streak': 10,
        'total_wins_in_window': 3,
        'total_guesses_in_window': 8,
      });
      expect(e.userId, 'u-1');
      expect(e.currentStreak, 5);
      expect(e.bestStreak, 10);
      expect(e.totalWinsInWindow, 3);
      expect(e.totalGuessesInWindow, 8);
    });

    test('fromJson accepts camelCase keys', () {
      final e = PBv1LeaderboardEntry.fromJson({
        'userId': 'u-2',
        'currentStreak': 2,
        'bestStreak': 7,
        'totalWinsInWindow': 1,
        'totalGuessesInWindow': 4,
      });
      expect(e.userId, 'u-2');
      expect(e.currentStreak, 2);
      expect(e.bestStreak, 7);
    });

    test('fromJson defaults to zeros when fields missing', () {
      final e = PBv1LeaderboardEntry.fromJson({'user_id': 'u-3'});
      expect(e.userId, 'u-3');
      expect(e.currentStreak, 0);
      expect(e.bestStreak, 0);
      expect(e.totalWinsInWindow, 0);
      expect(e.totalGuessesInWindow, 0);
    });

    test('toJson round-trips through fromJson', () {
      final e = PBv1LeaderboardEntry(
        userId: 'u-4',
        currentStreak: 6,
        bestStreak: 12,
        totalWinsInWindow: 4,
        totalGuessesInWindow: 10,
      );
      final back = PBv1LeaderboardEntry.fromJson(e.toJson());
      expect(back.userId, 'u-4');
      expect(back.currentStreak, 6);
      expect(back.bestStreak, 12);
      expect(back.totalWinsInWindow, 4);
      expect(back.totalGuessesInWindow, 10);
    });

    test('windowWinRate returns 0 when no guesses in window', () {
      const e = PBv1LeaderboardEntry(
        userId: 'u-5',
        currentStreak: 0,
        bestStreak: 0,
        totalWinsInWindow: 0,
        totalGuessesInWindow: 0,
      );
      expect(e.windowWinRate, 0);
    });

    test('windowWinRate returns the correct fraction', () {
      const e = PBv1LeaderboardEntry(
        userId: 'u-6',
        currentStreak: 3,
        bestStreak: 5,
        totalWinsInWindow: 4,
        totalGuessesInWindow: 10,
      );
      expect(e.windowWinRate, 0.4);
    });

    test('windowWinRate is 1.0 when all guesses won', () {
      const e = PBv1LeaderboardEntry(
        userId: 'u-7',
        currentStreak: 5,
        bestStreak: 5,
        totalWinsInWindow: 5,
        totalGuessesInWindow: 5,
      );
      expect(e.windowWinRate, 1.0);
    });
  });

  group('PBv1History — leaderboard integration', () {
    test('parses leaderboard from RPC response', () {
      final json = {
        'ok': true,
        'streak': {'current_streak': 3, 'best_streak': 7},
        'rounds': <Map<String, dynamic>>[],
        'leaderboard': [
          {'user_id': 'u-1', 'current_streak': 5, 'best_streak': 10,
           'total_wins_in_window': 3, 'total_guesses_in_window': 8},
          {'user_id': 'u-2', 'current_streak': 2, 'best_streak': 4,
           'total_wins_in_window': 1, 'total_guesses_in_window': 5},
          {'user_id': 'u-3', 'current_streak': 0, 'best_streak': 1,
           'total_wins_in_window': 0, 'total_guesses_in_window': 2},
        ],
        'cachedAt': '2026-09-23T16:00:00.000Z',
      };
      final h = PBv1History.fromJson(json);
      expect(h.leaderboard.length, 3);
      expect(h.leaderboard[0].userId, 'u-1');
      expect(h.leaderboard[0].currentStreak, 5);
      expect(h.leaderboard[1].userId, 'u-2');
      expect(h.leaderboard[2].userId, 'u-3');
    });

    test('leaderboard defaults to empty list when field missing', () {
      // Simulates an old cache (pre-Phase 3.4) that doesn't have the
      // leaderboard field. The parser must not crash.
      final json = {
        'ok': true,
        'streak': {'current_streak': 0, 'best_streak': 0},
        'rounds': <Map<String, dynamic>>[],
        'cachedAt': '',
      };
      final h = PBv1History.fromJson(json);
      expect(h.leaderboard, isEmpty);
    });

    test('leaderboard survives toJson → fromJson round-trip', () {
      final original = PBv1History(
        streak: const PBv1Streak(currentStreak: 3, bestStreak: 7),
        rounds: const [],
        leaderboard: const [
          PBv1LeaderboardEntry(
            userId: 'u-1',
            currentStreak: 5,
            bestStreak: 10,
            totalWinsInWindow: 3,
            totalGuessesInWindow: 8,
          ),
        ],
        cachedAt: '2026-09-23T16:00:00.000Z',
      );
      final back = PBv1History.fromJson(original.toJson());
      expect(back.leaderboard.length, 1);
      expect(back.leaderboard[0].userId, 'u-1');
      expect(back.leaderboard[0].currentStreak, 5);
    });
  });
}
