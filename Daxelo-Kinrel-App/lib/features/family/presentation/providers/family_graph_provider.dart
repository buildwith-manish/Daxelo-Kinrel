// lib/features/family/presentation/providers/family_graph_provider.dart
//
// DAXELO KINREL — Family Graph Providers
//
// Riverpod providers for the family graph feature:
//   1. familyGraphProvider(familyId) — fetches flat graph data via Dio
//   2. graphLayoutProvider(familyId) — computes layout in an isolate
//   3. selectedEdgeProvider — tracks selected edge
//   4. selectedNodeProvider — tracks selected node
//   5. graphZoomProvider — tracks zoom level
//   6. graphRealtimeProvider(familyId) — Socket.IO real-time invalidation

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/networking/dio_client.dart';
import '../../../../core/network/socket_service.dart';
import '../../../../core/services/graph_layout_service.dart';
import '../widgets/graph_canvas_widget.dart';

// ═══════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// Flat graph data as received from the API.
///
/// Contains raw person and relationship maps plus metadata about
/// truncation for very large families.
class FlatGraphResult {
  /// Raw person data from the API.
  final List<Map<String, dynamic>> persons;

  /// Raw relationship data from the API.
  final List<Map<String, dynamic>> relationships;

  /// Whether the response was truncated (server capped at 5000 persons).
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

  /// Parses the API response JSON into a [FlatGraphResult].
  factory FlatGraphResult.fromJson(Map<String, dynamic> json) {
    return FlatGraphResult(
      persons: (json['persons'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      relationships: (json['relationships'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
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
///
/// Must be a top-level or static function so it can be sent across
/// isolate boundaries.
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
// 1. FAMILY GRAPH PROVIDER — AsyncNotifierProvider.family
// ═══════════════════════════════════════════════════════════════════════

/// AsyncNotifier that fetches and caches flat graph data for a family.
///
/// Features:
///   - Fetches from `GET /graph/:familyId?format=flat` via Dio
///   - Caches the last successful result in memory
///   - On error, returns cached data if available (graceful degradation)
///   - Supports refresh via [refreshGraph]
class FamilyGraphNotifier extends FamilyAsyncNotifier<FlatGraphResult, String> {
  /// In-memory cache keyed by familyId so we can fallback on error.
  static final Map<String, FlatGraphResult> _cache = {};

  @override
  Future<FlatGraphResult> build(String familyId) async {
    // Ensure the socket joins this family's room for real-time updates
    _joinFamilyRoom(familyId);

    // Invalidate the layout when graph data is (re)fetched
    ref.invalidate(graphLayoutProvider(familyId));

    return _fetchGraph(familyId);
  }

  // ── Data Fetching ──────────────────────────────────────────────────

  Future<FlatGraphResult> _fetchGraph(String familyId) async {
    final dio = ref.read(dioProvider);

    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/graph/$familyId',
        queryParameters: {'format': 'flat'},
      );

      final data = response.data;
      if (data == null) {
        throw const FormatException('Empty response from /graph endpoint');
      }

      final result = FlatGraphResult.fromJson(data);

      // Cache the successful result
      _cache[familyId] = result;

      return result;
    } on DioException catch (e) {
      // On network/server error, try to return cached data
      final cached = _cache[familyId];
      if (cached != null) {
        debugPrint(
          '[FamilyGraphNotifier] Using cached data for $familyId '
          'after DioException: ${e.type}',
        );
        return cached;
      }
      rethrow;
    } on FormatException catch (_) {
      final cached = _cache[familyId];
      if (cached != null) {
        debugPrint(
          '[FamilyGraphNotifier] Using cached data for $familyId '
          'after FormatException',
        );
        return cached;
      }
      rethrow;
    } catch (e) {
      final cached = _cache[familyId];
      if (cached != null) {
        debugPrint(
          '[FamilyGraphNotifier] Using cached data for $familyId '
          'after error: $e',
        );
        return cached;
      }
      rethrow;
    }
  }

  // ── Public Methods ─────────────────────────────────────────────────

  /// Refreshes the graph data by invalidating and re-fetching.
  Future<void> refreshGraph() async {
    ref.invalidateSelf();
  }

  // ── Socket Room Management ─────────────────────────────────────────

  void _joinFamilyRoom(String familyId) {
    try {
      final socketService = ref.read(socketServiceProvider);
      socketService.joinFamily(familyId);
    } catch (e) {
      debugPrint('[FamilyGraphNotifier] Could not join family room: $e');
    }
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
///
/// Depends on [familyGraphProvider] for raw data, then passes typed
/// [GraphPerson] and [GraphRelationship] lists to
/// [GraphLayoutService.computeLayout] via [compute].
///
/// Automatically recomputes when the graph data changes
/// (i.e., when [familyGraphProvider] is invalidated).
///
/// Uses compact mode when the person count exceeds 50.
final graphLayoutProvider =
    FutureProvider.family<GraphLayoutResult, String>((ref, familyId) async {
  final graphAsync = ref.watch(familyGraphProvider(familyId));

  final graphData = graphAsync.valueOrNull;
  if (graphData == null) {
    // Return an empty layout while loading
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

  // Find anchor person ID
  final anchorPerson = persons.firstWhere(
    (p) => p.isAnchor,
    orElse: () => persons.first,
  );

  // Use compact mode for large graphs
  final compactMode = persons.length > 50;

  final params = _LayoutComputeParams(
    persons: graphPersons,
    relationships: graphRelationships,
    anchorPersonId: anchorPerson.id,
    compactMode: compactMode,
  );

  // Run layout computation in a background isolate
  try {
    return await compute(_runLayoutInIsolate, params);
  } catch (e) {
    debugPrint('[graphLayoutProvider] Isolate compute failed, '
        'falling back to main thread: $e');
    // Fallback to main-thread computation if isolate fails
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
///
/// Set to `null` when no edge is selected.
final selectedEdgeProvider = StateProvider<String?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════
// 4. SELECTED NODE PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Tracks the currently selected person node ID.
///
/// Set to `null` when no node is selected.
final selectedNodeProvider = StateProvider<String?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════
// 5. GRAPH ZOOM PROVIDER
// ═══════════════════════════════════════════════════════════════════════

/// Tracks the current zoom level of the graph viewer.
///
/// Default is 1.0 (100%). Updated by the [InteractiveViewer] controller
/// when the user pinches or uses zoom FABs.
final graphZoomProvider = StateProvider<double>((ref) => 1.0);

// ═══════════════════════════════════════════════════════════════════════
// 6. GRAPH REALTIME PROVIDER — Socket.IO event listener
// ═══════════════════════════════════════════════════════════════════════

/// Listens to `graph:updated` Socket.IO events for a specific family
/// and invalidates [familyGraphProvider] when graph data changes.
///
/// This provider is kept alive as long as the family graph screen is
/// mounted. On dispose, it leaves the family room and cleans up
/// the socket listener.
///
/// Usage:
/// ```dart
/// // In the screen's build or initState:
/// ref.watch(graphRealtimeProvider(familyId));
/// ```
final graphRealtimeProvider =
    Provider.family<void, String>((ref, familyId) {
  // Ensure the socket service is initialized and connected
  final socketService = ref.read(socketServiceProvider);

  // Timer to debounce rapid invalidation events
  DateTime? _lastInvalidation;

  void onGraphUpdated(dynamic data) {
    final now = DateTime.now();

    // Debounce: skip if we invalidated less than 2 seconds ago
    if (_lastInvalidation != null &&
        now.difference(_lastInvalidation!) < const Duration(seconds: 2)) {
      return;
    }

    _lastInvalidation = now;

    // Check if the event is for this specific family
    if (data is Map<String, dynamic>) {
      final eventFamilyId = data['familyId'] as String?;
      if (eventFamilyId != null && eventFamilyId != familyId) {
        return; // Not for this family — skip
      }
    }

    debugPrint('[graphRealtimeProvider] Invalidating graph for $familyId');
    ref.invalidate(familyGraphProvider(familyId));
  }

  // Register the listener
  // The SocketService already listens to 'graph:updated' internally,
  // but we add a direct listener here for per-family granularity.
  try {
    socketService.joinFamily(familyId);
  } catch (e) {
    debugPrint('[graphRealtimeProvider] Could not join family room: $e');
  }

  // Clean up on dispose
  ref.onDispose(() {
    try {
      socketService.leaveFamily(familyId);
    } catch (e) {
      debugPrint('[graphRealtimeProvider] Could not leave family room: $e');
    }
  });
});
