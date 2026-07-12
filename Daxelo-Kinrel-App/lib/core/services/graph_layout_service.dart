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
// - Optional force-relaxation pass for medium-sized families (> 60 nodes)
// - Pure radial with angle jitter for very large families (> 1000 nodes)
// - Computes canvas dimensions from outermost ring + padding
//
// Angle convention (screen coordinates, Y-down):
//   0° = right, 90° = down, 180° = left, 270° = up

import 'dart:math';
import 'package:flutter/material.dart';

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

  const GraphRelationship({
    required this.id,
    required this.fromPersonId,
    required this.toPersonId,
    required this.relationshipKey,
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

  const GraphLayoutResult({
    required this.positions,
    required this.canvasWidth,
    required this.canvasHeight,
    this.ringRadii = const {},
    this.ringAngleOffsets = const {},
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
  ///
  /// Returns a [GraphLayoutResult] with personId → Offset positions,
  /// canvas dimensions, and ring metadata.
  GraphLayoutResult computeLayout({
    required List<GraphPerson> persons,
    required List<GraphRelationship> relationships,
    String? anchorPersonId,
    bool compactMode = false,
    Map<String, int>? kinshipGenerationMap,
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
    final n = persons.length;
    final useForceRelaxation = n > 60 && n <= 1000;
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

    // ── Step 6: Force-relaxation for medium families ──────────────────
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

    // ── Step 7: Translate positions so everything is in positive space ─
    _normalizePositions(positions, ringRadii);

    // ── Step 8: Compute canvas dimensions ─────────────────────────────
    final (cw, ch) = _computeCanvasSize(positions, ringRadii);

    return GraphLayoutResult(
      positions: positions,
      canvasWidth: cw,
      canvasHeight: ch,
      ringRadii: ringRadii,
      ringAngleOffsets: ringAngleOffsets,
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
      // v2.2: Look up the key in the kinshipGenerationMap FIRST. This
      // map contains all 5,359 Indian kinship types with their correct
      // generational distance from the viewer (e.g., "father" = -1,
      // "paternal_uncle" = -1, "cousin" = 0, "grandfather" = -2).
      //
      // If the map is not available or the key is not in it, fall back
      // to the hardcoded key sets (which cover ~38 common types).
      int fromToTo;
      if (kinshipGenerationMap != null &&
          kinshipGenerationMap.containsKey(rel.relationshipKey)) {
        fromToTo = kinshipGenerationMap[rel.relationshipKey]!;
      } else if (_grandparentKeys.contains(rel.relationshipKey)) {
        fromToTo = -2;
      } else if (_parentKeys.contains(rel.relationshipKey)) {
        fromToTo = -1;
      } else if (_grandchildKeys.contains(rel.relationshipKey)) {
        fromToTo = 2;
      } else if (_childKeys.contains(rel.relationshipKey)) {
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
