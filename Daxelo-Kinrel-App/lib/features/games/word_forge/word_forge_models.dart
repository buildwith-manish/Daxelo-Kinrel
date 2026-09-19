// lib/features/games/word_forge/word_forge_models.dart
//
// Word Forge — wire models for the multiplayer party game.

import 'word_forge_engine.dart';

export 'word_forge_engine.dart'
    show
        WordForgePhase,
        WordForgePhaseX,
        WordForgePlayer,
        WordForgeDefinition,
        WordForgePointsAwarded,
        WordForgeRound,
        WordForgeBoardState,
        WordForgeEngine,
        kWordForgeMinPlayers,
        kWordForgeMaxPlayers,
        kWordForgeDefaultAnswerSeconds,
        kWordForgeMaxDefinitionLength,
        kWordForgePointsCorrectGuess,
        kWordForgePointsPerFooledVote,
        kWordForgePointsCloseMatchBonus;

enum WordForgeStatus { waiting, inProgress, completed }

extension WordForgeStatusX on WordForgeStatus {
  String get wire {
    switch (this) {
      case WordForgeStatus.waiting:
        return 'waiting';
      case WordForgeStatus.inProgress:
        return 'in_progress';
      case WordForgeStatus.completed:
        return 'completed';
    }
  }

  static WordForgeStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return WordForgeStatus.inProgress;
      case 'completed':
        return WordForgeStatus.completed;
      case 'waiting':
      default:
        return WordForgeStatus.waiting;
    }
  }
}

class WordForgePlayerWire {
  const WordForgePlayerWire({
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

  factory WordForgePlayerWire.fromJson(Map<String, dynamic> json) =>
      WordForgePlayerWire(
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

class WordForgeGame {
  const WordForgeGame({
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
    this.totalRounds = 10,
    this.answerSeconds = 60,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final WordForgeStatus status;
  final int maxPlayers;
  final DateTime createdAt;
  final String? roomName;
  final List<String> playerOrder;
  final String? currentPlayerId;
  final int currentTurnIndex;
  final DateTime? turnEndsAt;
  final WordForgeBoardState? boardState;
  final List<String> winnerUserIds;
  final String? endReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool spectatorsEnabled;

  // Game-specific config
  final int totalRounds;
  final int answerSeconds;

  bool get isWaiting => status == WordForgeStatus.waiting;
  bool get isInProgress => status == WordForgeStatus.inProgress;
  bool get isCompleted => status == WordForgeStatus.completed;

  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  factory WordForgeGame.fromJson(Map<String, dynamic> json) {
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
    WordForgeBoardState? boardState;
    final rawBoard = json['boardState'];
    if (rawBoard is Map<String, dynamic>) {
      boardState = WordForgeBoardState.fromJson(rawBoard);
    }
    return WordForgeGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: WordForgeStatusX.fromString(json['status'] as String?),
      maxPlayers: (json['maxPlayers'] ?? 8) as int,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ??
          DateTime.now(),
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
      totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 10,
      answerSeconds:
          (json['answerSeconds'] as num?)?.toInt() ?? 60,
    );
  }
}

/// One row from word_forge_definitions (RLS limits to caller's own row
/// during writing/voting phases; server publishes all during results).
class WordForgeDefinitionWire {
  const WordForgeDefinitionWire({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.roundNumber,
    required this.definition,
    required this.isReal,
    required this.submittedAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final int roundNumber;
  final String definition;
  final bool isReal;
  final DateTime submittedAt;

  factory WordForgeDefinitionWire.fromJson(Map<String, dynamic> json) =>
      WordForgeDefinitionWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
        definition: (json['definition'] ?? '') as String,
        isReal: (json['isReal'] ?? false) as bool,
        submittedAt: DateTime.tryParse(json['submittedAt'] ?? '') ??
            DateTime.now(),
      );
}

/// One row from word_forge_votes (RLS limits to caller's own row until
/// the resolution RPC publishes results into boardState).
class WordForgeVoteWire {
  const WordForgeVoteWire({
    required this.id,
    required this.gameId,
    required this.voterUserId,
    required this.roundNumber,
    required this.votedForUserId,
    required this.votedAt,
  });

  final String id;
  final String gameId;
  final String voterUserId;
  final int roundNumber;
  final String votedForUserId;
  final DateTime votedAt;

  factory WordForgeVoteWire.fromJson(Map<String, dynamic> json) =>
      WordForgeVoteWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        voterUserId: (json['voterUserId'] ?? '') as String,
        roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
        votedForUserId: (json['votedForUserId'] ?? '') as String,
        votedAt: DateTime.tryParse(json['votedAt'] ?? '') ??
            DateTime.now(),
      );
}
