import 'dart:math';
import 'dart:ui' show ImageFilter;
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
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/sync/connectivity_service.dart' show isOnlineProvider;
import '../../core/family/family_provider.dart' show currentUserFamilyRoleProvider;
import '../../core/services/analytics_service.dart';
import '../../core/services/graph_layout_service.dart' show GraphLayoutResult, GraphPerson;
import '../../features/family/presentation/providers/family_graph_provider.dart'
    show
        FlatGraphResult,
        familyGraphProvider,
        graphLayoutProvider,
        graphRealtimeProvider,
        selectedEdgeProvider,
        selectedNodeProvider;
import '../data/graph_data_models.dart' show GraphEdgeData;
import '../data/position_memory.dart' show PositionMemory;
import '../engine/edge_dedup.dart' show DedupedEdge, EdgeDeduplicator;
import '../interaction/camera_controller.dart' show CameraController;
import '../interaction/expand_collapse.dart'
    show ExpandCollapseController, ExpandCollapseState;
import '../interaction/haptic_language.dart' show GraphHaptics;
import '../interaction/keyboard_navigation_controller.dart'
    show handleGraphKeyEvent;
import '../rendering/birthday_pulse_controller.dart' show birthdayPulseProvider;
import '../rendering/birthday_util.dart' show isNearBirthday, daysUntilBirthday;
import '../rendering/memorial_candle_flicker_controller.dart'
    show memorialCandleFlickerProvider;
import '../rendering/ambient_particle_painter.dart' show AmbientParticlePainter;
import '../rendering/ambient_particle_controller.dart'
    show ambientParticleProvider;
import '../interaction/graph_focus_state.dart'
    show
        GraphFocusNotifier,
        GraphFocusState,
        FocusViewportSnapshot,
        FocusHistoryEntry,
        PathSelectPhase,
        graphFocusProvider;
import '../interaction/couple_union_model.dart'
    show CoupleUnion, unionMidpoint;
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
import '../interaction/couple_union_model.dart'
    show
        CoupleUnion,
        deriveCoupleUnions,
        resolveEffectiveEdgeEndpoints,
        unionMidpoint;
import '../../core/constants/feature_flags.dart' show kEnableGraphShareExport;
import '../../core/constants/brand_colors.dart' show KinrelColors;
import '../../core/constants/brand_typography.dart' show KinrelTypography;
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
import '../rendering/emphasis_priority.dart'
    show EmphasisLevel, computeEmphasisLevel;
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
import 'graph_node.dart' show GraphNode, NodeState;
import 'on_this_day_badge.dart' show OnThisDayBadge, OnThisDayEvent, OnThisDayEventType, showOnThisDayEventSheet;
import 'graph_minimap.dart' show GraphMiniMap;
import 'graph_outline_view.dart' show GraphOutlineView;
import 'graph_legend.dart' show GraphLegend;
import 'graph_quick_actions.dart' show GraphQuickActions;
import 'graph_relationship_labels.dart' show GraphPersonData;
import '../interaction/relationship_linking_state.dart'
    show
        RelationshipCreationState,
        RelationshipCreationNotifier,
        relationshipCreationProvider,
        CreationPhase;
import 'relationship_info_sheet.dart' show RelationshipInfoSheet;

// ── P0.4: Extracted helpers (imports MUST come before part directives) ──
import 'engine/lod.dart' show Lod;
import 'engine/dot.dart' show Dot;
import 'engine/dot_grid_painter.dart' show DotGridPainter;
import 'engine/node_dot_painter.dart' show NodeDotPainter;
import 'engine/engine_edge_painter.dart' show EngineEdgePainter;
import 'engine/edge_selection_wrapper.dart' show EdgeSelectionWrapper;
import 'engine/branch_affordance_chip.dart' show BranchAffordanceChip;
import 'engine/offline_banner.dart' show OfflineBanner;
import 'engine/empty_graph.dart' show EmptyGraph, ErrorRetry;
import 'engine/claim_profile_banner.dart' show ClaimProfileBanner;
import 'engine/viewer_linked_provider.dart' show isViewerLinkedProvider;

// ── P0.4: Extracted parts (MUST come after all imports) ────────────────
part 'engine/canvas_mixin.dart';
part 'engine/interaction_mixin.dart';
part 'engine/subtree_mixin.dart';
part 'engine/event_helpers.dart';
part 'engine/node_builders.dart';
part 'engine/branch_affordance.dart';
part 'engine/node_layer.dart';
part 'engine/relationship_view.dart';

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
class _FamilyGraphEngineViewState extends ConsumerState<FamilyGraphEngineView>
 {
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

  /// v107: Pending Reset View request. Set to true when the user taps
  /// the "Center on Root" / "Reset View" button (recenterKey changes).
  /// The build method checks this flag AFTER the layout is available
  /// and calls _camera.resetView(...) with the focus node's position.
  /// This deferred execution is necessary because didUpdateWidget
  /// (where recenterKey is detected) runs BEFORE the build method
  /// has access to the current layout positions.
  bool _pendingResetView = false;

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

  // Phase 6 (hit-test parity): Cache the current couple unions so the
  // tap hit-tester can apply the SAME union-redirect the painter applies
  // to the rendered bezier curve. Without this, tapping a parent→child
  // edge near the union glyph would silently miss because the rendered
  // curve starts at the union midpoint while the hit-test midpoint was
  // computed from the parent's raw node position.
  //
  // See `resolveEffectiveEdgeEndpoints` in couple_union_model.dart —
  // it is the SINGLE source of truth used by BOTH the painter and this
  // hit-tester. These two call sites must never diverge.
  List<CoupleUnion> _currentCoupleUnions = const [];

  // Repaint/recull throttling.
  Rect _lastCullViewport = Rect.zero;
  Lod _lastLod = Lod.full;

  // v96 (Phase 3): Semantic zoom tier with hysteresis memory.
  // The current tier is remembered so computeSemanticTier can apply
  // hysteresis margins (enter/leave thresholds differ). This prevents
  // visual flicker when zoom oscillates near a tier boundary.
  SemanticTier? _currentSemanticTier;

  // v102 (semantic-zoom fix): Cache the current family's member count
  // so _lodFor can pass it to computeSemanticTier. Small families
  // (< 30 members) are pinned to the NEAR tier regardless of zoom —
  // they never degrade to unlabeled dots. Updated once per build.
  int _currentMemberCount = 0;

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

  /// P4.5: Whether the screen-reader outline view is showing.
  bool _showOutlineView = false;

  // ── P2.4: Two-node select-and-compare drag gesture ───────────────────
  /// When non-null, the user is long-pressing + dragging from this node
  /// to another node to compare their relationship. The drag line follows
  /// the finger; on release over a node, the path trace fires.
  String? _compareDragFromId;
  /// The current screen-space position of the drag finger, for drawing
  /// the visual connection line.
  Offset _compareDragPosition = Offset.zero;

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
    // v62/v107: Re-center when recenterKey changes (Center on Root /
    // Reset View button). v107 changes this from the old fitToView
    // (which centered the bounding BOX — putting the focus node
    // off-center for unbalanced graphs) to resetView (which centers
    // the primary focus NODE at the exact viewport center).
    //
    // We set a flag here and execute the reset in the build method
    // (via _maybeRunPendingResetView) because didUpdateWidget runs
    // BEFORE the build method has access to the current layout
    // positions. The flag is checked after the layout is resolved.
    if (oldWidget.recenterKey != widget.recenterKey) {
      _pendingResetView = true;
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
    final Lod lod = _lodFor(_camera.zoomLevel);
    if (lod != _lastLod || _culler.shouldRebuild(_lastCullViewport, vp)) {
      setState(() {});
    }
  }

  Lod _lodFor(double zoom) {
    // v97: Semantic zoom with hysteresis.
    // Camera range restored to 0.2–5.0 — CHIP and DOT are reachable.
    //
    // v102 (semantic-zoom fix): Pass _currentMemberCount so small
    // families (< 30 members) are pinned to NEAR (full detail)
    // regardless of zoom. This prevents a 4-person family from
    // degrading to unlabeled dots when the user pinch-zooms out.
    //
    // P2.3: Pass focusActive so the tier is floored at MEDIUM when
    // focus mode is active — the focus subgraph stays legible even
    // if the user zooms out to FAR. Pairs semantic zoom with focus
    // mode per Vision §5 Layer 1.
    final focusActive = ref.read(graphFocusProvider).focusedPersonId != null;
    _currentSemanticTier = computeSemanticTier(
      zoom,
      currentTier: _currentSemanticTier,
      thresholds: defaultThresholds,
      memberCount: _currentMemberCount,
      focusActive: focusActive,
    );
    switch (_currentSemanticTier!) {
      case SemanticTier.near:
        return Lod.full;
      case SemanticTier.medium:
        return Lod.chip;
      case SemanticTier.far:
        return Lod.dot;
    }
  }

  /// v96 (Phase 3): Returns the current semantic tier (with hysteresis).
  /// Computed as a side effect of [_lodFor] — call _lodFor first.
  SemanticTier get _currentTier => _currentSemanticTier ?? SemanticTier.near;

  /// Maps the current LOD to the edge-layer visual quality tier (PART 10).
  /// Computed ONCE per build and passed to `EngineEdgePainter` — the
  /// painter never derives quality per edge.
  EdgeQuality _edgeQualityFor(Lod lod) {
    switch (lod) {
      case Lod.full:
        return EdgeQuality.full;
      case Lod.chip:
        return EdgeQuality.chip;
      case Lod.dot:
        return EdgeQuality.dot;
    }
  }

  // ── P3.3/P3.4/P3.7 helpers extracted to engine/event_helpers.dart ───

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
  String _lodTierName(Lod lod) {
    switch (lod) {
      case Lod.full:
        return 'full';
      case Lod.chip:
        return 'chip';
      case Lod.dot:
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
    // EdgeSelectionWrapper (a separate ConsumerWidget) so that tapping an
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
    // The check is best-effort: if isViewerLinkedProvider hasn't resolved
    // yet (loading) or errors, we assume "linked" so we never block the
    // graph UI or show a false-positive banner.
    final viewerIsLinked =
        ref.watch(isViewerLinkedProvider(widget.familyId)).valueOrNull ??
            true;
    final viewerIsUnlinked =
        viewerPersonId != null && !viewerIsLinked;

    return layoutAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => ErrorRetry(
        onRetry: () =>
            ref.invalidate(familyGraphProvider(widget.familyId)),
      ),
      data: (GraphLayoutResult layout) {
        if (layout.positions.isEmpty || flat == null) {
          return const EmptyGraph();
        }
        // v4.4: Check if the camera needs recentering after layout change
        // (e.g. add/remove person changed the bounding box). Content bounds
        // are pushed in _buildCanvas; this just triggers the recenter check.
        _onLayoutChanged(layout);
        // v107: Execute a pending Reset View request now that the
        // layout positions are available. This runs the new
        // resetView() method which centers the focus node (selected →
        // anchor → first node) at the exact viewport center.
        if (_pendingResetView) {
          _pendingResetView = false;
          _maybeRunPendingResetView(layout, flat, viewerPersonId);
        }
        // Wrap the graph in a Column so we can show a claim-profile banner
        // above it when the viewer is unlinked. The graph itself expands
        // to fill the remaining space.
        return Column(
          children: [
            // Claim banner — shown when user has no linked Person node
            if (viewerIsUnlinked)
              ClaimProfileBanner(familyId: widget.familyId),
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
                        left: 0, right: 0, top: 0, child: OfflineBanner()),
                  // v99 (Phase 1): Focus Back control
                  if (ref.watch(graphFocusProvider.select((s) => s.history)).isNotEmpty)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 8,
                      child: FloatingActionButton.small(
                        heroTag: 'graph_focus_back',
                        backgroundColor: KinrelColors.darkCard,
                        foregroundColor: KinrelColors.textWhite,
                        onPressed: _onFocusBack,
                        tooltip: 'Back to previous person',
                        child: const Icon(Icons.arrow_back),
                      ),
                    ),
                  // P4.1: Mini-map
                  if (flat.persons.length > 30)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: GraphMiniMap(
                        camera: _camera,
                        positions: layout.positions,
                        viewportSize: _viewportSize,
                        anchorId: _SubtreeMethods._findAnchorId(flat, viewerPersonId),
                        onTap: (graphSpaceTarget) {
                          final bool reduced =
                              MediaQuery.disableAnimationsOf(context);
                          _camera.animateToWithSpring(
                            -graphSpaceTarget.dx * _camera.zoomLevel +
                                _viewportSize.width / 2,
                            -graphSpaceTarget.dy * _camera.zoomLevel +
                                _viewportSize.height / 2,
                            _camera.zoomLevel,
                            reducedMotion: reduced,
                          );
                        },
                      ),
                    ),
                  // Share FAB
                  if (kEnableGraphShareExport)
                    Positioned(
                      right: 16,
                      bottom: flat.persons.length > 30 ? 80 : 16,
                      child: FloatingActionButton(
                        heroTag: 'graph_share_export',
                        backgroundColor: KinrelColors.orange,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        onPressed: _shareGraph,
                        tooltip: 'Share graph',
                        child: const Icon(Icons.ios_share),
                      ),
                    ),
                  // P4.5: Outline view overlay
                  if (_showOutlineView)
                    Positioned.fill(
                      child: GraphOutlineView(
                        persons: flat.persons,
                        relationshipLabels: const {},
                        onNodeFocus: (personId, personName) {
                          setState(() => _showOutlineView = false);
                          _onFocusPerson(personId, personName);
                        },
                        onClose: () =>
                            setState(() => _showOutlineView = false),
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

  /// v4.4: Called after the layout changes (add/remove person, expand/
  /// collapse subtree) to check if the camera needs recentering.
  void _onLayoutChanged(GraphLayoutResult layout) {
    // Content bounds are already pushed in _buildCanvas. Just check if
    // the camera needs to recenter to keep nodes visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _camera.recenterIfNeeded();
    });
  }

  /// v107: Executes a pending Reset View request using the current
  /// layout positions. Centers the primary focus node (selected →
  /// anchor → viewer → first node) at the EXACT viewport center with
  /// the whole graph fitting on screen.
  ///
  /// Called from the build method when [_pendingResetView] is true
  /// and the layout is available. The viewport size must be resolved
  /// (it's set by the LayoutBuilder in _buildCanvas); if it's still
  /// zero (first frame), the reset is deferred to the next build by
  /// re-setting the flag.
  void _maybeRunPendingResetView(
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    // Viewport not resolved yet — defer to next build.
    if (_viewportSize.width <= 0 || _viewportSize.height <= 0) {
      _pendingResetView = true;
      return;
    }
    if (layout.positions.isEmpty) return;

    // v107.1: Resolve the primary focus node ID. The user requirement
    // is that the green "You" (anchor) node is centered. Priority:
    //   1. The anchor node (isAnchor == true) — this is the green
    //      "You" node the user expects to be centered on reset.
    //   2. The viewer's own person node (if different from anchor).
    //   3. The currently selected node (as a courtesy — but the user
    //      explicitly wants the BASE/YOU node centered, not the
    //      selected node, so this is a low-priority fallback).
    //   4. The first node in the layout (last resort).
    //
    // The previous version prioritized the SELECTED node, which meant
    // tapping any node and hitting Reset centered THAT node instead of
    // the You node. The user said "center the base person (the green
    // 'You' node)", so anchor is now top priority.
    String? focusId = _SubtreeMethods._findAnchorId(flat, viewerPersonId);
    if (focusId == null || !layout.positions.containsKey(focusId)) {
      // No anchor — fall back to the selected node.
      final selectedNodeId = ref.read(selectedNodeProvider);
      if (selectedNodeId != null &&
          layout.positions.containsKey(selectedNodeId)) {
        focusId = selectedNodeId;
      } else {
        // Last resort: first node.
        focusId = layout.positions.keys.first;
      }
    }
    if (focusId == null) return;

    final focusPosition = layout.positions[focusId];
    if (focusPosition == null) return;

    final bool reduced = MediaQuery.disableAnimationsOf(context);
    _camera.resetView(
      focusNodePosition: focusPosition,
      // Pass the visual-circle Y offset so the camera centers the
      // CIRCLE (what the user sees), not the bounding box. The
      // offset is negative because the circle sits at the top of
      // the node's Column, above the box center.
      circleCenterYOffset: _kCircleCenterYOffset,
      viewportSize: _viewportSize,
      reducedMotion: reduced,
    );
    _culler.invalidate();
  }

  // ── Expand / collapse ────────────────────────────────────────────────────

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
