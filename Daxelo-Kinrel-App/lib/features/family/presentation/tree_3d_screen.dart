// lib/features/family/presentation/tree_3d_screen.dart
//
// DAXELO KINREL — 3D Interactive Family Tree Screen
//
// Full-screen immersive 3D family tree visualization with perspective
// transforms, rotation controls, depth-based rendering, starfield
// background, generation rings, layout modes, and node detail pop-ups.

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

  // ── Animation controllers ────────────────────────────────────────
  late AnimationController _ambientController;
  late AnimationController _pulseController;
  late AnimationController _floatController;

  // ── Computed layout data ─────────────────────────────────────────
  Map<String, Offset> _nodePositions = {};
  Map<String, int> _nodeGenerations = {};
  Map<String, String> _nodeLineages = {};
  List<VisEdge> _edges = [];
  Map<String, VisTreeNode> _nodes = {};

  // ── Star field (pre-generated) ───────────────────────────────────
  final List<_Star> _stars = [];
  final List<_Particle> _particles = [];

  // ── Canvas size for layout computation ───────────────────────────
  static const double _canvasSize = 2000.0;

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

    _generateStars();
    _generateParticles();
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _pulseController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  // ── Star & particle generation ────────────────────────────────────

  void _generateStars() {
    final rng = math.Random(42);
    _stars.clear();
    for (int i = 0; i < 200; i++) {
      _stars.add(_Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: 0.3 + rng.nextDouble() * 1.2,
        baseOpacity: 0.03 + rng.nextDouble() * 0.08,
        twinkleSpeed: 0.5 + rng.nextDouble() * 2.0,
        twinklePhase: rng.nextDouble() * math.pi * 2,
      ));
    }
  }

  void _generateParticles() {
    final rng = math.Random(77);
    _particles.clear();
    for (int i = 0; i < 30; i++) {
      _particles.add(_Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        vx: (rng.nextDouble() - 0.5) * 0.0003,
        vy: (rng.nextDouble() - 0.5) * 0.0003,
        radius: 1.0 + rng.nextDouble() * 2.0,
        opacity: 0.05 + rng.nextDouble() * 0.15,
      ));
    }
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
        _nodes[spouseId] = VisTreeNode(person: node.spouse!, lineage: 'marital');
        _nodeLineages[spouseId] = 'marital';
        _nodeGenerations[spouseId] = depth;
        final spouseMember = memberMap[spouseId];
        if (spouseMember != null && spouseMember.generationIndex > 0) {
          _nodeGenerations[spouseId] = spouseMember.generationIndex;
        }
        _edges.add(VisEdge(fromId: id, toId: spouseId, type: EdgeType.spouse, label: 'spouse'));
      }

      for (final child in node.children) {
        _edges.add(VisEdge(fromId: id, toId: child.person.id, type: EdgeType.parentChild, label: 'parent-child'));
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
        _edges.add(VisEdge(fromId: rel.fromId, toId: rel.toId, type: edgeType, label: rel.type));
        existingEdgeSet.add(key1);
        existingEdgeSet.add('${rel.toId}-${rel.fromId}');
      }
    }

    // Compute positions based on layout mode
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
      _nodePositions.putIfAbsent(id, () => const Offset(_canvasSize / 2, _canvasSize / 2));
    }
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
        if (!positions.containsKey(edge.fromId) || !positions.containsKey(edge.toId)) continue;
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
    final allIds = _nodes.keys.toList();

    // Sort by generation for spiral arm assignment
    final byGen = <int, List<String>>{};
    for (final entry in _nodeGenerations.entries) {
      byGen.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    // Spiral galaxy: multiple arms
    final armCount = 2;
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
          center.dx + spiralRadius * math.cos(spiralAngle) + spread * math.cos(spiralAngle + math.pi / 2),
          center.dy + spiralRadius * math.sin(spiralAngle) + spread * math.sin(spiralAngle + math.pi / 2),
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
      if (entry.key == _nodeGenerations[anchorId]) continue;
      byGen.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    final sortedGens = byGen.keys.toList()..sort();

    for (final gen in sortedGens) {
      final ids = byGen[gen]!;
      final genDiff = (gen - (anchorId != null ? (_nodeGenerations[anchorId] ?? 1) : 1)).abs();
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

  // ── 3D perspective is handled in the painter via manual rotation ──
  // Matrix4 is used for reference: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateX(rotationX)..rotateY(rotationY)

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

          return Stack(
            children: [
              // ── 3D Canvas ────────────────────────────────────────
              GestureDetector(
                onDoubleTap: _resetView,
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
                    ]),
                    builder: (context, _) {
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
                        ),
                      );
                    },
                  ),
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
                    onLayoutModeChanged: (m) => setState(() {
                      _layoutMode = m;
                      _nodePositions.clear();
                    }),
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
          )
              .animate(onPlay: (c) => c.repeat())
              .fadeIn(duration: 600.ms),
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
              Icon(Icons.error_outline_rounded, color: KinrelColors.error, size: 40),
              const SizedBox(height: 16),
              Text(
                'Could not load family tree',
                style: KinrelTypography.headlineSmall.copyWith(color: KinrelColors.textWhite),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: KinrelTypography.bodySmall.copyWith(color: KinrelColors.textSilver),
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

  /// Transform a graph-space offset to screen-space using 3D perspective
  Offset _transformPoint(Offset graphPos, Size screenSize) {
    // Center of the canvas in graph space
    final cx = _canvasSize / 2;
    final cy = _canvasSize / 2;

    // Translate to origin
    double x = graphPos.dx - cx;
    double y = graphPos.dy - cy;

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
    final screenX = x2 * perspective * zoom + screenSize.width / 2 + panOffset.dx;
    final screenY = y2 * perspective * zoom + screenSize.height / 2 + panOffset.dy;

    return Offset(screenX, screenY);
  }

  /// Get depth (z-value) for a graph point after rotation
  double _getDepth(Offset graphPos) {
    final cx = _canvasSize / 2;
    final cy = _canvasSize / 2;
    double x = graphPos.dx - cx;
    double y = graphPos.dy - cy;

    final cosY = math.cos(rotationY);
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
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.6,
        colors: [
          KinrelColors.orange.withValues(alpha: 0.08),
          KinrelColors.amber.withValues(alpha: 0.03),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: glowCenter, radius: size.width * 0.6));
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
      final edgeOpacity = (1.0 - avgDepth.abs() * 0.0003).clamp(0.2, isConnectedToSelected ? 0.9 : 0.4);

      final paint = Paint()
        ..color = color.withValues(alpha: edgeOpacity)
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      _drawEdgePath(canvas, from, to, edge.type, paint);

      // Heart at midpoint for spouse
      if (edge.type == EdgeType.spouse) {
        final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
        final heartPainter = TextPainter(
          text: const TextSpan(text: '\u2764', style: TextStyle(fontSize: 10, color: Color(0xFFE8612A))),
          textDirection: TextDirection.ltr,
        );
        heartPainter.layout();
        heartPainter.paint(canvas, Offset(mid.dx - heartPainter.width / 2, mid.dy - heartPainter.height / 2));
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
      final twinkle = math.sin(ambientValue * 2 * math.pi * star.twinkleSpeed + star.twinklePhase);
      final opacity = star.baseOpacity + twinkle * 0.03;
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.radius,
        Paint()..color = const Color(0xFFF5F0EE).withValues(alpha: opacity.clamp(0.0, 1.0)),
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
        Paint()..color = KinrelColors.orange.withValues(alpha: (p.opacity + pulse).clamp(0.0, 1.0)),
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
      labelPainter.paint(canvas, Offset(labelPos.dx - labelPainter.width / 2, labelPos.dy - labelPainter.height / 2));
    }
  }

  // ── Edge path drawing ───────────────────────────────────────────────

  void _drawEdgePath(Canvas canvas, Offset start, Offset end, EdgeType type, Paint paint) {
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

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint, double dashLen, double gapLen) {
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

  void _drawDottedLine(Canvas canvas, Offset start, Offset end, Paint paint, double dotRadius, double spacing) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance == 0) return;
    final steps = (distance / spacing).floor();
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      canvas.drawCircle(Offset(start.dx + dx * t, start.dy + dy * t), dotRadius, paint);
    }
  }

  // ── Node drawing with 3D effects ────────────────────────────────────

  void _drawNode(Canvas canvas, String id, Offset center, double depth, Size screenSize) {
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
    final depthOpacity = (1.0 - depth.abs() * 0.0003).clamp(0.4, 1.0);
    final ringColor = _generationRingColor(generation);

    // ── Selection glow (pulsing orange) ────────────────────────────
    if (isSelected) {
      final glowAlpha = 0.2 + pulseValue * 0.15;
      final glowPaint = Paint()
        ..color = KinrelColors.orange.withValues(alpha: glowAlpha * depthOpacity)
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
        : const LinearGradient(colors: [KinrelColors.orange, KinrelColors.amber]);

    final bodyRect = Rect.fromCircle(center: center, radius: effectiveRadius);
    canvas.drawCircle(center, effectiveRadius, Paint()..shader = gradient.createShader(bodyRect));

    // ── Deceased overlay ───────────────────────────────────────────
    if (isDeceased) {
      canvas.drawCircle(center, effectiveRadius, Paint()..color = Colors.white.withValues(alpha: 0.08));
    }

    // ── Depth dimming overlay ──────────────────────────────────────
    if (depthOpacity < 0.95) {
      canvas.drawCircle(
        center,
        effectiveRadius,
        Paint()..color = KinrelColors.darkBackground.withValues(alpha: (1.0 - depthOpacity) * 0.6),
      );
    }

    // ── Content: Initial or dove ───────────────────────────────────
    if (isDeceased) {
      final dovePainter = TextPainter(
        text: const TextSpan(text: '\u2702', style: TextStyle(fontSize: effectiveRadius * 0.7)),
        textDirection: TextDirection.ltr,
      );
      dovePainter.layout();
      dovePainter.paint(canvas, Offset(center.dx - dovePainter.width / 2, center.dy - dovePainter.height / 2));
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
      initialPainter.paint(canvas, Offset(center.dx - initialPainter.width / 2, center.dy - initialPainter.height / 2));
    }

    // ── Name label below node ──────────────────────────────────────
    final labelAlpha = depthOpacity;
    final namePainter = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: (11 * zoom).clamp(6, 16),
          fontWeight: FontWeight.w500,
          color: const Color(0xFFF5F0EE).withValues(alpha: labelAlpha),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    );
    namePainter.layout(maxWidth: 80 * zoom);
    namePainter.paint(canvas, Offset(center.dx - namePainter.width / 2, center.dy + effectiveRadius + 6));

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
      kinshipPainter.paint(canvas, Offset(center.dx - kinshipPainter.width / 2, center.dy - effectiveRadius - 18));
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
        oldDelegate.nodePositions != nodePositions;
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
        border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.15)),
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
              Icon(Icons.view_in_ar_rounded, color: KinrelColors.orange, size: 16),
              const SizedBox(width: 6),
              Text(
                '3D CONTROLS',
                style: KinrelTypography.overline.copyWith(color: KinrelColors.orange),
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
            style: KinrelTypography.overline.copyWith(color: KinrelColors.textDim),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _LayoutChip(
                label: 'Constellation',
                isSelected: layoutMode == Tree3DLayoutMode.constellation,
                onTap: () => onLayoutModeChanged(Tree3DLayoutMode.constellation),
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
            style: KinrelTypography.labelSmall.copyWith(color: KinrelColors.textSilver),
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
          color: isSelected ? KinrelColors.orange.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(KinrelRadius.full),
          border: Border.all(
            color: isSelected ? KinrelColors.orange : KinrelColors.orange.withValues(alpha: 0.3),
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
        child: Icon(Icons.arrow_back_rounded, color: KinrelColors.textWhite, size: 20),
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
          Icon(Icons.auto_awesome_rounded, color: KinrelColors.orange, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              familyName,
              style: KinrelTypography.labelMedium.copyWith(color: KinrelColors.textWhite),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// NODE DETAIL POPUP
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
  });

  final Person person;
  final String? relationshipKey;
  final String familyId;
  final String? primaryLanguage;
  final VoidCallback onDismiss;
  final ValueChanged<Person> onNodeTap;
  final List<Person> members;
  final List<FamilyRelationship> relationships;

  @override
  ConsumerState<_NodeDetailPopup> createState() => _NodeDetailPopupState();
}

class _NodeDetailPopupState extends ConsumerState<_NodeDetailPopup> {
  @override
  Widget build(BuildContext context) {
    final language = widget.primaryLanguage ?? 'en';

    // Try to get kinship term
    final kinshipTermAsync = widget.relationshipKey != null
        ? ref.watch(kinshipTermProvider((key: widget.relationshipKey!, language: language)))
        : null;

    final kinshipNative = kinshipTermAsync?.valueOrNull?.native ?? '';
    final kinshipLatin = kinshipTermAsync?.valueOrNull?.latin ?? '';

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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(KinrelRadius.xxl)),
            border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.2)),
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
                          initials: widget.person.name.isNotEmpty ? widget.person.name[0].toUpperCase() : '?',
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
                                style: KinrelTypography.headlineMedium.copyWith(color: KinrelColors.textWhite),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              if (widget.relationshipKey != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: KinrelColors.orange.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(KinrelRadius.full),
                                    border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    widget.relationshipKey!.replaceAll('_', ' '),
                                    style: KinrelTypography.labelSmall.copyWith(color: KinrelColors.orange),
                                  ),
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
                              border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.2)),
                            ),
                            child: Icon(Icons.close_rounded, color: KinrelColors.textSilver, size: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

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
                            icon: widget.person.gender == 'male' ? Icons.male_rounded : Icons.female_rounded,
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
                    if (kinshipNative.isNotEmpty || kinshipLatin.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: KinrelGradients.igniteGradient,
                          borderRadius: BorderRadius.circular(KinrelRadius.md),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.translate_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (kinshipNative.isNotEmpty)
                                    Text(
                                      kinshipNative,
                                      style: KinrelTypography.headlineSmall.copyWith(color: Colors.white),
                                    ),
                                  if (kinshipLatin.isNotEmpty && kinshipLatin != kinshipNative)
                                    Text(
                                      kinshipLatin,
                                      style: KinrelTypography.bodySmall.copyWith(color: Colors.white70),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Action buttons
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
                        const SizedBox(width: 12),
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
        .slideY(begin: 0.3, end: 0, duration: 300.ms, curve: Curves.easeOutCubic);
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
