// lib/features/games/nameplace/nameplace_models.dart

import 'nameplace_game_logic.dart';

export 'nameplace_game_logic.dart' show NameplaceAnswer, RoundScoreResult, FinalResult;

enum NameplaceStatus { waiting, inProgress, completed }

extension NameplaceStatusX on NameplaceStatus {
  String get name => switch (this) {
    NameplaceStatus.waiting => 'waiting',
    NameplaceStatus.inProgress => 'in_progress',
    NameplaceStatus.completed => 'completed',
  };
  static NameplaceStatus fromString(String? s) => switch (s) {
    'in_progress' => NameplaceStatus.inProgress,
    'completed' => NameplaceStatus.completed,
    _ => NameplaceStatus.waiting,
  };
}

class NameplaceGame {
  const NameplaceGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.status,
    required this.categories,
    required this.roundTimerSeconds,
    required this.totalRounds,
    required this.currentRound,
    this.currentLetterChooserId,
    this.currentLetter,
    this.roundEndsAt,
    required this.allAnswersSubmitted,
    required this.roundScoringDone,
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
  final NameplaceStatus status;
  final List<String> categories;
  final int roundTimerSeconds;
  final int totalRounds;
  final int currentRound;
  final String? currentLetterChooserId;
  final String? currentLetter;
  final DateTime? roundEndsAt;
  final bool allAnswersSubmitted;
  final bool roundScoringDone;
  final List<String>? winnerUserIds;
  final List<String>? winnerNames;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  factory NameplaceGame.fromJson(Map<String, dynamic> json) => NameplaceGame(
    id: json['id'] ?? '',
    familyId: json['familyId'] ?? '',
    hostUserId: json['hostUserId'] ?? '',
    hostUserName: json['hostUserName'] ?? 'Host',
    status: NameplaceStatusX.fromString(json['status']),
    categories: (json['categories'] as List? ?? []).map((e) => e.toString()).toList(),
    roundTimerSeconds: json['roundTimerSeconds'] ?? 60,
    totalRounds: json['totalRounds'] ?? 5,
    currentRound: json['currentRound'] ?? 0,
    currentLetterChooserId: json['currentLetterChooserId'],
    currentLetter: json['currentLetter'],
    roundEndsAt: json['roundEndsAt'] != null ? DateTime.tryParse(json['roundEndsAt']) : null,
    allAnswersSubmitted: json['allAnswersSubmitted'] ?? false,
    roundScoringDone: json['roundScoringDone'] ?? false,
    winnerUserIds: (json['winnerUserIds'] as List?)?.map((e) => e.toString()).toList(),
    winnerNames: (json['winnerNames'] as List?)?.map((e) => e.toString()).toList(),
    startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt']) : null,
    completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt']) : null,
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );

  bool get isWaiting => status == NameplaceStatus.waiting;
  bool get isInProgress => status == NameplaceStatus.inProgress;
  bool get isCompleted => status == NameplaceStatus.completed;
}

class NameplacePlayer {
  const NameplacePlayer({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.turnOrder,
    required this.totalScore,
    required this.hasSubmitted,
    required this.joinedAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final int turnOrder;
  final int totalScore;
  final bool hasSubmitted;
  final DateTime joinedAt;

  factory NameplacePlayer.fromJson(Map<String, dynamic> json) => NameplacePlayer(
    id: json['id'] ?? '',
    gameId: json['gameId'] ?? '',
    userId: json['userId'] ?? '',
    userName: json['userName'] ?? 'Player',
    turnOrder: json['turnOrder'] ?? 0,
    totalScore: json['totalScore'] ?? 0,
    hasSubmitted: json['hasSubmitted'] ?? false,
    joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
  );
}

class NameplaceRound {
  const NameplaceRound({
    required this.id,
    required this.gameId,
    required this.roundNumber,
    required this.letter,
    required this.letterChooserId,
    required this.letterChooserName,
    required this.createdAt,
  });

  final String id;
  final String gameId;
  final int roundNumber;
  final String letter;
  final String letterChooserId;
  final String letterChooserName;
  final DateTime createdAt;

  factory NameplaceRound.fromJson(Map<String, dynamic> json) => NameplaceRound(
    id: json['id'] ?? '',
    gameId: json['gameId'] ?? '',
    roundNumber: json['roundNumber'] ?? 0,
    letter: json['letter'] ?? '',
    letterChooserId: json['letterChooserId'] ?? '',
    letterChooserName: json['letterChooserName'] ?? 'Player',
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );
}

class NameplaceAnswerModel {
  const NameplaceAnswerModel({
    required this.id,
    required this.roundId,
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.category,
    required this.answerText,
    this.pointsAwarded,
    required this.createdAt,
  });

  final String id;
  final String roundId;
  final String gameId;
  final String playerId;
  final String playerName;
  final String category;
  final String answerText;
  final int? pointsAwarded;
  final DateTime createdAt;

  factory NameplaceAnswerModel.fromJson(Map<String, dynamic> json) => NameplaceAnswerModel(
    id: json['id'] ?? '',
    roundId: json['roundId'] ?? '',
    gameId: json['gameId'] ?? '',
    playerId: json['playerId'] ?? '',
    playerName: json['playerName'] ?? 'Player',
    category: json['category'] ?? '',
    answerText: json['answerText'] ?? '',
    pointsAwarded: json['pointsAwarded'],
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );
}
