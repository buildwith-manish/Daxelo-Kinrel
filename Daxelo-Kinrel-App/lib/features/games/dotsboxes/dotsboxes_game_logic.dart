// lib/features/games/dotsboxes/dotsboxes_game_logic.dart
//
// Pure Dots and Boxes logic — no Flutter deps, fully testable.
// Grid: gridSize × gridSize boxes, (gridSize+1) × (gridSize+1) dots.

enum LineType { horizontal, vertical }

extension LineTypeX on LineType {
  String get name => this == LineType.horizontal ? 'horizontal' : 'vertical';
  static LineType fromString(String? s) => s == 'vertical' ? LineType.vertical : LineType.horizontal;
}

/// A line between two adjacent dots.
class DotsLine {
  const DotsLine({required this.type, required this.row, required this.col});
  final LineType type;
  final int row;
  final int col;

  /// Unique key for set lookups.
  String get key => '${type.name}_${row}_$col';

  @override
  String toString() => '${type.name}($row,$col)';
}

/// A box on the grid, identified by its top-left corner.
class DotsBox {
  const DotsBox({required this.row, required this.col});
  final int row;
  final int col;

  /// The 4 lines that border this box.
  /// - Top: horizontal at (row, col)
  /// - Bottom: horizontal at (row+1, col)
  /// - Left: vertical at (row, col)
  /// - Right: vertical at (row, col+1)
  List<DotsLine> get borders => [
    DotsLine(type: LineType.horizontal, row: row, col: col),       // top
    DotsLine(type: LineType.horizontal, row: row + 1, col: col),   // bottom
    DotsLine(type: LineType.vertical, row: row, col: col),         // left
    DotsLine(type: LineType.vertical, row: row, col: col + 1),     // right
  ];
}

/// The result of drawing a line.
class DrawLineResult {
  const DrawLineResult({required this.capturedBoxes, required this.continuesTurn});
  /// Box coordinates that were captured by this move: List of (row, col).
  final List<(int, int)> capturedBoxes;
  /// True if the player gets a bonus turn (captured at least 1 box).
  final bool continuesTurn;
}

/// Check if a line is already drawn.
bool isLineDrawn(Set<String> drawnLines, DotsLine line) {
  return drawnLines.contains(line.key);
}

/// Check if a box has all 4 borders drawn.
bool isBoxComplete(Set<String> drawnLines, DotsBox box) {
  return box.borders.every((line) => drawnLines.contains(line.key));
}

/// Find which boxes a newly drawn line could complete.
/// A horizontal line at (row, col) borders:
///   - Box above: (row-1, col) if row > 0
///   - Box below: (row, col) if row < gridSize
/// A vertical line at (row, col) borders:
///   - Box left: (row, col-1) if col > 0
///   - Box right: (row, col) if col < gridSize
List<DotsBox> boxesBorderingLine(DotsLine line, int gridSize) {
  final boxes = <DotsBox>[];
  if (line.type == LineType.horizontal) {
    if (line.row > 0) boxes.add(DotsBox(row: line.row - 1, col: line.col));
    if (line.row < gridSize) boxes.add(DotsBox(row: line.row, col: line.col));
  } else {
    if (line.col > 0) boxes.add(DotsBox(row: line.row, col: line.col - 1));
    if (line.col < gridSize) boxes.add(DotsBox(row: line.row, col: line.col));
  }
  return boxes;
}

/// Evaluate the result of drawing a line.
/// [drawnLines] should already include the new line.
DrawLineResult evaluateLineDraw({
  required Set<String> drawnLines,
  required DotsLine line,
  required int gridSize,
}) {
  final borderingBoxes = boxesBorderingLine(line, gridSize);
  final captured = <(int, int)>[];

  for (final box in borderingBoxes) {
    if (isBoxComplete(drawnLines, box)) {
      captured.add((box.row, box.col));
    }
  }

  return DrawLineResult(
    capturedBoxes: captured,
    continuesTurn: captured.isNotEmpty,
  );
}

/// Total number of possible lines for a gridSize × gridSize grid.
/// Horizontal lines: (gridSize+1) rows × gridSize cols
/// Vertical lines: gridSize rows × (gridSize+1) cols
int totalLines(int gridSize) {
  return 2 * gridSize * (gridSize + 1);
}

/// Check if the game is over (all lines drawn).
bool isGameOver(Set<String> drawnLines, int gridSize) {
  return drawnLines.length >= totalLines(gridSize);
}

/// Determine the winner(s) from final scores.
/// Returns a list of player indices (0-based) with the highest score.
List<int> getWinners(List<int> scores) {
  if (scores.isEmpty) return [];
  final maxScore = scores.reduce((a, b) => a > b ? a : b);
  final winners = <int>[];
  for (int i = 0; i < scores.length; i++) {
    if (scores[i] == maxScore) winners.add(i);
  }
  return winners;
}

/// Get the next player in turn order (wraps around).
String nextPlayerId(List<String> playerIds, String currentPlayerId) {
  final idx = playerIds.indexOf(currentPlayerId);
  if (idx == -1 || playerIds.length <= 1) return currentPlayerId;
  return playerIds[(idx + 1) % playerIds.length];
}

/// Player colors for 2-4 players.
List<int> get playerColorValues => [0, 1, 2, 3]; // orange, blue, teal, gold
