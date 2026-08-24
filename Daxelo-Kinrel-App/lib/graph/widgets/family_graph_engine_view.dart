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
        selectedNodeProvider,
        unlinkedPersonIdsProvider; // v5.9
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
import '../../core/services/supabase_service.dart' show supabaseProvider, currentUserProvider;
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
  late final ExpandCollapseController _expandCollapse;
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
    _connectOnOpenController!.addListener(_onConnectOnOpenTick);

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
    _camera.removeListener(_onCameraChanged);
    _camera.dispose();
    _culler.dispose();
    _expandCollapse.dispose();
    _positionMemory.dispose();
    // v5.27 Task 1: dispose the reset animation controller.
    _resetController?.removeStatusListener(_onResetAnimationStatus);
    _resetController?.removeListener(_onResetAnimationTick);
    _resetController?.dispose();
    _resetController = null;
    // v5.27 Task 2: dispose the connect-on-open controller.
    _connectOnOpenController?.removeListener(_onConnectOnOpenTick);
    _connectOnOpenController?.detach();
    _connectOnOpenController?.dispose();
    _connectOnOpenController = null;
    // v5.30 Issue 2: dispose the load animation controller.
    _loadController?.removeStatusListener(_onLoadAnimationStatus);
    _loadController?.removeListener(_onLoadAnimationTick);
    _loadController?.dispose();
    _loadController = null;
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
    ref.read(graphFocusProvider.notifier).clearAll();
    // v5.74 (BUG 1 FIX): Clear the selectedNodeProvider on dispose.
    // This is a global StateProvider that survives screen exits —
    // without clearing it, a node selected in a prior session stays
    // "selected" (highlighted with a glow ring) when the user returns
    // to the graph, even though they didn't tap anything. This caused
    // the "Manish's node appears highlighted without being tapped" bug.
    ref.read(selectedNodeProvider.notifier).state = null;
    super.dispose();
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

  void _onConnectOnOpenTick() {
    if (!mounted) return;
    // Trigger a rebuild so the painter sees the new trace state
    // (currentEdgeId, traceProgress, completedEdgeIds).
    setState(() {});
  }

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
    // Propagate reduced-motion to the controller so it suppresses
    // per-step haptics (same pattern as the existing path trace).
    _connectOnOpenController!.reducedMotion = reduced;
    if (reduced) {
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
      _connectOnOpenController!.startTrace(
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
  Future<void> _maybeFrame(
    GraphLayoutResult layout,
    FlatGraphResult flat,
    String? viewerPersonId,
  ) async {
    if (_framed) return;
    if (_viewportSize.width <= 0 || _viewportSize.height <= 0) return;
    if (layout.positions.isEmpty) return;
    _framed = true;

    // Step 1: Do the initial bounding-box fit to set a reasonable zoom
    // level. This ensures all nodes are visible at a comfortable scale.
    _camera.initialFitOnce(layout.positions, _viewportSize);

    // Step 2 (v5.75): If the viewer's Person ID is resolved, re-center
    // on the viewer's node. This overrides the bounding-box center with
    // the viewer's node position, putting "You" dead-center on screen.
    if (viewerPersonId != null) {
      final viewerPos = layout.positions[viewerPersonId];
      if (viewerPos != null) {
        final bool reduced = MediaQuery.disableAnimationsOf(context);
        _camera.resetView(
          focusNodePosition: viewerPos,
          circleCenterYOffset: _kCircleCenterYOffset,
          viewportSize: _viewportSize,
          reducedMotion: reduced,
        );
      }
    }

    _culler.invalidate();
    if (mounted) setState(() {});
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
