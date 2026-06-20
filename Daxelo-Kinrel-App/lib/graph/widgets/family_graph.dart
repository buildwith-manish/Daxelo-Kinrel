// lib/graph/widgets/family_graph.dart
//
// DAXELO KINREL — Family Graph Widget (V2.1 Redesign)
//
// The top-level graph container that replaces the existing graph canvas.
//
// Unidirectional data flow:
//   User Action → Intent → Interaction → Engine → Rendering → Presentation
//
// Integrates:
//   - CameraController for pan/zoom/focus (graph/interaction/)
//   - ExpandCollapseController for progressive disclosure (graph/interaction/)
//   - ViewportCuller for virtualization (graph/rendering/)
//   - NodeRenderCoordinator for RepaintBoundary management (graph/rendering/)
//   - EdgePathCache for path caching (graph/rendering/)
//   - PermissionValidator for visibility filtering (graph/security/)
//   - AnalyticsTracker for event tracking (graph/analytics/)
//   - FallbackManager for engine switching (graph/engine/)
//   - PositionMemory for camera persistence (graph/data/)

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/services/graph_layout_service.dart';
import '../../features/family/presentation/add_person_sheet.dart';
import '../../features/family/presentation/providers/family_graph_provider.dart';
import '../analytics/analytics_tracker.dart';
import '../data/family_graph_repository.dart' show GraphData, GraphEdgeData;
import '../data/position_memory.dart';
import '../interaction/camera_controller.dart';
import '../rendering/viewport_culler.dart';
import 'edge_midpoint_layer.dart';
import 'empty_state.dart';
import 'filter_panel.dart';
import 'graph_error_state.dart';
import 'graph_gesture_math.dart';
import 'graph_legend.dart';
import 'graph_node.dart';
import 'graph_node_state.dart';
import 'graph_quick_actions.dart';
import 'graph_relationship_labels.dart';
import 'graph_web_gestures.dart';
// v8: GraphPanZoom import removed — now using Flutter's built-in InteractiveViewer
import 'onboarding_flow.dart';
import 'relationship_edge.dart';
import 'relationship_info_sheet.dart';
import 'search_bar.dart';

// ═══════════════════════════════════════════════════════════════════════
// FAMILY GRAPH WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// The main graph widget that replaces the existing graph canvas.
///
/// Combines all layers (security, analytics, rendering) into a single
/// widget with unidirectional data flow and optimized rendering via
/// RepaintBoundary and viewport culling.
///
/// Layout structure:
/// ```
/// Stack(
///   RepaintBoundary(  // Camera transform layer
///     Transform(pan + zoom)
///       RepaintBoundary(  // Edge layer
///         CustomPaint(painter: RelationshipEdge)
///       )
///       ...visible nodes wrapped in RepaintBoundary(  // Node layer
///         GraphNode
///       )
///   )
///   RepaintBoundary(SearchBar)
///   RepaintBoundary(ControlBar)
///   EmptyState (conditional)
/// )
/// ```
class FamilyGraphWidget extends ConsumerStatefulWidget {
  const FamilyGraphWidget({
    super.key,
    required this.familyId,
    required this.familyName,
    this.externalTransformController,
    this.graphData,
  });

  /// The family ID for data fetching and permission checks.
  final String familyId;

  /// The family display name.
  final String familyName;

  /// Optional external TransformationController so the parent screen
  /// can control zoom/pan programmatically. When provided, the widget
  /// uses it instead of creating its own, and will NOT dispose it.
  final TransformationController? externalTransformController;

  /// Optional pre-fetched graph data from the parent screen.
  /// When provided, the widget uses this data instead of watching
  /// the familyGraphProvider, avoiding double-fetching and ensuring
  /// data consistency between the parent screen and the graph widget.
  final FlatGraphResult? graphData;

  @override
  ConsumerState<FamilyGraphWidget> createState() => _FamilyGraphWidgetState();
}

class _FamilyGraphWidgetState extends ConsumerState<FamilyGraphWidget>
    with SingleTickerProviderStateMixin {
  // ── Controllers ────────────────────────────────────────────────────

  late final CameraController _cameraController;
  ViewportCuller? _viewportCuller;
  late final PositionMemory _positionMemory;
  late final TransformationController _transformationController;

  // ── State ──────────────────────────────────────────────────────────

  /// Computed layout result.
  GraphLayoutResult? _layoutResult;

  /// Map of person ID → PersonData for quick lookups.
  final Map<String, GraphPersonData> _personMap = {};

  /// List of relationship edge data.
  /// NOT final — must be reassigned as a new list each build so that
  /// [RelationshipEdge.shouldRepaint] detects the change (reference
  /// equality fails when the same list is mutated in-place via
  /// clear + add, causing edges to never repaint after the first frame).
  List<GraphEdgeData> _edges = [];

  /// Currently selected node ID.
  String? _selectedNodeId;

  /// Currently selected edge ID.
  String? _selectedEdgeId;

  /// Currently focused node ID (pulsing glow).
  String? _focusedNodeId;

  /// Currently highlighted generation index.
  int? _highlightedGeneration;

  /// Set of visible node IDs (viewport culling).
  Set<String> _visibleNodeIds = {};

  /// Set of blocked node IDs from permission filter.
  Set<String> _blockedNodeIds = {};

  /// Set of anonymous node IDs from permission filter.
  Set<String> _anonymousNodeIds = {};

  /// Whether the search bar is visible.
  bool _searchBarVisible = false;

  /// Whether the filter panel is visible.
  bool _filterVisible = false;

  /// Whether the legend panel is visible.
  bool _legendVisible = false;

  // _showNoEdgesBanner and _realEdgesCount were removed in v4 along
  // with the "No relationships in database" warning banner. Kept as
  // comments for git-blame archaeology.

  /// Current filter state.
  FilterState _currentFilter = const FilterState();

  /// Debounce timer for camera position saving.
  Timer? _cameraSaveDebounce;

  /// Stopwatch for graph open time tracking.
  final Stopwatch _openStopwatch = Stopwatch();

  /// Current viewport size for culling.
  Size _viewportSize = Size.zero;

  /// Whether the initial camera centering on the anchor node has been done.
  bool _initialCenterDone = false;

  /// v26 BUG-FIX (blank screen):
  /// Fingerprint of the last graph layout we successfully rendered with
  /// auto-center applied. When the graph data changes (members added/
  /// removed, relationships changed), the fingerprint changes and we
  /// force `_initialCenterDone = false` so the next build re-applies the
  /// auto-centering transform.
  ///
  /// Without this, a stale transform restored from SharedPreferences
  /// (or a transform left over from a previous layout with different
  /// canvas dimensions) would be honored via the
  /// `hasExistingTransform` branch in `_buildGraphStack`, leaving the
  /// canvas rendered at coordinates outside the viewport → blank screen.
  String _previousGraphFingerprint = '';

  /// Whether onboarding has been permanently dismissed for this family.
  /// This is a local cache so we don't need to check the async provider
  /// on every build, preventing onboarding flashes.
  bool _onboardingLocallyDismissed = false;

  // v10 Fix #3c: Flags to prevent feedback loops between
  // CameraController and TransformationController.
  bool _transformationControllerChangeFromExternal = false;
  bool _cameraControllerChangeFromInternal = false;

  // ── Gesture state (ScaleGestureRecognizer-based pinch/pan) ─────────

  double _gestureStartScale = 1.0;
  Offset _gestureStartTranslation = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;

  // Fling / momentum state
  late final AnimationController _flingController;
  FrictionSimulation? _flingSimX;
  FrictionSimulation? _flingSimY;
  double _flingScale = 1.0;

  // ── Constants ──────────────────────────────────────────────────────

  static const double _nodeWidth = 72.0;
  static const double _nodeHeight = 72.0;

  // ── Lifecycle ──────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _positionMemory = PositionMemory();
    _cameraController = CameraController(positionMemory: _positionMemory);
    _transformationController =
        widget.externalTransformController ?? TransformationController();
    _transformationController.addListener(_onTransformChanged);
    _openStopwatch.start();

    // Fling / momentum animation controller (unbounded — the fling
    // simulation drives it from 0→1 with a friction curve).
    _flingController = AnimationController(vsync: this)
      ..addListener(_onFlingTick);

    // v10 Fix #3c: Bridge CameraController output to TransformationController.
    // When CameraController.focusOnNode animates, it calls notifyListeners(),
    // which fires this listener. We push the new matrix into the
    // TransformationController so the double-tap-to-focus actually works.
    // The _transformationControllerChangeFromExternal flag prevents feedback
    // loops (TransformationController listener → CameraController → back).
    _cameraController.addListener(() {
      if (!mounted) return;
      if (!_transformationControllerChangeFromExternal) {
        _cameraControllerChangeFromInternal = true;
        _transformationController.value = _cameraController.transformMatrix;
        _cameraControllerChangeFromInternal = false;
      }
    });

    // Auto-dismiss onboarding for existing users on first build
    _autoDismissOnboardingIfExistingUser();
  }

  /// Automatically dismisses onboarding for families that already have
  /// members. Only brand-new users with 0 members should see onboarding.
  Future<void> _autoDismissOnboardingIfExistingUser() async {
    try {
      final dismissed = await OnboardingPrefs.load();
      if (dismissed.contains(widget.familyId)) {
        // Already dismissed — set local flag to prevent any flash
        if (mounted) {
          setState(() => _onboardingLocallyDismissed = true);
        }
      }
    } catch (_) {
      // Silently ignore — onboarding will still be gated in build()
    }
  }

  @override
  void didUpdateWidget(covariant FamilyGraphWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // v21 FIX: Reset centering when familyId changes OR when graphData
    // changes (new members added). The old code only reset on familyId
    // change, so adding a member to the same family didn't re-center.
    if (oldWidget.familyId != widget.familyId) {
      _initialCenterDone = false;
      _viewportCuller = null;
      _onboardingLocallyDismissed = false;
    }
    // v21: Also reset centering if graphData changed (new members added)
    if (oldWidget.graphData != widget.graphData && widget.graphData != null) {
      _initialCenterDone = false;
    }
    // Detect when the external transform controller is reset to identity
    // (e.g., user tapped "Center on Root" in the parent screen) and
    // trigger re-centering on the anchor node.
    if (widget.externalTransformController != null &&
        widget.externalTransformController!.value.isIdentity() &&
        _initialCenterDone) {
      _initialCenterDone = false;
    }
  }

  @override
  void dispose() {
    _cameraSaveDebounce?.cancel();
    _openStopwatch.stop();
    _flingController.dispose();
    _transformationController.removeListener(_onTransformChanged);
    // Only dispose the transformation controller if we created it
    if (widget.externalTransformController == null) {
      _transformationController.dispose();
    }
    _cameraController.dispose();
    _viewportCuller?.dispose();
    super.dispose();
  }

  // ── Transform Change Handler ───────────────────────────────────────

  void _onTransformChanged() {
    if (!mounted) return;

    // v10 Fix #3c: Set flag so the CameraController listener doesn't
    // fire when the change came from the user manually panning/zooming
    // (which updates the TransformationController directly).
    if (!_cameraControllerChangeFromInternal) {
      _transformationControllerChangeFromExternal = true;
    }

    final zoom = _currentZoom;
    final pan = _currentPan;

    // Update viewport culling using the existing ViewportCuller
    if (_viewportSize != Size.zero && _layoutResult != null) {
      // For small graphs (<=30 nodes), skip culling entirely — always
      // show all nodes. This prevents the "only creator visible" bug
      // on small families where viewport culling can be too aggressive.
      final totalNodeCount = _layoutResult!.positions.length;
      if (totalNodeCount <= 30) {
        final allIds = Set<String>.from(_layoutResult!.positions.keys);
        if (!GraphRelationshipLabels.setsEqual(allIds, _visibleNodeIds)) {
          setState(() {
            _visibleNodeIds = allIds;
          });
        }
      } else {
        final viewport = Rect.fromLTWH(
          -pan.dx / zoom,
          -pan.dy / zoom,
          _viewportSize.width / zoom,
          _viewportSize.height / zoom,
        );

        // Initialize culler if needed (larger buffer for smoother initial visibility)
        if (_viewportCuller == null) {
          _viewportCuller = ViewportCuller(
            viewport: viewport,
            bufferPixels: 600.0,
          );
        }

        final nodeSizes = <String, Size>{
          for (final id in _layoutResult!.positions.keys)
            id: const Size(_nodeWidth, _nodeHeight),
        };

        final newVisible = _viewportCuller!.cull(
          _layoutResult!.positions,
          nodeSizes,
          viewport,
        );

        // Always force-include the anchor node so it's never culled
        final anchorId = _personMap.values
            .firstWhere((p) => p.isAnchor, orElse: () => GraphPersonData.empty())
            .id;
        if (anchorId.isNotEmpty) newVisible.add(anchorId);

        if (!GraphRelationshipLabels.setsEqual(newVisible, _visibleNodeIds)) {
          setState(() {
            _visibleNodeIds = newVisible;
          });
        }
      }
    }

    // Debounced camera position save (500ms)
    _cameraSaveDebounce?.cancel();
    _cameraSaveDebounce = Timer(const Duration(milliseconds: 500), () {
      _positionMemory.savePosition(
        widget.familyId,
        panX: pan.dx,
        panY: pan.dy,
        zoomLevel: zoom,
      );
    });

    // v10 Fix #3c: Reset the flag after handling the external change.
    _transformationControllerChangeFromExternal = false;
  }

  /// Gets the current zoom level from the transformation matrix.
  double get _currentZoom {
    return _transformationController.value.getMaxScaleOnAxis();
  }

  /// Gets the current pan offset from the transformation matrix.
  Offset get _currentPan {
    final m = _transformationController.value;
    return Offset(m.getTranslation().x, m.getTranslation().y);
  }

  // ── Gesture Handlers ───────────────────────────────────────────────
  //
  // Uses a GestureDetector with ScaleGestureRecognizer for pinch-to-zoom
  // and one-finger pan. Child nodes use HitTestBehavior.translucent, so
  // both the node's TapGestureRecognizer and our ScaleGestureRecognizer
  // compete in the same arena:
  //   • Single-finger tap → TapGestureRecognizer wins ✓
  //   • Two-finger pinch → ScaleGestureRecognizer wins (2 pointers) ✓
  //   • One-finger drag → ScaleGestureRecognizer (1-pointer pan) ✓
  // The parent GestureDetector has NO onDoubleTap — this is critical.
  // Having DoubleTapGestureRecognizer on the parent delays tap resolution
  // and interferes with ScaleGestureRecognizer (confirmed GraphPanZoom v4.1).

  void _onScaleStart(ScaleStartDetails details) {
    // Stop any in-progress fling
    _flingController.stop();
    _flingSimX = null;
    _flingSimY = null;

    final matrix = _transformationController.value;
    _gestureStartScale = matrix.getMaxScaleOnAxis();
    _gestureStartTranslation = Offset(
      matrix.getTranslation().x,
      matrix.getTranslation().y,
    );
    // Use localFocalPoint (GestureDetector-local coords), NOT focalPoint
    // (screen-global). Mixing coordinate spaces causes jumps.
    _gestureStartFocalPoint = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final newScale = (_gestureStartScale * details.scale)
        .clamp(0.05, 5.0);

    final focalNow = details.localFocalPoint;
    final scaleRatio =
        _gestureStartScale == 0 ? 1.0 : newScale / _gestureStartScale;

    // Focal-point-anchored zoom + pan (single formula handles all cases):
    //   1. Pinch in place: focalNow ≈ focalStart → canvas zooms around focal ✓
    //   2. Two-finger pan: scaleRatio ≈ 1 → canvas tracks focal movement ✓
    //   3. Combined: both terms contribute ✓
    final newTranslation = Offset(
      focalNow.dx +
          (_gestureStartTranslation.dx - _gestureStartFocalPoint.dx) *
              scaleRatio,
      focalNow.dy +
          (_gestureStartTranslation.dy - _gestureStartFocalPoint.dy) *
              scaleRatio,
    );

    _transformationController.value = Matrix4.identity()
      ..translate(newTranslation.dx, newTranslation.dy)
      ..scale(newScale);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // ── Momentum / fling ──────────────────────────────────────────────
    // If the user lifted their finger(s) while panning quickly, apply a
    // decelerating fling so the graph glides to a stop — map-app feel.
    final velocity = details.velocity.pixelsPerSecond;
    final speed = velocity.distance;
    if (speed < 50) return; // Too slow — skip fling

    final matrix = _transformationController.value;
    _flingScale = matrix.getMaxScaleOnAxis();
    final startTx = matrix.getTranslation().x;
    final startTy = matrix.getTranslation().y;

    // FrictionSimulation: drag=0.015 → ~1–2 second glide (Google Maps feel).
    // x(t) = position at time t (seconds); finalX = settled position.
    _flingSimX = FrictionSimulation(0.015, startTx, velocity.dx);
    _flingSimY = FrictionSimulation(0.015, startTy, velocity.dy);

    // Compute how long until both axes settle, capped at 2.5 s.
    final endTime = [
      _flingSimX!.timeAtX(_flingSimX!.finalX),
      _flingSimY!.timeAtX(_flingSimY!.finalX),
    ].reduce((a, b) => a > b ? a : b).clamp(0.0, 2.5);

    if (endTime <= 0) return;

    _flingController.duration = Duration(
      milliseconds: (endTime * 1000).round(),
    );
    // forward(from:0) → controller goes 0→1 over `duration` seconds.
    // _onFlingTick maps controller.value * endTime → simulation seconds.
    _flingController.forward(from: 0.0);
  }

  void _onFlingTick() {
    if (_flingSimX == null || !mounted) return;
    // Map normalized controller value (0→1) to real time in seconds.
    final durationSecs =
        (_flingController.duration?.inMilliseconds ?? 0) / 1000.0;
    final t = _flingController.value * durationSecs;
    _transformationController.value = Matrix4.identity()
      ..translate(_flingSimX!.x(t), _flingSimY!.x(t))
      ..scale(_flingScale);
  }

  void _onNodeTap(String personId) {
    final tracker = ref.read(analyticsTrackerProvider);
    final person = _personMap[personId];
    if (person != null) {
      tracker.trackNodeClick(
        personId,
        person.relationshipKey ?? 'unknown',
        person.disclosureLevel,
      );
    }

    setState(() {
      _selectedNodeId = _selectedNodeId == personId ? null : personId;
      _selectedEdgeId = null;
    });
  }

  void _onNodeLongPress(String personId) {
    final person = _personMap[personId];
    if (person != null) {
      GraphQuickActions.show(context, person);
    }
  }

  void _onNodeDoubleTap(String personId) {
    // Focus camera on this node
    final pos = _layoutResult?.positions[personId];
    if (pos != null) {
      _cameraController.focusOnNode(personId, pos);
      ref.read(analyticsTrackerProvider).trackCameraFocus(personId, 400);
    }

    setState(() {
      _focusedNodeId = _focusedNodeId == personId ? null : personId;
    });
  }

  void _onEdgeTap(String edgeId) {
    setState(() {
      _selectedEdgeId = _selectedEdgeId == edgeId ? null : edgeId;
      _selectedNodeId = null;
    });
  }

  /// Called when the user taps the midpoint dot on a connection line.
  /// Highlights the edge and shows the relationship info bottom sheet.
  void _onEdgeMidpointTap(String edgeId) {
    final edge = _edges.firstWhere(
      (e) => e.id == edgeId,
      orElse: () => const GraphEdgeData(
        id: '', sourceId: '', targetId: '', relationshipKey: '',
      ),
    );
    if (edge.id.isEmpty) return;

    final source = _personMap[edge.sourceId];
    final target = _personMap[edge.targetId];
    if (source == null || target == null) return;

    // Highlight the edge visually while the sheet is open
    setState(() {
      _selectedEdgeId = edgeId;
      _selectedNodeId = null;
    });

    RelationshipInfoSheet.show(
      context,
      sourceId: edge.sourceId,
      sourceName: source.name,
      sourceGender: source.gender,
      targetId: edge.targetId,
      targetName: target.name,
      targetGender: target.gender,
      relationshipKey: edge.relationshipKey,
    ).then((_) {
      // Clear selection when sheet is dismissed
      if (mounted) {
        setState(() => _selectedEdgeId = null);
      }
    });
  }

  // ── Quick Actions Bottom Sheet ─────────────────────────────────────
  // v31: _showQuickActions extracted to GraphQuickActions.show().
  // The _onNodeLongPress handler now calls GraphQuickActions.show directly.

  // ── Add Member Sheet Handler ──────────────────────────────────────

  /// Opens the AddPersonSheet and invalidates graph data when it closes
  /// to ensure newly added members are immediately visible.
  Future<void> _openAddMemberSheet() async {
    await AddPersonSheet.show(context, familyId: widget.familyId);
    // Invalidate graph data after the sheet closes to show new members
    if (mounted) {
      ref.invalidate(familyGraphProvider(widget.familyId));
      // Safety net: second refresh after delay for slow DB propagation
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          ref.invalidate(familyGraphProvider(widget.familyId));
        }
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Accessibility: reduced motion
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // If parent provided graphData, use it directly (no double-fetch).
    // Otherwise, fall back to watching the provider.
    final FlatGraphResult? effectiveGraphData = widget.graphData;

    if (effectiveGraphData != null) {
      return _buildFromGraphData(effectiveGraphData, reduceMotion);
    }

    // Watch graph data provider as fallback
    final graphAsync = ref.watch(familyGraphProvider(widget.familyId));

    return graphAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      ),
      error: (error, stack) => GraphErrorState(
        familyId: widget.familyId,
        error: error,
      ),
      data: (graphData) => _buildFromGraphData(graphData, reduceMotion),
    );
  }

  /// Builds the graph from resolved data, shared by both code paths.
  Widget _buildFromGraphData(FlatGraphResult graphData, bool reduceMotion) {
    final persons = graphData.toPersonDataList();

    if (persons.isEmpty) {
      // ── Onboarding for 0-member families ──
      // ONLY show onboarding for brand-new families that have never
      // been dismissed. Existing users (with members) NEVER see it.
      final dismissedAsync = ref.watch(onboardingDismissedProvider);
      final isDismissed = dismissedAsync.valueOrNull?.contains(widget.familyId) ?? true;

      if (!isDismissed && !_onboardingLocallyDismissed) {
        // First-time user with 0 members: show onboarding overlay
        return Stack(
          children: [
            EmptyState(
              familyId: widget.familyId,
              memberCount: 0,
              onAddMember: _openAddMemberSheet,
            ),
            OnboardingFlow(
              familyId: widget.familyId,
              memberCount: 0,
            ),
          ],
        );
      }

      return GraphEmptyStack(
        child: EmptyState(
          familyId: widget.familyId,
          memberCount: 0,
          onAddMember: _openAddMemberSheet,
        ),
      );
    }

    // ── Existing users with members: permanently dismiss onboarding ──
    // This ensures onboarding NEVER re-appears for families with members.
    if (persons.isNotEmpty && !_onboardingLocallyDismissed) {
      final dismissedAsync = ref.watch(onboardingDismissedProvider);
      final isDismissed = dismissedAsync.valueOrNull?.contains(widget.familyId) ?? true;
      if (!isDismissed) {
        // Persist dismissal so onboarding never re-appears
        ref.read(onboardingDismissedProvider.notifier).dismiss(widget.familyId);
      }
      // Set local flag so we don't keep reading the async provider
      _onboardingLocallyDismissed = true;
    }

    // Build person map and edges
    _personMap.clear();
    // Create a NEW list each build so RelationshipEdge.shouldRepaint
    // detects the change via reference equality. Mutating the same list
    // (clear + add) causes shouldRepaint to always return false because
    // oldDelegate.edges and edges are the same object.
    final newEdges = <GraphEdgeData>[];

    for (final p in persons) {
      _personMap[p.id] = GraphPersonData(
        id: p.id,
        name: p.name,
        gender: p.gender,
        generationIndex: p.generationIndex,
        isAnchor: p.isAnchor,
        photoUrl: p.photoUrl,
        isDeceased: p.isDeceased,
      );
    }

    final relationships = graphData.toRelationshipDataList();

    for (final r in relationships) {
      newEdges.add(GraphEdgeData(
        id: r.id,
        sourceId: r.fromPersonId,
        targetId: r.toPersonId,
        relationshipKey: r.relationshipKey,
      ));
    }

    // ── SYNTHETIC EDGE FALLBACK ──────────────────────────────────────
    // v14 Fix #2: REMOVED synthetic edge fallback entirely.
    // The synthetic 'extended' edges were causing:
    //   1. Nodes stacked in a vertical line (layout engine treated
    //      'extended' as same-generation = gen 0, stacking all orphans
    //      directly below the anchor)
    //   2. "Extended" label visible on node chips (confusing to users)
    //   3. Fake connections between members with no real relationship
    // Orphan nodes now sit at their proper generationIndex position
    // with no fake edge. If a user wants to connect them, they use
    // the Add Relative flow.

    _edges = newEdges;

    // Compute layout
    final graphPersons =
        persons.map((p) => p.toGraphPerson()).toList();
    final graphRelationships =
        relationships.map((r) => r.toGraphRelationship()).toList();

    final service = GraphLayoutService();
    _layoutResult = service.computeLayout(
      persons: graphPersons,
      relationships: graphRelationships,
    );

    if (_layoutResult == null || _layoutResult!.positions.isEmpty) {
      return GraphEmptyStack(
        child: EmptyState(
          familyId: widget.familyId,
          memberCount: persons.length,
          onAddMember: () {
            AddPersonSheet.show(context, familyId: widget.familyId);
          },
        ),
      );
    }

    // v26 BUG-FIX (blank screen):
    // Compute a fingerprint of the current graph layout. If it differs
    // from the last one we rendered, force re-centering by clearing
    // `_initialCenterDone`. This ensures that when the graph data
    // changes (members added/removed, relationships changed), the
    // auto-center transform is recomputed for the new canvas dimensions
    // instead of reusing a stale transform that may now point outside
    // the viewport.
    //
    // The fingerprint includes the sorted person IDs and the canvas
    // dimensions. Including canvas dimensions catches the case where
    // the same set of persons produces a different layout (e.g., after
    // a relationship is added/removed, the BFS generation assignment
    // changes and the radial rings shift).
    final sortedPersonIds = (persons.map((p) => p.id).toList()..sort()).join(',');
    final fingerprint =
        '${sortedPersonIds}|${_layoutResult!.canvasWidth.toStringAsFixed(0)}x'
        '${_layoutResult!.canvasHeight.toStringAsFixed(0)}|'
        '${relationships.length}';
    if (fingerprint != _previousGraphFingerprint) {
      // Graph layout changed — discard any stale saved transform and
      // force the auto-center block in _buildGraphStack to run.
      _initialCenterDone = false;
      _previousGraphFingerprint = fingerprint;
      // Clear any external transform that was restored from
      // SharedPreferences in the parent screen's initState. Without
      // this, the `hasExistingTransform` branch below would honor the
      // stale transform and skip auto-center, reproducing the blank
      // screen even after we've decided to re-center.
      if (widget.externalTransformController != null) {
        widget.externalTransformController!.value = Matrix4.identity();
      }
      debugPrint('[FamilyGraph] Layout changed — forcing re-center. '
          'persons=${persons.length} canvas=${_layoutResult!.canvasWidth.toStringAsFixed(0)}x${_layoutResult!.canvasHeight.toStringAsFixed(0)} '
          'positions=${_layoutResult!.positions.length} edges=${_edges.length}');
    }

    // Track graph open time on first render
    if (_openStopwatch.isRunning) {
      _openStopwatch.stop();
      ref.read(analyticsTrackerProvider).trackGraphOpenTime(
            _openStopwatch.elapsedMilliseconds,
            persons.length,
            false,
          );
    }

    return _buildGraphStack(_layoutResult!, reduceMotion: reduceMotion);
  }

  // ── Graph Stack Builder ────────────────────────────────────────────

  Widget _buildGraphStack(GraphLayoutResult layout, {bool reduceMotion = false}) {
    final positions = layout.positions;
    final canvasWidth = layout.canvasWidth;
    final canvasHeight = layout.canvasHeight;
    final zoomLevel = _currentZoom;

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        // Auto-center on anchor node on first load (moved inside LayoutBuilder
        // so _viewportSize is guaranteed to be set before postFrameCallback fires).
        // If an external controller was provided and already has a non-identity
        // transform (e.g. restored from SharedPreferences), respect it instead
        // of overriding with auto-center.
        if (!_initialCenterDone && _layoutResult != null) {
          final hasExistingTransform =
              widget.externalTransformController != null &&
              !widget.externalTransformController!.value.isIdentity();
          if (hasExistingTransform) {
            // External controller already has a saved position — skip auto-center
            _initialCenterDone = true;
          } else {
            final screenW = constraints.maxWidth;
            final screenH = constraints.maxHeight;

            if (screenW > 0 && screenH > 0 && canvasWidth > 0 && canvasHeight > 0) {
              _initialCenterDone = true;

              // v32 FIX (blank screen): Apply the fit transform SYNCHRONOUSLY
              // during build, NOT in a post-frame callback.
              //
              // The previous post-frame callback approach (v22-v31) had a
              // critical flaw: the first frame rendered at identity matrix
              // (canvas at 0,0 — top-left corner). If the canvas was smaller
              // than the viewport, nodes appeared in the top-left and were
              // often off-screen or invisible. The post-frame callback was
              // supposed to center the canvas, but:
              //   1. If the widget was unmounted by the time the callback
              //      fired, the centering was skipped entirely.
              //   2. If the callback's setState triggered a rebuild that
              //      reset _initialCenterDone, the centering never applied.
              //   3. On some devices, the post-frame callback fired but
              //      the AnimatedBuilder didn't pick up the new value
              //      because the build phase had already completed.
              //
              // Setting _transformationController.value during build is
              // SAFE here because:
              //   - The _onTransformChanged listener only calls setState()
              //     when the visible node IDs change. For the initial
              //     auto-center, the IDs are already set to all nodes,
              //     so setsEqual() returns true and setState() is NOT called.
              //   - The AnimatedBuilder reads _transformationController.value
              //     in its builder function, which runs AFTER this code block.
              //     So it will see the new matrix and render the canvas
              //     at the correct position on the VERY FIRST frame.
              final matrix = GraphGestureMath.computeFitTransform(
                screenW: screenW,
                screenH: screenH,
                canvasW: canvasWidth,
                canvasH: canvasHeight,
                nodeCount: positions.length,
              );
              if (matrix != null) {
                _transformationController.value = matrix;
              }
            }
          }
        }

        // Update viewport culling using the existing ViewportCuller
        final viewport = Rect.fromLTWH(
          -_currentPan.dx / zoomLevel,
          -_currentPan.dy / zoomLevel,
          _viewportSize.width / zoomLevel,
          _viewportSize.height / zoomLevel,
        );

        if (_viewportCuller == null) {
          _viewportCuller = ViewportCuller(
            viewport: viewport,
            bufferPixels: 600.0,
          );
        }

        final nodeSizes = <String, Size>{
          for (final id in positions.keys)
            id: const Size(_nodeWidth, _nodeHeight),
        };

        // FIX A (improved): On first render before camera has centered,
        // show ALL nodes to prevent the "only creator visible" bug.
        // The viewport culling only works correctly once the camera
        // transform has been applied, which happens in a post-frame
        // callback. Until then, show every node.
        //
        // Additionally, for small graphs (<=30 nodes), always show all
        // nodes since the culling overhead isn't worth the visual bugs
        // it can cause on small families.
        final totalNodeCount = positions.length;
        if (!_initialCenterDone && positions.isNotEmpty) {
          _visibleNodeIds = Set<String>.from(positions.keys);
        } else if (totalNodeCount <= 30) {
          // For small families, always show all nodes — no culling needed
          _visibleNodeIds = Set<String>.from(positions.keys);
        } else {
          final culled = _viewportCuller!.cull(
            positions,
            nodeSizes,
            viewport,
          );

          // FIX C: Always force-include the anchor node in culling
          final anchorId = _personMap.values
              .firstWhere((p) => p.isAnchor,
                  orElse: () => GraphPersonData.empty())
              .id;
          if (anchorId.isNotEmpty && !culled.contains(anchorId)) {
            culled.add(anchorId);
          }

          _visibleNodeIds = culled;
        }

        final effectiveVisibleIds = _visibleNodeIds;

        // v31: Wrap the graph stack with GraphWebGestures for desktop
        // mouse-wheel zoom + mouse-drag pan. On mobile (kIsWeb == false),
        // GraphWebGestures is a no-op pass-through — touch gestures are
        // handled by the GestureDetector inside the Stack below.
        return GraphWebGestures(
          transformationController: _transformationController,
          child: Stack(
            children: [
            // ── Camera Transform Layer ───────────────────────────────
            //
            // CRITICAL: Positioned.fill ensures the GestureDetector fills
            // the entire viewport. Without it, the outer Stack passes
            // LOOSE constraints to ClipRect → GestureDetector's inner
            // Stack (only Positioned children) sizes to 0×0 → no gesture
            // events ever fire. Positioned.fill gives TIGHT constraints
            // = full viewport, so every pixel is hit-testable.
            //
            // ScaleGestureRecognizer handles pinch-to-zoom + pan.
            // Child nodes use HitTestBehavior.translucent + onDoubleTap:null
            // so both TapGestureRecognizer (node) and ScaleGestureRecognizer
            // (parent) compete fairly — taps win on lift, pinch wins with 2pts.
            // NO onDoubleTap on parent — would break ScaleGestureRecognizer.
            Positioned.fill(
              child: ClipRect(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: AnimatedBuilder(
                    animation: _transformationController,
                    builder: (context, _) {
                      final matrix = _transformationController.value;
                      final scale = matrix.getMaxScaleOnAxis();
                      final tx = matrix.getTranslation().x;
                      final ty = matrix.getTranslation().y;
                      // StackFit.expand ensures this Stack also fills the
                      // full viewport (belt-and-suspenders for hit testing).
                      return Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: tx,
                            top: ty,
                            child: Transform.scale(
                              scale: scale,
                              alignment: Alignment.topLeft,
                              child: SizedBox(
                                width: canvasWidth,
                                height: canvasHeight,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // ── Edge Layer ──────────────
                                    Positioned.fill(
                                      child: CustomPaint(
                                        size: Size(canvasWidth, canvasHeight),
                                        painter: RelationshipEdge(
                                          positions: positions,
                                          edges: _edges,
                                          selectedEdgeId: _selectedEdgeId,
                                          zoomLevel: zoomLevel,
                                          nodeWidth: _nodeWidth,
                                          nodeHeight: _nodeHeight,
                                          generationMap: {
                                            for (final p in _personMap.values)
                                              p.id: p.generationIndex,
                                          },
                                          highlightedGeneration:
                                              _highlightedGeneration,
                                          anonymousNodeIds: _anonymousNodeIds,
                                          blockedNodeIds: _blockedNodeIds,
                                        ),
                                      ),
                                    ),

                                    // ── Midpoint Hit Layer ───────
                                    Positioned.fill(
                                      child: EdgeMidpointHitLayer(
                                        edges: _edges,
                                        positions: positions,
                                        onMidpointTap: _onEdgeMidpointTap,
                                        nodeWidth: _nodeWidth,
                                        nodeHeight: _nodeHeight,
                                        blockedNodeIds: _blockedNodeIds,
                                      ),
                                    ),

                                    // ── Node Layer ───────────────
                                    ..._buildVisibleNodes(
                                      positions,
                                      zoomLevel,
                                      effectiveVisibleIds,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            // ── Search Bar ───────────────────────────────────────────
            if (_searchBarVisible)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8.0,
                left: 16.0,
                right: 16.0,
                child: RepaintBoundary(
                  child: GraphSearchBar(
                    familyId: widget.familyId,
                    onResultTap: (memberId) {
                      final pos = positions[memberId];
                      if (pos != null) {
                        _cameraController.focusOnNode(memberId, pos);
                        ref
                            .read(analyticsTrackerProvider)
                            .trackCameraFocus(memberId, 400);
                      }
                    },
                    onClose: () {
                      setState(() {
                        _searchBarVisible = false;
                      });
                    },
                  ),
                ),
              ),

            // ── Filter Panel ─────────────────────────────────────────
            // v10 Fix #1A: When hidden, render SizedBox.shrink() instead
            // of IgnorePointer wrapping a hidden widget. This guarantees
            // NO widget in the upper Stack layer participates in hit
            // testing when the panel is hidden, so all touches fall
            // through to the GestureDetector canvas layer below.
            if (_filterVisible)
              GraphFilterPanel(
                isVisible: _filterVisible,
                onClose: () => setState(() => _filterVisible = false),
                onFilterChanged: (filter) => setState(() => _currentFilter = filter),
                currentFilter: _currentFilter,
              )
            else
              const SizedBox.shrink(),

            // ── Legend Panel ───────────────────────────────────────────
            // v10 Fix #1A: Same pattern — SizedBox.shrink() when hidden.
            if (_legendVisible)
              GraphLegend(
                isVisible: _legendVisible,
                onToggle: () => setState(() => _legendVisible = !_legendVisible),
              )
            else
              const SizedBox.shrink(),

            // ── Fit-to-View + Zoom Controls ──────────────────────────
            Positioned(
              right: 12,
              bottom: 90,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fit all nodes into view
                  _GraphToolButton(
                    icon: Icons.fit_screen_rounded,
                    tooltip: 'Fit to view',
                    onTap: () {
                      final pos = _layoutResult?.positions;
                      if (pos != null && _viewportSize != Size.zero) {
                        _cameraController.fitToView(pos, _viewportSize);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  // Zoom in
                  _GraphToolButton(
                    icon: Icons.add_rounded,
                    tooltip: 'Zoom in',
                    onTap: () {
                      final matrix = _transformationController.value;
                      final scale =
                          (matrix.getMaxScaleOnAxis() * 1.3).clamp(0.05, 5.0);
                      final tx = matrix.getTranslation().x;
                      final ty = matrix.getTranslation().y;
                      // Zoom toward center of viewport
                      final cx = _viewportSize.width / 2;
                      final cy = _viewportSize.height / 2;
                      final oldScale = matrix.getMaxScaleOnAxis();
                      final ratio = scale / oldScale;
                      final newTx = cx + (tx - cx) * ratio;
                      final newTy = cy + (ty - cy) * ratio;
                      _transformationController.value = Matrix4.identity()
                        ..translate(newTx, newTy)
                        ..scale(scale);
                    },
                  ),
                  const SizedBox(height: 8),
                  // Zoom out
                  _GraphToolButton(
                    icon: Icons.remove_rounded,
                    tooltip: 'Zoom out',
                    onTap: () {
                      final matrix = _transformationController.value;
                      final scale =
                          (matrix.getMaxScaleOnAxis() / 1.3).clamp(0.05, 5.0);
                      final tx = matrix.getTranslation().x;
                      final ty = matrix.getTranslation().y;
                      final cx = _viewportSize.width / 2;
                      final cy = _viewportSize.height / 2;
                      final oldScale = matrix.getMaxScaleOnAxis();
                      final ratio = scale / oldScale;
                      final newTx = cx + (tx - cx) * ratio;
                      final newTy = cy + (ty - cy) * ratio;
                      _transformationController.value = Matrix4.identity()
                        ..translate(newTx, newTy)
                        ..scale(scale);
                    },
                  ),
                ],
              ),
            ),

            // ── "No Relationships" Banner — REMOVED in v4 ────────────
            // The banner was removed per user request 2026-06-18:
            //   - It was showing even when relationships existed in the
            //     app (false positive due to _realEdgesCount being 0
            //     when synthetic 'related' edges were drawn).
            //   - It was visually intrusive and overlapped the graph.
            //   - The synthetic 'related' edge is sufficient indication
            //     that the graph is functional; users can add proper
            //     relationships via the Add Member flow.
            // The _showNoEdgesBanner state variable is kept (declared
            // elsewhere) but the banner widget is no longer rendered.

            // ── Debug State Badge — REMOVED in v4 ─────────────────────
            // The debug overlay (P:2 E:1 L:2 C:500x250 V:284x693 Z:0.64 A:Y)
            // was visible to end users in debug builds and cluttered
            // the UI. Removed per user request 2026-06-18.
            // Developers who need to inspect graph state can use the
            // Flutter DevTools inspector or add print statements.
          ],
          ),
        );
      },
    );
  }

  List<Widget> _buildVisibleNodes(
    Map<String, Offset> positions,
    double zoomLevel,
    [Set<String>? visibleIds]
  ) {
    final nodes = <Widget>[];
    final effectiveIds = visibleIds ?? _visibleNodeIds;

    for (final person in _personMap.values) {
      final pos = positions[person.id];
      if (pos == null) continue;

      // Skip nodes outside viewport (virtualization)
      if (!effectiveIds.contains(person.id)) continue;

      final isSelected = _selectedNodeId == person.id;
      final isFocused = _focusedNodeId == person.id;
      final isAnonymous = _anonymousNodeIds.contains(person.id);

      // Compute opacity based on highlightedGeneration
      final double nodeOpacity;
      if (_highlightedGeneration != null &&
          person.generationIndex != _highlightedGeneration) {
        nodeOpacity = 0.15;
      } else {
        nodeOpacity = 1.0;
      }

      // Determine node state
      final nodeState = GraphNodeStateResolver.resolve(
        isSelected: isSelected,
        isFocused: isFocused,
        isAnonymous: isAnonymous,
      );

      // Resolve relationship label
      final relationLabel = GraphRelationshipLabels.getRelationLabel(
        person, _personMap, _edges,
      );

      nodes.add(
        Positioned(
          left: pos.dx - _nodeWidth / 2,
          top: pos.dy - _nodeHeight / 2,
          child: RepaintBoundary(
            key: ValueKey('node_${person.id}'),
            child: GraphNode(
              personId: person.id,
              name: isAnonymous ? '' : person.name,
              gender: person.gender,
              generationIndex: person.generationIndex,
              isAnchor: person.isAnchor,
              photoUrl: isAnonymous ? null : person.photoUrl,
              isDeceased: person.isDeceased,
              isAnonymous: isAnonymous,
              relationshipKey: GraphRelationshipLabels.getRelationshipKey(
                person.id, _personMap, _edges,
              ),
              relationLabel: relationLabel,
              nodeState: nodeState,
              opacity: nodeOpacity,
              nodeSize: GraphNodeStateResolver.resolveSize(
                viewportWidth: _viewportSize.width,
                zoomLevel: zoomLevel,
              ),
              onTap: () => _onNodeTap(person.id),
              onLongPress: () => _onNodeLongPress(person.id),
              // v14: onDoubleTap set to null to prevent DoubleTapGestureRecognizer
              // on each node from competing with the custom ScaleGestureRecognizer.
              onDoubleTap: null,
            ),
          ),
        ),
      );
    }

    return nodes;
  }

  // v31: The following methods have been extracted to separate files:
  //   - _resolveNodeState        → GraphNodeStateResolver.resolve()
  //   - _resolveNodeSize         → GraphNodeStateResolver.resolveSize()
  //   - _getRelationLabel        → GraphRelationshipLabels.getRelationLabel()
  //   - _getRelationshipKey      → GraphRelationshipLabels.getRelationshipKey()
  //   - _formatKey               → GraphRelationshipLabels.formatKey()
  //   - _getInverseKey           → GraphRelationshipLabels.getInverseKey()
  //   - _setsEqual               → GraphRelationshipLabels.setsEqual()
  //   - _buildErrorState         → GraphErrorState widget
  //   - _buildEmptyStack         → GraphEmptyStack widget
  //   - _showQuickActions         → GraphQuickActions.show()
  //   - _GraphPersonData class   → GraphPersonData (in graph_relationship_labels.dart)
  // See the imports at the top of this file for the new locations.
}
// ═══════════════════════════════════════════════════════════════════════
// GRAPH TOOL BUTTON
// Small circular icon button used for the fit-to-view / zoom controls.
// ═══════════════════════════════════════════════════════════════════════

class _GraphToolButton extends StatelessWidget {
  const _GraphToolButton({
    required this.icon,
    required this.onTap,
    this.tooltip = '',
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF334155),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: const Color(0xFFCBD5E1),
            ),
          ),
        ),
      ),
    );
  }
}

