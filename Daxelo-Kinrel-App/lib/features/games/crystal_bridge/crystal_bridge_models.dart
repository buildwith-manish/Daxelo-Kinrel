// lib/features/games/crystal_bridge/crystal_bridge_models.dart
//
// Crystal Bridge — wire models for the multiplayer survival game.

import 'crystal_bridge_engine.dart';

export 'crystal_bridge_engine.dart'
    show
        CrystalBridgeType,
        CrystalBridgeTypeX,
        CrystalBridgePhase,
        CrystalBridgePhaseX,
        CrystalBridgePower,
        CrystalBridgePowerX,
        CrystalBridgeTeamMode,
        CrystalBridgeTeamModeX,
        CrystalBridgeRow,
        CrystalBridgePlayer,
        CrystalBridgeEvent,
        CrystalBridgeBoardState,
        CrystalBridgeEngine,
        kCrystalBridgeMinPlayers,
        kCrystalBridgeMaxPlayers,
        kCrystalBridgeDefaultTurnSeconds;

enum CrystalBridgeStatus { waiting, inProgress, completed }

extension CrystalBridgeStatusX on CrystalBridgeStatus {
  String get wire {
    switch (this) {
      case CrystalBridgeStatus.waiting:
        return 'waiting';
      case CrystalBridgeStatus.inProgress:
        return 'in_progress';
      case CrystalBridgeStatus.completed:
        return 'completed';
    }
  }

  static CrystalBridgeStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return CrystalBridgeStatus.inProgress;
      case 'completed':
        return CrystalBridgeStatus.completed;
      case 'waiting':
      default:
        return CrystalBridgeStatus.waiting;
    }
  }
}

class CrystalBridgePlayerWire {
  const CrystalBridgePlayerWire({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.joinedAt,
    this.isReady = false,
    this.leftAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final DateTime joinedAt;
  final bool isReady;
  final DateTime? leftAt;

  bool get isActive => leftAt == null;

  factory CrystalBridgePlayerWire.fromJson(Map<String, dynamic> json) =>
      CrystalBridgePlayerWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        userName: (json['userName'] ?? 'Player') as String,
        joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ??
            DateTime.now(),
        isReady: (json['isReady'] ?? false) as bool,
        leftAt: json['leftAt'] != null
            ? DateTime.tryParse(json['leftAt'] as String)
            : null,
      );
}

class CrystalBridgeGame {
  const CrystalBridgeGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.status,
    required this.maxPlayers,
    required this.createdAt,
    this.roomName,
    this.playerOrder = const [],
    this.turnEndsAt,
    this.boardState,
    this.winnerUserIds = const [],
    this.endReason,
    this.startedAt,
    this.completedAt,
    this.spectatorsEnabled = true,
    this.bridgeType = CrystalBridgeType.crystal,
    this.totalRows = 20,
    this.teamMode = CrystalBridgeTeamMode.solo,
    this.turnSeconds = kCrystalBridgeDefaultTurnSeconds,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final CrystalBridgeStatus status;
  final int maxPlayers;
  final DateTime createdAt;
  final String? roomName;
  final List<String> playerOrder;
  final DateTime? turnEndsAt;
  final CrystalBridgeBoardState? boardState;
  final List<String> winnerUserIds;
  final String? endReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool spectatorsEnabled;

  // Game-specific config
  final CrystalBridgeType bridgeType;
  final int totalRows;
  final CrystalBridgeTeamMode teamMode;
  final int turnSeconds;

  bool get isWaiting => status == CrystalBridgeStatus.waiting;
  bool get isInProgress => status == CrystalBridgeStatus.inProgress;
  bool get isCompleted => status == CrystalBridgeStatus.completed;

  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  factory CrystalBridgeGame.fromJson(Map<String, dynamic> json) {
    final order = <String>[];
    final rawOrder = json['playerOrder'];
    if (rawOrder is List) {
      order.addAll(rawOrder.whereType<String>());
    }
    final winners = <String>[];
    final rawWinners = json['winnerUserIds'];
    if (rawWinners is List) {
      winners.addAll(rawWinners.whereType<String>());
    }
    CrystalBridgeBoardState? boardState;
    final rawBoard = json['boardState'];
    if (rawBoard is Map<String, dynamic>) {
      boardState = CrystalBridgeBoardState.fromJson(rawBoard);
    }
    return CrystalBridgeGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: CrystalBridgeStatusX.fromString(json['status'] as String?),
      maxPlayers: (json['maxPlayers'] ?? 8) as int,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ??
          DateTime.now(),
      roomName: json['roomName'] as String?,
      playerOrder: order,
      turnEndsAt: json['turnEndsAt'] != null
          ? DateTime.tryParse(json['turnEndsAt'] as String)
          : null,
      boardState: boardState,
      winnerUserIds: winners,
      endReason: json['endReason'] as String?,
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      spectatorsEnabled: (json['spectatorsEnabled'] ?? true) as bool,
      bridgeType:
          CrystalBridgeTypeX.fromString(json['bridgeType'] as String?),
      totalRows: (json['totalRows'] as num?)?.toInt() ?? 20,
      teamMode:
          CrystalBridgeTeamModeX.fromString(json['teamMode'] as String?),
      turnSeconds: (json['turnSeconds'] as num?)?.toInt() ??
          kCrystalBridgeDefaultTurnSeconds,
    );
  }
}
