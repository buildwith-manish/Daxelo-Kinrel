// lib/features/games/checkers/checkers_game_logic.dart
//
// Pure Checkers game logic — no Flutter dependencies, fully testable.
//
// Standard checkers rules:
//   • 8x8 board, 32 dark squares used
//   • 12 pieces per player, placed on dark squares of first 3 rows
//   • Player One (red) starts at the bottom (rows 5-7), moves UP (decreasing row)
//   • Player Two (black) starts at the top (rows 0-2), moves DOWN (increasing row)
//   • Regular pieces move diagonally forward 1 square
//   • Kings move diagonally in any direction 1 square
//   • Captures: jump diagonally over an opponent's piece into an empty square
//   • Multi-jumps: if a capture leads to another capture, the same piece
//     must continue jumping in the same turn (mandatory)
//   • Mandatory capture: if any capture is available, the player MUST take it
//   • King promotion: piece reaching the far row becomes a king
//   • Game ends when a player has no pieces or no legal moves

/// Represents a single piece on the board.
/// Stored in boardState as JSON: {"player": 1|2, "isKing": bool}
class CheckersPiece {
  const CheckersPiece({required this.player, required this.isKing});

  /// 1 = red (bottom, moves up), 2 = black (top, moves down)
  final int player;
  final bool isKing;

  Map<String, dynamic> toJson() => {'player': player, 'isKing': isKing};

  factory CheckersPiece.fromJson(Map<String, dynamic> json) => CheckersPiece(
    player: json['player'] as int,
    isKing: json['isKing'] as bool? ?? false,
  );

  CheckersPiece copyWith({bool? isKing}) => CheckersPiece(
    player: player,
    isKing: isKing ?? this.isKing,
  );

  @override
  String toString() => 'P$player${isKing ? 'K' : ''}';
}

/// The board is an 8x8 grid. Only dark squares are used.
/// board[row][col] is a CheckersPiece or null.
/// Dark squares: (row + col) % 2 == 1
typedef CheckersBoard = List<List<CheckersPiece?>>;

/// Create a fresh board with pieces in starting positions.
CheckersBoard createInitialBoard() {
  final board = List<List<CheckersPiece?>>.generate(
    8,
    (_) => List<CheckersPiece?>.filled(8, null),
  );
  // Player Two (black) at top — rows 0, 1, 2
  for (int r = 0; r < 3; r++) {
    for (int c = 0; c < 8; c++) {
      if ((r + c) % 2 == 1) {
        board[r][c] = const CheckersPiece(player: 2, isKing: false);
      }
    }
  }
  // Player One (red) at bottom — rows 5, 6, 7
  for (int r = 5; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      if ((r + c) % 2 == 1) {
        board[r][c] = const CheckersPiece(player: 1, isKing: false);
      }
    }
  }
  return board;
}

/// Convert board to JSON-serializable format.
List<List<Map<String, dynamic>?>> boardToJson(CheckersBoard board) {
  return board
      .map((row) => row.map((cell) => cell?.toJson()).toList())
      .toList();
}

/// Convert from JSON format back to a board.
CheckersBoard boardFromJson(List<dynamic> json) {
  return json
      .map<List<CheckersPiece?>>((row) =>
          (row as List)
              .map((cell) => cell == null
                  ? null
                  : CheckersPiece.fromJson(cell as Map<String, dynamic>))
              .toList())
      .toList();
}

/// A single move: from (row, col) to (row, col), possibly a capture.
class CheckersMove {
  const CheckersMove({
    required this.fromRow,
    required this.fromCol,
    required this.toRow,
    required this.toCol,
    this.isCapture = false,
    this.capturedRow,
    this.capturedCol,
  });

  final int fromRow;
  final int fromCol;
  final int toRow;
  final int toCol;
  final bool isCapture;
  final int? capturedRow;
  final int? capturedCol;

  @override
  String toString() =>
      '($fromRow,$fromCol)→($toRow,$toCol)${isCapture ? 'x' : ''}';
}

/// Get the direction a piece can move (rows decrease for player 1 going up,
/// rows increase for player 2 going down). Kings can move both directions.
List<int> _getMoveDirections(CheckersPiece piece) {
  if (piece.isKing) return [-1, 1]; // both
  if (piece.player == 1) return [-1]; // up only
  return [1]; // down only
}

/// Check if a square is on the board and is a dark square.
bool _isValidSquare(int row, int col) {
  return row >= 0 && row < 8 && col >= 0 && col < 8 && (row + col) % 2 == 1;
}

/// Get all simple (non-capture) moves for a piece at (row, col).
List<CheckersMove> _getSimpleMoves(CheckersBoard board, int row, int col) {
  final piece = board[row][col];
  if (piece == null) return const [];

  final moves = <CheckersMove>[];
  final directions = _getMoveDirections(piece);

  for (final dRow in directions) {
    for (final dCol in [-1, 1]) {
      final newRow = row + dRow;
      final newCol = col + dCol;
      if (_isValidSquare(newRow, newCol) && board[newRow][newCol] == null) {
        moves.add(CheckersMove(
          fromRow: row,
          fromCol: col,
          toRow: newRow,
          toCol: newCol,
        ));
      }
    }
  }
  return moves;
}

/// Get all capture moves for a piece at (row, col).
/// Captures can be in any direction for kings, forward-only for regular pieces.
/// But standard checkers also allows backward captures for regular pieces
/// when continuing a multi-jump (we handle this via the isMultiJump flag).
List<CheckersMove> _getCaptureMoves(
  CheckersBoard board,
  int row,
  int col, {
  bool isMultiJump = false,
}) {
  final piece = board[row][col];
  if (piece == null) return const [];

  final moves = <CheckersMove>[];
  // For kings or multi-jump continuation, allow all 4 directions.
  // For regular pieces' first capture, only forward directions.
  final directions = (piece.isKing || isMultiJump)
      ? [-1, 1]
      : _getMoveDirections(piece);

  for (final dRow in directions) {
    for (final dCol in [-1, 1]) {
      final adjRow = row + dRow;
      final adjCol = col + dCol;
      final landRow = row + 2 * dRow;
      final landCol = col + 2 * dCol;

      if (!_isValidSquare(landRow, landCol)) continue;
      if (board[landRow][landCol] != null) continue; // landing must be empty

      final adjPiece = board[adjRow][adjCol];
      if (adjPiece == null) continue;
      if (adjPiece.player == piece.player) continue; // can't capture own piece

      moves.add(CheckersMove(
        fromRow: row,
        fromCol: col,
        toRow: landRow,
        toCol: landCol,
        isCapture: true,
        capturedRow: adjRow,
        capturedCol: adjCol,
      ));
    }
  }
  return moves;
}

/// Get ALL capture moves available for a player anywhere on the board.
/// Used to enforce the mandatory capture rule.
List<CheckersMove> getAllCapturesForPlayer(CheckersBoard board, int player) {
  final allCaptures = <CheckersMove>[];
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final piece = board[r][c];
      if (piece != null && piece.player == player) {
        allCaptures.addAll(_getCaptureMoves(board, r, c));
      }
    }
  }
  return allCaptures;
}

/// Get all legal moves for a specific piece at (row, col).
/// Enforces the mandatory capture rule: if any capture is available
/// for the player anywhere on the board, only capture moves are legal.
///
/// If [forcedPieceRow]/[forcedPieceCol] are provided (multi-jump in progress),
/// only that piece's capture moves are returned.
List<CheckersMove> getLegalMovesForPiece(
  CheckersBoard board,
  int row,
  int col, {
  int? forcedPieceRow,
  int? forcedPieceCol,
}) {
  final piece = board[row][col];
  if (piece == null) return const [];

  // If we're in a multi-jump, only the forced piece can move, and only captures
  if (forcedPieceRow != null && forcedPieceCol != null) {
    if (row != forcedPieceRow || col != forcedPieceCol) {
      return const [];
    }
    return _getCaptureMoves(board, row, col, isMultiJump: true);
  }

  // Mandatory capture rule: if any capture is available, only captures are legal
  final playerCaptures = getAllCapturesForPlayer(board, piece.player);
  if (playerCaptures.isNotEmpty) {
    // Filter to only this piece's captures
    return _getCaptureMoves(board, row, col);
  }

  // No captures available — return simple moves
  return _getSimpleMoves(board, row, col);
}

/// Get all legal moves for a player (used to detect game-end).
List<CheckersMove> getAllLegalMovesForPlayer(
  CheckersBoard board,
  int player, {
  int? forcedPieceRow,
  int? forcedPieceCol,
}) {
  if (forcedPieceRow != null && forcedPieceCol != null) {
    return getLegalMovesForPiece(
      board,
      forcedPieceRow,
      forcedPieceCol,
      forcedPieceRow: forcedPieceRow,
      forcedPieceCol: forcedPieceCol,
    );
  }

  final allMoves = <CheckersMove>[];
  // Check if captures are available (mandatory)
  final captures = getAllCapturesForPlayer(board, player);
  if (captures.isNotEmpty) return captures;

  // No captures — get all simple moves
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final piece = board[r][c];
      if (piece != null && piece.player == player) {
        allMoves.addAll(_getSimpleMoves(board, r, c));
      }
    }
  }
  return allMoves;
}

/// Apply a move to the board and return the new board state.
/// Does NOT validate the move — caller should validate first.
/// Returns the new board, whether the piece became a king, and whether
/// another capture is available from the new position (for multi-jump).
class ApplyMoveResult {
  const ApplyMoveResult({
    required this.board,
    required this.becameKing,
    required this.canContinueCapture,
  });
  final CheckersBoard board;
  final bool becameKing;
  final bool canContinueCapture;
}

ApplyMoveResult applyMove(CheckersBoard board, CheckersMove move) {
  // Make a deep copy
  final newBoard = board
      .map((row) => List<CheckersPiece?>.from(row))
      .toList();

  final piece = newBoard[move.fromRow][move.fromCol]!;
  newBoard[move.fromRow][move.fromCol] = null;

  // Remove captured piece if applicable
  if (move.isCapture && move.capturedRow != null && move.capturedCol != null) {
    newBoard[move.capturedRow!][move.capturedCol!] = null;
  }

  // Check for king promotion
  bool becameKing = false;
  CheckersPiece finalPiece = piece;
  if (!piece.isKing) {
    if (piece.player == 1 && move.toRow == 0) {
      finalPiece = piece.copyWith(isKing: true);
      becameKing = true;
    } else if (piece.player == 2 && move.toRow == 7) {
      finalPiece = piece.copyWith(isKing: true);
      becameKing = true;
    }
  }

  newBoard[move.toRow][move.toCol] = finalPiece;

  // Check if the same piece can continue capturing (multi-jump)
  // Note: standard rules say a piece that just became a king ends its turn
  // (can't continue capturing as a king in the same move). We follow this.
  bool canContinueCapture = false;
  if (move.isCapture && !becameKing) {
    final furtherCaptures = _getCaptureMoves(
      newBoard,
      move.toRow,
      move.toCol,
      isMultiJump: true,
    );
    canContinueCapture = furtherCaptures.isNotEmpty;
  }

  return ApplyMoveResult(
    board: newBoard,
    becameKing: becameKing,
    canContinueCapture: canContinueCapture,
  );
}

/// Count pieces for a player.
int countPieces(CheckersBoard board, int player) {
  int count = 0;
  for (final row in board) {
    for (final cell in row) {
      if (cell != null && cell.player == player) count++;
    }
  }
  return count;
}

/// Check if the game is over and return the winner (1, 2, or 0 for not over).
/// Game ends when a player has no pieces or no legal moves.
int? checkGameOver(CheckersBoard board, int currentPlayer) {
  final player1Count = countPieces(board, 1);
  final player2Count = countPieces(board, 2);

  if (player1Count == 0) return 2;
  if (player2Count == 0) return 1;

  // Check if the current player has any legal moves
  final currentMoves = getAllLegalMovesForPlayer(board, currentPlayer);
  if (currentMoves.isEmpty) {
    // Current player can't move — they lose
    return currentPlayer == 1 ? 2 : 1;
  }

  return null; // game continues
}

/// Validate a move. Returns null if valid, or an error message.
String? validateMove({
  required CheckersBoard board,
  required int playerId,
  required CheckersMove move,
  int? forcedPieceRow,
  int? forcedPieceCol,
}) {
  final piece = board[move.fromRow][move.fromCol];
  if (piece == null) return 'No piece at starting square';
  if (piece.player != playerId) return 'Not your piece';

  final legalMoves = getLegalMovesForPiece(
    board,
    move.fromRow,
    move.fromCol,
    forcedPieceRow: forcedPieceRow,
    forcedPieceCol: forcedPieceCol,
  );

  final isValid = legalMoves.any(
    (m) =>
        m.fromRow == move.fromRow &&
        m.fromCol == move.fromCol &&
        m.toRow == move.toRow &&
        m.toCol == move.toCol,
  );

  if (!isValid) {
    // Provide a helpful error message
    final allCaptures = getAllCapturesForPlayer(board, playerId);
    if (allCaptures.isNotEmpty) {
      return 'A capture is available — you must take it';
    }
    return 'Illegal move';
  }

  return null;
}
