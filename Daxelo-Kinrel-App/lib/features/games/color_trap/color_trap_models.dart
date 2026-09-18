// lib/features/games/color_trap/color_trap_models.dart
import 'color_trap_engine.dart';

enum ColorTrapStatus { waiting, inProgress, completed }
extension ColorTrapStatusX on ColorTrapStatus {
  String get wire => switch (this) { ColorTrapStatus.waiting => 'waiting', ColorTrapStatus.inProgress => 'in_progress', ColorTrapStatus.completed => 'completed' };
  static ColorTrapStatus fromString(String? s) => switch (s) { 'in_progress' => ColorTrapStatus.inProgress, 'completed' => ColorTrapStatus.completed, _ => ColorTrapStatus.waiting };
}

class ColorTrapPlayerWire {
  const ColorTrapPlayerWire({required this.id, required this.gameId, required this.userId, required this.userName, required this.joinedAt, this.isReady = false, this.leftAt});
  final String id; final String gameId; final String userId; final String userName;
  final DateTime joinedAt; final bool isReady; final DateTime? leftAt;
  bool get isActive => leftAt == null;
  factory ColorTrapPlayerWire.fromJson(Map<String, dynamic> json) => ColorTrapPlayerWire(
    id: (json['id'] ?? '') as String, gameId: (json['gameId'] ?? '') as String,
    userId: (json['userId'] ?? '') as String, userName: (json['userName'] ?? 'Player') as String,
    joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
    isReady: (json['isReady'] ?? false) as bool,
    leftAt: json['leftAt'] != null ? DateTime.tryParse(json['leftAt'] as String) : null);
}

class ColorTrapGame {
  const ColorTrapGame({required this.id, required this.familyId, required this.hostUserId, required this.hostUserName, required this.status, required this.maxPlayers, required this.createdAt, this.roomName, this.playerOrder = const [], this.currentPlayerId, this.currentTurnIndex = 0, this.turnEndsAt, this.boardState, this.winnerUserIds = const [], this.endReason, this.startedAt, this.completedAt, this.spectatorsEnabled = true, this.difficulty = ColorTrapDifficulty.medium});
  final String id; final String familyId; final String hostUserId; final String hostUserName;
  final ColorTrapStatus status; final int maxPlayers; final DateTime createdAt;
  final String? roomName; final List<String> playerOrder; final String? currentPlayerId;
  final int currentTurnIndex; final DateTime? turnEndsAt; final ColorTrapGameState? boardState;
  final List<String> winnerUserIds; final String? endReason; final DateTime? startedAt;
  final DateTime? completedAt; final bool spectatorsEnabled; final ColorTrapDifficulty difficulty;
  bool get isWaiting => status == ColorTrapStatus.waiting;
  bool get isInProgress => status == ColorTrapStatus.inProgress;
  bool get isCompleted => status == ColorTrapStatus.completed;
  int? get turnSecondsRemaining { if (!isInProgress || turnEndsAt == null) return null; final left = turnEndsAt!.difference(DateTime.now()).inSeconds; return left < 0 ? 0 : left; }
  factory ColorTrapGame.fromJson(Map<String, dynamic> json) {
    final order = <String>[]; final rawOrder = json['playerOrder']; if (rawOrder is List) order.addAll(rawOrder.whereType<String>());
    final winners = <String>[]; final rawWinners = json['winnerUserIds']; if (rawWinners is List) winners.addAll(rawWinners.whereType<String>());
    ColorTrapGameState? boardState; final rawBoard = json['boardState']; if (rawBoard is Map<String, dynamic>) boardState = ColorTrapGameState.fromJson(rawBoard);
    return ColorTrapGame(
      id: (json['id'] ?? '') as String, familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String, hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: ColorTrapStatusX.fromString(json['status'] as String?),
      maxPlayers: (json['maxPlayers'] ?? 8) as int,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      roomName: json['roomName'] as String?, playerOrder: order,
      currentPlayerId: json['currentPlayerId'] as String?, currentTurnIndex: (json['currentTurnIndex'] ?? 0) as int,
      turnEndsAt: json['turnEndsAt'] != null ? DateTime.tryParse(json['turnEndsAt'] as String) : null,
      boardState: boardState, winnerUserIds: winners, endReason: json['endReason'] as String?,
      startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt'] as String) : null,
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
      spectatorsEnabled: (json['spectatorsEnabled'] ?? true) as bool,
      difficulty: ColorTrapDifficultyX.fromString(json['difficulty'] as String?));
  }
}
