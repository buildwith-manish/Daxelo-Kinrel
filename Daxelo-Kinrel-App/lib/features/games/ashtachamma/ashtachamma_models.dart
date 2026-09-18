// lib/features/games/ashtachamma/ashtachamma_models.dart
//
// Ashta Chamma — wire models for the multiplayer board game.
//
// Mirrors the structure of memorymatch_models.dart. The game state is
// serialized as JSON and synced via Supabase Realtime. The Dart models
// parse the JSONB returned by the ashta_chamma_games RPCs
// (fn_ashtachamma_start, fn_ashtachamma_roll, fn_ashtachamma_move,
// fn_ashtachamma_finish, etc.).
//
// The pure game logic lives in ashtachamma_engine.dart. These models are
// the "wire" representation — what gets sent over the network.

import 'ashtachamma_engine.dart';

enum AshtaChammaStatus { waiting, inProgress, completed }

extension AshtaChammaStatusX on AshtaChammaStatus {
  String get wire {
    switch (this) {
      case AshtaChammaStatus.waiting:
        return 'waiting';
      case AshtaChammaStatus.inProgress:
        return 'in_progress';
      case AshtaChammaStatus.completed:
        return 'completed';
    }
  }

  static AshtaChammaStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return AshtaChammaStatus.inProgress;
      case 'completed':
        return AshtaChammaStatus.completed;
      case 'waiting':
      default:
        return AshtaChammaStatus.waiting;
    }
  }
}

/// The two phases of a turn: the player must roll the dice, then move
/// a piece (or pass if no legal moves).
enum AshtaChammaPhase { roll, move }

extension AshtaChammaPhaseX on AshtaChammaPhase {
  String get wire => this == AshtaChammaPhase.move ? 'move' : 'roll';

  static AshtaChammaPhase fromString(String? s) =>
      s == 'move' ? AshtaChammaPhase.move : AshtaChammaPhase.roll;
}

/// One player in an Ashta Chamma match. Mirrors MemoryMatchPlayer.
class AshtaChammaPlayer {
  const AshtaChammaPlayer({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.joinedAt,
    required this.turnOrder,
    this.isReady = false,
    this.leftAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final DateTime joinedAt;
  final int turnOrder;
  final bool isReady;
  final DateTime? leftAt;

  bool get isActive => leftAt == null;

  factory AshtaChammaPlayer.fromJson(Map<String, dynamic> json) {
    return AshtaChammaPlayer(
      id: (json['id'] ?? '') as String,
      gameId: (json['gameId'] ?? '') as String,
      userId: (json['userId'] ?? '') as String,
      userName: (json['userName'] ?? 'Player') as String,
      joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ?? DateTime.now(),
      turnOrder: (json['turnOrder'] as num?)?.toInt() ?? 0,
      isReady: (json['isReady'] ?? false) as bool,
      leftAt: json['leftAt'] != null
          ? DateTime.tryParse(json['leftAt'] as String)
          : null,
    );
  }
}

/// Final ranking entry (computed server-side at completion).
class AshtaChammaPlacement {
  const AshtaChammaPlacement({
    required this.userId,
    required this.userName,
    required this.place,
    required this.piecesHome,
    required this.captures,
    required this.turnDurationMs,
  });

  final String userId;
  final String userName;
  final int place;
  final int piecesHome;
  final int captures;
  final int turnDurationMs;

  factory AshtaChammaPlacement.fromJson(Map<String, dynamic> json) {
    return AshtaChammaPlacement(
      userId: (json['userId'] ?? '') as String,
      userName: (json['userName'] ?? 'Player') as String,
      place: (json['place'] ?? 0) as int,
      piecesHome: (json['piecesHome'] ?? 0) as int,
      captures: (json['captures'] ?? 0) as int,
      turnDurationMs: (json['turnDurationMs'] ?? 0) as int,
    );
  }

  String get medal {
    switch (place) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '🏅';
    }
  }
}

/// The full game row from `ashta_chamma_games`. Mirrors MemoryMatchGame.
class AshtaChammaGame {
  const AshtaChammaGame({
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
    this.phase = AshtaChammaPhase.roll,
    this.lastDiceValue = 0,
    this.boardState,
    this.consecutiveSixes = 0,
    this.scores = const {},
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
  final AshtaChammaStatus status;
  final int maxPlayers;
  final DateTime createdAt;
  final String? roomName;
  final List<String> playerOrder;
  final String? currentPlayerId;
  final int currentTurnIndex;
  final DateTime? turnEndsAt;
  final AshtaChammaPhase phase;
  final int lastDiceValue;

  /// The full serializable game state (pieces, current player, move
  /// history). Stored as JSONB on the game row. See AshtaChammaGameState
  /// in the engine file.
  final AshtaChammaGameState? boardState;

  final int consecutiveSixes;
  final Map<String, int> scores;
  final List<AshtaChammaPlacement> placements;
  final List<String> winnerUserIds;
  final String? endReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool spectatorsEnabled;

  bool get isWaiting => status == AshtaChammaStatus.waiting;
  bool get isInProgress => status == AshtaChammaStatus.inProgress;
  bool get isCompleted => status == AshtaChammaStatus.completed;

  /// Seconds left in the current turn (null when not running).
  int? get turnSecondsRemaining {
    if (!isInProgress || turnEndsAt == null) return null;
    final left = turnEndsAt!.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  String get endReasonLabel {
    switch (endReason) {
      case 'all_home':
        return 'All pieces reached home!';
      case 'walkover':
        return 'The others left — last player standing';
      default:
        return 'Game complete';
    }
  }

  factory AshtaChammaGame.fromJson(Map<String, dynamic> json) {
    final order = <String>[];
    final rawOrder = json['playerOrder'];
    if (rawOrder is List) {
      order.addAll(rawOrder.whereType<String>());
    }

    final scores = <String, int>{};
    final rawScores = json['scores'];
    if (rawScores is Map) {
      rawScores.forEach((k, v) {
        if (k is String && v is num) scores[k] = v.toInt();
      });
    }

    final placements = <AshtaChammaPlacement>[];
    final rawPlacements = json['placements'];
    if (rawPlacements is List) {
      for (final p in rawPlacements) {
        if (p is Map<String, dynamic>) {
          placements.add(AshtaChammaPlacement.fromJson(p));
        }
      }
    }

    final winners = <String>[];
    final rawWinners = json['winnerUserIds'];
    if (rawWinners is List) {
      winners.addAll(rawWinners.whereType<String>());
    }

    AshtaChammaGameState? boardState;
    final rawBoard = json['boardState'];
    if (rawBoard is Map<String, dynamic>) {
      boardState = AshtaChammaGameState.fromJson(rawBoard);
    }

    return AshtaChammaGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: AshtaChammaStatusX.fromString(json['status'] as String?),
      maxPlayers: (json['maxPlayers'] ?? 4) as int,
      createdAt:
          DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      roomName: json['roomName'] as String?,
      playerOrder: order,
      currentPlayerId: json['currentPlayerId'] as String?,
      currentTurnIndex: (json['currentTurnIndex'] ?? 0) as int,
      turnEndsAt: json['turnEndsAt'] != null
          ? DateTime.tryParse(json['turnEndsAt'] as String)
          : null,
      phase: AshtaChammaPhaseX.fromString(json['phase'] as String?),
      lastDiceValue: (json['lastDiceValue'] as num?)?.toInt() ?? 0,
      boardState: boardState,
      consecutiveSixes: (json['consecutiveSixes'] as num?)?.toInt() ?? 0,
      scores: scores,
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
