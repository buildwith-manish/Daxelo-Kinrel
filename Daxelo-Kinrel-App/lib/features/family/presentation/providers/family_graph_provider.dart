// lib/features/family/presentation/providers/family_graph_provider.dart
//
// DAXELO KINREL — Family Graph Providers
//
// Riverpod providers for the family graph feature:
//   1. familyGraphProvider(familyId) — fetches flat graph data via Supabase RPC
//   2. graphLayoutProvider(familyId) — computes layout in an isolate
//   3. selectedEdgeProvider — tracks selected edge
//   4. selectedNodeProvider — tracks selected node
//   5. graphZoomProvider — tracks zoom level
//   6. graphRealtimeProvider(familyId) — Supabase Realtime invalidation
//
// CHANGED (Option C): Replaced Dio/Render server calls with direct
// Supabase RPC calls (`get_family_graph`). No external server dependency.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/graph_layout_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../widgets/graph_canvas_widget.dart';

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

    return _fetchGraph(familyId);
  }

  // ── Data Fetching ──────────────────────────────────────────────────

  Future<FlatGraphResult> _fetchGraph(String familyId) async {
    final client = ref.read(supabaseProvider);
    if (client == null) {
      throw Exception('Supabase client not available');
    }

    try {
      // Resolve which member ID to use as the graph anchor
      final memberId = await _resolveAnchorMemberId(client, familyId);

      if (memberId == null) {
        // Family exists but has no members yet — return empty graph
        debugPrint('[FamilyGraphNotifier] No members in family $familyId');
        return const FlatGraphResult(persons: [], relationships: []);
      }

      // Call Supabase RPC directly — no Render server involved
      final response = await client.rpc(
        'get_family_graph',
        params: <String, dynamic>{
          'p_member_id': memberId,
          'p_max_degree': 4,
          'p_include_hidden': false,
        },
      ).timeout(const Duration(seconds: 30));

      final data = response as Map<String, dynamic>?;
      if (data == null) {
        throw const FormatException('Empty response from get_family_graph RPC');
      }

      final result = FlatGraphResult.fromRpc(data);

      // Cache the successful result
      _cache[familyId] = result;

      debugPrint(
        '[FamilyGraphNotifier] Loaded ${result.persons.length} persons, '
        '${result.relationships.length} relationships for $familyId',
      );

      return result;
    } on PostgrestException catch (e) {
      debugPrint('[FamilyGraphNotifier] Supabase error: ${e.message}');
      return _fallbackOrThrow(familyId, e);
    } on TimeoutException catch (e) {
      debugPrint('[FamilyGraphNotifier] Timeout: $e');
      return _fallbackOrThrow(familyId, e);
    } on FormatException catch (e) {
      debugPrint('[FamilyGraphNotifier] Format error: $e');
      return _fallbackOrThrow(familyId, e);
    } catch (e) {
      debugPrint('[FamilyGraphNotifier] Unexpected error: $e');
      return _fallbackOrThrow(familyId, e);
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
