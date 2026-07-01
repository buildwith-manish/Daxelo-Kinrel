// lib/graph/widgets/family_graph_engine_view.dart
//
// DAXELO KINREL — Family Graph (V2.1 Engine view)
//
// v68: This is the SOLE graph renderer. The old v40 FamilyGraphWidget
// (family_graph.dart) has been removed — this engine is no longer gated
// behind a feature flag.
//
// Performance design (Steps 3/4 of Path B — see docs/graph/PATH_B_REWIRE.md):
//
//   • Viewport culling      — ViewportCuller builds only on-screen nodes/edges.
//   • Edge path caching      — EdgePathCache memoises bezier Paths keyed by
//                             quantized endpoints. Graph-space positions don't
//                             change during pan/zoom, so paths are pure cache
//                             hits across frames (no per-frame recompute, and
//                             NO per-edge O(N) collision scan).
//   • Level of detail (LOD)  — zoomed in: full GraphNode; mid: lightweight name
//                             chips; zoomed out: a SINGLE CustomPainter draws
//                             every node as a dot (no per-node widgets), which
//                             is what keeps 1000–2000 nodes smooth.
//   • Cheap pan/zoom         — content is built once per cull/LOD change and
//                             wrapped in a RepaintBoundary; an AnimatedBuilder
//                             re-applies only the camera Transform on each
//                             frame, so panning reuses the cached raster.
//
// Also wired to the live providers:
//   • Initial fit   — CameraController.initialFitOnce() (blank-screen fix).
//   • Position memory — CameraController persists/restores pan+zoom per family.
//   • Realtime       — graphRealtimeProvider invalidation while mounted.
//   • Offline        — isOnlineProvider banner; Drift cache serves data offline.
//   • Expand/collapse — long-press a node to toggle its descendants.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/sync/connectivity_service.dart' show isOnlineProvider;
import '../../core/services/analytics_service.dart';
import '../../core/services/graph_layout_service.dart' show GraphLayoutResult;
import '../../features/family/presentation/providers/family_graph_provider.dart'
    show
        FlatGraphResult,
        familyGraphProvider,
        graphLayoutProvider,
        graphRealtimeProvider,
        selectedEdgeProvider,
        selectedNodeProvider;
import '../data/family_graph_repository.dart' show GraphEdgeData;
import '../data/position_memory.dart' show PositionMemory;
import '../engine/edge_dedup.dart' show DedupedEdge, EdgeDeduplicator;
import '../interaction/camera_controller.dart' show CameraController;
import '../interaction/expand_collapse.dart'
    show ExpandCollapseController, ExpandCollapseState;
import '../../core/constants/feature_flags.dart' show kEnableGraphShareExport;
import '../../core/constants/brand_colors.dart' show KinrelColors;
import '../../core/kinship/kinship_edge_style.dart';
import '../../core/kinship/kinship_service.dart' show KinshipService;
import '../../core/relationship/relationship_engine.dart' show RelationshipEngine;
import '../../core/services/graph_layout_service.dart' show GraphPerson;
import '../../core/viewer/viewer_provider.dart' show viewerPersonIdProvider;
import '../../core/viewer/viewer_api_client.dart'
    show viewerApiClientProvider;
import '../../features/family/presentation/services/graph_export_service.dart'
    show GraphExportService;
import '../rendering/edge_path_cache.dart' show EdgePathCache;
import '../rendering/viewport_culler.dart' show ViewportCuller;
import 'graph_node.dart' show GraphNode;
import 'graph_legend.dart' show GraphLegend;
import 'graph_quick_actions.dart' show GraphQuickActions;
import 'graph_relationship_labels.dart' show GraphPersonData;

/// LOD tiers, chosen by camera zoom.
enum _Lod {
  /// Full interactive node cards.
  full,

  /// Lightweight name-only chips.
  chip,

  /// Single painter draws every node as a dot (max scale).
  dot,
}

/// Returns true if the current user has an explicit `linkedUserId` link
/// to their Person node in this family (as opposed to falling back to
/// `isAnchor` via [viewerPersonIdProvider]).
///
/// GAP 3 FIX: Used by [FamilyGraphEngineView] to decide whether to show
/// the "_ClaimProfileBanner". When the authenticated user has not yet
/// claimed a Person node, the viewer silently resolves to the anchor —
/// the graph renders but from the wrong perspective. This provider
/// surfaces that state so the UI can prompt the user to claim.
///
/// Returns `true` on error so we never show a false-positive banner —
/// the graph stays usable even if the viewer-resolution endpoint fails.
final _isViewerLinkedProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, familyId) async {
  try {
    final client = ref.read(viewerApiClientProvider);
    final resolution = await client.resolveViewer(familyId);
    return resolution.isLinked;
  } catch (_) {
    // Assume linked on error — don't show banner unnecessarily
    return true;
  }
});

/// Engine-backed family graph view (see file header).
class FamilyGraphEngineView extends ConsumerStatefulWidget {
  const FamilyGraphEngineView({
    super.key,
    required this.familyId,
    this.highlightedGeneration,
    this.recenterKey,
  });

  /// The family whose graph to render.
  final String familyId;

  /// v62: Generation to highlight (null = show all). When set, nodes
  /// NOT in this generation are dimmed to 15% opacity. Passed from
  /// the parent screen's generation filter chip bar.
  final int? highlightedGeneration;

  /// v62: When this value changes, the camera re-centers on the
  /// anchor node. Passed from the parent screen's "Center on Root"
  /// button.
  final int? recenterKey;

  @override
  ConsumerState<FamilyGraphEngineView> createState() =>
      _FamilyGraphEngineViewState();
}

class _FamilyGraphEngineViewState
    extends ConsumerState<FamilyGraphEngineView> {
  /// Bounding box used for culling + node placement (circle + label).
  static const Size _kNodeSize = Size(96, 120);

  /// The visual circle diameter inside each node (GraphNode.nodeSize).
  /// The circle is at the TOP of the Column, so its visual center is
  /// offset from the Positioned center by:
  ///   circleCenterY = boxTop + diameter/2
  ///   boxCenterY    = boxTop + boxHeight/2
  ///   offset = circleCenterY - boxCenterY = diameter/2 - boxHeight/2
  ///          = 72/2 - 120/2 = 36 - 60 = -24
  /// Edge endpoints must use this offset so lines connect to the
  /// visual circle center, not the Positioned box center.
  static const double _kCircleCenterYOffset = 36.0 - 60.0; // = -24.0

  /// Zoom thresholds for LOD tiers.
  static const double _kChipZoom = 0.55;
  static const double _kDotZoom = 0.3;

  late final PositionMemory _positionMemory;
  late final CameraController _camera;
  late final ViewportCuller _culler;
  late final ExpandCollapseController _expandCollapse;
  final EdgePathCache _edgePathCache = EdgePathCache();

  /// Wraps the on-screen graph so it can be captured for share/export.
  final GlobalKey _graphBoundaryKey = GlobalKey();

  /// v62: Periodic telemetry timer — logs edge cache hit rate + cull
  /// stats every 30 seconds while the graph is mounted.
  Timer? _telemetryTimer;
  int _lastCullVisibleCount = 0;

  /// v62: Position of the last double-tap, for zoom-toward-focal-point.
  Offset _doubleTapPosition = Offset.zero;

  Size _viewportSize = Size.zero;
  bool _framed = false; // one-time initial framing per family

  // PERF: Cache relation labels/keys so they don't recompute on every
  // pan/zoom frame. Only recompute when the underlying flat data changes.
  FlatGraphResult? _lastFlat;
  String? _lastViewerId;
  Map<String, String>? _cachedRelationLabels;
  Map<String, String>? _cachedRelationKeys;

  // Repaint/recull throttling.
  Rect _lastCullViewport = Rect.zero;
  _Lod _lastLod = _Lod.full;

  // Gesture bookkeeping for pan + pinch-zoom.
  Offset _lastFocal = Offset.zero;
  double _baseZoom = 1.0;

  /// v2.2: Whether the graph legend panel is visible.
  /// Toggled by the "?" button in the bottom-left corner.
  bool _showLegend = false;

  @override
  void initState() {
    super.initState();
    _positionMemory = PositionMemory();
    _camera = CameraController(positionMemory: _positionMemory)
      ..setFamilyId(widget.familyId)
      ..addListener(_onCameraChanged);
    _culler = ViewportCuller(
      viewport: Rect.zero,
      bufferPixels: 300,
      rebuildThreshold: 80,
    );
    _expandCollapse =
        ExpandCollapseController(const ExpandCollapseState());

    // v62: Start periodic telemetry — log edge cache + cull stats every
    // 30 seconds so we can monitor production performance.
    _telemetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      // Fire-and-forget — never let telemetry break the build.
      AnalyticsService.instance
          .logEvent('graph_render_stats', {
            'edge_cache_size': _edgePathCache.size,
            'edge_cache_hit_rate': _edgePathCache.hitRate,
            'edge_cache_hits': _edgePathCache.hits,
            'edge_cache_misses': _edgePathCache.misses,
            'visible_node_count': _culler.visibleCount,
            'zoom_level': double.parse(_camera.zoomLevel.toStringAsFixed(2)),
          })
          .catchError((Object e) {
        debugPrint('⚠️ Analytics (suppressed): $e');
      });
    });
  }

  @override
  void didUpdateWidget(covariant FamilyGraphEngineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyId != widget.familyId) {
      _framed = false;
      _camera
        ..resetInitialFit()
        ..setFamilyId(widget.familyId);
      _culler.invalidate();
      _edgePathCache.clear();
      _expandCollapse.updateVisibleNodes(<String>{});
    }
    // v62: Re-center when recenterKey changes (Center on Root button).
    if (oldWidget.recenterKey != widget.recenterKey) {
      _framed = false;
      _camera.resetInitialFit();
      _culler.invalidate();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _camera.removeListener(_onCameraChanged);
    _camera.dispose();
    _culler.dispose();
    _expandCollapse.dispose();
    _positionMemory.dispose();
    super.dispose();
  }

  /// Rebuild content ONLY when the visible set or LOD tier would change.
  /// Otherwise the AnimatedBuilder pans/zooms the Transform layer for free.
  void _onCameraChanged() {
    if (!mounted) return;
    final Rect vp = _graphSpaceViewport();
    final _Lod lod = _lodFor(_camera.zoomLevel);
    if (lod != _lastLod || _culler.shouldRebuild(_lastCullViewport, vp)) {
      setState(() {});
    }
  }

  _Lod _lodFor(double zoom) {
    if (zoom >= _kChipZoom) return _Lod.full;
    if (zoom >= _kDotZoom) return _Lod.chip;
    return _Lod.dot;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Keep Supabase Realtime invalidation alive while this view is mounted.
    ref.watch(graphRealtimeProvider(widget.familyId));

    final bool isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final layoutAsync = ref.watch(graphLayoutProvider(widget.familyId));
    final flat = ref.watch(familyGraphProvider(widget.familyId)).valueOrNull;
    // PERF: selectedEdgeProvider is NOT watched here — it's watched inside
    // _EdgeSelectionWrapper (a separate ConsumerWidget) so that tapping an
    // edge only rebuilds the edge painter, not the entire canvas.
    // v2.2: Resolve the viewer's Person ID for perspective-based rendering.
    final viewerPersonId =
        ref.watch(viewerPersonIdProvider(widget.familyId)).valueOrNull;

    // GAP 3 FIX: Detect if the viewer resolved via anchor fallback (not
    // linked). When the authenticated user has not claimed a Person node
    // in this family, viewerPersonIdProvider silently falls back to the
    // anchor person — the graph looks "wrong" from the user's perspective
    // but gives no indication why. We surface a banner prompting them to
    // claim their profile.
    //
    // The check is best-effort: if _isViewerLinkedProvider hasn't resolved
    // yet (loading) or errors, we assume "linked" so we never block the
    // graph UI or show a false-positive banner.
    final viewerIsLinked =
        ref.watch(_isViewerLinkedProvider(widget.familyId)).valueOrNull ??
            true;
    final viewerIsUnlinked =
        viewerPersonId != null && !viewerIsLinked;

    return layoutAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => _ErrorRetry(
        onRetry: () =>
            ref.invalidate(familyGraphProvider(widget.familyId)),
      ),
      data: (GraphLayoutResult layout) {
        if (layout.positions.isEmpty || flat == null) {
          return const _EmptyGraph();
        }
        // Wrap the graph in a Column so we can show a claim-profile banner
        // above it when the viewer is unlinked. The graph itself expands
        // to fill the remaining space.
        return Column(
          children: [
            // Claim banner — shown when user has no linked Person node
            if (viewerIsUnlinked)
              _ClaimProfileBanner(familyId: widget.familyId),
            // Existing graph widget — expand to fill remaining space
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      key: _graphBoundaryKey,
                      child: _buildCanvas(
                          layout, flat, viewerPersonId),
                    ),
                  ),
                  if (!isOnline)
                    const Positioned(
                        left: 0, right: 0, top: 0, child: _OfflineBanner()),
                  // v2.2: Graph legend — shows section colors + edge styles for
                  // the kinship categories present in the current graph.
                  GraphLegend(
                    isVisible: _showLegend,
                    onToggle: () =>
                        setState(() => _showLegend = !_showLegend),
                    presentCategories: _presentCategories(flat),
                  ),
                  if (kEnableGraphShareExport)
                    // Directional alignment so the FAB sits at the bottom-end
                    // edge (bottom-right in LTR, bottom-left in RTL) instead of
                    // always at the physical right.
                    Align(
                      alignment: AlignmentDirectional.bottomEnd,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: FloatingActionButton.small(
                          heroTag: 'graph_share_export',
                          onPressed: _shareGraph,
                          tooltip: 'Share graph',
                          child: const Icon(Icons.ios_share),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCanvas(
      GraphLayoutResult layout, FlatGraphResult flat, String? viewerPersonId) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // FIX (keyboard-resize): Don't update _viewportSize if the height
        // shrank by more than 25% — that's a keyboard push, not a real
        // resize. The camera was fitted to the original viewport; using
        // a keyboard-shrunken viewport would cause the camera viewport
        // rect to be recalculated incorrectly, making nodes/edges
        // disappear and the background turn white.
        final newHeight = constraints.biggest.height;
        final newWidth = constraints.biggest.width;
        final isKeyboardPush = _viewportSize.height > 0 &&
            newHeight < _viewportSize.height * 0.75;
        if (!isKeyboardPush) {
          final sizeChanged = _viewportSize.width != newWidth ||
              _viewportSize.height != newHeight;
          _viewportSize = constraints.biggest;
          // FIX (culler-invalidation): After a REAL viewport size change
          // (orientation change, window resize — NOT keyboard), invalidate
          // the culler so the next build recalculates visibility with the
          // correct new viewport.
          if (sizeChanged) {
            _culler.invalidate();
          }
        }

        // One-time framing AFTER the first frame — never during build, which
        // avoids the historical setState-during-build crash.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _maybeFrame(layout));

        final personById = <String, Map<String, dynamic>>{
          for (final Map<String, dynamic> p in flat.persons)
            if (p['id'] != null) p['id'] as String: p,
        };
        // PERF: Only recompute relation labels/keys when the underlying
        // flat data or viewer changes — NOT on every pan/zoom frame.
        if (!identical(_lastFlat, flat) || _lastViewerId != viewerPersonId) {
          // CRITICAL FIX: Invalidate the RelationshipEngine cache when
          // graph data changes. Without this, the engine returns stale
          // cached results from before the new person was added, so the
          // new person gets no relationship key → no label → no color.
          RelationshipEngine.instance.invalidateCache();
          _cachedRelationLabels = _relationLabels(flat, viewerPersonId);
          _cachedRelationKeys = _relationKeys(flat, viewerPersonId);
          _lastFlat = flat;
          _lastViewerId = viewerPersonId;
        }
        final relationLabelById = _cachedRelationLabels!;
        final relationKeyById = _cachedRelationKeys!;

        // Expand/collapse filter — empty visible set means "show everything".
        final Set<String> allowed =
            _expandCollapse.state.visibleNodeIds.isEmpty
                ? layout.positions.keys.toSet()
                : _expandCollapse.state.visibleNodeIds;

        // Cull to the on-screen set, then intersect with the allowed set.
        final nodeSizes = <String, Size>{
          for (final String id in layout.positions.keys) id: _kNodeSize,
        };
        final Rect vp = _graphSpaceViewport();
        final Set<String> culled =
            _culler.cull(layout.positions, nodeSizes, vp);
        final Set<String> visible = culled.where(allowed.contains).toSet();

        // Record throttling baselines for _onCameraChanged.
        _lastCullViewport = vp;
        _lastLod = _lodFor(_camera.zoomLevel);

        // Edges: only when BOTH endpoints are visible.
        //
        // v64 (BUG-2 FIX): We collect ALL edges first (no first-match-wins
        // dedup here), then pass them through EdgeDeduplicator.deduplicate()
        // which:
        //   - Collapses duplicate rows (A→B "father" + B→A "child") into ONE
        //     edge, picking the strongest category.
        //   - Keeps DISTINCT categories (e.g. parent + spouse) as separate
        //     edges with lateral offsets so they don't stack on each other.
        final rawEdges = <GraphEdgeData>[];
        for (final Map<String, dynamic> r in flat.relationships) {
          final s = r['fromPersonId'] as String?;
          final t = r['toPersonId'] as String?;
          if (s == null || t == null) continue;
          if (!_culler.isEdgeVisible(s, t, visible)) continue;
          rawEdges.add(GraphEdgeData(
            id: (r['id'] ?? '$s-$t').toString(),
            sourceId: s,
            targetId: t,
            relationshipKey: (r['relationshipKey'] ?? 'unknown').toString(),
            isPrivate: r['isPrivate'] as bool? ?? false,
          ));
        }

        // ── Synthetic edge fallback ─────────────────────────────────────
        // Nodes that exist in the family but have no relationship rows in
        // the DB will appear as floating disconnected circles with no line.
        // For every such node, draw a synthetic dashed 'related' edge to
        // the anchor so the graph always looks connected.
        // This is purely visual — no DB writes occur.
        {
          // Find the anchor person ID from the flat data
          String? anchorId;
          for (final p in flat.persons) {
            if (p['isAnchor'] == true) {
              anchorId = p['id'] as String?;
              break;
            }
          }
          // Fall back to the first person if no anchor
          anchorId ??= flat.persons.isNotEmpty
              ? flat.persons.first['id'] as String?
              : null;
          if (anchorId != null) {
            // Track which node pairs already have a real edge so we don't
            // add a synthetic edge on top of an existing one.
            final existingPairs = <String>{};
            for (final e in rawEdges) {
              final ids = [e.sourceId, e.targetId]..sort();
              existingPairs.add('${ids[0]}_${ids[1]}');
            }
            for (final p in flat.persons) {
              final personId = p['id'] as String?;
              if (personId == null || personId == anchorId) continue;
              if (!visible.contains(personId)) continue;
              final ids = [anchorId, personId]..sort();
              final pairKey = '${ids[0]}_${ids[1]}';
              if (existingPairs.contains(pairKey)) continue;
              existingPairs.add(pairKey);
              rawEdges.add(GraphEdgeData(
                id: 'synthetic_$personId',
                sourceId: anchorId,
                targetId: personId,
                relationshipKey: 'related',
              ));
            }
          }
        }

        // v64 (BUG-2 FIX): Deduplicate with smart category-strength
        // selection + lateral offsets for parallel edges.
        final edges = EdgeDeduplicator.deduplicate(rawEdges);

        // v65 (BUGFIX): Resolve each edge's relationshipKey from the
        // anchor's perspective so the edge LINE color matches the node
        // color. Previously the edge used the raw stored key, which could
        // be the inverse direction (e.g. 'child' instead of 'father'),
        // causing the edge to be pink while the node was blue.
        //
        // For each deduped edge, if one endpoint is the anchor (or the
        // viewer), replace the edge's relationshipKey with the
        // BFS-resolved key for the OTHER endpoint. This guarantees
        // edge color == node color for every anchor-connected edge.
        //
        // The anchor is identified from flat.persons (isAnchor == true),
        // falling back to viewerPersonId. The BFS source used by
        // _relationKeys is one of these two, so checking both covers
        // all cases.
        final String? anchorId = _findAnchorId(flat, viewerPersonId);
        if (anchorId != null && relationKeyById.isNotEmpty) {
          for (int i = 0; i < edges.length; i++) {
            final deduped = edges[i];
            final e = deduped.edge;
            // Determine which endpoint is the anchor and which is the
            // relative. Use the relative's BFS-resolved key.
            final String? relativeKey;
            if (e.sourceId == anchorId) {
              relativeKey = relationKeyById[e.targetId];
            } else if (e.targetId == anchorId) {
              relativeKey = relationKeyById[e.sourceId];
            } else {
              relativeKey = null; // edge between two non-anchor nodes
            }
            if (relativeKey != null && relativeKey.isNotEmpty) {
              edges[i] = DedupedEdge(
                edge: GraphEdgeData(
                  id: e.id,
                  sourceId: e.sourceId,
                  targetId: e.targetId,
                  relationshipKey: relativeKey,
                  isPrivate: e.isPrivate,
                ),
                lateralOffset: deduped.lateralOffset,
                parallelCount: deduped.parallelCount,
              );
            }
          }
        }

        // Build the (transform-independent) content once. The AnimatedBuilder
        // below re-applies only the camera Transform per frame, so the cached
        // raster is reused while panning/zooming.
        //
        // v2.2 Fix 7: The entire graph canvas (edges + nodes together) is
        // wrapped in ONE RepaintBoundary. Previously, separate boundaries
        // around the edge layer caused it to not repaint when node positions
        // updated during pan/zoom.
        final Widget content = RepaintBoundary(
          child: SizedBox(
            width: layout.canvasWidth,
            height: layout.canvasHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // v2.2 Fix 2: Edge layer is FIRST in the Stack (drawn
                // beneath nodes). This ensures edges never cover nodes
                // and are never clipped by node RepaintBoundaries.
                //
                // v2.2 Fix 1: CustomPaint uses size: Size.infinite via
                // Positioned.fill + child: SizedBox.expand() so the paint
                // canvas covers the full Stack area. Without this, the
                // canvas defaults to zero/child size and clips all lines.
                Positioned.fill(
                  // PERF: Wrap the edge painter in a ConsumerWidget that
                  // watches selectedEdgeProvider independently. This way,
                  // tapping an edge to select it only rebuilds the edge
                  // painter — NOT the entire canvas (nodes, layout, etc).
                  child: _EdgeSelectionWrapper(
                    // BUG 1 FIX: Apply Y offset so edge endpoints connect
                    // to the visual circle center, not the Positioned box
                    // center. The circle is at the TOP of the Column
                    // (72px diameter in a 120px tall box), so the visual
                    // circle center is 24px above the box center.
                    positions: {
                      for (final entry in layout.positions.entries)
                        entry.key: Offset(
                          entry.value.dx,
                          entry.value.dy + _kCircleCenterYOffset,
                        ),
                    },
                    edges: edges,
                    cache: _edgePathCache,
                  ),
                ),
                // Node layer — LOD-dependent. Drawn ON TOP of edges.
                ..._buildNodeLayer(
                    layout, visible, personById, relationLabelById, relationKeyById, viewerPersonId),
              ],
            ),
          ),
        );

        return ColoredBox(
          color: KinrelColors.darkBackground,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            // v62: Double-tap to zoom in 2× toward the focal point,
            // toggles back to 1× on second double-tap.
            onDoubleTapDown: (details) =>
                _doubleTapPosition = details.localPosition,
            onDoubleTap: _handleDoubleTapZoom,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _camera,
                child: content,
                builder: (BuildContext context, Widget? child) {
                  return Transform(
                    transform: _camera.transformMatrix,
                    child: child,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the node layer for the current LOD tier.
  List<Widget> _buildNodeLayer(
    GraphLayoutResult layout,
    Set<String> visible,
    Map<String, Map<String, dynamic>> personById,
    Map<String, String> relationLabelById,
    Map<String, String> relationKeyById,
    String? viewerPersonId,
  ) {
    final _Lod lod = _lodFor(_camera.zoomLevel);

    // Dot tier: one painter for ALL visible nodes — no per-node widgets.
    if (lod == _Lod.dot) {
      final dots = <_Dot>[];
      for (final String id in visible) {
        final pos = layout.positions[id];
        final p = personById[id];
        if (pos == null || p == null) continue;
        dots.add(_Dot(
          pos,
          _dotColor(
            p['gender'] as String?,
            (p['isAnchor'] as bool?) ?? false,
            // FIX (node-colors): Use the RAW kinship key for color
            // resolution, not the localized display name.
            relationshipKey: relationKeyById[id],
          ),
        ));
      }
      return <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _NodeDotPainter(dots),
            // v2.2 Fix 1: SizedBox.expand() ensures the dot painter
            // canvas covers the full Stack area.
            child: const SizedBox.expand(),
          ),
        ),
      ];
    }

    // Full / chip tiers: individual widgets (culling keeps the count small).
    final widgets = <Widget>[];
    final highlightedGen = widget.highlightedGeneration;
    for (final String id in visible) {
      final pos = layout.positions[id];
      final p = personById[id];
      if (pos == null || p == null) continue;
      final Widget node = lod == _Lod.full
          ? _buildFullNode(id, p, relationLabelById, relationKeyById, viewerPersonId)
          : _buildChipNode(p, relationshipKey: relationKeyById[id]);

      // v62: Dim nodes not in the highlighted generation (if set).
      final int personGen =
          (p['generationIndex'] as num?)?.toInt() ?? 0;
      final double opacity = (highlightedGen != null &&
              personGen != highlightedGen)
          ? 0.15
          : 1.0;

      widgets.add(Positioned(
        left: pos.dx - _kNodeSize.width / 2,
        top: pos.dy - _kNodeSize.height / 2,
        width: _kNodeSize.width,
        height: _kNodeSize.height,
        child: Opacity(
          opacity: opacity,
          child: RepaintBoundary(child: node),
        ),
      ));
    }
    return widgets;
  }

  Widget _buildFullNode(
    String id,
    Map<String, dynamic> p,
    Map<String, String> labels,
    Map<String, String> relationKeyById,
    String? viewerPersonId,
  ) {
    // v2.2: If this node IS the viewer, show "You" as the relation label.
    final bool isViewer = viewerPersonId != null && id == viewerPersonId;
    return GraphNode(
      personId: id,
      name: (p['name'] as String?) ?? '',
      gender: p['gender'] as String?,
      generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
      isAnchor: (p['isAnchor'] as bool?) ?? false,
      photoUrl: p['photoUrl'] as String?,
      isDeceased: (p['isDeceased'] as bool?) ?? false,
      // FIX (node-colors): Pass the RAW kinship key so GraphNode can
      // resolve the correct border/tint color from the 8-color scheme.
      // Previously this was not passed at all, causing every non-anchor
      // node to fall back to 'extended' (slate #64748B).
      relationshipKey: relationKeyById[id],
      // v2.2: "You" label for the viewer's node; otherwise use the
      // computed relation label from the viewer's perspective.
      relationLabel: isViewer ? 'You' : (labels[id] ?? ''),
      onTap: () => ref.read(selectedNodeProvider.notifier).state = id,
      // v62.2 FIX: Long-press shows the quick-actions sheet (matching
      // the v40 FamilyGraphWidget behavior) instead of toggling the
      // subtree (which was hiding nodes — confusing and unexpected).
      onLongPress: () {
        final personData = GraphPersonData(
          id: id,
          name: (p['name'] as String?) ?? '',
          gender: p['gender'] as String?,
          generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
          isAnchor: (p['isAnchor'] as bool?) ?? false,
          photoUrl: p['photoUrl'] as String?,
          isDeceased: (p['isDeceased'] as bool?) ?? false,
        );
        GraphQuickActions.show(context, personData);
      },
    );
  }

  /// Lightweight mid-zoom node: a coloured dot + the name, no avatar/animations.
  Widget _buildChipNode(Map<String, dynamic> p, {String? relationshipKey}) {
    final color = _dotColor(
      p['gender'] as String?,
      (p['isAnchor'] as bool?) ?? false,
      relationshipKey: relationshipKey,
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: Text(
            (p['name'] as String?) ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  // ── Share / export ───────────────────────────────────────────────────────

  Future<void> _shareGraph() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final bool ok =
        await GraphExportService.shareGraph(_graphBoundaryKey);
    if (!ok && mounted) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not capture the graph to share.')),
      );
    }
  }

  // ── Camera / culling helpers ─────────────────────────────────────────────

  /// Screen rect → graph-space rect using the inverse camera transform.
  Rect _graphSpaceViewport() {
    final double z = _camera.zoomLevel == 0 ? 1.0 : _camera.zoomLevel;
    return Rect.fromLTWH(
      -_camera.panX / z,
      -_camera.panY / z,
      _viewportSize.width / z,
      _viewportSize.height / z,
    );
  }

  Future<void> _maybeFrame(GraphLayoutResult layout) async {
    if (_framed) return;
    if (_viewportSize.width <= 0 || _viewportSize.height <= 0) return;
    if (layout.positions.isEmpty) return;
    _framed = true;

    // FIX (blank-on-load): Always call initialFitOnce on the first frame.
    // Previously, when a saved camera position existed from a previous
    // session, initialFitOnce was skipped — but the saved pan/zoom was
    // computed for a different viewport size, causing the camera to
    // point at empty space (blank screen until the user manually zoomed).
    // initialFitOnce has its own _didInitialFit guard so it's safe to
    // call unconditionally.
    _camera.initialFitOnce(layout.positions, _viewportSize);
    _culler.invalidate();
    if (mounted) setState(() {});
  }

  // ── Gestures ───────────────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _lastFocal = d.focalPoint;
    _baseZoom = _camera.zoomLevel;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // Pan (works for one- and two-finger drags).
    final Offset delta = d.focalPoint - _lastFocal;
    if (delta != Offset.zero) {
      _camera.panBy(delta.dx, delta.dy);
    }
    _lastFocal = d.focalPoint;

    // Pinch zoom around the focal point.
    if (d.scale != 1.0) {
      final box = context.findRenderObject() as RenderBox?;
      final Offset local = box?.globalToLocal(d.focalPoint) ?? d.focalPoint;
      _camera.zoomTo(_baseZoom * d.scale, focalPoint: local);
    }
  }

  /// v62: Double-tap toggles between 1× and 2× zoom, centered on
  /// the tap focal point. Uses the camera's zoomTo with focalPoint
  /// so the zoom target stays under the user's finger.
  void _handleDoubleTapZoom() {
    final currentZoom = _camera.zoomLevel;
    final targetZoom = currentZoom < 1.5 ? 2.0 : 1.0;
    _camera.zoomTo(targetZoom, focalPoint: _doubleTapPosition);
  }

  // ── Expand / collapse ────────────────────────────────────────────────────

  void _toggleSubtree(String id) {
    final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;
    if (flat == null) return;

    final all = <String>{
      for (final Map<String, dynamic> p in flat.persons)
        if (p['id'] != null) p['id'] as String,
    };
    final Set<String> visible = _expandCollapse.state.visibleNodeIds.isEmpty
        ? Set<String>.of(all)
        : Set<String>.of(_expandCollapse.state.visibleNodeIds);

    final Set<String> descendants = _descendantsOf(id, flat);
    final bool isExpanded = descendants.any(visible.contains);
    if (isExpanded) {
      visible.removeAll(descendants);
    } else {
      visible.addAll(descendants);
    }
    _expandCollapse.updateVisibleNodes(visible);
    _culler.invalidate();
    if (mounted) setState(() {});
  }

  Set<String> _descendantsOf(String root, FlatGraphResult flat) {
    final children = <String, List<String>>{};
    for (final Map<String, dynamic> r in flat.relationships) {
      final s = r['fromPersonId'] as String?;
      final t = r['toPersonId'] as String?;
      if (s == null || t == null) continue;
      children.putIfAbsent(s, () => <String>[]).add(t);
    }
    final out = <String>{};
    final queue = <String>[...?children[root]];
    while (queue.isNotEmpty) {
      final String n = queue.removeLast();
      if (out.add(n)) {
        queue.addAll(children[n] ?? const <String>[]);
      }
    }
    return out;
  }

  /// v2.2: Computes a relation label for every person in the graph from
  /// the VIEWER's perspective using [RelationshipEngine.resolveKey].
  ///
  /// The viewer's own node is omitted (the UI shows "You" for it).
  ///
  /// Falls back to the stored `relationshipKey` only when no viewer is
  /// available (e.g., anonymous mode), preserving legacy behavior.
  Map<String, String> _relationLabels(
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final labels = <String, String>{};

    // No viewer → use the structural classifier on stored edges.
    //
    // v67 (BUG-19 FIX): The previous version assigned the raw
    // relationshipKey to the `to` person of each edge — but the key
    // describes the `from` person's relationship TO the `to` person,
    // not the anchor's perspective. This caused labels to be backwards
    // (e.g. anchor labeled "Father", actual father unlabeled).
    //
    // The fix: resolve labels from the ANCHOR's perspective using the
    // same directionality logic as _getStoredKey(). The anchor is the
    // person with isAnchor == true (or the first person as fallback).
    if (viewerPersonId == null) {
      // Find the anchor.
      String? anchorId;
      for (final Map<String, dynamic> p in flat.persons) {
        if (p['isAnchor'] == true) {
          anchorId = p['id'] as String?;
          break;
        }
      }
      anchorId ??= flat.persons.isNotEmpty
          ? flat.persons.first['id'] as String?
          : null;

      if (anchorId == null) return labels;

      for (final Map<String, dynamic> r in flat.relationships) {
        final from = r['fromPersonId'] as String?;
        final to = r['toPersonId'] as String?;
        final key = r['relationshipKey'] as String?;
        if (key == null || key.isEmpty) continue;

        // Edge points TO anchor: stored key IS the anchor's perspective
        // on `from`. Label the `from` person.
        if (to == anchorId && from != null && !labels.containsKey(from)) {
          labels[from] = _prettyPrintKey(key);
        }
        // Edge points FROM anchor: anchor's perspective on `to` is the
        // inverse. Label the `to` person with the inverse key.
        else if (from == anchorId && to != null && !labels.containsKey(to)) {
          final inverseKey = _inverseRelationshipKey(key);
          labels[to] = _prettyPrintKey(inverseKey ?? key);
        }
      }
      return labels;
    }

    // Build typed inputs for RelationshipEngine.
    final graphPersons = <GraphPerson>[
      for (final Map<String, dynamic> p in flat.persons)
        if (p['id'] != null)
          GraphPerson(
            id: p['id'] as String,
            name: (p['name'] as String?) ?? '',
            gender: p['gender'] as String?,
            generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
            isAnchor: (p['isAnchor'] as bool?) ?? false,
            photoUrl: p['photoUrl'] as String?,
            isDeceased: (p['isDeceased'] as bool?) ?? false,
          ),
    ];
    final graphRels = <({String fromId, String toId, String type})>[
      for (final Map<String, dynamic> r in flat.relationships)
        if (r['fromPersonId'] != null &&
            r['toPersonId'] != null &&
            r['relationshipKey'] != null)
          (
            fromId: r['fromPersonId'] as String,
            toId: r['toPersonId'] as String,
            type: r['relationshipKey'] as String,
          ),
    ];

    final engine = RelationshipEngine.instance;
    for (final GraphPerson p in graphPersons) {
      if (p.id == viewerPersonId) continue; // viewer's own label is "You"
      final classification = engine.resolveClassification(
        viewerPersonId: viewerPersonId,
        targetPersonId: p.id,
        persons: graphPersons,
        relationships: graphRels,
      );
      if (classification != null) {
        // v66: Use the structural classifier's label directly — it's
        // already human-readable ("Father", "Grandfather", "Cousin", etc.)
        // and matches the category color. This replaces the old
        // _localizeKinshipKey() lookup which failed for multi-hop paths.
        labels[p.id] = classification.label;
      }
    }
    return labels;
  }

  /// Computes the RAW kinship key (e.g., "father", "mothers_brother")
  /// for each person from the viewer's perspective.
  ///
  /// Unlike [_relationLabels] which returns LOCALIZED display names
  /// (e.g., "Father"), this returns the raw key needed for color
  /// resolution via [RelationshipColors.borderColorFor] and
  /// [KinshipEdgeStyleResolver.styleFor].
  ///
  /// Used to pass `relationshipKey` to [GraphNode] so node borders,
  /// tints, and dots use the correct 8-color scheme.
  Map<String, String> _relationKeys(
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final keys = <String, String>{};

    // v63: Build the GraphPerson + GraphRelationship shapes ONCE for both
    // code paths. Previously this was only built inside the viewer != null
    // branch, so the no-viewer path couldn't use the RelationshipEngine
    // for multi-hop BFS resolution. Now both paths share the same data
    // shapes and the engine is used whenever an anchor (or viewer) can be
    // identified.
    final graphPersons = <GraphPerson>[
      for (final Map<String, dynamic> p in flat.persons)
        if (p['id'] != null)
          GraphPerson(
            id: p['id'] as String,
            name: (p['name'] as String?) ?? '',
            gender: p['gender'] as String?,
            generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
            isAnchor: (p['isAnchor'] as bool?) ?? false,
            photoUrl: p['photoUrl'] as String?,
            isDeceased: (p['isDeceased'] as bool?) ?? false,
          ),
    ];
    final graphRels = <({String fromId, String toId, String type})>[
      for (final Map<String, dynamic> r in flat.relationships)
        if (r['fromPersonId'] != null &&
            r['toPersonId'] != null &&
            r['relationshipKey'] != null)
          (
            fromId: r['fromPersonId'] as String,
            toId: r['toPersonId'] as String,
            type: r['relationshipKey'] as String,
          ),
    ];

    // v63: Pick the BFS source — prefer the viewer, fall back to the
    // anchor person (every family has exactly one anchor). If neither
    // exists, fall back to the legacy direct-edge-only path.
    String? bfsSource = viewerPersonId;
    if (bfsSource == null && graphPersons.isNotEmpty) {
      final anchor = graphPersons.firstWhere(
        (p) => p.isAnchor,
        orElse: () => graphPersons.first,
      );
      bfsSource = anchor.id;
    }

    if (bfsSource == null || graphPersons.isEmpty) {
      // No source — fall back to direct-edge assignment so connected
      // nodes still get a color (better than nothing).
      for (final Map<String, dynamic> r in flat.relationships) {
        final from = r['fromPersonId'] as String?;
        final to = r['toPersonId'] as String?;
        final key = r['relationshipKey'] as String?;
        if (key == null) continue;
        if (to != null && !keys.containsKey(to)) {
          keys[to] = key;
        }
        if (from != null && !keys.containsKey(from)) {
          final inverseKey = _inverseRelationshipKey(key);
          if (inverseKey != null) {
            keys[from] = inverseKey;
          }
        }
      }
      return keys;
    }

    // v63: Use RelationshipEngine for BFS resolution from the chosen
    // source. This handles multi-hop relatives (e.g. paternal_grandfather
    // via father → grandfather) which the direct-edge lookup missed,
    // causing them to fall through to the 'extended' slate gray fallback.
    //
    // v65 GUARD: If bfsSource is not in graphPersons (e.g. the viewer's
    // Person was deleted or is from a different family), the BFS will
    // silently fail for ALL targets, leaving every non-self node grey.
    // Fall back to the anchor in that case.
    final effectiveSource = graphPersons.any((p) => p.id == bfsSource)
        ? bfsSource
        : (graphPersons.any((p) => p.isAnchor)
            ? graphPersons.firstWhere((p) => p.isAnchor).id
            : (graphPersons.isNotEmpty ? graphPersons.first.id : null));

    if (effectiveSource != null) {
      final engine = RelationshipEngine.instance;
      for (final GraphPerson p in graphPersons) {
        if (p.id == effectiveSource) continue;
        // v66: Use resolveClassification — returns the category-correct
        // key even when chain rules fail. This ensures EVERY reachable
        // node gets a color, not just the 2-3 that match the 26-key
        // kinship dataset.
        final classification = engine.resolveClassification(
          viewerPersonId: effectiveSource,
          targetPersonId: p.id,
          persons: graphPersons,
          relationships: graphRels,
        );
        if (classification != null && classification.key.isNotEmpty) {
          keys[p.id] = classification.key;
        }
      }
    }

    // v65 (BUGFIX): Backfill for any person the engine couldn't resolve.
    //
    // CRITICAL DIRECTIONALITY FIX: The stored relationship
    //   from: Rajesh, to: anchor, key: 'father'
    // means "Rajesh IS the father OF the anchor". From the ANCHOR's
    // perspective, Rajesh IS 'father' — the stored key already IS the
    // anchor's perspective on Rajesh. The previous code was assigning
    // the INVERSE ('child') to Rajesh, which is the relationship from
    // RAJESH's perspective, not the anchor's. This caused every node
    // to get the wrong color (e.g. a father node colored pink/child
    // instead of blue/parent).
    //
    // The correct logic:
    //   - Edge points TO anchor (to == source): the stored key IS the
    //     source's perspective on `from`. Assign key DIRECTLY to `from`.
    //   - Edge points FROM anchor (from == source): the stored key IS
    //     the source's perspective on `to`. Assign key DIRECTLY to `to`.
    //   - Edge doesn't involve anchor: assign key to `to` and inverse
    //     to `from` (legacy behavior for non-anchor-centric edges).
    final sourceId = effectiveSource;
    for (final Map<String, dynamic> r in flat.relationships) {
      final from = r['fromPersonId'] as String?;
      final to = r['toPersonId'] as String?;
      final key = r['relationshipKey'] as String?;
      if (key == null || key.isEmpty) continue;
      if (sourceId == null) continue;

      // Case 1: Edge points TO the anchor.
      // Stored key = anchor's perspective on `from` person.
      if (to == sourceId && from != null && !keys.containsKey(from)) {
        keys[from] = key;
        continue;
      }

      // Case 2: Edge points FROM the anchor.
      // Stored key = anchor's perspective on `to` person.
      if (from == sourceId && to != null && !keys.containsKey(to)) {
        keys[to] = key;
        continue;
      }

      // Case 3: Edge doesn't involve the anchor (e.g. between two
      // non-anchor nodes).
      //
      // v67 (BUG-18 FIX): Previously this assigned keys to BOTH
      // endpoints from the same edge — but the key only describes one
      // person's relationship to the other, not the anchor's
      // perspective on either. This produced wrong colors for non-
      // anchor-connected nodes.
      //
      // The fix: SKIP non-anchor edges entirely. The BFS above should
      // have already resolved keys for any node reachable from the
      // anchor. If a node is NOT reachable (disconnected subgraph),
      // it's better to leave it with no key (GraphNode falls back to
      // 'extended' grey) than to assign a wrong key from an arbitrary
      // edge. The grey fallback is the spec-correct behavior for
      // genuinely unclassifiable nodes.
      //
      // Exception: if the edge is a spouse edge between two non-anchor
      // nodes and ONE of them already has a BFS-resolved key, we can
      // infer the other is the spouse. But this is rare and the BFS
      // usually handles it. Skip for safety.
      break;
    }

    return keys;
  }

  /// v65: Finds the anchor person ID from the flat graph data.
  ///
  /// Used to identify which node is the graph's center so that edge
  /// colors can be resolved from the anchor's perspective (matching
  /// the node colors).
  ///
  /// Resolution order:
  ///   1. The person with `isAnchor == true` in [flat.persons].
  ///   2. [viewerPersonId] as a fallback (when no anchor is flagged).
  ///   3. null if neither exists.
  static String? _findAnchorId(FlatGraphResult flat, String? viewerPersonId) {
    for (final Map<String, dynamic> p in flat.persons) {
      if (p['isAnchor'] == true) {
        final id = p['id'];
        if (id is String && id.isNotEmpty) return id;
      }
    }
    return viewerPersonId;
  }

  /// Returns the inverse relationship key for common kinship terms.
  /// Used by [_relationKeys] when no viewer is available to assign
  /// colors to BOTH endpoints of an edge.
  static String? _inverseRelationshipKey(String key) {
    const inverseMap = <String, String>{
      'father': 'child',
      'mother': 'child',
      'parent': 'child',
      'child': 'parent',
      'son': 'parent',
      'daughter': 'parent',
      'brother': 'sibling',
      'sister': 'sibling',
      'sibling': 'sibling',
      'husband': 'wife',
      'wife': 'husband',
      'spouse': 'spouse',
      'grandfather': 'grandchild',
      'grandmother': 'grandchild',
      'grandson': 'grandparent',
      'granddaughter': 'grandparent',
      'uncle': 'nephew',
      'aunt': 'niece',
      'nephew': 'uncle',
      'niece': 'aunt',
      'cousin': 'cousin',
    };
    return inverseMap[key];
  }

  /// Resolves a kinship key (e.g. "father", "mothers_brother") to a
  /// human-readable display name using [KinshipService]. Returns the
  /// pretty-printed raw key if no translation is available.
  String _localizeKinshipKey(String key) {
    try {
      final kinship = KinshipService.instance;
      if (kinship.isLoaded) {
        // English is always available; the app's localization layer can
        // re-translate this key per the user's preferred language later.
        final rel = kinship.getRelationship(key);
        final term = rel?.englishTerm;
        if (term != null && term.isNotEmpty) {
          return term;
        }
      }
    } catch (_) {
      // Fall through to the pretty-printed key.
    }
    return _prettyPrintKey(key);
  }

  /// v67: Pretty-prints a kinship key as a human-readable label.
  /// "father" → "Father", "father_in_law" → "Father In Law",
  /// "mothers_brother" → "Mothers Brother".
  String _prettyPrintKey(String key) {
    return key
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join(' ');
  }

  /// v2.2: Returns the node dot color based on the kinship category
  /// of the relationship connecting this node to the viewer.
  ///
  /// Falls back to gender-based colors (blue/pink/grey) only when the
  /// relationship key is null or unknown — preserving the previous
  /// behavior for backward compatibility.
  ///
  /// The anchor/viewer node always uses the Teal "self" color so it
  /// stands out from all other categories.
  Color _dotColor(String? gender, bool isAnchor, {String? relationshipKey}) {
    if (isAnchor) return KinshipEdgeColors.self;
    // v2.2: Prefer kinship category color over plain gender color.
    if (relationshipKey != null && relationshipKey.isNotEmpty) {
      final style = KinshipEdgeStyleResolver.styleFor(relationshipKey);
      // Don't use the 'self' category color for non-anchor nodes —
      // fall through to gender-based color in that case.
      if (style.category != KinshipEdgeCategory.self) {
        return style.color;
      }
    }
    // Legacy fallback: gender-based color.
    switch (gender) {
      case 'male':
        return Colors.blue;
      case 'female':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  /// v2.2: Returns the set of kinship categories present in the current
  /// graph. Used by the legend to show only relevant rows.
  ///
  /// Iterates all edges in [flat] and classifies each by its
  /// relationship key. Returns an empty set if [flat] is null.
  Set<KinshipEdgeCategory> _presentCategories(FlatGraphResult? flat) {
    if (flat == null) return <KinshipEdgeCategory>{};
    final cats = <KinshipEdgeCategory>{};
    for (final Map<String, dynamic> r in flat.relationships) {
      final key = r['relationshipKey'] as String?;
      if (key != null && key.isNotEmpty) {
        cats.add(KinshipEdgeClassifier.classify(key));
      }
    }
    // Always include 'self' so the viewer's own node color is documented.
    cats.add(KinshipEdgeCategory.self);
    return cats;
  }
}

// ── Painters ────────────────────────────────────────────────────────────────

/// Draws relationship edges using cached bezier paths.
///
/// Wraps the edge CustomPaint in a ConsumerWidget that independently
/// watches [selectedEdgeProvider]. When the user taps an edge, only
/// this widget rebuilds — the main canvas (nodes, layout, etc.) does
/// not rebuild at all.
class _EdgeSelectionWrapper extends ConsumerWidget {
  const _EdgeSelectionWrapper({
    required this.positions,
    required this.edges,
    required this.cache,
  });

  final Map<String, Offset> positions;
  final List<DedupedEdge> edges;
  final EdgePathCache cache;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? selectedEdgeId = ref.watch(selectedEdgeProvider);
    return CustomPaint(
      painter: _EngineEdgePainter(
        positions: positions,
        edges: edges,
        cache: cache,
        selectedEdgeId: selectedEdgeId,
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Paths are memoised in [EdgePathCache] keyed by quantized endpoint
/// positions. Because graph-space positions are constant during pan/zoom,
/// repeated frames hit the cache and skip path construction entirely. The
/// factory is O(1) (no per-edge node-collision scan).
class _EngineEdgePainter extends CustomPainter {
  _EngineEdgePainter({
    required this.positions,
    required this.edges,
    required this.cache,
    this.selectedEdgeId,
  });

  final Map<String, Offset> positions;
  final List<DedupedEdge> edges;
  final EdgePathCache cache;
  final String? selectedEdgeId;

  /// Builds a bezier curve path between two node centers.
  ///
  /// The curve is designed to:
  ///   1. Start and end at the EXACT center of each node (no offset)
  ///   2. Use a smooth S-curve when nodes are vertically aligned
  ///   3. Use a gentle arc when nodes are horizontally offset
  ///   4. Avoid overlapping with other edges by using directional
  ///      control points that spread curves apart
  ///
  /// v64 (BUG-2 FIX): [lateralOffset] shifts the curve sideways so that
  /// parallel edges between the same node pair (e.g. parent + spouse)
  /// don't stack on top of each other. 0.0 for solo edges.
  static Path _bezier(Offset s, Offset t, {double lateralOffset = 0.0}) {
    final double dy = t.dy - s.dy;
    final double dx = t.dx - s.dx;
    final double distance = (s - t).distance;

    // For very short distances, use a simple line to avoid weird curves.
    // We still apply the lateral offset so parallel short edges separate.
    if (distance < 20.0) {
      return Path()
        ..moveTo(s.dx + lateralOffset, s.dy)
        ..lineTo(t.dx + lateralOffset, t.dy);
    }

    // Control point offset — scales with distance for smooth curves
    // at any zoom level. Clamped to prevent extreme curves.
    final double cpOffset = (distance * 0.3).clamp(30.0, 120.0);

    if (dx.abs() < 10.0) {
      // Vertically aligned nodes: S-curve with lateral offset.
      // Add the parallel offset to the lateral shift so parallel
      // edges bow in different directions.
      final double lateral =
          (dx >= 0 ? cpOffset * 0.5 : -cpOffset * 0.5) + lateralOffset;
      final cp1 = Offset(s.dx + lateral, s.dy + dy * 0.35);
      final cp2 = Offset(t.dx + lateral, t.dy - dy * 0.35);
      return Path()
        ..moveTo(s.dx, s.dy)
        ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, t.dx, t.dy);
    }

    // Horizontally offset nodes: gentle vertical bezier.
    // Control points are placed along the vertical midpoint to create
    // a smooth, non-overlapping curve. Apply the parallel offset to
    // the Y axis of the control points so parallel edges separate
    // vertically when nodes are side-by-side.
    final midY = s.dy + dy * 0.5 + lateralOffset;
    final cp1 = Offset(s.dx + dx * 0.25, midY);
    final cp2 = Offset(t.dx - dx * 0.25, midY);
    return Path()
      ..moveTo(s.dx, s.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, t.dx, t.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // v2.2 Fix 6: Null/empty guards — skip painting entirely if there
    // are no edges or no positions. This prevents crashes and wasted
    // CPU when the graph is empty or still loading.
    if (edges.isEmpty) return;
    if (positions.isEmpty) return;

    final selectedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Colors.orange
      ..isAntiAlias = true;

    for (final DedupedEdge deduped in edges) {
      final GraphEdgeData e = deduped.edge;
      final Offset? s = positions[e.sourceId];
      final Offset? t = positions[e.targetId];
      if (s == null || t == null) continue;
      // v64 (BUG-2 FIX): Pass the lateral offset so parallel edges
      // (e.g. parent + spouse between the same pair) are visually
      // separated instead of stacked on top of each other.
      //
      // v67 (BUG-11 FIX): Append the lateral offset to the edge ID
      // passed to the cache, so parallel edges between the same pair
      // (which may share the same base edge ID after dedup) get
      // SEPARATE cache entries. Without this, the second parallel edge
      // would hit the cache and get the FIRST edge's path (wrong curve).
      final cacheEdgeId = deduped.lateralOffset != 0.0
          ? '${e.id}__offset_${deduped.lateralOffset.toStringAsFixed(1)}'
          : e.id;
      final Path path = cache.getOrCreate(
        edgeId: cacheEdgeId,
        sourceId: e.sourceId,
        targetId: e.targetId,
        sourcePos: s,
        targetPos: t,
        // The cache factory signature only takes (s, t) — we wrap the
        // call so the lateral offset is applied inside _bezier.
        // NOTE: The cache key includes the source/target IDs but NOT
        // the lateral offset, so two parallel edges between the same
        // pair would share a cache entry. To avoid this, we append the
        // offset to the edge ID passed to the cache.
        pathFactory: (Offset ss, Offset tt) =>
            _bezier(ss, tt, lateralOffset: deduped.lateralOffset),
      );

      if (e.id == selectedEdgeId) {
        canvas.drawPath(path, selectedPaint);
        continue;
      }

      // Resolve the kinship edge style for this edge's key.
      // v2.2 Fix 4: Add a fallback color and minimum alpha floor so edges
      // are always visible. The 'extended' category uses alpha 0.45 which
      // is correct for the dim aesthetic, but we floor at 0.3 to ensure
      // the line is never invisible.
      final style = KinshipEdgeStyleResolver.styleFor(e.relationshipKey);
      final edgeColor = style.color ?? const Color(0xFF888888);
      final edgeAlpha = style.defaultAlpha.clamp(0.3, 1.0);
      final edgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.strokeWidth.clamp(1.5, 5.0)
        ..color = edgeColor.withValues(alpha: edgeAlpha)
        ..isAntiAlias = true
        ..strokeCap = StrokeCap.round;

      // Apply dash pattern if the style is dashed.
      if (style.dashPattern.isNotEmpty && style.dashPattern.length >= 2) {
        for (final metric in path.computeMetrics()) {
          double pos = 0;
          final dashWidth = style.dashPattern[0];
          final dashGap = style.dashPattern[1];
          while (pos < metric.length) {
            final segEnd = (pos + dashWidth).clamp(0.0, metric.length);
            canvas.drawPath(metric.extractPath(pos, segEnd), edgePaint);
            pos += dashWidth + dashGap;
          }
        }
      } else {
        canvas.drawPath(path, edgePaint);
      }

      // Draw midpoint symbol (dot or heart) — NO text labels on edges.
      if (style.midpointSymbol != KinshipMidpointSymbol.none) {
        // Compute the actual midpoint on the bezier path using PathMetrics.
        // This is more accurate than manually computing control points
        // because it accounts for the actual curve geometry.
        Offset midPoint = Offset(
          (s.dx + t.dx) / 2,
          (s.dy + t.dy) / 2,
        );
        for (final metric in path.computeMetrics()) {
          if (metric.length > 0) {
            final tangent = metric.getTangentForOffset(metric.length * 0.5);
            if (tangent != null) {
              midPoint = tangent.position;
              break;
            }
          }
        }

        // Fix 3: Dot radius 4.0 (was 2.5), full opacity, heart stays 4.0.
        if (style.midpointSymbol == KinshipMidpointSymbol.heart) {
          canvas.drawCircle(
            midPoint,
            4.0,
            Paint()
              ..color = style.midpointColor
              ..style = PaintingStyle.fill,
          );
        } else {
          canvas.drawCircle(
            midPoint,
            4.0,
            Paint()
              ..color = style.midpointColor
              ..style = PaintingStyle.fill,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EngineEdgePainter old) {
    // v2.2 Fix 3: Repaint when ANY of the following changes:
    //   - edges list (new/deleted relationships)
    //   - positions map (nodes moved during pan/zoom or layout recompute)
    //   - selectedEdgeId (user tapped a different edge)
    // Previously only edges.length and identical(edges) were checked, so
    // when nodes moved but the edge list stays the same, edges were NOT
    // repainted — they stayed at their old positions until a full rebuild.
    return old.edges.length != edges.length ||
        old.selectedEdgeId != selectedEdgeId ||
        !identical(old.edges, edges) ||
        !identical(old.positions, positions) ||
        old.positions.length != positions.length;
  }
}

/// A single node rendered as a coloured dot at the lowest LOD tier.
class _Dot {
  const _Dot(this.pos, this.color);
  final Offset pos;
  final Color color;
}

/// Draws every visible node as a dot in ONE painter — avoids thousands of
/// widgets when fully zoomed out (the 2000-node case).
class _NodeDotPainter extends CustomPainter {
  _NodeDotPainter(this.dots);

  final List<_Dot> dots;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    for (final _Dot d in dots) {
      paint.color = d.color;
      canvas.drawCircle(d.pos, 6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NodeDotPainter old) =>
      old.dots.length != dots.length || !identical(old.dots, dots);
}

// ── Small presentational helpers ───────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Offline. Showing cached graph.',
      liveRegion: true,
      child: Material(
        color: Colors.orange.shade800,
        child: const SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 16, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Offline — showing cached graph',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyGraph extends StatelessWidget {
  const _EmptyGraph();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No family members yet.\nAdd someone to start the graph.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          const Text('Could not load the family graph.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Banner shown when the authenticated user has not yet claimed a
/// Person node in this family. Tapping it navigates to person selection
/// so the user can tap "This is me" / Claim on their own Person node.
///
/// GAP 3 FIX: Without this banner, the graph silently renders from the
/// anchor person's perspective when the user has no linked Person node,
/// which makes the labels look wrong (e.g. a father sees his children
/// labeled as "sibling") with no explanation.
class _ClaimProfileBanner extends ConsumerWidget {
  const _ClaimProfileBanner({required this.familyId});
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFE8622A).withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(Icons.person_search, color: Color(0xFFE8622A), size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Tap to claim your profile — you're viewing as the family anchor",
              style: TextStyle(
                color: Color(0xFFE8622A),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              // Navigate to the family detail screen, which has a Members
              // tab where the user can find their own Person node and tap
              // "This is me" / Claim. The app uses GoRouter, so we use
              // context.push('/family/$familyId'). If the route changes,
              // search for how other parts of the app navigate to the
              // members list for a family.
              context.push('/family/$familyId');
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE8622A),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Claim', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
