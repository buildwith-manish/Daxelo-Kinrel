// lib/features/games/connect4/connect4_models.dart
//
// Connect 4 — wire models for the multiplayer game.
// Mirrors memorymatch_models.dart / ashtachamma_models.dart.

import 'connect4_engine.dart';

enum Connect4Status { waiting, inProgress, completed }

extension Connect4StatusX on Connect4Status {
  String get wire {
    switch (this) {
      case Connect4Status.waiting:
        return 'waiting';
      case Connect4Status.inProgress:
        return 'in_progress';
      case Connect4Status.completed:
        return 'completed';
    }
  }

  static Connect4Status fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return Connect4Status.inProgress;
      case 'completed':
        return Connect4Status.completed;
      case 'waiting':
      default:
        return Connect4Status.waiting;
    }
  }
}

class Connect4Player {
  const Connect4Player({
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

  factory Connect4Player.fromJson(Map<String, dynamic> json) {
    return Connect4Player(
      id: (json['id'] ?? '') as String,
      gameId: (json['gameId'] ?? '') as String,
      userId: (json['userId'] ?? '') as String,
      userName: (json['userName'] ?? 'Player') as String,
      joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
      isReady: (json['isReady'] ?? false) as bool,
      leftAt: json['leftAt'] != null
          ? DateTime.tryParse(json['leftAt'] as String)
          : null,
    );
  }
}

class Connect4Placement {
  const Connect4Placement({
    required this.userId,
    required this.userName,
    required this.place,
    required this.discs,
    required this.moves,
  });

  final String userId;
  final String userName;
  final int place;
  final int discs;
  final int moves;

  factory Connect4Placement.fromJson(Map<String, dynamic> json) {
    return Connect4Placement(
      userId: (json['userId'] ?? '') as String,
      userName: (json['userName'] ?? 'Player') as String,
      place: (json['place'] ?? 0) as int,
      discs: (json['discs'] ?? 0) as int,
      moves: (json['moves'] ?? 0) as int,
    );
  }

  String get medal {
    switch (place) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      default:
        return '🏅';
    }
  }
}

class Connect4Game {
  const Connect4Game({
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
    this.placements = const [],
    this.winnerUserIds = const [],
    this.endReason,
    this.startedAt,
    this.completedAt,
    this.spectatorsEnabled = true,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final Connect4Status status;
  final int maxPlayers;
  final DateTime createdAt;
  final String? roomName;
  final List<String> playerOrder;
  final String? currentPlayerId;
  final int currentTurnIndex;
  final DateTime? turnEndsAt;
  final Connect4GameState? boardState;
  final List<Connect4Placement> placements;
  final List<String> winnerUserIds;
  final String? endReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool spectatorsEnabled;

  bool get isWaiting => status == Connect4Status.waiting;
  bool get isInProgress => status == Connect4Status.inProgress;
  bool get isCompleted => status == Connect4Status.completed;

  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  String get endReasonLabel {
    switch (endReason) {
      case 'four_in_a_row':
        return 'Four in a row!';
      case 'draw':
        return 'Board full — it\'s a draw!';
      case 'walkover':
        return 'Opponent left — you win by default';
      default:
        return 'Game complete';
    }
  }

  factory Connect4Game.fromJson(Map<String, dynamic> json) {
    final order = <String>[];
    final rawOrder = json['playerOrder'];
    if (rawOrder is List) {
      order.addAll(rawOrder.whereType<String>());
    }

    final placements = <Connect4Placement>[];
    final rawPlacements = json['placements'];
    if (rawPlacements is List) {
      for (final p in rawPlacements) {
        if (p is Map<String, dynamic>) {
          placements.add(Connect4Placement.fromJson(p));
        }
      }
    }

    final winners = <String>[];
    final rawWinners = json['winnerUserIds'];
    if (rawWinners is List) {
      winners.addAll(rawWinners.whereType<String>());
    }

    Connect4GameState? boardState;
    final rawBoard = json['boardState'];
    if (rawBoard is Map<String, dynamic>) {
      boardState = Connect4GameState.fromJson(rawBoard);
    }

    return Connect4Game(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: Connect4StatusX.fromString(json['status'] as String?),
      maxPlayers: (json['maxPlayers'] ?? 2) as int,
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
      placements: placements,
      winnerUserIds: winners,
      endReason: json['endReason'] as String?,
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      spectatorsEnabled: (json['spectatorsEnabled'] ?? true) as bool,
    );
  }
}
