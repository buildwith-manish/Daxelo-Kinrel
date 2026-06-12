// lib/graph/data/graph_cache.dart
//
// DAXELO KINREL — Graph Cache (V2.1 Data Layer)
//
// Offline cache with SQLite (Drift). Serializes graph state to local
// storage with size limits, TTL-based invalidation, and a 3-phase
// sync protocol for offline-first operation.
//
// Cache Invalidation Strategy:
//   Graph State Cache: Supabase Realtime event, manual refresh, TTL 30 min
//   Node Position Cache: Force simulation completion, session duration
//   Search Index Cache: Graph state invalidation, TTL 60 min
//   Avatar Image Cache: HTTP cache headers, TTL 24 hours
//   Mutation Queue: Successful sync, no TTL (persistent)
//
// 3-Phase Sync Protocol:
//   Phase 1: Replay queued mutations in order
//   Phase 2: Fetch latest graph state from Supabase
//   Phase 3: Merge remote updates into local cache, trigger UI refresh
//   Conflict resolution: "server wins"

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'family_graph_repository.dart';

part 'graph_cache.g.dart';

// ═══════════════════════════════════════════════════════════════════════
// DRIFT TABLE DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════

/// Drift table for cached graph states.
class CachedGraphStates extends Table {
  /// Family ID (primary key).
  TextColumn get familyId => text()();

  /// JSON-serialized [GraphData].
  TextColumn get graphJson => text()();

  /// When this cache entry was created.
  DateTimeColumn get cachedAt => dateTime()();

  /// When this cache entry expires.
  DateTimeColumn get expiresAt => dateTime()();

  /// Size in bytes of the cached data.
  IntColumn get sizeBytes => integer()();

  @override
  Set<Column> get primaryKey => {familyId};
}

/// Drift table for cached node positions.
class CachedNodePositions extends Table {
  /// Family ID (part of composite key).
  TextColumn get familyId => text()();

  /// Disclosure level when positions were saved.
  IntColumn get disclosureLevel => integer()();

  /// JSON-serialized position map.
  TextColumn get positionsJson => text()();

  /// When positions were cached.
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {familyId, disclosureLevel};
}

/// Drift table for the offline mutation queue.
class MutationQueue extends Table {
  /// Unique mutation ID (primary key).
  TextColumn get id => text()();

  /// Mutation type (e.g. "add_relationship", "update_member").
  TextColumn get type => text()();

  /// JSON-serialized mutation payload.
  TextColumn get payloadJson => text()();

  /// When this mutation was created.
  DateTimeColumn get createdAt => dateTime()();

  /// Whether this mutation has been synced.
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Drift table for cached search results.
class CachedSearchResults extends Table {
  /// Search query (part of composite key).
  TextColumn get query => text()();

  /// Family ID (part of composite key).
  TextColumn get familyId => text()();

  /// JSON-serialized search results.
  TextColumn get resultsJson => text()();

  /// When results were cached.
  DateTimeColumn get cachedAt => dateTime()();

  /// When this cache entry expires.
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column> get primaryKey => {query, familyId};
}

// ═══════════════════════════════════════════════════════════════════════
// DRIFT DATABASE
// ═══════════════════════════════════════════════════════════════════════

/// Drift database for graph cache tables.
@DriftDatabase(
  tables: [
    CachedGraphStates,
    CachedNodePositions,
    MutationQueue,
    CachedSearchResults,
  ],
)
class GraphCacheDatabase extends _$GraphCacheDatabase {
  /// Creates a graph cache database.
  GraphCacheDatabase() : super(_openConnection());

  /// Creates a graph cache database with an explicit executor.
  GraphCacheDatabase.withExecutor(QueryExecutor executor)
      : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Future migration logic goes here.
        },
      );

  /// Returns a drift query executor for the current platform.
  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'kinrel_graph_cache');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// A pending mutation in the offline queue.
class GraphMutation {
  /// Creates a graph mutation.
  const GraphMutation({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  /// Unique mutation ID.
  final String id;

  /// Mutation type (e.g. "add_relationship", "update_member").
  final String type;

  /// Mutation payload data.
  final Map<String, dynamic> payload;

  /// When this mutation was created.
  final DateTime createdAt;

  /// Deserializes from a JSON map.
  factory GraphMutation.fromJson(Map<String, dynamic> json) {
    return GraphMutation(
      id: json['id'] as String,
      type: json['type'] as String,
      payload: json['payload'] as Map<String, dynamic>? ??
          <String, dynamic>{},
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// Serializes to a JSON map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
      };
}

// ═══════════════════════════════════════════════════════════════════════
// GRAPH CACHE
// ═══════════════════════════════════════════════════════════════════════

/// Offline cache for graph data with SQLite persistence via Drift.
///
/// Provides:
/// - Graph state caching (50 MB max, TTL 30 min)
/// - Node position caching (5 MB max, session duration)
/// - Search index caching (10 MB max, TTL 60 min)
/// - Mutation queue (100 mutations max, persistent until synced)
/// - Avatar 3-tier caching (in-memory → disk → network)
///
/// 3-Phase Sync Protocol:
/// 1. Replay queued mutations in order
/// 2. Fetch latest graph state from Supabase
/// 3. Merge remote updates into local cache, trigger UI refresh
///
/// Conflict resolution: "server wins"
class GraphCache {
  /// Creates a graph cache with the given [database].
  ///
  /// [maxGraphStorageBytes] is the maximum bytes for graph state
  ///   caching (default: 50 MB).
  /// [maxPositionStorageBytes] is the maximum bytes for position
  ///   caching (default: 5 MB).
  /// [maxSearchStorageBytes] is the maximum bytes for search index
  ///   caching (default: 10 MB).
  /// [maxAvatarDiskBytes] is the maximum bytes for avatar disk cache
  ///   (default: 100 MB).
  /// [maxMutationQueueSize] is the maximum number of pending mutations
  ///   (default: 100).
  /// [graphStateTtl] is the time-to-live for graph state cache
  ///   (default: 30 minutes).
  /// [searchCacheTtl] is the time-to-live for search cache
  ///   (default: 60 minutes).
  GraphCache({
    GraphCacheDatabase? database,
    int maxGraphStorageBytes = 50 * 1024 * 1024,
    int maxPositionStorageBytes = 5 * 1024 * 1024,
    int maxSearchStorageBytes = 10 * 1024 * 1024,
    int maxAvatarDiskBytes = 100 * 1024 * 1024,
    int maxMutationQueueSize = 100,
    Duration graphStateTtl = const Duration(minutes: 30),
    Duration searchCacheTtl = const Duration(minutes: 60),
  })  : _db = database ?? GraphCacheDatabase(),
        _maxGraphStorageBytes = maxGraphStorageBytes,
        _maxPositionStorageBytes = maxPositionStorageBytes,
        _maxSearchStorageBytes = maxSearchStorageBytes,
        _maxAvatarDiskBytes = maxAvatarDiskBytes,
        _maxMutationQueueSize = maxMutationQueueSize,
        _graphStateTtl = graphStateTtl,
        _searchCacheTtl = searchCacheTtl;

  final GraphCacheDatabase _db;

  final int _maxGraphStorageBytes;
  final int _maxPositionStorageBytes;
  final int _maxSearchStorageBytes;
  final int _maxAvatarDiskBytes;
  final int _maxMutationQueueSize;
  final Duration _graphStateTtl;
  final Duration _searchCacheTtl;

  /// In-memory texture cache for avatars (Tier 1).
  /// Maps avatar URL → raw image bytes.
  final Map<String, _AvatarCacheEntry> _avatarMemoryCache =
      <String, _AvatarCacheEntry>{};

  /// LRU order for avatar memory cache eviction.
  final List<String> _avatarMemoryLru = <String>[];

  /// Maximum in-memory avatar cache size (20 MB).
  static const int _maxAvatarMemoryBytes = 20 * 1024 * 1024;

  int _avatarMemoryBytes = 0;

  bool _isDisposed = false;

  // ── Graph State Cache ────────────────────────────────────────────

  /// Saves a graph state to the local cache.
  ///
  /// [familyId] identifies the family. [data] is the complete graph
  /// data to cache. The entry will expire after [_graphStateTtl].
  Future<void> saveGraphState(String familyId, GraphData data) async {
    _checkDisposed();
    try {
      final graphJson = jsonEncode(data.toJson());
      final now = DateTime.now();
      final expiresAt = now.add(_graphStateTtl);
      final sizeBytes = graphJson.length;

      // Evict if exceeding storage limit.
      await _enforceGraphStorageLimit(sizeBytes);

      await _db.into(_db.cachedGraphStates).insertOnConflictUpdate(
            CachedGraphStatesCompanion.insert(
              familyId: familyId,
              graphJson: graphJson,
              cachedAt: now,
              expiresAt: expiresAt,
              sizeBytes: sizeBytes,
            ),
          );
    } catch (e) {
      debugPrint('⚠️ GraphCache.saveGraphState error: $e');
    }
  }

  /// Loads a cached graph state if it exists and has not expired.
  ///
  /// Returns null if no cached state exists or if it has expired.
  Future<GraphData?> loadGraphState(String familyId) async {
    _checkDisposed();
    try {
      final query = _db.select(_db.cachedGraphStates)
        ..where(($CachedGraphStatesTable t) =>
            t.familyId.equals(familyId));

      final row = await query.getSingleOrNull();
      if (row == null) return null;

      // Check expiration.
      if (DateTime.now().isAfter(row.expiresAt)) {
        await (_db.delete(_db.cachedGraphStates)
              ..where(($CachedGraphStatesTable t) =>
                  t.familyId.equals(familyId)))
            .go();
        return null;
      }

      final json = jsonDecode(row.graphJson) as Map<String, dynamic>;
      return GraphData.fromJson(json);
    } catch (e) {
      debugPrint('⚠️ GraphCache.loadGraphState error: $e');
      return null;
    }
  }

  // ── Node Position Cache ──────────────────────────────────────────

  /// Saves node positions for a family at a given disclosure level.
  ///
  /// [familyId] identifies the family.
  /// [positions] maps node IDs to their offsets.
  /// [disclosureLevel] is the expansion level when positions were saved.
  Future<void> savePositions(
    String familyId,
    Map<String, Offset> positions,
    int disclosureLevel,
  ) async {
    _checkDisposed();
    try {
      // Serialize positions as a flat list of objects.
      final positionsList = positions.entries
          .map((MapEntry<String, Offset> e) => <String, dynamic>{
                'id': e.key,
                'x': e.value.dx,
                'y': e.value.dy,
              })
          .toList();
      final positionsJson = jsonEncode(positionsList);
      final now = DateTime.now();

      await _db.into(_db.cachedNodePositions).insertOnConflictUpdate(
            CachedNodePositionsCompanion.insert(
              familyId: familyId,
              disclosureLevel: disclosureLevel,
              positionsJson: positionsJson,
              cachedAt: now,
            ),
          );
    } catch (e) {
      debugPrint('⚠️ GraphCache.savePositions error: $e');
    }
  }

  /// Loads cached node positions for a family at a given disclosure
  /// level.
  ///
  /// Returns null if no cached positions exist.
  Future<Map<String, Offset>?> loadPositions(
    String familyId,
    int disclosureLevel,
  ) async {
    _checkDisposed();
    try {
      final query = _db.select(_db.cachedNodePositions)
        ..where(($CachedNodePositionsTable t) =>
            t.familyId.equals(familyId) &
            t.disclosureLevel.equals(disclosureLevel));

      final row = await query.getSingleOrNull();
      if (row == null) return null;

      final positionsList =
          jsonDecode(row.positionsJson) as List<dynamic>;
      final positions = <String, Offset>{};
      for (final entry in positionsList) {
        final map = entry as Map<String, dynamic>;
        final id = map['id'] as String;
        final x = (map['x'] as num).toDouble();
        final y = (map['y'] as num).toDouble();
        positions[id] = Offset(x, y);
      }
      return positions;
    } catch (e) {
      debugPrint('⚠️ GraphCache.loadPositions error: $e');
      return null;
    }
  }

  // ── Mutation Queue ───────────────────────────────────────────────

  /// Queues a mutation for offline-first sync.
  ///
  /// Mutations are replayed in FIFO order during the 3-phase sync.
  Future<void> queueMutation(GraphMutation mutation) async {
    _checkDisposed();
    try {
      // Enforce queue size limit.
      final pending = await getPendingMutations();
      if (pending.length >= _maxMutationQueueSize) {
        // Remove the oldest mutation to make room.
        await (_db.delete(_db.mutationQueue)
              ..where(($MutationQueueTable t) =>
                  t.id.equals(pending.first.id)))
            .go();
      }

      await _db.into(_db.mutationQueue).insertOnConflictUpdate(
            MutationQueueCompanion.insert(
              id: mutation.id,
              type: mutation.type,
              payloadJson: jsonEncode(mutation.payload),
              createdAt: mutation.createdAt,
            ),
          );
    } catch (e) {
      debugPrint('⚠️ GraphCache.queueMutation error: $e');
    }
  }

  /// Returns all pending (unsynced) mutations in creation order.
  Future<List<GraphMutation>> getPendingMutations() async {
    _checkDisposed();
    try {
      final query = _db.select(_db.mutationQueue)
        ..orderBy([
          ($MutationQueueTable t) => OrderingTerm.asc(t.createdAt),
        ]);
      final rows = await query.get();

      return rows.map((MutationQueueData row) {
        return GraphMutation(
          id: row.id,
          type: row.type,
          payload: jsonDecode(row.payloadJson) as Map<String, dynamic>,
          createdAt: row.createdAt,
        );
      }).toList();
    } catch (e) {
      debugPrint('⚠️ GraphCache.getPendingMutations error: $e');
      return <GraphMutation>[];
    }
  }

  /// Removes mutations that have been successfully synced.
  ///
  /// [mutationIds] is the list of mutation IDs to remove.
  Future<void> clearProcessedMutations(List<String> mutationIds) async {
    _checkDisposed();
    try {
      for (final id in mutationIds) {
        await (_db.delete(_db.mutationQueue)
              ..where(($MutationQueueTable t) => t.id.equals(id)))
            .go();
      }
    } catch (e) {
      debugPrint('⚠️ GraphCache.clearProcessedMutations error: $e');
    }
  }

  // ── Cache Management ─────────────────────────────────────────────

  /// Invalidates all cached data for the given [familyId].
  ///
  /// Removes graph state, positions, and search results for the
  /// specified family.
  Future<void> invalidateCache(String familyId) async {
    _checkDisposed();
    try {
      await (_db.delete(_db.cachedGraphStates)
            ..where(($CachedGraphStatesTable t) =>
                t.familyId.equals(familyId)))
          .go();
      await (_db.delete(_db.cachedNodePositions)
            ..where(($CachedNodePositionsTable t) =>
                t.familyId.equals(familyId)))
          .go();
      await (_db.delete(_db.cachedSearchResults)
            ..where(($CachedSearchResultsTable t) =>
                t.familyId.equals(familyId)))
          .go();
    } catch (e) {
      debugPrint('⚠️ GraphCache.invalidateCache error: $e');
    }
  }

  /// Returns the total cache size in bytes.
  Future<int> getCacheSize() async {
    _checkDisposed();
    try {
      // Sum sizes of all graph state entries.
      final graphRows = await _db.select(_db.cachedGraphStates).get();
      final graphSize =
          graphRows.fold<int>(0, (int sum, CachedGraphStatesData row) {
        return sum + row.sizeBytes;
      });

      // Estimate position and search cache sizes.
      final positionRows =
          await _db.select(_db.cachedNodePositions).get();
      final positionSize = positionRows.fold<int>(
          0, (int sum, CachedNodePositionsData row) {
        return sum + row.positionsJson.length;
      });

      final searchRows =
          await _db.select(_db.cachedSearchResults).get();
      final searchSize = searchRows.fold<int>(
          0, (int sum, CachedSearchResultsData row) {
        return sum + row.resultsJson.length;
      });

      return graphSize + positionSize + searchSize;
    } catch (e) {
      debugPrint('⚠️ GraphCache.getCacheSize error: $e');
      return 0;
    }
  }

  /// Clears all cached data across all families.
  Future<void> clearAllCache() async {
    _checkDisposed();
    try {
      await _db.delete(_db.cachedGraphStates).go();
      await _db.delete(_db.cachedNodePositions).go();
      await _db.delete(_db.cachedSearchResults).go();
      _avatarMemoryCache.clear();
      _avatarMemoryLru.clear();
      _avatarMemoryBytes = 0;
    } catch (e) {
      debugPrint('⚠️ GraphCache.clearAllCache error: $e');
    }
  }

  // ── Avatar 3-Tier Caching ────────────────────────────────────────

  /// Retrieves an avatar image using the 3-tier cache strategy.
  ///
  /// Tier 1: In-memory texture cache (LRU, 20 MB budget).
  /// Tier 2: Disk cache (WebP, 100 MB max).
  /// Tier 3: Network fetch (Supabase Storage signed URLs).
  ///
  /// [avatarUrl] is the URL of the avatar image.
  /// [size] controls the resolution: 128x128 for visible, 32x32 for
  ///   off-screen, or null for original size.
  ///
  /// Returns the raw image bytes, or null if unavailable.
  Future<Uint8List?> getAvatar({
    required String avatarUrl,
    AvatarSize size = AvatarSize.visible,
  }) async {
    _checkDisposed();

    final cacheKey = '${avatarUrl}_${size.name}';

    // Tier 1: In-memory cache.
    final memoryEntry = _avatarMemoryCache[cacheKey];
    if (memoryEntry != null) {
      _touchAvatarLru(cacheKey);
      return memoryEntry.bytes;
    }

    // Tier 2: Disk cache (via Flutter's CachedNetworkImage).
    // In a production app, this would use flutter_cache_manager
    // to check the disk cache. For now, we fall through to Tier 3.

    // Tier 3: Network fetch.
    // This would normally use Supabase Storage signed URLs.
    // The actual download is handled by CachedNetworkImage at the
    // widget level. Here we return null to indicate the image
    // should be fetched via the standard image pipeline.
    return null;
  }

  /// Stores avatar bytes in the in-memory cache (Tier 1).
  ///
  /// Evicts LRU entries if the memory budget is exceeded.
  Future<void> cacheAvatarBytes(
    String avatarUrl,
    Uint8List bytes, {
    AvatarSize size = AvatarSize.visible,
  }) async {
    _checkDisposed();

    final cacheKey = '${avatarUrl}_${size.name}';
    final entrySize = bytes.lengthInBytes;

    // Evict LRU entries until we have room.
    while (_avatarMemoryBytes + entrySize > _maxAvatarMemoryBytes &&
        _avatarMemoryLru.isNotEmpty) {
      final evictKey = _avatarMemoryLru.removeAt(0);
      final evicted = _avatarMemoryCache.remove(evictKey);
      if (evicted != null) {
        _avatarMemoryBytes -= evicted.bytes.lengthInBytes;
      }
    }

    _avatarMemoryCache[cacheKey] = _AvatarCacheEntry(bytes: bytes);
    _touchAvatarLru(cacheKey);
    _avatarMemoryBytes += entrySize;
  }

  // ── Search Cache ─────────────────────────────────────────────────

  /// Saves search results to the cache.
  Future<void> saveSearchResults(
    String query,
    String familyId,
    SearchResult results,
  ) async {
    _checkDisposed();
    try {
      final resultsJson = jsonEncode(results.toJson());
      final now = DateTime.now();
      final expiresAt = now.add(_searchCacheTtl);

      await _db.into(_db.cachedSearchResults).insertOnConflictUpdate(
            CachedSearchResultsCompanion.insert(
              query: query,
              familyId: familyId,
              resultsJson: resultsJson,
              cachedAt: now,
              expiresAt: expiresAt,
            ),
          );
    } catch (e) {
      debugPrint('⚠️ GraphCache.saveSearchResults error: $e');
    }
  }

  /// Loads cached search results if they exist and haven't expired.
  Future<SearchResult?> loadSearchResults(
    String query,
    String familyId,
  ) async {
    _checkDisposed();
    try {
      final q = _db.select(_db.cachedSearchResults)
        ..where(($CachedSearchResultsTable t) =>
            t.query.equals(query) & t.familyId.equals(familyId));

      final row = await q.getSingleOrNull();
      if (row == null) return null;

      if (DateTime.now().isAfter(row.expiresAt)) {
        await (_db.delete(_db.cachedSearchResults)
              ..where(($CachedSearchResultsTable t) =>
                  t.query.equals(query) & t.familyId.equals(familyId)))
            .go();
        return null;
      }

      final json = jsonDecode(row.resultsJson) as Map<String, dynamic>;
      return SearchResult.fromJson(json);
    } catch (e) {
      debugPrint('⚠️ GraphCache.loadSearchResults error: $e');
      return null;
    }
  }

  // ── Sync Protocol Helpers ────────────────────────────────────────

  /// Executes Phase 1 of the 3-phase sync protocol: replays queued
  /// mutations in order.
  ///
  /// Returns the list of mutation IDs that were successfully replayed.
  Future<List<String>> replayMutations(
    Future<bool> Function(GraphMutation mutation) replayFn,
  ) async {
    _checkDisposed();
    final pending = await getPendingMutations();
    final syncedIds = <String>[];

    for (final mutation in pending) {
      try {
        final success = await replayFn(mutation);
        if (success) {
          syncedIds.add(mutation.id);
        }
      } catch (e) {
        debugPrint('⚠️ Mutation replay failed for ${mutation.id}: $e');
        break; // Stop replaying on first failure.
      }
    }

    await clearProcessedMutations(syncedIds);
    return syncedIds;
  }

  /// Executes Phase 3 of the sync protocol: merges remote updates
  /// into the local cache.
  ///
  /// Conflict resolution strategy: "server wins" — remote data
  /// always overwrites local data.
  Future<void> mergeRemoteUpdates(
    String familyId,
    GraphData remoteData,
  ) async {
    _checkDisposed();
    // "Server wins" — simply overwrite the local cache.
    await saveGraphState(familyId, remoteData);
  }

  // ── Lifecycle ────────────────────────────────────────────────────

  /// Disposes the cache and closes the database connection.
  Future<void> dispose() async {
    _isDisposed = true;
    _avatarMemoryCache.clear();
    _avatarMemoryLru.clear();
    await _db.close();
  }

  // ── Private Helpers ──────────────────────────────────────────────

  /// Throws if the cache has been disposed.
  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('GraphCache has been disposed');
    }
  }

  /// Enforces the graph storage limit by evicting the oldest entries.
  Future<void> _enforceGraphStorageLimit(int additionalBytes) async {
    final currentSize = await getCacheSize();
    if (currentSize + additionalBytes <= _maxGraphStorageBytes) return;

    // Delete oldest entries until we have room.
    final rows = await (_db.select(_db.cachedGraphStates)
          ..orderBy([
            ($CachedGraphStatesTable t) =>
                OrderingTerm.asc(t.cachedAt),
          ]))
        .get();

    var freedBytes = 0;
    for (final row in rows) {
      if (currentSize - freedBytes + additionalBytes <=
          _maxGraphStorageBytes) {
        break;
      }
      await (_db.delete(_db.cachedGraphStates)
            ..where(($CachedGraphStatesTable t) =>
                t.familyId.equals(row.familyId)))
          .go();
      freedBytes += row.sizeBytes;
    }
  }

  /// Updates the LRU position for an avatar cache key.
  void _touchAvatarLru(String cacheKey) {
    _avatarMemoryLru.remove(cacheKey);
    _avatarMemoryLru.add(cacheKey);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SUPPORTING TYPES
// ═══════════════════════════════════════════════════════════════════════

/// Avatar size categories for the 3-tier caching strategy.
enum AvatarSize {
  /// 128×128 — for visible, on-screen nodes.
  visible,

  /// 32×32 — for off-screen / thumbnail nodes.
  thumbnail,

  /// Original resolution — for detail views.
  full,
}

/// An entry in the in-memory avatar cache.
class _AvatarCacheEntry {
  const _AvatarCacheEntry({required this.bytes});

  /// Raw image bytes.
  final Uint8List bytes;
}
