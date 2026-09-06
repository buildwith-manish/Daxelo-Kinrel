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
        FamilyGraphNotifier, // v5.115: for fetchBranchAndMerge
        familyGraphProvider,
        graphLayoutProvider,
        graphRealtimeProvider,
        selectedEdgeProvider,
        selectedNodeProvider,
        unlinkedPersonIdsProvider; // v5.9
import '../data/graph_data_models.dart' show GraphEdgeData;
import '../data/position_memory.dart' show PositionMemory;
import '../engine/edge_dedup.dart' show DedupedEdge, EdgeDeduplicator;
// v5.x (Feature 2): pure helper for the edge dim hierarchy (search /
// focus / selection / default-dim). Used by `_computeDimmedEdgeIds`
// in interaction_mixin.dart so the dim logic is unit-testable.
import '../engine/edge_dim_hierarchy.dart'
    show computeDimmedEdgeIds, EdgeDimHierarchyInput;
// v5.x (chip-placement fix): pure helper for branch-chip placement
// (anchor below the parent node's name label, multi-direction
// collision avoidance against chips + node circles + name labels).
// Shared by _buildCollapsedBranchChips (branch_affordance.dart) and
// _hitTestBranchChip (interaction_mixin.dart) so the rendered chip
// and the tap target can never drift apart.
import '../engine/branch_chip_layout.dart'
    show
        placeBranchChips,
        nodeBoxForPosition,
        BranchChipPlacement,
        BranchChipPlacementRequest;
import '../interaction/camera_controller.dart' show CameraController;
// v5.132 (System B REMOVAL): the ExpandCollapseController import was
// removed along with the engine view's private _expandCollapse store —
// the real collapse pipeline is branchCollapseProvider +
// proximityGraphProvider (see branch_affordance.dart).
import '../interaction/haptic_language.dart' show GraphHaptics;
import '../interaction/keyboard_navigation_controller.dart'
    show handleGraphKeyEvent;
import '../rendering/birthday_pulse_controller.dart' show birthdayPulseProvider;
import '../rendering/birthday_util.dart' show isNearBirthday, daysUntilBirthday;
import '../rendering/memorial_candle_flicker_controller.dart'
    show memorialCandleFlickerProvider;
import '../rendering/ambient_particle_painter.dart' show AmbientParticlePainter;
import '../rendering/ambient_particle_controller.dart'
    show ambientParticleControllerProvider, ambientParticleProvider;
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
        branchCollapseProvider,
        kMaxNodesPerExpansion;
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
import '../../core/constants/feature_flags.dart' show kEnableGraphShareExport, kShowViewerDebugBanner;
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
import '../interaction/indirect_relation_provider.dart'
    show indirectRelationIdsProvider, hasSeenIndirectBadgeProvider;
// v5.114: Ego-centric proximity graph state.
import '../interaction/proximity_graph_state.dart'
    show proximityGraphProvider, ProximityGraphNotifier, buildAdjacency;
import '../../core/services/supabase_service.dart' show supabaseProvider, currentUserProvider;
import '../../core/viewer/viewer_api_client.dart'
    show viewerApiClientProvider;
import '../../features/family/presentation/services/graph_export_service.dart'
    show GraphExportService;
import '../rendering/edge_path_cache.dart' show EdgePathCache;
import '../rendering/edge_quality.dart' show EdgeQuality, EdgeQualityX;
import '../rendering/graph_lighting.dart' show GraphLighting;
import '../rendering/lod_render_metrics.dart'
    show
        LodRenderMetrics,
        computeLodMetrics,
        overviewGraphRadius,
        overviewGraphRingStroke,
        miniGraphRadius,
        microGraphRadius;
import '../rendering/emphasis_priority.dart'
    show EmphasisLevel, computeEmphasisLevel;
import '../rendering/semantic_zoom.dart'
    show
        SemanticTier,
        SemanticZoomThresholds,
        defaultThresholds,
        thresholdsForMemberCount,
        computeSemanticTier,
        semanticTierToLodName,
        shouldOverrideFarTier,
        farTierDotRadius,
        farTierExcludesPremiumEffects,
        shouldRenderText,
        miniTierRadius,
        microTierRadius;
import '../rendering/viewport_culler.dart' show ViewportCuller;
// v5.140 (PERF): RelationLabelOpacityScope hoists label-opacity
// computation out of per-node AnimatedBuilders into a single
// canvas-hosted InheritedWidget — eliminates 50–100 per-frame
// subtree rebuilds during pan/zoom.
import '../rendering/relationship_label_opacity.dart'
    show relationLabelOpacityFor, RelationLabelOpacityScope;
// v5.141 (LOW-END PERF): Tier-aware performance profile. Centralizes
// all low-end / mid / high-end decisions so the graph degrades
// gracefully on 2–4 GB RAM devices while keeping the full premium
// experience on high-end devices.
import '../rendering/graph_performance_profile.dart'
    show GraphPerformanceProfile;
// v5.143 (HIDDEN-NODE AUDIT): FilteredGraph — a precomputed,
// immutable view of the graph containing ONLY visible nodes + edges.
// This is the single object that replaces the 5-6 iterations of
// flat.relationships (1000 edges) per rebuild. Built ONCE per
// graph-data change, memoized on identical(flat).
import '../rendering/filtered_graph.dart'
    show
        FilteredGraph,
        FilteredRelationship,
        buildFilteredGraph,
        setsEqualString;
// v5.143 (HIDDEN-NODE AUDIT): Lightweight timing logger for the
// graph pipeline. Logs filter/layout/edges/paint durations when they
// exceed thresholds or the total exceeds the 16.67ms frame budget.
import '../rendering/graph_perf_logger.dart' show GraphPerfLogger;
import 'graph_node.dart' show GraphNode, NodeState;
import 'on_this_day_badge.dart' show OnThisDayBadge, OnThisDayEvent, OnThisDayEventType, showOnThisDayEventSheet;
import 'graph_minimap.dart' show GraphMiniMap;
import 'graph_outline_view.dart' show GraphOutlineView;
// v5.x (legend wiring fix): the GraphLegend import was unused — the
// legend widget is now rendered by the parent family_graph_screen
// (toggled by the bottom dock's Help/Legend button), not by this
// engine view. Removed to keep the import list accurate.
import 'graph_quick_actions.dart' show GraphQuickActions, BranchCollapseInfo;
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
// v5.111: New MINI and MICRO painters for the 5-tier semantic zoom.
import 'engine/node_mini_painter.dart' show NodeMiniPainter;
import 'engine/node_micro_painter.dart' show NodeMicroPainter;
import 'engine/engine_edge_painter.dart' show EngineEdgePainter;
import 'engine/edge_selection_wrapper.dart' show EdgeSelectionWrapper;
// v5.132 (System B REMOVAL): BranchAffordanceChip (the legacy per-node
// "+N" chip) was deleted with _withBranchAffordance — the ONLY branch
// chips now render via _buildCollapsedBranchChips in
// branch_affordance.dart.
import 'engine/offline_banner.dart' show OfflineBanner;
import 'engine/empty_graph.dart' show EmptyGraph, ErrorRetry, AccessIssueGraph;
import 'engine/claim_profile_banner.dart' show ClaimProfileBanner;
import 'engine/viewer_linked_provider.dart' show isViewerLinkedProvider;

// v5.22: Personal layout overrides + Rearrange-mode toggle.
// Both consumed by the canvas mixin and the interaction mixin.
// v5.27 Task 1: also imports resetAnimationTriggerProvider.
// v5.34: also imports saveAllOverridesTriggerProvider + resetUnsavedOverridesTriggerProvider.
// v5.38: also imports hasUnsavedChangesProvider + saveCompletedTriggerProvider.
import '../rearrange/layout_overrides_service.dart'
    show
        LayoutOverridesService,
        PersonalLayoutOverrides,
        personalLayoutOverridesProvider,
        branchExpansionStateProvider,
        rearrangeModeProvider,
        resetAnimationTriggerProvider,
        saveAllOverridesTriggerProvider,
        resetUnsavedOverridesTriggerProvider,
        hasUnsavedChangesProvider,
        saveCompletedTriggerProvider;
import '../rearrange/save_lock_pill.dart' show SaveLockPill;

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
    this.bottomChromeHeight = 0,
    this.topChromeHeight = 0,
  });

  /// The family whose graph to render.
  final String familyId;

  /// v62: Generation to highlight (null = show all). When set, nodes
  /// NOT in this generation are dimmed to 15% opacity. Passed from
  /// the parent screen's generation filter chip bar.
  final int? highlightedGeneration;

  /// v4.10: Height of the app's own bottom UI chrome (stats panel + toolbar)
  /// that overlays the canvas. Passed from family_graph_screen.dart where the
  /// real overlay geometry is computed. Used by fitToView to center content
  /// above the bottom overlay instead of behind it.
  final double bottomChromeHeight;

  /// v4.10: Height of the app's top UI chrome (AppBar). 0 if the Scaffold
  /// already excludes the AppBar from the body (which it does in this app).
  final double topChromeHeight;

  /// v62: When this value changes, the camera re-centers on the
  /// anchor node. Passed from the parent screen's "Center on Root"
  /// button.
  final int? recenterKey;

  @override
  ConsumerState<FamilyGraphEngineView> createState() =>
      _FamilyGraphEngineViewState();
}
class _FamilyGraphEngineViewState extends ConsumerState<FamilyGraphEngineView>
    with TickerProviderStateMixin {
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
  // v5.132 (System B REMOVAL): the private ExpandCollapseController
  // (_expandCollapse) was deleted. Its visibleNodeIds set was only ever
  // written by the dead _toggleSubtree path and never by the real
  // density-collapse pipeline (branchCollapseProvider /
  // proximityGraphProvider / computeDensityCollapse) — the store was
  // permanently empty, i.e. "show everything", and its per-node
  // "+N" chips rendered but did nothing on tap.
  final EdgePathCache _edgePathCache = EdgePathCache();

  /// Wraps the on-screen graph so it can be captured for share/export.
  final GlobalKey _graphBoundaryKey = GlobalKey();

  /// v62: Periodic telemetry timer — logs edge cache hit rate + cull
  /// stats every 30 seconds while the graph is mounted.
  Timer? _telemetryTimer;
  int _lastCullVisibleCount = 0;

  /// v5.72 (ZOOM LOOP FIX): Auto-timeout timer for the Isolate Connections
  /// feature. When the user isolates a person's connections, the focus
  /// state + camera animation auto-clears after 18 seconds so the graph
  /// returns to normal. This prevents the "keeps zooming in and out
  /// forever" bug where the focus state persists indefinitely.
  Timer? _focusTimeoutTimer;

  /// v5.123 (DISPOSE FIX): Notifier references captured in initState so
  /// dispose() can clear GLOBAL interaction state WITHOUT calling
  /// `ref.read` — Riverpod throws "Cannot use ref after the widget was
  /// disposed" when the element is unmounted during tree finalization
  /// (e.g. test teardown). The notifier instances are owned by the
  /// ProviderScope and outlive this widget, so calling them directly
  /// is always safe.
  late final GraphFocusNotifier _focusNotifierForCleanup;
  late final StateController<String?> _selectedNodeNotifierForCleanup;

  /// v5.123 (Step 5): The branch-collapse notifier — captured in
  /// initState to (a) wire the expansion-persistence callback and
  /// (b) clear it on dispose without touching `ref`.
  late final BranchCollapseNotifier _branchCollapseNotifierForCleanup;

  /// v5.123 (Step 5): The family whose persisted branch-expansion
  /// state has been applied (seeded + revealed) — guards the
  /// once-per-family-load seeding.
  String? _persistedExpansionSeededFamilyId;

  /// v62: Position of the last double-tap, for zoom-toward-focal-point.
  Offset _doubleTapPosition = Offset.zero;

  Size _viewportSize = Size.zero;
  bool _framed = false; // one-time initial framing per family

  // v5.x (progressive-load fix): Track whether the user has manually
  // panned/zoomed the camera. When false, the camera auto-re-centers
  // on the anchor whenever its layout position changes (which happens
  // when progressive data loading completes and the layout is
  // recomputed with the full dataset). When true, the camera respects
  // the user's manual position and does NOT fight them.
  //
  // Set true by _onScaleStart (the user's finger touched the canvas
  // for a pan/zoom gesture). Reset to false on family switch (so the
  // new family gets the auto-centering benefit).
  bool _userHasInteractedWithCamera = false;

  // v5.x (progressive-load fix): The anchor's position as of the last
  // camera centering. Compared against the anchor's current layout
  // position on every build — if it moved (because more data loaded
  // and the layout was recomputed), the camera re-centers (unless the
  // user has manually interacted).
  Offset? _lastFramedAnchorPos;

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

  // v5.143 (HIDDEN-NODE AUDIT): Cache the FilteredGraph so the 5-6
  // iterations of flat.relationships (1000 edges) happen ONCE per
  // graph-data change, NOT once per rebuild. The cache key is the
  // identity of `flat` + the identity of `effectivePositions` (which
  // changes on layout recompute even when flat is unchanged) + the
  // hiddenIds set (which changes on collapse/expand).
  //
  // This is the single biggest perf win: previously every pan-triggered
  // rebuild iterated flat.relationships 5-6 times = 5000-6000 ops,
  // plus 50,000 for the lifeguard safeguard, plus 50,000 for
  // _buildFullNode tap-highlight. Now those iterations happen only
  // when the graph data actually changes.
  FilteredGraph _filteredGraph = FilteredGraph.empty;
  FlatGraphResult? _filteredGraphFlat;
  Map<String, Offset>? _filteredGraphPositions;
  Set<String>? _filteredGraphHiddenIds;
  int _filteredGraphVersion = 0;

  // v5.143 (HIDDEN-NODE AUDIT): Cache the FULL adjacency map (all
  // edges, not just visible) for consumers that run BEFORE density
  // collapse (anchor-neighbor protection, computeDensityCollapse's
  // hidden-edge computation). This is memoized on identical(flat) so
  // it's built ONCE per graph-data change, not once per rebuild.
  //
  // Key: personId → list of (otherId, edgeId, relationshipKey, rawRow)
  // for EVERY edge touching that person (visible or hidden).
  Map<String, List<({String otherId, String edgeId, String relationshipKey, Map<String, dynamic> rawRow})>>?
      _cachedFullAdjacency;
  FlatGraphResult? _cachedFullAdjacencyFlat;

  /// v5.143: Returns the full adjacency map (all edges), cached on
  /// identical(flat). Used by anchor-neighbor protection + density
  /// collapse computation which run BEFORE the FilteredGraph is built.
  Map<String, List<({String otherId, String edgeId, String relationshipKey, Map<String, dynamic> rawRow})>>
      _fullAdjacency(FlatGraphResult flat) {
    if (_cachedFullAdjacency != null && identical(_cachedFullAdjacencyFlat, flat)) {
      return _cachedFullAdjacency!;
    }
    final adj =
        <String, List<({String otherId, String edgeId, String relationshipKey, Map<String, dynamic> rawRow})>>{};
    for (final r in flat.relationships) {
      final s = (r['fromPersonId'] ?? '').toString();
      final t = (r['toPersonId'] ?? '').toString();
      final edgeId = (r['id'] ?? '').toString();
      final relationshipKey = (r['relationshipKey'] ?? 'unknown').toString();
      if (s.isEmpty || t.isEmpty) continue;
      (adj[s] ??= []).add((
        otherId: t,
        edgeId: edgeId,
        relationshipKey: relationshipKey,
        rawRow: r,
      ));
      (adj[t] ??= []).add((
        otherId: s,
        edgeId: edgeId,
        relationshipKey: relationshipKey,
        rawRow: r,
      ));
    }
    _cachedFullAdjacency = adj;
    _cachedFullAdjacencyFlat = flat;
    return adj;
  }

  /// v5.143: Returns the first-degree neighbor IDs of [personId] from
  /// the full (unfiltered) adjacency map. O(1) lookup + O(degree) list
  /// build. Used by anchor-neighbor protection which runs BEFORE
  /// density collapse.
  Set<String> _fullFirstDegreeNeighbors(String personId, FlatGraphResult flat) {
    final adj = _fullAdjacency(flat);
    final neighbors = adj[personId];
    if (neighbors == null || neighbors.isEmpty) return <String>{};
    return <String>{for (final n in neighbors) n.otherId};
  }

  /// v5.143 (HIDDEN-NODE AUDIT): The performance logger for the
  /// current build. Reset at the start of _buildCanvas, finished at
  /// the end. Logs only when a stage exceeds threshold or the total
  /// exceeds the 16.67ms frame budget.
  final GraphPerfLogger _perfLogger = GraphPerfLogger();

  // v92 (PART 17): Cache the current deduped edges + positions (with
  // the visual-circle Y offset applied) so the canvas tap handler can
  // do geometric midpoint hit-testing without recomputing them.
  // Updated once per build in the build method.
  List<DedupedEdge> _currentEdges = const [];
  Map<String, Offset> _currentPositionsWithOffset = const {};
  Map<String, KinshipEdgeCategory> _currentEdgeCategories = const {};
  Map<String, Map<String, dynamic>> _currentEdgeCustomColors = const {};

  // v5.137: Cache the current collapsed branches so the canvas tap
  // handler can do geometric hit-testing on branch chips. On Flutter
  // Web, the parent GestureDetector's ScaleGestureRecognizer wins the
  // gesture arena, so the chip's own onTap/onLongPress never fire.
  // This cache lets the parent-level hit-tester intercept chip taps
  // and route them to the same handlers the chip would have called.
  List<CollapsedBranch> _currentCollapsedBranches = const [];

  // v5.153 (FIX 2.A): Cache the current density-hidden IDs so the
  // hit-tester can skip orphaned chips (branches whose root is itself
  // hidden by another collapse). Updated in canvas_mixin when the
  // chip list is rebuilt.
  Set<String> _currentDensityHiddenIds = const {};

  // v5.166 (BRANCH BUBBLE CONNECTOR): Cache the current branch chip
  // placements (branchId → placement rect) so the lifeguard can
  // synthesize connector edges from isolated visible nodes to the
  // nearest branch bubble. Without this, a visible node whose only
  // relatives are all hidden inside a collapsed branch renders with
  // NO connecting edge — the "isolated visible node" bug (e.g. Geeta
  // Iyer). The lifeguard now falls back to connecting such nodes to
  // the branch bubble's center position.
  Map<String, Rect> _currentBranchBubblePositions = const {};

  // v5.137: Records which branch chip was hit during onTapDown, so the
  // onTap callback (which fires only for quick taps, NOT long-presses)
  // can expand the correct branch. This prevents the chip from expanding
  // on pointer-down (which would prevent long-press from ever firing).
  CollapsedBranch? _pendingChipTapBranch;

  // v5.137.2: Timer that fires the chip expand after 500ms if no long-press
  // was recognized. On Flutter Web, the ScaleGestureRecognizer wins the
  // gesture arena, which means Flutter's built-in tap/long-press distinction
  // is unreliable — onTap can fire even after a long hold. This timer-based
  // approach gives us precise control: if the timer fires (no long-press
  // happened within 500ms), expand the branch. If onLongPressStart fires
  // first, cancel the timer and open the action sheet instead.
  Timer? _chipExpandTimer;

  // v5.x (perf fix): Debounce timer for camera-driven widget rebuilds.
  // See _onCameraChanged — prevents setState on every pan/zoom frame.
  Timer? _cameraRebuildTimer;

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

  // v5.125 (Step 6): Cache the anchor geometry for the SAME reason as
  // the fields above — the tap hit-tester must compute edge midpoints
  // with the SAME bow-around-the-anchor offset + sector fan-out the
  // painter renders, or the marker and the tap target drift apart.
  // Updated once per build in the canvas build (canvas_mixin.dart).
  String? _currentAnchorId;
  Offset? _currentAnchorCenter;

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

  // v5.x (perf fix — pinch-zoom GPU-transform): The two fields below
  // are the engine-side counterpart of the painter's
  // [EngineEdgePainter.painterActiveGesture] +
  // [EngineEdgePainter.zoomCommitRevision]. Together they make the
  // pinch-zoom gesture use the SAME GPU-transform fast path that pan
  // already uses — instead of re-rasterizing every edge on every
  // frame of the pinch (which reruns the O(edges) anchor sector
  // fan-out computation and is the architectural bottleneck).
  //
  // Lifecycle:
  //   _onScaleStart     : set _painterActiveGesture = true,
  //                       _lastCommittedZoom = _camera.zoomLevel
  //                       (the zoom the painter last rendered at).
  //   _onScaleUpdate    : if the pinch zoom has moved more than
  //                       [_kZoomCommitThreshold] (15%) past the last
  //                       committed zoom, bump _zoomCommitRevision
  //                       and update _lastCommittedZoom — this gives
  //                       large pinch excursions a periodic stroke-width
  //                       refresh so the visual doesn't drift too far
  //                       before snapping back.
  //   _onScaleEnd       : set _painterActiveGesture = false and bump
  //                       _zoomCommitRevision — this commits the one
  //                       final real repaint at the resting zoom, so
  //                       the constant-width strokes are correct on
  //                       the resting frame. setState is called to
  //                       force the rebuild that delivers the new
  //                       painter with painterActiveGesture=false.
  //
  // During the gesture, the AnimatedBuilder in canvas_mixin scales
  // the cached edge raster on the GPU via a Matrix4 transform —
  // exactly like it does for panning. Edge strokes will visually
  // thicken/thin slightly during the gesture (acceptable — matches
  // WhatsApp/Instagram pinch behavior), then snap to the correct
  // constant-width strokes on gesture end.
  bool _painterActiveGesture = false;
  int _zoomCommitRevision = 0;

  /// v5.141 (LOW-END PERF): The performance profile for the current
  /// device. Computed once in initState from [DeviceTierCache]. All
  /// tier-aware code paths (LOD selection, edge quality, ambient
  /// particles, connect-on-open animation, culler thresholds, image
  /// cache size) read from this profile so low-end devices get
  /// graceful degradation while high-end devices keep the full
  /// premium experience.
  late final GraphPerformanceProfile _perfProfile;
  /// The zoom level the painter last rasterized at. Used by
  /// [_onScaleUpdate] to detect when a 15% interim repaint is needed
  /// during a long pinch.
  double _lastCommittedZoom = 1.0;
  /// The interim-commit threshold — if the pinch zoom moves more
  /// than 15% past the last committed zoom, force one repaint at
  /// the new zoom baseline (and update _lastCommittedZoom).
  static const double _kZoomCommitThreshold = 0.15;

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

  // ── v5.22 Rearrange mode drag state ───────────────────────────────────
  //
  // Personal (per-viewer), persisted node position + edge midpoint bow
  // overrides. These state fields hold LIVE drag deltas while the
  // finger is down (NOT yet persisted). After release, a SaveLockPill
  // is shown; Save persists via LayoutOverridesService, Cancel reverts
  // to the pre-drag state.
  //
  // Outside Rearrange mode, all these fields stay null/empty — no
  // existing gesture is overloaded.

  /// Active drag kind when in Rearrange mode: 'node' or 'edge' (or null).
  /// Disambiguates what the same onLongPressMoveUpdate / onLongPressEnd
  /// should do — see _handleRearrangeDragUpdate / _handleRearrangeDragEnd.
  String? _rearrangeDragKind;

  /// When _rearrangeDragKind == 'node', the personId being dragged.
  /// When _rearrangeDragKind == 'edge', the relationshipId whose
  /// midpoint dot is being dragged.
  String? _rearrangeDragId;

  /// Snapshot of the node's position BEFORE the drag started. Cancel
  /// reverts to this. If the node already had a saved override, this
  /// is that override's last value. If not, this is the auto-layout
  /// position (Cancel restores auto-layout).
  Offset? _rearrangePreDragPosition;

  /// Snapshot of the edge's RELATIVE midpoint delta BEFORE the drag
  /// started (could be Offset.zero when no override existed — Cancel
  /// restores zero = true computed midpoint).
  Offset _rearrangePreDragEdgeDelta = Offset.zero;

  /// LIVE per-node position overrides (graph space). Applied on top of
  /// the saved overrides on top of auto-layout while dragging. Cleared
  /// on Save (persisted into the saved overrides) or Cancel (reverted).
  Map<String, Offset> _rearrangeLiveNodeOverrides = const {};

  /// LIVE per-edge midpoint delta overrides (graph space, RELATIVE to
  /// the true bezier t=0.5 midpoint). Applied on top of saved edge
  /// waypoints. Cleared on Save / Cancel.
  Map<String, Offset> _rearrangeLiveEdgeWaypoints = const {};

  /// Whether the SaveLockPill is currently visible. When true, the
  /// canvas renders a floating pill near the dragged element with
  /// Save/Cancel buttons. Auto-dismisses after 6s (defaulting to
  /// Cancel/revert) so unconfirmed changes never silently persist.
  bool _rearrangePillVisible = false;

  /// Screen-space position where the SaveLockPill should appear
  /// (near the dragged element). Updated on drag end.
  Offset _rearrangePillScreenPosition = Offset.zero;

  /// Which kind the pill is confirming — drives the pill's label
  /// ("Save this position?" for nodes, "Save this curve?" for edges)
  /// and which callback runs on Save vs Cancel.
  String? _rearrangePillKind;

  /// The element ID the pill is confirming (personId or relationshipId).
  String? _rearrangePillId;

  /// v5.22: Per-drag-update revision counter. Bumped on every
  /// onLongPressMoveUpdate during a Rearrange drag and on Save/Cancel.
  /// Included in the EdgeSelectionWrapper's `layoutRevision` so the
  /// painter repaints with the new live override position each frame.
  /// Without this, the painter's shouldRepaint would skip repainting
  /// because none of the existing revision counters (edge count,
  /// position count, canvas dimensions) change during a drag —
  /// only the VALUES of overridden positions change.
  int _rearrangeDragRevision = 0;

  // ── v5.27 Task 1 — Reset animation state ──────────────────────────
  //
  // When a reset (resetAllOverrides / removeNodeOverride /
  // removeEdgeWaypoint) is triggered, LayoutOverridesService bumps
  // resetAnimationTriggerProvider BEFORE the DB write + provider
  // invalidation. We watch that counter via ref.listen in initState;
  // on increment we capture the CURRENT effectivePositions (which
  // still includes saved overrides + live drag overrides — the "from"
  // state of the lerp) into _preResetPositions / _preResetEdgeWaypoints
  // and start a 350ms easeOutCubic animation.
  //
  // On each tick the canvas_mixin computes:
  //   effectivePositions =
  //     lerp(_preResetPositions, layout.positions, _resetProgress)
  //   effectiveEdgeWaypoints =
  //     lerp(_preResetEdgeWaypoints, {}, _resetProgress)
  // (Edges redraw automatically each frame since they derive paths
  // from node positions.)
  //
  // On complete: clear _preResetPositions + _preResetEdgeWaypoints so
  // effectivePositions falls back to the auto-layout (which is the
  // post-reset state, with savedOverrides empty).
  //
  // Reduced-motion: if MediaQuery.disableAnimationsOf(context) is
  // true at trigger time, skip the animation — clear the pre-reset
  // snapshots immediately so the canvas snaps to pure auto-layout.
  //
  // Single shared AnimationController (NOT one per node — that's the
  // expensive mistake to avoid on low-end devices). The lerp is cheap
  // (simple Offset math per node, no re-running the layout engine per
  // frame). Duration is 350ms flat regardless of how many nodes are
  // resetting at once — so resetting a 50-person tree feels just as
  // snappy as resetting 2 nodes.
  AnimationController? _resetController;
  Map<String, Offset>? _preResetPositions;
  Map<String, Offset>? _preResetEdgeWaypoints;
  bool _animatingReset = false;
  int _lastResetTriggerValue = 0;

  // v5.34: Trigger counters for the new Save-All + Reset-Unsaved
  // workflow. The engine view watches saveAllOverridesTriggerProvider
  // and resetUnsavedOverridesTriggerProvider; on increment, it does
  // the actual work (iterate over live overrides, save/clear).
  int _lastSaveAllTriggerValue = 0;
  int _lastResetUnsavedTriggerValue = 0;

  // ── v5.27 Task 2 — Connect-on-open animation state ───────────────
  //
  // On first graph load for a session, we animate edges appearing
  // progressively outward from the viewer's anchor node. Reuses the
  // EXISTING GraphPathTraceController (one AnimationController +
  // orderedEdgeIds + per-edge duration scaling 320/250/180ms with
  // 2200ms cap) — we just instantiate a SECOND controller for
  // connect-on-open and add a painter flag to interpret
  // currentEdgeId+traceProgress as fade-in alpha (vs the existing
  // sweep semantics).
  //
  // The _hasPlayedConnectOnOpen flag is a one-time gate — only runs
  // on the FIRST render after opening the graph screen, never on
  // subsequent rebuilds/pan/zoom.
  GraphPathTraceController? _connectOnOpenController;
  bool _hasPlayedConnectOnOpen = false;
  // The ordered edge IDs (BFS from viewer anchor) we last kicked off
  // a connect-on-open trace for. Used to detect when flat.relationships
  // has been populated enough to start the trace.
  List<String> _connectOnOpenOrderedEdgeIds = const [];

  // ── v5.30 Issue 2 — Load animation for saved node overrides ──────
  //
  // When the graph first renders with personalLayoutOverridesProvider
  // returning non-empty node positions, any node that has a saved
  // override animates from its auto-layout origin to its saved
  // position over ~500ms using easeOutCubic. Same pattern as
  // _maybeStartConnectOnOpen (one-time flag, deferred-first-render).
  //
  // This prevents the "snap or flash" where the node briefly appears
  // at the auto-layout position before jumping to the saved position.
  // Instead, the node smoothly animates from auto-layout → saved.
  AnimationController? _loadController;
  bool _animatingLoad = false;
  bool _hasPlayedLoadAnimation = false;

  // v5.147 (TIER 1C): Avatar pre-warming gate. When the graph data
  // changes (new family, new member added), we precacheImage all
  // avatar URLs in parallel so the GraphNode widgets don't show
  // empty circles for 200-500ms while the network fetch happens.
  // Reset to false when flat changes (detected by tracking the last
  // flat identity we prewarmed for).
  bool _hasPrewarmedAvatars = false;
  FlatGraphResult? _prewarmedAvatarsFlat;

  // v5.143: Branch expand/collapse animation controller.
  // 280ms easeOut — animates newly-revealed nodes from the chip's
  // position outward to their computed final positions on expand,
  // and reverses (nodes converge to chip position) on collapse.
  // This masks layout-computation latency behind smooth motion.
  AnimationController? _branchExpandController;
  bool _animatingBranchExpand = false;
  Set<String> _branchAnimatingNodeIds = {};
  Offset _branchAnimationOrigin = Offset.zero;
  double _branchAnimationProgress = 1.0;
  // v5.143: Optimistic chip loading state — set immediately on tap
  // before the RPC returns, so the user gets sub-100ms feedback.
  String? _optimisticLoadingChipRootId;

  // v5.159 (ENTRANCE ANIMATION): person IDs revealed by the most recent
  // branch-bubble tap that are WAITING for their first layout positions.
  // The canvas build (canvas_mixin.dart) promotes them into
  // [_branchAnimatingNodeIds] the moment the layout assigns them
  // positions and starts the v5.143 controller — so newly revealed
  // nodes FLY OUT from the bubble instead of popping in, while their
  // edges follow (edge paths derive from effectivePositions every
  // frame, keeping node + connecting line GLUED together).
  Set<String> _pendingEntranceNodeIds = {};

  @override
  void initState() {
    super.initState();
    // v5.141 (LOW-END PERF): Build the performance profile ONCE from
    // the device tier. All tier-aware code paths read from this.
    _perfProfile = GraphPerformanceProfile.forCurrentDevice();
    _positionMemory = PositionMemory();
    _camera = CameraController(positionMemory: _positionMemory)
      ..setFamilyId(widget.familyId)
      ..addListener(_onCameraChanged);
    _culler = ViewportCuller(
      viewport: Rect.zero,
      // v5.141: Use tier-aware buffer + rebuild threshold. Low-end
      // devices get a smaller buffer (fewer nodes built) + larger
      // rebuild threshold (fewer rebuilds during pan). High-end
      // devices keep the original 300px / 80px values.
      bufferPixels: _perfProfile.cullerBufferPixels,
      rebuildThreshold: _perfProfile.cullerRebuildThresholdPixels,
    );
    // v5.132: no ExpandCollapseController here anymore (System B).

    // v5.123 (DISPOSE FIX): Capture the global interaction-state notifiers
    // now (ref is valid in initState) so dispose() can clear them without
    // touching ref — see the field docs on _focusNotifierForCleanup.
    _focusNotifierForCleanup = ref.read(graphFocusProvider.notifier);
    _selectedNodeNotifierForCleanup =
        ref.read(selectedNodeProvider.notifier);

    // v5.123 (Step 5): Wire branch-expansion persistence. Whenever a
    // branch is expanded (chip tap) or re-collapsed, the choice is
    // stored on the viewer's GraphLayoutState row keyed by
    // (userId, familyId, branchRootId) and re-applied on the next
    // graph load (see _applyPersistedBranchExpansion below).
    _branchCollapseNotifierForCleanup =
        ref.read(branchCollapseProvider.notifier);
    _branchCollapseNotifierForCleanup.onExpansionChanged =
        (String rootPersonId, bool expanded) {
      if (!mounted) return;
      LayoutOverridesService.saveBranchExpansionState(
        ref,
        widget.familyId,
        rootPersonId,
        expanded,
      );
    };

    // v5.27 Task 1: reset animation controller. 350ms easeOutCubic,
    // flat duration regardless of how many nodes are resetting.
    // Reduced-motion is checked at trigger time in _onResetTrigger.
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _resetController!.addStatusListener(_onResetAnimationStatus);
    _resetController!.addListener(_onResetAnimationTick);

    // v5.30 Issue 2: Load animation controller for saved node overrides.
    // 500ms easeOutCubic — animates nodes from their auto-layout origin
    // to their saved override position on first render.
    _loadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _loadController!.addStatusListener(_onLoadAnimationStatus);
    _loadController!.addListener(_onLoadAnimationTick);

    // v5.143: Branch expand/collapse animation controller.
    // 280ms easeOut for smooth node reveal/converge.
    _branchExpandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _branchExpandController!.addStatusListener(_onBranchExpandStatus);
    _branchExpandController!.addListener(_onBranchExpandTick);
    // v5.27 Task 1: watch the reset trigger counter — bumped by
    // LayoutOverridesService before each reset DB write. We use
    // ref.listenManual (not watch) so we run a callback on change
    // WITHOUT triggering a rebuild (the rebuild happens naturally
    // when the provider invalidation fires next frame).
    //
    // We can't call ref.listenManual directly in initState because the
    // widget isn't fully built yet (ref isn't ready). Use postFrame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.listenManual(resetAnimationTriggerProvider, (previous, next) {
        if (next != null && next > _lastResetTriggerValue) {
          _lastResetTriggerValue = next;
          _onResetTrigger();
        }
      });
      // v5.34: Listen for the Save-All trigger (persistent Save button).
      ref.listenManual(saveAllOverridesTriggerProvider, (previous, next) {
        if (next != null && next > _lastSaveAllTriggerValue) {
          _lastSaveAllTriggerValue = next;
          _onSaveAllTrigger();
        }
      });
      // v5.34: Listen for the Reset-Unsaved trigger (Reset button).
      ref.listenManual(resetUnsavedOverridesTriggerProvider, (previous, next) {
        if (next != null && next > _lastResetUnsavedTriggerValue) {
          _lastResetUnsavedTriggerValue = next;
          _onResetUnsavedTrigger();
        }
      });
      // v5.39: Listen for Rearrange-mode ON/OFF transitions so the
      // Save (✓) button state always reflects whether there are
      // unsaved node/edge position changes — never stale, never
      // orphaned from a prior session.
      //
      //   • Turn ON  → defensively reset hasUnsavedChangesProvider to
      //                false and clear the live override maps. The
      //                button starts disabled; it only enables when
      //                the user actually drags a node or curve dot.
      //   • Turn OFF → discard any unsaved live overrides (the user
      //                chose to exit without saving) and reset
      //                hasUnsavedChangesProvider to false. Re-entering
      //                Rearrange mode now starts from a clean slate.
      //
      // This listener is the single source of truth for "session
      // scope" cleanup; per-drag cleanup remains in
      // _handleRearrangeDragEnd and per-save cleanup in
      // _onSaveAllTrigger.
      ref.listenManual(rearrangeModeProvider, (previous, next) {
        final turnedOn = next == true && previous != true;
        final turnedOff = next != true && previous == true;
        if (!turnedOn && !turnedOff) return;
        if (!mounted) return;
        // Clear any in-flight drag state — defensive (the drag-end
        // handlers normally do this, but an exit mid-drag could leave
        // stale state).
        _rearrangeDragKind = null;
        _rearrangeDragId = null;
        _rearrangePreDragPosition = null;
        _rearrangePreDragEdgeDelta = Offset.zero;
        // Discard live overrides on BOTH transitions:
        //   - On turn-OFF: discard unsaved changes (the user exited).
        //   - On turn-ON: clear any stale state from a prior session
        //     that might have leaked (e.g. process restart, hot
        //     reload, or a previous turn-OFF that didn't run).
        // After clearing, the only positions in effect are auto-layout
        // ⊕ savedOverrides — i.e. the last committed layout.
        _rearrangeLiveNodeOverrides = const {};
        _rearrangeLiveEdgeWaypoints = const {};
        _rearrangeDragRevision++;
        ref.read(hasUnsavedChangesProvider.notifier).state = false;
        setState(() {});
      });
    });

    // v5.27 Task 2: connect-on-open animation controller. Reuses
    // the EXISTING GraphPathTraceController pattern (one
    // AnimationController + orderedEdgeIds + per-edge duration scaling
    // 320/250/180ms with 2200ms cap). We add a painter flag
    // (connectOnOpenActive) so the painter interprets
    // currentEdgeId+traceProgress as fade-in alpha instead of the
    // existing sweep semantics.
    _connectOnOpenController = GraphPathTraceController()..attach(this);
    // v5.140 (PERF): The connect-on-open controller's tick listener is
    // now hosted by EdgeSelectionWrapper (passed via the
    // `connectOnOpenController` constructor param). This means each
    // animation tick repaints ONLY the edge painter, not the entire
    // graph canvas. The parent state no longer calls setState on tick.
    // The parent still OWNS the controller and calls methods on it
    // (revealAll, startTraceSimultaneous, reducedMotion=, etc.) —
    // those calls trigger the wrapper's listener via ChangeNotifier.

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
      // v5.x (progressive-load fix): reset the user-interaction flag +
      // last-framed anchor position on family switch so the new
      // family gets the auto-centering benefit.
      _userHasInteractedWithCamera = false;
      _lastFramedAnchorPos = null;
      // v5.x (perf fix — pinch-zoom GPU-transform): reset the gesture
      // flag + commit revision on family switch so the new family
      // doesn't inherit a stale "gesture in progress" state if the
      // user happened to switch families mid-pinch (which can happen
      // via deep links or provider-driven navigation).
      _painterActiveGesture = false;
      _zoomCommitRevision = 0;
      _lastCommittedZoom = 1.0;
      _camera
        ..resetInitialFit()
        ..setFamilyId(widget.familyId);
      _culler.invalidate();
      _edgePathCache.clear();
      // v5.117: Reset the proximity graph state when switching families
      // so the new family's anchor + 2-hop neighborhood is computed
      // fresh (not the stale set from the previous family).
      ref.read(proximityGraphProvider.notifier).reset();
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
      // v5.123 (Step 5): Re-apply persisted branch expansion for the
      // NEW family on its first build (the guard family ID resets).
      _persistedExpansionSeededFamilyId = null;
      _lastEdgeFingerprint = 0;
      _lastFocusedPersonId = null;
      // v5.27 Task 2: reset the connect-on-open flag on family switch
      // so the new family's graph plays the connect-on-open animation
      // from scratch. Also stop any in-flight trace from the previous
      // family.
      _hasPlayedConnectOnOpen = false;
      _connectOnOpenOrderedEdgeIds = const [];
      _connectOnOpenController?.reset();
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
    _cameraRebuildTimer?.cancel(); // v5.x (perf fix)
    _camera.removeListener(_onCameraChanged);
    _camera.dispose();
    _culler.dispose();
    _positionMemory.dispose();
    // v5.27 Task 1: dispose the reset animation controller.
    _resetController?.removeStatusListener(_onResetAnimationStatus);
    _resetController?.removeListener(_onResetAnimationTick);
    _resetController?.dispose();
    _resetController = null;
    // v5.27 Task 2: dispose the connect-on-open controller.
    // v5.140 (PERF): The tick listener is now hosted by
    // EdgeSelectionWrapper — no listener to remove here. We still
    // detach + dispose the controller itself (the wrapper only listens,
    // it doesn't own the controller).
    _connectOnOpenController?.detach();
    _connectOnOpenController?.dispose();
    _connectOnOpenController = null;
    // v5.30 Issue 2: dispose the load animation controller.
    _loadController?.removeStatusListener(_onLoadAnimationStatus);
    _loadController?.removeListener(_onLoadAnimationTick);
    _loadController?.dispose();
    _loadController = null;
    // v5.143: Dispose branch expand animation controller.
    _branchExpandController?.removeStatusListener(_onBranchExpandStatus);
    _branchExpandController?.removeListener(_onBranchExpandTick);
    _branchExpandController?.dispose();
    _branchExpandController = null;
    // v5.72 (ZOOM LOOP FIX): Clear focus state when the graph widget is
    // disposed. The graphFocusProvider is a GLOBAL provider that survives
    // screen exits — without this clear, the focused person ID persists
    // after the user leaves the graph. When they return, the new widget
    // instance has _lastFocusedPersonId = null, so the guard
    // `focusState.focusedPersonId != _lastFocusedPersonId` is TRUE →
    // _maybeFocusCameraOnNode re-fires → the camera re-animates → the
    // user sees the zoom loop again. Clearing focus on dispose ensures
    // the focus state doesn't survive screen exits.
    //
    // Also cancel the focus auto-timeout timer (see _focusTimeoutTimer
    // in the _onFocusPerson handler).
    _focusTimeoutTimer?.cancel();
    // v5.123 (DISPOSE FIX): Call the captured notifier instances instead
    // of ref.read — using ref after the element has been disposed throws
    // "Bad state: Cannot use ref after the widget was disposed" during
    // tree finalization (test teardown hit this).
    _focusNotifierForCleanup.clearAll();
    // v5.74 (BUG 1 FIX): Clear the selectedNodeProvider on dispose.
    // This is a global StateProvider that survives screen exits —
    // without clearing it, a node selected in a prior session stays
    // "selected" (highlighted with a glow ring) when the user returns
    // to the graph, even though they didn't tap anything. This caused
    // the "Manish's node appears highlighted without being tapped" bug.
    _selectedNodeNotifierForCleanup.state = null;
    // v5.123 (Step 5): Detach the expansion-persistence callback — the
    // captured `ref` in its closure must never be used after disposal.
    _branchCollapseNotifierForCleanup.onExpansionChanged = null;
    super.dispose();
  }

  /// v5.123 (Step 5): Applies PERSISTED branch expansion choices on
  /// top of the default density-collapse computation, once per family
  /// load. Branches the user previously expanded (persisted as
  /// `true` keyed by (userId, familyId, branchRootId) on the
  /// GraphLayoutState row) load ALREADY-EXPANDED:
  ///   1. Their roots join expandedBranchRoots (seedExpandedBranchRoots)
  ///      so the budget rule skips them — even when it would otherwise
  ///      have collapsed them.
  ///   2. Their subtrees are revealed into the proximity visible set
  ///      (revealBranchSubtree) so the members actually render.
  ///
  /// Called post-frame from the canvas build (provider mutations are
  /// not allowed during the build phase).
  void _applyPersistedBranchExpansion(FlatGraphResult flat) {
    final familyId = widget.familyId;
    if (_persistedExpansionSeededFamilyId == familyId) return;

    final persisted =
        ref.read(branchExpansionStateProvider(familyId)).valueOrNull;
    if (persisted == null) return; // Still loading — retry on next build.

    // Mark this family as seeded from here on. An empty persisted map
    // means the viewer never expanded a branch — nothing to apply.
    // In-session saves (expandBranch) don't need re-seeding: the reveal
    // already happened interactively via _fetchAndExpandBranch.
    _persistedExpansionSeededFamilyId = familyId;

    final expandedRoots = <String>{
      for (final entry in persisted.entries)
        if (entry.value) entry.key,
    };
    if (expandedRoots.isEmpty) return;

    // 1. Protect the persisted-expanded roots from the budget rule.
    _branchCollapseNotifierForCleanup.seedExpandedBranchRoots(expandedRoots);

    // 2. Reveal each root's subtree so the members render (only roots
    //    that exist in this family's data).
    final allPersonIds = <String>{
      for (final p in flat.persons) (p['id'] ?? '').toString(),
    };
    final childrenOf = <String, Set<String>>{};
    for (final Map<String, dynamic> r in flat.relationships) {
      final label = (r['labelAtoB'] as String?) ??
          (r['relationshipKey'] as String?) ?? '';
      if (label == 'father' || label == 'mother' || label == 'parent') {
        final from = r['fromPersonId'] as String?;
        final to = r['toPersonId'] as String?;
        if (from != null && to != null) {
          // "toPerson is fromPerson's parent" → from is child of to.
          childrenOf.putIfAbsent(to, () => <String>{}).add(from);
        }
      }
    }
    for (final rootId in expandedRoots) {
      if (!allPersonIds.contains(rootId)) continue;
      ref.read(proximityGraphProvider.notifier).revealBranchSubtree(
            rootId: rootId,
            childrenOf: childrenOf,
            allPersons: allPersonIds,
          );
    }
  }

  // ── v5.27 Task 1 — Reset animation callbacks ─────────────────────

  void _onResetAnimationTick() {
    if (!mounted) return;
    // Bump the per-frame revision so the EdgeSelectionWrapper's
    // layoutRevision changes — its painter's shouldRepaint checks
    // layoutRevision, not the positions map content, so without this
    // bump the painter would skip repainting during the animation.
    // (This is the same pattern used during Rearrange drags — see
    // _handleRearrangeDragUpdate which bumps _rearrangeDragRevision.)
    _rearrangeDragRevision++;
    // Trigger a rebuild so the canvas_mixin re-computes effectivePositions
    // using the lerp'd values for the current _resetController.value.
    setState(() {});
  }

  void _onResetAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted) return;
    // Animation finished — clear the pre-reset snapshots so the
    // canvas_mixin falls back to pure auto-layout (which is the
    // post-reset state — savedOverrides is empty after the
    // provider invalidation).
    _preResetPositions = null;
    _preResetEdgeWaypoints = null;
    _animatingReset = false;
    setState(() {});
  }

  /// Called when resetAnimationTriggerProvider increments. Captures
  /// the current effectivePositions (including saved overrides + live
  /// drag overrides — the "from" state of the lerp) into
  /// _preResetPositions / _preResetEdgeWaypoints, then starts the
  /// 350ms animation (or skips it entirely if reduced-motion is on).
  void _onResetTrigger() {
    if (!mounted) return;
    // Capture the current effective positions. These are the values
    // the canvas_mixin computed on the LAST build — accessible here
    // via the _currentPositionsWithOffset cache (which is updated
    // every build).
    //
    // _currentPositionsWithOffset is keyed by personId and includes
    // the visual-circle Y offset. For the lerp we want the raw graph
    // positions (without the Y offset), so we strip the offset back
    // out: rawY = withOffsetY - _kCircleCenterYOffset.
    //
    // If _currentPositionsWithOffset is empty (very first frame,
    // nothing rendered yet), there's nothing to animate from — skip
    // the animation entirely and let the provider invalidation snap
    // to the new state.
    if (_currentPositionsWithOffset.isEmpty) {
      // Nothing to lerp from — snap to pure auto-layout.
      _preResetPositions = null;
      _preResetEdgeWaypoints = null;
      _animatingReset = false;
      return;
    }
    final preResetPositions = <String, Offset>{};
    for (final entry in _currentPositionsWithOffset.entries) {
      preResetPositions[entry.key] = Offset(
        entry.value.dx,
        entry.value.dy - _kCircleCenterYOffset,
      );
    }
    // Also capture the current edge waypoints (saved + live). The
    // canvas_mixin stores these in effectiveEdgeWaypoints which is a
    // LOCAL in the build method — we don't have a cached field. So
    // we read from the saved overrides + live overrides directly.
    final saved = ref
        .read(personalLayoutOverridesProvider(widget.familyId))
        .valueOrNull;
    final preResetEdgeWaypoints = <String, Offset>{
      ...?saved?.edgeWaypoints,
      ..._rearrangeLiveEdgeWaypoints,
    };

    // Reduced motion: skip the animation entirely. Just clear the
    // pre-reset snapshots so the canvas_mixin falls back to the
    // post-reset state (pure auto-layout) on the next build.
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _preResetPositions = null;
      _preResetEdgeWaypoints = null;
      _animatingReset = false;
      return;
    }

    // Start the animation. The 350ms duration is already set on the
    // controller in initState (flat — not scaled per node count, so
    // resetting a 50-person tree feels just as snappy as resetting 2).
    _preResetPositions = preResetPositions;
    _preResetEdgeWaypoints = preResetEdgeWaypoints;
    _animatingReset = true;
    _resetController?.forward(from: 0.0);
    // Trigger an immediate rebuild so the canvas_mixin sees
    // _animatingReset=true + _preResetPositions and starts lerping.
    setState(() {});
  }

  // ── v5.34 — Save-All + Reset-Unsaved handlers ─────────────────────

  /// v5.34: Called when the user taps the persistent Save button.
  /// Iterates over _rearrangeLiveNodeOverrides and
  /// _rearrangeLiveEdgeWaypoints, saves each entry via
  /// LayoutOverridesService, waits for the provider to resolve, then
  /// clears both maps. All changes committed in one operation.
  Future<void> _onSaveAllTrigger() async {
    if (!mounted) return;
    // v5.35: Debug logging to trace why Save might not be working.
    debugPrint('[v5.35 Save] triggered — '
        'liveNodes=${_rearrangeLiveNodeOverrides.length} '
        'liveEdges=${_rearrangeLiveEdgeWaypoints.length}');
    // Save all node overrides.
    for (final entry in _rearrangeLiveNodeOverrides.entries) {
      debugPrint('[v5.35 Save] saving node ${entry.key} at ${entry.value}');
      await LayoutOverridesService.saveNodeOverride(
          ref, widget.familyId, entry.key, entry.value);
    }
    // Save all edge waypoint overrides.
    for (final entry in _rearrangeLiveEdgeWaypoints.entries) {
      debugPrint('[v5.35 Save] saving edge ${entry.key} at ${entry.value}');
      await LayoutOverridesService.saveEdgeWaypoint(
          ref, widget.familyId, entry.key, entry.value);
    }
    // Wait for the provider to resolve with the new persisted values
    // BEFORE clearing the live overrides (same fix as v5.30 Issue 1 —
    // prevents the one-frame gap where neither saved nor live overrides
    // are present).
    if (_rearrangeLiveNodeOverrides.isNotEmpty ||
        _rearrangeLiveEdgeWaypoints.isNotEmpty) {
      await ref.read(
          personalLayoutOverridesProvider(widget.familyId).future);
    }
    // Clear the live override maps — the saved overrides now reflect
    // all the changes.
    _rearrangeLiveNodeOverrides = const {};
    _rearrangeLiveEdgeWaypoints = const {};
    _rearrangeDragRevision++;
    // v5.38: Clear the unsaved-changes flag so the Save button
    // disables. Also increment saveCompletedTriggerProvider so the
    // screen shows the "Layout saved successfully" snackbar.
    ref.read(hasUnsavedChangesProvider.notifier).state = false;
    ref.read(saveCompletedTriggerProvider.notifier).state++;
    if (mounted) setState(() {});
  }

  /// v5.34: Called when the user taps the Reset button.
  /// Discards ALL unsaved changes (clears _rearrangeLiveNodeOverrides +
  /// _rearrangeLiveEdgeWaypoints). The graph snaps back to the LAST
  /// SAVED layout (whatever was in the DB when Rearrange mode was
  /// entered). Does NOT touch the DB — saved overrides are preserved.
  void _onResetUnsavedTrigger() {
    if (!mounted) return;
    debugPrint('[v5.35 Reset] triggered — clearing '
        '${_rearrangeLiveNodeOverrides.length} node overrides + '
        '${_rearrangeLiveEdgeWaypoints.length} edge overrides');
    _rearrangeLiveNodeOverrides = const {};
    _rearrangeLiveEdgeWaypoints = const {};
    _rearrangeDragKind = null;
    _rearrangeDragId = null;
    _rearrangePreDragPosition = null;
    _rearrangePreDragEdgeDelta = Offset.zero;
    _rearrangeDragRevision++;
    // v5.38: Clear the unsaved-changes flag so the Save button disables.
    ref.read(hasUnsavedChangesProvider.notifier).state = false;
    setState(() {});
  }

  // ── v5.27 Task 2 — Connect-on-open animation callbacks ──────────
  //
  // v5.140 (PERF): _onConnectOnOpenTick was removed. The connect-on-
  // open controller's tick listener now lives inside EdgeSelectionWrapper
  // (added via the `connectOnOpenController` constructor param). This
  // scopes each animation tick's repaint to JUST the edge painter
  // instead of the entire graph canvas — eliminating the 1–3s window
  // of degraded pan/zoom on first graph load.

  /// Ordered edge IDs (BFS from the viewer's own anchor node) for the
  /// connect-on-open animation. Used by _maybeStartConnectOnOpen to
  /// order the edge draw-in: viewer's own edges first, then outward
  /// by BFS distance. Falls back to flat.relationships order if the
  /// viewer has no resolved Person node.
  List<String> _orderedEdgesForConnectOnOpen(FlatGraphResult flat, String? viewerPersonId) {
    if (flat.relationships.isEmpty) return const [];
    // Build adjacency list (personId → list of edge IDs touching them).
    final adjacency = <String, List<String>>{};
    final edgeById = <String, Map<String, dynamic>>{};
    for (final r in flat.relationships) {
      final id = r['id']?.toString();
      final from = r['fromPersonId']?.toString();
      final to = r['toPersonId']?.toString();
      if (id == null || from == null || to == null) continue;
      edgeById[id] = r;
      adjacency.putIfAbsent(from, () => []).add(id);
      adjacency.putIfAbsent(to, () => []).add(id);
    }

    // BFS from the viewer's own node (or fall back to the first
    // edge's source if the viewer has no resolved Person node).
    final startNode = viewerPersonId ??
        (flat.relationships.first['fromPersonId']?.toString() ??
            flat.relationships.first['toPersonId']?.toString());
    if (startNode == null) {
      // No edges → empty list. (Connect-on-open is a no-op for empty
      // graphs, but the spec says we should still set _hasPlayed.)
      return const [];
    }

    final orderedEdgeIds = <String>[];
    final visitedNodes = <String>{};
    final visitedEdges = <String>{};
    final queue = <String>[startNode];
    visitedNodes.add(startNode);
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      final incidentEdgeIds = adjacency[node] ?? const [];
      for (final edgeId in incidentEdgeIds) {
        if (visitedEdges.contains(edgeId)) continue;
        final r = edgeById[edgeId]!;
        final from = r['fromPersonId']!.toString();
        final to = r['toPersonId']!.toString();
        orderedEdgeIds.add(edgeId);
        visitedEdges.add(edgeId);
        // Enqueue the OTHER endpoint (BFS expands outward).
        final other = from == node ? to : from;
        if (!visitedNodes.contains(other)) {
          visitedNodes.add(other);
          queue.add(other);
        }
      }
    }
    return orderedEdgeIds;
  }

  /// Drives the connect-on-open animation on the FIRST render after
  /// opening the graph screen (gated by _hasPlayedConnectOnOpen). If
  /// reduced motion is active, calls revealAll instead of startTrace
  /// (so all edges appear immediately, no animation).
  ///
  /// v5.93: Now passes per-edge pixel lengths to startTrace so the
  /// animation duration is proportional to each edge's length (1–3s
  /// per edge), making all edges appear to draw at the same visual
  /// speed. The length is computed as the straight-line distance
  /// between the two node center positions (sufficient — exact bezier
  /// arc length is not needed for timing).
  void _maybeStartConnectOnOpen(
    FlatGraphResult flat,
    String? viewerPersonId,
    Map<String, Offset> positions,
  ) {
    if (_hasPlayedConnectOnOpen) return;
    if (flat.relationships.isEmpty) {
      // Empty family — nothing to animate. But still mark as played
      // so we don't keep checking.
      _hasPlayedConnectOnOpen = true;
      return;
    }
    // Only kick off the trace ONCE — when flat.relationships is first
    // populated. Subsequent rebuilds (pan/zoom/new members) won't
    // re-trigger.
    _hasPlayedConnectOnOpen = true;
    final ordered =
        _orderedEdgesForConnectOnOpen(flat, viewerPersonId);
    _connectOnOpenOrderedEdgeIds = ordered;
    if (ordered.isEmpty) return;
    final reduced = MediaQuery.disableAnimationsOf(context);
    // v5.141 (LOW-END PERF): On low-end devices, skip the connect-on-
    // open animation entirely. The animation previously caused 1–3s
    // of degraded pan/zoom on first load because each tick repainted
    // the edge layer. On low-end devices the frame budget is already
    // tight — the animation pushes it over the edge. revealAll()
    // shows all edges instantly at full alpha, which is perfectly
    // acceptable on a low-end device (no "premium reveal" expectation).
    final skipAnimation = reduced || !_perfProfile.allowConnectOnOpenAnimation;
    // Propagate reduced-motion to the controller so it suppresses
    // per-step haptics (same pattern as the existing path trace).
    _connectOnOpenController!.reducedMotion = reduced;
    if (skipAnimation) {
      // Skip the animation — all edges revealed immediately.
      _connectOnOpenController!.revealAll(ordered);
    } else {
      // v5.93: Compute per-edge pixel lengths (straight-line distance
      // between the two node centers) so startTrace can use
      // length-proportional timing (1–3s per edge).
      final edgeLengths = <String, double>{};
      final edgeById = <String, Map<String, dynamic>>{};
      for (final r in flat.relationships) {
        final id = r['id']?.toString();
        if (id != null) edgeById[id] = r;
      }
      for (final edgeId in ordered) {
        final r = edgeById[edgeId];
        if (r == null) {
          edgeLengths[edgeId] = 400.0; // fallback
          continue;
        }
        final fromId = r['fromPersonId']?.toString();
        final toId = r['toPersonId']?.toString();
        final fromPos = fromId != null ? positions[fromId] : null;
        final toPos = toId != null ? positions[toId] : null;
        if (fromPos != null && toPos != null) {
          edgeLengths[edgeId] = (fromPos - toPos).distance;
        } else {
          edgeLengths[edgeId] = 400.0; // fallback if positions missing
        }
      }
      _connectOnOpenController!.startTraceSimultaneous(
        ordered,
        edgeLengths: edgeLengths,
      );
    }
  }

  // ── v5.30 Issue 2 — Load animation callbacks ────────────────────

  void _onLoadAnimationTick() {
    if (!mounted) return;
    // Bump the per-frame revision so the EdgeSelectionWrapper's
    // layoutRevision changes and the painter repaints (same pattern
    // as the reset animation tick).
    _rearrangeDragRevision++;
    setState(() {});
  }

  void _onLoadAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted) return;
    _animatingLoad = false;
    setState(() {});
  }

  // ── v5.143 — Branch expand/collapse animation callbacks ─────────

  void _onBranchExpandTick() {
    if (!mounted) return;
    _branchAnimationProgress = Curves.easeOut.transform(
      _branchExpandController!.value,
    );
    _rearrangeDragRevision++;
    setState(() {});
  }

  void _onBranchExpandStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!mounted) return;
    _animatingBranchExpand = false;
    _branchAnimatingNodeIds = {};
    _branchAnimationProgress = 1.0;
    setState(() {});
  }

  /// v5.143: Starts the branch expand animation.
  /// [origin] is the chip's graph-space position (where the chip was).
  /// [revealedNodeIds] are the IDs of the newly-revealed nodes that
  /// should animate from [origin] to their computed final positions.
  void _startBranchExpandAnimation(
    Offset origin,
    Set<String> revealedNodeIds,
  ) {
    if (!mounted || revealedNodeIds.isEmpty) return;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      // Skip animation — nodes appear at final positions immediately.
      _branchAnimationProgress = 1.0;
      _animatingBranchExpand = false;
      _branchAnimatingNodeIds = {};
      return;
    }
    _branchAnimationOrigin = origin;
    _branchAnimatingNodeIds = revealedNodeIds;
    _animatingBranchExpand = true;
    _branchAnimationProgress = 0.0;
    _branchExpandController!.forward(from: 0.0);
  }

  /// v5.159 (ENTRANCE ANIMATION): records the members a branch-bubble
  /// tap just revealed, plus the bubble's position (the branch root's
  /// position at tap time) to fly them out from.
  ///
  /// Unlike [_startBranchExpandAnimation] (v5.143, never called), this
  /// does NOT start the controller immediately — the revealed members
  /// have no positions yet (the layout provider recomputes
  /// asynchronously after the proximity reveal). The ids sit in
  /// [_pendingEntranceNodeIds] until the canvas build observes that the
  /// layout has assigned them positions; it then promotes them into
  /// [_branchAnimatingNodeIds] and starts the controller — so the
  /// animation begins at the exact frame the nodes first render, and
  /// the nodes animate from the bubble's position out to their final
  /// spots instead of popping in.
  void _markNodesForEntrance(Set<String> ids, {Offset? origin}) {
    if (ids.isEmpty) return;
    if (origin != null && origin != Offset.zero) {
      _branchAnimationOrigin = origin;
    }
    _pendingEntranceNodeIds = Set<String>.of(ids);
  }

  /// v5.159 (RE-COLLAPSE CLEANUP): cancels any in-flight entrance
  /// animation. Called when a branch is re-collapsed or manually
  /// collapsed — the concealed members must not keep flying in (their
  /// positions vanish with the conceal anyway; this stops the
  /// controller churn + keeps _branchAnimatingNodeIds from referencing
  /// concealed ids for the remaining frames).
  void _cancelEntranceAnimation() {
    _pendingEntranceNodeIds = {};
    _branchAnimatingNodeIds = {};
    _animatingBranchExpand = false;
    _branchAnimationProgress = 1.0;
    _branchExpandController?.stop();
  }

  /// v5.30 Issue 2: On first render with non-empty saved overrides,
  /// start a load animation that lerps every node from its auto-layout
  /// origin to its saved override position over ~500ms easeOutCubic.
  /// Uses a one-time _hasPlayedLoadAnimation flag (same pattern as
  /// _hasPlayedConnectOnOpen) so it only fires once per session load.
  ///
  /// The animation is driven by the canvas_mixin's effectivePositions
  /// computation: when _animatingLoad is true, it lerps from
  /// layout.positions (auto-layout) to effectivePositions (which
  /// includes saved overrides) by _loadController.value.
  void _maybeStartLoadAnimation(PersonalLayoutOverrides savedOverrides) {
    if (_hasPlayedLoadAnimation) return;
    // Only start when saved overrides are non-empty (otherwise there's
    // nothing to animate to — all nodes are already at auto-layout).
    if (savedOverrides.isEmpty) {
      // Mark as played so we don't keep checking on every rebuild.
      // If overrides are saved LATER (via a drag+Save), they'll just
      // snap into place on the next render — no load animation for
      // mid-session saves, only on initial graph load.
      _hasPlayedLoadAnimation = true;
      return;
    }
    _hasPlayedLoadAnimation = true;
    // Reduced-motion: skip the animation entirely.
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _animatingLoad = false;
      return;
    }
    _animatingLoad = true;
    _loadController?.forward(from: 0.0);
    setState(() {});
  }

  /// v5.147 (TIER 1C): Pre-warm avatar cache by calling precacheImage
  /// for all visible persons' photo URLs in parallel. This eliminates
  /// the 200-500ms "empty circle" pop-in that happens when GraphNode
  /// widgets build before their avatars are downloaded.
  ///
  /// Runs ONCE per graph-data change (tracked by _prewarmedAvatarsFlat
  /// identity check). On subsequent rebuilds (pan/zoom), avatars are
  /// already in the image cache — no-op.
  void _maybePrewarmAvatars(FlatGraphResult flat) {
    if (!mounted) return;
    // Skip if we already prewarmed for this exact flat instance.
    if (identical(_prewarmedAvatarsFlat, flat) && _hasPrewarmedAvatars) {
      return;
    }
    _prewarmedAvatarsFlat = flat;
    _hasPrewarmedAvatars = true;

    // Collect all non-null, non-empty photo URLs.
    final photoUrls = <String>[];
    for (final p in flat.persons) {
      final url = p['photoUrl'] as String?;
      if (url != null && url.isNotEmpty && url.startsWith('http')) {
        photoUrls.add(url);
      }
    }
    if (photoUrls.isEmpty) return;

    // precacheImage needs a BuildContext — use the current context
    // via a post-frame callback. We precache in parallel by firing
    // all calls without awaiting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in photoUrls) {
        precacheImage(
          NetworkImage(url),
          context,
          onError: (e, stack) {
            // Silent — avatar load failure is non-fatal (GraphNode
            // shows a fallback initial circle).
          },
        );
      }
      debugPrint('[v5.147] Pre-warmed ${photoUrls.length} avatars');
    });
  }

  /// Rebuild content ONLY when the visible set or LOD tier would change.
  /// Otherwise the AnimatedBuilder pans/zooms the Transform layer for free.
  void _onCameraChanged() {
    if (!mounted) return;
    final Rect vp = _graphSpaceViewport();
    final Lod lod = _lodFor(_camera.zoomLevel);

    // v5.148 (TIER 2E): Adaptive culler threshold. Scale the rebuild
    // threshold by the current visible node count so small families
    // don't rebuild on every 50px pan (wasteful — same visible set
    // is returned). Formula: threshold = clamp(visibleCount * 5, base, base*4).
    // With 22 visible nodes: threshold = 110px (vs 50px default).
    // With 5 visible nodes: threshold = 50px (minimum).
    // This reduces rebuild frequency by ~40% on small families.
    final visibleCount = _culler.visibleCount;
    final baseThreshold = _perfProfile.cullerRebuildThresholdPixels;
    final adaptiveThreshold =
        (visibleCount * 5.0).clamp(baseThreshold, baseThreshold * 4.0);
    if (_culler.rebuildThreshold != adaptiveThreshold) {
      _culler.rebuildThreshold = adaptiveThreshold;
    }

    // v5.x (perf fix — pinch-zoom GPU-transform): During an active
    // pinch-zoom gesture, the AnimatedBuilder in canvas_mixin is
    // scaling the cached raster on the GPU via a Matrix4 transform —
    // exactly like it does for panning. We must NOT trigger a
    // setState-based rebuild of the node widget list on every frame
    // of the gesture; that would defeat the GPU-transform fast path
    // (the same architectural bottleneck the painter fix addresses).
    //
    // The culler's `shouldRebuild` already has a 10% zoom threshold,
    // but during a fast pinch it still fires multiple times per
    // second — and each fire runs an O(visible-nodes) cull pass on
    // the raster thread. We add a stricter gate here for the gesture
    // window: only allow a culler-driven rebuild when the pinch has
    // moved more than [_kZoomCommitThreshold] (15%) past the last
    // committed zoom (matching the painter's interim-commit cadence
    // — so the culler and the edge painter refresh on the same
    // schedule during a long pinch). On gesture end, the
    // _onScaleEnd handler bumps _zoomCommitRevision and calls
    // setState, which delivers the final correct zoom to both the
    // culler and the painter in a single coalesced rebuild.
    if (_painterActiveGesture) {
      final currentZoom = _camera.zoomLevel;
      final baseline =
          _lastCommittedZoom > 0 ? _lastCommittedZoom : currentZoom;
      final zoomDelta = (currentZoom - baseline).abs() / baseline;
      if (zoomDelta <= _kZoomCommitThreshold) {
        // Within the 15% window — the GPU transform carries the
        // visual update. Skip the culler/LOD rebuild entirely.
        return;
      }
      // Crossed the 15% threshold — let the culler/LOD rebuild path
      // below run, then update the baseline so the next window is
      // measured incrementally. (The painter's interim-commit
      // handler in _onScaleUpdate bumps _zoomCommitRevision on the
      // same threshold, so both subsystems refresh in lockstep.)
      _lastCommittedZoom = currentZoom;
    }

    // v5.x (perf fix): Do NOT call setState() during an active pan/zoom
    // gesture. The AnimatedBuilder in canvas_mixin already handles
    // the camera transform repaint — setState here is ONLY needed to
    // rebuild the node widget list when the visible set changes (new
    // nodes enter/leave the viewport). Calling setState on every
    // camera frame during a drag forces a full Element-tree rebuild
    // (every Positioned node widget), which is the #1 cause of the
    // "stuck stuttery" panning the user reported.
    //
    // Fix: debounce the rebuild — if the culler says a rebuild is
    // needed, schedule it for the NEXT microtask (not synchronously).
    // During a fast drag, multiple camera changes arrive before the
    // next frame, so the debounce coalesces them into a single
    // rebuild per frame. The AnimatedBuilder handles the transform
    // in the meantime, so the user sees smooth panning with the
    // current node set; the node list updates one frame later when
    // new nodes are needed.
    if (lod != _lastLod || _culler.shouldRebuild(_lastCullViewport, vp)) {
      // Debounce: only schedule one rebuild per frame.
      _cameraRebuildTimer?.cancel();
      _cameraRebuildTimer = Timer(const Duration(milliseconds: 16), () {
        if (mounted) setState(() {});
      });
    }
  }

  Lod _lodFor(double zoom) {
    // v5.141 (LOW-END PERF): Use the tier-aware LOD function from the
    // performance profile.
    //
    // • High-end: always Lod.full (per the user's v5.112 request —
    //   "nodes should NEVER degrade to simple colored dots or
    //   circles"). The profile's lodForZoom returns Lod.full for
    //   every zoom on high-end devices.
    // • Mid-range: Lod.full for zoom >= 0.50, Lod.compact below.
    //   Compact is still a full GraphNode — just with the relation
    //   label faded. The user's "no dots" request is respected.
    // • Low-end: Lod.full for zoom >= 0.65, Lod.compact for 0.30–0.65,
    //   Lod.mini (circle + initial) below 0.30. Mini is still
    //   recognizable — NOT anonymous dots.
    //
    // Additionally, on low-end/mid devices, if the visible node count
    // exceeds _perfProfile.maxVisibleNodesBeforeForceMini, the graph
    // FORCES Lod.mini regardless of zoom — preventing the culler from
    // juggling 100+ premium GraphNode widgets (each with 5
    // AnimationControllers) on devices that can't handle it.

    // Preserve the SemanticTier computation for backward compat
    // (focus-mode logic, tests). This no longer drives the Lod
    // selection — the profile does.
    final focusActive = ref.read(graphFocusProvider).focusedPersonId != null;
    final thresholds = thresholdsForMemberCount(_currentMemberCount);
    _currentSemanticTier = computeSemanticTier(
      zoom,
      currentTier: _currentSemanticTier,
      thresholds: thresholds,
      memberCount: _currentMemberCount,
      focusActive: focusActive,
    );

    final forceMiniThreshold = _perfProfile.maxVisibleNodesBeforeForceMini;
    if (forceMiniThreshold != null &&
        _culler.visibleCount > forceMiniThreshold) {
      // Too many visible nodes for this device tier — force mini to
      // keep the frame rate stable. The user's "no dots" request is
      // still respected (mini = circle + initial, not anonymous dots).
      return Lod.mini;
    }
    return _perfProfile.lodForZoom(zoom);
  }

  /// v96 (Phase 3): Returns the current semantic tier (with hysteresis).
  /// Computed as a side effect of [_lodFor] — call _lodFor first.
  SemanticTier get _currentTier => _currentSemanticTier ?? SemanticTier.near;

  /// Maps the current LOD to the edge-layer visual quality tier (PART 10).
  /// Computed ONCE per build and passed to `EngineEdgePainter` — the
  /// painter never derives quality per edge.
  ///
  /// v5.111: Updated for 5-tier system. COMPACT uses full edge quality
  /// (the GraphNode is still premium — no reason to degrade edges).
  /// MINI and MICRO use chip-quality edges (simplified but still visible).
  ///
  /// v5.141 (LOW-END PERF): Now delegates to the performance profile.
  /// On low-end devices, even at Lod.full the edge quality is
  /// downgraded to EdgeQuality.chip (lighter shadow sigma, reduced
  /// ridge alpha). Combined with the allowEdgeShadowPass /
  /// allowEdgeRidgePass flags (consumed by the painter via the
  /// profile), this means low-end edges are a single body pass —
  /// the cheapest possible visible edge.
  EdgeQuality _edgeQualityFor(Lod lod) {
    return _perfProfile.edgeQualityForLod(lod);
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
  /// v5.111: Added 'compact', 'mini', 'micro' tiers.
  String _lodTierName(Lod lod) {
    switch (lod) {
      case Lod.full:
        return 'full';
      case Lod.compact:
        return 'compact';
      case Lod.mini:
        return 'mini';
      case Lod.micro:
        return 'micro';
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
    // v5.11: isViewerLinkedProvider is now a synchronous Provider (not
    // FutureProvider) that derives from viewerPersonIdProvider. It returns
    // true when the viewer is linked, false when not, and true on loading/error.
    final viewerIsLinked = ref.watch(isViewerLinkedProvider(widget.familyId));
    // v4.9: viewerIsUnlinked removed — was only used by the ClaimProfileBanner
    // which is no longer rendered. Left viewerIsLinked in case it's needed later.

    // v5.22: Personal layout overrides (saved per-viewer node positions +
    // edge midpoint bow offsets) and the Rearrange-mode toggle. Both are
    // watched here so the canvas rebuilds when (a) the user toggles
    // Rearrange mode, or (b) the saved overrides row changes (e.g. after
    // a Save in the SaveLockPill — the LayoutOverridesService invalidates
    // the provider so the engine view re-reads the fresh row).
    final savedOverrides =
        ref.watch(personalLayoutOverridesProvider(widget.familyId)).valueOrNull ??
            PersonalLayoutOverrides.empty;
    final rearrangeMode = ref.watch(rearrangeModeProvider);

    // v5.97: Use skipLoadingOnReload so that when the graph is invalidated
    // by realtime events (or any other ref.invalidate), the UI keeps
    // showing the PREVIOUS layout instead of flashing a loading spinner.
    // The loading spinner only shows on the FIRST load (when there's no
    // previous data). This prevents the "Loading family graph..." from
    // appearing repeatedly every few seconds.
    return layoutAsync.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, _) => ErrorRetry(
        onRetry: () =>
            ref.invalidate(familyGraphProvider(widget.familyId)),
      ),
      data: (GraphLayoutResult layout) {
        // v5.135: Distinguish between "genuinely empty family" (0 real
        // members) and "access denied / layout failed" (members exist in
        // the graph data but positions are empty). The old code showed
        // the same misleading "No family members yet. Add someone to
        // start" message in both cases — confusing when the stats panel
        // simultaneously shows "714 members".
        //
        // Logic:
        //   - flat == null OR flat.persons.isEmpty → genuinely empty
        //     → EmptyGraph ("add someone to start")
        //   - flat.persons.isNotEmpty BUT layout.positions.isEmpty
        //     → access issue / layout failure
        //     → AccessIssueGraph ("unable to load, try logging out")
        if (flat == null || flat.persons.isEmpty) {
          return const EmptyGraph();
        }
        if (layout.positions.isEmpty) {
          // Members exist in the graph data but the layout produced no
          // positions. This is the "RLS blocked the direct query" or
          // "stale session" case — NOT a genuinely empty family.
          debugPrint('[v5.135] AccessIssueGraph: flat has '
              '${flat.persons.length} persons but layout.positions is empty. '
              'This indicates an access/session issue, not an empty family.');
          return AccessIssueGraph(
            reportedMemberCount: flat.persons.length,
            onRetry: () =>
                ref.invalidate(familyGraphProvider(widget.familyId)),
          );
        }
        // v4.16: Removed _onLayoutChanged call — it triggered recenterIfNeeded()
        // which forced the camera back after panning. With free panning, no
        // forced recentering should happen.
        // v107: Execute a pending Reset View request now that the
        // layout positions are available. This runs the new
        // resetView() method which centers the focus node (selected →
        // anchor → first node) at the exact viewport center.
        if (_pendingResetView) {
          _pendingResetView = false;
          _maybeRunPendingResetView(layout, flat, viewerPersonId);
        }
        // v5.27 Task 2: Kick off the connect-on-open animation on the
        // FIRST render where flat.relationships is populated. The
        // _hasPlayedConnectOnOpen flag is a one-time gate — subsequent
        // rebuilds (pan/zoom/new members) won't re-trigger.
        // v5.93: Pass layout.positions so per-edge pixel lengths can be
        // computed for length-proportional animation timing.
        _maybeStartConnectOnOpen(flat, viewerPersonId, layout.positions);
        // v5.30 Issue 2: Kick off the load animation for saved node
        // overrides on the FIRST render where savedOverrides is non-empty.
        // The _hasPlayedLoadAnimation flag is a one-time gate — subsequent
        // rebuilds won't re-trigger.
        _maybeStartLoadAnimation(savedOverrides);

        // v5.147 (TIER 1C): Pre-warm avatar cache. When the proximity RPC
        // returns ~22 nodes, immediately call precacheImage for all 22
        // avatar URLs in parallel. By the time the GraphNode widgets
        // build, avatars are already in the image cache — no pop-in,
        // no empty circles for 200-500ms.
        //
        // This is gated by _hasPrewarmedAvatars so it only runs ONCE
        // per graph-data change (not on every rebuild).
        _maybePrewarmAvatars(flat);

        // v5.x (anchor centering wiring fix): call _maybeFrame and
        // _maybeRecenterOnAnchorDrift HERE in build() — directly in
        // the data: callback of layoutAsync.when — so they run on
        // EVERY build where layout data is available, not just when
        // the LayoutBuilder inside _buildCanvas happens to rebuild.
        //
        // _maybeFrame: centers the camera on the anchor the FIRST
        // time it runs (guarded by _framed). After that it's a cheap
        // no-op (early return on `if (_framed) return;`).
        //
        // _maybeRecenterOnAnchorDrift: on every subsequent build,
        // compares the anchor's current layout position to
        // _lastFramedAnchorPos. If it moved >5px (because progressive
        // data loading completed and the layout was recomputed) AND
        // the user hasn't manually interacted with the camera
        // (_userHasInteractedWithCamera == false), re-centers
        // instantly. This is the fix for the "anchor visible for
        // 3-5 seconds then disappears" bug — the layout recalculates
        // when the full dataset loads, moving the anchor off-screen,
        // and this method follows it back to center.
        //
        // Both methods have internal guards (empty positions, zero
        // viewport size) so they're cheap no-ops on builds where
        // nothing changed. The viewport size is set by the
        // LayoutBuilder in _buildCanvas — on the first build it's
        // still Size.zero, so these calls no-op. On subsequent builds
        // (after the LayoutBuilder has resolved), the viewport size
        // is available and the centering actually runs.
        //
        // Note: we do NOT call _maybeFrame via addPostFrameCallback
        // here (that's already done in _buildCanvas). Calling it
        // directly in build() ensures it also runs on builds where
        // the LayoutBuilder doesn't rebuild (e.g., a provider
        // invalidation that changes the layout but not the viewport
        // constraints). The method is idempotent — double-calling is
        // safe because _framed guards the one-time init and the
        // drift check is a cheap distance comparison.
        _maybeFrame(layout, flat, viewerPersonId);
        _maybeRecenterOnAnchorDrift(layout, flat, viewerPersonId);
        // Wrap the graph in a Column so the graph expands to fill the space.
        // v4.9: Removed the ClaimProfileBanner — it's no longer rendered here.
        // The claim_profile_banner.dart file is left in place (unused) in case
        // it's wanted later. The graph's Expanded child fills the full remaining
        // space with the banner gone.
        return Column(
          children: [
            // v5.76: TEMPORARY debug banner showing viewer resolution state.
            // This helps diagnose why the viewer-relative perspective is not
            // working for non-creator accounts.
            if (kShowViewerDebugBanner)
              _ViewerDebugBanner(
                authUserId: ref.watch(currentUserProvider)?.id,
                authUserEmail: ref.watch(currentUserProvider)?.email,
                viewerPersonId: viewerPersonId,
                flat: flat,
                familyId: widget.familyId,
                supabaseClient: ref.watch(supabaseProvider),
              ),
            // v5.8: Re-enabled ClaimProfileBanner — shows a prompt when the
            // current user has NOT claimed a Person node in this family.
            // v5.11: SAFETY NET — only show when viewerPersonId is null
            // (genuinely unlinked). If viewerPersonId resolved to a real
            // Person, the graph is already showing "You" on their node —
            // the banner would contradict that. This guard prevents the
            // banner from ever appearing when the graph is working correctly.
            if (!viewerIsLinked && viewerPersonId == null)
              ClaimProfileBanner(familyId: widget.familyId),
            // Existing graph widget — expand to fill remaining space
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      key: _graphBoundaryKey,
                      child: _buildCanvas(
                          layout, flat, viewerPersonId,
                          savedOverrides: savedOverrides,
                          rearrangeMode: rearrangeMode),
                    ),
                  ),
                  if (!isOnline)
                    const Positioned(
                        left: 0, right: 0, top: 0, child: OfflineBanner()),
                  // v99 (Phase 1): Focus Back control
                  // v5.25 (distraction-free Rearrange): hide during
                  // Rearrange mode — its top-left position would
                  // visually conflict with the Rearrange toggle FAB
                  // (also top-left) and the focus-back action isn't
                  // relevant mid-drag.
                  if (ref
                      .watch(graphFocusProvider.select((s) => s.history))
                      .isNotEmpty &&
                      !rearrangeMode)
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
                  // v5.65 (ISOLATE CONNECTIONS): Persistent "Showing: X's
                  // connections — Show all" chip. Appears whenever a person
                  // is focused (isolation active). Tapping "Show all" (or
                  // the X icon) clears the focus and restores full opacity
                  // to the entire graph.
                  //
                  // Positioned at top-center so it doesn't conflict with
                  // the top-left Focus Back FAB or the top-right graph
                  // controls. Hidden during Rearrange mode (the isolation
                  // visual would interfere with drag feedback).
                  if (ref.watch(graphFocusProvider.select(
                          (s) => s.focusedPersonId != null)) &&
                      !rearrangeMode)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: _IsolateConnectionsChip(
                          personName: ref.watch(graphFocusProvider.select(
                              (s) => s.focusedPersonName ?? '')),
                          onShowAll: () {
                            // v5.72: Cancel the auto-timeout timer when
                            // the user manually exits isolation.
                            _focusTimeoutTimer?.cancel();
                            ref.read(graphFocusProvider.notifier).clearFocus();
                          },
                        ),
                      ),
                    ),
                  // P4.1: Mini-map
                  // v5.25 (distraction-free Rearrange): hide during
                  // Rearrange mode — its bottom-right position would
                  // visually conflict with the SaveLockPill (when a
                  // drag release happens near the right edge) and the
                  // mini-map tap-to-pan feature is not relevant
                  // mid-drag.
                  if (flat.persons.length > 30 && !rearrangeMode)
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
                  // v5.25 (distraction-free Rearrange): hide during
                  // Rearrange mode so it doesn't clutter the screen
                  // mid-drag and risk accidental taps.
                  if (kEnableGraphShareExport && !rearrangeMode)
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

  // v5.x (anchor-centering fix): SHARED centering helper used by BOTH
  // the initial-load _maybeFrame AND the recenter _maybeRunPending
  // ResetView. This ensures both paths produce IDENTICAL centering —
  // no drift or inconsistency between the two, as the user requires.
  //
  // Computes the camera pan + zoom so the anchor node's visual circle
  // center maps to the EXACT center of the VISIBLE DRAWABLE CANVAS
  // (accounting for the bottom UI chrome — toolbar + stats panel —
  // that overlays the canvas). The "center" is:
  //   visibleCenterY = (viewportHeight - bottomChromeHeight) / 2
  //
  // NOT the full viewport center (viewportHeight / 2) which would put
  // the anchor behind the bottom toolbar / stats panel.
  //
  // The zoom level is computed to fit the proximity set's bounding box
  // around the anchor (so first-degree relationships are visible),
  // clamped to [0.35, 1.3] for readability.

  ({double panX, double panY, double zoom}) _computeAnchorCenteredCamera({
    required Offset anchorPos,
    required Size viewportSize,
    required double bottomChrome,
    required Map<String, Offset> allPositions,
  }) {
    // The visual circle center in graph space (the circle sits at
    // the top of the node's Column, offset by _kCircleCenterYOffset
    // from the box center).
    final focusCircleCenter = Offset(
      anchorPos.dx,
      anchorPos.dy + _kCircleCenterYOffset,
    );

    // Compute a zoom level that fits the proximity set's bounding box
    // around the anchor. At zoom 1.0, only the anchor is visible
    // because the canvas is large. We zoom OUT so the anchor + its
    // neighbors are all visible.
    double maxDistX = 0;
    double maxDistY = 0;
    for (final pos in allPositions.values) {
      final dx = (pos.dx - anchorPos.dx).abs();
      final dy = (pos.dy - anchorPos.dy).abs();
      if (dx > maxDistX) maxDistX = dx;
      if (dy > maxDistY) maxDistY = dy;
    }
    const kFramePadding = 160.0;
    // Use the VISIBLE canvas height (excluding bottom chrome) for
    // the Y zoom fit so the graph fills the drawable area, not the
    // area behind the toolbar.
    final visibleHeight = viewportSize.height - bottomChrome;
    final targetZoomX =
        (viewportSize.width - kFramePadding) / (2 * maxDistX + 1);
    final targetZoomY =
        (visibleHeight - kFramePadding) / (2 * maxDistY + 1);
    var fitZoom = targetZoomX < targetZoomY ? targetZoomX : targetZoomY;
    if (fitZoom > 1.3) fitZoom = 1.3;
    if (fitZoom < 0.35) fitZoom = 0.35;

    // The VISIBLE drawable canvas center (accounting for bottom
    // chrome). The X center is the full viewport width / 2 (no side
    // chrome on the graph screen). The Y center is the midpoint of
    // the visible canvas area [0, viewportHeight - bottomChrome].
    final visibleCenterX = viewportSize.width / 2;
    final visibleCenterY = (viewportSize.height - bottomChrome) / 2;

    // Pan so the focus node's visual circle center lands at the
    // visible canvas center.
    final targetPanX = visibleCenterX - (focusCircleCenter.dx * fitZoom);
    final targetPanY = visibleCenterY - (focusCircleCenter.dy * fitZoom);

    return (panX: targetPanX, panY: targetPanY, zoom: fitZoom);
  }

  /// v5.75: Centers the graph on the VIEWER'S OWN NODE on fresh load.
  ///
  /// Previously, _maybeFrame called _camera.initialFitOnce which centers on
  /// the BOUNDING BOX of all nodes — putting the viewer's node off-center
  /// (often in the top-left corner). The user reported "nodes appear
  /// positioned toward the top-left corner instead of being centered."
  ///
  /// The fix: after the initial bounding-box fit (which sets a reasonable
  /// zoom level), if the viewer's Person ID is resolved, re-center the
  /// camera on the viewer's node position using _camera.resetView (the
  /// same method used by the "Reset View" button). This puts the "You"
  /// node dead-center on screen, with immediately-connected nodes
  /// visible around it.
  ///
  /// If viewerPersonId is null (unlinked user), falls back to the
  /// bounding-box fit (the existing behavior).
  /// v5.116 (Task 5): ALWAYS center on the anchor at zoom 1.0.
  ///
  /// Previously this did two steps:
  ///   1. initialFitOnce (fit ALL positions to viewport → very low zoom)
  ///   2. resetView (center on viewer at zoom 1.0, IF viewerPersonId != null)
  ///
  /// The problem: if viewerPersonId was null (or not in positions), step 2
  /// was skipped, leaving the anchor at the top edge of a zoomed-out view.
  ///
  /// The fix: ALWAYS center on the anchor at zoom 1.0, using the same
  /// resetView math. The anchor is determined by: viewer's node →
  /// isAnchor person → first person in the layout. This is the same
  /// fallback chain used in graphLayoutProvider.
  ///
  /// fitToView-style whole-tree framing is NOT used on first load anymore.
  /// It's reserved for an explicit user action (e.g. a future "Fit All"
  /// button). The initialFitOnce method still exists for that purpose.
  Future<void> _maybeFrame(
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) async {
    if (_framed) return;
    if (_viewportSize.width <= 0 || _viewportSize.height <= 0) return;
    if (layout.positions.isEmpty) return;
    _framed = true;

    // Determine the anchor position: viewer → isAnchor → first person.
    Offset? anchorPos;
    if (viewerPersonId != null) {
      anchorPos = layout.positions[viewerPersonId];
    }
    if (anchorPos == null) {
      // Fall back to the isAnchor person.
      for (final p in flat.persons) {
        if (p['isAnchor'] == true) {
          final id = p['id'] as String?;
          if (id != null) {
            anchorPos = layout.positions[id];
            if (anchorPos != null) break;
          }
        }
      }
    }
    if (anchorPos == null && layout.positions.isNotEmpty) {
      // Last resort: first person in the layout.
      anchorPos = layout.positions.values.first;
    }

    if (anchorPos != null) {
      // v5.x (anchor-centering fix): use the SHARED centering helper
      // so the initial load produces IDENTICAL centering to the
      // recenter button — no drift or inconsistency between the two.
      // The helper accounts for the bottom UI chrome (toolbar + stats
      // panel) that overlays the canvas, so the anchor maps to the
      // center of the VISIBLE drawable canvas, not the full screen
      // bounds. On initial load, snap INSTANTLY (1ms) so the user
      // never sees an off-center initial state.
      final cam = _computeAnchorCenteredCamera(
        anchorPos: anchorPos,
        viewportSize: _viewportSize,
        bottomChrome: widget.bottomChromeHeight,
        allPositions: layout.positions,
      );

      _camera.animateTo(
        cam.panX,
        cam.panY,
        cam.zoom,
        duration: const Duration(milliseconds: 1),
        curve: Curves.linear,
      );

      // v5.x (progressive-load fix): record the anchor's position so
      // the build loop can detect when it changes (because more data
      // loaded and the layout was recomputed) and re-center.
      _lastFramedAnchorPos = anchorPos;
    } else {
      // No positions at all — fall back to the old bounding-box fit.
      _camera.initialFitOnce(layout.positions, _viewportSize);
    }

    _culler.invalidate();
    if (mounted) setState(() {});
  }

  /// v5.x (progressive-load fix): Detects when the anchor node's layout
  /// position has changed since the last camera centering (because
  /// progressive data loading completed and the layout was recomputed
  /// with the full dataset). When the anchor drifts AND the user hasn't
  /// manually interacted with the camera, re-center automatically.
  ///
  /// This is the fix for the bug where the anchor node is visible for
  /// 3-5 seconds after open, then disappears when the full dataset
  /// finishes loading and the layout recalculates — the old code only
  /// centered once (_framed = true, never runs again), so the anchor's
  /// new position was off-screen with no camera follow.
  ///
  /// The threshold for "meaningful change" is 5px — small enough to
  /// catch real layout shifts, large enough to avoid re-centering on
  /// sub-pixel rounding noise.
  void _maybeRecenterOnAnchorDrift(
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) {
    if (_lastFramedAnchorPos == null) return; // not framed yet
    if (layout.positions.isEmpty) return;

    // Resolve the anchor's current position (same priority chain as
    // _maybeFrame: viewer → isAnchor → first person).
    Offset? currentAnchorPos;
    if (viewerPersonId != null) {
      currentAnchorPos = layout.positions[viewerPersonId];
    }
    if (currentAnchorPos == null) {
      final anchorId = _SubtreeMethods._findAnchorId(flat, viewerPersonId);
      if (anchorId != null) {
        currentAnchorPos = layout.positions[anchorId];
      }
    }
    if (currentAnchorPos == null && layout.positions.isNotEmpty) {
      currentAnchorPos = layout.positions.values.first;
    }
    if (currentAnchorPos == null) return;

    // Compare against the last-framed position. If the anchor moved
    // meaningfully (> 5px), re-center.
    const double kDriftThreshold = 5.0;
    final drift = (currentAnchorPos - _lastFramedAnchorPos!).distance;
    if (drift < kDriftThreshold) return; // no meaningful drift

    // The anchor drifted — re-center the camera on the new position.
    // Use the SAME shared helper as _maybeFrame and the recenter
    // button, so all three produce identical centering. Snap
    // instantly (1ms) — this is a background re-centering, not a
    // user-initiated action, so no animation is needed.
    final cam = _computeAnchorCenteredCamera(
      anchorPos: currentAnchorPos,
      viewportSize: _viewportSize,
      bottomChrome: widget.bottomChromeHeight,
      allPositions: layout.positions,
    );

    _camera.animateTo(
      cam.panX,
      cam.panY,
      cam.zoom,
      duration: const Duration(milliseconds: 1),
      curve: Curves.linear,
    );

    // Record the new position so we don't re-center again until the
    // NEXT layout change.
    _lastFramedAnchorPos = currentAnchorPos;
  }

  /// v4.16: _onLayoutChanged is now a NO-OP.
  /// Previously this called recenterIfNeeded() which forced the camera back
  /// after panning. With free panning enabled, no forced recentering.
  void _onLayoutChanged(GraphLayoutResult layout) {
    // No-op — free panning, no forced recentering
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

    // v5.28 Fix 4a: Clear ALL personal layout overrides so positions
    // snap back to auto-layout instantly — no stale saved positions
    // remain. Without this clear, the reset animation + resetView
    // would center on the anchor's auto-layout position, which may
    // differ from where it's currently visually displayed if overrides
    // exist. Clearing the live override maps ensures the next build's
    // effectivePositions uses pure auto-layout for every node + edge,
    // so the anchor position passed to resetView matches what's
    // rendered on screen.
    _rearrangeLiveNodeOverrides = const {};
    _rearrangeLiveEdgeWaypoints = const {};
    _rearrangeDragRevision++;

    // v5.x (anchor-centering fix): use the SAME shared centering
    // helper as _maybeFrame (initial load). This ensures the recenter
    // button produces IDENTICAL centering to the initial load — no
    // drift or inconsistency between the two, as the user requires.
    // The previous version called _camera.resetView which used zoom
    // 1.0 (hardcoded) and centered on the full viewport (not
    // accounting for bottom chrome). Now both paths use
    // _computeAnchorCenteredCamera for consistent centering + a
    // zoom that fits the proximity set.
    final bool reduced = MediaQuery.disableAnimationsOf(context);
    final cam = _computeAnchorCenteredCamera(
      anchorPos: focusPosition,
      viewportSize: _viewportSize,
      bottomChrome: widget.bottomChromeHeight,
      allPositions: layout.positions,
    );

    if (reduced) {
      _camera.animateTo(
        cam.panX,
        cam.panY,
        cam.zoom,
        duration: const Duration(milliseconds: 1),
        curve: Curves.linear,
      );
    } else {
      // Smooth animated transition (the user tapped recenter, so
      // they EXPECT to see the camera move).
      _camera.animateTo(
        cam.panX,
        cam.panY,
        cam.zoom,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }

    // v5.x (progressive-load fix): record the anchor's position so the
    // build loop can detect future drift. Also reset the
    // _userHasInteractedWithCamera flag — a manual recenter is the
    // user saying "put me back on the anchor", so we re-enable
    // auto-centering until the next manual pan/zoom.
    _lastFramedAnchorPos = focusPosition;
    _userHasInteractedWithCamera = false;
    _culler.invalidate();
  }

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
  Color _dotColor(String? gender, bool isAnchor, {KinshipEdgeCategory? category, Map<String, dynamic>? customColors, bool isViewer = false}) {
    // v5.71 (VIEWER PERSPECTIVE): ONLY the viewer's own node uses the
    // "self" color (green). The family creator/anchor no longer gets
    // green automatically — when a non-creator member logs in, they
    // should see THEIR OWN node as green, and the family creator's
    // node should be colored by its relationship category (just like
    // every other node).
    //
    // Previously (v5.60), the condition was `if (isViewer || isAnchor)`
    // which caused TWO green nodes when a non-creator was viewing:
    // their own node + the anchor's node. This was confusing — it
    // looked like there were two "You" nodes. Now only the actual
    // viewer gets green.
    if (isViewer) return KinshipEdgeColors.self;
    // v83: If custom colors are provided, use the custom node color
    if (customColors != null && customColors['nodeColor'] != null) {
      return Color(customColors['nodeColor'] as int);
    }
    // v69: Use the authoritative category directly — no string round-trip.
    if (category != null && category != KinshipEdgeCategory.self) {
      return KinshipEdgeStyleResolver.styleForCategory(category).color;
    }
    // Legacy fallback: gender-based color.
    // v5.107: Changed final fallback from Colors.grey to
    // KinshipEdgeColors.extended (slate #64748B) — the app's existing
    // tone reserved for extended/unclassified relatives. Colors.grey
    // is not part of the kinship palette and made nodes look broken.
    switch (gender) {
      case 'male':
        return Colors.blue;
      case 'female':
        return Colors.pink;
      default:
        return KinshipEdgeColors.extended;
    }
  }

  // v5.x (legend wiring fix): the _presentCategories helper that used
  // to live here has been removed. The legend is now rendered by the
  // parent family_graph_screen.dart, which has its own
  // _computePresentLegendCategories helper (combines server-computed
  // person kinshipCategory + relationship relationshipKey — more
  // accurate than this helper which only looked at relationshipKey).
  // Removing the dead helper eliminates the unused_element warning
  // and keeps the engine view's API surface focused on rendering.
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

// ═══════════════════════════════════════════════════════════════════════
// v5.65 (ISOLATE CONNECTIONS) — "Showing: X's connections" chip
// ═══════════════════════════════════════════════════════════════════════

/// A persistent chip shown at the top of the graph when isolation mode
/// is active. Displays the focused person's name + a "Show all" action
/// that clears the focus and restores full opacity to the entire graph.
///
/// Styled as a rounded pill with a dark background + orange accent,
/// matching the app's existing chip/badge design language. Tapping the
/// whole chip OR the X icon clears the focus.
class _IsolateConnectionsChip extends StatelessWidget {
  const _IsolateConnectionsChip({
    required this.personName,
    required this.onShowAll,
  });

  final String personName;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onShowAll,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_alt_rounded,
                size: 16,
                color: KinrelColors.orange,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.5,
                ),
                child: Text(
                  "Showing: $personName's connections",
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textWhite,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // "Show all" text button — tapping anywhere on the chip
              // (including this text) triggers onShowAll.
              Text(
                'Show all',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.tealAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              // X icon — also triggers onShowAll (same action).
              Icon(
                Icons.close_rounded,
                size: 16,
                color: KinrelColors.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// v5.76: TEMPORARY viewer debug banner
// v5.88: ENHANCED with DB query — shows ALL Persons' linkedUserIds in
//        the current family so we can immediately see which auth users
//        are linked to which Person nodes.
// ═══════════════════════════════════════════════════════════════════════

/// Shows the current auth user ID, resolved viewerPersonId, and which
/// Person node is getting isViewer=true. This helps diagnose why the
/// viewer-relative perspective is not working for non-creator accounts.
///
/// v5.88: Now also queries the DB for ALL Persons' linkedUserIds in the
/// current family, so we can see exactly which auth users are linked
/// to which Person nodes. This is critical for diagnosing the regression
/// where viewerPersonId is null even though the user is logged in.
class _ViewerDebugBanner extends StatefulWidget {
  const _ViewerDebugBanner({
    required this.authUserId,
    required this.authUserEmail,
    required this.viewerPersonId,
    required this.flat,
    required this.familyId,
    required this.supabaseClient,
  });

  final String? authUserId;
  final String? authUserEmail;
  final String? viewerPersonId;
  final FlatGraphResult? flat;
  final String familyId;
  final dynamic supabaseClient; // SupabaseClient?

  @override
  State<_ViewerDebugBanner> createState() => _ViewerDebugBannerState();
}

class _ViewerDebugBannerState extends State<_ViewerDebugBanner> {
  /// List of (personId, name, linkedUserId, isAnchor) tuples fetched
  /// from the DB. Null while loading, empty list if query failed.
  List<_PersonLinkInfo>? _personLinks;
  String? _fetchError;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchPersonLinks();
  }

  @override
  void didUpdateWidget(_ViewerDebugBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-fetch when auth user changes (so we can see the new user's link)
    if (oldWidget.authUserId != widget.authUserId ||
        oldWidget.familyId != widget.familyId) {
      _fetchPersonLinks();
    }
  }

  Future<void> _fetchPersonLinks() async {
    if (widget.supabaseClient == null) return;
    setState(() {
      _isLoading = true;
      _fetchError = null;
    });
    try {
      final response = await widget.supabaseClient
          .from('Person')
          .select('id,name,isAnchor,linkedUserId,gender')
          .eq('familyId', widget.familyId)
          .filter('deletedAt', 'is', null)
          .order('isAnchor', ascending: false)
          .order('name')
          .timeout(const Duration(seconds: 8));
      final rows = (response as List).map((r) {
        final m = r as Map<String, dynamic>;
        return _PersonLinkInfo(
          id: m['id'] as String?,
          name: m['name'] as String? ?? '?',
          isAnchor: m['isAnchor'] as bool? ?? false,
          linkedUserId: m['linkedUserId'] as String?,
          gender: m['gender'] as String?,
        );
      }).toList();
      if (mounted) {
        setState(() {
          _personLinks = rows;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchError = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Find which person in the flat data has isAnchor=true
    String? anchorPersonId;
    String? anchorName;
    String? viewerName;
    if (widget.flat != null) {
      for (final p in widget.flat!.persons) {
        final id = p['id'] as String?;
        final name = p['name'] as String? ?? '?';
        final isAnchor = p['isAnchor'] as bool? ?? false;
        if (isAnchor) {
          anchorPersonId = id;
          anchorName = name;
        }
        if (id == widget.viewerPersonId) {
          viewerName = name;
        }
      }
    }

    // Determine which auth user the anchor is linked to (from DB query)
    String? anchorLinkedUserId;
    int linkedCount = 0;
    if (_personLinks != null) {
      for (final p in _personLinks!) {
        if (p.isAnchor) {
          anchorLinkedUserId = p.linkedUserId;
        }
        if (p.linkedUserId != null && p.linkedUserId!.isNotEmpty) {
          linkedCount++;
        }
      }
    }

    // Check if the current auth user matches ANY person's linkedUserId
    final bool authUserIsLinkedToSomeone = _personLinks?.any(
          (p) => p.linkedUserId != null && p.linkedUserId == widget.authUserId,
        ) ??
        false;

    final bool viewerIsNull = widget.viewerPersonId == null;
    final bool authIsNull = widget.authUserId == null;

    // Status logic
    String statusText;
    Color statusColor;
    if (authIsNull) {
      statusText = 'AUTH NULL — auth state not initialized (v5.78 regression?)';
      statusColor = Colors.red;
    } else if (viewerIsNull && !authUserIsLinkedToSomeone) {
      statusText =
          'VIEWER NULL — no Person has linkedUserId == authUserId (DB link broken)';
      statusColor = Colors.amber;
    } else if (viewerIsNull && authUserIsLinkedToSomeone) {
      statusText =
          'VIEWER NULL but auth matches a Person.linkedUserId — viewerPersonIdProvider bug';
      statusColor = Colors.red;
    } else if (widget.viewerPersonId == anchorPersonId) {
      statusText = 'VIEWER == ANCHOR (viewer is the anchor — correct)';
      statusColor = Colors.green;
    } else {
      statusText = 'VIEWER != ANCHOR (different — correct!)';
      statusColor = Colors.green;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF1a1a2e),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'VIEWER DEBUG (v5.88)',
                style: TextStyle(
                  color: KinrelColors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              if (_isLoading)
                const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                  ),
                )
              else
                GestureDetector(
                  onTap: _fetchPersonLinks,
                  child: const Icon(Icons.refresh,
                      color: Colors.white54, size: 14),
                ),
            ],
          ),
          const SizedBox(height: 4),
          _debugLine('Auth User ID: ${widget.authUserId ?? "NULL"}'),
          _debugLine(
              'Auth Email: ${widget.authUserEmail ?? "NULL"}', color: Colors.cyan),
          _debugLine('Viewer Person ID: ${widget.viewerPersonId ?? "NULL"}'),
          _debugLine('Viewer Person Name: ${viewerName ?? "NULL"}'),
          _debugLine(
              'Anchor Person: ${anchorName ?? "NULL"} (${anchorPersonId?.substring(0, 8) ?? "NULL"})'),
          _debugLine(
              'Anchor linkedUserId: ${anchorLinkedUserId?.substring(0, 8) ?? "NULL"}',
              color: anchorLinkedUserId == null
                  ? Colors.red
                  : (anchorLinkedUserId == widget.authUserId
                      ? Colors.green
                      : Colors.amber)),
          _debugLine(
              'Persons with linkedUserId set: $linkedCount / ${_personLinks?.length ?? "?"}'),
          _debugLine(
              'Auth user matches a Person.linkedUserId: $authUserIsLinkedToSomeone',
              color: authUserIsLinkedToSomeone ? Colors.green : Colors.red),
          const SizedBox(height: 4),
          Text(
            'Status: $statusText',
            style: TextStyle(
              color: statusColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          if (_fetchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'DB fetch error: $_fetchError',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          // List all persons with their linkedUserIds
          if (_personLinks != null && _personLinks!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'ALL PERSONS (DB):',
              style: TextStyle(
                color: KinrelColors.orange.withValues(alpha: 0.8),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 2),
            ..._personLinks!.map((p) {
              final isViewerLink = p.linkedUserId == widget.authUserId &&
                  widget.authUserId != null;
              final isAnchorLink = p.isAnchor;
              return _debugLine(
                '${isAnchorLink ? "★" : " "} ${p.name.padRight(12).substring(0, 12)} | link=${p.linkedUserId?.substring(0, 8) ?? "NULL"}${isViewerLink ? " ← YOU" : ""}',
                color: isViewerLink
                    ? Colors.green
                    : (p.linkedUserId != null ? Colors.white : Colors.white24),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _debugLine(String text, {Color color = Colors.white70}) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontFamily: 'monospace',
      ),
    );
  }
}

/// Helper class for the person-link diagnostic dump.
class _PersonLinkInfo {
  const _PersonLinkInfo({
    required this.id,
    required this.name,
    required this.isAnchor,
    required this.linkedUserId,
    required this.gender,
  });
  final String? id;
  final String name;
  final bool isAnchor;
  final String? linkedUserId;
  final String? gender;
}
