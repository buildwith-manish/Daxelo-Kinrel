// lib/core/network/realtime_subscription.dart
//
// DAXELO KINREL — Supabase Realtime Subscription Service
//
// Manages per-family Supabase Realtime channels that listen to Postgres
// Changes on Person, Relationship, and Family tables. Provides:
//   1. Per-family channels with Postgres Change listeners
//   2. Echo skipping via RealtimeDedup (own mutations are filtered out)
//   3. Auto-reconnect on auth state changes (token refresh / sign-in)
//   4. Debounced Drift cache + Riverpod provider invalidation

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/isar_database.dart';
import '../database/sync/cache_invalidation.dart';
import '../family/family_provider.dart';
import '../services/supabase_service.dart';
import 'realtime_dedup.dart';

// ── Realtime Subscription Service ─────────────────────────────────

/// Manages Supabase Realtime subscriptions for per-family Postgres Changes.
///
/// For each family the user is a member of, creates a dedicated channel
/// (`family:<familyId>`) that listens to INSERT/UPDATE/DELETE on Person,
/// Relationship, and Family tables.
///
/// On receiving a valid (non-echo) event:
/// - Invalidates the relevant Drift cache via [CacheInvalidation]
/// - Invalidates the relevant Riverpod providers (familyMembersProvider,
///   familyRelationshipsProvider, familyListProvider, familyDetailProvider)
///
/// Uses a 200ms debounced invalidation to prevent rapid Realtime events
/// from causing ANR due to cascading provider rebuilds.
class RealtimeSubscriptionService {
  RealtimeSubscriptionService(this._ref);

  final Ref _ref;

  /// Active family channels, keyed by familyId.
  final Map<String, RealtimeChannel> _channels = {};

  /// Deduplication helper to skip echo events (own mutations).
  final RealtimeDedup _dedup = RealtimeDedup();

  /// Auth state change subscription for auto-reconnect.
  StreamSubscription<AuthState>? _authSubscription;

  /// Debounce timer for batched invalidation.
  Timer? _invalidationDebounce;

  /// Pending invalidation keys (`table:familyId`) to flush on next debounce.
  final Set<String> _pendingInvalidations = {};

  // ── Public API ──────────────────────────────────────────────────

  /// Subscribe to Realtime events for a specific family.
  ///
  /// Creates a channel (`family:<familyId>`) with Postgres Change listeners
  /// for Person (INSERT/UPDATE/DELETE), Relationship (INSERT/UPDATE/DELETE),
  /// and Family (UPDATE only) tables, all filtered by [familyId].
  ///
  /// If a channel for this family already exists, this is a no-op.
  void subscribeFamily(String familyId) {
    if (_channels.containsKey(familyId)) return;

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        debugPrint('[RealtimeSub] Cannot subscribe — Supabase client is null');
        return;
      }

      final channel = client.realtime.channel('family:$familyId');

      // ── Person: INSERT ──────────────────────────────────────────
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'Person',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'familyId',
          value: familyId,
        ),
        callback: (payload) => _handlePostgresChange(
          'Person',
          'INSERT',
          familyId,
          payload,
        ),
      );

      // ── Person: UPDATE ──────────────────────────────────────────
      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'Person',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'familyId',
          value: familyId,
        ),
        callback: (payload) => _handlePostgresChange(
          'Person',
          'UPDATE',
          familyId,
          payload,
        ),
      );

      // ── Person: DELETE ──────────────────────────────────────────
      channel.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'Person',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'familyId',
          value: familyId,
        ),
        callback: (payload) => _handlePostgresChange(
          'Person',
          'DELETE',
          familyId,
          payload,
        ),
      );

      // ── Relationship: INSERT ────────────────────────────────────
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'Relationship',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'familyId',
          value: familyId,
        ),
        callback: (payload) => _handlePostgresChange(
          'Relationship',
          'INSERT',
          familyId,
          payload,
        ),
      );

      // ── Relationship: UPDATE ────────────────────────────────────
      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'Relationship',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'familyId',
          value: familyId,
        ),
        callback: (payload) => _handlePostgresChange(
          'Relationship',
          'UPDATE',
          familyId,
          payload,
        ),
      );

      // ── Relationship: DELETE ────────────────────────────────────
      channel.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'Relationship',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'familyId',
          value: familyId,
        ),
        callback: (payload) => _handlePostgresChange(
          'Relationship',
          'DELETE',
          familyId,
          payload,
        ),
      );

      // ── Family: UPDATE only, filtered by id ─────────────────────
      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'Family',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: familyId,
        ),
        callback: (payload) => _handlePostgresChange(
          'Family',
          'UPDATE',
          familyId,
          payload,
        ),
      );

      // Subscribe to the channel with status callback
      channel.subscribe((String event, dynamic? error) {
        if (event == 'SUBSCRIBED') {
          debugPrint('[RealtimeSub] ✅ Subscribed to family:$familyId');
        } else if (event == 'CHANNEL_ERROR') {
          debugPrint(
            '[RealtimeSub] ❌ Channel error for family:$familyId: $error',
          );
        } else if (event == 'TIMED_OUT') {
          debugPrint('[RealtimeSub] ⏰ Channel timed out for family:$familyId');
        }
      });

      _channels[familyId] = channel;
    } catch (e) {
      debugPrint('[RealtimeSub] Error subscribing to family:$familyId: $e');
    }
  }

  /// Unsubscribe from Realtime events for a specific family.
  ///
  /// Removes the channel and cancels all Postgres Change listeners
  /// for the given [familyId].
  void unsubscribeFamily(String familyId) {
    final channel = _channels.remove(familyId);
    if (channel != null) {
      try {
        channel.unsubscribe();
        debugPrint('[RealtimeSub] Unsubscribed from family:$familyId');
      } catch (e) {
        debugPrint(
          '[RealtimeSub] Error unsubscribing from family:$familyId: $e',
        );
      }
    }
  }

  /// Subscribe to all families the current user is a member of.
  ///
  /// Reads family IDs from [familyListProvider] and creates a channel
  /// for each. Also sets up the auth state listener for auto-reconnect.
  void subscribeAllFamilies() {
    try {
      final familiesAsync = _ref.read(familyListProvider);
      final families = familiesAsync.valueOrNull;
      if (families == null) {
        debugPrint('[RealtimeSub] Family list not yet loaded');
        return;
      }

      for (final family in families) {
        subscribeFamily(family.id);
      }

      debugPrint(
        '[RealtimeSub] Subscribed to ${families.length} families',
      );

      // Set up auth state listener for auto-reconnect
      _setupAuthListener();
    } catch (e) {
      debugPrint('[RealtimeSub] Error subscribing to all families: $e');
    }
  }

  /// Dispose all subscriptions and resources.
  ///
  /// Cancels auth listener, debounce timer, and unsubscribes all channels.
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;

    _invalidationDebounce?.cancel();
    _pendingInvalidations.clear();

    for (final entry in _channels.entries) {
      try {
        entry.value.unsubscribe();
      } catch (e) {
        debugPrint(
          '[RealtimeSub] Error unsubscribing channel ${entry.key}: $e',
        );
      }
    }
    _channels.clear();
    _dedup.clear();

    debugPrint('[RealtimeSub] Disposed all subscriptions');
  }

  // ── Private: Event Handling ──────────────────────────────────────

  /// Handle a Postgres Change event from Supabase Realtime.
  ///
  /// 1. Extract the record ID from the payload.
  /// 2. Check dedup — if this event was caused by our own mutation
  ///    (or is a duplicate), skip it.
  /// 3. Schedule a debounced cache invalidation for the affected table
  ///    and family.
  void _handlePostgresChange(
    String table,
    String eventType,
    String familyId,
    PostgresChangePayload payload,
  ) {
    try {
      // Extract record ID from the payload.
      // For INSERT/UPDATE, the new record has the ID.
      // For DELETE, only the old record is available.
      final recordId = payload.newRecord['id']?.toString() ??
          payload.oldRecord['id']?.toString() ??
          '';

      if (recordId.isEmpty) {
        debugPrint('[RealtimeSub] Skipping event with empty record ID');
        return;
      }

      // Build dedup key: `table:recordId:eventType`
      final dedupKey = '$table:$recordId:$eventType';

      // Check dedup — skip if this was our own mutation or a duplicate.
      // isDuplicate() returns true if the key was already seen, false if
      // new (and it adds the key to the dedup set).
      if (_dedup.isDuplicate(dedupKey)) {
        debugPrint('[RealtimeSub] Skipping echo/duplicate: $dedupKey');
        return;
      }

      debugPrint(
        '[RealtimeSub] Processing $dedupKey for family:$familyId',
      );

      // Schedule debounced invalidation
      _scheduleInvalidation(table, familyId);
    } catch (e) {
      debugPrint('[RealtimeSub] Error handling Postgres change: $e');
    }
  }

  // ── Private: Invalidation ────────────────────────────────────────

  /// Schedule a debounced cache invalidation for the given table and family.
  ///
  /// Events are batched with a 200ms debounce to prevent rapid Realtime
  /// events from causing ANR due to cascading provider rebuilds.
  void _scheduleInvalidation(String table, String familyId) {
    _pendingInvalidations.add('$table:$familyId');
    _invalidationDebounce?.cancel();
    _invalidationDebounce = Timer(const Duration(milliseconds: 200), () {
      _flushInvalidations();
    });
  }

  /// Flush all pending invalidations.
  ///
  /// For each pending key:
  /// - Invalidates Drift cache first via [CacheInvalidation.invalidateFamily]
  /// - Then invalidates the relevant Riverpod providers based on table type
  void _flushInvalidations() {
    if (_pendingInvalidations.isEmpty) return;

    try {
      final invalidatedFamilyIds = <String>{};

      for (final key in _pendingInvalidations) {
        final colonIndex = key.indexOf(':');
        if (colonIndex == -1) continue;

        final table = key.substring(0, colonIndex);
        final familyId = key.substring(colonIndex + 1);
        invalidatedFamilyIds.add(familyId);
      }

      // 1. Invalidate Drift cache FIRST so that when Riverpod providers
      //    re-evaluate, they don't read stale data from Drift before
      //    the Supabase fetch returns fresh data.
      if (IsarDatabase.isInitialized) {
        for (final familyId in invalidatedFamilyIds) {
          CacheInvalidation.invalidateFamily(familyId).catchError((_) {});
        }
      }

      // 2. Then invalidate Riverpod providers to trigger Supabase re-fetch
      for (final key in _pendingInvalidations) {
        final colonIndex = key.indexOf(':');
        if (colonIndex == -1) continue;

        final table = key.substring(0, colonIndex);
        final familyId = key.substring(colonIndex + 1);

        switch (table) {
          case 'Person':
            _ref.invalidate(familyMembersProvider(familyId));
            break;
          case 'Relationship':
            _ref.invalidate(familyRelationshipsProvider(familyId));
            break;
          case 'Family':
            _ref.invalidate(familyListProvider);
            _ref.invalidate(familyDetailProvider(familyId));
            break;
        }
      }

      _pendingInvalidations.clear();
    } catch (e) {
      debugPrint('[RealtimeSub] Error flushing invalidations: $e');
    }
  }

  // ── Private: Auto-Reconnect ──────────────────────────────────────

  /// Set up auth state listener for auto-reconnect.
  ///
  /// On token refresh or sign-in, re-subscribes all channels so they
  /// use the fresh JWT. On sign-out, unsubscribes all channels.
  void _setupAuthListener() {
    if (_authSubscription != null) return; // already listening

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) return;

      _authSubscription = client.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.tokenRefreshed ||
            state.event == AuthChangeEvent.signedIn) {
          _resubscribeAllChannels();
        } else if (state.event == AuthChangeEvent.signedOut) {
          _unsubscribeAllChannels();
        }
      });
    } catch (e) {
      debugPrint('[RealtimeSub] Error setting up auth listener: $e');
    }
  }

  /// Re-subscribe all channels after auth state change.
  ///
  /// Preserves the list of family IDs that were previously subscribed,
  /// then unsubscribes all existing channels and creates fresh ones
  /// with the new auth token.
  void _resubscribeAllChannels() {
    final familyIds = _channels.keys.toList();

    // Unsubscribe existing channels
    _unsubscribeAllChannels();

    // Re-subscribe with fresh connection
    for (final familyId in familyIds) {
      subscribeFamily(familyId);
    }

    if (familyIds.isNotEmpty) {
      debugPrint(
        '[RealtimeSub] Re-subscribed ${familyIds.length} channels',
      );
    }
  }

  /// Unsubscribe all channels without clearing the tracked family IDs.
  void _unsubscribeAllChannels() {
    for (final entry in _channels.entries) {
      try {
        entry.value.unsubscribe();
      } catch (e) {
        debugPrint(
          '[RealtimeSub] Error unsubscribing channel ${entry.key}: $e',
        );
      }
    }
    _channels.clear();
  }
}

// ── Riverpod Provider ─────────────────────────────────────────────

/// Riverpod provider for the [RealtimeSubscriptionService] singleton.
/// Manages its own lifecycle via `ref.onDispose`.
final realtimeSubscriptionProvider =
    Provider<RealtimeSubscriptionService>((ref) {
  final service = RealtimeSubscriptionService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
