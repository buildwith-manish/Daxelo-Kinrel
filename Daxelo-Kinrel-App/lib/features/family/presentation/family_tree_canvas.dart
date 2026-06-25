import 'package:kinrel/core/widgets/global_error_widget.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/graph/graph_service.dart';
import '../../../core/services/graph_layout_service.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/utils/smart_preloader.dart';
import '../../../core/services/analytics_service.dart';
import '../../../graph/widgets/graph_pan_zoom.dart';
import '../../../shared/widgets/dk_components.dart';
import 'services/graph_export_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// Extended tree node with layout metadata
class VisTreeNode {
  const VisTreeNode({
    required this.person,
    this.spouse,
    this.children = const [],
    this.lineage = '',
  });

  final GraphPerson person;
  final GraphPerson? spouse;
  final List<VisTreeNode> children;
  final String lineage;
}

/// Lineage color coding for node backgrounds
enum NodeLineage { paternal, maternal, marital, self, none }

/// Layout mode for the family graph
enum GraphLayoutMode { force, hierarchical, radial, generational }

/// Edge type classification for styling
enum EdgeType { spouse, parentChild, sibling, inLaw, unknown }

/// Represents a visible edge in the graph
class VisEdge {
  const VisEdge({
    required this.fromId,
    required this.toId,
    required this.type,
    this.label,
  });

  final String fromId;
  final String toId;
  final EdgeType type;
  final String? label;
}

/// Filter state for the graph
class GraphFilters {
  const GraphFilters({
    this.visibleGenerations = const {1, 2, 3, 4, 5},
    this.branch = 'all',
    this.showDeceased = true,
    this.showMaritalLinks = true,
  });

  final Set<int> visibleGenerations;
  final String branch;
  final bool showDeceased;
  final bool showMaritalLinks;

  GraphFilters copyWith({
    Set<int>? visibleGenerations,
    String? branch,
    bool? showDeceased,
    bool? showMaritalLinks,
  }) {
    return GraphFilters(
      visibleGenerations: visibleGenerations ?? this.visibleGenerations,
      branch: branch ?? this.branch,
      showDeceased: showDeceased ?? this.showDeceased,
      showMaritalLinks: showMaritalLinks ?? this.showMaritalLinks,
    );
  }
}

/// Layout result using center positions for circular nodes
class LayoutResult {
  const LayoutResult({
    required this.positions,
    required this.nodes,
    required this.nodeLineages,
    required this.edges,
    required this.nodeGenerations,
    this.kinshipLabels = const {},
    this.relativeLevels = const {},
    this.edgeMidpoints = const {},
  });

  final Map<String, Offset> positions;
  final Map<String, VisTreeNode> nodes;
  final Map<String, String> nodeLineages;
  final List<VisEdge> edges;
  final Map<String, int> nodeGenerations;

  /// Kinship label for each node (e.g. "Father", "Sister")
  final Map<String, String?> kinshipLabels;

  /// Relative generation level from anchor (-2=grandparent, -1=parent, 0=self, +1=child, +2=grandchild)
  final Map<String, int> relativeLevels;

  /// Maps edge key "fromId|toId" → midpoint Offset (canvas coords, no ambient)
  final Map<String, Offset> edgeMidpoints;
}

// ═══════════════════════════════════════════════════════════════════════
// FORCE SIMULATION ISOLATE DATA TYPES
// ═══════════════════════════════════════════════════════════════════════

/// Simple edge representation for isolate communication
class _SimEdge {
  const _SimEdge({required this.fromId, required this.toId});
  final String fromId;
  final String toId;
}

/// Input for the force simulation isolate
class _ForceSimInput {
  const _ForceSimInput({
    required this.positions,
    required this.velocities,
    required this.edges,
    required this.allIds,
    required this.centerX,
    required this.centerY,
  });

  final Map<String, Offset> positions;
  final Map<String, Offset> velocities;
  final List<_SimEdge> edges;
  final List<String> allIds;
  final double centerX;
  final double centerY;
}

/// Output from the force simulation isolate
class _ForceSimResult {
  const _ForceSimResult({
    required this.positions,
    required this.velocities,
  });

  final Map<String, Offset> positions;
  final Map<String, Offset> velocities;
}

/// Top-level function to run force-directed simulation in a background isolate
_ForceSimResult _runForceSimulationIsolate(_ForceSimInput input) {
  const double repulsionStrength = 6000;
  const double attractionStrength = 0.004;
  const double gravityStrength = 0.008;
  const double damping = 0.82;
  const double idealEdgeLength = 150;
  const int maxSteps = 80;

  final positions = Map<String, Offset>.from(input.positions);
  final velocities = Map<String, Offset>.from(input.velocities);
  final allIds = input.allIds;
  final center = Offset(input.centerX, input.centerY);

  for (int step = 0; step < maxSteps; step++) {
    final forces = <String, Offset>{
      for (final id in allIds) id: Offset.zero,
    };

    // Repulsion
    for (int i = 0; i < allIds.length; i++) {
      for (int j = i + 1; j < allIds.length; j++) {
        final a = allIds[i];
        final b = allIds[j];
        final delta = positions[a]! - positions[b]!;
        final dist = math.max(delta.distance, 0.1);
        final force = repulsionStrength / (dist * dist);
        final direction = delta / dist;
        forces[a] = forces[a]! + direction * force;
        forces[b] = forces[b]! - direction * force;
      }
    }

    // Attraction
    for (final edge in input.edges) {
      if (!positions.containsKey(edge.fromId) ||
          !positions.containsKey(edge.toId)) {
        continue;
      }
      final delta = positions[edge.toId]! - positions[edge.fromId]!;
      final dist = math.max(delta.distance, 0.1);
      final force = attractionStrength * (dist - idealEdgeLength);
      final direction = delta / dist;
      forces[edge.fromId] = forces[edge.fromId]! + direction * force;
      forces[edge.toId] = forces[edge.toId]! - direction * force;
    }

    // Gravity
    for (final id in allIds) {
      final delta = center - positions[id]!;
      forces[id] = forces[id]! + delta * gravityStrength;
    }

    // Apply
    for (final id in allIds) {
      final vel = (velocities[id] ?? Offset.zero) + forces[id]!;
      velocities[id] = vel * damping;
      positions[id] = positions[id]! + velocities[id]!;
    }
  }

  return _ForceSimResult(positions: positions, velocities: velocities);
}

// ═══════════════════════════════════════════════════════════════════════
// MAIN CANVAS WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// Canvas-based interactive family constellation view with force-directed
/// layout, circular nodes with generation rings, styled edges, ambient
/// floating animation, and rich interaction support.
class FamilyTreeCanvas extends StatefulWidget {
  FamilyTreeCanvas({
    super.key,
    required this.members,
    required this.relationships,
    this.anchorPersonId,
    this.onNodeTap,
    this.onNodeLongPress,
  });

  final List<Person> members;
  final List<FamilyRelationship> relationships;
  final String? anchorPersonId;
  final ValueChanged<Person>? onNodeTap;
  final void Function(Person person)? onNodeLongPress;

  @override
  State<FamilyTreeCanvas> createState() => _FamilyTreeCanvasState();
}

class _FamilyTreeCanvasState extends State<FamilyTreeCanvas>
    with TickerProviderStateMixin {
  // ── View state ──────────────────────────────────────────────────
  String? _selectedNodeId;
  GraphFilters _filters = GraphFilters();
  GraphLayoutMode _layoutMode = GraphLayoutMode.generational; // Default to generational
  bool _showLabels = true;
  bool _showGenBands = false;
  double _currentScale = 1.0;

  // 1H: GlobalKey for RepaintBoundary (graph share/export)
  final GlobalKey _canvasBoundaryKey = GlobalKey();

  // 1G: Selected language for kinship terms (default English)
  SupportedLanguage _selectedLanguage = SupportedLanguage.english;

  // ── Transformation controller for InteractiveViewer ─────────────
  final TransformationController _transformationController =
      TransformationController();

  // ── Animation ───────────────────────────────────────────────────
  late AnimationController _ambientController;
  late AnimationController _pulseController;

  // Change 8: Layout transition animation
  Map<String, Offset> _previousPositions = {};
  late AnimationController _layoutTransitionController;
  Animation<double> _layoutTransitionAnimation =
      const AlwaysStoppedAnimation(1.0);

  // ── Force-directed simulation state ─────────────────────────────
  final Map<String, Offset> _forcePositions = {};
  Map<String, Offset> _forceVelocities = {};

  // ── Layout caching (F4-5: Cache node positions) ────────────────
  Map<String, Offset> _cachedPositions = {}; // F4-5: Cached positions map
  int _layoutVersion = 0;
  LayoutResult? _cachedLayout;
  bool _isAsyncComputing = false;

  // ── Layout constants ────────────────────────────────────────────
  static const double nodeRadius = 40.0; // Change 9: was 24.0
  static const double horizontalGap = 100.0;
  static const double verticalGap = 140.0;
  static const double canvasSize = 2000.0;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Change 8: Layout transition controller
    _layoutTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _layoutTransitionAnimation = CurvedAnimation(
      parent: _layoutTransitionController,
      curve: Curves.easeInOutCubic,
    );

    // Change 1: Center on anchor after first frame
    // v9: Guard with mounted check for safety
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerOnAnchor();
    });

    // P5-F1: Track graph opened with node count
    final activeCount =
        widget.members.where((p) => p.deletedAt == null).length;
    AnalyticsService.instance.logGraphOpened(activeCount);
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _pulseController.dispose();
    _layoutTransitionController.dispose(); // Change 8
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FamilyTreeCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.members, widget.members) ||
        oldWidget.anchorPersonId != widget.anchorPersonId) {
      _invalidateLayoutCache();
    }
  }

  // ── Cache invalidation (F4-5) ──────────────────────────────────

  void _invalidateLayoutCache() {
    _cachedLayout = null;
  }

  // Change 8: Start layout transition animation
  void _startLayoutTransition() {
    _layoutTransitionController.forward(from: 0);
  }

  /// Computes the visible viewport rect in graph coordinates
  Rect _computeVisibleRect() {
    final screenSize = MediaQuery.of(context).size;
    final transform = _transformationController.value;
    final inverse = Matrix4.identity()..copyInverse(transform);
    final topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final bottomRight = MatrixUtils.transformPoint(
      inverse,
      Offset(screenSize.width, screenSize.height),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  // ══════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final activeMembers =
        widget.members.where((p) => p.deletedAt == null).toList();

    // F4-5: Use cached layout; only recompute when data/layout mode/filters change
    if (_cachedLayout == null) {
      final treeRoots = _buildTree();
      _cachedLayout = _computeLayout(treeRoots);
      _cachedPositions = Map<String, Offset>.from(_cachedLayout!.positions);
      _layoutVersion++;

      // F4-6: For > 300 nodes in force mode, trigger async force simulation
      if (_layoutMode == GraphLayoutMode.force &&
          _cachedLayout!.nodes.length > 300 &&
          !_isAsyncComputing) {
        _computeForceLayoutAsync(_cachedLayout!, _layoutVersion);
      }
    }

    final layout = _cachedLayout!;

    return Container(
      color: DKColors.isLight(context)
          ? DKColors.lightBg
          : const Color(0xFF131416),
      child: Stack(
        children: [
          // ── Interactive graph canvas ─────────────────────────────
          // v45 FIX: Remove GestureDetector wrapper around GraphPanZoom child.
          // The GestureDetector was creating an arena entry that competed with
          // GraphPanZoom's Listener on Android, causing pinch-to-zoom to freeze.
          // GraphPanZoom v5.0+ handles all gestures via raw Listener — no
          // GestureDetector needed. Tap/long-press/double-tap are handled
          // by GraphPanZoom's onTap/onLongPress callbacks.
          GraphPanZoom(
            transformationController: _transformationController,
            minScale: 0.2,
            maxScale: 4.0,
            onTransformChanged: () {
              final newScale = _transformationController.value.getMaxScaleOnAxis();
              if (newScale != _currentScale) {
                AnalyticsService.instance.logGraphZoomed(newScale);
              }
              setState(() {
                _currentScale = newScale;
              });
            },
            onTap: (localPosition) => _handleTap(localPosition, layout),
            onLongPress: (localPosition) => _handleLongPress(localPosition, layout),
            child: SizedBox(
                  width: canvasSize,
                  height: canvasSize,
                  child: KinrelAnimatedBuilder(
                    animation: Listenable.merge([
                      _ambientController,
                      _pulseController,
                      _layoutTransitionController, // Change 8
                    ]),
                    builder: (context, _) {
                      // F4-3: Wrap in RepaintBoundary
                      // 1H: Use _canvasBoundaryKey for graph share/export
                      return RepaintBoundary(
                        key: _canvasBoundaryKey,
                        child: CustomPaint(
                          painter: _ConstellationPainter(
                            layout: layout,
                            scale: _currentScale,
                            selectedNodeId: _selectedNodeId,
                            anchorPersonId: widget.anchorPersonId,
                            showLabels: _showLabels,
                            showGenBands: _showGenBands,
                            ambientValue: _ambientController.value,
                            pulseValue: _pulseController.value,
                            members: widget.members,
                            visibleRect: _computeVisibleRect(),
                            previousPositions:
                                _previousPositions, // Change 8
                            layoutTransitionValue:
                                _layoutTransitionAnimation.value, // Change 8
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

          // Change 2: Removed _LanguageSelectorButton and _FilterBar from top
          // Change 5: Replaced _GraphControls, _AddNodeFab, _Minimap with single pill

          // ── Color legend bar (Fix Root Cause #5) ──────────────────
          if (activeMembers.isNotEmpty)
            Positioned(
              bottom: 90,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1B2E).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFE8622A).withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LegendDot(
                        color: const Color(0xFF4A9FBF),
                        label: 'Parents',
                      ),
                      const SizedBox(width: 14),
                      _LegendDot(
                        color: const Color(0xFF00B4A6),
                        label: 'Self',
                      ),
                      const SizedBox(width: 14),
                      _LegendDot(
                        color: const Color(0xFF4A4A6A),
                        label: 'Siblings',
                      ),
                      const SizedBox(width: 14),
                      _LegendDot(
                        color: const Color(0xFFBF4A4A),
                        label: 'Children',
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Graph pill (bottom center) ──────────────────────────
          if (activeMembers.isNotEmpty)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: _GraphPill(
                  layoutMode: _layoutMode,
                  onToggleLayout: (mode) {
                    setState(() {
                      _previousPositions =
                          Map<String, Offset>.from(_cachedPositions);
                      _layoutMode = mode;
                      _forcePositions.clear();
                      _forceVelocities.clear();
                      _invalidateLayoutCache();
                      _startLayoutTransition(); // Change 8
                    });
                  },
                  onZoomIn: _zoomIn,
                  onZoomOut: _zoomOut,
                  onCenterYou: _centerOnAnchor,
                  onFit: _fitToScreen,
                  onAddPerson: () {
                    // Parent screen handles showing AddPersonSheet
                  },
                  onOpenMenu: () => _showMenuBottomSheet(context),
                ),
              ),
            ),

          // ── Accessibility: Semantic overlay for graph nodes ────
          // Positioned invisible Semantics nodes for each person in the
          // graph so TalkBack/VoiceOver can navigate and announce them.
          if (activeMembers.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: _AccessibilityNodeOverlay(
                  layout: layout,
                  members: widget.members,
                  selectedNodeId: _selectedNodeId,
                  anchorPersonId: widget.anchorPersonId,
                  transformationController: _transformationController,
                ),
              ),
            ),

          // ── Empty state ─────────────────────────────────────────
          if (activeMembers.isEmpty)
            Center(
              child: _EmptyConstellation(
                onAddFirst: () {
                  // Parent should handle by showing AddPersonSheet
                },
              ),
            ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // INTERACTION HANDLERS
  // ══════════════════════════════════════════════════════════════════

  void _handleTap(Offset localPos, LayoutResult layout) {
    final transform = _transformationController.value;
    final inverse = Matrix4.identity()..copyInverse(transform);
    final graphPos = MatrixUtils.transformPoint(inverse, localPos);

    // ── 1. Check node hit ──────────────────────────────────────────
    String? tappedNodeId;
    for (final entry in layout.positions.entries) {
      final center = entry.value + _ambientOffsetFor(entry.key);
      if ((center - graphPos).distance < nodeRadius * 1.4) {
        tappedNodeId = entry.key;
        break;
      }
    }

    if (tappedNodeId != null) {
      final person = widget.members.firstWhere(
        (p) => p.id == tappedNodeId,
        orElse: () => Person(id: tappedNodeId!, familyId: '', name: 'Unknown'),
      );
      try {
        SmartPreloader.precacheSingleImage(context: context, imageUrl: person.photoUrl);
      } catch (_) {}
      setState(() => _selectedNodeId = tappedNodeId);
      AnalyticsService.instance.logGraphNodeTapped();
      widget.onNodeTap?.call(person);
      return;
    }

    // ── 2. Check edge midpoint hit ─────────────────────────────────
    for (final edge in layout.edges) {
      final fromPos = layout.positions[edge.fromId];
      final toPos = layout.positions[edge.toId];
      if (fromPos == null || toPos == null) continue;

      // Use same ambient offsets as painter
      final from = fromPos + _ambientOffsetFor(edge.fromId);
      final to = toPos + _ambientOffsetFor(edge.toId);

      // Midpoint is at center of trimmed line (same trim as painter)
      final dir = (to - from);
      final dist = dir.distance;
      if (dist < 1) continue;
      final unit = dir / dist;
      const nodeR = nodeRadius;
      final trimStart = from + unit * (nodeR + 4);
      final trimEnd = to - unit * (nodeR + 4);
      final mid = (trimStart + trimEnd) / 2;

      if ((mid - graphPos).distance < 22) {
        // Tapped a midpoint dot — show relationship popup
        _showEdgeRelationshipSheet(edge.fromId, edge.toId);
        return;
      }
    }

    // ── 3. Tap on empty space — deselect ──────────────────────────
    setState(() => _selectedNodeId = null);
  }

  /// Resolves a kinship label from [fromId]'s perspective looking at [toId].
  /// Checks direct edges in both directions and returns the correct label.
  String? _getKinshipFrom(String fromId, String toId) {
    // Try direct edge: fromId → toId
    final fwd = widget.relationships.where((r) => r.isActive).firstWhereOrNull(
      (r) => r.fromPersonId == fromId && r.toPersonId == toId,
    );
    if (fwd != null) {
      return fwd.relationshipKey.replaceAll('_', ' ');
    }
    // Try reverse edge: toId → fromId, then invert
    final rev = widget.relationships.where((r) => r.isActive).firstWhereOrNull(
      (r) => r.fromPersonId == toId && r.toPersonId == fromId,
    );
    if (rev != null) {
      return getInverseRelationshipType(rev.relationshipKey).replaceAll('_', ' ');
    }
    return null;
  }

  void _showEdgeRelationshipSheet(String fromId, String toId) {
    final memberMap = {for (final m in widget.members) m.id: m};
    final personA = memberMap[fromId];
    final personB = memberMap[toId];
    if (personA == null || personB == null) return;

    final aCallsB = _getKinshipFrom(fromId, toId);
    final bCallsA = _getKinshipFrom(toId, fromId);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF13141A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F0EE).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header: two avatar circles connected
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RelationAvatar(name: personA.name, color: const Color(0xFF4A9FBF)),
                    const SizedBox(width: 8),
                    const Icon(Icons.swap_horiz_rounded,
                        color: Color(0xFFE8612A), size: 20),
                    const SizedBox(width: 8),
                    _RelationAvatar(name: personB.name, color: const Color(0xFF8A8AAA)),
                  ],
                ),

                const SizedBox(height: 24),

                // Card A → B
                if (aCallsB != null)
                  _RelationCard(
                    fromName: personA.name,
                    toName: personB.name,
                    label: _capitalize(aCallsB),
                    color: const Color(0xFF4A9FBF),
                  ),

                if (aCallsB != null) const SizedBox(height: 12),

                // Card B → A
                if (bCallsA != null)
                  _RelationCard(
                    fromName: personB.name,
                    toName: personA.name,
                    label: _capitalize(bCallsA),
                    color: const Color(0xFF8A8AAA),
                  ),

                if (aCallsB == null && bCallsA == null)
                  Text(
                    'No relationship label found',
                    style: TextStyle(
                      color: const Color(0xFFF5F0EE).withValues(alpha: 0.4),
                      fontSize: 14,
                    ),
                  ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  void _handleLongPress(Offset localPos, LayoutResult layout) {
    final transform = _transformationController.value;
    final inverse = Matrix4.identity()..copyInverse(transform);
    final graphPos = MatrixUtils.transformPoint(inverse, localPos);

    String? tappedId;
    for (final entry in layout.positions.entries) {
      final ambientOffset = _ambientOffsetFor(entry.key);
      final center = entry.value + ambientOffset;
      final dist = (center - graphPos).distance;
      if (dist < nodeRadius * 1.4) {
        // Change 7C: was 1.3
        tappedId = entry.key;
        break;
      }
    }

    if (tappedId != null) {
      final person = widget.members.firstWhere(
        (p) => p.id == tappedId,
        orElse: () => Person(id: tappedId!, familyId: '', name: 'Unknown'),
      );
      widget.onNodeLongPress?.call(person);
    }
  }

  void _handleDoubleTap(Offset localPos, LayoutResult layout) {
    final transform = _transformationController.value;
    final inverse = Matrix4.identity()..copyInverse(transform);
    final graphPos = MatrixUtils.transformPoint(inverse, localPos);

    String? tappedId;
    for (final entry in layout.positions.entries) {
      final ambientOffset = _ambientOffsetFor(entry.key);
      final center = entry.value + ambientOffset;
      final dist = (center - graphPos).distance;
      if (dist < nodeRadius * 1.4) {
        tappedId = entry.key;
        break;
      }
    }

    if (tappedId != null) {
      // Center on this node, zoom to 1.5x
      final pos = layout.positions[tappedId];
      if (pos != null) {
        final screenSize = MediaQuery.of(context).size;
        setState(() {
          final m = Matrix4.identity()
            ..translate(screenSize.width / 2 - pos.dx * 1.5, screenSize.height / 2 - pos.dy * 1.5)
            ..scale(1.5);
          _transformationController.value = m;
          _currentScale = 1.5;
        });
      }
    }
  }

  Offset _ambientOffsetFor(String id) {
    final phase = id.hashCode * 0.1;
    final dx = math.sin(_ambientController.value * 2 * math.pi + phase) * 1.5;
    final dy =
        math.cos(_ambientController.value * 2 * math.pi + phase * 0.7) * 1.5;
    return Offset(dx, dy);
  }

  void _fitToScreen() {
    _centerOnAnchor(); // reuse same fit logic
  }

  void _centerOnAnchor() {
    if (_cachedPositions.isEmpty) return;
    final anchorPos = _cachedPositions[widget.anchorPersonId];
    if (anchorPos == null) return;
    final screenSize = MediaQuery.of(context).size;

    // Calculate bounding box of all nodes
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final pos in _cachedPositions.values) {
      minX = math.min(minX, pos.dx);
      maxX = math.max(maxX, pos.dx);
      minY = math.min(minY, pos.dy);
      maxY = math.max(maxY, pos.dy);
    }

    // Add padding around the bounding box (80px per side + nodeRadius)
    const padding = 120.0;
    final contentW = (maxX - minX) + padding * 2;
    final contentH = (maxY - minY) + padding * 2;

    // Fit scale: smallest of width-fit and height-fit, capped at 1.5
    final scaleX = screenSize.width / contentW;
    final scaleY = screenSize.height / contentH;
    final fitScale = math.min(math.min(scaleX, scaleY), 1.5);

    // Center the bounding box on screen
    final contentCenterX = (minX + maxX) / 2;
    final contentCenterY = (minY + maxY) / 2;
    final tx = screenSize.width / 2 - contentCenterX * fitScale;
    final ty = screenSize.height / 2 - contentCenterY * fitScale;

    setState(() {
      final m = Matrix4.identity()
        ..translate(tx, ty)
        ..scale(fitScale);
      _transformationController.value = m;
      _currentScale = fitScale;
    });
  }

  // v9: Read scale from matrix (not _currentScale which can drift)
  void _zoomIn() {
    final screenSize = MediaQuery.of(context).size;
    final viewportCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 1.3).clamp(0.2, 4.0);
    setState(() {
      final inverse = Matrix4.identity()
        ..copyInverse(_transformationController.value);
      final graphCenter = MatrixUtils.transformPoint(inverse, viewportCenter);
      final m = Matrix4.identity();
      m.setEntry(0, 3, viewportCenter.dx - graphCenter.dx * newScale);
      m.setEntry(1, 3, viewportCenter.dy - graphCenter.dy * newScale);
      m.scaleByDouble(newScale, newScale, 1.0, 1.0);
      _transformationController.value = m;
      _currentScale = newScale;
    });
  }

  void _zoomOut() {
    final screenSize = MediaQuery.of(context).size;
    final viewportCenter = Offset(screenSize.width / 2, screenSize.height / 2);
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final newScale = (currentScale / 1.3).clamp(0.2, 4.0);
    setState(() {
      final inverse = Matrix4.identity()
        ..copyInverse(_transformationController.value);
      final graphCenter = MatrixUtils.transformPoint(inverse, viewportCenter);
      final m = Matrix4.identity();
      m.setEntry(0, 3, viewportCenter.dx - graphCenter.dx * newScale);
      m.setEntry(1, 3, viewportCenter.dy - graphCenter.dy * newScale);
      m.scaleByDouble(newScale, newScale, 1.0, 1.0);
      _transformationController.value = m;
      _currentScale = newScale;
    });
  }

  // ══════════════════════════════════════════════════════════════════
  // 1G: LANGUAGE PICKER
  // ══════════════════════════════════════════════════════════════════

  void _showLanguagePicker(BuildContext context) {
    // Show 7 Indian languages + English
    final languages = [
      SupportedLanguage.hindi,
      SupportedLanguage.bengali,
      SupportedLanguage.tamil,
      SupportedLanguage.telugu,
      SupportedLanguage.marathi,
      SupportedLanguage.gujarati,
      SupportedLanguage.kannada,
      SupportedLanguage.english,
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Language',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            ...languages.map((lang) {
              final isSelected = lang == _selectedLanguage;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSelected ? KinrelColors.orange : KinrelColors.textDim,
                  size: 20,
                ),
                title: Text(
                  lang.name,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 15,
                    color: isSelected ? KinrelColors.orange : KinrelColors.textWhite,
                  ),
                ),
                trailing: Text(
                  lang.nativeName,
                  style: TextStyle(
                    fontSize: 16,
                    color: KinrelColors.textSilver,
                  ),
                ),
                onTap: () {
                  setState(() => _selectedLanguage = lang);
                  Navigator.pop(ctx);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // 1H: CANVAS SHARE / EXPORT
  // ══════════════════════════════════════════════════════════════════

  Future<void> _shareGraph() async {
    try {
      await GraphExportService.shareGraph(
        _canvasBoundaryKey,
        subject: 'My Family Tree on Kinrel',
        fileName: 'kinrel_family_tree.png',
      );
    } catch (e) {
      // Never crash on share failure — fallback gracefully
      debugPrint('Graph export failed: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // MENU BOTTOM SHEET (Change 2/5: moved from top bar + controls)
  // ══════════════════════════════════════════════════════════════════

  void _showMenuBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F0EE).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Toggle labels
                _MenuTile(
                  icon: _showLabels
                      ? Icons.label_rounded
                      : Icons.label_off_rounded,
                  label: _showLabels ? 'Hide Labels' : 'Show Labels',
                  trailing: Switch(
                    value: _showLabels,
                    activeColor: const Color(0xFFE8612A),
                    onChanged: (v) {
                      setState(() => _showLabels = v);
                      Navigator.pop(context);
                    },
                  ),
                  onTap: () {
                    setState(() => _showLabels = !_showLabels);
                    Navigator.pop(context);
                  },
                ),
                // Toggle gen bands
                _MenuTile(
                  icon: Icons.album_rounded,
                  label: _showGenBands
                      ? 'Hide Generation Bands'
                      : 'Show Generation Bands',
                  trailing: Switch(
                    value: _showGenBands,
                    activeColor: const Color(0xFFE8612A),
                    onChanged: (v) {
                      setState(() => _showGenBands = v);
                      Navigator.pop(context);
                    },
                  ),
                  onTap: () {
                    setState(() => _showGenBands = !_showGenBands);
                    Navigator.pop(context);
                  },
                ),
                const SizedBox(height: 12),
                // Language selector
                _MenuTile(
                  icon: Icons.language_rounded,
                  label: 'Language',
                  onTap: () {
                    Navigator.pop(context);
                    // 1G: Language Picker — gated behind kEnableLanguagePicker
                    if (kEnableLanguagePicker) {
                      _showLanguagePicker(context);
                    }
                  },
                ),
                // Share
                _MenuTile(
                  icon: Icons.share_rounded,
                  label: 'Share Graph',
                  onTap: () {
                    Navigator.pop(context);
                    // 1H: Canvas Share/Export — gated behind kEnableGraphShareExport
                    if (kEnableGraphShareExport) {
                      _shareGraph();
                    }
                  },
                ),
                const SizedBox(height: 16),
                // Filter chips (old FilterBar content)
                Text(
                  'Filter by Generation',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFC9B4A8),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (int gen = 1; gen <= 5; gen++)
                      _GenChip(
                        label: 'G$gen',
                        color: _genColor(gen),
                        isSelected:
                            _filters.visibleGenerations.contains(gen),
                        onTap: () {
                          final newGens =
                              Set<int>.from(_filters.visibleGenerations);
                          if (newGens.contains(gen)) {
                            newGens.remove(gen);
                          } else {
                            newGens.add(gen);
                          }
                          setState(() {
                            _filters =
                                _filters.copyWith(visibleGenerations: newGens);
                            _invalidateLayoutCache();
                          });
                          Navigator.pop(context);
                        },
                      ),
                    Container(
                      width: 1,
                      height: 20,
                      color: const Color(0xFFE8612A).withValues(alpha: 0.15),
                    ),
                    _GenChip(
                      label: 'All',
                      color: const Color(0xFFE8612A),
                      isSelected: _filters.branch == 'all',
                      onTap: () {
                        setState(() {
                          _filters = _filters.copyWith(branch: 'all');
                          _invalidateLayoutCache();
                        });
                        Navigator.pop(context);
                      },
                    ),
                    _GenChip(
                      label: 'Paternal',
                      color: const Color(0xFFC44A18),
                      isSelected: _filters.branch == 'paternal',
                      onTap: () {
                        setState(() {
                          _filters = _filters.copyWith(branch: 'paternal');
                          _invalidateLayoutCache();
                        });
                        Navigator.pop(context);
                      },
                    ),
                    _GenChip(
                      label: 'Maternal',
                      color: const Color(0xFFF59240),
                      isSelected: _filters.branch == 'maternal',
                      onTap: () {
                        setState(() {
                          _filters = _filters.copyWith(branch: 'maternal');
                          _invalidateLayoutCache();
                        });
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _genColor(int gen) {
    if (gen >= 3) return const Color(0xFFC44A18);
    if (gen == 2) return const Color(0xFFE8612A);
    if (gen == 1) return const Color(0xFFF59240);
    return const Color(0xFFFFB870);
  }

  // ══════════════════════════════════════════════════════════════════
  // KINSHIP LABEL RESOLUTION (Fix Root Cause #1)
  // ══════════════════════════════════════════════════════════════════

  /// Resolves the kinship label for a node relative to the anchor person.
  /// Finds the direct FamilyRelationship edge from anchor → this node,
  /// then uses the relationshipKey to produce a human-readable label.
  String? _resolveKinshipLabel(String nodeId) {
    if (widget.anchorPersonId == null || nodeId == widget.anchorPersonId) {
      return null;
    }
    final anchorId = widget.anchorPersonId!;

    // Find the direct relationship edge between anchor and this node
    final rel = widget.relationships.where((r) => r.isActive).firstWhereOrNull(
      (r) =>
          (r.fromPersonId == anchorId && r.toPersonId == nodeId) ||
          (r.toPersonId == anchorId && r.fromPersonId == nodeId),
    );
    if (rel == null) return null;

    // Determine the correct key direction: from anchor's perspective
    String key;
    if (rel.fromPersonId == anchorId) {
      // Anchor → other, use the relationshipKey directly
      key = rel.relationshipKey;
    } else {
      // Other → anchor, use the inverse
      key = getInverseRelationshipType(rel.relationshipKey);
    }

    // Format the key as a readable label
    return key.replaceAll('_', ' ').toLowerCase();
  }

  /// Compute relative generation level from anchor for each node.
  /// anchor = 0, parents = -1, grandparents = -2,
  /// children = +1, grandchildren = +2, siblings/spouse = 0
  // v9: Robust normalized key matching — handles mixed case, whitespace,
  // underscores, and common Indian family terms (nana, nani, dada, dadi).
  Map<String, int> _computeRelativeLevels(Set<String> nodeIds) {
    final relLevel = <String, int>{};
    if (widget.anchorPersonId == null) return relLevel;
    final anchorId = widget.anchorPersonId!;

    relLevel[anchorId] = 0;

    for (final rel in widget.relationships) {
      if (!rel.isActive) continue;

      // Normalize key: lowercase + collapse whitespace/underscores
      final rawKey = rel.relationshipKey
          .toLowerCase()
          .replaceAll(RegExp(r'[\s]+'), '_');

      final isFromAnchor = rel.fromPersonId == anchorId;
      final isToAnchor   = rel.toPersonId   == anchorId;
      if (!isFromAnchor && !isToAnchor) continue;

      final otherId = isFromAnchor ? rel.toPersonId : rel.fromPersonId;

      // Grandparent of anchor?
      final otherIsGrandparentOfAnchor =
          (isFromAnchor && {'grandchild', 'grandson', 'granddaughter'}.contains(rawKey)) ||
          (isToAnchor   && {
            'grandfather', 'grandmother', 'grandparent',
            'paternal_grandfather', 'paternal_grandmother',
            'maternal_grandfather', 'maternal_grandmother',
            'nana', 'nani', 'dada', 'dadi',
          }.contains(rawKey));

      // Parent of anchor?
      final otherIsParentOfAnchor =
          (isFromAnchor && {'child', 'son', 'daughter'}.contains(rawKey)) ||
          (isToAnchor   && {'father', 'mother', 'parent', 'parent_of',
            'dad', 'mom', 'papa', 'mama'}.contains(rawKey));

      // Same generation (sibling, spouse)?
      final otherIsSameLevel = {
        'brother', 'sister', 'sibling',
        'spouse', 'husband', 'wife',
        'elder_brother', 'younger_brother',
        'elder_sister', 'younger_sister',
        'brother_in_law', 'sister_in_law',
        'twin_brother', 'twin_sister',
      }.contains(rawKey);

      // Child of anchor?
      final otherIsChildOfAnchor =
          (isFromAnchor && {'father', 'mother', 'parent', 'parent_of',
            'dad', 'mom', 'papa', 'mama'}.contains(rawKey)) ||
          (isToAnchor   && {'child', 'son', 'daughter'}.contains(rawKey));

      // Grandchild of anchor?
      final otherIsGrandchildOfAnchor =
          (isFromAnchor && {
            'grandfather', 'grandmother', 'grandparent',
            'paternal_grandfather', 'paternal_grandmother',
            'maternal_grandfather', 'maternal_grandmother',
            'nana', 'nani', 'dada', 'dadi',
          }.contains(rawKey)) ||
          (isToAnchor && {'grandchild', 'grandson', 'granddaughter'}.contains(rawKey));

      if (otherIsGrandparentOfAnchor) {
        relLevel[otherId] = -2;
      } else if (otherIsParentOfAnchor) {
        relLevel[otherId] = -1;
      } else if (otherIsSameLevel) {
        relLevel[otherId] = 0;
      } else if (otherIsChildOfAnchor) {
        relLevel[otherId] = 1;
      } else if (otherIsGrandchildOfAnchor) {
        relLevel[otherId] = 2;
      } else {
        relLevel.putIfAbsent(otherId, () => 0);
      }
    }

    // Ensure every visible node has a level
    for (final id in nodeIds) {
      relLevel.putIfAbsent(id, () => 0);
    }

    return relLevel;
  }

  // ══════════════════════════════════════════════════════════════════
  // TREE BUILDING (preserved logic)
  // ══════════════════════════════════════════════════════════════════

  List<VisTreeNode> _buildTree() {
    var activeMembers =
        widget.members.where((p) => p.deletedAt == null).toList();

    if (!_filters.showDeceased) {
      activeMembers = activeMembers.where((p) => !p.isDeceased).toList();
    }

    final persons = activeMembers.map((p) => p.toGraphPerson()).toList();
    final rels = widget.relationships.map((r) => r.toGraphEdge()).toList();

    if (persons.isEmpty) return [];

    final personMap = {for (final p in persons) p.id: p};

    final childOf = <String, String>{};
    final spouseOf = <String, String>{};
    final lineageOf = <String, String>{};

    for (final rel in rels) {
      final type = rel.type.toLowerCase();
      if (['child', 'son', 'daughter'].contains(type)) {
        childOf[rel.fromId] = rel.toId;
      } else if (['father', 'mother', 'parent'].contains(type)) {
        childOf[rel.toId] = rel.fromId;
      } else if (type == 'spouse' || type == 'husband' || type == 'wife') {
        if (_filters.showMaritalLinks) {
          spouseOf[rel.fromId] = rel.toId;
          spouseOf[rel.toId] = rel.fromId;
        }
      }

      if (type == 'father' ||
          type == 'paternal_grandfather' ||
          type == 'paternal_grandmother') {
        lineageOf[rel.toId] = 'paternal';
      } else if (type == 'mother' ||
          type == 'maternal_grandfather' ||
          type == 'maternal_grandmother') {
        lineageOf[rel.toId] = 'maternal';
      }
    }

    final rootIds = <String>{};
    for (final p in persons) {
      if (!childOf.containsKey(p.id)) {
        rootIds.add(p.id);
      }
    }

    if (rootIds.isEmpty && persons.isNotEmpty) {
      rootIds.add(persons.first.id);
    }

    final childrenOf = <String, List<String>>{};
    for (final entry in childOf.entries) {
      childrenOf.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    final usedIds = <String>{};

    VisTreeNode? buildNode(String id) {
      if (usedIds.contains(id) || !personMap.containsKey(id)) return null;
      usedIds.add(id);

      final person = personMap[id]!;
      final spouseId = spouseOf[id];
      GraphPerson? spouse;
      if (spouseId != null &&
          personMap.containsKey(spouseId) &&
          !usedIds.contains(spouseId)) {
        usedIds.add(spouseId);
        spouse = personMap[spouseId]!;
      }

      final childIds = childrenOf[id] ?? [];
      final childNodes = <VisTreeNode>[];
      for (final childId in childIds) {
        final node = buildNode(childId);
        if (node != null) childNodes.add(node);
      }

      String lineage = lineageOf[id] ?? '';
      if (id == widget.anchorPersonId) lineage = 'self';

      return VisTreeNode(
        person: person,
        spouse: spouse,
        children: childNodes,
        lineage: lineage,
      );
    }

    final roots = <VisTreeNode>[];
    for (final rootId in rootIds) {
      final node = buildNode(rootId);
      if (node != null) roots.add(node);
    }

    for (final p in persons) {
      if (!usedIds.contains(p.id)) {
        roots.add(
          VisTreeNode(
            person: p,
            lineage: p.id == widget.anchorPersonId ? 'self' : '',
          ),
        );
        usedIds.add(p.id);
      }
    }

    return roots;
  }

  // ══════════════════════════════════════════════════════════════════
  // LAYOUT COMPUTATION
  // ══════════════════════════════════════════════════════════════════

  LayoutResult _computeLayout(List<VisTreeNode> roots) {
    final positions = <String, Offset>{};
    final nodes = <String, VisTreeNode>{};
    final lineages = <String, String>{};
    final edges = <VisEdge>[];
    final generations = <String, int>{};
    final memberMap = {for (final m in widget.members) m.id: m};

    // Collect all nodes and edges from the tree
    void collectNodes(VisTreeNode node, int depth) {
      final id = node.person.id;
      nodes[id] = node;
      lineages[id] = node.lineage;
      generations[id] = depth;

      final member = memberMap[id];
      if (member != null && member.generationIndex > 0) {
        generations[id] = member.generationIndex;
      }

      if (node.spouse != null && _filters.showMaritalLinks) {
        final spouseId = node.spouse!.id;
        nodes[spouseId] =
            VisTreeNode(person: node.spouse!, lineage: 'marital');
        lineages[spouseId] = 'marital';
        generations[spouseId] = depth;
        final spouseMember = memberMap[spouseId];
        if (spouseMember != null && spouseMember.generationIndex > 0) {
          generations[spouseId] = spouseMember.generationIndex;
        }

        edges.add(
          VisEdge(
            fromId: id,
            toId: spouseId,
            type: EdgeType.spouse,
            label: 'spouse',
          ),
        );
      }

      for (final child in node.children) {
        edges.add(
          VisEdge(
            fromId: id,
            toId: child.person.id,
            type: EdgeType.parentChild,
            label: 'parent-child',
          ),
        );
        collectNodes(child, depth + 1);
      }
    }

    for (final root in roots) {
      collectNodes(root, 1);
    }

    // Add sibling and in-law edges
    final rels = widget.relationships.map((r) => r.toGraphEdge()).toList();
    final existingEdgeSet = <String>{};
    for (final e in edges) {
      existingEdgeSet.add('${e.fromId}-${e.toId}');
      existingEdgeSet.add('${e.toId}-${e.fromId}');
    }

    for (final rel in rels) {
      final key1 = '${rel.fromId}-${rel.toId}';
      if (existingEdgeSet.contains(key1)) continue;

      final type = rel.type.toLowerCase();
      EdgeType? edgeType;
      if (type.contains('sibling') ||
          type == 'brother' ||
          type == 'sister') {
        edgeType = EdgeType.sibling;
      } else if (type.contains('in_law') || type.contains('inlaw')) {
        edgeType = EdgeType.inLaw;
      }

      if (edgeType != null &&
          nodes.containsKey(rel.fromId) &&
          nodes.containsKey(rel.toId)) {
        edges.add(
          VisEdge(
            fromId: rel.fromId,
            toId: rel.toId,
            type: edgeType,
            label: rel.type,
          ),
        );
        existingEdgeSet.add(key1);
        existingEdgeSet.add('${rel.toId}-${rel.fromId}');
      }
    }

    // ── Resolve kinship labels for each node (Fix Root Cause #1) ──
    final kinshipLabels = <String, String?>{};
    for (final id in nodes.keys) {
      kinshipLabels[id] = _resolveKinshipLabel(id);
    }

    // ── Compute relative generation levels (Fix Root Cause #2) ──
    final relativeLevels = _computeRelativeLevels(nodes.keys.toSet());

    // Compute positions based on layout mode
    // F4-6: For > 300 nodes in force mode, skip simulation (async will handle it)
    switch (_layoutMode) {
      case GraphLayoutMode.hierarchical:
        _computeHierarchicalLayout(
          roots,
          positions,
          nodes,
          lineages,
          generations,
        );
      case GraphLayoutMode.radial:
        _computeRadialLayout(roots, positions, nodes, lineages, generations);
      case GraphLayoutMode.generational:
        _computeGenerationalLayout(
          roots,
          positions,
          nodes,
          lineages,
          generations,
          relativeLevels,
        );
      case GraphLayoutMode.force:
        _computeForceLayout(
          roots,
          positions,
          nodes,
          edges,
          lineages,
          generations,
          skipSimulation: nodes.length > 300,
        );
    }

    // Ensure all nodes have positions
    for (final id in nodes.keys) {
      positions.putIfAbsent(
          id, () => Offset(canvasSize / 2, canvasSize / 2));
    }

    // Compute edge midpoints for tap detection
    final edgeMidpoints = <String, Offset>{};
    for (final edge in edges) {
      final fromPos = positions[edge.fromId];
      final toPos = positions[edge.toId];
      if (fromPos != null && toPos != null) {
        final mid = Offset((fromPos.dx + toPos.dx) / 2, (fromPos.dy + toPos.dy) / 2);
        edgeMidpoints['${edge.fromId}|${edge.toId}'] = mid;
      }
    }

    return LayoutResult(
      positions: positions,
      nodes: nodes,
      nodeLineages: lineages,
      edges: edges,
      nodeGenerations: generations,
      kinshipLabels: kinshipLabels,
      relativeLevels: relativeLevels,
      edgeMidpoints: edgeMidpoints,
    );
  }

  // ── Hierarchical layout (top-down tree) ─────────────────────────

  void _computeHierarchicalLayout(
    List<VisTreeNode> roots,
    Map<String, Offset> positions,
    Map<String, VisTreeNode> nodes,
    Map<String, String> lineages,
    Map<String, int> generations,
  ) {
    final startY = canvasSize / 3;
    final startX = canvasSize / 4;
    double xOffset = startX;

    double layoutSubtree(VisTreeNode node, double xOff, double yOff) {
      final hasSpouse = node.spouse != null;
      final coupleWidth = hasSpouse ? nodeRadius * 4 + 30 : nodeRadius * 2;

      if (node.children.isEmpty) {
        positions[node.person.id] = Offset(xOff + nodeRadius, yOff);
        if (hasSpouse) {
          positions[node.spouse!.id] =
              Offset(xOff + nodeRadius * 3 + 30, yOff);
        }
        return coupleWidth;
      }

      double childX = xOff;
      double maxChildWidth = 0;

      for (final child in node.children) {
        final w = layoutSubtree(child, childX, yOff + verticalGap);
        maxChildWidth += w + horizontalGap / 2;
        childX += w + horizontalGap / 2;
      }
      maxChildWidth -= horizontalGap / 2;

      final centerX = xOff + maxChildWidth / 2;
      positions[node.person.id] = Offset(centerX, yOff);

      if (hasSpouse) {
        positions[node.spouse!.id] = Offset(
          centerX + nodeRadius * 2 + 30,
          yOff,
        );
      }

      return math.max(maxChildWidth, coupleWidth);
    }

    final double yOffset = startY;
    for (final root in roots) {
      final width = layoutSubtree(root, xOffset, yOffset);
      xOffset += width + horizontalGap;
    }
  }

  // ── Radial layout (centered on "You") ───────────────────────────

  void _computeRadialLayout(
    List<VisTreeNode> roots,
    Map<String, Offset> positions,
    Map<String, VisTreeNode> nodes,
    Map<String, String> lineages,
    Map<String, int> generations,
  ) {
    final center = Offset(canvasSize / 2, canvasSize / 2);

    // Place anchor in center
    if (widget.anchorPersonId != null) {
      positions[widget.anchorPersonId!] = center;
    }

    // Group by generation
    final byGeneration = <int, List<String>>{};
    for (final entry in generations.entries) {
      if (entry.key == widget.anchorPersonId) continue;
      byGeneration.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    for (final entry in byGeneration.entries) {
      final gen = entry.key;
      final ids = entry.value;
      final ringRadius = gen == 1 ? 120.0 : 120.0 + 100.0 * (gen - 1);
      final angleStep = 2 * math.pi / math.max(ids.length, 1);

      for (int i = 0; i < ids.length; i++) {
        if (positions.containsKey(ids[i])) continue;
        final angle = angleStep * i - math.pi / 2;
        positions[ids[i]] = Offset(
          center.dx + ringRadius * math.cos(angle),
          center.dy + ringRadius * math.sin(angle),
        );
      }
    }

    // Fallback
    double fallbackX = 100;
    for (final id in nodes.keys) {
      if (!positions.containsKey(id)) {
        positions[id] = Offset(fallbackX, canvasSize / 2);
        fallbackX += horizontalGap;
      }
    }
  }

  // ── Generational layout (Y-axis hierarchy: Parents above, Self center, Children below)
  //    Fix Root Cause #2 & #6: Replaces radial scatter with strict vertical hierarchy

  void _computeGenerationalLayout(
    List<VisTreeNode> roots,
    Map<String, Offset> positions,
    Map<String, VisTreeNode> nodes,
    Map<String, String> lineages,
    Map<String, int> generations,
    Map<String, int> relativeLevels,
  ) {
    const double centerX = canvasSize / 2;
    const double centerY = canvasSize / 2;
    // v9: Increased spacing so nodes at the same level don't overlap.
    const double levelHeight = 220.0; // vertical gap between generations
    const double nodeSpacing = 170.0; // horizontal gap between siblings

    if (widget.anchorPersonId == null) {
      // Fallback to radial if no anchor
      _computeRadialLayout(roots, positions, nodes, lineages, generations);
      return;
    }

    // Group nodes by relative level
    final byLevel = <int, List<String>>{};
    for (final entry in relativeLevels.entries) {
      if (nodes.containsKey(entry.key)) {
        byLevel.putIfAbsent(entry.value, () => []).add(entry.key);
      }
    }

    // Assign positions — Y from level, X evenly spaced
    for (final entry in byLevel.entries) {
      final level = entry.key;
      final ids = entry.value;
      final y = centerY + level * levelHeight;
      final totalWidth = (ids.length - 1) * nodeSpacing;
      double startX = centerX - totalWidth / 2;

      // Keep anchor in the center of its row
      if (ids.contains(widget.anchorPersonId!)) {
        final anchorIdx = ids.indexOf(widget.anchorPersonId!);
        // Reorder so anchor is at center
        final reordered = <String>[...ids];
        reordered.removeAt(anchorIdx);
        reordered.insert(reordered.length ~/ 2, widget.anchorPersonId!);
        for (int i = 0; i < reordered.length; i++) {
          positions[reordered[i]] = Offset(startX + i * nodeSpacing, y);
        }
      } else {
        for (int i = 0; i < ids.length; i++) {
          positions[ids[i]] = Offset(startX + i * nodeSpacing, y);
        }
      }
    }

    // v9: Ensure spouse pairs sit side by side
    for (final node in nodes.values) {
      if (node.spouse == null) continue;
      final myPos = positions[node.person.id];
      if (myPos == null) continue;
      if (!positions.containsKey(node.spouse!.id)) {
        positions[node.spouse!.id] = Offset(myPos.dx + nodeSpacing, myPos.dy);
      }
    }

    // Fallback: ensure all nodes have positions
    double fallbackX = 100;
    for (final id in nodes.keys) {
      if (!positions.containsKey(id)) {
        positions[id] = Offset(fallbackX, centerY);
        fallbackX += nodeSpacing;
      }
    }
  }

  // ── Force-directed layout ────────────────────────────────────────

  void _computeForceLayout(
    List<VisTreeNode> roots,
    Map<String, Offset> positions,
    Map<String, VisTreeNode> nodes,
    List<VisEdge> edges,
    Map<String, String> lineages,
    Map<String, int> generations, {
    bool skipSimulation = false,
  }) {
    const double repulsionStrength = 6000;
    const double attractionStrength = 0.004;
    const double gravityStrength = 0.008;
    const double damping = 0.82;
    const double idealEdgeLength = 150;
    const int maxSteps = 80;

    final center = Offset(canvasSize / 2, canvasSize / 2);
    final allIds = nodes.keys.toList();

    // Initialize positions if needed
    if (_forcePositions.length != allIds.length ||
        !_forcePositions.keys.toSet().containsAll(allIds)) {
      final tempPositions = <String, Offset>{};
      _computeHierarchicalLayout(
        roots,
        tempPositions,
        nodes,
        lineages,
        generations,
      );

      for (final id in allIds) {
        _forcePositions[id] = tempPositions[id] ??
            Offset(
              center.dx + (math.Random().nextDouble() - 0.5) * 300,
              center.dy + (math.Random().nextDouble() - 0.5) * 300,
            );
      }
      _forceVelocities = {for (final id in allIds) id: Offset.zero};
    }

    // F4-6: Skip simulation for large graphs (handled async via compute)
    if (!skipSimulation) {
      // Run simulation
      for (int step = 0; step < maxSteps; step++) {
        final forces = <String, Offset>{
          for (final id in allIds) id: Offset.zero,
        };

        // Repulsion
        for (int i = 0; i < allIds.length; i++) {
          for (int j = i + 1; j < allIds.length; j++) {
            final a = allIds[i];
            final b = allIds[j];
            final delta = _forcePositions[a]! - _forcePositions[b]!;
            final dist = math.max(delta.distance, 0.1);
            final force = repulsionStrength / (dist * dist);
            final direction = delta / dist;
            forces[a] = forces[a]! + direction * force;
            forces[b] = forces[b]! - direction * force;
          }
        }

        // Attraction
        for (final edge in edges) {
          if (!_forcePositions.containsKey(edge.fromId) ||
              !_forcePositions.containsKey(edge.toId)) {
            continue;
          }
          final delta =
              _forcePositions[edge.toId]! - _forcePositions[edge.fromId]!;
          final dist = math.max(delta.distance, 0.1);
          final force = attractionStrength * (dist - idealEdgeLength);
          final direction = delta / dist;
          forces[edge.fromId] = forces[edge.fromId]! + direction * force;
          forces[edge.toId] = forces[edge.toId]! - direction * force;
        }

        // Gravity
        for (final id in allIds) {
          final delta = center - _forcePositions[id]!;
          forces[id] = forces[id]! + delta * gravityStrength;
        }

        // Apply
        for (final id in allIds) {
          final vel =
              (_forceVelocities[id] ?? Offset.zero) + forces[id]!;
          _forceVelocities[id] = vel * damping;
          _forcePositions[id] = _forcePositions[id]! + _forceVelocities[id]!;
        }
      }
    }

    for (final id in allIds) {
      positions[id] = _forcePositions[id]!;
    }
  }

  // ── F4-6: Async force layout for large graphs using compute() ────

  Future<void> _computeForceLayoutAsync(
    LayoutResult currentLayout,
    int startVersion,
  ) async {
    _isAsyncComputing = true;

    final allIds = currentLayout.nodes.keys.toList();
    final simEdges = currentLayout.edges
        .map((e) => _SimEdge(fromId: e.fromId, toId: e.toId))
        .toList();

    // Prepare initial positions from _forcePositions or current layout
    final inputPositions = <String, Offset>{};
    for (final id in allIds) {
      inputPositions[id] = _forcePositions[id] ??
          currentLayout.positions[id] ??
          Offset(canvasSize / 2, canvasSize / 2);
    }
    final inputVelocities = <String, Offset>{};
    for (final id in allIds) {
      inputVelocities[id] = _forceVelocities[id] ?? Offset.zero;
    }

    final input = _ForceSimInput(
      positions: inputPositions,
      velocities: inputVelocities,
      edges: simEdges,
      allIds: allIds,
      centerX: canvasSize / 2,
      centerY: canvasSize / 2,
    );

    try {
      final result = await compute(_runForceSimulationIsolate, input);

      if (!mounted) {
        _isAsyncComputing = false;
        return;
      }

      // Only apply if layout hasn't been recomputed since we started
      if (_layoutVersion == startVersion) {
        _forcePositions
          ..clear()
          ..addAll(result.positions);
        _forceVelocities
          ..clear()
          ..addAll(result.velocities);

        // Rebuild cached layout with force-directed positions
        final newPositions =
            Map<String, Offset>.from(currentLayout.positions);
        for (final id in result.positions.keys) {
          newPositions[id] = result.positions[id]!;
        }

        setState(() {
          _cachedLayout = LayoutResult(
            positions: newPositions,
            nodes: currentLayout.nodes,
            nodeLineages: currentLayout.nodeLineages,
            edges: currentLayout.edges,
            nodeGenerations: currentLayout.nodeGenerations,
            kinshipLabels: currentLayout.kinshipLabels,
            relativeLevels: currentLayout.relativeLevels,
          );
          _cachedPositions = Map<String, Offset>.from(newPositions);
          _layoutVersion++;
          _isAsyncComputing = false;
        });
      } else {
        // Layout was invalidated while computing; discard result
        _isAsyncComputing = false;
      }
    } catch (_) {
      _isAsyncComputing = false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ACCESSIBILITY NODE OVERLAY — Screen reader support for graph nodes
// ═══════════════════════════════════════════════════════════════════════

/// An invisible overlay that places [Semantics] nodes at each graph
/// node position. This allows TalkBack / VoiceOver users to navigate
/// the family tree by swiping through nodes, hearing each person's
/// name and relation.
///
/// The overlay uses [IgnorePointer] so it does not intercept taps;
/// real touch handling is done by the [GestureDetector] beneath.
class _AccessibilityNodeOverlay extends StatelessWidget {
  const _AccessibilityNodeOverlay({
    required this.layout,
    required this.members,
    required this.selectedNodeId,
    required this.anchorPersonId,
    required this.transformationController,
  });

  final LayoutResult layout;
  final List<Person> members;
  final String? selectedNodeId;
  final String? anchorPersonId;
  final TransformationController transformationController;

  @override
  Widget build(BuildContext context) {
    if (layout.positions.isEmpty) return const SizedBox.shrink();

    final memberMap = {for (final m in members) m.id: m};
    final screenSize = MediaQuery.of(context).size;

    return Stack(
      children: layout.positions.entries.map((entry) {
        final id = entry.key;
        final pos = entry.value;
        final person = memberMap[id];
        final name = person?.name ?? 'Unknown';
        final lineage = layout.nodeLineages[id] ?? '';
        final generation = layout.nodeGenerations[id];
        final isSelected = id == selectedNodeId;
        final isAnchor = id == anchorPersonId;

        // Build a descriptive semantic label
        final parts = <String>[name];
        if (isAnchor) parts.add('You');
        if (lineage.isNotEmpty && lineage != 'self') {
          parts.add('${lineage} lineage');
        }
        if (generation != null) parts.add('Generation $generation');
        if (isSelected) parts.add('Selected');

        // Find edges involving this node for relation info
        final relations = layout.edges
            .where((e) => e.fromId == id || e.toId == id)
            .map((e) {
          final otherId = e.fromId == id ? e.toId : e.fromId;
          final otherName = memberMap[otherId]?.name ?? 'Unknown';
          final label = e.label ?? e.type.name;
          return '$label: $otherName';
        }).join('; ');

        final semanticLabel = parts.join(', ');
        final semanticHint = relations.isNotEmpty
            ? 'Relations: $relations'
            : 'No relations';

        // Transform graph position to screen position
        final transform = transformationController.value;
        final screenPos = MatrixUtils.transformPoint(transform, pos);

        // Only show nodes that are roughly on-screen
        if (screenPos.dx < -100 ||
            screenPos.dx > screenSize.width + 100 ||
            screenPos.dy < -100 ||
            screenPos.dy > screenSize.height + 100) {
          return const SizedBox.shrink();
        }

        return Positioned(
          left: screenPos.dx - 24,
          top: screenPos.dy - 24,
          child: Semantics(
            button: true,
            label: semanticLabel,
            hint: semanticHint,
            selected: isSelected,
            child: const SizedBox(width: 48, height: 48),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CONSTELLATION PAINTER — Full canvas rendering
// ═══════════════════════════════════════════════════════════════════════

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.layout,
    required this.scale,
    required this.selectedNodeId,
    required this.anchorPersonId,
    required this.showLabels,
    required this.showGenBands,
    required this.ambientValue,
    required this.pulseValue,
    required this.members,
    required this.visibleRect,
    required this.previousPositions, // Change 8
    required this.layoutTransitionValue, // Change 8
  });

  final LayoutResult layout;
  final double scale;
  final String? selectedNodeId;
  final String? anchorPersonId;
  final bool showLabels;
  final bool showGenBands;
  final double ambientValue;
  final double pulseValue;
  final List<Person> members;
  final Rect visibleRect; // F4-2: Viewport rect for culling
  final Map<String, Offset> previousPositions; // Change 8
  final double layoutTransitionValue; // Change 8

  // ── Design constants ────────────────────────────────────────────
  static const double nodeRadius = 40.0; // Change 9: was 24.0
  static const double nodeRadiusSelected = 44.0; // Change 9: was 26.4
  static const double ringWidth = 2.0;
  static const double nameFontSize = 12.0;
  static const double kinshipFontSize = 11.0;

  // Generation ring colors
  static const Color genGrandparent = Color(0xFFC44A18);
  static const Color genParent = Color(0xFFE8612A);
  static const Color genUser = Color(0xFFF59240);
  static const Color genChild = Color(0xFFFFB870);

  // Edge colors
  static const Color spouseEdgeColor = Color(0xFFE8612A);
  static const Color parentChildEdgeColor = Color(0xFFE8612A);
  static const Color siblingEdgeColor = Color(0xFFF59240);
  static const Color inLawEdgeColor = Color(0xFFF59240);

  // ── F4-1: shouldRepaint with strict equality checks ─────────────

  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) {
    return !identical(oldDelegate.layout, layout) ||
        oldDelegate.scale != scale ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.anchorPersonId != anchorPersonId ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.showGenBands != showGenBands ||
        oldDelegate.ambientValue != ambientValue ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.layoutTransitionValue != layoutTransitionValue ||
        !identical(oldDelegate.members, members);
  }

  // ── Helpers ─────────────────────────────────────────────────────

  // Change 8: Lerp position for layout transitions
  Offset _lerpedPosition(String id, Offset current) {
    final prev = previousPositions[id];
    if (prev == null) return current;
    return Offset.lerp(prev, current, layoutTransitionValue) ?? current;
  }

  Color _generationRingColor(int generation) {
    if (generation >= 3) return genGrandparent;
    if (generation == 2) return genParent;
    if (generation == 1) return genUser;
    return genChild;
  }

  /// Category-aware node fill color based on relationship to anchor.
  /// Fix Root Cause #3: Parents=blue, Self=teal, Siblings=slate, Children=rose
  Color _nodeFillColor(String id, bool isDeceased) {
    if (isDeceased) return const Color(0xFF3A3A4E);
    if (id == anchorPersonId) return const Color(0xFF00B4A6); // teal for You
    final label = layout.kinshipLabels[id]?.toLowerCase() ?? '';
    if (label.contains('father') ||
        label.contains('mother') ||
        label.contains('grandfather') ||
        label.contains('grandmother') ||
        label.contains('parent')) {
      return const Color(0xFF2E6B8A); // blue for parents/grandparents
    }
    if (label.contains('son') ||
        label.contains('daughter') ||
        label.contains('child')) {
      return const Color(0xFF8A3A3A); // rose for children
    }
    if (label.contains('brother') ||
        label.contains('sister') ||
        label.contains('sibling')) {
      return const Color(0xFF4A4A6A); // slate for siblings
    }
    if (label.contains('spouse') ||
        label.contains('husband') ||
        label.contains('wife')) {
      return const Color(0xFF6B4A8A); // purple for spouse
    }
    // Fallback: use relative level if no label
    final level = layout.relativeLevels[id] ?? 0;
    if (level < 0) return const Color(0xFF2E6B8A); // blue for ancestors
    if (level > 0) return const Color(0xFF8A3A3A); // rose for descendants
    return const Color(0xFF3D3E55); // default muted
  }

  /// Create a gradient from a fill color for node body rendering
  LinearGradient _categoryGradient(String id, bool isDeceased) {
    if (isDeceased) {
      return const LinearGradient(
        colors: [Color(0xFF4A4A5E), Color(0xFF2A2A3E)],
      );
    }
    final fillColor = _nodeFillColor(id, isDeceased);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        fillColor.withValues(alpha: 0.9),
        fillColor.withValues(alpha: 0.6),
      ],
    );
  }

  /// Category-aware ring color matching the fill category
  Color _nodeRingColor(String id, bool isDeceased, int generation) {
    if (isDeceased) return const Color(0xFF4A4A5E);
    if (id == anchorPersonId) return const Color(0xFF00B4A6);
    final label = layout.kinshipLabels[id]?.toLowerCase() ?? '';
    if (label.contains('father') ||
        label.contains('mother') ||
        label.contains('grandfather') ||
        label.contains('grandmother') ||
        label.contains('parent')) {
      return const Color(0xFF4A9FBF); // lighter blue ring for parents
    }
    if (label.contains('son') ||
        label.contains('daughter') ||
        label.contains('child')) {
      return const Color(0xFFBF4A4A); // lighter rose ring for children
    }
    if (label.contains('brother') ||
        label.contains('sister') ||
        label.contains('sibling')) {
      return const Color(0xFF6A6A8A); // lighter slate ring for siblings
    }
    if (label.contains('spouse') ||
        label.contains('husband') ||
        label.contains('wife')) {
      return const Color(0xFF9A6ABF); // lighter purple ring for spouse
    }
    // Fallback to generation ring color
    final level = layout.relativeLevels[id] ?? 0;
    if (level < 0) return const Color(0xFF4A9FBF);
    if (level > 0) return const Color(0xFFBF4A4A);
    return _generationRingColor(generation);
  }

  Offset _ambientOffset(String id) {
    final phase = id.hashCode * 0.1;
    final dx = math.sin(ambientValue * 2 * math.pi + phase) * 1.5;
    final dy = math.cos(ambientValue * 2 * math.pi + phase * 0.7) * 1.5;
    return Offset(dx, dy);
  }

  // ── Main paint ──────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    // Night sky background
    final bgPaint = Paint()..color = const Color(0xFF131416);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    if (layout.positions.isEmpty) return;

    // ── Star field ───────────────────────────────────────────────
    _drawStarfield(canvas, size);

    // ── Generation bands (optional concentric rings) ─────────────
    if (showGenBands) {
      _drawGenerationBands(canvas, size);
    }

    // ── Zone labels (Fix Root Cause #4: PARENTS/SELF/CHILDREN) ────
    _drawZoneLabels(canvas);

    // ── F4-2: Viewport culling ────────────────────────────────────
    // Expand viewport rect by node radius + margin for culling
    final cullRect = visibleRect.inflate(nodeRadiusSelected + 20);

    // ── Edges (skip if BOTH endpoints outside viewport) ──────────
    for (final edge in layout.edges) {
      final rawFromPos = layout.positions[edge.fromId];
      final rawToPos = layout.positions[edge.toId];
      if (rawFromPos == null || rawToPos == null) continue;

      // Change 8: Use lerped positions for edges, plus ambient offset
      final fromPos = _lerpedPosition(edge.fromId, rawFromPos) + _ambientOffset(edge.fromId);
      final toPos = _lerpedPosition(edge.toId, rawToPos) + _ambientOffset(edge.toId);

      // Cull edges where both endpoints are outside the viewport
      final fromVisible = cullRect.contains(fromPos);
      final toVisible = cullRect.contains(toPos);
      if (!fromVisible && !toVisible) continue;

      _drawEdge(canvas, edge, fromPos, toPos);
    }

    // ── Nodes (selected last so it renders on top) ───────────────
    final sortedIds = layout.positions.keys.toList()
      ..sort((a, b) {
        if (a == selectedNodeId) return 1;
        if (b == selectedNodeId) return -1;
        if (a == anchorPersonId) return 1;
        if (b == anchorPersonId) return -1;
        return 0;
      });

    for (final id in sortedIds) {
      final rawPos = layout.positions[id]!;

      // Change 8: Lerp positions for transition
      final lerpedPos = _lerpedPosition(id, rawPos);

      // Cull nodes whose center + radius is outside viewport
      if (!cullRect.contains(lerpedPos)) continue;

      final ambient = _ambientOffset(id);
      _drawNode(canvas, id, lerpedPos + ambient);
    }
  }

  // ── Star field (night sky effect) ────────────────────────────────

  void _drawStarfield(Canvas canvas, Size size) {
    final random = math.Random(42);
    for (int i = 0; i < 80; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final opacity = 0.02 + random.nextDouble() * 0.06;
      final radius = 0.3 + random.nextDouble() * 1.0;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = const Color(0xFFF5F0EE).withValues(alpha: opacity),
      );
    }
  }

  // ── Generation bands ─────────────────────────────────────────────

  void _drawGenerationBands(Canvas canvas, Size size) {
    if (layout.nodeGenerations.isEmpty) return;

    final center =
        layout.positions[anchorPersonId] ?? layout.positions.values.first;

    final maxGen = layout.nodeGenerations.values.fold(0, math.max);
    final minGen = layout.nodeGenerations.values.fold(100, math.min);

    for (int gen = minGen; gen <= maxGen; gen++) {
      final radius = (gen - minGen + 1) * 140.0;
      final ringPaint = Paint()
        ..color = _generationRingColor(gen).withValues(alpha: 0.05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      canvas.drawCircle(center, radius, ringPaint);

      if (showLabels && scale > 0.5) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: 'Gen $gen',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              color: _generationRingColor(gen).withValues(alpha: 0.2),
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        labelPainter.layout();
        labelPainter.paint(
          canvas,
          Offset(center.dx - labelPainter.width / 2,
              center.dy - radius - 14),
        );
      }
    }
  }

  // ── Zone labels (Fix Root Cause #4: PARENTS/SELF/CHILDREN pills) ──

  void _drawZoneLabels(Canvas canvas) {
    if (anchorPersonId == null) return;
    final anchorPos = layout.positions[anchorPersonId];
    if (anchorPos == null) return;

    const double levelHeight = 180.0;
    final zones = [
      (-2, 'GRANDPARENTS', const Color(0xFF4A9FBF)),
      (-1, 'PARENTS', const Color(0xFF4A9FBF)),
      (0, 'SELF & SIBLINGS', const Color(0xFF00B4A6)),
      (1, 'CHILDREN', const Color(0xFFBF4A4A)),
      (2, 'GRANDCHILDREN', const Color(0xFFBF4A4A)),
    ];

    for (final (level, label, color) in zones) {
      // Only draw label if any node is at this level
      final y = anchorPos.dy + level * levelHeight;
      final hasNodes = layout.positions.values.any(
        (p) => (p.dy - y).abs() < 40,
      );
      if (!hasNodes) continue;

      final pill = RRect.fromRectAndRadius(
        Rect.fromLTWH(anchorPos.dx - 340, y - 12, 110, 24),
        const Radius.circular(12),
      );
      canvas.drawRRect(pill, Paint()..color = color.withValues(alpha: 0.15));

      final dotOffset = Offset(anchorPos.dx - 325, y);
      canvas.drawCircle(dotOffset, 4, Paint()..color = color);

      final labelPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 0.8,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      labelPainter.layout();
      labelPainter.paint(canvas, Offset(anchorPos.dx - 315, y - 6));
    }
  }

  // ── Edge drawing ─────────────────────────────────────────────────
  // v16: Dashed orange glow lines matching the reference design.
  // All edges use the same warm orange color with dashed pattern,
  // glow effect, and connection dots. Spouse edges get a heart icon.
  void _drawEdge(Canvas canvas, VisEdge edge, Offset start, Offset end) {
    if ((end - start).distance < 1) return;

    final isConnectedToSelected =
        edge.fromId == selectedNodeId || edge.toId == selectedNodeId;

    // v16: Unified warm orange color for all edges (matching reference)
    const Color lineColor = Color(0xFFE8612A);
    final effectiveColor =
        isConnectedToSelected ? lineColor : lineColor;

    // Shorten endpoints so lines don't pass under node circles
    final dir = end - start;
    final dist = dir.distance;
    final unit = dir / dist;
    const double nodeR = nodeRadius; // 40.0
    final trimmedStart = start + unit * (nodeR + 4);
    final trimmedEnd = end - unit * (nodeR + 4);
    if ((trimmedEnd - trimmedStart).distance < 10) return;

    final strokeWidth = isConnectedToSelected ? 2.5 : 2.0;
    final alpha = isConnectedToSelected ? 1.0 : 0.8;

    // Glow paint (soft blur behind dashed line)
    final glowPaint = Paint()
      ..color = effectiveColor.withValues(alpha: isConnectedToSelected ? 0.35 : 0.20)
      ..strokeWidth = strokeWidth + 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    // Main dashed line paint
    final linePaint = Paint()
      ..color = effectiveColor.withValues(alpha: alpha)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // v16: Dashed pattern — 8px dash, 5px gap (matching reference)
    const double dashLen = 8.0;
    const double gapLen = 5.0;

    if (edge.type == EdgeType.parentChild) {
      // Parent→Child: smooth bezier curve with dashed pattern
      final controlPoint = Offset(
        (trimmedStart.dx + trimmedEnd.dx) / 2,
        trimmedStart.dy + (trimmedEnd.dy - trimmedStart.dy) * 0.35,
      );
      final path = Path()
        ..moveTo(trimmedStart.dx, trimmedStart.dy)
        ..quadraticBezierTo(
            controlPoint.dx, controlPoint.dy,
            trimmedEnd.dx, trimmedEnd.dy);

      // Draw glow (solid, not dashed — gives soft halo)
      canvas.drawPath(path, glowPaint);

      // Draw dashed line along the bezier path
      _drawDashedPath(canvas, path, linePaint, dashLen, gapLen);

      // Small arrowhead to show direction (parent → child)
      _drawArrowhead(canvas, trimmedStart, trimmedEnd, linePaint);

    } else if (edge.type == EdgeType.spouse) {
      // Spouse: straight dashed line + heart icon at midpoint
      _drawDashedLine(canvas, trimmedStart, trimmedEnd, glowPaint, dashLen, gapLen);
      _drawDashedLine(canvas, trimmedStart, trimmedEnd, linePaint, dashLen, gapLen);
      _drawHeartAtMidpoint(canvas, start, end);

    } else {
      // Sibling / inLaw / unknown: straight dashed line + connection dot
      _drawDashedLine(canvas, trimmedStart, trimmedEnd, glowPaint, dashLen, gapLen);
      _drawDashedLine(canvas, trimmedStart, trimmedEnd, linePaint, dashLen, gapLen);

      // Glowing connection dot at midpoint
      final mid = Offset(
        (trimmedStart.dx + trimmedEnd.dx) / 2,
        (trimmedStart.dy + trimmedEnd.dy) / 2,
      );
      // Glow halo behind dot
      canvas.drawCircle(mid, 10.0, Paint()
        ..color = effectiveColor.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      // Solid dot
      canvas.drawCircle(mid, 5.5, Paint()
        ..color = effectiveColor.withValues(alpha: alpha));
      // White center highlight
      canvas.drawCircle(mid, 2.0, Paint()
        ..color = Colors.white.withValues(alpha: 0.65));
    }

    // v16: Small glowing dots at both connection points (start + end)
    // These mark where the line meets the node edge
    _drawConnectionDot(canvas, trimmedStart, effectiveColor, alpha);
    _drawConnectionDot(canvas, trimmedEnd, effectiveColor, alpha);
  }

  /// Draws a small glowing dot at a connection point (where line meets node).
  void _drawConnectionDot(Canvas canvas, Offset pos, Color color, double alpha) {
    // Glow halo
    canvas.drawCircle(pos, 6.0, Paint()
      ..color = color.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    // Solid dot
    canvas.drawCircle(pos, 3.0, Paint()
      ..color = color.withValues(alpha: alpha));
    // White center
    canvas.drawCircle(pos, 1.0, Paint()
      ..color = Colors.white.withValues(alpha: 0.5));
  }

  /// Draws a dashed line between two points.
  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dashLen,
    double gapLen,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance == 0) return;
    final steps = (distance / (dashLen + gapLen)).floor();
    for (int i = 0; i < steps; i++) {
      final s = i * (dashLen + gapLen) / distance;
      final e = math.min((i * (dashLen + gapLen) + dashLen) / distance, 1.0);
      canvas.drawLine(
        Offset(start.dx + dx * s, start.dy + dy * s),
        Offset(start.dx + dx * e, start.dy + dy * e),
        paint,
      );
    }
  }

  /// Draws a dashed path along a Path (for bezier curves).
  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint,
    double dashLen,
    double gapLen,
  ) {
    for (final ui.PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final double len = draw ? dashLen : gapLen;
        final double next = (distance + len).clamp(0.0, metric.length);
        if (draw) {
          final tangent = metric.getTangentForOffset(distance);
          if (tangent != null) {
            final endTangent = metric.getTangentForOffset(next);
            if (endTangent != null) {
              canvas.drawLine(
                tangent.position,
                endTangent.position,
                paint,
              );
            }
          }
        }
        distance = next;
        draw = !draw;
      }
    }
  }

  // Change 10D: Draw arrowhead for parent→child edges
  void _drawArrowhead(Canvas canvas, Offset from, Offset to, Paint paint) {
    final direction = (to - from);
    final distance = direction.distance;
    if (distance < 1) return;
    final unitDir = direction / distance;
    final arrowSize = 6.0;
    // Position arrow at the edge of the target node
    final tipPos = to - unitDir * nodeRadius;
    final perpDir = Offset(-unitDir.dy, unitDir.dx);
    final path = Path()
      ..moveTo(tipPos.dx, tipPos.dy)
      ..lineTo(
          tipPos.dx -
              unitDir.dx * arrowSize +
              perpDir.dx * arrowSize * 0.5,
          tipPos.dy -
              unitDir.dy * arrowSize +
              perpDir.dy * arrowSize * 0.5)
      ..lineTo(
          tipPos.dx -
              unitDir.dx * arrowSize -
              perpDir.dx * arrowSize * 0.5,
          tipPos.dy -
              unitDir.dy * arrowSize -
              perpDir.dy * arrowSize * 0.5)
      ..close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  void _drawHeartAtMidpoint(Canvas canvas, Offset start, Offset end) {
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    // v2 (2026-06-23): Spouse heart is now PINK #EC4899 per the
    // central edge color & midpoint spec. Previously it was orange
    // which made it indistinguishable from every other edge dot.
    final heartPainter = TextPainter(
      text: const TextSpan(
        text: '\u2764',
        style: TextStyle(fontSize: 12, color: Color(0xFFEC4899)),
      ),
      textDirection: TextDirection.ltr,
    );
    heartPainter.layout();
    heartPainter.paint(
      canvas,
      Offset(mid.dx - heartPainter.width / 2,
          mid.dy - heartPainter.height / 2),
    );
  }

  // ── Node drawing with Level-of-Detail (F4-4) ────────────────────

  /// LOD 0: Circle only, no text, no avatar details (zoom < 0.25)
  void _drawNodeLod0(
    Canvas canvas,
    Offset center,
    double radius,
    Color ringColor,
    bool isDeceased,
    bool isSelected,
    bool isAnchor,
    String id, // Added for category-aware coloring
  ) {
    // Use category-aware ring color
    final categoryRingColor = isAnchor
        ? const Color(0xFF00B4A6)
        : _nodeRingColor(id, isDeceased, 1);

    // Minimal selection indicator
    if (isSelected) {
      final glowPaint = Paint()
        ..color = const Color(0xFFE8612A).withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, radius + 4, glowPaint);
    }

    // Change 3: Anchor double ring at LOD0
    if (isAnchor) {
      final anchorGlow = Paint()
        ..color = const Color(0xFF00B4A6).withValues(alpha: 0.2 + pulseValue * 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, radius + 6, anchorGlow);
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()
          ..color = const Color(0xFF00B4A6).withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      canvas.drawCircle(
        center,
        radius + ringWidth,
        Paint()
          ..color = const Color(0xFF00B4A6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    } else {
      // Category-aware ring
      final ringPaint = Paint()
        ..color = categoryRingColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth;
      canvas.drawCircle(center, radius + ringWidth, ringPaint);
    }

    // Simplified body — category-aware color
    final fillColor = _nodeFillColor(id, isDeceased);
    final bodyPaint = Paint()
      ..color = isDeceased
          ? const Color(0xFF3A3A4E)
          : fillColor.withValues(alpha: 0.7);
    canvas.drawCircle(center, radius, bodyPaint);
  }

  /// LOD 1: Circle + name text only (zoom 0.25–0.5)
  void _drawNodeLod1(
    Canvas canvas,
    Offset center,
    double radius,
    Color ringColor,
    bool isDeceased,
    String name,
    String? relationship,
    bool isSelected,
    bool isAnchor,
    String id, // Added for category-aware coloring
  ) {
    // Use category-aware ring color
    final categoryRingColor = isAnchor
        ? const Color(0xFF00B4A6)
        : _nodeRingColor(id, isDeceased, 1);

    // Selection glow (simplified)
    if (isSelected) {
      final glowAlpha = 0.2 + pulseValue * 0.15;
      final glowPaint = Paint()
        ..color = const Color(0xFFE8612A).withValues(alpha: glowAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(center, radius + 8, glowPaint);
    }

    // Change 3: Anchor glow at LOD1
    if (isAnchor && !isSelected) {
      final anchorGlow = Paint()
        ..color = const Color(0xFF00B4A6).withValues(alpha: 0.2 + pulseValue * 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, radius + 6, anchorGlow);
      // Double ring
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()
          ..color = const Color(0xFF00B4A6).withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      canvas.drawCircle(
        center,
        radius + ringWidth,
        Paint()
          ..color = const Color(0xFF00B4A6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    } else {
      // Category-aware ring
      final ringPaint = Paint()
        ..color = categoryRingColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth;
      canvas.drawCircle(center, radius + ringWidth, ringPaint);
    }

    // Node body (category-aware gradient)
    final gradient = _categoryGradient(id, isDeceased);
    final bodyRect = Rect.fromCircle(center: center, radius: radius);
    final bodyPaint = Paint()..shader = gradient.createShader(bodyRect);
    canvas.drawCircle(center, radius, bodyPaint);

    // Initial (simplified — just the letter)
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final initialPainter = TextPainter(
      text: TextSpan(
        text: initial,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    initialPainter.layout();
    initialPainter.paint(
      canvas,
      Offset(
        center.dx - initialPainter.width / 2,
        center.dy - initialPainter.height / 2,
      ),
    );

    // Name label below node
    if (showLabels) {
      final namePainter = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: nameFontSize,
            fontWeight: FontWeight.w500,
            color: const Color(0xFFF5F0EE).withValues(alpha: 0.8),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      namePainter.layout(maxWidth: 100);
      namePainter.paint(
        canvas,
        Offset(
          center.dx - namePainter.width / 2,
          center.dy + radius + 8,
        ),
      );
    }

    // Change 3: Anchor "You" label always visible at LOD1
    if (isAnchor) {
      final youPainter = TextPainter(
        text: const TextSpan(
          text: 'You',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF00B4A6), // teal for You
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      youPainter.layout();
      youPainter.paint(
        canvas,
        Offset(
          center.dx - youPainter.width / 2,
          center.dy + radius + 24,
        ),
      );
    }

    // Kinship label ABOVE the node (category-aware color)
    if (relationship != null && relationship.isNotEmpty && showLabels) {
      final kinshipText = relationship.replaceAll('_', ' ');
      final kinshipColor = _nodeFillColor(id, isDeceased);
      final kinshipPainter = TextPainter(
        text: TextSpan(
          text: kinshipText,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: kinshipFontSize,
            fontWeight: FontWeight.w600,
            color: kinshipColor,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      kinshipPainter.layout(maxWidth: 100);
      kinshipPainter.paint(
        canvas,
        Offset(
          center.dx - kinshipPainter.width / 2,
          center.dy - radius - 16,
        ),
      );
    }
  }

  void _drawNode(Canvas canvas, String id, Offset center) {
    final isSelected = id == selectedNodeId;
    final isAnchor = id == anchorPersonId;
    final node = layout.nodes[id];
    final generation = layout.nodeGenerations[id] ?? 1;
    final isDeceased = node?.person.isDeceased ?? false;
    final name = node?.person.name ?? 'Unknown';
    // Use resolved kinship label from LayoutResult (Fix Root Cause #1)
    final relationship = layout.kinshipLabels[id] ?? node?.person.relationship;

    // Change 3: Anchor node is always dominant
    final effectiveRadius = isAnchor
        ? nodeRadius * 1.6
        : isSelected
            ? nodeRadiusSelected
            : nodeRadius;

    final ringColor = _generationRingColor(generation);

    // ── F4-4: Level-of-detail by zoom ────────────────────────────
    // Change 9: Updated LOD thresholds
    if (scale < 0.25) {
      // LOD 0: Circle only, no text, no avatar details
      _drawNodeLod0(
        canvas,
        center,
        effectiveRadius,
        ringColor,
        isDeceased,
        isSelected,
        isAnchor,
        id,
      );
      return;
    }

    if (scale <= 0.5) {
      // LOD 1: Circle + name text only
      _drawNodeLod1(
        canvas,
        center,
        effectiveRadius,
        ringColor,
        isDeceased,
        name,
        relationship,
        isSelected,
        isAnchor,
        id,
      );
      return;
    }

    // ── LOD 2: Full detail ───────────────────────────────────────

    // Change 7A: Drop shadow behind every node
    canvas.drawCircle(
      center + const Offset(0, 3),
      effectiveRadius + 1,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // ── Selection glow (pulsing orange) ──────────────────────────
    if (isSelected) {
      final glowAlpha = 0.2 + pulseValue * 0.15;
      final glowPaint = Paint()
        ..color = const Color(0xFFE8612A).withValues(alpha: glowAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, effectiveRadius + 10, glowPaint);
    }

    // ── Change 3: Anchor double ring with permanent pulse glow ──
    if (isAnchor) {
      // Permanent pulse glow (teal for You)
      final anchorGlow = Paint()
        ..color = const Color(0xFF00B4A6)
            .withValues(alpha: 0.2 + pulseValue * 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, effectiveRadius + 6, anchorGlow);

      // Outer ring
      canvas.drawCircle(
        center,
        effectiveRadius + 6,
        Paint()
          ..color = const Color(0xFF00B4A6).withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    } else if (!isSelected) {
      // ── Non-anchor uses category-aware ring ──
    }

    // ── Ring (category-aware) ────────────────────────────────────
    if (isAnchor) {
      // Inner ring for anchor (teal)
      canvas.drawCircle(
        center,
        effectiveRadius + ringWidth,
        Paint()
          ..color = const Color(0xFF00B4A6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    } else {
      final categoryRingColor = _nodeRingColor(id, isDeceased, generation);
      final ringPaint = Paint()
        ..color = categoryRingColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth;
      canvas.drawCircle(center, effectiveRadius + ringWidth, ringPaint);
    }

    // ── Node body (category-aware gradient) ────────────────────────
    final gradient = _categoryGradient(id, isDeceased);
    final bodyRect =
        Rect.fromCircle(center: center, radius: effectiveRadius);
    final bodyPaint = Paint()..shader = gradient.createShader(bodyRect);
    canvas.drawCircle(center, effectiveRadius, bodyPaint);

    // Change 7B: Inner white shimmer ring (depth effect)
    canvas.drawCircle(
      center,
      effectiveRadius - 3,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // ── Deceased overlay ────────────────────────────────────────
    if (isDeceased) {
      final deceasedPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.08);
      canvas.drawCircle(center, effectiveRadius, deceasedPaint);
    }

    // ── Content: Initial or dove ────────────────────────────────
    if (isDeceased) {
      // Change 7D: Dove instead of scissors
      final dovePainter = TextPainter(
        text: const TextSpan(
            text: '\u{1F54A}', style: TextStyle(fontSize: 16)),
        textDirection: TextDirection.ltr,
      );
      dovePainter.layout();
      dovePainter.paint(
        canvas,
        Offset(
          center.dx - dovePainter.width / 2,
          center.dy - dovePainter.height / 2,
        ),
      );
    } else {
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
      final initialPainter = TextPainter(
        text: TextSpan(
          text: initial,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      initialPainter.layout();
      initialPainter.paint(
        canvas,
        Offset(
          center.dx - initialPainter.width / 2,
          center.dy - initialPainter.height / 2,
        ),
      );
    }

    // ── Name label below node ───────────────────────────────────
    if (showLabels || scale >= 1.0) {
      final labelAlpha =
          scale < 1.0 ? (scale / 1.0).clamp(0.0, 1.0) : 1.0;
      final namePainter = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: nameFontSize,
            fontWeight: FontWeight.w500,
            color: const Color(0xFFF5F0EE).withValues(alpha: labelAlpha),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      namePainter.layout(maxWidth: 100);
      namePainter.paint(
        canvas,
        Offset(
          center.dx - namePainter.width / 2,
          center.dy + effectiveRadius + 8,
        ),
      );
    }

    // ── Change 3: Anchor "You" label always visible ─────────────
    if (isAnchor) {
      final youPainter = TextPainter(
        text: const TextSpan(
          text: 'You',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF00B4A6), // teal for You
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      youPainter.layout();
      youPainter.paint(
        canvas,
        Offset(
          center.dx - youPainter.width / 2,
          center.dy + effectiveRadius + 24,
        ),
      );
    }

    // Kinship label ABOVE the node (category-aware color)
    if (relationship != null && relationship.isNotEmpty && showLabels) {
      final kinshipText = relationship.replaceAll('_', ' ');
      final kinshipColor = _nodeFillColor(id, isDeceased);
      final kinshipPainter = TextPainter(
        text: TextSpan(
          text: kinshipText,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: kinshipFontSize,
            fontWeight: FontWeight.w600,
            color: kinshipColor,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      kinshipPainter.layout(maxWidth: 100);
      kinshipPainter.paint(
        canvas,
        Offset(
          center.dx - kinshipPainter.width / 2,
          center.dy - effectiveRadius - 16,
        ),
      );
    }

    // ── Extra detail when zoomed above 2x ──────────────────────
    if (scale > 2.0) {
      final member = members.where((m) => m.id == id).firstOrNull;
      if (member != null) {
        final detailParts = <String>[];
        if (member.dateOfBirth != null && member.dateOfBirth!.isNotEmpty) {
          detailParts.add(member.dateOfBirth!);
        }
        if (member.city != null && member.city!.isNotEmpty) {
          detailParts.add(member.city!);
        }
        if (detailParts.isNotEmpty) {
          final detailPainter = TextPainter(
            text: TextSpan(
              text: detailParts.join(' \u00B7 '),
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 8,
                color: const Color(0xFFC9B4A8).withValues(alpha: 0.6),
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          );
          detailPainter.layout(maxWidth: 120);
          detailPainter.paint(
            canvas,
            Offset(
              center.dx - detailPainter.width / 2,
              center.dy + effectiveRadius + 22,
            ),
          );
        }
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// GRAPH PILL (Change 5: Replaces _GraphControls, _AddNodeFab, _Minimap)
// ═══════════════════════════════════════════════════════════════════════

class _GraphPill extends StatelessWidget {
  const _GraphPill({
    required this.layoutMode,
    required this.onToggleLayout,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCenterYou,
    required this.onFit,
    required this.onAddPerson,
    required this.onOpenMenu,
  });

  final GraphLayoutMode layoutMode;
  final ValueChanged<GraphLayoutMode> onToggleLayout;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenterYou;
  final VoidCallback onFit;
  final VoidCallback onAddPerson;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1B2E).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: const Color(0xFFE8612A).withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillIcon(icon: Icons.remove_rounded, onTap: onZoomOut),
          _PillIcon(icon: Icons.add_rounded, onTap: onZoomIn),
          const _PillDivider(),
          _PillToggle(
            icon: Icons.family_restroom_rounded,
            label: 'Gen',
            active: layoutMode == GraphLayoutMode.generational,
            onTap: () => onToggleLayout(GraphLayoutMode.generational),
          ),
          _PillToggle(
            icon: Icons.hub_rounded,
            label: 'Radial',
            active: layoutMode == GraphLayoutMode.radial,
            onTap: () => onToggleLayout(GraphLayoutMode.radial),
          ),
          _PillToggle(
            icon: Icons.account_tree_rounded,
            label: 'Tree',
            active: layoutMode == GraphLayoutMode.hierarchical,
            onTap: () => onToggleLayout(GraphLayoutMode.hierarchical),
          ),
          _PillToggle(
            icon: Icons.grain_rounded,
            label: 'Web',
            active: layoutMode == GraphLayoutMode.force,
            onTap: () => onToggleLayout(GraphLayoutMode.force),
          ),
          const _PillDivider(),
          _PillIcon(
              icon: Icons.my_location_rounded, onTap: onCenterYou),
          _PillIcon(icon: Icons.fit_screen_rounded, onTap: onFit),
          const _PillDivider(),
          _PillIcon(
            icon: Icons.person_add_rounded,
            color: const Color(0xFFE8612A),
            onTap: onAddPerson,
          ),
          _PillIcon(icon: Icons.tune_rounded, onTap: onOpenMenu),
        ],
      ),
    );
  }
}

class _PillToggle extends StatelessWidget {
  const _PillToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFE8612A).withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: active
                    ? const Color(0xFFE8612A)
                    : const Color(0xFFF5F0EE).withValues(alpha: 0.5)),
            if (active) ...[
              const SizedBox(height: 1),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFE8612A),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PillIcon extends StatelessWidget {
  const _PillIcon({
    required this.icon,
    this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: color ?? const Color(0xFFF5F0EE).withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _PillDivider extends StatelessWidget {
  const _PillDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFFE8612A).withValues(alpha: 0.2),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LEGEND DOT (Fix Root Cause #5: color legend bar)
// ═══════════════════════════════════════════════════════════════════════

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MENU TILE (for bottom sheet)
// ═══════════════════════════════════════════════════════════════════════

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: const Color(0xFFF5F0EE).withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFF5F0EE),
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EMPTY CONSTELLATION STATE
// ═══════════════════════════════════════════════════════════════════════

class _EmptyConstellation extends StatelessWidget {
  const _EmptyConstellation({required this.onAddFirst});

  final VoidCallback onAddFirst;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF131416).withValues(alpha: 0.92),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: _ConstellationIllustrationPainter(),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Your family tree is waiting',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFF5F0EE),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Add your first family member to begin\nmapping your constellation.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFFC9B4A8),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Container(
                decoration: BoxDecoration(
                  gradient: KinrelGradients.igniteGradient,
                  borderRadius:
                      BorderRadius.circular(KinrelRadius.full),
                  boxShadow: [
                    BoxShadow(
                      color: KinrelColors.orangeGlow,
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(KinrelRadius.full),
                  child: InkWell(
                    onTap: onAddFirst,
                    borderRadius:
                        BorderRadius.circular(KinrelRadius.full),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Add First Member',
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini constellation illustration for empty state
class _ConstellationIllustrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final orangePaint = Paint()..color = const Color(0xFFE8612A);
    final amberPaint = Paint()..color = const Color(0xFFF59240);
    final edgePaint = Paint()
      ..color = const Color(0xFFF5F0EE).withValues(alpha: 0.12)
      ..strokeWidth = 1;

    final points = [
      center,
      Offset(center.dx - 40, center.dy - 30),
      Offset(center.dx + 40, center.dy - 30),
      Offset(center.dx - 50, center.dy + 25),
      Offset(center.dx + 50, center.dy + 25),
      Offset(center.dx, center.dy + 40),
      Offset(center.dx - 25, center.dy - 50),
      Offset(center.dx + 25, center.dy - 50),
    ];

    final edgePairs = [
      [0, 1],
      [0, 2],
      [0, 3],
      [0, 4],
      [0, 5],
      [1, 6],
      [2, 7],
      [3, 5],
      [4, 5],
    ];

    for (final pair in edgePairs) {
      canvas.drawLine(points[pair[0]], points[pair[1]], edgePaint);
    }

    for (int i = 0; i < points.length; i++) {
      final glowPaint = Paint()
        ..color =
            (i == 0 ? orangePaint : amberPaint).color.withValues(
                  alpha: 0.3,
                )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(points[i], 10, glowPaint);
      canvas.drawCircle(points[i], 4, i == 0 ? orangePaint : amberPaint);
      canvas.drawCircle(points[i], 1.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Relation avatar for edge popup ─────────────────────────────────
class _RelationAvatar extends StatelessWidget {
  const _RelationAvatar({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.25),
            border: Border.all(color: color, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: color,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFFF5F0EE),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Relation card row for edge popup ───────────────────────────────
class _RelationCard extends StatelessWidget {
  const _RelationCard({
    required this.fromName,
    required this.toName,
    required this.label,
    required this.color,
  });
  final String fromName;
  final String toName;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 14, height: 1.4),
                children: [
                  TextSpan(
                    text: fromName,
                    style: TextStyle(
                      color: const Color(0xFFF5F0EE),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: '  calls  ',
                    style: TextStyle(
                      color: const Color(0xFFF5F0EE).withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: toName,
                    style: TextStyle(
                      color: const Color(0xFFF5F0EE),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: ':  ',
                    style: TextStyle(
                      color: const Color(0xFFF5F0EE).withValues(alpha: 0.45),
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: label,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// GEN CHIP (used in menu bottom sheet)
// ═══════════════════════════════════════════════════════════════════════

class _GenChip extends StatelessWidget {
  const _GenChip({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color:
                isSelected ? color : color.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
