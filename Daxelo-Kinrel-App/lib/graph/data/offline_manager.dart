// lib/graph/data/offline_manager.dart
//
// DAXELO KINREL — Offline Manager (V2.1 Blueprint §§12, 28)
//
// v99 STATUS: NOT CURRENTLY USED in production. The
// `offlineManagerProvider` is only ever referenced within this same
// file — `grep -rln "offlineManagerProvider" lib/` returns only
// `offline_manager.dart` itself. No screen, widget, or provider
// outside this file watches or reads it.
//
// The live app handles offline state via:
//   - `connectivity_service.dart` (`isOnlineProvider`) for connectivity
//   - Drift-based optimistic mutations in `optimistic_actions.dart`
//   - `supabase_realtime_service.dart` for live invalidation when
//     connectivity is restored
//
// Nothing else in this file is load-bearing — it imports
// `family_graph_repository.dart`, `graph_cache.dart`, and
// `supabase_data_source.dart`, all of which are themselves unused.
// Safe to delete alongside those three files' eventual cleanup.
//
// Manages offline state tracking, mutation queuing, and 3-phase sync
// protocol for the family graph. Extracted from family_graph_repository
// into a dedicated class per the blueprint specification.
//
// Responsibilities:
//   - Track connectivity via connectivity_plus stream
//   - Expose isOnline / offlineStream
//   - Cache mutation queue (write to Drift, replay when online)
//   - 3-phase sync protocol on reconnect:
//       Phase 1: replay queued mutations in order
//       Phase 2: fetch latest graph state from Supabase
//       Phase 3: merge remote updates into local cache + trigger UI refresh
//   - Conflict resolution: server wins
//   - Expose syncProgress stream (0.0–1.0)
//   - Max 100 queued mutations

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'family_graph_repository.dart';
import 'graph_cache.dart';

// ═══════════════════════════════════════════════════════════════════════
// OFFLINE MANAGER
// ═══════════════════════════════════════════════════════════════════════

/// Manages offline state, mutation queuing, and 3-phase sync for the
/// family graph.
///
/// Tracks connectivity via [Connectivity] and queues mutations when
/// offline. On reconnect, performs a 3-phase sync:
///   Phase 1: Replay queued mutations
///   Phase 2: Fetch latest graph state from Supabase
///   Phase 3: Merge remote updates into local cache
///
/// Conflict resolution: server wins.
/// Maximum 100 queued mutations (oldest dropped on overflow).
class OfflineManager {
  /// Creates an offline manager.
  OfflineManager({
    required this.graphCache,
    required this.supabaseDataSource,
  });

  /// The graph cache for local storage.
  final GraphCache graphCache;

  /// The Supabase data source for remote operations.
  final dynamic supabaseDataSource;

  /// Stream controller for online status.
  final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();

  /// Stream controller for sync progress.
  final StreamController<double> _syncProgressController =
      StreamController<double>.broadcast();

  /// Connectivity subscription.
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// Whether the device is currently online.
  bool _isOnline = true;

  /// Queued mutations for offline replay.
  final List<GraphMutation> _mutationQueue = [];

  /// Maximum number of queued mutations.
  static const int _maxQueuedMutations = 100;

  /// Whether a sync is currently in progress.
  bool _isSyncing = false;

  // ── Public API ──────────────────────────────────────────────────────

  /// Stream of online status changes.
  Stream<bool> get onlineStream => _onlineController.stream;

  /// Whether the device is currently online.
  bool get isOnline => _isOnline;

  /// Stream of sync progress (0.0 to 1.0).
  Stream<double> get syncProgress => _syncProgressController.stream;

  /// Current number of queued mutations.
  int get queuedMutationCount => _mutationQueue.length;

  /// Initializes the offline manager and starts connectivity monitoring.
  void initialize() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        final wasOnline = _isOnline;
        _isOnline = results.any((r) => r != ConnectivityResult.none);

        if (!_onlineController.isClosed) {
          _onlineController.add(_isOnline);
        }

        // Auto-sync when coming back online
        if (!wasOnline && _isOnline && _mutationQueue.isNotEmpty) {
          syncWhenOnline();
        }
      },
    );
  }

  /// Queues a mutation for later replay.
  ///
  /// If the queue is full (100 items), the oldest mutation is dropped.
  Future<void> queueMutation(GraphMutation mutation) async {
    if (_mutationQueue.length >= _maxQueuedMutations) {
      _mutationQueue.removeAt(0);
    }
    _mutationQueue.add(mutation);

    // Persist to cache
    await graphCache.enqueueMutation(mutation);
  }

  /// Performs the 3-phase sync protocol when coming back online.
  ///
  /// Phase 1: Replay queued mutations in order
  /// Phase 2: Fetch latest graph state from Supabase
  /// Phase 3: Merge remote updates into local cache
  ///
  /// Conflict resolution: server wins.
  Future<void> syncWhenOnline() async {
    if (_isSyncing || !_isOnline) return;
    _isSyncing = true;

    try {
      final totalSteps = _mutationQueue.length + 2.0;
      var completedSteps = 0.0;

      // Phase 1: Replay queued mutations
      for (final mutation in List<GraphMutation>.from(_mutationQueue)) {
        try {
          await _replayMutation(mutation);
          _mutationQueue.remove(mutation);
          await graphCache.removeMutation(mutation.id);
        } catch (e) {
          debugPrint('[OfflineManager] Mutation replay failed: $e');
          // Skip failed mutations — server wins
        }
        completedSteps++;
        _emitProgress(completedSteps / totalSteps);
      }

      // Phase 2: Fetch latest graph state from Supabase
      try {
        await _fetchLatestState();
      } catch (e) {
        debugPrint('[OfflineManager] Fetch latest failed: $e');
      }
      completedSteps++;
      _emitProgress(completedSteps / totalSteps);

      // Phase 3: Merge remote updates into local cache
      try {
        await graphCache.clearStaleEntries();
      } catch (e) {
        debugPrint('[OfflineManager] Cache merge failed: $e');
      }

      _emitProgress(1.0);
    } finally {
      _isSyncing = false;
    }
  }

  /// Disposes resources.
  void dispose() {
    _connectivitySubscription?.cancel();
    _onlineController.close();
    _syncProgressController.close();
  }

  // ── Private ─────────────────────────────────────────────────────────

  /// Replays a single mutation against the server.
  Future<void> _replayMutation(GraphMutation mutation) async {
    try {
      final ds = supabaseDataSource;
      if (ds == null) return;

      // Delegate to Supabase data source for RPC call
      await (ds as dynamic).replayMutation(mutation);
    } catch (e) {
      debugPrint('[OfflineManager] Replay error: $e');
      rethrow;
    }
  }

  /// Fetches the latest graph state from Supabase.
  Future<void> _fetchLatestState() async {
    try {
      final ds = supabaseDataSource;
      if (ds == null) return;

      // Delegate to Supabase data source
      await (ds as dynamic).refreshAll();
    } catch (e) {
      debugPrint('[OfflineManager] Fetch error: $e');
    }
  }

  /// Emits sync progress.
  void _emitProgress(double progress) {
    if (!_syncProgressController.isClosed) {
      _syncProgressController.add(progress.clamp(0.0, 1.0));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the [OfflineManager].
final offlineManagerProvider = Provider<OfflineManager>((ref) {
  final graphCache = ref.watch(graphCacheProvider);
  final manager = OfflineManager(
    graphCache: graphCache,
    supabaseDataSource: null, // Set after initialization
  );

  ref.onDispose(() => manager.dispose());

  return manager;
});
