// lib/features/games/carrom/carrom_models.dart
//
// Carrom — data models for the 2-player physics board game.

import 'carrom_constants.dart';
import 'carrom_game_logic.dart';

export 'carrom_constants.dart'
    show
        CarromCoinType,
        CarromCoinTypeX,
        CarromQueenStatus,
        CarromQueenStatusX,
        CarromStatus,
        CarromStatusX,
        CarromBoard,
        CarromPhysics;
export 'carrom_game_logic.dart' show CarromCoin, TurnResult;

class CarromGame {
  const CarromGame({
    required this.id,
    required this.familyId,
    required this.playerOneId,
    required this.playerOneName,
    required this.playerTwoId,
    required this.playerTwoName,
    required this.currentTurnPlayerId,
    required this.status,
    required this.playerOneColor,
    required this.playerTwoColor,
    required this.boardState,
    required this.strikerX,
    required this.strikerY,
    required this.playerOneScore,
    required this.playerTwoScore,
    required this.queenStatus,
    this.queenPottedBy,
    this.winnerId,
    this.winnerName,
    this.lastTurnSummary,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String playerOneId;
  final String playerOneName;
  final String playerTwoId;
  final String playerTwoName;
  final String currentTurnPlayerId;
  final CarromStatus status;
  final CarromCoinType playerOneColor;
  final CarromCoinType playerTwoColor;
  final List<CarromCoin> boardState;
  final double strikerX;
  final double strikerY;
  final int playerOneScore;
  final int playerTwoScore;
  final CarromQueenStatus queenStatus;
  final String? queenPottedBy;
  final String? winnerId;
  final String? winnerName;
  final Map<String, dynamic>? lastTurnSummary;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  factory CarromGame.fromJson(Map<String, dynamic> json) => CarromGame(
    id: json['id'] ?? '',
    familyId: json['familyId'] ?? '',
    playerOneId: json['playerOneId'] ?? '',
    playerOneName: json['playerOneName'] ?? 'Player 1',
    playerTwoId: json['playerTwoId'] ?? '',
    playerTwoName: json['playerTwoName'] ?? 'Player 2',
    currentTurnPlayerId: json['currentTurnPlayerId'] ?? '',
    status: CarromStatusX.fromString(json['status']),
    playerOneColor: CarromCoinTypeX.fromString(json['playerOneColor']),
    playerTwoColor: CarromCoinTypeX.fromString(json['playerTwoColor']),
    boardState: (json['boardState'] as List? ?? [])
        .map((c) => CarromCoin.fromJson(c as Map<String, dynamic>))
        .toList(),
    strikerX: (json['strikerX'] as num?)?.toDouble() ?? 0,
    strikerY: (json['strikerY'] as num?)?.toDouble() ?? 0,
    playerOneScore: json['playerOneScore'] ?? 0,
    playerTwoScore: json['playerTwoScore'] ?? 0,
    queenStatus: CarromQueenStatusX.fromString(json['queenStatus']),
    queenPottedBy: json['queenPottedBy'],
    winnerId: json['winnerId'],
    winnerName: json['winnerName'],
    lastTurnSummary: json['lastTurnSummary'] as Map<String, dynamic>?,
    startedAt: json['startedAt'] != null
        ? DateTime.tryParse(json['startedAt'])
        : null,
    completedAt: json['completedAt'] != null
        ? DateTime.tryParse(json['completedAt'])
        : null,
    createdAt:
        DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );

  bool get isWaiting => status == CarromStatus.waiting;
  bool get isInProgress => status == CarromStatus.inProgress;
  bool get isCompleted => status == CarromStatus.completed;

  int? playerNumberFor(String? userId) {
    if (userId == null) return null;
    if (userId == playerOneId) return 1;
    if (userId == playerTwoId) return 2;
    return null;
  }

  CarromCoinType? colorFor(String? userId) {
    final n = playerNumberFor(userId);
    if (n == 1) return playerOneColor;
    if (n == 2) return playerTwoColor;
    return null;
  }
}

class CarromTurnRecord {
  const CarromTurnRecord({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.strikerStartX,
    required this.strikerStartY,
    required this.angle,
    required this.force,
    required this.pottedCoins,
    required this.wasFoul,
    this.foulReason,
    required this.extraTurn,
    required this.queenPotted,
    required this.queenCovered,
    required this.turnNumber,
    required this.createdAt,
  });

  final String id;
  final String gameId;
  final String playerId;
  final String playerName;
  final double strikerStartX;
  final double strikerStartY;
  final double angle;
  final double force;
  final List<String> pottedCoins;
  final bool wasFoul;
  final String? foulReason;
  final bool extraTurn;
  final bool queenPotted;
  final bool queenCovered;
  final int turnNumber;
  final DateTime createdAt;

  factory CarromTurnRecord.fromJson(Map<String, dynamic> json) =>
      CarromTurnRecord(
        id: json['id'] ?? '',
        gameId: json['gameId'] ?? '',
        playerId: json['playerId'] ?? '',
        playerName: json['playerName'] ?? 'Player',
        strikerStartX: (json['strikerStartX'] as num?)?.toDouble() ?? 0,
        strikerStartY: (json['strikerStartY'] as num?)?.toDouble() ?? 0,
        angle: (json['angle'] as num?)?.toDouble() ?? 0,
        force: (json['force'] as num?)?.toDouble() ?? 0,
        pottedCoins: (json['pottedCoins'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        wasFoul: json['wasFoul'] ?? false,
        foulReason: json['foulReason'],
        extraTurn: json['extraTurn'] ?? false,
        queenPotted: json['queenPotted'] ?? false,
        queenCovered: json['queenCovered'] ?? false,
        turnNumber: json['turnNumber'] ?? 0,
        createdAt:
            DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}
