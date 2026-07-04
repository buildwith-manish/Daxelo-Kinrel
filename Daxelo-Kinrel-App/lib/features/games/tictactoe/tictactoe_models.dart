// lib/features/games/tictactoe/tictactoe_models.dart

import 'tictactoe_game_logic.dart';

export 'tictactoe_game_logic.dart' show Mark, MarkX, RoundResult, RoundResultX;

enum TttStatus { waiting, inProgress, completed }
extension TttStatusX on TttStatus {
  String get name => switch (this) { TttStatus.waiting => 'waiting', TttStatus.inProgress => 'in_progress', TttStatus.completed => 'completed' };
  static TttStatus fromString(String? s) => switch (s) { 'in_progress' => TttStatus.inProgress, 'completed' => TttStatus.completed, _ => TttStatus.waiting };
}

class TttGame {
  const TttGame({required this.id, required this.familyId, required this.playerXId, required this.playerXName, required this.playerOId, required this.playerOName, required this.currentTurnPlayerId, required this.bestOf, required this.roundsWonX, required this.roundsWonO, required this.currentRound, required this.status, this.overallWinnerId, this.overallWinnerName, this.startedAt, this.completedAt, required this.createdAt});
  final String id; final String familyId; final String playerXId; final String playerXName; final String playerOId; final String playerOName; final String currentTurnPlayerId; final int bestOf; final int roundsWonX; final int roundsWonO; final int currentRound; final TttStatus status; final String? overallWinnerId; final String? overallWinnerName; final DateTime? startedAt; final DateTime? completedAt; final DateTime createdAt;

  factory TttGame.fromJson(Map<String, dynamic> json) => TttGame(
    id: json['id'] ?? '', familyId: json['familyId'] ?? '', playerXId: json['playerXId'] ?? '', playerXName: json['playerXName'] ?? 'Player 1',
    playerOId: json['playerOId'] ?? '', playerOName: json['playerOName'] ?? 'Player 2', currentTurnPlayerId: json['currentTurnPlayerId'] ?? '',
    bestOf: json['bestOf'] ?? 1, roundsWonX: json['roundsWonX'] ?? 0, roundsWonO: json['roundsWonO'] ?? 0, currentRound: json['currentRound'] ?? 1,
    status: TttStatusX.fromString(json['status']), overallWinnerId: json['overallWinnerId'], overallWinnerName: json['overallWinnerName'],
    startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt']) : null, completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt']) : null,
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );

  bool get isWaiting => status == TttStatus.waiting;
  bool get isInProgress => status == TttStatus.inProgress;
  bool get isCompleted => status == TttStatus.completed;

  Mark? markForPlayer(String? userId) { if (userId == playerXId) return Mark.x; if (userId == playerOId) return Mark.o; return null; }
  String? idForMark(Mark m) => m == Mark.x ? playerXId : playerOId;
  String nameForMark(Mark m) => m == Mark.x ? playerXName : playerOName;
  bool isMyTurn(String? userId) => currentTurnPlayerId == userId;
}

class TttRound {
  const TttRound({required this.id, required this.gameId, required this.roundNumber, required this.boardState, this.result, this.completedAt, required this.createdAt});
  final String id; final String gameId; final int roundNumber; final List<String?> boardState; final RoundResult? result; final DateTime? completedAt; final DateTime createdAt;

  factory TttRound.fromJson(Map<String, dynamic> json) => TttRound(
    id: json['id'] ?? '', gameId: json['gameId'] ?? '', roundNumber: json['roundNumber'] ?? 1,
    boardState: (json['boardState'] as List? ?? List.filled(9, null)).map((e) => e?.toString()).toList(),
    result: RoundResultX.fromString(json['result']), completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt']) : null,
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );
}

class TttMoveRecord {
  const TttMoveRecord({required this.id, required this.roundId, required this.playerId, required this.playerName, required this.cellIndex, required this.mark, required this.moveNumber, required this.createdAt});
  final String id; final String roundId; final String playerId; final String playerName; final int cellIndex; final String mark; final int moveNumber; final DateTime createdAt;

  factory TttMoveRecord.fromJson(Map<String, dynamic> json) => TttMoveRecord(
    id: json['id'] ?? '', roundId: json['roundId'] ?? '', playerId: json['playerId'] ?? '', playerName: json['playerName'] ?? 'Player',
    cellIndex: json['cellIndex'] ?? 0, mark: json['mark'] ?? 'X', moveNumber: json['moveNumber'] ?? 0,
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );
}
