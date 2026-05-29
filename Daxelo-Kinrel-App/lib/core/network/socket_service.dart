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
import '../database/isar_database.dart';
import '../database/app_database.dart';
import '../database/collections/cached_person.dart';
import '../database/collections/cached_family.dart';
import '../database/collections/cached_relationship.dart';
import '../database/sync/cache_invalidation.dart';
import '../services/supabase_service.dart';
import '../networking/dio_client.dart';
import '../family/family_provider.dart';

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
      if (IsarDatabase.isInitialized) {
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
      if (IsarDatabase.isInitialized) {
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
      if (IsarDatabase.isInitialized) {
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

  /// Invalidate all Riverpod providers related to a family,
  /// causing the UI to refetch fresh data.
  void _invalidateProvidersForFamily(String familyId) {
    try {
      _ref.invalidate(familyMembersProvider(familyId));
      _ref.invalidate(familyDetailProvider(familyId));
      _ref.invalidate(familyRelationshipsProvider(familyId));
      _ref.invalidate(familyMemberCountProvider(familyId));
      _ref.invalidate(familyListProvider);
    } catch (e) {
      debugPrint('[SocketService] Provider invalidation error: $e');
    }
  }

  // ── Delta Sync on Reconnect ─────────────────────────────────────

  /// Called on connect/reconnect. Fetches changes since lastSyncTimestamp
  /// from /api/sync, merges into Isar, and invalidates providers.
  Future<void> _performDeltaSync() async {
    if (_isSyncing) return;
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
    if (!IsarDatabase.isInitialized) return;

    final db = IsarDatabase.instance;
    final affectedFamilyIds = <String>{};

    // Merge families
    for (final familyJson in sync.familyMeta) {
      try {
        final familyId = familyJson['id'] as String? ?? '';
        if (familyId.isEmpty) continue;

        final cached = CachedFamily.fromJson(familyJson);
        await db.upsertFamily(CachedFamiliesCompanion(
          id: Value(cached.id),
          name: Value(cached.name),
          data: Value(_jsonEncode(cached.toJson())),
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

        final cached = CachedPerson.fromJson(personJson);
        await db.upsertPerson(CachedPersonsCompanion(
          id: Value(cached.id),
          familyId: Value(cached.familyId),
          name: Value(cached.name),
          data: Value(_jsonEncode(cached.toJson())),
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

        final cached = CachedRelationship.fromJson(relJson);
        await db.upsertRelationship(CachedRelationshipsCompanion(
          id: Value(cached.id),
          fromId: Value(cached.fromPersonId),
          toId: Value(cached.toPersonId),
          relationshipType: Value(cached.relationshipKey),
          kinshipName: Value(cached.label),
          data: Value(_jsonEncode(cached.toJson())),
          cachedAt: Value(DateTime.now()),
        ));
        affectedFamilyIds.add(familyId);
      } catch (e) {
        debugPrint('[SocketService] Error merging relationship: $e');
      }
    }
  }

  /// Invalidate Riverpod providers for all families affected by the sync.
  void _invalidateAfterSync(_SyncResponse sync) {
    try {
      // Invalidate the family list (may have new families)
      _ref.invalidate(familyListProvider);

      // Invalidate detail providers for each family in the sync
      final familyIds = <String>{};
      for (final f in sync.familyMeta) {
        final id = f['id'] as String?;
        if (id != null) familyIds.add(id);
      }
      for (final m in sync.members) {
        final fid = m['familyId'] as String?;
        if (fid != null) familyIds.add(fid);
      }

      for (final familyId in familyIds) {
        _invalidateProvidersForFamily(familyId);
      }
    } catch (e) {
      debugPrint('[SocketService] Post-sync invalidation error: $e');
    }
  }

  // ── Timestamp Persistence ────────────────────────────────────────

  /// Read lastSyncTimestamp from Drift UserSettings.
  Future<String?> _getLastSyncTimestamp() async {
    if (!IsarDatabase.isInitialized) return null;

    try {
      final db = IsarDatabase.instance;
      return db.getSetting('lastSyncTimestamp');
    } catch (e) {
      debugPrint('[SocketService] Error reading lastSyncTimestamp: $e');
      return null;
    }
  }

  /// Save lastSyncTimestamp to Drift UserSettings.
  Future<void> _saveLastSyncTimestamp(String timestamp) async {
    if (!IsarDatabase.isInitialized) return;

    try {
      final db = IsarDatabase.instance;
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
