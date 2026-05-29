import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../isar_database.dart';
import '../app_database.dart';
import '../collections/pending_operation.dart';
import '../sync/connectivity_service.dart';
import '../../services/supabase_service.dart';

/// Manages offline write operations that need to be synced when online.
/// Stores failed write operations in Drift and retries them when
/// connectivity is restored.
class OfflineQueueManager {
  final Ref _ref;

  OfflineQueueManager(this._ref);

  AppDatabase get _db => _ref.read(isarProvider);
  ConnectivityService get _connectivity => _ref.read(connectivityServiceProvider);
  bool get _isOnline => _connectivity.isOnline;

  /// Enqueue a write operation for later sync.
  /// Use this when a network write fails due to being offline.
  Future<void> enqueue({
    required String operationType,
    required String collection,
    String? recordId,
    Map<String, dynamic>? payload,
    int priority = 1,
  }) async {
    final op = PendingOperation.create(
      operationType: operationType,
      collection: collection,
      recordId: recordId,
      payload: payload != null ? jsonEncode(payload) : null,
      priority: priority,
    );

    await _db.upsertPendingOperation(PendingOperationsCompanion(
      operationType: Value(op.operationType),
      collection: Value(op.collection),
      recordId: Value(op.recordId),
      payload: Value(op.payload),
      createdAt: Value(DateTime.parse(op.createdAt)),
      retryCount: Value(op.retryCount),
      lastRetryAt: Value(op.lastRetryAt != null ? DateTime.parse(op.lastRetryAt!) : null),
      priority: Value(op.priority),
      isProcessing: Value(op.isProcessing),
    ));

    debugPrint(
      '📥 Queued offline operation: $operationType on $collection'
      '${recordId != null ? ' ($recordId)' : ''}',
    );
  }

  /// Process all pending operations in priority order.
  /// Called when connectivity is restored or periodically.
  Future<int> processPendingOperations() async {
    if (!_isOnline) return 0;

    // Get all non-processing operations, sorted by priority then creation time
    final pending = await _db.getPendingOperations();

    if (pending.isEmpty) return 0;

    debugPrint('🔄 Processing ${pending.length} pending operations...');

    int successCount = 0;
    int failCount = 0;

    for (final op in pending) {
      // Mark as processing
      await _db.upsertPendingOperation(PendingOperationsCompanion(
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
        await _db.deletePendingOperation(op.id);

        successCount++;
        debugPrint('✅ Synced: ${op.operationType} on ${op.collection}');
      } catch (e) {
        // Failed — increment retry count and mark as not processing
        await _db.upsertPendingOperation(PendingOperationsCompanion(
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
          ' (retry ${op.retryCount + 1}/${PendingOperation.maxRetries}): $e',
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
    final expired = await _db.getExpiredOperations();

    if (expired.isNotEmpty) {
      for (final op in expired) {
        await _db.deletePendingOperation(op.id);
      }
      debugPrint('🗑️ Removed ${expired.length} expired operations');
    }
  }

  /// Get the count of pending operations.
  Future<int> getPendingCount() async {
    return _db.pendingOperationCount();
  }

  /// Clear all pending operations (e.g., on logout).
  Future<void> clearAll() async {
    await _db.clearPendingOperations();
  }
}

/// Riverpod provider for the OfflineQueueManager.
final offlineQueueProvider = Provider<OfflineQueueManager>((ref) {
  return OfflineQueueManager(ref);
});
