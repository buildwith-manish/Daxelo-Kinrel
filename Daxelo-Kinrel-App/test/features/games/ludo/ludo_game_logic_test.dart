// test/features/games/ludo/ludo_game_logic_test.dart
//
// Tests for Ludo game logic — covers the most error-prone rules:
//   • 6-roll-again rule
//   • Exact-count-to-finish rule
//   • Capture on non-safe squares
//   • Capture blocked on safe squares
//   • Block rule (2+ stacked tokens = no capture)
//   • Home-column entry (no captures inside)
//   • Win detection
//
// Run with: flutter test test/features/games/ludo/ludo_game_logic_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/ludo/ludo_game_logic.dart';

void main() {
  // Helper: create a token at a given position for a given color/player.
  LudoToken makeToken({
    required String id,
    required String playerId,
    required LudoColor color,
    required int position,
    int tokenIndex = 0,
  }) {
    return LudoToken(
      id: id,
      playerId: playerId,
      tokenIndex: tokenIndex,
      position: position,
      color: color,
    );
  }

  group('canMoveToken — 6-to-leave-home rule', () {
    test('token in home base can only move on a 6', () {
      final token = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: -1,
      );

      expect(canMoveToken(token, 6), true, reason: '6 should allow leaving home');
      expect(canMoveToken(token, 1), false, reason: '1 should not leave home');
      expect(canMoveToken(token, 5), false, reason: '5 should not leave home');
    });

    test('token on track can move with any dice value that doesn\'t overshoot', () {
      final token = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 10,
      );

      expect(canMoveToken(token, 1), true);
      expect(canMoveToken(token, 6), true);
      expect(canMoveToken(token, 3), true);
    });
  });

  group('canMoveToken — exact-count-to-finish rule', () {
    test('token at position 56 needs exactly 1 to finish', () {
      final token = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 56, // one before finish
      );

      expect(canMoveToken(token, 1), true, reason: 'Exact 1 should finish');
      expect(canMoveToken(token, 2), false, reason: '2 overshoots — cannot move');
      expect(canMoveToken(token, 6), false, reason: '6 overshoots — cannot move');
    });

    test('token at position 52 needs exactly 5 to finish', () {
      final token = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 52,
      );

      expect(canMoveToken(token, 5), true, reason: 'Exact 5 should finish');
      expect(canMoveToken(token, 6), false, reason: '6 overshoots');
    });

    test('token at position 50 can move into home column with 1-7', () {
      final token = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 50, // last track square
      );

      expect(canMoveToken(token, 1), true, reason: '1 enters home column at 51');
      expect(canMoveToken(token, 7), true, reason: '7 reaches finish (57)');
      expect(canMoveToken(token, 8), false, reason: '8 overshoots');
    });

    test('finished token cannot move', () {
      final token = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 57, // finished
      );

      expect(canMoveToken(token, 1), false);
      expect(canMoveToken(token, 6), false);
    });
  });

  group('getLegalTokens — multiple tokens offered', () {
    test('if one token can\'t move but another can, the other is offered', () {
      final tokens = [
        makeToken(id: 't1', playerId: 'p1', color: LudoColor.red, position: 56, tokenIndex: 0),
        makeToken(id: 't2', playerId: 'p1', color: LudoColor.red, position: 10, tokenIndex: 1),
      ];

      // Roll a 6: t1 can't move (56+6=52? wait, 56+6=62>57 → can't), t2 can move (10+6=16)
      final legal = getLegalTokens(tokens, 6);
      expect(legal.length, 1);
      expect(legal.first.id, 't2');
    });

    test('tokens in home + on track with a 6: both offered', () {
      final tokens = [
        makeToken(id: 't1', playerId: 'p1', color: LudoColor.red, position: -1, tokenIndex: 0),
        makeToken(id: 't2', playerId: 'p1', color: LudoColor.red, position: 10, tokenIndex: 1),
      ];

      final legal = getLegalTokens(tokens, 6);
      expect(legal.length, 2);
    });
  });

  group('checkCapture — safe square logic', () {
    test('capture happens on non-safe square', () {
      final myToken = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 5, // on track
      );
      final opponent = makeToken(
        id: 't2',
        playerId: 'p2',
        color: LudoColor.blue,
        position: 5, // same relative position → same absolute (red start 0 + 5 = 5, blue start 13 + 5 = 18)
      );

      // Wait — relative positions differ by color. Red at rel 5 → abs 5.
      // Blue at rel 5 → abs 18. They're NOT on the same square.
      // Let me fix: put opponent at a relative position that maps to abs 5.
      // Blue start = 13, so rel position for abs 5 = (5 - 13) % 52 = 44.
      final opponentOnSameSquare = makeToken(
        id: 't2',
        playerId: 'p2',
        color: LudoColor.blue,
        position: 44, // abs = (13 + 44) % 52 = 57 % 52 = 5 — same as red's abs 5
      );

      // My token moves to relative position 5 (abs 5, which is NOT a safe square)
      final captured = checkCapture(
        token: myToken,
        newPosition: 5,
        allTokens: [myToken, opponentOnSameSquare],
      );

      expect(captured, isNotNull, reason: 'Should capture on non-safe square');
      expect(captured!.id, 't2');
    });

    test('capture blocked on safe square (start square)', () {
      // Red start square = absolute 0, which is in safeSquares.
      // Red token at relative 0 → absolute 0.
      // Blue token at relative 39 → absolute (13+39)%52 = 52%52 = 0 → same square.
      final myToken = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 0,
      );
      final opponent = makeToken(
        id: 't2',
        playerId: 'p2',
        color: LudoColor.blue,
        position: 39, // abs = (13+39)%52 = 0 — Red's start square (safe)
      );

      final captured = checkCapture(
        token: myToken,
        newPosition: 0,
        allTokens: [myToken, opponent],
      );

      expect(captured, isNull, reason: 'Should NOT capture on safe square');
    });

    test('capture blocked on star square (absolute 8)', () {
      // Absolute 8 is a safe star square.
      // Red at relative 8 → abs 8.
      // Blue at relative 47 → abs (13+47)%52 = 60%52 = 8 → same square.
      final myToken = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 8,
      );
      final opponent = makeToken(
        id: 't2',
        playerId: 'p2',
        color: LudoColor.blue,
        position: 47, // abs = 8
      );

      final captured = checkCapture(
        token: myToken,
        newPosition: 8,
        allTokens: [myToken, opponent],
      );

      expect(captured, isNull, reason: 'Should NOT capture on star safe square');
    });
  });

  group('checkCapture — block rule', () {
    test('2 stacked same-color tokens form a block — no capture', () {
      final myToken = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 5,
      );
      final opponent1 = makeToken(
        id: 't2',
        playerId: 'p2',
        color: LudoColor.blue,
        position: 44, // abs 5
      );
      final opponent2 = makeToken(
        id: 't3',
        playerId: 'p2',
        color: LudoColor.blue,
        position: 44, // abs 5 — stacked with opponent1
        tokenIndex: 1,
      );

      final captured = checkCapture(
        token: myToken,
        newPosition: 5,
        allTokens: [myToken, opponent1, opponent2],
      );

      expect(captured, isNull, reason: 'Block rule: 2 stacked tokens cannot be captured');
    });

    test('single token is captured normally (no block)', () {
      final myToken = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 5,
      );
      final opponent = makeToken(
        id: 't2',
        playerId: 'p2',
        color: LudoColor.blue,
        position: 44, // abs 5
      );

      final captured = checkCapture(
        token: myToken,
        newPosition: 5,
        allTokens: [myToken, opponent],
      );

      expect(captured, isNotNull, reason: 'Single token should be captured');
      expect(captured!.id, 't2');
    });
  });

  group('checkCapture — home column (no captures)', () {
    test('cannot capture in home column (position 51+)', () {
      final myToken = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 50,
      );
      final opponent = makeToken(
        id: 't2',
        playerId: 'p2',
        color: LudoColor.blue,
        position: 51, // in home column
      );

      // My token moves to position 51 (home column)
      final captured = checkCapture(
        token: myToken,
        newPosition: 51,
        allTokens: [myToken, opponent],
      );

      expect(captured, isNull, reason: 'No captures in home column');
    });
  });

  group('computeNewPosition', () {
    test('home token with 6 enters at position 0', () {
      final token = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: -1,
      );
      expect(computeNewPosition(token, 6), 0);
    });

    test('home token with non-6 stays at -1', () {
      final token = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: -1,
      );
      expect(computeNewPosition(token, 5), -1);
    });

    test('track token moves forward', () {
      final token = makeToken(
        id: 't1',
        playerId: 'p1',
        color: LudoColor.red,
        position: 10,
      );
      expect(computeNewPosition(token, 3), 13);
    });
  });

  group('getsExtraTurn', () {
    test('rolling a 6 grants extra turn', () {
      final result = LudoMoveResult(
        newPosition: 10,
        capturedToken: null,
        becameFinished: false,
      );
      expect(getsExtraTurn(diceValue: 6, moveResult: result), true);
    });

    test('capturing an opponent grants extra turn', () {
      final opponent = makeToken(
        id: 't2',
        playerId: 'p2',
        color: LudoColor.blue,
        position: 5,
      );
      final result = LudoMoveResult(
        newPosition: 10,
        capturedToken: opponent,
        becameFinished: false,
      );
      expect(getsExtraTurn(diceValue: 3, moveResult: result), true);
    });

    test('finishing a token grants extra turn', () {
      final result = LudoMoveResult(
        newPosition: 57,
        capturedToken: null,
        becameFinished: true,
      );
      expect(getsExtraTurn(diceValue: 1, moveResult: result), true);
    });

    test('normal move (no 6, no capture, no finish) does not grant extra turn', () {
      final result = LudoMoveResult(
        newPosition: 10,
        capturedToken: null,
        becameFinished: false,
      );
      expect(getsExtraTurn(diceValue: 3, moveResult: result), false);
    });
  });

  group('hasPlayerWon', () {
    test('all 4 tokens finished = win', () {
      final tokens = [
        makeToken(id: 't1', playerId: 'p1', color: LudoColor.red, position: 57, tokenIndex: 0),
        makeToken(id: 't2', playerId: 'p1', color: LudoColor.red, position: 57, tokenIndex: 1),
        makeToken(id: 't3', playerId: 'p1', color: LudoColor.red, position: 57, tokenIndex: 2),
        makeToken(id: 't4', playerId: 'p1', color: LudoColor.red, position: 57, tokenIndex: 3),
      ];
      expect(hasPlayerWon(tokens), true);
    });

    test('3 of 4 finished = no win', () {
      final tokens = [
        makeToken(id: 't1', playerId: 'p1', color: LudoColor.red, position: 57, tokenIndex: 0),
        makeToken(id: 't2', playerId: 'p1', color: LudoColor.red, position: 57, tokenIndex: 1),
        makeToken(id: 't3', playerId: 'p1', color: LudoColor.red, position: 57, tokenIndex: 2),
        makeToken(id: 't4', playerId: 'p1', color: LudoColor.red, position: 50, tokenIndex: 3),
      ];
      expect(hasPlayerWon(tokens), false);
    });
  });

  group('positionToGridCoord — finished token offsets', () {
    test('finished tokens of different colors get different positions', () {
      final redFinished = makeToken(id: 'r', playerId: 'p1', color: LudoColor.red, position: 57);
      final blueFinished = makeToken(id: 'b', playerId: 'p2', color: LudoColor.blue, position: 57);
      final greenFinished = makeToken(id: 'g', playerId: 'p3', color: LudoColor.green, position: 57);
      final yellowFinished = makeToken(id: 'y', playerId: 'p4', color: LudoColor.yellow, position: 57);

      final redPos = positionToGridCoord(redFinished);
      final bluePos = positionToGridCoord(blueFinished);
      final greenPos = positionToGridCoord(greenFinished);
      final yellowPos = positionToGridCoord(yellowFinished);

      expect(redPos, isNot(equals(bluePos)), reason: 'Red and Blue should have different finish positions');
      expect(redPos, isNot(equals(greenPos)), reason: 'Red and Green should have different finish positions');
      expect(redPos, isNot(equals(yellowPos)), reason: 'Red and Yellow should have different finish positions');
      expect(bluePos, isNot(equals(greenPos)), reason: 'Blue and Green should have different finish positions');
      expect(bluePos, isNot(equals(yellowPos)), reason: 'Blue and Yellow should have different finish positions');
      expect(greenPos, isNot(equals(yellowPos)), reason: 'Green and Yellow should have different finish positions');
    });
  });
}
