// lib/graph/engine/hierarchical_layout.dart
//
// DAXELO KINREL — Hierarchical Layout Engine
//
// Traditional top-down tree layout for 3,000–10,000+ nodes.
// Target: 30 FPS at 5,000 nodes; 60 FPS at 10,000 with viewport culling
// (handled by the view, not this engine — the engine itself is O(V+E)).
//
// Design principles:
//   - Generation levels map to horizontal rows (top = oldest ancestors)
//   - Same-generation nodes share the same Y coordinate
//   - Couples (married partners) are ONE positioning unit — children
//     center under the couple's midpoint, not under one individual.
//   - Siblings ordered left-to-right beneath their parent(s), sorted
//     by birth date then id for determinism.
//   - Minimal computation — no force simulation, purely algebraic
//   - Maximum readability at scale
//
// The layout is deterministic: same input always produces same output.
//
// v5.128 (Tree layout correctness): COUPLES + SIBLING ORDER + DEEPER-OF-TWO
// -----------------------------------------------------------------------
// Three correctness fixes per the "Tree View — Layout Engine Fix &
// Scale Implementation Prompt":
//
//   §2.3 COUPLES AS ATOMIC UNIT:
//     Previously, spouses were positioned side-by-side AFTER the primary
//     node was placed, but children were centered under the PRIMARY only.
//     Now: children center under the COUPLE's midpoint (primary + first
//     spouse). Multi-spouse rule: only the FIRST spouse forms the primary
//     couple (children center under them); additional spouses are positioned
//     beside with a visually distinct (dashed) connector — exposed via
//     `secondarySpouseIds` on the layout result so the painter can render
//     them differently.
//
//   §2.4 SIBLING ORDERING (DETERMINISTIC):
//     Previously, `node.children` populated in whatever order childMap
//     iterated — non-deterministic across app sessions. Now: sort
//     siblings by `birthDate` ascending (nulls last), then by `id`
//     ascending as the final tiebreak. Adding a new person to a family
//     never reshuffles existing siblings' left-right order.
//
//   §2.5 COUSIN MARRIAGE TIE-BREAK (DEEPER-OF-TWO):
//     Previously, BFS used "first-write-wins" — whichever path reached
//     a node first set its gen. For cousin marriages (two people from
//     different lineages marry, their descendants can be reached via two
//     paths at different depths), this gave inconsistent gens depending
//     on traversal order. Now: iterative max-propagation — gen =
//     max(parents.gen) + 1, with multiple passes until stable. Spouses
//     also take the max of both partners' lineages (the couple "floats
//     up" to the deeper of the two).
//
// v5.126 (prior fix, kept): ROOT-FINDING + Y ASSIGNMENT REWRITE
// -------------------------------------------------------------
//   §2.1 ONE-PASS ROOT FINDING: a person is a root iff they have no
//     parent-edge in the graph. No anchor walk, no fallback loop.
//
//   §2.2 Y FROM BFS GEN: Y = padding + (bfsGen - minBfsGen) * levelSp.
//     No `y = parentY + levelSp` recursion. Single source of truth.

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
  ///
  /// v5.128: With the deeper-of-two rule, bfsGen may be updated multiple
  /// times during iterative max-propagation. The final value is the
  /// deepest gen reachable via any path from any root.
  int? bfsGen;

  /// v5.128 §2.3: True if this node is a SECONDARY spouse (index >= 1
  /// in their partner's spouses list). The painter renders secondary
  /// spouse edges with a dashed connector to distinguish them from
  /// the primary couple.
  bool isSecondarySpouse = false;

  _TreeNode(this.person);
}

// ═══════════════════════════════════════════════════════════════════════
// HIERARCHICAL LAYOUT
// ═══════════════════════════════════════════════════════════════════════

/// Hierarchical tree layout engine for family graphs with 3,000–10,000+ nodes.
///
/// Algorithm (v5.128):
///   Pass 1: One-pass root finding — anyone with no parent-edge is a root.
///   Pass 2: Iterative max-propagation BFS — assigns each node a `bfsGen`
///           that's the MAX of (parents.gen + 1) across all paths. Handles
///           cousin marriages correctly (deeper-of-two rule, §2.5).
///           Spouses take the max of both partners' lineages.
///   Pass 3: Sort siblings by birthDate asc, then id asc (§2.4).
///   Pass 4: Bottom-up subtree-width computation (couples as one unit, §2.3).
///   Pass 5: Top-down X + Y assignment. Y from bfsGen; X centered under
///           the couple's midpoint (primary + first spouse), not the
///           primary alone.
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

  /// v5.129: Sibling labels — when labelAtoB is one of these, the edge
  /// connects two people at the SAME generation (not parent→child).
  /// The DB stores ALL non-spouse edges as `relationshipKey='parent'`
  /// (due to the `relationship_fundamental_edge_check` constraint), so
  /// the layout engine MUST check `labelAtoB` to distinguish siblings
  /// from actual parent-child edges.
  ///
  /// Without this check, a "brother" edge (relationshipKey='parent',
  /// labelAtoB='brother') would be treated as a parent-child edge and
  /// place the brother one generation below — the exact "disconnected/
  /// misplaced people" bug the user reported.
  static const Set<String> _siblingLabels = {
    'brother', 'sister', 'sibling',
    'elder_brother', 'elder_sister',
    'younger_brother', 'younger_sister',
    'step_brother', 'step_sister',
    'half_brother', 'half_sister',
  };

  /// v5.129: Returns true if this edge is a sibling edge (same-generation),
  /// detected via labelAtoB. Falls back to relationshipKey if labelAtoB
  /// is null (for backward compat with edges that don't have labelAtoB set).
  bool _isSiblingEdge(GraphRelationship r) {
    final label = (r.labelAtoB ?? r.relationshipKey).toLowerCase();
    return _siblingLabels.contains(label);
  }

  // ── Public API ────────────────────────────────────────────────────

  /// Compute the hierarchical layout for the given graph data.
  ///
  /// Returns a [GraphLayoutResult] with positions, canvas dimensions,
  /// and ring radii (repurposed as level Y-coordinates for compatibility).
  ///
  /// [secondarySpouseIds] (output parameter, populated by this method)
  /// contains the IDs of all spouses beyond the first for each couple —
  /// the painter should render their edges with a dashed connector.
  GraphLayoutResult compute({
    required List<GraphPerson> persons,
    required List<GraphRelationship> relationships,
    String? anchorPersonId,
    bool? compact,
    Set<String>? secondarySpouseIds,
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
    final siblingMap = <String, List<String>>{}; // personId → siblingIds (v5.129)

    for (final r in relationships) {
      if (_isSiblingEdge(r)) {
        // v5.129: Sibling edges connect same-generation people.
        // DON'T treat as parent-child — add to siblingMap instead.
        siblingMap.putIfAbsent(r.fromPersonId, () => []).add(r.toPersonId);
        siblingMap.putIfAbsent(r.toPersonId, () => []).add(r.fromPersonId);
      } else if (_spouseKeys.contains(r.relationshipKey)) {
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
    // v5.128 §2.4: children + spouses are SORTED deterministically here so
    // downstream passes don't need to re-sort.
    for (final person in persons) {
      final node = treeNodeMap[person.id]!;

      // Spouses — sort by birthDate asc (nulls last), then id asc.
      // The FIRST spouse in this sorted list is the "primary spouse" —
      // they form the couple unit with this node for child centering (§2.3).
      final spouseIds = spouseMap[person.id] ?? [];
      final sortedSpouseNodes = <_TreeNode>[];
      for (final spouseId in spouseIds) {
        final spouseNode = treeNodeMap[spouseId];
        if (spouseNode != null) {
          sortedSpouseNodes.add(spouseNode);
        }
      }
      sortedSpouseNodes.sort(_siblingSortComparator);
      // Deduplicate (a spouse edge stored bidirectionally could double-add).
      for (final spouseNode in sortedSpouseNodes) {
        if (!node.spouses.contains(spouseNode)) {
          node.spouses.add(spouseNode);
        }
      }

      // Children — sort by birthDate asc (nulls last), then id asc.
      // This determines left-to-right order beneath the parent.
      final childIds = childMap[person.id] ?? [];
      final sortedChildNodes = <_TreeNode>[];
      for (final childId in childIds) {
        final childNode = treeNodeMap[childId];
        if (childNode != null) {
          sortedChildNodes.add(childNode);
        }
      }
      sortedChildNodes.sort(_siblingSortComparator);
      for (final childNode in sortedChildNodes) {
        if (!node.children.contains(childNode)) {
          node.children.add(childNode);
        }
      }
    }

    // v5.128 §2.3: Mark secondary spouses (index >= 1) for the painter.
    // The first spouse forms the primary couple; additional spouses get
    // a dashed connector.
    final secondarySpouses = secondarySpouseIds ?? <String>{};
    for (final node in treeNodeMap.values) {
      for (var i = 1; i < node.spouses.length; i++) {
        final spouse = node.spouses[i];
        spouse.isSecondarySpouse = true;
        secondarySpouses.add(spouse.person.id);
      }
    }

    // ── Step 2: One-pass root finding ────────────────────────────────
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

    // ── Step 3: Iterative max-propagation BFS (deeper-of-two rule) ────
    // v5.128 §2.5: For cousin marriages, a node can be reached via two
    // paths at different depths. The "deeper-of-two" rule says: take
    // the MAX gen across all paths. This requires iterative propagation
    // until no changes (Bellman-Ford-style longest path).
    _assignBfsGenerationsDeeperOfTwo(rootNodes, treeNodeMap, parentMap, siblingMap);

    // Determine BFS generation range (used for Y computation + ringRadii)
    int minBfsGen = 1 << 30;
    int maxBfsGen = -(1 << 30);
    for (final node in treeNodeMap.values) {
      final g = node.bfsGen;
      if (g == null) continue; // unreachable — left at default Y
      if (g < minBfsGen) minBfsGen = g;
      if (g > maxBfsGen) maxBfsGen = g;
    }
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
    // v5.128 §2.3: children center under the COUPLE's midpoint
    // (primary + first spouse), not under the primary alone.
    final positions = <String, Offset>{};
    final ringRadii = <int, double>{};
    final ringAngleOffsets = <int, double>{};

    var currentX = _config.padding;
    final positionVisited = <String>{};

    for (final root in rootNodes) {
      // v5.128: Skip roots already visited as a spouse of another root
      // (couples share a row — only one of them is the layout "root").
      if (positionVisited.contains(root.person.id)) {
        continue;
      }
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

    // Fill ringRadii with Y positions per BFS generation.
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

  /// v5.128 §2.4: Sibling/spouse sort comparator.
  ///
  /// Sort by:
  ///   1. birthDate ascending (nulls last) — oldest first
  ///   2. id ascending (string compare) — stable tiebreak
  ///
  /// This must be deterministic across app sessions and across re-layouts
  /// so adding a new person doesn't reshuffle existing siblings.
  int _siblingSortComparator(_TreeNode a, _TreeNode b) {
    final bdA = a.person.birthDate;
    final bdB = b.person.birthDate;
    if (bdA != null && bdB != null) {
      final cmp = bdA.compareTo(bdB);
      if (cmp != 0) return cmp;
    } else if (bdA != null && bdB == null) {
      return -1; // A has birthDate → comes first
    } else if (bdA == null && bdB != null) {
      return 1; // B has birthDate → comes first
    }
    // Both null OR same birthDate → id tiebreak.
    return a.person.id.compareTo(b.person.id);
  }

  /// Y coordinate for a node with the given BFS generation.
  double _yForBfsGen(int bfsGen, int minBfsGen, double levelSp) {
    return _config.padding + (bfsGen - minBfsGen) * levelSp;
  }

  /// v5.128 §2.5: Iterative max-propagation BFS.
  ///
  /// For each node: gen = max(parents.gen) + 1, or 0 if no parents.
  /// For each couple: both partners take max(genA, genB).
  ///
  /// Iterates until no changes (handles cousin marriages correctly —
  /// a node reachable via two paths at different depths gets the deeper
  /// gen, propagated consistently to descendants).
  ///
  /// Uses an iterative fixpoint algorithm (Bellman-Ford longest path)
  /// with a safety cap on iterations to prevent infinite loops on cycles.
  /// For typical family data with sparse cousin-marriage cycles, this
  /// converges in 3-5 iterations.
  void _assignBfsGenerationsDeeperOfTwo(
    List<_TreeNode> roots,
    Map<String, _TreeNode> treeNodeMap,
    Map<String, List<String>> parentMap,
    Map<String, List<String>> siblingMap,
  ) {
    // Initialize roots
    for (final root in roots) {
      root.bfsGen = 0;
    }

    // Iterate until stable. Safety cap: 100 iterations (more than enough
    // for any realistic family graph — even a 100-generation chain
    // converges in 100 passes).
    var changed = true;
    var iterations = 0;
    const maxIterations = 100;
    while (changed && iterations < maxIterations) {
      changed = false;
      iterations++;

      // Parent → child propagation: child.gen = max(parents.gen) + 1
      for (final entry in treeNodeMap.entries) {
        final node = entry.value;
        final parentIds = parentMap[node.person.id];
        if (parentIds == null || parentIds.isEmpty) {
          // Root — stays 0 (already set above)
          if (node.bfsGen != 0) {
            node.bfsGen = 0;
            changed = true;
          }
          continue;
        }
        int maxParentGen = -1;
        for (final pid in parentIds) {
          final p = treeNodeMap[pid];
          if (p?.bfsGen != null && p!.bfsGen! > maxParentGen) {
            maxParentGen = p.bfsGen!;
          }
        }
        if (maxParentGen >= 0) {
          final newGen = maxParentGen + 1;
          if (node.bfsGen == null || newGen > node.bfsGen!) {
            node.bfsGen = newGen;
            changed = true;
          }
        }
      }

      // Spouse propagation: couples take max of both partners' lineages.
      for (final node in treeNodeMap.values) {
        if (node.bfsGen == null) continue;
        for (final spouse in node.spouses) {
          if (spouse.bfsGen == null) continue;
          final maxGen = node.bfsGen! > spouse.bfsGen!
              ? node.bfsGen!
              : spouse.bfsGen!;
          if (node.bfsGen != maxGen) {
            node.bfsGen = maxGen;
            changed = true;
          }
          if (spouse.bfsGen != maxGen) {
            spouse.bfsGen = maxGen;
            changed = true;
          }
        }
      }

      // v5.129: Sibling propagation — siblings take the SAME gen as
      // each other (max of both). This is the key fix for siblings
      // stored as relationshipKey='parent' with labelAtoB='brother'.
      // Without this, a sibling edge would be treated as parent→child
      // and place the sibling one generation below.
      for (final node in treeNodeMap.values) {
        if (node.bfsGen == null) continue;
        final sibIds = siblingMap[node.person.id];
        if (sibIds == null || sibIds.isEmpty) continue;
        for (final sibId in sibIds) {
          final sib = treeNodeMap[sibId];
          if (sib == null) continue;
          if (sib.bfsGen == null) {
            sib.bfsGen = node.bfsGen;
            changed = true;
          } else {
            final maxGen = node.bfsGen! > sib.bfsGen!
                ? node.bfsGen!
                : sib.bfsGen!;
            if (node.bfsGen != maxGen) {
              node.bfsGen = maxGen;
              changed = true;
            }
            if (sib.bfsGen != maxGen) {
              sib.bfsGen = maxGen;
              changed = true;
            }
          }
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
  /// v5.128 §2.3: The subtree width INCLUDES all spouses (primary +
  /// secondary) — they're part of the same horizontal unit. Children
  /// centering (in _assignPositions) uses this width but centers under
  /// the primary couple's midpoint only.
  double _computeSubtreeWidth(
    _TreeNode node,
    double spacing,
    Set<String> visited,
  ) {
    if (visited.contains(node.person.id)) {
      return node.subtreeWidth;
    }
    visited.add(node.person.id);

    // Base width: this node + ALL spouses (primary + secondary).
    // The couple is one horizontal unit; children center under the
    // primary couple's midpoint (handled in _assignPositions).
    final spouseCount = node.spouses.length;
    final spouseWidth = spouseCount * (_config.nodeWidth + _config.spouseGap);
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
  /// v5.128 §2.3: Children center under the COUPLE's midpoint (primary +
  /// first spouse), not under the primary alone. This is the key change
  /// that makes children visually belong to BOTH parents, not just one.
  ///
  /// Y comes from `bfsGen` (looked up via _yForBfsGen).
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

    // v5.128 §2.3: Compute the couple's midpoint.
    // Primary is at `centerX`. First spouse (index 0) is at
    //   centerX + (nodeWidth + spouseGap)
    // Couple midpoint = (primary center + first spouse center) / 2
    //   = centerX + (nodeWidth + spouseGap) / 2
    // If no spouses, couple midpoint = primary center (unchanged behavior).
    final hasSpouses = node.spouses.isNotEmpty;
    final coupleMidpointX = hasSpouses
        ? centerX + (_config.nodeWidth + _config.spouseGap) / 2
        : centerX;

    // Position spouses to the right (same Y).
    // v5.128 §2.3: ALL spouses (primary + secondary) get positioned
    // to the right of the primary. The painter renders secondary
    // spouses (index >= 1) with a dashed connector.
    var spouseX = centerX + _config.nodeWidth + _config.spouseGap;
    for (final spouse in node.spouses) {
      if (visited.contains(spouse.person.id)) continue;
      visited.add(spouse.person.id);

      spouse.x = spouseX;
      spouse.y = y;
      positions[spouse.person.id] = Offset(spouseX, y);
      spouseX += _config.nodeWidth + _config.spouseGap;
    }

    // Position children centered under the COUPLE's midpoint (§2.3).
    if (node.children.isEmpty) return;

    double childStartX = coupleMidpointX - node.subtreeWidth / 2;

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
        y, // unused for Y computation — kept for API stability
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
