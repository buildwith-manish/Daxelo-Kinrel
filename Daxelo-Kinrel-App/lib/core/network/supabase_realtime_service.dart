// lib/core/network/supabase_realtime_service.dart
//
// DAXELO KINREL — Supabase Realtime Service (Flutter)
//
// Replaces Socket.IO with Supabase Realtime for real-time updates.
// Subscribes to Postgres Changes, Presence, and Broadcast channels.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../database/sync/cache_invalidation.dart';
import '../database/isar_database.dart';
import '../family/family_provider.dart';
import '../networking/dio_client.dart';
import 'realtime_dedup.dart';

// ── Event Models ────────────────────────────────────────────────────

/// Event payload for family graph updates.
class FamilyUpdateEvent {
  final String familyId;
  final String eventType;
  final Map<String, dynamic> payload;
  final String timestamp;

  FamilyUpdateEvent({
    required this.familyId,
    required this.eventType,
    required this.payload,
    required this.timestamp,
  });

  factory FamilyUpdateEvent.fromJson(Map<String, dynamic> json) {
    return FamilyUpdateEvent(
      familyId: json['familyId'] as String? ?? '',
      eventType: json['eventType'] as String? ?? '',
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      timestamp: json['timestamp'] as String? ?? '',
    );
  }
}

/// Event payload for user-specific notifications.
class NotificationEvent {
  final String eventType;
  final Map<String, dynamic> payload;
  final String timestamp;

  NotificationEvent({
    required this.eventType,
    required this.payload,
    required this.timestamp,
  });

  factory NotificationEvent.fromJson(Map<String, dynamic> json) {
    return NotificationEvent(
      eventType: json['eventType'] as String? ?? '',
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      timestamp: json['timestamp'] as String? ?? '',
    );
  }
}

/// Presence state for online/offline tracking.
class FamilyPresenceState {
  final String userId;
  final String familyId;
  final String status;
  final String lastSeen;

  FamilyPresenceState({
    required this.userId,
    required this.familyId,
    required this.status,
    required this.lastSeen,
  });

  factory FamilyPresenceState.fromJson(Map<String, dynamic> json) {
    return FamilyPresenceState(
      userId: json['userId'] as String? ?? '',
      familyId: json['familyId'] as String? ?? '',
      status: json['status'] as String? ?? 'offline',
      lastSeen: json['lastSeen'] as String? ?? '',
    );
  }
}

// ── Realtime Connection Status ──────────────────────────────────────

enum RealtimeStatus {
  connected,
  disconnected,
  connecting,
}

/// Global Riverpod StateProvider for realtime connection status.
final realtimeStatusProvider = StateProvider<RealtimeStatus>(
  (ref) => RealtimeStatus.disconnected,
);

// ── Supabase Realtime Service ───────────────────────────────────────

/// Manages Supabase Realtime subscriptions for family and user channels.
///
/// Replaces the Socket.IO-based approach with Supabase's native Realtime:
/// - **Postgres Changes**: Listen to INSERT/UPDATE/DELETE on Person,
///   Relationship, FamilyInvite, Notification tables.
/// - **Presence**: Track online/offline status per family.
/// - **Broadcast**: Custom events like graph:updated.
///
/// Enhancements over original:
/// - **Deduplication**: Uses [RealtimeDedup] to skip duplicate events.
/// - **Member Presence**: Subscribes to Presence channels for each family.
/// - **Connection Status Stream**: Exposes a Stream<bool> for online/offline.
/// - **Duplicate Subscription Prevention**: Checks if already subscribed
///   before creating a new channel.
class SupabaseRealtimeService {
  SupabaseRealtimeService(this._ref);

  final Ref _ref;

  /// Active Supabase Realtime channels keyed by channel name.
  final Map<String, RealtimeChannel> _channels = {};

  /// Stream controllers for family update events.
  final Map<String, StreamController<FamilyUpdateEvent>> _familyStreams = {};

  /// Stream controller for notification events.
  final StreamController<NotificationEvent> _notificationStreamController =
      StreamController<NotificationEvent>.broadcast();

  /// Stream controllers for presence updates per family.
  final Map<String, StreamController<List<FamilyPresenceState>>>
      _presenceStreams = {};

  /// Set of currently subscribed family IDs.
  final Set<String> _subscribedFamilies = {};

  /// Whether the service is currently active.
  bool _isActive = false;

  /// Deduplication helper to prevent processing duplicate events.
  final RealtimeDedup _dedup = RealtimeDedup();

  /// Stream controller for connection status (online/offline).
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();

  /// Stream of connection status changes (true = online, false = offline).
  Stream<bool> get onConnectionStatusChanged =>
      _connectionStatusController.stream;

  /// Current connection status.
  bool _isOnline = false;

  /// Whether the realtime connection is currently online.
  bool get isOnline => _isOnline;

  // ── Public API ────────────────────────────────────────────────────

  /// Subscribe to a family channel for real-time updates.
  ///
  /// Returns a stream of [FamilyUpdateEvent] for the given family.
  /// If already subscribed, returns the existing stream without
  /// creating a duplicate subscription.
  Stream<FamilyUpdateEvent> subscribeToFamily(String familyId) {
    if (!_familyStreams.containsKey(familyId)) {
      _familyStreams[familyId] =
          StreamController<FamilyUpdateEvent>.broadcast();
    }

    // Prevent duplicate subscription — only set up channel once
    if (!_subscribedFamilies.contains(familyId)) {
      _subscribedFamilies.add(familyId);
      _setupFamilyChannel(familyId);
    }

    return _familyStreams[familyId]!.stream;
  }

  /// Subscribe to user notification events.
  /// Prevents duplicate subscription by checking if the channel exists.
  Stream<NotificationEvent> subscribeToNotifications(String userId) {
    final channelName = 'user:$userId';
    if (!_channels.containsKey(channelName)) {
      _setupUserChannel(userId);
    }
    return _notificationStreamController.stream;
  }

  /// Subscribe to presence updates for a family.
  Stream<List<FamilyPresenceState>> subscribeToPresence(String familyId) {
    if (!_presenceStreams.containsKey(familyId)) {
      _presenceStreams[familyId] =
          StreamController<List<FamilyPresenceState>>.broadcast();
    }
    return _presenceStreams[familyId]!.stream;
  }

  /// Update presence status for a family.
  Future<void> updatePresence(String familyId, String status) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;

    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    final channelName = 'family:$familyId';
    final channel = _channels[channelName];

    if (channel == null) return;

    try {
      if (status == 'online') {
        await channel.track({
          'userId': userId,
          'familyId': familyId,
          'status': 'online',
          'lastSeen': DateTime.now().toIso8601String(),
        });
      } else {
        await channel.untrack();
      }

      debugPrint(
        '[SupabaseRealtime] Presence updated: $userId → $status in family:$familyId',
      );
    } catch (e) {
      debugPrint('[SupabaseRealtime] Error updating presence: $e');
    }
  }

  /// Unsubscribe from a specific family channel.
  void unsubscribeFromFamily(String familyId) {
    _subscribedFamilies.remove(familyId);

    final channelName = 'family:$familyId';
    final channel = _channels.remove(channelName);
    if (channel != null) {
      try {
        Supabase.instance.client.removeChannel(channel);
      } catch (_) {}
    }

    final stream = _familyStreams.remove(familyId);
    stream?.close();

    final presenceStream = _presenceStreams.remove(familyId);
    presenceStream?.close();

    debugPrint(
      '[SupabaseRealtime] Unsubscribed from family:$familyId',
    );
  }

  /// Unsubscribe from all channels.
  void unsubscribeAll() {
    for (final entry in _channels.entries) {
      try {
        Supabase.instance.client.removeChannel(entry.value);
      } catch (_) {}
    }
    _channels.clear();
    _subscribedFamilies.clear();

    for (final stream in _familyStreams.values) {
      stream.close();
    }
    _familyStreams.clear();

    for (final stream in _presenceStreams.values) {
      stream.close();
    }
    _presenceStreams.clear();

    _notificationStreamController.close();
    _connectionStatusController.close();

    _isActive = false;
    _isOnline = false;
    _dedup.clear();

    _ref.read(realtimeStatusProvider.notifier).state =
        RealtimeStatus.disconnected;

    debugPrint('[SupabaseRealtime] Unsubscribed from all channels');
  }

  /// Whether the service is currently active.
  bool get isActive => _isActive;

  // ── Channel Setup ─────────────────────────────────────────────────

  /// Set up a family channel with Postgres Changes, Presence, and Broadcast.
  void _setupFamilyChannel(String familyId) {
    final client = _ref.read(supabaseProvider);
    if (client == null) {
      debugPrint(
        '[SupabaseRealtime] Cannot setup family channel — Supabase not initialized',
      );
      return;
    }

    final channelName = 'family:$familyId';

    if (_channels.containsKey(channelName)) return;

    _ref.read(realtimeStatusProvider.notifier).state =
        RealtimeStatus.connecting;

    final channel = client.channel(channelName);

    // ── Postgres Changes: Person table ──
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'Person',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'familyId',
        value: familyId,
      ),
      callback: (PostgresChangePayload payload) {
        _handlePersonChange(familyId, payload);
      },
    );

    // ── Postgres Changes: Relationship table ──
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'Relationship',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'familyId',
        value: familyId,
      ),
      callback: (PostgresChangePayload payload) {
        _handleRelationshipChange(familyId, payload);
      },
    );

    // ── Broadcast: Custom events (graph:updated, etc.) ──
    channel.onBroadcastEvent(
      event: 'graph:updated',
      callback: (Map<String, dynamic> payload) {
        _handleBroadcastEvent(familyId, 'graph:updated', payload);
      },
    );

    channel.onBroadcastEvent(
      event: 'person:created',
      callback: (Map<String, dynamic> payload) {
        _handleBroadcastEvent(familyId, 'person:created', payload);
      },
    );

    channel.onBroadcastEvent(
      event: 'person:updated',
      callback: (Map<String, dynamic> payload) {
        _handleBroadcastEvent(familyId, 'person:updated', payload);
      },
    );

    channel.onBroadcastEvent(
      event: 'person:deleted',
      callback: (Map<String, dynamic> payload) {
        _handleBroadcastEvent(familyId, 'person:deleted', payload);
      },
    );

    channel.onBroadcastEvent(
      event: 'relationship:created',
      callback: (Map<String, dynamic> payload) {
        _handleBroadcastEvent(familyId, 'relationship:created', payload);
      },
    );

    channel.onBroadcastEvent(
      event: 'relationship:deleted',
      callback: (Map<String, dynamic> payload) {
        _handleBroadcastEvent(familyId, 'relationship:deleted', payload);
      },
    );

    // ── Presence ──
    channel.onPresenceSync((PresenceSyncPayload payload) {
      _handlePresenceSync(familyId, payload);
    });

    channel.onPresenceJoin((PresenceJoinPayload payload) {
      _handlePresenceSync(
        familyId,
        PresenceSyncPayload(
          currentPresence: payload.currentPresences,
          joinedPresence: payload.newPresences,
          leftPresence: [],
        ),
      );
    });

    channel.onPresenceLeave((PresenceLeavePayload payload) {
      _handlePresenceSync(
        familyId,
        PresenceSyncPayload(
          currentPresence: payload.currentPresences,
          joinedPresence: [],
          leftPresence: payload.leftPresences,
        ),
      );
    });

    // Subscribe
    channel.subscribe((RealtimeSubscribeStatus status, Object? error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _isActive = true;
        _isOnline = true;
        _ref.read(realtimeStatusProvider.notifier).state =
            RealtimeStatus.connected;
        if (!_connectionStatusController.isClosed) {
          _connectionStatusController.add(true);
        }
        debugPrint(
          '[SupabaseRealtime] ✅ Subscribed to $channelName',
        );

        // Track presence
        final userId = client.auth.currentUser?.id;
        if (userId != null) {
          channel.track({
            'userId': userId,
            'familyId': familyId,
            'status': 'online',
            'lastSeen': DateTime.now().toIso8601String(),
          });
        }
      } else if (status == RealtimeSubscribeStatus.channelError) {
        _isOnline = false;
        if (!_connectionStatusController.isClosed) {
          _connectionStatusController.add(false);
        }
        _ref.read(realtimeStatusProvider.notifier).state =
            RealtimeStatus.disconnected;
        debugPrint(
          '[SupabaseRealtime] ❌ Channel error on $channelName: $error',
        );
      } else if (status == RealtimeSubscribeStatus.timedOut) {
        _isOnline = false;
        if (!_connectionStatusController.isClosed) {
          _connectionStatusController.add(false);
        }
        _ref.read(realtimeStatusProvider.notifier).state =
            RealtimeStatus.disconnected;
        debugPrint(
          '[SupabaseRealtime] ⏳ Subscription timed out on $channelName',
        );
      }
    });

    _channels[channelName] = channel;
  }

  /// Set up a user-specific notification channel.
  void _setupUserChannel(String userId) {
    final client = _ref.read(supabaseProvider);
    if (client == null) return;

    final channelName = 'user:$userId';

    if (_channels.containsKey(channelName)) return;

    final channel = client.channel(channelName);

    // Postgres Changes: Notification table for this user
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'Notification',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'userId',
        value: userId,
      ),
      callback: (PostgresChangePayload payload) {
        final event = NotificationEvent(
          eventType: 'notification:new',
          payload: payload.newRecord,
          timestamp: DateTime.now().toIso8601String(),
        );

        if (!_notificationStreamController.isClosed) {
          _notificationStreamController.add(event);
        }
      },
    );

    // Broadcast events from the server
    channel.onBroadcastEvent(
      event: 'invite:updated',
      callback: (Map<String, dynamic> payload) {
        final event = NotificationEvent(
          eventType: 'invite:updated',
          payload: payload,
          timestamp: DateTime.now().toIso8601String(),
        );
        if (!_notificationStreamController.isClosed) {
          _notificationStreamController.add(event);
        }
      },
    );

    channel.subscribe((RealtimeSubscribeStatus status, Object? error) {
      debugPrint(
        '[SupabaseRealtime] User channel $channelName status: $status',
      );
    });

    _channels[channelName] = channel;
  }

  // ── Event Handlers ────────────────────────────────────────────────

  void _handlePersonChange(
    String familyId,
    PostgresChangePayload payload,
  ) {
    final eventType = payload.eventType.name;
    final record = payload.newRecord.isNotEmpty
        ? payload.newRecord
        : payload.oldRecord;

    // ── Deduplication ──────────────────────────────────────────────
    final eventId = 'person:${record['id']}:$eventType:${record['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch}';
    if (_dedup.isDuplicate(eventId)) {
      debugPrint(
        '[SupabaseRealtime] Skipping duplicate person event: $eventId',
      );
      return;
    }

    debugPrint(
      '[SupabaseRealtime] Person $eventType in family:$familyId — id: ${record['id']}',
    );

    final event = FamilyUpdateEvent(
      familyId: familyId,
      eventType: 'person:$eventType',
      payload: Map<String, dynamic>.from(record),
      timestamp: DateTime.now().toIso8601String(),
    );

    _emitFamilyEvent(familyId, event);
    _invalidateProvidersForFamily(familyId);
  }

  void _handleRelationshipChange(
    String familyId,
    PostgresChangePayload payload,
  ) {
    final eventType = payload.eventType.name;

    // ── Deduplication ──────────────────────────────────────────────
    final record = payload.newRecord.isNotEmpty
        ? payload.newRecord
        : payload.oldRecord;
    final eventId = 'relationship:${record['id']}:$eventType:${record['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch}';
    if (_dedup.isDuplicate(eventId)) {
      debugPrint(
        '[SupabaseRealtime] Skipping duplicate relationship event: $eventId',
      );
      return;
    }

    debugPrint(
      '[SupabaseRealtime] Relationship $eventType in family:$familyId',
    );

    final event = FamilyUpdateEvent(
      familyId: familyId,
      eventType: 'relationship:$eventType',
      payload: Map<String, dynamic>.from(record),
      timestamp: DateTime.now().toIso8601String(),
    );

    _emitFamilyEvent(familyId, event);
    _invalidateProvidersForFamily(familyId);
  }

  void _handleBroadcastEvent(
    String familyId,
    String eventType,
    Map<String, dynamic> payload,
  ) {
    debugPrint(
      '[SupabaseRealtime] Broadcast $eventType in family:$familyId',
    );

    final event = FamilyUpdateEvent(
      familyId: familyId,
      eventType: eventType,
      payload: payload,
      timestamp: DateTime.now().toIso8601String(),
    );

    _emitFamilyEvent(familyId, event);
    _invalidateProvidersForFamily(familyId);
  }

  void _handlePresenceSync(
    String familyId,
    PresenceSyncPayload payload,
  ) {
    final users = <FamilyPresenceState>[];

    for (final presence in payload.currentPresence) {
      try {
        users.add(FamilyPresenceState.fromJson(
          Map<String, dynamic>.from(presence as Map),
        ));
      } catch (_) {}
    }

    final stream = _presenceStreams[familyId];
    if (stream != null && !stream.isClosed) {
      stream.add(users);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  void _emitFamilyEvent(String familyId, FamilyUpdateEvent event) {
    final stream = _familyStreams[familyId];
    if (stream != null && !stream.isClosed) {
      stream.add(event);
    }
  }

  void _invalidateProvidersForFamily(String familyId) {
    try {
      // Invalidate Isar cache for this family
      if (IsarDatabase.isInitialized) {
        try {
          CacheInvalidation.invalidateFamily(familyId);
        } catch (_) {}
      }

      // Invalidate Riverpod providers so UI refetches
      _ref.invalidate(familyMembersProvider(familyId));
      _ref.invalidate(familyDetailProvider(familyId));
      _ref.invalidate(familyRelationshipsProvider(familyId));
      _ref.invalidate(familyMemberCountProvider(familyId));
      _ref.invalidate(familyListProvider);
    } catch (e) {
      debugPrint('[SupabaseRealtime] Provider invalidation error: $e');
    }
  }

  /// Dispose all resources.
  void dispose() {
    unsubscribeAll();
  }
}

// ── Riverpod Providers ──────────────────────────────────────────────

/// Provider for the SupabaseRealtimeService singleton.
final supabaseRealtimeServiceProvider = Provider<SupabaseRealtimeService>(
  (ref) {
    final service = SupabaseRealtimeService(ref);
    ref.onDispose(() => service.dispose());
    return service;
  },
);

/// Provider that exposes the realtime connection status.
final realtimeConnectionStatusProvider = Provider<RealtimeStatus>(
  (ref) => ref.watch(realtimeStatusProvider),
);

/// Provider for online members in a specific family.
final familyOnlineMembersProvider =
    StreamProvider.family<List<FamilyPresenceState>, String>(
  (ref, familyId) {
    final service = ref.watch(supabaseRealtimeServiceProvider);
    return service.subscribeToPresence(familyId);
  },
);

/// Provider for family update events.
final familyUpdateEventsProvider =
    StreamProvider.family<FamilyUpdateEvent, String>(
  (ref, familyId) {
    final service = ref.watch(supabaseRealtimeServiceProvider);
    return service.subscribeToFamily(familyId);
  },
);

/// Provider for user notification events.
final userNotificationEventsProvider =
    StreamProvider.family<NotificationEvent, String>(
  (ref, userId) {
    final service = ref.watch(supabaseRealtimeServiceProvider);
    return service.subscribeToNotifications(userId);
  },
);

/// Provider for realtime connection status stream (bool: true = online).
final realtimeOnlineStatusProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(supabaseRealtimeServiceProvider);
  return service.onConnectionStatusChanged;
});
