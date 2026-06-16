// lib/features/family/presentation/providers/family_graph_provider.dart
//
// DAXELO KINREL — Family Graph Providers
//
// Riverpod providers for the family graph feature:
//   1. familyGraphProvider(familyId) — fetches flat graph data via Supabase
//   2. graphLayoutProvider(familyId) — computes layout in an isolate
//   3. selectedEdgeProvider — tracks selected edge
//   4. selectedNodeProvider — tracks selected node
//   5. graphZoomProvider — tracks zoom level
//   6. graphRealtimeProvider(familyId) — Supabase Realtime invalidation
//
// DATA FETCHING STRATEGY (V6.0):
//   - Direct Supabase query (Person + Relationship tables) is the PRIMARY source
//     because it ALWAYS returns all non-deleted persons in the family, regardless
//     of relationship connectivity or p_max_degree limits.
//   - The RPC `get_family_graph` is used as a SUPPLEMENTARY source for richer
//     data (kinship labels, computed relationships), but ONLY if it returns
//     the same or more persons than the direct query.
//   - This ensures newly added members are ALWAYS visible, even if they
//     don't have relationships connecting them to the anchor yet.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/isar_database.dart';
import '../../../../core/services/graph_layout_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../widgets/graph_canvas_widget.dart';

/// Provider for the Drift database instance.
/// Used by [FamilyGraphNotifier] to persist graph data locally.
final driftDatabaseProvider = Provider<AppDatabase?>((ref) {
  try {
    if (IsarDatabase.isInitialized) {
      return IsarDatabase.instance;
    }
  } catch (e) {
    debugPrint('[driftDatabaseProvider] Error: $e');
  }
  return null;
});

// ═══════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// Flat graph data as received from the Supabase RPC.
///
/// The RPC `get_family_graph` returns { nodes, edges, isTruncated, totalCount }.
/// We map nodes → persons and edges → relationships to keep the rest of the
/// app (GraphCanvasWidget, graphLayoutProvider) unchanged.
class FlatGraphResult {
  /// Raw person data mapped from RPC nodes.
  final List<Map<String, dynamic>> persons;

  /// Raw relationship data mapped from RPC edges.
  final List<Map<String, dynamic>> relationships;

  /// Whether the response was truncated (server capped at 5000 nodes).
  final bool isTruncated;

  /// Total count of persons in the family (may exceed [persons.length]
  /// when [isTruncated] is true).
  final int? totalCount;

  const FlatGraphResult({
    required this.persons,
    required this.relationships,
    this.isTruncated = false,
    this.totalCount,
  });

  /// Parses the Supabase RPC JSONB response into a [FlatGraphResult].
  ///
  /// RPC node shape:  { id, name, username, avatarUrl, gender,
  ///                    generationIndex, isAnchor, isDeceased, visibility }
  /// RPC edge shape:  { id, sourceId, targetId, relationshipKey, isPrivate }
  factory FlatGraphResult.fromRpc(Map<String, dynamic> json) {
    final rawNodes = (json['nodes'] as List?) ?? [];
    final rawEdges = (json['edges'] as List?) ?? [];

    // Map RPC node keys → legacy API keys expected by the rest of the app
    final persons = rawNodes.map((dynamic n) {
      final node = n as Map<String, dynamic>;
      return <String, dynamic>{
        'id': node['id'],
        'name': node['name'],
        'gender': node['gender'],
        'generationIndex': node['generationIndex'] ?? 0,
        'isAnchor': node['isAnchor'] ?? false,
        'photoUrl': node['avatarUrl'],
        'isDeceased': node['isDeceased'] ?? false,
        'visibility': node['visibility'],
        'username': node['username'],
      };
    }).toList();

    // Map RPC edge keys → legacy API keys
    final relationships = rawEdges.map((dynamic e) {
      final edge = e as Map<String, dynamic>;
      return <String, dynamic>{
        'id': edge['id'],
        'fromPersonId': edge['sourceId'],
        'toPersonId': edge['targetId'],
        'relationshipKey': edge['relationshipKey'],
        'isPrivate': edge['isPrivate'] ?? false,
      };
    }).toList();

    return FlatGraphResult(
      persons: persons,
      relationships: relationships,
      isTruncated: json['isTruncated'] as bool? ?? false,
      totalCount: json['totalCount'] as int?,
    );
  }

  /// Convenience: parse raw person maps into typed [PersonData] objects.
  List<PersonData> toPersonDataList() {
    return persons.map((p) {
      return PersonData(
        id: p['id'] as String? ?? '',
        name: p['name'] as String? ?? '',
        gender: p['gender'] as String?,
        generationIndex: p['generationIndex'] as int? ?? 0,
        isAnchor: p['isAnchor'] as bool? ?? false,
        photoUrl: p['photoUrl'] as String?,
        isDeceased: p['isDeceased'] as bool? ?? false,
        kinshipCategory: p['kinshipCategory'] as String?,
        computedKinship: p['computedKinship'] as String?,
      );
    }).toList();
  }

  /// Convenience: parse raw relationship maps into typed [RelationshipData].
  List<RelationshipData> toRelationshipDataList() {
    return relationships.map((r) {
      return RelationshipData(
        id: r['id'] as String? ?? '',
        fromPersonId: r['fromPersonId'] as String? ?? '',
        toPersonId: r['toPersonId'] as String? ?? '',
        relationshipKey: r['relationshipKey'] as String? ?? '',
        displayLabel: r['displayLabel'] as String?,
      );
    }).toList();
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ISOLATE LAYOUT PARAMS (for compute())
// ═══════════════════════════════════════════════════════════════════════

/// Parameter bundle passed to the isolate for layout computation.
class _LayoutComputeParams {
  final List<GraphPerson> persons;
  final List<GraphRelationship> relationships;
  final String? anchorPersonId;
  final bool compactMode;

  const _LayoutComputeParams({
    required this.persons,
    required this.relationships,
    this.anchorPersonId,
    this.compactMode = false,
  });
}

/// Top-level function executed inside the isolate via [compute].
GraphLayoutResult _runLayoutInIsolate(_LayoutComputeParams params) {
  final service = GraphLayoutService();
  return service.computeLayout(
    persons: params.persons,
    relationships: params.relationships,
    anchorPersonId: params.anchorPersonId,
    compactMode: params.compactMode,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER: resolve anchor member ID for a family
// ═══════════════════════════════════════════════════════════════════════

/// Looks up the anchor person ID for [familyId] from the Person table.
/// Falls back to the first person in the family if no anchor is set.
Future<String?> _resolveAnchorMemberId(
  SupabaseClient client,
  String familyId,
) async {
  try {
    // Try anchor person first (non-deleted)
    final anchor = await client
        .from('Person')
        .select('id')
        .eq('familyId', familyId)
        .eq('isAnchor', true)
        .isFilter('deletedAt', null)
        .maybeSingle();

    if (anchor != null) return anchor['id'] as String?;

    // Fallback: first non-deleted person in family
    final first = await client
        .from('Person')
        .select('id')
        .eq('familyId', familyId)
        .isFilter('deletedAt', null)
        .order('createdAt')
        .limit(1)
        .maybeSingle();

    return first?['id'] as String?;
  } catch (e) {
    debugPrint('[_resolveAnchorMemberId] Error: $e');
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 1. FAMILY GRAPH PROVIDER — AsyncNotifierProvider.family
// ═══════════════════════════════════════════════════════════════════════

/// AsyncNotifier that fetches and caches flat graph data for a family.
///
/// Features:
///   - Fetches from Supabase RPC `get_family_graph` directly (no server hop)
///   - Caches the last successful result in memory
///   - On error, returns cached data if available (graceful degradation)
///   - Supports refresh via [refreshGraph]
class FamilyGraphNotifier extends FamilyAsyncNotifier<FlatGraphResult, String> {
  /// In-memory cache keyed by familyId so we can fallback on error.
  static final Map<String, FlatGraphResult> _cache = {};

  @override
  Future<FlatGraphResult> build(String familyId) async {
    // Invalidate the layout when graph data is (re)fetched
    ref.invalidate(graphLayoutProvider(familyId));

    // Guard against empty familyId
    if (familyId.isEmpty) {
      debugPrint('[FamilyGraphNotifier] build() called with empty familyId, returning empty result');
      return const FlatGraphResult(persons: [], relationships: []);
    }

    debugPrint('[FamilyGraphNotifier] build() called for familyId=$familyId');
    final result = await _fetchGraph(familyId);

    // Persist fetched data to Drift for offline access and reactive streams
    await _syncToDrift(familyId, result);

    debugPrint('[FamilyGraphNotifier] Loaded ${result.persons.length} persons, '
        '${result.relationships.length} relationships for $familyId');
    return result;
  }

  /// Persists fetched graph data into the local Drift database so that
  /// Drift watch streams emit and the graph re-renders reactively.
  Future<void> _syncToDrift(String familyId, FlatGraphResult result) async {
    try {
      final db = ref.read(driftDatabaseProvider);
      if (db == null) return;

      final persons = result.persons.map((p) {
        return CachedPersonsCompanion(
          id: Value(p['id'] as String? ?? ''),
          familyId: Value(familyId),
          name: Value(p['name'] as String? ?? ''),
          data: Value(p.toString()),
          cachedAt: Value(DateTime.now()),
        );
      }).toList();

      if (persons.isNotEmpty) {
        await db.upsertPersons(persons);
        debugPrint('[FamilyGraphNotifier] Synced ${persons.length} persons to Drift for $familyId');
      }

      final relationships = result.relationships.map((r) {
        return CachedRelationshipsCompanion(
          id: Value(r['id'] as String? ?? ''),
          familyId: Value(familyId),
          fromId: Value(r['fromPersonId'] as String? ?? ''),
          toId: Value(r['toPersonId'] as String? ?? ''),
          relationshipType: Value(r['relationshipKey'] as String? ?? ''),
          data: Value(r.toString()),
          cachedAt: Value(DateTime.now()),
        );
      }).toList();

      if (relationships.isNotEmpty) {
        await db.upsertRelationships(relationships);
        debugPrint('[FamilyGraphNotifier] Synced ${relationships.length} relationships to Drift for $familyId');
      }
    } catch (e) {
      // Silently fail — Drift sync is best-effort, Supabase is the source of truth
      debugPrint('[FamilyGraphNotifier] Drift sync failed: $e');
    }
  }

  // ── Data Fetching ──────────────────────────────────────────────────

  Future<FlatGraphResult> _fetchGraph(String familyId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      throw Exception('Supabase client not available');
    }

    try {
      // ── Step 1: Always fetch direct query first ──
      // Direct query is the source of truth — it always returns ALL
      // non-deleted persons in the family, regardless of relationships
      // or connectivity. The RPC `get_family_graph` may return incomplete
      // data (e.g., only the anchor node) if the person is not connected
      // via relationships within p_max_degree. By always using direct
      // query as the primary source, we guarantee all members are visible.
      final directResult = await _fetchGraphDirectQuery(client, familyId);

      if (directResult.persons.isEmpty) {
        debugPrint('[FamilyGraphNotifier] No members found in family $familyId');
        return const FlatGraphResult(persons: [], relationships: []);
      }

      // ── Step 2: Try RPC as a supplementary source for richer data ──
      // The RPC may provide enriched data (kinship labels, computed
      // relationships, etc.) that the direct query doesn't have. If the
      // RPC returns a complete result (same or more persons than direct
      // query), prefer it for the richer data. Otherwise, use direct query.
      try {
        final memberId = await _resolveAnchorMemberId(client, familyId);
        if (memberId != null) {
          final response = await client.rpc(
            'get_family_graph',
            params: <String, dynamic>{
              'p_member_id': memberId,
              'p_max_degree': 6,
              'p_include_hidden': false,
            },
          ).timeout(const Duration(seconds: 15));

          final data = response as Map<String, dynamic>?;
          if (data != null) {
            final rpcResult = FlatGraphResult.fromRpc(data);

            // Use RPC result ONLY if it returns all (or more) persons
            // than the direct query. If it returns fewer, it means the
            // RPC is missing disconnected members — use direct query instead.
            if (rpcResult.persons.length >= directResult.persons.length) {
              _cache[familyId] = rpcResult;
              debugPrint(
                '[FamilyGraphNotifier] RPC: Loaded ${rpcResult.persons.length} persons, '
                '${rpcResult.relationships.length} relationships for $familyId',
              );
              return rpcResult;
            }

            // RPC returned fewer persons — log and use direct query
            debugPrint(
              '[FamilyGraphNotifier] RPC returned ${rpcResult.persons.length} persons '
              'but direct query found ${directResult.persons.length}. '
              'Using direct query for completeness.',
            );
          }
        }
      } catch (rpcError) {
        debugPrint('[FamilyGraphNotifier] RPC failed: $rpcError, using direct query');
      }

      // ── Step 3: Return direct query result ──
      // This is always the fallback and the primary source.
      _cache[familyId] = directResult;
      return directResult;
    } on PostgrestException catch (e) {
      debugPrint('[FamilyGraphNotifier] Supabase error: ${e.message}');
      return _fallbackOrThrow(familyId, e);
    } on TimeoutException catch (e) {
      debugPrint('[FamilyGraphNotifier] Timeout: $e');
      return _fallbackOrThrow(familyId, e);
    } catch (e) {
      debugPrint('[FamilyGraphNotifier] Unexpected error: $e');
      return _fallbackOrThrow(familyId, e);
    }
  }

  /// Fetches graph data by directly querying Person and Relationship tables.
  /// Used as a fallback when the `get_family_graph` RPC fails or returns
  /// incomplete results.
  Future<FlatGraphResult> _fetchGraphDirectQuery(
    SupabaseClient client,
    String familyId,
  ) async {
    try {
      // Query all non-deleted persons in this family
      final rawPersons = await client
          .from('Person')
          .select('id, name, gender, "generationIndex", "isAnchor", "photoUrl", '
              '"isDeceased", visibility, username, "familyId"')
          .eq('familyId', familyId)
          .isFilter('deletedAt', null)
          .timeout(const Duration(seconds: 15));

      // Query all relationships in this family
      final rawRelationships = await client
          .from('Relationship')
          .select('id, "fromPersonId", "toPersonId", "relationshipKey", is_private, "familyId"')
          .eq('familyId', familyId)
          .timeout(const Duration(seconds: 15));

      // Map to the same format as FlatGraphResult.fromRpc
      final persons = rawPersons.map((dynamic n) {
        final node = n as Map<String, dynamic>;
        return <String, dynamic>{
          'id': node['id'],
          'name': node['name'],
          'gender': node['gender'],
          'generationIndex': node['generationIndex'] ?? 0,
          'isAnchor': node['isAnchor'] ?? false,
          'photoUrl': node['photoUrl'],
          'isDeceased': node['isDeceased'] ?? false,
          'visibility': node['visibility'],
          'username': node['username'],
        };
      }).toList();

      final relationships = rawRelationships.map((dynamic e) {
        final edge = e as Map<String, dynamic>;
        return <String, dynamic>{
          'id': edge['id'],
          'fromPersonId': edge['fromPersonId'],
          'toPersonId': edge['toPersonId'],
          'relationshipKey': edge['relationshipKey'],
          'isPrivate': edge['is_private'] ?? false,
        };
      }).toList();

      final result = FlatGraphResult(
        persons: persons,
        relationships: relationships,
        isTruncated: false,
        totalCount: persons.length,
      );

      _cache[familyId] = result;

      debugPrint(
        '[FamilyGraphNotifier] Direct query: Loaded ${result.persons.length} persons, '
        '${result.relationships.length} relationships for $familyId',
      );

      return result;
    } catch (e) {
      debugPrint('[FamilyGraphNotifier] Direct query error: $e');
      // If even the direct query fails, try cache
      final cached = _cache[familyId];
      if (cached != null) {
        debugPrint('[FamilyGraphNotifier] Using cached data for $familyId');
        return cached;
      }
      rethrow;
    }
  }

  /// Returns cached data if available, otherwise rethrows [error].
  FlatGraphResult _fallbackOrThrow(String familyId, Object error) {
    final cached = _cache[familyId];
    if (cached != null) {
      debugPrint('[FamilyGraphNotifier] Using cached data for $familyId');
      return cached;
    }
    throw error;
  }

  // ── Public Methods ─────────────────────────────────────────────────

  /// Refreshes the graph data by invalidating and re-fetching.
  Future<void> refreshGraph() async {
    ref.invalidateSelf();
  }
}

/// Family-scoped provider that fetches flat graph data for a given family.
///
/// Usage:
/// ```dart
/// final asyncResult = ref.watch(familyGraphProvider(familyId));
/// asyncResult.when(
///   data: (result) => /* use result.persons, result.relationships */,
///   loading: () => /* show shimmer */,
///   error: (e, st) => /* show error with retry */,
/// );
/// ```
final familyGraphProvider =
    AsyncNotifierProvider.family<FamilyGraphNotifier, FlatGraphResult, String>(
  FamilyGraphNotifier.new,
);

// ═══════════════════════════════════════════════════════════════════════
// 2. GRAPH LAYOUT PROVIDER — FutureProvider.family
// ═══════════════════════════════════════════════════════════════════════

/// Computes the graph layout for a given family in a background isolate.
final graphLayoutProvider =
    FutureProvider.family<GraphLayoutResult, String>((ref, familyId) async {
  final graphAsync = ref.watch(familyGraphProvider(familyId));

  final graphData = graphAsync.valueOrNull;
  if (graphData == null) {
    return const GraphLayoutResult(
      positions: {},
      canvasWidth: 0,
      canvasHeight: 0,
    );
  }

  final persons = graphData.toPersonDataList();
  final relationships = graphData.toRelationshipDataList();

  if (persons.isEmpty) {
    return const GraphLayoutResult(
      positions: {},
      canvasWidth: 0,
      canvasHeight: 0,
    );
  }

  final graphPersons = persons.map((p) => p.toGraphPerson()).toList();
  final graphRelationships =
      relationships.map((r) => r.toGraphRelationship()).toList();

  final anchorPerson = persons.firstWhere(
    (p) => p.isAnchor,
    orElse: () => persons.first,
  );

  final compactMode = persons.length > 50;

  final params = _LayoutComputeParams(
    persons: graphPersons,
    relationships: graphRelationships,
    anchorPersonId: anchorPerson.id,
    compactMode: compactMode,
  );

  try {
    return await compute(_runLayoutInIsolate, params);
  } catch (e) {
    debugPrint('[graphLayoutProvider] Isolate compute failed, '
        'falling back to main thread: $e');
    final service = GraphLayoutService();
    return service.computeLayout(
      persons: graphPersons,
      relationships: graphRelationships,
      anchorPersonId: anchorPerson.id,
      compactMode: compactMode,
    );
  }
});

// ═══════════════════════════════════════════════════════════════════════
// 3. SELECTED EDGE PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Tracks the currently selected relationship edge ID.
final selectedEdgeProvider = StateProvider<String?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════
// 4. SELECTED NODE PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Tracks the currently selected person node ID.
final selectedNodeProvider = StateProvider<String?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════
// 5. GRAPH ZOOM PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Tracks the current zoom level of the graph viewer.
final graphZoomProvider = StateProvider<double>((ref) => 1.0);

// ═══════════════════════════════════════════════════════════════════════
// 5b. HIGHLIGHTED GENERATION PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Tracks the currently highlighted generation index for the graph canvas.
final highlightedGenerationProvider = StateProvider<int?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════
// 6. GRAPH REALTIME PROVIDER — Supabase Realtime
// ═══════════════════════════════════════════════════════════════════════

/// Listens to Supabase Realtime changes on Person and Relationship tables
/// for this family and invalidates [familyGraphProvider] when data changes.
///
/// Replaces the Socket.IO-based graphRealtimeProvider since we no longer
/// depend on the Render server.
final graphRealtimeProvider =
    Provider.family<void, String>((ref, familyId) {
  final client = ref.read(supabaseProvider);
  if (client == null) return;

  DateTime? _lastInvalidation;

  void invalidateIfNeeded() {
    final now = DateTime.now();
    if (_lastInvalidation != null &&
        now.difference(_lastInvalidation!) < const Duration(seconds: 2)) {
      return;
    }
    _lastInvalidation = now;
    debugPrint('[graphRealtimeProvider] Invalidating graph for $familyId');
    ref.invalidate(familyGraphProvider(familyId));
  }

  // Subscribe to Relationship changes for this family
  final channel = client
      .channel('graph_realtime_$familyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'Relationship',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'familyId',
          value: familyId,
        ),
        callback: (_) => invalidateIfNeeded(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'Person',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'familyId',
          value: familyId,
        ),
        callback: (_) => invalidateIfNeeded(),
      )
      .subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
  });
});

// ═══════════════════════════════════════════════════════════════════════
// 7. GRAPH DRIFT STREAM PROVIDER — Reactive local DB watcher
// ═══════════════════════════════════════════════════════════════════════

/// StreamProvider that watches cached persons for a specific family from
/// the Drift database. This is a reactive stream that emits whenever the
/// local cache changes — including after [_syncToDrift] writes, optimistic
/// actions, or background sync operations.
///
/// The graph screen can watch this provider as a supplementary data source
/// to ensure members are never invisible even if Supabase fetch is slow.
///
/// Usage:
/// ```dart
/// final driftMembersAsync = ref.watch(graphDriftMembersProvider(familyId));
/// ```
final graphDriftMembersProvider =
    StreamProvider.family<List<CachedPerson>, String>((ref, familyId) async* {
  final db = ref.read(driftDatabaseProvider);
  if (db == null) {
    yield [];
    return;
  }

  yield* db.watchPersonsByFamily(familyId);
});

/// StreamProvider that watches cached relationships for a specific family.
final graphDriftRelationshipsProvider =
    StreamProvider.family<List<CachedRelationship>, String>(
        (ref, familyId) async* {
  final db = ref.read(driftDatabaseProvider);
  if (db == null) {
    yield [];
    return;
  }

  yield* db.watchRelationshipsByFamily(familyId);
});
