// lib/features/games/tictactoe/tictactoe_game_logic.dart
//
// Pure Tic-Tac-Toe logic — written from scratch (no external package).
// Win detection is trivial (~20 lines); no dependency needed.

enum Mark { x, o }

extension MarkX on Mark {
  String get name => this == Mark.x ? 'X' : 'O';
  Mark get opposite => this == Mark.x ? Mark.o : Mark.x;
  static Mark? fromString(String? s) {
    if (s == 'X') return Mark.x;
    if (s == 'O') return Mark.o;
    return null;
  }
}

enum RoundResult { xWin, oWin, draw, ongoing }

extension RoundResultX on RoundResult {
  String get name => switch (this) {
    RoundResult.xWin => 'x_win',
    RoundResult.oWin => 'o_win',
    RoundResult.draw => 'draw',
    RoundResult.ongoing => 'ongoing',
  };
  static RoundResult fromString(String? s) => switch (s) {
    'x_win' => RoundResult.xWin,
    'o_win' => RoundResult.oWin,
    'draw' => RoundResult.draw,
    _ => RoundResult.ongoing,
  };
}

/// The 8 winning lines (3 rows, 3 cols, 2 diagonals).
const List<List<int>> winLines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
  [0, 3, 6], [1, 4, 7], [2, 5, 8], // cols
  [0, 4, 8], [2, 4, 6],             // diagonals
];

/// Check the board for a winner. Returns the winning line indices or null.
List<int>? checkWinner(List<String?> board) {
  for (final line in winLines) {
    final a = board[line[0]];
    if (a != null && a == board[line[1]] && a == board[line[2]]) {
      return line;
    }
  }
  return null;
}

/// Determine the current state of the round.
RoundResult getRoundResult(List<String?> board) {
  final winner = checkWinner(board);
  if (winner != null) {
    return board[winner[0]] == 'X' ? RoundResult.xWin : RoundResult.oWin;
  }
  if (board.every((c) => c != null)) {
    return RoundResult.draw;
  }
  return RoundResult.ongoing;
}

/// Validate a move. Returns null if valid, error message otherwise.
String? validateMove({
  required List<String?> board,
  required int cellIndex,
  required Mark mark,
  required Mark expectedMark,
}) {
  if (cellIndex < 0 || cellIndex > 8) return 'Invalid cell';
  if (board[cellIndex] != null) return 'Cell already taken';
  if (mark != expectedMark) return 'Not your turn';
  return null;
}

/// Check if the overall match is decided (best-of-N).
/// Returns the winning Mark or null if match continues.
Mark? getMatchWinner(int roundsWonX, int roundsWonO, int bestOf) {
  final needed = (bestOf ~/ 2) + 1;
  if (roundsWonX >= needed) return Mark.x;
  if (roundsWonO >= needed) return Mark.o;
  return null;
}

/// Create an empty board.
List<String?> createEmptyBoard() => List<String?>.filled(9, null);
