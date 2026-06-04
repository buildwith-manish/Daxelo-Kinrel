import 'package:kinrel/core/widgets/global_error_widget.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/graph/graph_service.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/utils/smart_preloader.dart';
import '../../../core/utils/accessibility_utils.dart';
import '../../../core/services/analytics_service.dart';

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
enum GraphLayoutMode { force, hierarchical, radial }

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
  });

  final Map<String, Offset> positions;
  final Map<String, VisTreeNode> nodes;
  final Map<String, String> nodeLineages;
  final List<VisEdge> edges;
  final Map<String, int> nodeGenerations;
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
  GraphLayoutMode _layoutMode = GraphLayoutMode.radial; // Change 1: default to radial
  bool _showLabels = true;
  bool _showGenBands = false;
  double _currentScale = 1.0;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerOnAnchor();
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
      color: const Color(0xFF131416),
      child: Stack(
        children: [
          // ── Interactive graph canvas ─────────────────────────────
          InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.3,
            maxScale: 3.0,
            boundaryMargin: const EdgeInsets.all(2000),
            onInteractionUpdate: (details) {
              // P5-F1: Track zoom changes (only for pinch zoom, not pan)
              if (details.scale != 1.0 && details.scale != _currentScale) {
                AnalyticsService.instance.logGraphZoomed(details.scale);
              }
              setState(() {
                _currentScale = details.scale;
              });
            },
            child: Semantics(
              label:
                  'Family relationship graph with ${activeMembers.length} members',
              hint: 'Pinch to zoom, drag to pan, tap a node to view member',
              child: GestureDetector(
                onTapUp: (details) =>
                    _handleTap(details.localPosition, layout),
                onLongPressStart: (details) =>
                    _handleLongPress(details.localPosition, layout),
                onDoubleTap: () {}, // Required for onDoubleTapDown to work
                onDoubleTapDown: (details) =>
                    _handleDoubleTap(details.localPosition, layout),
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
                      return RepaintBoundary(
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
            ),
          ),

          // Change 2: Removed _LanguageSelectorButton and _FilterBar from top
          // Change 5: Replaced _GraphControls, _AddNodeFab, _Minimap with single pill

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
    // Convert screen position to graph position
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

      // P8: Smart preloading — precache full-size photo on tap
      try {
        SmartPreloader.precacheSingleImage(
          context: context,
          imageUrl: person.photoUrl,
        );
      } catch (_) {
        // Silently ignore — preloading is best-effort
      }

      setState(() => _selectedNodeId = tappedId);
      // P5-F1: Track graph node tap
      AnalyticsService.instance.logGraphNodeTapped();
      widget.onNodeTap?.call(person);
    } else {
      setState(() => _selectedNodeId = null);
    }
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
        // Change 7C: was 1.3
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
          final m = Matrix4.identity();
          m.setEntry(0, 3, screenSize.width / 2 - pos.dx * 1.5);
          m.setEntry(1, 3, screenSize.height / 2 - pos.dy * 1.5);
          m.scaleByDouble(1.5, 1.5, 1.0, 1.0);
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

  // ══════════════════════════════════════════════════════════════════
  // ZOOM / NAVIGATION HELPERS
  // ══════════════════════════════════════════════════════════════════

  void _zoomIn() {
    final current = _transformationController.value;
    final newScale = (_currentScale * 1.2).clamp(0.3, 3.0);
    final scaleFactor = newScale / _currentScale;
    setState(() {
      final m = Matrix4.copy(current);
      m.scaleByDouble(scaleFactor, scaleFactor, 1.0, 1.0);
      _transformationController.value = m;
      _currentScale = newScale;
    });
  }

  void _zoomOut() {
    final current = _transformationController.value;
    final newScale = (_currentScale / 1.2).clamp(0.3, 3.0);
    final scaleFactor = newScale / _currentScale;
    setState(() {
      final m = Matrix4.copy(current);
      m.scaleByDouble(scaleFactor, scaleFactor, 1.0, 1.0);
      _transformationController.value = m;
      _currentScale = newScale;
    });
  }

  void _fitToScreen() {
    setState(() {
      _transformationController.value = Matrix4.identity();
      _currentScale = 1.0;
    });
  }

  void _centerOnAnchor() {
    if (_cachedPositions.isEmpty) return;
    final anchorPos = _cachedPositions[widget.anchorPersonId];
    if (anchorPos != null) {
      final screenSize = MediaQuery.of(context).size;
      setState(() {
        final m = Matrix4.identity();
        m.setEntry(0, 3, screenSize.width / 2 - anchorPos.dx * 1.5);
        m.setEntry(1, 3, screenSize.height / 2 - anchorPos.dy * 1.5);
        m.scaleByDouble(1.5, 1.5, 1.0, 1.0);
        _transformationController.value = m;
        _currentScale = 1.5;
      });
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
                    // TODO: Show language picker
                  },
                ),
                // Share
                _MenuTile(
                  icon: Icons.share_rounded,
                  label: 'Share Graph',
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Implement share/export
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

    return LayoutResult(
      positions: positions,
      nodes: nodes,
      nodeLineages: lineages,
      edges: edges,
      nodeGenerations: generations,
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
      final ringRadius = 180.0 * gen;
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

  LinearGradient _avatarGradient(bool isDeceased) {
    if (isDeceased) {
      return const LinearGradient(
        colors: [Color(0xFF4A4A5E), Color(0xFF2A2A3E)],
      );
    }
    return const LinearGradient(
      colors: [KinrelColors.orange, KinrelColors.amber],
    );
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

  // ── Edge drawing ─────────────────────────────────────────────────

  // Change 10: Updated _drawEdge to accept pre-computed start/end positions
  void _drawEdge(Canvas canvas, VisEdge edge, Offset start, Offset end) {
    final isConnectedToSelected =
        edge.fromId == selectedNodeId || edge.toId == selectedNodeId;

    Color color;
    double width;

    switch (edge.type) {
      case EdgeType.spouse:
        color = spouseEdgeColor;
        width = 2.0;
      case EdgeType.parentChild:
        color = parentChildEdgeColor;
        width = 2.0; // Change 10C: was 1.5
      case EdgeType.sibling:
        color = siblingEdgeColor;
        width = 1.0;
      case EdgeType.inLaw:
        color = inLawEdgeColor;
        width = 1.0;
      case EdgeType.unknown:
        color = parentChildEdgeColor.withValues(alpha: 0.3);
        width = 1.0;
    }

    // Glow when connected to selected
    if (isConnectedToSelected) {
      color = const Color(0xFFE8612A);
      width = width * 1.5;

      final glowPaint = Paint()
        ..color = const Color(0xFFE8612A).withValues(alpha: 0.15)
        ..strokeWidth = width + 6
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      _drawEdgePath(canvas, start, end, edge.type, glowPaint);
    }

    final paint = Paint()
      ..color = color.withValues(
          alpha: isConnectedToSelected ? 0.95 : 0.75) // Change 10A: was 0.4
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Change 10B: Spouse edge animated gradient
    if (edge.type == EdgeType.spouse) {
      final shader = LinearGradient(
        colors: [const Color(0xFFE8612A), const Color(0xFFF59240)],
      ).createShader(Rect.fromPoints(start, end));
      paint.shader = shader;
    }

    _drawEdgePath(canvas, start, end, edge.type, paint);

    // Change 10D: Arrowhead on parent→child
    if (edge.type == EdgeType.parentChild) {
      _drawArrowhead(canvas, start, end, paint);
    }

    // Heart at midpoint for spouse
    if (edge.type == EdgeType.spouse) {
      _drawHeartAtMidpoint(canvas, start, end);
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

  void _drawEdgePath(
    Canvas canvas,
    Offset start,
    Offset end,
    EdgeType type,
    Paint paint,
  ) {
    switch (type) {
      case EdgeType.parentChild:
        final midY = (start.dy + end.dy) / 2;
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(start.dx, midY, end.dx, midY, end.dx, end.dy);
        canvas.drawPath(path, paint);
      case EdgeType.sibling:
        _drawDashedLine(canvas, start, end, paint, 6, 4);
      case EdgeType.inLaw:
        _drawDottedLine(canvas, start, end, paint, 2, 5);
      default:
        canvas.drawLine(start, end, paint);
    }
  }

  void _drawHeartAtMidpoint(Canvas canvas, Offset start, Offset end) {
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final heartPainter = TextPainter(
      text: const TextSpan(
        text: '\u2764',
        style: TextStyle(fontSize: 10, color: Color(0xFFE8612A)),
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
      final e = (i * (dashLen + gapLen) + dashLen) / distance;
      canvas.drawLine(
        Offset(start.dx + dx * s, start.dy + dy * s),
        Offset(start.dx + dx * e, start.dy + dy * e),
        paint,
      );
    }
  }

  void _drawDottedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dotRadius,
    double spacing,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance == 0) return;

    final steps = (distance / spacing).floor();
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      canvas.drawCircle(
        Offset(start.dx + dx * t, start.dy + dy * t),
        dotRadius,
        paint,
      );
    }
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
  ) {
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
        ..color = KinrelColors.orange.withValues(alpha: 0.2 + pulseValue * 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, radius + 6, anchorGlow);
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()
          ..color = KinrelColors.orange.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      canvas.drawCircle(
        center,
        radius + ringWidth,
        Paint()
          ..color = KinrelColors.orange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    } else {
      // Generation ring
      final ringPaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth;
      canvas.drawCircle(center, radius + ringWidth, ringPaint);
    }

    // Simplified body — flat color instead of gradient
    final bodyPaint = Paint()
      ..color = isDeceased
          ? const Color(0xFF3A3A4E)
          : ringColor.withValues(alpha: 0.7);
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
  ) {
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
        ..color = KinrelColors.orange.withValues(alpha: 0.2 + pulseValue * 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, radius + 6, anchorGlow);
      // Double ring
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()
          ..color = KinrelColors.orange.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      canvas.drawCircle(
        center,
        radius + ringWidth,
        Paint()
          ..color = KinrelColors.orange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    } else {
      // Generation ring
      final ringPaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth;
      canvas.drawCircle(center, radius + ringWidth, ringPaint);
    }

    // Node body (gradient)
    final gradient = _avatarGradient(isDeceased);
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
            color: KinrelColors.orange,
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

    // Kinship label ABOVE the node (prominent, orange)
    if (relationship != null && relationship.isNotEmpty && showLabels) {
      final kinshipText = relationship.replaceAll('_', ' ');
      final kinshipPainter = TextPainter(
        text: TextSpan(
          text: kinshipText,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: kinshipFontSize,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFE8612A),
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
    final relationship = node?.person.relationship;

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
      // Permanent pulse glow
      final anchorGlow = Paint()
        ..color = KinrelColors.orange
            .withValues(alpha: 0.2 + pulseValue * 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, effectiveRadius + 6, anchorGlow);

      // Outer ring
      canvas.drawCircle(
        center,
        effectiveRadius + 6,
        Paint()
          ..color = KinrelColors.orange.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    } else if (!isSelected) {
      // ── Anchor glow (non-anchor, non-selected uses generation ring) ──
    }

    // ── Generation ring ─────────────────────────────────────────
    if (isAnchor) {
      // Inner ring for anchor
      canvas.drawCircle(
        center,
        effectiveRadius + ringWidth,
        Paint()
          ..color = KinrelColors.orange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    } else {
      final ringPaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth;
      canvas.drawCircle(center, effectiveRadius + ringWidth, ringPaint);
    }

    // ── Node body (gradient circle) ─────────────────────────────
    final gradient = _avatarGradient(isDeceased);
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
            color: KinrelColors.orange,
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

    // Kinship label ABOVE the node (prominent, orange)
    if (relationship != null && relationship.isNotEmpty && showLabels) {
      final kinshipText = relationship.replaceAll('_', ' ');
      final kinshipPainter = TextPainter(
        text: TextSpan(
          text: kinshipText,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: kinshipFontSize,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFE8612A),
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
    required this.onCenterYou,
    required this.onFit,
    required this.onAddPerson,
    required this.onOpenMenu,
  });

  final GraphLayoutMode layoutMode;
  final ValueChanged<GraphLayoutMode> onToggleLayout;
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
