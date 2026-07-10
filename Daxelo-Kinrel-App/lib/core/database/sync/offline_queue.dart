import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../isar_database.dart';
import '../app_database.dart';
import '../sync/connectivity_service.dart';
import '../../services/supabase_service.dart';

/// Maximum number of retry attempts before giving up on a pending operation.
const int _maxRetries = 5;

/// Manages offline write operations that need to be synced when online.
/// Stores failed write operations in Drift and retries them when
/// connectivity is restored.
///
/// WEB: On Flutter Web, Drift is unavailable (sqlite3.wasm + drift_worker.js
/// are not set up). All methods early-return as no-ops on web. The
/// `IsarDatabase.isInitialized` guard prevents the "IsarDatabase not
/// initialized" error that was previously logged on every web launch.
class OfflineQueueManager {
  final Ref _ref;

  OfflineQueueManager(this._ref);

  /// Get the Drift database, or null on web/uninitialized.
  /// Always use this getter — never call `_ref.read(isarProvider)` directly.
  AppDatabase? get _db {
    if (!IsarDatabase.isInitialized) return null;
    try {
      return _ref.read(isarProvider);
    } catch (_) {
      return null;
    }
  }

  ConnectivityService get _connectivity => _ref.read(connectivityServiceProvider);
  bool get _isOnline => _connectivity.isOnline;

  /// Enqueue a write operation for later sync.
  /// Use this when a network write fails due to being offline.
  /// No-op on web (Drift is unavailable).
  Future<void> enqueue({
    required String operationType,
    required String collection,
    String? recordId,
    Map<String, dynamic>? payload,
    int priority = 1,
  }) async {
    final db = _db;
    if (db == null) {
      // Web / not initialized — operations are lost (web is online-only).
      return;
    }
    await db.upsertPendingOperation(PendingOperationsCompanion(
      operationType: Value(operationType),
      collection: Value(collection),
      recordId: Value(recordId),
      payload: Value(payload != null ? jsonEncode(payload) : null),
      createdAt: Value(DateTime.now()),
      retryCount: const Value(0),
      lastRetryAt: const Value.absent(),
      priority: Value(priority),
      isProcessing: const Value(false),
    ));

    debugPrint(
      '📥 Queued offline operation: $operationType on $collection'
      '${recordId != null ? ' ($recordId)' : ''}',
    );
  }

  /// Process all pending operations in priority order.
  /// Called when connectivity is restored or periodically.
  /// Returns 0 on web (no Drift database).
  Future<int> processPendingOperations() async {
    if (!_isOnline) return 0;

    final db = _db;
    if (db == null) return 0;

    // Get all non-processing operations, sorted by priority then creation time
    final pending = await db.getPendingOperations();

    if (pending.isEmpty) return 0;

    debugPrint('🔄 Processing ${pending.length} pending operations...');

    int successCount = 0;
    int failCount = 0;

    for (final op in pending) {
      // Mark as processing
      await db.upsertPendingOperation(PendingOperationsCompanion(
        id: Value(op.id),
        operationType: Value(op.operationType),
        collection: Value(op.collection),
        recordId: Value(op.recordId),
        payload: Value(op.payload),
        createdAt: Value(op.createdAt),
        retryCount: Value(op.retryCount),
        lastRetryAt: Value(op.lastRetryAt),
        priority: Value(op.priority),
        isProcessing: const Value(true),
      ));

      try {
        await _executeOperation(op);

        // Success — remove from queue
        await db.deletePendingOperation(op.id);

        successCount++;
        debugPrint('✅ Synced: ${op.operationType} on ${op.collection}');
      } catch (e) {
        // Failed — increment retry count and mark as not processing
        await db.upsertPendingOperation(PendingOperationsCompanion(
          id: Value(op.id),
          operationType: Value(op.operationType),
          collection: Value(op.collection),
          recordId: Value(op.recordId),
          payload: Value(op.payload),
          createdAt: Value(op.createdAt),
          retryCount: Value(op.retryCount + 1),
          lastRetryAt: Value(DateTime.now()),
          priority: Value(op.priority),
          isProcessing: const Value(false),
        ));

        failCount++;
        debugPrint(
          '⚠️ Failed to sync: ${op.operationType} on ${op.collection}'
          ' (retry ${op.retryCount + 1}/$_maxRetries): $e',
        );

        // If we get a network error, stop processing (we're probably offline again)
        final errStr = e.toString();
        if (_isNetworkError(errStr)) {
          debugPrint('🔴 Network error during sync, stopping batch');
          break;
        }
      }
    }

    debugPrint(
      '🔄 Sync complete: $successCount succeeded, $failCount failed',
    );

    // Clean up old expired operations (max retries exceeded)
    await _cleanExpiredOperations();

    return successCount;
  }

  /// Execute a single pending operation against Supabase.
  Future<void> _executeOperation(PendingOperation op) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) throw Exception('Supabase not available');

    final payload = op.payload != null
        ? jsonDecode(op.payload!) as Map<String, dynamic>
        : <String, dynamic>{};

    // Add updatedAt timestamp for mutations
    if (op.operationType != 'delete') {
      payload['updatedAt'] = DateTime.now().toIso8601String();
    }

    // Sanitize Person payload — remove fields not in Person table schema
    if (op.collection == 'Person') {
      payload.remove('relationshipType');
    }

    switch (op.operationType) {
      case 'create':
        await client.from(op.collection).insert(payload).select().maybeSingle();
        break;

      case 'update':
        if (op.recordId == null) throw Exception('Record ID required for update');
        await client
            .from(op.collection)
            .update(payload)
            .eq('id', op.recordId!)
            .select()
            .maybeSingle();
        break;

      case 'delete':
        if (op.recordId == null) throw Exception('Record ID required for delete');
        await client.from(op.collection).delete().eq('id', op.recordId!);
        break;

      default:
        throw Exception('Unknown operation type: ${op.operationType}');
    }
  }

  /// Check if an error is network-related (so we should stop batch processing).
  bool _isNetworkError(String errStr) {
    return errStr.contains('SocketException') ||
        errStr.contains('Failed host lookup') ||
        errStr.contains('Connection refused') ||
        errStr.contains('Network is unreachable') ||
        errStr.contains('Connection timed out') ||
        errStr.contains('TimeoutException') ||
        errStr.contains('timed out');
  }

  /// Remove operations that have exceeded the maximum retry count.
  Future<void> _cleanExpiredOperations() async {
    final db = _db;
    if (db == null) return;

    final expired = await db.getExpiredOperations();

    if (expired.isNotEmpty) {
      for (final op in expired) {
        await db.deletePendingOperation(op.id);
      }
      debugPrint('🗑️ Removed ${expired.length} expired operations');
    }
  }

  /// Get the count of pending operations.
  /// Returns 0 on web (no Drift database).
  Future<int> getPendingCount() async {
    final db = _db;
    if (db == null) return 0;
    return db.pendingOperationCount();
  }

  /// Clear all pending operations (e.g., on logout).
  /// No-op on web (no Drift database).
  Future<void> clearAll() async {
    final db = _db;
    if (db == null) return;
    await db.clearPendingOperations();
  }
}

/// Riverpod provider for the OfflineQueueManager.
final offlineQueueProvider = Provider<OfflineQueueManager>((ref) {
  return OfflineQueueManager(ref);
});
