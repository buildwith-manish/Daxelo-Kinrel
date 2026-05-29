// lib/core/database/sync/background_sync_manager.dart
//
// DAXELO KINREL — Background Sync Manager
//
// Manages background sync when the app is in background or resumed.
// Coordinates with SyncEngine and ConnectivityService to trigger sync
// at appropriate times:
//   - When app resumes from background
//   - When connectivity is restored
//   - Periodically (every 5 minutes when app is active)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_engine.dart';
import 'connectivity_service.dart';
import '../../services/supabase_service.dart';

class BackgroundSyncManager {
  BackgroundSyncManager(this._ref);

  final Ref _ref;

  Timer? _periodicSyncTimer;
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<SyncEvent>? _syncEventSubscription;
  bool _isDisposed = false;

  // ── Lifecycle ────────────────────────────────────────────────────

  /// Initialize the background sync manager.
  /// Sets up connectivity listener and periodic sync timer.
  /// Does NOT perform an initial sync — call [start] for that.
  void init() {
    if (_isDisposed) return;

    // Listen for connectivity changes
    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        _ref.read(connectivityServiceProvider).onConnectivityChanged.listen(
      (isOnline) {
        if (isOnline) {
          onConnectivityRestored();
        }
      },
    );

    // Set up periodic sync (every 5 minutes)
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => onPeriodicSync(),
    );

    debugPrint('🔄 BackgroundSyncManager initialized');
  }

  /// Start the sync engine and perform an initial sync if online.
  Future<void> start() async {
    if (_isDisposed) return;

    final engine = _ref.read(syncEngineProvider);
    await engine.start();

    // Listen for sync events for UI updates / logging
    _syncEventSubscription?.cancel();
    _syncEventSubscription = engine.syncEvents.listen((event) {
      _handleSyncEvent(event);
    });

    debugPrint('🔄 BackgroundSyncManager started');
  }

  /// Stop the background sync manager.
  /// Cancels timers and subscriptions but does NOT dispose SyncEngine.
  void stop() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _syncEventSubscription?.cancel();
    _syncEventSubscription = null;

    final engine = _ref.read(syncEngineProvider);
    engine.stop();

    debugPrint('🔄 BackgroundSyncManager stopped');
  }

  /// Dispose the background sync manager permanently.
  void dispose() {
    _isDisposed = true;
    stop();
    debugPrint('🔄 BackgroundSyncManager disposed');
  }

  // ── Sync Triggers ────────────────────────────────────────────────

  /// Called when app resumes from background.
  /// Performs a delta sync if the user is authenticated and online.
  Future<void> onAppResumed() async {
    if (_isDisposed) return;

    final connectivity = _ref.read(connectivityServiceProvider);
    if (!connectivity.isOnline) {
      debugPrint('🔄 App resumed but offline — skipping sync');
      return;
    }

    final userId = _currentUserId;
    if (userId == null) {
      debugPrint('🔄 App resumed but not authenticated — skipping sync');
      return;
    }

    debugPrint('🔄 App resumed — triggering delta sync');

    try {
      final engine = _ref.read(syncEngineProvider);
      await engine.deltaSync(userId);
    } catch (e) {
      debugPrint('⚠️ App resume sync failed: $e');
    }
  }

  /// Called when connectivity is restored.
  /// Performs a full sync to catch up on any changes made while offline.
  Future<void> onConnectivityRestored() async {
    if (_isDisposed) return;

    final userId = _currentUserId;
    if (userId == null) {
      debugPrint('🔄 Connectivity restored but not authenticated — pushing pending only');
      try {
        final engine = _ref.read(syncEngineProvider);
        await engine.pushPendingOperations();
      } catch (e) {
        debugPrint('⚠️ Connectivity restored push failed: $e');
      }
      return;
    }

    debugPrint('🔄 Connectivity restored — triggering full sync');

    try {
      final engine = _ref.read(syncEngineProvider);
      await engine.fullSync(userId);
    } catch (e) {
      debugPrint('⚠️ Connectivity restored sync failed: $e');
    }
  }

  /// Called periodically (every 5 minutes when app is active).
  /// Performs a lightweight delta sync.
  Future<void> onPeriodicSync() async {
    if (_isDisposed) return;

    final connectivity = _ref.read(connectivityServiceProvider);
    if (!connectivity.isOnline) return;

    final userId = _currentUserId;
    if (userId == null) return;

    final engine = _ref.read(syncEngineProvider);
    // Skip if already syncing
    if (engine.status.isSyncing) return;

    debugPrint('🔄 Periodic sync — triggering delta sync');

    try {
      await engine.deltaSync(userId);
    } catch (e) {
      debugPrint('⚠️ Periodic sync failed: $e');
    }
  }

  /// Force an immediate full sync (e.g., user pulled to refresh).
  Future<void> forceSync() async {
    if (_isDisposed) return;

    final userId = _currentUserId;
    if (userId == null) return;

    try {
      final engine = _ref.read(syncEngineProvider);
      await engine.fullSync(userId);
    } catch (e) {
      debugPrint('⚠️ Force sync failed: $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  /// Get the current user ID from Supabase auth.
  String? get _currentUserId {
    try {
      final client = _ref.read(supabaseProvider);
      return client?.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Handle sync events for logging and potential UI updates.
  void _handleSyncEvent(SyncEvent event) {
    switch (event.type) {
      case SyncEventType.started:
        debugPrint('🔄 Sync started: ${event.message}');
        break;
      case SyncEventType.pulling:
        debugPrint('🔄 Pulling: ${event.message} (${(event.progress ?? 0) * 100}%)');
        break;
      case SyncEventType.pushing:
        debugPrint('🔄 Pushing: ${event.message} (${(event.progress ?? 0) * 100}%)');
        break;
      case SyncEventType.conflict:
        debugPrint('⚠️ Conflict: ${event.message}');
        break;
      case SyncEventType.completed:
        debugPrint('✅ Sync completed: ${event.message}');
        break;
      case SyncEventType.error:
        debugPrint('❌ Sync error: ${event.message}');
        break;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the BackgroundSyncManager singleton.
final backgroundSyncManagerProvider = Provider<BackgroundSyncManager>((ref) {
  final manager = BackgroundSyncManager(ref);
  ref.onDispose(() => manager.dispose());
  return manager;
});
