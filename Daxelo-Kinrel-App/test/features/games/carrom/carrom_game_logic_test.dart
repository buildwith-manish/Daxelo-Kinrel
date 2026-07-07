// test/features/games/carrom/carrom_game_logic_test.dart
//
// Basic tests for Carrom game logic — win condition and turn transition.
// Run with: flutter test test/features/games/carrom/carrom_game_logic_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/carrom/carrom_constants.dart';
import 'package:kinrel/features/games/carrom/carrom_game_logic.dart';

void main() {
  group('createInitialBoard', () {
    test('creates exactly 19 coins', () {
      final board = createInitialBoard();
      expect(board.length, 19);
    });

    test('has 1 queen at center', () {
      final board = createInitialBoard();
      final queens = board.where((c) => c.type == CarromCoinType.queen);
      expect(queens.length, 1);
      expect(queens.first.x, 0);
      expect(queens.first.y, 0);
    });

    test('has 9 white and 9 black coins', () {
      final board = createInitialBoard();
      final whites = board.where((c) => c.type == CarromCoinType.white);
      final blacks = board.where((c) => c.type == CarromCoinType.black);
      expect(whites.length, 9);
      expect(blacks.length, 9);
    });

    test('all coins start unpotted', () {
      final board = createInitialBoard();
      expect(board.every((c) => !c.isPotted), true);
    });
  });

  group('evaluateTurn - turn transitions', () {
    final playerOneId = 'player1';
    final playerTwoId = 'player2';

    test('potting own color grants extra turn', () {
      final board = createInitialBoard();
      final afterBoard = List<CarromCoin>.from(board);
      afterBoard[1] = afterBoard[1].copyWith(isPotted: true);

      final result = evaluateTurn(
        coinsBefore: board,
        coinsAfter: afterBoard,
        playerId: playerOneId,
        playerColor: CarromCoinType.white,
        opponentId: playerTwoId,
        opponentColor: CarromCoinType.black,
        queenStatusBefore: CarromQueenStatus.onBoard,
        queenPottedByBefore: null,
        strikerPotted: false,
        playerOneScore: 0,
        playerTwoScore: 0,
        playerOneId: playerOneId,
        playerTwoId: playerTwoId,
      );

      expect(result.wasFoul, false);
      expect(result.extraTurn, true);
      expect(result.nextPlayerId, playerOneId);
      expect(result.playerOneScoreDelta, 1);
    });

    test('potting opponent color passes turn', () {
      final board = createInitialBoard();
      final afterBoard = List<CarromCoin>.from(board);
      afterBoard[2] = afterBoard[2].copyWith(isPotted: true);

      final result = evaluateTurn(
        coinsBefore: board,
        coinsAfter: afterBoard,
        playerId: playerOneId,
        playerColor: CarromCoinType.white,
        opponentId: playerTwoId,
        opponentColor: CarromCoinType.black,
        queenStatusBefore: CarromQueenStatus.onBoard,
        queenPottedByBefore: null,
        strikerPotted: false,
        playerOneScore: 0,
        playerTwoScore: 0,
        playerOneId: playerOneId,
        playerTwoId: playerTwoId,
      );

      expect(result.wasFoul, false);
      expect(result.extraTurn, false);
      expect(result.nextPlayerId, playerTwoId);
    });

    test('no coins potted passes turn', () {
      final board = createInitialBoard();

      final result = evaluateTurn(
        coinsBefore: board,
        coinsAfter: board,
        playerId: playerOneId,
        playerColor: CarromCoinType.white,
        opponentId: playerTwoId,
        opponentColor: CarromCoinType.black,
        queenStatusBefore: CarromQueenStatus.onBoard,
        queenPottedByBefore: null,
        strikerPotted: false,
        playerOneScore: 0,
        playerTwoScore: 0,
        playerOneId: playerOneId,
        playerTwoId: playerTwoId,
      );

      expect(result.wasFoul, false);
      expect(result.extraTurn, false);
      expect(result.nextPlayerId, playerTwoId);
    });

    test('potting striker is a foul and passes turn', () {
      final board = createInitialBoard();

      final result = evaluateTurn(
        coinsBefore: board,
        coinsAfter: board,
        playerId: playerOneId,
        playerColor: CarromCoinType.white,
        opponentId: playerTwoId,
        opponentColor: CarromCoinType.black,
        queenStatusBefore: CarromQueenStatus.onBoard,
        queenPottedByBefore: null,
        strikerPotted: true,
        playerOneScore: 0,
        playerTwoScore: 0,
        playerOneId: playerOneId,
        playerTwoId: playerTwoId,
      );

      expect(result.wasFoul, true);
      expect(result.foulReason, 'Striker potted');
      expect(result.extraTurn, false);
      expect(result.nextPlayerId, playerTwoId);
    });
  });

  group('evaluateTurn - queen covering', () {
    final playerOneId = 'player1';
    final playerTwoId = 'player2';

    test('queen potted with own color coin is immediately covered', () {
      final board = createInitialBoard();
      final afterBoard = List<CarromCoin>.from(board);
      afterBoard[0] = afterBoard[0].copyWith(isPotted: true);
      afterBoard[1] = afterBoard[1].copyWith(isPotted: true);

      final result = evaluateTurn(
        coinsBefore: board,
        coinsAfter: afterBoard,
        playerId: playerOneId,
        playerColor: CarromCoinType.white,
        opponentId: playerTwoId,
        opponentColor: CarromCoinType.black,
        queenStatusBefore: CarromQueenStatus.onBoard,
        queenPottedByBefore: null,
        strikerPotted: false,
        playerOneScore: 0,
        playerTwoScore: 0,
        playerOneId: playerOneId,
        playerTwoId: playerTwoId,
      );

      expect(result.queenPotted, true);
      expect(result.queenCovered, true);
      expect(result.updatedQueenStatus, CarromQueenStatus.pottedCovered);
    });

    test('queen potted without covering coin stays uncovered', () {
      final board = createInitialBoard();
      final afterBoard = List<CarromCoin>.from(board);
      afterBoard[0] = afterBoard[0].copyWith(isPotted: true);

      final result = evaluateTurn(
        coinsBefore: board,
        coinsAfter: afterBoard,
        playerId: playerOneId,
        playerColor: CarromCoinType.white,
        opponentId: playerTwoId,
        opponentColor: CarromCoinType.black,
        queenStatusBefore: CarromQueenStatus.onBoard,
        queenPottedByBefore: null,
        strikerPotted: false,
        playerOneScore: 0,
        playerTwoScore: 0,
        playerOneId: playerOneId,
        playerTwoId: playerTwoId,
      );

      expect(result.queenPotted, true);
      expect(result.queenCovered, false);
      expect(result.updatedQueenStatus, CarromQueenStatus.pottedUncovered);
    });
  });

  group('win detection', () {
    final playerOneId = 'player1';
    final playerTwoId = 'player2';

    test('all own coins potted + queen covered = win', () {
      final board = createInitialBoard();
      final afterBoard = List<CarromCoin>.from(board);
      for (int i = 0; i < afterBoard.length; i++) {
        if (afterBoard[i].type == CarromCoinType.white ||
            afterBoard[i].type == CarromCoinType.queen) {
          afterBoard[i] = afterBoard[i].copyWith(isPotted: true);
        }
      }

      final result = evaluateTurn(
        coinsBefore: board,
        coinsAfter: afterBoard,
        playerId: playerOneId,
        playerColor: CarromCoinType.white,
        opponentId: playerTwoId,
        opponentColor: CarromCoinType.black,
        queenStatusBefore: CarromQueenStatus.onBoard,
        queenPottedByBefore: null,
        strikerPotted: false,
        playerOneScore: 8,
        playerTwoScore: 0,
        playerOneId: playerOneId,
        playerTwoId: playerTwoId,
      );

      expect(result.gameOver, true);
      expect(result.winnerId, playerOneId);
    });

    test('not all coins potted = no win', () {
      final board = createInitialBoard();
      final afterBoard = List<CarromCoin>.from(board);
      int potted = 0;
      for (int i = 0; i < afterBoard.length && potted < 5; i++) {
        if (afterBoard[i].type == CarromCoinType.white) {
          afterBoard[i] = afterBoard[i].copyWith(isPotted: true);
          potted++;
        }
      }

      final result = evaluateTurn(
        coinsBefore: board,
        coinsAfter: afterBoard,
        playerId: playerOneId,
        playerColor: CarromCoinType.white,
        opponentId: playerTwoId,
        opponentColor: CarromCoinType.black,
        queenStatusBefore: CarromQueenStatus.pottedCovered,
        queenPottedByBefore: playerOneId,
        strikerPotted: false,
        playerOneScore: 4,
        playerTwoScore: 0,
        playerOneId: playerOneId,
        playerTwoId: playerTwoId,
      );

      expect(result.gameOver, false);
    });
  });

  group('allCoinsPotted', () {
    test('returns true when all of a color are potted', () {
      final board = createInitialBoard();
      final allWhitePotted = board.map((c) {
        if (c.type == CarromCoinType.white) {
          return c.copyWith(isPotted: true);
        }
        return c;
      }).toList();

      expect(allCoinsPotted(allWhitePotted, CarromCoinType.white), true);
      expect(allCoinsPotted(allWhitePotted, CarromCoinType.black), false);
    });

    test('returns false when not all are potted', () {
      final board = createInitialBoard();
      expect(allCoinsPotted(board, CarromCoinType.white), false);
    });
  });

  group('remainingCoins', () {
    test('counts unpotted coins of a given color', () {
      final board = createInitialBoard();
      expect(remainingCoins(board, CarromCoinType.white), 9);
      expect(remainingCoins(board, CarromCoinType.black), 9);
      expect(remainingCoins(board, CarromCoinType.queen), 1);
    });

    test('decrements when coins are potted', () {
      final board = createInitialBoard();
      final modified = List<CarromCoin>.from(board);
      modified[1] = modified[1].copyWith(isPotted: true);
      expect(remainingCoins(modified, CarromCoinType.white), 8);
    });
  });
}
