// lib/features/games/connect4/connect4_engine.dart
//
// Connect 4 — pure Dart game engine.
//
// Classic strategy game on a 7-column × 6-row grid. Two players (Red and
// Yellow) take turns dropping discs into columns. Discs fall to the lowest
// empty row due to "gravity". First player to connect 4 of their discs
// horizontally, vertically, or diagonally wins. If the board fills up
// with no winner, it's a draw.
//
// This engine is completely separated from UI. It exposes:
//   • dropDisc()         — place a disc in a column
//   • getValidColumns()  — list of columns that aren't full
//   • isValidMove()      — validate a proposed column
//   • checkWinner()      — detect 4-in-a-row
//   • checkDraw()        — detect board-full draw
//   • switchTurn()       — advance to the next player
//   • getGameState()     — return the full serializable state
//
// The engine is DETERMINISTIC — every client independently derives the
// same board state from the same sequence of (playerIndex, column) moves.
// Only those two values are synced; all board state is derived.
//
// REFERENCE: The win-detection algorithm checks 4 directions (horizontal,
// vertical, diagonal ↘, diagonal ↙) from the last-placed disc. This is
// the standard approach used by open-source Connect 4 implementations
// (e.g. PascalPons/connect4 solver, the canonical academic reference).

// ─────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────

const int kConnect4Columns = 7;
const int kConnect4Rows = 6;
const int kConnect4WinLength = 4;

/// The two players. 0 = Red (goes first), 1 = Yellow.
enum Connect4PlayerColor { red, yellow }

extension Connect4PlayerColorX on Connect4PlayerColor {
  int get indexValue => this == Connect4PlayerColor.red ? 0 : 1;
  Connect4PlayerColor get opponent =>
      this == Connect4PlayerColor.red
          ? Connect4PlayerColor.yellow
          : Connect4PlayerColor.red;
  String get name => this == Connect4PlayerColor.red ? 'Red' : 'Yellow';
}

// ─────────────────────────────────────────────────────────────────────────
// Move — a single play: (playerIndex, column).
// ─────────────────────────────────────────────────────────────────────────

class Connect4Move {
  const Connect4Move({
    required this.playerIndex,
    required this.column,
  });

  /// Which player made the move (0 = Red, 1 = Yellow).
  final int playerIndex;

  /// Which column they dropped the disc into (0..6).
  final int column;

  Map<String, dynamic> toJson() => {
        'player': playerIndex,
        'col': column,
      };

  factory Connect4Move.fromJson(Map<String, dynamic> json) => Connect4Move(
        playerIndex: (json['player'] as num?)?.toInt() ?? 0,
        column: (json['col'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() => 'Connect4Move(player=$playerIndex, col=$column)';
}

// ─────────────────────────────────────────────────────────────────────────
// Winner — the result of a completed game.
// ─────────────────────────────────────────────────────────────────────────

class Connect4Winner {
  const Connect4Winner({
    this.playerIndex = -1,
    this.isDraw = false,
    this.winningCells = const [],
  });

  /// -1 if no winner yet; 0 or 1 if a player won.
  final int playerIndex;

  /// True if the game ended in a draw (board full, no winner).
  final bool isDraw;

  /// The 4 (row, col) cells that form the winning line. Empty if no
  /// winner or draw. Used by the UI to highlight the winning line.
  final List<(int, int)> winningCells;

  bool get hasWinner => playerIndex >= 0;
  bool get isFinished => hasWinner || isDraw;
}

// ─────────────────────────────────────────────────────────────────────────
// Game state — the full serializable state of a match.
// ─────────────────────────────────────────────────────────────────────────

class Connect4GameState {
  Connect4GameState({
    required this.board,
    required this.currentPlayerIndex,
    required this.moveHistory,
    required this.winner,
    required this.status,
  });

  /// 6×7 grid. board[row][col] = 0 (Red), 1 (Yellow), or -1 (empty).
  /// Row 0 = top, row 5 = bottom. Discs "fall" to the highest row index
  /// that's empty in a column.
  List<List<int>> board;

  /// Whose turn it is (0 = Red, 1 = Yellow).
  int currentPlayerIndex;

  /// The complete move history (for replay + determinism verification).
  List<Connect4Move> moveHistory;

  /// The winner, if the game is finished.
  Connect4Winner winner;

  /// 'waiting' | 'in_progress' | 'completed'.
  String status;

  /// The total number of discs placed so far.
  int get discCount => moveHistory.length;

  /// Whether the board is completely full.
  bool get isBoardFull => discCount >= kConnect4Columns * kConnect4Rows;

  /// Whether the game is over (win or draw).
  bool get isFinished => winner.isFinished || status == 'completed';

  Map<String, dynamic> toJson() => {
        'board': board,
        'currentPlayer': currentPlayerIndex,
        'moves': moveHistory.map((m) => m.toJson()).toList(),
        'winner': winner.playerIndex,
        'isDraw': winner.isDraw,
        'winningCells':
            winner.winningCells.map((c) => [c.$1, c.$2]).toList(),
        'status': status,
      };

  factory Connect4GameState.fromJson(Map<String, dynamic> json) {
    final board = <List<int>>[];
    final rawBoard = json['board'];
    if (rawBoard is List) {
      for (final row in rawBoard) {
        if (row is List) {
          board.add(row.map((c) => (c as num?)?.toInt() ?? -1).toList());
        }
      }
    }
    if (board.isEmpty) {
      board = Connect4Engine.emptyBoard();
    }

    final moves = <Connect4Move>[];
    final rawMoves = json['moves'];
    if (rawMoves is List) {
      for (final m in rawMoves) {
        if (m is Map) {
          moves.add(
              Connect4Move.fromJson(Map<String, dynamic>.from(m)));
        }
      }
    }

    final winningCells = <(int, int)>[];
    final rawCells = json['winningCells'];
    if (rawCells is List) {
      for (final c in rawCells) {
        if (c is List && c.length >= 2) {
          winningCells.add(((c[0] as num).toInt(), (c[1] as num).toInt()));
        }
      }
    }

    return Connect4GameState(
      board: board,
      currentPlayerIndex: (json['currentPlayer'] as num?)?.toInt() ?? 0,
      moveHistory: moves,
      winner: Connect4Winner(
        playerIndex: (json['winner'] as num?)?.toInt() ?? -1,
        isDraw: (json['isDraw'] as bool?) ?? false,
        winningCells: winningCells,
      ),
      status: (json['status'] as String?) ?? 'waiting',
    );
  }

  Connect4GameState copy() => Connect4GameState(
        board: board.map((row) => List<int>.from(row)).toList(),
        currentPlayerIndex: currentPlayerIndex,
        moveHistory: List<Connect4Move>.from(moveHistory),
        winner: Connect4Winner(
          playerIndex: winner.playerIndex,
          isDraw: winner.isDraw,
          winningCells: List<(int, int)>.from(winner.winningCells),
        ),
        status: status,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// The engine — pure functions on Connect4GameState.
// ─────────────────────────────────────────────────────────────────────────

class Connect4Engine {
  Connect4Engine._();

  /// Create a fresh empty board (6 rows × 7 columns, all -1).
  static List<List<int>> emptyBoard() {
    return List.generate(
      kConnect4Rows,
      (_) => List<int>.filled(kConnect4Columns, -1),
    );
  }

  /// Create a fresh game state for a new match.
  static Connect4GameState initialState() {
    return Connect4GameState(
      board: emptyBoard(),
      currentPlayerIndex: 0, // Red goes first
      moveHistory: const [],
      winner: const Connect4Winner(),
      status: 'in_progress',
    );
  }

  /// Get the list of columns that aren't full (valid drop targets).
  static List<int> getValidColumns(Connect4GameState state) {
    final cols = <int>[];
    for (var c = 0; c < kConnect4Columns; c++) {
      if (state.board[0][c] == -1) {
        cols.add(c);
      }
    }
    return cols;
  }

  /// Check if a column is a valid move (not full, game not finished).
  static bool isValidMove(Connect4GameState state, int column) {
    if (state.isFinished) return false;
    if (column < 0 || column >= kConnect4Columns) return false;
    return state.board[0][column] == -1;
  }

  /// Find the row where a disc would land in `column` (the lowest empty
  /// row). Returns -1 if the column is full.
  static int _findDropRow(List<List<int>> board, int column) {
    for (var r = kConnect4Rows - 1; r >= 0; r--) {
      if (board[r][column] == -1) return r;
    }
    return -1;
  }

  /// Drop a disc into `column` for the current player. Returns the new
  /// state with the disc placed, turn switched (or game finished).
  ///
  /// If the move is invalid, returns the state unchanged.
  static Connect4GameState dropDisc(
      Connect4GameState state, int column) {
    if (!isValidMove(state, column)) return state;

    final next = state.copy();
    final row = _findDropRow(next.board, column);
    if (row < 0) return state;

    // Place the disc.
    next.board[row][column] = next.currentPlayerIndex;
    next.moveHistory = List<Connect4Move>.from(next.moveHistory)
      ..add(Connect4Move(
        playerIndex: next.currentPlayerIndex,
        column: column,
      ));

    // Check for a winner.
    final winner = checkWinner(next.board, row, column, next.currentPlayerIndex);
    if (winner.hasWinner) {
      next.winner = winner;
      next.status = 'completed';
      return next;
    }

    // Check for a draw (board full).
    if (next.isBoardFull) {
      next.winner = const Connect4Winner(isDraw: true);
      next.status = 'completed';
      return next;
    }

    // Switch turns.
    return switchTurn(next);
  }

  /// Switch the current player (0 → 1, 1 → 0).
  static Connect4GameState switchTurn(Connect4GameState state) {
    final next = state.copy();
    next.currentPlayerIndex = (next.currentPlayerIndex + 1) % 2;
    return next;
  }

  /// Check for a winner by examining 4 directions from (row, col).
  /// Returns a Connect4Winner with the winning cells if 4-in-a-row is
  /// found for `playerIndex`; otherwise returns an empty winner.
  ///
  /// The 4 directions to check:
  ///   • Horizontal →
  ///   • Vertical ↓
  ///   • Diagonal ↘
  ///   • Diagonal ↙
  ///
  /// For each direction, we count consecutive discs of the same color
  /// in both directions from the placed disc. If the total (including
  /// the placed disc) is >= 4, we have a winner.
  static Connect4Winner checkWinner(
      List<List<int>> board, int row, int col, int playerIndex) {
    // 4 directions: (dr, dc) pairs
    const directions = [
      (0, 1),  // horizontal →
      (1, 0),  // vertical ↓
      (1, 1),  // diagonal ↘
      (1, -1), // diagonal ↙
    ];

    for (final (dr, dc) in directions) {
      final cells = <(int, int)>[(row, col)];

      // Count in the positive direction.
      for (var i = 1; i < kConnect4WinLength; i++) {
        final r = row + dr * i;
        final c = col + dc * i;
        if (r < 0 ||
            r >= kConnect4Rows ||
            c < 0 ||
            c >= kConnect4Columns) break;
        if (board[r][c] != playerIndex) break;
        cells.add((r, c));
      }

      // Count in the negative direction.
      for (var i = 1; i < kConnect4WinLength; i++) {
        final r = row - dr * i;
        final c = col - dc * i;
        if (r < 0 ||
            r >= kConnect4Rows ||
            c < 0 ||
            c >= kConnect4Columns) break;
        if (board[r][c] != playerIndex) break;
        cells.insert(0, (r, c));
      }

      if (cells.length >= kConnect4WinLength) {
        // Winner! Return the first 4 cells (or all if > 4).
        return Connect4Winner(
          playerIndex: playerIndex,
          winningCells: cells.take(kConnect4WinLength).toList(),
        );
      }
    }

    return const Connect4Winner();
  }

  /// Check if the game is a draw (board full, no winner).
  static bool checkDraw(Connect4GameState state) {
    return state.isBoardFull && !state.winner.hasWinner;
  }

  /// Get the current game state (already available as the state object;
  /// this method is here for API completeness per the spec).
  static Connect4GameState getGameState(Connect4GameState state) => state;

  /// Rebuild the board from a move history (deterministic replay).
  /// This is used to verify that all clients derive the same board.
  static Connect4GameState replayMoves(List<Connect4Move> moves) {
    var state = initialState();
    for (final move in moves) {
      state = dropDisc(state, move.column);
      if (state.isFinished) break;
    }
    return state;
  }
}
