// lib/features/games/secret_heist/secret_heist_models.dart
//
// Secret Heist — wire models for the multiplayer hidden-role game.
//
// One row in secret_heist_games ↔ one [SecretHeistGame]. Player roster
// lives in secret_heist_players ↔ [SecretHeistPlayerWire]. Hidden
// actions live in secret_heist_actions (RLS hides other players' rows).

import 'secret_heist_engine.dart';

export 'secret_heist_engine.dart'
    show
        HeistAction,
        HeistActionX,
        HeistPhase,
        HeistPhaseX,
        SuspicionLevel,
        SuspicionLevelX,
        HeistPlayer,
        HeistEvent,
        RevealedAction,
        HeistRound,
        HeistBoardState,
        SecretHeistEngine,
        kSecretHeistMinPlayers,
        kSecretHeistMaxPlayers,
        kSecretHeistDefaultActionSeconds,
        kSecretHeistMinSteal,
        kSecretHeistMaxSteal,
        kSecretHeistProtectAmount,
        kSecretHeistTrapPenalty;

enum SecretHeistStatus { waiting, inProgress, completed }

extension SecretHeistStatusX on SecretHeistStatus {
  String get wire {
    switch (this) {
      case SecretHeistStatus.waiting: return 'waiting';
      case SecretHeistStatus.inProgress: return 'in_progress';
      case SecretHeistStatus.completed: return 'completed';
    }
  }

  static SecretHeistStatus fromString(String? s) {
    switch (s) {
      case 'in_progress': return SecretHeistStatus.inProgress;
      case 'completed': return SecretHeistStatus.completed;
      case 'waiting':
      default:
        return SecretHeistStatus.waiting;
    }
  }
}

class SecretHeistPlayerWire {
  const SecretHeistPlayerWire({
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

  factory SecretHeistPlayerWire.fromJson(Map<String, dynamic> json) =>
      SecretHeistPlayerWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        userName: (json['userName'] ?? 'Player') as String,
        joinedAt:
            DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
        isReady: (json['isReady'] ?? false) as bool,
        leftAt: json['leftAt'] != null
            ? DateTime.tryParse(json['leftAt'] as String)
            : null,
      );
}

class SecretHeistGame {
  const SecretHeistGame({
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
    this.totalRounds = 5,
    this.startingCoins = 100,
    this.vaultSize = 500,
    this.chaosMode = false,
    this.actionSeconds = 30,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final SecretHeistStatus status;
  final int maxPlayers;
  final DateTime createdAt;
  final String? roomName;
  final List<String> playerOrder;
  final String? currentPlayerId;
  final int currentTurnIndex;
  final DateTime? turnEndsAt;
  final HeistBoardState? boardState;
  final List<String> winnerUserIds;
  final String? endReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool spectatorsEnabled;

  // Game-specific config
  final int totalRounds;
  final int startingCoins;
  final int vaultSize;
  final bool chaosMode;
  final int actionSeconds;

  bool get isWaiting => status == SecretHeistStatus.waiting;
  bool get isInProgress => status == SecretHeistStatus.inProgress;
  bool get isCompleted => status == SecretHeistStatus.completed;

  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  factory SecretHeistGame.fromJson(Map<String, dynamic> json) {
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
    HeistBoardState? boardState;
    final rawBoard = json['boardState'];
    if (rawBoard is Map<String, dynamic>) {
      boardState = HeistBoardState.fromJson(rawBoard);
    }
    return SecretHeistGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: SecretHeistStatusX.fromString(json['status'] as String?),
      maxPlayers: (json['maxPlayers'] ?? 8) as int,
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
      totalRounds: (json['totalRounds'] as num?)?.toInt() ?? 5,
      startingCoins: (json['startingCoins'] as num?)?.toInt() ?? 100,
      vaultSize: (json['vaultSize'] as num?)?.toInt() ?? 500,
      chaosMode: (json['chaosMode'] as bool?) ?? false,
      actionSeconds: (json['actionSeconds'] as num?)?.toInt() ?? 30,
    );
  }
}

/// One row from secret_heist_actions (RLS limits to caller's own row).
class SecretHeistActionWire {
  const SecretHeistActionWire({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.roundNumber,
    required this.action,
    required this.amount,
    required this.submittedAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final int roundNumber;
  final String action;
  final int amount;
  final DateTime submittedAt;

  HeistAction get parsedAction => HeistActionX.fromString(action);

  factory SecretHeistActionWire.fromJson(Map<String, dynamic> json) =>
      SecretHeistActionWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 1,
        action: (json['action'] ?? 'steal') as String,
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        submittedAt: DateTime.tryParse(json['submittedAt'] ?? '') ??
            DateTime.now(),
      );
}
