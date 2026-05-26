import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/graph/graph_service.dart';
import '../../../core/family/family_provider.dart';

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
  GraphLayoutMode _layoutMode = GraphLayoutMode.force;
  bool _showLabels = true;
  bool _showGenBands = false;
  double _currentScale = 1.0;

  // ── Transformation controller for InteractiveViewer ─────────────
  final TransformationController _transformationController =
      TransformationController();

  // ── Animation ───────────────────────────────────────────────────
  late AnimationController _ambientController;
  late AnimationController _pulseController;

  // ── Force-directed simulation state ─────────────────────────────
  Map<String, Offset> _forcePositions = {};
  Map<String, Offset> _forceVelocities = {};

  // ── Layout constants ────────────────────────────────────────────
  static const double nodeRadius = 24.0;
  static const double horizontalGap = 80.0;
  static const double verticalGap = 100.0;
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
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _pulseController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final treeRoots = _buildTree();
    final activeMembers =
        widget.members.where((p) => p.deletedAt == null).toList();
    final layout = _computeLayout(treeRoots);

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
              setState(() {
                _currentScale = details.scale;
              });
            },
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
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _ambientController,
                    _pulseController,
                  ]),
                  builder: (context, _) {
                    return CustomPaint(
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
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // ── Language selector (top-left) ────────────────────────
          Positioned(
            top: 8,
            left: 8,
            child: _LanguageSelectorButton(),
          ),

          // ── Filter bar (top-center) ─────────────────────────────
          Positioned(
            top: 8,
            left: 52,
            right: 52,
            child: _FilterBar(
              filters: _filters,
              onFiltersChanged: (f) => setState(() => _filters = f),
            ),
          ),

          // ── Graph controls (bottom-right) ───────────────────────
          Positioned(
            bottom: 16,
            right: 16,
            child: _GraphControls(
              layoutMode: _layoutMode,
              showLabels: _showLabels,
              showGenBands: _showGenBands,
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
              onFit: _fitToScreen,
              onCenterYou: _centerOnAnchor,
              onToggleLayout: (mode) {
                setState(() {
                  _layoutMode = mode;
                  _forcePositions.clear();
                  _forceVelocities.clear();
                });
              },
              onToggleLabels: () {
                setState(() => _showLabels = !_showLabels);
              },
              onToggleGenBands: () {
                setState(() => _showGenBands = !_showGenBands);
              },
              onShare: () {
                // TODO: Implement share/export
              },
            ),
          ),

          // ── Add member FAB ──────────────────────────────────────
          if (activeMembers.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 16,
              child: _AddNodeFab(
                onTap: () {
                  // Parent screen handles showing AddPersonSheet
                },
              ),
            ),

          // ── Minimap (bottom-left, above FAB) ────────────────────
          if (activeMembers.isNotEmpty)
            Positioned(
              bottom: 76,
              left: 16,
              child: _Minimap(
                layout: layout,
                transformationController: _transformationController,
                canvasSize: const Size(canvasSize, canvasSize),
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
      if (dist < nodeRadius * 1.3) {
        tappedId = entry.key;
        break;
      }
    }

    if (tappedId != null) {
      final person = widget.members.firstWhere(
        (p) => p.id == tappedId,
        orElse: () => Person(id: tappedId!, familyId: '', name: 'Unknown'),
      );
      setState(() => _selectedNodeId = tappedId);
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
      if (dist < nodeRadius * 1.3) {
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
      if (dist < nodeRadius * 1.3) {
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
          _transformationController.value = Matrix4.identity()
            ..translate(screenSize.width / 2 - pos.dx * 1.5,
                screenSize.height / 2 - pos.dy * 1.5)
            ..scale(1.5);
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
      _transformationController.value = current.scaled(scaleFactor, scaleFactor);
      _currentScale = newScale;
    });
  }

  void _zoomOut() {
    final current = _transformationController.value;
    final newScale = (_currentScale / 1.2).clamp(0.3, 3.0);
    final scaleFactor = newScale / _currentScale;
    setState(() {
      _transformationController.value = current.scaled(scaleFactor, scaleFactor);
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
    final treeRoots = _buildTree();
    final layout = _computeLayout(treeRoots);
    final anchorPos = layout.positions[widget.anchorPersonId];
    if (anchorPos != null) {
      final screenSize = MediaQuery.of(context).size;
      setState(() {
        _transformationController.value = Matrix4.identity()
          ..translate(screenSize.width / 2 - anchorPos.dx * 1.5,
              screenSize.height / 2 - anchorPos.dy * 1.5)
          ..scale(1.5);
        _currentScale = 1.5;
      });
    }
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
        roots.add(VisTreeNode(
          person: p,
          lineage: p.id == widget.anchorPersonId ? 'self' : '',
        ));
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
        nodes[spouseId] = VisTreeNode(
          person: node.spouse!,
          lineage: 'marital',
        );
        lineages[spouseId] = 'marital';
        generations[spouseId] = depth;
        final spouseMember = memberMap[spouseId];
        if (spouseMember != null && spouseMember.generationIndex > 0) {
          generations[spouseId] = spouseMember.generationIndex;
        }

        edges.add(VisEdge(
          fromId: id,
          toId: spouseId,
          type: EdgeType.spouse,
          label: 'spouse',
        ));
      }

      for (final child in node.children) {
        edges.add(VisEdge(
          fromId: id,
          toId: child.person.id,
          type: EdgeType.parentChild,
          label: 'parent-child',
        ));
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
        edges.add(VisEdge(
          fromId: rel.fromId,
          toId: rel.toId,
          type: edgeType,
          label: rel.type,
        ));
        existingEdgeSet.add(key1);
        existingEdgeSet.add('${rel.toId}-${rel.fromId}');
      }
    }

    // Compute positions based on layout mode
    switch (_layoutMode) {
      case GraphLayoutMode.hierarchical:
        _computeHierarchicalLayout(
            roots, positions, nodes, lineages, generations);
      case GraphLayoutMode.radial:
        _computeRadialLayout(
            roots, positions, nodes, lineages, generations);
      case GraphLayoutMode.force:
        _computeForceLayout(
            roots, positions, nodes, edges, lineages, generations);
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
      final coupleWidth =
          hasSpouse ? nodeRadius * 4 + 20 : nodeRadius * 2;

      if (node.children.isEmpty) {
        positions[node.person.id] =
            Offset(xOff + nodeRadius, yOff);
        if (hasSpouse) {
          positions[node.spouse!.id] = Offset(
            xOff + nodeRadius * 3 + 20,
            yOff,
          );
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
          centerX + nodeRadius * 2 + 20,
          yOff,
        );
      }

      return math.max(maxChildWidth, coupleWidth);
    }

    double yOffset = startY;
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
      final ringRadius = 140.0 * gen;
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
    Map<String, int> generations,
  ) {
    const double repulsionStrength = 6000;
    const double attractionStrength = 0.004;
    const double gravityStrength = 0.008;
    const double damping = 0.82;
    const double idealEdgeLength = 120;
    const int maxSteps = 80;

    final center = Offset(canvasSize / 2, canvasSize / 2);
    final allIds = nodes.keys.toList();

    // Initialize positions if needed
    if (_forcePositions.length != allIds.length ||
        !_forcePositions.keys.toSet().containsAll(allIds)) {
      final tempPositions = <String, Offset>{};
      _computeHierarchicalLayout(
          roots, tempPositions, nodes, lineages, generations);

      for (final id in allIds) {
        _forcePositions[id] = tempPositions[id] ??
            Offset(
              center.dx + (math.Random().nextDouble() - 0.5) * 300,
              center.dy + (math.Random().nextDouble() - 0.5) * 300,
            );
      }
      _forceVelocities = {for (final id in allIds) id: Offset.zero};
    }

    // Run simulation
    for (int step = 0; step < maxSteps; step++) {
      final forces = <String, Offset>{for (final id in allIds) id: Offset.zero};

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
            !_forcePositions.containsKey(edge.toId)) continue;
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
        final vel = (_forceVelocities[id] ?? Offset.zero) + forces[id]!;
        _forceVelocities[id] = vel * damping;
        _forcePositions[id] = _forcePositions[id]! + _forceVelocities[id]!;
      }
    }

    for (final id in allIds) {
      positions[id] = _forcePositions[id]!;
    }
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

  // ── Design constants ────────────────────────────────────────────
  static const double nodeRadius = 24.0;
  static const double nodeRadiusSelected = 26.4;
  static const double ringWidth = 2.0;
  static const double nameFontSize = 11.0;
  static const double kinshipFontSize = 10.0;

  // Generation ring colors
  static const Color genGrandparent = Color(0xFFC44A18);
  static const Color genParent = Color(0xFFE8612A);
  static const Color genUser = Color(0xFFF59240);
  static const Color genChild = Color(0xFFFFB870);

  // Edge colors
  static const Color spouseEdgeColor = Color(0xFFE8612A);
  static const Color parentChildEdgeColor = Color(0xFFF5F0EE);
  static const Color siblingEdgeColor = Color(0xFFF59240);
  static const Color inLawEdgeColor = Color(0xFFC9B4A8);

  // ── Helpers ─────────────────────────────────────────────────────

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

    // ── Edges ────────────────────────────────────────────────────
    for (final edge in layout.edges) {
      _drawEdge(canvas, edge);
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
      final pos = layout.positions[id]!;
      final ambient = _ambientOffset(id);
      _drawNode(canvas, id, pos + ambient);
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

    final center = layout.positions[anchorPersonId] ??
        layout.positions.values.first;

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

  void _drawEdge(Canvas canvas, VisEdge edge) {
    final fromPos = layout.positions[edge.fromId];
    final toPos = layout.positions[edge.toId];
    if (fromPos == null || toPos == null) return;

    final start = fromPos + _ambientOffset(edge.fromId);
    final end = toPos + _ambientOffset(edge.toId);

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
        width = 1.5;
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
      ..color = color.withValues(alpha: isConnectedToSelected ? 0.9 : 0.4)
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawEdgePath(canvas, start, end, edge.type, paint);

    // Heart at midpoint for spouse
    if (edge.type == EdgeType.spouse) {
      _drawHeartAtMidpoint(canvas, start, end);
    }
  }

  void _drawEdgePath(
      Canvas canvas, Offset start, Offset end, EdgeType type, Paint paint) {
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
    final mid = Offset(
      (start.dx + end.dx) / 2,
      (start.dy + end.dy) / 2,
    );
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

  void _drawDashedLine(Canvas canvas, Offset start, Offset end,
      Paint paint, double dashLen, double gapLen) {
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

  void _drawDottedLine(Canvas canvas, Offset start, Offset end,
      Paint paint, double dotRadius, double spacing) {
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

  // ── Node drawing ─────────────────────────────────────────────────

  void _drawNode(Canvas canvas, String id, Offset center) {
    final isSelected = id == selectedNodeId;
    final isAnchor = id == anchorPersonId;
    final node = layout.nodes[id];
    final generation = layout.nodeGenerations[id] ?? 1;
    final isDeceased = node?.person.isDeceased ?? false;
    final name = node?.person.name ?? 'Unknown';
    final relationship = node?.person.relationship;

    final effectiveRadius = isSelected ? nodeRadiusSelected : nodeRadius;
    final ringColor = _generationRingColor(generation);

    // ── Selection glow (pulsing orange) ──────────────────────────
    if (isSelected) {
      final glowAlpha = 0.2 + pulseValue * 0.15;
      final glowPaint = Paint()
        ..color = const Color(0xFFE8612A).withValues(alpha: glowAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, effectiveRadius + 10, glowPaint);
    }

    // ── Anchor glow ─────────────────────────────────────────────
    if (isAnchor && !isSelected) {
      final anchorGlow = Paint()
        ..color = KinrelColors.orangeGlowIntense
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(center, effectiveRadius + 6, anchorGlow);
    }

    // ── Generation ring ─────────────────────────────────────────
    final ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth;
    canvas.drawCircle(center, effectiveRadius + ringWidth, ringPaint);

    // ── Node body (gradient circle) ─────────────────────────────
    final gradient = _avatarGradient(isDeceased);
    final bodyRect = Rect.fromCircle(center: center, radius: effectiveRadius);
    final bodyPaint = Paint()
      ..shader = gradient.createShader(bodyRect);
    canvas.drawCircle(center, effectiveRadius, bodyPaint);

    // ── Deceased overlay ────────────────────────────────────────
    if (isDeceased) {
      final deceasedPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.08);
      canvas.drawCircle(center, effectiveRadius, deceasedPaint);
    }

    // ── Content: Initial or dove ────────────────────────────────
    if (isDeceased) {
      final dovePainter = TextPainter(
        text: const TextSpan(text: '\u2702', style: TextStyle(fontSize: 16)),
        textDirection: TextDirection.ltr,
      );
      dovePainter.layout();
      dovePainter.paint(
        canvas,
        Offset(center.dx - dovePainter.width / 2,
            center.dy - dovePainter.height / 2),
      );
    } else {
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
      final initialPainter = TextPainter(
        text: TextSpan(
          text: initial,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      initialPainter.layout();
      initialPainter.paint(
        canvas,
        Offset(center.dx - initialPainter.width / 2,
            center.dy - initialPainter.height / 2),
      );
    }

    // ── Name label below node ───────────────────────────────────
    if (showLabels || scale >= 1.0) {
      final labelAlpha = scale < 1.0 ? (scale / 1.0).clamp(0.0, 1.0) : 1.0;
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
      namePainter.layout(maxWidth: 80);
      namePainter.paint(
        canvas,
        Offset(center.dx - namePainter.width / 2,
            center.dy + effectiveRadius + 6),
      );
    }

    // ── Kinship label above when selected ───────────────────────
    if (isSelected && relationship != null && relationship.isNotEmpty) {
      final kinshipPainter = TextPainter(
        text: TextSpan(
          text: relationship.replaceAll('_', ' '),
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: kinshipFontSize,
            fontWeight: FontWeight.w400,
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
        Offset(center.dx - kinshipPainter.width / 2,
            center.dy - effectiveRadius - 18),
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
            Offset(center.dx - detailPainter.width / 2,
                center.dy + effectiveRadius + 22),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.scale != scale ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.showLabels != showLabels ||
        oldDelegate.showGenBands != showGenBands ||
        oldDelegate.ambientValue != ambientValue ||
        oldDelegate.pulseValue != pulseValue;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LANGUAGE SELECTOR BUTTON
// ═══════════════════════════════════════════════════════════════════════

class _LanguageSelectorButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1B2E).withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.language, color: KinrelColors.orange, size: 18),
        tooltip: 'Language',
        onPressed: () {
          // TODO: Show language picker
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// GRAPH CONTROLS (floating toolbar, bottom-right)
// ═══════════════════════════════════════════════════════════════════════

class _GraphControls extends StatelessWidget {
  const _GraphControls({
    required this.layoutMode,
    required this.showLabels,
    required this.showGenBands,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onCenterYou,
    required this.onToggleLayout,
    required this.onToggleLabels,
    required this.onToggleGenBands,
    required this.onShare,
  });

  final GraphLayoutMode layoutMode;
  final bool showLabels;
  final bool showGenBands;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final VoidCallback onCenterYou;
  final ValueChanged<GraphLayoutMode> onToggleLayout;
  final VoidCallback onToggleLabels;
  final VoidCallback onToggleGenBands;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1B2E).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ControlButton(icon: Icons.add_rounded, onTap: onZoomIn),
          const _ControlDivider(),
          _ControlButton(icon: Icons.remove_rounded, onTap: onZoomOut),
          const _ControlDivider(),
          _ControlButton(
            icon: Icons.fit_screen_rounded,
            color: KinrelColors.orange,
            onTap: onFit,
          ),
          const _ControlDivider(),
          _ControlButton(
            icon: Icons.person_pin_circle_rounded,
            color: KinrelColors.amber,
            onTap: onCenterYou,
          ),
          const _ControlDivider(),
          _ControlButton(
            icon: layoutMode == GraphLayoutMode.force
                ? Icons.bubble_chart_rounded
                : layoutMode == GraphLayoutMode.hierarchical
                    ? Icons.account_tree_rounded
                    : Icons.radar_rounded,
            color: KinrelColors.orange,
            onTap: () {
              final next = GraphLayoutMode.values[
                  (layoutMode.index + 1) % GraphLayoutMode.values.length];
              onToggleLayout(next);
            },
          ),
          const _ControlDivider(),
          _ControlButton(
            icon: showLabels ? Icons.label_rounded : Icons.label_off_rounded,
            onTap: onToggleLabels,
            isActive: showLabels,
          ),
          const _ControlDivider(),
          _ControlButton(
            icon: Icons.album_rounded,
            onTap: onToggleGenBands,
            isActive: showGenBands,
          ),
          const _ControlDivider(),
          _ControlButton(icon: Icons.share_rounded, onTap: onShare),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.color,
    this.isActive = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isActive
        ? KinrelColors.orange
        : color ?? const Color(0xFFF5F0EE).withValues(alpha: 0.7);

    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, color: effectiveColor, size: 18),
        onPressed: onTap,
      ),
    );
  }
}

class _ControlDivider extends StatelessWidget {
  const _ControlDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 1,
      color: KinrelColors.orange.withValues(alpha: 0.1),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ADD NODE FAB
// ═══════════════════════════════════════════════════════════════════════

class _AddNodeFab extends StatelessWidget {
  const _AddNodeFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: KinrelGradients.igniteGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orangeGlow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.add_rounded, color: Colors.white, size: 24),
          ),
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
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
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
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                  child: InkWell(
                    onTap: onAddFirst,
                    borderRadius: BorderRadius.circular(KinrelRadius.full),
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded,
                              color: Colors.white, size: 20),
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
            (i == 0 ? orangePaint : amberPaint).color.withValues(alpha: 0.3)
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
// FILTER BAR
// ═══════════════════════════════════════════════════════════════════════

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.onFiltersChanged,
  });

  final GraphFilters filters;
  final ValueChanged<GraphFilters> onFiltersChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: KinrelSpacing.sm,
        vertical: KinrelSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1B2E).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.15),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int gen = 1; gen <= 5; gen++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _GenChip(
                  label: 'G$gen',
                  color: _genColor(gen),
                  isSelected: filters.visibleGenerations.contains(gen),
                  onTap: () {
                    final newGens = Set<int>.from(filters.visibleGenerations);
                    if (newGens.contains(gen)) {
                      newGens.remove(gen);
                    } else {
                      newGens.add(gen);
                    }
                    onFiltersChanged(
                        filters.copyWith(visibleGenerations: newGens));
                  },
                ),
              ),
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 20,
              color: KinrelColors.orange.withValues(alpha: 0.15),
            ),
            const SizedBox(width: 8),
            _GenChip(
              label: 'All',
              color: KinrelColors.orange,
              isSelected: filters.branch == 'all',
              onTap: () => onFiltersChanged(filters.copyWith(branch: 'all')),
            ),
            _GenChip(
              label: 'Paternal',
              color: const Color(0xFFC44A18),
              isSelected: filters.branch == 'paternal',
              onTap: () =>
                  onFiltersChanged(filters.copyWith(branch: 'paternal')),
            ),
            _GenChip(
              label: 'Maternal',
              color: const Color(0xFFF59240),
              isSelected: filters.branch == 'maternal',
              onTap: () =>
                  onFiltersChanged(filters.copyWith(branch: 'maternal')),
            ),
          ],
        ),
      ),
    );
  }

  Color _genColor(int gen) {
    if (gen >= 3) return const Color(0xFFC44A18);
    if (gen == 2) return const Color(0xFFE8612A);
    if (gen == 1) return const Color(0xFFF59240);
    return const Color(0xFFFFB870);
  }
}

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
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
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
            color: isSelected ? color : color.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MINIMAP
// ═══════════════════════════════════════════════════════════════════════

class _Minimap extends StatelessWidget {
  const _Minimap({
    required this.layout,
    required this.transformationController,
    required this.canvasSize,
  });

  final LayoutResult layout;
  final TransformationController transformationController;
  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1B2E).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.2),
        ),
      ),
      child: CustomPaint(
        painter: _MinimapPainter(
          layout: layout,
          canvasSize: canvasSize,
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.layout,
    required this.canvasSize,
  });

  final LayoutResult layout;
  final Size canvasSize;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF131416),
    );

    if (layout.positions.isEmpty) return;

    // Scale positions to minimap
    final dotPaint = Paint()..color = const Color(0xFFF59240);

    for (final pos in layout.positions.values) {
      final x = (pos.dx / canvasSize.width) * size.width;
      final y = (pos.dy / canvasSize.height) * size.height;
      canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
    }

    // Viewport indicator
    final vpPaint = Paint()
      ..color = const Color(0xFFE8612A).withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
      vpPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.layout != layout;
  }
}
