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
//
// v5.126 (Tree fix): ROOT-FINDING + Y ASSIGNMENT REWRITE
// ------------------------------------------------------
// Two bugs were silently corrupting the layout:
//
//   BUG 1 — FALSE ROOTS:
//     The old root-finder walked UP from the anchor only. Any node NOT
//     visited by that walk (i.e. every descendant of the anchor + every
//     disconnected component) was then "rescued" by a fallback loop and
//     added as a separate root. A family with an anchor at gen 0 and
//     50 descendants would render 50 false root columns at the top row.
//     Symptom: extremely long horizontal connector lines.
//
//     FIX: iterate all persons in one pass; anyone with no parent-edge
//     in the graph is a root. No anchor-based walk, no fallback loop.
//
//   BUG 2 — INCONSISTENT Y:
//     The old Y-assignment used `y = parentY + levelSpacing` recursion
//     (top-down DFS). But roots were initialized with
//     `padding + (root.generationIndex - minGen) * levelSp` — using
//     the stale `Person.generationIndex` database field that's almost
//     always 0 for fresh rows. So roots got one Y, descendants got a
//     different Y incremented per recursion level — and the two systems
//     disagreed on shared nodes (a grandchild reached via two paths got
//     the Y of whichever path the DFS visited first).
//
//     FIX: do a single BFS from ALL roots simultaneously. Each node
//     gets a `bfsGen = parent.bfsGen + 1` exactly once. Spouses inherit
//     their partner's bfsGen if they don't have one yet. Then Y is
//     computed from `bfsGen` directly — no recursion. This is the same
//     BFS strategy `graph_layout_service.dart` already trusts over the
//     stale generationIndex field.
//
// Both fixes use the SAME algorithm pattern as the production radial
// layout, so Tree and Graph agree on what "generation" means.

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
    // v5.127: defaults re-tuned for the new rounded-rect Tree node
    // shape (120×72, 5:3 aspect). The old defaults (60/160/30/100/100×120)
    // were sized for circular nodes — they over-spaced the new cards.
    // Callers that pass explicit configs (e.g. treeLayoutProvider,
    // TreePdfExporter) override these; the defaults are kept sensible
    // for any future caller.
    this.siblingSpacing = 20.0,
    this.levelSpacing = 110.0,
    this.spouseGap = 8.0,
    this.padding = 60.0,
    this.nodeWidth = 120.0,
    this.nodeHeight = 72.0,
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
/// Tracks the graph person, their subtree width, children, spouses,
/// and the BFS-assigned generation number used for Y positioning.
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

  /// v5.126: BFS generation number assigned exactly once during the
  /// single BFS-from-all-roots pass. Roots get bfsGen = 0, their
  /// children get 1, and so on. Spouses inherit their partner's bfsGen
  /// if they don't have one yet. Y is computed from this number — never
  /// from the stale `Person.generationIndex` field.
  int? bfsGen;

  _TreeNode(this.person);
}

// ═══════════════════════════════════════════════════════════════════════
// HIERARCHICAL LAYOUT
// ═══════════════════════════════════════════════════════════════════════

/// Hierarchical tree layout engine for family graphs with 3,000–5,000 nodes.
///
/// Computes a traditional top-down tree layout where:
///   - Roots (persons with no parent-edges) are placed at the top row
///   - Each BFS generation is one horizontal row below the previous
///   - Spouses are positioned side-by-side on the same row
///   - Children are centered beneath their parent(s)
///
/// Three-pass algorithm:
///   Pass 1: One-pass root finding (anyone with no parent-edge is a root).
///   Pass 2: Single BFS from all roots simultaneously → assigns each
///           node a `bfsGen` number. Spouses inherit their partner's
///           bfsGen if they don't have one yet.
///   Pass 3: Bottom-up subtree-width computation + top-down X/Y
///           assignment. Y comes from bfsGen (not from parent's Y).
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

    // ── Step 1: Build lookup maps + adjacency structures ────────────
    final treeNodeMap = <String, _TreeNode>{
      for (final p in persons) p.id: _TreeNode(p),
    };

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

    // Link spouses + children into _TreeNode objects for the X-assignment pass.
    for (final person in persons) {
      final node = treeNodeMap[person.id]!;

      final spouses = spouseMap[person.id] ?? [];
      for (final spouseId in spouses) {
        final spouseNode = treeNodeMap[spouseId];
        if (spouseNode != null && !node.spouses.contains(spouseNode)) {
          node.spouses.add(spouseNode);
        }
      }

      final children = childMap[person.id] ?? [];
      for (final childId in children) {
        final childNode = treeNodeMap[childId];
        if (childNode != null && !node.children.contains(childNode)) {
          node.children.add(childNode);
        }
      }
    }

    // ── Step 2: One-pass root finding ────────────────────────────────
    // v5.126 BUG FIX: the old code walked UP from the anchor and treated
    // any unvisited person as a "disconnected root". This added every
    // descendant of the anchor as a separate root column — creating the
    // "very long lines" symptom the user reported.
    //
    // The fix is one clean pass: a person is a root iff they have no
    // parent-edge in the graph. No anchor walk, no fallback loop.
    final rootNodes = <_TreeNode>[];
    for (final person in persons) {
      final parents = parentMap[person.id];
      if (parents == null || parents.isEmpty) {
        rootNodes.add(treeNodeMap[person.id]!);
      }
    }

    // Edge case: every person has a parent-edge (cycle). Pick the
    // anchor as the sole root to break the cycle deterministically.
    if (rootNodes.isEmpty) {
      final anchor = _findAnchor(persons, anchorPersonId);
      rootNodes.add(treeNodeMap[anchor.id]!);
    }

    // ── Step 3: Single BFS from ALL roots simultaneously ────────────
    // v5.126 BUG FIX: Y used to be assigned via `childY = y + levelSp`
    // recursion, but roots were initialized with a Y derived from the
    // STALE `Person.generationIndex` DB field. The two systems
    // disagreed on shared nodes — a node reachable via two paths got
    // the Y of whichever path the DFS visited first.
    //
    // The fix: BFS from all roots simultaneously, assign each node a
    // `bfsGen` exactly once. Spouses inherit their partner's bfsGen if
    // they don't have one yet. Y is then computed from bfsGen directly.
    _assignBfsGenerations(rootNodes, treeNodeMap, spouseMap, childMap);

    // Determine BFS generation range (used for Y computation + ringRadii)
    int minBfsGen = 1 << 30;
    int maxBfsGen = -(1 << 30);
    for (final node in treeNodeMap.values) {
      final g = node.bfsGen;
      if (g == null) continue; // unreachable — left at default Y
      if (g < minBfsGen) minBfsGen = g;
      if (g > maxBfsGen) maxBfsGen = g;
    }
    // If every node was unreachable (no BFS reached them), fall back
    // to gen 0 so the Y computation doesn't blow up.
    if (minBfsGen > maxBfsGen) {
      minBfsGen = 0;
      maxBfsGen = 0;
    }

    // ── Step 4: Bottom-up subtree width computation ─────────────────
    final widthVisited = <String>{};
    for (final root in rootNodes) {
      _computeSubtreeWidth(root, spacing, widthVisited);
    }

    // ── Step 5: Top-down X + Y assignment ───────────────────────────
    // X comes from the subtree-width recursion (per-root side-by-side).
    // Y comes from bfsGen directly — NO `y + levelSp` recursion.
    final positions = <String, Offset>{};
    final ringRadii = <int, double>{};
    final ringAngleOffsets = <int, double>{};

    var currentX = _config.padding;
    final positionVisited = <String>{};

    for (final root in rootNodes) {
      // Root Y = padding + (0 - 0) * levelSp = padding (top of canvas).
      // Children get Y = padding + (bfsGen - minBfsGen) * levelSp.
      final rootY = _yForBfsGen(root.bfsGen ?? 0, minBfsGen, levelSp);
      _assignPositions(
        root,
        currentX + root.subtreeWidth / 2,
        rootY,
        positions,
        positionVisited,
        spacing,
        minBfsGen,
        levelSp,
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

    // Fill ringRadii with Y positions per BFS generation (1-indexed
    // offset from minBfsGen). Consumers (e.g. camera focus) use this
    // to know each row's Y without re-running the layout.
    for (var gen = minBfsGen; gen <= maxBfsGen; gen++) {
      ringRadii[gen] = _yForBfsGen(gen, minBfsGen, levelSp);
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

  /// Y coordinate for a node with the given BFS generation.
  ///
  /// v5.126: Y comes from bfsGen directly — NOT from `parentY + levelSp`
  /// recursion. This eliminates the inconsistency between roots (which
  /// previously used the stale generationIndex field) and descendants
  /// (which previously used parent's Y + levelSp).
  double _yForBfsGen(int bfsGen, int minBfsGen, double levelSp) {
    return _config.padding + (bfsGen - minBfsGen) * levelSp;
  }

  /// Single BFS from all roots simultaneously.
  ///
  /// - Each root gets `bfsGen = 0`.
  /// - Each unvisited child gets `bfsGen = parent.bfsGen + 1`.
  /// - Each unvisited spouse inherits their partner's `bfsGen` (so
  ///   spouses land on the same row — they're at the "same generation"
  ///   in the visual tree even if the kinship dataset disagrees).
  ///
  /// Uses an explicit queue (no recursion — survives 5,000-node chains
  /// without stack overflow). A node is visited exactly once; if a
  /// second path reaches it, the BFS skips it. This is what makes Y
  /// assignment consistent regardless of which path found the node
  /// first.
  void _assignBfsGenerations(
    List<_TreeNode> roots,
    Map<String, _TreeNode> treeNodeMap,
    Map<String, List<String>> spouseMap,
    Map<String, List<String>> childMap,
  ) {
    final queue = List<_TreeNode>.of(roots);
    for (final root in roots) {
      root.bfsGen = 0;
    }

    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);

      // Spouses inherit this node's bfsGen (and we still queue them so
      // THEIR spouses/children get visited too).
      final spouseIds = spouseMap[node.person.id] ?? [];
      for (final spouseId in spouseIds) {
        final spouseNode = treeNodeMap[spouseId];
        if (spouseNode == null) continue;
        if (spouseNode.bfsGen == null) {
          spouseNode.bfsGen = node.bfsGen;
          queue.add(spouseNode);
        }
      }

      // Children get parent.bfsGen + 1.
      final childIds = childMap[node.person.id] ?? [];
      for (final childId in childIds) {
        final childNode = treeNodeMap[childId];
        if (childNode == null) continue;
        if (childNode.bfsGen == null) {
          childNode.bfsGen = (node.bfsGen ?? 0) + 1;
          queue.add(childNode);
        }
      }
    }
  }

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
  ///
  /// v5.126: Y comes from `bfsGen` (looked up via _yForBfsGen), NOT
  /// from `parentY + levelSpacing`. This eliminates the inconsistency
  /// between roots (which used the stale generationIndex) and descendants
  /// (which used parent Y + levelSpacing).
  void _assignPositions(
    _TreeNode node,
    double centerX,
    double rootY,
    Map<String, Offset> positions,
    Set<String> visited,
    double spacing,
    int minBfsGen,
    double levelSp,
  ) {
    if (visited.contains(node.person.id)) return;
    visited.add(node.person.id);

    // Y from BFS gen — single source of truth.
    final y = _yForBfsGen(node.bfsGen ?? 0, minBfsGen, levelSp);

    node.x = centerX;
    node.y = y;
    positions[node.person.id] = Offset(centerX, y);

    // Position spouses to the right (same Y).
    var spouseX = centerX + _config.nodeWidth + _config.spouseGap;
    for (final spouse in node.spouses) {
      if (visited.contains(spouse.person.id)) continue;
      visited.add(spouse.person.id);

      spouse.x = spouseX;
      spouse.y = y;
      positions[spouse.person.id] = Offset(spouseX, y);
      spouseX += _config.nodeWidth + _config.spouseGap;
    }

    // Position children centered below this node. X uses the
    // subtree-width recursion (per-root side-by-side). Y for each
    // child comes from their own bfsGen via _yForBfsGen.
    if (node.children.isEmpty) return;

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
        // rootY param is now unused for Y computation — kept for
        // API stability. Each node computes its own Y from bfsGen.
        y,
        positions,
        visited,
        spacing,
        minBfsGen,
        levelSp,
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
