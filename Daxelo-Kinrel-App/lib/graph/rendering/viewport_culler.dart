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

  /// v84: Tracks the last-seen node ID set so we can detect when
  /// nodes are added/removed (not just when the viewport moves).
  /// Without this, adding a member without panning causes the culler
  /// to return a STALE visible set that excludes the new node —
  /// and since edges only render when BOTH endpoints are visible,
  /// the connection line is silently dropped.
  Set<String> _lastNodeIds = const <String>{};

  // ── v5.142 (DIAGNOSTICS): Culler stats for the perf overlay ──────
  //
  // These fields are read by GraphPerformanceDiagnostics to show the
  // user (in profile/debug mode) whether the culler is actually
  // excluding off-screen nodes. If `totalPositionsSeen` is 200 but
  // `visibleCount` is also 200, the culler is NOT culling — which
  // means either (a) the viewport is mis-aligned with graph-space,
  // or (b) the blank-screen safety net fired (see `cull()`).
  //
  // All fields are updated in `cull()` and reset only when the culler
  // is constructed or `invalidate()` is called.

  /// Total number of positions passed to the last `cull()` call.
  /// This is the denominator for the cull ratio
  /// (`visibleCount / totalPositionsSeen`).
  int _totalPositionsSeen = 0;

  /// Number of times `cull()` has actually recomputed the visible
  /// set (vs. returned the cached result). A high count during a
  /// slow pan indicates the rebuild threshold is too low for this
  /// device — each rebuild costs O(N) where N = total positions.
  int _rebuildCount = 0;

  /// Number of times `cull()` has short-circuited (returned the
  /// cached result without recomputation). A high skip count is
  /// GOOD — it means the rebuild threshold is doing its job.
  int _skipCount = 0;

  /// The last reason `cull()` recomputed or skipped. Human-readable,
  /// shown in the diagnostics overlay so the user can see WHY the
  /// culler is rebuilding (e.g. "viewport moved 75px > 50px threshold"
  /// vs "node set changed" vs "skipped: viewport moved 12px < 50px").
  String _lastActionReason = 'initialized';

  /// v5.142 (DIAGNOSTICS): Whether cull() has been called at least
  /// once. Used to detect the "first call" case for the reason string
  /// (since _lastViewport is non-nullable and initialized in the
  /// constructor, we can't use nullness to detect first call).
  bool _hasCulled = false;

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

  /// v5.142 (DIAGNOSTICS): Total positions passed to the last cull.
  int get totalPositionsSeen => _totalPositionsSeen;

  /// v5.142 (DIAGNOSTICS): Number of times cull() recomputed.
  int get rebuildCount => _rebuildCount;

  /// v5.142 (DIAGNOSTICS): Number of times cull() short-circuited.
  int get skipCount => _skipCount;

  /// v5.142 (DIAGNOSTICS): Human-readable reason for the last action.
  String get lastActionReason => _lastActionReason;

  /// v5.142 (DIAGNOSTICS): The cull ratio (0.0–1.0). 1.0 means the
  /// culler is NOT culling (every node is visible). 0.1 means only
  /// 10% of nodes are visible (good culling on a large family).
  double get cullRatio => _totalPositionsSeen > 0
      ? _currentVisibleIds.length / _totalPositionsSeen
      : 0.0;

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

  /// Recommended buffer zone (in graph-space pixels) for a graph with
  /// [memberCount] members.
  ///
  /// The fixed 200px default is generous and works well for small /
  /// medium families where the on-screen node density is low — the
  /// extra buffer keeps nodes built slightly before they enter the
  /// viewport, giving smooth pan/zoom entry/exit animations.
  ///
  /// For LARGE graphs (hundreds to thousands of members) the same 200px
  /// buffer becomes wasteful: it keeps many off-screen nodes built even
  /// though the on-screen node density is already high enough that
  /// smooth entry/exit is perceptually unnecessary. This helper scales
  /// the buffer DOWN as the member count grows:
  ///
  ///   • < 100 members   → 200px (default, generous)
  ///   • 100–499         → 140px
  ///   • 500–1499        → 90px
  ///   • 1500+           → 60px
  ///
  /// The minimum (60px) is still larger than a single node footprint
  /// (~72px diameter) so a node never pops in at the very edge — it
  /// always has at least ~half a node-width of pre-build margin.
  ///
  /// Callers should call this whenever the member count changes (e.g.
  /// when [flat.persons] changes) and assign the result to
  /// [bufferPixels]. The culler's [invalidate] should also be called
  /// so the next [cull] uses the new buffer immediately.
  static double recommendedBufferForMemberCount(int memberCount) {
    if (memberCount < 100) return 200.0;
    if (memberCount < 500) return 140.0;
    if (memberCount < 1500) return 90.0;
    return 60.0;
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
    // v5.142 (DIAGNOSTICS): Track total positions for the cull ratio.
    _totalPositionsSeen = positions.length;

    // v84 FIX: Also force recomputation when the node ID set changes
    // (e.g. member added, member deleted, expand/collapse). Previously,
    // the culler only recomputed when the viewport moved >80px, so
    // adding a member WITHOUT panning left the new node invisible —
    // and its connecting edge was silently dropped because
    // isEdgeVisible() requires BOTH endpoints to be in the visible set.
    final currentNodeIds = positions.keys.toSet();
    final nodeSetChanged = !_setsEqual(_lastNodeIds, currentNodeIds);

    // Compute the viewport displacement for the diagnostics reason
    // string (helps the user see WHY the culler is rebuilding).
    final viewportDisplacement = !_hasCulled
        ? double.infinity
        : (Offset(
                  viewport.center.dx - _lastViewport.center.dx,
                  viewport.center.dy - _lastViewport.center.dy,
                ))
                .distance;

    // Skip recalculation if viewport hasn't moved enough AND node set
    // hasn't changed.
    if (_hasCulled &&
        !nodeSetChanged &&
        !shouldRebuild(_lastViewport, viewport)) {
      _skipCount++;
      _lastActionReason = 'skipped: viewport moved '
          '${viewportDisplacement.toStringAsFixed(0)}px '
          '< ${_rebuildThreshold.toStringAsFixed(0)}px threshold';
      return _currentVisibleIds;
    }

    // Record the reason for this rebuild.
    if (!_hasCulled) {
      _lastActionReason = 'rebuilt: first call';
    } else if (nodeSetChanged) {
      _lastActionReason = 'rebuilt: node set changed '
          '(${_lastNodeIds.length} → ${currentNodeIds.length} nodes)';
    } else {
      _lastActionReason = 'rebuilt: viewport moved '
          '${viewportDisplacement.toStringAsFixed(0)}px '
          '> ${_rebuildThreshold.toStringAsFixed(0)}px threshold';
    }
    _rebuildCount++;
    _hasCulled = true;

    _lastNodeIds = currentNodeIds;

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

  /// Returns whether an edge should be built, using a viewport-aware test
  /// that keeps edges visible even when BOTH endpoint nodes are off-screen
  /// (e.g. when zoomed in and the connecting line passes through the
  /// viewport).
  ///
  /// An edge is considered visible when ANY of the following is true:
  ///   1. At least one endpoint node is in [visibleNodeIds] (preserves
  ///      the original behaviour for nodes near the viewport edge and
  ///      gives smooth entry/exit animations).
  ///   2. The edge's straight bounding segment from [sourcePos] to
  ///      [targetPos] intersects the (already buffer-expanded) graph-space
  ///      [viewport]. This catches the common zoomed-in case where both
  ///      endpoints are off-screen but the line between them crosses the
  ///      visible area. The bezier curve used by the painter stays close
  ///      to this segment for our short family-tree edges, so the segment
  ///      test is a tight-enough approximation and is O(1) per edge.
  ///
  /// Pass the SAME buffered viewport that [cull] uses internally — i.e.
  /// call [cull] first to populate [visibleNodeIds], then call this with
  /// the buffer-expanded viewport rect. The caller can obtain the
  /// expanded viewport via [expandedViewport].
  ///
  /// [sourceId] / [targetId] — endpoint node IDs.
  /// [sourcePos] / [targetPos] — endpoint node CENTRES in graph space.
  /// [visibleNodeIds] — the visible node ID set produced by [cull].
  /// [viewport] — the BUFFER-EXPANDED graph-space viewport rect.
  bool isEdgeVisibleWithViewport({
    required String sourceId,
    required String targetId,
    required Offset sourcePos,
    required Offset targetPos,
    required Set<String> visibleNodeIds,
    required Rect viewport,
  }) {
    // Fast path: at least one endpoint is visible → keep the edge.
    if (visibleNodeIds.contains(sourceId) ||
        visibleNodeIds.contains(targetId)) {
      return true;
    }

    // Both endpoints are off-screen. Fall back to a segment-vs-rect
    // intersection test so the connecting line does not disappear when
    // the user zooms in on the middle of a long edge.
    return _segmentIntersectsRect(sourcePos, targetPos, viewport);
  }

  /// Returns the buffer-expanded version of [viewport].
  ///
  /// Exposed so callers can build the same expanded rect that [cull]
  /// uses internally, for use in [isEdgeVisibleWithViewport].
  Rect expandedViewport(Rect viewport) => _expandViewport(viewport);

  /// Liang–Barsky segment-vs-rect intersection test.
  ///
  /// Returns true if the segment from [a] to [b] intersects (or is
  /// contained within) [rect]. Used to keep edges visible when both
  /// endpoint nodes are off-screen but the line crosses the viewport.
  ///
  /// The segment is parameterised as P(t) = a + t·(b − a) for t ∈ [0, 1].
  /// For each of the four rect edges we compute the t-range that lies
  /// inside that edge's half-plane and intersect it with the running
  /// [t0, t1] window. If the window stays valid (t0 ≤ t1) after all
  /// four edges, the segment intersects the rect.
  ///
  /// This is O(1) and branch-friendly — important because it runs for
  /// every edge on every cull rebuild.
  bool _segmentIntersectsRect(Offset a, Offset b, Rect rect) {
    final double dx = b.dx - a.dx;
    final double dy = b.dy - a.dy;
    double t0 = 0.0;
    double t1 = 1.0;

    // Helper: clip the running [t0, t1] window against one half-plane.
    // p is the component of the segment direction along the edge normal
    // (sign indicates entering vs exiting), q is the signed distance
    // from the segment start to the edge. Returns false if the segment
    // is entirely outside this half-plane (early reject).
    bool clip(double p, double q) {
      if (p < 0) {
        // Segment potentially ENTERS the half-plane at t = q / p.
        final double r = q / p;
        if (r > t1) return false; // enters after the window ends
        if (r > t0) t0 = r;
      } else if (p > 0) {
        // Segment potentially EXITS the half-plane at t = q / p.
        final double r = q / p;
        if (r < t0) return false; // exits before the window starts
        if (r < t1) t1 = r;
      } else {
        // p == 0: segment is parallel to this edge. If q < 0 the whole
        // segment is outside this half-plane.
        if (q < 0) return false;
      }
      return true;
    }

    // Left edge:   x >= rect.left   →  p = -dx, q = a.dx - rect.left
    if (!clip(-dx, a.dx - rect.left)) return false;
    // Right edge:  x <= rect.right  →  p =  dx, q = rect.right - a.dx
    if (!clip(dx, rect.right - a.dx)) return false;
    // Top edge:    y >= rect.top    →  p = -dy, q = a.dy - rect.top
    if (!clip(-dy, a.dy - rect.top)) return false;
    // Bottom edge: y <= rect.bottom →  p =  dy, q = rect.bottom - a.dy
    if (!clip(dy, rect.bottom - a.dy)) return false;

    return t0 <= t1;
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
