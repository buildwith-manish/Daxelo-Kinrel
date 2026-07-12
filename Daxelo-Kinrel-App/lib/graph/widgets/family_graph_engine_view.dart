import 'dart:math';
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
import '../interaction/graph_focus_state.dart'
    show
        GraphFocusNotifier,
        GraphFocusState,
        FocusViewportSnapshot,
        FocusHistoryEntry,
        graphFocusProvider;
import '../interaction/branch_collapse_state.dart'
    show
        BranchCollapseNotifier,
        BranchCollapseState,
        CollapsedBranch,
        branchCollapseProvider;
import '../interaction/graph_search_state.dart'
    show
        GraphSearchNotifier,
        GraphSearchState,
        graphSearchProvider;
import '../interaction/relationship_validation.dart'
    show GraphUndoNotifier, graphUndoProvider;
import '../interaction/graph_kinship_path_focus.dart'
    show
        GraphKinshipPathFocus,
        GraphPathFocusNotifier,
        GraphPathFocusState,
        graphPathFocusProvider;
import '../interaction/graph_path_trace_controller.dart'
    show GraphPathTraceController, GraphPathTraceState, GraphPathTracePhase;
import '../../core/constants/feature_flags.dart' show kEnableGraphShareExport;
import '../../core/constants/brand_colors.dart' show KinrelColors;
import '../../core/kinship/kinship_edge_style.dart';
import '../../core/kinship/kinship_category_map.dart';
import '../../core/kinship/structural_kinship_classifier.dart';
import '../../core/kinship/heart_shape.dart' show HeartShape;
import '../../core/kinship/kinship_service.dart' show KinshipService;
import '../../core/relationship/relationship_engine.dart' show RelationshipEngine;
import '../../core/services/graph_layout_service.dart' show GraphPerson;
import '../../core/viewer/viewer_provider.dart' show viewerPersonIdProvider;
import '../../core/viewer/viewer_api_client.dart'
    show viewerApiClientProvider;
import '../../features/family/presentation/services/graph_export_service.dart'
    show GraphExportService;
import '../rendering/edge_path_cache.dart' show EdgePathCache;
import '../rendering/edge_quality.dart' show EdgeQuality, EdgeQualityX;
import '../rendering/graph_lighting.dart' show GraphLighting;
import '../rendering/lod_render_metrics.dart'
    show LodRenderMetrics, computeLodMetrics, overviewGraphRadius, overviewGraphRingStroke;
import '../rendering/semantic_zoom.dart'
    show
        SemanticTier,
        SemanticZoomThresholds,
        defaultThresholds,
        computeSemanticTier,
        semanticTierToLodName,
        shouldOverrideFarTier,
        farTierDotRadius,
        farTierExcludesPremiumEffects,
        shouldRenderText;
import '../rendering/viewport_culler.dart' show ViewportCuller;
import 'graph_node.dart' show GraphNode, RelationshipColors, NodeState;
import 'graph_legend.dart' show GraphLegend;
import 'graph_quick_actions.dart' show GraphQuickActions;
import 'graph_relationship_labels.dart' show GraphPersonData;
import 'relationship_info_sheet.dart' show RelationshipInfoSheet;

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
  static const Size _kNodeSize = Size(140, 176);

  /// The visual circle diameter inside each node (GraphNode.nodeSize).
  /// The circle is at the TOP of the Column, so its visual center is
  /// offset from the Positioned center by:
  ///   circleCenterY = boxTop + diameter/2
  ///   boxCenterY    = boxTop + boxHeight/2
  ///   offset = circleCenterY - boxCenterY = diameter/2 - boxHeight/2
  ///          = 72/2 - 120/2 = 36 - 60 = -24
  /// Edge endpoints must use this offset so lines connect to the
  /// visual circle center, not the Positioned box center.
  // Updated for _kNodeSize = 140×176: circle is at top of Column.
  // Circle diameter = 72, so visual center is at 36px from top.
  // Box center is at 88px (176/2). Offset = 36 - 88 = -52.
  // But the Padding(24) shifts everything down by 24, so the actual
  // visual center is at 36 + 24 = 60 from box top.
  // Box center = 88. Offset = 60 - 88 = -28.
  static const double _kCircleCenterYOffset = -28.0;

  /// Zoom thresholds for LOD tiers.
  //
  // v97: Camera zoom range restored to 0.2–5.0. Semantic LOD handles
  // node readability at low zoom — the camera does NOT clamp to
  // prevent zooming out.
  //
  //   • zoom >= 0.72 → FULL  (close-up, full Obsidian Glass medallions)
  //   • zoom >= 0.34 → CHIP  (mid-range, name + coloured marker)
  //   • zoom <  0.34 → OVERVIEW/DOT (far-out, single painter, no widgets)
  //
  // CHIP and DOT are reachable via normal pinch-zoom.
  // _kLabelHideZoom controls when the secondary relationship label
  // (e.g. "Husband", "You") is hidden to reduce clutter at lower zoom.
  static const double _kChipZoom = 0.72;
  static const double _kDotZoom = 0.34;
  static const double _kLabelHideZoom = 1.0;

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

  // PERF: Cache relation labels/keys/categories so they don't recompute
  // on every pan/zoom frame. Only recompute when the underlying flat
  // data changes.
  FlatGraphResult? _lastFlat;
  String? _lastViewerId;
  Map<String, String>? _cachedRelationLabels;
  Map<String, String>? _cachedRelationKeys;
  // v69: Cache the authoritative KinshipEdgeCategory per person —
  // eliminates the lossy string round-trip that caused grey nodes.
  Map<String, KinshipEdgeCategory>? _cachedRelationCategories;
  // v83: Cache custom colors per person (from customColors JSONB column)
  Map<String, Map<String, dynamic>>? _cachedCustomColors;

  // v92 (PART 17): Cache the current deduped edges + positions (with
  // the visual-circle Y offset applied) so the canvas tap handler can
  // do geometric midpoint hit-testing without recomputing them.
  // Updated once per build in the build method.
  List<DedupedEdge> _currentEdges = const [];
  Map<String, Offset> _currentPositionsWithOffset = const {};
  Map<String, KinshipEdgeCategory> _currentEdgeCategories = const {};
  Map<String, Map<String, dynamic>> _currentEdgeCustomColors = const {};

  // Repaint/recull throttling.
  Rect _lastCullViewport = Rect.zero;
  _Lod _lastLod = _Lod.full;

  // v96 (Phase 3): Semantic zoom tier with hysteresis memory.
  // The current tier is remembered so computeSemanticTier can apply
  // hysteresis margins (enter/leave thresholds differ). This prevents
  // visual flicker when zoom oscillates near a tier boundary.
  SemanticTier? _currentSemanticTier;

  // v99: Track edge fingerprint + focused person ID to gate
  // build-path side effects (recomputeNeighbours, camera animation).
  // These prevent redundant BFS walks and camera animations every
  // frame during pan/zoom.
  int _lastEdgeFingerprint = 0;
  String? _lastFocusedPersonId;

  // Gesture bookkeeping for pan + pinch-zoom.
  Offset _lastFocal = Offset.zero;
  double _baseZoom = 1.0;
  /// v97: Track whether the current gesture is a multi-pointer pinch.
  /// Prevents fling momentum from being applied after a pinch release.
  bool _isPinching = false;

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
      // v95 (Phase 1): Clear focus + history when switching families.
      // Focus is local graph interaction state — it should not persist
      // across family boundaries.
      ref.read(graphFocusProvider.notifier).clearAll();
      // v96 (Phase 4): Clear branch collapse state when switching
      // families. Collapse state is per-family presentation state.
      ref.read(branchCollapseProvider.notifier).clearAll();
      // v99 (Phase 11): Clear ALL interaction state on family switch.
      // No IDs from family A must survive into family B.
      ref.read(graphSearchProvider.notifier).clear();
      ref.read(graphPathFocusProvider.notifier).clear();
      ref.read(selectedNodeProvider.notifier).state = null;
      ref.read(selectedEdgeProvider.notifier).state = null;
      ref.read(graphUndoProvider.notifier).clearAll();
      _lastEdgeFingerprint = 0;
      _lastFocusedPersonId = null;
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
    // v97: Semantic zoom with hysteresis.
    // Camera range restored to 0.2–5.0 — CHIP and DOT are reachable.
    _currentSemanticTier = computeSemanticTier(
      zoom,
      currentTier: _currentSemanticTier,
      thresholds: defaultThresholds,
    );
    switch (_currentSemanticTier!) {
      case SemanticTier.near:
        return _Lod.full;
      case SemanticTier.medium:
        return _Lod.chip;
      case SemanticTier.far:
        return _Lod.dot;
    }
  }

  /// v96 (Phase 3): Returns the current semantic tier (with hysteresis).
  /// Computed as a side effect of [_lodFor] — call _lodFor first.
  SemanticTier get _currentTier => _currentSemanticTier ?? SemanticTier.near;

  /// Maps the current LOD to the edge-layer visual quality tier (PART 10).
  /// Computed ONCE per build and passed to `_EngineEdgePainter` — the
  /// painter never derives quality per edge.
  EdgeQuality _edgeQualityFor(_Lod lod) {
    switch (lod) {
      case _Lod.full:
        return EdgeQuality.full;
      case _Lod.chip:
        return EdgeQuality.chip;
      case _Lod.dot:
        return EdgeQuality.dot;
    }
  }

  // ── v97 Zoom-aware sizing helpers ────────────────────────────────────
  //
  // These helpers convert desired SCREEN-SPACE sizes to GRAPH-SPACE
  // sizes. The camera Transform scales graph-space by `zoom`, so
  // graphSpaceValue * zoom = screenSpaceValue.
  //
  // For LOD-aware rendering, use [computeLodMetrics] from
  // lod_render_metrics.dart — it centralizes all zoom math.

  /// Converts a desired screen-space radius to graph-space.
  double graphRadiusForScreenRadius(double screenRadius, double zoom) {
    final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
    return screenRadius / safeZoom;
  }

  /// Converts a desired screen-space stroke width to graph-space.
  double graphStrokeForScreenStroke(double screenStroke, double zoom) {
    final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
    return screenStroke / safeZoom;
  }

  /// Returns true when labels should be visible at [zoom].
  bool shouldShowLabel(double zoom) {
    return zoom >= _kLabelHideZoom;
  }

  /// v97: Returns the LOD tier name for the current zoom.
  String _lodTierName(_Lod lod) {
    switch (lod) {
      case _Lod.full:
        return 'full';
      case _Lod.chip:
        return 'chip';
      case _Lod.dot:
        return 'overview';
    }
  }

  /// v97: Computes render metrics for the current LOD + zoom.
  /// Used by culling, hit testing, and overview painting.
  LodRenderMetrics _currentMetrics() {
    final lod = _lodFor(_camera.zoomLevel);
    return computeLodMetrics(
      tier: _lodTierName(lod),
      zoom: _camera.zoomLevel,
    );
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
                  // v99 (Phase 1): Focus Back control — visible when
                  // focus history is non-empty. Tapping it restores
                  // the previous focused person + viewport.
                  if (ref.watch(graphFocusProvider.select((s) => s.history)).isNotEmpty)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 8,
                      child: FloatingActionButton.small(
                        heroTag: 'graph_focus_back',
                        onPressed: _onFocusBack,
                        tooltip: 'Back to previous person',
                        child: const Icon(Icons.arrow_back),
                      ),
                    ),
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
          // v84 FIX: Also invalidate the edge path cache so stale Path
          // objects (keyed to old positions) don't get reused after a
          // data refresh. Without this, edges to newly-positioned nodes
          // can render at their OLD position or not at all.
          _edgePathCache.clear();
          // v84 FIX: Invalidate the viewport culler so the new node
          // set is recomputed immediately (not waiting for a pan).
          _culler.invalidate();
          _cachedRelationLabels = _relationLabels(flat, viewerPersonId);
          _cachedRelationKeys = _relationKeys(flat, viewerPersonId);
          // v69: Compute authoritative categories — this is the SINGLE
          // source of truth for node/edge colors. No lossy string
          // round-trip through KinshipEdgeClassifier.classify().
          _cachedRelationCategories = _relationCategories(flat, viewerPersonId);
          // v83: Build custom colors map from relationship data
          _cachedCustomColors = _extractCustomColors(flat);
          _lastFlat = flat;
          _lastViewerId = viewerPersonId;
        }
        final relationLabelById = _cachedRelationLabels!;
        final relationKeyById = _cachedRelationKeys!;
        final relationCategoryById = _cachedRelationCategories!;
        final customColorsByPersonId = _cachedCustomColors!;

        // Expand/collapse filter — empty visible set means "show everything".
        final Set<String> allowed =
            _expandCollapse.state.visibleNodeIds.isEmpty
                ? layout.positions.keys.toSet()
                : _expandCollapse.state.visibleNodeIds;

        // v99: Build RAW edge tuples from flat.relationships BEFORE
        // visibility filtering. These are needed for computeCollapse
        // which must run BEFORE the visible-set derivation so the
        // hidden IDs are current (not one-frame stale).
        final rawEdgeTuples = <({String fromId, String toId, String edgeId, String relationshipKey})>[
          for (final r in flat.relationships)
            (
              fromId: (r['fromPersonId'] ?? '').toString(),
              toId: (r['toPersonId'] ?? '').toString(),
              edgeId: (r['id'] ?? '').toString(),
              relationshipKey: (r['relationshipKey'] ?? 'unknown').toString(),
            ),
        ];

        // v99: Watch focus + search + path state BEFORE computing
        // collapse, so collapse has the current protected sets.
        final focusState = ref.watch(graphFocusProvider);
        final searchState = ref.watch(graphSearchProvider);
        final pathFocus = ref.watch(graphPathFocusProvider).focus;
        final selectedPerson = ref.read(selectedNodeProvider);

        // v99: Compute collapse BEFORE visible-set derivation.
        // This eliminates the one-frame lag where the visible set
        // used stale hidden IDs from the previous build.
        ref.read(branchCollapseProvider.notifier).computeCollapse(
              allPersons: {
                for (final p in flat.persons) (p['id'] ?? '').toString(),
              },
              allEdges: rawEdgeTuples,
              focusPersonId: focusState.focusedPersonId,
              firstDegreeIds: focusState.firstDegreeIds,
              secondDegreeIds: focusState.secondDegreeIds,
              pathNodeIds: pathFocus?.orderedPersonIds.toSet(),
              searchMatchIds: searchState.isActive
                  ? searchState.matchIdSet
                  : null,
              selectedPersonId: selectedPerson,
              familyMemberCount: flat.persons.length,
            );
        // Read the UPDATED collapse state (computeCollapse just ran).
        final collapseState = ref.watch(branchCollapseProvider);
        final hiddenIds = collapseState.allHiddenMemberIds;

        // v99: Recompute focus neighbours ONLY when the edge fingerprint
        // changes (not every build). This prevents a BFS walk over all
        // edges every frame during pan/zoom.
        final edgeFingerprint = rawEdgeTuples.length * 100003 + flat.persons.length;
        if (focusState.focusedPersonId != null &&
            edgeFingerprint != _lastEdgeFingerprint) {
          _lastEdgeFingerprint = edgeFingerprint;
          ref.read(graphFocusProvider.notifier).recomputeNeighbours(
                [for (final e in rawEdgeTuples) (fromId: e.fromId, toId: e.toId)],
              );
        }

        // v99: Animate camera to focused node ONLY when the focused
        // person ID changes (not every build).
        if (focusState.focusedPersonId != null &&
            focusState.focusedPersonId != _lastFocusedPersonId) {
          _lastFocusedPersonId = focusState.focusedPersonId;
          _maybeFocusCameraOnNode(focusState.focusedPersonId!, layout);
        } else if (focusState.focusedPersonId == null) {
          _lastFocusedPersonId = null;
        }

        // v97: Cull using LOD-aware node footprints, not always 140×176.
        final lod = _lodFor(_camera.zoomLevel);
        final metrics = computeLodMetrics(
          tier: _lodTierName(lod),
          zoom: _camera.zoomLevel,
        );
        final nodeSizes = <String, Size>{
          for (final String id in layout.positions.keys)
            id: metrics.cullSize,
        };
        final Rect vp = _graphSpaceViewport();
        final Set<String> culled =
            _culler.cull(layout.positions, nodeSizes, vp);
        // v99: Subtract branch-collapse hidden member IDs — now uses
        // the CURRENT collapse state (computed above, not stale).
        final Set<String> visible = hiddenIds.isEmpty
            ? culled.where(allowed.contains).toSet()
            : culled.where((id) => allowed.contains(id) && !hiddenIds.contains(id)).toSet();

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

        // v70 (FIX): REMOVED the synthetic edge fallback.
        //
        // Previously, when a person had NO relationship row in the DB
        // (e.g. they were added without selecting a relationship type),
        // the code drew a FAKE dashed 'related' edge to the anchor.
        // This was misleading — it made the graph look connected when
        // it wasn't, and the fake 'related' key classified as 'extended'
        // (grey), making the node appear grey with no label.
        //
        // Now, unlinked nodes simply have NO edge drawn. They appear as
        // floating circles with no connecting line, which truthfully
        // represents their state: the user hasn't specified how they're
        // related to the anchor. The node still renders with its name,
        // and the user can tap it to add a relationship.
        //
        // The "Links: 0" stat in the home screen correctly reflects
        // this — it counts actual DB rows, not visual edges.

        // v64 (BUG-2 FIX): Deduplicate with smart category-strength
        // selection + lateral offsets for parallel edges.
        final edges = EdgeDeduplicator.deduplicate(rawEdges);

        // v69: Resolve each edge's color from the authoritative category
        // map (relationCategoryById) — no lossy string round-trip.
        //
        // v83: Also check customColors — if an edge has customColors in
        // the relationship data, use the custom line color instead.
        final String? anchorId = _findAnchorId(flat, viewerPersonId);
        final edgeCategories = <String, KinshipEdgeCategory>{};
        final edgeCustomColors = <String, Map<String, dynamic>>{};
        if (anchorId != null) {
          for (final deduped in edges) {
            final e = deduped.edge;
            // Check for custom colors on this edge
            final customColors = customColorsByPersonId[e.sourceId] ??
                customColorsByPersonId[e.targetId];
            if (customColors != null) {
              edgeCustomColors[e.id] = customColors;
            }
            // Determine which endpoint is the anchor and which is the
            // relative. Use the relative's authoritative category.
            KinshipEdgeCategory? cat;
            if (e.sourceId == anchorId) {
              cat = relationCategoryById[e.targetId];
            } else if (e.targetId == anchorId) {
              cat = relationCategoryById[e.sourceId];
            }
            if (cat != null) {
              edgeCategories[e.id] = cat;
            }
          }
        }

        // v92 (PARTS 14–16): Resolve the viewer→target kinship path.
        // This is the SINGLE place path resolution happens — the
        // painter NEVER calls RelationshipEngine. The resolved path
        // is cached in `graphPathFocusProvider` and invalidated
        // automatically when target / viewer / graphRevision change.
        //
        // The selected node IS the path target. When no node is
        // selected the path is cleared.
        final GraphKinshipPathFocus? pathFocus =
            _resolvePathFocus(
          viewerPersonId: viewerPersonId,
          flat: flat,
          edges: edges,
          anchorId: anchorId,
        );
        // v99: Path focus, focus, search, and collapse are all watched
        // + computed ABOVE (before visible-set derivation). No duplicate
        // watches or mutations here.

        // v92 (PART 17): Cache the current edges + positions + categories
        // so the canvas tap handler can do midpoint hit-testing without
        // recomputing them. The positions map includes the visual-circle
        // Y offset so midpoint hit-testing matches the rendered edge
        // geometry exactly.
        _currentEdges = edges;
        _currentEdgeCategories = edgeCategories;
        _currentEdgeCustomColors = edgeCustomColors;
        _currentPositionsWithOffset = {
          for (final entry in layout.positions.entries)
            entry.key: Offset(
              entry.value.dx,
              entry.value.dy + _kCircleCenterYOffset,
            ),
        };

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
                  // v85 FIX: Add ValueKey with edges length + positions
                  // length so the wrapper rebuilds when data changes on
                  // Flutter Web (where identical() can be unreliable).
                  child: _EdgeSelectionWrapper(
                    key: ValueKey('edge_layer_${edges.length}_${layout.positions.length}_${_lodFor(_camera.zoomLevel).name}'),
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
                    edgeCategories: edgeCategories,
                    edgeCustomColors: edgeCustomColors,
                    cache: _edgePathCache,
                    // v91 (PART 10): LOD-aware edge quality.
                    edgeQuality:
                        _edgeQualityFor(_lodFor(_camera.zoomLevel)),
                    // v91 (PART 11): Revision-based repaint correctness.
                    // The painter compares these in `shouldRepaint`
                    // instead of deep-comparing maps every frame.
                    //
                    //   graphRevision    — bumped when edges/positions
                    //                      counts change (add/remove
                    //                      member, edge add/delete).
                    //   layoutRevision   — bumped when layout positions
                    //                      change (re-layout, drag).
                    //   edgeVisualRevision — bumped when categories or
                    //                      custom colours change.
                    //
                    // We use a combined length-based fingerprint for
                    // graphRevision and edgeVisualRevision, and the
                    // layout's canvasWidth/Height + positions length
                    // for layoutRevision. This is O(1) and catches
                    // every real mutation that affects rendering.
                    graphRevision:
                        edges.length * 100003 + layout.positions.length,
                    layoutRevision:
                        (layout.canvasWidth * 1000).round() +
                            (layout.canvasHeight).round() +
                            layout.positions.length,
                    edgeVisualRevision:
                        edgeCategories.length * 100003 +
                            edgeCustomColors.length,
                    // v91 (PART 13): Relationship focus mode. When a
                    // node is selected, unrelated edges are dimmed.
                    // Computed here (cheaply) from the current
                    // selectedNodeProvider + the edge list.
                    dimmedEdgeIds: _computeDimmedEdgeIds(edges),
                    // v92 (PART 14): Kinship path focus. When a path is
                    // resolved, its edges retain full clarity while
                    // unrelated edges dim.
                    pathFocusedEdgeIds: pathFocus?.orderedEdgeIds.toSet(),
                    pathFocusActive: pathFocus != null,
                  ),
                ),
                // Node layer — LOD-dependent. Drawn ON TOP of edges.
                ..._buildNodeLayer(
                    layout, visible, personById, relationLabelById, relationCategoryById, customColorsByPersonId, viewerPersonId, flat),
              ],
            ),
          ),
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.1),
              radius: 1.3,
              colors: [
                Color.lerp(KinrelColors.darkBackground, RelationshipColors.self, 0.06)!,
                KinrelColors.darkBackground,
              ],
              stops: const [0.0, 0.75],
            ),
          ),
          child: CustomPaint(
            painter: _DotGridPainter(color: Colors.white.withValues(alpha: 0.025)),
            child: GestureDetector(
            // v72 FIX: Use translucent (NOT opaque) so child GraphNode
            // gesture detectors can receive tap/long-press events.
            // The previous `opaque` setting swallowed all touch events
            // before they reached the nodes, making taps/long-press
            // impossible on both web and app.
            behavior: HitTestBehavior.translucent,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            // v72 FIX: Add onTapDown + onLongPress for geometric node
            // hit-testing. The parent ScaleGestureRecognizer competes
            // with the child's TapGestureRecognizer in the gesture arena.
            // On web, the scale recognizer wins for ANY pointer sequence,
            // so node taps never fire. We do a geometric hit-test here
            // (convert screen pos → graph space → check if inside any
            // node circle) and handle the tap directly.
            onTapDown: (details) => _handleCanvasTapDown(details, layout, flat, viewerPersonId),
            onLongPressStart: (details) => _handleNodeLongPress(details, layout, flat, viewerPersonId),
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
    Map<String, KinshipEdgeCategory> relationCategoryById,
    Map<String, Map<String, dynamic>> customColorsByPersonId,
    String? viewerPersonId,
    FlatGraphResult flat,
  ) {
    final _Lod lod = _lodFor(_camera.zoomLevel);

    // Dot tier: one painter for ALL visible nodes — no per-node widgets.
    if (lod == _Lod.dot) {
      final dots = <_Dot>[];
      for (final String id in visible) {
        final pos = layout.positions[id];
        final p = personById[id];
        if (pos == null || p == null) continue;

        // v96 (Phase 3): At FAR (dot) zoom, focused/selected/path
        // nodes get an emphasised dot (larger + accent ring) so they
        // remain discoverable.
        // v96 (Phase 5): Search matches also get emphasised dots.
        final focusedId = ref.read(graphFocusProvider).focusedPersonId;
        final selectedId = ref.read(selectedNodeProvider);
        final pathFocus = ref.read(graphPathFocusProvider).focus;
        final pathNodeIds = pathFocus?.orderedPersonIds.toSet();
        final searchState = ref.read(graphSearchProvider);
        final isEmphasised = shouldOverrideFarTier(
          nodeId: id,
          focusedPersonId: focusedId,
          selectedPersonId: selectedId,
          pathNodeIds: pathNodeIds,
        ) || (searchState.isActive && searchState.isMatch(id));

        dots.add(_Dot(
          pos,
          _dotColor(
            p['gender'] as String?,
            (p['isAnchor'] as bool?) ?? false,
            // v69: Use the authoritative category for dot color.
            category: relationCategoryById[id],
            // v83: Use custom colors if available
            customColors: customColorsByPersonId[id],
          ),
          isEmphasised: isEmphasised,
        ));
      }
      return <Widget>[
        Positioned.fill(
          child: CustomPaint(
            painter: _NodeDotPainter(dots, zoom: _camera.zoomLevel),
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
          ? _buildFullNode(id, p, relationLabelById, relationCategoryById, customColorsByPersonId, viewerPersonId)
          : _buildChipNode(p, category: relationCategoryById[id], customColors: customColorsByPersonId[id]);

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
          // 2.5D: Add padding around the node so the elevation shadows
          // (blurRadius up to 20px) have room to render inside the
          // RepaintBoundary layer. Without this padding, the RepaintBoundary
          // clips the shadow to the node's bounds, making it invisible.
          child: RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              // v92 (PART 19): Wrap the node in a Stack so we can
              // overlay the +N collapsed-branch affordance chip.
              child: _withBranchAffordance(node, id, flat),
            ),
          ),
        ),
      ));
    }
    return widgets;
  }

  /// v92 (PART 19): Wraps [node] in a Stack and overlays a "+N"
  /// collapsed-branch affordance chip when the node has hidden
  /// descendants. The chip is positioned at the bottom-right of the
  /// node box, outside the visual circle, so it does not cover the
  /// initials, name, or midpoint bead.
  ///
  /// The chip is only shown when:
  ///   • the node has hidden descendants (descendants not in the
  ///     current visible set)
  ///   • the node is rendered at FULL LOD (the chip is meaningless
  ///     at CHIP/DOT LOD where every node is already a dot)
  ///
  /// Tapping the chip calls `_toggleSubtree` to reveal the branch,
  /// then gently adjusts the camera if the revealed branch would be
  /// mostly outside the viewport.
  Widget _withBranchAffordance(Widget node, String nodeId, FlatGraphResult flat) {
    final hiddenCount = _hiddenDescendantsCount(nodeId, flat);
    if (hiddenCount <= 0) return node;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        node,
        // Position the chip at the bottom-right corner of the node box,
        // just outside the visual circle. The visual circle is ~72px
        // diameter centered at the top of the 140×176 box; the chip
        // sits at the bottom-right where it won't overlap the face
        // or the name.
        Positioned(
          right: -4,
          bottom: 28,
          child: _BranchAffordanceChip(
            count: hiddenCount,
            onTap: () => _handleBranchExpand(nodeId, flat),
          ),
        ),
      ],
    );
  }

  /// v92 (PART 19): Computes the number of hidden descendants for
  /// [nodeId] — i.e. descendants that are NOT in the current visible
  /// set managed by ExpandCollapseController.
  ///
  /// Returns 0 when:
  ///   • the node has no descendants at all
  ///   • all descendants are already visible
  ///   • the visible set is empty (meaning "show everything")
  int _hiddenDescendantsCount(String nodeId, FlatGraphResult flat) {
    final allDescendants = _descendantsOf(nodeId, flat);
    if (allDescendants.isEmpty) return 0;

    // When visibleNodeIds is empty, the controller treats it as
    // "show everything" — so nothing is hidden.
    final visible = _expandCollapse.state.visibleNodeIds;
    if (visible.isEmpty) return 0;

    int hidden = 0;
    for (final d in allDescendants) {
      if (!visible.contains(d)) hidden++;
    }
    return hidden;
  }

  /// v92 (PART 19): Handle a tap on the +N branch affordance chip.
  /// Reveals the hidden branch via the existing `_toggleSubtree`
  /// architecture, then gently adjusts the camera if the revealed
  /// branch would be mostly outside the viewport.
  void _handleBranchExpand(String nodeId, FlatGraphResult flat) {
    // Reduced motion → reveal immediately (no camera animation).
    final bool reduced = MediaQuery.disableAnimationsOf(context);

    // Reveal the branch via the existing toggle architecture.
    _toggleSubtree(nodeId);

    // After the layout rebuilds, gently adjust the camera to bring
    // the newly-revealed descendants into view. We defer this to the
    // next frame so the new positions are available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeAdjustCameraAfterExpand(nodeId, flat, reduced);
    });
  }

  /// v92 (PART 19): After a branch is expanded, check whether the
  /// newly-revealed descendants are mostly outside the viewport. If
  /// so, gently pan the camera (preserving zoom) to bring them in.
  void _maybeAdjustCameraAfterExpand(
      String nodeId, FlatGraphResult flat, bool reduced) {
    if (_viewportSize == Size.zero) return;

    final layoutAsync = ref.read(graphLayoutProvider(widget.familyId));
    final layout = layoutAsync.valueOrNull;
    if (layout == null) return;

    final descendants = _descendantsOf(nodeId, flat);
    if (descendants.isEmpty) return;

    // Compute the bounding box of the revealed descendants.
    final revealedPositions = <Offset>[];
    for (final d in descendants) {
      final pos = layout.positions[d];
      if (pos != null) revealedPositions.add(pos);
    }
    if (revealedPositions.isEmpty) return;

    // Build the bounding box by folding the positions.
    var bounds = Rect.fromPoints(
      revealedPositions.first,
      revealedPositions.first,
    );
    for (final pos in revealedPositions.skip(1)) {
      bounds = Rect.fromPoints(
        Offset(
            min(bounds.left, pos.dx), min(bounds.top, pos.dy)),
        Offset(
            max(bounds.right, pos.dx), max(bounds.bottom, pos.dy)),
      );
    }

    // Expand the bounds a bit for padding.
    final paddedBounds = bounds.inflate(80);

    // Check if the bounds are mostly outside the current viewport.
    final viewport = _camera.computeViewport(_viewportSize);
    final intersection = paddedBounds.intersect(viewport);
    final visibleArea = intersection.width * intersection.height;
    final totalArea = paddedBounds.width * paddedBounds.height;
    if (totalArea <= 0) return;

    // If >50% of the revealed bounds are outside the viewport, pan.
    final visibleFraction = visibleArea / totalArea;
    if (visibleFraction > 0.5) return;

    // Pan the camera to center on the revealed bounds' center.
    final center = paddedBounds.center;
    final Duration duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 420);
    _camera.animateTo(
      -center.dx * _camera.zoomLevel + _viewportSize.width / 2,
      -center.dy * _camera.zoomLevel + _viewportSize.height / 2,
      _camera.zoomLevel,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildFullNode(
    String id,
    Map<String, dynamic> p,
    Map<String, String> labels,
    Map<String, KinshipEdgeCategory> relationCategoryById,
    Map<String, Map<String, dynamic>> customColorsByPersonId,
    String? viewerPersonId,
  ) {
    // v2.2: If this node IS the viewer, show "You" as the relation label.
    final bool isViewer = viewerPersonId != null && id == viewerPersonId;
    // §4: Wire selectedNodeProvider to the node's NodeState so
    // selection visually highlights the node.
    final selectedId = ref.watch(selectedNodeProvider);
    // v95 (Phase 1): Wire graphFocusProvider to NodeState.focused.
    // Focus takes visual precedence over selection — a focused node
    // gets the pulsing glow + camera centering. Selection (tap)
    // still shows the accent border via NodeState.selected, but only
    // when the node is NOT focused.
    final focusedId = ref.watch(graphFocusProvider).focusedPersonId;
    final NodeState nodeState;
    if (id == focusedId) {
      nodeState = NodeState.focused;
    } else if (id == selectedId) {
      nodeState = NodeState.selected;
    } else {
      nodeState = NodeState.normal;
    }

    return GraphNode(
      personId: id,
      name: (p['name'] as String?) ?? '',
      gender: p['gender'] as String?,
      generationIndex: (p['generationIndex'] as num?)?.toInt() ?? 0,
      isAnchor: (p['isAnchor'] as bool?) ?? false,
      photoUrl: p['photoUrl'] as String?,
      isDeceased: (p['isDeceased'] as bool?) ?? false,
      nodeState: nodeState,
      // The "Pending" badge was previously shown for ANY person without
      // a linkedUserId (i.e., not yet claimed by a Kinrel account). But
      // most family tree members (grandparents, children, etc.) are
      // added as Person nodes without Kinrel accounts — they're real
      // family members, not pending invitations. Showing "Pending" on
      // them is misleading.
      //
      // The badge is now disabled by default. It should only be shown
      // when there's an actual pending invitation for this person,
      // which requires checking the FamilyInvite table — not available
      // at the graph node level without an additional query.
      isUnclaimed: false,
      // Pass familyId so GraphNode can render the Kinrel role glyph badge
      // (root/anchor/bridge/weaver/leaf/twin_node) on the node when
      // kEnableKinrel is true.
      familyId: widget.familyId,
      // v69: Pass the AUTHORITATIVE category directly — no lossy string
      // round-trip. GraphNode uses styleForCategory(category) for its
      // border/tint color, which is always correct.
      category: relationCategoryById[id],
      // v2.2: "You" label for the viewer's node; otherwise use the
      // computed relation label from the viewer's perspective.
      relationLabel: isViewer ? 'You' : (labels[id] ?? ''),
      // v93 (ZOOM FIX): Hide the relation label when zoomed out below
      // _kLabelHideZoom (1.0) to reduce clutter. The primary member
      // name is ALWAYS visible.
      showRelationLabel: shouldShowLabel(_camera.zoomLevel),
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
          dateOfBirth: p['dateOfBirth'] as String?,
        );
        // v87: Pass familyId + isOwner + isSelf for Remove Member
        final isAnchor = (p['isAnchor'] as bool?) ?? false;
        GraphQuickActions.show(
          context,
          personData,
          familyId: widget.familyId,
          isOwner: true, // v99 TODO: resolve actual family role from provider
          isSelf: isAnchor, // anchor = family creator = can't remove self
          ref: ref, // v95: enables "Focus on person" action
          onFocusPerson: _onFocusPerson, // v98: real edges + viewport
          onViewRelationship: _onViewRelationship, // v98: "How are we related?"
        );
      },
    );
  }

  /// Lightweight mid-zoom node: a coloured dot + the name, no avatar/animations.
  /// v97: Zoom-aware geometry — chip dimensions are computed from desired
  /// screen-space sizes and converted to graph space so the parent camera
  /// Transform restores them to stable screen-space sizes.
  Widget _buildChipNode(Map<String, dynamic> p, {KinshipEdgeCategory? category, Map<String, dynamic>? customColors}) {
    final color = _dotColor(
      p['gender'] as String?,
      (p['isAnchor'] as bool?) ?? false,
      category: category,
      customColors: customColors,
    );
    // v97: Compute graph-space dimensions from desired screen-space targets.
    final zoom = _camera.zoomLevel;
    final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
    // Screen-space targets (constants):
    const screenMarkerDiameter = 8.0;  // 8px screen marker
    const screenMarkerBorder = 1.5;    // 1.5px screen border
    const screenFontSize = 11.0;       // 11px screen font
    const screenSpacing = 4.0;         // 4px screen gap
    // Graph-space values (divided by zoom so Transform restores them):
    final graphMarkerDiameter = screenMarkerDiameter / safeZoom;
    final graphMarkerBorder = screenMarkerBorder / safeZoom;
    final graphFontSize = screenFontSize / safeZoom;
    final graphSpacing = screenSpacing / safeZoom;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: graphMarkerDiameter,
          height: graphMarkerDiameter,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.3),
              width: graphMarkerBorder,
            ),
          ),
        ),
        SizedBox(height: graphSpacing),
        Flexible(
          child: Text(
            (p['name'] as String?) ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: graphFontSize),
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
    _camera.stopAnimation(); // cancel any in-flight fling/animateTo
    _lastFocal = d.focalPoint;
    _baseZoom = _camera.zoomLevel;
    _isPinching = false; // reset; will be set true on first multi-touch update
  }

  void _onScaleEnd(ScaleEndDetails d) {
    // v97: Only fling on a single-finger pan release.
    // Never fling after a pinch — the velocity is unreliable
    // (pinch-release jitter produces large fake velocities).
    if (!_isPinching) {
      final v = d.velocity.pixelsPerSecond;
      if (v.distance > 50) {
        _camera.applyMomentum(v.dx, v.dy);
      }
    }
    _isPinching = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // v97: Determine if this is a pinch (multi-pointer) or a pan.
    // pointerCount > 1 OR a meaningful scale delta indicates pinch.
    final isPinch = d.pointerCount > 1 || (d.scale - 1.0).abs() > 0.01;
    if (isPinch) {
      _isPinching = true;
    }

    // Pan (works for one- and two-finger drags).
    // During a pinch, the focal point moves as the pinch center
    // shifts. This is natural two-finger panning — apply it once
    // here. The zoomTo focal-point compensation below handles
    // keeping the pinch center stable; we do NOT double-apply.
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

  // ── v72: Geometric Node Hit-Testing ────────────────────────────────────
  //
  // The parent GestureDetector's ScaleGestureRecognizer competes with
  // the child GraphNode's TapGestureRecognizer. On Flutter web, the
  // scale recognizer wins for ANY pointer sequence, so node taps never
  // fire. We solve this by doing a GEOMETRIC hit-test at the parent
  // level: convert the screen position to graph space, then check if
  // it falls inside any node circle.

  /// Converts a screen-space [localPosition] to graph-space coordinates
  /// using the camera's inverse transform.
  ///
  /// The camera transform is: translate(tx, ty) → scale(zoom).
  /// The inverse is: scale(1/zoom) → translate(-tx, -ty).
  /// So: graphPos = (screenPos - translation) / zoom.
  Offset _screenToGraphSpace(Offset localPosition) {
    final matrix = _camera.transformMatrix;
    // Extract translation (tx, ty) and scale (zoom) from the matrix.
    final zoom = matrix.getMaxScaleOnAxis();
    if (zoom == 0) return localPosition;
    final tx = matrix.getTranslation().x;
    final ty = matrix.getTranslation().y;
    return Offset(
      (localPosition.dx - tx) / zoom,
      (localPosition.dy - ty) / zoom,
    );
  }

  /// Finds the node ID at [screenPos], or null if no node is hit.
  /// v97: LOD-aware hit testing — the hit radius is converted from
  /// a minimum screen-space target to graph space via the current zoom.
  String? _hitTestNode(Offset screenPos, GraphLayoutResult layout) {
    final graphPos = _screenToGraphSpace(screenPos);
    // Compute the graph-space hit radius from a screen-space minimum.
    final metrics = _currentMetrics();
    final graphHitRadius = metrics.graphHitRadius;
    String? bestId;
    double bestDist = double.infinity;
    for (final entry in layout.positions.entries) {
      final dist = (entry.value - graphPos).distance;
      if (dist < graphHitRadius && dist < bestDist) {
        bestDist = dist;
        bestId = entry.key;
      }
    }
    return bestId;
  }

  /// v91 (PART 13): Computes the set of edge IDs that should be dimmed
  /// when relationship focus mode is active.
  ///
  /// When a node is selected, DIRECTLY CONNECTED edges retain normal
  /// (or increased) clarity, while UNRELATED edges gently reduce
  /// opacity by ~30%. The selected edge (if any) and any sweep edge
  /// are never dimmed.
  ///
  /// v95 (Phase 1): When a person is FOCUSED (via graphFocusProvider),
  /// uses the focus state's first-degree + second-degree neighbour
  /// sets to keep more edges visible. Only truly unrelated edges
  /// (neither first nor second degree) are dimmed. This creates a
  /// richer focus experience: immediate family stays bright, near
  /// relatives stay visible, distant branches dim softly.
  ///
  /// When no person is focused, falls back to the selection-based
  /// first-degree dim (the v91 behavior).
  ///
  /// Returns `null` when no node is selected AND no person is focused,
  /// so the painter can short-circuit the dim check entirely.
  Set<String>? _computeDimmedEdgeIds(List<DedupedEdge> edges) {
    final focusState = ref.read(graphFocusProvider);
    final String? focusedPerson = focusState.focusedPersonId;
    final searchState = ref.read(graphSearchProvider);

    // v96 (Phase 5): When search is active, dim edges that are NOT
    // connected to any matching node. Matching nodes stay bright
    // regardless of focus state.
    if (searchState.isActive && searchState.matchIds.isNotEmpty) {
      final connected = <String>{};
      final matchSet = searchState.matchIdSet;
      for (final deduped in edges) {
        final e = deduped.edge;
        if (matchSet.contains(e.sourceId) || matchSet.contains(e.targetId)) {
          connected.add(e.id);
        }
      }
      if (connected.length == edges.length) return null;
      final dimmed = <String>{};
      for (final deduped in edges) {
        if (!connected.contains(deduped.edge.id)) {
          dimmed.add(deduped.edge.id);
        }
      }
      return dimmed;
    }

    if (focusedPerson != null) {
      // Focus mode: use first + second degree neighbour sets.
      // An edge is "connected" if EITHER endpoint is the focus person,
      // a first-degree neighbour, or a second-degree neighbour.
      final connected = <String>{};
      final emphasisedIds = <String>{
        focusedPerson,
        ...focusState.firstDegreeIds,
        ...focusState.secondDegreeIds,
      };
      for (final deduped in edges) {
        final e = deduped.edge;
        if (emphasisedIds.contains(e.sourceId) ||
            emphasisedIds.contains(e.targetId)) {
          connected.add(e.id);
        }
      }
      if (connected.length == edges.length) return null;
      final dimmed = <String>{};
      for (final deduped in edges) {
        if (!connected.contains(deduped.edge.id)) {
          dimmed.add(deduped.edge.id);
        }
      }
      return dimmed;
    }

    // Fallback: selection-based first-degree dim (v91 behavior).
    final String? selectedNode = ref.read(selectedNodeProvider);
    if (selectedNode == null) return null;

    final connected = <String>{};
    for (final deduped in edges) {
      final e = deduped.edge;
      if (e.sourceId == selectedNode || e.targetId == selectedNode) {
        connected.add(e.id);
      }
    }

    // If every visible edge is connected, there's nothing to dim.
    if (connected.length == edges.length) return null;

    // Return the COMPLEMENT — edges that are NOT connected.
    final dimmed = <String>{};
    for (final deduped in edges) {
      if (!connected.contains(deduped.edge.id)) {
        dimmed.add(deduped.edge.id);
      }
    }
    return dimmed;
  }

  /// v92 (PARTS 14–16): Resolve the viewer→target kinship path.
  ///
  /// The selected node is the path target. The viewer is the current
  /// viewerPersonId. The path is resolved via the existing
  /// `RelationshipEngine.resolvePath` (which delegates to
  /// `GraphService.findPath` BFS) and post-processed into ordered
  /// person IDs + ordered edge IDs by the
  /// `GraphPathFocusNotifier`.
  ///
  /// This method is called ONCE per build — never inside paint().
  /// The notifier caches the result and short-circuits when the
  /// inputs (viewer, target, graphRevision) haven't changed.
  ///
  /// Returns the resolved `GraphKinshipPathFocus`, or null when:
  ///   • no node is selected
  ///   • viewer is null
  ///   • viewer == selected node
  ///   • no path exists
  GraphKinshipPathFocus? _resolvePathFocus({
    required String? viewerPersonId,
    required FlatGraphResult flat,
    required List<DedupedEdge> edges,
    required String? anchorId,
  }) {
    final String? targetPersonId = ref.read(selectedNodeProvider);
    if (targetPersonId == null || viewerPersonId == null) {
      // Clear any previous focus when nothing is selected.
      ref.read(graphPathFocusProvider.notifier).clear();
      return null;
    }

    // Build the GraphPerson list + relationship tuples the engine needs.
    final persons = <GraphPerson>[];
    for (final p in flat.persons) {
      persons.add(GraphPerson(
        id: (p['id'] ?? '').toString(),
        name: (p['name'] ?? '').toString(),
        gender: p['gender'] as String?,
        generationIndex:
            (p['generationIndex'] as num?)?.toInt() ?? 0,
        isAnchor: (p['isAnchor'] as bool?) ?? false,
        photoUrl: p['photoUrl'] as String?,
        isDeceased: (p['isDeceased'] as bool?) ?? false,
      ));
    }
    final relationships = <({String fromId, String toId, String type})>[
      for (final r in flat.relationships)
        (
          fromId: (r['fromPersonId'] ?? '').toString(),
          toId: (r['toPersonId'] ?? '').toString(),
          type: (r['relationshipKey'] ?? 'unknown').toString(),
        ),
    ];

    // Resolve the structural classification for the overall label/key.
    // Reuses the cached classification from relationCategoryById when
    // possible (already computed for node coloring).
    StructuralClassification? classification;
    try {
      classification = RelationshipEngine.instance.resolveClassification(
        viewerPersonId: viewerPersonId,
        targetPersonId: targetPersonId,
        persons: persons,
        relationships: relationships,
      );
    } catch (_) {
      // Classification is best-effort — if it fails, the path is
      // still resolved without a label.
      classification = null;
    }

    final graphRevision =
        edges.length * 100003 + flat.persons.length;

    return ref.read(graphPathFocusProvider.notifier).resolve(
          viewerPersonId: viewerPersonId,
          targetPersonId: targetPersonId,
          edges: edges,
          persons: persons,
          relationships: relationships,
          graphRevision: graphRevision,
          classification: classification,
        );
  }

  /// v91 (PART 12): Cinematic node focus. When the user taps a person,
  /// the camera gently animates to bring the node towards the focus
  /// region (slightly above viewport center, where the eye naturally
  /// rests). The zoom level is preserved — this is a guided pan, NOT
  /// an aggressive zoom-in.
  ///
  /// Respects reduced motion: when `MediaQuery.disableAnimationsOf` is
  /// true, the camera jumps immediately instead of animating.
  ///
  /// Does NOT create a second camera system — uses the existing
  /// `CameraController` and its `animateTo` API.
  void _maybeFocusCameraOnNode(String nodeId, GraphLayoutResult layout) {
    final pos = layout.positions[nodeId];
    if (pos == null || _viewportSize == Size.zero) return;

    // If the node is already comfortably visible near the viewport
    // center, do not move the camera. This prevents unnecessary motion
    // when the user taps a node that's already in focus.
    final viewport = _camera.computeViewport(_viewportSize);
    final focusRegion = Rect.fromCenter(
      center: viewport.center,
      width: viewport.width * 0.4,
      height: viewport.height * 0.4,
    );
    // Apply the same Y offset used for edges so the focus region aligns
    // with the visual circle center, not the Positioned box center.
    final visualPos = Offset(pos.dx, pos.dy + _kCircleCenterYOffset);
    if (focusRegion.contains(visualPos)) return;

    // Reduced motion → immediate pan, no animation.
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    final Duration duration =
        reduced ? Duration.zero : const Duration(milliseconds: 420);

    // Target: bring the node to viewport center, preserving current zoom.
    _camera.animateTo(
      -pos.dx * _camera.zoomLevel + _viewportSize.width / 2,
      -pos.dy * _camera.zoomLevel + _viewportSize.height / 2,
      _camera.zoomLevel,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  /// v92 (PART 17): Canvas tap dispatcher. Checks edge midpoints FIRST
  /// (with a 48px invisible hit target), then falls back to node
  /// hit-testing. This lets the user tap the small midpoint bead/heart
  /// to open the relationship details sheet without enlarging the
  /// visual bead to 48px.
  ///
  /// The hit-test order is:
  ///   1. Edge midpoint (48px radius) — opens RelationshipInfoSheet
  ///   2. Node (44px radius) — selects node + shows quick-actions sheet
  ///
  /// If neither hits, the tap is a no-op (canvas background tap).
  void _handleCanvasTapDown(
    TapDownDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    // ── 1. Edge midpoint hit-test ──────────────────────────────────
    final edgeId = _hitTestEdge(details.localPosition);
    if (edgeId != null) {
      _handleEdgeTap(edgeId, flat, viewerPersonId);
      return;
    }

    // ── 2. Fall back to node hit-test ──────────────────────────────
    _handleNodeTapDown(details, layout, flat, viewerPersonId);
  }

  /// v92 (PART 17): Geometric hit-test for edge midpoints. Returns the
  /// edge ID whose midpoint is within 48 logical px of [screenPos], or
  /// null if no edge hits.
  ///
  /// The 48px hit target is the spec'd accessible touch size (PART 21).
  /// The VISUAL bead remains 4–6px — only the invisible hit region is
  /// enlarged. If multiple edges overlap near the tap point, the
  /// closest midpoint wins.
  String? _hitTestEdge(Offset screenPos) {
    if (_currentEdges.isEmpty || _currentPositionsWithOffset.isEmpty) {
      return null;
    }
    final graphPos = _screenToGraphSpace(screenPos);
    // v97: Convert screen-space hit radius (48px) to graph space.
    final zoom = _camera.zoomLevel;
    final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
    final hitRadius = 48.0 / safeZoom; // 48px screen-space touch target
    String? bestId;
    double bestDist = double.infinity;
    for (final deduped in _currentEdges) {
      final e = deduped.edge;
      final s = _currentPositionsWithOffset[e.sourceId];
      final t = _currentPositionsWithOffset[e.targetId];
      if (s == null || t == null) continue;
      // The midpoint is the visual center of the edge. For Bézier
      // curves the actual PathMetric 50% tangent position may differ
      // slightly, but for hit-testing the geometric midpoint is a
      // close-enough approximation and is O(1) per edge.
      final mid = Offset((s.dx + t.dx) / 2, (s.dy + t.dy) / 2);
      final dist = (mid - graphPos).distance;
      if (dist < hitRadius && dist < bestDist) {
        bestDist = dist;
        bestId = e.id;
      }
    }
    return bestId;
  }

  /// v92 (PART 17): Handle a tap on an edge midpoint. Selects the edge
  /// (drives the v91 premium selected-edge + one-shot sweep visual)
  /// and opens the RelationshipInfoSheet with the relationship
  /// details + optional path focus info.
  ///
  /// IMPORTANT: The heart symbol is a VISUAL choice — it does NOT
  /// imply spouse semantics. The relationship label is always
  /// resolved from the actual `relationshipKey` stored on the edge,
  /// not from the midpoint symbol. A custom relationship with a heart
  /// midpoint will show its actual custom name in the sheet.
  void _handleEdgeTap(
    String edgeId,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    // Find the deduped edge.
    final deduped = _currentEdges
        .where((d) => d.edge.id == edgeId)
        .firstOrNull;
    if (deduped == null) return;
    final e = deduped.edge;

    // Select the edge — drives the v91 premium selected-edge visual
    // + the one-shot sweep.
    ref.read(selectedEdgeProvider.notifier).state = edgeId;

    // Resolve person A (source) and person B (target) from flat.persons.
    final sourceMap = flat.persons
        .where((p) => p['id'] == e.sourceId)
        .firstOrNull;
    final targetMap = flat.persons
        .where((p) => p['id'] == e.targetId)
        .firstOrNull;
    if (sourceMap == null || targetMap == null) return;

    final sourceName = (sourceMap['name'] as String?) ?? 'Unknown';
    final targetName = (targetMap['name'] as String?) ?? 'Unknown';
    final sourceGender = sourceMap['gender'] as String?;
    final targetGender = targetMap['gender'] as String?;

    // Resolve the relationship label from the actual relationshipKey.
    // The heart symbol does NOT override this — heart is purely visual.
    // PART 17 / PART 21: heart-symbol semantic separation proof.
    final customColors = _currentEdgeCustomColors[e.id];
    String relationshipKey = e.relationshipKey;
    String? customRelationshipName;
    if (customColors != null) {
      // If the custom colors include a custom relationship name, use it.
      // Otherwise fall back to the relationshipKey.
      customRelationshipName =
          customColors['relationshipName'] as String?;
    }

    // v92 (PART 16): Resolve the path focus (if any) to pass to the
    // sheet. If the tapped edge is part of the active path, show the
    // step index.
    final pathFocus = ref.read(graphPathFocusProvider).focus;
    int? stepIndex;
    int? stepCount;
    if (pathFocus != null && pathFocus.orderedEdgeIds.contains(e.id)) {
      stepCount = pathFocus.stepCount;
      stepIndex = pathFocus.orderedEdgeIds.indexOf(e.id) + 1;
    }

    // Open the relationship details sheet. The sheet shows:
    //   • Person A → Person B with the relationship label
    //   • Directional sentences (A is the X of B / B is the Y of A)
    //   • Optional path focus section (if pathFocus is non-null)
    //   • Optional "Focus Path" button (if pathFocus is multi-hop)
    RelationshipInfoSheet.show(
      context,
      sourceId: e.sourceId,
      sourceName: sourceName,
      sourceGender: sourceGender,
      targetId: e.targetId,
      targetName: targetName,
      targetGender: targetGender,
      relationshipKey:
          customRelationshipName ?? relationshipKey,
      pathFocus: pathFocus,
      stepIndex: stepIndex,
      stepCount: stepCount,
      onFocusPath: (pathFocus != null && pathFocus.isMultiHop)
          ? () {
              // Re-trigger the trace by re-selecting the target node.
              // The trace controller will (re)start because the path
              // is already resolved — _maybeStartTrace in the wrapper
              // sees the same path and no-ops, so we explicitly reset
              // and restart by toggling the selection.
              Navigator.of(context).maybePop();
              // Re-select the target to retrigger the trace.
              ref.read(selectedNodeProvider.notifier).state =
                  pathFocus.targetPersonId;
            }
          : null,
    );
  }

  /// Handles a tap-down on the canvas. If the tap hits a node, shows
  /// the quick-actions sheet (same as long-press) — does NOT navigate
  /// to a separate route, avoiding the "Page Not Found" error.
  void _handleNodeTapDown(
    TapDownDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final nodeId = _hitTestNode(details.localPosition, layout);
    if (nodeId == null) return;

    // Select the node.
    ref.read(selectedNodeProvider.notifier).state = nodeId;

    // v91 (PART 12): Cinematic camera focus on node selection.
    _maybeFocusCameraOnNode(nodeId, layout);

    // Show the quick-actions sheet (same as long-press).
    final personData = flat.persons
        .where((p) => p['id'] == nodeId)
        .firstOrNull;
    if (personData == null) return;

    final graphPersonData = GraphPersonData(
      id: nodeId,
      name: (personData['name'] as String?) ?? '',
      gender: personData['gender'] as String?,
      generationIndex:
          (personData['generationIndex'] as num?)?.toInt() ?? 0,
      isAnchor: (personData['isAnchor'] as bool?) ?? false,
      photoUrl: personData['photoUrl'] as String?,
      isDeceased: (personData['isDeceased'] as bool?) ?? false,
    );
    final isAnchor = (personData['isAnchor'] as bool?) ?? false;
    GraphQuickActions.show(
      context,
      graphPersonData,
      familyId: widget.familyId,
      isOwner: true,
      isSelf: isAnchor,
      ref: ref,
      onFocusPerson: _onFocusPerson,
      onViewRelationship: _onViewRelationship,
    );
  }

  /// Handles a long-press on the canvas. If the press hits a node,
  /// shows the quick-actions sheet.
  void _handleNodeLongPress(
    LongPressStartDetails details,
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final nodeId = _hitTestNode(details.localPosition, layout);
    if (nodeId == null) return;

    // Find the person data for this node.
    final personData = flat.persons
        .where((p) => p['id'] == nodeId)
        .firstOrNull;
    if (personData == null) return;

    final graphPersonData = GraphPersonData(
      id: nodeId,
      name: (personData['name'] as String?) ?? '',
      gender: personData['gender'] as String?,
      generationIndex:
          (personData['generationIndex'] as num?)?.toInt() ?? 0,
      isAnchor: (personData['isAnchor'] as bool?) ?? false,
      photoUrl: personData['photoUrl'] as String?,
      isDeceased: (personData['isDeceased'] as bool?) ?? false,
    );
    final isAnchor = (personData['isAnchor'] as bool?) ?? false;
    GraphQuickActions.show(
      context,
      graphPersonData,
      familyId: widget.familyId,
      isOwner: true,
      isSelf: isAnchor,
      ref: ref,
      onFocusPerson: _onFocusPerson,
      onViewRelationship: _onViewRelationship,
    );
  }

  // ── v99 (Phase 1): Engine-owned focus callback ────────────────────────
  //
  // Passed to GraphQuickActions.show() so the Focus action has access
  // to real deduped edges + camera viewport — NOT the empty edges +
  // null viewport that the previous direct-provider-call passed.
  void _onFocusPerson(String personId, String personName) {
    // Build real edge tuples from the current deduped edges.
    final edgeTuples = [
      for (final d in _currentEdges)
        (fromId: d.edge.sourceId, toId: d.edge.targetId),
    ];
    // Capture the current camera viewport for history restore.
    final viewport = FocusViewportSnapshot(
      panX: _camera.panX,
      panY: _camera.panY,
      zoom: _camera.zoomLevel,
    );
    ref.read(graphFocusProvider.notifier).focus(
          personId: personId,
          personName: personName,
          edges: edgeTuples,
          currentViewport: viewport,
        );
  }

  /// v99 (Phase 1): Focus Back — restores the previous focused person
  /// + viewport from focus history.
  void _onFocusBack() {
    final popped = ref.read(graphFocusProvider.notifier).back();
    if (popped == null) return;

    // Restore the camera viewport from the popped history entry.
    final viewport = popped.viewport;
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    _camera.animateTo(
      viewport.panX,
      viewport.panY,
      viewport.zoom,
      duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );

    // Force re-animation + neighbour recompute for restored focus.
    _lastFocusedPersonId = null;
    final currentFocus = ref.read(graphFocusProvider).focusedPersonId;
    if (currentFocus != null) {
      final edgeTuples = [
        for (final d in _currentEdges)
          (fromId: d.edge.sourceId, toId: d.edge.targetId),
      ];
      ref.read(graphFocusProvider.notifier).recomputeNeighbours(edgeTuples);
    }
  }

  /// v98 (Phase 2): Engine-owned "View relationship" callback.
  ///
  /// Resolves the kinship path from the viewer to [targetPersonId]
  /// using the existing RelationshipEngine + graphPathFocusProvider,
  /// then opens RelationshipInfoSheet with the resolved path.
  ///
  /// This is the "How are we related?" hero flow — reachable from
  /// any person's quick-actions menu, not just from edge taps.
  void _onViewRelationship(String targetPersonId) {
    final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;
    if (flat == null) return;

    // Resolve viewerPersonId from the provider.
    final viewerPersonId =
        ref.read(viewerPersonIdProvider(widget.familyId)).valueOrNull;
    if (viewerPersonId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not resolve your family identity. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (viewerPersonId == targetPersonId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This is you!')),
        );
      }
      return;
    }

    // v99 (Phase 2): Resolve the path SYNCHRONOUSLY before opening
    // the sheet. The existing _resolvePathFocus method does this via
    // RelationshipEngine.resolvePath — we call it directly here so
    // the sheet opens with the RESOLVED path, not a placeholder.
    final pathFocus = _resolvePathFocus(
      viewerPersonId: viewerPersonId,
      flat: flat,
      edges: _currentEdges,
      anchorId: _findAnchorId(flat, viewerPersonId),
    );

    // Select the target so the edge painter highlights the path edges
    // and dims non-path context.
    ref.read(selectedNodeProvider.notifier).state = targetPersonId;

    final targetPerson = flat.persons
        .where((p) => p['id'] == targetPersonId)
        .firstOrNull;
    final viewerPerson = flat.persons
        .where((p) => p['id'] == viewerPersonId)
        .firstOrNull;
    if (targetPerson == null || viewerPerson == null) return;

    final targetName = (targetPerson['name'] as String?) ?? '';
    final viewerName = (viewerPerson['name'] as String?) ?? 'You';

    if (pathFocus == null) {
      // No path found — show a clear "no relationship" state.
      RelationshipInfoSheet.show(
        context,
        sourceId: viewerPersonId,
        sourceName: viewerName,
        sourceGender: viewerPerson['gender'] as String?,
        targetId: targetPersonId,
        targetName: targetName,
        targetGender: targetPerson['gender'] as String?,
        relationshipKey: 'unknown',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No confirmed family relationship path found.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Path resolved — open sheet with the ACTUAL resolved kinship term.
    RelationshipInfoSheet.show(
      context,
      sourceId: viewerPersonId,
      sourceName: viewerName,
      sourceGender: viewerPerson['gender'] as String?,
      targetId: targetPersonId,
      targetName: targetName,
      targetGender: targetPerson['gender'] as String?,
      relationshipKey: pathFocus.resolvedRelationshipKey ?? 'related',
      pathFocus: pathFocus,
    );
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
      // v76 FIX: The stored key describes the anchor's relationship TO
      // `to`, NOT the anchor's perspective ON `to`.
      // Example: from: anchor, to: newPerson, key: 'son'
      // → "anchor IS son OF newPerson"
      // → anchor's perspective on newPerson = INVERSE of 'son' = 'parent'
      // Previously this used the raw key 'son', giving the wrong label.
      if (from == sourceId && to != null && !keys.containsKey(to)) {
        final inverseKey = _inverseRelationshipKey(key) ?? key;
        keys[to] = inverseKey;
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

  /// v69: Computes the AUTHORITATIVE [KinshipEdgeCategory] for every
  /// person in the graph from the viewer/anchor's perspective.
  ///
  /// This is the SINGLE source of truth for node AND edge colors. It
  /// eliminates the lossy string round-trip that caused grey nodes:
  /// previously, the render path stored only the kinship key STRING
  /// (via `_relationKeys`), then re-classified it via
  /// `KinshipEdgeClassifier.classify()` — which has gaps (e.g.
  /// 'great_grandfather', 'unknown', compound keys → all fall through
  /// to 'extended' grey).
  ///
  /// This method returns the category DIRECTLY from the structural
  /// classifier, which never has gaps. The caller passes the category
  /// to `GraphNode` and the edge painter, which use
  /// `KinshipEdgeStyleResolver.styleForCategory(category)` — always
  /// correct, never grey for a known relationship.
  ///
  /// PRIORITY (first match wins):
  ///   1. Direct edge from anchor to person → use the STORED key the
  ///      user explicitly selected (honor their choice, don't let BFS
  ///      overwrite it). Classify via the structural classifier.
  ///   2. Multi-hop BFS via RelationshipEngine → use classification.category.
  ///   3. Fallback: null (GraphNode uses 'extended' grey — spec-correct
  ///      for genuinely unclassifiable nodes).
  /// v83: Extracts custom colors from the relationship data.
  ///
  /// Returns a Map<personId, customColors> where customColors is the
  /// JSONB object stored in the Relationship table's customColors column.
  /// Used to override the standard category colors for custom kinships.
  Map<String, Map<String, dynamic>> _extractCustomColors(
    FlatGraphResult flat,
  ) {
    final result = <String, Map<String, dynamic>>{};

    // Find the anchor
    String? anchorId;
    for (final p in flat.persons) {
      if (p['isAnchor'] == true) {
        anchorId = p['id'] as String?;
        break;
      }
    }
    if (anchorId == null) return result;

    for (final r in flat.relationships) {
      final from = r['fromPersonId'] as String?;
      final to = r['toPersonId'] as String?;
      final customColors = r['customColors'];
      if (customColors == null || customColors is! Map) continue;

      // Assign custom colors to the non-anchor person
      final customMap = Map<String, dynamic>.from(customColors);
      if (to == anchorId && from != null) {
        result[from] = customMap;
      } else if (from == anchorId && to != null) {
        result[to] = customMap;
      }
    }

    return result;
  }

  Map<String, KinshipEdgeCategory> _relationCategories(
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    final categories = <String, KinshipEdgeCategory>{};

    // Build GraphPerson list for the structural classifier.
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

    // Find the BFS source (viewer or anchor).
    String? bfsSource = viewerPersonId;
    if (bfsSource == null && graphPersons.isNotEmpty) {
      final anchor = graphPersons.firstWhere(
        (p) => p.isAnchor,
        orElse: () => graphPersons.first,
      );
      bfsSource = anchor.id;
    }
    // Guard: if source is not in graphPersons, fall back to anchor.
    final effectiveSource = graphPersons.any((p) => p.id == bfsSource)
        ? bfsSource
        : (graphPersons.any((p) => p.isAnchor)
            ? graphPersons.firstWhere((p) => p.isAnchor).id
            : (graphPersons.isNotEmpty ? graphPersons.first.id : null));

    if (effectiveSource == null || graphPersons.isEmpty) return categories;

    // Build a set of direct-edge person IDs for fast lookup.
    // A "direct edge" is any edge where one endpoint is the source.
    final directEdgePersons = <String>{};
    for (final r in flat.relationships) {
      final from = r['fromPersonId'] as String?;
      final to = r['toPersonId'] as String?;
      final key = r['relationshipKey'] as String?;
      if (key == null || key.isEmpty) continue;
      if (to == effectiveSource && from != null) {
        directEdgePersons.add(from);
      }
      if (from == effectiveSource && to != null) {
        directEdgePersons.add(to);
      }
    }

    final engine = RelationshipEngine.instance;
    for (final GraphPerson p in graphPersons) {
      if (p.id == effectiveSource) continue; // source is "self"

      KinshipEdgeCategory? category;

      // Priority 1: Direct edge from anchor → use the STORED key.
      // Honor the user's explicit selection — don't let BFS overwrite.
      //
      // v76 FIX: The stored key has DIFFERENT meanings depending on
      // edge direction:
      //   from: newPerson, to: anchor, key: 'father'
      //     → "newPerson IS father OF anchor"
      //     → newPerson's category = 'father' = parent (blue) ✅
      //
      //   from: anchor, to: newPerson, key: 'son'
      //     → "anchor IS son OF newPerson"
      //     → newPerson's category = INVERSE of 'son' = parent (blue) ✅
      //
      // Previously both branches used the raw key, so the second case
      // classified newPerson as 'son' = child (pink) — WRONG.
      if (directEdgePersons.contains(p.id)) {
        // Find the stored key for this direct edge.
        String? storedKey;
        bool needsInverse = false;
        for (final r in flat.relationships) {
          final from = r['fromPersonId'] as String?;
          final to = r['toPersonId'] as String?;
          final key = r['relationshipKey'] as String?;
          if (key == null || key.isEmpty) continue;
          if (to == effectiveSource && from == p.id) {
            // Edge points TO anchor: key IS the anchor's perspective
            // on `from`. Use the key DIRECTLY.
            storedKey = key;
            needsInverse = false;
            break;
          }
          if (from == effectiveSource && to == p.id) {
            // Edge points FROM anchor: key is the anchor's relationship
            // TO `to`, NOT the anchor's perspective ON `to`.
            // The anchor's perspective on `to` is the INVERSE.
            storedKey = key;
            needsInverse = true;
            break;
          }
        }
        if (storedKey != null) {
          // v76: If the edge points FROM anchor, we need the INVERSE
          // key to get the anchor's perspective on the target person.
          // For example: from: anchor, to: newPerson, key: 'son'
          // → anchor IS son OF newPerson → newPerson is anchor's PARENT
          // → we need to classify 'son' as its inverse (parent), not as 'son' (child).
          //
          // For edges pointing TO anchor, the key is already correct.
          final effectiveKey = needsInverse
              ? _inverseKeyForCategory(storedKey)
              : storedKey;

          // v71: Use the 5,363-entry lookup map as the PRIMARY resolver
          // — no string guessing, no gaps. Falls back to the structural
          // classifier only for keys not in the map (e.g. synthetic keys).
          if (KinshipCategoryMap.isKnown(effectiveKey)) {
            category = KinshipCategoryMap.categoryFor(effectiveKey);
          } else {
            final classification = StructuralKinshipClassifier.classify(
              path: [effectiveKey],
              targetGender: p.gender,
            );
            category = classification.category;
          }
        }
      }

      // Priority 2: Multi-hop BFS via RelationshipEngine.
      category ??= engine.resolveClassification(
        viewerPersonId: effectiveSource,
        targetPersonId: p.id,
        persons: graphPersons,
        relationships: graphRels,
      )?.category;

      if (category != null) {
        categories[p.id] = category;
      }
    }

    return categories;
  }

  /// v76: Returns the inverse relationship key for common kinship terms.
  ///
  /// Used by `_relationCategories()` when the stored edge points FROM
  /// the anchor (e.g. `from: anchor, to: newPerson, key: 'son'`).
  /// In this case, 'son' means "anchor IS son OF newPerson", so
  /// newPerson's category is the INVERSE of 'son' = 'parent'.
  ///
  /// For keys not in this map, returns the key unchanged (the
  /// structural classifier will handle it via path analysis).
  static String _inverseKeyForCategory(String key) {
    const inverseMap = <String, String>{
      // Parent ↔ Child
      'father': 'child',
      'mother': 'child',
      'parent': 'child',
      'child': 'parent',
      'son': 'parent',
      'daughter': 'parent',
      // Sibling (symmetric)
      'brother': 'sibling',
      'sister': 'sibling',
      'sibling': 'sibling',
      'elder_brother': 'sibling',
      'younger_brother': 'sibling',
      'elder_sister': 'sibling',
      'younger_sister': 'sibling',
      // Spouse (symmetric)
      'husband': 'spouse',
      'wife': 'spouse',
      'spouse': 'spouse',
      'partner': 'spouse',
      // Grandparent ↔ Grandchild
      'grandfather': 'grandchild',
      'grandmother': 'grandchild',
      'grandparent': 'grandchild',
      'grandchild': 'grandparent',
      'grandson': 'grandparent',
      'granddaughter': 'grandparent',
      // Aunt/Uncle ↔ Nephew/Niece
      'uncle': 'nephew',
      'aunt': 'niece',
      'nephew': 'uncle',
      'niece': 'aunt',
      // Cousin (symmetric)
      'cousin': 'cousin',
      // In-law
      'father_in_law': 'child_in_law',
      'mother_in_law': 'child_in_law',
      'son_in_law': 'parent_in_law',
      'daughter_in_law': 'parent_in_law',
      'brother_in_law': 'sibling_in_law',
      'sister_in_law': 'sibling_in_law',
      // Step
      'step_father': 'step_child',
      'step_mother': 'step_child',
      'step_son': 'step_parent',
      'step_daughter': 'step_parent',
      'step_brother': 'step_sibling',
      'step_sister': 'step_sibling',
      // Compound Indian kinship (common ones)
      'fathers_brother': 'nephew',
      'fathers_sister': 'niece',
      'mothers_brother': 'nephew',
      'mothers_sister': 'niece',
      'brothers_son': 'uncle',
      'brothers_daughter': 'uncle',
      'sisters_son': 'uncle',
      'sisters_daughter': 'uncle',
    };
    return inverseMap[key] ?? key;
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
  Color _dotColor(String? gender, bool isAnchor, {KinshipEdgeCategory? category, Map<String, dynamic>? customColors}) {
    if (isAnchor) return KinshipEdgeColors.self;
    // v83: If custom colors are provided, use the custom node color
    if (customColors != null && customColors['nodeColor'] != null) {
      return Color(customColors['nodeColor'] as int);
    }
    // v69: Use the authoritative category directly — no string round-trip.
    if (category != null && category != KinshipEdgeCategory.self) {
      return KinshipEdgeStyleResolver.styleForCategory(category).color;
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
///
/// v91 (FINAL 10/10 PASS): The wrapper now also drives the ONE graph-level
/// selected-edge light sweep. When `selectedEdgeId` changes, a single
/// AnimationController runs for ~650 ms (or is skipped entirely under
/// reduced motion). The painter receives `sweepProgress` and
/// `sweepActive` and draws a short travelling highlight segment along
/// the selected edge's cached Path. The controller lives HERE — not on
/// the painter — so the painter remains stateless and repaints are
/// scoped to the edge layer only.
///
/// v92 (PARTS 14–15): The wrapper now ALSO drives the sequential
/// kinship path trace via a dedicated `GraphPathTraceController`.
/// When a new path focus is resolved, the trace walks the ordered
/// edges one-by-one (320 ms per edge for short paths, 250 ms for
/// medium, 180 ms for long, capped at ~2200 ms total). The painter
/// receives `traceEdgeId`, `traceProgress`, `traceActive`, and
/// `completedEdgeIds` so it can render:
///   • completed edges — normal path-focus state
///   • current edge    — the moving sweep highlight (reusing the
///                        existing sweep paint pass from v91)
///   • future edges    — normal path-focus state
/// Reduced motion → `revealAll()` instead of `startTrace()`.
class _EdgeSelectionWrapper extends ConsumerStatefulWidget {
  const _EdgeSelectionWrapper({
    super.key,
    required this.positions,
    required this.edges,
    required this.edgeCategories,
    required this.edgeCustomColors,
    required this.cache,
    required this.edgeQuality,
    required this.graphRevision,
    required this.layoutRevision,
    required this.edgeVisualRevision,
    required this.dimmedEdgeIds,
    required this.pathFocusedEdgeIds,
    required this.pathFocusActive,
  });

  final Map<String, Offset> positions;
  final List<DedupedEdge> edges;
  final Map<String, KinshipEdgeCategory> edgeCategories;
  final Map<String, Map<String, dynamic>> edgeCustomColors;
  final EdgePathCache cache;

  /// LOD-derived visual quality tier for the entire edge layer. Computed
  /// ONCE per build from the current graph LOD; the painter never
  /// derives quality per edge.
  final EdgeQuality edgeQuality;

  /// Lightweight revision counters. The painter compares these in
  /// `shouldRepaint` instead of deep-comparing thousands of map entries
  /// every animation frame. See PART 11.
  final int graphRevision;
  final int layoutRevision;
  final int edgeVisualRevision;

  /// Edges that should be visually dimmed (relationship focus mode,
  /// PART 13). Null or empty set = no dimming. The selected edge and
  /// path-focused edges are NEVER dimmed.
  final Set<String>? dimmedEdgeIds;

  /// v92 (PART 14): Edges that are part of the focused viewer→target
  /// kinship path. These retain normal clarity (or slightly increased
  /// clarity) while unrelated edges dim. The selected edge, sweep
  /// edge, and trace edge are always included implicitly by the
  /// painter — they do NOT need to be in this set.
  final Set<String>? pathFocusedEdgeIds;

  /// v92 (PART 14): True when a path focus is active (target selected
  /// and path resolved). When false, `pathFocusedEdgeIds` is ignored.
  final bool pathFocusActive;

  @override
  ConsumerState<_EdgeSelectionWrapper> createState() =>
      _EdgeSelectionWrapperState();
}

class _EdgeSelectionWrapperState extends ConsumerState<_EdgeSelectionWrapper>
    with TickerProviderStateMixin {
  late final AnimationController _sweepController;
  Animation<double>? _sweepAnimation;

  /// The edge ID that was selected when the current sweep started. The
  /// painter uses this (not `selectedEdgeProvider`) to decide which Path
  /// to draw the sweep on, so the sweep stays attached to the right
  /// edge even if selection changes mid-sweep.
  String? _sweepEdgeId;

  /// v92 (PART 15): The sequential path trace controller. One
  /// controller for the entire edge layer — drives edge-by-edge
  /// one-shot sweeps along the focused path.
  late final GraphPathTraceController _traceController;

  /// The ordered edge IDs of the path currently being traced (or
  /// last traced). Used to detect when a new path is resolved so we
  /// can (re)start the trace.
  List<String> _lastTracedEdgeIds = const [];

  /// Reduced-motion preference. When true, the sweep AND the trace
  /// are suppressed and the selected edge / path render in their
  /// static premium state immediately.
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: GraphLighting.sweepDurationMs),
    );
    _sweepAnimation = CurvedAnimation(
      parent: _sweepController,
      curve: Curves.easeOutCubic,
    )..addListener(_onSweepTick);
    _traceController = GraphPathTraceController()..attach(this);
    _traceController.addListener(_onTraceTick);
    // Reduced-motion is resolved per-build via MediaQuery; default false.
  }

  @override
  void dispose() {
    _sweepAnimation?.removeListener(_onSweepTick);
    _sweepController.dispose();
    _traceController.removeListener(_onTraceTick);
    _traceController.dispose();
    super.dispose();
  }

  void _onSweepTick() {
    if (mounted) setState(() {});
  }

  void _onTraceTick() {
    if (mounted) setState(() {});
  }

  /// Called from `build()` to (re)evaluate reduced-motion and start a
  /// fresh sweep when selection changes. This is the SINGLE place that
  /// decides whether to animate — keeping the logic out of the painter.
  void _maybeStartSweep(String? selectedEdgeId) {
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
    }

    // No selection → cancel any in-flight sweep.
    if (selectedEdgeId == null) {
      _sweepController.stop();
      _sweepEdgeId = null;
      return;
    }

    // Same selection as the running sweep → no-op.
    if (selectedEdgeId == _sweepEdgeId) return;

    // New selection → start one sweep (unless reduced motion).
    if (_reducedMotion ||
        !widget.edgeQuality.allowsSweep ||
        !widget.edgeQuality.allowsRidge) {
      // Static-only: immediately show the selected state, no sweep.
      _sweepController.stop();
      _sweepEdgeId = selectedEdgeId;
      return;
    }

    _sweepEdgeId = selectedEdgeId;
    _sweepController.forward(from: 0.0);
  }

  /// v92 (PART 15): Drive the sequential path trace. Called from
  /// `build()` whenever the path focus changes. If the path is new
  /// (different ordered edge IDs), the trace (re)starts. If reduced
  /// motion is on, the path is revealed statically instead.
  void _maybeStartTrace() {
    final pathFocus = ref.read(graphPathFocusProvider).focus;

    if (pathFocus == null || pathFocus.orderedEdgeIds.isEmpty) {
      // No path → reset trace.
      if (_lastTracedEdgeIds.isNotEmpty) {
        _traceController.reset();
        _lastTracedEdgeIds = const [];
      }
      return;
    }

    // Same path as already traced → no-op.
    if (_listEquals(_lastTracedEdgeIds, pathFocus.orderedEdgeIds)) {
      return;
    }

    _lastTracedEdgeIds = List.unmodifiable(pathFocus.orderedEdgeIds);

    // DOT LOD: never animate the trace — reveal statically.
    // CHIP LOD: also skip the trace for performance; reveal statically.
    // FULL LOD: animate (unless reduced motion).
    if (_reducedMotion ||
        !widget.edgeQuality.allowsSweep ||
        !widget.edgeQuality.allowsRidge) {
      _traceController.revealAll(pathFocus.orderedEdgeIds);
    } else {
      _traceController.startTrace(pathFocus.orderedEdgeIds);
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final String? selectedEdgeId = ref.watch(selectedEdgeProvider);
    _maybeStartSweep(selectedEdgeId);
    _maybeStartTrace();

    final double sweepProgress = _sweepAnimation?.value ?? 0.0;
    final bool sweepActive = _sweepController.isAnimating &&
        !_reducedMotion &&
        widget.edgeQuality.allowsSweep;

    // v92 (PART 15): Read the trace state once per build.
    final traceState = _traceController.state;

    return CustomPaint(
      painter: _EngineEdgePainter(
        positions: widget.positions,
        edges: widget.edges,
        edgeCategories: widget.edgeCategories,
        edgeCustomColors: widget.edgeCustomColors,
        cache: widget.cache,
        selectedEdgeId: selectedEdgeId,
        edgeQuality: widget.edgeQuality,
        graphRevision: widget.graphRevision,
        layoutRevision: widget.layoutRevision,
        edgeVisualRevision: widget.edgeVisualRevision,
        dimmedEdgeIds: widget.dimmedEdgeIds,
        sweepEdgeId: sweepActive ? _sweepEdgeId : null,
        sweepProgress: sweepActive ? sweepProgress : 0.0,
        sweepActive: sweepActive,
        // v92 (PARTS 14–15): path focus + sequential trace state.
        pathFocusedEdgeIds: widget.pathFocusActive
            ? widget.pathFocusedEdgeIds
            : null,
        pathFocusActive: widget.pathFocusActive,
        traceEdgeId: traceState.traceActive ? traceState.currentEdgeId : null,
        traceProgress: traceState.traceActive ? traceState.traceProgress : 0.0,
        traceActive: traceState.traceActive,
        completedTraceEdgeIds: traceState.completedEdgeIds.isNotEmpty
            ? traceState.completedEdgeIds
            : null,
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Paths are memoised in [EdgePathCache] keyed by quantized endpoint
/// positions. Because graph-space positions are constant during pan/zoom,
/// repeated frames hit the cache and skip path construction entirely. The
/// factory is O(1) (no per-edge node-collision scan).
///
/// v91 (FINAL 10/10 PASS): The painter is now a stateless physical
/// thread renderer. For each edge it applies the GraphLighting contract:
///
///   FULL LOD — solid edges:
///     PASS 1: contact shadow (neutral black, offset down-right)
///     PASS 2: relationship body (category colour, custom colour)
///     PASS 3: directional light ridge (top-left highlight)
///
///   FULL LOD — dashed edges:
///     Per visible dash segment, the SAME three passes are applied
///     so each dash reads as a physical chip, not a flat coloured
///     tick. Gaps remain real — no continuous glow underneath.
///
///   CHIP LOD: same three passes with conservative sigma / ridge alpha.
///
///   DOT LOD: a single relationship-coloured stroke, no blur, no
///   midpoint, no ridge.
///
///   SELECTED edge (FULL LOD): four passes — stronger shadow, body,
///   brighter ridge, subtle Kinrel-orange interaction aura. The
///   relationship identity is preserved; orange is the interaction
///   accent only.
///
///   ONE-SHOT SWEEP: when `sweepActive`, a short near-white highlight
///   segment travels ONCE along the selected edge's cached Path. The
///   painter does NOT own the AnimationController — it receives
///   `sweepProgress` and draws the segment at that position.
///
/// v92 (PARTS 14–15) PATH FOCUS + SEQUENTIAL TRACE:
///   When `pathFocusActive` is true, edges in `pathFocusedEdgeIds`
///   retain their relationship category colour (and custom colour)
///   but receive a subtle clarity boost — they are NOT recoloured
///   orange. Unrelated edges (those in `dimmedEdgeIds`) dim to ~70%
///   alpha. The trace edge (when `traceActive`) receives the same
///   moving sweep highlight as the selected-edge sweep, reusing the
///   existing `_paintSweepSegment` pass. Completed trace edges
///   remain statically focused via the path-focus state.
class _EngineEdgePainter extends CustomPainter {
  _EngineEdgePainter({
    required this.positions,
    required this.edges,
    required this.edgeCategories,
    required this.edgeCustomColors,
    required this.cache,
    required this.edgeQuality,
    required this.graphRevision,
    required this.layoutRevision,
    required this.edgeVisualRevision,
    this.selectedEdgeId,
    this.dimmedEdgeIds,
    this.sweepEdgeId,
    this.sweepProgress = 0.0,
    this.sweepActive = false,
    this.pathFocusedEdgeIds,
    this.pathFocusActive = false,
    this.traceEdgeId,
    this.traceProgress = 0.0,
    this.traceActive = false,
    this.completedTraceEdgeIds,
  });

  final Map<String, Offset> positions;
  final List<DedupedEdge> edges;
  final Map<String, KinshipEdgeCategory> edgeCategories;
  final Map<String, Map<String, dynamic>> edgeCustomColors;
  final EdgePathCache cache;
  final EdgeQuality edgeQuality;

  /// Revision counters — see PART 11. The painter compares these in
  /// `shouldRepaint` instead of deep-comparing maps every frame.
  final int graphRevision;
  final int layoutRevision;
  final int edgeVisualRevision;

  final String? selectedEdgeId;
  final Set<String>? dimmedEdgeIds;

  /// Edge ID the sweep is currently travelling along. Null when no
  /// sweep is active. May differ from `selectedEdgeId` if selection
  /// changed mid-sweep (the sweep completes on the original edge).
  final String? sweepEdgeId;
  final double sweepProgress;
  final bool sweepActive;

  /// v92 (PART 14): Edges in the focused viewer→target kinship path.
  /// These retain full clarity while unrelated edges dim.
  final Set<String>? pathFocusedEdgeIds;

  /// v92 (PART 14): True when a path focus is active.
  final bool pathFocusActive;

  /// v92 (PART 15): Edge currently being traced by the sequential
  /// path trace. Null when no trace is active.
  final String? traceEdgeId;
  final double traceProgress;
  final bool traceActive;

  /// v92 (PART 15): Edges already traced by the sequential trace.
  /// These remain statically focused after their sweep completes.
  final Set<String>? completedTraceEdgeIds;

  // ── Path construction ─────────────────────────────────────────────────

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

    // Pre-resolve a few per-frame constants from the lighting contract.
    final bool isDot = edgeQuality == EdgeQuality.dot;
    final double shadowSigma = edgeQuality.shadowSigma;
    final double ridgeAlpha = edgeQuality.ridgeAlpha;

    // Relationship-focus dimming factor (PART 13). Edges in
    // `dimmedEdgeIds` get this alpha multiplier so unrelated threads
    // recede gently when a node is selected. The selected edge and
    // any sweep edge are never dimmed.
    const double dimAlpha = 0.70; // ~30% reduction per PART 13

    for (final DedupedEdge deduped in edges) {
      final GraphEdgeData e = deduped.edge;
      final Offset? s = positions[e.sourceId];
      final Offset? t = positions[e.targetId];
      if (s == null || t == null) {
        continue;
      }
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
        pathFactory: (Offset ss, Offset tt) =>
            _bezier(ss, tt, lateralOffset: deduped.lateralOffset),
      );

      final bool isSelected = e.id == selectedEdgeId;
      final bool isSweep = sweepActive && e.id == sweepEdgeId;
      // v92 (PART 14): path-focus state. A path-focused edge retains
      // normal clarity (the dimAlpha does NOT apply to it). The
      // selected edge and sweep edge are always treated as
      // path-focused for dim purposes.
      final bool isPathFocused = pathFocusActive &&
          pathFocusedEdgeIds != null &&
          pathFocusedEdgeIds!.contains(e.id);
      // v92 (PART 15): sequential trace state.
      final bool isTrace = traceActive && e.id == traceEdgeId;
      final bool isCompletedTrace = completedTraceEdgeIds != null &&
          completedTraceEdgeIds!.contains(e.id);
      final bool isDimmed = !isSelected &&
          !isSweep &&
          !isPathFocused &&
          !isTrace &&
          !isCompletedTrace &&
          dimmedEdgeIds != null &&
          dimmedEdgeIds!.contains(e.id);

      // v69: Resolve the edge style from the AUTHORITATIVE category —
      // no lossy string round-trip. If edgeCategories has this edge,
      // use styleForCategory() (always correct, never grey for known
      // relationships). Fall back to styleFor(key) only when no category
      // is available (e.g. edges between two non-anchor nodes).
      //
      // v83: If edgeCustomColors has this edge, override with custom colors.
      final customColors = edgeCustomColors[e.id];
      final KinshipEdgeCategory? edgeCat = edgeCategories[e.id];
      final style = edgeCat != null
          ? KinshipEdgeStyleResolver.styleForCategory(edgeCat)
          : KinshipEdgeStyleResolver.styleFor(e.relationshipKey);

      // v83: Apply custom colors if available
      final Color edgeColor;
      final double edgeAlpha;
      final List<double> dashPattern;
      final KinshipMidpointSymbol midpointSymbol;

      if (customColors != null) {
        edgeColor = Color(customColors['lineColor'] as int? ?? style.color?.value ?? 0xFF888888);
        edgeAlpha = 1.0;
        dashPattern = customColors['lineType'] == 'dashed' ? [6.0, 4.0] : [];
        final dotType = customColors['dotType'] as String? ?? 'dot';
        midpointSymbol = dotType == 'heart'
            ? KinshipMidpointSymbol.heart
            : dotType == 'none'
                ? KinshipMidpointSymbol.none
                : KinshipMidpointSymbol.dot;
      } else {
        edgeColor = style.color ?? const Color(0xFF888888);
        edgeAlpha = style.defaultAlpha.clamp(0.3, 1.0);
        dashPattern = style.dashPattern;
        midpointSymbol = style.midpointSymbol;
      }

      // Effective stroke width clamped to the lighting contract range.
      final double bodyWidth = GraphLighting.clampBodyWidth(style.strokeWidth);

      // v92 (PART 14): Path-focused edges get a subtle clarity boost
      // (~10% alpha lift, capped at 1.0). They retain their
      // relationship category colour — orange is NOT applied here.
      final double pathFocusBoost =
          (isPathFocused || isCompletedTrace) ? 0.10 : 0.0;

      // Final alpha after relationship-focus dimming + path-focus boost.
      final double effectiveAlpha = isDimmed
          ? (edgeAlpha * dimAlpha).clamp(0.0, 1.0)
          : (edgeAlpha + pathFocusBoost).clamp(0.0, 1.0);

      // ── DOT LOD: minimal stroke only ──────────────────────────────
      // No blur, no ridge, no midpoint, no sweep. Selected edges get
      // a slightly thicker stroke + a subtle orange aura so focus is
      // still legible at the cheapest tier.
      if (isDot) {
        if (isSelected) {
          // PASS D — orange interaction aura (cheap, no blur)
          final dotAuraPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = bodyWidth + 2.0
            ..color = KinrelColors.orange
                .withValues(alpha: GraphLighting.selectedAuraAlpha)
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true;
          canvas.drawPath(path, dotAuraPaint);
        }
        final dotBodyPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? bodyWidth + 0.6 : bodyWidth
          ..color = edgeColor.withValues(alpha: effectiveAlpha)
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
        canvas.drawPath(path, dotBodyPaint);
        continue;
      }

      // ── FULL / CHIP LOD: physical 3-pass thread ───────────────────
      //
      // For dashed edges we apply the SAME 3 passes to each visible
      // dash segment (no continuous glow underneath). For solid edges
      // we apply the 3 passes to the whole Path.

      if (isSelected) {
        _paintSelectedEdge(
          canvas: canvas,
          path: path,
          edgeColor: edgeColor,
          bodyWidth: bodyWidth,
          edgeAlpha: edgeAlpha,
          dashPattern: dashPattern,
          shadowSigma: shadowSigma,
          ridgeAlpha: ridgeAlpha,
        );
      } else if (dashPattern.isNotEmpty && dashPattern.length >= 2) {
        _paintDashedPhysical(
          canvas: canvas,
          path: path,
          edgeColor: edgeColor,
          bodyWidth: bodyWidth,
          edgeAlpha: effectiveAlpha,
          dashPattern: dashPattern,
          shadowSigma: shadowSigma,
          ridgeAlpha: ridgeAlpha,
        );
      } else {
        _paintSolidPhysical(
          canvas: canvas,
          path: path,
          edgeColor: edgeColor,
          bodyWidth: bodyWidth,
          edgeAlpha: effectiveAlpha,
          shadowSigma: shadowSigma,
          ridgeAlpha: ridgeAlpha,
        );
      }

      // ── ONE-SHOT SWEEP ────────────────────────────────────────────
      // Drawn ABOVE the selected-edge passes. A short near-white
      // highlight segment travels once along the cached Path.
      if (isSweep) {
        _paintSweepSegment(
          canvas: canvas,
          path: path,
          progress: sweepProgress,
          edgeColor: edgeColor,
          bodyWidth: bodyWidth,
        );
      }

      // v92 (PART 15): SEQUENTIAL TRACE SWEEP — drawn ABOVE the
      // path-focus state. Reuses the same `_paintSweepSegment` pass
      // as the selected-edge sweep, but driven by `traceProgress`
      // along the current trace edge. Completed trace edges remain
      // statically focused via the `isCompletedTrace` alpha boost
      // applied above — no extra paint pass needed for them.
      if (isTrace) {
        _paintSweepSegment(
          canvas: canvas,
          path: path,
          progress: traceProgress,
          edgeColor: edgeColor,
          bodyWidth: bodyWidth,
        );
      }

      // ── MIDPOINT SYMBOL ───────────────────────────────────────────
      // Bead / heart only at FULL or CHIP LOD (PART 10). Skipped at
      // DOT LOD and skipped when the edge is dimmed (focus mode).
      if (edgeQuality.allowsMidpoint &&
          midpointSymbol != KinshipMidpointSymbol.none &&
          !isDimmed) {
        _paintMidpoint(
          canvas: canvas,
          path: path,
          s: s,
          t: t,
          midpointSymbol: midpointSymbol,
          customColors: customColors,
          style: style,
          edgeColor: edgeColor,
          effectiveStrokeWidth: bodyWidth,
          isSelected: isSelected,
        );
      }
    }
  }

  // ── Physical paint helpers ───────────────────────────────────────────

  /// PASS 1 + 2 + 3 for a solid (non-dashed) relationship thread.
  ///
  ///   PASS 1: contact shadow — neutral black, offset down-right,
  ///           slightly wider than the body, blurred.
  ///   PASS 2: relationship body — category colour (or custom colour),
  ///           clamped to the lighting contract width range.
  ///   PASS 3: directional light ridge — thin top-left highlight,
  ///           translated by `GraphLighting.highlightOffset`.
  void _paintSolidPhysical({
    required Canvas canvas,
    required Path path,
    required Color edgeColor,
    required double bodyWidth,
    required double edgeAlpha,
    required double shadowSigma,
    required double ridgeAlpha,
  }) {
    // PASS 1 — contact shadow (only when blur is allowed — never at DOT).
    if (shadowSigma > 0) {
      canvas.save();
      canvas.translate(GraphLighting.shadowOffset.dx, GraphLighting.shadowOffset.dy);
      final shadowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth + 2.4
        ..color = Colors.black.withValues(alpha: GraphLighting.shadowAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowSigma)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(path, shadowPaint);
      canvas.restore();
    }

    // PASS 2 — relationship body.
    final bodyPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bodyWidth
      ..color = edgeColor.withValues(alpha: edgeAlpha)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(path, bodyPaint);

    // PASS 3 — directional light ridge (top-left highlight).
    if (ridgeAlpha > 0) {
      canvas.save();
      canvas.translate(GraphLighting.highlightOffset.dx, GraphLighting.highlightOffset.dy);
      final ridgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (bodyWidth * 0.32).clamp(0.6, 1.0)
        ..color = GraphLighting.ridgeColor(edgeColor)
            .withValues(alpha: ridgeAlpha)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(path, ridgePaint);
      canvas.restore();
    }
  }

  /// Per-dash 3-pass physical rendering for dashed relationship threads.
  ///
  /// Obtains the PathMetric ONCE, extracts all visible dash segments
  /// ONCE, and reuses those segments for shadow / body / ridge — so we
  /// never recompute dash geometry across the three passes.
  ///
  /// Gaps remain real: no continuous coloured glow is painted
  /// underneath the dashed edge (PART 4).
  void _paintDashedPhysical({
    required Canvas canvas,
    required Path path,
    required Color edgeColor,
    required double bodyWidth,
    required double edgeAlpha,
    required List<double> dashPattern,
    required double shadowSigma,
    required double ridgeAlpha,
  }) {
    final dashWidth = dashPattern[0];
    final dashGap = dashPattern[1];

    // Collect dash segments ONCE for all 3 passes.
    final segments = <Path>[];
    for (final metric in path.computeMetrics()) {
      double pos = 0;
      while (pos < metric.length) {
        final segEnd = (pos + dashWidth).clamp(0.0, metric.length);
        segments.add(metric.extractPath(pos, segEnd));
        pos += dashWidth + dashGap;
      }
    }

    // PASS 1 — per-dash contact shadow.
    if (shadowSigma > 0) {
      canvas.save();
      canvas.translate(GraphLighting.shadowOffset.dx, GraphLighting.shadowOffset.dy);
      final shadowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth + 2.0
        ..color = Colors.black.withValues(alpha: GraphLighting.shadowAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowSigma)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      for (final seg in segments) {
        canvas.drawPath(seg, shadowPaint);
      }
      canvas.restore();
    }

    // PASS 2 — per-dash relationship body.
    final bodyPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bodyWidth
      ..color = edgeColor.withValues(alpha: edgeAlpha)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (final seg in segments) {
      canvas.drawPath(seg, bodyPaint);
    }

    // PASS 3 — per-dash directional light ridge.
    if (ridgeAlpha > 0) {
      canvas.save();
      canvas.translate(GraphLighting.highlightOffset.dx, GraphLighting.highlightOffset.dy);
      final ridgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (bodyWidth * 0.32).clamp(0.6, 1.0)
        ..color = GraphLighting.ridgeColor(edgeColor)
            .withValues(alpha: ridgeAlpha)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      for (final seg in segments) {
        canvas.drawPath(seg, ridgePaint);
      }
      canvas.restore();
    }
  }

  /// 4-pass premium treatment for the SELECTED edge (PART 7).
  ///
  ///   PASS A: stronger neutral contact shadow
  ///   PASS B: ORIGINAL relationship-coloured body (identity preserved)
  ///   PASS C: brighter top-left ridge
  ///   PASS D: subtle Kinrel-orange interaction aura
  ///
  /// The orange is an INTERACTION accent only — it never replaces the
  /// relationship category colour.
  void _paintSelectedEdge({
    required Canvas canvas,
    required Path path,
    required Color edgeColor,
    required double bodyWidth,
    required double edgeAlpha,
    required List<double> dashPattern,
    required double shadowSigma,
    required double ridgeAlpha,
  }) {
    // For dashed selected edges, fall back to per-dash physical
    // rendering for the body + ridge (so dash semantics survive
    // selection), then add the orange aura as a continuous underneath
    // pass. The aura is the only continuous pass; it is subtle and
    // does NOT obscure the dashes.
    final bool dashed = dashPattern.isNotEmpty && dashPattern.length >= 2;

    // PASS D — Kinrel orange interaction aura (drawn FIRST so it sits
    // underneath the body). Continuous even for dashed edges, but very
    // subtle so dash gaps still read.
    if (shadowSigma > 0) {
      final auraPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth + GraphLighting.selectedAuraWidthDelta
        ..color = KinrelColors.orange
            .withValues(alpha: GraphLighting.selectedAuraAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, GraphLighting.selectedAuraSigma)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(path, auraPaint);
    }

    // PASS A — stronger neutral contact shadow.
    if (shadowSigma > 0) {
      canvas.save();
      canvas.translate(GraphLighting.shadowOffset.dx, GraphLighting.shadowOffset.dy);
      final shadowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth + 2.8
        ..color = Colors.black
            .withValues(alpha: GraphLighting.selectedShadowAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowSigma)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(path, shadowPaint);
      canvas.restore();
    }

    if (dashed) {
      // PASS B + C per dash segment.
      final dashWidth = dashPattern[0];
      final dashGap = dashPattern[1];
      final segments = <Path>[];
      for (final metric in path.computeMetrics()) {
        double pos = 0;
        while (pos < metric.length) {
          final segEnd = (pos + dashWidth).clamp(0.0, metric.length);
          segments.add(metric.extractPath(pos, segEnd));
          pos += dashWidth + dashGap;
        }
      }

      // PASS B — relationship-coloured body per dash.
      final bodyPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth
        ..color = edgeColor.withValues(alpha: edgeAlpha)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      for (final seg in segments) {
        canvas.drawPath(seg, bodyPaint);
      }

      // PASS C — brighter top-left ridge per dash.
      if (ridgeAlpha > 0) {
        canvas.save();
        canvas.translate(GraphLighting.highlightOffset.dx, GraphLighting.highlightOffset.dy);
        final ridgePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (bodyWidth * 0.36).clamp(0.6, 1.2)
          ..color = GraphLighting.ridgeColor(edgeColor, t: 0.65)
              .withValues(alpha: (ridgeAlpha + 0.10).clamp(0.0, 1.0))
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
        for (final seg in segments) {
          canvas.drawPath(seg, ridgePaint);
        }
        canvas.restore();
      }
    } else {
      // PASS B — relationship-coloured body (continuous).
      final bodyPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyWidth
        ..color = edgeColor.withValues(alpha: edgeAlpha)
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawPath(path, bodyPaint);

      // PASS C — brighter top-left ridge.
      if (ridgeAlpha > 0) {
        canvas.save();
        canvas.translate(GraphLighting.highlightOffset.dx, GraphLighting.highlightOffset.dy);
        final ridgePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (bodyWidth * 0.36).clamp(0.6, 1.2)
          ..color = GraphLighting.ridgeColor(edgeColor, t: 0.65)
              .withValues(alpha: (ridgeAlpha + 0.10).clamp(0.0, 1.0))
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true;
        canvas.drawPath(path, ridgePaint);
        canvas.restore();
      }
    }
  }

  /// ONE-SHOT sweep (PART 8). A short near-white highlight segment
  /// travels ONCE along the selected edge's cached Path. The painter
  /// does NOT own the AnimationController — it receives `progress`
  /// (0..1) and extracts the segment at that position.
  void _paintSweepSegment({
    required Canvas canvas,
    required Path path,
    required double progress,
    required Color edgeColor,
    required double bodyWidth,
  }) {
    final metrics = path.computeMetrics();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    if (metric.length <= 0) return;

    final double center = (metric.length * progress).clamp(0.0, metric.length);
    final double segLen =
        (metric.length * GraphLighting.sweepSegmentFraction)
            .clamp(8.0, metric.length);
    final double start = (center - segLen / 2).clamp(0.0, metric.length);
    final double end = (center + segLen / 2).clamp(0.0, metric.length);
    if (end <= start) return;

    final Path sweepPath = metric.extractPath(start, end);

    // Soft near-white tinted-with-relationship-colour highlight.
    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bodyWidth + 1.2
      ..color = GraphLighting.ridgeColor(edgeColor, t: 0.75)
          .withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(sweepPath, sweepPaint);

    // Crisp inner core for a premium "polished filament" read.
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (bodyWidth * 0.5).clamp(0.8, 1.6)
      ..color = Colors.white.withValues(alpha: 0.70)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(sweepPath, corePaint);
  }

  /// Midpoint bead / heart (PART 6). Branches on `midpointSymbol`:
  ///   • heart → HeartShape.drawHeart (spouse pink, or custom-heart pink)
  ///   • dot   → pseudo-3D obsidian bead with effective midpoint colour
  void _paintMidpoint({
    required Canvas canvas,
    required Path path,
    required Offset s,
    required Offset t,
    required KinshipMidpointSymbol midpointSymbol,
    required Map<String, dynamic>? customColors,
    required KinshipEdgeStyle style,
    required Color edgeColor,
    required double effectiveStrokeWidth,
    required bool isSelected,
  }) {
    Offset midPoint = Offset((s.dx + t.dx) / 2, (s.dy + t.dy) / 2);
    for (final metric in path.computeMetrics()) {
      if (metric.length > 0) {
        final tangent = metric.getTangentForOffset(metric.length * 0.5);
        if (tangent != null) {
          midPoint = tangent.position;
          break;
        }
      }
    }

    // Resolve the effective midpoint color.
    //   • Default relationship → style.midpointColor (pink for spouse,
    //     edge colour for every other category).
    //   • Custom relationship + heart → force pink (hearts are always
    //     pink in Kinrel's design language).
    //   • Custom relationship + dot   → use the custom edge colour so
    //     the bead inherits the user's chosen relationship identity.
    final Color effectiveMidpointColor;
    if (customColors != null) {
      if (midpointSymbol == KinshipMidpointSymbol.heart) {
        effectiveMidpointColor = KinshipEdgeColors.spouseHeart;
      } else {
        effectiveMidpointColor = edgeColor;
      }
    } else {
      effectiveMidpointColor = style.midpointColor;
    }

    if (midpointSymbol == KinshipMidpointSymbol.heart) {
      // ── HEART (spouse only by default) ───────────────────────
      final double heartSize =
          GraphLighting.heartSizeFor(effectiveStrokeWidth);
      HeartShape.drawHeart(
        canvas: canvas,
        center: midPoint,
        size: heartSize,
        color: effectiveMidpointColor,
        compact: edgeQuality != EdgeQuality.full,
      );
    } else {
      // ── PSEUDO-3D DOT BEAD ───────────────────────────────────
      final double beadR =
          GraphLighting.beadRadiusFor(effectiveStrokeWidth);
      final beadRect = Rect.fromCircle(center: midPoint, radius: beadR);

      // Shadow — down-right per global lighting contract.
      canvas.drawCircle(
        midPoint + GraphLighting.shadowOffset,
        beadR,
        Paint()
          ..color = Colors.black
              .withValues(alpha: isSelected
                  ? GraphLighting.selectedShadowAlpha
                  : GraphLighting.shadowAlpha)
          ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              edgeQuality == EdgeQuality.full
                  ? 2.0
                  : 1.4),
      );

      // Dark rim (bottom) — adds convex depth reading.
      canvas.drawArc(
        Rect.fromCircle(
            center: midPoint + const Offset(0, 1.5), radius: beadR),
        0.0,
        pi,
        false,
        Paint()
          ..color =
              Color.lerp(effectiveMidpointColor, Colors.black, 0.5)!,
      );

      // Face gradient — upper-left light, darker bottom-right.
      canvas.drawCircle(
        midPoint,
        beadR,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 0.8,
            colors: [
              Color.lerp(effectiveMidpointColor, Colors.white, 0.3)!,
              effectiveMidpointColor,
              Color.lerp(effectiveMidpointColor, Colors.black, 0.3)!,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(beadRect),
      );

      // Specular highlight — tiny, upper-left.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
              midPoint.dx - beadR * 0.25, midPoint.dy - beadR * 0.3),
          width: beadR * 0.5,
          height: beadR * 0.3,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EngineEdgePainter old) {
    // v91 (PART 11): Revision-based repaint correctness.
    //
    // The old implementation compared only collection LENGTHS, which
    // missed content changes where:
    //   • edge count is unchanged but a category changed
    //   • position count is unchanged but coordinates changed
    //   • custom colours changed without changing edge count
    //
    // The new implementation compares lightweight revision counters
    // that are bumped by the data layer whenever the corresponding
    // data mutation happens. This avoids deep-comparing thousands of
    // map entries on every animation frame (which would be O(N) per
    // tick) while still repainting on every real content change.
    //
    // We also repaint on:
    //   • selectedEdgeId change (selected-edge premium treatment)
    //   • sweepActive / sweepProgress change (one-shot sweep ticks)
    //   • edgeQuality change (LOD transition)
    //   • dimmedEdgeIds presence change (relationship focus mode)
    //   • pathFocusActive / pathFocusedEdgeIds change (PART 14)
    //   • traceActive / traceProgress / traceEdgeId change (PART 15)
    //   • completedTraceEdgeIds change (PART 15)
    //
    // We intentionally do NOT use `identical()` — on Flutter Web
    // (dart2js) it is unreliable across widget rebuilds.
    return old.graphRevision != graphRevision ||
        old.layoutRevision != layoutRevision ||
        old.edgeVisualRevision != edgeVisualRevision ||
        old.selectedEdgeId != selectedEdgeId ||
        old.edgeQuality != edgeQuality ||
        old.sweepActive != sweepActive ||
        (sweepActive && old.sweepProgress != sweepProgress) ||
        !_sameDimmedSet(old.dimmedEdgeIds) ||
        // v92 (PART 14): path-focus changes
        old.pathFocusActive != pathFocusActive ||
        !_sameSet(old.pathFocusedEdgeIds, pathFocusedEdgeIds) ||
        // v92 (PART 15): trace changes
        old.traceActive != traceActive ||
        old.traceEdgeId != traceEdgeId ||
        (traceActive && old.traceProgress != traceProgress) ||
        !_sameSet(old.completedTraceEdgeIds, completedTraceEdgeIds);
  }

  /// Lightweight dimmed-set comparison. We do NOT deep-compare element
  /// by element on every frame — we compare length + identity first,
  /// and only fall back to a containsAll check when lengths match but
  /// identities differ. This is O(N) only on actual focus-mode
  /// transitions, not on every animation tick.
  bool _sameDimmedSet(Set<String>? other) =>
      _sameSet(dimmedEdgeIds, other);

  /// v92: Generic lightweight set comparison used for dimmedEdgeIds,
  /// pathFocusedEdgeIds, and completedTraceEdgeIds.
  bool _sameSet(Set<String>? a, Set<String>? b) {
    if (identical(a, b)) return true;
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// v92 (PART 19) — +N COLLAPSED BRANCH AFFORDANCE
// ═══════════════════════════════════════════════════════════════════════

/// A small "+N" chip overlaid on a node that has [count] hidden
/// descendants. Tapping the chip reveals the branch via the existing
/// ExpandCollapseController.
///
/// Visual design (per PART 19 spec):
///   • dark Kinrel surface (#1A1F2B)
///   • subtle border (orange @ 0.4 alpha)
///   • restrained orange interaction accent
///   • minimum accessible hit target (44×44)
///   • visual element remains compact (the chip itself is small, but
///     the hit area extends to 44px)
class _BranchAffordanceChip extends StatelessWidget {
  const _BranchAffordanceChip({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  static const Color _bg = Color(0xFF1A1F2B);
  static const Color _orange = Color(0xFFE8863A);
  static const Color _textWhite = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$count hidden family members. Expand branch.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          // The visual chip is compact, but the hit area is the
          // minimum accessible size (44×44) via the InkWell's
          // automatic minimum size.
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _orange.withValues(alpha: 0.4)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 6,
                    offset: Offset(1, 2),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.unfold_more_rounded,
                      color: _orange,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '+$count',
                      style: const TextStyle(
                        color: _textWhite,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single node rendered as a coloured dot at the lowest LOD tier.
class _Dot {
  const _Dot(this.pos, this.color, {this.isEmphasised = false});
  final Offset pos;
  final Color color;
  /// v96 (Phase 3): When true, this dot is drawn larger (9px) with an
  /// accent ring — used for focused/selected/path nodes at FAR zoom
  /// so they remain discoverable.
  final bool isEmphasised;
}

/// Paints a very faint dot-grid on the graph background for spatial texture.
/// Static (shouldRepaint returns false) — painted once, not per-frame.
class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color, this.spacing = 32.0});
  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) => false;
}

/// Draws every visible node as a dot in ONE painter — avoids thousands of
/// widgets when fully zoomed out (the 2000-node case).
///
/// v97: Node radius is now ZOOM-AWARE. The painter receives the current
/// camera zoom and computes graph-space radii from desired screen-space
/// radii: graphRadius = screenRadius / zoom. This ensures overview
/// markers maintain a minimum visible screen-space diameter (10–16px)
/// across the entire zoom range — they never become 1–5px specks.
class _NodeDotPainter extends CustomPainter {
  _NodeDotPainter(this.dots, {this.zoom = 1.0});

  final List<_Dot> dots;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final ringPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    // v97: Compute graph-space radii from desired screen-space radii.
    // safeZoom guards against NaN, zero, and negative zoom.
    final safeZoom = (zoom > 0.001 && zoom.isFinite) ? zoom : 1.0;
    const screenNormalR = 6.0;
    const screenEmphasisR = 9.0;
    const screenRingStroke = 2.0;
    final graphNormalR = screenNormalR / safeZoom;
    final graphEmphasisR = screenEmphasisR / safeZoom;
    final graphRingStroke = screenRingStroke / safeZoom;
    final graphRingOffset = 3.0 / safeZoom; // ring is 3px outside the dot

    ringPaint.strokeWidth = graphRingStroke;

    for (final _Dot d in dots) {
      final radius = d.isEmphasised ? graphEmphasisR : graphNormalR;
      paint.color = d.color;

      if (d.isEmphasised) {
        // Draw an accent ring around the emphasised dot.
        ringPaint.color = d.color.withValues(alpha: 0.5);
        canvas.drawCircle(d.pos, radius + graphRingOffset, ringPaint);
      }

      canvas.drawCircle(d.pos, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NodeDotPainter old) =>
      old.dots.length != dots.length ||
      !identical(old.dots, dots) ||
      (old.zoom - zoom).abs() > 0.001;
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
