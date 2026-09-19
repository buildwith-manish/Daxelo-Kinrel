// lib/features/games/night_falls/night_falls_models.dart
//
// Night Falls — wire models for the multiplayer Werewolf game.

import 'night_falls_engine.dart';

export 'night_falls_engine.dart'
    show
        NightFallsRole,
        NightFallsRoleX,
        NightFallsPhase,
        NightFallsPhaseX,
        NightFallsActionType,
        NightFallsActionTypeX,
        NightFallsTeam,
        NightFallsTeamX,
        NightFallsPlayer,
        NightFallsNightActions,
        NightFallsVote,
        NightFallsRound,
        NightFallsBoardState,
        NightFallsEngine,
        kNightFallsMinPlayers,
        kNightFallsMaxPlayers,
        kNightFallsDefaultNightSeconds,
        kNightFallsDefaultDaySeconds,
        kNightFallsDefaultVoteSeconds,
        kNightFallsDefaultRoleRevealSeconds;

enum NightFallsStatus { waiting, inProgress, completed }

extension NightFallsStatusX on NightFallsStatus {
  String get wire => switch (this) {
        NightFallsStatus.waiting => 'waiting',
        NightFallsStatus.inProgress => 'in_progress',
        NightFallsStatus.completed => 'completed',
      };

  static NightFallsStatus fromString(String? s) => switch (s) {
        'in_progress' => NightFallsStatus.inProgress,
        'completed' => NightFallsStatus.completed,
        _ => NightFallsStatus.waiting,
      };
}

/// A row from `night_falls_players`. The `role` column is hidden via
/// column-level GRANT — it will be null unless populated from
/// `boardState.roles` (at game end) or via `fn_nightfalls_my_role`
/// (for the caller's own role).
class NightFallsPlayerWire {
  const NightFallsPlayerWire({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.joinedAt,
    this.isAlive = true,
    this.isReady = false,
    this.leftAt,
    this.role,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final DateTime joinedAt;
  final bool isAlive;
  final bool isReady;
  final DateTime? leftAt;
  final NightFallsRole? role;

  bool get isActive => leftAt == null;

  factory NightFallsPlayerWire.fromJson(Map<String, dynamic> json) =>
      NightFallsPlayerWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        userName: (json['userName'] ?? 'Player') as String,
        joinedAt:
            DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
        isAlive: (json['isAlive'] as bool?) ?? true,
        isReady: (json['isReady'] ?? false) as bool,
        leftAt: json['leftAt'] != null
            ? DateTime.tryParse(json['leftAt'] as String)
            : null,
        // role column is hidden via GRANT — will be null unless the row
        // is fetched via a SECURITY DEFINER RPC.
        role: NightFallsRoleX.fromString(json['role'] as String?),
      );
}

/// A row from `night_falls_games`.
class NightFallsGame {
  const NightFallsGame({
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
    this.nightSeconds = kNightFallsDefaultNightSeconds,
    this.daySeconds = kNightFallsDefaultDaySeconds,
    this.voteSeconds = kNightFallsDefaultVoteSeconds,
    this.roleRevealSeconds = kNightFallsDefaultRoleRevealSeconds,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final NightFallsStatus status;
  final int maxPlayers;
  final DateTime createdAt;
  final String? roomName;
  final List<String> playerOrder;
  final String? currentPlayerId;
  final int currentTurnIndex;
  final DateTime? turnEndsAt;
  final NightFallsBoardState? boardState;
  final List<String> winnerUserIds;
  final String? endReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool spectatorsEnabled;

  // Game-specific config
  final int nightSeconds;
  final int daySeconds;
  final int voteSeconds;
  final int roleRevealSeconds;

  bool get isWaiting => status == NightFallsStatus.waiting;
  bool get isInProgress => status == NightFallsStatus.inProgress;
  bool get isCompleted => status == NightFallsStatus.completed;

  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  factory NightFallsGame.fromJson(Map<String, dynamic> json) {
    final order = <String>[];
    final rawOrder = json['playerOrder'];
    if (rawOrder is List) order.addAll(rawOrder.whereType<String>());
    final winners = <String>[];
    final rawWinners = json['winnerUserIds'];
    if (rawWinners is List) winners.addAll(rawWinners.whereType<String>());
    NightFallsBoardState? boardState;
    final rawBoard = json['boardState'];
    if (rawBoard is Map<String, dynamic>) {
      boardState = NightFallsBoardState.fromJson(rawBoard);
    }
    return NightFallsGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: NightFallsStatusX.fromString(json['status'] as String?),
      maxPlayers: (json['maxPlayers'] ?? 12) as int,
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
      winnerUserIds: winners,
      endReason: json['endReason'] as String?,
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      spectatorsEnabled: (json['spectatorsEnabled'] ?? true) as bool,
      nightSeconds:
          (json['nightSeconds'] as num?)?.toInt() ??
              kNightFallsDefaultNightSeconds,
      daySeconds: (json['daySeconds'] as num?)?.toInt() ??
          kNightFallsDefaultDaySeconds,
      voteSeconds: (json['voteSeconds'] as num?)?.toInt() ??
          kNightFallsDefaultVoteSeconds,
      roleRevealSeconds:
          (json['roleRevealSeconds'] as num?)?.toInt() ??
              kNightFallsDefaultRoleRevealSeconds,
    );
  }
}

/// A row from `night_falls_actions` (RLS limits to caller's own rows).
/// Used by the provider to fetch the caller's action history — including
/// the seer's accumulated investigation results.
class NightFallsActionWire {
  const NightFallsActionWire({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.roundNumber,
    required this.actionType,
    this.targetUserId,
    this.result,
    required this.submittedAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final int roundNumber;
  final NightFallsActionType actionType;
  final String? targetUserId;
  /// For `seer_investigate` actions: 'werewolf' or 'villager'. Null
  /// until the night is resolved.
  final String? result;
  final DateTime submittedAt;

  /// True if this is a seer investigation with a resolved result.
  bool get isSeerResult =>
      actionType == NightFallsActionType.seerInvestigate &&
      result != null;

  /// The seer's verdict for this investigation ('werewolf' or 'villager'),
  /// or null if not a seer action / not yet resolved.
  String? get seerVerdict => isSeerResult ? result : null;

  factory NightFallsActionWire.fromJson(Map<String, dynamic> json) =>
      NightFallsActionWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
        actionType: NightFallsActionTypeX.fromString(
            json['actionType'] as String?),
        targetUserId: json['targetUserId'] as String?,
        result: json['result'] as String?,
        submittedAt:
            DateTime.tryParse(json['submittedAt'] ?? '') ?? DateTime.now(),
      );
}
