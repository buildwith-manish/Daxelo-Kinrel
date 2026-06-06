// lib/features/family/presentation/relationship_graph_screen.dart
//
// DAXELO KINREL — Relationship Graph Screen
//
// A STUNNING hierarchical family relationship graph with:
// - Vertical layout: Great-Grandparents → Grandparents → Parents → You → Children
// - Circular nodes with initials, names, and relationship labels
// - Color-coded by generation (lavender → purple → blue → teal → pink)
// - Glowing "You" anchor node with pulsing animation
// - Dashed connection lines (parent-child & spouse)
// - Smooth entry animations (generation by generation)
// - InteractiveViewer for zoom/pan
// - Generation labels on the left side
// - Bottom control pill (zoom, center, fit)
// - Tap nodes for person detail sheet

import 'dart:collection';
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
import '../../../core/graph/graph_service.dart';
import '../../../shared/widgets/dk_components.dart';
import 'add_person_sheet.dart';
import 'person_detail_sheet.dart';

// ═══════════════════════════════════════════════════════════════════════
// GENERATION COLORS (Figma reference)
// ═══════════════════════════════════════════════════════════════════════

class _GenColors {
  _GenColors._();

  /// Great-grandparents+ (generation 0 and below)
  static const Color greatGrandparent = Color(0xFF9B8EC4);

  /// Grandparents (generation 1)
  static const Color grandparent = Color(0xFFB8A9D4);

  /// Parents / Uncles / Aunts (generation 2)
  static const Color parent = Color(0xFF7EB8D8);

  /// Self / Spouse (generation 3 — anchor)
  static const Color self = Color(0xFF4ECDC4);

  /// Children (generation 4)
  static const Color child = Color(0xFFFFB6C1);

  /// Grandchildren (generation 5+)
  static const Color grandchild = Color(0xFFFFD1DC);

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

enum _EdgeType { parentChild, spouse }

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
  final queue = Queue<_QueueItem>();

  // Anchor is generation 3 (center)
  generationMap[anchor.id] = 3;
  visited.add(anchor.id);
  queue.add(_QueueItem(anchor.id, 3));

  // BFS to assign generations
  while (queue.isNotEmpty) {
    final item = queue.removeFirst();
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

    _EdgeType? edgeType;
    if (['spouse', 'husband', 'wife'].contains(type)) {
      edgeType = _EdgeType.spouse;
    } else if (['father', 'mother', 'parent', 'child', 'son', 'daughter'].contains(type)) {
      edgeType = _EdgeType.parentChild;
    }

    if (edgeType != null) {
      edges.add(_GraphEdge(fromId: fromId, toId: toId, type: edgeType));
      edgeSet.add(key1);
      edgeSet.add(key2);
    }
  }

  // Compute positions
  const double nodeRadius = 36.0;
  const double horizontalGap = 110.0;
  const double verticalGap = 160.0;
  const double spouseGap = 90.0;
  const double leftPadding = 160.0; // Space for generation labels
  const double topPadding = 80.0;

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

    // Compute total width
    double totalWidth = 0;
    for (int i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit.length == 2) {
        totalWidth += nodeRadius * 2 * 2 + spouseGap;
      } else {
        totalWidth += nodeRadius * 2;
      }
      if (i < units.length - 1) {
        totalWidth += horizontalGap;
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

          return _buildGraph(detail);
        },
      ),
    );
  }

  Widget _buildGraph(FamilyDetail detail) {
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
        // ── Interactive graph canvas ─────────────────────────────
        Container(
          color: DKColors.isLight(context) ? DKColors.lightBg : KinrelColors.darkBackground,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.3,
            maxScale: 3.0,
            boundaryMargin: const EdgeInsets.all(2000),
            onInteractionUpdate: (details) {
              // Sync _currentScale from the InteractiveViewer's actual transform.
              // Using details.scale is unreliable because it reports the scale
              // *delta* during a pinch gesture, not the absolute scale — this
              // caused drift when combining manual _zoomIn/_zoomOut with
              // InteractiveViewer's built-in gestures.
              final transform = _transformationController.value;
              // Extract absolute scale from the 2x2 sub-matrix
              final sx = transform.entry(0, 0);
              final sy = transform.entry(1, 1);
              final absoluteScale = (sx.abs() + sy.abs()) / 2;
              if ((_currentScale - absoluteScale).abs() > 0.01) {
                setState(() => _currentScale = absoluteScale);
              }
            },
            child: GestureDetector(
              onTapUp: (details) => _handleTap(details.localPosition, layout),
              child: SizedBox(
                width: layout.canvasSize.width,
                height: layout.canvasSize.height,
                child: KinrelAnimatedBuilder(
                  listenable: Listenable.merge([_pulseController, _entryController]),
                  builder: (context, _) {
                    return RepaintBoundary(
                      child: CustomPaint(
                        size: layout.canvasSize,
                        painter: _RelationshipGraphPainter(
                          layout: layout,
                          pulseValue: _pulseController.value,
                          entryValue: _entryController.value,
                          selectedNodeId: _selectedNodeId,
                          anchorId: layout.anchorId,
                        ),
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
  const _RelationshipGraphPainter({
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

  @override
  bool shouldRepaint(covariant _RelationshipGraphPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.entryValue != entryValue ||
        oldDelegate.anchorId != anchorId;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.nodes.isEmpty) return;

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

    for (final gen in sortedGens) {
      final ids = genGroups[gen]!;
      // Compute average Y for this generation
      double sumY = 0;
      for (final id in ids) {
        final pos = layout.positions[id];
        if (pos != null) sumY += pos.dy;
      }
      final avgY = sumY / ids.length;

      final label = _GenColors.labelForGeneration(gen);
      final color = _GenColors.forGeneration(gen);

      // Label background pill
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 9,
            fontWeight: FontWeight.w500,
            color: color,
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final pillW = textPainter.width + 20;
      final pillH = 22.0;
      final pillX = 12.0;
      final pillY = avgY - pillH / 2;

      final pillPaint = Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;
      final pillBorderPaint = Paint()
        ..color = color.withValues(alpha: 0.25)
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
      canvas.drawCircle(Offset(pillX + 10, avgY), 3, dotPaint);

      // Label text
      textPainter.paint(canvas, Offset(pillX + 18, pillY + (pillH - textPainter.height) / 2));
    }
  }

  void _drawEdge(Canvas canvas, _GraphEdge edge) {
    final fromPos = layout.positions[edge.fromId];
    final toPos = layout.positions[edge.toId];
    if (fromPos == null || toPos == null) return;

    if (edge.type == _EdgeType.spouse) {
      _drawSpouseEdge(canvas, fromPos, toPos);
    } else {
      _drawParentChildEdge(canvas, fromPos, toPos);
    }
  }

  void _drawParentChildEdge(Canvas canvas, Offset parentPos, Offset childPos) {
    final paint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Step-down line: down from parent, horizontal, down to child
    final midY = (parentPos.dy + childPos.dy) / 2;

    final path = Path()
      ..moveTo(parentPos.dx, parentPos.dy + nodeRadius)
      ..lineTo(parentPos.dx, midY)
      ..lineTo(childPos.dx, midY)
      ..lineTo(childPos.dx, childPos.dy - nodeRadius);

    _drawDashedPath(canvas, path, paint);

    // Small arrow dot at child end
    final dotPaint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(childPos.dx, childPos.dy - nodeRadius - 3), 3, dotPaint);
  }

  void _drawSpouseEdge(Canvas canvas, Offset pos1, Offset pos2) {
    final paint = Paint()
      ..color = KinrelColors.amber.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // Horizontal dashed line between spouses
    final path = Path()
      ..moveTo(pos1.dx + nodeRadius + 2, pos1.dy)
      ..lineTo(pos2.dx - nodeRadius - 2, pos2.dy);

    _drawDashedPath(canvas, path, paint);

    // Heart icon at midpoint
    final midX = (pos1.dx + pos2.dx) / 2;
    final midY = (pos1.dy + pos2.dy) / 2;
    _drawHeart(canvas, Offset(midX, midY), 6);
  }

  void _drawHeart(Canvas canvas, Offset center, double size) {
    final paint = Paint()
      ..color = KinrelColors.amber.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    // Simple heart shape using two arcs
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
    final color = _GenColors.forGeneration(node.generation);
    final isAnchor = node.isAnchor;
    final isSelected = node.person.id == selectedNodeId;

    // Apply entry animation: scale + opacity
    final scale = Curves.easeOutBack.transform(entryProgress);
    final opacity = entryProgress;

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(scale);
    canvas.translate(-pos.dx, -pos.dy);

    // ── Anchor glow effect ──────────────────────────────────────
    if (isAnchor) {
      final glowRadius = nodeRadius + 12 + pulseValue * 8;
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            _GenColors.self.withValues(alpha: 0.4 * opacity),
            _GenColors.self.withValues(alpha: 0.1 * opacity),
            Colors.transparent,
          ],
          stops: [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: pos, radius: glowRadius));
      canvas.drawCircle(pos, glowRadius, glowPaint);

      // Pulsing ring
      final ringPaint = Paint()
        ..color = _GenColors.self.withValues(alpha: (0.3 + pulseValue * 0.2) * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(pos, nodeRadius + 6 + pulseValue * 4, ringPaint);
    }

    // ── Node circle ─────────────────────────────────────────────
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.2 * opacity)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = color.withValues(alpha: (isSelected ? 1.0 : 0.6) * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 3.0 : 2.0;

    canvas.drawCircle(pos, nodeRadius, bgPaint);
    canvas.drawCircle(pos, nodeRadius, borderPaint);

    // ── Deceased indicator ──────────────────────────────────────
    if (node.person.isDeceased) {
      final deceasedPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.15 * opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, nodeRadius, deceasedPaint);
    }

    // ── Initials ────────────────────────────────────────────────
    final initialsPainter = TextPainter(
      text: TextSpan(
        text: node.initials,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 16,
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
        pos.dy + nodeRadius + 6,
      ),
    );

    // ── Relationship label ──────────────────────────────────────
    if (node.relationshipLabel != null) {
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
          pos.dy + nodeRadius + 22,
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
