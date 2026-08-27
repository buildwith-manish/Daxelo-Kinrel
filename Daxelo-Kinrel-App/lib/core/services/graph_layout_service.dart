// lib/core/services/graph_layout_service.dart
//
// DAXELO KINREL — Radial / Orbital Graph Layout Service
//
// A production-ready family tree layout engine that:
// - Places the anchor person at the exact center of the canvas
// - Maps each generationIndex to a concentric ring radius
// - Ancestors (gen < 0) arc above center (trunk angle 270°)
// - Descendants (gen > 0) arc below center (trunk angle 90°)
// - Siblings / spouse of anchor sit on the anchor ring (gen 0)
// - Spouses are always placed adjacent to their partner on the same ring
// - Optional force-relaxation pass — EXPLICIT opt-in only (Show-All path)
// - Pure radial with angle jitter for very large families (> 1000 nodes)
// - Computes canvas dimensions from outermost ring + padding
//
// Angle convention (screen coordinates, Y-down):
//   0° = right, 90° = down, 180° = left, 270° = up

import 'dart:math';
import 'package:flutter/material.dart';

import '../../graph/interaction/couple_union_model.dart' show CoupleUnion, deriveCoupleUnions;

// ═══════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// A person node in the graph layout input.
///
/// This is the single canonical `GraphPerson` for the entire codebase.
/// It merges the fields previously split across `graph_service.dart`
/// (which used `generation`, `relationship`, `deletedAt`) and the layout
/// service (which used `generationIndex`, `gender`, `isAnchor`, `photoUrl`).
/// All callers — tree building, path finding, force simulation, and layout —
/// now share this one definition, eliminating the cross-module type mismatch
/// that caused the Stack Overflow at runtime.
class GraphPerson {
  final String id;
  final String name;
  final String? gender;
  final int generationIndex;
  final bool isAnchor;
  final String? photoUrl;
  final bool isDeceased;
  final String? relationship;
  final String? deletedAt;

  const GraphPerson({
    required this.id,
    required this.name,
    this.gender,
    this.generationIndex = 0,
    this.isAnchor = false,
    this.photoUrl,
    this.isDeceased = false,
    this.relationship,
    this.deletedAt,
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
  /// v5.99: The specific label (e.g. 'father', 'brother', 'wife') used
  /// for generation lookup. Falls back to [relationshipKey] if not set.
  final String? labelAtoB;

  const GraphRelationship({
    required this.id,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
    this.labelAtoB,
  });
}

/// The computed layout result: positions, canvas dimensions, and ring metadata.
class GraphLayoutResult {
  final Map<String, Offset> positions;
  final double canvasWidth;
  final double canvasHeight;

  /// Maps generationIndex → computed ring radius (dp).
  final Map<int, double> ringRadii;

  /// Maps generationIndex → base angle offset (radians) for that ring.
  final Map<int, double> ringAngleOffsets;

  /// v99 (Phase 6): Derived couple unions for the layout. Each union
  /// represents a confirmed partner pairing with shared children.
  /// The engine view uses these to render union junctions at the
  /// midpoint between partners and to route child edges through the
  /// union. Unions are presentation-only — never persisted, never
  /// in search, never in kinship BFS.
  final List<dynamic> coupleUnions;

  /// v5.99: BFS-computed generation for each person (personId → gen).
  /// Used by the stats panel to show the correct GENS count (based on
  /// the layout's own BFS, not the stale API generationIndex).
  final Map<String, int> generations;

  const GraphLayoutResult({
    required this.positions,
    required this.canvasWidth,
    required this.canvasHeight,
    this.ringRadii = const {},
    this.ringAngleOffsets = const {},
    this.coupleUnions = const [],
    this.generations = const {},
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

/// Radial / orbital family graph layout service.
///
/// Computes a concentric-ring layout where:
/// - The anchor person sits at the center (ring 0)
/// - Ancestors occupy rings above (generationIndex < 0)
/// - Descendants occupy rings below (generationIndex > 0)
/// - Spouses are clamped to their partner's ring
/// - Direct-lineage nodes remain roughly vertically aligned
class GraphLayoutService {
  GraphLayoutService();

  // ── Radial Layout Constants ────────────────────────────────────────

  /// Base ring radius for the first ring around the anchor (dp).
  /// Increased from 160 to 200 for wider spacing between rings to
  /// prevent edge overlapping when multiple members are added.
  static const double baseRadius = 200.0;

  /// Spacing between consecutive rings (dp).
  /// Increased from 160 to 220 for wider spacing so edges between
  /// different rings don't intersect.
  static const double ringSpacing = 220.0;

  /// Horizontal offset for a spouse placed beside their partner (dp).
  /// Increased from 90 to 110 for slightly more spouse separation.
  static const double spouseOffset = 110.0;

  /// Padding around the outermost ring for canvas sizing (dp).
  static const double canvasPadding = 120.0;

  // ── Design Tokens (kept for backward-compat utility methods) ───────

  /// Node width in compact mode (dp).
  static const double nodeWidthCompact = 80.0;

  /// Node width in normal mode (dp).
  static const double nodeWidthNormal = 100.0;

  /// Node height in compact mode (dp).
  static const double nodeHeightCompact = 100.0;

  /// Node height in normal mode (dp).
  static const double nodeHeightNormal = 120.0;

  /// Horizontal spacing between nodes (dp) — used by utility methods.
  static const double horizontalSpacing = 60.0;

  /// Vertical spacing between generations (dp) — used by utility methods.
  static const double verticalSpacing = 120.0;

  // ── Relationship Key Categories ────────────────────────────────────

  /// Keys where toPerson is a parent of fromPerson (one generation above).
  static const Set<String> _parentKeys = {
    'parent',
    'father',
    'mother',
    'stepfather',
    'stepmother',
  };

  /// Keys where toPerson is a child of fromPerson (one generation below).
  static const Set<String> _childKeys = {
    'child',
    'son',
    'daughter',
    'stepson',
    'stepdaughter',
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
    'half_brother',
    'half_sister',
    'elder_brother',
    'elder_sister',
    'younger_brother',
    'younger_sister',
    'stepbrother',
    'stepsister',
  };

  /// Extended family keys that span two generations above.
  // NOTE: grandparent/grandchild keys intentionally NOT in _parentKeys/_childKeys
  // so they use the correct ±2 offset in BFS (checked before _parentKeys).
  static const Set<String> _grandparentKeys = {
    'grandparent',
    'grandfather',
    'grandmother',
    'paternal_grandfather',
    'paternal_grandmother',
    'maternal_grandfather',
    'maternal_grandmother',
  };

  /// Extended family keys that span two generations below.
  static const Set<String> _grandchildKeys = {
    'grandchild',
    'grandson',
    'granddaughter',
  };

  // ── Mutable State (per compute call) ──────────────────────────────

  bool _compactMode = false;

  double get _nodeWidth =>
      _compactMode ? nodeWidthCompact : nodeWidthNormal;
  double get _nodeHeight =>
      _compactMode ? nodeHeightCompact : nodeHeightNormal;

  // ── Radians helpers ───────────────────────────────────────────────

  /// Convert degrees to radians.
  static double _degToRad(double deg) => deg * pi / 180.0;

  /// Trunk angle for ancestor rings (pointing up in screen coords).
  static final double _ancestorTrunk = _degToRad(270.0);

  /// Trunk angle for descendant rings (pointing down in screen coords).
  static final double _descendantTrunk = _degToRad(90.0);

  // ── Public API ────────────────────────────────────────────────────

  /// Compute the full radial/orbital layout for a family graph.
  ///
  /// [persons] — all person nodes to lay out.
  /// [relationships] — all directed relationship edges.
  /// [anchorPersonId] — optional ID of the anchor/ego person to center on.
  ///   Falls back to `isAnchor` flag, then the first person.
  /// [compactMode] — use compact node dimensions for dense graphs.
  /// [allowForceRelaxation] — v5.123: EXPLICIT opt-in for the
  ///   force-relaxation physics pass. Defaults to FALSE: the default
  ///   ego-centric view (proximity-budget-driven, roughly ≤ 40 nodes)
  ///   positions nodes PURELY from ring radius (fixed by
  ///   generationIndex) + evenly-spaced angles within the ring +
  ///   branch grouping (the barycenter pass sorts siblings/couples
  ///   from the same parent adjacent before angle assignment), so
  ///   nodes stay exactly ON their assigned rings and edges stay
  ///   clean. Only the "Show All Branches" / Level 4 path — where the
  ///   node count can be much larger and pure radial placement would
  ///   overlap — should pass true. This replaces the old implicit
  ///   `n > 60` node-count check, which silently repositioned nodes
  ///   OFF their rings at normal view sizes and produced crossed,
  ///   messy edges.
  ///
  /// Returns a [GraphLayoutResult] with personId → Offset positions,
  /// canvas dimensions, and ring metadata.
  GraphLayoutResult computeLayout({
    required List<GraphPerson> persons,
    required List<GraphRelationship> relationships,
    String? anchorPersonId,
    bool compactMode = false,
    Map<String, int>? kinshipGenerationMap,
    bool allowForceRelaxation = false,
  }) {
    _compactMode = compactMode;

    // Edge case: empty input
    if (persons.isEmpty) {
      return const GraphLayoutResult(
        positions: {},
        canvasWidth: 0,
        canvasHeight: 0,
        ringRadii: {},
        ringAngleOffsets: {},
      );
    }

    // Build lookup maps
    final personMap = <String, GraphPerson>{};
    for (final p in persons) {
      personMap[p.id] = p;
    }

    // v94 (EDGE BUG FIX): Debug-mode assertions to catch missing-endpoint
    // edges before they reach the painter. If a relationship references a
    // personId that's not in `persons`, the edge will be silently skipped
    // by the layout (and the painter), resulting in an "orphan edge" that
    // exists in the data but never renders. These assertions make the
    // mismatch visible during development so it can be diagnosed.
    assert(() {
      final personIds = personMap.keys.toSet();
      for (final rel in relationships) {
        assert(
          personIds.contains(rel.fromPersonId),
          'GraphLayoutService: relationship ${rel.id} references '
          'fromPersonId "${rel.fromPersonId}" which is not in the '
          'persons list. The edge will be silently dropped.',
        );
        assert(
          personIds.contains(rel.toPersonId),
          'GraphLayoutService: relationship ${rel.id} references '
          'toPersonId "${rel.toPersonId}" which is not in the '
          'persons list. The edge will be silently dropped.',
        );
      }
      return true;
    }(), 'GraphLayoutService: edge endpoint mismatch detected');

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

    // ── Step 1: Assign generation levels via BFS ──────────────────────
    final generations = _assignGenerations(
      persons,
      relationships,
      anchor,
      personMap,
      kinshipGenerationMap,
    );

    // ── Step 2: Build spouse map & clamp spouse generations ───────────
    final spouseOf = <String, String>{};
    for (final rel in relationships) {
      if (!_spouseKeys.contains(rel.relationshipKey)) continue;
      if (!personMap.containsKey(rel.fromPersonId) ||
          !personMap.containsKey(rel.toPersonId)) {
        continue;
      }
      // Only record the first spouse pairing per person
      if (!spouseOf.containsKey(rel.fromPersonId) &&
          !spouseOf.containsKey(rel.toPersonId)) {
        spouseOf[rel.fromPersonId] = rel.toPersonId;
        spouseOf[rel.toPersonId] = rel.fromPersonId;
      }
    }

    // Clamp each spouse to their partner's generation so they sit on
    // the same ring.
    for (final entry in spouseOf.entries) {
      final personId = entry.key;
      final partnerId = entry.value;
      if (generations.containsKey(personId) &&
          generations.containsKey(partnerId)) {
        // Keep the generation that is closer to the anchor (smaller abs)
        final pGen = generations[personId]!;
        final qGen = generations[partnerId]!;
        // Anchor's spouse uses anchor's generation (0)
        if (partnerId == anchor) {
          generations[personId] = 0;
        } else if (personId == anchor) {
          generations[partnerId] = 0;
        } else {
          // Use the average or the partner's gen; prefer the partner's
          // generation so they appear on the same ring.  We pick the
          // one whose absolute value is smaller (closer to anchor).
          final target = pGen.abs() <= qGen.abs() ? pGen : qGen;
          generations[personId] = target;
          generations[partnerId] = target;
        }
      }
    }

    // ── Step 3: Group persons by generation ───────────────────────────
    final genGroups = <int, List<String>>{};
    for (final person in persons) {
      final gen = generations[person.id] ?? person.generationIndex;
      genGroups.putIfAbsent(gen, () => []).add(person.id);
    }

    // ── Step 4: Compute ring radii and angle offsets ──────────────────
    final ringRadii = <int, double>{};
    final ringAngleOffsets = <int, double>{};

    for (final gen in genGroups.keys) {
      ringRadii[gen] = baseRadius + (gen.abs() * ringSpacing);
      if (gen < 0) {
        ringAngleOffsets[gen] = _ancestorTrunk;
      } else if (gen > 0) {
        ringAngleOffsets[gen] = _descendantTrunk;
      } else {
        ringAngleOffsets[gen] = 0.0; // anchor ring — 0° (right)
      }
    }

    // ── Step 5: Assign initial radial positions ──────────────────────
    final positions = <String, Offset>{};
    final center = Offset(0.0, 0.0); // will translate later

    // Place anchor at center
    positions[anchor] = center;

    // Determine family size bucket
    // v5.123: Force relaxation is now an EXPLICIT opt-in
    // ([allowForceRelaxation], default false) instead of the old
    // implicit `n > 60` node-count check. The physics pass moved nodes
    // OFF their assigned ring radii at normal (~20-40 node) view sizes,
    // producing crossed/messy edges. Only the Show-All/Level 4 path —
    // which can have far more nodes — opts in. The upper bound (pure
    // radial + jitter above 1000 nodes) is unchanged.
    final n = persons.length;
    final useForceRelaxation = allowForceRelaxation && n <= 1000;
    final useJitter = n > 1000;

    // Place anchor-ring non-anchor persons (siblings, spouse on gen 0)
    _placeAnchorRing(
      anchor: anchor,
      genGroups: genGroups,
      spouseOf: spouseOf,
      positions: positions,
      ringRadii: ringRadii,
      ringAngleOffsets: ringAngleOffsets,
    );

    // Place each non-zero generation ring
    for (final gen in genGroups.keys) {
      if (gen == 0) continue; // already handled
      _placeRing(
        gen: gen,
        genGroups: genGroups,
        spouseOf: spouseOf,
        positions: positions,
        ringRadii: ringRadii,
        ringAngleOffsets: ringAngleOffsets,
        useJitter: useJitter,
      );
    }

    // ── Step 6: Force-relaxation (explicit opt-in: Show-All/Level 4) ──
    if (useForceRelaxation) {
      _forceRelax(
        positions: positions,
        generations: generations,
        spouseOf: spouseOf,
        anchor: anchor,
        ringRadii: ringRadii,
        maxIterations: 60,
      );
    }

    // v2.2 Fix 9: Safety net — ensure EVERY person has a position.
    // If any person was missed by the ring placement (e.g., disconnected
    // subgraph with no generation assignment, or a bug in the BFS),
    // assign them a position near the anchor so they don't end up at
    // Offset.zero (which may be off-canvas after normalization).
    for (final person in persons) {
      if (!positions.containsKey(person.id)) {
        final gen = generations[person.id] ?? person.generationIndex;
        final radius = ringRadii[gen] ?? baseRadius;
        final angle = ringAngleOffsets[gen] ?? _descendantTrunk;
        positions[person.id] = Offset(
          radius * cos(angle),
          radius * sin(angle),
        );
        debugPrint('[GraphLayoutService] Safety net: assigned position '
            'to ${person.id} (gen=$gen) at ${positions[person.id]}');
      }
    }

    // ── Step 6.5: v5.101 — Convert to hierarchical Y-bands ──────────
    // Override Y-positions to create clear horizontal generational bands.
    _applyHierarchicalYBands(positions, generations, ringSpacing);

    // ── Step 6.6: v5.102 — Barycenter reordering within each generation ──
    // Reorder nodes within each generation band so that connected nodes
    // are positioned near each other, minimizing edge crossings.
    // Uses iterative median heuristic (2 passes for convergence).
    // Scales: skipped for >2000 nodes (too expensive), 1 pass for >500,
    // 2 passes for ≤500 (better convergence at manageable cost).
    final nodeCount = persons.length;
    final barycenterPasses = nodeCount > 2000 ? 0 : (nodeCount > 500 ? 1 : 2);
    for (int pass = 0; pass < barycenterPasses; pass++) {
      _barycenterReorder(
        positions: positions,
        generations: generations,
        relationships: relationships,
        personMap: personMap,
        bandHeight: ringSpacing,
      );
    }

    // ── Step 6.7: v5.102 — Label collision avoidance ─────────────────
    // Nudge X positions so that no two nodes in the same generation band
    // are closer than a minimum horizontal gap (prevents label overlap).
    // Scales: gap widens with node count to maintain readability.
    _avoidLabelCollisions(
      positions: positions,
      generations: generations,
      personMap: personMap,
      bandHeight: ringSpacing,
      nodeCount: nodeCount,
    );

    // ── Step 6.8: v5.113 — 2D COLLISION RESOLUTION ──────────────────
    // The label collision avoidance above only enforces an X-gap within
    // the same generation band. It does NOT detect:
    //   • Nodes at the exact same position (stacked duplicates)
    //   • Cross-band overlaps (rare but possible with large families)
    //   • Nodes that were pushed to the same X by the barycenter reorder
    //
    // This new pass runs a proper 2D circle-based collision resolution:
    //   1. For each pair of nodes closer than minDistance, push them apart
    //   2. Iterate multiple times for convergence
    //   3. Keep nodes in their correct generation band (Y-axis clamped)
    //
    // This ensures NO two nodes overlap, regardless of family size.
    _resolve2DCollisions(
      positions: positions,
      generations: generations,
      nodeCount: nodeCount,
      bandHeight: ringSpacing,
    );

    // ── Step 7: Translate positions so everything is in positive space ─
    _normalizePositions(positions, ringRadii);

    // ── Step 8: Compute canvas dimensions ─────────────────────────────
    final (cw, ch) = _computeCanvasSize(positions, ringRadii);

    // v99 (Phase 6): Derive couple unions from the canonical
    // relationship edges. Unions are presentation-only — they are
    // NOT persisted, NOT in search, NOT in kinship BFS. The engine
    // view reads layout.coupleUnions to render union junctions.
    final coupleUnions = deriveCoupleUnions([
      for (final rel in relationships)
        (
          fromId: rel.fromPersonId,
          toId: rel.toPersonId,
          edgeId: rel.id,
          relationshipKey: rel.relationshipKey,
        ),
    ]);

    return GraphLayoutResult(
      positions: positions,
      canvasWidth: cw,
      canvasHeight: ch,
      ringRadii: ringRadii,
      ringAngleOffsets: ringAngleOffsets,
      coupleUnions: coupleUnions,
      // v5.99: Pass the BFS-computed generations so the stats panel
      // can show the correct GENS count (not the stale API values).
      generations: generations,
    );
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
    Map<String, int>? kinshipGenerationMap,
  ) {
    final generations = <String, int>{};
    final visited = <String>{};

    // Build adjacency: personId → [(neighborId, generationOffset)]
    //
    // v2.2 FIX: When both forward (A→B "uncle") and inverse (B→A "nephew")
    // edges exist for the same pair, they may have DIFFERENT keys. We
    // must NOT add both to the adjacency list — that creates conflicting
    // offsets. Instead, for each (fromId, toId) pair, we keep only the
    // edge whose key produces a non-zero offset (more specific), or the
    // first edge if both produce the same offset.
    final adjacency = <String, List<(String, int)>>{};
    for (final p in persons) {
      adjacency[p.id] = [];
    }

    // Track the best offset for each (fromId, toId) pair.
    // "Best" = largest absolute offset (most specific generational info).
    final bestOffset = <String, int>{};

    for (final rel in relationships) {
      final fromId = rel.fromPersonId;
      final toId = rel.toPersonId;
      if (!personMap.containsKey(fromId) || !personMap.containsKey(toId)) {
        continue;
      }

      // Determine generational offset from fromPerson → toPerson.
      //
      // v5.99: Use labelAtoB (specific label like 'father', 'brother')
      // instead of relationshipKey (fundamental type like 'parent').
      // The mapToFundamentalEdge() function maps ALL non-spouse
      // relationships to 'parent', so using relationshipKey would
      // treat siblings, children, grandparents ALL as parent edges
      // (generation -1), producing wrong generation assignments.
      //
      // The kinshipGenerationMap is keyed by SPECIFIC labels
      // ('father' → -1, 'brother' → 0, 'son' → +1, etc.), so we
      // must look up the specific label, not the fundamental type.
      final lookupKey = rel.labelAtoB ?? rel.relationshipKey;
      int fromToTo;
      if (kinshipGenerationMap != null &&
          kinshipGenerationMap.containsKey(lookupKey)) {
        fromToTo = kinshipGenerationMap[lookupKey]!;
      } else if (_grandparentKeys.contains(lookupKey)) {
        fromToTo = -2;
      } else if (_parentKeys.contains(lookupKey)) {
        fromToTo = -1;
      } else if (_grandchildKeys.contains(lookupKey)) {
        fromToTo = 2;
      } else if (_childKeys.contains(lookupKey)) {
        fromToTo = 1;
      } else {
        fromToTo = 0; // spouse, sibling, cousin, in-law, etc.
      }

      // Deduplicate: for each (fromId, toId) pair, keep the edge with
      // the largest absolute offset. This ensures that if both a
      // forward edge (offset -1) and a mis-keyed inverse edge (offset 0)
      // exist for the same pair, the forward edge wins.
      final pairKey = '${fromId}|$toId';
      final existing = bestOffset[pairKey];
      if (existing != null) {
        if (fromToTo.abs() <= existing.abs()) {
          // Existing edge is at least as specific — skip this one.
          continue;
        }
        // New edge is more specific — replace the existing adjacency entry.
        // Remove the old entry from adjacency[fromId].
        adjacency[fromId]!.removeWhere((entry) => entry.$1 == toId);
      }
      bestOffset[pairKey] = fromToTo;

      // Forward edge: from → to with +offset
      adjacency[fromId]!.add((toId, fromToTo));
    }

    // Also add reverse edges (to → from with −offset) for each
    // forward edge we kept. This ensures the BFS can traverse in
    // both directions without conflicting offsets.
    for (final entry in bestOffset.entries) {
      final parts = entry.key.split('|');
      final fromId = parts[0];
      final toId = parts[1];
      final offset = entry.value;
      // Reverse: to → from with −offset
      // Only add if not already present (avoid duplicates from forward).
      final hasReverse = bestOffset.containsKey('${toId}|$fromId');
      if (!hasReverse) {
        adjacency[toId]!.add((fromId, -offset));
      }
    }

    // ── Primary BFS from anchor ────────────────────────────────────
    _bfsGeneration(anchorId, 0, adjacency, generations, visited);

    // ── Handle disconnected subgraphs ──────────────────────────────
    for (final person in persons) {
      if (visited.contains(person.id)) continue;

      // Use the API-provided generationIndex as base for disconnected
      // components so they appear at roughly the correct level.
      final baseGen = person.generationIndex;
      _bfsGeneration(person.id, baseGen, adjacency, generations, visited);
    }

    // ── Normalize: shift so anchor's generation is 0 ───────────────
    // Unlike the old code that shifted min to 0, we want the anchor at
    // gen 0 so that negative = ancestors, positive = descendants.
    // BFS already starts anchor at 0, but disconnected components may
    // shift the range.  We keep the BFS result as-is since anchor
    // starts at 0 and that's the reference.

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
  // STEP 5a: PLACE ANCHOR RING (generation 0, non-anchor persons)
  // ═══════════════════════════════════════════════════════════════════

  /// Place non-anchor persons on the anchor's ring (generation 0).
  ///
  /// These are spouses and siblings of the anchor. They fan out around
  /// the anchor at radius 0 (same center) using the spouse offset for
  /// spouses, or at baseRadius for siblings.
  void _placeAnchorRing({
    required String anchor,
    required Map<int, List<String>> genGroups,
    required Map<String, String> spouseOf,
    required Map<String, Offset> positions,
    required Map<int, double> ringRadii,
    required Map<int, double> ringAngleOffsets,
  }) {
    final gen0 = genGroups[0];
    if (gen0 == null) return;

    // Anchor spouse sits adjacent (spouseOffset to the right)
    final anchorSpouse = spouseOf[anchor];

    // Separate into: anchor spouse, other spouses of gen-0 people, siblings
    final siblings = <String>[];
    String? anchorSpouseId;

    for (final id in gen0) {
      if (id == anchor) continue;
      if (id == anchorSpouse) {
        anchorSpouseId = id;
      } else {
        siblings.add(id);
      }
    }

    // Place anchor spouse at horizontal offset from anchor
    if (anchorSpouseId != null) {
      positions[anchorSpouseId] = Offset(spouseOffset, 0.0);
    }

    // Place siblings on the anchor ring at baseRadius, fanned around
    // 0° and 180° (left/right of anchor)
    if (siblings.isNotEmpty) {
      final radius = ringRadii[0] ?? baseRadius;
      final totalAngle = _degToRad(360.0);
      // We place siblings evenly around the anchor ring but avoid
      // the angle where the spouse sits (0°).
      // For small families (≤8), fan around 0° and 180°.
      final angleStep = totalAngle / (siblings.length + 1);
      // Start offset so they're centered around 180° (left of anchor)
      final startAngle = _degToRad(180.0) -
          (angleStep * (siblings.length - 1) / 2);

      for (int i = 0; i < siblings.length; i++) {
        final angle = startAngle + angleStep * i;
        final x = radius * cos(angle);
        final y = radius * sin(angle);
        positions[siblings[i]] = Offset(x, y);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 5b: PLACE A NON-ZERO GENERATION RING
  // ═══════════════════════════════════════════════════════════════════

  /// Place all persons on a given generation ring.
  ///
  /// Ancestor rings (gen < 0) fan around 270° (up).
  /// Descendant rings (gen > 0) fan around 90° (down).
  /// Within the ring, nodes are distributed evenly.
  /// Spouses are placed adjacent to their partner.
  void _placeRing({
    required int gen,
    required Map<int, List<String>> genGroups,
    required Map<String, String> spouseOf,
    required Map<String, Offset> positions,
    required Map<int, double> ringRadii,
    required Map<int, double> ringAngleOffsets,
    required bool useJitter,
  }) {
    final ids = genGroups[gen];
    if (ids == null || ids.isEmpty) return;

    final radius = ringRadii[gen]!;
    final baseAngle = ringAngleOffsets[gen]!;

    // Separate persons into: those with a spouse on this ring,
    // and independent persons.
    final placed = <String>{};
    final independent = <String>[];
    final coupleSlots = <(String, String)>[]; // (person, spouse) pairs

    for (final id in ids) {
      if (placed.contains(id)) continue;
      final spouse = spouseOf[id];
      if (spouse != null && ids.contains(spouse) && !placed.contains(spouse)) {
        coupleSlots.add((id, spouse));
        placed.add(id);
        placed.add(spouse);
      } else {
        independent.add(id);
        placed.add(id);
      }
    }

    // Total visual slots: each couple occupies 1 primary slot (spouse is
    // offset from it), each independent person occupies 1 slot.
    final totalSlots = coupleSlots.length + independent.length;

    // Determine the angular spread for this ring.
    // For small families (≤8 people total), use a semicircle.
    // For larger families, use a wider arc.
    // BUG 2 FIX: Widened arcs at every tier so edges between nodes
    // on the same ring don't overlap. More angular spread = more
    // horizontal separation between nodes = less edge crossing.
    double totalArcAngle;
    if (gen < 0) {
      // Ancestors: arc from 200° to 340° (centered on 270°)
      totalArcAngle = _degToRad(140.0); // 140° arc (was 90°)
    } else {
      // Descendants: arc from 20° to 160° (centered on 90°)
      totalArcAngle = _degToRad(140.0); // 140° arc (was 90°)
    }

    // For larger families, widen the arc to avoid cramping
    if (totalSlots > 3) {
      totalArcAngle = _degToRad(200.0); // 200° arc (was 180°)
    }
    if (totalSlots > 6) {
      totalArcAngle = _degToRad(300.0); // 300° arc (was 270°)
    }
    if (totalSlots > 12) {
      totalArcAngle = _degToRad(360.0); // full circle (was >16)
    }

    final angleStep = totalArcAngle / (totalSlots + 1);
    final startAngle = baseAngle - totalArcAngle / 2;

    int slotIndex = 0;

    // Place couples first — they get primary slot positions
    for (final (personId, spouseId) in coupleSlots) {
      final angle = startAngle + angleStep * (slotIndex + 1);
      final jitter = useJitter ? (Random().nextDouble() - 0.5) * _degToRad(2.0) : 0.0;
      final a = angle + jitter;
      final x = radius * cos(a);
      final y = radius * sin(a);
      positions[personId] = Offset(x, y);

      // Spouse: adjacent on same ring, offset perpendicular (to the right)
      final spouseAngle = a + _spouseAngularOffset(radius);
      final sx = radius * cos(spouseAngle);
      final sy = radius * sin(spouseAngle);
      positions[spouseId] = Offset(sx, sy);

      slotIndex++;
    }

    // Place independent persons
    for (final id in independent) {
      final angle = startAngle + angleStep * (slotIndex + 1);
      final jitter = useJitter ? (Random().nextDouble() - 0.5) * _degToRad(2.0) : 0.0;
      final a = angle + jitter;
      final x = radius * cos(a);
      final y = radius * sin(a);
      positions[id] = Offset(x, y);
      slotIndex++;
    }
  }

  /// Compute the angular offset for a spouse given the ring radius,
  /// such that the chord distance ≈ [spouseOffset] dp.
  double _spouseAngularOffset(double radius) {
    if (radius <= 0) return _degToRad(30.0); // fallback
    // chord = 2 * r * sin(θ/2) = spouseOffset
    // θ = 2 * arcsin(spouseOffset / (2 * r))
    final arg = spouseOffset / (2 * radius);
    if (arg > 1.0) return _degToRad(60.0); // clamp for tiny radii
    return 2 * asin(arg);
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 6: FORCE-RELAXATION (medium families: 61–1000 nodes)
  // ═══════════════════════════════════════════════════════════════════

  /// Simple force-directed relaxation that:
  /// - Applies repulsion between all node pairs
  /// - Constrains nodes to their assigned ring radius
  /// - Keeps the anchor pinned at center
  /// - Keeps spouses tethered together
  void _forceRelax({
    required Map<String, Offset> positions,
    required Map<String, int> generations,
    required Map<String, String> spouseOf,
    required String anchor,
    required Map<int, double> ringRadii,
    required int maxIterations,
  }) {
    const double repulsionStrength = 5000.0;
    const double ringSpringStrength = 0.3;
    const double spouseSpringStrength = 0.5;
    const double damping = 0.8;
    const double minDist = 40.0;

    final ids = positions.keys.toList();
    final velocities = <String, Offset>{};
    for (final id in ids) {
      velocities[id] = Offset.zero;
    }

    for (int iter = 0; iter < maxIterations; iter++) {
      final forces = <String, Offset>{};
      for (final id in ids) {
        forces[id] = Offset.zero;
      }

      // ── Repulsion between all pairs ────────────────────────────────
      for (int i = 0; i < ids.length; i++) {
        for (int j = i + 1; j < ids.length; j++) {
          final a = ids[i];
          final b = ids[j];
          final pa = positions[a]!;
          final pb = positions[b]!;
          final dx = pa.dx - pb.dx;
          final dy = pa.dy - pb.dy;
          final dist2 = dx * dx + dy * dy;
          final dist = sqrt(max(dist2, minDist * minDist));
          final force = repulsionStrength / (dist * dist);
          final fx = (dx / dist) * force;
          final fy = (dy / dist) * force;
          forces[a] = Offset(forces[a]!.dx + fx, forces[a]!.dy + fy);
          forces[b] = Offset(forces[b]!.dx - fx, forces[b]!.dy - fy);
        }
      }

      // ── Ring constraint spring ─────────────────────────────────────
      for (final id in ids) {
        if (id == anchor) continue;
        final gen = generations[id] ?? 0;
        final targetR = ringRadii[gen] ?? baseRadius;
        final pos = positions[id]!;
        final currentR = sqrt(pos.dx * pos.dx + pos.dy * pos.dy);
        if (currentR <= 0) continue;
        final dr = targetR - currentR;
        // Pull radially toward the target radius
        final ux = pos.dx / currentR;
        final uy = pos.dy / currentR;
        forces[id] = Offset(
          forces[id]!.dx + ux * dr * ringSpringStrength,
          forces[id]!.dy + uy * dr * ringSpringStrength,
        );
      }

      // ── Spouse tether spring ───────────────────────────────────────
      final processed = <String>{};
      for (final entry in spouseOf.entries) {
        final a = entry.key;
        final b = entry.value;
        if (processed.contains(a) || processed.contains(b)) continue;
        if (!positions.containsKey(a) || !positions.containsKey(b)) continue;
        processed.add(a);
        processed.add(b);

        final pa = positions[a]!;
        final pb = positions[b]!;
        final dx = pb.dx - pa.dx;
        final dy = pb.dy - pa.dy;
        final dist = sqrt(dx * dx + dy * dy);
        final targetDist = spouseOffset;
        if (dist <= 0) continue;
        final dr = targetDist - dist;
        final ux = dx / dist;
        final uy = dy / dist;
        final fx = ux * dr * spouseSpringStrength;
        final fy = uy * dr * spouseSpringStrength;
        if (a != anchor) {
          forces[a] = Offset(forces[a]!.dx - fx, forces[a]!.dy - fy);
        }
        if (b != anchor) {
          forces[b] = Offset(forces[b]!.dx + fx, forces[b]!.dy + fy);
        }
      }

      // ── Apply forces with damping ──────────────────────────────────
      for (final id in ids) {
        if (id == anchor) continue; // pin anchor
        final v = velocities[id]!;
        final f = forces[id]!;
        velocities[id] = Offset(
          (v.dx + f.dx) * damping,
          (v.dy + f.dy) * damping,
        );
        positions[id] = Offset(
          positions[id]!.dx + velocities[id]!.dx,
          positions[id]!.dy + velocities[id]!.dy,
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 6.5: v5.101 — APPLY HIERARCHICAL Y-BANDS
  // ═══════════════════════════════════════════════════════════════════

  /// Override Y-coordinates to create clear horizontal generational bands.
  ///
  /// Each generation gets a fixed Y position:
  ///   gen -2 → y = -2 * bandHeight (grandparents, top)
  ///   gen -1 → y = -1 * bandHeight (parents, aunts/uncles)
  ///   gen  0 → y = 0 (self, siblings, spouse, cousins)
  ///   gen +1 → y = +1 * bandHeight (children, nieces/nephews)
  ///   gen +2 → y = +2 * bandHeight (grandchildren, bottom)
  ///
  /// X-coordinates are preserved from the radial layout, which gives
  /// a natural horizontal spread within each band. This converts the
  /// radial layout into a hierarchical band layout while keeping the
  /// existing X-spread and spouse placement logic.
  void _applyHierarchicalYBands(
    Map<String, Offset> positions,
    Map<String, int> generations,
    double bandHeight,
  ) {
    for (final entry in positions.entries) {
      final id = entry.key;
      final pos = entry.value;
      final gen = generations[id] ?? 0;
      // Override Y with fixed band position. Negative gen = above (negative Y),
      // positive gen = below (positive Y), gen 0 = center (Y=0).
      final y = gen * bandHeight;
      positions[id] = Offset(pos.dx, y);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 6.6: v5.102 — BARYCENTER REORDER (crossing minimization)
  // ═══════════════════════════════════════════════════════════════════

  /// Reorder nodes within each generation band using the median heuristic.
  ///
  /// For each node, compute the median X of all its connected neighbors
  /// in adjacent generations. Then sort nodes within each band by their
  /// median X, and re-assign X positions evenly spaced across the band.
  ///
  /// This minimizes edge crossings because connected nodes end up near
  /// each other horizontally, so their connecting lines don't cross
  /// lines from unrelated nodes.
  ///
  /// Iterative: run 2 passes for ≤500 nodes, 1 pass for 501-2000,
  /// skip for >2000 (too expensive at that scale).
  void _barycenterReorder({
    required Map<String, Offset> positions,
    required Map<String, int> generations,
    required List<GraphRelationship> relationships,
    required Map<String, GraphPerson> personMap,
    required double bandHeight,
  }) {
    // Build adjacency: personId → list of (neighborId, genDiff)
    final adjacency = <String, List<String>>{};
    for (final rel in relationships) {
      final from = rel.fromPersonId;
      final to = rel.toPersonId;
      if (!personMap.containsKey(from) || !personMap.containsKey(to)) continue;
      adjacency.putIfAbsent(from, () => []).add(to);
      adjacency.putIfAbsent(to, () => []).add(from);
    }

    // Group by generation
    final genGroups = <int, List<String>>{};
    for (final entry in generations.entries) {
      genGroups.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    // For each generation band, compute median X and reorder
    for (final gen in genGroups.keys) {
      final ids = genGroups[gen]!;
      if (ids.length <= 1) continue;

      // Compute median X for each node based on neighbors in OTHER generations
      final medianX = <String, double>{};
      for (final id in ids) {
        final neighbors = adjacency[id] ?? [];
        final neighborXs = <double>[];
        for (final neighborId in neighbors) {
          final nGen = generations[neighborId];
          if (nGen == null || nGen == gen) continue; // skip same-gen neighbors
          final nPos = positions[neighborId];
          if (nPos != null) {
            neighborXs.add(nPos.dx);
          }
        }
        if (neighborXs.isEmpty) {
          // No cross-generation neighbors — keep current X
          medianX[id] = positions[id]?.dx ?? 0.0;
        } else {
          neighborXs.sort();
          medianX[id] = neighborXs[neighborXs.length ~/ 2]; // median
        }
      }

      // Sort by median X
      ids.sort((a, b) => (medianX[a] ?? 0.0).compareTo(medianX[b] ?? 0.0));

      // Re-assign X positions: spread evenly across the band's width
      // Use the existing X range but reorder the nodes within it
      final xs = ids.map((id) => positions[id]?.dx ?? 0.0).toList()..sort();
      for (int i = 0; i < ids.length; i++) {
        final id = ids[i];
        final y = gen * bandHeight;
        positions[id] = Offset(xs[i], y);
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 6.7: v5.102 — LABEL COLLISION AVOIDANCE
  // ═══════════════════════════════════════════════════════════════════

  /// Nudge X positions so that no two nodes in the same generation band
  /// are closer than a minimum horizontal gap.
  ///
  /// The gap scales with node count: more nodes = wider gap needed
  /// to keep labels legible. At 500+ nodes, the gap is ~80px (enough
  /// for a 2-letter initial + name label). At 50 nodes, ~120px.
  ///
  /// Algorithm: sort nodes by X within each band, then sweep left-to-right
  /// pushing any node that's too close to its left neighbor rightward.
  /// O(n log n) per band — scales linearly with total node count.
  void _avoidLabelCollisions({
    required Map<String, Offset> positions,
    required Map<String, int> generations,
    required Map<String, GraphPerson> personMap,
    required double bandHeight,
    required int nodeCount,
  }) {
    // Scale gap: wider for small families (more space), narrower for
    // large families (prevent canvas from becoming too wide).
    // v5.113: Increased gaps to match the full 72dp GraphNode widget.
    // The widget is 72dp diameter + 24px padding = ~96dp footprint.
    // At 50 nodes: 140px gap. At 500: 120px. At 2000: 100px.
    final minGap = nodeCount > 2000
        ? 100.0
        : nodeCount > 500
            ? 120.0
            : nodeCount > 100
                ? 130.0
                : 140.0;

    // Group by generation
    final genGroups = <int, List<String>>{};
    for (final entry in generations.entries) {
      genGroups.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    for (final gen in genGroups.keys) {
      final ids = genGroups[gen]!;
      if (ids.length <= 1) continue;

      // Sort by current X
      ids.sort((a, b) =>
          (positions[a]?.dx ?? 0.0).compareTo(positions[b]?.dx ?? 0.0));

      // Sweep: push right if too close to left neighbor
      double lastX = positions[ids.first]?.dx ?? 0.0;
      for (int i = 1; i < ids.length; i++) {
        final id = ids[i];
        final pos = positions[id];
        if (pos == null) continue;
        var newX = pos.dx;
        if (newX - lastX < minGap) {
          newX = lastX + minGap;
        }
        positions[id] = Offset(newX, pos.dy);
        lastX = newX;
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 6.8: v5.113 — 2D COLLISION RESOLUTION
  // ═══════════════════════════════════════════════════════════════════

  /// Resolve 2D overlaps between ALL nodes using an iterative push-apart
  /// algorithm.
  ///
  /// This is the ONLY pass in the production layout pipeline that detects
  /// true 2D (circle-vs-circle) overlaps. The previous _avoidLabelCollisions
  /// only enforced an X-gap within the same generation band, which left
  /// gaps:
  ///   • Nodes at the exact same (x, y) position (stacked duplicates)
  ///   • Nodes pushed to the same X by the barycenter reorder
  ///   • Cross-band overlaps when bands are dense
  ///
  /// Algorithm:
  ///   1. For each pair of nodes, compute the 2D distance.
  ///   2. If distance < minDistance, push both nodes apart along the
  ///      vector connecting them (50/50 displacement).
  ///   3. Clamp Y to the node's generation band so the hierarchical
  ///      band structure is preserved (Y = gen * bandHeight).
  ///   4. Repeat for maxIterations until no overlaps remain or the
  ///      iteration budget is exhausted.
  ///
  /// Performance: O(n² × iterations) per pass. For 714 nodes × 5
  /// iterations, that's ~2.5M pair checks — runs in <100ms on the
  /// compute isolate. For 2000+ nodes, iterations are reduced to 3
  /// to keep the isolate under 500ms.
  void _resolve2DCollisions({
    required Map<String, Offset> positions,
    required Map<String, int> generations,
    required int nodeCount,
    required double bandHeight,
  }) {
    if (positions.isEmpty || nodeCount <= 1) return;

    // Minimum distance between node centers (dp).
    // The full GraphNode widget is 72dp diameter + 24px padding = ~96dp
    // on each side. We want at least 100dp between centers so nodes
    // don't visually overlap. For large families we allow a slightly
    // smaller gap to prevent the canvas from becoming too wide.
    final minDistance = nodeCount > 2000
        ? 90.0
        : nodeCount > 500
            ? 100.0
            : 120.0;

    // Iteration count: more iterations = better convergence.
    // Scale down for very large families to keep the isolate fast.
    final maxIterations = nodeCount > 2000
        ? 3
        : nodeCount > 500
            ? 5
            : 8;

    final ids = positions.keys.toList();
    final n = ids.length;

    // v5.123 (PERF): Cache positions + generations in parallel LISTS so
    // the O(n²) pairwise scan touches plain array slots instead of two
    // hash-map lookups per pair. For 2,000 nodes that removes ~4M map
    // lookups per iteration. Position writes go back to the map ONLY
    // when an overlap is actually resolved (rare after the
    // label-collision sweep), and the caches are refreshed per
    // iteration so multi-pass convergence is unchanged.
    final minDistSq = minDistance * minDistance;
    for (int iteration = 0; iteration < maxIterations; iteration++) {
      int overlapsFound = 0;

      final xs = List<double>.filled(n, 0.0);
      final ys = List<double>.filled(n, 0.0);
      for (int i = 0; i < n; i++) {
        final p = positions[ids[i]]!;
        xs[i] = p.dx;
        ys[i] = p.dy;
      }

      // O(n²) pairwise check. For 714 nodes this is ~254k pairs — fast
      // enough on the compute isolate.
      for (int i = 0; i < n; i++) {
        final ax = xs[i];
        final ay = ys[i];

        for (int j = i + 1; j < n; j++) {
          // Fast reject: bands are `bandHeight` apart vertically, so any
          // pair from different bands with |Δy| >= minDistance can never
          // overlap — skip without the full distance math.
          final dy = ys[j] - ay;
          if (dy > minDistance || dy < -minDistance) continue;

          final dx = xs[j] - ax;
          final distSq = dx * dx + dy * dy;

          if (distSq < minDistSq && distSq > 0.001) {
            overlapsFound++;
            final dist = sqrt(distSq);
            // Push-apart amount: half the overlap on each side.
            final overlap = (minDistance - dist) / 2.0;
            // Unit vector from A to B.
            final ux = dx / dist;

            // Push B away from A (X-axis only — Y is clamped to band).
            final newBx = xs[j] + ux * overlap;
            // Push A away from B (X-axis only — Y is clamped to band).
            final newAx = ax - ux * overlap;

            // Clamp Y to the node's generation band so the hierarchical
            // band structure is preserved. This prevents the push-apart
            // from scattering nodes into wrong generations.
            final idA = ids[i];
            final idB = ids[j];
            final bandYA = (generations[idA] ?? 0) * bandHeight;
            final bandYB = (generations[idB] ?? 0) * bandHeight;

            positions[idA] = Offset(newAx, bandYA);
            positions[idB] = Offset(newBx, bandYB);
            xs[i] = newAx;
            xs[j] = newBx;
            ys[i] = bandYA;
            ys[j] = bandYB;
          } else if (distSq <= 0.001) {
            // Nodes at the exact same position — nudge B to the right.
            overlapsFound++;
            final idB = ids[j];
            final bandYB = (generations[idB] ?? 0) * bandHeight;
            final newBx = xs[j] + minDistance;
            positions[idB] = Offset(newBx, bandYB);
            xs[j] = newBx;
            ys[j] = bandYB;
          }
        }
      }

      // If no overlaps were found in this iteration, we're done.
      if (overlapsFound == 0) break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 7: NORMALIZE POSITIONS (translate to positive coordinates)
  // ═══════════════════════════════════════════════════════════════════

  /// Shift all positions so that minimum X and Y are at [canvasPadding].
  void _normalizePositions(
    Map<String, Offset> positions,
    Map<int, double> ringRadii,
  ) {
    if (positions.isEmpty) return;

    double minX = double.infinity;
    double minY = double.infinity;
    for (final pos in positions.values) {
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
    }

    final shiftX = canvasPadding - minX;
    final shiftY = canvasPadding - minY;

    for (final key in positions.keys.toList()) {
      final p = positions[key]!;
      positions[key] = Offset(p.dx + shiftX, p.dy + shiftY);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 8: COMPUTE CANVAS SIZE
  // ═══════════════════════════════════════════════════════════════════

  /// Compute canvas width and height from positions + outermost ring.
  (double, double) _computeCanvasSize(
    Map<String, Offset> positions,
    Map<int, double> ringRadii,
  ) {
    if (positions.isEmpty) return (0.0, 0.0);

    double maxX = 0;
    double maxY = 0;
    for (final pos in positions.values) {
      if (pos.dx + _nodeWidth > maxX) maxX = pos.dx + _nodeWidth;
      if (pos.dy + _nodeHeight > maxY) maxY = pos.dy + _nodeHeight;
    }

    return (
      maxX + canvasPadding,
      maxY + canvasPadding,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // PUBLIC UTILITY METHODS (backward-compatible)
  // ═══════════════════════════════════════════════════════════════════

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
