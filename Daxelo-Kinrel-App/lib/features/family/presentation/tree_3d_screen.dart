// lib/features/family/presentation/tree_3d_screen.dart
//
// DAXELO KINREL — 3D Interactive Family Tree Screen
//
// Full-screen immersive 3D family tree visualization with perspective
// transforms, rotation controls, depth-based rendering, starfield
// background, generation rings, layout modes, and node detail pop-ups.
//
// ENHANCEMENTS:
// - Touch hit-testing for node selection
// - Search/highlight functionality
// - Minimap with viewport indicator
// - Curved bezier edge rendering (parent-child, spouse, sibling)
// - Enhanced node detail popup (kinship term, generation, quick actions)
// - Node labels with zoom-based scaling and fading
// - Auto-layout animation when switching layout modes

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../../core/graph/graph_service.dart';
import 'family_tree_canvas.dart';

// ═══════════════════════════════════════════════════════════════════════
// LAYOUT MODE ENUM
// ═══════════════════════════════════════════════════════════════════════

/// 3D layout modes for the family tree visualization
enum Tree3DLayoutMode { constellation, galaxy, solar }

// ═══════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════

/// Full-screen immersive 3D family tree visualization.
///
/// Wraps the existing [FamilyTreeCanvas] data pipeline with 3D perspective
/// transforms, rotation controls, depth-based node rendering, an immersive
/// deep-space background, generation rings, and a node detail pop-up.
class Tree3DScreen extends ConsumerStatefulWidget {
  const Tree3DScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<Tree3DScreen> createState() => _Tree3DScreenState();
}

class _Tree3DScreenState extends ConsumerState<Tree3DScreen>
    with TickerProviderStateMixin {
  // ── 3D Rotation state ────────────────────────────────────────────
  double _rotationX = 0.0; // pitch
  double _rotationY = 0.0; // yaw
  double _zoom = 1.0;
  Offset _panOffset = Offset.zero;

  // ── Drag state for two-finger rotation ───────────────────────────
  Offset _lastPanPosition = Offset.zero;

  // ── Layout mode ──────────────────────────────────────────────────
  Tree3DLayoutMode _layoutMode = Tree3DLayoutMode.constellation;

  // ── Selected node for detail popup ───────────────────────────────
  Person? _selectedPerson;
  String? _selectedRelationshipKey;

  // ── Show control panel ───────────────────────────────────────────
  bool _showControls = true;

  // ── Search state ─────────────────────────────────────────────────
  String _searchQuery = '';
  final Set<String> _highlightedNodeIds = {};
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchController = TextEditingController();

  // ── Auto-layout animation state ──────────────────────────────────
  Map<String, Offset> _previousPositions = {};
  Map<String, Offset> _targetPositions = {};
  late AnimationController _layoutAnimationController;
  late Animation<double> _layoutAnimation;
  bool _isAnimatingLayout = false;

  // ── Screen-space positions for hit testing ───────────────────────
  final Map<String, Offset> _screenNodePositions = {};

  // ── Animation controllers ────────────────────────────────────────
  late AnimationController _ambientController;
  late AnimationController _pulseController;
  late AnimationController _floatController;

  // ── Computed layout data ─────────────────────────────────────────
  Map<String, Offset> _nodePositions = {};
  final Map<String, int> _nodeGenerations = {};
  final Map<String, String> _nodeLineages = {};
  final List<VisEdge> _edges = [];
  final Map<String, VisTreeNode> _nodes = {};

  // ── Star field (pre-generated) ───────────────────────────────────
  final List<_Star> _stars = [];
  final List<_Particle> _particles = [];

  // ── Canvas size for layout computation ───────────────────────────
  static const double _canvasSize = 2000.0;

  // ── Node radius constant (must match painter) ───────────────────
  static const double _nodeRadius = 24.0;

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

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _layoutAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _layoutAnimation = CurvedAnimation(
      parent: _layoutAnimationController,
      curve: Curves.easeInOutCubic,
    );

    _layoutAnimationController.addListener(_onLayoutAnimationTick);

    _generateStars();
    _generateParticles();
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _pulseController.dispose();
    _floatController.dispose();
    _layoutAnimationController.removeListener(_onLayoutAnimationTick);
    _layoutAnimationController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Star & particle generation ────────────────────────────────────

  void _generateStars() {
    final rng = math.Random(42);
    _stars.clear();
    for (int i = 0; i < 200; i++) {
      _stars.add(
        _Star(
          x: rng.nextDouble(),
          y: rng.nextDouble(),
          radius: 0.3 + rng.nextDouble() * 1.2,
          baseOpacity: 0.03 + rng.nextDouble() * 0.08,
          twinkleSpeed: 0.5 + rng.nextDouble() * 2.0,
          twinklePhase: rng.nextDouble() * math.pi * 2,
        ),
      );
    }
  }

  void _generateParticles() {
    final rng = math.Random(77);
    _particles.clear();
    for (int i = 0; i < 30; i++) {
      _particles.add(
        _Particle(
          x: rng.nextDouble(),
          y: rng.nextDouble(),
          vx: (rng.nextDouble() - 0.5) * 0.0003,
          vy: (rng.nextDouble() - 0.5) * 0.0003,
          radius: 1.0 + rng.nextDouble() * 2.0,
          opacity: 0.05 + rng.nextDouble() * 0.15,
        ),
      );
    }
  }

  // ── 3D transform (shared between hit-test and painter) ───────────

  Offset _transformPoint(Offset graphPos, Size screenSize) {
    final cx = _canvasSize / 2;
    final cy = _canvasSize / 2;

    final double x = graphPos.dx - cx;
    final double y = graphPos.dy - cy;

    final cosY = math.cos(_rotationY);
    final sinY = math.sin(_rotationY);
    final x2 = x * cosY;
    final z2 = x * sinY;

    final cosX = math.cos(_rotationX);
    final sinX = math.sin(_rotationX);
    final y2 = y * cosX - z2 * sinX;
    final z3 = y * sinX + z2 * cosX;

    final perspective = 1.0 / (1.0 + z3 * 0.001);
    final screenX =
        x2 * perspective * _zoom + screenSize.width / 2 + _panOffset.dx;
    final screenY =
        y2 * perspective * _zoom + screenSize.height / 2 + _panOffset.dy;

    return Offset(screenX, screenY);
  }

  /// Compute screen-space positions of all nodes for hit testing
  void _computeScreenPositions(Size screenSize) {
    _screenNodePositions.clear();
    for (final entry in _nodePositions.entries) {
      final ambient = _ambientOffsetForId(entry.key);
      final floating = _floatOffsetForId(entry.key);
      final graphPos = entry.value + ambient + floating;
      _screenNodePositions[entry.key] = _transformPoint(graphPos, screenSize);
    }
  }

  Offset _ambientOffsetForId(String id) {
    final phase = id.hashCode * 0.1;
    final dx = math.sin(_ambientController.value * 2 * math.pi + phase) * 2.0;
    final dy =
        math.cos(_ambientController.value * 2 * math.pi + phase * 0.7) * 2.0;
    return Offset(dx, dy);
  }

  Offset _floatOffsetForId(String id) {
    final phase = id.hashCode * 0.37;
    final dx = math.sin(_floatController.value * 2 * math.pi + phase) * 3.0;
    final dy =
        math.cos(_floatController.value * 2 * math.pi + phase * 0.6) * 3.0;
    return Offset(dx, dy);
  }

  // ── Touch hit-testing ────────────────────────────────────────────

  /// Find the nearest node to a screen tap position
  String? _findNearestNode(Offset screenPos) {
    String? nearestId;
    double nearestDist = double.infinity;
    final tapRadius = _nodeRadius * _zoom * 1.8; // generous tap target

    for (final entry in _screenNodePositions.entries) {
      final dist = (entry.value - screenPos).distance;
      if (dist < tapRadius && dist < nearestDist) {
        nearestDist = dist;
        nearestId = entry.key;
      }
    }
    return nearestId;
  }

  // ── Search/highlight ─────────────────────────────────────────────

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _highlightedNodeIds.clear();

      if (query.isEmpty) return;

      final q = query.toLowerCase();
      for (final entry in _nodes.entries) {
        final name = entry.value.person.name.toLowerCase();
        if (name.contains(q)) {
          _highlightedNodeIds.add(entry.key);
        }
      }

      // Auto-focus camera on first match
      if (_highlightedNodeIds.isNotEmpty) {
        final firstId = _highlightedNodeIds.first;
        _focusOnNode(firstId);
      }
    });
  }

  /// Focus camera on a specific node by adjusting pan offset
  void _focusOnNode(String nodeId) {
    final graphPos = _nodePositions[nodeId];
    if (graphPos == null) return;

    final cx = _canvasSize / 2;
    final cy = _canvasSize / 2;

    final double x = graphPos.dx - cx;
    final double y = graphPos.dy - cy;

    final cosY = math.cos(_rotationY);
    final sinY = math.sin(_rotationY);
    final x2 = x * cosY;
    final z2 = x * sinY;

    final cosX = math.cos(_rotationX);
    final sinX = math.sin(_rotationX);
    final y2 = y * cosX - z2 * sinX;
    final z3 = y * sinX + z2 * cosX;

    final perspective = 1.0 / (1.0 + z3 * 0.001);

    // We want the node to appear at screen center
    // screenX = x2 * perspective * zoom + width/2 + panOffset.dx
    // 0 = x2 * perspective * zoom + panOffset.dx
    // panOffset.dx = -x2 * perspective * zoom
    setState(() {
      _panOffset = Offset(-x2 * perspective * _zoom, -y2 * perspective * _zoom);
      _zoom = _zoom.clamp(1.0, 2.0);
    });
  }

  // ── Auto-layout animation ────────────────────────────────────────

  void _onLayoutAnimationTick() {
    if (!_isAnimatingLayout) return;

    final t = _layoutAnimation.value;
    final interpolated = <String, Offset>{};

    for (final id in _targetPositions.keys) {
      final from = _previousPositions[id] ?? _targetPositions[id]!;
      final to = _targetPositions[id]!;
      interpolated[id] = Offset(
        from.dx + (to.dx - from.dx) * t,
        from.dy + (to.dy - from.dy) * t,
      );
    }

    // Also include any positions in previous but not in target
    for (final id in _previousPositions.keys) {
      if (!interpolated.containsKey(id)) {
        interpolated[id] = _previousPositions[id]!;
      }
    }

    setState(() {
      _nodePositions = interpolated;
    });

    if (_layoutAnimationController.isCompleted) {
      _isAnimatingLayout = false;
      _nodePositions = Map.from(_targetPositions);
    }
  }

  void _switchLayoutMode(Tree3DLayoutMode newMode) {
    if (newMode == _layoutMode && !_isAnimatingLayout) return;

    // Save current positions as start for animation
    _previousPositions = Map.from(_nodePositions);

    setState(() {
      _layoutMode = newMode;
    });

    // Compute target positions for the new layout
    _computeLayoutPositions();

    // Start animation
    _targetPositions = Map.from(_nodePositions);
    _nodePositions = Map.from(_previousPositions);

    setState(() {
      _isAnimatingLayout = true;
    });

    _layoutAnimationController.forward(from: 0.0);
  }

  /// Compute only the positions (without re-computing the full tree structure)
  void _computeLayoutPositions() {
    switch (_layoutMode) {
      case Tree3DLayoutMode.constellation:
        _computeConstellationLayout();
      case Tree3DLayoutMode.galaxy:
        _computeGalaxyLayout();
      case Tree3DLayoutMode.solar:
        _computeSolarLayout();
    }

    // Ensure all nodes have positions
    for (final id in _nodes.keys) {
      _nodePositions.putIfAbsent(
        id,
        () => const Offset(_canvasSize / 2, _canvasSize / 2),
      );
    }
  }

  // ── Minimap navigation ───────────────────────────────────────────

  void _onMinimapTap(Offset minimapTapPos, Size minimapSize) {
    // Convert minimap tap to graph space
    final graphX = (minimapTapPos.dx / minimapSize.width) * _canvasSize;
    final graphY = (minimapTapPos.dy / minimapSize.height) * _canvasSize;

    // Adjust pan offset so that graph point appears at screen center
    final graphPos = Offset(graphX, graphY);

    final cx = _canvasSize / 2;
    final cy = _canvasSize / 2;
    final double x = graphPos.dx - cx;
    final double y = graphPos.dy - cy;

    final cosY = math.cos(_rotationY);
    final sinY = math.sin(_rotationY);
    final x2 = x * cosY;
    final z2 = x * sinY;

    final cosX = math.cos(_rotationX);
    final sinX = math.sin(_rotationX);
    final y2 = y * cosX - z2 * sinX;
    final z3 = y * sinX + z2 * cosX;

    final perspective = 1.0 / (1.0 + z3 * 0.001);

    setState(() {
      _panOffset = Offset(-x2 * perspective * _zoom, -y2 * perspective * _zoom);
    });
  }

  // ── Layout computation ─────────────────────────────────────────────

  void _computeLayout(List<Person> members, List<FamilyRelationship> rels) {
    _nodePositions.clear();
    _nodeGenerations.clear();
    _nodeLineages.clear();
    _edges.clear();
    _nodes.clear();

    final activeMembers = members.where((p) => p.deletedAt == null).toList();
    if (activeMembers.isEmpty) return;

    final persons = activeMembers.map((p) => p.toGraphPerson()).toList();
    final graphEdges = rels.map((r) => r.toGraphEdge()).toList();

    final personMap = {for (final p in persons) p.id: p};
    final memberMap = {for (final m in activeMembers) m.id: m};

    // Build tree relationships
    final childOf = <String, String>{};
    final spouseOf = <String, String>{};
    final lineageOf = <String, String>{};

    for (final rel in graphEdges) {
      final type = rel.type.toLowerCase();
      if (['child', 'son', 'daughter'].contains(type)) {
        childOf[rel.fromId] = rel.toId;
      } else if (['father', 'mother', 'parent'].contains(type)) {
        childOf[rel.toId] = rel.fromId;
      } else if (type == 'spouse' || type == 'husband' || type == 'wife') {
        spouseOf[rel.fromId] = rel.toId;
        spouseOf[rel.toId] = rel.fromId;
      }
      if (type == 'father' || type == 'paternal_grandfather') {
        lineageOf[rel.toId] = 'paternal';
      } else if (type == 'mother' || type == 'maternal_grandfather') {
        lineageOf[rel.toId] = 'maternal';
      }
    }

    // Build tree nodes
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

      final childIds = <String>[];
      for (final entry in childOf.entries) {
        if (entry.value == id && !usedIds.contains(entry.key)) {
          childIds.add(entry.key);
        }
      }

      final childNodes = <VisTreeNode>[];
      for (final childId in childIds) {
        final node = buildNode(childId);
        if (node != null) childNodes.add(node);
      }

      String lineage = lineageOf[id] ?? '';
      final familyDetail = ref.read(familyDetailProvider(widget.familyId));
      final anchorId = familyDetail.valueOrNull?.family.anchorPersonId;
      if (id == anchorId) lineage = 'self';

      return VisTreeNode(
        person: person,
        spouse: spouse,
        children: childNodes,
        lineage: lineage,
      );
    }

    // Find root nodes
    final rootIds = <String>{};
    for (final p in persons) {
      if (!childOf.containsKey(p.id)) {
        rootIds.add(p.id);
      }
    }
    if (rootIds.isEmpty && persons.isNotEmpty) {
      rootIds.add(persons.first.id);
    }

    final roots = <VisTreeNode>[];
    for (final rootId in rootIds) {
      final node = buildNode(rootId);
      if (node != null) roots.add(node);
    }
    for (final p in persons) {
      if (!usedIds.contains(p.id)) {
        roots.add(VisTreeNode(person: p, lineage: ''));
        usedIds.add(p.id);
      }
    }

    // Collect nodes, edges, generations
    void collectNodes(VisTreeNode node, int depth) {
      final id = node.person.id;
      _nodes[id] = node;
      _nodeLineages[id] = node.lineage;
      _nodeGenerations[id] = depth;

      final member = memberMap[id];
      if (member != null && member.generationIndex > 0) {
        _nodeGenerations[id] = member.generationIndex;
      }

      if (node.spouse != null) {
        final spouseId = node.spouse!.id;
        _nodes[spouseId] = VisTreeNode(
          person: node.spouse!,
          lineage: 'marital',
        );
        _nodeLineages[spouseId] = 'marital';
        _nodeGenerations[spouseId] = depth;
        final spouseMember = memberMap[spouseId];
        if (spouseMember != null && spouseMember.generationIndex > 0) {
          _nodeGenerations[spouseId] = spouseMember.generationIndex;
        }
        _edges.add(
          VisEdge(
            fromId: id,
            toId: spouseId,
            type: EdgeType.spouse,
            label: 'spouse',
          ),
        );
      }

      for (final child in node.children) {
        _edges.add(
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
    final existingEdgeSet = <String>{};
    for (final e in _edges) {
      existingEdgeSet.add('${e.fromId}-${e.toId}');
      existingEdgeSet.add('${e.toId}-${e.fromId}');
    }

    for (final rel in graphEdges) {
      final key1 = '${rel.fromId}-${rel.toId}';
      if (existingEdgeSet.contains(key1)) continue;

      final type = rel.type.toLowerCase();
      EdgeType? edgeType;
      if (type.contains('sibling') || type == 'brother' || type == 'sister') {
        edgeType = EdgeType.sibling;
      } else if (type.contains('in_law') || type.contains('inlaw')) {
        edgeType = EdgeType.inLaw;
      }

      if (edgeType != null &&
          _nodes.containsKey(rel.fromId) &&
          _nodes.containsKey(rel.toId)) {
        _edges.add(
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
    _computeLayoutPositions();
  }

  // ── Constellation layout (force-directed) ─────────────────────────

  void _computeConstellationLayout() {
    final center = const Offset(_canvasSize / 2, _canvasSize / 2);
    final allIds = _nodes.keys.toList();
    final positions = <String, Offset>{};

    // Use generation-based radial placement for a nice default layout
    final byGen = <int, List<String>>{};
    for (final entry in _nodeGenerations.entries) {
      byGen.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    for (final entry in byGen.entries) {
      final gen = entry.key;
      final ids = entry.value;
      final ringRadius = 140.0 * gen;
      final angleStep = 2 * math.pi / math.max(ids.length, 1);
      for (int i = 0; i < ids.length; i++) {
        final angle = angleStep * i - math.pi / 2;
        positions[ids[i]] = Offset(
          center.dx + ringRadius * math.cos(angle),
          center.dy + ringRadius * math.sin(angle),
        );
      }
    }

    // Simple force relaxation
    for (int step = 0; step < 40; step++) {
      final forces = {for (final id in allIds) id: Offset.zero};

      // Repulsion
      for (int i = 0; i < allIds.length; i++) {
        for (int j = i + 1; j < allIds.length; j++) {
          final a = allIds[i];
          final b = allIds[j];
          final posA = positions[a] ?? center;
          final posB = positions[b] ?? center;
          final delta = posA - posB;
          final dist = math.max(delta.distance, 0.1);
          final force = 4000 / (dist * dist);
          final direction = delta / dist;
          forces[a] = forces[a]! + direction * force;
          forces[b] = forces[b]! - direction * force;
        }
      }

      // Attraction
      for (final edge in _edges) {
        if (!positions.containsKey(edge.fromId) ||
            !positions.containsKey(edge.toId)) {
          continue;
        }
        final delta = positions[edge.toId]! - positions[edge.fromId]!;
        final dist = math.max(delta.distance, 0.1);
        final force = 0.003 * (dist - 120);
        final direction = delta / dist;
        forces[edge.fromId] = forces[edge.fromId]! + direction * force;
        forces[edge.toId] = forces[edge.toId]! - direction * force;
      }

      // Gravity
      for (final id in allIds) {
        final delta = center - (positions[id] ?? center);
        forces[id] = forces[id]! + delta * 0.005;
      }

      for (final id in allIds) {
        positions[id] = (positions[id] ?? center) + forces[id]! * 0.5;
      }
    }

    _nodePositions = positions;
  }

  // ── Galaxy layout (spiral galaxy) ─────────────────────────────────

  void _computeGalaxyLayout() {
    final center = const Offset(_canvasSize / 2, _canvasSize / 2);

    // Sort by generation for spiral arm assignment
    final byGen = <int, List<String>>{};
    for (final entry in _nodeGenerations.entries) {
      byGen.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    // Spiral galaxy: multiple arms
    const armCount = 2;
    final positions = <String, Offset>{};

    int globalIndex = 0;
    final sortedGens = byGen.keys.toList()..sort();

    for (final gen in sortedGens) {
      final ids = byGen[gen]!;
      for (int i = 0; i < ids.length; i++) {
        final arm = globalIndex % armCount;
        final armOffset = (2 * math.pi / armCount) * arm;
        final t = globalIndex * 0.3;
        final spiralRadius = 80.0 + t * 30;
        final spiralAngle = armOffset + t * 0.8;

        // Add some spread for same-gen nodes
        final spread = (i - ids.length / 2) * 15.0;

        positions[ids[i]] = Offset(
          center.dx +
              spiralRadius * math.cos(spiralAngle) +
              spread * math.cos(spiralAngle + math.pi / 2),
          center.dy +
              spiralRadius * math.sin(spiralAngle) +
              spread * math.sin(spiralAngle + math.pi / 2),
        );
        globalIndex++;
      }
    }

    _nodePositions = positions;
  }

  // ── Solar layout (solar system with center node) ──────────────────

  void _computeSolarLayout() {
    final center = const Offset(_canvasSize / 2, _canvasSize / 2);
    final familyDetail = ref.read(familyDetailProvider(widget.familyId));
    final anchorId = familyDetail.valueOrNull?.family.anchorPersonId;

    // Place anchor in center
    final positions = <String, Offset>{};
    if (anchorId != null && _nodes.containsKey(anchorId)) {
      positions[anchorId] = center;
    }

    // Group by generation for orbital rings
    final byGen = <int, List<String>>{};
    for (final entry in _nodeGenerations.entries) {
      if (_nodeGenerations[entry.key] == _nodeGenerations[anchorId]) continue;
      byGen.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    final sortedGens = byGen.keys.toList()..sort();

    for (final gen in sortedGens) {
      final ids = byGen[gen]!;
      final genDiff =
          (gen - (anchorId != null ? (_nodeGenerations[anchorId] ?? 1) : 1))
              .abs();
      final ringRadius = 120.0 + genDiff * 100.0;
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

    _nodePositions = positions;
  }

  // ── Reset view ─────────────────────────────────────────────────────

  void _resetView() {
    setState(() {
      _rotationX = 0.0;
      _rotationY = 0.0;
      _zoom = 1.0;
      _panOffset = Offset.zero;
    });
  }

  // ── Handle node tap ────────────────────────────────────────────────

  void _handleNodeTap(Person person) {
    // Find the relationship key for this person
    final familyDetail = ref.read(familyDetailProvider(widget.familyId));
    final rels = familyDetail.valueOrNull?.relationships ?? [];
    String? relKey;
    for (final rel in rels) {
      if (rel.toPersonId == person.id || rel.fromPersonId == person.id) {
        relKey = rel.relationshipKey;
        break;
      }
    }

    setState(() {
      _selectedPerson = person;
      _selectedRelationshipKey = relKey;
    });
  }

  void _dismissDetail() {
    setState(() {
      _selectedPerson = null;
      _selectedRelationshipKey = null;
    });
  }

  // ════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final familyDetailAsync = ref.watch(familyDetailProvider(widget.familyId));

    return DKScaffold(
      backgroundColor: KinrelColors.darkBackground,
      body: familyDetailAsync.when(
        loading: () => _buildLoadingState(),
        error: (e, _) => _buildErrorState(e),
        data: (detail) {
          if (detail == null) return _buildErrorState('Family not found');

          // Compute layout
          _computeLayout(detail.members, detail.relationships);

          // Compute screen positions for hit testing
          final screenSize = MediaQuery.of(context).size;
          _computeScreenPositions(screenSize);

          return Stack(
            children: [
              // ── 3D Canvas ────────────────────────────────────────
              GestureDetector(
                onDoubleTap: _resetView,
                onTapUp: (details) {
                  final tappedId = _findNearestNode(details.localPosition);
                  if (tappedId != null) {
                    Person? member;
                    for (final p in detail.members) {
                      if (p.id == tappedId && p.deletedAt == null) {
                        member = p;
                        break;
                      }
                    }
                    if (member != null) {
                      _handleNodeTap(member);
                    }
                  } else {
                    // Tap on empty space dismisses selection
                    if (_selectedPerson != null) {
                      _dismissDetail();
                    }
                  }
                },
                onScaleStart: (details) {
                  _lastPanPosition = details.focalPoint;
                },
                onScaleUpdate: (details) {
                  final delta = details.focalPoint - _lastPanPosition;
                  setState(() {
                    if (details.pointerCount >= 2) {
                      // Pinch to zoom
                      _zoom = (_zoom * details.scale).clamp(0.3, 3.0);
                      // Two-finger drag rotates
                      _rotationY += delta.dx * 0.005;
                      _rotationX += delta.dy * 0.005;
                    } else {
                      // Single-finger drag rotates
                      _rotationY += delta.dx * 0.005;
                      _rotationX += delta.dy * 0.005;
                    }
                    // Clamp rotation
                    _rotationX = _rotationX.clamp(-0.5, 0.5);
                    _rotationY = _rotationY.clamp(-1.0, 1.0);
                  });
                  _lastPanPosition = details.focalPoint;
                },
                child: SizedBox.expand(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _ambientController,
                      _pulseController,
                      _floatController,
                      _layoutAnimationController,
                    ]),
                    builder: (context, _) {
                      // Recompute screen positions on each animation frame
                      _computeScreenPositions(screenSize);

                      return CustomPaint(
                        painter: _Tree3DCanvasPainter(
                          nodePositions: _nodePositions,
                          nodeGenerations: _nodeGenerations,
                          nodeLineages: _nodeLineages,
                          edges: _edges,
                          nodes: _nodes,
                          members: detail.members,
                          anchorPersonId: detail.family.anchorPersonId,
                          rotationX: _rotationX,
                          rotationY: _rotationY,
                          zoom: _zoom,
                          panOffset: _panOffset,
                          ambientValue: _ambientController.value,
                          pulseValue: _pulseController.value,
                          floatValue: _floatController.value,
                          stars: _stars,
                          particles: _particles,
                          selectedPersonId: _selectedPerson?.id,
                          layoutMode: _layoutMode,
                          highlightedNodeIds: _highlightedNodeIds,
                          searchQuery: _searchQuery,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── Search bar (top-center) ─────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 48,
                left: 12,
                right: _showControls ? 230 : 12,
                child: _SearchBar3D(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  query: _searchQuery,
                  matchCount: _highlightedNodeIds.length,
                  onChanged: _onSearchChanged,
                  onClear: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
              ),

              // ── Floating control panel (top-right) ──────────────
              if (_showControls)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 12,
                  child: _FloatingControlPanel(
                    rotationX: _rotationX,
                    rotationY: _rotationY,
                    zoom: _zoom,
                    layoutMode: _layoutMode,
                    onRotationXChanged: (v) => setState(() => _rotationX = v),
                    onRotationYChanged: (v) => setState(() => _rotationY = v),
                    onZoomChanged: (v) => setState(() => _zoom = v),
                    onLayoutModeChanged: _switchLayoutMode,
                    onReset: _resetView,
                  ),
                ),

              // ── Toggle controls button ──────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: _showControls ? 220 : 12,
                child: _ControlToggleButton(
                  isOpen: _showControls,
                  onTap: () => setState(() => _showControls = !_showControls),
                ),
              ),

              // ── Back button ─────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: _BackButton(onTap: () => context.pop()),
              ),

              // ── Title bar ───────────────────────────────────────
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 56,
                right: _showControls ? 230 : 56,
                child: _TitleBar(familyName: detail.family.name),
              ),

              // ── Minimap (bottom-left) ───────────────────────────
              Positioned(
                bottom: 24,
                left: 12,
                child: _Minimap3D(
                  nodePositions: _nodePositions,
                  nodeGenerations: _nodeGenerations,
                  anchorPersonId: detail.family.anchorPersonId,
                  screenSize: screenSize,
                  zoom: _zoom,
                  panOffset: _panOffset,
                  rotationX: _rotationX,
                  rotationY: _rotationY,
                  transformPoint: _transformPoint,
                  onTap: _onMinimapTap,
                ),
              ),

              // ── Node detail popup ───────────────────────────────
              if (_selectedPerson != null)
                _NodeDetailPopup(
                  person: _selectedPerson!,
                  relationshipKey: _selectedRelationshipKey,
                  familyId: widget.familyId,
                  primaryLanguage: detail.family.primaryLanguage,
                  onDismiss: _dismissDetail,
                  onNodeTap: _handleNodeTap,
                  members: detail.members,
                  relationships: detail.relationships,
                  nodeGenerations: _nodeGenerations,
                  nodes: _nodes,
                  edges: _edges,
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Loading state ──────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(KinrelColors.orange),
            ),
          ).animate(onPlay: (c) => c.repeat()).fadeIn(duration: 600.ms),
          const SizedBox(height: 16),
          Text(
            'Loading 3D Tree...',
            style: KinrelTypography.bodyMedium.copyWith(
              color: KinrelColors.textSilver,
            ),
          ),
        ],
      ),
    );
  }

  // ── Error state ────────────────────────────────────────────────────

  Widget _buildErrorState(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: DKCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: KinrelColors.error,
                size: 40,
              ),
              const SizedBox(height: 16),
              Text(
                'Could not load family tree',
                style: KinrelTypography.headlineSmall.copyWith(
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: KinrelTypography.bodySmall.copyWith(
                  color: KinrelColors.textSilver,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 3D CANVAS PAINTER
// ═══════════════════════════════════════════════════════════════════════

class _Tree3DCanvasPainter extends CustomPainter {
  _Tree3DCanvasPainter({
    required this.nodePositions,
    required this.nodeGenerations,
    required this.nodeLineages,
    required this.edges,
    required this.nodes,
    required this.members,
    required this.anchorPersonId,
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
    required this.panOffset,
    required this.ambientValue,
    required this.pulseValue,
    required this.floatValue,
    required this.stars,
    required this.particles,
    required this.selectedPersonId,
    required this.layoutMode,
    required this.highlightedNodeIds,
    required this.searchQuery,
  });

  final Map<String, Offset> nodePositions;
  final Map<String, int> nodeGenerations;
  final Map<String, String> nodeLineages;
  final List<VisEdge> edges;
  final Map<String, VisTreeNode> nodes;
  final List<Person> members;
  final String? anchorPersonId;
  final double rotationX;
  final double rotationY;
  final double zoom;
  final Offset panOffset;
  final double ambientValue;
  final double pulseValue;
  final double floatValue;
  final List<_Star> stars;
  final List<_Particle> particles;
  final String? selectedPersonId;
  final Tree3DLayoutMode layoutMode;
  final Set<String> highlightedNodeIds;
  final String searchQuery;

  static const double _nodeRadius = 24.0;
  static const double _canvasSize = 2000.0;

  // Generation ring colors
  static const Color _genGrandparent = Color(0xFFC44A18);
  static const Color _genParent = Color(0xFFE8612A);
  static const Color _genUser = Color(0xFFF59240);
  static const Color _genChild = Color(0xFFFFB870);

  Color _generationRingColor(int generation) {
    if (generation >= 3) return _genGrandparent;
    if (generation == 2) return _genParent;
    if (generation == 1) return _genUser;
    return _genChild;
  }

  Offset _ambientOffset(String id) {
    final phase = id.hashCode * 0.1;
    final dx = math.sin(ambientValue * 2 * math.pi + phase) * 2.0;
    final dy = math.cos(ambientValue * 2 * math.pi + phase * 0.7) * 2.0;
    return Offset(dx, dy);
  }

  Offset _floatOffset(String id) {
    final phase = id.hashCode * 0.37;
    final dx = math.sin(floatValue * 2 * math.pi + phase) * 3.0;
    final dy = math.cos(floatValue * 2 * math.pi + phase * 0.6) * 3.0;
    return Offset(dx, dy);
  }

  /// Whether search highlight mode is active
  bool get _isSearchActive =>
      searchQuery.isNotEmpty && highlightedNodeIds.isNotEmpty;

  /// Transform a graph-space offset to screen-space using 3D perspective
  Offset _transformPoint(Offset graphPos, Size screenSize) {
    // Center of the canvas in graph space
    final cx = _canvasSize / 2;
    final cy = _canvasSize / 2;

    // Translate to origin
    final double x = graphPos.dx - cx;
    final double y = graphPos.dy - cy;

    // Apply rotation Y (yaw)
    final cosY = math.cos(rotationY);
    final sinY = math.sin(rotationY);
    final x2 = x * cosY;
    final z2 = x * sinY;

    // Apply rotation X (pitch)
    final cosX = math.cos(rotationX);
    final sinX = math.sin(rotationX);
    final y2 = y * cosX - z2 * sinX;
    final z3 = y * sinX + z2 * cosX;

    // Perspective projection
    final perspective = 1.0 / (1.0 + z3 * 0.001);
    final screenX =
        x2 * perspective * zoom + screenSize.width / 2 + panOffset.dx;
    final screenY =
        y2 * perspective * zoom + screenSize.height / 2 + panOffset.dy;

    return Offset(screenX, screenY);
  }

  /// Get depth (z-value) for a graph point after rotation
  double _getDepth(Offset graphPos) {
    final cx = _canvasSize / 2;
    final cy = _canvasSize / 2;
    final double x = graphPos.dx - cx;
    final double y = graphPos.dy - cy;

    final sinY = math.sin(rotationY);
    final z2 = x * sinY;

    final cosX = math.cos(rotationX);
    final sinX = math.sin(rotationX);
    final z3 = y * sinX + z2 * cosX;

    return z3;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ── Deep space background ──────────────────────────────────────
    final bgPaint = Paint()..color = KinrelColors.darkBackground;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // ── Ambient orange glow from center ────────────────────────────
    final glowCenter = Offset(size.width / 2, size.height / 2);
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            center: Alignment.center,
            radius: 0.6,
            colors: [
              KinrelColors.orange.withValues(alpha: 0.08),
              KinrelColors.amber.withValues(alpha: 0.03),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(center: glowCenter, radius: size.width * 0.6),
          );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), glowPaint);

    // ── Star field ─────────────────────────────────────────────────
    _drawStarfield(canvas, size);

    // ── Floating particles ─────────────────────────────────────────
    _drawParticles(canvas, size);

    if (nodePositions.isEmpty) return;

    // ── Generation rings (3D concentric rings) ─────────────────────
    _drawGenerationRings(canvas, size);

    // ── Transform all positions ────────────────────────────────────
    final transformedPositions = <String, Offset>{};
    final depthMap = <String, double>{};

    for (final entry in nodePositions.entries) {
      final ambient = _ambientOffset(entry.key);
      final floating = _floatOffset(entry.key);
      final graphPos = entry.value + ambient + floating;
      transformedPositions[entry.key] = _transformPoint(graphPos, size);
      depthMap[entry.key] = _getDepth(graphPos);
    }

    // Sort by depth (furthest first = painter's algorithm)
    final sortedIds = nodePositions.keys.toList()
      ..sort((a, b) => depthMap[b]!.compareTo(depthMap[a]!));

    // ── Draw edges ─────────────────────────────────────────────────
    for (final edge in edges) {
      final from = transformedPositions[edge.fromId];
      final to = transformedPositions[edge.toId];
      if (from == null || to == null) continue;

      final isConnectedToSelected =
          edge.fromId == selectedPersonId || edge.toId == selectedPersonId;

      // Search highlight: dim edges not connected to highlighted nodes
      final isEdgeHighlighted =
          _isSearchActive &&
          (highlightedNodeIds.contains(edge.fromId) ||
              highlightedNodeIds.contains(edge.toId));
      final isEdgeDimmed = _isSearchActive && !isEdgeHighlighted;

      Color color;
      double width;
      switch (edge.type) {
        case EdgeType.spouse:
          color = const Color(0xFFE8612A);
          width = 2.0;
        case EdgeType.parentChild:
          color = const Color(0xFFF5F0EE);
          width = 1.5;
        case EdgeType.sibling:
          color = const Color(0xFFF59240);
          width = 1.0;
        case EdgeType.inLaw:
          color = const Color(0xFFC9B4A8);
          width = 1.0;
        case EdgeType.unknown:
          color = const Color(0xFFF5F0EE).withValues(alpha: 0.3);
          width = 1.0;
      }

      if (isConnectedToSelected) {
        color = const Color(0xFFE8612A);
        width = width * 1.5;

        final glowPaint = Paint()
          ..color = const Color(0xFFE8612A).withValues(alpha: 0.15)
          ..strokeWidth = width + 6
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        _drawEdgePath(canvas, from, to, edge.type, glowPaint);
      }

      // Depth-based opacity for edges
      final fromDepth = depthMap[edge.fromId] ?? 0.0;
      final toDepth = depthMap[edge.toId] ?? 0.0;
      final avgDepth = (fromDepth + toDepth) / 2;
      double edgeOpacity = (1.0 - avgDepth.abs() * 0.0003).clamp(
        0.2,
        isConnectedToSelected ? 0.9 : 0.4,
      );

      // Dim edges during search
      if (isEdgeDimmed) {
        edgeOpacity *= 0.15;
      }
      // Brighten highlighted edges during search
      if (isEdgeHighlighted) {
        edgeOpacity = (edgeOpacity * 1.5).clamp(0.5, 1.0);
      }

      final paint = Paint()
        ..color = color.withValues(alpha: edgeOpacity)
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      _drawEdgePath(canvas, from, to, edge.type, paint);

      // Heart/diamond at midpoint for spouse
      if (edge.type == EdgeType.spouse) {
        final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
        _drawDiamond(
          canvas,
          mid,
          5.0,
          const Color(0xFFE8612A).withValues(alpha: edgeOpacity),
        );
      }
    }

    // ── Draw nodes (depth-sorted) ──────────────────────────────────
    for (final id in sortedIds) {
      final pos = transformedPositions[id]!;
      final depth = depthMap[id]!;
      _drawNode(canvas, id, pos, depth, size);
    }
  }

  // ── Star field ──────────────────────────────────────────────────────

  void _drawStarfield(Canvas canvas, Size size) {
    for (final star in stars) {
      final twinkle = math.sin(
        ambientValue * 2 * math.pi * star.twinkleSpeed + star.twinklePhase,
      );
      final opacity = star.baseOpacity + twinkle * 0.03;
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        Paint()
          ..color = const Color(
            0xFFF5F0EE,
          ).withValues(alpha: opacity.clamp(0.0, 1.0)),
      );
    }
  }

  // ── Floating particles ──────────────────────────────────────────────

  void _drawParticles(Canvas canvas, Size size) {
    for (final p in particles) {
      // Update position (wrapping)
      p.x = (p.x + p.vx) % 1.0;
      p.y = (p.y + p.vy) % 1.0;
      if (p.x < 0) p.x += 1.0;
      if (p.y < 0) p.y += 1.0;

      final pulse = math.sin(ambientValue * 2 * math.pi + p.x * 10) * 0.05;
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.radius,
        Paint()
          ..color = KinrelColors.orange.withValues(
            alpha: (p.opacity + pulse).clamp(0.0, 1.0),
          ),
      );
    }
  }

  // ── Generation rings (3D concentric) ────────────────────────────────

  void _drawGenerationRings(Canvas canvas, Size screenSize) {
    if (nodeGenerations.isEmpty) return;

    final center = nodePositions[anchorPersonId] ?? nodePositions.values.first;
    final maxGen = nodeGenerations.values.fold(0, math.max);
    final minGen = nodeGenerations.values.fold(100, math.min);

    for (int gen = minGen; gen <= maxGen; gen++) {
      final ringRadius = (gen - minGen + 1) * 140.0;
      final ringColor = _generationRingColor(gen);

      // Draw ring as polygon of transformed points
      final pointCount = 60;
      final ringPath = Path();
      for (int i = 0; i <= pointCount; i++) {
        final angle = (i / pointCount) * 2 * math.pi;
        final graphPos = Offset(
          center.dx + ringRadius * math.cos(angle),
          center.dy + ringRadius * math.sin(angle),
        );
        final screenPos = _transformPoint(graphPos, screenSize);
        if (i == 0) {
          ringPath.moveTo(screenPos.dx, screenPos.dy);
        } else {
          ringPath.lineTo(screenPos.dx, screenPos.dy);
        }
      }

      // Glow ring
      final glowPaint = Paint()
        ..color = ringColor.withValues(alpha: 0.06 + pulseValue * 0.02)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawPath(ringPath, glowPaint);

      // Sharp ring
      final ringPaint = Paint()
        ..color = ringColor.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawPath(ringPath, ringPaint);

      // Generation label
      final labelAngle = -math.pi / 2;
      final labelPos = _transformPoint(
        Offset(
          center.dx + (ringRadius + 16) * math.cos(labelAngle),
          center.dy + (ringRadius + 16) * math.sin(labelAngle),
        ),
        screenSize,
      );
      final labelPainter = TextPainter(
        text: TextSpan(
          text: 'Gen $gen',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9,
            color: ringColor.withValues(alpha: 0.25),
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(
          labelPos.dx - labelPainter.width / 2,
          labelPos.dy - labelPainter.height / 2,
        ),
      );
    }
  }

  // ── Edge path drawing (enhanced bezier curves) ────────────────────

  void _drawEdgePath(
    Canvas canvas,
    Offset start,
    Offset end,
    EdgeType type,
    Paint paint,
  ) {
    switch (type) {
      case EdgeType.parentChild:
        // Smooth S-curve from parent down to child
        final midY = (start.dy + end.dy) / 2;
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx,
            start.dy + (midY - start.dy) * 0.6,
            end.dx,
            end.dy - (end.dy - midY) * 0.6,
            end.dx,
            end.dy,
          );
        canvas.drawPath(path, paint);

      case EdgeType.spouse:
        // Horizontal bezier with slight arc
        final midX = (start.dx + end.dx) / 2;
        final dy = (end.dy - start.dy).abs();
        final arcHeight = dy < 30
            ? -20.0
            : 0.0; // gentle arc when nodes are level
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + (midX - start.dx) * 0.5,
            start.dy + arcHeight,
            end.dx - (end.dx - midX) * 0.5,
            end.dy + arcHeight,
            end.dx,
            end.dy,
          );
        canvas.drawPath(path, paint);

      case EdgeType.sibling:
        // Dashed bezier curve (arc above/below)
        final midX = (start.dx + end.dx) / 2;
        final midY = (start.dy + end.dy) / 2;
        final dist = (end - start).distance;
        final arcHeight = -dist * 0.15; // arc outward
        final controlY = midY + arcHeight;
        _drawDashedBezier(
          canvas,
          start,
          Offset(midX, controlY),
          end,
          paint,
          6,
          4,
        );

      case EdgeType.inLaw:
        // Dotted curve
        final midX = (start.dx + end.dx) / 2;
        final midY = (start.dy + end.dy) / 2;
        final dist = (end - start).distance;
        final arcHeight = dist * 0.1;
        final controlY = midY + arcHeight;
        _drawDottedBezier(
          canvas,
          start,
          Offset(midX, controlY),
          end,
          paint,
          2,
          6,
        );

      default:
        canvas.drawLine(start, end, paint);
    }
  }

  /// Draw a dashed quadratic bezier curve
  void _drawDashedBezier(
    Canvas canvas,
    Offset start,
    Offset control,
    Offset end,
    Paint paint,
    double dashLen,
    double gapLen,
  ) {
    final totalLen = _bezierLength(start, control, end);
    final segments = (totalLen / (dashLen + gapLen)).floor();
    final stepsPerDash = 4;

    for (int seg = 0; seg < segments; seg++) {
      final startT = seg * (dashLen + gapLen) / totalLen;
      final endT = (seg * (dashLen + gapLen) + dashLen) / totalLen;

      final path = Path();
      for (int s = 0; s <= stepsPerDash; s++) {
        final t = startT + (endT - startT) * s / stepsPerDash;
        final point = _quadraticBezierPoint(start, control, end, t);
        if (s == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  /// Draw a dotted quadratic bezier curve
  void _drawDottedBezier(
    Canvas canvas,
    Offset start,
    Offset control,
    Offset end,
    Paint paint,
    double dotRadius,
    double spacing,
  ) {
    final totalLen = _bezierLength(start, control, end);
    final steps = (totalLen / spacing).floor();
    final dotPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final point = _quadraticBezierPoint(start, control, end, t);
      canvas.drawCircle(point, dotRadius, dotPaint);
    }
  }

  /// Approximate length of a quadratic bezier
  double _bezierLength(Offset start, Offset control, Offset end) {
    double len = 0;
    Offset prev = start;
    for (int i = 1; i <= 20; i++) {
      final t = i / 20;
      final p = _quadraticBezierPoint(start, control, end, t);
      len += (p - prev).distance;
      prev = p;
    }
    return len;
  }

  /// Evaluate quadratic bezier at parameter t
  Offset _quadraticBezierPoint(
    Offset start,
    Offset control,
    Offset end,
    double t,
  ) {
    final mt = 1 - t;
    return Offset(
      mt * mt * start.dx + 2 * mt * t * control.dx + t * t * end.dx,
      mt * mt * start.dy + 2 * mt * t * control.dy + t * t * end.dy,
    );
  }

  /// Draw a diamond shape at a position (for spouse edge midpoint)
  void _drawDiamond(Canvas canvas, Offset center, double size, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy - size)
      ..lineTo(center.dx + size, center.dy)
      ..lineTo(center.dx, center.dy + size)
      ..lineTo(center.dx - size, center.dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  // ── Node drawing with 3D effects ────────────────────────────────────

  void _drawNode(
    Canvas canvas,
    String id,
    Offset center,
    double depth,
    Size screenSize,
  ) {
    final isSelected = id == selectedPersonId;
    final isAnchor = id == anchorPersonId;
    final node = nodes[id];
    final generation = nodeGenerations[id] ?? 1;
    final isDeceased = node?.person.isDeceased ?? false;
    final name = node?.person.name ?? 'Unknown';
    final relationship = node?.person.relationship;

    // Depth-based effects
    final depthScale = 1.0 + depth * 0.0001;
    final effectiveRadius = (_nodeRadius * depthScale * zoom).clamp(8.0, 60.0);
    double depthOpacity = (1.0 - depth.abs() * 0.0003).clamp(0.4, 1.0);

    // ── Search highlight/dim effects ────────────────────────────────
    final isHighlighted = _isSearchActive && highlightedNodeIds.contains(id);
    final isDimmed = _isSearchActive && !isHighlighted;

    if (isDimmed) {
      depthOpacity *= 0.2;
    }

    final ringColor = _generationRingColor(generation);

    // ── Search highlight glow (pulsing bright glow) ────────────────
    if (isHighlighted) {
      final highlightAlpha = 0.25 + pulseValue * 0.2;
      final highlightPaint = Paint()
        ..color = KinrelColors.amber.withValues(alpha: highlightAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
      canvas.drawCircle(center, effectiveRadius + 16, highlightPaint);

      // Outer ring pulse
      final ringAlpha = 0.15 + pulseValue * 0.15;
      final ringPaint2 = Paint()
        ..color = KinrelColors.amber.withValues(alpha: ringAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(
        center,
        effectiveRadius + 10 + pulseValue * 6,
        ringPaint2,
      );
    }

    // ── Selection glow (pulsing orange) ────────────────────────────
    if (isSelected) {
      final glowAlpha = 0.2 + pulseValue * 0.15;
      final glowPaint = Paint()
        ..color = KinrelColors.orange.withValues(
          alpha: glowAlpha * depthOpacity,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, effectiveRadius + 12, glowPaint);
    }

    // ── Anchor glow ────────────────────────────────────────────────
    if (isAnchor && !isSelected) {
      final anchorGlow = Paint()
        ..color = KinrelColors.orangeGlowIntense.withValues(alpha: depthOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(center, effectiveRadius + 8, anchorGlow);
    }

    // ── Depth shadow ───────────────────────────────────────────────
    final shadowOffset = Offset(0, 2 + depth.abs() * 0.005);
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3 * depthOpacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center + shadowOffset, effectiveRadius + 2, shadowPaint);

    // ── Generation ring ────────────────────────────────────────────
    final ringPaint = Paint()
      ..color = ringColor.withValues(alpha: depthOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * zoom;
    canvas.drawCircle(center, effectiveRadius + 2 * zoom, ringPaint);

    // ── Node body (gradient circle) ────────────────────────────────
    final gradient = isDeceased
        ? const LinearGradient(colors: [Color(0xFF4A4A5E), Color(0xFF2A2A3E)])
        : const LinearGradient(
            colors: [KinrelColors.orange, KinrelColors.amber],
          );

    final bodyRect = Rect.fromCircle(center: center, radius: effectiveRadius);
    canvas.drawCircle(
      center,
      effectiveRadius,
      Paint()..shader = gradient.createShader(bodyRect),
    );

    // ── Deceased overlay ───────────────────────────────────────────
    if (isDeceased) {
      canvas.drawCircle(
        center,
        effectiveRadius,
        Paint()..color = Colors.white.withValues(alpha: 0.08),
      );
    }

    // ── Depth dimming overlay ──────────────────────────────────────
    if (depthOpacity < 0.95) {
      canvas.drawCircle(
        center,
        effectiveRadius,
        Paint()
          ..color = KinrelColors.darkBackground.withValues(
            alpha: (1.0 - depthOpacity) * 0.6,
          ),
      );
    }

    // ── Content: Initial or dove ───────────────────────────────────
    if (isDeceased) {
      final dovePainter = TextPainter(
        text: TextSpan(
          text: '\u2702',
          style: TextStyle(fontSize: effectiveRadius * 0.7),
        ),
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
            fontSize: effectiveRadius * 0.75,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: depthOpacity),
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

    // ── Name label below node (zoom-based scaling and fading) ──────
    final labelAlpha =
        depthOpacity * (zoom < 0.5 ? (zoom - 0.3) / 0.2 : 1.0).clamp(0.0, 1.0);

    if (labelAlpha > 0.05) {
      final namePainter = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: (11 * zoom).clamp(6, 16),
            fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w500,
            color:
                (isHighlighted ? KinrelColors.amber : const Color(0xFFF5F0EE))
                    .withValues(alpha: labelAlpha),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      namePainter.layout(maxWidth: 80 * zoom);
      namePainter.paint(
        canvas,
        Offset(
          center.dx - namePainter.width / 2,
          center.dy + effectiveRadius + 6,
        ),
      );
    }

    // ── Kinship label above when selected ──────────────────────────
    if (isSelected && relationship != null && relationship.isNotEmpty) {
      final kinshipPainter = TextPainter(
        text: TextSpan(
          text: relationship.replaceAll('_', ' '),
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: (10 * zoom).clamp(6, 14),
            fontWeight: FontWeight.w400,
            color: KinrelColors.orange,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      kinshipPainter.layout(maxWidth: 100 * zoom);
      kinshipPainter.paint(
        canvas,
        Offset(
          center.dx - kinshipPainter.width / 2,
          center.dy - effectiveRadius - 18,
        ),
      );
    }

    // ── Generation badge (small label at top-right when zoomed in) ─
    if (zoom > 0.8 && labelAlpha > 0.3) {
      final genText = 'G$generation';
      final genPainter = TextPainter(
        text: TextSpan(
          text: genText,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: (8 * zoom).clamp(5, 10),
            fontWeight: FontWeight.w500,
            color: ringColor.withValues(alpha: labelAlpha * 0.7),
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      genPainter.layout();
      genPainter.paint(
        canvas,
        Offset(
          center.dx + effectiveRadius * 0.5,
          center.dy - effectiveRadius - 4,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Tree3DCanvasPainter oldDelegate) {
    return oldDelegate.rotationX != rotationX ||
        oldDelegate.rotationY != rotationY ||
        oldDelegate.zoom != zoom ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.ambientValue != ambientValue ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.floatValue != floatValue ||
        oldDelegate.selectedPersonId != selectedPersonId ||
        oldDelegate.layoutMode != layoutMode ||
        oldDelegate.nodePositions != nodePositions ||
        oldDelegate.highlightedNodeIds != highlightedNodeIds ||
        oldDelegate.searchQuery != searchQuery;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SEARCH BAR 3D
// ═══════════════════════════════════════════════════════════════════════

class _SearchBar3D extends StatelessWidget {
  const _SearchBar3D({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.matchCount,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final int matchCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(KinrelRadius.full),
        border: Border.all(
          color: query.isNotEmpty
              ? KinrelColors.amber.withValues(alpha: 0.5)
              : KinrelColors.orange.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(
            Icons.search_rounded,
            color: query.isNotEmpty ? KinrelColors.amber : KinrelColors.textDim,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: KinrelTypography.bodySmall.copyWith(
                color: KinrelColors.textWhite,
              ),
              decoration: InputDecoration(
                hintText: 'Search family members...',
                hintStyle: KinrelTypography.bodySmall.copyWith(
                  color: KinrelColors.textDim,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          if (query.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: KinrelColors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(KinrelRadius.full),
              ),
              child: Text(
                '$matchCount',
                style: KinrelTypography.labelSmall.copyWith(
                  color: KinrelColors.amber,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClear,
              child: Icon(
                Icons.close_rounded,
                color: KinrelColors.textSilver,
                size: 16,
              ),
            ),
          ],
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MINIMAP 3D
// ═══════════════════════════════════════════════════════════════════════

class _Minimap3D extends StatelessWidget {
  const _Minimap3D({
    required this.nodePositions,
    required this.nodeGenerations,
    required this.anchorPersonId,
    required this.screenSize,
    required this.zoom,
    required this.panOffset,
    required this.rotationX,
    required this.rotationY,
    required this.transformPoint,
    required this.onTap,
  });

  final Map<String, Offset> nodePositions;
  final Map<String, int> nodeGenerations;
  final String? anchorPersonId;
  final Size screenSize;
  final double zoom;
  final Offset panOffset;
  final double rotationX;
  final double rotationY;
  final Offset Function(Offset, Size) transformPoint;
  final void Function(Offset, Size) onTap;

  static const double _minimapSize = 120.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (details) {
        onTap(details.localPosition, const Size(_minimapSize, _minimapSize));
      },
      child: Container(
        width: _minimapSize,
        height: _minimapSize,
        decoration: BoxDecoration(
          color: KinrelColors.darkCard.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          child: CustomPaint(
            size: const Size(_minimapSize, _minimapSize),
            painter: _MinimapPainter(
              nodePositions: nodePositions,
              nodeGenerations: nodeGenerations,
              anchorPersonId: anchorPersonId,
              screenSize: screenSize,
              zoom: zoom,
              panOffset: panOffset,
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.nodePositions,
    required this.nodeGenerations,
    required this.anchorPersonId,
    required this.screenSize,
    required this.zoom,
    required this.panOffset,
  });

  final Map<String, Offset> nodePositions;
  final Map<String, int> nodeGenerations;
  final String? anchorPersonId;
  final Size screenSize;
  final double zoom;
  final Offset panOffset;

  static const double _canvasSize = 2000.0;

  Color _genColor(int gen) {
    if (gen >= 3) return const Color(0xFFC44A18);
    if (gen == 2) return const Color(0xFFE8612A);
    if (gen == 1) return const Color(0xFFF59240);
    return const Color(0xFFFFB870);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0D0E12),
    );

    if (nodePositions.isEmpty) return;

    // Scale graph coords to minimap coords
    Offset toMini(Offset graphPos) {
      return Offset(
        (graphPos.dx / _canvasSize) * size.width,
        (graphPos.dy / _canvasSize) * size.height,
      );
    }

    // Draw nodes as dots
    for (final entry in nodePositions.entries) {
      final id = entry.key;
      final pos = toMini(entry.value);
      final gen = nodeGenerations[id] ?? 1;
      final isAnchor = id == anchorPersonId;
      final color = _genColor(gen);

      final dotRadius = isAnchor ? 3.0 : 2.0;
      canvas.drawCircle(
        pos,
        dotRadius,
        Paint()..color = color.withValues(alpha: 0.8),
      );

      // Anchor ring
      if (isAnchor) {
        canvas.drawCircle(
          pos,
          5.0,
          Paint()
            ..color = KinrelColors.orange.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    // Draw viewport indicator
    // The viewport shows what's visible on screen. We need to compute
    // the graph-space bounds that map to the current screen view.
    // Simplified: show a rectangle representing the current view.
    final viewWidth = screenSize.width / zoom;
    final viewHeight = screenSize.height / zoom;
    final viewCenter = Offset(_canvasSize / 2, _canvasSize / 2);

    final viewRect = Rect.fromCenter(
      center: viewCenter,
      width: viewWidth,
      height: viewHeight,
    );

    final miniRect = Rect.fromLTRB(
      (viewRect.left / _canvasSize) * size.width,
      (viewRect.top / _canvasSize) * size.height,
      (viewRect.right / _canvasSize) * size.width,
      (viewRect.bottom / _canvasSize) * size.height,
    );

    // Clamp to minimap bounds
    final clampedRect = miniRect.intersect(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );

    canvas.drawRect(
      clampedRect,
      Paint()
        ..color = KinrelColors.orange.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Semi-transparent fill for viewport area
    canvas.drawRect(
      clampedRect,
      Paint()..color = KinrelColors.orange.withValues(alpha: 0.05),
    );

    // Label
    final labelPainter = TextPainter(
      text: TextSpan(
        text: 'MAP',
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 7,
          color: KinrelColors.textDim.withValues(alpha: 0.5),
          fontWeight: FontWeight.w500,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    labelPainter.layout();
    labelPainter.paint(canvas, const Offset(4, 2));
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) {
    return oldDelegate.nodePositions != nodePositions ||
        oldDelegate.zoom != zoom ||
        oldDelegate.panOffset != panOffset;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FLOATING CONTROL PANEL
// ═══════════════════════════════════════════════════════════════════════

class _FloatingControlPanel extends StatelessWidget {
  const _FloatingControlPanel({
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
    required this.layoutMode,
    required this.onRotationXChanged,
    required this.onRotationYChanged,
    required this.onZoomChanged,
    required this.onLayoutModeChanged,
    required this.onReset,
  });

  final double rotationX;
  final double rotationY;
  final double zoom;
  final Tree3DLayoutMode layoutMode;
  final ValueChanged<double> onRotationXChanged;
  final ValueChanged<double> onRotationYChanged;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<Tree3DLayoutMode> onLayoutModeChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
          width: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(
              color: KinrelColors.orange.withValues(alpha: 0.15),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.view_in_ar_rounded,
                    color: KinrelColors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '3D CONTROLS',
                    style: KinrelTypography.overline.copyWith(
                      color: KinrelColors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // X Rotation slider
              _SliderRow(
                label: 'Pitch',
                icon: Icons.swap_vert_rounded,
                value: rotationX,
                min: -0.5,
                max: 0.5,
                color: KinrelColors.amber,
                onChanged: onRotationXChanged,
              ),
              const SizedBox(height: 8),

              // Y Rotation slider
              _SliderRow(
                label: 'Yaw',
                icon: Icons.swap_horiz_rounded,
                value: rotationY,
                min: -1.0,
                max: 1.0,
                color: KinrelColors.orange,
                onChanged: onRotationYChanged,
              ),
              const SizedBox(height: 8),

              // Zoom slider
              _SliderRow(
                label: 'Zoom',
                icon: Icons.zoom_in_rounded,
                value: zoom,
                min: 0.3,
                max: 3.0,
                color: KinrelColors.gold,
                onChanged: onZoomChanged,
              ),
              const SizedBox(height: 12),

              // Layout mode toggle
              Text(
                'LAYOUT',
                style: KinrelTypography.overline.copyWith(
                  color: KinrelColors.textDim,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _LayoutChip(
                    label: 'Constellation',
                    isSelected: layoutMode == Tree3DLayoutMode.constellation,
                    onTap: () =>
                        onLayoutModeChanged(Tree3DLayoutMode.constellation),
                  ),
                  const SizedBox(width: 4),
                  _LayoutChip(
                    label: 'Galaxy',
                    isSelected: layoutMode == Tree3DLayoutMode.galaxy,
                    onTap: () => onLayoutModeChanged(Tree3DLayoutMode.galaxy),
                  ),
                  const SizedBox(width: 4),
                  _LayoutChip(
                    label: 'Solar',
                    isSelected: layoutMode == Tree3DLayoutMode.solar,
                    onTap: () => onLayoutModeChanged(Tree3DLayoutMode.solar),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Reset button
              SizedBox(
                width: double.infinity,
                child: DKButton(
                  label: 'Reset View',
                  variant: DKButtonVariant.secondary,
                  size: DKButtonSize.sm,
                  icon: Icons.refresh_rounded,
                  onPressed: onReset,
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideX(begin: 0.1, end: 0, duration: 300.ms);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SLIDER ROW
// ═══════════════════════════════════════════════════════════════════════

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: KinrelTypography.labelSmall.copyWith(
              color: KinrelColors.textSilver,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: color.withValues(alpha: 0.2),
              thumbColor: color,
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LAYOUT CHIP
// ═══════════════════════════════════════════════════════════════════════

class _LayoutChip extends StatelessWidget {
  const _LayoutChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: KinrelMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? KinrelColors.orange.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          border: Border.all(
            color: isSelected
                ? KinrelColors.orange
                : KinrelColors.orange.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: KinrelTypography.labelSmall.copyWith(
            color: isSelected ? KinrelColors.orange : KinrelColors.textDim,
            fontSize: 9,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CONTROL TOGGLE BUTTON
// ═══════════════════════════════════════════════════════════════════════

class _ControlToggleButton extends StatelessWidget {
  const _ControlToggleButton({required this.isOpen, required this.onTap});

  final bool isOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: KinrelColors.darkCard.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          isOpen ? Icons.settings_rounded : Icons.tune_rounded,
          color: KinrelColors.orange,
          size: 18,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// BACK BUTTON
// ═══════════════════════════════════════════════════════════════════════

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: KinrelColors.darkCard.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.arrow_back_rounded,
          color: KinrelColors.textWhite,
          size: 20,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TITLE BAR
// ═══════════════════════════════════════════════════════════════════════

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.familyName});

  final String familyName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(KinrelRadius.full),
        border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            color: KinrelColors.orange,
            size: 16,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              familyName,
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textWhite,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NODE DETAIL POPUP (ENHANCED)
// ═══════════════════════════════════════════════════════════════════════

class _NodeDetailPopup extends ConsumerStatefulWidget {
  const _NodeDetailPopup({
    required this.person,
    required this.relationshipKey,
    required this.familyId,
    required this.primaryLanguage,
    required this.onDismiss,
    required this.onNodeTap,
    required this.members,
    required this.relationships,
    required this.nodeGenerations,
    required this.nodes,
    required this.edges,
  });

  final Person person;
  final String? relationshipKey;
  final String familyId;
  final String? primaryLanguage;
  final VoidCallback onDismiss;
  final ValueChanged<Person> onNodeTap;
  final List<Person> members;
  final List<FamilyRelationship> relationships;
  final Map<String, int> nodeGenerations;
  final Map<String, VisTreeNode> nodes;
  final List<VisEdge> edges;

  @override
  ConsumerState<_NodeDetailPopup> createState() => _NodeDetailPopupState();
}

class _NodeDetailPopupState extends ConsumerState<_NodeDetailPopup> {
  /// Count spouse connections
  int get _spouseCount {
    int count = 0;
    for (final rel in widget.relationships) {
      if ((rel.fromPersonId == widget.person.id ||
              rel.toPersonId == widget.person.id) &&
          rel.relationshipKey.toLowerCase().contains('spouse')) {
        count++;
      }
    }
    return count;
  }

  /// Count children
  int get _childrenCount {
    int count = 0;
    for (final edge in widget.edges) {
      if (edge.fromId == widget.person.id &&
          edge.type == EdgeType.parentChild) {
        count++;
      }
    }
    return count;
  }

  /// Count sibling connections
  int get _siblingCount {
    int count = 0;
    for (final edge in widget.edges) {
      if ((edge.fromId == widget.person.id || edge.toId == widget.person.id) &&
          edge.type == EdgeType.sibling) {
        count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.primaryLanguage ?? 'en';

    // Try to get kinship term
    final kinshipTermAsync = widget.relationshipKey != null
        ? ref.watch(
            kinshipTermProvider((
              key: widget.relationshipKey!,
              language: language,
            )),
          )
        : null;

    final kinshipNative = kinshipTermAsync?.valueOrNull?.native ?? '';
    final kinshipLatin = kinshipTermAsync?.valueOrNull?.latin ?? '';

    final generation = widget.nodeGenerations[widget.person.id] ?? 0;

    return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              if (details.delta.dy > 20) {
                widget.onDismiss();
              }
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    KinrelColors.darkCard.withValues(alpha: 0.95),
                    KinrelColors.darkElevated,
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(KinrelRadius.xxl),
                ),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.orangeGlow,
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: KinrelColors.textDim.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row
                        Row(
                          children: [
                            DKAvatar(
                              initials: widget.person.name.isNotEmpty
                                  ? widget.person.name[0].toUpperCase()
                                  : '?',
                              size: DKAvatarSize.lg,
                              showGlow: true,
                              borderColor: KinrelColors.orange,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.person.name,
                                    style: KinrelTypography.headlineMedium
                                        .copyWith(
                                          color: KinrelColors.textWhite,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  // Kinship term badge + generation badge
                                  Row(
                                    children: [
                                      if (widget.relationshipKey != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: KinrelColors.orange
                                                .withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                              KinrelRadius.full,
                                            ),
                                            border: Border.all(
                                              color: KinrelColors.orange
                                                  .withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Text(
                                            widget.relationshipKey!.replaceAll(
                                              '_',
                                              ' ',
                                            ),
                                            style: KinrelTypography.labelSmall
                                                .copyWith(
                                                  color: KinrelColors.orange,
                                                ),
                                          ),
                                        ),
                                      const SizedBox(width: 6),
                                      if (generation > 0)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: KinrelColors.amber
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              KinrelRadius.full,
                                            ),
                                            border: Border.all(
                                              color: KinrelColors.amber
                                                  .withValues(alpha: 0.25),
                                            ),
                                          ),
                                          child: Text(
                                            'Gen $generation',
                                            style: KinrelTypography.labelSmall
                                                .copyWith(
                                                  color: KinrelColors.amber,
                                                  fontSize: 10,
                                                ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Close button
                            GestureDetector(
                              onTap: widget.onDismiss,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: KinrelColors.darkElevated,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: KinrelColors.orange.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: KinrelColors.textSilver,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Relationship counts row
                        Row(
                          children: [
                            _RelationshipCountChip(
                              icon: Icons.favorite_rounded,
                              count: _spouseCount,
                              label: 'Spouse',
                              color: const Color(0xFFE8612A),
                            ),
                            const SizedBox(width: 8),
                            _RelationshipCountChip(
                              icon: Icons.child_care_rounded,
                              count: _childrenCount,
                              label: 'Children',
                              color: KinrelColors.amber,
                            ),
                            const SizedBox(width: 8),
                            _RelationshipCountChip(
                              icon: Icons.people_outline_rounded,
                              count: _siblingCount,
                              label: 'Siblings',
                              color: KinrelColors.gold,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Stats row
                        Row(
                          children: [
                            DKStatChip(
                              icon: Icons.people_rounded,
                              value: '${widget.person.generationIndex}',
                              label: 'Generation',
                              color: KinrelColors.amber,
                            ),
                            const SizedBox(width: 8),
                            if (widget.person.gender != null)
                              DKStatChip(
                                icon: widget.person.gender == 'male'
                                    ? Icons.male_rounded
                                    : Icons.female_rounded,
                                value: widget.person.gender!.capitalize(),
                                label: 'Gender',
                                color: KinrelColors.orange,
                              ),
                            if (widget.person.city != null) ...[
                              const SizedBox(width: 8),
                              DKStatChip(
                                icon: Icons.location_on_rounded,
                                value: widget.person.city!,
                                label: 'City',
                                color: KinrelColors.gold,
                              ),
                            ],
                          ],
                        ),

                        // Kinship term in primary language
                        if (kinshipNative.isNotEmpty ||
                            kinshipLatin.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: KinrelGradients.igniteGradient,
                              borderRadius: BorderRadius.circular(
                                KinrelRadius.md,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.translate_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (kinshipNative.isNotEmpty)
                                        Text(
                                          kinshipNative,
                                          style: KinrelTypography.headlineSmall
                                              .copyWith(color: Colors.white),
                                        ),
                                      if (kinshipLatin.isNotEmpty &&
                                          kinshipLatin != kinshipNative)
                                        Text(
                                          kinshipLatin,
                                          style: KinrelTypography.bodySmall
                                              .copyWith(color: Colors.white70),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Action buttons (3 buttons: View Profile, Find Path, Add Relationship)
                        Row(
                          children: [
                            Expanded(
                              child: DKButton(
                                label: 'View Profile',
                                variant: DKButtonVariant.gradient,
                                size: DKButtonSize.md,
                                icon: Icons.person_rounded,
                                onPressed: () {
                                  // TODO: Navigate to profile
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DKButton(
                                label: 'Find Path',
                                variant: DKButtonVariant.secondary,
                                size: DKButtonSize.md,
                                icon: Icons.route_rounded,
                                onPressed: () {
                                  // TODO: Navigate to path finder
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DKButton(
                                label: 'Add Rel',
                                variant: DKButtonVariant.secondary,
                                size: DKButtonSize.md,
                                icon: Icons.add_circle_outline_rounded,
                                onPressed: () {
                                  // TODO: Navigate to add relationship
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(
          begin: 0.3,
          end: 0,
          duration: 300.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RELATIONSHIP COUNT CHIP
// ═══════════════════════════════════════════════════════════════════════

class _RelationshipCountChip extends StatelessWidget {
  const _RelationshipCountChip({
    required this.icon,
    required this.count,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: KinrelTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: KinrelTypography.labelSmall.copyWith(
              color: color.withValues(alpha: 0.7),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════

class _Star {
  _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.baseOpacity,
    required this.twinkleSpeed,
    required this.twinklePhase,
  });

  final double x;
  final double y;
  final double radius;
  final double baseOpacity;
  final double twinkleSpeed;
  final double twinklePhase;
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.opacity,
  });

  double x;
  double y;
  final double vx;
  final double vy;
  final double radius;
  final double opacity;
}

// ═══════════════════════════════════════════════════════════════════════
// STRING EXTENSION
// ═══════════════════════════════════════════════════════════════════════

extension _StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
