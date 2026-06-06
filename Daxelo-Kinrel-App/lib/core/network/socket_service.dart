// lib/core/network/socket_service.dart
//
// DAXELO KINREL — Socket.IO Reconnection Service
//
// Manages WebSocket connection with automatic reconnection,
// silent delta sync on reconnect, and Riverpod provider invalidation.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_config.dart';
import '../database/app_database_service.dart';
import '../database/app_database.dart';
import '../database/sync/cache_invalidation.dart';
import '../services/supabase_service.dart';
import '../networking/dio_client.dart';
import '../family/family_provider.dart';
import '../../presentation/providers/follow_provider.dart';
import '../../presentation/providers/sparq_provider.dart';
import '../../features/notifications/providers/notifications_provider.dart';

// ── Socket Status Enum ──────────────────────────────────────────────

/// Represents the current state of the WebSocket connection.
enum SocketStatus {
  connected,
  disconnected,
  reconnecting,
}

// ── Socket Status Provider ──────────────────────────────────────────

/// Global Riverpod StateProvider for socket connection status.
/// Accessible from anywhere without creating coupling — just read/watch
/// this provider to react to connection state changes.
final socketStatusProvider = StateProvider<SocketStatus>(
  (ref) => SocketStatus.disconnected,
);

// ── Minimal Event Payload Models ────────────────────────────────────

/// Minimal payload emitted by the NestJS gateway for person events.
class _MinimalPersonEvent {
  final String id;
  final String updatedAt;
  final String? familyId;

  _MinimalPersonEvent({
    required this.id,
    required this.updatedAt,
    this.familyId,
  });

  factory _MinimalPersonEvent.fromJson(Map<String, dynamic> json) {
    return _MinimalPersonEvent(
      id: json['id'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      familyId: json['familyId'] as String?,
    );
  }
}

/// Minimal payload for graph update events.
class _MinimalGraphEvent {
  final String familyId;
  final String updatedAt;

  _MinimalGraphEvent({
    required this.familyId,
    required this.updatedAt,
  });

  factory _MinimalGraphEvent.fromJson(Map<String, dynamic> json) {
    return _MinimalGraphEvent(
      familyId: json['familyId'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

// ── Sync Response Model ─────────────────────────────────────────────

/// Response model for the /api/sync endpoint.
class _SyncResponse {
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> familyMeta;
  final String serverTime;
  final bool hasMore;

  _SyncResponse({
    required this.members,
    required this.events,
    required this.familyMeta,
    required this.serverTime,
    required this.hasMore,
  });

  factory _SyncResponse.fromJson(Map<String, dynamic> json) {
    return _SyncResponse(
      members: (json['members'] as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      events: (json['events'] as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      familyMeta: (json['familyMeta'] as List?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
      serverTime: json['serverTime'] as String? ?? '',
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }
}

// ── Socket Service ──────────────────────────────────────────────────

/// Manages the Socket.IO connection with reconnection and delta sync.
///
/// Lifecycle:
/// 1. [connect] — establish WebSocket with auth token
/// 2. On connect/reconnect — call /api/sync with lastSyncTimestamp
/// 3. Merge sync response into Isar silently
/// 4. Invalidate affected Riverpod providers
/// 5. Listen for real-time minimal events and invalidate as needed
class SocketService {
  SocketService(this._ref);

  final Ref _ref;
  io.Socket? _socket;
  StreamSubscription<AuthState>? _authSubscription;

  /// Currently joined family room IDs.
  final Set<String> _joinedFamilyRooms = {};

  /// Last sync timestamp stored in Isar AppSettingsEntry.
  String? _lastSyncTimestamp;

  /// Whether a sync is currently in progress.
  bool _isSyncing = false;

  /// Timestamp of the last completed delta sync. Used to throttle
  /// consecutive syncs and prevent overlapping sync operations that
  /// can cascade into provider invalidation storms causing ANR.
  DateTime? _lastSyncCompletedAt;

  /// Minimum interval between delta syncs to prevent ANR from
  /// rapid reconnection-triggered sync storms.
  static const _minSyncInterval = Duration(seconds: 3);

  /// Debounce timer for batching provider invalidations.
  Timer? _invalidationDebounce;

  /// Pending family IDs to invalidate on the next debounce fire.
  final Set<String> _pendingInvalidations = {};

  /// Timestamp of the last provider invalidation batch.
  /// Used to enforce a cooldown between invalidation batches to prevent
  /// ANR from rapid socket events causing cascading provider rebuilds.
  DateTime? _lastInvalidationAt;

  /// Minimum cooldown between provider invalidation batches.
  /// Prevents rapid socket events from triggering cascading rebuilds
  /// that block the main thread and cause ANR.
  static const _invalidationCooldown = Duration(seconds: 2);

  // ── Public API ──────────────────────────────────────────────────

  /// Connect to the WebSocket server.
  /// Should be called after Supabase initialization.
  void connect() {
    if (_socket != null && _socket!.connected) return;

    final token = _getCurrentAuthToken();
    final socketUrl = _resolveSocketUrl();

    debugPrint('[SocketService] Connecting to $socketUrl...');

    _socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket']) // skip polling entirely
          .setReconnectionAttempts(999)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setTimeout(10000)
          .disableForceNew() // reuse connection (forceNew: false)
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .setAuth({'token': token})
          .enableReconnection()
          .build(),
    );

    _registerEventHandlers();
    _socket!.connect();

    // Listen for auth state changes to reconnect with new token
    _authSubscription?.cancel();
    try {
      final client = _ref.read(supabaseProvider);
      if (client != null) {
        _authSubscription = client.auth.onAuthStateChange.listen((state) {
          if (state.event == AuthChangeEvent.tokenRefreshed ||
              state.event == AuthChangeEvent.signedIn) {
            _reconnectWithNewToken();
          } else if (state.event == AuthChangeEvent.signedOut) {
            disconnect();
          }
        });
      }
    } catch (_) {}
  }

  /// Disconnect from the WebSocket server.
  void disconnect() {
    _invalidationDebounce?.cancel();
    _pendingInvalidations.clear();
    _authSubscription?.cancel();
    _authSubscription = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _joinedFamilyRooms.clear();
    _ref.read(socketStatusProvider.notifier).state =
        SocketStatus.disconnected;
    debugPrint('[SocketService] Disconnected');
  }

  /// Join a family room for real-time updates.
  void joinFamily(String familyId) {
    if (_socket == null || !_socket!.connected) {
      _joinedFamilyRooms.add(familyId);
      return;
    }
    _socket!.emit('join:family', {'familyId': familyId});
    _joinedFamilyRooms.add(familyId);
  }

  /// Leave a family room.
  void leaveFamily(String familyId) {
    _joinedFamilyRooms.remove(familyId);
    if (_socket == null || !_socket!.connected) return;
    _socket!.emit('leave:family', {'familyId': familyId});
  }

  /// Whether the socket is currently connected.
  bool get isConnected =>
      _socket != null && _socket!.connected;

  /// Re-join all family rooms after reconnection.
  void _rejoinAllRooms() {
    for (final familyId in _joinedFamilyRooms) {
      _socket?.emit('join:family', {'familyId': familyId});
    }
  }

  // ── Event Handlers ──────────────────────────────────────────────

  void _registerEventHandlers() {
    final socket = _socket!;

    socket.onConnect((_) {
      debugPrint('[SocketService] ✅ Connected');
      _ref.read(socketStatusProvider.notifier).state =
          SocketStatus.connected;

      // Re-join rooms on reconnect
      _rejoinAllRooms();

      // Perform delta sync on every (re)connection
      _performDeltaSync();
    });

    socket.onDisconnect((_) {
      debugPrint('[SocketService] 🔴 Disconnected');
      _ref.read(socketStatusProvider.notifier).state =
          SocketStatus.disconnected;
    });

    // socket_io_client uses onReconnect for reconnect events
    socket.onReconnect((_) {
      debugPrint('[SocketService] 🔄 Reconnected');
      _ref.read(socketStatusProvider.notifier).state =
          SocketStatus.connected;
      // Delta sync is already triggered by onConnect above
      // (socket.io fires connect after reconnect)
    });

    // Use string event name for reconnecting since socket_io_client
    // doesn't have a dedicated onReconnecting method
    socket.on('reconnecting', (_) {
      debugPrint('[SocketService] ⏳ Reconnecting...');
      _ref.read(socketStatusProvider.notifier).state =
          SocketStatus.reconnecting;
    });

    socket.onConnectError((err) {
      debugPrint('[SocketService] ❌ Connect error: $err');
      _ref.read(socketStatusProvider.notifier).state =
          SocketStatus.reconnecting;
    });

    // ── Real-time minimal event listeners ──────────────────────

    socket.on('person:created', (data) => _onPersonEvent(data, 'created'));
    socket.on('person:updated', (data) => _onPersonEvent(data, 'updated'));
    socket.on('person:deleted', (data) => _onPersonEvent(data, 'deleted'));
    socket.on('relationship:created', (data) => _onRelationshipEvent(data));
    socket.on('relationship:deleted', (data) => _onRelationshipEvent(data));
    socket.on('graph:updated', (data) => _onGraphUpdated(data));
    socket.on('joined:family', (data) {
      debugPrint('[SocketService] Joined family: $data');
    });
    socket.on('left:family', (data) {
      debugPrint('[SocketService] Left family: $data');
    });
    socket.on('error', (data) {
      debugPrint('[SocketService] Error: $data');
    });

    // ── Follow events ──────────────────────────────────────────────
    socket.on('follow:request', (data) {
      debugPrint('[SocketService] follow:request — $data');
      try {
        // Reload follow requests to show the new request
        _ref.read(followProvider.notifier).loadRequests();
        // Show in-app notification
        final json = data is Map<String, dynamic> ? data : <String, dynamic>{};
        final fromName = json['fromName'] as String? ?? 'Someone';
        _showInAppNotification(
          '@$fromName wants to follow you',
          type: 'follow:request',
        );
      } catch (e) {
        debugPrint('[SocketService] Error handling follow:request: $e');
      }
    });

    socket.on('follow:accepted', (data) {
      debugPrint('[SocketService] follow:accepted — $data');
      try {
        final json = data is Map<String, dynamic> ? data : <String, dynamic>{};
        final userId = json['userId'] as String? ?? '';
        // Update follow status cache for that userId → 'following'
        final updatedCache = Map<String, String>.from(
          _ref.read(followProvider).statusCache,
        );
        updatedCache[userId] = 'following';
        _ref.read(followProvider.notifier).state = _ref.read(followProvider).copyWith(
          statusCache: updatedCache,
        );
        // Reload following list
        _ref.read(followProvider.notifier).loadFollowing();
        // Show in-app notification
        final fromName = json['fromName'] as String? ?? 'Someone';
        _showInAppNotification(
          '@$fromName accepted your follow request',
          type: 'follow:accepted',
        );
      } catch (e) {
        debugPrint('[SocketService] Error handling follow:accepted: $e');
      }
    });

    socket.on('follow:new', (data) {
      debugPrint('[SocketService] follow:new — $data');
      try {
        // Reload followers to update count
        _ref.read(followProvider.notifier).loadFollowers();
        // Show in-app notification
        final json = data is Map<String, dynamic> ? data : <String, dynamic>{};
        final fromName = json['fromName'] as String? ?? 'Someone';
        _showInAppNotification(
          '@$fromName started following you',
          type: 'follow:new',
        );
      } catch (e) {
        debugPrint('[SocketService] Error handling follow:new: $e');
      }
    });

    // ── Family events ──────────────────────────────────────────────
    socket.on('family:member:joined', (data) {
      debugPrint('[SocketService] family:member:joined — $data');
      try {
        final json = data is Map<String, dynamic> ? data : <String, dynamic>{};
        final familyId = json['familyId'] as String? ?? '';
        if (familyId.isNotEmpty) {
          _invalidateProvidersForFamily(familyId);
        }
        // Show in-app notification
        final memberName = json['name'] as String? ?? 'Someone';
        _showInAppNotification(
          '@$memberName joined your family',
          type: 'family:member:joined',
        );
      } catch (e) {
        debugPrint('[SocketService] Error handling family:member:joined: $e');
      }
    });

    // ── Sparq events ──────────────────────────────────────────────
    socket.on('sparq:new', (data) {
      debugPrint('[SocketService] sparq:new — $data');
      try {
        // Refresh sparq feed to show new sparq
        _ref.read(sparqProvider.notifier).fetchFeed();
      } catch (e) {
        debugPrint('[SocketService] Error handling sparq:new: $e');
      }
    });
  }

  /// Show an in-app notification banner. Uses the notifications provider
  /// if available, otherwise falls back to a debug print.
  void _showInAppNotification(String message, {String type = 'info'}) {
    try {
      _ref.read(notificationsProvider.notifier).loadNotifications();
    } catch (e) {
      debugPrint('[SocketService] Could not update notifications: $e');
    }
    debugPrint('[SocketService] 🔔 Notification ($type): $message');
  }

  // ── Person Event Handler ────────────────────────────────────────

  /// Handles minimal person events from the server.
  /// Invalidates the relevant family's providers so the UI refetches
  /// fresh data from the API/Isar on demand.
  Future<void> _onPersonEvent(dynamic data, String eventType) async {
    try {
      final json = data is Map<String, dynamic>
          ? data
          : <String, dynamic>{};
      final event = _MinimalPersonEvent.fromJson(json);
      final familyId = event.familyId;

      if (familyId == null || familyId.isEmpty) return;

      debugPrint(
        '[SocketService] person:$eventType — id: ${event.id}, '
        'familyId: $familyId',
      );

      // Invalidate Isar cache for this family
      if (AppDatabaseService.isInitialized) {
        try {
          await CacheInvalidation.invalidateFamily(familyId);
        } catch (_) {}
      }

      // Invalidate Riverpod providers so UI refetches
      _invalidateProvidersForFamily(familyId);
    } catch (e) {
      debugPrint('[SocketService] Error handling person event: $e');
    }
  }

  // ── Relationship Event Handler ──────────────────────────────────

  Future<void> _onRelationshipEvent(dynamic data) async {
    try {
      final json = data is Map<String, dynamic>
          ? data
          : <String, dynamic>{};
      final familyId = json['familyId'] as String?;

      if (familyId == null || familyId.isEmpty) return;

      debugPrint(
        '[SocketService] relationship event — familyId: $familyId',
      );

      // Invalidate Isar cache for this family
      if (AppDatabaseService.isInitialized) {
        try {
          await CacheInvalidation.invalidateFamily(familyId);
        } catch (_) {}
      }

      // Invalidate Riverpod providers
      _invalidateProvidersForFamily(familyId);
    } catch (e) {
      debugPrint('[SocketService] Error handling relationship event: $e');
    }
  }

  // ── Graph Updated Handler ───────────────────────────────────────

  Future<void> _onGraphUpdated(dynamic data) async {
    try {
      final json = data is Map<String, dynamic>
          ? data
          : <String, dynamic>{};
      final event = _MinimalGraphEvent.fromJson(json);

      debugPrint(
        '[SocketService] graph:updated — familyId: ${event.familyId}',
      );

      // Invalidate Isar cache for this family
      if (AppDatabaseService.isInitialized) {
        try {
          await CacheInvalidation.invalidateFamily(event.familyId);
        } catch (_) {}
      }

      // Invalidate Riverpod providers
      _invalidateProvidersForFamily(event.familyId);
    } catch (e) {
      debugPrint('[SocketService] Error handling graph:updated: $e');
    }
  }

  // ── Provider Invalidation ───────────────────────────────────────

  /// Invalidate Riverpod providers related to a family,
  /// causing the UI to refetch fresh data.
  ///
  /// Only invalidates the leaf dependency providers — providers that
  /// ref.watch() those dependencies (familyDetailProvider,
  /// familyMemberCountProvider) will auto-rebuild, avoiding cascading
  /// rebuild loops from double invalidation.
  ///
  /// Uses a 500ms debounce (increased from 100ms) and a 2-second
  /// cooldown between invalidation batches to prevent ANR from rapid
  /// socket events causing cascading provider rebuilds. Invalidations
  /// are queued and processed after the cooldown expires, so no
  /// updates are lost — just delayed.
  void _invalidateProvidersForFamily(String familyId) {
    _pendingInvalidations.add(familyId);
    _invalidationDebounce?.cancel();

    // Check cooldown — if we just invalidated, delay the next batch
    // until the cooldown period has elapsed.
    final canInvalidateNow = _lastInvalidationAt == null ||
        DateTime.now().difference(_lastInvalidationAt!) >= _invalidationCooldown;

    final delay = canInvalidateNow
        ? const Duration(milliseconds: 500)
        : _lastInvalidationAt!
            .add(_invalidationCooldown)
            .difference(DateTime.now());

    _invalidationDebounce = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        try {
          for (final id in _pendingInvalidations) {
            _ref.invalidate(familyMembersProvider(id));
            // familyDetailProvider and familyMemberCountProvider auto-rebuild
            // via ref.watch on familyMembersProvider — no need to invalidate directly
            _ref.invalidate(familyRelationshipsProvider(id));
          }
          if (_pendingInvalidations.isNotEmpty) {
            _ref.invalidate(familyListProvider);
          }
          _lastInvalidationAt = DateTime.now();
          _pendingInvalidations.clear();
        } catch (e) {
          debugPrint('[SocketService] Provider invalidation error: $e');
        }
      },
    );
  }

  // ── Delta Sync on Reconnect ─────────────────────────────────────

  /// Called on connect/reconnect. Fetches changes since lastSyncTimestamp
  /// from /api/sync, merges into Isar, and invalidates providers.
  /// Throttled: won't run if a sync completed less than 3 seconds ago
  /// to prevent rapid reconnection-triggered sync storms causing ANR.
  Future<void> _performDeltaSync() async {
    if (_isSyncing) return;

    // Throttle: don't sync if one just completed recently
    if (_lastSyncCompletedAt != null) {
      final elapsed = DateTime.now().difference(_lastSyncCompletedAt!);
      if (elapsed < _minSyncInterval) {
        debugPrint('[SocketService] Throttling delta sync — last sync was ${elapsed.inMilliseconds}ms ago');
        return;
      }
    }

    _isSyncing = true;

    try {
      // 1. Read lastSyncTimestamp from Isar AppSettingsEntry
      _lastSyncTimestamp = await _getLastSyncTimestamp();

      // 2. Call /api/sync with since parameter
      final syncResponse = await _callSyncEndpoint(_lastSyncTimestamp);

      if (syncResponse == null) {
        debugPrint('[SocketService] Sync endpoint returned null');
        return;
      }

      // 3. Merge response into Isar silently
      await _mergeSyncResponse(syncResponse);

      // 4. Invalidate affected Riverpod providers
      _invalidateAfterSync(syncResponse);

      // 5. Update lastSyncTimestamp in Isar
      final newTimestamp = syncResponse.serverTime.isNotEmpty
          ? syncResponse.serverTime
          : DateTime.now().toIso8601String();
      await _saveLastSyncTimestamp(newTimestamp);
      _lastSyncTimestamp = newTimestamp;

      debugPrint(
        '[SocketService] Delta sync complete — '
        '${syncResponse.members.length} members, '
        '${syncResponse.familyMeta.length} families, '
        '${syncResponse.events.length} events',
      );
    } catch (e) {
      debugPrint('[SocketService] Delta sync error: $e');
    } finally {
      _isSyncing = false;
      _lastSyncCompletedAt = DateTime.now();
    }
  }

  /// Call the /api/sync endpoint with a `since` timestamp.
  Future<_SyncResponse?> _callSyncEndpoint(String? since) async {
    try {
      final dio = _ref.read(dioProvider);
      final response = await dio.post(
        '/sync',
        data: {
          if (since != null && since.isNotEmpty) 'since': since,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : <String, dynamic>{};
        return _SyncResponse.fromJson(data);
      }
    } catch (e) {
      debugPrint('[SocketService] Sync endpoint error: $e');
    }
    return null;
  }

  /// Merge the sync response into Drift silently.
  Future<void> _mergeSyncResponse(_SyncResponse sync) async {
    if (!AppDatabaseService.isInitialized) return;

    final db = AppDatabaseService.instance;
    final affectedFamilyIds = <String>{};

    // Merge families
    for (final familyJson in sync.familyMeta) {
      try {
        final familyId = familyJson['id'] as String? ?? '';
        if (familyId.isEmpty) continue;

        await db.upsertFamily(CachedFamiliesCompanion(
          id: Value(familyJson['id']?.toString() ?? ''),
          name: Value(familyJson['name'] as String? ?? 'Unnamed Family'),
          data: Value(_jsonEncode(familyJson)),
          cachedAt: Value(DateTime.now()),
        ));
        affectedFamilyIds.add(familyId);
      } catch (e) {
        debugPrint('[SocketService] Error merging family: $e');
      }
    }

    // Merge persons
    for (final personJson in sync.members) {
      try {
        final personId = personJson['id'] as String? ?? '';
        final familyId = personJson['familyId'] as String? ?? '';
        if (personId.isEmpty) continue;

        // Skip soft-deleted persons — remove from cache
        final deletedAt = personJson['deletedAt'] as String?;
        if (deletedAt != null) {
          await db.deletePerson(personId);
          affectedFamilyIds.add(familyId);
          continue;
        }

        await db.upsertPerson(CachedPersonsCompanion(
          id: Value(personJson['id']?.toString() ?? ''),
          familyId: Value(personJson['familyId']?.toString() ?? ''),
          name: Value(personJson['name'] as String? ?? 'Unknown'),
          data: Value(_jsonEncode(personJson)),
          cachedAt: Value(DateTime.now()),
        ));
        affectedFamilyIds.add(familyId);
      } catch (e) {
        debugPrint('[SocketService] Error merging person: $e');
      }
    }

    // Merge relationships (from events array)
    for (final relJson in sync.events) {
      try {
        final relId = relJson['id'] as String? ?? '';
        final familyId = relJson['familyId'] as String? ?? '';
        if (relId.isEmpty) continue;

        final isActive = relJson['isActive'] as bool? ?? true;
        if (!isActive) {
          await db.deleteRelationship(relId);
          affectedFamilyIds.add(familyId);
          continue;
        }

        await db.upsertRelationship(CachedRelationshipsCompanion(
          id: Value(relJson['id']?.toString() ?? ''),
          fromId: Value(relJson['fromPersonId']?.toString() ?? ''),
          toId: Value(relJson['toPersonId']?.toString() ?? ''),
          relationshipType: Value(relJson['relationshipKey'] as String? ?? ''),
          kinshipName: Value(relJson['label'] as String?),
          data: Value(_jsonEncode(relJson)),
          cachedAt: Value(DateTime.now()),
        ));
        affectedFamilyIds.add(familyId);
      } catch (e) {
        debugPrint('[SocketService] Error merging relationship: $e');
      }
    }
  }

  /// Invalidate Riverpod providers for all families affected by the sync.
  /// Batches all family invalidations into a single debounce cycle and
  /// invalidates familyListProvider only ONCE (not per family) to avoid
  /// cascading rebuilds that cause ANR.
  void _invalidateAfterSync(_SyncResponse sync) {
    try {
      // Collect all family IDs affected by the sync
      final familyIds = <String>{};
      for (final f in sync.familyMeta) {
        final id = f['id'] as String?;
        if (id != null) familyIds.add(id);
      }
      for (final m in sync.members) {
        final fid = m['familyId'] as String?;
        if (fid != null) familyIds.add(fid);
      }

      // Batch all family IDs into a single invalidation cycle
      // instead of calling _invalidateProvidersForFamily per family
      // (which would trigger N separate debounce timers and N
      // familyListProvider invalidations, causing cascading rebuilds)
      for (final familyId in familyIds) {
        _pendingInvalidations.add(familyId);
      }

      // Fire the batched invalidation once with cooldown-aware delay.
      // Uses the same cooldown mechanism as _invalidateProvidersForFamily
      // to prevent rapid invalidation batches that cause ANR.
      _invalidationDebounce?.cancel();

      final canInvalidateNow = _lastInvalidationAt == null ||
          DateTime.now().difference(_lastInvalidationAt!) >= _invalidationCooldown;

      final delay = canInvalidateNow
          ? const Duration(milliseconds: 500)
          : _lastInvalidationAt!
              .add(_invalidationCooldown)
              .difference(DateTime.now());

      _invalidationDebounce = Timer(
        delay.isNegative ? Duration.zero : delay,
        () {
          try {
            for (final id in _pendingInvalidations) {
              _ref.invalidate(familyMembersProvider(id));
              _ref.invalidate(familyRelationshipsProvider(id));
            }
            // Invalidate familyListProvider only ONCE for the whole batch
            if (_pendingInvalidations.isNotEmpty) {
              _ref.invalidate(familyListProvider);
            }
            _lastInvalidationAt = DateTime.now();
            _pendingInvalidations.clear();
          } catch (e) {
            debugPrint('[SocketService] Post-sync invalidation error: $e');
          }
        },
      );
    } catch (e) {
      debugPrint('[SocketService] Post-sync invalidation error: $e');
    }
  }

  // ── Timestamp Persistence ────────────────────────────────────────

  /// Read lastSyncTimestamp from Drift UserSettings.
  Future<String?> _getLastSyncTimestamp() async {
    if (!AppDatabaseService.isInitialized) return null;

    try {
      final db = AppDatabaseService.instance;
      return db.getSetting('lastSyncTimestamp');
    } catch (e) {
      debugPrint('[SocketService] Error reading lastSyncTimestamp: $e');
      return null;
    }
  }

  /// Save lastSyncTimestamp to Drift UserSettings.
  Future<void> _saveLastSyncTimestamp(String timestamp) async {
    if (!AppDatabaseService.isInitialized) return;

    try {
      final db = AppDatabaseService.instance;
      await db.setSetting('lastSyncTimestamp', timestamp);
    } catch (e) {
      debugPrint('[SocketService] Error saving lastSyncTimestamp: $e');
    }
  }

  // ── Helper Methods ──────────────────────────────────────────────

  /// Get the current auth token from Supabase.
  String? _getCurrentAuthToken() {
    try {
      final client = _ref.read(supabaseProvider);
      return client?.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  /// Resolve the WebSocket URL from the API base URL.
  /// Converts https:// → wss:// and http:// → ws://
  String _resolveSocketUrl() {
    final apiBaseUrl = EnvConfig.apiBaseUrl;
    if (apiBaseUrl.startsWith('https://')) {
      return 'wss://${apiBaseUrl.substring(8)}';
    } else if (apiBaseUrl.startsWith('http://')) {
      return 'ws://${apiBaseUrl.substring(7)}';
    }
    // Fallback
    return 'wss://$apiBaseUrl';
  }

  /// Reconnect with a fresh auth token (e.g., after token refresh).
  void _reconnectWithNewToken() {
    final token = _getCurrentAuthToken();
    if (token == null) return;

    if (_socket != null) {
      _socket!.io.options?['extraHeaders'] = {
        'Authorization': 'Bearer $token',
      };
      _socket!.io.options?['auth'] = {'token': token};
    }
  }

  /// Dispose resources.
  void dispose() {
    disconnect();
    _invalidationDebounce?.cancel();
  }

  /// JSON encode helper for merge operations.
  static String _jsonEncode(Map<String, dynamic> data) {
    return json.encode(data);
  }
}

// ── Riverpod Provider ───────────────────────────────────────────────

/// Riverpod provider for the SocketService singleton.
/// Manages its own lifecycle via ref.onDispose.
final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
