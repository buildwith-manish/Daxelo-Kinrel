// lib/features/games/mind_match/mind_match_models.dart
//
// Mind Match — wire models for the multiplayer party game.

import 'mind_match_engine.dart';

export 'mind_match_engine.dart'
    show
        MindMatchCategory,
        MindMatchCategoryX,
        MindMatchPhase,
        MindMatchPhaseX,
        MindMatchPlayer,
        MindMatchAnswerGroup,
        MindMatchPointsAwarded,
        MindMatchRound,
        MindMatchBoardState,
        MindMatchEngine,
        normalizeAnswer,
        kMindMatchMinPlayers,
        kMindMatchMaxPlayers,
        kMindMatchDefaultAnswerSeconds,
        kMindMatchMaxAnswerLength;

enum MindMatchStatus { waiting, inProgress, completed }

extension MindMatchStatusX on MindMatchStatus {
  String get wire {
    switch (this) {
      case MindMatchStatus.waiting:
        return 'waiting';
      case MindMatchStatus.inProgress:
        return 'in_progress';
      case MindMatchStatus.completed:
        return 'completed';
    }
  }

  static MindMatchStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return MindMatchStatus.inProgress;
      case 'completed':
        return MindMatchStatus.completed;
      case 'waiting':
      default:
        return MindMatchStatus.waiting;
    }
  }
}

class MindMatchPlayerWire {
  const MindMatchPlayerWire({
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

  factory MindMatchPlayerWire.fromJson(Map<String, dynamic> json) =>
      MindMatchPlayerWire(
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

class MindMatchGame {
  const MindMatchGame({
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
    this.answerSeconds = 30,
    this.categories = const ['everyday', 'fun', 'family', 'global'],
    this.familyQuestionsEnabled = true,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final MindMatchStatus status;
  final int maxPlayers;
  final DateTime createdAt;
  final String? roomName;
  final List<String> playerOrder;
  final String? currentPlayerId;
  final int currentTurnIndex;
  final DateTime? turnEndsAt;
  final MindMatchBoardState? boardState;
  final List<String> winnerUserIds;
  final String? endReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool spectatorsEnabled;

  // Game-specific config
  final int totalRounds;
  final int answerSeconds;
  final List<String> categories;
  final bool familyQuestionsEnabled;

  bool get isWaiting => status == MindMatchStatus.waiting;
  bool get isInProgress => status == MindMatchStatus.inProgress;
  bool get isCompleted => status == MindMatchStatus.completed;

  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  factory MindMatchGame.fromJson(Map<String, dynamic> json) {
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
    MindMatchBoardState? boardState;
    final rawBoard = json['boardState'];
    if (rawBoard is Map<String, dynamic>) {
      boardState = MindMatchBoardState.fromJson(rawBoard);
    }
    final cats = <String>[];
    final rawCats = json['categories'];
    if (rawCats is List) {
      cats.addAll(rawCats.whereType<String>());
    }
    if (cats.isEmpty) {
      cats.addAll(const ['everyday', 'fun', 'family', 'global']);
    }
    return MindMatchGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: MindMatchStatusX.fromString(json['status'] as String?),
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
          (json['answerSeconds'] as num?)?.toInt() ?? 30,
      categories: cats,
      familyQuestionsEnabled:
          (json['familyQuestionsEnabled'] as bool?) ?? true,
    );
  }
}

/// One row from mind_match_answers (RLS limits to caller's own row).
class MindMatchAnswerWire {
  const MindMatchAnswerWire({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.roundNumber,
    required this.answer,
    required this.submittedAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final int roundNumber;
  final String answer;
  final DateTime submittedAt;

  factory MindMatchAnswerWire.fromJson(Map<String, dynamic> json) =>
      MindMatchAnswerWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
        answer: (json['answer'] ?? '') as String,
        submittedAt: DateTime.tryParse(json['submittedAt'] ?? '') ??
            DateTime.now(),
      );
}
