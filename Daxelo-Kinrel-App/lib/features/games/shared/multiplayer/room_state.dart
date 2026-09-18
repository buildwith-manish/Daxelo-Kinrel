// lib/features/games/shared/multiplayer/room_state.dart
//
// Shared state model for the multiplayer room framework. The
// [RoomController] holds a [RoomState] and notifies listeners on every
// change. The state is the single source of truth for:
//
//   • Game row (status, hostUserId, spectatorsEnabled, autoCloseDeadline, ...)
//   • Participants (with readyAt + connectionState)
//   • Spectators (count + names)
//   • Recent room events (join/leave/ready/chat/...)
//   • Local UI state (isLoading, isSubmitting, friendlyError)
//
// The state is intentionally framework-agnostic — it knows nothing
// about SOS / Bingo / Ludo specifics. Game-specific state (moves,
// scores, board) is held by the game's own provider alongside this one.

import 'package:flutter/foundation.dart';

/// A single participant in a room, with their ready + connection status.
@immutable
class RoomParticipant {
  const RoomParticipant({
    required this.userId,
    required this.userName,
    required this.role,
    this.readyAt,
    this.connectionState = 'online',
    this.joinedAt,
    this.leftAt,
  });

  final String userId;
  final String? userName;
  final String role; // 'player' | 'host' | 'spectator'
  final DateTime? readyAt;
  final String connectionState; // 'online' | 'offline'
  final DateTime? joinedAt;
  final DateTime? leftAt;

  bool get isReady => readyAt != null;
  bool get isHost => role == 'host';
  bool get isSpectator => role == 'spectator';
  bool get isOnline => connectionState == 'online' && leftAt == null;

  factory RoomParticipant.fromJson(Map<String, dynamic> json) {
    return RoomParticipant(
      userId: (json['userId'] ?? '') as String,
      userName: json['userName'] as String?,
      role: (json['role'] ?? 'player') as String,
      readyAt: json['readyAt'] is String
          ? DateTime.tryParse(json['readyAt'] as String)
          : null,
      connectionState: (json['connectionState'] ?? 'online') as String,
      joinedAt: json['joinedAt'] is String
          ? DateTime.tryParse(json['joinedAt'] as String)
          : null,
      leftAt: json['leftAt'] is String
          ? DateTime.tryParse(json['leftAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'role': role,
        'readyAt': readyAt?.toIso8601String(),
        'connectionState': connectionState,
        'joinedAt': joinedAt?.toIso8601String(),
        'leftAt': leftAt?.toIso8601String(),
      };

  RoomParticipant copyWith({
    String? userId,
    String? userName,
    String? role,
    DateTime? readyAt,
    bool clearReadyAt = false,
    String? connectionState,
    DateTime? joinedAt,
    DateTime? leftAt,
    bool clearLeftAt = false,
  }) =>
      RoomParticipant(
        userId: userId ?? this.userId,
        userName: userName ?? this.userName,
        role: role ?? this.role,
        readyAt: clearReadyAt ? null : (readyAt ?? this.readyAt),
        connectionState: connectionState ?? this.connectionState,
        joinedAt: joinedAt ?? this.joinedAt,
        leftAt: clearLeftAt ? null : (leftAt ?? this.leftAt),
      );
}

/// A spectator watching a room (read-only viewer).
@immutable
class RoomSpectator {
  const RoomSpectator({
    required this.userId,
    required this.userName,
    this.joinedAt,
  });

  final String userId;
  final String? userName;
  final DateTime? joinedAt;

  factory RoomSpectator.fromJson(Map<String, dynamic> json) {
    return RoomSpectator(
      userId: (json['userId'] ?? '') as String,
      userName: json['userName'] as String?,
      joinedAt: json['joinedAt'] is String
          ? DateTime.tryParse(json['joinedAt'] as String)
          : null,
    );
  }
}

/// A single system event in the room's event log (join / leave / ready /
/// spectator_join / cancel / auto_close / chat / countdown / match_start).
@immutable
class RoomEvent {
  const RoomEvent({
    required this.id,
    required this.gameTable,
    required this.gameId,
    required this.familyId,
    required this.eventType,
    required this.createdAt,
    this.userId,
    this.userName,
    this.payload = const {},
  });

  final String id;
  final String gameTable;
  final String gameId;
  final String familyId;
  final String eventType; // join|leave|ready|not_ready|spectator_join|
                          // spectator_leave|cancel|auto_close|chat|
                          // countdown|match_start|system
  final DateTime createdAt;
  final String? userId;
  final String? userName;
  final Map<String, dynamic> payload;

  /// True if this is a chat message (text or emoji) rather than a system event.
  bool get isChat => eventType == 'chat';

  /// True if this is a 'countdown' event (host started the 5-4-3-2-1).
  bool get isCountdown => eventType == 'countdown';

  /// True if this is a system message that should be shown italicized in
  /// the lobby chat panel (e.g. "John joined the room.").
  bool get isSystemMessage =>
      eventType == 'join' ||
      eventType == 'leave' ||
      eventType == 'spectator_join' ||
      eventType == 'spectator_leave' ||
      eventType == 'cancel' ||
      eventType == 'auto_close' ||
      eventType == 'countdown' ||
      eventType == 'match_start';

  /// Returns a human-readable system message for this event.
  /// Returns null for chat events (the payload['content'] is the message).
  String? get systemMessage {
    final name = userName ?? 'Someone';
    switch (eventType) {
      case 'join':
        return '$name joined the room.';
      case 'leave':
        final wasHost = payload['wasHost'] == true;
        final reason = payload['reason'];
        if (reason == 'disconnected') {
          return '$name disconnected.';
        }
        return wasHost ? '$name (host) left the room.' : '$name left the room.';
      case 'spectator_join':
        return '$name is now watching.';
      case 'spectator_leave':
        return '$name stopped watching.';
      case 'ready':
        return '$name is ready.';
      case 'not_ready':
        return '$name is not ready.';
      case 'cancel':
        return 'Room closed by host.';
      case 'auto_close':
        return 'Room auto-closed (time expired).';
      case 'countdown':
        return 'Match starts in ${(payload['seconds'] ?? 5)}…';
      case 'match_start':
        return 'Match started!';
      default:
        return null;
    }
  }

  factory RoomEvent.fromJson(Map<String, dynamic> json) {
    return RoomEvent(
      id: (json['id'] ?? '') as String,
      gameTable: (json['gameTable'] ?? '') as String,
      gameId: (json['gameId'] ?? '') as String,
      familyId: (json['familyId'] ?? '') as String,
      eventType: (json['eventType'] ?? 'system') as String,
      createdAt: json['createdAt'] is String
          ? (DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now())
          : DateTime.now(),
      userId: json['userId'] as String?,
      userName: json['userName'] as String?,
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
    );
  }
}

/// The room's status (lobby / countdown / active / finished / cancelled).
///
/// `countdown` is the 5-second window between "host taps Start Match" and
/// "match actually begins" — every client shows a 5-4-3-2-1 overlay so
/// nobody misses the start.
enum RoomStatus { lobby, countdown, active, finished, cancelled, unknown }

/// The full state of a multiplayer room.
@immutable
class RoomState {
  const RoomState({
    this.gameId,
    this.familyId,
    this.hostUserId,
    this.hostUserName,
    this.status = RoomStatus.unknown,
    this.spectatorsEnabled = true,
    this.autoCloseDeadline,
    this.countdownEndsAt,
    this.cancelledAt,
    this.closedAt,
    this.participants = const [],
    this.spectators = const [],
    this.events = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.friendlyError,
    this.myUserId,
    this.connectionStatus = RoomConnectionStatus.idle,
  });

  final String? gameId;
  final String? familyId;
  final String? hostUserId;
  final String? hostUserName;
  final RoomStatus status;
  final bool spectatorsEnabled;

  /// Server-authoritative auto-close deadline. When this timestamp passes,
  /// the room is closed automatically (by the cron RPC or by the local
  /// countdown hitting zero, whichever fires first).
  final DateTime? autoCloseDeadline;

  /// Server-authoritative match-start countdown deadline. When this
  /// timestamp passes, the host's client calls the game's own start
  /// callback to transition the game row from lobby → active. All
  /// connected clients tick against the same deadline so the overlay
  /// stays in sync.
  final DateTime? countdownEndsAt;

  final DateTime? cancelledAt;
  final DateTime? closedAt;

  final List<RoomParticipant> participants;
  final List<RoomSpectator> spectators;
  final List<RoomEvent> events;

  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final String? friendlyError;
  final String? myUserId;
  final RoomConnectionStatus connectionStatus;

  // ── Convenience getters ────────────────────────────────────────────

  bool get hasGame => gameId != null;
  bool get isLobby => status == RoomStatus.lobby;
  bool get isCountdown => status == RoomStatus.countdown;
  bool get isActive => status == RoomStatus.active;
  bool get isFinished => status == RoomStatus.finished;
  bool get isCancelled => status == RoomStatus.cancelled;
  bool get isClosed => cancelledAt != null || closedAt != null;

  /// True if the local user is the host.
  bool get isHost => hostUserId != null && hostUserId == myUserId;

  /// True if the local user is a spectator (not a participant).
  bool get isSpectator =>
      !participants.any((p) => p.userId == myUserId) &&
      spectators.any((s) => s.userId == myUserId);

  /// True if the local user is in the room at all (participant or spectator).
  bool get isInRoom =>
      participants.any((p) => p.userId == myUserId) ||
      spectators.any((s) => s.userId == myUserId);

  /// The local user's participant record (null if not a participant).
  RoomParticipant? get me {
    final id = myUserId;
    if (id == null) return null;
    for (final p in participants) {
      if (p.userId == id) return p;
    }
    return null;
  }

  /// Number of participants (excluding spectators).
  int get playerCount => participants.length;

  /// Number of ready participants (host always counts as ready).
  int get readyCount =>
      participants.where((p) => p.isReady || p.isHost).length;

  /// Are all required players ready?
  /// (Host is always ready; non-host players must tap Ready.)
  bool get allRequiredReady {
    if (participants.isEmpty) return false;
    for (final p in participants) {
      if (!p.isHost && !p.isReady) return false;
    }
    return true;
  }

  /// Number of seconds until auto-close. Returns null if no deadline.
  /// Returns 0 if the deadline has passed (caller should trigger close).
  int? get secondsUntilAutoClose {
    final deadline = autoCloseDeadline;
    if (deadline == null) return null;
    final now = DateTime.now();
    final delta = deadline.difference(now).inSeconds;
    return delta < 0 ? 0 : delta;
  }

  /// Number of seconds until the match-start countdown ends. Returns null
  /// if no countdown is active. Returns 0 if the countdown has expired
  /// (the host's client should fire the game's start callback now).
  int? get secondsUntilCountdownEnds {
    final deadline = countdownEndsAt;
    if (deadline == null) return null;
    final now = DateTime.now();
    final delta = deadline.difference(now).inSeconds;
    return delta < 0 ? 0 : delta;
  }

  /// Number of online (non-spectator) participants.
  int get onlineParticipantCount =>
      participants.where((p) => p.isOnline).length;

  /// Number of spectators currently watching.
  int get spectatorCount => spectators.length;

  /// A short human-readable status string for the lobby header.
  /// Examples:
  ///   "Waiting for 1 more player • Invite family members"
  ///   "Room ready • All players joined"
  ///   "Match starts in 5…"
  String lobbySubtitle({required int minPlayers}) {
    if (isCountdown) {
      final s = secondsUntilCountdownEnds ?? 0;
      return 'Match starts in $s\u2026';
    }
    final missing = minPlayers - playerCount;
    if (missing > 0) {
      return 'Waiting for $missing more player${missing == 1 ? '' : 's'} \u2022 Invite family members';
    }
    if (!allRequiredReady) {
      return 'Waiting for players to ready up \u2022 $readyCount of $playerCount ready';
    }
    return 'Room ready \u2022 All players joined';
  }

  RoomState copyWith({
    String? gameId,
    bool clearGameId = false,
    String? familyId,
    String? hostUserId,
    String? hostUserName,
    RoomStatus? status,
    bool? spectatorsEnabled,
    DateTime? autoCloseDeadline,
    bool clearAutoCloseDeadline = false,
    DateTime? countdownEndsAt,
    bool clearCountdownEndsAt = false,
    DateTime? cancelledAt,
    bool clearCancelledAt = false,
    DateTime? closedAt,
    bool clearClosedAt = false,
    List<RoomParticipant>? participants,
    List<RoomSpectator>? spectators,
    List<RoomEvent>? events,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
    String? friendlyError,
    bool clearFriendlyError = false,
    String? myUserId,
    RoomConnectionStatus? connectionStatus,
  }) =>
      RoomState(
        gameId: clearGameId ? null : (gameId ?? this.gameId),
        familyId: familyId ?? this.familyId,
        hostUserId: hostUserId ?? this.hostUserId,
        hostUserName: hostUserName ?? this.hostUserName,
        status: status ?? this.status,
        spectatorsEnabled: spectatorsEnabled ?? this.spectatorsEnabled,
        autoCloseDeadline:
            clearAutoCloseDeadline ? null : (autoCloseDeadline ?? this.autoCloseDeadline),
        countdownEndsAt: clearCountdownEndsAt
            ? null
            : (countdownEndsAt ?? this.countdownEndsAt),
        cancelledAt: clearCancelledAt ? null : (cancelledAt ?? this.cancelledAt),
        closedAt: clearClosedAt ? null : (closedAt ?? this.closedAt),
        participants: participants ?? this.participants,
        spectators: spectators ?? this.spectators,
        events: events ?? this.events,
        isLoading: isLoading ?? this.isLoading,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
        friendlyError: clearFriendlyError ? null : (friendlyError ?? this.friendlyError),
        myUserId: myUserId ?? this.myUserId,
        connectionStatus: connectionStatus ?? this.connectionStatus,
      );
}

/// Coarse-grained realtime channel state. Drives the "Reconnecting…" /
/// "Connection lost" banner in the lobby UI.
enum RoomConnectionStatus { idle, connecting, connected, reconnecting, error }
