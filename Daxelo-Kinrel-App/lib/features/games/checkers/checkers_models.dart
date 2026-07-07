// lib/features/games/checkers/checkers_models.dart
//
// Checkers — data models for the 2-player board game.

import 'checkers_game_logic.dart';

export 'checkers_game_logic.dart' show CheckersPiece, CheckersMove, CheckersBoard;

enum CheckersStatus { waiting, inProgress, completed }

extension CheckersStatusX on CheckersStatus {
  String get name {
    switch (this) {
      case CheckersStatus.waiting:
        return 'waiting';
      case CheckersStatus.inProgress:
        return 'in_progress';
      case CheckersStatus.completed:
        return 'completed';
    }
  }

  static CheckersStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return CheckersStatus.inProgress;
      case 'completed':
        return CheckersStatus.completed;
      case 'waiting':
      default:
        return CheckersStatus.waiting;
    }
  }
}

class CheckersGame {
  const CheckersGame({
    required this.id,
    required this.familyId,
    required this.playerOneId,
    required this.playerOneName,
    required this.playerTwoId,
    required this.playerTwoName,
    required this.currentTurnPlayerId,
    required this.boardState,
    required this.status,
    this.winnerId,
    this.winnerName,
    required this.mandatoryCapturePending,
    this.multiJumpPieceRow,
    this.multiJumpPieceCol,
    required this.playerOneCaptured,
    required this.playerTwoCaptured,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String playerOneId; // red (bottom)
  final String playerOneName;
  final String playerTwoId; // black (top)
  final String playerTwoName;
  final String currentTurnPlayerId;
  final CheckersBoard boardState;
  final CheckersStatus status;
  final String? winnerId;
  final String? winnerName;
  final bool mandatoryCapturePending;
  final int? multiJumpPieceRow;
  final int? multiJumpPieceCol;
  final int playerOneCaptured;
  final int playerTwoCaptured;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  factory CheckersGame.fromJson(Map<String, dynamic> json) => CheckersGame(
    id: json['id'] ?? '',
    familyId: json['familyId'] ?? '',
    playerOneId: json['playerOneId'] ?? '',
    playerOneName: json['playerOneName'] ?? 'Player 1',
    playerTwoId: json['playerTwoId'] ?? '',
    playerTwoName: json['playerTwoName'] ?? 'Player 2',
    currentTurnPlayerId: json['currentTurnPlayerId'] ?? '',
    boardState: boardFromJson(json['boardState'] as List? ?? []),
    status: CheckersStatusX.fromString(json['status']),
    winnerId: json['winnerId'],
    winnerName: json['winnerName'],
    mandatoryCapturePending: json['mandatoryCapturePending'] ?? false,
    multiJumpPieceRow: json['multiJumpPieceRow'],
    multiJumpPieceCol: json['multiJumpPieceCol'],
    playerOneCaptured: json['playerOneCaptured'] ?? 0,
    playerTwoCaptured: json['playerTwoCaptured'] ?? 0,
    startedAt: json['startedAt'] != null
        ? DateTime.tryParse(json['startedAt'])
        : null,
    completedAt: json['completedAt'] != null
        ? DateTime.tryParse(json['completedAt'])
        : null,
    createdAt:
        DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );

  bool get isWaiting => status == CheckersStatus.waiting;
  bool get isInProgress => status == CheckersStatus.inProgress;
  bool get isCompleted => status == CheckersStatus.completed;

  /// Which player number (1 or 2) is the given userId?
  int? playerNumberFor(String? userId) {
    if (userId == null) return null;
    if (userId == playerOneId) return 1;
    if (userId == playerTwoId) return 2;
    return null;
  }

  String? nameForPlayer(int playerNumber) {
    switch (playerNumber) {
      case 1:
        return playerOneName;
      case 2:
        return playerTwoName;
      default:
        return null;
    }
  }

  String? idForPlayer(int playerNumber) {
    switch (playerNumber) {
      case 1:
        return playerOneId;
      case 2:
        return playerTwoId;
      default:
        return null;
    }
  }
}

class CheckersMoveRecord {
  const CheckersMoveRecord({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.fromRow,
    required this.fromCol,
    required this.toRow,
    required this.toCol,
    required this.wasCapture,
    this.capturedRow,
    this.capturedCol,
    required this.becameKing,
    required this.moveNumber,
    required this.createdAt,
  });

  final String id;
  final String gameId;
  final String playerId;
  final String playerName;
  final int fromRow;
  final int fromCol;
  final int toRow;
  final int toCol;
  final bool wasCapture;
  final int? capturedRow;
  final int? capturedCol;
  final bool becameKing;
  final int moveNumber;
  final DateTime createdAt;

  factory CheckersMoveRecord.fromJson(Map<String, dynamic> json) =>
      CheckersMoveRecord(
        id: json['id'] ?? '',
        gameId: json['gameId'] ?? '',
        playerId: json['playerId'] ?? '',
        playerName: json['playerName'] ?? 'Player',
        fromRow: json['fromRow'] ?? 0,
        fromCol: json['fromCol'] ?? 0,
        toRow: json['toRow'] ?? 0,
        toCol: json['toCol'] ?? 0,
        wasCapture: json['wasCapture'] ?? false,
        capturedRow: json['capturedRow'],
        capturedCol: json['capturedCol'],
        becameKing: json['becameKing'] ?? false,
        moveNumber: json['moveNumber'] ?? 0,
        createdAt:
            DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}
