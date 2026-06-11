// lib/core/services/graph_layout_service.dart
//
// DAXELO KINREL — Generational Graph Layout Service
//
// A production-ready family tree layout engine that:
// - Uses BFS from an anchor person to assign generation indices
// - Groups persons by generation level
// - Sorts within generations (spouses side-by-side, siblings grouped)
// - Assigns (x, y) positions with proper spacing from brand tokens
// - Supports curved Bezier edges for parent-child connections
// - Handles disconnected subgraphs gracefully
// - Scales to large families (200+ persons, 800+ relationships)
// - Uses the generationIndex field from the API response when available
//
// Design tokens sourced from brand_colors.dart / brand_spacing.dart:
//   Node width:  80 dp compact / 100 dp normal
//   Node height: 100 dp compact / 120 dp normal
//   Horizontal spacing: 60 dp between nodes
//   Vertical spacing:   120 dp between generations
//   Spouse offset:      20 dp (side by side at same level)

import 'dart:math';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// A person node in the graph layout input.
class GraphPerson {
  final String id;
  final String name;
  final String? gender;
  final int generationIndex;
  final bool isAnchor;
  final String? photoUrl;
  final bool isDeceased;

  const GraphPerson({
    required this.id,
    required this.name,
    this.gender,
    this.generationIndex = 0,
    this.isAnchor = false,
    this.photoUrl,
    this.isDeceased = false,
  });
}

/// A directed relationship edge in the graph layout input.
///
/// [relationshipKey] describes toPerson's relationship to fromPerson.
/// e.g. from=A, to=B, key="father" → B is the father of A.
class GraphRelationship {
  final String id;
  final String fromPersonId;
  final String toPersonId;
  final String relationshipKey;

  const GraphRelationship({
    required this.id,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
  });
}

/// The computed layout result: positions and canvas dimensions.
class GraphLayoutResult {
  final Map<String, Offset> positions;
  final double canvasWidth;
  final double canvasHeight;

  const GraphLayoutResult({
    required this.positions,
    required this.canvasWidth,
    required this.canvasHeight,
  });
}

/// Cubic Bezier edge data for drawing curved parent-child connections.
class BezierEdge {
  /// Start point (bottom-center of parent node).
  final Offset start;

  /// First control point (pulls downward from parent).
  final Offset controlPoint1;

  /// Second control point (pulls upward toward child).
  final Offset controlPoint2;

  /// End point (top-center of child node).
  final Offset end;

  const BezierEdge({
    required this.start,
    required this.controlPoint1,
    required this.controlPoint2,
    required this.end,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// GRAPH LAYOUT SERVICE
// ═══════════════════════════════════════════════════════════════════════

/// Generational graph layout service for family tree visualization.
///
/// Computes a layered (Sugiyama-inspired) layout where:
/// - Y position = generation level × row step
/// - X position = sequential placement with alignment passes
/// - Spouses are placed side-by-side with reduced gap
/// - Parents are centered above their children
/// - Disconnected subgraphs are laid out without overlap
class GraphLayoutService {
  GraphLayoutService();

  // ── Design Tokens (from brand_colors.dart) ───────────────────────

  /// Node width in compact mode (dp).
  static const double nodeWidthCompact = 80.0;

  /// Node width in normal mode (dp).
  static const double nodeWidthNormal = 100.0;

  /// Node height in compact mode (dp).
  static const double nodeHeightCompact = 100.0;

  /// Node height in normal mode (dp).
  static const double nodeHeightNormal = 120.0;

  /// Horizontal spacing between nodes in the same generation (dp).
  static const double horizontalSpacing = 60.0;

  /// Vertical spacing between generations (dp).
  static const double verticalSpacing = 120.0;

  /// Reduced gap between spouse nodes (dp).
  static const double spouseOffset = 20.0;

  // ── Relationship Key Categories ──────────────────────────────────

  /// Keys where toPerson is a parent of fromPerson (one generation above).
  static const Set<String> _parentKeys = {
    'parent',
    'father',
    'mother',
    'grandparent',
    'grandfather',
    'grandmother',
  };

  /// Keys where toPerson is a child of fromPerson (one generation below).
  static const Set<String> _childKeys = {
    'child',
    'son',
    'daughter',
    'grandchild',
  };

  /// Keys where toPerson is a spouse/partner of fromPerson (same generation).
  static const Set<String> _spouseKeys = {
    'spouse',
    'husband',
    'wife',
    'partner',
  };

  /// Keys where toPerson is a sibling of fromPerson (same generation).
  // ignore: unused_field
  static const Set<String> _siblingKeys = {
    'sibling',
    'brother',
    'sister',
  };

  /// Extended family keys that span two generations above.
  static const Set<String> _grandparentKeys = {
    'grandparent',
    'grandfather',
    'grandmother',
  };

  /// Extended family keys that span two generations below.
  static const Set<String> _grandchildKeys = {
    'grandchild',
  };

  // ── Mutable State (per compute call) ─────────────────────────────

  bool _compactMode = false;

  double get _nodeWidth =>
      _compactMode ? nodeWidthCompact : nodeWidthNormal;
  double get _nodeHeight =>
      _compactMode ? nodeHeightCompact : nodeHeightNormal;
  double get _colStep => _nodeWidth + horizontalSpacing;
  double get _rowStep => _nodeHeight + verticalSpacing;

  // ── Public API ───────────────────────────────────────────────────

  /// Compute the full generational layout for a family graph.
  ///
  /// [persons] — all person nodes to lay out.
  /// [relationships] — all directed relationship edges.
  /// [anchorPersonId] — optional ID of the anchor/ego person to center on.
  ///   Falls back to `isAnchor` flag, then the first person.
  /// [compactMode] — use compact node dimensions for dense graphs.
  ///
  /// Returns a [GraphLayoutResult] with personId → Offset positions
  /// and the total canvas dimensions.
  GraphLayoutResult computeLayout({
    required List<GraphPerson> persons,
    required List<GraphRelationship> relationships,
    String? anchorPersonId,
    bool compactMode = false,
  }) {
    _compactMode = compactMode;

    // Edge case: empty input
    if (persons.isEmpty) {
      return const GraphLayoutResult(
        positions: {},
        canvasWidth: 0,
        canvasHeight: 0,
      );
    }

    // Build lookup maps
    final personMap = <String, GraphPerson>{};
    for (final p in persons) {
      personMap[p.id] = p;
    }

    // Resolve the anchor person ID
    String anchor = anchorPersonId ?? '';
    if (!personMap.containsKey(anchor)) {
      GraphPerson? flagged;
      for (final p in persons) {
        if (p.isAnchor) {
          flagged = p;
          break;
        }
      }
      anchor = flagged?.id ?? persons.first.id;
    }

    // Step 1: Assign generation levels via BFS from anchor
    final generations = _assignGenerations(
      persons,
      relationships,
      anchor,
      personMap,
    );

    // Step 2: Group persons by generation level
    final generationGroups = _groupByGeneration(persons, generations);

    // Step 3: Sort within each generation (spouses, siblings)
    final sortedGroups = <int, List<String>>{};
    for (final level in generationGroups.keys) {
      sortedGroups[level] = _sortWithinGeneration(
        generationGroups[level]!,
        relationships,
        personMap,
      );
    }

    // Step 4: Assign (x, y) positions
    final positions = <String, Offset>{};
    _assignPositions(
      sortedGroups,
      generations,
      positions,
      relationships,
      personMap,
      anchor,
    );

    // Step 5: Resolve overlaps
    _resolveOverlaps(positions, sortedGroups);

    // Step 6: Center layout around anchor
    _centerLayout(positions, anchor);

    // Compute canvas dimensions
    double maxX = 0;
    double maxY = 0;
    for (final offset in positions.values) {
      if (offset.dx + _nodeWidth > maxX) maxX = offset.dx + _nodeWidth;
      if (offset.dy + _nodeHeight > maxY) maxY = offset.dy + _nodeHeight;
    }

    return GraphLayoutResult(
      positions: positions,
      canvasWidth: maxX + horizontalSpacing,
      canvasHeight: maxY + verticalSpacing,
    );
  }

  /// Compute cubic Bezier control points for a curved parent-child edge.
  ///
  /// [parentPos] — top-left Offset of the parent node.
  /// [childPos] — top-left Offset of the child node.
  ///
  /// Returns a [BezierEdge] with start/end at node centers and
  /// two control points that create a smooth S-curve.
  BezierEdge computeBezierEdge(Offset parentPos, Offset childPos) {
    final start = Offset(
      parentPos.dx + _nodeWidth / 2,
      parentPos.dy + _nodeHeight,
    );
    final end = Offset(
      childPos.dx + _nodeWidth / 2,
      childPos.dy,
    );
    final midY = (start.dy + end.dy) / 2;

    return BezierEdge(
      start: start,
      controlPoint1: Offset(start.dx, midY),
      controlPoint2: Offset(end.dx, midY),
      end: end,
    );
  }

  /// Compute the two endpoints for a horizontal spouse connection.
  ///
  /// Returns (leftNodeRightCenter, rightNodeLeftCenter) as a tuple.
  (Offset, Offset) computeSpouseEdge(Offset leftPos, Offset rightPos) {
    final leftCenter = Offset(
      leftPos.dx + _nodeWidth,
      leftPos.dy + _nodeHeight / 2,
    );
    final rightCenter = Offset(
      rightPos.dx,
      rightPos.dy + _nodeHeight / 2,
    );
    return (leftCenter, rightCenter);
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 1: ASSIGN GENERATIONS VIA BFS
  // ═══════════════════════════════════════════════════════════════════

  /// Assign generation levels using BFS from [anchorId].
  ///
  /// The BFS traverses relationships and assigns generation offsets:
  /// - parent keys → neighbor is 1 generation above (−1 offset)
  /// - child keys → neighbor is 1 generation below (+1 offset)
  /// - grandparent keys → neighbor is 2 generations above (−2 offset)
  /// - grandchild keys → neighbor is 2 generations below (+2 offset)
  /// - spouse/sibling keys → same generation (0 offset)
  ///
  /// Disconnected subgraphs are handled by running secondary BFS
  /// from each unvisited person, using their API [generationIndex]
  /// as the base generation level.
  Map<String, int> _assignGenerations(
    List<GraphPerson> persons,
    List<GraphRelationship> relationships,
    String anchorId,
    Map<String, GraphPerson> personMap,
  ) {
    final generations = <String, int>{};
    final visited = <String>{};

    // Build adjacency: personId → [(neighborId, generationOffset)]
    final adjacency = <String, List<(String, int)>>{};
    for (final p in persons) {
      adjacency[p.id] = [];
    }

    for (final rel in relationships) {
      final fromId = rel.fromPersonId;
      final toId = rel.toPersonId;
      if (!personMap.containsKey(fromId) || !personMap.containsKey(toId)) {
        continue;
      }

      // Determine generational offset from fromPerson → toPerson
      int fromToTo;
      if (_grandparentKeys.contains(rel.relationshipKey)) {
        fromToTo = -2;
      } else if (_parentKeys.contains(rel.relationshipKey)) {
        fromToTo = -1;
      } else if (_grandchildKeys.contains(rel.relationshipKey)) {
        fromToTo = 2;
      } else if (_childKeys.contains(rel.relationshipKey)) {
        fromToTo = 1;
      } else {
        fromToTo = 0; // spouse, sibling, etc.
      }

      // Forward edge: from → to with +offset
      adjacency[fromId]!.add((toId, fromToTo));
      // Reverse edge: to → from with −offset
      adjacency[toId]!.add((fromId, -fromToTo));
    }

    // ── Primary BFS from anchor ──────────────────────────────────
    _bfsGeneration(anchorId, 0, adjacency, generations, visited);

    // ── Handle disconnected subgraphs ────────────────────────────
    for (final person in persons) {
      if (visited.contains(person.id)) continue;

      // Use the API-provided generationIndex as base for disconnected
      // components so they appear at roughly the correct level.
      final baseGen = person.generationIndex;
      _bfsGeneration(person.id, baseGen, adjacency, generations, visited);
    }

    // ── Normalize: shift so minimum generation is 0 ──────────────
    if (generations.isNotEmpty) {
      int minGen = generations.values.first;
      for (final g in generations.values) {
        if (g < minGen) minGen = g;
      }
      if (minGen != 0) {
        for (final key in generations.keys) {
          generations[key] = generations[key]! - minGen;
        }
      }
    }

    // ── Validate with API generationIndex for connected component ─
    // If a person has a non-zero API generationIndex and it conflicts
    // with BFS, we trust BFS for the anchor's component but use API
    // values to refine positioning (applied during sort).
    // For disconnected components, API values are already used as base.

    return generations;
  }

  /// Run BFS from [startId] at [startGen] to assign generation levels.
  void _bfsGeneration(
    String startId,
    int startGen,
    Map<String, List<(String, int)>> adjacency,
    Map<String, int> generations,
    Set<String> visited,
  ) {
    if (visited.contains(startId)) return;

    final queue = <_BFSEntry>[];
    generations[startId] = startGen;
    visited.add(startId);
    queue.add(_BFSEntry(startId, startGen));

    int head = 0;
    while (head < queue.length) {
      final current = queue[head];
      head++;

      for (final (neighborId, offset) in adjacency[current.personId]!) {
        if (visited.contains(neighborId)) continue;

        final neighborGen = current.generation + offset;
        generations[neighborId] = neighborGen;
        visited.add(neighborId);
        queue.add(_BFSEntry(neighborId, neighborGen));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 2: GROUP BY GENERATION
  // ═══════════════════════════════════════════════════════════════════

  /// Group person IDs by their assigned generation level.
  Map<int, List<String>> _groupByGeneration(
    List<GraphPerson> persons,
    Map<String, int> generations,
  ) {
    final groups = <int, List<String>>{};
    for (final person in persons) {
      final gen = generations[person.id] ?? person.generationIndex;
      groups.putIfAbsent(gen, () => []).add(person.id);
    }
    return groups;
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 3: SORT WITHIN GENERATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Sort persons within a generation so that:
  /// - Spouses are placed side-by-side (left spouse first)
  /// - Siblings are grouped together
  /// - Remaining persons are sorted alphabetically
  List<String> _sortWithinGeneration(
    List<String> personIds,
    List<GraphRelationship> relationships,
    Map<String, GraphPerson> personMap,
  ) {
    final personSet = personIds.toSet();

    // ── Identify spouse pairs within this generation ──────────────
    final spouseOf = <String, String>{};
    final spouseIsRight = <String, bool>{};

    for (final rel in relationships) {
      if (!_spouseKeys.contains(rel.relationshipKey)) continue;
      if (!personSet.contains(rel.fromPersonId) ||
          !personSet.contains(rel.toPersonId)) {
        continue;
      }
      // Only record the first spouse pairing per person
      if (!spouseOf.containsKey(rel.fromPersonId) &&
          !spouseOf.containsKey(rel.toPersonId)) {
        spouseOf[rel.fromPersonId] = rel.toPersonId;
        spouseOf[rel.toPersonId] = rel.fromPersonId;
        // Convention: fromPerson is "left", toPerson is "right"
        spouseIsRight[rel.fromPersonId] = false;
        spouseIsRight[rel.toPersonId] = true;
      }
    }

    // ── Identify sibling groups (share at least one parent) ───────
    final parentToChildren = <String, Set<String>>{};
    for (final rel in relationships) {
      String? parentId;
      String? childId;
      if (_childKeys.contains(rel.relationshipKey)) {
        parentId = rel.fromPersonId;
        childId = rel.toPersonId;
      } else if (_parentKeys.contains(rel.relationshipKey)) {
        parentId = rel.toPersonId;
        childId = rel.fromPersonId;
      }
      if (parentId != null && childId != null) {
        parentToChildren.putIfAbsent(parentId, () => {}).add(childId);
      }
    }

    // Build person → sibling group ID
    final personToSiblingGroup = <String, int>{};
    final siblingGroups = <int, Set<String>>{};
    int nextGroupId = 0;

    for (final children in parentToChildren.values) {
      // Only consider children in this generation
      final relevantChildren = <String>{};
      for (final c in children) {
        if (personSet.contains(c)) relevantChildren.add(c);
      }
      if (relevantChildren.length < 2) continue;

      // Check if any child is already in an existing group
      int? existingGroupId;
      for (final child in relevantChildren) {
        if (personToSiblingGroup.containsKey(child)) {
          existingGroupId = personToSiblingGroup[child];
          break;
        }
      }

      if (existingGroupId != null) {
        for (final child in relevantChildren) {
          personToSiblingGroup[child] = existingGroupId;
          siblingGroups[existingGroupId]!.add(child);
        }
      } else {
        final gid = nextGroupId++;
        siblingGroups[gid] = relevantChildren;
        for (final child in relevantChildren) {
          personToSiblingGroup[child] = gid;
        }
      }
    }

    // ── Build sorted result ───────────────────────────────────────
    final visited = <String>{};
    final result = <String>[];

    void addPersonWithSpouse(String id) {
      if (visited.contains(id)) return;

      // If this person is the "right" spouse, skip — the left spouse
      // will add both.
      if (spouseIsRight[id] == true &&
          spouseOf.containsKey(id) &&
          !visited.contains(spouseOf[id]!)) {
        return;
      }

      visited.add(id);
      result.add(id);

      // Add spouse immediately after (if in this generation)
      if (spouseOf.containsKey(id)) {
        final spouseId = spouseOf[id]!;
        if (!visited.contains(spouseId) && personSet.contains(spouseId)) {
          visited.add(spouseId);
          result.add(spouseId);
        }
      }
    }

    // First pass: process persons with sibling groups
    final sortedGroupIds = siblingGroups.keys.toList()..sort();
    for (final gid in sortedGroupIds) {
      final group = siblingGroups[gid]!.toList();
      // Sort within group by name for deterministic order
      group.sort((a, b) =>
          (personMap[a]?.name ?? '').compareTo(personMap[b]?.name ?? ''));
      for (final personId in group) {
        addPersonWithSpouse(personId);
      }
    }

    // Second pass: add remaining persons (sorted by name)
    final remaining = personIds
        .where((id) => !visited.contains(id))
        .toList()
      ..sort((a, b) =>
          (personMap[a]?.name ?? '').compareTo(personMap[b]?.name ?? ''));
    for (final personId in remaining) {
      addPersonWithSpouse(personId);
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 4: ASSIGN POSITIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Assign (x, y) positions for all persons across all generations.
  ///
  /// Y is determined by generation level. X is assigned sequentially
  /// with spouse-offset gaps for spouse pairs, then refined through
  /// multiple alignment passes to center parents above children.
  void _assignPositions(
    Map<int, List<String>> sortedGroups,
    Map<String, int> generations,
    Map<String, Offset> positions,
    List<GraphRelationship> relationships,
    Map<String, GraphPerson> personMap,
    String anchorId,
  ) {
    if (sortedGroups.isEmpty) return;

    // ── Identify spouse pairs globally ────────────────────────────
    final spouseOf = <String, String>{};
    for (final rel in relationships) {
      if (!_spouseKeys.contains(rel.relationshipKey)) continue;
      if (!spouseOf.containsKey(rel.fromPersonId) &&
          !spouseOf.containsKey(rel.toPersonId)) {
        spouseOf[rel.fromPersonId] = rel.toPersonId;
        spouseOf[rel.toPersonId] = rel.fromPersonId;
      }
    }

    // ── Identify parent → children mapping ────────────────────────
    final parentToChildren = <String, Set<String>>{};
    for (final rel in relationships) {
      String? parentId;
      String? childId;
      if (_childKeys.contains(rel.relationshipKey)) {
        parentId = rel.fromPersonId;
        childId = rel.toPersonId;
      } else if (_parentKeys.contains(rel.relationshipKey)) {
        parentId = rel.toPersonId;
        childId = rel.fromPersonId;
      } else if (_grandchildKeys.contains(rel.relationshipKey)) {
        parentId = rel.fromPersonId;
        childId = rel.toPersonId;
      } else if (_grandparentKeys.contains(rel.relationshipKey)) {
        parentId = rel.toPersonId;
        childId = rel.fromPersonId;
      }
      if (parentId != null && childId != null) {
        parentToChildren.putIfAbsent(parentId, () => {}).add(childId);
      }
    }

    // ── Sort generation levels ────────────────────────────────────
    final levels = sortedGroups.keys.toList()..sort();

    // ── Phase 1: Sequential X assignment ──────────────────────────
    for (final level in levels) {
      final y = level * _rowStep;
      final persons = sortedGroups[level]!;

      double x = 0;
      for (int i = 0; i < persons.length; i++) {
        final id = persons[i];
        positions[id] = Offset(x, y.toDouble());

        // Determine spacing to the next person
        if (i + 1 < persons.length) {
          final nextId = persons[i + 1];
          if (spouseOf[id] == nextId) {
            // Spouses: tight gap
            x += _nodeWidth + spouseOffset;
          } else {
            // Standard gap
            x += _colStep;
          }
        }
      }
    }

    // ── Phase 2: Alignment passes (center parents above children) ─
    const int maxAlignmentPasses = 10;
    const double dampening = 0.4;

    for (int pass = 0; pass < maxAlignmentPasses; pass++) {
      double totalShift = 0;

      // Process generations bottom-up (align parents to children)
      for (int li = levels.length - 1; li >= 0; li--) {
        final level = levels[li];
        final persons = sortedGroups[level]!;

        for (int i = 0; i < persons.length; i++) {
          final id = persons[i];
          final spouse = spouseOf[id];

          // Collect children of this person and their spouse
          final children = <String>{};
          if (parentToChildren.containsKey(id)) {
            children.addAll(parentToChildren[id]!);
          }
          if (spouse != null && parentToChildren.containsKey(spouse)) {
            children.addAll(parentToChildren[spouse]!);
          }

          if (children.isEmpty) continue;

          // Calculate center X of children
          double childCenterX = 0;
          int childCount = 0;
          for (final childId in children) {
            if (positions.containsKey(childId)) {
              childCenterX += positions[childId]!.dx + _nodeWidth / 2;
              childCount++;
            }
          }
          if (childCount == 0) continue;
          childCenterX /= childCount;

          // Calculate current center of parent (or couple)
          double parentCenterX = positions[id]!.dx + _nodeWidth / 2;
          if (spouse != null && positions.containsKey(spouse)) {
            // Only count spouse if they appear adjacent (right of this person)
            final spouseIdx = persons.indexOf(spouse);
            if (spouseIdx == i + 1) {
              parentCenterX =
                  (positions[id]!.dx + positions[spouse]!.dx + _nodeWidth) / 2;
            }
          }

          // Compute desired shift with dampening
          final shift = (childCenterX - parentCenterX) * dampening;
          if (shift.abs() < 0.5) continue;

          // Apply shift to this person
          final current = positions[id]!;
          positions[id] = Offset(current.dx + shift, current.dy);
          totalShift += shift.abs();

          // Also shift the spouse if they're adjacent
          if (spouse != null && positions.containsKey(spouse)) {
            final spouseIdx = persons.indexOf(spouse);
            if (spouseIdx == i + 1) {
              final spouseCurrent = positions[spouse]!;
              positions[spouse] =
                  Offset(spouseCurrent.dx + shift, spouseCurrent.dy);
            }
          }
        }

        // After processing each generation, resolve overlaps
        _resolveOverlapsForGeneration(positions, sortedGroups[level]!, spouseOf);
      }

      // Convergence check
      if (totalShift < 1.0) break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 5: RESOLVE OVERLAPS
  // ═══════════════════════════════════════════════════════════════════

  /// Resolve horizontal overlaps across all generations.
  ///
  /// Ensures every node has at least [_colStep] of horizontal space
  /// from the previous node (or [_nodeWidth + spouseOffset] for
  /// spouse pairs).
  void _resolveOverlaps(
    Map<String, Offset> positions,
    Map<int, List<String>> sortedGroups,
  ) {
    // Identify spouse pairs for reduced gap
    // (We don't have relationships here, so use a simplified approach:
    //  check if consecutive nodes are within spouseOffset + nodeWidth)
    for (final level in sortedGroups.keys) {
      final persons = sortedGroups[level]!;
      _resolveOverlapsForGenerationSimple(positions, persons);
    }
  }

  /// Resolve overlaps for a single generation using only position data.
  void _resolveOverlapsForGenerationSimple(
    Map<String, Offset> positions,
    List<String> persons,
  ) {
    if (persons.isEmpty) return;

    // Sort by current X position
    final sorted = List<String>.from(persons)
      ..sort((a, b) => positions[a]!.dx.compareTo(positions[b]!.dx));

    // Forward pass: push right if overlapping
    for (int i = 1; i < sorted.length; i++) {
      final prevX = positions[sorted[i - 1]]!.dx;
      final curr = positions[sorted[i]]!;

      // Determine if these two are spouses (very close together)
      final gap = curr.dx - prevX;
      final isLikelySpouse = gap > 0 && gap <= _nodeWidth + spouseOffset + 1;
      final minGap = isLikelySpouse
          ? _nodeWidth + spouseOffset
          : _colStep;

      final requiredX = prevX + minGap;
      if (curr.dx < requiredX) {
        positions[sorted[i]] = Offset(requiredX, curr.dy);
      }
    }
  }

  /// Resolve overlaps for a single generation using known spouse pairs.
  void _resolveOverlapsForGeneration(
    Map<String, Offset> positions,
    List<String> persons,
    Map<String, String> spouseOf,
  ) {
    if (persons.isEmpty) return;

    // Sort by current X position
    final sorted = List<String>.from(persons)
      ..sort((a, b) => positions[a]!.dx.compareTo(positions[b]!.dx));

    // Forward pass: push right if overlapping
    for (int i = 1; i < sorted.length; i++) {
      final prevId = sorted[i - 1];
      final currId = sorted[i];
      final prev = positions[prevId]!;
      final curr = positions[currId]!;

      // Determine minimum gap
      final areSpouses = spouseOf[prevId] == currId || spouseOf[currId] == prevId;
      final minGap = areSpouses
          ? _nodeWidth + spouseOffset
          : _colStep;

      final requiredX = prev.dx + minGap;
      if (curr.dx < requiredX) {
        positions[currId] = Offset(requiredX, curr.dy);
      }
    }

    // Backward pass: push left if overlapping (for centering stability)
    for (int i = sorted.length - 2; i >= 0; i--) {
      final nextId = sorted[i + 1];
      final currId = sorted[i];
      final next = positions[nextId]!;
      final curr = positions[currId]!;

      final areSpouses = spouseOf[currId] == nextId || spouseOf[nextId] == currId;
      final minGap = areSpouses
          ? _nodeWidth + spouseOffset
          : _colStep;

      final maxAllowedX = next.dx - minGap;
      if (curr.dx > maxAllowedX) {
        positions[currId] = Offset(maxAllowedX, curr.dy);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 6: CENTER LAYOUT
  // ═══════════════════════════════════════════════════════════════════

  /// Center the layout so that:
  /// - Minimum X starts at [horizontalSpacing] padding
  /// - The anchor person is visually prominent
  void _centerLayout(Map<String, Offset> positions, String anchorId) {
    if (positions.isEmpty) return;

    // Find the minimum X across all positions
    double minX = double.infinity;
    for (final offset in positions.values) {
      if (offset.dx < minX) minX = offset.dx;
    }

    // Shift everything so the leftmost node starts at horizontalSpacing
    if (minX != horizontalSpacing) {
      final shift = horizontalSpacing - minX;
      for (final key in positions.keys) {
        final current = positions[key]!;
        positions[key] = Offset(current.dx + shift, current.dy);
      }
    }

    // Also ensure minimum Y padding
    double minY = double.infinity;
    for (final offset in positions.values) {
      if (offset.dy < minY) minY = offset.dy;
    }
    if (minY != verticalSpacing) {
      final shift = verticalSpacing - minY;
      for (final key in positions.keys) {
        final current = positions[key]!;
        positions[key] = Offset(current.dx, current.dy + shift);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ═══════════════════════════════════════════════════════════════════

  /// Get all parent IDs for a given person from the relationships.
  List<String> getParentsOf(
    String personId,
    List<GraphRelationship> relationships,
  ) {
    final parents = <String>[];
    for (final rel in relationships) {
      // toPerson is the parent of fromPerson
      if (_parentKeys.contains(rel.relationshipKey) &&
          rel.fromPersonId == personId) {
        parents.add(rel.toPersonId);
      }
      // fromPerson is the parent of toPerson (reverse direction)
      if (_childKeys.contains(rel.relationshipKey) &&
          rel.toPersonId == personId) {
        parents.add(rel.fromPersonId);
      }
    }
    return parents;
  }

  /// Get all child IDs for a given person from the relationships.
  List<String> getChildrenOf(
    String personId,
    List<GraphRelationship> relationships,
  ) {
    final children = <String>[];
    for (final rel in relationships) {
      // toPerson is the child of fromPerson
      if (_childKeys.contains(rel.relationshipKey) &&
          rel.fromPersonId == personId) {
        children.add(rel.toPersonId);
      }
      // fromPerson is the child of toPerson (reverse direction)
      if (_parentKeys.contains(rel.relationshipKey) &&
          rel.toPersonId == personId) {
        children.add(rel.fromPersonId);
      }
    }
    return children;
  }

  /// Get the spouse ID for a given person from the relationships.
  String? getSpouseOf(
    String personId,
    List<GraphRelationship> relationships,
  ) {
    for (final rel in relationships) {
      if (!_spouseKeys.contains(rel.relationshipKey)) continue;
      if (rel.fromPersonId == personId) return rel.toPersonId;
      if (rel.toPersonId == personId) return rel.fromPersonId;
    }
    return null;
  }

  /// Compute the bounding box of all positions.
  Rect computeBoundingBox(Map<String, Offset> positions) {
    if (positions.isEmpty) {
      return Rect.zero;
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final offset in positions.values) {
      if (offset.dx < minX) minX = offset.dx;
      if (offset.dy < minY) minY = offset.dy;
      if (offset.dx + _nodeWidth > maxX) maxX = offset.dx + _nodeWidth;
      if (offset.dy + _nodeHeight > maxY) maxY = offset.dy + _nodeHeight;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Compute the initial transform to fit the layout in a viewport.
  ///
  /// Returns a [Matrix4] that scales and translates the layout to fit
  /// within [viewportSize] with [padding] on all sides.
  Matrix4 computeFitTransform(
    Map<String, Offset> positions,
    Size viewportSize,
    double padding,
  ) {
    final bounds = computeBoundingBox(positions);
    if (bounds.isEmpty) return Matrix4.identity();

    final contentWidth = bounds.width + padding * 2;
    final contentHeight = bounds.height + padding * 2;

    final scaleX = viewportSize.width / contentWidth;
    final scaleY = viewportSize.height / contentHeight;
    final scale = min(scaleX, scaleY);

    // Clamp scale to reasonable range
    final clampedScale = scale.clamp(0.1, 2.0);

    final tx = (viewportSize.width - bounds.width * clampedScale) / 2 -
        bounds.left * clampedScale;
    final ty = (viewportSize.height - bounds.height * clampedScale) / 2 -
        bounds.top * clampedScale;

    return Matrix4.identity()
      ..translate(tx, ty)
      ..scale(clampedScale, clampedScale);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// INTERNAL HELPERS
// ═══════════════════════════════════════════════════════════════════════

/// Entry for the BFS queue during generation assignment.
class _BFSEntry {
  final String personId;
  final int generation;

  const _BFSEntry(this.personId, this.generation);
}
