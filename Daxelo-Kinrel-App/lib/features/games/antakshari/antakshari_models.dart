// lib/features/games/antakshari/antakshari_models.dart
//
// Antakshari — data models for the turn-based singing game.
// NO song lyrics or audio are stored — pure turn tracking + letter chain.

enum AntakshariStatus { waiting, inProgress, completed }

enum AntakshariGameMode { standard, roundLimited }

enum AntakshariChallengeResult { pending, valid, invalid, timedOut }

extension AntakshariStatusX on AntakshariStatus {
  String get name {
    switch (this) {
      case AntakshariStatus.waiting:
        return 'waiting';
      case AntakshariStatus.inProgress:
        return 'in_progress';
      case AntakshariStatus.completed:
        return 'completed';
    }
  }

  static AntakshariStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return AntakshariStatus.inProgress;
      case 'completed':
        return AntakshariStatus.completed;
      case 'waiting':
      default:
        return AntakshariStatus.waiting;
    }
  }
}

extension AntakshariGameModeX on AntakshariGameMode {
  String get label {
    switch (this) {
      case AntakshariGameMode.standard:
        return 'Standard';
      case AntakshariGameMode.roundLimited:
        return 'Round-Limited';
    }
  }

  String get name {
    switch (this) {
      case AntakshariGameMode.standard:
        return 'standard';
      case AntakshariGameMode.roundLimited:
        return 'round_limited';
    }
  }

  String get description {
    switch (this) {
      case AntakshariGameMode.standard:
        return 'Last player standing wins (recommended ≤12 players)';
      case AntakshariGameMode.roundLimited:
        return 'Game ends after N rounds — all survivors win jointly';
    }
  }

  static AntakshariGameMode fromString(String? s) {
    return s == 'round_limited'
        ? AntakshariGameMode.roundLimited
        : AntakshariGameMode.standard;
  }
}

extension AntakshariChallengeResultX on AntakshariChallengeResult {
  String get name {
    switch (this) {
      case AntakshariChallengeResult.pending:
        return 'pending';
      case AntakshariChallengeResult.valid:
        return 'valid';
      case AntakshariChallengeResult.invalid:
        return 'invalid';
      case AntakshariChallengeResult.timedOut:
        return 'timed_out';
    }
  }

  static AntakshariChallengeResult fromString(String? s) {
    switch (s) {
      case 'valid':
        return AntakshariChallengeResult.valid;
      case 'invalid':
        return AntakshariChallengeResult.invalid;
      case 'timed_out':
        return AntakshariChallengeResult.timedOut;
      case 'pending':
      default:
        return AntakshariChallengeResult.pending;
    }
  }
}

class AntakshariGame {
  const AntakshariGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.status,
    required this.gameMode,
    this.currentTurnPlayerId,
    this.currentRequiredLetter,
    required this.turnTimerSeconds,
    this.turnStartedAt,
    required this.maxPlayers,
    this.roundLimit,
    required this.currentTurnNumber,
    required this.currentRound,
    this.winnerUserIds,
    this.winnerNames,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final AntakshariStatus status;
  final AntakshariGameMode gameMode;
  final String? currentTurnPlayerId;
  final String? currentRequiredLetter;
  final int turnTimerSeconds;
  final DateTime? turnStartedAt;
  final int maxPlayers;
  final int? roundLimit;
  final int currentTurnNumber;
  final int currentRound;
  final List<String>? winnerUserIds;
  final List<String>? winnerNames;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  factory AntakshariGame.fromJson(Map<String, dynamic> json) => AntakshariGame(
    id: json['id'] ?? '',
    familyId: json['familyId'] ?? '',
    hostUserId: json['hostUserId'] ?? '',
    hostUserName: json['hostUserName'] ?? 'Host',
    status: AntakshariStatusX.fromString(json['status']),
    gameMode: AntakshariGameModeX.fromString(json['gameMode']),
    currentTurnPlayerId: json['currentTurnPlayerId'],
    currentRequiredLetter: json['currentRequiredLetter'],
    turnTimerSeconds: json['turnTimerSeconds'] ?? 30,
    turnStartedAt: json['turnStartedAt'] != null
        ? DateTime.tryParse(json['turnStartedAt'])
        : null,
    maxPlayers: json['maxPlayers'] ?? 12,
    roundLimit: json['roundLimit'],
    currentTurnNumber: json['currentTurnNumber'] ?? 0,
    currentRound: json['currentRound'] ?? 0,
    winnerUserIds: (json['winnerUserIds'] as List?)
        ?.map((e) => e.toString())
        .toList(),
    winnerNames: (json['winnerNames'] as List?)
        ?.map((e) => e.toString())
        .toList(),
    startedAt: json['startedAt'] != null
        ? DateTime.tryParse(json['startedAt'])
        : null,
    completedAt: json['completedAt'] != null
        ? DateTime.tryParse(json['completedAt'])
        : null,
    createdAt:
        DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );

  bool get isWaiting => status == AntakshariStatus.waiting;
  bool get isInProgress => status == AntakshariStatus.inProgress;
  bool get isCompleted => status == AntakshariStatus.completed;
}

class AntakshariPlayer {
  const AntakshariPlayer({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.turnOrder,
    required this.isEliminated,
    this.eliminatedAt,
    required this.joinedAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final int turnOrder;
  final bool isEliminated;
  final DateTime? eliminatedAt;
  final DateTime joinedAt;

  factory AntakshariPlayer.fromJson(Map<String, dynamic> json) =>
      AntakshariPlayer(
        id: json['id'] ?? '',
        gameId: json['gameId'] ?? '',
        userId: json['userId'] ?? '',
        userName: json['userName'] ?? 'Player',
        turnOrder: json['turnOrder'] ?? 0,
        isEliminated: json['isEliminated'] ?? false,
        eliminatedAt: json['eliminatedAt'] != null
            ? DateTime.tryParse(json['eliminatedAt'])
            : null,
        joinedAt:
            DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
      );
}

class AntakshariTurn {
  const AntakshariTurn({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.letterStartedWith,
    this.letterEndedWith,
    required this.turnNumber,
    required this.wasChallenged,
    required this.challengeResult,
    this.challengeWindowEndsAt,
    required this.createdAt,
  });

  final String id;
  final String gameId;
  final String playerId;
  final String playerName;
  final String letterStartedWith;
  final String? letterEndedWith;
  final int turnNumber;
  final bool wasChallenged;
  final AntakshariChallengeResult challengeResult;
  final DateTime? challengeWindowEndsAt;
  final DateTime createdAt;

  factory AntakshariTurn.fromJson(Map<String, dynamic> json) =>
      AntakshariTurn(
        id: json['id'] ?? '',
        gameId: json['gameId'] ?? '',
        playerId: json['playerId'] ?? '',
        playerName: json['playerName'] ?? 'Player',
        letterStartedWith: json['letterStartedWith'] ?? '',
        letterEndedWith: json['letterEndedWith'],
        turnNumber: json['turnNumber'] ?? 0,
        wasChallenged: json['wasChallenged'] ?? false,
        challengeResult:
            AntakshariChallengeResultX.fromString(json['challengeResult']),
        challengeWindowEndsAt: json['challengeWindowEndsAt'] != null
            ? DateTime.tryParse(json['challengeWindowEndsAt'])
            : null,
        createdAt:
            DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}

class AntakshariChallenge {
  const AntakshariChallenge({
    required this.id,
    required this.turnId,
    required this.challengerId,
    required this.challengerName,
    required this.createdAt,
  });

  final String id;
  final String turnId;
  final String challengerId;
  final String challengerName;
  final DateTime createdAt;

  factory AntakshariChallenge.fromJson(Map<String, dynamic> json) =>
      AntakshariChallenge(
        id: json['id'] ?? '',
        turnId: json['turnId'] ?? '',
        challengerId: json['challengerId'] ?? '',
        challengerName: json['challengerName'] ?? 'Player',
        createdAt:
            DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}
