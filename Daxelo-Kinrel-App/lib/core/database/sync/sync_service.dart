import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../isar_database.dart';
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

    final db = IsarDatabase.instance;
    final allEntries = await db.getAllApiCacheEntries();
    int removedCount = 0;

    for (final entry in allEntries) {
      final cachedTime = DateTime.tryParse(entry.cachedAt.toIso8601String());
      if (cachedTime == null) {
        await db.deleteApiCacheEntry(entry.id);
        removedCount++;
        continue;
      }
      final expiresAt = cachedTime.add(Duration(seconds: entry.ttlSeconds));
      if (DateTime.now().isAfter(expiresAt)) {
        await db.deleteApiCacheEntry(entry.id);
        removedCount++;
      }
    }

    if (removedCount > 0) {
      debugPrint('🗑️ Cleaned up $removedCount expired cache entries');
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
