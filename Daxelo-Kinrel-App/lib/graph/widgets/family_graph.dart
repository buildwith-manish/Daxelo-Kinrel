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

import 'package:flutter/material.dart';
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
import 'graph_legend.dart';
import 'graph_node.dart';
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

class _FamilyGraphWidgetState extends ConsumerState<FamilyGraphWidget> {
  // ── Controllers ────────────────────────────────────────────────────

  late final CameraController _cameraController;
  ViewportCuller? _viewportCuller;
  late final PositionMemory _positionMemory;
  late final TransformationController _transformationController;

  // ── State ──────────────────────────────────────────────────────────

  /// Computed layout result.
  GraphLayoutResult? _layoutResult;

  /// Map of person ID → PersonData for quick lookups.
  final Map<String, _GraphPersonData> _personMap = {};

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

  /// Whether onboarding has been permanently dismissed for this family.
  /// This is a local cache so we don't need to check the async provider
  /// on every build, preventing onboarding flashes.
  bool _onboardingLocallyDismissed = false;

  // v10 Fix #3c: Flags to prevent feedback loops between
  // CameraController and TransformationController.
  bool _transformationControllerChangeFromExternal = false;
  bool _cameraControllerChangeFromInternal = false;

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
    if (oldWidget.familyId != widget.familyId) {
      _initialCenterDone = false;
      _viewportCuller = null;
      _onboardingLocallyDismissed = false;
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
        if (!_setsEqual(allIds, _visibleNodeIds)) {
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
            .firstWhere((p) => p.isAnchor, orElse: () => _GraphPersonData.empty())
            .id;
        if (anchorId.isNotEmpty) newVisible.add(anchorId);

        if (!_setsEqual(newVisible, _visibleNodeIds)) {
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
  // Gesture handling is now delegated to Flutter's InteractiveViewer,
  // which provides smooth, map-like pinch-to-zoom and pan out of the
  // box. The TransformationController bridges user gestures to the
  // CameraController for programmatic animations (focus-on-node, etc.).

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
    _showQuickActions(personId);
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

  void _showQuickActions(String personId) {
    final person = _personMap[personId];
    if (person == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
              child: Container(
                width: 40.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: KinrelColors.textDim,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 12.0,
              ),
              child: Text(
                person.name,
                style: const TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18.0,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            const Divider(color: Color(0x1AFFFFFF), height: 1.0),
            ListTile(
              leading:
                  const Icon(Icons.person, color: KinrelColors.tealAccent),
              title: const Text(
                'View Profile',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: KinrelColors.amber),
              title: const Text(
                'Edit',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8.0),
          ],
        ),
      ),
    );
  }

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
      error: (error, stack) => _buildErrorState(error),
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

      return _buildEmptyStack(
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
      _personMap[p.id] = _GraphPersonData(
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
      return _buildEmptyStack(
        child: EmptyState(
          familyId: widget.familyId,
          memberCount: persons.length,
          onAddMember: () {
            AddPersonSheet.show(context, familyId: widget.familyId);
          },
        ),
      );
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
            // RELEASE-READY FIX: Apply the initial centering transform
            // SYNCHRONOUSLY in the build (not in a post-frame callback).
            //
            // The previous post-frame-callback approach caused a race:
            // the first frame rendered the canvas at the identity matrix
            // (canvas top-left at viewport top-left), then the callback
            // fired after the frame and set the matrix. If the canvas
            // was smaller than the viewport, the first frame showed
            // nodes in the top-left corner; then the callback moved
            // them to center. This worked but caused a visible flash.
            //
            // WORSE: if the post-frame callback's setState triggered a
            // rebuild that reset _initialCenterDone (e.g., because the
            // widget was still mounting), the centering never applied
            // and the canvas stayed at identity — visible but in the
            // top-left corner, not centered. For a 500x360 canvas in a
            // 384x693 viewport, the right 116px of the canvas was
            // clipped, and the bottom 333px of the viewport was empty.
            //
            // The new approach: compute the "fit" transform here and
            // set it on the controller BEFORE the build returns. The
            // first frame will already show the centered, fitted canvas.
            _initialCenterDone = true;
            final screenW = constraints.maxWidth;
            final screenH = constraints.maxHeight;

            if (screenW > 0 && screenH > 0 && canvasWidth > 0 && canvasHeight > 0) {
              // Compute a scale that fits the entire canvas in the
              // viewport with a small margin. Use the min of the
              // horizontal and vertical fit ratios so the whole canvas
              // is visible.
              const margin = 32.0; // 16px margin on each side
              final fitScaleX = (screenW - margin * 2) / canvasWidth;
              final fitScaleY = (screenH - margin * 2) / canvasHeight;
              var fitScale = fitScaleX < fitScaleY ? fitScaleX : fitScaleY;
              // v10 Fix #3b: Allow small graphs (≤12 nodes) to scale up
              // to 2.0x so they fill the viewport. Large graphs stay at
              // 1.0 max to avoid pixelation. Previously the hard clamp
              // at 1.0 left small graphs tiny in the center of the screen.
              final double fitCeiling = positions.length <= 12 ? 2.0 : 1.0;
              if (fitScale > fitCeiling) fitScale = fitCeiling;
              // Don't go below the min scale.
              if (fitScale < 0.1) fitScale = 0.1;

              // Center the canvas in the viewport:
              //   translate = (viewport_center) - (canvas_center * scale)
              final canvasCenterX = canvasWidth / 2;
              final canvasCenterY = canvasHeight / 2;
              final translateX = (screenW / 2) - (canvasCenterX * fitScale);
              final translateY = (screenH / 2) - (canvasCenterY * fitScale);

              final matrix = Matrix4.identity()
                ..translate(translateX, translateY)
                ..scale(fitScale);
              // Set the matrix directly. Setting TransformationController
              // value during build is safe — it calls notifyListeners()
              // which schedules (not immediately invokes) listener
              // callbacks. The AnimatedBuilder inside GraphPanZoom
              // listens to the controller and will rebuild with the new
              // transform on the next frame.
              _transformationController.value = matrix;
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
                  orElse: () => _GraphPersonData.empty())
              .id;
          if (anchorId.isNotEmpty && !culled.contains(anchorId)) {
            culled.add(anchorId);
          }

          _visibleNodeIds = culled;
        }

        final effectiveVisibleIds = _visibleNodeIds;

        return Stack(
          children: [
            // ── Camera Transform Layer ───────────────────────────────
            //
            // Uses Flutter's built-in InteractiveViewer for smooth,
            // map-like pinch-to-zoom and one-finger pan. It uses the
            // same TransformationController that the CameraController
            // drives for programmatic animations (focus-on-node, fit).
            //
            // Why InteractiveViewer works here:
            //   - Its ScaleGestureRecognizer handles pinch natively and
            //     does NOT conflict with child TapGestureRecognizers.
            //   - It has no DoubleTapGestureRecognizer of its own, so
            //     child node double-tap (focus camera) works cleanly.
            //   - boundaryMargin: infinite → free pan beyond canvas edges.
            //   - constrained: false → canvas can be larger than viewport.
            ClipRect(
              child: InteractiveViewer(
                transformationController: _transformationController,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: 0.05,
                maxScale: 5.0,
                constrained: false,
                child: SizedBox(
                  width: canvasWidth,
                  height: canvasHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // ── Edge Layer ────────────────────────────────
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
                            highlightedGeneration: _highlightedGeneration,
                            anonymousNodeIds: _anonymousNodeIds,
                            blockedNodeIds: _blockedNodeIds,
                          ),
                        ),
                      ),

                      // ── Midpoint Hit Layer ────────────────────────
                      // Transparent tap targets at every edge midpoint.
                      // Tapping shows the relationship info bottom sheet.
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

                      // ── Node Layer ────────────────────────────────
                      ..._buildVisibleNodes(positions, zoomLevel, effectiveVisibleIds),
                    ],
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
            // through to the InteractiveViewer below.
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

            // Control Bar is NO LONGER rendered inside FamilyGraphWidget.
            // It has been replaced by the bottom toolbar in FamilyGraphScreen
            // which contains: Center, Filter, Help (zoom in AppBar).
            // This eliminates duplicate zoom controls and gesture conflicts.

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
        );
      },
    );
  }

  // ── Visible Nodes Builder ──────────────────────────────────────────

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
      final nodeState = _resolveNodeState(
        person.id,
        isSelected,
        isFocused,
        isAnonymous,
      );

      // Resolve relationship label
      final relationLabel = _getRelationLabel(person);

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
              relationshipKey: _getRelationshipKey(person.id),
              relationLabel: relationLabel,
              nodeState: nodeState,
              opacity: nodeOpacity,
              nodeSize: _resolveNodeSize(zoomLevel),
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

  // ── Node State Resolution ──────────────────────────────────────────

  NodeState _resolveNodeState(
    String personId,
    bool isSelected,
    bool isFocused,
    bool isAnonymous,
  ) {
    if (isAnonymous) return NodeState.normal;
    if (isFocused) return NodeState.focused;
    if (isSelected) return NodeState.selected;
    return NodeState.normal;
  }

  /// Resolves responsive node size based on screen width breakpoints
  /// per V2.1 Blueprint §20, combined with zoom level.
  double _resolveNodeSize(double zoomLevel) {
    // Screen-width breakpoints take priority
    final screenWidth = _viewportSize.width;
    double baseSize;
    if (screenWidth < 400) {
      baseSize = 48.0; // Compact: iPhone SE
    } else if (screenWidth < 720) {
      baseSize = 56.0; // Standard: iPhone 15, Pixel 8
    } else if (screenWidth < 1024) {
      baseSize = 60.0; // Expanded: large phones, small tablets
    } else {
      baseSize = 64.0; // Large: iPad Air and above
    }

    // Zoom-level scaling on top of base
    if (zoomLevel < 0.5) return baseSize * 0.85; // compact at zoom
    if (zoomLevel < 0.8) return baseSize * 0.95; // standard at zoom
    if (zoomLevel < 1.5) return baseSize; // expanded at zoom
    return baseSize * 1.05; // large at zoom
  }

  // ── Relationship Label ─────────────────────────────────────────────

  /// Returns the relationship label for [person] relative to the anchor.
  String _getRelationLabel(_GraphPersonData person) {
    if (person.isAnchor) return 'You';

    // Find a true anchor — if none exists, no relation labels can be shown
    final anchors = _personMap.values.where((p) => p.isAnchor).toList();
    if (anchors.isEmpty) return '';
    final anchor = anchors.first;
    if (anchor.id == person.id) return 'You'; // shouldn't happen since person.isAnchor checked above

    // Search for an edge connecting this person to the anchor
    for (final edge in _edges) {
      if (edge.sourceId == anchor.id && edge.targetId == person.id) {
        return _formatKey(edge.relationshipKey);
      }
      if (edge.sourceId == person.id && edge.targetId == anchor.id) {
        return _formatKey(_getInverseKey(edge.relationshipKey));
      }
    }

    return '';
  }

  /// Returns the relationship key for a person from the anchor.
  String? _getRelationshipKey(String personId) {
    final anchor = _personMap.values.firstWhere(
      (p) => p.isAnchor,
      orElse: () => _GraphPersonData.empty(),
    );

    for (final edge in _edges) {
      if (edge.sourceId == anchor.id && edge.targetId == personId) {
        return edge.relationshipKey;
      }
      if (edge.sourceId == personId && edge.targetId == anchor.id) {
        return _getInverseKey(edge.relationshipKey);
      }
    }
    return null;
  }

  /// Formats a relationship key like 'father_in_law' → 'Father In Law'.
  static String _formatKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Returns the inverse relationship key.
  static String _getInverseKey(String key) {
    const inverseMap = <String, String>{
      // Core parent/child
      'father': 'son',
      'mother': 'daughter',
      'son': 'father',
      'daughter': 'mother',
      'parent': 'child',
      'child': 'parent',
      // Sibling
      'brother': 'brother',
      'sister': 'sister',
      'sibling': 'sibling',
      'elder_brother': 'younger_brother',
      'younger_brother': 'elder_brother',
      'elder_sister': 'younger_sister',
      'younger_sister': 'elder_sister',
      'half_brother': 'half_brother',
      'half_sister': 'half_sister',
      // Spouse
      'husband': 'wife',
      'wife': 'husband',
      'spouse': 'spouse',
      'partner': 'partner',
      // Grandparent / grandchild
      'grandfather': 'grandson',
      'grandmother': 'granddaughter',
      'grandson': 'grandfather',
      'granddaughter': 'grandmother',
      'grandparent': 'grandchild',
      'grandchild': 'grandparent',
      'paternal_grandfather': 'grandson',
      'paternal_grandmother': 'granddaughter',
      'maternal_grandfather': 'grandson',
      'maternal_grandmother': 'granddaughter',
      // Uncle / aunt / nephew / niece
      'uncle': 'nephew',
      'aunt': 'niece',
      'nephew': 'uncle',
      'niece': 'aunt',
      'paternal_uncle': 'nephew',
      'paternal_aunt': 'niece',
      'maternal_uncle': 'nephew',
      'maternal_aunt': 'niece',
      // Cousin
      'cousin': 'cousin',
      'cousin_brother': 'cousin_sister',
      'cousin_sister': 'cousin_brother',
      // In-law
      'father_in_law': 'son_in_law',
      'mother_in_law': 'daughter_in_law',
      'son_in_law': 'father_in_law',
      'daughter_in_law': 'mother_in_law',
      'brother_in_law': 'sister_in_law',
      'sister_in_law': 'brother_in_law',
      // Step
      'stepfather': 'stepson',
      'stepmother': 'stepdaughter',
      'stepson': 'stepfather',
      'stepdaughter': 'stepmother',
      'stepbrother': 'stepbrother',
      'stepsister': 'stepsister',
    };
    return inverseMap[key] ?? key;
  }

  /// Compares two Sets by value (not reference).
  static bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }

  // ── Error State ────────────────────────────────────────────────────

  Widget _buildErrorState(Object error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48.0,
            color: KinrelColors.error,
          ),
          const SizedBox(height: 16.0),
          Text(
            'Failed to load graph',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            error.toString(),
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13.0,
              color: KinrelColors.textSilver,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
          ),
          const SizedBox(height: 16.0),
          ElevatedButton(
            onPressed: () {
              ref.invalidate(familyGraphProvider(widget.familyId));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: KinrelColors.orange,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ── Empty Stack Wrapper ────────────────────────────────────────────

  Widget _buildEmptyStack({required Widget child}) {
    // EmptyState handles the zero-member UI.
    return Stack(
      children: [
        child,
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// INTERNAL DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

class _GraphPersonData {
  final String id;
  final String name;
  final String? gender;
  final int generationIndex;
  final bool isAnchor;
  final String? photoUrl;
  final bool isDeceased;
  final String? relationshipKey;
  final int disclosureLevel;

  const _GraphPersonData({
    required this.id,
    required this.name,
    this.gender,
    this.generationIndex = 0,
    this.isAnchor = false,
    this.photoUrl,
    this.isDeceased = false,
    this.relationshipKey,
    this.disclosureLevel = 1,
  });

  factory _GraphPersonData.empty() => const _GraphPersonData(
        id: '',
        name: '',
      );
}
