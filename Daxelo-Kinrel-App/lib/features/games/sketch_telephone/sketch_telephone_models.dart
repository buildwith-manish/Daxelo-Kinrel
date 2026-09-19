// lib/features/games/sketch_telephone/sketch_telephone_models.dart
//
// Sketch Telephone — wire models for the multiplayer drawing-chain game.

import 'sketch_telephone_engine.dart';

export 'sketch_telephone_engine.dart'
    show
        SketchStepType,
        SketchStepTypeX,
        SketchPhase,
        SketchPhaseX,
        SketchStrokePoint,
        SketchStroke,
        SketchChainStep,
        SketchChain,
        SketchPlayerInfo,
        SketchBoardState,
        SketchTelephoneEngine,
        stepTypeForIndex,
        phaseForStep,
        kSketchTelephoneMinPlayers,
        kSketchTelephoneMaxPlayers,
        kSketchTelephoneDefaultDrawingSeconds,
        kSketchTelephoneMaxPromptLength,
        kSketchTelephoneMaxDescriptionLength;

enum SketchTelephoneStatus { waiting, inProgress, completed }

extension SketchTelephoneStatusX on SketchTelephoneStatus {
  String get wire {
    switch (this) {
      case SketchTelephoneStatus.waiting:
        return 'waiting';
      case SketchTelephoneStatus.inProgress:
        return 'in_progress';
      case SketchTelephoneStatus.completed:
        return 'completed';
    }
  }

  static SketchTelephoneStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return SketchTelephoneStatus.inProgress;
      case 'completed':
        return SketchTelephoneStatus.completed;
      case 'waiting':
      default:
        return SketchTelephoneStatus.waiting;
    }
  }
}

class SketchTelephonePlayerWire {
  const SketchTelephonePlayerWire({
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

  factory SketchTelephonePlayerWire.fromJson(Map<String, dynamic> json) =>
      SketchTelephonePlayerWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        userName: (json['userName'] ?? 'Player') as String,
        joinedAt:
            DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
        isReady: (json['isReady'] ?? false) as bool,
        leftAt: json['leftAt'] != null
            ? DateTime.tryParse(json['leftAt'] as String)
            : null,
      );
}

class SketchTelephoneGame {
  const SketchTelephoneGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.status,
    required this.maxPlayers,
    required this.createdAt,
    this.roomName,
    this.playerOrder = const [],
    this.currentPlayerId,
    this.currentTurnIndex = 0,
    this.turnEndsAt,
    this.boardState,
    this.winnerUserIds = const [],
    this.endReason,
    this.startedAt,
    this.completedAt,
    this.spectatorsEnabled = true,
    this.drawingSeconds = 90,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final SketchTelephoneStatus status;
  final int maxPlayers;
  final DateTime createdAt;
  final String? roomName;
  final List<String> playerOrder;
  final String? currentPlayerId;
  final int currentTurnIndex;
  final DateTime? turnEndsAt;
  final SketchBoardState? boardState;
  final List<String> winnerUserIds;
  final String? endReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool spectatorsEnabled;

  // Game-specific config
  final int drawingSeconds;

  bool get isWaiting => status == SketchTelephoneStatus.waiting;
  bool get isInProgress => status == SketchTelephoneStatus.inProgress;
  bool get isCompleted => status == SketchTelephoneStatus.completed;

  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  factory SketchTelephoneGame.fromJson(Map<String, dynamic> json) {
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
    SketchBoardState? boardState;
    final rawBoard = json['boardState'];
    if (rawBoard is Map<String, dynamic>) {
      boardState = SketchBoardState.fromJson(rawBoard);
    }
    return SketchTelephoneGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: SketchTelephoneStatusX.fromString(json['status'] as String?),
      maxPlayers: (json['maxPlayers'] ?? 8) as int,
      createdAt:
          DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      roomName: json['roomName'] as String?,
      playerOrder: order,
      currentPlayerId: json['currentPlayerId'] as String?,
      currentTurnIndex: (json['currentTurnIndex'] ?? 0) as int,
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
      drawingSeconds:
          (json['drawingSeconds'] as num?)?.toInt() ?? 90,
    );
  }
}

/// One row from sketch_telephone_chains (RLS lets every family member
/// read every row — the reveal phase needs that. During active play the
/// UI only surfaces the player's currently-assigned chain's previous
/// step, so other rows are present but not shown.)
class SketchChainWire {
  const SketchChainWire({
    required this.id,
    required this.gameId,
    required this.chainIndex,
    required this.stepIndex,
    required this.stepType,
    required this.content,
    required this.authorUserId,
    required this.authorUserName,
    required this.submittedAt,
  });

  final String id;
  final String gameId;
  final int chainIndex;
  final int stepIndex;
  final SketchStepType stepType;
  final String content;
  final String authorUserId;
  final String authorUserName;
  final DateTime submittedAt;

  factory SketchChainWire.fromJson(Map<String, dynamic> json) =>
      SketchChainWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        chainIndex: (json['chainIndex'] as num?)?.toInt() ?? 0,
        stepIndex: (json['stepIndex'] as num?)?.toInt() ?? 0,
        stepType: SketchStepTypeX.fromString(json['stepType'] as String?),
        content: (json['content'] ?? '') as String,
        authorUserId: (json['authorUserId'] ?? '') as String,
        authorUserName: (json['authorUserName'] ?? 'Player') as String,
        submittedAt: DateTime.tryParse(json['submittedAt'] ?? '') ??
            DateTime.now(),
      );
}
