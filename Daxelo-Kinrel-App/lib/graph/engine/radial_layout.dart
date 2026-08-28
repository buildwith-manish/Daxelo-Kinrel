// lib/graph/engine/radial_layout.dart
//
// DAXELO KINREL — Radial Layout Engine
//
// Algebraic (non-simulation) concentric-ring layout optimized for
// 1,000–3,000 nodes. Target: 30 FPS at 3,000 nodes.
//
// Design principles:
//   - Anchor person at exact center of canvas
//   - Each concentric ring = one generation / relationship distance
//   - Ancestors (gen < 0) above center (270° trunk angle)
//   - Descendants (gen > 0) below center (90° trunk angle)
//   - Spouses on partner's ring with 90 dp angular offset
//   - No force simulation — pure trigonometric position calculation
//   - Compact spacing available for dense graphs

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/graph_layout_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// RADIAL LAYOUT CONFIG
// ═══════════════════════════════════════════════════════════════════════

/// Configuration for the [RadialLayout] engine.
class RadialLayoutConfig {
  /// Standard spacing between concentric rings (dp).
  final double ringSpacing;

  /// Compact spacing for dense graphs (dp).
  final double compactSpacing;

  /// Horizontal angular offset for spouses from partner (dp).
  final double spouseAngularOffset;

  /// Canvas padding around outermost ring (dp).
  final double canvasPadding;

  /// Base radius of the first ring around the anchor (dp).
  final double baseRadius;

  /// Whether to use compact spacing.
  final bool compact;

  /// Minimum angular gap between nodes on the same ring (radians).
  final double minAngularGap;

  const RadialLayoutConfig({
    this.ringSpacing = 180.0,
    this.compactSpacing = 120.0,
    this.spouseAngularOffset = 90.0,
    this.canvasPadding = 120.0,
    this.baseRadius = 160.0,
    this.compact = false,
    this.minAngularGap = 0.02,
  });

  /// Active ring spacing based on compact mode.
  double get activeSpacing => compact ? compactSpacing : ringSpacing;

  RadialLayoutConfig copyWith({
    double? ringSpacing,
    double? compactSpacing,
    double? spouseAngularOffset,
    double? canvasPadding,
    double? baseRadius,
    bool? compact,
    double? minAngularGap,
  }) {
    return RadialLayoutConfig(
      ringSpacing: ringSpacing ?? this.ringSpacing,
      compactSpacing: compactSpacing ?? this.compactSpacing,
      spouseAngularOffset: spouseAngularOffset ?? this.spouseAngularOffset,
      canvasPadding: canvasPadding ?? this.canvasPadding,
      baseRadius: baseRadius ?? this.baseRadius,
      compact: compact ?? this.compact,
      minAngularGap: minAngularGap ?? this.minAngularGap,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RADIAL LAYOUT
// ═══════════════════════════════════════════════════════════════════════

/// Radial layout engine for family graphs with 1,000–3,000 nodes.
///
/// Positions nodes on concentric rings using pure algebraic calculation —
/// no force simulation required. This ensures deterministic, fast layout
/// even at the upper end of the node range.
///
/// Ring assignment:
///   - Anchor (gen 0) sits at the center (radius 0)
///   - Each absolute generation index maps to a ring: radius = baseRadius + |gen| * activeSpacing
///   - Ancestors (gen < 0) are placed in the upper semicircle (trunk 270°)
///   - Descendants (gen > 0) are placed in the lower semicircle (trunk 90°)
///   - Spouses share their partner's ring with an angular offset
///
/// Usage:
/// ```dart
/// final layout = RadialLayout();
/// final result = layout.compute(persons: persons, relationships: relationships);
/// ```
class RadialLayout {
  RadialLayoutConfig _config;

  RadialLayout({RadialLayoutConfig? config})
      : _config = config ?? const RadialLayoutConfig();

  /// Current configuration.
  RadialLayoutConfig get config => _config;

  // ── Relationship key sets ─────────────────────────────────────────

  static const Set<String> _spouseKeys = {
    'spouse', 'husband', 'wife', 'partner',
  };

  static const Set<String> _siblingKeys = {
    'sibling', 'brother', 'sister',
  };

  static const Set<String> _parentKeys = {
    'parent', 'father', 'mother',
  };

  static const Set<String> _childKeys = {
    'child', 'son', 'daughter',
  };

  // ── Public API ────────────────────────────────────────────────────

  /// Compute the radial layout for the given graph data.
  ///
  /// Returns a [GraphLayoutResult] with positions, canvas dimensions,
  /// and ring metadata. Compatible with the existing [GraphLayoutService]
  /// output format.
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

    // Auto-enable compact for large graphs
    if (persons.length > 1500 && !_config.compact) {
      _config = _config.copyWith(compact: true);
    }

    // 1. Find the anchor person
    final anchor = _findAnchor(persons, anchorPersonId);

    // 2. Build lookup maps
    final personById = <String, GraphPerson>{
      for (final p in persons) p.id: p,
    };

    // 3. Build spouse map: personId → list of spouse personIds
    final spouseMap = <String, List<String>>{};
    for (final r in relationships) {
      if (_spouseKeys.contains(r.relationshipKey)) {
        spouseMap.putIfAbsent(r.fromPersonId, () => []).add(r.toPersonId);
        spouseMap.putIfAbsent(r.toPersonId, () => []).add(r.fromPersonId);
      }
    }

    // 4. Build parent-child map for line-of-descent alignment
    final childrenOf = <String, List<String>>{};
    for (final r in relationships) {
      if (_parentKeys.contains(r.relationshipKey)) {
        // toPerson is parent of fromPerson → fromPerson is child of toPerson
        childrenOf.putIfAbsent(r.toPersonId, () => []).add(r.fromPersonId);
      }
      if (_childKeys.contains(r.relationshipKey)) {
        // toPerson is child of fromPerson
        childrenOf.putIfAbsent(r.fromPersonId, () => []).add(r.toPersonId);
      }
    }

    // 5. Group persons by generation
    //
    // v5.114: Compute relationship-distance rings (hop count) from the
    // anchor using BFS. The stored generationIndex from the RPC is not
    // reliable for radial placement (it's often -degree for ALL nodes,
    // putting ancestors and descendants on the same ring).
    //
    // Instead, we compute the actual hop distance:
    //   - Anchor = ring 0 (center)
    //   - Direct neighbors (1 hop) = ring 1
    //   - Neighbors of neighbors (2 hops) = ring 2
    //   - etc.
    //
    // We also determine the DIRECTION (ancestor vs descendant) from the
    // relationship key so ancestors go to the upper semicircle and
    // descendants go to the lower semicircle:
    //   - parent/father/mother → ancestor (negative ring)
    //   - child/son/daughter → descendant (positive ring)
    //   - spouse/sibling → same ring as the connected person
    final hopDistance = _computeHopDistance(anchor.id, persons, relationships);

    // Assign signed generation: positive for descendants, negative for
    // ancestors, 0 for same-generation (spouse/sibling/anchor).
    final signedGen = <String, int>{};
    for (final person in persons) {
      final hops = hopDistance[person.id] ?? 0;
      if (person.id == anchor.id) {
        signedGen[person.id] = 0;
      } else {
        // Determine direction from the relationship connecting this
        // person to the anchor's neighborhood. Default to positive
        // (descendant) if we can't determine.
        final direction = _computeDirection(person.id, anchor.id, relationships);
        signedGen[person.id] = direction == -1 ? -hops : hops;
      }
    }

    final generationGroups = <int, List<GraphPerson>>{};
    for (final person in persons) {
      final gen = signedGen[person.id] ?? 0;
      generationGroups.putIfAbsent(gen, () => []).add(GraphPerson(
        id: person.id,
        name: person.name,
        gender: person.gender,
        generationIndex: gen,
        isAnchor: person.id == anchor.id,
        photoUrl: person.photoUrl,
        isDeceased: person.isDeceased,
        relationship: person.relationship,
        deletedAt: person.deletedAt,
      ));
    }

    // 6. Compute ring radii — use abs() for radius, but keep the sign
    // for trunk angle selection below.
    final ringRadii = <int, double>{};
    for (final gen in generationGroups.keys) {
      if (gen == 0) {
        ringRadii[gen] = 0.0;
      } else {
        ringRadii[gen] = _config.baseRadius + gen.abs() * _config.activeSpacing;
      }
    }

    // 7. Assign angular positions on each ring
    final positions = <String, Offset>{};
    final ringAngleOffsets = <int, double>{};

    // Place anchor at center
    final center = _computeCanvasCenter(ringRadii);
    positions[anchor.id] = center;

    // Determine trunk angles
    const ancestorTrunk = pi * 1.5; // 270°
    const descendantTrunk = pi * 0.5; // 90°

    // Process each generation ring
    final sortedGens = generationGroups.keys.toList()..sort();

    for (final gen in sortedGens) {
      if (gen == 0) {
        // Gen 0: anchor already placed; place siblings and anchor's spouse
        _placeGen0(
          generationGroups[gen]!,
          anchor,
          center,
          spouseMap,
          positions,
          ringAngleOffsets,
        );
        continue;
      }

      final radius = ringRadii[gen]!;
      final trunk = gen < 0 ? ancestorTrunk : descendantTrunk;
      final members = generationGroups[gen]!;

      // Separate spouses from non-spouses
      final placed = <String>{};
      final nonSpouseMembers = <GraphPerson>[];

      for (final person in members) {
        if (placed.contains(person.id)) continue;
        nonSpouseMembers.add(person);
      }

      // v5.116 (Task 7): Barycenter sort — group siblings under their
      // parent's angular sector to reduce edge crossings.
      //
      // For each person in generation N, find their parent in generation
      // N-1 (already placed on the previous ring), get the parent's
      // angle, and sort by that angle. This groups siblings together
      // in the same angular sector instead of interleaving them with
      // children of other parents.
      //
      // This is an ordering fix inside the existing radial placement
      // step — NOT a new layout algorithm. The same median-heuristic
      // is used by GraphLayoutService._barycenterReorder.
      //
      // v5.125 (Step 7): the lookup is now a three-tier FALLBACK chain:
      //   1. Parent/child relationship to a placed node (the original
      //      behaviour — strongest signal).
      //   2. ANY relationship (any key — spouse, in-law, cousin,
      //      grandparent-in-law, …) to an already-placed node. A person
      //      whose only connection to the placed set is a
      //      non-parent/child key (e.g. a father-in-law tied to his
      //      placed daughter-in-law) previously got NO angle and fell
      //      through to the end-of-ring fallback — landing far from
      //      their actual branch (the "Radha Menon / Vikram Mehta
      //      floating outlier" bug). Tier 2 pulls them into their
      //      connected node's angular sector.
      //   3. Neither exists → keep current order (sorted last, stable).
      if (gen.abs() >= 1 && nonSpouseMembers.length > 1) {
        // Build a parent lookup: personId → parent's angle (if placed).
        final parentAngle = <String, double>{};
        for (final person in nonSpouseMembers) {
          // Tier 1: find this person's parent in the relationships.
          for (final r in relationships) {
            String? parentId;
            if (_parentKeys.contains(r.relationshipKey) &&
                r.fromPersonId == person.id) {
              parentId = r.toPersonId;
            } else if (_childKeys.contains(r.relationshipKey) &&
                       r.toPersonId == person.id) {
              parentId = r.fromPersonId;
            }
            if (parentId != null && positions.containsKey(parentId)) {
              final pPos = positions[parentId]!;
              final angle = atan2(
                pPos.dy - center.dy,
                pPos.dx - center.dx,
              );
              parentAngle[person.id] = angle;
              break;
            }
          }
          // Tier 2 (v5.125 Step 7): no parent-type relationship to a
          // placed node — fall back to ANY relationship (any key) to
          // an already-placed node and use that node's angle. This is
          // a fallback tier, not a replacement: tier 1 above ran
          // first and only missing persons reach here.
          if (parentAngle.containsKey(person.id)) continue;
          for (final r in relationships) {
            String? connectedId;
            if (r.fromPersonId == person.id &&
                positions.containsKey(r.toPersonId)) {
              connectedId = r.toPersonId;
            } else if (r.toPersonId == person.id &&
                positions.containsKey(r.fromPersonId)) {
              connectedId = r.fromPersonId;
            }
            if (connectedId != null) {
              final cPos = positions[connectedId]!;
              parentAngle[person.id] = atan2(
                cPos.dy - center.dy,
                cPos.dx - center.dx,
              );
              break;
            }
          }
        }
        // Sort by parent's angle (fall back to current order for
        // persons with no placed parent).
        nonSpouseMembers.sort((a, b) {
          final aAngle = parentAngle[a.id];
          final bAngle = parentAngle[b.id];
          if (aAngle == null && bAngle == null) return 0;
          if (aAngle == null) return 1;
          if (bAngle == null) return -1;
          return aAngle.compareTo(bAngle);
        });
      }

      // Compute angular spread for this ring
      const arcFraction = 0.8; // 80% of semicircle
      final totalArc = pi * arcFraction;
      final nodeCount = nonSpouseMembers.length;
      if (nodeCount == 0) continue;

      final angularStep = nodeCount > 1
          ? totalArc / (nodeCount - 1)
          : 0.0;
      final startAngle = trunk - totalArc / 2;

      for (var i = 0; i < nonSpouseMembers.length; i++) {
        final person = nonSpouseMembers[i];
        if (positions.containsKey(person.id)) continue;

        final angle = startAngle + i * angularStep;
        final x = center.dx + radius * cos(angle);
        final y = center.dy + radius * sin(angle);
        positions[person.id] = Offset(x, y);

        // Place spouses of this person on the same ring
        _placeSpouses(
          person,
          radius,
          angle,
          center,
          spouseMap,
          personById,
          positions,
          placed,
        );
      }

      ringAngleOffsets[gen] = trunk;
    }

    // 8. Compute canvas dimensions
    final maxRadius = ringRadii.values.fold(0.0, max);
    final canvasWidth = (center.dx + maxRadius + _config.canvasPadding) * 2;
    final canvasHeight = (center.dy + maxRadius + _config.canvasPadding) * 2;

    return GraphLayoutResult(
      positions: positions,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      ringRadii: ringRadii,
      ringAngleOffsets: ringAngleOffsets,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────

  /// v5.114: Compute the hop distance (relationship distance) from the
  /// anchor to every other person using BFS.
  ///
  /// Returns a map: personId → hop count.
  /// The anchor itself has hop 0.
  Map<String, int> _computeHopDistance(
    String anchorId,
    List<GraphPerson> persons,
    List<GraphRelationship> relationships,
  ) {
    // Build undirected adjacency.
    final adjacency = <String, Set<String>>{};
    for (final r in relationships) {
      adjacency.putIfAbsent(r.fromPersonId, () => <String>{}).add(r.toPersonId);
      adjacency.putIfAbsent(r.toPersonId, () => <String>{}).add(r.fromPersonId);
    }

    final distances = <String, int>{anchorId: 0};
    final queue = <String>[anchorId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentDist = distances[current] ?? 0;
      final neighbors = adjacency[current] ?? <String>{};
      for (final neighbor in neighbors) {
        if (!distances.containsKey(neighbor)) {
          distances[neighbor] = currentDist + 1;
          queue.add(neighbor);
        }
      }
    }
    return distances;
  }

  /// v5.114: Determine whether a person is an ancestor (-1) or
  /// descendant (+1) of the anchor, based on the relationship keys
  /// connecting them.
  ///
  /// Returns -1 for ancestors (parent/father/mother), +1 for descendants
  /// (child/son/daughter), 0 for same-generation (spouse/sibling/in-law).
  ///
  /// v5.123 (DIRECTION FIX): The stored edge `from: A, to: B, key: X`
  /// means "B is the X of A" (A sees B as X) — the canonical convention
  /// used by GraphService.buildAdjacencyList,
  /// GraphLayoutService._assignGenerations, and
  /// buildCanonicalRelationshipEdge (see labelAtoB_convention_test).
  /// Both branches below were previously INVERTED, which placed
  /// ancestors in the descendant (lower) semicircle and vice versa —
  /// the root cause of crossed edges and the failing
  /// radial_layout_test ancestor/descendant assertions.
  int _computeDirection(
    String personId,
    String anchorId,
    List<GraphRelationship> relationships,
  ) {
    // Check direct relationships between this person and the anchor.
    for (final r in relationships) {
      final isPersonToAnchor =
          r.fromPersonId == personId && r.toPersonId == anchorId;
      final isAnchorToPerson =
          r.fromPersonId == anchorId && r.toPersonId == personId;

      if (isPersonToAnchor) {
        // person → anchor with key X: the ANCHOR is the X of person.
        // Parent-type key → anchor is person's parent → person is a
        // DESCENDANT of the anchor (+1).
        // Child-type key → anchor is person's child → person is an
        // ANCESTOR of the anchor (-1).
        if (_parentKeys.contains(r.relationshipKey)) return 1;
        if (_childKeys.contains(r.relationshipKey)) return -1;
      }
      if (isAnchorToPerson) {
        // anchor → person with key X: the PERSON is the X of anchor.
        // Parent-type key → person is anchor's parent → ANCESTOR (-1).
        // Child-type key → person is anchor's child → DESCENDANT (+1).
        if (_parentKeys.contains(r.relationshipKey)) return -1;
        if (_childKeys.contains(r.relationshipKey)) return 1;
      }
    }
    // Default: same generation (spouse, sibling, in-law, etc.)
    return 0;
  }

  /// Find the anchor person from the list.
  GraphPerson _findAnchor(List<GraphPerson> persons, String? anchorId) {
    if (anchorId != null) {
      final found = persons.where((p) => p.id == anchorId).firstOrNull;
      if (found != null) return found;
    }
    final flagged = persons.where((p) => p.isAnchor).firstOrNull;
    if (flagged != null) return flagged;
    return persons.first;
  }

  /// Compute the canvas center point from ring radii.
  Offset _computeCanvasCenter(Map<int, double> ringRadii) {
    final maxRadius = ringRadii.values.fold(0.0, max);
    final center = maxRadius + _config.canvasPadding;
    return Offset(center, center);
  }

  /// Place generation-0 members (anchor's siblings, anchor's spouse).
  void _placeGen0(
    List<GraphPerson> gen0Members,
    GraphPerson anchor,
    Offset center,
    Map<String, List<String>> spouseMap,
    Map<String, Offset> positions,
    Map<int, double> ringAngleOffsets,
  ) {
    // Anchor's spouse(s) placed adjacent on the anchor ring (radius 0 = center)
    // They get a horizontal offset since they share gen 0.
    //
    // v67 (BUG-14 FIX): The previous offset was 90dp, but with 72dp node
    // diameters, the two circles overlapped by 54dp. The fix uses an
    // offset of at least (nodeDiameter + gap) so the circles don't
    // overlap. We use 96dp (72 + 24 gap) for the first spouse, then
    // alternate sides.
    final anchorSpouses = spouseMap[anchor.id] ?? [];
    const nodeDiameter = 72.0;
    const spouseGap = 24.0;
    const spouseOffset = nodeDiameter + spouseGap; // 96dp
    for (var i = 0; i < anchorSpouses.length; i++) {
      final spouseId = anchorSpouses[i];
      if (positions.containsKey(spouseId)) continue;

      // Horizontal offset from anchor — alternate sides for multiple spouses
      final offset = spouseOffset * (i + 1) * (i.isEven ? 1 : -1);
      positions[spouseId] = Offset(center.dx + offset, center.dy);
    }

    // Siblings placed on a small ring around the anchor
    final siblings = gen0Members.where((p) =>
        p.id != anchor.id &&
        !anchorSpouses.contains(p.id) &&
        !positions.containsKey(p.id));

    final siblingList = siblings.toList();
    if (siblingList.isEmpty) return;

    const siblingRadius = 120.0;
    final angleStep = 2 * pi / (siblingList.length + anchorSpouses.length + 1);

    for (var i = 0; i < siblingList.length; i++) {
      final angle = angleStep * (i + 1);
      positions[siblingList[i].id] = Offset(
        center.dx + siblingRadius * cos(angle),
        center.dy + siblingRadius * sin(angle),
      );
    }

    ringAngleOffsets[0] = 0.0;
  }

  /// Place spouses of a person on the same ring with angular offset.
  void _placeSpouses(
    GraphPerson person,
    double radius,
    double baseAngle,
    Offset center,
    Map<String, List<String>> spouseMap,
    Map<String, GraphPerson> personById,
    Map<String, Offset> positions,
    Set<String> placed,
  ) {
    final spouses = spouseMap[person.id] ?? [];
    for (var i = 0; i < spouses.length; i++) {
      final spouseId = spouses[i];
      if (positions.containsKey(spouseId)) {
        placed.add(spouseId);
        continue;
      }

      final spousePerson = personById[spouseId];
      if (spousePerson == null) continue;

      // Angular offset: 90dp / radius gives radians, with sign alternating
      final angularOffset = (_config.spouseAngularOffset / radius) * (i + 1);
      final spouseAngle = baseAngle + angularOffset;

      final x = center.dx + radius * cos(spouseAngle);
      final y = center.dy + radius * sin(spouseAngle);
      positions[spouseId] = Offset(x, y);
      placed.add(spouseId);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RIVERPOD PROVIDERS
// ═══════════════════════════════════════════════════════════════════════

/// Provider for the [RadialLayout] engine.
final radialLayoutProvider = Provider<RadialLayout>((ref) {
  return RadialLayout();
});

/// Provider for computing a radial layout result.
///
/// Watch this provider to get the latest layout when input changes.
final radialLayoutResultProvider = Provider.family<GraphLayoutResult,
    ({List<GraphPerson> persons, List<GraphRelationship> relationships, String? anchorId})>(
  (ref, params) {
    final layout = ref.watch(radialLayoutProvider);
    return layout.compute(
      persons: params.persons,
      relationships: params.relationships,
      anchorPersonId: params.anchorId,
    );
  },
);
