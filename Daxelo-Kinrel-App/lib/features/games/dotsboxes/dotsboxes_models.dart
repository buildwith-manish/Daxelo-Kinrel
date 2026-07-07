// lib/features/games/dotsboxes/dotsboxes_models.dart
import 'dotsboxes_game_logic.dart';

export 'dotsboxes_game_logic.dart' show LineType, LineTypeX, DotsLine, DotsBox, DrawLineResult;

enum DbStatus { waiting, inProgress, completed }
extension DbStatusX on DbStatus {
  String get name => switch (this) { DbStatus.waiting => 'waiting', DbStatus.inProgress => 'in_progress', DbStatus.completed => 'completed' };
  static DbStatus fromString(String? s) => switch (s) { 'in_progress' => DbStatus.inProgress, 'completed' => DbStatus.completed, _ => DbStatus.waiting };
}

class DbGame {
  const DbGame({required this.id, required this.familyId, required this.hostUserId, required this.hostUserName, required this.status, required this.gridSize, this.currentTurnPlayerId, required this.bonusTurn, this.winnerUserIds, this.winnerNames, this.startedAt, this.completedAt, required this.createdAt});
  final String id; final String familyId; final String hostUserId; final String hostUserName; final DbStatus status; final int gridSize; final String? currentTurnPlayerId; final bool bonusTurn; final List<String>? winnerUserIds; final List<String>? winnerNames; final DateTime? startedAt; final DateTime? completedAt; final DateTime createdAt;
  factory DbGame.fromJson(Map<String, dynamic> json) => DbGame(id: json['id'] ?? '', familyId: json['familyId'] ?? '', hostUserId: json['hostUserId'] ?? '', hostUserName: json['hostUserName'] ?? 'Host', status: DbStatusX.fromString(json['status']), gridSize: json['gridSize'] ?? 5, currentTurnPlayerId: json['currentTurnPlayerId'], bonusTurn: json['bonusTurn'] ?? false, winnerUserIds: (json['winnerUserIds'] as List?)?.map((e) => e.toString()).toList(), winnerNames: (json['winnerNames'] as List?)?.map((e) => e.toString()).toList(), startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt']) : null, completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt']) : null, createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now());
  bool get isWaiting => status == DbStatus.waiting; bool get isInProgress => status == DbStatus.inProgress; bool get isCompleted => status == DbStatus.completed;
}

class DbPlayer {
  const DbPlayer({required this.id, required this.gameId, required this.userId, required this.userName, required this.turnOrder, required this.playerColor, required this.boxesCaptured, required this.joinedAt});
  final String id; final String gameId; final String userId; final String userName; final int turnOrder; final int playerColor; final int boxesCaptured; final DateTime joinedAt;
  factory DbPlayer.fromJson(Map<String, dynamic> json) => DbPlayer(id: json['id'] ?? '', gameId: json['gameId'] ?? '', userId: json['userId'] ?? '', userName: json['userName'] ?? 'Player', turnOrder: json['turnOrder'] ?? 0, playerColor: json['playerColor'] ?? 0, boxesCaptured: json['boxesCaptured'] ?? 0, joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now());
}

class DbLineRecord {
  const DbLineRecord({required this.id, required this.gameId, required this.lineType, required this.row, required this.col, required this.drawnByPlayerId, required this.drawnByPlayerName, required this.createdAt});
  final String id; final String gameId; final String lineType; final int row; final int col; final String drawnByPlayerId; final String drawnByPlayerName; final DateTime createdAt;
  factory DbLineRecord.fromJson(Map<String, dynamic> json) => DbLineRecord(id: json['id'] ?? '', gameId: json['gameId'] ?? '', lineType: json['lineType'] ?? 'horizontal', row: json['row'] ?? 0, col: json['col'] ?? 0, drawnByPlayerId: json['drawnByPlayerId'] ?? '', drawnByPlayerName: json['drawnByPlayerName'] ?? 'Player', createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now());
  DotsLine toDotsLine() => DotsLine(type: LineTypeX.fromString(lineType), row: row, col: col);
}

class DbBoxRecord {
  const DbBoxRecord({required this.id, required this.gameId, required this.boxRow, required this.boxCol, this.capturedByPlayerId, this.capturedByPlayerName, this.capturedAt});
  final String id; final String gameId; final int boxRow; final int boxCol; final String? capturedByPlayerId; final String? capturedByPlayerName; final DateTime? capturedAt;
  factory DbBoxRecord.fromJson(Map<String, dynamic> json) => DbBoxRecord(id: json['id'] ?? '', gameId: json['gameId'] ?? '', boxRow: json['boxRow'] ?? 0, boxCol: json['boxCol'] ?? 0, capturedByPlayerId: json['capturedByPlayerId'], capturedByPlayerName: json['capturedByPlayerName'], capturedAt: json['capturedAt'] != null ? DateTime.tryParse(json['capturedAt']) : null);
  bool get isCaptured => capturedByPlayerId != null;
}

/// Player colors matching Kinrel brand palette.
List<int> get dbPlayerColors => [0xFFE8612A, 0xFF3B82F6, 0xFF2DD4BF, 0xFFD4AF37]; // orange, blue, teal, gold
