// lib/features/games/impostor/impostor_models.dart
import 'impostor_engine.dart';

enum ImpostorStatus { waiting, inProgress, completed }
extension ImpostorStatusX on ImpostorStatus {
  String get wire => switch(this) {
    ImpostorStatus.waiting => 'waiting',
    ImpostorStatus.inProgress => 'in_progress',
    ImpostorStatus.completed => 'completed',
  };
  static ImpostorStatus fromString(String? s) => switch(s) {
    'in_progress' => ImpostorStatus.inProgress,
    'completed' => ImpostorStatus.completed,
    _ => ImpostorStatus.waiting,
  };
}

class ImpostorPlayer {
  const ImpostorPlayer({required this.id, required this.gameId, required this.userId, required this.userName, required this.joinedAt, this.isReady = false, this.leftAt});
  final String id; final String gameId; final String userId; final String userName;
  final DateTime joinedAt; final bool isReady; final DateTime? leftAt;
  bool get isActive => leftAt == null;
  factory ImpostorPlayer.fromJson(Map<String, dynamic> json) => ImpostorPlayer(
    id: (json['id'] ?? '') as String, gameId: (json['gameId'] ?? '') as String,
    userId: (json['userId'] ?? '') as String, userName: (json['userName'] ?? 'Player') as String,
    joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
    isReady: (json['isReady'] ?? false) as bool,
    leftAt: json['leftAt'] != null ? DateTime.tryParse(json['leftAt'] as String) : null,
  );
}

class ImpostorGame {
  const ImpostorGame({required this.id, required this.familyId, required this.hostUserId, required this.hostUserName, required this.status, required this.maxPlayers, required this.createdAt, this.roomName, this.playerOrder = const [], this.currentPlayerId, this.currentTurnIndex = 0, this.turnEndsAt, this.boardState, this.winnerUserIds = const [], this.endReason, this.startedAt, this.completedAt, this.spectatorsEnabled = true, this.totalRounds = 3, this.wordPackId = 'food', this.clueSeconds = 30, this.voteSeconds = 30});
  final String id; final String familyId; final String hostUserId; final String hostUserName;
  final ImpostorStatus status; final int maxPlayers; final DateTime createdAt;
  final String? roomName; final List<String> playerOrder; final String? currentPlayerId;
  final int currentTurnIndex; final DateTime? turnEndsAt; final ImpostorGameState? boardState;
  final List<String> winnerUserIds; final String? endReason; final DateTime? startedAt;
  final DateTime? completedAt; final bool spectatorsEnabled; final int totalRounds;
  final String wordPackId; final int clueSeconds; final int voteSeconds;
  bool get isWaiting => status == ImpostorStatus.waiting;
  bool get isInProgress => status == ImpostorStatus.inProgress;
  bool get isCompleted => status == ImpostorStatus.completed;
  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }
  factory ImpostorGame.fromJson(Map<String, dynamic> json) {
    final order = <String>[];
    final rawOrder = json['playerOrder'];
    if (rawOrder is List) order.addAll(rawOrder.whereType<String>());
    final winners = <String>[];
    final rawWinners = json['winnerUserIds'];
    if (rawWinners is List) winners.addAll(rawWinners.whereType<String>());
    ImpostorGameState? boardState;
    final rawBoard = json['boardState'];
    if (rawBoard is Map<String, dynamic>) boardState = ImpostorGameState.fromJson(rawBoard);
    return ImpostorGame(
      id: (json['id'] ?? '') as String, familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String, hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: ImpostorStatusX.fromString(json['status'] as String?),
      maxPlayers: (json['maxPlayers'] ?? 10) as int,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      roomName: json['roomName'] as String?, playerOrder: order,
      currentPlayerId: json['currentPlayerId'] as String?,
      currentTurnIndex: (json['currentTurnIndex'] ?? 0) as int,
      turnEndsAt: json['turnEndsAt'] != null ? DateTime.tryParse(json['turnEndsAt'] as String) : null,
      boardState: boardState, winnerUserIds: winners,
      endReason: json['endReason'] as String?,
      startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt'] as String) : null,
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
      spectatorsEnabled: (json['spectatorsEnabled'] ?? true) as bool,
      totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 3,
      wordPackId: (json['wordPackId'] as String?) ?? 'food',
      clueSeconds: (json['clueSeconds'] as num?)?.toInt() ?? 30,
      voteSeconds: (json['voteSeconds'] as num?)?.toInt() ?? 30,
    );
  }
}
