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
// v5.164 (LOCAL EXPANSION): reuse HierarchicalLayout's subtree-width
// algorithm for local fan-out of newly-revealed nodes.
import 'hierarchical_layout.dart' show HierarchicalLayout;

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

  // v5.131 (Bug 2 fix, direction classification): the original key
  // sets only covered the 4 canonical fundamental edges (parent/spouse/
  // child/sibling). Custom + step/adoptive/foster/half relationship keys
  // — exactly the kinds of keys that surface in the "+N" chips for
  // StepMother / HalfBrother / YakFather — were not recognized, so
  // `_computeDirection` returned 0 and the node was misclassified as
  // "same generation as anchor" even when it was actually an ancestor
  // or descendant. The fix expands the key sets to recognize all
  // parent-type and child-type variants. (BFS in `_computeHopDistance`
  // already traverses any edge regardless of key — this fix only
  // affects direction sign, not reachability.)
  static const Set<String> _spouseKeys = {
    'spouse', 'husband', 'wife', 'partner',
    'fiancé', 'fiancée', 'fiance', 'fiancee',
  };

  static const Set<String> _siblingKeys = {
    'sibling', 'brother', 'sister',
    'half_brother', 'half_sister', 'halfbrother', 'halfsister',
    'step_brother', 'step_sister', 'stepbrother', 'stepsister',
    'adopted_brother', 'adopted_sister', 'foster_brother', 'foster_sister',
    'elder_brother', 'elder_sister', 'younger_brother', 'younger_sister',
  };

  static const Set<String> _parentKeys = {
    'parent', 'father', 'mother',
    'step_father', 'step_mother', 'stepfather', 'stepmother',
    'adoptive_father', 'adoptive_mother', 'adopted_father', 'adopted_mother',
    'foster_father', 'foster_mother',
    'biological_father', 'biological_mother',
    'guardian_father', 'guardian_mother',
    // v5.131: truly custom keys (e.g. test fixtures like "yak_father")
    // are NOT in this set — they fall through to direction=0 (same-
    // generation as anchor). That's a direction misclassification but
    // not a pile-up: Bug 2's peripheral-ring fix catches unreachable
    // nodes, and reachable custom-key nodes still get a unique hop
    // distance. The trade-off is intentional — fragile suffix-matching
    // (e.g. treating "father_in_law" as ancestor because it ends with
    // "father") would be a worse bug than misclassifying custom keys.
  };

  static const Set<String> _childKeys = {
    'child', 'son', 'daughter',
    'step_son', 'step_daughter', 'stepson', 'stepdaughter',
    'adoptive_son', 'adoptive_daughter', 'adopted_son', 'adopted_daughter',
    'foster_son', 'foster_daughter',
    'biological_son', 'biological_daughter',
  };

  /// v5.167: Sibling labels — when labelAtoB is one of these, the edge
  /// connects two people at the SAME generation (not parent→child).
  /// Used to skip sibling edges in the local expansion grouping —
  /// siblings should NOT be placed as children (one generation below);
  /// they should stay at the same level as the node they're siblings with.
  /// Matches HierarchicalLayout._siblingLabels.
  static const Set<String> _siblingLabels = {
    'sibling', 'brother', 'sister',
    'half_brother', 'half_sister', 'halfbrother', 'halfsister',
    'step_brother', 'step_sister', 'stepbrother', 'stepsister',
    'elder_brother', 'elder_sister', 'younger_brother', 'younger_sister',
  };

  // ── Public API ────────────────────────────────────────────────────

  /// Compute the radial layout for the given graph data.
  ///
  /// Returns a [GraphLayoutResult] with positions, canvas dimensions,
  /// and ring metadata. Compatible with the existing [GraphLayoutService]
  /// output format.
  ///
  /// [preservePositions] (v5.161): when true, the de-overlap pass NEVER
  /// moves a node that was already placed at a valid position relative
  /// to every other settled node. Only newly-added nodes get pushed.
  /// This keeps unrelated branches stable when ONE branch expands —
  /// the user's "expanding one branch should not reposition everything"
  /// requirement. Defaults to false (the original full-relax behaviour)
  /// for backward compatibility.
  ///
  /// [previousPositions] (v5.161): the positions from the previous
  /// layout pass. When [preservePositions] is true, any node ID present
  /// in this map keeps its previous position (if it's still valid);
  /// only new nodes get a fresh placement. The anchor is ALWAYS pinned
  /// to the canvas center regardless.
  ///
  /// [expandedBranchRoots] (v5.161): the set of branch root IDs that
  /// have been expanded by the user. Used to assign each expanded
  /// branch its OWN angular sector (a wedge centered on the branch
  /// root's current angle) so sibling branches never visually merge.
  /// Empty by default (no expansion sectors needed).
  GraphLayoutResult compute({
    required List<GraphPerson> persons,
    required List<GraphRelationship> relationships,
    String? anchorPersonId,
    bool? compact,
    bool preservePositions = false,
    Map<String, Offset>? previousPositions,
    Set<String>? expandedBranchRoots,
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

    // v5.131 (Bug 2 fix): Compute the maximum reachable hop distance
    // BEFORE assigning signed generations. Unreachable nodes (no path
    // from the anchor through the visible-edge subgraph) previously
    // fell through to `hopDistance[id] ?? 0`, landing them on ring 0
    // alongside the anchor. When several such nodes existed (e.g. a
    // branch fetch returned persons without their connecting edges),
    // they all piled up at the anchor's position — the "fanned pile"
    // observed when revealing step/adoptive/half branches.
    //
    // Now: unreachable nodes get sent to a peripheral ring one hop
    // beyond the deepest reachable ring (maxHop + 1, positive
    // direction). They still render on the lower semicircle, evenly
    // spaced, far from the anchor — no pile-up, and they're visually
    // distinct as "loose ends" waiting for their connecting edges to
    // arrive (which usually happens on the next layout pass after
    // the fetch completes).
    int maxHop = 0;
    for (final h in hopDistance.values) {
      if (h > maxHop) maxHop = h;
    }
    // v5.134: Use a SEPARATE ring for unreachable nodes, placed BEYOND
    // the deepest reachable ring. The old code used maxHop + 1 which
    // could collide with a real descendant ring when maxHop was small.
    // Now we use maxHop + 2 to leave a visual gap, and track which
    // nodes are unreachable so the angular placement can spread them
    // across the FULL circle instead of clustering them at the end of
    // a semicircle arc (the root cause of the 'fan pile' overlap bug).
    final peripheralRing = maxHop + 2;
    final unreachableIds = <String>{};

    // Assign signed generation: positive for descendants, negative for
    // ancestors, 0 for same-generation (spouse/sibling/anchor).
    final signedGen = <String, int>{};
    for (final person in persons) {
      if (person.id == anchor.id) {
        signedGen[person.id] = 0;
        continue;
      }
      final hops = hopDistance[person.id];
      if (hops == null) {
        // v5.131: unreachable from anchor in the current visible-edge
        // subgraph — banish to the peripheral ring instead of ring 0.
        // v5.134: track unreachable IDs so the angular placement can
        // give them a dedicated full-circle spread.
        signedGen[person.id] = peripheralRing;
        unreachableIds.add(person.id);
        continue;
      }
      // Determine direction from the relationship connecting this
      // person to the anchor's neighborhood. Default to positive
      // (descendant) if we can't determine.
      final direction = _computeDirection(person.id, anchor.id, relationships);
      signedGen[person.id] = direction == -1 ? -hops : hops;
    }

    final generationGroups = <int, List<GraphPerson>>{};
    for (final person in persons) {
      // v5.134: Guard the ?? 0 fallback. signedGen is built for every
      // person in the loop above, so this should never be null. But if
      // it ever is (duplicate ID, race condition), send the node to the
      // peripheral ring instead of ring 0 to avoid pile-up.
      final gen = signedGen[person.id] ?? peripheralRing;
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

    // v5.161 (LAYOUT STABILITY): when preservePositions is true, seed
    // the positions map with the previous positions of every node that
    // was previously placed AND is still in the persons list. This
    // happens BEFORE the ring placement runs, so when the ring
    // placement iterates, it will SKIP nodes that already have a
    // position (the `if (positions.containsKey(person.id)) continue;`
    // check at the top of the per-ring loop).
    //
    // Nodes that are NEW (not in previousPositions) get a fresh radial
    // placement. Nodes that were previously placed KEEP their previous
    // position. The de-overlap pass then only pushes new nodes that
    // overlap with settled ones — settled ones stay put.
    //
    // The anchor itself is always overwritten above (centered), and
    // previous positions are translated to match the current center
    // (which may have shifted if the ring radii changed).
    if (preservePositions && previousPositions != null &&
        previousPositions.isNotEmpty) {
      // Compute the previous center (use the anchor's previous
      // position if available; otherwise infer from the average).
      final prevAnchorPos = previousPositions[anchor.id];
      final Offset prevCenter;
      if (prevAnchorPos != null) {
        prevCenter = prevAnchorPos;
      } else if (previousPositions.length > 1) {
        // Fall back to the centroid.
        double sx = 0, sy = 0;
        for (final p in previousPositions.values) {
          sx += p.dx;
          sy += p.dy;
        }
        prevCenter = Offset(sx / previousPositions.length,
            sy / previousPositions.length);
      } else {
        prevCenter = previousPositions.values.first;
      }
      // Translation vector: previous center → current center.
      final translateX = center.dx - prevCenter.dx;
      final translateY = center.dy - prevCenter.dy;

      // Seed positions for every previously-placed node that's still
      // in the persons set.
      final currentIds = <String>{for (final p in persons) p.id};
      for (final entry in previousPositions.entries) {
        if (entry.key == anchor.id) continue; // anchor already placed
        if (!currentIds.contains(entry.key)) continue;
        // Translate to the new center so the relative layout is
        // preserved.
        positions[entry.key] = Offset(
          entry.value.dx + translateX,
          entry.value.dy + translateY,
        );
      }

      // v5.164 (LOCAL EXPANSION LAYOUT): instead of letting new nodes
      // (not in previousPositions) fall through to the global ring-fill
      // placement, position them LOCALLY relative to their expansion
      // origin using HierarchicalLayout's subtree-width algorithm.
      //
      // For each new node, find its parent in the relationships. If the
      // parent is a settled node (already placed), use the parent's
      // position as the local origin and call
      // [HierarchicalLayout.computeLocalExpansionLayout] to position the
      // new node + its siblings as a small hierarchical tree hanging off
      // that parent. This makes edges SHORT (local, direct) instead of
      // long (ring-fill slot → connect after).
      //
      // New nodes whose parent is NOT in the settled set (e.g. both
      // parent and child are new) are left for the ring-fill pass — the
      // local layout only handles groups where the origin is already
      // placed, which is the common case (the user tapped a visible
      // branch bubble, revealing its hidden children).
      final newIds = currentIds.difference(positions.keys.toSet())
          ..remove(anchor.id);
      if (newIds.isNotEmpty) {
        // v5.167 (LABEL FIX): use labelAtoB (the SPECIFIC label like
        // 'son', 'daughter', 'father') instead of relationshipKey (which
        // is ALWAYS 'parent' for non-spouse edges due to the DB's
        // relationship_fundamental_edge_check constraint). Without this
        // fix, ALL edges match _parentKeys.contains('parent') → true,
        // so EVERY edge is treated as "toPerson is parent of fromPerson"
        // — even when labelAtoB='son' (meaning fromPerson IS the parent
        // and toPerson IS the child). This caused children to be placed
        // in the wrong direction relative to their parent.
        //
        // Also: skip sibling edges (labelAtoB='brother'/'sister') —
        // siblings are SAME-generation, not parent-child. Treating a
        // sibling as a child would place them one generation below,
        // creating a wrong hierarchy.
        final parentKeys = _parentKeys;
        final childKeys = _childKeys;
        final siblingLabels = _siblingLabels;
        final groupsByOrigin = <String, Set<String>>{};
        for (final r in relationships) {
          final fromId = r.fromPersonId;
          final toId = r.toPersonId;
          if (!newIds.contains(fromId) && !newIds.contains(toId)) continue;
          // v5.167: use labelAtoB (SPECIFIC) not relationshipKey (always 'parent').
          final key = (r.labelAtoB ?? r.relationshipKey).toLowerCase();
          // Skip sibling edges — they're same-generation, not parent-child.
          if (siblingLabels.contains(key)) continue;
          String? parentId;
          String? childId;
          if (parentKeys.contains(key)) {
            // toPerson is parent of fromPerson.
            parentId = toId;
            childId = fromId;
          } else if (childKeys.contains(key)) {
            // fromPerson is parent of toPerson.
            parentId = fromId;
            childId = toId;
          } else {
            continue;
          }
          // Only group if the parent is settled (already placed) and
          // the child is a new node.
          if (newIds.contains(childId) && positions.containsKey(parentId)) {
            groupsByOrigin.putIfAbsent(parentId, () => <String>{}).add(childId);
          }
        }

        // For each group, call HierarchicalLayout.computeLocalExpansionLayout.
        if (groupsByOrigin.isNotEmpty) {
          final hLayout = HierarchicalLayout();
          for (final entry in groupsByOrigin.entries) {
            final originId = entry.key;
            final revealed = entry.value;
            final originPos = positions[originId];
            if (originPos == null) continue;
            final result = hLayout.computeLocalExpansionLayout(
              originPersonId: originId,
              revealedIds: revealed,
              persons: persons,
              relationships: relationships,
              originPosition: originPos,
            );
            // Merge the locally-computed positions into the main map.
            // The ring placement loop will SKIP these (they're already
            // in `positions`).
            for (final posEntry in result.positions.entries) {
              positions[posEntry.key] = posEntry.value;
            }
            // Remove from newIds so they don't get ring-filled.
            newIds.removeAll(result.positionedIds);
          }
        }
        // Any remaining newIds (no settled parent found) fall through
        // to the ring-fill placement below — backward compatible.
      }
    }

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

        // v5.151 (LAYOUT FIX): Secondary sort by relationship category.
        // After the parent-angle sort groups siblings together, this
        // secondary sort ensures that within the same parent-angle
        // cluster, nodes are further ordered by their relationship
        // category (spouse → parent → child → sibling → grandparent →
        // aunt/uncle → cousin → inLaw → extended). This makes the fan
        // of lines from the anchor read as organized arcs (all siblings
        // together, all in-laws together) instead of chaotic
        // interleaved spaghetti.
        //
        // The category is derived from the relationship key to the
        // placed parent (or any placed connection). This is a stable
        // secondary sort — it only reorders within equal parent-angle
        // buckets, never across them.
        nonSpouseMembers.sort((a, b) {
          final aAngle = parentAngle[a.id];
          final bAngle = parentAngle[b.id];
          // If angles differ, keep the primary sort.
          if (aAngle != null && bAngle != null) {
            final cmp = aAngle.compareTo(bAngle);
            if (cmp != 0) return cmp;
          }
          // Equal parent angle (or both null) — sort by category rank.
          final aRank = _categoryRank(a.id, relationships, positions);
          final bRank = _categoryRank(b.id, relationships, positions);
          return aRank.compareTo(bRank);
        });
      }

      // v5.134: ADAPTIVE ARC — use a wider arc when a ring has many
      // nodes to prevent overlap/pile-up. The old code always used 80%
      // of a semicircle (0.8π), which at radius 780 with 40 nodes gives
      // only ~39px per node — well below the 72px node diameter, causing
      // the 'fan pile' overlap bug on dense peripheral rings.
      //
      // v5.136: MINIMUM ANGULAR STEP — compute the minimum angular gap
      // needed so that adjacent nodes on this ring are at least
      // (nodeDiameter + padding) pixels apart at the current radius.
      // If the arc would be too small to fit all nodes at this minimum
      // gap, expand the arc (up to the full circle). If even the full
      // circle isn't enough, the de-overlap pass will push them apart.
      //
      // Logic:
      //   1. Compute minAngularStep = (nodeDiameter + padding) / radius
      //   2. Compute requiredArc = nodeCount * minAngularStep
      //   3. totalArc = max(requiredArc, adaptiveArc, 0.8π)
      //   4. Cap at 2π (full circle)
      final nodeCount = nonSpouseMembers.length;
      if (nodeCount == 0) continue;

      // v5.134: Check if this ring contains unreachable nodes. If it
      // does, use the FULL circle for placement so they don't cluster
      // at the end of a semicircle arc.
      final hasUnreachable = nonSpouseMembers
          .any((p) => unreachableIds.contains(p.id));

      // v5.136: Compute the minimum angular step needed for nodes to
      // not overlap at this radius. nodeDiameter=72, padding=48 → 120px.
      // v5.153: Increased padding from 24→48 to match the new minDistance.
      // At radius 780, minAngularStep = 120/780 ≈ 0.154 rad ≈ 8.8°.
      const nodeDiameter = 72.0;
      const nodePadding = 48.0;
      final minAngularStep = radius > 0
          ? (nodeDiameter + nodePadding) / radius
          : 0.15;
      final requiredArc = nodeCount > 1
          ? nodeCount * minAngularStep
          : 0.0;

      // v5.134 original adaptive arc (for small node counts)
      final double adaptiveArc;
      if (hasUnreachable && nodeCount > 8) {
        adaptiveArc = 2 * pi;
      } else if (nodeCount > 50) {
        adaptiveArc = 2 * pi;
      } else if (nodeCount > 20) {
        adaptiveArc = 1.5 * pi;
      } else if (nodeCount > 8) {
        adaptiveArc = pi;
      } else {
        adaptiveArc = 0.8 * pi;
      }

      // v5.136: Use the LARGER of requiredArc, adaptiveArc, and 0.8π,
      // capped at 2π (full circle). This guarantees nodes are spaced
      // at least minAngularStep apart unless there are so many that
      // even the full circle can't fit them — in which case the
      // de-overlap pass handles it.
      final totalArc = (requiredArc > adaptiveArc ? requiredArc : adaptiveArc)
          .clamp(0.8 * pi, 2 * pi);

      final angularStep = nodeCount > 1
          ? totalArc / nodeCount
          : 0.0;
      // For full-circle placement, start at 0° (right side). For
      // semicircle placement, center on the trunk angle.
      final startAngle = totalArc >= 2 * pi
          ? 0.0
          : (totalArc >= 1.5 * pi
              ? trunk - totalArc / 2
              : trunk - totalArc / 2);

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

    // v5.134: POST-PLACEMENT DE-OVERLAP SAFETY NET.
    // Even with the adaptive arc, edge cases (duplicate positions from
    // spouse placement, rounding errors, or overlapping rings) can
    // produce nodes at near-identical coordinates. This pass nudges
    // any overlapping nodes apart by a minimum distance, guaranteeing
    // no two nodes render at the same point.
    //
    // v5.161 (LAYOUT STABILITY): when [preservePositions] is true and
    // [previousPositions] is provided, the de-overlap pass respects
    // nodes that were already placed — only newly-added nodes (those
    // NOT in previousPositions, OR those whose previous position is
    // now occupied by another node) get pushed. This is the "expand
    // only the local area, don't reposition everything" fix.
    //
    // v5.165 (ANCHOR PINNING): the anchor is ALWAYS settled — it must
    // NEVER be moved by the de-overlap pass, even during initial layout
    // (preservePositions=false). Without this, the anchor can be pushed
    // off-center by the more aggressive 180px/220px axis-aligned overlap
    // detection when many nodes cluster on ring 1. Adding the anchor to
    // settledNodeIds ensures `aSettled || bSettled` is true for any pair
    // involving the anchor, so the anchor stays at the canvas center.
    final settledNodeIds = (preservePositions && previousPositions != null)
        ? (previousPositions.keys.toSet()..add(anchor.id))
        : ({anchor.id});

    // v5.164 (SECTOR CONTAINMENT): compute each node's assigned angle
    // from its current position relative to the canvas center. This
    // constrains pushes so nodes slide along their ring (tangent)
    // instead of flying sideways into a different branch's territory.
    //
    // v5.164 (FIX): only use sector containment during EXPANSION
    // (preservePositions=true). During initial layout, the free-axis
    // push is needed to resolve dense rings (e.g. 30 nodes on a ring
    // that's too small for 132px spacing) — sector containment's
    // tangent projection reduces the effective push and prevents
    // full resolution. During expansion, settled nodes need
    // protection from cross-branch drift — sector containment
    // provides that without the dense-ring problem (expansions add
    // only ~15 new nodes, not 30).
    final Map<String, double>? nodeSectorAngles;
    if (preservePositions) {
      final angles = <String, double>{};
      for (final entry in positions.entries) {
        if (entry.key == anchor.id) continue;
        final dx = entry.value.dx - center.dx;
        final dy = entry.value.dy - center.dy;
        if (dx.abs() > 0.01 || dy.abs() > 0.01) {
          angles[entry.key] = atan2(dy, dx);
        }
      }
      nodeSectorAngles = angles;
    } else {
      nodeSectorAngles = null;
    }

    _deOverlapPositions(
      positions,
      persons,
      settledNodeIds: settledNodeIds,
      center: preservePositions ? center : null,
      nodeSectorAngles: nodeSectorAngles,
    );

    // v5.151 (LAYOUT FIX): Cluster children into tight angular wedges
    // near their parent's angle. This runs AFTER de-overlap so it can
    // compact children without worrying about overlaps (de-overlap
    // already resolved them). The wedge clustering reduces edge
    // crossings — lines from the anchor to one branch don't cross
    // lines to another branch.
    //
    // v5.161 (LAYOUT STABILITY): pass the same settled-node set so the
    // wedge compaction also doesn't move previously-placed nodes.
    _clusterChildrenIntoWedges(
      positions, persons, relationships, center,
      settledNodeIds: settledNodeIds,
    );
    // Re-run de-overlap after wedge clustering — the compaction may
    // have created new overlaps within a wedge.
    // v5.164: only use sector containment during expansion (same as
    // the first de-overlap call). During initial layout, free-axis
    // pushes resolve dense clusters better.
    if (nodeSectorAngles != null) {
      nodeSectorAngles.clear();
      for (final entry in positions.entries) {
        if (entry.key == anchor.id) continue;
        final dx = entry.value.dx - center.dx;
        final dy = entry.value.dy - center.dy;
        if (dx.abs() > 0.01 || dy.abs() > 0.01) {
          nodeSectorAngles[entry.key] = atan2(dy, dx);
        }
      }
    }
    _deOverlapPositions(
      positions,
      persons,
      settledNodeIds: settledNodeIds,
      center: nodeSectorAngles != null ? center : null,
      nodeSectorAngles: nodeSectorAngles,
    );

    // 8. Compute canvas dimensions
    // v5.134: Account for peripheral ring radius which may not be in
    // ringRadii if all peripheral-ring nodes were unreachable.
    //
    // v5.161 (AUTO-GROW CANVAS): scale canvasPadding with node count so
    // dense graphs get more breathing room without squeezing nodes. The
    // user's request: "instead of squeezing more nodes into the same
    // fixed area, let the canvas grow (with pan/zoom already supported)
    // so density stays consistent no matter how many branches are open."
    //
    // Formula: padding = basePadding + (nodeCount - 30) * 1.5dp, capped
    // at 320dp. So a 30-node graph keeps the original 120dp; a 100-node
    // graph gets 225dp; a 200-node graph gets the cap of 320dp. This
    // grows the canvas in every direction as branches expand, keeping
    // the on-screen density roughly constant.
    final allRadii = <double>[
      ...ringRadii.values,
      if (peripheralRing > 0)
        _config.baseRadius + peripheralRing.abs() * _config.activeSpacing,
    ];
    final maxRadius = allRadii.fold(0.0, max);
    final nodeCount = persons.length;
    final grownPadding = (_config.canvasPadding +
            (nodeCount > 30 ? (nodeCount - 30) * 1.5 : 0.0))
        .clamp(_config.canvasPadding, 320.0);
    final canvasWidth = (center.dx + maxRadius + grownPadding) * 2;
    final canvasHeight = (center.dy + maxRadius + grownPadding) * 2;

    return GraphLayoutResult(
      positions: positions,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      ringRadii: ringRadii,
      ringAngleOffsets: ringAngleOffsets,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────

  /// v5.134: POST-PLACEMENT DE-OVERLAP SAFETY NET.
  ///
  /// Iterates over all placed positions and nudges any pair of nodes
  /// that are closer than [minDistance] apart. This is a lightweight
  /// O(n²) pass that runs after the initial placement — it's NOT a
  /// force simulation. It catches edge cases that the angular placement
  /// can't handle:
  ///   - Spouses placed at the same angle as their partner on a dense
  ///     ring
  ///   - Nodes from different rings that happen to land at the same
  ///     (x, y) due to radius collision (e.g. gen +3 and gen -3 share
  ///     the same radius)
  ///   - Rounding errors that place two nodes within sub-pixel distance
  ///
  /// v5.151 (LAYOUT FIX): Returns a rank (0-9) for the relationship
  /// category of [personId] relative to its placed connections. Lower
  /// rank = closer relationship = placed earlier in the ring arc.
  ///
  /// This is used as a SECONDARY sort key after the parent-angle sort.
  /// It groups same-category nodes (all siblings, all in-laws) into
  /// contiguous angular arcs so the fan of lines from the anchor reads
  /// as organized arcs instead of crossing spaghetti.
  ///
  /// Rank mapping (matches kProximityCategoryKeepPriority):
  ///   0 = self (anchor)
  ///   1 = spouse
  ///   2 = parent
  ///   3 = child
  ///   4 = sibling
  ///   5 = grandparent
  ///   6 = aunt/uncle
  ///   7 = cousin
  ///   8 = in-law
  ///   9 = extended/unknown
  int _categoryRank(
    String personId,
    List<GraphRelationship> relationships,
    Map<String, Offset> positions,
  ) {
    // Find the relationship key to the first placed connection.
    for (final r in relationships) {
      if (r.fromPersonId == personId && positions.containsKey(r.toPersonId)) {
        return _keyToRank(r.relationshipKey);
      }
      if (r.toPersonId == personId && positions.containsKey(r.fromPersonId)) {
        return _keyToRank(r.relationshipKey);
      }
    }
    return 9; // unknown / no placed connection
  }

  /// Maps a relationship key string to a category rank.
  int _keyToRank(String key) {
    if (_spouseKeys.contains(key)) return 1;
    if (_parentKeys.contains(key)) return 2;
    if (_childKeys.contains(key)) return 3;
    if (_siblingKeys.contains(key)) return 4;
    // Grandparents
    if (key.contains('grand') && (key.contains('father') || key.contains('mother'))) {
      return 5;
    }
    // Aunt/uncle
    if (key.contains('uncle') || key.contains('aunt')) return 6;
    // Cousin
    if (key.contains('cousin')) return 7;
    // In-laws
    if (key.contains('in_law') || key.contains('inlaw') ||
        key.contains('father_in_law') || key.contains('mother_in_law') ||
        key.contains('brother_in_law') || key.contains('sister_in_law') ||
        key.contains('husbands_') || key.contains('wifes_') ||
        key.contains('sons_wife') || key.contains('daughters_husband')) {
      return 8;
    }
    return 9; // extended / unknown
  }

  /// v5.151 (LAYOUT FIX): Clusters children of the same parent into a
  /// tight angular wedge near the parent's angle, instead of spreading
  /// them across the full ring. This reduces edge crossings — lines
  /// from the anchor to one branch don't cross lines to another branch.
  ///
  /// Called after the initial ring placement to NUDGE children toward
  /// their parent's angle. The nudge is bounded so it doesn't override
  /// the de-overlap pass — it only compacts children into a wedge when
  /// they were spread too far apart.
  ///
  /// v5.161 (LAYOUT STABILITY): [settledNodeIds] is the set of node IDs
  /// whose positions are "settled" from the previous layout pass. When
  /// provided, settled children KEEP their previous angle — only
  /// newly-added children get redistributed into the wedge. This
  /// prevents an unrelated sibling group from jumping when ONE branch
  /// expands.
  void _clusterChildrenIntoWedges(
    Map<String, Offset> positions,
    List<GraphPerson> persons,
    List<GraphRelationship> relationships,
    Offset center, {
    Set<String>? settledNodeIds,
  }) {
    // Build: parentId → list of child positions (already placed).
    final childrenOf = <String, List<String>>{};
    for (final r in relationships) {
      if (_parentKeys.contains(r.relationshipKey)) {
        childrenOf.putIfAbsent(r.toPersonId, () => []).add(r.fromPersonId);
      }
      if (_childKeys.contains(r.relationshipKey)) {
        childrenOf.putIfAbsent(r.fromPersonId, () => []).add(r.toPersonId);
      }
    }

    // For each parent with >3 children, compact the children into a
    // tighter wedge around the parent's angle.
    for (final entry in childrenOf.entries) {
      final parentId = entry.key;
      final childIds = entry.value;
      if (childIds.length < 4) continue; // only cluster large sibling groups
      final parentPos = positions[parentId];
      if (parentPos == null) continue;

      final parentAngle = atan2(
        parentPos.dy - center.dy,
        parentPos.dx - center.dx,
      );
      final parentRadius = (parentPos - center).distance;
      if (parentRadius < 1) continue;

      // Collect placed children with their current angles.
      final placedChildren = <(String, double)>[]; // (id, currentAngle)
      for (final cid in childIds) {
        final cpos = positions[cid];
        if (cpos == null) continue;
        final cAngle = atan2(cpos.dy - center.dy, cpos.dx - center.dx);
        placedChildren.add((cid, cAngle));
      }
      if (placedChildren.length < 4) continue;

      // v5.161 (LAYOUT STABILITY): if every child is settled, skip the
      // redistribution entirely — their angles are already validated
      // from the previous pass and the user has seen them there.
      // Moving them would violate the "don't reposition everything"
      // requirement.
      if (settledNodeIds != null &&
          placedChildren.every((c) => settledNodeIds.contains(c.$1))) {
        continue;
      }

      // Sort children by their current angle.
      placedChildren.sort((a, b) => a.$2.compareTo(b.$2));

      // Compute the current angular spread (max - min).
      final minAngle = placedChildren.first.$2;
      final maxAngle = placedChildren.last.$2;
      final currentSpread = _angleDistance(maxAngle, minAngle);

      // Target spread: enough to fit all children at minAngularGap.
      // Don't compact if they're already within a tight wedge.
      final childRadius = (positions[placedChildren.first.$1]! - center).distance;
      final minGap = childRadius > 0 ? (72.0 + 48.0) / childRadius : 0.15;
      final targetSpread = (placedChildren.length * minGap).clamp(minGap, pi * 0.8);

      if (currentSpread <= targetSpread) continue; // already compact

      // Redistribute children evenly within targetSpread, centered on
      // the parent's angle.
      final step = placedChildren.length > 1
          ? targetSpread / (placedChildren.length - 1)
          : 0.0;
      final startAngle = parentAngle - targetSpread / 2;

      for (var i = 0; i < placedChildren.length; i++) {
        final cid = placedChildren[i].$1;
        // v5.161: don't move settled children — keep their previous
        // angle so the user doesn't see them jump.
        if (settledNodeIds?.contains(cid) ?? false) continue;
        final newAngle = startAngle + i * step;
        final r = (positions[cid]! - center).distance;
        positions[cid] = Offset(
          center.dx + r * cos(newAngle),
          center.dy + r * sin(newAngle),
        );
      }
    }
  }

  /// Returns the shortest angular distance between two angles (0..π).
  double _angleDistance(double a, double b) {
    var d = (a - b).abs() % (2 * pi);
    if (d > pi) d = 2 * pi - d;
    return d;
  }

  /// v5.136: Increased minDistance from 60 to 96 (72px node diameter +
  /// 24px padding) so nodes NEVER touch, even after branch expansion.
  /// Increased maxIterations from 5 to 12 to fully resolve cascading
  /// overlaps in dense graphs (50+ nodes on a single ring).
  ///
  /// The nudge pushes both nodes apart along the line connecting them.
  /// The anchor is never moved.
  ///
  /// v5.161 (LAYOUT STABILITY): [settledNodeIds] is the set of node IDs
  /// whose positions are "settled" — they were placed in a previous
  /// layout pass and the user has already seen them there. When this
  /// set is non-null, the de-overlap pass ONLY moves nodes that are NOT
  /// in the set (i.e., newly-added nodes). Settled nodes that overlap
  /// with a new node push the NEW node out of the way; the settled
  /// node stays put. This implements the user's "expand only the local
  /// area, don't reposition everything" requirement: unrelated branches
  /// stay stable when ONE branch expands.
  ///
  /// If [settledNodeIds] is null (the default), the original full-relax
  /// behaviour applies — both nodes in an overlapping pair are pushed.
  ///
  /// v5.164 (SECTOR CONTAINMENT): when [center] + [nodeSectorAngles] are
  /// provided, the push is projected onto each node's TANGENT (arc
  /// direction) first — the node slides along its assigned ring instead
  /// of flying sideways into a different branch's territory. If the
  /// tangent push is insufficient (still overlapping after the tangent
  /// move), the node is pushed RADIALLY outward (to a wider ring) —
  /// staying in its angular sector but moving further from the center.
  /// This fixes the "Arjun Patel / Ritu Patel / DG / CM scattered away
  /// with long edges" bug: nodes can no longer be shoved into unrelated
  /// territory to resolve a collision.
  ///
  /// When [center] is null (no sector data available), the original
  /// 50/50 push-apart behaviour applies — backward compatible.
  void _deOverlapPositions(
    Map<String, Offset> positions,
    List<GraphPerson> persons, {
    Set<String>? settledNodeIds,
    Offset? center,
    Map<String, double>? nodeSectorAngles,
  }) {
    // Skip if fewer than 2 nodes — can't overlap.
    if (positions.length < 2) return;

    // v5.165 (MINIMUM SPACING): separate horizontal and vertical minimums
    // per the user's explicit spec:
    //   Horizontal: >= 180px (prevents node + label overlap side-by-side)
    //   Vertical:   >= 220px (prevents node + label overlap row-to-row,
    //               accounts for 4-line labels extending below the circle)
    //
    // The overlap check is now AXIS-ALIGNED (not Euclidean): two nodes
    // overlap if AND ONLY IF |dx| < minHorizontal AND |dy| < minVertical.
    // The push is along the axis with the SMALLER overlap (the axis
    // needing less displacement to resolve). This produces cleaner
    // horizontal rows and vertical columns than Euclidean pushes.
    const minHorizontal = 180.0;
    const minVertical = 220.0;

    // v5.164 (DISPLACEMENT CAP REMOVED): the original v5.164 work added
    // a maxDisplacement cap (108px) to prevent long-distance relocation.
    // However, this conflicts with the minimum spacing guarantee.
    // The SECTOR CONTAINMENT (tangent push) is the real fix for
    // cross-branch drift. Removed.
    // const maxDisplacement = 108.0;

    // v5.164: only apply sector containment when we have BOTH the center
    // and per-node angle data. When absent, fall back to the original
    // 50/50 push-apart (backward compat for any caller that doesn't
    // pass sector data — e.g. tests).
    final useSectorContainment =
        center != null && nodeSectorAngles != null && nodeSectorAngles.isNotEmpty;

    final ids = positions.keys.toList();
    var overlapsFound = true;
    var iterations = 0;
    // v5.153: Increased from 12 to 20 iterations. Dense chains (like
    // SP→KS→MG→MM→AJ→SI→RI) need more passes to fully resolve because
    // each push creates a new overlap with the next node in the chain.
    // v5.161: Increased to 25 — when only NEW nodes are being pushed
    // (settled-node mode), each new node may collide with multiple
    // settled nodes in sequence, requiring more iterations to converge.
    // v5.164: Increased to 30 — sector-constrained pushes (tangent +
    // free-axis fallback for same-angle pairs) need more iterations
    // to fully separate dense clusters.
    const maxIterations = 30;

    while (overlapsFound && iterations < maxIterations) {
      overlapsFound = false;
      iterations++;

      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final idA = ids[i];
          final idB = ids[j];
          final a = positions[idA]!;
          final b = positions[idB]!;
          final dx = b.dx - a.dx;
          final dy = b.dy - a.dy;

          // v5.165 (AXIS-ALIGNED OVERLAP): two nodes overlap if AND
          // ONLY IF |dx| < minHorizontal AND |dy| < minVertical. This
          // is a bounding-box check, not Euclidean — it enforces the
          // user's explicit 180px H / 220px V spacing requirements.
          final absDx = dx.abs();
          final absDy = dy.abs();
          final hOverlap = minHorizontal - absDx;
          final vOverlap = minVertical - absDy;

          if (hOverlap > 0 && vOverlap > 0) {
            // Determine which (if any) of the two nodes is settled.
            final aSettled = settledNodeIds?.contains(idA) ?? false;
            final bSettled = settledNodeIds?.contains(idB) ?? false;

            // Both settled → leave alone (rare; would have been a bug
            // in the previous layout pass).
            if (aSettled && bSettled) continue;

            overlapsFound = true;

            // v5.165: push along the axis with the SMALLER overlap
            // (the axis needing less displacement to resolve). This
            // produces cleaner rows/columns than pushing diagonally.
            final pushHorizontal = hOverlap <= vOverlap;

            if (dx.abs() < 0.01 && dy.abs() < 0.01) {
              // Exact same position — nudge B in X (fallback).
              if (aSettled) {
                positions[idB] = Offset(b.dx + minHorizontal, b.dy);
              } else if (bSettled) {
                positions[idA] = Offset(a.dx - minHorizontal, a.dy);
              } else {
                positions[idB] = Offset(b.dx + minHorizontal, b.dy);
              }
            } else if (pushHorizontal) {
              // Push along X axis — resolve horizontal overlap.
              final sign = dx >= 0 ? 1.0 : -1.0;
              final push = hOverlap / 2 + 2.0;
              if (useSectorContainment) {
                _pushNodeWithSectorContainment(
                  positions: positions,
                  nodeId: idA,
                  currentPos: a,
                  pushDx: -sign * push,
                  pushDy: 0.0,
                  center: center,
                  sectorAngles: nodeSectorAngles,
                  settled: aSettled,
                );
                _pushNodeWithSectorContainment(
                  positions: positions,
                  nodeId: idB,
                  currentPos: b,
                  pushDx: sign * push,
                  pushDy: 0.0,
                  center: center,
                  sectorAngles: nodeSectorAngles,
                  settled: bSettled,
                );
              } else {
                if (aSettled) {
                  positions[idB] = Offset(b.dx + sign * push * 2, b.dy);
                } else if (bSettled) {
                  positions[idA] = Offset(a.dx - sign * push * 2, a.dy);
                } else {
                  positions[idA] = Offset(a.dx - sign * push, a.dy);
                  positions[idB] = Offset(b.dx + sign * push, b.dy);
                }
              }
            } else {
              // Push along Y axis — resolve vertical overlap.
              final sign = dy >= 0 ? 1.0 : -1.0;
              final push = vOverlap / 2 + 2.0;
              if (useSectorContainment) {
                _pushNodeWithSectorContainment(
                  positions: positions,
                  nodeId: idA,
                  currentPos: a,
                  pushDx: 0.0,
                  pushDy: -sign * push,
                  center: center,
                  sectorAngles: nodeSectorAngles,
                  settled: aSettled,
                );
                _pushNodeWithSectorContainment(
                  positions: positions,
                  nodeId: idB,
                  currentPos: b,
                  pushDx: 0.0,
                  pushDy: sign * push,
                  center: center,
                  sectorAngles: nodeSectorAngles,
                  settled: bSettled,
                );
              } else {
                if (aSettled) {
                  positions[idB] = Offset(b.dx, b.dy + sign * push * 2);
                } else if (bSettled) {
                  positions[idA] = Offset(a.dx, a.dy - sign * push * 2);
                } else {
                  positions[idA] = Offset(a.dx, a.dy - sign * push);
                  positions[idB] = Offset(b.dx, b.dy + sign * push);
                }
              }
            }
          }
        }
      }
    }
  }

  /// v5.164 (SECTOR CONTAINMENT): pushes a single node while keeping it
  /// within its assigned angular sector.
  ///
  /// The push vector `(pushDx, pushDy)` is decomposed into:
  ///   1. The TANGENT component (along the ring's arc) — applied first.
  ///   2. The RADIAL component (outward from center) — applied if the
  ///      tangent component alone is insufficient to resolve the
  ///      overlap (less than 30% of the needed push).
  ///
  /// This keeps the node on its assigned ring (same radius) when
  /// possible, sliding it along the arc away from the collision. When
  /// sliding isn't enough (e.g. two nodes at the exact same angle),
  /// the node is pushed radially outward to a wider ring — but it
  /// stays at the same angle, so it doesn't cross into a sibling
  /// branch's territory.
  ///
  /// When [settled] is true, the node is NOT moved (settled nodes are
  /// immune to displacement — see v5.161).
  void _pushNodeWithSectorContainment({
    required Map<String, Offset> positions,
    required String nodeId,
    required Offset currentPos,
    required double pushDx,
    required double pushDy,
    required Offset center,
    required Map<String, double> sectorAngles,
    required bool settled,
  }) {
    if (settled) return; // v5.161: settled nodes never move.

    final angle = sectorAngles[nodeId];
    if (angle == null) {
      // No sector data for this node — fall back to a free push.
      positions[nodeId] = Offset(currentPos.dx + pushDx, currentPos.dy + pushDy);
      return;
    }

    // Tangent direction at `angle` (90° CCW from the radial direction).
    // Radial outward = (cos θ, sin θ); tangent = (-sin θ, cos θ).
    final tx = -sin(angle);
    final ty = cos(angle);

    // Decompose the push into tangent component.
    final tangentComponent = pushDx * tx + pushDy * ty;

    // The magnitude of the requested push.
    final pushMag = sqrt(pushDx * pushDx + pushDy * pushDy);
    final tangentAbs = tangentComponent.abs();

    // v5.164 (FIX): when the tangent component is too small (< 30% of
    // the needed push), the two nodes are at nearly the same angle —
    // pushing radially outward doesn't resolve their overlap (they
    // stay at the same angle, just on different rings). Instead, fall
    // back to a FREE-AXIS push (no sector containment) for this pair.
    // This allows the node to move in ANY direction to escape the
    // collision. The sector containment still applies to the MAJORITY
    // of pairs (those at different angles), preventing cross-branch
    // drift. Only same-angle pairs get the free-axis fallback.
    if (tangentAbs < pushMag * 0.3) {
      // Free-axis fallback — push in the original direction.
      positions[nodeId] = Offset(currentPos.dx + pushDx, currentPos.dy + pushDy);
      return;
    }

    // Tangent is sufficient — slide along the arc.
    final applyTangent = tangentComponent;
    final newDx = currentPos.dx + tx * applyTangent;
    final newDy = currentPos.dy + ty * applyTangent;
    positions[nodeId] = Offset(newDx, newDy);
  }

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
    const spouseGap = 48.0; // v5.153: increased to match minDistance padding
    const spouseOffset = nodeDiameter + spouseGap; // v5.153: 72+48=120dp
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
    // v5.136: Use a distance-based spouse offset instead of the raw
    // spouseAngularOffset (90°). The old code used 90/radius radians,
    // which at radius 480 gives only 90px — barely below the 96px
    // minimum distance. Now we compute the angular offset from the
    // desired arc distance (nodeDiameter + padding = 96px) so spouses
    // are always at least 96px apart from their partner.
    const nodeDiameter = 72.0;
    const spouseGap = 48.0; // v5.153: increased to match minDistance padding
    const spouseArcDistance = nodeDiameter + spouseGap; // v5.153: 120px

    for (var i = 0; i < spouses.length; i++) {
      final spouseId = spouses[i];
      if (positions.containsKey(spouseId)) {
        placed.add(spouseId);
        continue;
      }

      final spousePerson = personById[spouseId];
      if (spousePerson == null) continue;

      // v5.136: Compute angular offset from the desired arc distance.
      // angularOffset = arcDistance / radius (in radians)
      // Multiply by (i+1) so multiple spouses stack at increasing offsets.
      final angularOffset = radius > 0
          ? (spouseArcDistance / radius) * (i + 1)
          : 0.15 * (i + 1);
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
