// test/features/games/dotsboxes/dotsboxes_game_logic_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/games/dotsboxes/dotsboxes_game_logic.dart';

void main() {
  group('isLineDrawn', () {
    test('returns true for drawn line', () {
      final drawn = <String>{'horizontal_0_0'};
      expect(isLineDrawn(drawn, DotsLine(type: LineType.horizontal, row: 0, col: 0)), true);
    });
    test('returns false for undrawn line', () {
      final drawn = <String>{};
      expect(isLineDrawn(drawn, DotsLine(type: LineType.horizontal, row: 0, col: 0)), false);
    });
  });

  group('isBoxComplete', () {
    test('true when all 4 borders drawn', () {
      final drawn = <String>{
        'horizontal_0_0', 'horizontal_1_0', 'vertical_0_0', 'vertical_0_1',
      };
      expect(isBoxComplete(drawn, DotsBox(row: 0, col: 0)), true);
    });
    test('false when missing a border', () {
      final drawn = <String>{
        'horizontal_0_0', 'horizontal_1_0', 'vertical_0_0',
      };
      expect(isBoxComplete(drawn, DotsBox(row: 0, col: 0)), false);
    });
  });

  group('evaluateLineDraw — single box capture', () {
    test('drawing the 4th line captures one box and grants bonus turn', () {
      // Box (0,0) has 3 sides drawn. Draw the 4th (right side = vertical_0_1).
      final drawn = <String>{
        'horizontal_0_0', 'horizontal_1_0', 'vertical_0_0',
      };
      drawn.add('vertical_0_1'); // the new line

      final result = evaluateLineDraw(
        drawnLines: drawn,
        line: DotsLine(type: LineType.vertical, row: 0, col: 1),
        gridSize: 5,
      );

      expect(result.capturedBoxes.length, 1);
      expect(result.capturedBoxes.first, (0, 0));
      expect(result.continuesTurn, true);
    });
  });

  group('evaluateLineDraw — double box capture (chain)', () {
    test('drawing a shared line captures both boxes', () {
      // Two adjacent boxes: (0,0) and (0,1).
      // Box (0,0) has top, bottom, left drawn. Box (0,1) has top, bottom, right drawn.
      // The shared line is vertical_0_1 (right of box 0, left of box 1).
      // Drawing it completes BOTH boxes.
      final drawn = <String>{
        'horizontal_0_0', 'horizontal_1_0', 'vertical_0_0', // box (0,0) sides except right
        'horizontal_0_1', 'horizontal_1_1', 'vertical_0_2',  // box (0,1) sides except left
      };
      drawn.add('vertical_0_1'); // the new line — shared between both boxes

      final result = evaluateLineDraw(
        drawnLines: drawn,
        line: DotsLine(type: LineType.vertical, row: 0, col: 1),
        gridSize: 5,
      );

      expect(result.capturedBoxes.length, 2);
      expect(result.capturedBoxes.contains((0, 0)), true);
      expect(result.capturedBoxes.contains((0, 1)), true);
      expect(result.continuesTurn, true);
    });
  });

  group('evaluateLineDraw — non-capturing move', () {
    test('drawing a line that completes no boxes passes turn', () {
      // Only one line drawn — no box can be complete.
      final drawn = <String>{'horizontal_0_0'};
      drawn.add('horizontal_0_1'); // new line

      final result = evaluateLineDraw(
        drawnLines: drawn,
        line: DotsLine(type: LineType.horizontal, row: 0, col: 1),
        gridSize: 5,
      );

      expect(result.capturedBoxes.length, 0);
      expect(result.continuesTurn, false);
    });
  });

  group('isGameOver', () {
    test('false when not all lines drawn', () {
      expect(isGameOver(<String>{'horizontal_0_0'}, 5), false);
    });
    test('true when all lines drawn', () {
      final gridSize = 2; // 2x2 boxes = 3x3 dots, total lines = 2*2*3 = 12
      final total = totalLines(gridSize);
      final drawn = Set<String>.from(List.generate(total, (i) => 'line_$i'));
      expect(isGameOver(drawn, gridSize), true);
    });
  });

  group('totalLines', () {
    test('correct for 5x5 grid', () {
      // 5x5 boxes: horizontal = 6*5=30, vertical = 5*6=30, total = 60
      expect(totalLines(5), 60);
    });
    test('correct for 9x9 grid', () {
      // 9x9 boxes: horizontal = 10*9=90, vertical = 9*10=90, total = 180
      expect(totalLines(9), 180);
    });
  });

  group('getWinners', () {
    test('single winner', () {
      expect(getWinners([5, 3, 4]), [0]);
    });
    test('tied winners (2 players)', () {
      expect(getWinners([4, 4]), [0, 1]);
    });
    test('tied winners (3 players)', () {
      expect(getWinners([3, 5, 5]), [1, 2]);
    });
    test('all tied (4 players)', () {
      expect(getWinners([3, 3, 3, 3]), [0, 1, 2, 3]);
    });
  });

  group('nextPlayerId', () {
    test('advances to next player', () {
      expect(nextPlayerId(['p1', 'p2', 'p3'], 'p1'), 'p2');
    });
    test('wraps around', () {
      expect(nextPlayerId(['p1', 'p2', 'p3'], 'p3'), 'p1');
    });
  });

  group('boxesBorderingLine', () {
    test('horizontal line at edge borders 1 box', () {
      // Top edge horizontal line (row=0) — only box below it
      final boxes = boxesBorderingLine(DotsLine(type: LineType.horizontal, row: 0, col: 0), 5);
      expect(boxes.length, 1);
      expect(boxes.first.row, 0);
      expect(boxes.first.col, 0);
    });
    test('horizontal line in middle borders 2 boxes', () {
      final boxes = boxesBorderingLine(DotsLine(type: LineType.horizontal, row: 2, col: 0), 5);
      expect(boxes.length, 2);
    });
    test('vertical line at left edge borders 1 box', () {
      final boxes = boxesBorderingLine(DotsLine(type: LineType.vertical, row: 0, col: 0), 5);
      expect(boxes.length, 1);
    });
    test('vertical line in middle borders 2 boxes', () {
      final boxes = boxesBorderingLine(DotsLine(type: LineType.vertical, row: 0, col: 2), 5);
      expect(boxes.length, 2);
    });
  });
}
