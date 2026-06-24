// lib/graph/rendering/viewport_culler.dart
//
// DAXELO KINREL — Viewport Culler (V2.1 Rendering Layer)
//
// Computes which graph nodes are visible within the current viewport.
// Nodes outside the viewport + buffer zone are culled (not built),
// reducing widget count from potentially thousands to 30–80 visible
// nodes. Edges are only built when BOTH endpoint nodes are visible.
//
// Rebuild is triggered only when the camera pans/zooms beyond a
// configurable threshold (default 50 px), preventing excessive
// recalculation during smooth animations.

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// ═══════════════════════════════════════════════════════════════════════
// VIEWPORT CULLER
// ═══════════════════════════════════════════════════════════════════════

/// Virtualization engine that culls off-screen graph nodes.
///
/// The culler maintains the set of visible node IDs and notifies
/// listeners whenever the visible set changes. It uses a bounding-box
/// intersection test with a configurable buffer zone around the viewport.
///
/// Buffer zone strategy:
/// - Nodes fully inside the viewport are built AND painted.
/// - Nodes in the buffer zone are built but may be clipped (ensures
///   smooth entry/exit animations).
/// - Nodes outside the viewport + buffer are not built at all.
///
/// Typical usage:
/// ```dart
/// final culler = ViewportCuller(
///   viewport: Rect.fromLTWH(0, 0, 400, 800),
///   bufferPixels: 200,
/// );
/// final visible = culler.cull(positions, nodeSizes, viewport);
/// ```
class ViewportCuller extends ChangeNotifier {
  /// Creates a viewport culler with the given initial parameters.
  ///
  /// [viewport] is the initial visible rectangle in graph-space
  /// coordinates.
  /// [bufferPixels] is the buffer zone around the viewport (default:
  ///   200 px). Nodes within this zone are built but may be clipped.
  /// [rebuildThreshold] is the minimum pan/zoom displacement that
  ///   triggers a rebuild (default: 50 px).
  ViewportCuller({
    required Rect viewport,
    double bufferPixels = 200.0,
    double rebuildThreshold = 50.0,
  })  : _lastViewport = viewport,
        _bufferPixels = bufferPixels,
        _rebuildThreshold = rebuildThreshold;

  double _bufferPixels;
  double _rebuildThreshold;
  Rect _lastViewport;

  /// The current set of visible node IDs.
  Set<String> _currentVisibleIds = <String>{};

  // ── Public Getters ───────────────────────────────────────────────

  /// The current set of visible node IDs (viewport + buffer zone).
  Set<String> get currentVisibleIds =>
      Set<String>.unmodifiable(_currentVisibleIds);

  /// Number of currently visible nodes.
  int get visibleCount => _currentVisibleIds.length;

  /// The buffer zone size in pixels.
  double get bufferPixels => _bufferPixels;

  /// The rebuild threshold in pixels.
  double get rebuildThreshold => _rebuildThreshold;

  // ── Setters ──────────────────────────────────────────────────────

  /// Updates the buffer zone size. Triggers a recalculation on the
  /// next [cull] call.
  set bufferPixels(double value) {
    if (_bufferPixels == value) return;
    _bufferPixels = value;
  }

  /// Updates the rebuild threshold.
  set rebuildThreshold(double value) {
    if (_rebuildThreshold == value) return;
    _rebuildThreshold = value;
  }

  // ── Core API ─────────────────────────────────────────────────────

  /// Computes the set of visible node IDs for the given [viewport].
  ///
  /// [positions] maps node IDs to their center positions in graph
  ///   space.
  /// [nodeSizes] maps node IDs to their visual sizes (width, height).
  /// [viewport] is the current visible rectangle in graph space.
  ///
  /// Returns the set of visible node IDs. Also updates
  /// [currentVisibleIds] and notifies listeners if the set changed.
  ///
  /// If the viewport has not moved beyond [rebuildThreshold] since the
  /// last call, the previous result is returned without recalculation.
  Set<String> cull(
    Map<String, Offset> positions,
    Map<String, Size> nodeSizes,
    Rect viewport,
  ) {
    // Skip recalculation if viewport hasn't moved enough.
    if (!shouldRebuild(_lastViewport, viewport)) {
      return _currentVisibleIds;
    }

    final expandedViewport = _expandViewport(viewport);
    final visible = <String>{};

    for (final entry in positions.entries) {
      final nodeId = entry.key;
      final position = entry.value;
      final size = nodeSizes[nodeId] ?? const Size(100.0, 120.0);

      if (isNodeVisible(nodeId, position, size, expandedViewport)) {
        visible.add(nodeId);
      }
    }

    // ── BLANK-SCREEN SAFETY NET ──────────────────────────────────────────
    // If culling produced an empty set but there ARE nodes to show, the
    // viewport is almost certainly mis-aligned with graph-space — e.g. the
    // camera is still at the origin (pan 0,0 / zoom 1.0) while the
    // center-anchored layout places every node far from (0,0) on the first
    // frame. Rather than render a fully blank canvas (the historical v40
    // regression), fall back to showing every node so the user ALWAYS sees
    // content. The next cull (after the initial fit moves the camera) returns
    // the correct, much smaller visible set.
    if (visible.isEmpty && positions.isNotEmpty) {
      visible.addAll(positions.keys);
    }

    final changed = !_setsEqual(_currentVisibleIds, visible);
    _lastViewport = viewport;
    _currentVisibleIds = visible;

    if (changed) {
      notifyListeners();
    }

    return Set<String>.unmodifiable(_currentVisibleIds);
  }

  /// Returns whether a single node is visible within the given
  /// [viewport].
  ///
  /// The test uses bounding-box intersection. The node's bounding box
  /// is derived from its center [position] and [nodeSize].
  /// [viewport] should already include the buffer zone expansion if
  /// buffer behavior is desired.
  bool isNodeVisible(
    String nodeId,
    Offset position,
    Size nodeSize,
    Rect viewport,
  ) {
    // Compute the node's bounding box centered at position.
    final nodeRect = Rect.fromCenter(
      center: position,
      width: nodeSize.width,
      height: nodeSize.height,
    );
    return viewport.overlaps(nodeRect);
  }

  /// Returns whether an edge should be built, which requires BOTH
  /// endpoint nodes to be visible.
  ///
  /// [sourceId] is the source node ID.
  /// [targetId] is the target node ID.
  /// [visibleNodeIds] is the current set of visible node IDs.
  bool isEdgeVisible(
    String sourceId,
    String targetId,
    Set<String> visibleNodeIds,
  ) {
    return visibleNodeIds.contains(sourceId) &&
        visibleNodeIds.contains(targetId);
  }

  /// Returns whether the viewport has moved beyond the rebuild
  /// threshold since the last [cull] call.
  ///
  /// Compares the distance between [oldViewport] and [newViewport]
  /// centers (for pan) and the relative scale change (for zoom).
  /// Returns true if either dimension exceeds [rebuildThreshold].
  bool shouldRebuild(Rect oldViewport, Rect newViewport) {
    // Check pan displacement.
    final panDx = (newViewport.left - oldViewport.left).abs();
    final panDy = (newViewport.top - oldViewport.top).abs();
    final panDistance = math.sqrt(panDx * panDx + panDy * panDy);

    if (panDistance >= _rebuildThreshold) return true;

    // Check zoom change (relative scale difference).
    final oldArea = oldViewport.width * oldViewport.height;
    final newArea = newViewport.width * newViewport.height;
    if (oldArea > 0) {
      final areaRatio = (newArea / oldArea - 1.0).abs();
      // A 10% zoom change is enough to warrant a rebuild.
      if (areaRatio > 0.1) return true;
    }

    return false;
  }

  /// Forces a full recalculation on the next [cull] call, regardless
  /// of the rebuild threshold.
  void invalidate() {
    // Set lastViewport to something impossibly far away.
    _lastViewport = Rect.zero;
  }

  /// Resets the culler to an empty state.
  void reset() {
    _currentVisibleIds = <String>{};
    _lastViewport = Rect.zero;
    notifyListeners();
  }

  // ── Private Helpers ──────────────────────────────────────────────

  /// Expands the viewport by [_bufferPixels] on all sides.
  Rect _expandViewport(Rect viewport) {
    return Rect.fromLTRB(
      viewport.left - _bufferPixels,
      viewport.top - _bufferPixels,
      viewport.right + _bufferPixels,
      viewport.bottom + _bufferPixels,
    );
  }

  /// Compares two sets for equality.
  static bool _setsEqual<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }
}
