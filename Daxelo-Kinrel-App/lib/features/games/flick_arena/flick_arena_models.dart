// lib/features/games/flick_arena/flick_arena_models.dart
//
// Flick Arena — wire models for the multiplayer physics game.
//
// One row in flick_arena_games ↔ one [FlickArenaGame]. Turn history lives
// in flick_arena_turns ↔ [FlickArenaTurnRecord].

import 'flick_arena_constants.dart';
import 'flick_arena_engine.dart';

export 'flick_arena_constants.dart'
    show
        FlickArenaBoard,
        FlickArenaPhysics,
        FlickArenaMatchType,
        FlickArenaMatchTypeX,
        FlickArenaStatus,
        FlickArenaStatusX,
        kFlickArenaTurnDuration;
export 'flick_arena_engine.dart'
    show
        FlickDisc,
        FlickBall,
        FlickArenaState,
        FlickTurnResult,
        createInitialBoard,
        evaluateTurn,
        canFlickDisc,
        pickDiscForSlot,
        defaultTurnOrder,
        defaultTeamAssignment,
        teamForSlot;

class FlickArenaGame {
  const FlickArenaGame({
    required this.id,
    required this.familyId,
    required this.matchType,
    required this.maxPlayers,
    required this.status,
    required this.teamOneScore,
    required this.teamTwoScore,
    required this.boardState,
    required this.currentTurnSlot,
    required this.currentTurnPlayerId,
    required this.currentTurnPlayerName,
    required this.turnOrder,
    required this.teamAssignment,
    required this.createdAt,
    this.hostUserId,
    this.hostUserName,
    this.roomName,
    this.playerOneId = '',
    this.playerOneName = 'Player 1',
    this.playerTwoId = '',
    this.playerTwoName = 'Player 2',
    this.playerThreeId = '',
    this.playerThreeName = 'Player 3',
    this.playerFourId = '',
    this.playerFourName = 'Player 4',
    this.turnEndsAt,
    this.winningTeam,
    this.winnerUserIds = const [],
    this.endReason,
    this.lastTurnSummary,
    this.startedAt,
    this.completedAt,
    this.autoCloseDeadline,
    this.spectatorsEnabled = true,
  });

  final String id;
  final String familyId;
  final FlickArenaMatchType matchType;
  final int maxPlayers;
  final FlickArenaStatus status;

  final int teamOneScore;
  final int teamTwoScore;
  final FlickArenaState boardState;

  final int currentTurnSlot;
  final String currentTurnPlayerId;
  final String currentTurnPlayerName;
  final DateTime? turnEndsAt;

  /// Slot order, e.g. [1,2] for solo_duel or [1,2,3,4] for team_battle.
  final List<int> turnOrder;

  /// Slot → team (1 or 2).
  final Map<int, int> teamAssignment;

  final String? hostUserId;
  final String? hostUserName;
  final String? roomName;

  // Inline player slots (mirror carrom pattern).
  final String playerOneId;
  final String playerOneName;
  final String playerTwoId;
  final String playerTwoName;
  final String playerThreeId;
  final String playerThreeName;
  final String playerFourId;
  final String playerFourName;

  final int? winningTeam;
  final List<String> winnerUserIds;
  final String? endReason;
  final Map<String, dynamic>? lastTurnSummary;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime? autoCloseDeadline;
  final bool spectatorsEnabled;

  bool get isWaiting => status == FlickArenaStatus.waiting;
  bool get isInProgress => status == FlickArenaStatus.inProgress;
  bool get isCompleted => status == FlickArenaStatus.completed;

  /// Number of slots currently filled with a real player id.
  int get filledSlots {
    var n = 0;
    if (playerOneId.isNotEmpty) n++;
    if (playerTwoId.isNotEmpty) n++;
    if (playerThreeId.isNotEmpty) n++;
    if (playerFourId.isNotEmpty) n++;
    return n;
  }

  /// True while the room is still waiting for players to join.
  bool get needsMorePlayers => filledSlots < maxPlayers;

  /// Map slot number → (userId, userName). Empty slots return ('', 'Player N').
  (String, String) playerForSlot(int slot) {
    switch (slot) {
      case 1:
        return (playerOneId, playerOneName);
      case 2:
        return (playerTwoId, playerTwoName);
      case 3:
        return (playerThreeId, playerThreeName);
      case 4:
        return (playerFourId, playerFourName);
    }
    return ('', 'Player $slot');
  }

  /// Map userId → slot number, or null if not in this game.
  int? slotForUserId(String? userId) {
    if (userId == null) return null;
    if (playerOneId == userId) return 1;
    if (playerTwoId == userId) return 2;
    if (playerThreeId == userId) return 3;
    if (playerFourId == userId) return 4;
    return null;
  }

  /// Team for a slot, honoring the row's teamAssignment JSON.
  int teamForSlot(int slot) {
    if (teamAssignment.containsKey(slot)) return teamAssignment[slot]!;
    // default: 1,3 → team 1; 2,4 → team 2
    return (slot % 2 == 1) ? 1 : 2;
  }

  /// Seconds remaining on the current turn (clamped at 0).
  /// Returns null if the game isn't in progress or no timer is set.
  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  factory FlickArenaGame.fromJson(Map<String, dynamic> json) {
    final turnOrderList = <int>[];
    final rawTurnOrder = json['turnOrder'];
    if (rawTurnOrder is List) {
      for (final v in rawTurnOrder) {
        if (v is num) turnOrderList.add(v.toInt());
      }
    }
    if (turnOrderList.isEmpty) {
      turnOrderList.addAll(const [1, 2]);
    }

    final teamAssignmentMap = <int, int>{};
    final rawTeamAssignment = json['teamAssignment'];
    if (rawTeamAssignment is Map) {
      for (final entry in rawTeamAssignment.entries) {
        final slot = int.tryParse(entry.key.toString());
        final team = entry.value is num ? (entry.value as num).toInt() : null;
        if (slot != null && team != null) {
          teamAssignmentMap[slot] = team;
        }
      }
    }
    if (teamAssignmentMap.isEmpty) {
      teamAssignmentMap[1] = 1;
      teamAssignmentMap[2] = 2;
      teamAssignmentMap[3] = 1;
      teamAssignmentMap[4] = 2;
    }

    final winnerIds = <String>[];
    final rawWinners = json['winnerUserIds'];
    if (rawWinners is List) {
      for (final v in rawWinners) {
        if (v is String && v.isNotEmpty) winnerIds.add(v);
      }
    }

    final rawBoard = json['boardState'];
    final boardState = rawBoard is Map<String, dynamic>
        ? FlickArenaState.fromJson(rawBoard)
        : createInitialBoard(
            FlickArenaMatchTypeX.fromString(json['matchType'] as String?),
          );

    return FlickArenaGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      matchType: FlickArenaMatchTypeX.fromString(
        json['matchType'] as String?,
      ),
      maxPlayers: (json['maxPlayers'] as num?)?.toInt() ?? 2,
      status: FlickArenaStatusX.fromString(json['status'] as String?),
      teamOneScore: (json['teamOneScore'] as num?)?.toInt() ?? 0,
      teamTwoScore: (json['teamTwoScore'] as num?)?.toInt() ?? 0,
      boardState: boardState,
      currentTurnSlot: (json['currentTurnSlot'] as num?)?.toInt() ?? 1,
      currentTurnPlayerId:
          (json['currentTurnPlayerId'] ?? '') as String,
      currentTurnPlayerName:
          (json['currentTurnPlayerName'] ?? '') as String,
      turnEndsAt: json['turnEndsAt'] is String
          ? DateTime.tryParse(json['turnEndsAt'] as String)
          : null,
      turnOrder: turnOrderList,
      teamAssignment: teamAssignmentMap,
      hostUserId: json['hostUserId'] as String?,
      hostUserName: json['hostUserName'] as String?,
      roomName: json['roomName'] as String?,
      playerOneId: (json['playerOneId'] ?? '') as String,
      playerOneName: (json['playerOneName'] ?? 'Player 1') as String,
      playerTwoId: (json['playerTwoId'] ?? '') as String,
      playerTwoName: (json['playerTwoName'] ?? 'Player 2') as String,
      playerThreeId: (json['playerThreeId'] ?? '') as String,
      playerThreeName: (json['playerThreeName'] ?? 'Player 3') as String,
      playerFourId: (json['playerFourId'] ?? '') as String,
      playerFourName: (json['playerFourName'] ?? 'Player 4') as String,
      winningTeam: (json['winningTeam'] as num?)?.toInt(),
      winnerUserIds: winnerIds,
      endReason: json['endReason'] as String?,
      lastTurnSummary:
          json['lastTurnSummary'] as Map<String, dynamic>?,
      startedAt: json['startedAt'] is String
          ? DateTime.tryParse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] is String
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      createdAt:
          DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      autoCloseDeadline: json['autoCloseDeadline'] is String
          ? DateTime.tryParse(json['autoCloseDeadline'] as String)
          : null,
      spectatorsEnabled:
          (json['spectatorsEnabled'] as bool?) ?? true,
    );
  }
}

class FlickArenaTurnRecord {
  const FlickArenaTurnRecord({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.slotNumber,
    required this.teamNumber,
    required this.discId,
    required this.discStartX,
    required this.discStartY,
    required this.angle,
    required this.force,
    required this.shotDistance,
    required this.scoredGoal,
    this.goalForTeam,
    required this.wasAutoSkipped,
    required this.turnNumber,
    required this.createdAt,
  });

  final String id;
  final String gameId;
  final String playerId;
  final String playerName;
  final int slotNumber;
  final int teamNumber;
  final String discId;
  final double discStartX;
  final double discStartY;
  final double angle;
  final double force;
  final double shotDistance;
  final bool scoredGoal;
  final int? goalForTeam;
  final bool wasAutoSkipped;
  final int turnNumber;
  final DateTime createdAt;

  factory FlickArenaTurnRecord.fromJson(Map<String, dynamic> json) =>
      FlickArenaTurnRecord(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        playerId: (json['playerId'] ?? '') as String,
        playerName: (json['playerName'] ?? 'Player') as String,
        slotNumber: (json['slotNumber'] as num?)?.toInt() ?? 1,
        teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 1,
        discId: (json['discId'] ?? '') as String,
        discStartX: (json['discStartX'] as num?)?.toDouble() ?? 0,
        discStartY: (json['discStartY'] as num?)?.toDouble() ?? 0,
        angle: (json['angle'] as num?)?.toDouble() ?? 0,
        force: (json['force'] as num?)?.toDouble() ?? 0,
        shotDistance: (json['shotDistance'] as num?)?.toDouble() ?? 0,
        scoredGoal: (json['scoredGoal'] as bool?) ?? false,
        goalForTeam: (json['goalForTeam'] as num?)?.toInt(),
        wasAutoSkipped: (json['wasAutoSkipped'] as bool?) ?? false,
        turnNumber: (json['turnNumber'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}
