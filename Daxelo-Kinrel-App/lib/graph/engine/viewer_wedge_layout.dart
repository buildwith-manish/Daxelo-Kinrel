// lib/graph/engine/viewer_wedge_layout.dart
//
// DAXELO KINREL — Viewer-Centered Wedge Layout Engine
//
// An overlap-free radial "wedge" layout centered on the viewer:
//   • The viewer is the root of a breadth-first tree at (0, 0).
//   • Each person has exactly ONE tree parent, found by shortest path
//     from the viewer (ties broken by closer relationship first — via
//     the kProximityCategoryKeepPriority ordering — then by lower id).
//   • Each EXPANDED person shows at most [WedgeLayoutConfig.pageSize]
//     children; when more remain, ONE extra leaf slot is reserved for
//     the "+N" chip (rendered by the existing chip widget at the slot
//     centre — chip visuals unchanged).
//   • Angular wedges are split among children in proportion to each
//     child's subtree weight, so branches never crowd shared rings.
//   • Ring radii satisfy BOTH a minimum gap AND an arc-space constraint
//     derived from each node's subtree node count at every relative
//     depth: r ≥ arcSpacing · count(depth) / wedgeAngle.
//   • A deterministic footprint-relaxation pass guarantees ZERO
//     axis-aligned box overlaps between node/chip footprints.
//
// This class is PURE DART: no widgets, no I/O, no force simulation. It
// returns the same Map<String, Offset> positions shape GraphLayoutResult
// already uses (viewer pinned at the origin; the provider translates
// into canvas space for rendering).
//
// See the accompanying tests under test/graph/engine/ for the contract:
// determinism, zero-overlap at any expansion level, restore-identical
// positions, shortest-path parents, budget enforcement.

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../../core/graph/graph_service.dart' show inverseTypeMap;
import '../../core/kinship/kinship_edge_style.dart'
    show KinshipEdgeCategory;
import '../../core/kinship/structural_kinship_classifier.dart'
    show StructuralKinshipClassifier;
// The node budget constant is REUSED from the existing collapse system —
// never hardcoded in this engine (the caller may still override).
import '../interaction/branch_collapse_state.dart' show kNodeBudget;

/// THE ONE BOOLEAN SWITCH.
///
/// When true, graphLayoutProvider computes positions with
/// [ViewerWedgeLayout] (viewer-centered "top 8 + chips + search").
/// When false, the ORIGINAL RadialLayout path runs exactly as before —
/// reverting is this single constant.
const bool kUseViewerWedgeLayout = true;

/// One undirected family link used to build the BFS tree.
///
/// Semantics of [keyAtoB]: "person [toId] is person [fromId]'s
/// `<keyAtoB>`" — the SAME contract as RelationshipData.labelAtoB.
/// [keyBtoA] is the reverse-direction label when the source row
/// provides one; otherwise the canonical [inverseTypeMap] resolves it.
class WedgeLink {
  const WedgeLink({
    required this.fromId,
    required this.toId,
    required this.relationshipKey,
    this.keyAtoB,
    this.keyBtoA,
  });

  final String fromId;
  final String toId;
  final String relationshipKey;
  final String? keyAtoB;
  final String? keyBtoA;
}

/// A reserved "+N" page-chip slot in the layout.
///
/// The chip is rendered by the EXISTING chip widget (unchanged visuals)
/// centred on [slotCenter].
class WedgePageChip {
  const WedgePageChip({
    required this.personId,
    required this.slotCenter,
    required this.remainingCount,
    required this.hasNested,
  });

  /// The EXPANDED person whose children overflow the current page.
  final String personId;

  /// Layout-space centre of the reserved chip slot.
  final Offset slotCenter;

  /// How many more children exist beyond the currently shown page.
  final int remainingCount;

  /// Whether any hidden child itself has children (tree glyph vs chevron).
  final bool hasNested;
}

/// Output of [ViewerWedgeLayout.compute].
class WedgeLayoutOutput {
  const WedgeLayoutOutput({
    required this.positions,
    required this.pageChips,
    required this.depthById,
    required this.parentOf,
    required this.visibleIds,
    required this.extentSize,
  });

  /// Person id → position. ALWAYS contains the viewer at (0, 0).
  final Map<String, Offset> positions;

  /// Person id → reserved "+N" chip slot (only expanded persons with
  /// more children than the current page shows).
  final Map<String, WedgePageChip> pageChips;

  /// Ring (BFS depth) per positioned person. Viewer = 0.
  final Map<String, int> depthById;

  /// Tree parent per person (viewer maps to null). Parents always lie
  /// on a shortest path from the viewer.
  final Map<String, String?> parentOf;

  /// The ids that received positions (the paged visible set).
  final Set<String> visibleIds;

  /// (width, height) of the axis-aligned bounding box around every
  /// footprint, padding included.
  final Size extentSize;
}

/// All tunable constants for the wedge layout in ONE class.
class WedgeLayoutConfig {
  const WedgeLayoutConfig({
    this.pageSize = 8,
    this.rootFootprint = const Size(124, 140),
    this.nodeFootprint = const Size(124, 128),
    // The "+N" page bubble is now node-sized (124×128, the same as
    // nodeFootprint) so it reads as part of the family of nodes —
    // same circle diameter, same reserved slot, same label space
    // below. The bubble widget itself draws a Ø72 circle (matching
    // GraphNode's default nodeSize) plus the "N more / Tap to show"
    // label underneath, so the full 124×128 footprint is consumed.
    // The no-overlap guarantee still holds: the layout engine treats
    // chip slots with the SAME footprint as nodes when scanning for
    // axis-aligned box overlaps.
    this.chipFootprint = const Size(124, 128),
    this.footprintPadding = 6.0,
    this.firstRingRadius = 220.0,
    this.minRingGap = 200.0,
    this.arcSpacing = 200.0,
    this.arcSpacingGrowth = 1.07,
    this.maxArcRelaxAttempts = 16,
    this.maxRadialPushPasses = 1024,
    this.startAngle = -math.pi / 2.0,
  });

  /// Maximum children shown per expanded person ("top 8").
  final int pageSize;

  /// Axis-aligned footprint of the viewer (root) node.
  final Size rootFootprint;

  /// Axis-aligned footprint of a normal node.
  final Size nodeFootprint;

  /// Axis-aligned footprint of a "+N" chip slot.
  final Size chipFootprint;

  /// Inflation added to every footprint box before overlap tests.
  final double footprintPadding;

  /// Radius of ring 1 (minimum).
  final double firstRingRadius;

  /// Minimum radial gap between consecutive rings.
  final double minRingGap;

  /// Arc space granted per subtree node (see ring constraint formula).
  final double arcSpacing;

  /// Multiplier applied to [arcSpacing] per relaxation attempt.
  final double arcSpacingGrowth;

  /// Maximum arc-relaxation attempts before radial pushes take over.
  final int maxArcRelaxAttempts;

  /// Hard cap on radial push passes (convergence guard).
  final int maxRadialPushPasses;

  /// Angle (radians) where the root's full-circle wedge starts.
  /// -pi/2 = screen-space "top" (Y grows downward).
  final double startAngle;
}

/// The viewer-centered overlap-free wedge layout.
class ViewerWedgeLayout {
  ViewerWedgeLayout({WedgeLayoutConfig? config})
      : _config = config ?? const WedgeLayoutConfig();

  final WedgeLayoutConfig _config;

  /// Insertion-order index: the order in which each person id first
  /// appears in the [links] list. Used as the tiebreaker in
  /// [compareChildren] so children keep the order their edges were
  /// declared in (matching the spec's "in that order"), instead of
  /// being sorted lexicographically (which puts r10 before r2).
  /// Built fresh on every [compute] call.
  Map<String, int> _orderIndex = const {};

  /// Mirror of kProximityCategoryKeepPriority (proximity_graph_state.dart).
  /// Local copy so the engine stays free of Riverpod/provider imports —
  /// kept in EXACT sync with the canonical ordering: closer relationships
  /// (spouse/parent/child/sibling) rank before distant ones.
  static const Map<KinshipEdgeCategory, int> _categoryRank = {
    KinshipEdgeCategory.self: 0,
    KinshipEdgeCategory.spouse: 1,
    KinshipEdgeCategory.parent: 2,
    KinshipEdgeCategory.child: 3,
    KinshipEdgeCategory.sibling: 4,
    KinshipEdgeCategory.grandparent: 5,
    KinshipEdgeCategory.auntUncle: 6,
    KinshipEdgeCategory.cousin: 7,
    KinshipEdgeCategory.inLaw: 8,
    KinshipEdgeCategory.extended: 9,
    KinshipEdgeCategory.indirect: 10,
  };

  static int _rankOfKey(String key) {
    if (key.isEmpty) return _categoryRank[KinshipEdgeCategory.extended]!;
    final category =
        StructuralKinshipClassifier.classify(path: [key]).category;
    return _categoryRank[category] ?? _categoryRank[KinshipEdgeCategory.extended]!;
  }

  static KinshipEdgeCategory _categoryOfKey(String key) {
    if (key.isEmpty) return KinshipEdgeCategory.extended;
    return StructuralKinshipClassifier.classify(path: [key]).category;
  }

  /// Computes the wedge layout.
  ///
  /// [loadedPersonIds] — persons whose data is fetched (position
  ///   candidates). The tree itself may reference unloaded persons
  ///   (via [links]) so "+N" counts stay truthful.
  /// [nameOf] — display names (deterministic child ordering).
  /// [links] — the full family edge list.
  /// [viewerId] — the root person.
  /// [expandedPersonIds] — persons whose children are shown (paged).
  /// [manualPages] — user-driven page indexes (+N chip taps).
  /// [expansionOrder] — expansion order, OLDEST first (LRU budget).
  /// [revealTargets] — search results that must be visible together
  ///   with their full path from the viewer (pages auto-selected).
  /// [rootFilter] — when set, the root shows only direct connections of
  ///   this category (the filter-chip selection).
  /// [protectedIds] — persons never auto-collapsed by the budget
  ///   (focus path, selection, search matches).
  /// [nodeBudget] — maximum positioned persons. Defaults to the
  ///   EXISTING [kNodeBudget] constant from branch_collapse_state.dart
  ///   (50) — the same budget the Show-All path uses.
  WedgeLayoutOutput compute({
    required Set<String> loadedPersonIds,
    required Map<String, String> nameOf,
    required List<WedgeLink> links,
    required String viewerId,
    required Set<String> expandedPersonIds,
    required Map<String, int> manualPages,
    required List<String> expansionOrder,
    Set<String> revealTargets = const {},
    KinshipEdgeCategory? rootFilter,
    Set<String> protectedIds = const {},
    int nodeBudget = kNodeBudget,
  }) {
    if (viewerId.isEmpty) {
      return _empty(viewerId);
    }

    // ── 1. Adjacency + walking keys ────────────────────────────────
    // keyTo[a][b] = relationship key meaning "b is a's <key>".
    final keyTo = <String, Map<String, String>>{};
    final adjacency = <String, Set<String>>{};
    // Build the insertion-order index: the order in which each person
    // first appears in the [links] list. Used by compareChildren as
    // the tiebreaker so children keep edge-list order (numeric:
    // r0, r1, r2, ...) instead of lexicographic order (r0, r1, r10, ...).
    _orderIndex = <String, int>{};
    var order = 0;
    // Ensure the viewer gets index 0 (it's the root, always first).
    _orderIndex[viewerId] = order++;
    for (final link in links) {
      final a = link.fromId;
      final b = link.toId;
      if (a.isEmpty || b.isEmpty || a == b) continue;
      if (!_orderIndex.containsKey(a)) _orderIndex[a] = order++;
      if (!_orderIndex.containsKey(b)) _orderIndex[b] = order++;
      adjacency.putIfAbsent(a, () => <String>{}).add(b);
      adjacency.putIfAbsent(b, () => <String>{}).add(a);
      final forward = link.keyAtoB ?? link.relationshipKey;
      keyTo.putIfAbsent(a, () => <String, String>{})[b] = forward;
      final backward = link.keyBtoA ??
          inverseTypeMap[forward] ??
          inverseTypeMap[link.relationshipKey] ??
          link.relationshipKey;
      keyTo.putIfAbsent(b, () => <String, String>{})[a] = backward;
    }

    // (Every endpoint of [links] plus [loadedPersonIds] plus the
    // viewer implicitly forms the known-person universe.)

    // ── 2. Deterministic BFS tree from the viewer ──────────────────
    // Ring-by-ring claim resolution: every person gets exactly ONE
    // parent on a SHORTEST path; closer relationships win ties, then
    // the lower parent id.
    final parentOf = <String, String?>{viewerId: null};
    final keyFromParent = <String, String>{};
    final depthOf = <String, int>{viewerId: 0};
    var currentRing = <String>[viewerId];
    while (currentRing.isNotEmpty) {
      final claims = <String, _Claim>{};
      final ringSorted = List<String>.from(currentRing)..sort();
      for (final parent in ringSorted) {
        final neighbors = adjacency[parent];
        if (neighbors == null || neighbors.isEmpty) continue;
        final neighborList = neighbors.toList()..sort();
        for (final child in neighborList) {
          if (parentOf.containsKey(child)) continue; // already claimed
          final key = keyTo[parent]?[child] ?? '';
          final claim = _Claim(parent, key);
          final existing = claims[child];
          if (existing == null || claim.isBetterThan(existing)) {
            claims[child] = claim;
          }
        }
      }
      if (claims.isEmpty) break;
      final claimedIds = claims.keys.toList()..sort();
      for (final child in claimedIds) {
        final claim = claims[child]!;
        parentOf[child] = claim.parent;
        keyFromParent[child] = claim.key;
        depthOf[child] = depthOf[claim.parent]! + 1;
      }
      currentRing = claimedIds;
    }
    if (parentOf.length <= 1) {
      return WedgeLayoutOutput(
        positions: {viewerId: Offset.zero},
        pageChips: const {},
        depthById: {viewerId: 0},
        parentOf: parentOf,
        visibleIds: {viewerId},
        extentSize: _config.rootFootprint,
      );
    }

    // ── 3. Ordered children lists ──────────────────────────────────
    // Ordered by closeness (category rank of the connecting edge),
    // then by INSERTION ORDER (the order in which each person first
    // appears in the [links] list). This matches the spec's "in rank
    // order" and "in that order" — when all relationships have the
    // same rank, children keep the order their edges were declared
    // in (numeric: r0, r1, r2, ... not lexicographic: r0, r1, r10, ...).
    //
    // The insertion order is tracked via _orderIndex, built from the
    // links list above. Persons not in the links get a high index
    // (sorted last), breaking ties by id.
    final childrenOf = <String, List<String>>{};
    parentOf.forEach((child, parent) {
      if (parent == null) return;
      childrenOf.putIfAbsent(parent, () => <String>[]).add(child);
    });
    int compareChildren(String a, String b) {
      final rankA = _rankOfKey(keyFromParent[a] ?? '');
      final rankB = _rankOfKey(keyFromParent[b] ?? '');
      if (rankA != rankB) return rankA.compareTo(rankB);
      // Tiebreak by insertion order (edge list order), not by name.
      final oa = _orderIndex[a] ?? 0x7FFFFFFF;
      final ob = _orderIndex[b] ?? 0x7FFFFFFF;
      if (oa != ob) return oa.compareTo(ob);
      return a.compareTo(b);
    }

    for (final entry in childrenOf.entries) {
      entry.value.sort(compareChildren);
    }

    // Root filter (filter chips): the root shows only direct
    // connections of the selected category.
    List<String> childrenOfPerson(String person) {
      final kids = childrenOf[person];
      if (kids == null) return const <String>[];
      if (person == viewerId && rootFilter != null) {
        return kids
            .where((k) => _categoryOfKey(keyFromParent[k] ?? '') == rootFilter)
            .toList(growable: false);
      }
      return kids;
    }

    // ── 4. Reveal paths (search): expand ancestors + page overrides ─
    final expandedEff = <String>{viewerId, ...expandedPersonIds};
    final pageOverride = <String, int>{};
    for (final target in revealTargets) {
      if (!parentOf.containsKey(target)) continue;
      var cursor = target;
      while (cursor != viewerId) {
        final parent = parentOf[cursor];
        if (parent == null) break;
        expandedEff.add(parent);
        final siblings = childrenOfPerson(parent);
        final idx = siblings.indexOf(cursor);
        if (idx >= 0) {
          final page = idx ~/ _config.pageSize;
          final existing = pageOverride[parent];
          if (existing == null || page < existing) {
            pageOverride[parent] = page;
          }
        }
        cursor = parent;
      }
    }

    // Protected set: never budget-collapsed. Includes the reveal path
    // (the focus path) plus caller-supplied protected ids.
    final protected = <String>{viewerId, ...protectedIds};
    for (final target in revealTargets) {
      var cursor = target;
      while (parentOf.containsKey(cursor) && cursor != viewerId) {
        protected.add(cursor);
        cursor = parentOf[cursor]!;
      }
    }

    // ── 5. Budget: collapse the branch opened LONGEST ago ──────────
    final orderedExpansions = <String>[
      ...expansionOrder,
      ...(expandedEff.difference(expansionOrder.toSet()).toList()..sort()),
    ];

    int pageOfPerson(String person, List<String> kids) {
      final maxPage =
          kids.isEmpty ? 0 : ((kids.length - 1) ~/ _config.pageSize);
      var page = pageOverride[person] ?? manualPages[person] ?? 0;
      if (page < 0) page = 0;
      if (page > maxPage) page = maxPage;
      return page;
    }

    var shown = _buildShownTree(
      viewerId: viewerId,
      expandedEff: expandedEff,
      childrenOfPerson: childrenOfPerson,
      pageOfPerson: pageOfPerson,
      loadedPersonIds: loadedPersonIds,
    );

    var guard = 0;
    while (shown.personCount > nodeBudget && guard++ < 512) {
      var dropped = false;
      for (final person in orderedExpansions) {
        if (person == viewerId) continue;
        if (protected.contains(person)) continue;
        if (!expandedEff.contains(person)) continue;
        expandedEff.remove(person);
        dropped = true;
        break;
      }
      if (!dropped) break; // nothing eligible left
      shown = _buildShownTree(
        viewerId: viewerId,
        expandedEff: expandedEff,
        childrenOfPerson: childrenOfPerson,
        pageOfPerson: pageOfPerson,
        loadedPersonIds: loadedPersonIds,
      );
    }

    // ── 6. Wedges → radii → positions (arc-relaxation loop) ────────
    var arcSpacing = _config.arcSpacing;
    WedgeLayoutOutput candidate = _layoutOnce(
      viewerId: viewerId,
      parentOf: parentOf,
      keyFromParent: keyFromParent,
      shown: shown,
      arcSpacing: arcSpacing,
    );
    for (var attempt = 0; attempt <= _config.maxArcRelaxAttempts; attempt++) {
      final overlaps = _countOverlaps(candidate, viewerId);
      if (overlaps == 0) return candidate;
      arcSpacing *= _config.arcSpacingGrowth;
      candidate = _layoutOnce(
        viewerId: viewerId,
        parentOf: parentOf,
        keyFromParent: keyFromParent,
        shown: shown,
        arcSpacing: arcSpacing,
      );
    }

    // ── 7. Deterministic radial push for any remaining conflict ────
    return _pushConflictsOutward(candidate, viewerId);
  }

  // ── internals ────────────────────────────────────────────────────

  static WedgeLayoutOutput _empty(String viewerId) => WedgeLayoutOutput(
        positions: viewerId.isEmpty ? const {} : {viewerId: Offset.zero},
        pageChips: const {},
        depthById: viewerId.isEmpty ? const {} : {viewerId: 0},
        parentOf: viewerId.isEmpty ? const {} : {viewerId: null},
        visibleIds: viewerId.isEmpty ? const {} : {viewerId},
        extentSize: const Size(124, 140),
      );

  /// Builds the paged visible tree: which persons are positioned and
  /// which "+N" chip slots exist.
  _ShownTree _buildShownTree({
    required String viewerId,
    required Set<String> expandedEff,
    required List<String> Function(String) childrenOfPerson,
    required int Function(String, List<String>) pageOfPerson,
    required Set<String> loadedPersonIds,
  }) {
    final shownChildren = <String, List<String>>{};
    final chipFor = <String, _ChipPlaceholder>{};
    final orderedExpanded = expandedEff.toList()..sort();

    for (final person in orderedExpanded) {
      final kids = childrenOfPerson(person);
      if (kids.isEmpty) continue;
      final page = pageOfPerson(person, kids);
      final sliceStart = page * _config.pageSize;
      final sliceEnd = sliceStart + _config.pageSize;
      final slice = kids.sublist(
        sliceStart.clamp(0, kids.length),
        sliceEnd.clamp(0, kids.length),
      );
      // Only loaded children can be positioned right now; the rest
      // appear when their branch fetch lands.
      shownChildren[person] = <String>[
        for (final k in slice) if (loadedPersonIds.contains(k)) k,
      ];
      final remaining = kids.length - sliceEnd;
      if (remaining > 0) {
        var hasNested = false;
        for (var i = sliceEnd; i < kids.length; i++) {
          if (childrenOfPerson(kids[i]).isNotEmpty) {
            hasNested = true;
            break;
          }
        }
        chipFor[person] = _ChipPlaceholder(
          remainingCount: remaining,
          hasNested: hasNested,
        );
      }
    }

    // Visible set: viewer + every shown child reachable from the root.
    final visible = <String>{viewerId};
    final stack = <String>[viewerId];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      final kids = shownChildren[current];
      if (kids == null) continue;
      for (final k in kids) {
        if (visible.add(k)) stack.add(k);
      }
    }

    return _ShownTree(
      shownChildren: shownChildren,
      chipFor: chipFor,
      visibleIds: visible,
    );
  }

  /// One deterministic layout pass: wedges → radii → positions.
  WedgeLayoutOutput _layoutOnce({
    required String viewerId,
    required Map<String, String?> parentOf,
    required Map<String, String> keyFromParent,
    required _ShownTree shown,
    required double arcSpacing,
  }) {
    // Chip slots participate in the tree as ONE extra leaf child of
    // each expanded person whose children overflow the current page.
    final structuralChildren = <String, List<String>>{};
    shown.shownChildren.forEach((parent, kids) {
      final withChip = List<String>.from(kids);
      if (shown.chipFor[parent] != null) {
        withChip.add(_chipId(parent));
      }
      structuralChildren[parent] = withChip;
    });

    // ── a. Subtree counts per relative depth → weight ─────────────
    final countByNode = <String, Map<int, int>>{};
    void accumulate(String node) {
      final own = <int, int>{0: 1};
      final kids = structuralChildren[node] ?? const <String>[];
      for (final child in kids) {
        if (countByNode.containsKey(child)) continue; // guard vs cycles
        accumulate(child);
        final childCounts = countByNode[child] ?? const <int, int>{};
        childCounts.forEach((depth, count) {
          own[depth + 1] = (own[depth + 1] ?? 0) + count;
        });
      }
      countByNode[node] = own;
    }

    accumulate(viewerId);

    int weightOf(String node) {
      final counts = countByNode[node] ?? const <int, int>{};
      var max = 1;
      for (final c in counts.values) {
        if (c > max) max = c;
      }
      return max;
    }

    // ── b. Wedge angles (breadth-first, stable child order) ───────
    final centerAngle = <String, double>{
      viewerId: _config.startAngle + math.pi,
    };
    final wedgeSpan = <String, double>{viewerId: 2 * math.pi};
    final ringOf = <String, int>{viewerId: 0};
    final queue = <String>[viewerId];
    var head = 0;
    while (head < queue.length) {
      final parent = queue[head++];
      final kids = structuralChildren[parent] ?? const <String>[];
      if (kids.isEmpty) continue;
      final span = wedgeSpan[parent]!;
      var totalWeight = 0;
      for (final k in kids) {
        totalWeight += weightOf(k);
      }
      if (totalWeight <= 0) totalWeight = 1;
      var cursor = centerAngle[parent]! - span / 2.0;
      for (final child in kids) {
        final w = weightOf(child);
        final childSpan = span * (w / totalWeight);
        centerAngle[child] = cursor + childSpan / 2.0;
        wedgeSpan[child] = childSpan;
        ringOf[child] = (ringOf[parent] ?? 0) + 1;
        queue.add(child);
        // ADVANCE the cursor to the next sibling's slice — without
        // this every child of a parent lands on the SAME ray (a bug
        // the old overlap resolution masked by pushing siblings into
        // a radial line, wasting enormous canvas space).
        cursor += childSpan;
      }
    }

    // ── c. Ring radii: base gaps + arc-space constraints ──────────
    // For every node, the ring at the node's own depth must have
    // radius at least arcSpacing * weight(node) / span(node). This
    // ensures the node's OWN wedge is wide enough to fit its
    // subtree's widest level. Nodes with large subtrees (e.g. an
    // expanded hub with 9 children) push their OWN ring outward,
    // which in turn pushes their siblings' ring outward too.
    var maxRing = 0;
    ringOf.forEach((_, ring) {
      if (ring > maxRing) maxRing = ring;
    });
    final radii = <double>[0.0]; // ring 0 = viewer at origin
    for (var ring = 1; ring <= maxRing; ring++) {
      var radius = ring == 1
          ? _config.firstRingRadius
          : radii[ring - 1] + _config.minRingGap;
      // Constraint 1: from ancestors ABOVE this ring. For each
      // ancestor at ring (ring - d), its level-d count must fit:
      // r >= arcSpacing * count / ancestor_span.
      ringOf.forEach((node, nodeRing) {
        if (nodeRing >= ring) return;
        final d = ring - nodeRing;
        final count = countByNode[node]?[d] ?? 0;
        if (count == 0) return;
        final span = wedgeSpan[node]!;
        final required = arcSpacing * count / span;
        if (required > radius) radius = required;
      });
      // Constraint 2: from nodes AT this ring. Each node's OWN
      // weight (its subtree's widest level) must fit in its wedge:
      // r >= arcSpacing * weight / node_span. This is what pushes
      // expanded hubs outward — their weight is large, their span
      // is small, so the required radius is large.
      ringOf.forEach((node, nodeRing) {
        if (nodeRing != ring) return;
        final w = weightOf(node);
        final span = wedgeSpan[node]!;
        if (span <= 0) return;
        final required = arcSpacing * w / span;
        if (required > radius) radius = required;
      });
      radii.add(radius);
    }

    // ── d. Positions ──────────────────────────────────────────────
    final positions = <String, Offset>{viewerId: Offset.zero};
    ringOf.forEach((node, ring) {
      if (node == viewerId) return;
      if (_isChipId(node)) return;
      if (!shown.visibleIds.contains(node)) return;
      if (ring >= radii.length) return;
      positions[node] = WedgeGeometry.polar(radii[ring], centerAngle[node]!);
    });

    final pageChips = <String, WedgePageChip>{};
    shown.chipFor.forEach((person, placeholder) {
      final chipNode = _chipId(person);
      final ring = ringOf[chipNode] ?? ((ringOf[person] ?? 0) + 1);
      final angle =
          centerAngle[chipNode] ?? (centerAngle[person] ?? _config.startAngle);
      final radius = ring < radii.length ? radii[ring] : radii.last;
      pageChips[person] = WedgePageChip(
        personId: person,
        slotCenter: WedgeGeometry.polar(radius, angle),
        remainingCount: placeholder.remainingCount,
        hasNested: placeholder.hasNested,
      );
    });

    final depthById = <String, int>{
      for (final id in positions.keys) id: (ringOf[id] ?? 0),
    };

    return WedgeLayoutOutput(
      positions: positions,
      pageChips: pageChips,
      depthById: depthById,
      parentOf: parentOf,
      visibleIds: shown.visibleIds,
      extentSize: _extentSize(viewerId, positions, pageChips),
    );
  }

  Size _extentSize(
    String viewerId,
    Map<String, Offset> positions,
    Map<String, WedgePageChip> pageChips,
  ) {
    var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0;
    positions.forEach((id, pos) {
      final f =
          id == viewerId ? _config.rootFootprint : _config.nodeFootprint;
      final half = f.width / 2 + _config.footprintPadding;
      final halfY = f.height / 2 + _config.footprintPadding;
      minX = math.min(minX, pos.dx - half);
      maxX = math.max(maxX, pos.dx + half);
      minY = math.min(minY, pos.dy - halfY);
      maxY = math.max(maxY, pos.dy + halfY);
    });
    pageChips.forEach((_, chip) {
      final half = _config.chipFootprint.width / 2 + _config.footprintPadding;
      final halfY =
          _config.chipFootprint.height / 2 + _config.footprintPadding;
      minX = math.min(minX, chip.slotCenter.dx - half);
      maxX = math.max(maxX, chip.slotCenter.dx + half);
      minY = math.min(minY, chip.slotCenter.dy - halfY);
      maxY = math.max(maxY, chip.slotCenter.dy + halfY);
    });
    return Size(maxX - minX, maxY - minY);
  }

  /// Counts axis-aligned footprint overlaps (node↔node, node↔chip,
  /// chip↔chip), padding included.
  int _countOverlaps(WedgeLayoutOutput output, String viewerId) {
    final boxes = _allBoxes(output, viewerId);
    var count = 0;
    for (var i = 0; i < boxes.length; i++) {
      for (var j = i + 1; j < boxes.length; j++) {
        if (boxes[i].overlaps(boxes[j])) count++;
      }
    }
    return count;
  }

  List<_Box> _allBoxes(WedgeLayoutOutput output, String viewerId) {
    final boxes = <_Box>[];
    output.positions.forEach((id, pos) {
      final size = id == viewerId
          ? _config.rootFootprint
          : _config.nodeFootprint;
      final pad = _config.footprintPadding;
      boxes.add(_Box(
        id,
        pos.dx - size.width / 2 - pad,
        pos.dy - size.height / 2 - pad,
        pos.dx + size.width / 2 + pad,
        pos.dy + size.height / 2 + pad,
      ));
    });
    output.pageChips.forEach((owner, chip) {
      final size = _config.chipFootprint;
      final pad = _config.footprintPadding;
      boxes.add(_Box(
        _chipId(owner),
        chip.slotCenter.dx - size.width / 2 - pad,
        chip.slotCenter.dy - size.height / 2 - pad,
        chip.slotCenter.dx + size.width / 2 + pad,
        chip.slotCenter.dy + size.height / 2 + pad,
      ));
    });
    boxes.sort();
    return boxes;
  }

  /// Deterministic radial pushes: every remaining overlapping pair
  /// (scanned in deterministic order) has its OUTER box pushed radially
  /// outward until the pair clears. Every push strictly increases one
  /// node's radius, so the loop converges.
  WedgeLayoutOutput _pushConflictsOutward(
      WedgeLayoutOutput output, String viewerId) {
    var working = output;
    var passes = 0;
    while (passes++ < _config.maxRadialPushPasses) {
      final boxes = _allBoxes(working, viewerId);
      _Box? firstA;
      _Box? firstB;
      outer:
      for (var i = 0; i < boxes.length; i++) {
        for (var j = i + 1; j < boxes.length; j++) {
          if (boxes[i].overlaps(boxes[j])) {
            firstA = boxes[i];
            firstB = boxes[j];
            break outer;
          }
        }
      }
      if (firstA == null || firstB == null) break; // zero overlaps

      // The "outer" box = farther from the origin (deterministic tie
      // break by the box sort order).
      final distA = firstA.center.distance;
      final distB = firstB.center.distance;
      final outer = distA <= distB ? firstB : firstA;
      final inner = distA <= distB ? firstA : firstB;

      // Overlap amounts per axis.
      final overlapX =
          math.min(outer.maxX, inner.maxX) - math.max(outer.minX, inner.minX);
      final overlapY =
          math.min(outer.maxY, inner.maxY) - math.max(outer.minY, inner.minY);

      // Radial direction of the outer box.
      final angle = outer.center.direction;
      final ux = math.cos(angle).abs().clamp(0.2, 1.0);
      final uy = math.sin(angle).abs().clamp(0.2, 1.0);
      var delta = 1.0;
      if (overlapX > 0) delta = math.max(delta, overlapX / ux + 1.0);
      if (overlapY > 0) delta = math.max(delta, overlapY / uy + 1.0);

      final pushed = <String, Offset>{...working.positions};
      final pushedChips = <String, WedgePageChip>{...working.pageChips};
      if (_isChipId(outer.id)) {
        final owner = _ownerOfChip(outer.id);
        final chip = pushedChips[owner];
        if (chip != null) {
          pushedChips[owner] = WedgePageChip(
            personId: owner,
            slotCenter: WedgeGeometry.polar(
                chip.slotCenter.distance + delta, chip.slotCenter.direction),
            remainingCount: chip.remainingCount,
            hasNested: chip.hasNested,
          );
        }
      } else {
        final pos = pushed[outer.id];
        if (pos != null) {
          pushed[outer.id] =
              WedgeGeometry.polar(pos.distance + delta, pos.direction);
        }
      }
      working = WedgeLayoutOutput(
        positions: pushed,
        pageChips: pushedChips,
        depthById: working.depthById,
        parentOf: working.parentOf,
        visibleIds: working.visibleIds,
        // The pushes above moved nodes OUTWARD — recompute the extent
        // so the canvas dimensions always match the final positions
        // (a stale extent produced a canvas smaller than the content,
        // breaking the camera fit).
        extentSize: _extentSize(viewerId, pushed, pushedChips),
      );
    }
    return working;
  }

  static String _chipId(String personId) => '\u0000chip\u0000$personId';
  static bool _isChipId(String id) => id.startsWith('\u0000chip\u0000');
  static String _ownerOfChip(String chipId) =>
      chipId.substring('\u0000chip\u0000'.length);
}

/// Polar helper (screen coordinates: Y grows downward).
class WedgeGeometry {
  const WedgeGeometry._();

  static Offset polar(num radius, num angle) {
    final r = radius.toDouble();
    if (r == 0) return Offset.zero;
    return Offset(
      r * math.cos(angle.toDouble()),
      r * math.sin(angle.toDouble()),
    );
  }
}

class _Claim {
  const _Claim(this.parent, this.key);

  final String parent;
  final String key;

  /// Closer relationship first (category rank), then lower parent id.
  bool isBetterThan(_Claim other) {
    final mine = ViewerWedgeLayout._rankOfKey(key);
    final theirs = ViewerWedgeLayout._rankOfKey(other.key);
    if (mine != theirs) return mine < theirs;
    return parent.compareTo(other.parent) < 0;
  }
}

class _ChipPlaceholder {
  const _ChipPlaceholder({
    required this.remainingCount,
    required this.hasNested,
  });
  final int remainingCount;
  final bool hasNested;
}

class _ShownTree {
  const _ShownTree({
    required this.shownChildren,
    required this.chipFor,
    required this.visibleIds,
  });

  final Map<String, List<String>> shownChildren;
  final Map<String, _ChipPlaceholder> chipFor;
  final Set<String> visibleIds;

  int get personCount => visibleIds.length;
}

class _Box implements Comparable<_Box> {
  _Box(this.id, this.minX, this.minY, this.maxX, this.maxY);

  final String id;
  final double minX, minY, maxX, maxY;

  Offset get center => Offset((minX + maxX) / 2, (minY + maxY) / 2);
  double get distance => center.distance;
  double get angle => math.atan2(center.dy, center.dx);

  bool overlaps(_Box other) =>
      minX < other.maxX &&
      other.minX < maxX &&
      minY < other.maxY &&
      other.minY < maxY;

  @override
  int compareTo(_Box other) {
    final byRadius = other.distance.compareTo(distance);
    if (byRadius != 0) return byRadius;
    final byAngle = angle.compareTo(other.angle);
    if (byAngle != 0) return byAngle;
    return id.compareTo(other.id);
  }
}
