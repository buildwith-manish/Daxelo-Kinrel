// lib/features/games/stickman_heist/stickman_heist_models.dart
//
// Stickman Heist — wire models for Supabase.
//
// Two Postgres tables back this game's DURABLE state:
//   stickman_heist_games   — one row per match (status, boardState JSONB
//                            persisted only on match end, host config:
//                            mapId, respawnsEnabled, matchSeconds, etc.)
//   stickman_heist_players — one row per participant (RLS: insert by self
//                            or host; update by self)
//
// Per-frame input + per-frame board state travel over Supabase Realtime
// Broadcast (pure websocket pub/sub, no DB) — see
// stickman_heist_provider.dart for the channel topology.
//
// The `stickman_heist_inputs` table is retained in the schema for
// backward compatibility but is no longer written or read by the
// client. The previous design upserted a row per player per input
// frame at 20Hz (DB WRITE) and the host polled at 20Hz (DB READ) —
// both eliminated in favour of Broadcast. See worklog Task
// 2-stickman-heist.
//
// The host-authoritative model means:
//   • The host's client owns the Forge2D physics simulation.
//   • Every 100ms the host broadcasts the latest boardState JSON via
//     `channel.sendBroadcastMessage(event: 'state', ...)`. Realtime
//     delivers it to every other client over the websocket.
//   • On match completion, the host makes ONE final durable RPC call
//     to `fn_stickmanheist_broadcast_state(p_state)` to persist
//     winnerUserIds + endReason + completedAt + status='completed'.
//   • Non-host clients only render the boardState they receive and
//     broadcast their input frame (~20Hz) for the host to consume.

import 'stickman_heist_engine.dart';

export 'stickman_heist_engine.dart';

// ── Status ───────────────────────────────────────────────────────────

enum StickmanHeistStatus { waiting, inProgress, completed }

extension StickmanHeistStatusX on StickmanHeistStatus {
  String get wire {
    switch (this) {
      case StickmanHeistStatus.waiting:
        return 'waiting';
      case StickmanHeistStatus.inProgress:
        return 'in_progress';
      case StickmanHeistStatus.completed:
        return 'completed';
    }
  }

  static StickmanHeistStatus fromString(String? s) {
    switch (s) {
      case 'in_progress':
        return StickmanHeistStatus.inProgress;
      case 'completed':
        return StickmanHeistStatus.completed;
      case 'waiting':
      default:
        return StickmanHeistStatus.waiting;
    }
  }
}

// ── Player (wire) ────────────────────────────────────────────────────

/// A row from stickman_heist_players. Tracks lobby membership + ready
/// state — the in-game player state lives inside boardState.players.
class StickmanHeistPlayerWire {
  const StickmanHeistPlayerWire({
    required this.id,
    required this.gameId,
    required this.userId,
    required this.userName,
    required this.isReady,
    required this.joinedAt,
    this.leftAt,
  });

  final String id;
  final String gameId;
  final String userId;
  final String userName;
  final bool isReady;
  final DateTime joinedAt;
  final DateTime? leftAt;

  bool get isActive => leftAt == null;

  factory StickmanHeistPlayerWire.fromJson(Map<String, dynamic> json) =>
      StickmanHeistPlayerWire(
        id: (json['id'] ?? '') as String,
        gameId: (json['gameId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        userName: (json['userName'] ?? 'Player') as String,
        isReady: (json['isReady'] as bool?) ?? false,
        joinedAt: DateTime.tryParse(json['joinedAt'] ?? '') ??
            DateTime.now(),
        leftAt: json['leftAt'] != null
            ? DateTime.tryParse(json['leftAt'] as String)
            : null,
      );
}

// ── Game (wire) ──────────────────────────────────────────────────────

/// A row from stickman_heist_games.
class StickmanHeistGame {
  const StickmanHeistGame({
    required this.id,
    required this.familyId,
    required this.hostUserId,
    required this.hostUserName,
    required this.status,
    required this.maxPlayers,
    required this.createdAt,
    required this.playerOrder,
    required this.winnerUserIds,
    required this.spectatorsEnabled,
    required this.mapId,
    required this.respawnsEnabled,
    required this.matchSeconds,
    this.roomName,
    this.boardState,
    this.endReason,
    this.startedAt,
    this.completedAt,
    this.lastStateBroadcast,
  });

  final String id;
  final String familyId;
  final String hostUserId;
  final String hostUserName;
  final StickmanHeistStatus status;
  final int maxPlayers;
  final DateTime createdAt;

  final String? roomName;

  /// Ordered list of userIds — set by fn_stickmanheist_start. Index in
  /// this list = the player's idx inside boardState.players.
  final List<String> playerOrder;

  /// The live game state. Populated by fn_stickmanheist_start, updated
  /// by fn_stickmanheist_broadcast_state (host calls ~10Hz).
  final StickmanHeistBoardState? boardState;

  final List<String> winnerUserIds;
  final String? endReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? lastStateBroadcast;

  final bool spectatorsEnabled;

  // Game-specific config
  final String mapId;
  final bool respawnsEnabled;
  final int matchSeconds;

  bool get isWaiting => status == StickmanHeistStatus.waiting;
  bool get isInProgress => status == StickmanHeistStatus.inProgress;
  bool get isCompleted => status == StickmanHeistStatus.completed;

  /// The local user's idx inside boardState.players, or null.
  int? idxForUserId(String? userId) {
    if (userId == null) return null;
    final i = playerOrder.indexOf(userId);
    return i >= 0 ? i : null;
  }

  factory StickmanHeistGame.fromJson(Map<String, dynamic> json) {
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
    StickmanHeistBoardState? board;
    final rawBoard = json['boardState'];
    if (rawBoard is Map<String, dynamic>) {
      board = StickmanHeistBoardState.fromJson(rawBoard);
    } else if (rawBoard is Map) {
      board = StickmanHeistBoardState.fromJson(
          Map<String, dynamic>.from(rawBoard));
    }
    return StickmanHeistGame(
      id: (json['id'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      hostUserId: (json['hostUserId'] ?? '') as String,
      hostUserName: (json['hostUserName'] ?? 'Host') as String,
      status: StickmanHeistStatusX.fromString(
          json['status'] as String?),
      maxPlayers: (json['maxPlayers'] as num?)?.toInt() ??
          kStickmanHeistMaxPlayers,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ??
          DateTime.now(),
      roomName: json['roomName'] as String?,
      playerOrder: order,
      boardState: board,
      winnerUserIds: winners,
      endReason: json['endReason'] as String?,
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      lastStateBroadcast: json['lastStateBroadcast'] != null
          ? DateTime.tryParse(json['lastStateBroadcast'] as String)
          : null,
      spectatorsEnabled:
          (json['spectatorsEnabled'] as bool?) ?? true,
      mapId: (json['mapId'] ?? 'bank') as String,
      respawnsEnabled: (json['respawnsEnabled'] as bool?) ?? true,
      matchSeconds:
          (json['matchSeconds'] as num?)?.toInt() ?? 180,
    );
  }
}

// ── Input (wire) ─────────────────────────────────────────────────────

/// A row from stickman_heist_inputs. Each player upserts their own row
/// at ~20Hz; the host reads all rows for the active game and applies
/// them to the simulation.
class StickmanHeistInputWire {
  const StickmanHeistInputWire({
    required this.gameId,
    required this.userId,
    required this.moveX,
    required this.moveY,
    required this.aimAngle,
    required this.shooting,
    required this.reloadRequested,
    required this.swapWeaponRequested,
    this.updatedAt,
  });

  final String gameId;
  final String userId;
  final double moveX;
  final double moveY;
  final double aimAngle;
  final bool shooting;
  final bool reloadRequested;
  final bool swapWeaponRequested;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'userId': userId,
        'moveX': moveX,
        'moveY': moveY,
        'aimAngle': aimAngle,
        'shooting': shooting,
        'reloadRequested': reloadRequested,
        'swapWeaponRequested': swapWeaponRequested,
      };

  factory StickmanHeistInputWire.fromJson(Map<String, dynamic> json) =>
      StickmanHeistInputWire(
        gameId: (json['gameId'] ?? '') as String,
        userId: (json['userId'] ?? '') as String,
        moveX: (json['moveX'] as num?)?.toDouble() ?? 0,
        moveY: (json['moveY'] as num?)?.toDouble() ?? 0,
        aimAngle: (json['aimAngle'] as num?)?.toDouble() ?? 0,
        shooting: (json['shooting'] as bool?) ?? false,
        reloadRequested:
            (json['reloadRequested'] as bool?) ?? false,
        swapWeaponRequested:
            (json['swapWeaponRequested'] as bool?) ?? false,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );
}
