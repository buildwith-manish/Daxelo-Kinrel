// lib/graph/data/graph_cache.dart
//
// DAXELO KINREL — Graph Cache (V2.1 Data Layer)
//
// Offline cache with SharedPreferences. Serializes graph state to local
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
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'family_graph_repository.dart';

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

/// Offline cache for graph data with SharedPreferences persistence.
///
/// Provides:
/// - Graph state caching (TTL 30 min)
/// - Node position caching (session duration)
/// - Search index caching (TTL 60 min)
/// - Mutation queue (100 mutations max, persistent until synced)
/// - Avatar 3-tier caching (in-memory -> disk -> network)
///
/// 3-Phase Sync Protocol:
/// 1. Replay queued mutations in order
/// 2. Fetch latest graph state from Supabase
/// 3. Merge remote updates into local cache, trigger UI refresh
///
/// Conflict resolution: "server wins"
class GraphCache {
  /// Creates a graph cache using SharedPreferences for storage.
  ///
  /// [maxMutationQueueSize] is the maximum number of pending mutations
  ///   (default: 100).
  /// [graphStateTtl] is the time-to-live for graph state cache
  ///   (default: 30 minutes).
  /// [searchCacheTtl] is the time-to-live for search cache
  ///   (default: 60 minutes).
  GraphCache({
    int maxMutationQueueSize = 100,
    Duration graphStateTtl = const Duration(minutes: 30),
    Duration searchCacheTtl = const Duration(minutes: 60),
  })  : _maxMutationQueueSize = maxMutationQueueSize,
        _graphStateTtl = graphStateTtl,
        _searchCacheTtl = searchCacheTtl;

  final int _maxMutationQueueSize;
  final Duration _graphStateTtl;
  final Duration _searchCacheTtl;

  /// In-memory texture cache for avatars (Tier 1).
  /// Maps avatar URL -> raw image bytes.
  final Map<String, _AvatarCacheEntry> _avatarMemoryCache =
      <String, _AvatarCacheEntry>{};

  /// LRU order for avatar memory cache eviction.
  final List<String> _avatarMemoryLru = <String>[];

  /// Maximum in-memory avatar cache size (20 MB).
  static const int _maxAvatarMemoryBytes = 20 * 1024 * 1024;

  int _avatarMemoryBytes = 0;

  bool _isDisposed = false;

  /// SharedPreferences key prefix for graph state cache.
  static const String _graphStatePrefix = 'kinrel_graph_state_';

  /// SharedPreferences key prefix for position cache.
  static const String _positionPrefix = 'kinrel_graph_pos_';

  /// SharedPreferences key prefix for search cache.
  static const String _searchPrefix = 'kinrel_graph_search_';

  /// SharedPreferences key for mutation queue.
  static const String _mutationQueueKey = 'kinrel_graph_mutations';

  /// SharedPreferences key for tracking all graph state family IDs.
  static const String _graphStateIndexKey = 'kinrel_graph_state_index';

  /// SharedPreferences key for tracking all position keys.
  static const String _positionIndexKey = 'kinrel_graph_pos_index';

  /// SharedPreferences key for tracking all search cache keys.
  static const String _searchIndexKey = 'kinrel_graph_search_index';

  // ── Graph State Cache ────────────────────────────────────────────

  /// Saves a graph state to the local cache.
  ///
  /// [familyId] identifies the family. [data] is the complete graph
  /// data to cache. The entry will expire after [_graphStateTtl].
  Future<void> saveGraphState(String familyId, GraphData data) async {
    _checkDisposed();
    try {
      final dataJson = data.toJson();
      final graphJson = jsonEncode(dataJson);
      final now = DateTime.now();
      final expiresAt = now.add(_graphStateTtl);

      final cacheEntry = jsonEncode(<String, dynamic>{
        'data': dataJson,
        'cachedAt': now.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'sizeBytes': graphJson.length,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_graphStatePrefix$familyId', cacheEntry);

      // Track the family ID in the index for cache management.
      await _addToIndex(prefs, _graphStateIndexKey, familyId);
    } catch (e) {
      debugPrint('GraphCache.saveGraphState error: $e');
    }
  }

  /// Loads a cached graph state if it exists and has not expired.
  ///
  /// Returns null if no cached state exists or if it has expired.
  Future<GraphData?> loadGraphState(String familyId) async {
    _checkDisposed();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_graphStatePrefix$familyId');
      if (raw == null) return null;

      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final expiresAtStr = entry['expiresAt'] as String?;
      if (expiresAtStr != null) {
        final expiresAt = DateTime.parse(expiresAtStr);
        if (DateTime.now().isAfter(expiresAt)) {
          await prefs.remove('$_graphStatePrefix$familyId');
          await _removeFromIndex(prefs, _graphStateIndexKey, familyId);
          return null;
        }
      }

      final dataJson = entry['data'] as Map<String, dynamic>;
      return GraphData.fromJson(dataJson);
    } catch (e) {
      debugPrint('GraphCache.loadGraphState error: $e');
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
      // Serialize positions as a flat list of {id, x, y} objects.
      final positionsList = positions.entries
          .map((MapEntry<String, Offset> e) => <String, dynamic>{
                'id': e.key,
                'x': e.value.dx,
                'y': e.value.dy,
              })
          .toList();

      final cacheKey = '${familyId}_$disclosureLevel';
      final cacheEntry = jsonEncode(<String, dynamic>{
        'positions': positionsList,
        'disclosureLevel': disclosureLevel,
        'cachedAt': DateTime.now().toIso8601String(),
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_positionPrefix$cacheKey', cacheEntry);

      // Track the position key in the index for cache management.
      await _addToIndex(prefs, _positionIndexKey, cacheKey);
    } catch (e) {
      debugPrint('GraphCache.savePositions error: $e');
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
      final cacheKey = '${familyId}_$disclosureLevel';
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_positionPrefix$cacheKey');
      if (raw == null) return null;

      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final positionsList = entry['positions'] as List<dynamic>;

      final positions = <String, Offset>{};
      for (final item in positionsList) {
        final map = item as Map<String, dynamic>;
        final id = map['id'] as String;
        final x = (map['x'] as num).toDouble();
        final y = (map['y'] as num).toDouble();
        positions[id] = Offset(x, y);
      }
      return positions;
    } catch (e) {
      debugPrint('GraphCache.loadPositions error: $e');
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
      final prefs = await SharedPreferences.getInstance();
      final mutations = await _readMutationList(prefs);

      // Enforce queue size limit — remove the oldest mutation.
      if (mutations.length >= _maxMutationQueueSize) {
        mutations.removeAt(0);
      }

      mutations.add(mutation.toJson());
      await prefs.setString(_mutationQueueKey, jsonEncode(mutations));
    } catch (e) {
      debugPrint('GraphCache.queueMutation error: $e');
    }
  }

  /// Returns all pending (unsynced) mutations in creation order.
  Future<List<GraphMutation>> getPendingMutations() async {
    _checkDisposed();
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = await _readMutationList(prefs);

      return rawList.map((Map<String, dynamic> json) {
        return GraphMutation.fromJson(json);
      }).toList();
    } catch (e) {
      debugPrint('GraphCache.getPendingMutations error: $e');
      return <GraphMutation>[];
    }
  }

  /// Removes mutations that have been successfully synced.
  ///
  /// [mutationIds] is the list of mutation IDs to remove.
  Future<void> clearProcessedMutations(List<String> mutationIds) async {
    _checkDisposed();
    try {
      final prefs = await SharedPreferences.getInstance();
      final mutations = await _readMutationList(prefs);

      final idSet = mutationIds.toSet();
      mutations.removeWhere(
          (Map<String, dynamic> m) => idSet.contains(m['id']));

      await prefs.setString(_mutationQueueKey, jsonEncode(mutations));
    } catch (e) {
      debugPrint('GraphCache.clearProcessedMutations error: $e');
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
      final prefs = await SharedPreferences.getInstance();

      // Remove graph state.
      await prefs.remove('$_graphStatePrefix$familyId');
      await _removeFromIndex(prefs, _graphStateIndexKey, familyId);

      // Remove all position entries for this family.
      final posIndex = await _readIndex(prefs, _positionIndexKey);
      for (final key in posIndex) {
        if (key.startsWith('$familyId\_')) {
          await prefs.remove('$_positionPrefix$key');
        }
      }
      posIndex.removeWhere((k) => k.startsWith('$familyId\_'));
      await _writeIndex(prefs, _positionIndexKey, posIndex);

      // Remove all search entries for this family.
      final searchIndex = await _readIndex(prefs, _searchIndexKey);
      for (final key in searchIndex) {
        if (key.startsWith('${familyId}_')) {
          await prefs.remove('$_searchPrefix$key');
        }
      }
      searchIndex.removeWhere((k) => k.startsWith('${familyId}_'));
      await _writeIndex(prefs, _searchIndexKey, searchIndex);
    } catch (e) {
      debugPrint('GraphCache.invalidateCache error: $e');
    }
  }

  /// Returns the total cache size in bytes.
  Future<int> getCacheSize() async {
    _checkDisposed();
    try {
      final prefs = SharedPreferences.getInstance();
      final prefsInstance = await prefs;
      var totalSize = 0;

      // Graph state entries.
      final graphIndex = await _readIndex(prefsInstance, _graphStateIndexKey);
      for (final familyId in graphIndex) {
        final raw = prefsInstance.getString('$_graphStatePrefix$familyId');
        if (raw != null) {
          final entry = jsonDecode(raw) as Map<String, dynamic>;
          totalSize += (entry['sizeBytes'] as int?) ?? raw.length;
        }
      }

      // Position entries.
      final posIndex = await _readIndex(prefsInstance, _positionIndexKey);
      for (final key in posIndex) {
        final raw = prefsInstance.getString('$_positionPrefix$key');
        if (raw != null) {
          totalSize += raw.length;
        }
      }

      // Search entries.
      final searchIndex = await _readIndex(prefsInstance, _searchIndexKey);
      for (final key in searchIndex) {
        final raw = prefsInstance.getString('$_searchPrefix$key');
        if (raw != null) {
          totalSize += raw.length;
        }
      }

      // Mutation queue.
      final mutationsRaw = prefsInstance.getString(_mutationQueueKey);
      if (mutationsRaw != null) {
        totalSize += mutationsRaw.length;
      }

      return totalSize;
    } catch (e) {
      debugPrint('GraphCache.getCacheSize error: $e');
      return 0;
    }
  }

  /// Clears all cached data across all families.
  Future<void> clearAllCache() async {
    _checkDisposed();
    try {
      final prefs = await SharedPreferences.getInstance();

      // Graph state entries.
      final graphIndex = await _readIndex(prefs, _graphStateIndexKey);
      for (final familyId in graphIndex) {
        await prefs.remove('$_graphStatePrefix$familyId');
      }
      await prefs.remove(_graphStateIndexKey);

      // Position entries.
      final posIndex = await _readIndex(prefs, _positionIndexKey);
      for (final key in posIndex) {
        await prefs.remove('$_positionPrefix$key');
      }
      await prefs.remove(_positionIndexKey);

      // Search entries.
      final searchIndex = await _readIndex(prefs, _searchIndexKey);
      for (final key in searchIndex) {
        await prefs.remove('$_searchPrefix$key');
      }
      await prefs.remove(_searchIndexKey);

      // Mutation queue.
      await prefs.remove(_mutationQueueKey);

      // Clear in-memory avatar cache.
      _avatarMemoryCache.clear();
      _avatarMemoryLru.clear();
      _avatarMemoryBytes = 0;
    } catch (e) {
      debugPrint('GraphCache.clearAllCache error: $e');
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

      final cacheEntry = jsonEncode(<String, dynamic>{
        'results': results.toJson(),
        'cachedAt': now.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'sizeBytes': resultsJson.length,
      });

      // Composite key: familyId_query to support per-family queries.
      final cacheKey = '${familyId}_$query';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_searchPrefix$cacheKey', cacheEntry);

      // Track the search key in the index for cache management.
      await _addToIndex(prefs, _searchIndexKey, cacheKey);
    } catch (e) {
      debugPrint('GraphCache.saveSearchResults error: $e');
    }
  }

  /// Loads cached search results if they exist and haven't expired.
  Future<SearchResult?> loadSearchResults(
    String query,
    String familyId,
  ) async {
    _checkDisposed();
    try {
      final cacheKey = '${familyId}_$query';
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_searchPrefix$cacheKey');
      if (raw == null) return null;

      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final expiresAtStr = entry['expiresAt'] as String?;
      if (expiresAtStr != null) {
        final expiresAt = DateTime.parse(expiresAtStr);
        if (DateTime.now().isAfter(expiresAt)) {
          await prefs.remove('$_searchPrefix$cacheKey');
          await _removeFromIndex(prefs, _searchIndexKey, cacheKey);
          return null;
        }
      }

      final resultsJson = entry['results'] as Map<String, dynamic>;
      return SearchResult.fromJson(resultsJson);
    } catch (e) {
      debugPrint('GraphCache.loadSearchResults error: $e');
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
        debugPrint('Mutation replay failed for ${mutation.id}: $e');
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

  /// Disposes the cache and releases resources.
  Future<void> dispose() async {
    _isDisposed = true;
    _avatarMemoryCache.clear();
    _avatarMemoryLru.clear();
    _avatarMemoryBytes = 0;
  }

  // ── Private Helpers ──────────────────────────────────────────────

  /// Throws if the cache has been disposed.
  void _checkDisposed() {
    if (_isDisposed) {
      throw StateError('GraphCache has been disposed');
    }
  }

  /// Updates the LRU position for an avatar cache key.
  void _touchAvatarLru(String cacheKey) {
    _avatarMemoryLru.remove(cacheKey);
    _avatarMemoryLru.add(cacheKey);
  }

  /// Reads the mutation list from SharedPreferences.
  Future<List<Map<String, dynamic>>> _readMutationList(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_mutationQueueKey);
    if (raw == null) return <Map<String, dynamic>>[];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .cast<Map<String, dynamic>>()
        .toList();
  }

  /// Reads an index set from SharedPreferences.
  Future<Set<String>> _readIndex(
    SharedPreferences prefs,
    String indexKey,
  ) async {
    final raw = prefs.getStringList(indexKey);
    return raw?.toSet() ?? <String>{};
  }

  /// Writes an index set to SharedPreferences.
  Future<void> _writeIndex(
    SharedPreferences prefs,
    String indexKey,
    Set<String> index,
  ) async {
    await prefs.setStringList(indexKey, index.toList());
  }

  /// Adds an entry to an index.
  Future<void> _addToIndex(
    SharedPreferences prefs,
    String indexKey,
    String entry,
  ) async {
    final index = await _readIndex(prefs, indexKey);
    index.add(entry);
    await _writeIndex(prefs, indexKey, index);
  }

  /// Removes an entry from an index.
  Future<void> _removeFromIndex(
    SharedPreferences prefs,
    String indexKey,
    String entry,
  ) async {
    final index = await _readIndex(prefs, indexKey);
    index.remove(entry);
    await _writeIndex(prefs, indexKey, index);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SUPPORTING TYPES
// ═══════════════════════════════════════════════════════════════════════

/// Avatar size categories for the 3-tier caching strategy.
enum AvatarSize {
  /// 128x128 — for visible, on-screen nodes.
  visible,

  /// 32x32 — for off-screen / thumbnail nodes.
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

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Riverpod provider for the [GraphCache] singleton.
final graphCacheProvider = Provider<GraphCache>((Ref ref) {
  final cache = GraphCache();
  ref.onDispose(() => cache.dispose());
  return cache;
});
