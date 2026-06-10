// lib/features/family/presentation/relationship_graph_screen.dart
//
// DAXELO KINREL — Relationship Graph Screen
//
// A STUNNING hierarchical family relationship graph with:
// - Vertical layout: Great-Grandparents → Grandparents → Parents → You → Children
// - Circular nodes with initials, names, and relationship labels
// - Color-coded by generation (lavender → purple → blue → teal → pink)
// - Glowing "You" anchor node with pulsing animation
// - Dashed curved Bezier connection lines (parent-child, spouse & sibling)
// - Smooth entry animations (generation by generation)
// - InteractiveViewer for zoom/pan
// - Generation labels on the left side
// - Bottom control pill (zoom, center, fit)
// - Tap nodes for person detail sheet

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/graph/graph_provider.dart';
import '../../../shared/widgets/dk_components.dart';
import 'add_person_sheet.dart';
import 'person_detail_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════
// GENERATION COLORS (Figma reference)
// ═══════════════════════════════════════════════════════════════════════

class _GenColors {
  _GenColors._();

  // ── Relationship-based colors (matches Figma design spec) ──────────

  /// Great-grandparents+ (generation 0 and below)
  static const Color greatGrandparent = Color(0xFF9B8EC4); // lavender-purple

  /// Grandparents (generation 1)
  static const Color grandparent = Color(0xFF6B9FD4); // blue

  /// Parents / Uncles / Aunts (generation 2)
  static const Color parent = Color(0xFF5B9BD5); // steel blue (matches Figma "SR/SU" nodes)

  /// Self / Spouse (generation 3 — anchor)
  static const Color self = Color(0xFF4ECDC4); // bright teal (matches Figma "RA" node)

  /// Children (generation 4)
  static const Color child = Color(0xFFB87FA8); // mauve/dusty pink (matches Figma "AN" node)

  /// Grandchildren (generation 5+)
  static const Color grandchild = Color(0xFFFFB6C1); // light pink

  /// Siblings (same generation, not spouse)
  static const Color sibling = Color(0xFF7B8FA6); // slate blue-gray (matches Figma "MA/YA" nodes)

  /// Spouse (same generation, married to anchor)
  static const Color spouse = Color(0xFF4ECDC4); // same as self

  static Color forGeneration(int gen) {
    switch (gen) {
      case 0:
        return greatGrandparent;
      case 1:
        return grandparent;
      case 2:
        return parent;
      case 3:
        return self;
      case 4:
        return child;
      default:
        return grandchild;
    }
  }

  /// Returns color based on relationship to the anchor person.
  /// This matches the visual design spec from Figma:
  ///   - Parents: blue-teal
  ///   - Self: bright teal (with glow)
  ///   - Siblings: dark gray
  ///   - Children/Spouse: mauve/pink
  static Color forRelationship({
    required int generation,
    required String? relationshipLabel,
    required bool isAnchor,
    required int anchorGeneration,
  }) {
    if (isAnchor) return self;

    final genDiff = generation - anchorGeneration;
    final label = relationshipLabel?.toLowerCase() ?? '';

    // Spouse → same color as self (teal)
    if (label.contains('spouse') || label.contains('husband') || label.contains('wife')) {
      return spouse;
    }

    // Sibling → dark gray
    if (label.contains('brother') || label.contains('sister') || label.contains('sibling')) {
      return sibling;
    }

    // Parents (gen above) → blue-teal
    if (genDiff < 0) return parent;

    // Children (gen below) → mauve/pink
    if (genDiff > 0) return child;

    // Same generation but no specific label → gray (sibling default)
    return sibling;
  }

  static String labelForGeneration(int gen) {
    switch (gen) {
      case 0:
        return 'Great-Grandparents';
      case 1:
        return 'Grandparents';
      case 2:
        return 'Parents';
      case 3:
        return 'You';
      case 4:
        return 'Children';
      case 5:
        return 'Grandchildren';
      default:
        return 'Gen ${gen + 1}';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LAYOUT DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// A node in the relationship graph with computed position
class _GraphNode {
  const _GraphNode({
    required this.person,
    required this.generation,
    required this.isAnchor,
    this.relationshipLabel,
    this.spouseId,
  });

  final Person person;
  final int generation;
  final bool isAnchor;
  final String? relationshipLabel;
  final String? spouseId;

  /// 2-char initials from name
  String get initials {
    final parts = person.name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return person.name.isNotEmpty
        ? person.name.substring(0, math.min(2, person.name.length)).toUpperCase()
        : '??';
  }
}

/// An edge between two graph nodes
class _GraphEdge {
  const _GraphEdge({
    required this.fromId,
    required this.toId,
    required this.type,
  });

  final String fromId;
  final String toId;
  final _EdgeType type;
}

enum _EdgeType { parentChild, spouse, sibling }

// ═══════════════════════════════════════════════════════════════════════
// LAYOUT COMPUTATION
// ═══════════════════════════════════════════════════════════════════════

class _LayoutResult {
  const _LayoutResult({
    required this.nodes,
    required this.edges,
    required this.positions,
    required this.anchorId,
    required this.generations,
    required this.canvasSize,
  });

  final Map<String, _GraphNode> nodes;
  final List<_GraphEdge> edges;
  final Map<String, Offset> positions;
  final String? anchorId;
  final Set<int> generations;
  final Size canvasSize;
}

/// Build the hierarchical layout from family data
_LayoutResult _computeLayout({
  required List<Person> members,
  required List<FamilyRelationship> relationships,
  String? anchorPersonId,
}) {
  final activeMembers = members.where((p) => p.deletedAt == null).toList();
  if (activeMembers.isEmpty) {
    return _LayoutResult(
      nodes: {},
      edges: [],
      positions: {},
      anchorId: null,
      generations: {},
      canvasSize: Size.zero,
    );
  }

  // Find anchor person
  final anchor = activeMembers.firstWhere(
    (p) => p.isAnchor || p.id == anchorPersonId,
    orElse: () => activeMembers.first,
  );

  // Build adjacency from relationships
  final parentOf = <String, List<String>>{}; // personId → list of parent IDs
  final childOf = <String, List<String>>{}; // personId → list of child IDs
  final spouseOf = <String, String?>{}; // personId → spouse ID
  final siblingOf = <String, List<String>>{}; // personId → list of sibling IDs
  final relLabelOf = <String, String>{}; // personId → relationship label to anchor

  for (final rel in relationships) {
    if (!rel.isActive) continue;
    final type = rel.relationshipKey.toLowerCase();
    final fromId = rel.fromPersonId;
    final toId = rel.toPersonId;

    // Skip if either person is deleted
    if (!activeMembers.any((m) => m.id == fromId || m.id == toId)) continue;

    if (['father', 'mother', 'parent'].contains(type)) {
      // fromId is the parent of toId
      parentOf.putIfAbsent(toId, () => []).add(fromId);
      childOf.putIfAbsent(fromId, () => []).add(toId);
    } else if (['child', 'son', 'daughter'].contains(type)) {
      // fromId is the child of toId
      parentOf.putIfAbsent(fromId, () => []).add(toId);
      childOf.putIfAbsent(toId, () => []).add(fromId);
    } else if (['spouse', 'husband', 'wife'].contains(type)) {
      spouseOf[fromId] = toId;
      spouseOf[toId] = fromId;
    } else if (['brother', 'sister', 'sibling'].contains(type)) {
      // Sibling relationships — bidirectional
      siblingOf.putIfAbsent(fromId, () => []).add(toId);
      siblingOf.putIfAbsent(toId, () => []).add(fromId);
    }

    // Track relationship labels
    if (toId == anchor.id && fromId != anchor.id) {
      relLabelOf[fromId] = _formatRelLabel(type);
    } else if (fromId == anchor.id && toId != anchor.id) {
      relLabelOf[toId] = _formatRelLabel(type);
    }
  }

  // Assign generations via BFS from anchor
  final generationMap = <String, int>{};
  final visited = <String>{};
  final queue = <_QueueItem>[];

  // Anchor is generation 3 (center)
  generationMap[anchor.id] = 3;
  visited.add(anchor.id);
  queue.add(_QueueItem(anchor.id, 3));

  // BFS to assign generations
  while (queue.isNotEmpty) {
    final item = queue.removeAt(0);
    final currentGen = item.generation;

    // Parents are one generation above
    for (final parentId in parentOf[item.id] ?? []) {
      if (!visited.contains(parentId)) {
        visited.add(parentId);
        generationMap[parentId] = currentGen - 1;
        queue.add(_QueueItem(parentId, currentGen - 1));
      }
    }

    // Children are one generation below
    for (final childId in childOf[item.id] ?? []) {
      if (!visited.contains(childId)) {
        visited.add(childId);
        generationMap[childId] = currentGen + 1;
        queue.add(_QueueItem(childId, currentGen + 1));
      }
    }

    // Spouse is same generation
    final spouseId = spouseOf[item.id];
    if (spouseId != null && !visited.contains(spouseId)) {
      visited.add(spouseId);
      generationMap[spouseId] = currentGen;
      queue.add(_QueueItem(spouseId, currentGen));
    }

    // Siblings are same generation
    for (final siblingId in siblingOf[item.id] ?? []) {
      if (!visited.contains(siblingId)) {
        visited.add(siblingId);
        generationMap[siblingId] = currentGen;
        queue.add(_QueueItem(siblingId, currentGen));
      }
    }
  }

  // Assign remaining unvisited members
  for (final m in activeMembers) {
    if (!visited.contains(m.id)) {
      // Use generationIndex from Person if available, otherwise default to 3
      final gen = m.generationIndex > 0 ? m.generationIndex : 3;
      generationMap[m.id] = gen;
      visited.add(m.id);
    }
  }

  // Infer relationship labels for unlabeled nodes
  _inferRelationshipLabels(
    activeMembers: activeMembers,
    relationships: relationships,
    anchorId: anchor.id,
    relLabelOf: relLabelOf,
    generationMap: generationMap,
  );

  // Build graph nodes
  final nodes = <String, _GraphNode>{};
  for (final m in activeMembers) {
    final gen = generationMap[m.id] ?? 3;
    nodes[m.id] = _GraphNode(
      person: m,
      generation: gen,
      isAnchor: m.id == anchor.id,
      relationshipLabel: relLabelOf[m.id],
      spouseId: spouseOf[m.id],
    );
  }

  // Build edges (deduplicated)
  final edges = <_GraphEdge>[];
  final edgeSet = <String>{};

  for (final rel in relationships) {
    if (!rel.isActive) continue;
    final type = rel.relationshipKey.toLowerCase();
    final fromId = rel.fromPersonId;
    final toId = rel.toPersonId;
    if (!nodes.containsKey(fromId) || !nodes.containsKey(toId)) continue;

    final key1 = '$fromId-$toId';
    final key2 = '$toId-$fromId';
    if (edgeSet.contains(key1) || edgeSet.contains(key2)) continue;

    final _EdgeType edgeType;
    if (['spouse', 'husband', 'wife'].contains(type)) {
      edgeType = _EdgeType.spouse;
    } else if (['father', 'mother', 'parent', 'child', 'son', 'daughter'].contains(type)) {
      edgeType = _EdgeType.parentChild;
    } else {
      // All other relationship types (brother, sister, sibling, uncle, aunt,
      // nephew, niece, cousin, grandfather, grandmother, grandchild, etc.)
      // become sibling edges drawn as upward-curving bezier arcs.
      edgeType = _EdgeType.sibling;
    }

    edges.add(_GraphEdge(fromId: fromId, toId: toId, type: edgeType));
    edgeSet.add(key1);
    edgeSet.add(key2);
  }

  // Compute positions
  const double nodeRadius = 36.0;
  const double horizontalGap = 120.0;  // was 110
  const double verticalGap = 170.0;    // was 160
  const double spouseGap = 100.0;      // was 90
  const double leftPadding = 160.0;    // Space for generation labels
  const double topPadding = 90.0;      // was 80

  // Group by generation
  final genGroups = <int, List<String>>{};
  for (final entry in nodes.entries) {
    final gen = entry.value.generation;
    genGroups.putIfAbsent(gen, () => []).add(entry.key);
  }

  // Sort generations
  final sortedGens = genGroups.keys.toList()..sort();

  // Position each generation row
  final positions = <String, Offset>{};

  for (final gen in sortedGens) {
    final membersInGen = genGroups[gen]!;
    final genIndex = sortedGens.indexOf(gen);
    final y = topPadding + genIndex * verticalGap;

    // Sort: anchor first, then by name
    membersInGen.sort((a, b) {
      if (a == anchor.id) return -1;
      if (b == anchor.id) return 1;

      // Group spouses together
      final aSpouse = spouseOf[a];
      final bSpouse = spouseOf[b];
      if (aSpouse == b) return -1;
      if (bSpouse == a) return 1;

      return nodes[a]!.person.name.compareTo(nodes[b]!.person.name);
    });

    // Compute widths: spouse pairs count as one unit with smaller gap
    final units = <List<String>>[];
    final usedInPair = <String>{};

    for (final id in membersInGen) {
      if (usedInPair.contains(id)) continue;
      final spouse = spouseOf[id];
      if (spouse != null && membersInGen.contains(spouse) && !usedInPair.contains(spouse)) {
        units.add([id, spouse]);
        usedInPair.add(id);
        usedInPair.add(spouse);
      } else {
        units.add([id]);
        usedInPair.add(id);
      }
    }

    // Position each unit
    double x = leftPadding;
    for (int i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit.length == 2) {
        // Left person
        positions[unit[0]] = Offset(x + nodeRadius, y + nodeRadius);
        // Right person
        positions[unit[1]] = Offset(x + nodeRadius * 2 + spouseGap + nodeRadius, y + nodeRadius);
        x += nodeRadius * 2 * 2 + spouseGap;
      } else {
        positions[unit[0]] = Offset(x + nodeRadius, y + nodeRadius);
        x += nodeRadius * 2;
      }
      if (i < units.length - 1) {
        x += horizontalGap;
      }
    }
  }

  // Compute canvas size
  double maxX = 0;
  double maxY = 0;
  for (final pos in positions.values) {
    if (pos.dx + nodeRadius > maxX) maxX = pos.dx + nodeRadius;
    if (pos.dy + nodeRadius + 60 > maxY) maxY = pos.dy + nodeRadius + 60; // Extra for labels
  }

  final canvasW = math.max(maxX + 80, 800);
  final canvasH = math.max(maxY + 160, 600);

  return _LayoutResult(
    nodes: nodes,
    edges: edges,
    positions: positions,
    anchorId: anchor.id,
    generations: sortedGens.toSet(),
    canvasSize: Size(canvasW.toDouble(), canvasH.toDouble()),
  );
}

class _QueueItem {
  const _QueueItem(this.id, this.generation);
  final String id;
  final int generation;
}

String _formatRelLabel(String key) {
  const labelMap = {
    'father': 'Father',
    'mother': 'Mother',
    'parent': 'Parent',
    'child': 'Child',
    'son': 'Son',
    'daughter': 'Daughter',
    'brother': 'Brother',
    'sister': 'Sister',
    'spouse': 'Spouse',
    'husband': 'Husband',
    'wife': 'Wife',
    'grandfather': 'Grandfather',
    'grandmother': 'Grandmother',
    'grandparent': 'Grandparent',
    'grandchild': 'Grandchild',
    'uncle': 'Uncle',
    'aunt': 'Aunt',
    'nephew': 'Nephew',
    'niece': 'Niece',
    'cousin': 'Cousin',
    'father_in_law': 'Father-in-law',
    'mother_in_law': 'Mother-in-law',
    'son_in_law': 'Son-in-law',
    'daughter_in_law': 'Daughter-in-law',
    'brother_in_law': 'Brother-in-law',
    'sister_in_law': 'Sister-in-law',
  };
  return labelMap[key] ?? key.replaceAll('_', ' ').split(' ').map((w) => w.isNotEmpty ? w[0].toUpperCase() + w.substring(1) : '').join(' ');
}

void _inferRelationshipLabels({
  required List<Person> activeMembers,
  required List<FamilyRelationship> relationships,
  required String anchorId,
  required Map<String, String> relLabelOf,
  required Map<String, int> generationMap,
}) {
  // For each unlabeled node, infer from generation difference
  for (final m in activeMembers) {
    if (relLabelOf.containsKey(m.id)) continue;
    if (m.id == anchorId) continue;

    final genDiff = (generationMap[m.id] ?? 3) - 3;
    final gender = m.gender?.toLowerCase();

    if (genDiff == -2) {
      relLabelOf[m.id] = gender == 'male' ? 'Grandfather' : 'Grandmother';
    } else if (genDiff == -1) {
      relLabelOf[m.id] = gender == 'male' ? 'Father' : 'Mother';
    } else if (genDiff == 0) {
      // Check if spouse
      for (final rel in relationships) {
        if (!rel.isActive) continue;
        final type = rel.relationshipKey.toLowerCase();
        if (['spouse', 'husband', 'wife'].contains(type)) {
          if (rel.fromPersonId == m.id && rel.toPersonId == anchorId) {
            relLabelOf[m.id] = gender == 'male' ? 'Husband' : 'Wife';
            break;
          } else if (rel.toPersonId == m.id && rel.fromPersonId == anchorId) {
            relLabelOf[m.id] = gender == 'male' ? 'Husband' : 'Wife';
            break;
          }
        }
        if (['brother', 'sister', 'sibling'].contains(type)) {
          if (rel.fromPersonId == m.id || rel.toPersonId == m.id) {
            relLabelOf[m.id] = gender == 'male' ? 'Brother' : 'Sister';
            break;
          }
        }
      }
      if (!relLabelOf.containsKey(m.id)) {
        relLabelOf[m.id] = gender == 'male' ? 'Brother' : 'Sister';
      }
    } else if (genDiff == 1) {
      relLabelOf[m.id] = gender == 'male' ? 'Son' : 'Daughter';
    } else if (genDiff == 2) {
      relLabelOf[m.id] = gender == 'male' ? 'Grandson' : 'Granddaughter';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════

class RelationshipGraphScreen extends ConsumerStatefulWidget {
  const RelationshipGraphScreen({super.key, required this.familyId});

  final String familyId;

  @override
  ConsumerState<RelationshipGraphScreen> createState() => _RelationshipGraphScreenState();
}

class _RelationshipGraphScreenState extends ConsumerState<RelationshipGraphScreen>
    with TickerProviderStateMixin {
  // ── View state ──────────────────────────────────────────────────
  final TransformationController _transformationController = TransformationController();
  double _currentScale = 1.0;
  String? _selectedNodeId;

  // ── Animation ───────────────────────────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _entryController;

  // ── Layout cache ────────────────────────────────────────────────
  _LayoutResult? _cachedLayout;

  // ── Painter reference for midpoint hit detection ──────────────
  _RelationshipGraphPainter? _graphPainter;

  // ── Constants ───────────────────────────────────────────────────
  static const double nodeRadius = 36.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Start entry animation after a brief delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _entryController.forward();
    });

    // Center on anchor after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerOnAnchor();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entryController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _centerOnAnchor() {
    final layout = _cachedLayout;
    if (layout == null || layout.anchorId == null) return;
    final anchorPos = layout.positions[layout.anchorId];
    if (anchorPos == null) return;

    final screenSize = MediaQuery.of(context).size;
    final scale = 1.2;
    setState(() {
      final m = Matrix4.identity();
      m.setEntry(0, 3, screenSize.width / 2 - anchorPos.dx * scale);
      m.setEntry(1, 3, screenSize.height / 2 - anchorPos.dy * scale);
      m.scaleByDouble(scale, scale, 1.0, 1.0);
      _transformationController.value = m;
      _currentScale = scale;
    });
  }

  void _fitToScreen() {
    final layout = _cachedLayout;
    if (layout == null) return;

    final screenSize = MediaQuery.of(context).size;
    final canvasW = layout.canvasSize.width;
    final canvasH = layout.canvasSize.height;

    if (canvasW <= 0 || canvasH <= 0) return;

    final scaleX = (screenSize.width - 32) / canvasW;
    final scaleY = (screenSize.height - 200) / canvasH;
    final scale = math.min(scaleX, scaleY);
    final clampedScale = scale.clamp(0.3, 1.5);

    setState(() {
      final m = Matrix4.identity();
      m.setEntry(0, 3, (screenSize.width - canvasW * clampedScale) / 2);
      m.setEntry(1, 3, (screenSize.height - 100 - canvasH * clampedScale) / 2);
      m.scaleByDouble(clampedScale, clampedScale, 1.0, 1.0);
      _transformationController.value = m;
      _currentScale = clampedScale;
    });
  }

  void _zoomIn() {
    final newScale = (_currentScale * 1.2).clamp(0.3, 3.0);
    final screenSize = MediaQuery.of(context).size;
    setState(() {
      final m = _transformationController.value.clone();
      final centerX = screenSize.width / 2;
      final centerY = screenSize.height / 2;
      m.setEntry(0, 3, centerX - (centerX - m.entry(0, 3)) * (newScale / _currentScale));
      m.setEntry(1, 3, centerY - (centerY - m.entry(1, 3)) * (newScale / _currentScale));
      _transformationController.value = m;
      _currentScale = newScale;
    });
  }

  void _zoomOut() {
    final newScale = (_currentScale / 1.2).clamp(0.3, 3.0);
    final screenSize = MediaQuery.of(context).size;
    setState(() {
      final m = _transformationController.value.clone();
      final centerX = screenSize.width / 2;
      final centerY = screenSize.height / 2;
      m.setEntry(0, 3, centerX - (centerX - m.entry(0, 3)) * (newScale / _currentScale));
      m.setEntry(1, 3, centerY - (centerY - m.entry(1, 3)) * (newScale / _currentScale));
      _transformationController.value = m;
      _currentScale = newScale;
    });
  }

  void _handleTap(Offset localPos, _LayoutResult layout) {
    final transform = _transformationController.value;
    final inverse = Matrix4.identity()..copyInverse(transform);
    final graphPos = MatrixUtils.transformPoint(inverse, localPos);

    // ── Check midpoint dot hits first (priority over node taps) ──
    for (final target in _graphPainter?.midpointTargets ?? <_EdgeMidpointTarget>[]) {
      final dist = (target.midpointPos - graphPos).distance;
      if (dist < 18) {
        _showEdgeKinshipSheet(target);
        return;
      }
    }

    // ── Check node taps ──────────────────────────────────────────
    String? tappedId;
    for (final entry in layout.positions.entries) {
      final center = entry.value;
      final dist = (center - graphPos).distance;
      if (dist < nodeRadius * 1.5) {
        tappedId = entry.key;
        break;
      }
    }

    if (tappedId != null) {
      final node = layout.nodes[tappedId];
      if (node != null) {
        setState(() => _selectedNodeId = tappedId);
        final kinshipAsync = ref.read(kinshipServiceProvider);
        PersonDetailSheet.show(
          context,
          person: node.person,
          familyId: widget.familyId,
          kinshipService: kinshipAsync,
        );
      }
    } else {
      setState(() => _selectedNodeId = null);
    }
  }

  void _showEdgeKinshipSheet(_EdgeMidpointTarget target) async {
    // 4a — Resolve kinship term
    String kinshipLabel = 'Family Member';
    try {
      final graphService = ref.read(graphServiceProvider);
      final detail = await ref.read(familyDetailProvider(widget.familyId).future);

      if (detail != null) {
        final persons = detail.members
            .where((m) => m.deletedAt == null)
            .map((m) => m.toGraphPerson())
            .toList();
        final relationships = detail.relationships
            .where((r) => r.isActive)
            .map((r) => r.toGraphEdge())
            .toList();

        final result = await graphService.findPathAsync(
          persons: persons,
          relationships: relationships,
          fromPersonId: target.nodeA.person.id,
          toPersonId: target.nodeB.person.id,
          familyId: widget.familyId,
        );

        kinshipLabel = result?.composedKinshipTerm ??
            result?.localizedDescription ??
            result?.relationshipDescription ??
            'Family Member';
        if (kinshipLabel.isEmpty) kinshipLabel = 'Family Member';
      }
    } catch (_) {
      kinshipLabel = 'Family Member';
    }

    if (!mounted) return;

    // 4b — Show bottom sheet with loading state for kinship
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(KinrelSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle bar
                    Container(
                      width: 40,
                      height: 4,
                      margin: EdgeInsets.only(bottom: KinrelSpacing.sm),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Avatars row with connection line and heart
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left avatar — nodeA (52px)
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: KinrelColors.orange.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            color: KinrelColors.orange.withValues(alpha: 0.15),
                          ),
                          child: Center(
                            child: Text(
                              target.nodeA.initials,
                              style: TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.textWhite,
                                height: 1,
                              ),
                            ),
                          ),
                        ),

                        // Connection line with heart overlay
                        SizedBox(
                          width: 40,
                          height: 24,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                left: 0,
                                right: 0,
                                top: 11.25,
                                child: Container(
                                  height: 1.5,
                                  width: 40,
                                  color: KinrelColors.amber.withValues(alpha: 0.6),
                                ),
                              ),
                              Icon(
                                Icons.favorite_rounded,
                                size: 12,
                                color: KinrelColors.amber,
                              ),
                            ],
                          ),
                        ),

                        // Right avatar — nodeB (52px)
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: KinrelColors.orange.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            color: KinrelColors.orange.withValues(alpha: 0.15),
                          ),
                          child: Center(
                            child: Text(
                              target.nodeB.initials,
                              style: TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.textWhite,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: KinrelSpacing.md),

                    // Names row
                    Text(
                      '${target.nodeA.person.name}  ·  ${target.nodeB.person.name}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),

                    SizedBox(height: KinrelSpacing.sm),

                    // Kinship label pill (with loading indicator)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: KinrelColors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: KinrelColors.orange.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: kinshipLabel == 'Family Member' && kinshipLabel.isEmpty
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: KinrelColors.orange,
                              ),
                            )
                          : Text(
                              kinshipLabel,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: KinrelColors.orange,
                              ),
                              textAlign: TextAlign.center,
                            ),
                    ),

                    SizedBox(height: KinrelSpacing.lg),

                    // View profile buttons
                    Row(
                      children: [
                        Expanded(
                          child: DKButton(
                            label: 'View ${target.nodeA.person.name.split(' ').first}',
                            variant: DKButtonVariant.secondary,
                            size: DKButtonSize.md,
                            fullWidth: true,
                            onPressed: () {
                              context.pop();
                              context.push('/member/${target.nodeA.person.id}');
                            },
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: DKButton(
                            label: 'View ${target.nodeB.person.name.split(' ').first}',
                            variant: DKButtonVariant.primary,
                            size: DKButtonSize.md,
                            fullWidth: true,
                            onPressed: () {
                              context.pop();
                              context.push('/member/${target.nodeB.person.id}');
                            },
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: KinrelSpacing.sm),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(familyDetailProvider(widget.familyId));

    return DKScaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: detailAsync.when(
          loading: () => Text(
            'Relationship Graph',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
            ),
          ),
          error: (_, __) => Text(
            'Relationship Graph',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
            ),
          ),
          data: (detail) => Text(
            detail?.family.name ?? 'Relationship Graph',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
              fontSize: 17,
            ),
          ),
        ),
        actions: [
          // ✅ FIX: Add Member button in top-right corner so users can
          // add members even when the graph is already populated.
          if (detailAsync.valueOrNull?.members.isNotEmpty ?? false)
            IconButton(
              icon: const Icon(Icons.person_add_rounded, size: 22),
              onPressed: () => AddPersonSheet.show(
                context,
                familyId: widget.familyId,
              ),
              tooltip: 'Add Member',
            ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 22),
            onPressed: _zoomIn,
            tooltip: 'Zoom In',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 22),
            onPressed: _zoomOut,
            tooltip: 'Zoom Out',
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
        error: (e, _) => DKErrorState(
          message: 'Failed to load family data',
          onRetry: () => ref.invalidate(familyDetailProvider(widget.familyId)),
        ),
        data: (detail) {
          if (detail == null || detail.members.isEmpty) {
            return DKEmptyState(
              icon: Icons.account_tree_outlined,
              title: 'No Members Yet',
              subtitle: 'Add family members to see the relationship graph.',
              actionLabel: 'Add Member',
              onAction: () => AddPersonSheet.show(context, familyId: widget.familyId),
            );
          }

          // ── Phase 7: Privacy gate ──────────────────────────────
          final userFamilies = ref.watch(familyListProvider);
          // While family list is still loading, assume member to
          // avoid flashing the lock overlay for actual members.
          final isMember = userFamilies.isLoading
              ? true
              : userFamilies.valueOrNull
                      ?.any((f) => f.id == widget.familyId) ??
                  false;
          final isPrivate = detail.family.privacyMode == 'private';

          // Private + non-member → lock overlay
          if (!isMember && isPrivate) {
            return _buildPrivateOverlay();
          }

          // Public + non-member → graph with read-only banner
          return _buildGraph(detail, isReadOnly: !isMember);
        },
      ),
    );
  }

  // ── Phase 7: Private family lock overlay ────────────────────────
  Widget _buildPrivateOverlay() {
    final isLight = DKColors.isLight(context);
    return Container(
      color: isLight ? KinrelColors.lightBackground : KinrelColors.darkBackground,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: KinrelColors.orange.withValues(alpha: isLight ? 0.7 : 0.9),
              ),
              const SizedBox(height: 24),
              Text(
                'This family tree is private',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isLight ? KinrelColors.textDark : KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You must be a member to view it.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: isLight ? KinrelColors.textSecondaryLight : KinrelColors.textSilver,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 220,
                child: ElevatedButton(
                  onPressed: () => context.push('/family/${widget.familyId}/invite'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KinrelColors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Request Access',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
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

  Widget _buildGraph(FamilyDetail detail, {bool isReadOnly = false}) {
    // Compute layout
    final layout = _computeLayout(
      members: detail.members,
      relationships: detail.relationships,
      anchorPersonId: detail.family.anchorPersonId,
    );
    _cachedLayout = layout;

    if (layout.nodes.isEmpty) {
      return DKEmptyState(
        icon: Icons.account_tree_outlined,
        title: 'No Connections',
        subtitle: 'Add relationships between members to see the graph.',
      );
    }

    return Stack(
      children: [
        // ── Phase 7: Read-only banner (non-member, public family) ──
        if (isReadOnly)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.12),
                border: Border(
                  bottom: BorderSide(
                    color: KinrelColors.orange.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: KinrelColors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You are viewing this family tree in read-only mode. Contact details are hidden.',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Interactive graph canvas ─────────────────────────────
        Container(
          color: DKColors.isLight(context) ? DKColors.lightBg : KinrelColors.darkBackground,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.3,
            maxScale: 3.0,
            boundaryMargin: const EdgeInsets.all(2000),
            onInteractionUpdate: (details) {
              setState(() => _currentScale = details.scale);
            },
            child: GestureDetector(
              onTapUp: (details) => _handleTap(details.localPosition, layout),
              child: SizedBox(
                width: layout.canvasSize.width,
                height: layout.canvasSize.height,
                child: KinrelAnimatedBuilder(
                  listenable: Listenable.merge([_pulseController, _entryController]),
                  builder: (context, _) {
                    final painter = _RelationshipGraphPainter(
                      layout: layout,
                      pulseValue: _pulseController.value,
                      entryValue: _entryController.value,
                      selectedNodeId: _selectedNodeId,
                      anchorId: layout.anchorId,
                    );
                    _graphPainter = painter;
                    return RepaintBoundary(
                      child: CustomPaint(
                        size: layout.canvasSize,
                        painter: painter,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        // ── Bottom control pill ──────────────────────────────────
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: _ControlPill(
              onCenterYou: _centerOnAnchor,
              onFitAll: _fitToScreen,
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
            ),
          ),
        ),

        // ── Bottom legend ────────────────────────────────────────
        Positioned(
          bottom: 76,
          left: 0,
          right: 0,
          child: Center(
            child: _GenerationLegend(generations: layout.generations),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER — The core graph rendering
// ═══════════════════════════════════════════════════════════════════════

class _RelationshipGraphPainter extends CustomPainter {
  _RelationshipGraphPainter({
    required this.layout,
    required this.pulseValue,
    required this.entryValue,
    required this.selectedNodeId,
    required this.anchorId,
  });

  final _LayoutResult layout;
  final double pulseValue;
  final double entryValue;
  final String? selectedNodeId;
  final String? anchorId;

  static const double nodeRadius = 36.0;

  /// Hit targets for midpoint dots — populated fresh each paint call
  final List<_EdgeMidpointTarget> midpointTargets = [];

  void _drawCanvasBackground(Canvas canvas, Size size) {
    const double spacing = 40.0;
    final dotPaint = Paint()
      ..color = const Color(0xFF2A2A3D).withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.nodes.isEmpty) return;

    midpointTargets.clear();

    // ── Draw subtle dot grid background ───────────────────────
    _drawCanvasBackground(canvas, size);

    // ── Draw generation label bands ──────────────────────────────
    _drawGenerationLabels(canvas, size);

    // ── Draw edges ───────────────────────────────────────────────
    for (final edge in layout.edges) {
      _drawEdge(canvas, edge);
    }

    // ── Draw nodes (sorted by generation for entry animation) ────
    final sortedNodes = layout.nodes.values.toList()
      ..sort((a, b) => a.generation.compareTo(b.generation));

    for (final node in sortedNodes) {
      final pos = layout.positions[node.person.id];
      if (pos == null) continue;

      // Entry animation: fade in by generation
      final genIndex = layout.generations.toList()..sort();
      final genEntryIndex = genIndex.indexOf(node.generation);
      final totalGens = genIndex.length;
      final genDelay = genEntryIndex / math.max(totalGens, 1);
      final nodeEntryProgress = ((entryValue - genDelay * 0.6) / 0.4).clamp(0.0, 1.0);

      if (nodeEntryProgress <= 0) continue;

      _drawNode(canvas, node, pos, nodeEntryProgress);
    }
  }

  void _drawGenerationLabels(Canvas canvas, Size size) {
    final genGroups = <int, List<String>>{};
    for (final entry in layout.nodes.entries) {
      genGroups.putIfAbsent(entry.value.generation, () => []).add(entry.key);
    }

    final sortedGens = genGroups.keys.toList()..sort();
    final anchorGen = layout.nodes[anchorId]?.generation ?? 3;

    for (final gen in sortedGens) {
      final ids = genGroups[gen]!;
      double sumY = 0;
      for (final id in ids) {
        final pos = layout.positions[id];
        if (pos != null) sumY += pos.dy;
      }
      final avgY = sumY / ids.length;

      final genDiff = gen - anchorGen;
      final Color color;
      final String label;

      if (gen == anchorGen) {
        color = _GenColors.self;
        label = 'SELF';
      } else if (genDiff < 0) {
        // Color by how far above
        color = genDiff == -1 ? _GenColors.parent : _GenColors.grandparent;
        label = genDiff == -1 ? 'PARENTS' : genDiff == -2 ? 'GRANDPARENTS' : 'ANCESTORS';
      } else {
        color = genDiff == 1 ? _GenColors.child : _GenColors.grandchild;
        label = genDiff == 1 ? 'CHILDREN' : 'GRANDCHILDREN';
      }

      // Subtle horizontal guide line across canvas
      final guidePaint = Paint()
        ..color = color.withValues(alpha: 0.05)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(140, avgY), Offset(size.width, avgY), guidePaint);

      // Pill dimensions
      final pillX = 8.0;
      final pillH = 22.0;
      final dotRadius = 4.0;
      final dotX = pillX + 12;
      final textX = dotX + dotRadius + 6;

      // Measure text first
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 1.4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final pillW = textX + textPainter.width + 10 - pillX;
      final pillY = avgY - pillH / 2;

      // Pill background
      final pillPaint = Paint()
        ..color = color.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill;
      final pillBorderPaint = Paint()
        ..color = color.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      final pillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(pillX, pillY, pillW, pillH),
        Radius.circular(11),
      );
      canvas.drawRRect(pillRect, pillPaint);
      canvas.drawRRect(pillRect, pillBorderPaint);

      // Colored dot
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      // Tiny glow on dot
      final dotGlowPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(dotX, avgY), dotRadius + 1, dotGlowPaint);
      canvas.drawCircle(Offset(dotX, avgY), dotRadius, dotPaint);

      // Label text
      textPainter.paint(canvas, Offset(textX, pillY + (pillH - textPainter.height) / 2));
    }
  }

  void _drawEdge(Canvas canvas, _GraphEdge edge) {
    final fromPos = layout.positions[edge.fromId];
    final toPos = layout.positions[edge.toId];
    if (fromPos == null || toPos == null) return;

    // Draw the edge line and get midpoint
    final Offset midpoint;
    if (edge.type == _EdgeType.spouse) {
      midpoint = _drawSpouseEdge(canvas, fromPos, toPos);
    } else if (edge.type == _EdgeType.sibling) {
      midpoint = _drawSiblingEdge(canvas, fromPos, toPos);
    } else {
      midpoint = _drawParentChildEdge(canvas, fromPos, toPos);
    }

    // ── Entry animation check for midpoint dot ────────────────────
    final nodeA = layout.nodes[edge.fromId];
    final nodeB = layout.nodes[edge.toId];
    if (nodeA == null || nodeB == null) return;

    final genIndex = layout.generations.toList()..sort();
    final totalGens = genIndex.length;

    final genEntryIndexA = genIndex.indexOf(nodeA.generation);
    final genDelayA = genEntryIndexA / math.max(totalGens, 1);
    final progressA = ((entryValue - genDelayA * 0.6) / 0.4).clamp(0.0, 1.0);

    final genEntryIndexB = genIndex.indexOf(nodeB.generation);
    final genDelayB = genEntryIndexB / math.max(totalGens, 1);
    final progressB = ((entryValue - genDelayB * 0.6) / 0.4).clamp(0.0, 1.0);

    // Only draw dot if both nodes have progress above 0.3
    if (progressA <= 0.3 || progressB <= 0.3) return;

    // ── Draw the amber midpoint dot ───────────────────────────────
    // Outer glow (larger)
    final outerGlowPaint = Paint()
      ..color = KinrelColors.amber.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(midpoint, 10, outerGlowPaint);

    // Inner glow
    final glowPaint = Paint()
      ..color = KinrelColors.amber.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(midpoint, 6, glowPaint);

    // Filled dot
    final dotPaint = Paint()
      ..color = KinrelColors.amber
      ..style = PaintingStyle.fill;
    canvas.drawCircle(midpoint, 4.5, dotPaint);

    // White center highlight
    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(midpoint, 1.5, centerPaint);

    // Dark border ring
    final borderPaint = Paint()
      ..color = KinrelColors.darkBackground.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(midpoint, 4.5, borderPaint);

    // ── Populate hit target ───────────────────────────────────────
    midpointTargets.add(_EdgeMidpointTarget(
      midpointPos: midpoint,
      edge: edge,
      nodeA: nodeA,
      nodeB: nodeB,
    ));
  }

  Offset _drawParentChildEdge(Canvas canvas, Offset parentPos, Offset childPos) {
    final paint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // Smooth S-curve bezier from parent bottom to child top
    final startY = parentPos.dy + nodeRadius;
    final endY = childPos.dy - nodeRadius;
    final dy = endY - startY;

    // Control points create a graceful S-curve:
    //   CP1 is directly below parent at 40% of vertical distance
    //   CP2 is directly above child at 60% of vertical distance
    final cp1 = Offset(parentPos.dx, startY + dy * 0.4);
    final cp2 = Offset(childPos.dx, startY + dy * 0.6);

    final path = Path()
      ..moveTo(parentPos.dx, startY)
      ..cubicTo(
        cp1.dx, cp1.dy,
        cp2.dx, cp2.dy,
        childPos.dx, endY,
      );

    _drawDashedPath(canvas, path, paint);

    // Small arrow dot at child end
    final dotPaint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(childPos.dx, endY - 3), 3, dotPaint);

    // Midpoint is at the center of the cubic bezier at t=0.5
    // For a cubic bezier B(t) = (1-t)^3*P0 + 3(1-t)^2*t*P1 + 3(1-t)*t^2*P2 + t^3*P3
    final t = 0.5;
    final mt = 1 - t;
    final midX = mt*mt*mt*parentPos.dx + 3*mt*mt*t*cp1.dx + 3*mt*t*t*cp2.dx + t*t*t*childPos.dx;
    final midY = mt*mt*mt*startY + 3*mt*mt*t*cp1.dy + 3*mt*t*t*cp2.dy + t*t*t*endY;
    return Offset(midX, midY);
  }

  Offset _drawSpouseEdge(Canvas canvas, Offset pos1, Offset pos2) {
    final paint = Paint()
      ..color = KinrelColors.amber.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // Smooth horizontal bezier with a gentle arc between spouses
    final startX = pos1.dx + nodeRadius + 2;
    final endX = pos2.dx - nodeRadius - 2;
    final midX = (startX + endX) / 2;
    final midY = (pos1.dy + pos2.dy) / 2;

    // Control points create a gentle downward/upward arc
    final arcHeight = 12.0; // Subtle arc for visual softness
    final cp1 = Offset(startX + (endX - startX) * 0.3, midY + arcHeight);
    final cp2 = Offset(startX + (endX - startX) * 0.7, midY - arcHeight);

    final path = Path()
      ..moveTo(startX, pos1.dy)
      ..cubicTo(
        cp1.dx, cp1.dy,
        cp2.dx, cp2.dy,
        endX, pos2.dy,
      );

    _drawDashedPath(canvas, path, paint);

    // Heart icon at midpoint
    _drawHeart(canvas, Offset(midX, midY), 6);

    // Return midpoint 10px above heart to avoid overlap
    return Offset(midX, midY - 10);
  }

  Offset _drawSiblingEdge(Canvas canvas, Offset fromPos, Offset toPos) {
    final paint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    // Compute midpoint between the two positions
    final midX = (fromPos.dx + toPos.dx) / 2;
    final midY = (fromPos.dy + toPos.dy) / 2;

    // Control point above the midpoint for a smooth upward-curving arc
    // Scale the arc height based on horizontal distance for natural curves
    final dx = (toPos.dx - fromPos.dx).abs();
    final arcHeight = math.max(50.0, dx * 0.3);

    // Use cubic bezier with two control points for a smoother, more natural arc
    final cp1 = Offset(fromPos.dx + (toPos.dx - fromPos.dx) * 0.25, midY - arcHeight);
    final cp2 = Offset(fromPos.dx + (toPos.dx - fromPos.dx) * 0.75, midY - arcHeight);

    final path = Path()
      ..moveTo(fromPos.dx, fromPos.dy)
      ..cubicTo(
        cp1.dx, cp1.dy,
        cp2.dx, cp2.dy,
        toPos.dx, toPos.dy,
      );

    _drawDashedPath(canvas, path, paint);

    // Small dot at the apex of the arc (cubic bezier at t=0.5)
    final t = 0.5;
    final mt = 1 - t;
    final apexX = mt*mt*mt*fromPos.dx + 3*mt*mt*t*cp1.dx + 3*mt*t*t*cp2.dx + t*t*t*toPos.dx;
    final apexY = mt*mt*mt*fromPos.dy + 3*mt*mt*t*cp1.dy + 3*mt*t*t*cp2.dy + t*t*t*toPos.dy;
    final dotPaint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(apexX, apexY), 3, dotPaint);

    // Return the bezier midpoint (at t=0.5) as the midpoint target
    return Offset(apexX, apexY);
  }

  void _drawHeart(Canvas canvas, Offset center, double size) {
    // Glow behind heart
    final glowPaint = Paint()
      ..color = KinrelColors.amber.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    _drawHeartPath(canvas, center, size * 1.3, glowPaint);

    // Filled heart
    final fillPaint = Paint()
      ..color = KinrelColors.amber
      ..style = PaintingStyle.fill;
    _drawHeartPath(canvas, center, size, fillPaint);
  }

  void _drawHeartPath(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    path.moveTo(center.dx, center.dy + size * 0.3);
    path.cubicTo(
      center.dx - size, center.dy - size * 0.5,
      center.dx - size * 0.5, center.dy - size,
      center.dx, center.dy - size * 0.4,
    );
    path.cubicTo(
      center.dx + size * 0.5, center.dy - size,
      center.dx + size, center.dy - size * 0.5,
      center.dx, center.dy + size * 0.3,
    );
    canvas.drawPath(path, paint);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    // Manual dashed line implementation
    const double dashLength = 6.0;
    const double gapLength = 4.0;

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final start = distance;
        final end = math.min(distance + dashLength, metric.length);
        canvas.drawPath(
          metric.extractPath(start, end),
          paint,
        );
        distance += dashLength + gapLength;
      }
    }
  }

  void _drawNode(Canvas canvas, _GraphNode node, Offset pos, double entryProgress) {
    // Use relationship-based color matching the design spec
    final anchorGen = layout.nodes[anchorId]?.generation ?? 3;
    final color = _GenColors.forRelationship(
      generation: node.generation,
      relationshipLabel: node.relationshipLabel,
      isAnchor: node.isAnchor,
      anchorGeneration: anchorGen,
    );
    final isAnchor = node.isAnchor;
    final isSelected = node.person.id == selectedNodeId;

    // Anchor node is larger (44px vs 36px radius)
    final effectiveRadius = isAnchor ? nodeRadius + 8 : nodeRadius;

    // Apply entry animation: scale + opacity
    final scale = Curves.easeOutBack.transform(entryProgress);
    final opacity = entryProgress;

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(scale);
    canvas.translate(-pos.dx, -pos.dy);

    // ── Anchor glow effect ──────────────────────────────────────
    if (isAnchor) {
      // Outer radial halo
      final haloRadius = effectiveRadius + 20 + pulseValue * 12;
      final haloPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            _GenColors.self.withValues(alpha: 0.45 * opacity),
            _GenColors.self.withValues(alpha: 0.12 * opacity),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: pos, radius: haloRadius));
      canvas.drawCircle(pos, haloRadius, haloPaint);

      // Pulsing outer ring (thick)
      final outerRingPaint = Paint()
        ..color = _GenColors.self.withValues(alpha: (0.20 + pulseValue * 0.15) * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(pos, effectiveRadius + 12 + pulseValue * 6, outerRingPaint);

      // Pulsing inner ring (medium)
      final innerRingPaint = Paint()
        ..color = _GenColors.self.withValues(alpha: (0.40 + pulseValue * 0.25) * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(pos, effectiveRadius + 5 + pulseValue * 3, innerRingPaint);
    }

    // ── Node circle ─────────────────────────────────────────────
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.25 * opacity)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = color.withValues(alpha: (isSelected ? 1.0 : 0.8) * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 3.0 : 1.5;

    canvas.drawCircle(pos, effectiveRadius, bgPaint);

    // Inner highlight gradient for depth
    final innerGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.35 * opacity),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
        center: const Alignment(-0.3, -0.3),
      ).createShader(Rect.fromCircle(center: pos, radius: effectiveRadius));
    canvas.drawCircle(pos, effectiveRadius, innerGlowPaint);

    canvas.drawCircle(pos, effectiveRadius, borderPaint);

    // ── Deceased indicator ──────────────────────────────────────
    if (node.person.isDeceased) {
      final deceasedPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.15 * opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, effectiveRadius, deceasedPaint);
    }

    // ── Initials ────────────────────────────────────────────────
    final initialsSize = isAnchor ? 18.0 : 15.0;
    final initialsPainter = TextPainter(
      text: TextSpan(
        text: node.initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: initialsSize,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: opacity),
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    initialsPainter.paint(
      canvas,
      Offset(
        pos.dx - initialsPainter.width / 2,
        pos.dy - initialsPainter.height / 2,
      ),
    );

    // ── Name label ──────────────────────────────────────────────
    final name = node.person.name;
    final displayName = name.length > 14 ? '${name.substring(0, 12)}...' : name;
    final namePainter = TextPainter(
      text: TextSpan(
        text: displayName,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.9 * opacity),
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 100);
    namePainter.paint(
      canvas,
      Offset(
        pos.dx - namePainter.width / 2,
        pos.dy + effectiveRadius + 6,
      ),
    );

    // ── "You" badge under anchor node ───────────────────────
    // The anchor person gets a distinctive "You" label directly
    // below their name, so the user can always identify themselves
    // in the graph regardless of zoom or scroll position.
    if (isAnchor) {
      final youPainter = TextPainter(
        text: TextSpan(
          text: 'You',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: _GenColors.self.withValues(alpha: 0.9 * opacity),
            letterSpacing: 1.0,
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 100);
      youPainter.paint(
        canvas,
        Offset(
          pos.dx - youPainter.width / 2,
          pos.dy + effectiveRadius + 22,
        ),
      );
    }

    // ── Relationship label (non-anchor nodes) ──────────────────
    if (node.relationshipLabel != null && !isAnchor) {
      final relPainter = TextPainter(
        text: TextSpan(
          text: node.relationshipLabel,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9,
            fontWeight: FontWeight.w400,
            color: color.withValues(alpha: 0.7 * opacity),
            letterSpacing: 0.5,
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 100);
      relPainter.paint(
        canvas,
        Offset(
          pos.dx - relPainter.width / 2,
          pos.dy + effectiveRadius + 22,
        ),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RelationshipGraphPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
        oldDelegate.entryValue != entryValue ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.layout != layout;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// BOTTOM CONTROL PILL
// ═══════════════════════════════════════════════════════════════════════

class _ControlPill extends StatelessWidget {
  const _ControlPill({
    required this.onCenterYou,
    required this.onFitAll,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final VoidCallback onCenterYou;
  final VoidCallback onFitAll;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: DKColors.cardColor(context).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusXXl),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillButton(
            icon: Icons.zoom_out_rounded,
            tooltip: 'Zoom Out',
            onTap: onZoomOut,
          ),
          const SizedBox(width: 4),
          _PillButton(
            icon: Icons.zoom_in_rounded,
            tooltip: 'Zoom In',
            onTap: onZoomIn,
          ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: KinrelColors.border,
          ),
          _PillButton(
            icon: Icons.gps_fixed_rounded,
            tooltip: 'Center You',
            onTap: onCenterYou,
            accent: true,
          ),
          const SizedBox(width: 4),
          _PillButton(
            icon: Icons.fit_screen_rounded,
            tooltip: 'Fit All',
            onTap: onFitAll,
          ),
        ],
      ),
    )
    .animate(onPlay: (c) => c.forward())
    .fadeIn(duration: 400.ms)
    .slideY(begin: 0.2, end: 0, duration: 400.ms);
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: accent
            ? KinrelColors.orange.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: accent
                  ? Border.all(color: KinrelColors.orange.withValues(alpha: 0.3))
                  : null,
            ),
            child: Icon(
              icon,
              size: 20,
              color: accent ? KinrelColors.orange : KinrelColors.textSilver,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// GENERATION LEGEND (bottom)
// ═══════════════════════════════════════════════════════════════════════

class _GenerationLegend extends StatelessWidget {
  const _GenerationLegend({required this.generations});

  final Set<int> generations;

  @override
  Widget build(BuildContext context) {
    final sortedGens = generations.toList()..sort();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: DKColors.cardColor(context).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
        border: Border.all(color: KinrelColors.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: sortedGens.map((gen) {
          final color = _GenColors.forGeneration(gen);
          final label = _GenColors.labelForGeneration(gen);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    color: KinrelColors.textSilver,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    )
    .animate(onPlay: (c) => c.forward())
    .fadeIn(duration: 500.ms, delay: 300.ms);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// ANIMATED BUILDER HELPER (matches existing codebase pattern)
// ═══════════════════════════════════════════════════════════════════════

/// Custom animated builder that rebuilds on animation changes.
class KinrelAnimatedBuilder extends AnimatedWidget {
  const KinrelAnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
  });

  final Widget Function(BuildContext context, Widget? child) builder;

  @override
  Widget build(BuildContext context) {
    return builder(context, null);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MIDPOINT DOT HIT TARGET
// ═══════════════════════════════════════════════════════════════════════

/// Bridges between the painter (which draws midpoint dots) and the
/// gesture detector (which handles taps on those dots).
class _EdgeMidpointTarget {
  const _EdgeMidpointTarget({
    required this.midpointPos,
    required this.edge,
    required this.nodeA,
    required this.nodeB,
  });

  /// Screen-space position of the midpoint dot
  final Offset midpointPos;

  /// The graph edge this dot belongs to
  final _GraphEdge edge;

  /// The node at one end of the edge
  final _GraphNode nodeA;

  /// The node at the other end of the edge
  final _GraphNode nodeB;
}
