// lib/features/games/chitmatch/chitmatch_models.dart

import 'chitmatch_game_logic.dart';

export 'chitmatch_game_logic.dart' show ChitmatchPlayer, RoundResolution;

enum ChitmatchStatus { waiting, setup, inProgress, completed }
enum ChitmatchSetupPhase { joining, submittingWords, dealing, ready }

extension ChitmatchStatusX on ChitmatchStatus {
  String get name {
    switch (this) {
      case ChitmatchStatus.waiting: return 'waiting';
      case ChitmatchStatus.setup: return 'setup';
      case ChitmatchStatus.inProgress: return 'in_progress';
      case ChitmatchStatus.completed: return 'completed';
    }
  }
  static ChitmatchStatus fromString(String? s) {
    switch (s) {
      case 'setup': return ChitmatchStatus.setup;
      case 'in_progress': return ChitmatchStatus.inProgress;
      case 'completed': return ChitmatchStatus.completed;
      default: return ChitmatchStatus.waiting;
    }
  }
}

extension ChitmatchSetupPhaseX on ChitmatchSetupPhase {
  String get name {
    switch (this) {
      case ChitmatchSetupPhase.joining: return 'joining';
      case ChitmatchSetupPhase.submittingWords: return 'submitting_words';
      case ChitmatchSetupPhase.dealing: return 'dealing';
      case ChitmatchSetupPhase.ready: return 'ready';
    }
  }
  static ChitmatchSetupPhase fromString(String? s) {
    switch (s) {
      case 'submitting_words': return ChitmatchSetupPhase.submittingWords;
      case 'dealing': return ChitmatchSetupPhase.dealing;
      case 'ready': return ChitmatchSetupPhase.ready;
      default: return ChitmatchSetupPhase.joining;
    }
  }
}

class ChitmatchGame {
  const ChitmatchGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.status,
    required this.playerCount,
    required this.roundNumber,
    required this.roundTimerSeconds,
    this.roundEndsAt,
    required this.allPassesCollected,
    this.winnerUserIds,
    this.winnerNames,
    required this.setupPhase,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final ChitmatchStatus status;
  final int playerCount;
  final int roundNumber;
  final int roundTimerSeconds;
  final DateTime? roundEndsAt;
  final bool allPassesCollected;
  final List<String>? winnerUserIds;
  final List<String>? winnerNames;
  final ChitmatchSetupPhase setupPhase;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  factory ChitmatchGame.fromJson(Map<String, dynamic> json) => ChitmatchGame(
    id: json['id'] ?? '',
    familyId: json['familyId'] ?? '',
    hostUserId: json['hostUserId'] ?? '',
    hostUserName: json['hostUserName'] ?? 'Host',
    status: ChitmatchStatusX.fromString(json['status']),
    playerCount: json['playerCount'] ?? 4,
    roundNumber: json['roundNumber'] ?? 0,
    roundTimerSeconds: json['roundTimerSeconds'] ?? 20,
    roundEndsAt: json['roundEndsAt'] != null ? DateTime.tryParse(json['roundEndsAt']) : null,
    allPassesCollected: json['allPassesCollected'] ?? false,
    winnerUserIds: (json['winnerUserIds'] as List?)?.map((e) => e.toString()).toList(),
    winnerNames: (json['winnerNames'] as List?)?.map((e) => e.toString()).toList(),
    setupPhase: ChitmatchSetupPhaseX.fromString(json['setupPhase']),
    startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt']) : null,
    completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt']) : null,
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );

  bool get isWaiting => status == ChitmatchStatus.waiting;
  bool get isSetup => status == ChitmatchStatus.setup;
  bool get isInProgress => status == ChitmatchStatus.inProgress;
  bool get isCompleted => status == ChitmatchStatus.completed;
}

class ChitmatchPlayerModel {
  const ChitmatchPlayerModel({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.turnOrder,
    this.submittedWord,
    required this.currentHand,
    this.selectedChitIndex,
    required this.hasWon,
    required this.joinedAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final int turnOrder;
  final String? submittedWord;
  final List<String> currentHand;
  final int? selectedChitIndex;
  final bool hasWon;
  final DateTime joinedAt;

  factory ChitmatchPlayerModel.fromJson(Map<String, dynamic> json) => ChitmatchPlayerModel(
    id: json['id'] ?? '',
    gameId: json['gameId'] ?? '',
    userId: json['userId'] ?? '',
    userName: json['userName'] ?? 'Player',
    turnOrder: json['turnOrder'] ?? 0,
    submittedWord: json['submittedWord'],
    currentHand: (json['currentHand'] as List? ?? []).map((e) => e.toString()).toList(),
    selectedChitIndex: json['selectedChitIndex'],
    hasWon: json['hasWon'] ?? false,
    joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
  );
}

class ChitmatchPassRecord {
  const ChitmatchPassRecord({
    required this.id,
    required this.gameId,
    required this.roundNumber,
    required this.fromPlayerId,
    required this.fromPlayerName,
    required this.toPlayerId,
    required this.toPlayerName,
    required this.chitPassed,
    required this.createdAt,
  });

  final String id;
  final String gameId;
  final int roundNumber;
  final String fromPlayerId;
  final String fromPlayerName;
  final String toPlayerId;
  final String toPlayerName;
  final String chitPassed;
  final DateTime createdAt;

  factory ChitmatchPassRecord.fromJson(Map<String, dynamic> json) => ChitmatchPassRecord(
    id: json['id'] ?? '',
    gameId: json['gameId'] ?? '',
    roundNumber: json['roundNumber'] ?? 0,
    fromPlayerId: json['fromPlayerId'] ?? '',
    fromPlayerName: json['fromPlayerName'] ?? 'Player',
    toPlayerId: json['toPlayerId'] ?? '',
    toPlayerName: json['toPlayerName'] ?? 'Player',
    chitPassed: json['chitPassed'] ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
  );
}
