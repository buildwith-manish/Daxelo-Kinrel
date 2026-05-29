// ═══════════════════════════════════════════════════════════════════════════
// SyncEngine — Core offline-first bidirectional sync with Supabase
// ═══════════════════════════════════════════════════════════════════════════
//
// Architecture:
//   Supabase (remote)
//       ↕
//   SyncEngine (this file)
//       ↕
//   Drift (local — source of truth)
//
// Design principles:
//   1. Drift is the single source of truth for the UI layer
//   2. All remote data flows through SyncEngine before reaching Drift
//   3. All local mutations are written to Drift first, then pushed
//   4. Conflict resolution is configurable per entity type
//   5. Sync is rate-limited, batched, and resilient to network failures
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_database.dart';
import '../isar_database.dart';
import '../../networking/dio_client.dart';
import '../../services/crashlytics_service.dart';
import '../../services/supabase_service.dart';
import 'connectivity_service.dart';
import 'offline_queue.dart';
import 'cache_invalidation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SYNC DIRECTION
// ═══════════════════════════════════════════════════════════════════════════

/// Direction of data flow during sync.
enum SyncDirection {
  /// Local → Server: Push pending offline operations to Supabase.
  push,

  /// Server → Local: Pull latest changes from Supabase into Drift.
  pull,
}

// ═══════════════════════════════════════════════════════════════════════════
// SYNC EVENT TYPES & MODELS
// ═══════════════════════════════════════════════════════════════════════════

/// Types of events emitted by the sync engine for UI consumption.
enum SyncEventType {
  /// A sync operation has started.
  started,

  /// Currently pulling data from the server.
  pulling,

  /// Currently pushing pending operations to the server.
  pushing,

  /// A conflict was detected and resolved.
  conflict,

  /// The sync operation completed (successfully or with errors).
  completed,

  /// An error occurred during sync.
  error,
}

/// Event emitted by the sync engine for UI notifications.
class SyncEvent {
  final SyncEventType type;
  final String? message;
  final double? progress; // 0.0 – 1.0

  const SyncEvent({
    required this.type,
    this.message,
    this.progress,
  });

  @override
  String toString() =>
      'SyncEvent(type: $type, message: $message, progress: $progress)';
}

// ═══════════════════════════════════════════════════════════════════════════
// SYNC RESULT TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Result of a full or delta sync operation.
class SyncResult {
  /// Number of records pulled from the server.
  final int pulled;

  /// Number of pending operations pushed to the server.
  final int pushed;

  /// Number of conflicts detected and resolved.
  final int conflicts;

  /// Number of errors encountered.
  final int errors;

  /// Human-readable error messages.
  final List<String> errorMessages;

  /// Wall-clock duration of the sync operation.
  final Duration duration;

  const SyncResult({
    this.pulled = 0,
    this.pushed = 0,
    this.conflicts = 0,
    this.errors = 0,
    this.errorMessages = const [],
    this.duration = Duration.zero,
  });

  /// An empty result indicating no work was needed.
  static const empty = SyncResult();

  /// Whether the sync completed without errors.
  bool get isSuccessful => errors == 0;

  SyncResult copyWith({
    int? pulled,
    int? pushed,
    int? conflicts,
    int? errors,
    List<String>? errorMessages,
    Duration? duration,
  }) {
    return SyncResult(
      pulled: pulled ?? this.pulled,
      pushed: pushed ?? this.pushed,
      conflicts: conflicts ?? this.conflicts,
      errors: errors ?? this.errors,
      errorMessages: errorMessages ?? this.errorMessages,
      duration: duration ?? this.duration,
    );
  }

  @override
  String toString() =>
      'SyncResult(pulled: $pulled, pushed: $pushed, conflicts: $conflicts, '
      'errors: $errors, duration: ${duration.inMilliseconds}ms)';
}

/// Result of pushing pending operations to the server.
class PushResult {
  /// Number of operations that succeeded.
  final int succeeded;

  /// Number of operations that failed (will be retried).
  final int failed;

  /// Number of conflicts detected during push.
  final int conflicts;

  /// Human-readable error messages.
  final List<String> errorMessages;

  const PushResult({
    this.succeeded = 0,
    this.failed = 0,
    this.conflicts = 0,
    this.errorMessages = const [],
  });

  bool get isSuccessful => failed == 0 && conflicts == 0;

  @override
  String toString() =>
      'PushResult(succeeded: $succeeded, failed: $failed, '
      'conflicts: $conflicts)';
}

// ═══════════════════════════════════════════════════════════════════════════
// CONFLICT RESOLUTION
// ═══════════════════════════════════════════════════════════════════════════

/// Strategy for resolving sync conflicts.
enum ConflictResolutionStrategy {
  /// Compare `updatedAt` timestamps — newer write wins.
  lastWriteWins,

  /// Server data always wins (used for relationships to maintain integrity).
  serverWins,

  /// Merge non-conflicting fields at the field level (used for profiles).
  fieldLevelMerge,
}

/// Default conflict resolution strategy per entity type.
const Map<String, ConflictResolutionStrategy> _defaultConflictStrategies = {
  'family': ConflictResolutionStrategy.lastWriteWins,
  'person': ConflictResolutionStrategy.lastWriteWins,
  'relationship': ConflictResolutionStrategy.serverWins,
  'profile': ConflictResolutionStrategy.fieldLevelMerge,
  'invitation': ConflictResolutionStrategy.serverWins,
};

/// A log entry recording a detected conflict and how it was resolved.
class ConflictLogEntry {
  final String id;
  final String entityType;
  final String entityId;
  final String conflictType;
  final String localValue;
  final String serverValue;
  final String resolution;
  final DateTime resolvedAt;

  const ConflictLogEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.conflictType,
    required this.localValue,
    required this.serverValue,
    required this.resolution,
    required this.resolvedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'entityType': entityType,
        'entityId': entityId,
        'conflictType': conflictType,
        'localValue': localValue,
        'serverValue': serverValue,
        'resolution': resolution,
        'resolvedAt': resolvedAt.toIso8601String(),
      };

  factory ConflictLogEntry.fromJson(Map<String, dynamic> json) =>
      ConflictLogEntry(
        id: json['id'] as String,
        entityType: json['entityType'] as String,
        entityId: json['entityId'] as String,
        conflictType: json['conflictType'] as String,
        localValue: json['localValue'] as String,
        serverValue: json['serverValue'] as String,
        resolution: json['resolution'] as String,
        resolvedAt: DateTime.parse(json['resolvedAt'] as String),
      );
}

/// The outcome of resolving a conflict.
class ConflictResolution {
  /// The strategy that was applied.
  final ConflictResolutionStrategy strategy;

  /// The resolved data to be written to local storage.
  final Map<String, dynamic> resolvedData;

  /// Human-readable description of what was resolved.
  final String description;

  const ConflictResolution({
    required this.strategy,
    required this.resolvedData,
    required this.description,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SYNC STATUS
// ═══════════════════════════════════════════════════════════════════════════

/// Current status of the sync engine, exposed to the UI layer.
class SyncStatus {
  /// Whether a sync operation is currently in progress.
  final bool isSyncing;

  /// Timestamp of the last sync attempt (successful or not).
  final DateTime? lastSyncAt;

  /// Timestamp of the last successful sync.
  final DateTime? lastSuccessfulSyncAt;

  /// Number of pending operations waiting to be pushed.
  final int pendingOperations;

  /// Description of the last error, if any.
  final String? lastError;

  /// The current sync phase, if syncing.
  final SyncEventType? currentPhase;

  const SyncStatus({
    this.isSyncing = false,
    this.lastSyncAt,
    this.lastSuccessfulSyncAt,
    this.pendingOperations = 0,
    this.lastError,
    this.currentPhase,
  });

  SyncStatus copyWith({
    bool? isSyncing,
    DateTime? lastSyncAt,
    DateTime? lastSuccessfulSyncAt,
    int? pendingOperations,
    String? lastError,
    SyncEventType? currentPhase,
    bool clearError = false,
  }) {
    return SyncStatus(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastSuccessfulSyncAt:
          lastSuccessfulSyncAt ?? this.lastSuccessfulSyncAt,
      pendingOperations: pendingOperations ?? this.pendingOperations,
      lastError: clearError ? null : (lastError ?? this.lastError),
      currentPhase: currentPhase,
    );
  }

  @override
  String toString() =>
      'SyncStatus(isSyncing: $isSyncing, pending: $pendingOperations, '
      'lastSync: $lastSyncAt, lastError: $lastError)';
}

// ═══════════════════════════════════════════════════════════════════════════
// SYNC METADATA
// ═══════════════════════════════════════════════════════════════════════════

/// Keys used to persist sync metadata in the UserSettings table.
class _SyncMetaKeys {
  static const lastPullTime = 'sync_last_pull_time';
  static const lastFullSyncTime = 'sync_last_full_sync_time';
  static const lastSuccessfulSyncTime = 'sync_last_successful_time';
  static const lastPushTime = 'sync_last_push_time';
  static const conflictLog = 'sync_conflict_log';
}

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

/// Minimum interval between two sync operations (rate limiting).
const Duration _minSyncInterval = Duration(seconds: 30);

/// How often periodic sync runs while the app is active.
const Duration _periodicSyncInterval = Duration(minutes: 5);

/// Maximum number of pending operations processed per batch.
const int _maxBatchSize = 50;

/// Maximum number of records requested per page from the server.
const int _pageSize = 100;

/// Maximum number of retries before a pending operation is marked as failed.
const int _maxRetries = 5;

/// Maximum conflict log entries to keep (oldest are pruned).
const int _maxConflictLogEntries = 200;

/// Supabase table names mapped from entity type strings.
const Map<String, String> _entityTableMap = {
  'family': 'families',
  'person': 'persons',
  'relationship': 'relationships',
  'profile': 'profiles',
  'invitation': 'invitations',
};

// ═══════════════════════════════════════════════════════════════════════════
// SYNC ENGINE
// ═══════════════════════════════════════════════════════════════════════════

/// Core sync engine that makes Drift the source of truth and handles
/// bidirectional sync with Supabase.
///
/// Usage:
///   final engine = SyncEngine(ref);
///   await engine.fullSync(userId);
///   engine.syncEvents.listen((event) { ... });
///   print(engine.status);
class SyncEngine {
  SyncEngine(this._ref);

  final Ref _ref;

  // ── Dependencies ─────────────────────────────────────────────────────

  AppDatabase get _db => _ref.read(isarProvider);
  Dio get _dio => _ref.read(dioProvider);
  ConnectivityService get _connectivity =>
      _ref.read(connectivityServiceProvider);
  OfflineQueueManager get _offlineQueue => _ref.read(offlineQueueProvider);

  // ── State ────────────────────────────────────────────────────────────

  SyncStatus _status = const SyncStatus();
  SyncStatus get status => _status;

  DateTime? _lastSyncAttempt;
  Timer? _periodicSyncTimer;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _disposed = false;

  /// In-memory conflict log (persisted to UserSettings periodically).
  List<ConflictLogEntry> _conflictLog = [];

  /// Configurable conflict resolution strategy per entity type.
  /// Overrides can be set at runtime via [setConflictStrategy].
  Map<String, ConflictResolutionStrategy> _conflictStrategies = {
    ..._defaultConflictStrategies,
  };

  // ── Event Stream ─────────────────────────────────────────────────────

  final _eventController = StreamController<SyncEvent>.broadcast();

  /// Stream of sync events for UI consumption (snackbars, progress bars, etc.)
  Stream<SyncEvent> get syncEvents => _eventController.stream;

  // ── Status Notifier ──────────────────────────────────────────────────

  final _statusController = StreamController<SyncStatus>.broadcast();

  /// Stream of status changes for reactive UI updates.
  Stream<SyncStatus> get onStatusChanged => _statusController.stream;

  // ══════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════

  /// Start the sync engine:
  ///   1. Load persisted conflict log
  ///   2. Listen for connectivity changes → trigger sync
  ///   3. Set up periodic sync (every 5 minutes)
  ///   4. Perform an initial sync if online
  Future<void> start() async {
    if (_disposed) return;

    debugPrint('🔄 SyncEngine starting...');

    await _loadConflictLog();

    // Listen for connectivity changes
    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((isOnline) {
      if (isOnline) {
        debugPrint('🟢 Connectivity restored — triggering sync');
        final userId = _currentUserId;
        if (userId != null) {
          fullSync(userId);
        } else {
          pushPendingOperations();
        }
      }
    });

    // Set up periodic sync
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(_periodicSyncInterval, (_) {
      final userId = _currentUserId;
      if (userId != null && _connectivity.isOnline) {
        deltaSync(userId);
      }
    });

    // Initial sync if online
    if (_connectivity.isOnline) {
      final userId = _currentUserId;
      if (userId != null) {
        await fullSync(userId);
      }
    }

    debugPrint('✅ SyncEngine started');
  }

  /// Stop the sync engine and release resources.
  void stop() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    debugPrint('🔄 SyncEngine stopped');
  }

  /// Dispose the sync engine permanently.
  void dispose() {
    _disposed = true;
    stop();
    _persistConflictLog();
    _eventController.close();
    _statusController.close();
  }

  // ══════════════════════════════════════════════════════════════════════
  // FULL SYNC
  // ══════════════════════════════════════════════════════════════════════

  /// Perform a full sync for the given user:
  ///   1. Pull latest data from server for all families
  ///   2. Merge with local data (conflict resolution)
  ///   3. Push pending offline operations
  ///
  /// This is the primary entry point for:
  ///   - App startup
  ///   - Connectivity restored
  ///   - Manual refresh
  Future<SyncResult> fullSync(String userId) async {
    if (_disposed) return SyncResult.empty;
    if (!_canSync()) return SyncResult.empty;

    final stopwatch = Stopwatch()..start();
    int pulled = 0;
    int pushed = 0;
    int conflicts = 0;
    int errors = 0;
    final errorMessages = <String>[];

    _updateStatus(isSyncing: true, currentPhase: SyncEventType.started);
    _emitEvent(const SyncEvent(type: SyncEventType.started, message: 'Starting full sync'));

    try {
      // ── Phase 1: Pull ──────────────────────────────────────────────
      _updateStatus(currentPhase: SyncEventType.pulling);
      _emitEvent(const SyncEvent(type: SyncEventType.pulling, message: 'Pulling data from server', progress: 0.0));

      final pullResult = await _pullAllData(userId);
      pulled = pullResult.pulled;
      conflicts += pullResult.conflicts;
      errors += pullResult.errors;
      errorMessages.addAll(pullResult.errorMessages);

      _emitEvent(SyncEvent(
        type: SyncEventType.pulling,
        message: 'Pulled $pulled records',
        progress: 0.5,
      ));

      // ── Phase 2: Push ──────────────────────────────────────────────
      _updateStatus(currentPhase: SyncEventType.pushing);
      _emitEvent(const SyncEvent(type: SyncEventType.pushing, message: 'Pushing pending operations', progress: 0.5));

      final pushResult = await pushPendingOperations();
      pushed = pushResult.succeeded;
      conflicts += pushResult.conflicts;
      errors += pushResult.failed;
      errorMessages.addAll(pushResult.errorMessages);

      _emitEvent(SyncEvent(
        type: SyncEventType.pushing,
        message: 'Pushed $pushed operations',
        progress: 1.0,
      ));

      // ── Update metadata ────────────────────────────────────────────
      final now = DateTime.now();
      await _setMeta(_SyncMetaKeys.lastFullSyncTime, now.toIso8601String());
      await _setMeta(_SyncMetaKeys.lastSuccessfulSyncTime, now.toIso8601String());
      await _setMeta(_SyncMetaKeys.lastPullTime, now.toIso8601String());

      _updateStatus(
        isSyncing: false,
        lastSyncAt: now,
        lastSuccessfulSyncAt: now,
        clearError: true,
        currentPhase: null,
      );

      _emitEvent(SyncEvent(
        type: SyncEventType.completed,
        message: 'Full sync complete: $pulled pulled, $pushed pushed, $conflicts conflicts',
        progress: 1.0,
      ));

      stopwatch.stop();

      return SyncResult(
        pulled: pulled,
        pushed: pushed,
        conflicts: conflicts,
        errors: errors,
        errorMessages: errorMessages,
        duration: stopwatch.elapsed,
      );
    } catch (e, st) {
      stopwatch.stop();
      errors++;
      errorMessages.add(e.toString());

      _updateStatus(
        isSyncing: false,
        lastSyncAt: DateTime.now(),
        lastError: e.toString(),
        currentPhase: null,
      );

      _emitEvent(SyncEvent(
        type: SyncEventType.error,
        message: 'Full sync failed: $e',
      ));

      logError('SyncEngine.fullSync', st, reason: e.toString());

      return SyncResult(
        pulled: pulled,
        pushed: pushed,
        conflicts: conflicts,
        errors: errors,
        errorMessages: errorMessages,
        duration: stopwatch.elapsed,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // DELTA SYNC
  // ══════════════════════════════════════════════════════════════════════

  /// Perform a delta sync: pull only changes since the last successful sync,
  /// then push any pending operations.
  ///
  /// If [familyId] is provided, only sync data for that family.
  Future<SyncResult> deltaSync(String userId, {String? familyId}) async {
    if (_disposed) return SyncResult.empty;
    if (!_canSync()) return SyncResult.empty;

    final stopwatch = Stopwatch()..start();
    int pulled = 0;
    int pushed = 0;
    int conflicts = 0;
    int errors = 0;
    final errorMessages = <String>[];

    _updateStatus(isSyncing: true, currentPhase: SyncEventType.started);
    _emitEvent(const SyncEvent(
      type: SyncEventType.started,
      message: familyId != null
          ? 'Starting delta sync for family'
          : 'Starting delta sync',
    ));

    try {
      // ── Phase 1: Delta Pull ────────────────────────────────────────
      _updateStatus(currentPhase: SyncEventType.pulling);
      _emitEvent(const SyncEvent(type: SyncEventType.pulling, progress: 0.0));

      final lastPull = await _getMeta(_SyncMetaKeys.lastPullTime);
      final pullResult = await _pullDeltaData(
        userId,
        since: lastPull,
        familyId: familyId,
      );
      pulled = pullResult.pulled;
      conflicts += pullResult.conflicts;
      errors += pullResult.errors;
      errorMessages.addAll(pullResult.errorMessages);

      _emitEvent(SyncEvent(
        type: SyncEventType.pulling,
        message: 'Delta pulled $pulled records',
        progress: 0.5,
      ));

      // ── Phase 2: Push ──────────────────────────────────────────────
      _updateStatus(currentPhase: SyncEventType.pushing);
      _emitEvent(const SyncEvent(type: SyncEventType.pushing, progress: 0.5));

      final pushResult = await pushPendingOperations();
      pushed = pushResult.succeeded;
      conflicts += pushResult.conflicts;
      errors += pushResult.failed;
      errorMessages.addAll(pushResult.errorMessages);

      // ── Update metadata ────────────────────────────────────────────
      final now = DateTime.now();
      await _setMeta(_SyncMetaKeys.lastPullTime, now.toIso8601String());
      if (errors == 0) {
        await _setMeta(
            _SyncMetaKeys.lastSuccessfulSyncTime, now.toIso8601String());
      }

      _updateStatus(
        isSyncing: false,
        lastSyncAt: now,
        lastSuccessfulSyncAt: errors == 0 ? now : null,
        lastError: errors > 0 ? errorMessages.join('; ') : null,
        clearError: errors == 0,
        currentPhase: null,
      );

      _emitEvent(SyncEvent(
        type: SyncEventType.completed,
        message: 'Delta sync complete: $pulled pulled, $pushed pushed',
        progress: 1.0,
      ));

      stopwatch.stop();

      return SyncResult(
        pulled: pulled,
        pushed: pushed,
        conflicts: conflicts,
        errors: errors,
        errorMessages: errorMessages,
        duration: stopwatch.elapsed,
      );
    } catch (e, st) {
      stopwatch.stop();
      errors++;
      errorMessages.add(e.toString());

      _updateStatus(
        isSyncing: false,
        lastSyncAt: DateTime.now(),
        lastError: e.toString(),
        currentPhase: null,
      );

      _emitEvent(SyncEvent(
        type: SyncEventType.error,
        message: 'Delta sync failed: $e',
      ));

      logError('SyncEngine.deltaSync', st, reason: e.toString());

      return SyncResult(
        pulled: pulled,
        pushed: pushed,
        conflicts: conflicts,
        errors: errors,
        errorMessages: errorMessages,
        duration: stopwatch.elapsed,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // PUSH PENDING OPERATIONS
  // ══════════════════════════════════════════════════════════════════════

  /// Push all pending operations from the offline queue to the server.
  ///
  /// Operations are processed in batches of [_maxBatchSize], ordered by:
  ///   1. Priority (higher first — note: lower number = higher priority)
  ///   2. Creation time (older first)
  ///
  /// For each operation:
  ///   - Success: Remove from queue, update local cache
  ///   - Conflict: Log conflict, apply resolution strategy
  ///   - Network error: Increment retryCount, mark isProcessing=false
  ///   - After 5 retries: Mark as failed, remove from queue, log error
  Future<PushResult> pushPendingOperations() async {
    if (_disposed) return const PushResult();
    if (!_connectivity.isOnline) return const PushResult();

    int succeeded = 0;
    int failed = 0;
    int conflicts = 0;
    final errorMessages = <String>[];

    try {
      final pendingOps = await _db.getPendingOperations();

      if (pendingOps.isEmpty) return const PushResult();

      // Process in batches
      final batches = _batch(pendingOps, _maxBatchSize);

      for (final batch in batches) {
        for (final op in batch) {
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
            await _executePendingOperation(op);

            // Success — remove from queue
            await _db.deletePendingOperation(op.id);
            succeeded++;

            debugPrint(
              '✅ Pushed: ${op.operationType} on ${op.collection}'
              '${op.recordId != null ? ' (${op.recordId})' : ''}',
            );
          } on DioException catch (e) {
            final statusCode = e.response?.statusCode;

            // 409 Conflict or 412 Precondition Failed
            if (statusCode == 409 || statusCode == 412) {
              conflicts++;
              await _handlePushConflict(op, e);
              await _db.deletePendingOperation(op.id);

              _emitEvent(const SyncEvent(
                type: SyncEventType.conflict,
                message: 'Conflict during push — resolved',
              ));
            } else if (_isRetryableError(e)) {
              // Network/transient error — increment retry count
              final newRetryCount = op.retryCount + 1;

              if (newRetryCount >= _maxRetries) {
                // Max retries exceeded — remove from queue and log
                await _db.deletePendingOperation(op.id);
                failed++;
                errorMessages.add(
                  'Operation ${op.operationType} on ${op.collection}'
                  ' failed after $_maxRetries retries',
                );
                debugPrint(
                  '❌ Operation failed after $_maxRetries retries: '
                  '${op.operationType} on ${op.collection}',
                );
              } else {
                // Exponential backoff — update retry count
                await _db.upsertPendingOperation(PendingOperationsCompanion(
                  id: Value(op.id),
                  operationType: Value(op.operationType),
                  collection: Value(op.collection),
                  recordId: Value(op.recordId),
                  payload: Value(op.payload),
                  createdAt: Value(op.createdAt),
                  retryCount: Value(newRetryCount),
                  lastRetryAt: Value(DateTime.now()),
                  priority: Value(op.priority),
                  isProcessing: const Value(false),
                ));
                failed++;

                debugPrint(
                  '⚠️ Push failed (retry $newRetryCount/$_maxRetries): '
                  '${op.operationType} on ${op.collection}',
                );

                // If this is a network error, stop the batch — we're
                // probably offline again
                if (_isNetworkError(e)) {
                  debugPrint('🔴 Network error during push, stopping batch');
                  break;
                }
              }
            } else {
              // Non-retryable client error (400, 401, 403, 404, 422)
              await _db.deletePendingOperation(op.id);
              failed++;
              errorMessages.add(
                'Operation ${op.operationType} on ${op.collection}'
                ' failed with status $statusCode: ${e.message}',
              );
              debugPrint(
                '❌ Non-retryable error ($statusCode): '
                '${op.operationType} on ${op.collection}',
              );
            }
          } catch (e) {
            // Unexpected error
            final newRetryCount = op.retryCount + 1;

            if (newRetryCount >= _maxRetries) {
              await _db.deletePendingOperation(op.id);
              failed++;
              errorMessages.add(
                'Operation ${op.operationType} on ${op.collection}'
                ' failed unexpectedly: $e',
              );
            } else {
              await _db.upsertPendingOperation(PendingOperationsCompanion(
                id: Value(op.id),
                operationType: Value(op.operationType),
                collection: Value(op.collection),
                recordId: Value(op.recordId),
                payload: Value(op.payload),
                createdAt: Value(op.createdAt),
                retryCount: Value(newRetryCount),
                lastRetryAt: Value(DateTime.now()),
                priority: Value(op.priority),
                isProcessing: const Value(false),
              ));
              failed++;
            }

            debugPrint('❌ Unexpected error during push: $e');
          }
        }

        // Brief pause between batches to avoid overwhelming the server
        if (batches.length > 1 && batch != batches.last) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      // Update push timestamp
      await _setMeta(
          _SyncMetaKeys.lastPushTime, DateTime.now().toIso8601String());

      // Update pending count in status
      final pendingCount = await _db.pendingOperationCount();
      _updateStatus(pendingOperations: pendingCount);
    } catch (e, st) {
      logError('SyncEngine.pushPendingOperations', st, reason: e.toString());
      errorMessages.add('Push failed: $e');
    }

    return PushResult(
      succeeded: succeeded,
      failed: failed,
      conflicts: conflicts,
      errorMessages: errorMessages,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // ENTITY-SPECIFIC SYNC
  // ══════════════════════════════════════════════════════════════════════

  /// Sync family data only.
  Future<SyncResult> syncFamilies() async {
    if (_disposed) return SyncResult.empty;
    if (!_canSync()) return SyncResult.empty;

    final userId = _currentUserId;
    if (userId == null) {
      return const SyncResult(errors: 1, errorMessages: ['Not authenticated']);
    }

    final stopwatch = Stopwatch()..start();

    try {
      final lastPull = await _getMeta(_SyncMetaKeys.lastPullTime);
      final pullResult = await _pullDeltaData(userId, since: lastPull);
      stopwatch.stop();

      return SyncResult(
        pulled: pullResult.pulled,
        conflicts: pullResult.conflicts,
        errors: pullResult.errors,
        errorMessages: pullResult.errorMessages,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return SyncResult(
        errors: 1,
        errorMessages: [e.toString()],
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Sync persons for a specific family.
  Future<SyncResult> syncPersons(String familyId) async {
    if (_disposed) return SyncResult.empty;
    if (!_canSync()) return SyncResult.empty;

    final userId = _currentUserId;
    if (userId == null) {
      return const SyncResult(errors: 1, errorMessages: ['Not authenticated']);
    }

    final stopwatch = Stopwatch()..start();

    try {
      final lastPull = await _getMeta(_SyncMetaKeys.lastPullTime);
      final pullResult =
          await _pullDeltaData(userId, since: lastPull, familyId: familyId);
      stopwatch.stop();

      return SyncResult(
        pulled: pullResult.pulled,
        conflicts: pullResult.conflicts,
        errors: pullResult.errors,
        errorMessages: pullResult.errorMessages,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return SyncResult(
        errors: 1,
        errorMessages: [e.toString()],
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Sync relationships for a specific family.
  Future<SyncResult> syncRelationships(String familyId) async {
    if (_disposed) return SyncResult.empty;
    if (!_canSync()) return SyncResult.empty;

    final userId = _currentUserId;
    if (userId == null) {
      return const SyncResult(errors: 1, errorMessages: ['Not authenticated']);
    }

    final stopwatch = Stopwatch()..start();

    try {
      final lastPull = await _getMeta(_SyncMetaKeys.lastPullTime);
      final pullResult =
          await _pullDeltaData(userId, since: lastPull, familyId: familyId);
      stopwatch.stop();

      return SyncResult(
        pulled: pullResult.pulled,
        conflicts: pullResult.conflicts,
        errors: pullResult.errors,
        errorMessages: pullResult.errorMessages,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return SyncResult(
        errors: 1,
        errorMessages: [e.toString()],
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Sync invitations for the current user.
  Future<SyncResult> syncInvitations() async {
    if (_disposed) return SyncResult.empty;
    if (!_canSync()) return SyncResult.empty;

    final userId = _currentUserId;
    if (userId == null) {
      return const SyncResult(errors: 1, errorMessages: ['Not authenticated']);
    }

    final stopwatch = Stopwatch()..start();
    int pulled = 0;
    int errors = 0;
    final errorMessages = <String>[];

    try {
      final client = _ref.read(supabaseProvider);
      if (client == null) {
        return const SyncResult(
            errors: 1, errorMessages: ['Supabase not available']);
      }

      // Fetch invitations for this user from Supabase
      final invitations = await client
          .from('invitations')
          .select()
          .or('inviter_id.eq.$userId,invitee_id.eq.$userId')
          .order('created_at', ascending: false);

      pulled = invitations.length;

      // Cache invitations as API cache entries
      for (final inv in invitations) {
        final key = 'invitation_${inv['id']}';
        await _db.upsertApiCacheEntry(ApiCacheEntriesCompanion(
          key: Value(key),
          responseBody: Value(jsonEncode(inv)),
          cachedAt: Value(DateTime.now()),
          ttlSeconds: const Value(3600), // 1 hour
        ));
      }

      stopwatch.stop();

      return SyncResult(
        pulled: pulled,
        duration: stopwatch.elapsed,
      );
    } catch (e, st) {
      stopwatch.stop();
      errors++;
      errorMessages.add(e.toString());
      logError('SyncEngine.syncInvitations', st, reason: e.toString());
      return SyncResult(
        errors: errors,
        errorMessages: errorMessages,
        duration: stopwatch.elapsed,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // CONFLICT RESOLUTION
  // ══════════════════════════════════════════════════════════════════════

  /// Resolve a conflict using the configured strategy for the entity type.
  ///
  /// Strategies:
  ///   - [ConflictResolutionStrategy.lastWriteWins]: Compare updatedAt
  ///     timestamps, newer write wins.
  ///   - [ConflictResolutionStrategy.serverWins]: Server data always wins
  ///     (used for relationships to maintain data integrity).
  ///   - [ConflictResolutionStrategy.fieldLevelMerge]: Merge non-conflicting
  ///     fields from both local and server data (used for profiles).
  Future<ConflictResolution> resolveConflict(
      ConflictLogEntry conflict) async {
    final strategy =
        _conflictStrategies[conflict.entityType] ??
            ConflictResolutionStrategy.lastWriteWins;

    Map<String, dynamic> localData = {};
    Map<String, dynamic> serverData = {};

    try {
      localData =
          jsonDecode(conflict.localValue) as Map<String, dynamic>;
    } catch (_) {}

    try {
      serverData =
          jsonDecode(conflict.serverValue) as Map<String, dynamic>;
    } catch (_) {}

    switch (strategy) {
      case ConflictResolutionStrategy.lastWriteWins:
        return _resolveLastWriteWins(localData, serverData);

      case ConflictResolutionStrategy.serverWins:
        return ConflictResolution(
          strategy: strategy,
          resolvedData: serverData,
          description: 'Server wins — used server data for '
              '${conflict.entityType}/${conflict.entityId}',
        );

      case ConflictResolutionStrategy.fieldLevelMerge:
        return _resolveFieldLevelMerge(localData, serverData);
    }
  }

  /// Override the conflict resolution strategy for a specific entity type.
  void setConflictStrategy(
    String entityType,
    ConflictResolutionStrategy strategy,
  ) {
    _conflictStrategies[entityType] = strategy;
    debugPrint('🔧 Conflict strategy for $entityType set to $strategy');
  }

  /// Get the current conflict resolution strategy for an entity type.
  ConflictResolutionStrategy getConflictStrategy(String entityType) {
    return _conflictStrategies[entityType] ??
        ConflictResolutionStrategy.lastWriteWins;
  }

  // ── LWW Resolution ────────────────────────────────────────────────

  ConflictResolution _resolveLastWriteWins(
    Map<String, dynamic> localData,
    Map<String, dynamic> serverData,
  ) {
    final localUpdated = _parseTimestamp(localData['updatedAt']);
    final serverUpdated = _parseTimestamp(serverData['updatedAt']);

    // Newer timestamp wins; if equal, server wins (deterministic tiebreak)
    final serverWins = serverUpdated != null &&
        (localUpdated == null || !serverUpdated.isBefore(localUpdated));

    if (serverWins) {
      return ConflictResolution(
        strategy: ConflictResolutionStrategy.lastWriteWins,
        resolvedData: serverData,
        description: 'LWW: Server wins '
            '(server: $serverUpdated, local: $localUpdated)',
      );
    } else {
      return ConflictResolution(
        strategy: ConflictResolutionStrategy.lastWriteWins,
        resolvedData: localData,
        description: 'LWW: Local wins '
            '(server: $serverUpdated, local: $localUpdated)',
      );
    }
  }

  // ── Field-Level Merge ─────────────────────────────────────────────

  ConflictResolution _resolveFieldLevelMerge(
    Map<String, dynamic> localData,
    Map<String, dynamic> serverData,
  ) {
    // Fields that should not be merged (system fields)
    const systemFields = {'id', 'createdAt', 'createdBy', 'updatedAt'};

    final merged = <String, dynamic>{...serverData}; // Start with server data

    int localFieldsUsed = 0;
    int serverFieldsUsed = 0;

    for (final entry in localData.entries) {
      if (systemFields.contains(entry.key)) continue;

      final localVal = entry.value;
      final serverVal = serverData[entry.key];

      if (serverVal == null && localVal != null) {
        // Local has a value, server doesn't → use local
        merged[entry.key] = localVal;
        localFieldsUsed++;
      } else if (localVal != null &&
          serverVal != null &&
          localVal != serverVal) {
        // Both have values but they differ → server wins for the field,
        // but this is a conflict that should be noted
        serverFieldsUsed++;
      }
      // If both have the same value or local is null, server value stands
    }

    // Update the updatedAt to the latest of the two
    final localUpdated = _parseTimestamp(localData['updatedAt']);
    final serverUpdated = _parseTimestamp(serverData['updatedAt']);
    if (localUpdated != null && serverUpdated != null) {
      merged['updatedAt'] = localUpdated.isAfter(serverUpdated)
          ? localData['updatedAt']
          : serverData['updatedAt'];
    }

    return ConflictResolution(
      strategy: ConflictResolutionStrategy.fieldLevelMerge,
      resolvedData: merged,
      description: 'Field-level merge: $localFieldsUsed local fields, '
          '$serverFieldsUsed server fields used for conflicts',
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // CONFLICT LOG
  // ══════════════════════════════════════════════════════════════════════

  /// Get all recorded conflict log entries.
  List<ConflictLogEntry> get conflictLog => List.unmodifiable(_conflictLog);

  /// Clear the conflict log.
  Future<void> clearConflictLog() async {
    _conflictLog.clear();
    await _setMeta(_SyncMetaKeys.conflictLog, '[]');
  }

  void _recordConflict({
    required String entityType,
    required String entityId,
    required String conflictType,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> serverData,
    required String resolution,
  }) {
    final entry = ConflictLogEntry(
      id: '${entityType}_${entityId}_${DateTime.now().millisecondsSinceEpoch}',
      entityType: entityType,
      entityId: entityId,
      conflictType: conflictType,
      localValue: jsonEncode(localData),
      serverValue: jsonEncode(serverData),
      resolution: resolution,
      resolvedAt: DateTime.now(),
    );

    _conflictLog.add(entry);

    // Prune if too many entries
    if (_conflictLog.length > _maxConflictLogEntries) {
      _conflictLog.removeRange(
        0,
        _conflictLog.length - _maxConflictLogEntries,
      );
    }

    debugPrint(
      '⚠️ Conflict: $conflictType for $entityType/$entityId → $resolution',
    );
  }

  Future<void> _loadConflictLog() async {
    try {
      final json = await _getMeta(_SyncMetaKeys.conflictLog);
      if (json != null && json.isNotEmpty) {
        final list = jsonDecode(json) as List<dynamic>;
        _conflictLog = list
            .map((e) => ConflictLogEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load conflict log: $e');
      _conflictLog = [];
    }
  }

  Future<void> _persistConflictLog() async {
    try {
      final json =
          jsonEncode(_conflictLog.map((e) => e.toJson()).toList());
      await _setMeta(_SyncMetaKeys.conflictLog, json);
    } catch (e) {
      debugPrint('⚠️ Failed to persist conflict log: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // PULL IMPLEMENTATION
  // ══════════════════════════════════════════════════════════════════════

  /// Pull all data for the user's families from the server.
  /// Handles pagination automatically (cursor-based, [_pageSize] per page).
  Future<SyncResult> _pullAllData(String userId) async {
    return _pullDeltaData(userId, since: null);
  }

  /// Pull data modified since [since] for the user's families.
  /// If [familyId] is provided, filters to that family.
  /// Handles pagination with the `hasMore` flag from the server.
  Future<SyncResult> _pullDeltaData(
    String userId, {
    String? since,
    String? familyId,
  }) async {
    int pulled = 0;
    int conflicts = 0;
    int errors = 0;
    final errorMessages = <String>[];

    String? cursor = since;
    bool hasMore = true;
    int pageCount = 0;

    while (hasMore && pageCount < 50) {
      // Safety: max 50 pages per sync to prevent infinite loops
      pageCount++;

      try {
        final response = await _dio.post(
          '/sync',
          data: {
            'userId': userId,
            if (cursor != null) 'since': cursor,
          },
        );

        final data = response.data as Map<String, dynamic>;
        final serverTime = data['serverTime'] as String? ??
            DateTime.now().toIso8601String();
        hasMore = data['hasMore'] as bool? ?? false;

        // ── Process family metadata ────────────────────────────────
        final familyMeta =
            data['familyMeta'] as Map<String, dynamic>? ?? {};
        for (final entry in familyMeta.entries) {
          final familyId_ = entry.key;
          final familyData = entry.value as Map<String, dynamic>;
          try {
            final mergeResult = await _mergeFamily(
              familyId_: familyId_,
              serverData: familyData,
            );
            pulled++;
            if (mergeResult.hadConflict) conflicts++;
          } catch (e) {
            errors++;
            errorMessages.add('Failed to merge family $familyId_: $e');
            debugPrint('❌ Failed to merge family $familyId_: $e');
          }
        }

        // ── Process members (persons) ──────────────────────────────
        final members = data['members'] as List<dynamic>? ?? [];
        for (final memberRaw in members) {
          final memberData = memberRaw as Map<String, dynamic>;
          final personId = memberData['id']?.toString();
          if (personId == null) continue;

          // If a specific familyId filter is requested, skip others
          if (familyId != null &&
              memberData['familyId']?.toString() != familyId) {
            continue;
          }

          try {
            final mergeResult = await _mergePerson(
              personId: personId,
              serverData: memberData,
            );
            pulled++;
            if (mergeResult.hadConflict) conflicts++;
          } catch (e) {
            errors++;
            errorMessages.add('Failed to merge person $personId: $e');
            debugPrint('❌ Failed to merge person $personId: $e');
          }
        }

        // ── Process events (cached as API entries) ─────────────────
        final events = data['events'] as List<dynamic>? ?? [];
        for (final eventRaw in events) {
          final eventData = eventRaw as Map<String, dynamic>;
          final eventId = eventData['id']?.toString();
          if (eventId == null) continue;

          try {
            await _db.upsertApiCacheEntry(ApiCacheEntriesCompanion(
              key: Value('event_$eventId'),
              responseBody: Value(jsonEncode(eventData)),
              cachedAt: Value(DateTime.now()),
              ttlSeconds: const Value(3600),
            ));
            pulled++;
          } catch (e) {
            errors++;
            errorMessages.add('Failed to cache event $eventId: $e');
          }
        }

        // ── Pull relationships from Supabase ───────────────────────
        // The sync endpoint doesn't return relationships directly;
        // we pull them from Supabase for the family IDs we know about.
        try {
          final relResult = await _pullRelationships(familyMeta.keys.toList());
          pulled += relResult.pulled;
          conflicts += relResult.conflicts;
          errors += relResult.errors;
          errorMessages.addAll(relResult.errorMessages);
        } catch (e) {
          // Non-fatal — relationships are supplementary
          debugPrint('⚠️ Failed to pull relationships: $e');
        }

        // ── Update cursor for next page ────────────────────────────
        cursor = serverTime;

        // Emit progress
        _emitEvent(SyncEvent(
          type: SyncEventType.pulling,
          progress: hasMore ? 0.3 + (0.2 * (pageCount / 50)) : 0.5,
        ));

        // Brief pause between pages to avoid overwhelming the server
        if (hasMore) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      } on DioException catch (e) {
        errors++;
        final msg = 'Sync API request failed: ${e.message}';
        errorMessages.add(msg);
        debugPrint('❌ $msg');

        // If it's a network error, stop pulling — we're probably offline
        if (_isNetworkError(e)) break;
        // If it's an auth error, stop — we can't recover automatically
        if (e.response?.statusCode == 401) break;

        break;
      } catch (e, st) {
        errors++;
        errorMessages.add('Pull failed: $e');
        logError('SyncEngine._pullDeltaData', st, reason: e.toString());
        break;
      }
    }

    // Persist conflict log after processing
    await _persistConflictLog();

    return SyncResult(
      pulled: pulled,
      conflicts: conflicts,
      errors: errors,
      errorMessages: errorMessages,
    );
  }

  /// Pull relationships from Supabase for the given family IDs.
  Future<SyncResult> _pullRelationships(List<String> familyIds) async {
    if (familyIds.isEmpty) return SyncResult.empty;

    final client = _ref.read(supabaseProvider);
    if (client == null) {
      return const SyncResult(
          errors: 1, errorMessages: ['Supabase not available']);
    }

    int pulled = 0;
    int conflicts = 0;
    int errors = 0;
    final errorMessages = <String>[];

    try {
      // Fetch relationships for each family (batch up to 10 family IDs)
      final batches = _batch(familyIds, 10);

      for (final batch in batches) {
        final filter = batch.join(',');

        final relationships = await client
            .from('relationships')
            .select()
            .filter('family_id', 'in', '($filter)');

        for (final relData in relationships as List<dynamic>) {
          final relMap = relData as Map<String, dynamic>;
          final relId = relMap['id']?.toString();
          if (relId == null) continue;

          try {
            final mergeResult = await _mergeRelationship(
              relationshipId: relId,
              serverData: relMap,
            );
            pulled++;
            if (mergeResult.hadConflict) conflicts++;
          } catch (e) {
            errors++;
            errorMessages.add('Failed to merge relationship $relId: $e');
          }
        }
      }
    } catch (e) {
      errors++;
      errorMessages.add('Relationship pull failed: $e');
    }

    return SyncResult(
      pulled: pulled,
      conflicts: conflicts,
      errors: errors,
      errorMessages: errorMessages,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // MERGE OPERATIONS (local ← server)
  // ══════════════════════════════════════════════════════════════════════

  /// Result of a merge operation.
  _MergeResult _mergeOk() => const _MergeResult(hadConflict: false);
  _MergeResult _mergeConflict() => const _MergeResult(hadConflict: true);

  /// Merge server family data into local Drift cache.
  Future<_MergeResult> _mergeFamily({
    required String familyId_,
    required Map<String, dynamic> serverData,
  }) async {
    final existing = await _db.getFamily(familyId_);

    if (existing == null) {
      // No local data → insert server data directly
      await _upsertFamilyFromServer(familyId_, serverData);
      return _mergeOk();
    }

    // Check for conflict
    final localData = _safeDecode(existing.data);
    final localUpdated = _parseTimestamp(localData['updatedAt']);
    final serverUpdated = _parseTimestamp(serverData['updatedAt']);

    if (localUpdated != null &&
        serverUpdated != null &&
        localUpdated.isAfter(serverUpdated)) {
      // Local is newer → no conflict, keep local
      return _mergeOk();
    }

    if (localUpdated != null &&
        serverUpdated != null &&
        _dataEquals(localData, serverData)) {
      // Data is identical → no conflict
      return _mergeOk();
    }

    // Conflict detected — apply resolution
    final strategy = _conflictStrategies['family'] ??
        ConflictResolutionStrategy.lastWriteWins;

    Map<String, dynamic> resolvedData;

    switch (strategy) {
      case ConflictResolutionStrategy.lastWriteWins:
        if (serverUpdated != null &&
            (localUpdated == null || !serverUpdated.isBefore(localUpdated))) {
          resolvedData = serverData;
        } else {
          resolvedData = localData; // Local wins
          return _mergeOk(); // No change needed
        }
        break;
      case ConflictResolutionStrategy.serverWins:
        resolvedData = serverData;
        break;
      case ConflictResolutionStrategy.fieldLevelMerge:
        final resolution = _resolveFieldLevelMerge(localData, serverData);
        resolvedData = resolution.resolvedData;
        break;
    }

    _recordConflict(
      entityType: 'family',
      entityId: familyId_,
      conflictType: 'update_conflict',
      localData: localData,
      serverData: serverData,
      resolution: strategy.name,
    );

    await _upsertFamilyFromServer(familyId_, resolvedData);
    return _mergeConflict();
  }

  /// Merge server person data into local Drift cache.
  Future<_MergeResult> _mergePerson({
    required String personId,
    required Map<String, dynamic> serverData,
  }) async {
    final existing = await _db.getPerson(personId);

    // Handle soft-deleted records from server
    if (serverData['deletedAt'] != null) {
      if (existing != null) {
        await _db.deletePerson(personId);
        CacheInvalidation.invalidateProfile(personId);
      }
      return _mergeOk();
    }

    if (existing == null) {
      await _upsertPersonFromServer(personId, serverData);
      return _mergeOk();
    }

    final localData = _safeDecode(existing.data);
    final localUpdated = _parseTimestamp(localData['updatedAt']);
    final serverUpdated = _parseTimestamp(serverData['updatedAt']);

    if (localUpdated != null &&
        serverUpdated != null &&
        localUpdated.isAfter(serverUpdated)) {
      return _mergeOk(); // Local is newer
    }

    if (_dataEquals(localData, serverData)) {
      return _mergeOk(); // Identical
    }

    // Conflict — resolve
    final strategy = _conflictStrategies['person'] ??
        ConflictResolutionStrategy.lastWriteWins;

    Map<String, dynamic> resolvedData;

    switch (strategy) {
      case ConflictResolutionStrategy.lastWriteWins:
        if (serverUpdated != null &&
            (localUpdated == null || !serverUpdated.isBefore(localUpdated))) {
          resolvedData = serverData;
        } else {
          return _mergeOk(); // Local wins, no change
        }
        break;
      case ConflictResolutionStrategy.serverWins:
        resolvedData = serverData;
        break;
      case ConflictResolutionStrategy.fieldLevelMerge:
        final resolution = _resolveFieldLevelMerge(localData, serverData);
        resolvedData = resolution.resolvedData;
        break;
    }

    _recordConflict(
      entityType: 'person',
      entityId: personId,
      conflictType: 'update_conflict',
      localData: localData,
      serverData: serverData,
      resolution: strategy.name,
    );

    await _upsertPersonFromServer(personId, resolvedData);
    return _mergeConflict();
  }

  /// Merge server relationship data into local Drift cache.
  Future<_MergeResult> _mergeRelationship({
    required String relationshipId,
    required Map<String, dynamic> serverData,
  }) async {
    // Query by ID directly — AppDatabase doesn't expose getRelationship(id)
    final existing = await (_db.select(_db.cachedRelationships)
          ..where((t) => t.id.equals(relationshipId)))
        .getSingleOrNull();

    // Map server field names to our cache format
    final normalizedData = _normalizeRelationshipData(serverData);

    if (existing == null) {
      await _upsertRelationshipFromServer(relationshipId, normalizedData);
      return _mergeOk();
    }

    final localData = _safeDecode(existing.data);

    // Relationships use serverWins by default for data integrity
    final strategy = _conflictStrategies['relationship'] ??
        ConflictResolutionStrategy.serverWins;

    Map<String, dynamic> resolvedData;

    switch (strategy) {
      case ConflictResolutionStrategy.serverWins:
        resolvedData = normalizedData;
        break;
      case ConflictResolutionStrategy.lastWriteWins:
        final localUpdated = _parseTimestamp(localData['updatedAt']);
        final serverUpdated = _parseTimestamp(normalizedData['updatedAt']);
        if (localUpdated != null &&
            serverUpdated != null &&
            localUpdated.isAfter(serverUpdated)) {
          return _mergeOk(); // Local wins
        }
        resolvedData = normalizedData;
        break;
      case ConflictResolutionStrategy.fieldLevelMerge:
        final resolution = _resolveFieldLevelMerge(localData, normalizedData);
        resolvedData = resolution.resolvedData;
        break;
    }

    if (!_dataEquals(localData, resolvedData)) {
      _recordConflict(
        entityType: 'relationship',
        entityId: relationshipId,
        conflictType: 'update_conflict',
        localData: localData,
        serverData: normalizedData,
        resolution: strategy.name,
      );

      await _upsertRelationshipFromServer(relationshipId, resolvedData);
      return _mergeConflict();
    }

    return _mergeOk();
  }

  // ══════════════════════════════════════════════════════════════════════
  // UPSERT HELPERS (server data → Drift)
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _upsertFamilyFromServer(
    String familyId,
    Map<String, dynamic> data,
  ) async {
    await _db.upsertFamily(CachedFamiliesCompanion(
      id: Value(familyId),
      name: Value(data['name'] as String? ?? 'Unnamed Family'),
      data: Value(jsonEncode(data)),
      cachedAt: Value(DateTime.now()),
    ));
  }

  Future<void> _upsertPersonFromServer(
    String personId,
    Map<String, dynamic> data,
  ) async {
    final familyId = data['familyId']?.toString() ?? '';
    final name = data['name'] as String? ?? 'Unknown';

    await _db.upsertPerson(CachedPersonsCompanion(
      id: Value(personId),
      familyId: Value(familyId),
      name: Value(name),
      data: Value(jsonEncode(data)),
      cachedAt: Value(DateTime.now()),
    ));

    // Invalidate cache for this person's family
    CacheInvalidation.invalidateFamily(familyId);
  }

  Future<void> _upsertRelationshipFromServer(
    String relationshipId,
    Map<String, dynamic> data,
  ) async {
    final fromId = data['fromPersonId']?.toString() ??
        data['from_person_id']?.toString() ??
        '';
    final toId = data['toPersonId']?.toString() ??
        data['to_person_id']?.toString() ??
        '';
    final relType = data['relationshipKey']?.toString() ??
        data['relationship_key']?.toString() ??
        data['relationshipType']?.toString() ??
        data['relationship_type']?.toString() ??
        '';
    final kinshipName = data['kinshipName']?.toString() ??
        data['kinship_name']?.toString();

    await _db.upsertRelationship(CachedRelationshipsCompanion(
      id: Value(relationshipId),
      fromId: Value(fromId),
      toId: Value(toId),
      relationshipType: Value(relType),
      kinshipName: Value(kinshipName),
      data: Value(jsonEncode(data)),
      cachedAt: Value(DateTime.now()),
    ));
  }

  // ══════════════════════════════════════════════════════════════════════
  // PENDING OPERATION EXECUTION
  // ══════════════════════════════════════════════════════════════════════

  /// Execute a single pending operation against the Supabase API.
  Future<void> _executePendingOperation(PendingOperation op) async {
    final client = _ref.read(supabaseProvider);
    if (client == null) throw Exception('Supabase not available');

    final payload = op.payload != null
        ? jsonDecode(op.payload!) as Map<String, dynamic>
        : <String, dynamic>{};

    // Add updatedAt timestamp for mutations
    if (op.operationType != 'delete') {
      payload['updatedAt'] = DateTime.now().toIso8601String();
    }

    final tableName = _entityTableMap[op.collection] ?? op.collection;

    switch (op.operationType) {
      case 'create':
        await client
            .from(tableName)
            .insert(payload)
            .select()
            .maybeSingle();
        break;

      case 'update':
        if (op.recordId == null) {
          throw Exception('Record ID required for update');
        }
        await client
            .from(tableName)
            .update(payload)
            .eq('id', op.recordId!)
            .select()
            .maybeSingle();
        break;

      case 'delete':
        if (op.recordId == null) {
          throw Exception('Record ID required for delete');
        }
        await client.from(tableName).delete().eq('id', op.recordId!);
        break;

      default:
        throw Exception('Unknown operation type: ${op.operationType}');
    }
  }

  /// Handle a conflict detected during push (HTTP 409/412).
  Future<void> _handlePushConflict(
    PendingOperation op,
    DioException error,
  ) async {
    Map<String, dynamic> serverData = {};
    try {
      serverData = error.response?.data as Map<String, dynamic>? ?? {};
    } catch (_) {}

    Map<String, dynamic> localData = {};
    try {
      if (op.payload != null) {
        localData = jsonDecode(op.payload!) as Map<String, dynamic>;
      }
    } catch (_) {}

    final strategy = _conflictStrategies[op.collection] ??
        ConflictResolutionStrategy.lastWriteWins;

    _recordConflict(
      entityType: op.collection,
      entityId: op.recordId ?? 'unknown',
      conflictType: 'push_conflict',
      localData: localData,
      serverData: serverData,
      resolution: strategy.name,
    );

    // For push conflicts, we apply the resolution and update local cache
    final resolution = await resolveConflict(ConflictLogEntry(
      id: 'push_${op.id}',
      entityType: op.collection,
      entityId: op.recordId ?? 'unknown',
      conflictType: 'push_conflict',
      localValue: op.payload ?? '{}',
      serverValue: jsonEncode(serverData),
      resolution: strategy.name,
      resolvedAt: DateTime.now(),
    ));

    // Update local cache with resolved data
    switch (op.collection) {
      case 'family':
        if (op.recordId != null) {
          await _upsertFamilyFromServer(op.recordId!, resolution.resolvedData);
        }
        break;
      case 'person':
        if (op.recordId != null) {
          await _upsertPersonFromServer(
              op.recordId!, resolution.resolvedData);
        }
        break;
      case 'relationship':
        if (op.recordId != null) {
          await _upsertRelationshipFromServer(
              op.recordId!, resolution.resolvedData);
        }
        break;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // RATE LIMITING & GUARDS
  // ══════════════════════════════════════════════════════════════════════

  /// Check if a sync operation can proceed.
  /// Returns false if:
  ///   - Already syncing
  ///   - Too soon since last sync attempt (< 30 seconds)
  ///   - Device is offline
  ///   - Engine is disposed
  bool _canSync() {
    if (_disposed) return false;
    if (_status.isSyncing) {
      debugPrint('🔄 Sync already in progress, skipping');
      return false;
    }

    // Rate limiting: don't sync more than once per 30 seconds
    if (_lastSyncAttempt != null) {
      final elapsed = DateTime.now().difference(_lastSyncAttempt!);
      if (elapsed < _minSyncInterval) {
        debugPrint(
          '🔄 Rate limited — last sync was ${elapsed.inSeconds}s ago '
          '(min: ${_minSyncInterval.inSeconds}s)',
        );
        return false;
      }
    }

    if (!_connectivity.isOnline) {
      debugPrint('🔴 Device is offline, skipping sync');
      return false;
    }

    _lastSyncAttempt = DateTime.now();
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ══════════════════════════════════════════════════════════════════════

  /// Get the current user ID from the Supabase session.
  String? get _currentUserId {
    try {
      final client = _ref.read(supabaseProvider);
      return client?.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Emit a sync event to all listeners.
  void _emitEvent(SyncEvent event) {
    if (_disposed || _eventController.isClosed) return;
    _eventController.add(event);
  }

  /// Update the internal status and notify listeners.
  void _updateStatus({
    bool? isSyncing,
    DateTime? lastSyncAt,
    DateTime? lastSuccessfulSyncAt,
    int? pendingOperations,
    String? lastError,
    bool clearError = false,
    SyncEventType? currentPhase,
  }) {
    _status = _status.copyWith(
      isSyncing: isSyncing,
      lastSyncAt: lastSyncAt,
      lastSuccessfulSyncAt: lastSuccessfulSyncAt,
      pendingOperations: pendingOperations,
      lastError: lastError,
      clearError: clearError,
      currentPhase: currentPhase,
    );

    if (!_disposed && !_statusController.isClosed) {
      _statusController.add(_status);
    }
  }

  /// Read a value from the UserSettings table.
  Future<String?> _getMeta(String key) async {
    try {
      return _db.getSetting(key);
    } catch (_) {
      return null;
    }
  }

  /// Write a value to the UserSettings table.
  Future<void> _setMeta(String key, String value) async {
    try {
      await _db.setSetting(key, value);
    } catch (e) {
      debugPrint('⚠️ Failed to set sync meta $key: $e');
    }
  }

  /// Parse a timestamp from various formats.
  DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Safely decode a JSON string, returning an empty map on failure.
  Map<String, dynamic> _safeDecode(String json) {
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Check if two data maps are semantically equal.
  /// Compares JSON-encoded forms to handle type differences.
  bool _dataEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    // Quick size check
    if (a.length != b.length) return false;

    // Compare JSON strings for determinism (handles nested objects, lists)
    try {
      // Sort keys before encoding for deterministic comparison
      final encodedA = jsonEncode(_sortKeys(a));
      final encodedB = jsonEncode(_sortKeys(b));
      return encodedA == encodedB;
    } catch (_) {
      return false;
    }
  }

  /// Recursively sort map keys for deterministic JSON comparison.
  Map<String, dynamic> _sortKeys(Map<String, dynamic> map) {
    final sorted = <String, dynamic>{};
    final keys = map.keys.toList()..sort();
    for (final key in keys) {
      final val = map[key];
      if (val is Map<String, dynamic>) {
        sorted[key] = _sortKeys(val);
      } else if (val is List) {
        sorted[key] = val
            .map((e) =>
                e is Map<String, dynamic> ? _sortKeys(e) : e)
            .toList();
      } else {
        sorted[key] = val;
      }
    }
    return sorted;
  }

  /// Normalize relationship data from server field names to client field names.
  Map<String, dynamic> _normalizeRelationshipData(
      Map<String, dynamic> data) {
    return {
      'id': data['id'] ?? data['Id'],
      'familyId': data['familyId'] ?? data['family_id'],
      'fromPersonId':
          data['fromPersonId'] ?? data['from_person_id'] ?? data['fromId'],
      'toPersonId':
          data['toPersonId'] ?? data['to_person_id'] ?? data['toId'],
      'relationshipKey': data['relationshipKey'] ??
          data['relationship_key'] ??
          data['relationshipType'] ??
          data['relationship_type'],
      'direction': data['direction'] ?? 'from',
      'isActive': data['isActive'] ?? data['is_active'] ?? true,
      'label': data['label'],
      'createdAt': data['createdAt'] ?? data['created_at'],
      'updatedAt': data['updatedAt'] ?? data['updated_at'],
    };
  }

  /// Split a list into batches of the given size.
  List<List<T>> _batch<T>(List<T> items, int batchSize) {
    final batches = <List<T>>[];
    for (var i = 0; i < items.length; i += batchSize) {
      batches.add(
        items.sublist(i, min(i + batchSize, items.length)),
      );
    }
    return batches;
  }

  /// Check if a DioException represents a network error.
  bool _isNetworkError(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.error is SocketException ||
        e.error is TimeoutException;
  }

  /// Check if a DioException is retryable (transient server or network error).
  bool _isRetryableError(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode != null) {
      // Retry on server errors
      if (statusCode >= 500) return true;
      // Never retry client errors (except 409/412 which are conflicts)
      if (statusCode >= 400 && statusCode < 500) return false;
    }
    // Retry on network errors
    return _isNetworkError(e);
  }

  /// Force an immediate sync, bypassing rate limiting.
  /// Use for user-initiated refresh (pull-to-refresh).
  Future<SyncResult> forceSync() async {
    final userId = _currentUserId;
    if (userId == null) {
      return const SyncResult(errors: 1, errorMessages: ['Not authenticated']);
    }

    // Reset rate limiter
    _lastSyncAttempt = null;
    return fullSync(userId);
  }

  /// Get the count of pending operations.
  Future<int> getPendingCount() async {
    return _db.pendingOperationCount();
  }

  /// Get the last successful sync time.
  Future<DateTime?> getLastSuccessfulSyncTime() async {
    final value = await _getMeta(_SyncMetaKeys.lastSuccessfulSyncTime);
    return value != null ? DateTime.tryParse(value) : null;
  }

  /// Clear all sync metadata (for logout).
  Future<void> clearSyncData() async {
    await _setMeta(_SyncMetaKeys.lastPullTime, '');
    await _setMeta(_SyncMetaKeys.lastFullSyncTime, '');
    await _setMeta(_SyncMetaKeys.lastSuccessfulSyncTime, '');
    await _setMeta(_SyncMetaKeys.lastPushTime, '');
    await clearConflictLog();
    _lastSyncAttempt = null;
    _status = const SyncStatus();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MERGE RESULT HELPER
// ═══════════════════════════════════════════════════════════════════════════

class _MergeResult {
  final bool hadConflict;
  const _MergeResult({required this.hadConflict});
}

// ═══════════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the SyncEngine singleton.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(ref);
  ref.onDispose(() => engine.dispose());
  return engine;
});

/// Provider that reflects the current sync status as a stream.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.onStatusChanged;
});

/// Provider that streams sync events for UI consumption.
final syncEventsProvider = StreamProvider<SyncEvent>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.syncEvents;
});

/// Provider for the number of pending operations.
final pendingOpsCountProvider = FutureProvider<int>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.getPendingCount();
});
