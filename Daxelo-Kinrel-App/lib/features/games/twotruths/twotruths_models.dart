// lib/features/games/twotruths/twotruths_models.dart
import 'twotruths_game_logic.dart';

export 'twotruths_game_logic.dart' show RoundScoreResult, FinalResult;

enum TtStatus { waiting, inProgress, completed }
extension TtStatusX on TtStatus {
  String get name => switch (this) { TtStatus.waiting => 'waiting', TtStatus.inProgress => 'in_progress', TtStatus.completed => 'completed' };
  static TtStatus fromString(String? s) => switch (s) { 'in_progress' => TtStatus.inProgress, 'completed' => TtStatus.completed, _ => TtStatus.waiting };
}

enum TtMode { playerAuthored, aiLie }
extension TtModeX on TtMode {
  String get name => switch (this) { TtMode.playerAuthored => 'player_authored', TtMode.aiLie => 'ai_lie' };
  static TtMode fromString(String? s) => s == 'ai_lie' ? TtMode.aiLie : TtMode.playerAuthored;
}

class TtGame {
  const TtGame({required this.id, required this.familyId, required this.hostUserId, required this.hostUserName, required this.status, required this.mode, required this.currentRound, required this.totalRounds, this.currentSubmitterId, required this.roundTimerSeconds, this.roundEndsAt, required this.allGuessesSubmitted, required this.roundResolved, this.winnerUserIds, this.winnerNames, this.startedAt, this.completedAt, required this.createdAt});
  final String id; final String familyId; final String hostUserId; final String hostUserName; final TtStatus status; final TtMode mode; final int currentRound; final int totalRounds; final String? currentSubmitterId; final int roundTimerSeconds; final DateTime? roundEndsAt; final bool allGuessesSubmitted; final bool roundResolved; final List<String>? winnerUserIds; final List<String>? winnerNames; final DateTime? startedAt; final DateTime? completedAt; final DateTime createdAt;
  factory TtGame.fromJson(Map<String, dynamic> json) => TtGame(id: json['id'] ?? '', familyId: json['familyId'] ?? '', hostUserId: json['hostUserId'] ?? '', hostUserName: json['hostUserName'] ?? 'Host', status: TtStatusX.fromString(json['status']), mode: TtModeX.fromString(json['mode']), currentRound: json['currentRound'] ?? 0, totalRounds: json['totalRounds'] ?? 3, currentSubmitterId: json['currentSubmitterId'], roundTimerSeconds: json['roundTimerSeconds'] ?? 30, roundEndsAt: json['roundEndsAt'] != null ? DateTime.tryParse(json['roundEndsAt']) : null, allGuessesSubmitted: json['allGuessesSubmitted'] ?? false, roundResolved: json['roundResolved'] ?? false, winnerUserIds: (json['winnerUserIds'] as List?)?.map((e) => e.toString()).toList(), winnerNames: (json['winnerNames'] as List?)?.map((e) => e.toString()).toList(), startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt']) : null, completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt']) : null, createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now());
  bool get isWaiting => status == TtStatus.waiting; bool get isInProgress => status == TtStatus.inProgress; bool get isCompleted => status == TtStatus.completed;
}

class TtPlayer {
  const TtPlayer({required this.id, required this.gameId, required this.userId, required this.userName, required this.turnOrder, required this.totalScore, required this.hasGuessed, required this.joinedAt});
  final String id; final String gameId; final String userId; final String userName; final int turnOrder; final int totalScore; final bool hasGuessed; final DateTime joinedAt;
  factory TtPlayer.fromJson(Map<String, dynamic> json) => TtPlayer(id: json['id'] ?? '', gameId: json['gameId'] ?? '', userId: json['userId'] ?? '', userName: json['userName'] ?? 'Player', turnOrder: json['turnOrder'] ?? 0, totalScore: json['totalScore'] ?? 0, hasGuessed: json['hasGuessed'] ?? false, joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now());
}

class TtRound {
  const TtRound({required this.id, required this.gameId, required this.roundNumber, required this.submitterId, required this.submitterName, required this.statement1, required this.statement2, required this.statement3, required this.lieIndex, required this.createdAt});
  final String id; final String gameId; final int roundNumber; final String submitterId; final String submitterName; final String statement1; final String statement2; final String statement3; final int lieIndex; final DateTime createdAt;
  factory TtRound.fromJson(Map<String, dynamic> json) => TtRound(id: json['id'] ?? '', gameId: json['gameId'] ?? '', roundNumber: json['roundNumber'] ?? 0, submitterId: json['submitterId'] ?? '', submitterName: json['submitterName'] ?? 'Player', statement1: json['statement1'] ?? '', statement2: json['statement2'] ?? '', statement3: json['statement3'] ?? '', lieIndex: json['lieIndex'] ?? 1, createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now());
}

class TtGuess {
  const TtGuess({required this.id, required this.roundId, required this.gameId, required this.guesserId, required this.guesserName, required this.guessedLieIndex, this.isCorrect, required this.createdAt});
  final String id; final String roundId; final String gameId; final String guesserId; final String guesserName; final int guessedLieIndex; final bool? isCorrect; final DateTime createdAt;
  factory TtGuess.fromJson(Map<String, dynamic> json) => TtGuess(id: json['id'] ?? '', roundId: json['roundId'] ?? '', gameId: json['gameId'] ?? '', guesserId: json['guesserId'] ?? '', guesserName: json['guesserName'] ?? 'Player', guessedLieIndex: json['guessedLieIndex'] ?? 1, isCorrect: json['isCorrect'], createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now());
}
