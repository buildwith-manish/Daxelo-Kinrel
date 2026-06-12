// lib/graph/rendering/node_render_coordinator.dart
//
// DAXELO KINREL — Node Render Coordinator (V2.1 Rendering Layer)
//
// Manages RepaintBoundary placement and ValueKey assignment for graph
// rendering. Each visible GraphNode is wrapped in its own RepaintBoundary
// to isolate node animations from the rest of the graph. The edge layer
// uses a single CustomPainter inside one RepaintBoundary. Camera transform
// is applied OUTSIDE all RepaintBoundaries so pan/zoom repaints are cheap.
//
// Memory trade-off: boundaries are only created for nodes within the
// current viewport + 200 px buffer. Typical active boundary count:
// 30–80 depending on zoom level.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/services/graph_layout_service.dart';
import '../../core/services/analytics_service.dart';
import 'viewport_culler.dart';

// ═══════════════════════════════════════════════════════════════════════
// ENUMS
// ═══════════════════════════════════════════════════════════════════════

/// Policy controlling how RepaintBoundaries are placed around graph nodes.
///
/// - [perNode]: One boundary per visible node (default, best isolation).
/// - [perCluster]: One boundary per generation cluster (fewer boundaries,
///   useful on low-memory devices).
/// - [single]: Single boundary around all nodes (worst isolation, best
///   for very large graphs on constrained hardware).
enum RepaintBoundaryPolicy {
  perNode,
  perCluster,
  single,
}

// ═══════════════════════════════════════════════════════════════════════
// KEY STRATEGY
// ═══════════════════════════════════════════════════════════════════════

/// Manages stable [ValueKey] assignment for graph widgets.
///
/// Consistent keys preserve animation state across rebuilds and prevent
/// Flutter from recreating widgets that have not logically changed.
///
/// Key conventions:
/// - GraphNode: `ValueKey(memberId)`
/// - RelationshipEdge: `ValueKey("${sourceId}_${targetId}")`
/// - ExpandIndicator: `ValueKey("expand_${memberId}_${branchType}")`
/// - InfoSheet: `ValueKey("info_${memberId}")`
class KeyStrategy {
  /// Key for a person node widget.
  static ValueKey<String> nodeKey(String memberId) =>
      ValueKey<String>(memberId);

  /// Key for a relationship edge widget.
  static ValueKey<String> edgeKey(String sourceId, String targetId) =>
      ValueKey<String>('${sourceId}_$targetId');

  /// Key for an expand/collapse indicator widget.
  static ValueKey<String> expandIndicatorKey(
    String memberId,
    String branchType,
  ) =>
      ValueKey<String>('expand_${memberId}_$branchType');

  /// Key for a member info bottom-sheet widget.
  static ValueKey<String> infoSheetKey(String memberId) =>
      ValueKey<String>('info_$memberId');

  /// Key for the edge layer CustomPainter.
  static ValueKey<String> edgeLayerKey() =>
      const ValueKey<String>('edge_layer');

  /// Key for the legend widget.
  static ValueKey<String> legendKey() =>
      const ValueKey<String>('legend');

  /// Key for the search bar widget.
  static ValueKey<String> searchBarKey() =>
      const ValueKey<String>('search_bar');

  /// Key for the filter panel widget.
  static ValueKey<String> filterPanelKey() =>
      const ValueKey<String>('filter_panel');
}

// ═══════════════════════════════════════════════════════════════════════
// NODE RENDER COORDINATOR
// ═══════════════════════════════════════════════════════════════════════

/// Coordinates [RepaintBoundary] placement and rebuild signals for the
/// graph rendering layer.
///
/// Listens to the [ViewportCuller] to determine which nodes are visible
/// and therefore need their own [RepaintBoundary]. When the visible set
/// changes, this coordinator notifies listeners so the widget tree can
/// be rebuilt efficiently.
///
/// Usage:
/// ```dart
/// final coordinator = NodeRenderCoordinator(
///   viewportCuller: culler,
///   persons: persons,
///   policy: RepaintBoundaryPolicy.perNode,
/// );
/// coordinator.addListener(rebuildCallback);
/// ```
class NodeRenderCoordinator extends ChangeNotifier {
  /// Creates a coordinator bound to the given [viewportCuller].
  ///
  /// [persons] is the full set of person nodes in the graph.
  /// [policy] controls boundary granularity (default: per-node).
  /// [bufferPixels] is the viewport buffer used for visibility checks.
  NodeRenderCoordinator({
    required ViewportCuller viewportCuller,
    required List<GraphPerson> persons,
    RepaintBoundaryPolicy policy = RepaintBoundaryPolicy.perNode,
    double bufferPixels = 200.0,
  })  : _viewportCuller = viewportCuller,
        _persons = persons,
        _policy = policy,
        _bufferPixels = bufferPixels {
    _viewportCuller.addListener(_onViewportChanged);
  }

  final ViewportCuller _viewportCuller;
  final List<GraphPerson> _persons;
  final double _bufferPixels;

  RepaintBoundaryPolicy _policy;

  /// Currently visible node IDs according to the viewport culler.
  Set<String> _visibleNodeIds = <String>{};

  /// Cached generation clusters for [perCluster] policy.
  Map<int, Set<String>> _generationClusters = <int, Set<String>>{};

  // ── Public Getters ───────────────────────────────────────────────

  /// The current repaint boundary policy.
  RepaintBoundaryPolicy get policy => _policy;

  /// The set of node IDs that currently have an active RepaintBoundary.
  Set<String> get activeBoundaryIds => _visibleNodeIds;

  /// Number of active RepaintBoundaries (typically 30–80).
  int get activeBoundaryCount => _visibleNodeIds.length;

  /// The current RepaintBoundary policy.
  set policy(RepaintBoundaryPolicy value) {
    if (_policy == value) return;
    _policy = value;
    _rebuildGenerationClusters();
    notifyListeners();
  }

  // ── Lifecycle ────────────────────────────────────────────────────

  @override
  void dispose() {
    _viewportCuller.removeListener(_onViewportChanged);
    super.dispose();
  }

  // ── Public Methods ───────────────────────────────────────────────

  /// Updates the person list (e.g. after a branch expand/collapse).
  void updatePersons(List<GraphPerson> persons) {
    // Check for actual change before notifying.
    if (listEquals(
      _persons.map((GraphPerson p) => p.id).toList(),
      persons.map((GraphPerson p) => p.id).toList(),
    )) {
      return;
    }
    // Mutating the list reference; listeners will rebuild.
    _persons
      ..clear()
      ..addAll(persons);
    _rebuildGenerationClusters();
    notifyListeners();
  }

  /// Returns whether a node with [nodeId] should be wrapped in a
  /// RepaintBoundary according to the current policy and viewport.
  bool shouldWrapInBoundary(String nodeId) {
    switch (_policy) {
      case RepaintBoundaryPolicy.perNode:
        return _visibleNodeIds.contains(nodeId);
      case RepaintBoundaryPolicy.perCluster:
        return _clusterContainsVisibleNode(nodeId);
      case RepaintBoundaryPolicy.single:
        // Single boundary wraps all nodes; individual nodes are not
        // wrapped.
        return false;
    }
  }

  /// Returns whether a node is currently within the viewport + buffer
  /// zone and should be built (even if not painted).
  bool isNodeVisible(String nodeId) => _visibleNodeIds.contains(nodeId);

  /// Returns the set of node IDs in the same generation cluster as
  /// [nodeId]. Only meaningful when policy is [perCluster].
  Set<String> clusterForNode(String nodeId) {
    final person = _persons.cast<GraphPerson?>().firstWhere(
          (GraphPerson? p) => p?.id == nodeId,
          orElse: () => null,
        );
    if (person == null) return <String>{};
    return _generationClusters[person.generationIndex] ?? <String>{};
  }

  /// Builds the widget tree fragment for a single node, wrapped in a
  /// RepaintBoundary if the current policy requires it.
  ///
  /// [nodeId] identifies the node.
  /// [builder] creates the node widget subtree.
  Widget buildNode({
    required String nodeId,
    required WidgetBuilder builder,
    required BuildContext context,
  }) {
    final child = builder(context);
    if (!shouldWrapInBoundary(nodeId)) return child;

    return RepaintBoundary(
      key: KeyStrategy.nodeKey(nodeId),
      child: child,
    );
  }

  /// Builds the edge layer as a single CustomPainter inside one
  /// RepaintBoundary.
  ///
  /// [edgePainter] is the CustomPainter that draws all visible edges.
  Widget buildEdgeLayer({
    required CustomPainter edgePainter,
  }) {
    return RepaintBoundary(
      key: KeyStrategy.edgeLayerKey(),
      child: CustomPaint(
        painter: edgePainter,
        size: Size.infinite,
      ),
    );
  }

  /// Builds a legend widget inside its own RepaintBoundary.
  Widget buildLegend({
    required WidgetBuilder builder,
    required BuildContext context,
  }) {
    return RepaintBoundary(
      key: KeyStrategy.legendKey(),
      child: builder(context),
    );
  }

  /// Builds a search bar widget inside its own RepaintBoundary.
  Widget buildSearchBar({
    required WidgetBuilder builder,
    required BuildContext context,
  }) {
    return RepaintBoundary(
      key: KeyStrategy.searchBarKey(),
      child: builder(context),
    );
  }

  /// Builds a filter panel widget inside its own RepaintBoundary.
  Widget buildFilterPanel({
    required WidgetBuilder builder,
    required BuildContext context,
  }) {
    return RepaintBoundary(
      key: KeyStrategy.filterPanelKey(),
      child: builder(context),
    );
  }

  /// Wraps the entire graph content (nodes, edges, overlays) so that
  /// the camera [Transform] sits OUTSIDE all RepaintBoundaries.
  ///
  /// This ensures that pan/zoom only invalidates the transform layer,
  /// not individual node or edge boundaries.
  Widget applyCameraTransform({
    required Matrix4 transform,
    required Widget child,
  }) {
    return Transform(
      transform: transform,
      alignment: Alignment.topLeft,
      child: child,
    );
  }

  // ── Private Methods ──────────────────────────────────────────────

  /// Called when the viewport culler detects a visibility change.
  void _onViewportChanged() {
    final newVisible = _viewportCuller.currentVisibleIds;
    if (setEquals(_visibleNodeIds, newVisible)) return;

    final added = newVisible.difference(_visibleNodeIds).length;
    final removed = _visibleNodeIds.difference(newVisible).length;

    _visibleNodeIds = Set<String>.of(newVisible);

    // Track render boundary changes in analytics.
    if (added > 0 || removed > 0) {
      AnalyticsService.instance.logGraphNodeTapped();
    }

    notifyListeners();
  }

  /// Rebuilds the generation cluster map from [_persons].
  void _rebuildGenerationClusters() {
    final clusters = <int, Set<String>>{};
    for (final person in _persons) {
      clusters.putIfAbsent(person.generationIndex, () => <String>{});
      clusters[person.generationIndex]!.add(person.id);
    }
    _generationClusters = clusters;
  }

  /// Returns true if any node in [nodeId]'s generation cluster is
  /// visible. Used by [perCluster] policy.
  bool _clusterContainsVisibleNode(String nodeId) {
    final person = _persons.cast<GraphPerson?>().firstWhere(
          (GraphPerson? p) => p?.id == nodeId,
          orElse: () => null,
        );
    if (person == null) return false;
    final cluster = _generationClusters[person.generationIndex];
    if (cluster == null) return false;
    return cluster.intersection(_visibleNodeIds).isNotEmpty;
  }
}

/// Compares two sets for equality.
bool setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  for (final item in a) {
    if (!b.contains(item)) return false;
  }
  return true;
}
