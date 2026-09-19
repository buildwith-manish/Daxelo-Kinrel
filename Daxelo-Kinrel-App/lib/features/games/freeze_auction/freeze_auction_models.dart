// lib/features/games/freeze_auction/freeze_auction_models.dart
import 'freeze_auction_engine.dart';

enum FreezeAuctionStatus { waiting, inProgress, completed }
extension FreezeAuctionStatusX on FreezeAuctionStatus {
  String get wire => switch (this) { FreezeAuctionStatus.waiting => 'waiting', FreezeAuctionStatus.inProgress => 'in_progress', FreezeAuctionStatus.completed => 'completed' };
  static FreezeAuctionStatus fromString(String? s) => switch (s) { 'in_progress' => FreezeAuctionStatus.inProgress, 'completed' => FreezeAuctionStatus.completed, _ => FreezeAuctionStatus.waiting };
}

class FreezeAuctionPlayerWire {
  const FreezeAuctionPlayerWire({required this.id, required this.gameId, required this.userId, required this.userName, required this.joinedAt, this.isReady = false, this.leftAt});
  final String id; final String gameId; final String userId; final String userName;
  final DateTime joinedAt; final bool isReady; final DateTime? leftAt;
  bool get isActive => leftAt == null;
  factory FreezeAuctionPlayerWire.fromJson(Map<String, dynamic> json) => FreezeAuctionPlayerWire(
    id: (json['id'] ?? '') as String, gameId: (json['gameId'] ?? '') as String,
    userId: (json['userId'] ?? '') as String, userName: (json['userName'] ?? 'Player') as String,
    joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
    isReady: (json['isReady'] ?? false) as bool,
    leftAt: json['leftAt'] != null ? DateTime.tryParse(json['leftAt'] as String) : null);
}

class FreezeAuctionGame {
  const FreezeAuctionGame({required this.id, required this.familyId, required this.hostUserId, required this.hostUserName, required this.status, required this.maxPlayers, required this.createdAt, this.roomName, this.playerOrder = const [], this.currentPlayerId, this.currentTurnIndex = 0, this.turnEndsAt, this.boardState, this.winnerUserIds = const [], this.endReason, this.startedAt, this.completedAt, this.spectatorsEnabled = true, this.totalRounds = 5, this.startingCoins = 100, this.itemPoolId = 'normal'});
  final String id; final String familyId; final String hostUserId; final String hostUserName;
  final FreezeAuctionStatus status; final int maxPlayers; final DateTime createdAt;
  final String? roomName; final List<String> playerOrder; final String? currentPlayerId;
  final int currentTurnIndex; final DateTime? turnEndsAt; final FreezeAuctionState? boardState;
  final List<String> winnerUserIds; final String? endReason; final DateTime? startedAt;
  final DateTime? completedAt; final bool spectatorsEnabled; final int totalRounds;
  final int startingCoins; final String itemPoolId;
  bool get isWaiting => status == FreezeAuctionStatus.waiting;
  bool get isInProgress => status == FreezeAuctionStatus.inProgress;
  bool get isCompleted => status == FreezeAuctionStatus.completed;
  int? get turnSecondsRemaining { if (!isInProgress || turnEndsAt == null) return null; final left = turnEndsAt!.difference(DateTime.now()).inSeconds; return left < 0 ? 0 : left; }
  factory FreezeAuctionGame.fromJson(Map<String, dynamic> json) {
    final order = <String>[]; final rawOrder = json['playerOrder']; if (rawOrder is List) order.addAll(rawOrder.whereType<String>());
    final winners = <String>[]; final rawWinners = json['winnerUserIds']; if (rawWinners is List) winners.addAll(rawWinners.whereType<String>());
    FreezeAuctionState? boardState; final rawBoard = json['boardState']; if (rawBoard is Map<String, dynamic>) boardState = FreezeAuctionState.fromJson(rawBoard);
    return FreezeAuctionGame(
      id: (json['id'] ?? '') as String, familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String, hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: FreezeAuctionStatusX.fromString(json['status'] as String?),
      maxPlayers: (json['maxPlayers'] ?? 8) as int,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      roomName: json['roomName'] as String?, playerOrder: order,
      currentPlayerId: json['currentPlayerId'] as String?, currentTurnIndex: (json['currentTurnIndex'] ?? 0) as int,
      turnEndsAt: json['turnEndsAt'] != null ? DateTime.tryParse(json['turnEndsAt'] as String) : null,
      boardState: boardState, winnerUserIds: winners, endReason: json['endReason'] as String?,
      startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt'] as String) : null,
      completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt'] as String) : null,
      spectatorsEnabled: (json['spectatorsEnabled'] ?? true) as bool,
      totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 5,
      startingCoins: (json['startingCoins'] as num?)?.toInt() ?? 100,
      itemPoolId: (json['itemPoolId'] as String?) ?? 'normal');
  }
}
