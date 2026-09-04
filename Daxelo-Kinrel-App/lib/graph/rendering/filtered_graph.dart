// lib/graph/rendering/filtered_graph.dart
//
// DAXELO KINREL — Filtered Graph Model (v5.143)
//
// A precomputed, IMMUTABLE view of the graph containing ONLY the nodes
// and edges that actually participate in the current render. This is
// the single object that should be passed to every consumer that
// previously iterated `flat.relationships` (the full 700-1000 row
// Supabase result) on every canvas rebuild.
//
// WHY THIS EXISTS
// ───────────────
// The audit (v5.143) found that `canvas_mixin._buildCanvas` iterated
// `flat.relationships` (~1000 edges) 5-6 times per rebuild, and
// `node_builders._buildFullNode` iterated it once PER VISIBLE NODE
// when tap-highlight was active (50 nodes × 1000 edges = 50,000 ops
// per rebuild). The "hidden" Set<String> from branch_collapse_state
// was applied AFTER iteration, not before — so the engine was doing
// 100,000+ wasted ops per rebuild on a 700-member family even though
// only ~50 nodes had positions.
//
// FilteredGraph flips this: it filters ONCE at the top of _buildCanvas
// and exposes the result as O(1) lookups. Downstream code never
// touches `flat.relationships` directly.
//
// WHAT IT CONTAINS
// ────────────────
// • `visiblePersonIds` — the ~50 IDs that have a position in
//   `effectivePositions` AND are not hidden by collapse.
// • `visiblePersons` — the person maps (from flat.persons) for those
//   IDs, as a list.
// • `personById` — O(1) lookup from ID → person map.
// • `visibleRelationships` — only edges where BOTH endpoints are in
//   `visiblePersonIds`. Typically ~50-150 edges (vs 1000 in flat).
// • `adjacencyByVisibleId` — O(1) lookup from visible ID → list of
//   (otherId, edgeId, relationshipKey, rawRow). Used for first-degree
//   neighbor computation, lifeguard safeguard, anchor-neighbor
//   protection, etc.
// • `rawEdgeTuples` — the lightweight tuple form used by
//   proximity init + collapse computation, pre-filtered to visible.
//
// MEMOIZATION
// ───────────
// FilteredGraph is built ONCE per _buildCanvas call and cached on the
// state object via `identical(_lastFlat, flat)`. When `flat` is the
// same object (the common case during pan/zoom — the Supabase result
// hasn't changed), the cached FilteredGraph is reused. This means
// the 5-6 iterations of flat.relationships happen ONCE per graph-data
// change, not once per rebuild.
//
// The `effectivePositions` identity is also checked because layout
// recompute (on expand/collapse) changes the positions map even when
// `flat` is unchanged.

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/widgets.dart' show Offset;

import '../data/graph_data_models.dart' show GraphEdgeData;

/// A lightweight tuple representing a visible relationship edge.
/// Avoids allocating a full Map<String, dynamic> per edge.
@immutable
class FilteredRelationship {
  const FilteredRelationship({
    required this.fromId,
    required this.toId,
    required this.edgeId,
    required this.relationshipKey,
    required this.labelAtoB,
    required this.isPrivate,
    required this.rawRow,
  });

  final String fromId;
  final String toId;
  final String edgeId;
  final String relationshipKey;
  final String? labelAtoB;
  final bool isPrivate;

  /// The original row from `flat.relationships`. Kept so consumers
  /// that need arbitrary fields (e.g. customColors) can access them
  /// without a second pass over flat.relationships.
  final Map<String, dynamic> rawRow;
}

/// An immutable, pre-filtered view of the graph for the current render.
///
/// See the file header for the full rationale.
@immutable
class FilteredGraph {
  const FilteredGraph({
    required this.visiblePersonIds,
    required this.visiblePersons,
    required this.personById,
    required this.visibleRelationships,
    required this.adjacencyByVisibleId,
    required this.rawEdgeTuples,
    required this.allVisibleEdges,
    required this.edgeCount,
    required this.personCount,
  });

  /// The set of visible person IDs (has a position + not hidden).
  /// Typically ~50 IDs on a 700-member family.
  final Set<String> visiblePersonIds;

  /// The person maps for [visiblePersonIds], as a list.
  /// Use [personById] for O(1) lookup by ID.
  final List<Map<String, dynamic>> visiblePersons;

  /// O(1) lookup from person ID → person map.
  /// Only contains entries for [visiblePersonIds].
  final Map<String, Map<String, dynamic>> personById;

  /// Only edges where BOTH endpoints are in [visiblePersonIds].
  /// Typically ~50-150 edges (vs ~1000 in flat.relationships).
  final List<FilteredRelationship> visibleRelationships;

  /// O(1) lookup from visible person ID → list of adjacent edges
  /// (where the OTHER endpoint is also visible). Each entry contains
  /// the other person's ID, the edge ID, the relationship key, and
  /// the raw row.
  ///
  /// Used for:
  /// • First-degree neighbor computation (tap-highlight)
  /// • Lifeguard safeguard (find a visible relative for orphan nodes)
  /// • Anchor-neighbor protection (keep anchor's direct relatives visible)
  /// • BFS through hidden nodes to find nearest visible relative
  ///
  /// NOTE: This map only contains VISIBLE → VISIBLE adjacencies.
  /// Edges to hidden nodes are NOT here (they were filtered out).
  /// If you need the full adjacency (including hidden), use the
  /// rawEdgeTuples + flat.relationships directly.
  final Map<String, List<({String otherId, String edgeId, String relationshipKey, Map<String, dynamic> rawRow})>>
      adjacencyByVisibleId;

  /// Lightweight tuple form of [visibleRelationships], used by
  /// proximity init + collapse computation.
  final List<({String fromId, String toId, String edgeId, String relationshipKey})>
      rawEdgeTuples;

  /// All visible edges as GraphEdgeData (for the edge painter).
  /// Computed from [visibleRelationships] — no second pass over flat.
  final List<GraphEdgeData> allVisibleEdges;

  /// Number of edges in [visibleRelationships]. Convenience field
  /// for logging/diagnostics without calling .length on the list.
  final int edgeCount;

  /// Number of persons in [visiblePersons]. Convenience field.
  final int personCount;

  /// Returns the first-degree neighbor IDs of [personId] from the
  /// visible adjacency map. O(1) lookup + O(degree) list build.
  /// Returns an empty set if [personId] has no visible edges.
  Set<String> firstDegreeNeighborsOf(String personId) {
    final adj = adjacencyByVisibleId[personId];
    if (adj == null || adj.isEmpty) return <String>{};
    return <String>{for (final a in adj) a.otherId};
  }

  /// Returns true if [personId] has at least one visible edge.
  bool hasVisibleEdges(String personId) {
    final adj = adjacencyByVisibleId[personId];
    return adj != null && adj.isNotEmpty;
  }

  /// Empty singleton for the initial state before the first build.
  static const FilteredGraph empty = FilteredGraph(
    visiblePersonIds: <String>{},
    visiblePersons: <Map<String, dynamic>>[],
    personById: <String, Map<String, dynamic>>{},
    visibleRelationships: <FilteredRelationship>[],
    adjacencyByVisibleId: <String, List<({String otherId, String edgeId, String relationshipKey, Map<String, dynamic> rawRow})>>{},
    rawEdgeTuples: <({String fromId, String toId, String edgeId, String relationshipKey})>[],
    allVisibleEdges: <GraphEdgeData>[],
    edgeCount: 0,
    personCount: 0,
  );
}

/// Builds a [FilteredGraph] from the full `flat` result + the current
/// `effectivePositions` map + the `hiddenIds` set.
///
/// This is the SINGLE function that iterates `flat.relationships` and
/// `flat.persons`. Everything else downstream reads from the returned
/// [FilteredGraph].
///
/// Complexity: O(P + E) where P = flat.persons.length (~700) and
/// E = flat.relationships.length (~1000). This runs ONCE per graph-
/// data change (memoized on identical(flat)), NOT once per rebuild.
FilteredGraph buildFilteredGraph({
  required List<Map<String, dynamic>> allPersons,
  required List<Map<String, dynamic>> allRelationships,
  required Map<String, Offset> effectivePositions,
  required Set<String> hiddenIds,
}) {
  // ── Step 1: Determine visible person IDs ─────────────────────────
  // A person is "visible" if they have a position in the current
  // layout AND they're not hidden by collapse.
  final visiblePersonIds = <String>{};
  final personById = <String, Map<String, dynamic>>{};
  final visiblePersons = <Map<String, dynamic>>[];

  for (final p in allPersons) {
    final id = (p['id'] ?? '').toString();
    if (id.isEmpty) continue;
    if (!effectivePositions.containsKey(id)) continue;
    if (hiddenIds.contains(id)) continue;
    visiblePersonIds.add(id);
    personById[id] = p;
    visiblePersons.add(p);
  }

  // ── Step 2: Filter relationships to visible ↔ visible ────────────
  // An edge is included if BOTH endpoints are visible. Edges where
  // one endpoint is visible and the other is hidden are KEPT in the
  // full adjacency (for the lifeguard safeguard + BFS), but excluded
  // from the visible edge list (the painter only draws visible↔visible
  // OR visible↔hidden-positioned edges — see canvas_mixin L741).
  //
  // For the FilteredGraph, we keep edges where both endpoints are
  // visible OR both endpoints have a position (the painter's contract).
  final visibleRelationships = <FilteredRelationship>[];
  final adjacencyByVisibleId =
      <String, List<({String otherId, String edgeId, String relationshipKey, Map<String, dynamic> rawRow})>>{};
  final rawEdgeTuples =
      <({String fromId, String toId, String edgeId, String relationshipKey})>[];

  for (final r in allRelationships) {
    final fromId = (r['fromPersonId'] ?? '').toString();
    final toId = (r['toPersonId'] ?? '').toString();
    final edgeId = (r['id'] ?? '').toString();
    if (fromId.isEmpty || toId.isEmpty) continue;

    // Both endpoints must have a position to be drawable.
    if (!effectivePositions.containsKey(fromId)) continue;
    if (!effectivePositions.containsKey(toId)) continue;

    // Skip edges where BOTH endpoints are hidden (density collapse).
    final fromHidden = hiddenIds.contains(fromId);
    final toHidden = hiddenIds.contains(toId);
    if (fromHidden && toHidden) continue;

    final relationshipKey = (r['relationshipKey'] ?? 'unknown').toString();
    final labelAtoB = r['labelAtoB'] as String?;
    final isPrivate = (r['isPrivate'] as bool?) ?? false;

    final fr = FilteredRelationship(
      fromId: fromId,
      toId: toId,
      edgeId: edgeId,
      relationshipKey: relationshipKey,
      labelAtoB: labelAtoB,
      isPrivate: isPrivate,
      rawRow: r,
    );
    visibleRelationships.add(fr);
    rawEdgeTuples.add((
      fromId: fromId,
      toId: toId,
      edgeId: edgeId,
      relationshipKey: relationshipKey,
    ));

    // Build adjacency: only VISIBLE → visible adjacencies go in the
    // map. Edges to hidden nodes are in visibleRelationships (for the
    // painter) but NOT in adjacencyByVisibleId (for first-degree
    // neighbor computation — we only care about visible neighbors).
    if (!fromHidden && !toHidden) {
      final adjFrom = adjacencyByVisibleId.putIfAbsent(fromId, () => []);
      adjFrom.add((
        otherId: toId,
        edgeId: edgeId,
        relationshipKey: relationshipKey,
        rawRow: r,
      ));
      final adjTo = adjacencyByVisibleId.putIfAbsent(toId, () => []);
      adjTo.add((
        otherId: fromId,
        edgeId: edgeId,
        relationshipKey: relationshipKey,
        rawRow: r,
      ));
    }
  }

  // ── Step 3: Build GraphEdgeData list for the painter ─────────────
  final allVisibleEdges = <GraphEdgeData>[];
  for (final fr in visibleRelationships) {
    allVisibleEdges.add(GraphEdgeData(
      id: fr.edgeId,
      sourceId: fr.fromId,
      targetId: fr.toId,
      relationshipKey: fr.relationshipKey,
      labelAtoB: fr.labelAtoB ?? fr.relationshipKey,
      isPrivate: fr.isPrivate,
    ));
  }

  return FilteredGraph(
    visiblePersonIds: visiblePersonIds,
    visiblePersons: visiblePersons,
    personById: personById,
    visibleRelationships: visibleRelationships,
    adjacencyByVisibleId: adjacencyByVisibleId,
    rawEdgeTuples: rawEdgeTuples,
    allVisibleEdges: allVisibleEdges,
    edgeCount: visibleRelationships.length,
    personCount: visiblePersons.length,
  );
}

/// Returns true if two Set<String> are equal (same elements).
/// Used by the FilteredGraph cache to detect when hiddenIds change.
/// Avoids the O(N) allocation of SetEquality from package:collection.
bool setsEqualString(Set<String> a, Set<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final e in a) {
    if (!b.contains(e)) return false;
  }
  return true;
}
