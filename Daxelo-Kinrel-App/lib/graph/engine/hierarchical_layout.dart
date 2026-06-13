// lib/graph/engine/hierarchical_layout.dart
//
// DAXELO KINREL — Hierarchical Layout Engine
//
// Traditional top-down tree layout for 3,000–5,000 nodes.
// Target: 30 FPS at 5,000 nodes.
//
// Design principles:
//   - Generation levels map to horizontal rows (top = oldest ancestors)
//   - Same-generation nodes share the same Y coordinate
//   - Spouses positioned side-by-side on the same level
//   - Siblings ordered left-to-right beneath their parent
//   - Minimal computation — no force simulation, purely algebraic
//   - Maximum readability at scale
//
// The layout is deterministic: same input always produces same output.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/graph_layout_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// HIERARCHICAL LAYOUT CONFIG
// ═══════════════════════════════════════════════════════════════════════

/// Configuration for the [HierarchicalLayout] engine.
class HierarchicalLayoutConfig {
  /// Horizontal spacing between sibling nodes (dp).
  final double siblingSpacing;

  /// Vertical spacing between generation levels (dp).
  final double levelSpacing;

  /// Horizontal gap between spouses (dp).
  final double spouseGap;

  /// Padding around the entire layout (dp).
  final double padding;

  /// Minimum node width used for spacing calculations (dp).
  final double nodeWidth;

  /// Minimum node height used for spacing calculations (dp).
  final double nodeHeight;

  /// Whether to use compact mode (tighter spacing for dense graphs).
  final bool compact;

  const HierarchicalLayoutConfig({
    this.siblingSpacing = 60.0,
    this.levelSpacing = 160.0,
    this.spouseGap = 30.0,
    this.padding = 100.0,
    this.nodeWidth = 100.0,
    this.nodeHeight = 120.0,
    this.compact = false,
  });

  HierarchicalLayoutConfig copyWith({
    double? siblingSpacing,
    double? levelSpacing,
    double? spouseGap,
    double? padding,
    double? nodeWidth,
    double? nodeHeight,
    bool? compact,
  }) {
    return HierarchicalLayoutConfig(
      siblingSpacing: siblingSpacing ?? this.siblingSpacing,
      levelSpacing: levelSpacing ?? this.levelSpacing,
      spouseGap: spouseGap ?? this.spouseGap,
      padding: padding ?? this.padding,
      nodeWidth: nodeWidth ?? this.nodeWidth,
      nodeHeight: nodeHeight ?? this.nodeHeight,
      compact: compact ?? this.compact,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TREE NODE (internal)
// ═══════════════════════════════════════════════════════════════════════

/// Internal tree node used during hierarchical layout computation.
///
/// Tracks the graph person, their subtree width, and children
/// for the top-down positioning pass.
class _TreeNode {
  final GraphPerson person;
  final List<_TreeNode> children = [];
  final List<_TreeNode> spouses = [];

  /// Computed width of this node's subtree (including spouses).
  double subtreeWidth = 0.0;

  /// Assigned x position.
  double x = 0.0;

  /// Assigned y position.
  double y = 0.0;

  _TreeNode(this.person);
}

// ═══════════════════════════════════════════════════════════════════════
// HIERARCHICAL LAYOUT
// ═══════════════════════════════════════════════════════════════════════

/// Hierarchical tree layout engine for family graphs with 3,000–5,000 nodes.
///
/// Computes a traditional top-down tree layout where:
///   - The anchor person's generation is placed at a central level
///   - Ancestors are placed above (ascending generations)
///   - Descendants are placed below (descending generations)
///   - Spouses are positioned side-by-side on the same level
///   - Children are centered beneath their parent(s)
///
/// The layout uses a two-pass algorithm:
///   Pass 1 (bottom-up): Compute subtree widths
///   Pass 2 (top-down): Assign x,y positions based on widths
///
/// Usage:
/// ```dart
/// final layout = HierarchicalLayout();
/// final result = layout.compute(persons: persons, relationships: relationships);
/// ```
class HierarchicalLayout {
  HierarchicalLayoutConfig _config;

  HierarchicalLayout({HierarchicalLayoutConfig? config})
      : _config = config ?? const HierarchicalLayoutConfig();

  /// Current configuration.
  HierarchicalLayoutConfig get config => _config;

  // ── Relationship key sets ─────────────────────────────────────────

  static const Set<String> _spouseKeys = {
    'spouse', 'husband', 'wife', 'partner',
  };

  static const Set<String> _parentKeys = {
    'parent', 'father', 'mother',
    'grandparent', 'grandfather', 'grandmother',
  };

  static const Set<String> _childKeys = {
    'child', 'son', 'daughter', 'grandchild',
  };

  // ── Public API ────────────────────────────────────────────────────

  /// Compute the hierarchical layout for the given graph data.
  ///
  /// Returns a [GraphLayoutResult] with positions, canvas dimensions,
  /// and ring radii (repurposed as level Y-coordinates for compatibility).
  GraphLayoutResult compute({
    required List<GraphPerson> persons,
    required List<GraphRelationship> relationships,
    String? anchorPersonId,
    bool? compact,
  }) {
    if (persons.isEmpty) {
      return const GraphLayoutResult(
        positions: {},
        canvasWidth: 0,
        canvasHeight: 0,
      );
    }

    if (compact != null) {
      _config = _config.copyWith(compact: compact);
    }

    // Auto-compact for large graphs
    if (persons.length > 3000 && !_config.compact) {
      _config = _config.copyWith(compact: true);
    }

    final spacing = _config.compact
        ? _config.siblingSpacing * 0.6
        : _config.siblingSpacing;
    final levelSp = _config.compact
        ? _config.levelSpacing * 0.7
        : _config.levelSpacing;

    // 1. Build lookup maps
    final personById = <String, GraphPerson>{
      for (final p in persons) p.id: p,
    };

    // 2. Build adjacency structures
    final spouseMap = <String, List<String>>{};
    final parentMap = <String, List<String>>{}; // childId → parentIds
    final childMap = <String, List<String>>{}; // parentId → childIds

    for (final r in relationships) {
      if (_spouseKeys.contains(r.relationshipKey)) {
        spouseMap.putIfAbsent(r.fromPersonId, () => []).add(r.toPersonId);
        spouseMap.putIfAbsent(r.toPersonId, () => []).add(r.fromPersonId);
      } else if (_parentKeys.contains(r.relationshipKey)) {
        // toPerson is parent of fromPerson
        parentMap.putIfAbsent(r.fromPersonId, () => []).add(r.toPersonId);
        childMap.putIfAbsent(r.toPersonId, () => []).add(r.fromPersonId);
      } else if (_childKeys.contains(r.relationshipKey)) {
        // toPerson is child of fromPerson
        parentMap.putIfAbsent(r.toPersonId, () => []).add(r.fromPersonId);
        childMap.putIfAbsent(r.fromPersonId, () => []).add(r.toPersonId);
      }
    }

    // 3. Find the anchor
    final anchor = _findAnchor(persons, anchorPersonId);

    // 4. Build tree nodes
    final treeNodeMap = <String, _TreeNode>{};
    for (final person in persons) {
      treeNodeMap[person.id] = _TreeNode(person);
    }

    // 5. Link spouses and children into tree nodes
    for (final person in persons) {
      final node = treeNodeMap[person.id]!;

      // Add spouses
      final spouses = spouseMap[person.id] ?? [];
      for (final spouseId in spouses) {
        final spouseNode = treeNodeMap[spouseId];
        if (spouseNode != null && !node.spouses.contains(spouseNode)) {
          node.spouses.add(spouseNode);
        }
      }

      // Add children (only for the "primary" parent to avoid duplication)
      final children = childMap[person.id] ?? [];
      for (final childId in children) {
        final childNode = treeNodeMap[childId];
        if (childNode != null && !node.children.contains(childNode)) {
          node.children.add(childNode);
        }
      }
    }

    // 6. Group tree roots by generation
    // Find root nodes: those who have no parents in the graph
    final rootNodes = <_TreeNode>[];
    final visited = <String>{};

    // Start from the anchor and walk up to find ultimate ancestors
    _findRoots(treeNodeMap[anchor.id]!, parentMap, treeNodeMap, visited, rootNodes);

    // Add any disconnected persons as roots
    for (final person in persons) {
      if (!visited.contains(person.id)) {
        rootNodes.add(treeNodeMap[person.id]!);
        visited.add(person.id);
      }
    }

    // 7. Compute subtree widths (bottom-up pass)
    final widthVisited = <String>{};
    for (final root in rootNodes) {
      _computeSubtreeWidth(root, spacing, widthVisited);
    }

    // 8. Assign positions (top-down pass)
    final positions = <String, Offset>{};
    final ringRadii = <int, double>{};
    final ringAngleOffsets = <int, double>{};

    // Determine generation range
    final minGen = persons.map((p) => p.generationIndex).reduce(min);
    final maxGen = persons.map((p) => p.generationIndex).reduce(max);

    // Calculate total width needed
    double totalWidth = 0.0;
    for (final root in rootNodes) {
      totalWidth += root.subtreeWidth + spacing;
    }
    totalWidth = max(totalWidth, _config.nodeWidth * 2);

    // Position roots side by side
    var currentX = _config.padding;
    final positionVisited = <String>{};

    for (final root in rootNodes) {
      _assignPositions(
        root,
        currentX + root.subtreeWidth / 2,
        _config.padding + (root.person.generationIndex - minGen) * levelSp,
        levelSp,
        minGen,
        positions,
        positionVisited,
        ringRadii,
        spacing,
      );
      currentX += root.subtreeWidth + spacing;
    }

    // Compute canvas dimensions
    double maxX = 0.0;
    double maxY = 0.0;
    for (final pos in positions.values) {
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }

    final canvasWidth = maxX + _config.padding + _config.nodeWidth;
    final canvasHeight = maxY + _config.padding + _config.nodeHeight;

    // Fill ringRadii with Y positions per generation
    for (var gen = minGen; gen <= maxGen; gen++) {
      ringRadii[gen] = _config.padding + (gen - minGen) * levelSp;
    }

    return GraphLayoutResult(
      positions: positions,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      ringRadii: ringRadii,
      ringAngleOffsets: ringAngleOffsets,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────

  /// Find the anchor person.
  GraphPerson _findAnchor(List<GraphPerson> persons, String? anchorId) {
    if (anchorId != null) {
      final found = persons.where((p) => p.id == anchorId).firstOrNull;
      if (found != null) return found;
    }
    final flagged = persons.where((p) => p.isAnchor).firstOrNull;
    if (flagged != null) return flagged;
    return persons.first;
  }

  /// Walk up the parent chain to find root nodes (ultimate ancestors).
  void _findRoots(
    _TreeNode node,
    Map<String, List<String>> parentMap,
    Map<String, _TreeNode> treeNodeMap,
    Set<String> visited,
    List<_TreeNode> roots,
  ) {
    if (visited.contains(node.person.id)) return;
    visited.add(node.person.id);

    final parents = parentMap[node.person.id] ?? [];
    if (parents.isEmpty) {
      // This is a root
      if (!roots.contains(node)) {
        roots.add(node);
      }
    } else {
      for (final parentId in parents) {
        final parentNode = treeNodeMap[parentId];
        if (parentNode != null) {
          _findRoots(parentNode, parentMap, treeNodeMap, visited, roots);
        }
      }
    }
  }

  /// Compute the subtree width for each node (bottom-up).
  ///
  /// A leaf node's width = nodeWidth + spouseGap * spouseCount.
  /// A parent's width = sum of children widths (with spacing).
  double _computeSubtreeWidth(
    _TreeNode node,
    double spacing,
    Set<String> visited,
  ) {
    if (visited.contains(node.person.id)) {
      return node.subtreeWidth;
    }
    visited.add(node.person.id);

    // Base width: this node + spouses
    final spouseWidth = node.spouses.length * (_config.nodeWidth + _config.spouseGap);
    final ownWidth = _config.nodeWidth + spouseWidth;

    if (node.children.isEmpty) {
      node.subtreeWidth = ownWidth;
      return ownWidth;
    }

    // Sum children widths
    double childrenWidth = 0.0;
    for (final child in node.children) {
      childrenWidth += _computeSubtreeWidth(child, spacing, visited) + spacing;
    }
    childrenWidth = max(0.0, childrenWidth - spacing); // remove trailing space

    node.subtreeWidth = max(ownWidth, childrenWidth);
    return node.subtreeWidth;
  }

  /// Assign x,y positions to each node (top-down).
  void _assignPositions(
    _TreeNode node,
    double centerX,
    double y,
    double levelSpacing,
    int minGen,
    Map<String, Offset> positions,
    Set<String> visited,
    Map<int, double> ringRadii,
    double spacing,
  ) {
    if (visited.contains(node.person.id)) return;
    visited.add(node.person.id);

    // Position this node
    node.x = centerX;
    node.y = y;
    positions[node.person.id] = Offset(centerX, y);

    // Position spouses to the right
    var spouseX = centerX + _config.nodeWidth + _config.spouseGap;
    for (final spouse in node.spouses) {
      if (visited.contains(spouse.person.id)) continue;
      visited.add(spouse.person.id);

      spouse.x = spouseX;
      spouse.y = y;
      positions[spouse.person.id] = Offset(spouseX, y);
      spouseX += _config.nodeWidth + _config.spouseGap;
    }

    // Position children centered below this node
    if (node.children.isEmpty) return;

    final childY = y + levelSpacing;
    double childStartX = centerX - node.subtreeWidth / 2;

    for (final child in node.children) {
      if (visited.contains(child.person.id)) {
        // Still need to advance x for layout consistency
        childStartX += child.subtreeWidth + spacing;
        continue;
      }

      final childCenterX = childStartX + child.subtreeWidth / 2;
      _assignPositions(
        child,
        childCenterX,
        childY,
        levelSpacing,
        minGen,
        positions,
        visited,
        ringRadii,
        spacing,
      );
      childStartX += child.subtreeWidth + spacing;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the [HierarchicalLayout] engine.
final hierarchicalLayoutProvider = Provider<HierarchicalLayout>((ref) {
  return HierarchicalLayout();
});

/// Provider for computing a hierarchical layout result.
final hierarchicalLayoutResultProvider =
    Provider.family<GraphLayoutResult,
        ({List<GraphPerson> persons, List<GraphRelationship> relationships, String? anchorId})>(
  (ref, params) {
    final layout = ref.watch(hierarchicalLayoutProvider);
    return layout.compute(
      persons: params.persons,
      relationships: params.relationships,
      anchorPersonId: params.anchorId,
    );
  },
);
