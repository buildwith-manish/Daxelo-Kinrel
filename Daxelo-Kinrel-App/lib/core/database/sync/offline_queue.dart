import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../isar_database.dart';
import '../collections/pending_operation.dart';
import '../sync/connectivity_service.dart';
import '../../services/supabase_service.dart';

/// Manages offline write operations that need to be synced when online.
/// Stores failed write operations in Isar and retries them when
/// connectivity is restored.
class OfflineQueueManager {
  final Ref _ref;

  OfflineQueueManager(this._ref);

  Isar get _isar => _ref.read(isarProvider);
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

    await _isar.writeTxn(() async {
      await _isar.pendingOperations.put(op);
    });

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
    final pending = await _isar.pendingOperations
        .where()
        .filter()
        .isProcessingEqualTo(false)
        .and()
        .retryCountLessThan(PendingOperation.maxRetries)
        .sortByPriority()
        .thenByCreatedAt()
        .findAll();

    if (pending.isEmpty) return 0;

    debugPrint('🔄 Processing ${pending.length} pending operations...');

    int successCount = 0;
    int failCount = 0;

    for (final op in pending) {
      // Mark as processing
      await _isar.writeTxn(() async {
        op.isProcessing = true;
        await _isar.pendingOperations.put(op);
      });

      try {
        await _executeOperation(op);

        // Success — remove from queue
        await _isar.writeTxn(() async {
          await _isar.pendingOperations.delete(op.isarId);
        });

        successCount++;
        debugPrint('✅ Synced: ${op.operationType} on ${op.collection}');
      } catch (e) {
        // Failed — increment retry count and mark as not processing
        await _isar.writeTxn(() async {
          op.retryCount++;
          op.lastRetryAt = DateTime.now().toIso8601String();
          op.isProcessing = false;
          await _isar.pendingOperations.put(op);
        });

        failCount++;
        debugPrint(
          '⚠️ Failed to sync: ${op.operationType} on ${op.collection}'
          ' (retry ${op.retryCount}/${PendingOperation.maxRetries}): $e',
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
    final expired = await _isar.pendingOperations
        .where()
        .filter()
        .retryCountGreaterThan(PendingOperation.maxRetries - 1)
        .findAll();

    if (expired.isNotEmpty) {
      await _isar.writeTxn(() async {
        for (final op in expired) {
          await _isar.pendingOperations.delete(op.isarId);
        }
      });
      debugPrint('🗑️ Removed ${expired.length} expired operations');
    }
  }

  /// Get the count of pending operations.
  Future<int> getPendingCount() async {
    return _isar.pendingOperations
        .where()
        .filter()
        .retryCountLessThan(PendingOperation.maxRetries)
        .count();
  }

  /// Clear all pending operations (e.g., on logout).
  Future<void> clearAll() async {
    await _isar.writeTxn(() async {
      await _isar.pendingOperations.clear();
    });
  }
}

/// Riverpod provider for the OfflineQueueManager.
final offlineQueueProvider = Provider<OfflineQueueManager>((ref) {
  return OfflineQueueManager(ref);
});
