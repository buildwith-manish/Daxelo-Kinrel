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
import 'graph_legend.dart' show GraphLegend;
import 'graph_quick_actions.dart' show GraphQuickActions;
import 'graph_relationship_labels.dart' show GraphPersonData;
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

  // ── P3.3: Birthday glow helpers ───────────────────────────────────────────

  /// Returns true if [p] has a birthday within 7 days. Reads
  /// `p['dateOfBirth']` (added to the graph RPC by the P3.3 migration).
  bool isNearBirthdayForPerson(Map<String, dynamic> p) {
    final dobStr = p['dateOfBirth'] as String?;
    if (dobStr == null || dobStr.isEmpty) return false;
    final dob = DateTime.tryParse(dobStr);
    if (dob == null) return false;
    return isNearBirthday(dob);
  }

  /// Returns days until the next birthday for [p], or null if
  /// `dateOfBirth` is missing or invalid.
  int? daysUntilBirthdayForPerson(Map<String, dynamic> p) {
    final dobStr = p['dateOfBirth'] as String?;
    if (dobStr == null || dobStr.isEmpty) return null;
    final dob = DateTime.tryParse(dobStr);
    if (dob == null) return null;
    return daysUntilBirthday(dob);
  }

  /// P3.4: Returns true if the person is deceased AND the death was
  /// within the last 30 days. The memorial candle is brighter (alpha
  /// 0.8-1.0) for the first 30 days, then dims to 0.6-0.9.
  ///
  /// The graph RPC doesn't currently return dateOfDeath, so this
  /// helper returns false (standard candle) until the RPC is extended.
  /// The painter supports the brighter range via [isRecentlyDeceased]
  /// — flipping this to true once dateOfDeath is in the RPC will
  /// automatically brighten recently-deceased candles.
  bool isRecentlyDeceasedForPerson(Map<String, dynamic> p) {
    final isDeceased = (p['isDeceased'] as bool?) ?? false;
    if (!isDeceased) return false;
    final dodStr = p['dateOfDeath'] as String?;
    if (dodStr == null || dodStr.isEmpty) return false;
    final dod = DateTime.tryParse(dodStr);
    if (dod == null) return false;
    final daysSinceDeath = DateTime.now().difference(dod).inDays;
    return daysSinceDeath >= 0 && daysSinceDeath <= 30;
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

  /// v102 (BUG-2 FIX): Builds positioned chips for each collapsed branch.
  ///
  /// Each chip is positioned near the branch root node's coordinates
  /// and displays the branch label (e.g. "Mother's branch · 38").
  /// Tapping the chip calls `expandBranch(rootPersonId)` to reveal
  /// the hidden members.
  ///
  /// This is the UI affordance that was missing — the collapse state
  /// was computed but never surfaced to the user, so they had no way
  /// to know a branch was collapsed or to expand it.
  List<Widget> _buildCollapsedBranchChips(
    GraphLayoutResult layout,
    BranchCollapseState collapseState,
  ) {
    if (collapseState.collapsedBranches.isEmpty) return const [];

    final chips = <Widget>[];
    for (final branch in collapseState.collapsedBranches) {
      final pos = layout.positions[branch.rootPersonId];
      if (pos == null) continue;

      // Position the chip slightly below and to the right of the root
      // node so it doesn't overlap the node circle.
      final chipLeft = pos.dx + 40;
      final chipTop = pos.dy + _kCircleCenterYOffset + 40;

      chips.add(Positioned(
        left: chipLeft,
        top: chipTop,
        child: GestureDetector(
          onTap: () {
            // P3.2: "branch opening" haptic on branch expand.
            GraphHaptics.branchExpand(context);
            ref.read(branchCollapseProvider.notifier).expandBranch(branch.rootPersonId);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: KinrelColors.darkBackground.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.6),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(1, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.unfold_more,
                  size: 14,
                  color: KinrelColors.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  branch.branchLabel.isNotEmpty
                      ? branch.branchLabel
                      : 'Branch · ${branch.hiddenCount}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
    }
    return chips;
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
    final Lod lod = _lodFor(_camera.zoomLevel);

    // Dot tier: one painter for ALL visible nodes — no per-node widgets.
    if (lod == Lod.dot) {
      final dots = <Dot>[];
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

        dots.add(Dot(
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
            painter: NodeDotPainter(dots, zoom: _camera.zoomLevel),
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
      final Widget node = lod == Lod.full
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
          child: BranchAffordanceChip(
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
    // P3.1: route through the spring-based animator so the pan settles
    // with a cinematic spring instead of a curve tween.
    final center = paddedBounds.center;
    _camera.animateToWithSpring(
      -center.dx * _camera.zoomLevel + _viewportSize.width / 2,
      -center.dy * _camera.zoomLevel + _viewportSize.height / 2,
      _camera.zoomLevel,
      reducedMotion: reduced,
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
    final focusState = ref.watch(graphFocusProvider);
    final focusedId = focusState.focusedPersonId;

    // v99 (Phase 10): Use the centralized computeEmphasisLevel to
    // determine this node's emphasis. This replaces the old ad-hoc
    // if/else priority logic with ONE source of truth.
    final pathFocusState = ref.watch(graphPathFocusProvider).focus;
    final searchState = ref.watch(graphSearchProvider);
    final emphasis = computeEmphasisLevel(
      nodeId: id,
      focusedPersonId: focusedId,
      selectedPersonId: selectedId,
      pathNodeIds: pathFocusState?.orderedPersonIds.toSet(),
      pathEndpointIds: pathFocusState != null
          ? {pathFocusState.viewerPersonId, pathFocusState.targetPersonId}
          : null,
      searchMatchIds: searchState.isActive ? searchState.matchIdSet : null,
      firstDegreeIds: focusState.firstDegreeIds,
      searchActive: searchState.isActive,
      focusActive: focusedId != null,
    );

    // Map emphasis level to NodeState (visual treatment).
    final NodeState nodeState;
    if (emphasis == EmphasisLevel.focused || emphasis == EmphasisLevel.pathEndpoint) {
      nodeState = NodeState.focused;
    } else if (emphasis == EmphasisLevel.selected ||
               emphasis == EmphasisLevel.pathNode) {
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
      // P3.3: birthday glow — compute isNearBirthday from dateOfBirth
      // (now included in the graph RPC) and pass the shared pulse value.
      // Reduced motion → pass -1.0 as a sentinel so the painter uses a
      // static 0.45 alpha instead of reading the pulse.
      isNearBirthday: isNearBirthdayForPerson(p),
      birthdayPulseValue: isNearBirthdayForPerson(p)
          ? (MediaQuery.disableAnimationsOf(context)
              ? -1.0 // sentinel: static glow
              : ref.watch(birthdayPulseProvider).value)
          : 0.0,
      daysUntilBirthday: daysUntilBirthdayForPerson(p),
      // P3.4: memorial candle — deceased nodes get a flickering candle
      // at their center. All deceased nodes share one AnimationController
      // so they flicker in sync. Reduced motion → -1.0 sentinel = static
      // 0.75 alpha.
      memorialCandleFlickerValue: (p['isDeceased'] as bool?) ?? false
          ? (MediaQuery.disableAnimationsOf(context)
              ? -1.0 // sentinel: static candle
              : ref.watch(memorialCandleFlickerProvider).value)
          : 0.0,
      isRecentlyDeceased: isRecentlyDeceasedForPerson(p),
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
        // v99 (Phase 8): Resolve actual family role from provider.
        // Previously hardcoded isOwner: true — anyone could remove
        // any member from the UI. Now only admins/owners see Remove.
        final role = ref.read(currentUserFamilyRoleProvider(widget.familyId));
        final canRemove = role == 'admin' || role == 'owner';
        GraphQuickActions.show(
          context,
          personData,
          familyId: widget.familyId,
          isOwner: canRemove,
          isSelf: isAnchor,
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

  void _onFocusPerson(String personId, String personName) {
    // P3.2: clear "moment" haptic on focus enter.
    GraphHaptics.focusEnter(context);

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

    // P3.2: gentle release haptic on focus exit (back).
    GraphHaptics.focusExit(context);

    // Restore the camera viewport from the popped history entry.
    // P3.1: route through the spring-based animator so the focus-back
    // settles with a cinematic spring instead of a curve tween.
    final viewport = popped.viewport;
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    _camera.animateToWithSpring(
      viewport.panX,
      viewport.panY,
      viewport.zoom,
      reducedMotion: reduced,
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
      anchorId: _SubtreeMethods._findAnchorId(flat, viewerPersonId),
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
