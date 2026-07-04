// lib/features/games/ludo/ludo_game_logic.dart
//
// Pure Ludo game logic — no Flutter dependencies, fully testable.
//
// Position encoding:
//   -1   = in home base (not yet on board)
//   0-50 = relative position on shared 52-square track
//   51-56 = home column (6 private squares per color)
//   57   = finished (reached center)
//
// Each color has a start square on the absolute 0-51 track:
//   Red: 0, Blue: 13, Green: 26, Yellow: 39
//
// To convert relative → absolute: absolutePos = (startSquare + relativePos) % 52
// Each player travels 51 squares (relative 0-50) before entering home column.

/// The four Ludo colors.
enum LudoColor { red, blue, green, yellow }

extension LudoColorX on LudoColor {
  String get name {
    switch (this) {
      case LudoColor.red:
        return 'red';
      case LudoColor.blue:
        return 'blue';
      case LudoColor.green:
        return 'green';
      case LudoColor.yellow:
        return 'yellow';
    }
  }

  /// Absolute start square on the 52-square track.
  int get startSquare {
    switch (this) {
      case LudoColor.red:
        return 0;
      case LudoColor.blue:
        return 13;
      case LudoColor.green:
        return 26;
      case LudoColor.yellow:
        return 39;
    }
  }

  /// The last relative position on the track before entering home column.
  /// Each player travels 51 squares (relative 0-50), then enters home column.
  static const int lastTrackPosition = 50;

  static LudoColor fromString(String? s) {
    switch (s) {
      case 'blue':
        return LudoColor.blue;
      case 'green':
        return LudoColor.green;
      case 'yellow':
        return LudoColor.yellow;
      case 'red':
      default:
        return LudoColor.red;
    }
  }

  /// Get the next color in turn order (for 4-player games).
  static LudoColor next(LudoColor current) {
    switch (current) {
      case LudoColor.red:
        return LudoColor.blue;
      case LudoColor.blue:
        return LudoColor.green;
      case LudoColor.green:
        return LudoColor.yellow;
      case LudoColor.yellow:
        return LudoColor.red;
    }
  }
}

/// Safe squares (absolute positions on the 0-51 track).
/// These are the 4 start squares + 4 additional safe squares.
/// No captures can happen on safe squares.
const Set<int> safeSquares = {0, 8, 13, 21, 26, 34, 39, 47};

/// A token on the board.
class LudoToken {
  const LudoToken({
    required this.id,
    required this.playerId,
    required this.tokenIndex,
    required this.position,
    required this.color,
  });

  final String id;
  final String playerId;
  final int tokenIndex; // 0-3
  final int position; // see encoding above
  final LudoColor color;

  bool get isHome => position == -1;
  bool get isOnTrack => position >= 0 && position <= 50;
  bool get isInHomeColumn => position >= 51 && position <= 56;
  bool get isFinished => position == 57;

  /// Convert relative track position to absolute track position.
  /// Returns null if the token is not on the shared track.
  int? get absolutePosition {
    if (!isOnTrack) return null;
    return (color.startSquare + position) % 52;
  }

  LudoToken copyWith({int? position}) => LudoToken(
    id: id,
    playerId: playerId,
        tokenIndex: tokenIndex,
        position: position ?? this.position,
        color: color,
      );
}

/// Check if a token can move with the given dice value.
/// Returns true if the move is legal.
bool canMoveToken(LudoToken token, int diceValue) {
  if (token.isFinished) return false; // already at center

  if (token.isHome) {
    // Need a 6 to leave home
    return diceValue == 6;
  }

  if (token.isOnTrack) {
    // Check if the token would overshoot the finish
    final newPosition = token.position + diceValue;
    return newPosition <= 57; // 57 = finished
  }

  if (token.isInHomeColumn) {
    // In home column — must land exactly on 57 (center)
    final newPosition = token.position + diceValue;
    return newPosition <= 57;
  }

  return false;
}

/// Get all legal tokens that can be moved with the given dice value.
List<LudoToken> getLegalTokens(
  List<LudoToken> playerTokens,
  int diceValue,
) {
  return playerTokens.where((t) => canMoveToken(t, diceValue)).toList();
}

/// Compute the new position after moving a token by [diceValue].
int computeNewPosition(LudoToken token, int diceValue) {
  if (token.isHome) {
    if (diceValue == 6) return 0; // enter the board at start square
    return -1; // can't move
  }
  return token.position + diceValue;
}

/// Check if moving [token] to [newPosition] would capture an opponent's token.
/// Returns the captured token, or null if no capture.
LudoToken? checkCapture({
  required LudoToken token,
  required int newPosition,
  required List<LudoToken> allTokens,
}) {
  // Can only capture on the shared track (not in home column)
  if (newPosition < 0 || newPosition > 50) return null;

  // Compute the absolute position of the destination
  final destAbsolute = (token.color.startSquare + newPosition) % 52;

  // Check if destination is a safe square
  if (safeSquares.contains(destAbsolute)) return null;

  // Find any opponent token at the same absolute position
  for (final other in allTokens) {
    if (other.playerId == token.playerId) continue; // same player
    if (!other.isOnTrack) continue; // not on shared track
    final otherAbs = other.absolutePosition;
    if (otherAbs == destAbsolute) {
      return other; // capture!
    }
  }

  return null;
}

/// Apply a move: returns the new token state, captured token (if any),
/// and whether the token became finished.
class LudoMoveResult {
  const LudoMoveResult({
    required this.newPosition,
    this.capturedToken,
    required this.becameFinished,
  });
  final int newPosition;
  final LudoToken? capturedToken;
  final bool becameFinished;
}

LudoMoveResult applyTokenMove({
  required LudoToken token,
  required int diceValue,
  required List<LudoToken> allTokens,
}) {
  final newPosition = computeNewPosition(token, diceValue);
  final captured = checkCapture(
    token: token,
    newPosition: newPosition,
    allTokens: allTokens,
  );
  final becameFinished = newPosition == 57;

  return LudoMoveResult(
    newPosition: newPosition,
    capturedToken: captured,
    becameFinished: becameFinished,
  );
}

/// Check if a player has won (all 4 tokens finished).
bool hasPlayerWon(List<LudoToken> playerTokens) {
  return playerTokens.every((t) => t.isFinished);
}

/// Count finished tokens for a player.
int countFinishedTokens(List<LudoToken> playerTokens) {
  return playerTokens.where((t) => t.isFinished).length;
}

/// Determine if the player gets an extra turn.
/// Extra turn on: rolling a 6, capturing an opponent, or finishing a token.
bool getsExtraTurn({
  required int diceValue,
  required LudoMoveResult moveResult,
}) {
  if (diceValue == 6) return true;
  if (moveResult.capturedToken != null) return true;
  if (moveResult.becameFinished) return true;
  return false;
}

/// The 15×15 board grid coordinate for each absolute track position (0-51).
/// Maps the shared track to (row, col) on the visual board.
/// Going clockwise from Red's start at (6, 1).
const List<(int, int)> trackCoordinates = [
  // Red start, going right along row 6
  (6, 1), (6, 2), (6, 3), (6, 4), (6, 5),
  // Up the left side of the top arm
  (5, 6), (4, 6), (3, 6), (2, 6), (1, 6), (0, 6),
  // Across the top
  (0, 7),
  // Blue start, down the right side of the top arm
  (0, 8), (1, 8), (2, 8), (3, 8), (4, 8), (5, 8),
  // Right along row 6
  (6, 9), (6, 10), (6, 11), (6, 12), (6, 13), (6, 14),
  // Down the right side
  (7, 14),
  // Green start, left along row 8
  (8, 14), (8, 13), (8, 12), (8, 11), (8, 10), (8, 9),
  // Down the right side of the bottom arm
  (9, 8), (10, 8), (11, 8), (12, 8), (13, 8), (14, 8),
  // Across the bottom
  (14, 7),
  // Yellow start, up the left side of the bottom arm
  (14, 6), (13, 6), (12, 6), (11, 6), (10, 6), (9, 6),
  // Left along row 8
  (8, 5), (8, 4), (8, 3), (8, 2), (8, 1), (8, 0),
  // Up the left side
  (7, 0),
  // Back to start
  (6, 0),
];

/// Home column coordinates for each color (6 squares leading to center).
/// These are the private paths only that color can use.
Map<LudoColor, List<(int, int)>> get homeColumnCoordinates => {
  // Red: row 7, cols 1-6 (left to center)
  LudoColor.red: [(7, 1), (7, 2), (7, 3), (7, 4), (7, 5), (7, 6)],
  // Blue: col 7, rows 1-6 (top to center)
  LudoColor.blue: [(1, 7), (2, 7), (3, 7), (4, 7), (5, 7), (6, 7)],
  // Green: row 7, cols 13-8 (right to center)
  LudoColor.green: [(7, 13), (7, 12), (7, 11), (7, 10), (7, 9), (7, 8)],
  // Yellow: col 7, rows 13-8 (bottom to center)
  LudoColor.yellow: [(13, 7), (12, 7), (11, 7), (10, 7), (9, 7), (8, 7)],
};

/// Home base coordinates (4 slots per color in the 6×6 corner areas).
/// These are where tokens sit before entering the board.
Map<LudoColor, List<(int, int)>> get homeBaseCoordinates => {
  // Red: top-left corner, 2×2 grid of slots
  LudoColor.red: [(1, 1), (1, 4), (4, 1), (4, 4)],
  // Blue: top-right corner
  LudoColor.blue: [(1, 10), (1, 13), (4, 10), (4, 13)],
  // Green: bottom-right corner
  LudoColor.green: [(10, 10), (10, 13), (13, 10), (13, 13)],
  // Yellow: bottom-left corner
  LudoColor.yellow: [(10, 1), (10, 4), (13, 1), (13, 4)],
};

/// Convert a token's position to (row, col) on the 15×15 visual board.
(int, int)? positionToGridCoord(LudoToken token) {
  if (token.isHome) {
    // In home base — use the slot based on tokenIndex
    final base = homeBaseCoordinates[token.color]!;
    if (token.tokenIndex < base.length) return base[token.tokenIndex];
    return null;
  }

  if (token.isOnTrack) {
    // On the shared track — convert relative to absolute, then look up
    final absolute = (token.color.startSquare + token.position) % 52;
    if (absolute < trackCoordinates.length) {
      return trackCoordinates[absolute];
    }
    return null;
  }

  if (token.isInHomeColumn) {
    // In home column — position 51-56 maps to index 0-5
    final homeCol = homeColumnCoordinates[token.color]!;
    final index = token.position - 51;
    if (index >= 0 && index < homeCol.length) return homeCol[index];
    return null;
  }

  if (token.isFinished) {
    // At center — use a slot near the center based on color
    return (7, 7); // center
  }

  return null;
}
