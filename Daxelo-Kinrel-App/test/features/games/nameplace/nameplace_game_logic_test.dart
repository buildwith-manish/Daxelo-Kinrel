// test/features/games/nameplace/nameplace_game_logic_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/nameplace/nameplace_game_logic.dart';

void main() {
  group('scoreRound — fully unique answers (everyone gets 10s)', () {
    test('all unique non-dash answers get 10 points', () {
      final answers = [
        NameplaceAnswer(playerId: 'p1', playerName: 'A', category: 'Name', answerText: 'Alice'),
        NameplaceAnswer(playerId: 'p2', playerName: 'B', category: 'Name', answerText: 'Bob'),
        NameplaceAnswer(playerId: 'p3', playerName: 'C', category: 'Name', answerText: 'Carol'),
        NameplaceAnswer(playerId: 'p4', playerName: 'D', category: 'Name', answerText: 'Dave'),
      ];

      final result = scoreRound(answers: answers, categories: ['Name']);

      for (final a in result.scoredAnswers) {
        expect(a.pointsAwarded, 10, reason: 'Unique answer should get 10 points');
      }
      expect(result.playerRoundScores['p1'], 10);
      expect(result.playerRoundScores['p2'], 10);
      expect(result.playerRoundScores['p3'], 10);
      expect(result.playerRoundScores['p4'], 10);
    });
  });

  group('scoreRound — fully duplicate answers (everyone gets 5s)', () {
    test('all same answer gets 5 points each', () {
      final answers = [
        NameplaceAnswer(playerId: 'p1', playerName: 'A', category: 'Name', answerText: 'Alice'),
        NameplaceAnswer(playerId: 'p2', playerName: 'B', category: 'Name', answerText: 'Alice'),
        NameplaceAnswer(playerId: 'p3', playerName: 'C', category: 'Name', answerText: 'Alice'),
        NameplaceAnswer(playerId: 'p4', playerName: 'D', category: 'Name', answerText: 'Alice'),
      ];

      final result = scoreRound(answers: answers, categories: ['Name']);

      for (final a in result.scoredAnswers) {
        expect(a.pointsAwarded, 5, reason: 'Duplicate answer should get 5 points');
      }
    });

    test('two pairs of duplicates get 5 each', () {
      final answers = [
        NameplaceAnswer(playerId: 'p1', playerName: 'A', category: 'Place', answerText: 'Paris'),
        NameplaceAnswer(playerId: 'p2', playerName: 'B', category: 'Place', answerText: 'Paris'),
        NameplaceAnswer(playerId: 'p3', playerName: 'C', category: 'Place', answerText: 'Pune'),
        NameplaceAnswer(playerId: 'p4', playerName: 'D', category: 'Place', answerText: 'Pune'),
      ];

      final result = scoreRound(answers: answers, categories: ['Place']);

      for (final a in result.scoredAnswers) {
        expect(a.pointsAwarded, 5);
      }
    });
  });

  group('scoreRound — mixed unique and duplicate', () {
    test('unique gets 10, duplicates get 5, in same category', () {
      final answers = [
        NameplaceAnswer(playerId: 'p1', playerName: 'A', category: 'Animal', answerText: 'Ant'),
        NameplaceAnswer(playerId: 'p2', playerName: 'B', category: 'Animal', answerText: 'Ant'),
        NameplaceAnswer(playerId: 'p3', playerName: 'C', category: 'Animal', answerText: 'Ape'),
        NameplaceAnswer(playerId: 'p4', playerName: 'D', category: 'Animal', answerText: 'Alligator'),
      ];

      final result = scoreRound(answers: answers, categories: ['Animal']);

      // p1 and p2 have duplicate "ant" → 5 each
      expect(result.scoredAnswers.firstWhere((a) => a.playerId == 'p1').pointsAwarded, 5);
      expect(result.scoredAnswers.firstWhere((a) => a.playerId == 'p2').pointsAwarded, 5);
      // p3 "ape" is unique → 10
      expect(result.scoredAnswers.firstWhere((a) => a.playerId == 'p3').pointsAwarded, 10);
      // p4 "alligator" is unique → 10
      expect(result.scoredAnswers.firstWhere((a) => a.playerId == 'p4').pointsAwarded, 10);
    });

    test('multi-category scoring sums correctly', () {
      final answers = [
        NameplaceAnswer(playerId: 'p1', playerName: 'A', category: 'Name', answerText: 'Alice'),
        NameplaceAnswer(playerId: 'p1', playerName: 'A', category: 'Place', answerText: 'Paris'),
        NameplaceAnswer(playerId: 'p2', playerName: 'B', category: 'Name', answerText: 'Alice'),
        NameplaceAnswer(playerId: 'p2', playerName: 'B', category: 'Place', answerText: 'Pune'),
      ];

      final result = scoreRound(answers: answers, categories: ['Name', 'Place']);

      // p1: Name "Alice" = 5 (dup with p2), Place "Paris" = 10 (unique) → total 15
      expect(result.playerRoundScores['p1'], 15);
      // p2: Name "Alice" = 5 (dup with p1), Place "Pune" = 10 (unique) → total 15
      expect(result.playerRoundScores['p2'], 15);
    });
  });

  group('scoreRound — all dash answers (everyone gets 0)', () {
    test('all dashes get 0 points', () {
      final answers = [
        NameplaceAnswer(playerId: 'p1', playerName: 'A', category: 'Thing', answerText: '-'),
        NameplaceAnswer(playerId: 'p2', playerName: 'B', category: 'Thing', answerText: '-'),
        NameplaceAnswer(playerId: 'p3', playerName: 'C', category: 'Thing', answerText: '-'),
      ];

      final result = scoreRound(answers: answers, categories: ['Thing']);

      for (final a in result.scoredAnswers) {
        expect(a.pointsAwarded, 0, reason: 'Dash should get 0 points');
      }
      expect(result.playerRoundScores['p1'], 0);
      expect(result.playerRoundScores['p2'], 0);
      expect(result.playerRoundScores['p3'], 0);
    });

    test('mix of dash and non-dash in same category', () {
      final answers = [
        NameplaceAnswer(playerId: 'p1', playerName: 'A', category: 'Movie', answerText: 'Avatar'),
        NameplaceAnswer(playerId: 'p2', playerName: 'B', category: 'Movie', answerText: '-'),
        NameplaceAnswer(playerId: 'p3', playerName: 'C', category: 'Movie', answerText: 'Avatar'),
      ];

      final result = scoreRound(answers: answers, categories: ['Movie']);

      // p1 and p3 both said "Avatar" → 5 each (duplicate)
      expect(result.scoredAnswers.firstWhere((a) => a.playerId == 'p1').pointsAwarded, 5);
      expect(result.scoredAnswers.firstWhere((a) => a.playerId == 'p3').pointsAwarded, 5);
      // p2 dashed → 0
      expect(result.scoredAnswers.firstWhere((a) => a.playerId == 'p2').pointsAwarded, 0);
    });
  });

  group('scoreRound — case-insensitive normalization', () {
    test('same answer in different cases is treated as duplicate', () {
      final answers = [
        NameplaceAnswer(playerId: 'p1', playerName: 'A', category: 'Name', answerText: 'Alice'),
        NameplaceAnswer(playerId: 'p2', playerName: 'B', category: 'Name', answerText: 'alice'),
        NameplaceAnswer(playerId: 'p3', playerName: 'C', category: 'Name', answerText: 'ALICE'),
      ];

      final result = scoreRound(answers: answers, categories: ['Name']);

      for (final a in result.scoredAnswers) {
        expect(a.pointsAwarded, 5, reason: 'Different cases should be treated as duplicates');
      }
    });

    test('whitespace is trimmed before comparison', () {
      final answers = [
        NameplaceAnswer(playerId: 'p1', playerName: 'A', category: 'Place', answerText: ' Paris '),
        NameplaceAnswer(playerId: 'p2', playerName: 'B', category: 'Place', answerText: 'Paris'),
      ];

      final result = scoreRound(answers: answers, categories: ['Place']);

      expect(result.scoredAnswers.firstWhere((a) => a.playerId == 'p1').pointsAwarded, 5);
      expect(result.scoredAnswers.firstWhere((a) => a.playerId == 'p2').pointsAwarded, 5);
    });
  });

  group('validateAnswers', () {
    test('returns null when all categories filled', () {
      final answers = {'Name': 'Alice', 'Place': 'Paris', 'Animal': 'Ant', 'Thing': 'Apple', 'Movie': 'Avatar'};
      expect(validateAnswers(answersByCategory: answers, categories: defaultCategories), isNull);
    });

    test('returns error when a category is empty', () {
      final answers = {'Name': 'Alice', 'Place': '', 'Animal': 'Ant', 'Thing': 'Apple', 'Movie': 'Avatar'};
      expect(validateAnswers(answersByCategory: answers, categories: defaultCategories), isNotNull);
    });

    test('returns null when a category has a dash', () {
      final answers = {'Name': 'Alice', 'Place': '-', 'Animal': 'Ant', 'Thing': 'Apple', 'Movie': '-'};
      expect(validateAnswers(answersByCategory: answers, categories: defaultCategories), isNull);
    });
  });

  group('nextLetterChooserId', () {
    test('rotates through players in turn order', () {
      final playerIds = ['p1', 'p2', 'p3', 'p4'];
      expect(nextLetterChooserId(playerIdsInOrder: playerIds, roundNumber: 1), 'p1');
      expect(nextLetterChooserId(playerIdsInOrder: playerIds, roundNumber: 2), 'p2');
      expect(nextLetterChooserId(playerIdsInOrder: playerIds, roundNumber: 3), 'p3');
      expect(nextLetterChooserId(playerIdsInOrder: playerIds, roundNumber: 4), 'p4');
      expect(nextLetterChooserId(playerIdsInOrder: playerIds, roundNumber: 5), 'p1'); // wraps
    });
  });

  group('computeFinalScores', () {
    test('single winner', () {
      final scores = {'p1': 50, 'p2': 30, 'p3': 40};
      final result = computeFinalScores(playerTotalScores: scores);
      expect(result.winnerIds, ['p1']);
      expect(result.finalScores['p1'], 50);
    });

    test('tied winners', () {
      final scores = {'p1': 40, 'p2': 40, 'p3': 30};
      final result = computeFinalScores(playerTotalScores: scores);
      expect(result.winnerIds.length, 2);
      expect(result.winnerIds.contains('p1'), true);
      expect(result.winnerIds.contains('p2'), true);
    });

    test('all tied', () {
      final scores = {'p1': 30, 'p2': 30, 'p3': 30};
      final result = computeFinalScores(playerTotalScores: scores);
      expect(result.winnerIds.length, 3);
    });
  });
}
