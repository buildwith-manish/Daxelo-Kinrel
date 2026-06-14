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
import '../engine/fallback_manager.dart';
import '../interaction/camera_controller.dart';
import '../rendering/viewport_culler.dart';
import 'control_bar.dart';
import 'empty_state.dart';
import 'filter_panel.dart';
import 'graph_legend.dart';
import 'graph_node.dart';
import 'onboarding_flow.dart';
import 'relationship_edge.dart';
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
  });

  /// The family ID for data fetching and permission checks.
  final String familyId;

  /// The family display name.
  final String familyName;

  /// Optional external TransformationController so the parent screen
  /// can control zoom/pan programmatically. When provided, the widget
  /// uses it instead of creating its own, and will NOT dispose it.
  final TransformationController? externalTransformController;

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
  final List<GraphEdgeData> _edges = [];

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
  }

  @override
  void didUpdateWidget(covariant FamilyGraphWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.familyId != widget.familyId) {
      _initialCenterDone = false;
      _viewportCuller = null;
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

    final zoom = _currentZoom;
    final pan = _currentPan;

    // Update viewport culling using the existing ViewportCuller
    if (_viewportSize != Size.zero && _layoutResult != null) {
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

      if (newVisible != _visibleNodeIds) {
        setState(() {
          _visibleNodeIds = newVisible;
        });
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

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Accessibility: reduced motion
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // Watch graph data provider
    final graphAsync = ref.watch(familyGraphProvider(widget.familyId));

    // Watch engine tier for control bar
    final currentTier = ref.watch(currentEngineTierProvider);

    // Watch connectivity for offline badge
    final isOnline = ref.watch(isOnlineProvider);

    return graphAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      ),
      error: (error, stack) => _buildErrorState(error),
      data: (graphData) {
        final persons = graphData.toPersonDataList();

        if (persons.isEmpty) {
          return _buildEmptyStack(
            child: EmptyState(
              familyId: widget.familyId,
              memberCount: 0,
              onAddMember: () {
                AddPersonSheet.show(context, familyId: widget.familyId);
              },
            ),
          );
        }

        // Build person map and edges
        _personMap.clear();
        _edges.clear();

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
          _edges.add(GraphEdgeData(
            id: r.id,
            sourceId: r.fromPersonId,
            targetId: r.toPersonId,
            relationshipKey: r.relationshipKey,
          ));
        }

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

        return _buildGraphStack(_layoutResult!, reduceMotion: reduceMotion, currentTier: currentTier);
      },
    );
  }

  // ── Graph Stack Builder ────────────────────────────────────────────

  Widget _buildGraphStack(GraphLayoutResult layout, {bool reduceMotion = false, EngineTier currentTier = EngineTier.force}) {
    final positions = layout.positions;
    final canvasWidth = layout.canvasWidth;
    final canvasHeight = layout.canvasHeight;
    final zoomLevel = _currentZoom;

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        // Auto-center on anchor node on first load (moved inside LayoutBuilder
        // so _viewportSize is guaranteed to be set before postFrameCallback fires)
        if (!_initialCenterDone && _layoutResult != null) {
          final anchorId = _personMap.values
              .firstWhere((p) => p.isAnchor, orElse: () => _GraphPersonData.empty())
              .id;
          final anchorPos = _layoutResult!.positions[anchorId];
          if (anchorPos != null && anchorId.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final screenW = _viewportSize.width;
              final screenH = _viewportSize.height;
              if (screenW > 0 && screenH > 0) {
                final scale = 1.0;
                final translateX = (screenW / 2) - anchorPos.dx * scale;
                final translateY = (screenH / 2) - anchorPos.dy * scale;
                final matrix = Matrix4.identity()
                  ..translate(translateX, translateY)
                  ..scale(scale);
                _transformationController.value = matrix;
                setState(() => _initialCenterDone = true);
              }
            });
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

        // FIX A: Show all nodes on first render before camera centers
        if (_visibleNodeIds.isEmpty && positions.isNotEmpty) {
          _visibleNodeIds = Set<String>.from(positions.keys);
        } else {
          _visibleNodeIds = _viewportCuller!.cull(
            positions,
            nodeSizes,
            viewport,
          );
        }

        // FIX C: Always force-include the anchor node in LayoutBuilder culling
        final layoutAnchorId = _personMap.values
            .firstWhere((p) => p.isAnchor,
                orElse: () => _GraphPersonData.empty())
            .id;
        if (layoutAnchorId.isNotEmpty && !_visibleNodeIds.contains(layoutAnchorId)) {
          _visibleNodeIds = Set<String>.from(_visibleNodeIds)..add(layoutAnchorId);
        }

        final effectiveVisibleIds = _visibleNodeIds;

        // ── Onboarding dismissal check ────────────────────────────
        // Must be computed before the widget tree (not inside children list).
        final dismissedAsync = ref.watch(onboardingDismissedProvider);
        final isDismissed = dismissedAsync.valueOrNull
                ?.contains(widget.familyId) ??
            true; // Default TRUE (hidden) while loading

        return Stack(
          children: [
            // ── Camera Transform Layer ───────────────────────────────
            RepaintBoundary(
              child: ClipRect(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.1,
                  maxScale: 4.0,
                  constrained: false,
                  child: SizedBox(
                    width: canvasWidth,
                    height: canvasHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // ── Edge Layer ────────────────────────────────
                        RepaintBoundary(
                          child: Positioned.fill(
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
                        ),

                        // ── Node Layer ────────────────────────────────
                        ..._buildVisibleNodes(positions, zoomLevel, effectiveVisibleIds),
                      ],
                    ),
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
            GraphFilterPanel(
              isVisible: _filterVisible,
              onClose: () => setState(() => _filterVisible = false),
              onFilterChanged: (filter) => setState(() => _currentFilter = filter),
              currentFilter: _currentFilter,
            ),

            // ── Legend Panel ───────────────────────────────────────────
            GraphLegend(
              isVisible: _legendVisible,
              onToggle: () => setState(() => _legendVisible = !_legendVisible),
            ),

            // ── Control Bar ──────────────────────────────────────────
            GraphControlBar(
              cameraController: _cameraController,
              onFilterTap: () => setState(() => _filterVisible = !_filterVisible),
              onLegendTap: () => setState(() => _legendVisible = !_legendVisible),
              isFilterActive: _currentFilter.isActive,
              currentTier: currentTier,
            ),

            // ── Onboarding Flow (conditional) ────────────────────────
            // Only show onboarding if not yet dismissed for this family.
            if (!isDismissed)
              Positioned.fill(
                child: OnboardingFlow(
                  familyId: widget.familyId,
                  memberCount: _personMap.length,
                ),
              ),

            // ── Add Member FAB (always visible) ──────────────────────
            // BUG-3 FIX: Persistent FAB inside the graph stack, positioned
            // above the ControlBar so it's always accessible regardless of
            // onboarding state or member count.
            Positioned(
              right: 16.0,
              bottom: 96.0, // above the ControlBar
              child: FloatingActionButton(
                heroTag: 'graph_add_member_fab',
                onPressed: () => AddPersonSheet.show(context, familyId: widget.familyId),
                backgroundColor: KinrelColors.orange,
                foregroundColor: KinrelColors.textWhite,
                mini: false,
                tooltip: 'Add Member',
                child: const Icon(Icons.person_add_alt_1_rounded),
              ),
            ),
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
              onDoubleTap: () => _onNodeDoubleTap(person.id),
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

    // Find anchor
    final anchor = _personMap.values.firstWhere(
      (p) => p.isAnchor,
      orElse: () => person,
    );
    if (anchor.id == person.id) return 'You';

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
      'father': 'son',
      'mother': 'daughter',
      'son': 'father',
      'daughter': 'mother',
      'brother': 'brother',
      'sister': 'sister',
      'husband': 'wife',
      'wife': 'husband',
      'spouse': 'spouse',
      'partner': 'partner',
      'grandfather': 'grandson',
      'grandmother': 'granddaughter',
      'grandson': 'grandfather',
      'granddaughter': 'grandmother',
      'uncle': 'nephew',
      'aunt': 'niece',
      'nephew': 'uncle',
      'niece': 'aunt',
      'cousin': 'cousin',
      'father_in_law': 'son_in_law',
      'mother_in_law': 'daughter_in_law',
      'son_in_law': 'father_in_law',
      'daughter_in_law': 'mother_in_law',
      'brother_in_law': 'sister_in_law',
      'sister_in_law': 'brother_in_law',
      'half_brother': 'half_brother',
      'half_sister': 'half_sister',
    };
    return inverseMap[key] ?? key;
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
