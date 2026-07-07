// lib/features/games/ludo/ludo_models.dart
//
// Ludo — data models for the 2-4 player board game.

import 'ludo_game_logic.dart';

export 'ludo_game_logic.dart' show LudoColor, LudoColorX, LudoToken, LudoMoveResult;

enum LudoStatus { waiting, inProgress, completed }

extension LudoStatusX on LudoStatus {
  String get name {
    switch (this) {
      case LudoStatus.waiting:
        return 'waiting';
      case LudoStatus.inProgress:
        return 'in_progress';
      case LudoStatus.completed:
        return 'completed';
    }
  }

  static LudoStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return LudoStatus.inProgress;
      case 'completed':
        return LudoStatus.completed;
      case 'waiting':
      default:
        return LudoStatus.waiting;
    }
  }
}

class LudoGame {
  const LudoGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.status,
    required this.playerCount,
    this.currentTurnPlayerId,
    this.lastDiceRoll,
    required this.consecutiveSixes,
    required this.extraTurnPending,
    this.winnerId,
    this.winnerName,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final LudoStatus status;
  final int playerCount;
  final String? currentTurnPlayerId;
  final int? lastDiceRoll;
  final int consecutiveSixes;
  final bool extraTurnPending;
  final String? winnerId;
  final String? winnerName;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  factory LudoGame.fromJson(Map<String, dynamic> json) => LudoGame(
    id: json['id'] ?? '',
    familyId: json['familyId'] ?? '',
    hostUserId: json['hostUserId'] ?? '',
    hostUserName: json['hostUserName'] ?? 'Host',
    status: LudoStatusX.fromString(json['status']),
    playerCount: json['playerCount'] ?? 2,
    currentTurnPlayerId: json['currentTurnPlayerId'],
    lastDiceRoll: json['lastDiceRoll'],
    consecutiveSixes: json['consecutiveSixes'] ?? 0,
    extraTurnPending: json['extraTurnPending'] ?? false,
    winnerId: json['winnerId'],
    winnerName: json['winnerName'],
    startedAt: json['startedAt'] != null
        ? DateTime.tryParse(json['startedAt'])
        : null,
    completedAt: json['completedAt'] != null
        ? DateTime.tryParse(json['completedAt'])
        : null,
    createdAt:
        DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );

  bool get isWaiting => status == LudoStatus.waiting;
  bool get isInProgress => status == LudoStatus.inProgress;
  bool get isCompleted => status == LudoStatus.completed;
}

class LudoPlayer {
  const LudoPlayer({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.color,
    required this.turnOrder,
    required this.tokensFinished,
    required this.joinedAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final LudoColor color;
  final int turnOrder;
  final int tokensFinished;
  final DateTime joinedAt;

  factory LudoPlayer.fromJson(Map<String, dynamic> json) => LudoPlayer(
    id: json['id'] ?? '',
    gameId: json['gameId'] ?? '',
    userId: json['userId'] ?? '',
    userName: json['userName'] ?? 'Player',
    color: LudoColorX.fromString(json['color']),
    turnOrder: json['turnOrder'] ?? 0,
    tokensFinished: json['tokensFinished'] ?? 0,
    joinedAt:
        DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
  );
}

class LudoTokenModel {
  const LudoTokenModel({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.tokenIndex,
    required this.position,
    required this.color,
  });

  final String id;
  final String gameId;
  final String playerId;
  final int tokenIndex;
  final int position;
  final LudoColor color;

  factory LudoTokenModel.fromJson(Map<String, dynamic> json) =>
      LudoTokenModel(
        id: json['id'] ?? '',
        gameId: json['gameId'] ?? '',
        playerId: json['playerId'] ?? '',
        tokenIndex: json['tokenIndex'] ?? 0,
        position: json['position'] ?? -1,
        color: LudoColorX.fromString(
          // Color isn't stored on the token row — we look it up from players
          // But for convenience, we pass it in when converting
          json['color'],
        ),
      );

  /// Convert to the logic-layer LudoToken (which has the color).
  LudoToken toLogicToken() => LudoToken(
    id: id,
    playerId: playerId,
    tokenIndex: tokenIndex,
    position: position,
    color: color,
  );

  LudoTokenModel copyWith({int? position}) => LudoTokenModel(
    id: id,
    gameId: gameId,
    playerId: playerId,
    tokenIndex: tokenIndex,
    position: position ?? this.position,
    color: color,
  );
}

class LudoMoveRecord {
  const LudoMoveRecord({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.playerName,
    this.tokenId,
    this.tokenIndex,
    required this.diceValue,
    required this.fromPosition,
    required this.toPosition,
    this.capturedTokenId,
    this.capturedPlayerName,
    required this.moveNumber,
    required this.createdAt,
  });

  final String id;
  final String gameId;
  final String playerId;
  final String playerName;
  final String? tokenId;
  final int? tokenIndex;
  final int diceValue;
  final int fromPosition;
  final int toPosition;
  final String? capturedTokenId;
  final String? capturedPlayerName;
  final int moveNumber;
  final DateTime createdAt;

  factory LudoMoveRecord.fromJson(Map<String, dynamic> json) =>
      LudoMoveRecord(
        id: json['id'] ?? '',
        gameId: json['gameId'] ?? '',
        playerId: json['playerId'] ?? '',
        playerName: json['playerName'] ?? 'Player',
        tokenId: json['tokenId'],
        tokenIndex: json['tokenIndex'],
        diceValue: json['diceValue'] ?? 1,
        fromPosition: json['fromPosition'] ?? -1,
        toPosition: json['toPosition'] ?? -1,
        capturedTokenId: json['capturedTokenId'],
        capturedPlayerName: json['capturedPlayerName'],
        moveNumber: json['moveNumber'] ?? 0,
        createdAt:
            DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}
