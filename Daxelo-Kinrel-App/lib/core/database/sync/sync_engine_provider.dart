// lib/core/database/sync/sync_engine_provider.dart
//
// DAXELO KINREL — SyncEngine Riverpod Providers
//
// Provides Riverpod providers for the SyncEngine and its reactive
// streams (SyncStatus, SyncEvent). Replaces the simpler SyncService
// provider with the full bidirectional sync engine.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_engine.dart';
import 'connectivity_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// SYNC ENGINE PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the SyncEngine singleton.
/// Automatically disposes the engine when the provider is no longer needed.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(ref);
  ref.onDispose(() => engine.dispose());
  return engine;
});

/// Provider that exposes the SyncStatus stream as a StreamProvider.
/// UI widgets can watch this to reactively show sync progress, errors, etc.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.onStatusChanged;
});

/// Provider that exposes the SyncEvent stream as a StreamProvider.
/// UI widgets can watch this for granular sync events (started, pulling,
/// pushing, conflict, completed, error).
final syncEventsProvider = StreamProvider<SyncEvent>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.syncEvents;
});

/// Provider that reflects the current sync status synchronously.
/// Useful for one-shot reads (e.g., checking isSyncing).
final currentSyncStatusProvider = Provider<SyncStatus>((ref) {
  final asyncStatus = ref.watch(syncStatusProvider);
  return asyncStatus.valueOrNull ?? const SyncStatus();
});

/// Provider that reflects whether the app is currently online.
/// Combines SyncEngine awareness with connectivity service.
final isSyncOnlineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityServiceProvider);
  return connectivity.isOnline;
});
