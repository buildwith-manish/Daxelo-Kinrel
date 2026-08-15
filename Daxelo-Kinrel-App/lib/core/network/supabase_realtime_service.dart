// lib/core/network/supabase_realtime_service.dart
//
// DAXELO KINREL — Supabase Realtime Subscription Service
//
// Per-family Postgres Changes subscriptions that listen for INSERT/UPDATE/DELETE
// on families, persons, and relationships tables. When a change is detected,
// the service invalidates the relevant Riverpod providers and upserts/deletes
// the changed row in the Drift cache.
//
// Key design decisions:
// - Per-family channels (not global) so we only subscribe to families the user
//   is actively viewing or is a member of
// - Echo detection via RealtimeDedup (skips events caused by our own writes)
// - Auto-reconnect via Supabase Realtime's built-in mechanism
// - Debounced provider invalidation (500ms) to prevent ANR from rapid events
// - Co-exists with Socket.IO: Supabase Realtime handles Postgres changes;
//   Socket.IO handles application-level events (follow, sparq, etc.)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:drift/drift.dart';

import '../family/family_provider.dart';
import '../database/isar_database.dart';
import '../database/app_database.dart';
import '../services/supabase_service.dart';
import 'realtime_dedup.dart';

// ════════════════════════════════════════════════════════════════════
// SUPABASE REALTIME SERVICE
// ════════════════════════════════════════════════════════════════════

class SupabaseRealtimeService {
  SupabaseRealtimeService(this._ref);

  final Ref _ref;

  /// Active Supabase Realtime channels, keyed by family ID.
  final Map<String, RealtimeChannel> _familyChannels = {};

  /// Dedup cache for echo detection.
  final RealtimeDedup _dedup = RealtimeDedup();

  /// Debounce timers for provider invalidation.
  final Map<String, Timer> _invalidationTimers = {};

  /// Sets of family IDs that need provider invalidation.
  final Set<String> _pendingFamilyInvalidations = {};
  bool _pendingListInvalidation = false;

  /// Current user ID for echo detection.
  String? _currentUserId;

  /// Whether the service has been initialized.
  bool _isInitialized = false;

  // ── Lifecycle ────────────────────────────────────────────────────

  /// Initialize the realtime service. Call after Supabase is ready.
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    _currentUserId =
        _ref.read(supabaseProvider)?.auth.currentUser?.id;

    debugPrint('[SupabaseRealtime] Initialized for user: $_currentUserId');
  }

  /// Dispose all subscriptions.
  void dispose() {
    for (final timer in _invalidationTimers.values) {
      timer.cancel();
    }
    _invalidationTimers.clear();

    for (final channel in _familyChannels.values) {
      try {
        _ref.read(supabaseProvider)?.removeChannel(channel);
      } catch (_) {}
    }
    _familyChannels.clear();
    _isInitialized = false;
    debugPrint('[SupabaseRealtime] Disposed');
  }

  // ── Per-Family Subscription ──────────────────────────────────────

  /// Subscribe to realtime changes for a specific family.
  /// Creates a Supabase Realtime channel that listens for:
  /// - Person INSERT/UPDATE/DELETE (where familyId = target)
  /// - Relationship INSERT/UPDATE/DELETE (where familyId = target)
  /// - Family UPDATE (where id = target)
  ///
  /// If already subscribed, this is a no-op.
  void subscribeToFamily(String familyId) {
    if (_familyChannels.containsKey(familyId)) return;

    final client = _ref.read(supabaseProvider);
    if (client == null) return;

    if (!_isInitialized) initialize();

    final channelName = 'family_$familyId';

    final channel = client.channel(channelName);

    // ── Listen for Person changes ───────────────────────────────
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'Person',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'familyId',
        value: familyId,
      ),
      callback: (payload) => _handlePersonChange(payload, familyId),
    );

    // ── Listen for Relationship changes ─────────────────────────
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'Relationship',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'familyId',
        value: familyId,
      ),
      callback: (payload) =>
          _handleRelationshipChange(payload, familyId),
    );

    // ── Listen for Family changes ───────────────────────────────
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'Family',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: familyId,
      ),
      callback: (payload) => _handleFamilyChange(payload, familyId),
    );

    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint(
            '[SupabaseRealtime] Subscribed to family: $familyId');
      } else if (status == RealtimeSubscribeStatus.channelError) {
        debugPrint(
            '[SupabaseRealtime] Channel error for family $familyId: $error');
        // Auto-reconnect: remove the old channel entry so
        // subscribeToFamily can be called again
        _familyChannels.remove(familyId);
        // Retry after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          subscribeToFamily(familyId);
        });
      }
    });

    _familyChannels[familyId] = channel;
  }

  /// Unsubscribe from realtime changes for a specific family.
  void unsubscribeFromFamily(String familyId) {
    final channel = _familyChannels.remove(familyId);
    if (channel == null) return;

    final client = _ref.read(supabaseProvider);
    if (client != null) {
      try {
        client.removeChannel(channel);
      } catch (_) {}
    }
    debugPrint(
        '[SupabaseRealtime] Unsubscribed from family: $familyId');
  }

  /// Subscribe to all families the user is a member of.
  /// Call this after authentication and family list fetch.
  Future<void> subscribeToAllUserFamilies() async {
    if (!_isInitialized) initialize();

    final client = _ref.read(supabaseProvider);
    if (client == null) return;

    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    // Also subscribe to family-level changes (new families, deletions)
    _subscribeToFamilyListChanges(client, userId);

    // Subscribe to each existing family
    try {
      final familiesAsync = _ref.read(familyListProvider);
      final families = familiesAsync.valueOrNull ?? [];
      for (final family in families) {
        subscribeToFamily(family.id);
      }
    } catch (e) {
      debugPrint(
          '[SupabaseRealtime] Error subscribing to user families: $e');
    }
  }

  // ── Family List Subscription ────────────────────────────────────

  void _subscribeToFamilyListChanges(
      SupabaseClient client, String userId) {
    // Listen for new FamilyMember entries (user joins a family)
    // and Family changes (family updated/deleted)
    final channel = client.channel('user_families_$userId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'FamilyMember',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'userId',
        value: userId,
      ),
      callback: (payload) {
        debugPrint(
            '[SupabaseRealtime] New family membership detected');
        _scheduleListInvalidation();
        // Also subscribe to the new family's changes
        final newFamilyId =
            payload.newRecord['familyId']?.toString();
        if (newFamilyId != null) {
          subscribeToFamily(newFamilyId);
        }
      },
    );

    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint(
            '[SupabaseRealtime] Subscribed to family list changes');
      }
    });

    // Store this as a special channel (not per-family)
    _familyChannels['_user_families'] = channel;
  }

  // ── Change Handlers ──────────────────────────────────────────────

  void _handlePersonChange(
      PostgresChangePayload payload, String familyId) {
    final record = payload.newRecord;
    final oldRecord = payload.oldRecord;

    // Echo detection: skip if this change was caused by our own write
    final eventId =
        '${payload.table}_${record['id'] ?? oldRecord['id']}_${DateTime.now().millisecondsSinceEpoch}';
    if (_dedup.isDuplicate(eventId)) return;

    // Additional echo check: if updatedBy matches current user, skip
    final updatedBy = record['updatedBy']?.toString();
    if (updatedBy != null && updatedBy == _currentUserId) return;

    final eventType = payload.eventType;
    final personId =
        record['id']?.toString() ?? oldRecord['id']?.toString();

    if (personId == null) return;

    debugPrint(
        '[SupabaseRealtime] Person $eventType: $personId in family $familyId');

    // Update Drift cache
    _updatePersonInDrift(eventType, record, personId, familyId);

    // Schedule provider invalidation
    _scheduleFamilyInvalidation(familyId);
  }

  void _handleRelationshipChange(
      PostgresChangePayload payload, String familyId) {
    final record = payload.newRecord;
    final oldRecord = payload.oldRecord;

    final eventId =
        '${payload.table}_${record['id'] ?? oldRecord['id']}_${DateTime.now().millisecondsSinceEpoch}';
    if (_dedup.isDuplicate(eventId)) return;

    final updatedBy = record['updatedBy']?.toString();
    if (updatedBy != null && updatedBy == _currentUserId) return;

    final eventType = payload.eventType;
    final relId =
        record['id']?.toString() ?? oldRecord['id']?.toString();

    if (relId == null) return;

    debugPrint(
        '[SupabaseRealtime] Relationship $eventType: $relId in family $familyId');

    _updateRelationshipInDrift(eventType, record, relId, familyId);
    _scheduleFamilyInvalidation(familyId);
  }

  void _handleFamilyChange(
      PostgresChangePayload payload, String familyId) {
    final record = payload.newRecord;

    final eventId =
        '${payload.table}_${record['id']}_${DateTime.now().millisecondsSinceEpoch}';
    if (_dedup.isDuplicate(eventId)) return;

    final updatedBy = record['updatedBy']?.toString();
    if (updatedBy != null && updatedBy == _currentUserId) return;

    debugPrint(
        '[SupabaseRealtime] Family UPDATE: $familyId');

    _updateFamilyInDrift(record, familyId);
    _scheduleFamilyInvalidation(familyId);
    _scheduleListInvalidation();
  }

  // ── Drift Cache Updates ──────────────────────────────────────────

  void _updatePersonInDrift(PostgresChangeEvent eventType,
      Map<String, dynamic> record, String personId, String familyId) {
    if (!IsarDatabase.isInitialized) return;

    final db = IsarDatabase.instance;

    switch (eventType) {
      case PostgresChangeEvent.delete:
        try {
          db.deletePerson(personId);
        } catch (_) {}
        break;
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
      case PostgresChangeEvent.all:
        try {
          // Filter out soft-deleted persons from the stream
          if (record['deletedAt'] != null) {
            db.deletePerson(personId);
          } else {
            db.upsertPerson(CachedPersonsCompanion(
              id: Value(personId),
              familyId: Value(familyId),
              name: Value(record['name']?.toString() ?? 'Unknown'),
              data: Value(json.encode(record)),
              cachedAt: Value(DateTime.now()),
            ));
          }
        } catch (e) {
          debugPrint(
              '[SupabaseRealtime] Error upserting person: $e');
        }
        break;
    }
  }

  void _updateRelationshipInDrift(PostgresChangeEvent eventType,
      Map<String, dynamic> record, String relId, String familyId) {
    if (!IsarDatabase.isInitialized) return;

    final db = IsarDatabase.instance;

    switch (eventType) {
      case PostgresChangeEvent.delete:
        try {
          db.deleteRelationship(relId);
        } catch (_) {}
        break;
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
      case PostgresChangeEvent.all:
        try {
          // If isActive is false, remove from cache
          if (record['isActive'] == false) {
            db.deleteRelationship(relId);
          } else {
            final fromId = record['fromPersonId']?.toString() ?? '';
            final toId = record['toPersonId']?.toString() ?? '';
            final relType =
                record['relationshipKey']?.toString() ?? '';
            db.upsertRelationship(CachedRelationshipsCompanion(
              id: Value(relId),
              familyId: Value(familyId),
              fromId: Value(fromId),
              toId: Value(toId),
              relationshipType: Value(relType),
              data: Value(json.encode(record)),
              cachedAt: Value(DateTime.now()),
            ));
          }
        } catch (e) {
          debugPrint(
              '[SupabaseRealtime] Error upserting relationship: $e');
        }
        break;
    }
  }

  void _updateFamilyInDrift(
      Map<String, dynamic> record, String familyId) {
    if (!IsarDatabase.isInitialized) return;

    final db = IsarDatabase.instance;

    try {
      // If family is soft-deleted, remove from cache
      if (record['deletedAt'] != null) {
        db.deleteFamily(familyId);
      } else {
        db.upsertFamily(CachedFamiliesCompanion(
          id: Value(familyId),
          name: Value(record['name']?.toString() ?? ''),
          data: Value(json.encode(record)),
          kinFamilyId: Value(record['kinFamilyId']?.toString()),
          username: Value(record['username']?.toString()),
          cachedAt: Value(DateTime.now()),
        ));
      }
    } catch (e) {
      debugPrint(
          '[SupabaseRealtime] Error upserting family: $e');
    }
  }

  // ── Debounced Provider Invalidation ──────────────────────────────

  /// Schedule a debounced invalidation for a specific family's providers.
  /// Batches multiple rapid changes into a single invalidation.
  void _scheduleFamilyInvalidation(String familyId) {
    _pendingFamilyInvalidations.add(familyId);

    _invalidationTimers['family_batch'] ??= Timer(
      const Duration(milliseconds: 500),
      () {
        _invalidationTimers.remove('family_batch');

        for (final fid in _pendingFamilyInvalidations) {
          try {
            _ref.invalidate(familyMembersProvider(fid));
            _ref.invalidate(familyRelationshipsProvider(fid));
            _ref.invalidate(familyDetailProvider(fid));
          } catch (_) {}
        }
        _pendingFamilyInvalidations.clear();
      },
    );
  }

  /// Schedule a debounced invalidation for the family list provider.
  void _scheduleListInvalidation() {
    if (_pendingListInvalidation) return;
    _pendingListInvalidation = true;

    _invalidationTimers['list_batch'] ??= Timer(
      const Duration(milliseconds: 500),
      () {
        _invalidationTimers.remove('list_batch');
        _pendingListInvalidation = false;

        try {
          _ref.invalidate(familyListProvider);
          _ref.invalidate(archivedFamiliesProvider);
        } catch (_) {}
      },
    );
  }

  // ── Status ───────────────────────────────────────────────────────

  /// Get the number of active family subscriptions.
  int get activeSubscriptionCount =>
      _familyChannels.length -
      (_familyChannels.containsKey('_user_families') ? 1 : 0);

  /// Check if subscribed to a specific family.
  bool isSubscribedToFamily(String familyId) =>
      _familyChannels.containsKey(familyId);
}

// ════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ════════════════════════════════════════════════════════════════════

/// Provider for the Supabase Realtime service singleton.
/// Auto-disposes when no longer watched.
final supabaseRealtimeProvider =
    Provider<SupabaseRealtimeService>((ref) {
  final service = SupabaseRealtimeService(ref);

  // Auto-cleanup when provider is disposed
  ref.onDispose(() => service.dispose());

  return service;
});

/// Provider that tracks which families have active realtime subscriptions.
/// UI screens can watch this to know if they're receiving live updates.
final realtimeSubscriptionsProvider =
    StateProvider<Set<String>>((ref) => {});

/// Convenience provider that subscribes to all user families
/// when Supabase is ready and auto-disposes on sign-out.
final autoRealtimeSubscriptionProvider = Provider<void>((ref) {
  final isReady = ref.watch(isSupabaseReadyProvider);
  if (!isReady) return;

  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  if (!isAuthenticated) return;

  // Subscribe to all families when authenticated
  Future.microtask(() async {
    try {
      await ref
          .read(supabaseRealtimeProvider)
          .subscribeToAllUserFamilies();
    } catch (e) {
      debugPrint(
          '[SupabaseRealtime] Auto-subscribe error: $e');
    }
  });
});
