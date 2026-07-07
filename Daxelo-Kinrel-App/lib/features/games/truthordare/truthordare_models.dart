// lib/features/games/truthordare/truthordare_models.dart

import 'truthordare_selection_logic.dart';

export 'truthordare_selection_logic.dart' show seedPrompts, flagPrompt;

enum TodStatus { waiting, inProgress, completed }
extension TodStatusX on TodStatus {
  String get name => switch (this) { TodStatus.waiting => 'waiting', TodStatus.inProgress => 'in_progress', TodStatus.completed => 'completed' };
  static TodStatus fromString(String? s) => switch (s) { 'in_progress' => TodStatus.inProgress, 'completed' => TodStatus.completed, _ => TodStatus.waiting };
}

enum TodPromptStatus { pending, approved, rejected }
extension TodPromptStatusX on TodPromptStatus {
  String get name => switch (this) { TodPromptStatus.pending => 'pending', TodPromptStatus.approved => 'approved', TodPromptStatus.rejected => 'rejected' };
  static TodPromptStatus fromString(String? s) => switch (s) { 'approved' => TodPromptStatus.approved, 'rejected' => TodPromptStatus.rejected, _ => TodPromptStatus.pending };
}

class TodGame {
  const TodGame({required this.id, required this.familyId, required this.hostUserId, required this.hostUserName, required this.status, this.currentSpinnerId, required this.roundNumber, this.startedAt, this.completedAt, required this.createdAt});
  final String id; final String familyId; final String hostUserId; final String hostUserName; final TodStatus status; final String? currentSpinnerId; final int roundNumber; final DateTime? startedAt; final DateTime? completedAt; final DateTime createdAt;
  factory TodGame.fromJson(Map<String, dynamic> json) => TodGame(id: json['id'] ?? '', familyId: json['familyId'] ?? '', hostUserId: json['hostUserId'] ?? '', hostUserName: json['hostUserName'] ?? 'Host', status: TodStatusX.fromString(json['status']), currentSpinnerId: json['currentSpinnerId'], roundNumber: json['roundNumber'] ?? 0, startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt']) : null, completedAt: json['completedAt'] != null ? DateTime.tryParse(json['completedAt']) : null, createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now());
  bool get isWaiting => status == TodStatus.waiting; bool get isInProgress => status == TodStatus.inProgress; bool get isCompleted => status == TodStatus.completed;
}

class TodPlayer {
  const TodPlayer({required this.id, required this.gameId, required this.userId, required this.userName, required this.seatPosition, required this.timesSelected, required this.joinedAt});
  final String id; final String gameId; final String userId; final String userName; final int seatPosition; final int timesSelected; final DateTime joinedAt;
  factory TodPlayer.fromJson(Map<String, dynamic> json) => TodPlayer(id: json['id'] ?? '', gameId: json['gameId'] ?? '', userId: json['userId'] ?? '', userName: json['userName'] ?? 'Player', seatPosition: json['seatPosition'] ?? 0, timesSelected: json['timesSelected'] ?? 0, joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now());
}

class TodRound {
  const TodRound({required this.id, required this.gameId, required this.roundNumber, required this.spinnerId, required this.spinnerName, this.selectedPlayerId, this.selectedPlayerName, this.choice, this.promptId, this.promptText, required this.completed, required this.createdAt});
  final String id; final String gameId; final int roundNumber; final String spinnerId; final String spinnerName; final String? selectedPlayerId; final String? selectedPlayerName; final String? choice; final String? promptId; final String? promptText; final bool completed; final DateTime createdAt;
  factory TodRound.fromJson(Map<String, dynamic> json) => TodRound(id: json['id'] ?? '', gameId: json['gameId'] ?? '', roundNumber: json['roundNumber'] ?? 0, spinnerId: json['spinnerId'] ?? '', spinnerName: json['spinnerName'] ?? 'Player', selectedPlayerId: json['selectedPlayerId'], selectedPlayerName: json['selectedPlayerName'], choice: json['choice'], promptId: json['promptId'], promptText: json['promptText'], completed: json['completed'] ?? false, createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now());
}

class TodPrompt {
  const TodPrompt({required this.id, required this.familyId, required this.category, required this.promptText, required this.submittedById, required this.submittedByName, required this.status, required this.flaggedByFilter, this.reviewedById, this.reviewedByName, required this.createdAt, this.reviewedAt});
  final String id; final String familyId; final String category; final String promptText; final String submittedById; final String submittedByName; final TodPromptStatus status; final bool flaggedByFilter; final String? reviewedById; final String? reviewedByName; final DateTime createdAt; final DateTime? reviewedAt;
  factory TodPrompt.fromJson(Map<String, dynamic> json) => TodPrompt(id: json['id'] ?? '', familyId: json['familyId'] ?? '', category: json['category'] ?? 'truth', promptText: json['promptText'] ?? '', submittedById: json['submittedById'] ?? '', submittedByName: json['submittedByName'] ?? 'Member', status: TodPromptStatusX.fromString(json['status']), flaggedByFilter: json['flaggedByFilter'] ?? false, reviewedById: json['reviewedById'], reviewedByName: json['reviewedByName'], createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(), reviewedAt: json['reviewedAt'] != null ? DateTime.tryParse(json['reviewedAt']) : null);
}
