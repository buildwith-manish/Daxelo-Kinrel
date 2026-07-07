// test/features/games/tictactoe/tictactoe_game_logic_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/tictactoe/tictactoe_game_logic.dart';

void main() {
  group('checkWinner — all 8 win lines', () {
    test('row 0 (cells 0,1,2)', () {
      final board = ['X','X','X', null,null,null, null,null,null];
      expect(checkWinner(board), [0,1,2]);
    });
    test('row 1 (cells 3,4,5)', () {
      final board = [null,null,null, 'O','O','O', null,null,null];
      expect(checkWinner(board), [3,4,5]);
    });
    test('row 2 (cells 6,7,8)', () {
      final board = [null,null,null, null,null,null, 'X','X','X'];
      expect(checkWinner(board), [6,7,8]);
    });
    test('col 0 (cells 0,3,6)', () {
      final board = ['O',null,null, 'O',null,null, 'O',null,null];
      expect(checkWinner(board), [0,3,6]);
    });
    test('col 1 (cells 1,4,7)', () {
      final board = [null,'X',null, null,'X',null, null,'X',null];
      expect(checkWinner(board), [1,4,7]);
    });
    test('col 2 (cells 2,5,8)', () {
      final board = [null,null,'O', null,null,'O', null,null,'O'];
      expect(checkWinner(board), [2,5,8]);
    });
    test('diagonal (cells 0,4,8)', () {
      final board = ['X',null,null, null,'X',null, null,null,'X'];
      expect(checkWinner(board), [0,4,8]);
    });
    test('anti-diagonal (cells 2,4,6)', () {
      final board = [null,null,'O', null,'O',null, 'O',null,null];
      expect(checkWinner(board), [2,4,6]);
    });
  });

  group('checkWinner — no winner', () {
    test('empty board', () {
      expect(checkWinner(createEmptyBoard()), isNull);
    });
    test('partial board, no line', () {
      final board = ['X','O','X', 'O','X','O', 'O','X','O'];
      expect(checkWinner(board), isNull); // actually this is a full board with no winner
    });
    test('mixed, no complete line', () {
      final board = ['X','O',null, null,'X',null, null,null,'O'];
      expect(checkWinner(board), isNull);
    });
  });

  group('getRoundResult', () {
    test('X wins', () {
      final board = ['X','X','X', null,null,null, null,null,null];
      expect(getRoundResult(board), RoundResult.xWin);
    });
    test('O wins', () {
      final board = ['O',null,null, 'O',null,null, 'O',null,null];
      expect(getRoundResult(board), RoundResult.oWin);
    });
    test('draw — board full, no winner', () {
      final board = ['X','O','X', 'X','O','O', 'O','X','X'];
      expect(getRoundResult(board), RoundResult.draw);
    });
    test('ongoing — board not full, no winner', () {
      final board = ['X',null,null, null,'O',null, null,null,null];
      expect(getRoundResult(board), RoundResult.ongoing);
    });
  });

  group('validateMove', () {
    test('valid move returns null', () {
      expect(validateMove(board: createEmptyBoard(), cellIndex: 0, mark: Mark.x, expectedMark: Mark.x), isNull);
    });
    test('cell already taken', () {
      final board = ['X',null,null, null,null,null, null,null,null];
      expect(validateMove(board: board, cellIndex: 0, mark: Mark.o, expectedMark: Mark.o), isNotNull);
    });
    test('wrong turn', () {
      expect(validateMove(board: createEmptyBoard(), cellIndex: 0, mark: Mark.o, expectedMark: Mark.x), isNotNull);
    });
    test('out of bounds', () {
      expect(validateMove(board: createEmptyBoard(), cellIndex: 9, mark: Mark.x, expectedMark: Mark.x), isNotNull);
    });
  });

  group('getMatchWinner — best of N', () {
    test('best of 1: 1 win = match winner', () {
      expect(getMatchWinner(1, 0, 1), Mark.x);
      expect(getMatchWinner(0, 1, 1), Mark.o);
    });
    test('best of 3: need 2 wins', () {
      expect(getMatchWinner(2, 0, 3), Mark.x);
      expect(getMatchWinner(0, 2, 3), Mark.o);
      expect(getMatchWinner(1, 1, 3), isNull); // ongoing
    });
    test('best of 5: need 3 wins', () {
      expect(getMatchWinner(3, 1, 5), Mark.x);
      expect(getMatchWinner(2, 2, 5), isNull);
    });
  });

  group('createEmptyBoard', () {
    test('has 9 null cells', () {
      final board = createEmptyBoard();
      expect(board.length, 9);
      expect(board.every((c) => c == null), true);
    });
  });

  group('Mark', () {
    test('opposite works', () {
      expect(Mark.x.opposite, Mark.o);
      expect(Mark.o.opposite, Mark.x);
    });
    test('fromString', () {
      expect(MarkX.fromString('X'), Mark.x);
      expect(MarkX.fromString('O'), Mark.o);
      expect(MarkX.fromString(null), isNull);
      expect(MarkX.fromString('invalid'), isNull);
    });
  });
}
