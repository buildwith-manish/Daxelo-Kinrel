import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../isar_database.dart';
import '../collections/api_cache_entry.dart';
import 'connectivity_service.dart';
import 'offline_queue.dart';

/// Background sync service that:
/// 1. Processes pending offline operations when connectivity is restored
/// 2. Cleans up expired cache entries
/// 3. Runs periodic sync cycles
class SyncService {
  SyncService(this._ref);

  final Ref _ref;

  Timer? _periodicSyncTimer;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isSyncing = false;

  /// Start the sync service.
  /// - Listens for connectivity changes to trigger sync
  /// - Sets up periodic sync (every 5 minutes when online)
  void start() {
    if (!IsarDatabase.isInitialized) return;

    debugPrint('🔄 Starting SyncService...');

    // Listen for connectivity changes
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _ref
        .read(connectivityServiceProvider)
        .onConnectivityChanged
        .listen((isOnline) {
      if (isOnline) {
        _onConnectivityRestored();
      }
    });

    // Set up periodic sync (every 5 minutes)
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _syncCycle(),
    );

    // Do an initial sync if we're online
    final connectivity = _ref.read(connectivityServiceProvider);
    if (connectivity.isOnline) {
      _syncCycle();
    }
  }

  /// Stop the sync service.
  void stop() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    debugPrint('🔄 SyncService stopped');
  }

  /// Called when connectivity is restored.
  /// Triggers immediate sync of pending operations.
  Future<void> _onConnectivityRestored() async {
    debugPrint('🟢 Connectivity restored — triggering sync');
    await _syncCycle();
  }

  /// Run a full sync cycle:
  /// 1. Process pending offline operations
  /// 2. Clean up expired cache entries
  Future<void> _syncCycle() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      // Only sync if we're online
      final connectivity = _ref.read(connectivityServiceProvider);
      final isOnline = await connectivity.checkNow();
      if (!isOnline) return;

      // 1. Process pending operations
      final queueManager = _ref.read(offlineQueueProvider);
      await queueManager.processPendingOperations();

      // 2. Clean up expired API cache entries
      await _cleanupExpiredCache();
    } catch (e) {
      debugPrint('⚠️ Sync cycle error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Remove expired API cache entries.
  Future<void> _cleanupExpiredCache() async {
    if (!IsarDatabase.isInitialized) return;

    final isar = IsarDatabase.instance;
    final expiredIds = <Id>[];

    // Get all entry IDs and check freshness
    final allIds = isar.apiCacheEntrys.where().findAllSync();
    for (final entry in allIds) {
      if (!entry.isFresh) {
        expiredIds.add(entry.isarId);
      }
    }

    if (expiredIds.isNotEmpty) {
      await isar.writeTxn(() async {
        for (final id in expiredIds) {
          await isar.apiCacheEntrys.delete(id);
        }
      });
      debugPrint('🗑️ Cleaned up ${expiredIds.length} expired cache entries');
    }
  }

  /// Force an immediate sync (e.g., user pulled to refresh).
  Future<void> forceSync() async {
    await _syncCycle();
  }

  /// Dispose resources.
  void dispose() {
    stop();
  }
}

/// Riverpod provider for the SyncService.
final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
