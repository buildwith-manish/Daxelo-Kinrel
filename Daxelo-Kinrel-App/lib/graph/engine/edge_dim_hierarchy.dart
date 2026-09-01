// lib/graph/engine/edge_dim_hierarchy.dart
//
// DAXELO KINREL — Edge dim hierarchy (Feature 2)
//
// Pure function that computes the set of edge IDs that should be
// rendered at the dimmed alpha by the EngineEdgePainter. Extracted
// from `_computeDimmedEdgeIds` in interaction_mixin.dart so the
// resolution priority and the four cases (search / focus / selection
// / default-dim) are unit-testable without mounting a widget tree.
//
// Contract (priority highest → lowest):
//   1. Search active  → dim edges NOT connected to any match.
//   2. Focus active   → dim edges NOT directly incident to the
//                       focused person (Isolate Connections).
//   3. Selection only → dim edges NOT directly incident to the
//                       selected node (selectedNodeProvider).
//   4. Nothing active → dim ALL edges (the default-dim state).
//
// Returns `null` ONLY when there's nothing to dim (e.g. the edge
// list is empty, or every edge would stay bright in one of the
// active cases — the painter treats null as "no dimming" and
// short-circuits the per-edge dim check).
//
// This is a PURE function — same inputs always produce the same
// output, no side effects. The caller is responsible for reading
// the providers and passing the current values.

import '../data/graph_data_models.dart' show GraphEdgeData;
import '../engine/edge_dedup.dart' show DedupedEdge;

/// Inputs to [computeDimmedEdgeIds].
///
/// All fields are nullable so the caller can pass `null` for any
/// inactive state — the helper treats `null` as "this state is off".
class EdgeDimHierarchyInput {
  /// The set of edge IDs that match the active search (if any).
  /// When non-empty AND [searchIsActive] is true, edges NOT connected
  /// to any node in this set are dimmed.
  final Set<String>? searchMatchNodeIds;

  /// Whether search is currently active.
  final bool searchIsActive;

  /// The currently focused person ID (Isolate Connections), or null
  /// when no person is focused. When non-null, edges NOT directly
  /// incident to this person are dimmed.
  final String? focusedPersonId;

  /// The currently selected node ID (selectedNodeProvider), or null
  /// when no node is selected. When non-null AND no focus/search is
  /// active, edges NOT directly incident to this node are dimmed.
  final String? selectedNodeId;

  const EdgeDimHierarchyInput({
    this.searchMatchNodeIds,
    this.searchIsActive = false,
    this.focusedPersonId,
    this.selectedNodeId,
  });
}

/// Computes the set of edge IDs that should be rendered at the
/// dimmed alpha. See the file doc for the full contract.
///
/// Returns `null` when there's nothing to dim — the painter treats
/// `null` as "no dimming" and short-circuits the per-edge dim check.
Set<String>? computeDimmedEdgeIds(
    List<DedupedEdge> edges, EdgeDimHierarchyInput input) {
  if (edges.isEmpty) return null;

  // Case 1 — Search active.
  if (input.searchIsActive &&
      input.searchMatchNodeIds != null &&
      input.searchMatchNodeIds!.isNotEmpty) {
    final matchSet = input.searchMatchNodeIds!;
    final connected = <String>{};
    for (final deduped in edges) {
      final e = deduped.edge;
      if (matchSet.contains(e.sourceId) || matchSet.contains(e.targetId)) {
        connected.add(e.id);
      }
    }
    if (connected.length == edges.length) return null;
    return _complement(edges, connected);
  }

  // Case 2 — Focus (Isolate Connections) active.
  if (input.focusedPersonId != null) {
    final focused = input.focusedPersonId!;
    final connected = <String>{};
    for (final deduped in edges) {
      final e = deduped.edge;
      if (e.sourceId == focused || e.targetId == focused) {
        connected.add(e.id);
      }
    }
    if (connected.length == edges.length) return null;
    return _complement(edges, connected);
  }

  // Case 3 — Selection only (no focus / no search).
  if (input.selectedNodeId != null) {
    final selected = input.selectedNodeId!;
    final connected = <String>{};
    for (final deduped in edges) {
      final e = deduped.edge;
      if (e.sourceId == selected || e.targetId == selected) {
        connected.add(e.id);
      }
    }
    if (connected.length == edges.length) return null;
    return _complement(edges, connected);
  }

  // Case 4 — Default-dim: nothing active → dim ALL edges.
  final allDimmed = <String>{};
  for (final deduped in edges) {
    allDimmed.add(deduped.edge.id);
  }
  return allDimmed;
}

Set<String> _complement(List<DedupedEdge> edges, Set<String> bright) {
  final dimmed = <String>{};
  for (final deduped in edges) {
    if (!bright.contains(deduped.edge.id)) {
      dimmed.add(deduped.edge.id);
    }
  }
  return dimmed;
}

// ── Convenience extension for callers that have raw GraphEdgeData ─────
//
// Allows the helper to be used with a list of GraphEdgeData (without
// the DedupedEdge wrapper) for unit tests that build edge fixtures
// directly.

/// Inputs for the [GraphEdgeData] overload of [computeDimmedEdgeIds].
/// Same fields as [EdgeDimHierarchyInput] — kept separate so the
/// public API surface stays explicit about which list type it takes.
typedef EdgeDimHierarchyInputEdges = EdgeDimHierarchyInput;

/// GraphEdgeData-list overload — used by unit tests that build edge
/// fixtures directly. Production code (canvas_mixin.dart /
/// interaction_mixin.dart) uses [computeDimmedEdgeIds] with
/// [DedupedEdge] objects.
Set<String>? computeDimmedEdgeIdsFromEdges(
    List<GraphEdgeData> edges, EdgeDimHierarchyInputEdges input) {
  if (edges.isEmpty) return null;

  if (input.searchIsActive &&
      input.searchMatchNodeIds != null &&
      input.searchMatchNodeIds!.isNotEmpty) {
    final matchSet = input.searchMatchNodeIds!;
    final connected = <String>{};
    for (final e in edges) {
      if (matchSet.contains(e.sourceId) || matchSet.contains(e.targetId)) {
        connected.add(e.id);
      }
    }
    if (connected.length == edges.length) return null;
    return _complementEdges(edges, connected);
  }

  if (input.focusedPersonId != null) {
    final focused = input.focusedPersonId!;
    final connected = <String>{};
    for (final e in edges) {
      if (e.sourceId == focused || e.targetId == focused) {
        connected.add(e.id);
      }
    }
    if (connected.length == edges.length) return null;
    return _complementEdges(edges, connected);
  }

  if (input.selectedNodeId != null) {
    final selected = input.selectedNodeId!;
    final connected = <String>{};
    for (final e in edges) {
      if (e.sourceId == selected || e.targetId == selected) {
        connected.add(e.id);
      }
    }
    if (connected.length == edges.length) return null;
    return _complementEdges(edges, connected);
  }

  final allDimmed = <String>{};
  for (final e in edges) {
    allDimmed.add(e.id);
  }
  return allDimmed;
}

Set<String> _complementEdges(List<GraphEdgeData> edges, Set<String> bright) {
  final dimmed = <String>{};
  for (final e in edges) {
    if (!bright.contains(e.id)) {
      dimmed.add(e.id);
    }
  }
  return dimmed;
}
