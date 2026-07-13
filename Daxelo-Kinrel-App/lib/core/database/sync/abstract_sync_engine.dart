// lib/core/database/sync/abstract_sync_engine.dart
//
// DAXELO KINREL — Abstract Sync Engine (P5.4)
//
// Per Vision §5 Layer 4 + spec P5.4: "Extracts abstract SyncEngine
// from trackc_sync_engine.dart and creates 4 new sync engines (chat,
// feed, memories, calendar)."
//
// This is the abstract base class that all sync engines extend. It
// follows the Trackc pattern (watermark + outbox + LWW) without
// inventing a new sync architecture.
//
// Concrete implementations:
//   - TrackcSyncEngine (existing, refactored to extend this base)
//   - ChatSyncEngine (new)
//   - FeedSyncEngine (new)
//   - MemoriesSyncEngine (new)
//   - CalendarSyncEngine (new)

import 'dart:async';

/// Abstract base class for all sync engines.
///
/// Follows the Trackc pattern:
///   1. Drain outbox (push local mutations)
///   2. Pull delta (fetch server changes since watermark)
///   3. Update local cache + watermark
///   4. LWW conflict resolution (server-authoritative)
abstract class AbstractSyncEngine {
  /// The name of this engine (e.g., 'trackc', 'chat', 'feed').
  String get engineName;

  /// Whether a sync is currently in progress.
  bool get isSyncing;

  /// Stream of sync state changes for UI consumption.
  Stream<SyncEngineState> get syncState;

  /// Pulls delta from the server and updates the local cache.
  ///
  /// Returns the new watermark (or null if nothing was pulled).
  Future<DateTime?> pullDelta({List<String>? families});

  /// Pushes local outbox mutations to the server.
  ///
  /// Returns the number of mutations successfully pushed.
  Future<int> pushOutbox();

  /// Performs a full sync (push + pull).
  ///
  /// This is the main entry point called by BackgroundSyncManager.
  Future<void> fullSync({List<String>? families}) async {
    await pushOutbox();
    await pullDelta(families: families);
  }

  /// Disposes resources.
  void dispose();
}

/// State of a sync engine.
enum SyncEngineState {
  idle,
  running,
  alreadyRunning,
  success,
  error,
}

/// Provider metadata for a sync engine.
class SyncEngineMetadata {
  const SyncEngineMetadata({
    required this.name,
    required this.displayName,
    required this.description,
  });

  final String name;
  final String displayName;
  final String description;
}
