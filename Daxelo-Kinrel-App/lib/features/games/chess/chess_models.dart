// lib/features/games/chess/chess_models.dart
//
// Chess — data models for the 2-player standard chess game.
// Logic engine: chess.dart (MIT+BSD, port of chess.js)
// All UI is original to Kinrel — no visual assets copied from any source.

enum ChessStatus { waiting, inProgress, completed }

extension ChessStatusX on ChessStatus {
  String get name {
    switch (this) {
      case ChessStatus.waiting:
        return 'waiting';
      case ChessStatus.inProgress:
        return 'in_progress';
      case ChessStatus.completed:
        return 'completed';
    }
  }

  static ChessStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return ChessStatus.inProgress;
      case 'completed':
        return ChessStatus.completed;
      case 'waiting':
      default:
        return ChessStatus.waiting;
    }
  }
}

enum ChessColor { white, black }

extension ChessColorX on ChessColor {
  String get name {
    switch (this) {
      case ChessColor.white:
        return 'white';
      case ChessColor.black:
        return 'black';
    }
  }

  static ChessColor fromString(String? s) {
    return s == 'black' ? ChessColor.black : ChessColor.white;
  }
}

enum ChessResult { whiteWin, blackWin, draw, stalemate }

extension ChessResultX on ChessResult {
  String get name {
    switch (this) {
      case ChessResult.whiteWin:
        return 'white_win';
      case ChessResult.blackWin:
        return 'black_win';
      case ChessResult.draw:
        return 'draw';
      case ChessResult.stalemate:
        return 'stalemate';
    }
  }

  static ChessResult? fromString(String? s) {
    switch (s) {
      case 'white_win':
        return ChessResult.whiteWin;
      case 'black_win':
        return ChessResult.blackWin;
      case 'draw':
        return ChessResult.draw;
      case 'stalemate':
        return ChessResult.stalemate;
      default:
        return null;
    }
  }
}

class ChessGame {
  const ChessGame({
    required this.id,
    required this.familyId,
    required this.playerWhiteId,
    required this.playerWhiteName,
    required this.playerBlackId,
    required this.playerBlackName,
    required this.currentTurnColor,
    required this.boardState,
    required this.status,
    this.result,
    this.winnerId,
    this.winnerName,
    this.lastMoveAt,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String playerWhiteId;
  final String playerWhiteName;
  final String playerBlackId;
  final String playerBlackName;
  final ChessColor currentTurnColor;
  final String boardState; // FEN string
  final ChessStatus status;
  final ChessResult? result;
  final String? winnerId;
  final String? winnerName;
  final DateTime? lastMoveAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  factory ChessGame.fromJson(Map<String, dynamic> json) => ChessGame(
    id: json['id'] ?? '',
    familyId: json['familyId'] ?? '',
    playerWhiteId: json['playerWhiteId'] ?? '',
    playerWhiteName: json['playerWhiteName'] ?? 'Player 1',
    playerBlackId: json['playerBlackId'] ?? '',
    playerBlackName: json['playerBlackName'] ?? 'Player 2',
    currentTurnColor: ChessColorX.fromString(json['currentTurnColor']),
    boardState: json['boardState'] ?? '',
    status: ChessStatusX.fromString(json['status']),
    result: ChessResultX.fromString(json['result']),
    winnerId: json['winnerId'],
    winnerName: json['winnerName'],
    lastMoveAt: json['lastMoveAt'] != null
        ? DateTime.tryParse(json['lastMoveAt'])
        : null,
    startedAt: json['startedAt'] != null
        ? DateTime.tryParse(json['startedAt'])
        : null,
    completedAt: json['completedAt'] != null
        ? DateTime.tryParse(json['completedAt'])
        : null,
    createdAt:
        DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );

  bool get isWaiting => status == ChessStatus.waiting;
  bool get isInProgress => status == ChessStatus.inProgress;
  bool get isCompleted => status == ChessStatus.completed;

  /// Which player ID is the given color?
  String? playerIdForColor(ChessColor color) {
    switch (color) {
      case ChessColor.white:
        return playerWhiteId;
      case ChessColor.black:
        return playerBlackId;
    }
  }

  /// Which color is the given player?
  ChessColor? colorForPlayerId(String? userId) {
    if (userId == null) return null;
    if (userId == playerWhiteId) return ChessColor.white;
    if (userId == playerBlackId) return ChessColor.black;
    return null;
  }

  /// Is it this player's turn?
  bool isMyTurn(String? userId) {
    final myColor = colorForPlayerId(userId);
    return myColor != null && myColor == currentTurnColor;
  }
}

class ChessMoveRecord {
  const ChessMoveRecord({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.fromSquare,
    required this.toSquare,
    required this.pieceMoved,
    this.capturedPiece,
    this.specialMove,
    this.promotedTo,
    required this.moveNumber,
    required this.notation,
    required this.createdAt,
  });

  final String id;
  final String gameId;
  final String playerId;
  final String playerName;
  final String fromSquare;
  final String toSquare;
  final String pieceMoved;
  final String? capturedPiece;
  final String? specialMove;
  final String? promotedTo;
  final int moveNumber;
  final String notation;
  final DateTime createdAt;

  factory ChessMoveRecord.fromJson(Map<String, dynamic> json) =>
      ChessMoveRecord(
        id: json['id'] ?? '',
        gameId: json['gameId'] ?? '',
        playerId: json['playerId'] ?? '',
        playerName: json['playerName'] ?? 'Player',
        fromSquare: json['fromSquare'] ?? '',
        toSquare: json['toSquare'] ?? '',
        pieceMoved: json['pieceMoved'] ?? '',
        capturedPiece: json['capturedPiece'],
        specialMove: json['specialMove'],
        promotedTo: json['promotedTo'],
        moveNumber: json['moveNumber'] ?? 0,
        notation: json['notation'] ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}

/// The starting FEN for a standard chess game.
const String initialFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
