// lib/features/games/code_clues/code_clues_models.dart
//
// Code Clues — wire models for the multiplayer party game.

import 'code_clues_engine.dart';

export 'code_clues_engine.dart'
    show
        CodeCluesAssignment,
        CodeCluesPhase,
        CodeCluesPhaseX,
        CodeCluesPlayer,
        CodeCluesLogEntry,
        CodeCluesBoardState,
        CodeCluesEngine,
        wordAssignmentLabel,
        kCodeCluesMinPlayers,
        kCodeCluesMaxPlayers,
        kCodeCluesDefaultClueSeconds,
        kCodeCluesDefaultGuessSeconds,
        kCodeCluesMaxClueLength,
        kCodeCluesMaxClueNumber,
        kCodeCluesGridSize,
        kCodeCluesTeam1Total,
        kCodeCluesTeam2Total;

enum CodeCluesStatus { waiting, inProgress, completed }

extension CodeCluesStatusX on CodeCluesStatus {
  String get wire {
    switch (this) {
      case CodeCluesStatus.waiting:
        return 'waiting';
      case CodeCluesStatus.inProgress:
        return 'in_progress';
      case CodeCluesStatus.completed:
        return 'completed';
    }
  }

  static CodeCluesStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return CodeCluesStatus.inProgress;
      case 'completed':
        return CodeCluesStatus.completed;
      case 'waiting':
      default:
        return CodeCluesStatus.waiting;
    }
  }
}

class CodeCluesPlayerWire {
  const CodeCluesPlayerWire({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.team,
    required this.isSpymaster,
    required this.isReady,
    required this.joinedAt,
    this.leftAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;

  /// 1 (red) or 2 (blue).
  final int team;
  final bool isSpymaster;
  final bool isReady;
  final DateTime joinedAt;
  final DateTime? leftAt;

  bool get isActive => leftAt == null;

  CodeCluesPlayerWire copyWith({
    int? team,
    bool? isSpymaster,
    bool? isReady,
    DateTime? leftAt,
  }) =>
      CodeCluesPlayerWire(
        id: id,
        gameId: gameId,
        userId: userId,
        userName: userName,
        team: team ?? this.team,
        isSpymaster: isSpymaster ?? this.isSpymaster,
        isReady: isReady ?? this.isReady,
        joinedAt: joinedAt,
        leftAt: leftAt ?? this.leftAt,
      );

  factory CodeCluesPlayerWire.fromJson(Map<String, dynamic> json) =>
      CodeCluesPlayerWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        userName: (json['userName'] ?? 'Player') as String,
        team: (json['team'] as num?)?.toInt() ?? 1,
        isSpymaster: (json['isSpymaster'] as bool?) ?? false,
        isReady: (json['isReady'] as bool?) ?? false,
        joinedAt:
            DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
        leftAt: json['leftAt'] != null
            ? DateTime.tryParse(json['leftAt'] as String)
            : null,
      );
}

class CodeCluesGame {
  const CodeCluesGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.status,
    required this.maxPlayers,
    required this.createdAt,
    this.roomName,
    this.playerOrder = const [],
    this.currentTurnTeam = 1,
    this.turnEndsAt,
    this.boardState,
    this.winnerUserIds = const [],
    this.winningTeam,
    this.endReason,
    this.startedAt,
    this.completedAt,
    this.spectatorsEnabled = true,
    this.clueSeconds = kCodeCluesDefaultClueSeconds,
    this.guessSeconds = kCodeCluesDefaultGuessSeconds,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final CodeCluesStatus status;
  final int maxPlayers;
  final DateTime createdAt;
  final String? roomName;
  final List<String> playerOrder;
  final int currentTurnTeam;
  final DateTime? turnEndsAt;
  final CodeCluesBoardState? boardState;
  final List<String> winnerUserIds;
  final int? winningTeam;
  final String? endReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool spectatorsEnabled;
  final int clueSeconds;
  final int guessSeconds;

  bool get isWaiting => status == CodeCluesStatus.waiting;
  bool get isInProgress => status == CodeCluesStatus.inProgress;
  bool get isCompleted => status == CodeCluesStatus.completed;

  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  factory CodeCluesGame.fromJson(Map<String, dynamic> json) {
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
    CodeCluesBoardState? boardState;
    final rawBoard = json['boardState'];
    if (rawBoard is Map<String, dynamic>) {
      boardState = CodeCluesBoardState.fromJson(rawBoard);
    }
    return CodeCluesGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: CodeCluesStatusX.fromString(json['status'] as String?),
      maxPlayers: (json['maxPlayers'] as num?)?.toInt() ??
          kCodeCluesMaxPlayers,
      createdAt:
          DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      roomName: json['roomName'] as String?,
      playerOrder: order,
      currentTurnTeam:
          (json['currentTurnTeam'] as num?)?.toInt() ?? 1,
      turnEndsAt: json['turnEndsAt'] != null
          ? DateTime.tryParse(json['turnEndsAt'] as String)
          : null,
      boardState: boardState,
      winnerUserIds: winners,
      winningTeam: (json['winningTeam'] as num?)?.toInt(),
      endReason: json['endReason'] as String?,
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      spectatorsEnabled:
          (json['spectatorsEnabled'] ?? true) as bool,
      clueSeconds: (json['clueSeconds'] as num?)?.toInt() ??
          kCodeCluesDefaultClueSeconds,
      guessSeconds: (json['guessSeconds'] as num?)?.toInt() ??
          kCodeCluesDefaultGuessSeconds,
    );
  }
}
