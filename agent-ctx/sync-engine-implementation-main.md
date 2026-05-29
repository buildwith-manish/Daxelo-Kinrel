# Task: SyncEngine Implementation for Daxelo-Kinrel App

## Task ID: sync-engine-implementation
## Agent: main

## Summary

Implemented the complete `SyncEngine` at `/home/z/my-project/Daxelo-Kinrel-App/lib/core/database/sync/sync_engine.dart` (2,224 lines).

## Architecture

```
Supabase (remote)
    ↕
SyncEngine (this file)
    ↕
Drift (local — source of truth)
```

## Key Components Implemented

### Types & Models
- `SyncDirection` enum (push/pull)
- `SyncEventType` enum (started/pulling/pushing/conflict/completed/error)
- `SyncEvent` class with type, message, progress
- `SyncResult` class with pulled/pushed/conflicts/errors/duration
- `PushResult` class with succeeded/failed/conflicts
- `ConflictResolutionStrategy` enum (lastWriteWins/serverWins/fieldLevelMerge)
- `ConflictLogEntry` with toJson/fromJson for persistence
- `ConflictResolution` with strategy/resolvedData/description
- `SyncStatus` with isSyncing/lastSyncAt/pendingOperations/currentPhase

### SyncEngine Class
- **Lifecycle**: `start()`, `stop()`, `dispose()`
- **Full Sync**: `fullSync(userId)` — pull all → merge → push pending
- **Delta Sync**: `deltaSync(userId, familyId?)` — pull since last sync → merge → push
- **Push**: `pushPendingOperations()` — batched, retried, conflict-resolved
- **Entity-specific**: `syncFamilies()`, `syncPersons(familyId)`, `syncRelationships(familyId)`, `syncInvitations()`
- **Conflict resolution**: `resolveConflict(entry)`, `setConflictStrategy(entityType, strategy)`
- **Force sync**: `forceSync()` — bypasses rate limiting
- **Streams**: `syncEvents` for UI, `onStatusChanged` for reactive updates

### Conflict Resolution Strategies
- **LastWriteWins**: Compare updatedAt timestamps
- **ServerWins**: Server data always wins (relationships)
- **FieldLevelMerge**: Merge non-conflicting fields (profiles)

### Sync Metadata
- Persisted in `UserSettings` table via `_SyncMetaKeys`
- Keys: lastPullTime, lastFullSyncTime, lastSuccessfulSyncTime, lastPushTime, conflictLog

### Key Features
- Rate limiting: 30-second minimum between syncs
- Periodic sync: Every 5 minutes
- Batch processing: Max 50 operations per batch
- Pagination: Cursor-based, up to 50 pages per sync
- Retry with exponential backoff: 5 retries max
- Network error detection: Stops batch on network errors
- Conflict logging: In-memory with persistence, 200-entry max
- Cache invalidation via existing `CacheInvalidation` service
- Crashlytics error reporting via existing `logError`

### Riverpod Providers
- `syncEngineProvider` — singleton SyncEngine
- `syncStatusProvider` — StreamProvider<SyncStatus>
- `syncEventsProvider` — StreamProvider<SyncEvent>
- `pendingOpsCountProvider` — FutureProvider<int>

## Integration Points
- Uses `AppDatabase` (Drift) via `isarProvider`
- Uses `DioClient` via `dioProvider` for `/api/sync` calls
- Uses `ConnectivityService` for network detection
- Uses `OfflineQueueManager` for pending operation management
- Uses `CacheInvalidation` for cache invalidation after merges
- Uses `SupabaseService` for direct Supabase REST API calls
- Uses `CrashlyticsService.logError` for error reporting

## Design Decisions
1. Drift is the source of truth — all server data flows through SyncEngine before reaching Drift
2. Conflict log stored in UserSettings table (since we can't add new Drift tables without regeneration)
3. Relationship queries use direct Drift select API (no `getRelationship(id)` method on AppDatabase)
4. Server sync endpoint returns members, events, familyMeta — relationships are pulled separately from Supabase
5. Soft-deleted records (deletedAt != null) are removed from local cache
6. `_dataEquals` uses sorted JSON encoding for deterministic comparison
7. Push conflicts (HTTP 409/412) are resolved using entity-type strategy then local cache is updated
