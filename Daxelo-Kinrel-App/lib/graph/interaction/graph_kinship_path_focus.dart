// lib/graph/interaction/graph_kinship_path_focus.dart
//
// DAXELO KINREL — Kinship Path Focus (v92, 2026-07-12)
//
// FINAL 10/10 COMPLETION PASS — Parts 14–16.
//
// Resolves the relationship path between the current viewer and a
// selected target person, and exposes that path as a lightweight
// immutable model that the edge painter, the relationship explanation
// sheet, and the sequential trace controller can all consume.
//
// ARCHITECTURE
// ─────────────
// This file deliberately does NOT reimplement BFS. It wraps the
// existing `RelationshipEngine.resolvePath` (which itself delegates to
// `GraphService.findPath`) and post-processes the returned
// `List<PathStep>` into ordered person IDs + ordered edge IDs.
//
// `PathStep` carries personId + relationship type + direction but NO
// edge ID. To get edge IDs we match each consecutive (step[i-1],
// step[i]) pair against the deduped edge list by canonical pair. This
// is O(path_length × edges) but path_length is typically 1–5 and the
// call only fires on target/viewer/revision change — never during
// paint().
//
// The model is exposed via Riverpod as `graphPathFocusProvider`. The
// provider resolves only when:
//   • targetPersonId changes
//   • viewerPersonId changes
//   • graph relationship revision changes
// The result is cached. CustomPainter.paint() must NEVER call this.
//
// REDUCED MOTION
// ──────────────
// Reduced-motion detection is NOT done here. The trace controller
// (graph_path_trace_controller.dart) consults MediaQuery and skips the
// sequential animation when reduced motion is on, then immediately
// exposes the static path focus. This provider always returns the
// resolved path regardless of motion preference — the painter always
// has the path-focused edge set available.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/relationship/relationship_engine.dart' show RelationshipEngine;
import '../../core/kinship/structural_kinship_classifier.dart'
    show StructuralClassification;
import '../data/graph_data_models.dart' show GraphEdgeData;
import '../engine/edge_dedup.dart' show DedupedEdge, EdgeDeduplicator;
import '../../features/family/presentation/providers/family_graph_provider.dart'
    show familyGraphProvider;
import '../../core/viewer/viewer_provider.dart' show viewerPersonIdProvider;
import '../../core/services/graph_layout_service.dart' show GraphPerson;
import '../../core/kinship/kinship_edge_style.dart' show KinshipEdgeCategory;

/// A path step in the resolved viewer-to-target kinship path.
///
/// Each step pairs a person ID with the relationship edge that
/// connects them to the previous person in the path. The first step
/// has a null `edgeId` (it represents the viewer — no inbound edge).
@immutable
class GraphPathFocusStep {
  const GraphPathFocusStep({
    required this.personId,
    required this.personName,
    required this.relationshipType,
    required this.edgeId,
    required this.direction,
  });

  /// The person at this step of the path.
  final String personId;

  /// Display name of the person at this step.
  final String personName;

  /// The relationship type string for the hop INTO this step
  /// (e.g. "father", "sister"). Empty for the first step (the viewer).
  final String relationshipType;

  /// The deduped edge ID connecting the previous step to this step.
  /// Null for the first step (no inbound edge).
  final String? edgeId;

  /// Traversal direction for this hop: "from" or "to". Empty for the
  /// first step. Carried through from PathStep.direction.
  final String direction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphPathFocusStep &&
          other.personId == personId &&
          other.edgeId == edgeId;

  @override
  int get hashCode => Object.hash(personId, edgeId);

  @override
  String toString() =>
      'GraphPathFocusStep($personId via $relationshipType, edge=$edgeId)';
}

/// An immutable resolved kinship path between the viewer and a target.
///
/// This is the single source of truth consumed by:
///   • `_EngineEdgePainter` — receives `pathFocusedEdgeIds` and
///     `pathDimmedEdgeIds` to render the path-focus visual state.
///   • `GraphPathTraceController` — receives `orderedEdgeIds` to drive
///     the sequential one-shot trace animation.
///   • `RelationshipInfoSheet` — receives `steps` + `relationshipLabel`
///     to render the human-readable explanation.
@immutable
class GraphKinshipPathFocus {
  const GraphKinshipPathFocus({
    required this.viewerPersonId,
    required this.targetPersonId,
    required this.steps,
    required this.orderedPersonIds,
    required this.orderedEdgeIds,
    required this.resolvedRelationshipKey,
    required this.resolvedRelationshipLabel,
    required this.resolvedCategory,
    required this.graphRevision,
  });

  /// The viewer whose perspective this path is from.
  final String viewerPersonId;

  /// The target person the path leads to.
  final String targetPersonId;

  /// Ordered path steps. The first step is the viewer (edgeId == null);
  /// the last step is the target.
  final List<GraphPathFocusStep> steps;

  /// Convenience: ordered person IDs from viewer → target.
  final List<String> orderedPersonIds;

  /// Convenience: ordered edge IDs from viewer → target. Length is
  /// `steps.length - 1`.
  final List<String> orderedEdgeIds;

  /// The resolved kinship key for the overall viewer→target
  /// relationship (e.g. "fathers_brother"). May be null if no kinship
  /// rule matched.
  final String? resolvedRelationshipKey;

  /// Human-readable label for the overall relationship
  /// (e.g. "Father's Brother" or "Cousin").
  final String? resolvedRelationshipLabel;

  /// The authoritative category for the overall relationship.
  final KinshipEdgeCategory? resolvedCategory;

  /// The graph revision this path was resolved against. Used to
  /// invalidate the cache when the underlying graph data changes.
  final int graphRevision;

  /// Number of relationship hops. 0 = viewer is target (shouldn't
  /// happen — the provider returns null in that case).
  int get stepCount => orderedEdgeIds.length;

  /// True when the path has more than one hop (i.e. it's an indirect
  /// relationship that benefits from a sequential trace).
  bool get isMultiHop => stepCount > 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphKinshipPathFocus &&
          other.viewerPersonId == viewerPersonId &&
          other.targetPersonId == targetPersonId &&
          other.graphRevision == graphRevision &&
          _listEquals(other.orderedEdgeIds, orderedEdgeIds);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(viewerPersonId, targetPersonId, graphRevision, orderedEdgeIds.length);

  @override
  String toString() =>
      'GraphKinshipPathFocus($viewerPersonId → $targetPersonId, $stepCount steps, key=$resolvedRelationshipKey)';
}

/// State for the path-focus provider. Holds either a resolved path or
/// null (no target / unreachable / viewer is target).
@immutable
class GraphPathFocusState {
  const GraphPathFocusState({
    this.focus,
    this.resolvedAt,
  });

  /// The currently resolved path focus, or null when no target is
  /// selected or no path exists.
  final GraphKinshipPathFocus? focus;

  /// Logical timestamp (graph revision) at which the path was last
  /// resolved. Used to detect stale paths.
  final int? resolvedAt;

  static const GraphPathFocusState empty = GraphPathFocusState();

  GraphPathFocusState copyWith({
    GraphKinshipPathFocus? focus,
    int? resolvedAt,
  }) {
    return GraphPathFocusState(
      focus: focus ?? this.focus,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphPathFocusState && other.focus == focus;

  @override
  int get hashCode => focus.hashCode;
}

/// StateNotifier that owns the resolved path focus.
///
/// Resolution is triggered by:
///   • `resolve(...)` — called when target / viewer / graph data
///     changes. The caller passes the current deduped edge list +
///     persons + relationships + graph revision. The notifier caches
///     the result and notifies listeners.
///   • `clear()` — called when the target is deselected.
///
/// The notifier itself does NOT watch Riverpod providers — the
/// FamilyGraphEngineView widget drives resolution explicitly so that
/// it can pass the already-built `edges` list (which is built once per
/// graph-data change anyway) without recomputing it.
class GraphPathFocusNotifier extends StateNotifier<GraphPathFocusState> {
  GraphPathFocusNotifier() : super(GraphPathFocusState.empty);

  /// Resolve the kinship path between [viewerPersonId] and
  /// [targetPersonId] using the existing RelationshipEngine.
  ///
  /// [edges] must be the deduped edge list (EdgeDeduplicator.deduplicate
  /// output) — needed to map PathStep hops to concrete edge IDs.
  /// [persons] is the GraphPerson list from the layout service.
  /// [relationships] is the `List<({String fromId, String toId, String type})>`
  /// consumed by RelationshipEngine.resolvePath.
  /// [graphRevision] is the current graph revision counter (used for
  /// cache invalidation).
  /// [classification] is the pre-resolved StructuralClassification for
  /// the viewer→target pair (already computed by the engine view for
  /// node coloring). If null, the path is resolved but the label/key
  /// fields are null.
  ///
  /// This method is safe to call on every build — it short-circuits
  /// when the inputs haven't changed (same viewer + target + revision).
  GraphKinshipPathFocus? resolve({
    required String? viewerPersonId,
    required String? targetPersonId,
    required List<DedupedEdge> edges,
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String type})> relationships,
    required int graphRevision,
    StructuralClassification? classification,
  }) {
    // No viewer or no target → clear.
    if (viewerPersonId == null || targetPersonId == null) {
      if (state.focus != null) state = GraphPathFocusState.empty;
      return null;
    }

    // Viewer == target → clear (the viewer's relationship to themselves
    // is "You" — no path needed).
    if (viewerPersonId == targetPersonId) {
      if (state.focus != null) state = GraphPathFocusState.empty;
      return null;
    }

    // Cache hit — same viewer, same target, same revision, same
    // classification. Return the cached focus without re-resolving.
    final current = state.focus;
    if (current != null &&
        current.viewerPersonId == viewerPersonId &&
        current.targetPersonId == targetPersonId &&
        current.graphRevision == graphRevision) {
      // If the classification was passed in and matches, we're done.
      // If classification differs (e.g. label changed), re-resolve
      // by falling through.
      if (classification == null ||
          (current.resolvedRelationshipKey == classification.key &&
              current.resolvedRelationshipLabel == classification.label)) {
        return current;
      }
    }

    // Resolve the path via RelationshipEngine (cached internally).
    final pathSteps = RelationshipEngine.instance.resolvePath(
      viewerPersonId: viewerPersonId,
      targetPersonId: targetPersonId,
      persons: persons,
      relationships: relationships,
    );

    if (pathSteps == null || pathSteps.isEmpty) {
      // No path exists. Clear any previous focus.
      if (state.focus != null) state = GraphPathFocusState.empty;
      return null;
    }

    // Build ordered person IDs from the path.
    // PathStep[0] is the first hop FROM the viewer, so the viewer
    // themselves must be prepended.
    final orderedPersonIds = <String>[
      viewerPersonId,
      ...pathSteps.map((s) => s.personId),
    ];

    // Build a lookup from canonical pair → edge ID. Canonical pair is
    // the sorted (fromId, toId) tuple, because GraphEdgeData may store
    // the edge in either direction relative to BFS traversal.
    // EdgeDeduplicator already collapsed bidirectional duplicates, so
    // there's exactly one edge per canonical pair.
    final edgeByPair = <String, String>{};
    for (final deduped in edges) {
      final e = deduped.edge;
      final pairKey = _canonicalPairKey(e.sourceId, e.targetId);
      // First-write-wins — if duplicates exist (they shouldn't after
      // dedup), keep the first.
      edgeByPair.putIfAbsent(pairKey, () => e.id);
    }

    // Map each consecutive (personA, personB) pair to an edge ID.
    final orderedEdgeIds = <String>[];
    final focusSteps = <GraphPathFocusStep>[];
    for (var i = 0; i < orderedPersonIds.length; i++) {
      final pid = orderedPersonIds[i];
      final pname = i == 0
          ? (persons.firstWhere(
                  (p) => p.id == pid,
                  orElse: () => GraphPerson(id: pid, name: 'You'))
              .name)
          : pathSteps[i - 1].personName;
      final rtype = i == 0 ? '' : pathSteps[i - 1].type;
      final dir = i == 0 ? '' : pathSteps[i - 1].direction;
      String? edgeId;
      if (i > 0) {
        final prev = orderedPersonIds[i - 1];
        edgeId = edgeByPair[_canonicalPairKey(prev, pid)];
        if (edgeId != null) {
          orderedEdgeIds.add(edgeId);
        } else {
          // Edge not found in deduped list — the path traverses a
          // relationship that wasn't visible (e.g. culled). Skip but
          // keep the person in the ordered list. This is rare.
          debugPrint(
              '⚠️ GraphPathFocus: no edge for pair ($prev, $pid) — path may be incomplete');
        }
      }
      focusSteps.add(GraphPathFocusStep(
        personId: pid,
        personName: pname,
        relationshipType: rtype,
        edgeId: edgeId,
        direction: dir,
      ));
    }

    final focus = GraphKinshipPathFocus(
      viewerPersonId: viewerPersonId,
      targetPersonId: targetPersonId,
      steps: List.unmodifiable(focusSteps),
      orderedPersonIds: List.unmodifiable(orderedPersonIds),
      orderedEdgeIds: List.unmodifiable(orderedEdgeIds),
      resolvedRelationshipKey: classification?.key,
      resolvedRelationshipLabel: classification?.label,
      resolvedCategory: classification?.category,
      graphRevision: graphRevision,
    );

    state = GraphPathFocusState(focus: focus, resolvedAt: graphRevision);
    return focus;
  }

  /// Clear the resolved path. Called when the target is deselected.
  void clear() {
    if (state.focus != null) state = GraphPathFocusState.empty;
  }

  /// Canonical pair key — sorted (a, b) joined by '⇄' so (a,b) and (b,a)
  /// map to the same key.
  static String _canonicalPairKey(String a, String b) {
    if (a.compareTo(b) <= 0) return '$a⇄$b';
    return '$b⇄$a';
  }
}

/// Riverpod provider for the kinship path focus.
///
/// Watch this to get the current `GraphKinshipPathFocus` (or null).
/// The FamilyGraphEngineView drives resolution by calling
/// `ref.read(graphPathFocusProvider.notifier).resolve(...)` from its
/// build method whenever target / viewer / graph data changes.
final graphPathFocusProvider =
    StateNotifierProvider<GraphPathFocusNotifier, GraphPathFocusState>(
  (ref) => GraphPathFocusNotifier(),
);
