// lib/graph/widgets/engine/branch_affordance.dart
// Extracted from family_graph_engine_view.dart to keep the main file
// under ~900 lines.
//
// Contains the collapsed-branch chip builder (System A — the ONLY
// branch-chip rendering path in the app), the lazy per-branch
// fetch-and-expand pipeline, and the long-press action sheet +
// full-names preview sheets.
//
// v5.132 (System B REMOVAL): the legacy per-node "+N" affordance
// wrapper (_withBranchAffordance → _handleBranchExpand →
// _toggleSubtree via ExpandCollapseController) was deleted. That path
// rendered chips that read a state store NOTHING in the real collapse
// pipeline ever writes (branchCollapseProvider /
// proximityGraphProvider / computeDensityCollapse), so its chips
// silently did nothing on tap. Every collapse trigger now renders
// through _buildCollapsedBranchChips below:
//   • density-collapse branches (computeDensityCollapse)
//   • fundamental-relationship collapse (computeCollapse)
//   • recursive sub-branches at extreme scale (_computeSubBranches)

part of '../family_graph_engine_view.dart';

/// Mixin containing collapsed-branch affordance logic for
/// _FamilyGraphEngineViewState.
extension _BranchAffordanceMethods on _FamilyGraphEngineViewState {
  /// v102 (BUG-2 FIX) + v5.123 (Step 3) + v5.x (chip-placement fix):
  /// Builds positioned chips for each collapsed branch.
  ///
  /// Every [CollapsedBranch] renders a PERSISTENTLY VISIBLE chip at its
  /// attachment point on the canvas — a direct child of the graph Stack,
  /// never hidden inside a menu and never gated on the filter panel.
  /// The chip LEADS with "+{count}" (the number of hidden members) and
  /// appends a short label (the branch root's name, e.g. "Mother")
  /// when space permits (width-capped, single line, ellipsized).
  ///
  /// v5.x (CHIP-PLACEMENT FIX): chips are now anchored CENTERED ON
  /// their parent node, just below the name label (was: a fixed
  /// diagonal offset of +40,+40 from the node center, which pushed
  /// chips onto neighbouring nodes' circles/labels). Collision
  /// avoidance now considers:
  ///   • every other placed chip
  ///   • every visible node's full 140×176 bounding box (circle +
  ///     name label + badges) — so chips never overlap another
  ///     person's circle or name label
  /// Multi-direction search: straight down (preferred), then below +
  /// slightly left, then below + slightly right, then above the node.
  /// If every candidate collides, the chip is placed at the
  /// least-overlap candidate and a leader line is drawn back to the
  /// parent node's center so the user can still see which person the
  /// chip belongs to.
  ///
  /// GESTURES (v5.132):
  ///   • Tap        → instant single-branch expand via
  ///                  _fetchAndExpandBranch (lazy per-branch
  ///                  get_member_branch fetch + proximity reveal +
  ///                  expandBranch). No other branch's collapse state
  ///                  changes.
  ///   • Long-press → _showBranchActionSheet: branch root name, hidden
  ///                  count, generation depth, a 4-name preview, and
  ///                  buttons to expand the branch or preview the full
  ///                  hidden-names list WITHOUT expanding.
  ///
  /// The GestureDetector uses HitTestBehavior.opaque so the compact
  /// visual chip always receives taps reliably (no transparent gaps
  /// swallowing hit events in the graph Stack).
  List<Widget> _buildCollapsedBranchChips(
    GraphLayoutResult layout,
    BranchCollapseState collapseState,
    Set<String> densityHiddenIds,
  ) {
    if (collapseState.collapsedBranches.isEmpty) return const [];

    // v5.x (chip-placement fix): delegate placement to the pure
    // helper so the rendered chip and the canvas hit-test target
    // always agree (the helper is shared between this builder and
    // _hitTestBranchChip in interaction_mixin.dart).
    final placements = _computeBranchChipPlacements(layout, collapseState, densityHiddenIds);
    if (placements.isEmpty) return const [];

    // Build a quick lookup: branchId → placement so we can map the
    // helper's results back to the branch objects (the helper sorts
    // branches deterministically but returns in the request order).
    final placementByBranchId = <String, BranchChipPlacement>{
      for (final p in placements) p.request.branchId: p,
    };

    final chips = <Widget>[];
    for (final branch in collapseState.collapsedBranches) {
      final placement = placementByBranchId[branch.id];
      if (placement == null) continue;
      final chipLeft = placement.rect.left;
      final chipTop = placement.rect.top;
      // v5.x (BUG-1 fix): needsLeaderLine is now ALWAYS false — the
      // chip is attached to its parent, no leader line is ever drawn.
      // The field is kept for API compatibility with existing callers
      // + tests but is unused here.

      // v5.105: Use the dominant kinship category color for the chip
      // border/accent instead of hardcoded orange. The category is
      // derived from the relationshipKey field on the CollapsedBranch.
      final chipAccentColor = _chipColorForBranch(branch);

      // v5.123 (Step 3): The short label — the branch root's name
      // (surname-style context like "Mother" / "Rajesh"), falling back
      // to the generated branch label when the root name is unknown.
      final shortLabel = branch.rootPersonName.trim().isNotEmpty
          ? branch.rootPersonName.trim()
          : branch.branchLabel;

      // v5.159 (RICH BUBBLES): The representative name shown BEFORE the
      // count — "Geeta Iyer +207". Priority: the branch's resolved
      // representativeName (root name, else first resolvable hidden
      // member name), else the short label, else nothing (bare "+N").
      final representative = (branch.representativeName ?? '').trim();
      final namePart = representative.isNotEmpty
          ? representative
          : shortLabel;

      // v5.159 (RICH BUBBLES): Nesting glyph — a TREE icon when the
      // hidden members include FURTHER sub-branches (depth ≥ 2:
      // expanding reveals nodes that themselves carry bubbles), vs a
      // flat CHEVRON (⌵) when the group is a dead end of direct
      // people with no deeper levels.
      final IconData nestingGlyph = branch.hasNestedDescendants
          ? Icons.account_tree_rounded
          : Icons.expand_more_rounded;
      final String nestingSemantics = branch.hasNestedDescendants
          ? 'Contains further sub-branches inside. '
          : 'Flat group — direct relatives only, no deeper levels. ';

      final chipWidget = GestureDetector(
        // v5.132: opaque hit-testing — the visual chip is compact,
        // but every pixel inside its bounds must register the tap /
        // long-press so chips never "silently do nothing".
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // P3.2: "branch opening" haptic on branch expand.
          GraphHaptics.branchExpand(context);
          // v5.115 (Task 1) + v5.123 (Step 3): Fetch ONLY this branch
          // via get_member_branch RPC, then expand. This is a lazy
          // fetch — only the tapped branch's nodes/edges are loaded,
          // never the whole family, and unrelated branches are not
          // re-fetched or re-laid-out.
          _fetchAndExpandBranch(branch);
        },
        // v5.132: long-press → rich branch action sheet (details +
        // expand + full-names preview). Fires the DISTINCT
        // branchMenuOpen double-pulse haptic so users can feel the
        // difference between the instant expand (tap) and the
        // richer interaction (long-press).
        onLongPress: () {
          GraphHaptics.branchMenuOpen(context);
          _showBranchActionSheet(context, branch);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          constraints: const BoxConstraints(maxWidth: 190),
          decoration: BoxDecoration(
            color: KinrelColors.darkBackground.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: chipAccentColor.withValues(alpha: 0.6),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(1, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // v5.143: Show a different icon when this chip is in the
              // optimistic loading state (tap fired, RPC in flight).
              // v5.159: otherwise show the NESTING glyph (tree vs flat
              // chevron) so the user can tell at a glance whether the
              // group has more levels inside.
              // Gives sub-100ms visual feedback without needing a
              // Material ancestor for CircularProgressIndicator.
              Icon(
                _optimisticLoadingChipRootId == branch.rootPersonId
                    ? Icons.hourglass_top
                    : nestingGlyph,
                size: 14,
                color: chipAccentColor,
              ),
              const SizedBox(width: 6),
              // v5.159 (RICH BUBBLES): "<name> +<count>" — lead with the
              // representative name (e.g. "Geeta Iyer +207") so the user
              // knows WHOSE branch they are expanding, then the count.
              //
              // v5.160 (NEXT-LEVEL COUNT): the count is
              // [CollapsedBranch.nextExpansionCount] — the number of
              // nodes that will ACTUALLY APPEAR on tap (the immediate
              // next-level direct hidden neighbours, capped at
              // [kMaxNodesPerExpansion] = 15) — NOT the full recursive
              // descendant count. The full count stays available in the
              // long-press action sheet ("View all" summary panel).
              // Single line, ellipsized; the nesting semantics stay
              // available to screen readers via the Semantics label
              // below.
              Flexible(
                child: Text(
                  namePart.isEmpty
                      ? '+${branch.nextExpansionCount}'
                      : '$namePart +${branch.nextExpansionCount}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      );

      // v5.x (BUG-1 fix — REMOVE LEADER LINE): the previous version
      // rendered a dashed leader line from the chip back to the
      // parent node's center when the chip had to be placed far
      // away. The user reported this looked like "a floating
      // single-line-plus-badge in empty space that doesn't clearly
      // connect to anything meaningful." The leader line has been
      // REMOVED — the chip is now always attached to (overlapping)
      // the parent node's bottom edge, so no visual tether is needed.
      // The `_BranchChipLeaderPainter` class has been deleted.
      chips.add(Positioned(
        left: chipLeft,
        top: chipTop,
        child: Semantics(
          button: true,
          label:
              'Expand ${namePart.isEmpty ? 'collapsed' : namePart} branch: '
              '${branch.nextExpansionCount} members will appear on tap. '
              'Total hidden in this branch: ${branch.hiddenCount}. '
              '$nestingSemantics'
              'Double-tap to expand. Long-press for branch details and '
              'the full names list.',
          child: chipWidget,
        ),
      ));
    }
    return chips;
  }

  /// v5.x (chip-placement fix): delegate to the pure helper in
  /// lib/graph/engine/branch_chip_layout.dart so the placement
  /// logic is unit-testable AND shared with the canvas hit-tester
  /// (see _hitTestBranchChip in interaction_mixin.dart — calls the
  /// SAME helper so the rendered chip and the tap target can never
  /// drift apart).
  List<BranchChipPlacement> _computeBranchChipPlacements(
    GraphLayoutResult layout,
    BranchCollapseState collapseState,
    Set<String> densityHiddenIds,
  ) {
    if (collapseState.collapsedBranches.isEmpty) return const [];

    // Build the placement requests from the collapsed branches.
    final requests = <BranchChipPlacementRequest>[];
    for (final branch in collapseState.collapsedBranches) {
      final pos = layout.positions[branch.rootPersonId];
      if (pos == null) continue;
      // v5.153 (FIX 2.A): Skip branches whose root is itself hidden by
      // another collapse. Without this, the chip renders at a "floating"
      // location with no visible parent circle — the user reported
      // "hidden or not being displayed correctly."
      if (densityHiddenIds.contains(branch.rootPersonId)) continue;
      requests.add(BranchChipPlacementRequest(
        branchId: branch.id,
        rootPersonId: branch.rootPersonId,
        rootPosition: pos,
      ));
    }
    if (requests.isEmpty) return const [];

    // v5.153 (FIX 2.B): Build the node-box list for collision avoidance
    // using ONLY visible nodes (not hidden ones). The old code included
    // hidden nodes, which pushed chips into worse positions because they
    // were avoiding invisible nodes.
    final allNodeBoxes = <Rect>[
      for (final entry in layout.positions.entries)
        if (!densityHiddenIds.contains(entry.key))
          nodeBoxForPosition(entry.value),
    ];

    return placeBranchChips(
      requests: requests,
      allNodeBoxes: allNodeBoxes,
    );
  }

  /// v5.105: Returns the accent color for a collapsed-branch chip
  /// based on the branch's relationshipKey. Falls back to orange
  /// (the original color) when the key is empty.
  Color _chipColorForBranch(CollapsedBranch branch) {
    if (branch.relationshipKey.isEmpty) {
      return KinrelColors.orange;
    }
    // Map the relationship key to a category color.
    // (KinshipEdgeStyle.color is non-nullable — the resolver always
    // returns a color, including for unknown keys via its default
    // style, so no null fallback is needed here.)
    return KinshipEdgeStyleResolver.styleFor(branch.relationshipKey).color;
  }

  /// v5.115 (Task 1) + v5.123 (Step 3) + v5.131 (Bug 1 fix): Fetches the
  /// branch via get_member_branch RPC, then expands it in the collapse
  /// state AND reveals its members in the proximity set.
  ///
  /// This is the LAZY FETCH path: only the tapped branch's nodes/edges
  /// are loaded from Supabase, not the whole family. After the fetch
  /// merges the new data into the provider state, the branch is
  /// removed from the collapsed set (via the existing expandBranch
  /// path) so its nodes become visible.
  ///
  /// v5.123 (Step 3): the branch's hidden members are ALSO added to the
  /// proximity visible set via the existing expansion mechanism
  /// (ProximityGraphNotifier.revealPersons — the bulk sibling of the
  /// tap-to-expand expandFromPerson). Without this, expandBranch alone
  /// removed the chip but the members never rendered — they had no
  /// positions because the layout only positions proximity-visible
  /// nodes. The reveal is purely INCREMENTAL: unrelated branches keep
  /// their chips and their nodes keep their positions; only the tapped
  /// branch's members are added.
  ///
  /// v5.131 (Bug 1 fix): `branchTypeForRelationshipKey` now always
  /// returns a valid branch type (it falls back to `'generic'` for
  /// unrecognized keys — non-nullable return type since v5.132). The
  /// fetch therefore ALWAYS runs — previously a custom key like
  /// `YakFather` made `branchType` null, the fetch was skipped, and
  /// the subsequent `revealPersons()` found nothing to reveal because
  /// the hidden members were never in `flat.persons`.
  Future<void> _fetchAndExpandBranch(CollapsedBranch branch) async {
    // v5.143: Optimistic UI — set the loading state IMMEDIATELY so the
    // user gets sub-100ms feedback. The chip shows a different icon
    // while the RPC is in flight.
    _optimisticLoadingChipRootId = branch.rootPersonId;
    setState(() {});

    // v5.158 (ZONE BUBBLES): ALWAYS fetch with the 'generic' branch type.
    //
    // The old code mapped the branch's dominant relationship key to a
    // semantic branch type (maternal/paternal/cousins/inLaws/
    // grandchildren). But v5.158 zone bubbles represent "the hidden
    // members nearest to this root" — a MIXED set (spouses, descendants,
    // siblings of zone members...), not a single semantic branch. The
    // semantic fetch types return only specific relationship subsets,
    // so they systematically missed most of the zone's members.
    //
    // 'generic' runs a BFS from the root up to [fetchDepth] hops over
    // EVERY relationship type — exactly the neighborhood the zone
    // bubble claims to represent. Unrecognized keys ALSO land here
    // (the v5.131 safety net). This is the only correct fetch mode
    // for zone bubbles.
    const branchType = 'generic';
    // v5.153 (FIX 3.A): Adaptive depth. Large zones fetch 4 hops so a
    // single tap makes real progress (e.g. a 234-member component),
    // small zones fetch 2 hops. Deeper members stay hidden and get
    // re-zoned onto the new frontier — that IS the progressive
    // expansion behavior.
    final hiddenCount = branch.hiddenMemberIds.length;
    final fetchDepth = hiddenCount > 20 ? 4 : 2;
    await ref.read(familyGraphProvider(widget.familyId).notifier)
        .fetchBranchAndMerge(
      rootPersonId: branch.rootPersonId,
      branchType: branchType,
      depth: fetchDepth,
    );

    // v5.143: Clear the optimistic loading state — data has arrived.
    _optimisticLoadingChipRootId = null;

    // v5.159 (PROGRESSIVE DISCLOSURE — LEVEL REVEAL):
    //
    // The OLD behavior revealed EVERY hidden member of the branch in
    // one tap (a 207-member zone dumped 207 nodes onto the canvas at
    // once). The NEW contract, per spec:
    //
    //   • ONE tap reveals ONLY the immediate next level — the hidden
    //     members DIRECTLY connected to the branch root — never the
    //     deeper subtree.
    //   • The reveal is capped at [kMaxNodesPerExpansion] (15). When
    //     the immediate level is larger, the kinship-closest 15 are
    //     revealed and the REST stay hidden — the next density pass
    //     re-zones them into sub-bubbles attached to the newly
    //     revealed frontier nodes ("split into multiple sub-bubbles
    //     instead of rendering them all").
    //   • CONNECTIVITY GUARANTEE: every revealed member holds an edge,
    //     present in the fetched data, to a node that is ALREADY
    //     visible — so the moment a node renders, its connecting line
    //     to its parent is computable. No "floating node with a +N
    //     badge and no line" can ever appear.
    final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;
    var revealedIds = const <String>{};
    if (flat != null) {
      final allPersons = <String>{
        for (final p in flat.persons) (p['id'] ?? '').toString(),
      };
      // v5.159: The full edge list (allRelationships — the union of the
      // base graph and every merged branch fetch — when available).
      final edgesSrc = flat.allRelationships ?? flat.relationships;
      final fullEdges =
          <({String fromId, String toId, String edgeId, String relationshipKey})>[
        for (final Map<String, dynamic> r in edgesSrc)
          if (r['fromPersonId'] != null &&
              r['toPersonId'] != null &&
              r['id'] != null)
            (
              fromId: r['fromPersonId'].toString(),
              toId: r['toPersonId'].toString(),
              edgeId: r['id'].toString(),
              relationshipKey: (r['relationshipKey'] as String?) ?? '',
            ),
      ];
      // The visible set INCLUDES the branch root (it is rendered — its
      // chip is anchored on it), even when the proximity set has not
      // listed it yet.
      final visiblePlusRoot = Set<String>.of(
              ref.read(proximityGraphProvider).visibleIds)
        ..add(branch.rootPersonId);

      revealedIds = ProximityGraphNotifier.computeNextLevelReveal(
        rootPersonId: branch.rootPersonId,
        visibleIds: visiblePlusRoot,
        allPersons: allPersons,
        edges: fullEdges,
      );

      // v5.159 (ZONE FALLBACK): zone bubbles group the hidden members
      // NEAREST to the root, but those members may hang off OTHER
      // (visible) zone members rather than off the root itself. When
      // the root has no hidden direct neighbours, fall back to the
      // closest hidden members that are adjacent to ANY visible node
      // (BFS distance from the root, then deterministic ID order) —
      // the connectivity guarantee still holds for every pick.
      if (revealedIds.isEmpty && branch.hiddenMemberIds.isNotEmpty) {
        revealedIds = _computeZoneFallbackReveal(
          rootPersonId: branch.rootPersonId,
          hiddenIds: branch.hiddenMemberIds
              .where(allPersons.contains)
              .toSet(),
          visibleIds: visiblePlusRoot,
          edges: fullEdges,
        );
      }

      // v5.123 (Step 3) + v5.159: Reveal ONLY the computed level in
      // the proximity set so the layout provider gives these members
      // positions and the expansion is actually VISIBLE.
      ref.read(proximityGraphProvider.notifier).revealPersons(
            personIds: {
              branch.rootPersonId,
              ...revealedIds,
            },
            allPersons: allPersons,
          );

      // v5.159 (ENTRANCE ANIMATION): record the revealed members so
      // the node layer animates them in (fly-out from the branch
      // root's position) instead of popping. The canvas build promotes
      // them once the layout assigns positions.
      final layoutForOrigin =
          ref.read(graphLayoutProvider(widget.familyId)).valueOrNull;
      _markNodesForEntrance(
        revealedIds,
        origin: layoutForOrigin?.positions[branch.rootPersonId],
      );
    }

    // Expand the branch in the collapse state — removes it from the
    // collapsed set and adds the root to expandedBranchRoots so it
    // won't be auto-collapsed again.
    // v5.142: If this is a manually-collapsed branch, use expandManualBranch
    // (removes from manuallyCollapsedRoots instead of expandedBranchRoots).
    // v5.159: record WHICH members this expansion revealed so a later
    // re-collapse (collapseBranch) conceals exactly this set.
    //
    // v5.159 (EMPTY-REVEAL GUARD): when the reveal set is EMPTY (fetch
    // returned nothing / no hidden member is currently fetchable), the
    // chip STAYS — removing the branch would make the bubble vanish
    // while revealing nothing, leaving hidden members unreachable.
    // The user can tap again once data has loaded.
    if (revealedIds.isNotEmpty) {
      final collapseState = ref.read(branchCollapseProvider);
      if (collapseState.manuallyCollapsedRoots
          .contains(branch.rootPersonId)) {
        ref.read(branchCollapseProvider.notifier)
            .expandManualBranch(branch.rootPersonId);
      } else {
        // v5.161 (LRU CAP): expandBranch now returns the set of
        // person IDs that should be concealed if an OLDER expanded
        // branch was auto-collapsed to make room. Pass that set to
        // the proximity notifier so the auto-collapsed branch's
        // revealed members disappear from the canvas — otherwise
        // they'd stay visible with no bubble covering them.
        final concealFromLru = ref
            .read(branchCollapseProvider.notifier)
            .expandBranch(
              branch.rootPersonId,
              revealedIds: revealedIds,
            );
        if (concealFromLru.isNotEmpty) {
          ref.read(proximityGraphProvider.notifier).concealPersons(
                personIds: concealFromLru,
              );
        }
      }
    }

    // v5.159 (SUB-BUBBLES): when the immediate level exceeded the
    // 15-node cap, the members NOT revealed above are re-zoned by the
    // density pass (canvas_mixin) into sub-bubbles anchored on the
    // newly revealed frontier nodes — each tap makes visible progress
    // while the total on-canvas count stays bounded.

  }

  /// v5.159 (ZONE FALLBACK): picks the hidden members a branch-bubble
  /// tap should reveal when the branch root has no hidden DIRECT
  /// neighbours (zone bubbles group by proximity, not by adjacency to
  /// the root).
  ///
  /// Selection: hidden members that have at least one edge to a node
  /// in [visibleIds] (CONNECTIVITY GUARANTEE — the line to a visible
  /// parent exists the moment the node renders), ranked by BFS hop
  /// distance from the branch root (closest first), then by kinship
  /// priority of the connecting edge, then by ID for determinism.
  /// Capped at [kMaxNodesPerExpansion]; the rest stay hidden and get
  /// re-zoned into sub-bubbles on the next density pass.
  Set<String> _computeZoneFallbackReveal({
    required String rootPersonId,
    required Set<String> hiddenIds,
    required Set<String> visibleIds,
    required List<
            ({String fromId, String toId, String edgeId, String relationshipKey})>
        edges,
  }) {
    if (hiddenIds.isEmpty) return const <String>{};

    // Adjacency + hop distance from the root over the FULL edge list.
    final adjacency = <String, Set<String>>{};
    for (final e in edges) {
      if (e.fromId.isEmpty || e.toId.isEmpty) continue;
      adjacency.putIfAbsent(e.fromId, () => <String>{}).add(e.toId);
      adjacency.putIfAbsent(e.toId, () => <String>{}).add(e.fromId);
    }
    final hopFromRoot = <String, int>{rootPersonId: 0};
    final queue = <String>[rootPersonId];
    var head = 0;
    while (head < queue.length) {
      final current = queue[head++];
      final nextHops = hopFromRoot[current]! + 1;
      for (final n in adjacency[current] ?? const <String>{}) {
        if (!hopFromRoot.containsKey(n)) {
          hopFromRoot[n] = nextHops;
          queue.add(n);
        }
      }
    }

    // Connecting-key priority (mirrors the state layer's ranking so
    // both paths reveal the same KINDS of members first).
    const priorities = <String, int>{
      'spouse': 0, 'wife': 0, 'husband': 0, 'partner': 0,
      'mother': 1, 'father': 1, 'parent': 1,
      'son': 2, 'daughter': 2, 'child': 2,
      'brother': 3, 'sister': 3, 'sibling': 3,
      'grandmother': 4, 'grandfather': 4, 'grandparent': 4,
      'aunt': 5, 'uncle': 5,
      'nephew': 6, 'niece': 6, 'cousin': 6,
    };
    int priorityOf(String key) =>
        priorities[key.toLowerCase().trim()] ?? 9;

    // Candidate = hidden member adjacent to ≥1 VISIBLE node. Track its
    // best (lowest) connecting priority across all such edges.
    final candidatePriority = <String, int>{};
    for (final e in edges) {
      if (e.fromId.isEmpty || e.toId.isEmpty) continue;
      String? hiddenSide;
      String key;
      if (hiddenIds.contains(e.fromId) &&
          visibleIds.contains(e.toId)) {
        hiddenSide = e.fromId;
        key = e.relationshipKey;
      } else if (hiddenIds.contains(e.toId) &&
          visibleIds.contains(e.fromId)) {
        hiddenSide = e.toId;
        key = e.relationshipKey;
      } else {
        continue;
      }
      final rank = priorityOf(key);
      final existing = candidatePriority[hiddenSide];
      if (existing == null || rank < existing) {
        candidatePriority[hiddenSide] = rank;
      }
    }
    if (candidatePriority.isEmpty) return const <String>{};

    final ranked = candidatePriority.keys.toList()
      ..sort((a, b) {
        final byHops = (hopFromRoot[a] ?? 1 << 20)
            .compareTo(hopFromRoot[b] ?? 1 << 20);
        if (byHops != 0) return byHops;
        final byPriority = candidatePriority[a]!
            .compareTo(candidatePriority[b]!);
        if (byPriority != 0) return byPriority;
        return a.compareTo(b);
      });
    return Set<String>.of(
      ranked.take(kMaxNodesPerExpansion).toSet(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // v5.132: LONG-PRESS ACTION SHEET + FULL-NAMES PREVIEW
  // ═══════════════════════════════════════════════════════════════════

  /// v5.132: Resolves the display names of a branch's hidden members.
  ///
  /// Names come from the CURRENT provider state
  /// (`familyGraphProvider(familyId)`) — the same FlatGraphResult the
  /// canvas renders. For members that have not been fetched yet (the
  /// proximity view truncates large families, so distant branch
  /// members may not be in `flat.persons`), the RAW person ID is
  /// returned as a fallback (shortened for display). After
  /// `_fetchAndExpandBranch` has run at least once for the branch,
  /// `fetchBranchAndMerge` has merged the full names into the state
  /// and this resolver returns real names for every member.
  List<String> _resolveHiddenMemberNames(CollapsedBranch branch) {
    final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;

    // id → display name map from the current (possibly truncated) data.
    final namesById = <String, String>{};
    if (flat != null) {
      for (final p in flat.persons) {
        final id = (p['id'] ?? '').toString();
        final name = ((p['name'] as String?) ?? '').trim();
        if (id.isNotEmpty) namesById[id] = name;
      }
    }

    final names = <String>[];
    for (final id in branch.hiddenMemberIds) {
      final name = namesById[id];
      if (name != null && name.isNotEmpty) {
        names.add(name);
      } else {
        // Not fetched yet → raw-ID fallback. Shortened so the list
        // stays readable; the full name appears after the branch has
        // been fetched once (fetchBranchAndMerge).
        names.add(id.length > 10 ? '${id.substring(0, 10)}…' : id);
      }
    }
    // Deterministic display order (hiddenMemberIds is a Set — its
    // iteration order is traversal-dependent, not user-friendly).
    names.sort();
    return names;
  }

  /// v5.132: The long-press action sheet for a collapsed branch.
  ///
  /// Shows the branch summary (root name, hidden count, generation
  /// depth), a 4-name preview of the hidden members, and three
  /// actions:
  ///   • Expand this branch       → _fetchAndExpandBranch (instant
  ///                               single-branch expand, same as a
  ///                               chip tap)
  ///   • Preview full names list → _showFullNamesList — a separate
  ///                               scrollable sheet of ALL hidden
  ///                               names that does NOT expand the
  ///                               branch on the canvas
  ///   • Close
  ///
  /// The sheet itself NEVER expands anything — expansion only happens
  /// through the explicit "Expand this branch" button.
  void _showBranchActionSheet(BuildContext context, CollapsedBranch branch) {
    final names = _resolveHiddenMemberNames(branch);
    final rootName = branch.rootPersonName.trim().isNotEmpty
        ? branch.rootPersonName.trim()
        : branch.branchLabel;
    final depth = branch.hiddenGenerationDepth;
    final hasDepth = depth > 0;
    final preview = names.take(4).toList(growable: false);
    final remaining = names.length - preview.length;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header: branch root name + close ─────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.account_tree_rounded,
                      color: _chipColorForBranch(branch), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rootName.isEmpty
                          ? 'Collapsed branch'
                          : "$rootName's branch",
                      style: const TextStyle(
                        color: KinrelColors.textWhite,
                        fontFamily: 'DMSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: KinrelColors.textSecondaryDark),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
            // ── Summary: next-level count + total hidden count + depth ──
            // v5.160 (NEXT-LEVEL BUBBLE COUNT): this is the "View all"
            // summary panel — it shows BOTH counts so the user can see
            // what the tap will do (nextExpansionCount) AND the full
            // scope of the branch (hiddenCount). The chip itself only
            // shows nextExpansionCount; this panel is where the total
            // 714 / 234-style numbers live.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                hasDepth
                    ? 'Tap reveals ${branch.nextExpansionCount} '
                        '${branch.nextExpansionCount == 1 ? 'member' : 'members'} · '
                        '${branch.hiddenCount} total hidden · '
                        '$depth generation${depth == 1 ? '' : 's'} deep'
                    : 'Tap reveals ${branch.nextExpansionCount} '
                        '${branch.nextExpansionCount == 1 ? 'member' : 'members'} · '
                        '${branch.hiddenCount} total hidden',
                style: const TextStyle(
                  color: KinrelColors.textSecondaryDark,
                  fontSize: 13,
                ),
              ),
            ),
            // v5.159 (RICH BUBBLES): nesting hint — tells the user
            // whether one tap reveals a level that itself carries
            // further bubbles (tree) or a flat dead-end group (⌵).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(
                children: [
                  Icon(
                    branch.hasNestedDescendants
                        ? Icons.account_tree_rounded
                        : Icons.expand_more_rounded,
                    size: 14,
                    color: _chipColorForBranch(branch),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      branch.hasNestedDescendants
                          ? 'Expanding reveals the next level — deeper '
                              'levels hide behind further bubbles'
                          : 'Flat group — all hidden members are direct '
                              'relatives of the next level',
                      style: const TextStyle(
                        color: KinrelColors.textSecondaryDark,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // v5.160 (NEXT-LEVEL COUNT): one tap reveals exactly
            // [nextExpansionCount] members — that count is already on
            // the chip. When the immediate next level is larger than
            // [kMaxNodesPerExpansion], the cap kicks in and the rest
            // re-group into new sub-bubbles on the next density pass.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                branch.nextExpansionCount >= kMaxNodesPerExpansion &&
                        branch.hiddenCount > kMaxNodesPerExpansion
                    ? 'Tap shows the first $kMaxNodesPerExpansion closest '
                        'members — the rest re-group into new bubbles'
                    : 'Tap reveals the whole next level',
                style: const TextStyle(
                  color: KinrelColors.textSecondaryDark,
                  fontSize: 12,
                ),
              ),
            ),
            // ── 4-name preview ────────────────────────────────────────
            if (preview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  remaining > 0
                      ? 'Including ${preview.join(", ")} (+$remaining more)'
                      : 'Including ${preview.join(", ")}',
                  style: const TextStyle(
                    color: KinrelColors.textWhite,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // ── Actions ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.unfold_more_rounded, size: 18),
                label: const Text('Expand next level'),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  // Same haptic + pipeline as a direct chip tap.
                  GraphHaptics.branchExpand(sheetContext);
                  _fetchAndExpandBranch(branch);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: KinrelColors.textWhite,
                  side: BorderSide(
                    color: KinrelColors.textSecondaryDark.withValues(
                        alpha: 0.5),
                  ),
                ),
                icon: const Icon(Icons.list_alt_rounded, size: 18),
                label: const Text('Preview full names list'),
                // Opens the names sheet ON TOP of this one — the
                // branch is NOT expanded on the canvas; closing the
                // names sheet returns here so the user can still
                // expand via the button above.
                onPressed: () =>
                    _showFullNamesList(sheetContext, branch, names),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text(
                'Close',
                style:
                    TextStyle(color: KinrelColors.textSecondaryDark),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// v5.138: Action sheet for an EXPANDED branch root node.
  ///
  /// When a node that is the root of a currently-expanded branch is
  /// long-pressed, this sheet opens with a "Collapse this branch" option
  /// instead of "Expand this branch". The sheet reuses the same layout
  /// as [_showBranchActionSheet] but with:
  ///   - Header: "{rootPersonName}'s branch"
  ///   - Metadata: "{count} members shown · {depth} generation(s) deep"
  ///   - Primary button: "Collapse this branch" → calls collapseBranch()
  ///   - Secondary button: "Preview full names list" → same as collapsed sheet
  ///   - Close button
  void _showExpandedBranchActionSheet(
    BuildContext context,
    String rootPersonId,
    String rootPersonName,
  ) {
    // Resolve the currently-visible members of this branch from the
    // provider state. After expansion, these members are in flat.persons.
    final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;
    final List<String> visibleMemberNames = [];
    int memberCount = 0;
    if (flat != null) {
      // v5.146: Use the shared buildChildrenOf which handles BOTH
      // parent-type and child-type relationship directions.
      final childrenOfSet = BranchCollapseNotifier.buildChildrenOf(flat.relationships);
      final childrenMap = <String, List<String>>{
        for (final entry in childrenOfSet.entries)
          entry.key: entry.value.toList(),
      };
      // BFS from rootPersonId to find all descendants
      final visited = <String>{rootPersonId};
      final queue = [rootPersonId];
      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        for (final child in childrenMap[current] ?? <String>[]) {
          if (visited.add(child)) {
            queue.add(child);
            // Find the person's name from the flat graph data.
            String? name;
            for (final p in flat.persons) {
              if ((p['id'] ?? '').toString() == child) {
                name = (p['name'] ?? '').toString();
                break;
              }
            }
            if (name != null && name.isNotEmpty) visibleMemberNames.add(name);
          }
        }
      }
      memberCount = visibleMemberNames.length;
    }

    final rootName = rootPersonName.trim().isNotEmpty
        ? rootPersonName.trim()
        : 'Branch';
    final preview = visibleMemberNames.take(4).toList(growable: false);
    final remaining = visibleMemberNames.length - preview.length;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_rounded,
                      color: KinrelColors.orange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "$rootName's branch",
                      style: const TextStyle(
                        color: KinrelColors.textWhite,
                        fontFamily: 'DMSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: KinrelColors.textSecondaryDark),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
            // ── Summary: visible count ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                '$memberCount members shown',
                style: const TextStyle(
                  color: KinrelColors.textSecondaryDark,
                  fontSize: 13,
                ),
              ),
            ),
            // ── 4-name preview ────────────────────────────────────────
            if (preview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  remaining > 0
                      ? 'Including ${preview.join(", ")} (+$remaining more)'
                      : 'Including ${preview.join(", ")}',
                  style: const TextStyle(
                    color: KinrelColors.textWhite,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // ── Primary action: Collapse this branch ──────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.unfold_less_rounded, size: 18),
                label: const Text('Collapse this branch'),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  // Fire the SAME haptic as expanding (symmetric feel).
                  GraphHaptics.branchExpand(sheetContext);
                  // v5.159 (RE-COLLAPSE): collapseBranch returns the set
                  // of person IDs the expansion revealed (this root's
                  // level + any nested expansions inside it). Conceal
                  // them from the proximity set — they lose their
                  // positions, and the next density pass re-zones them
                  // under the root, RESTORING the "+N" bubble with the
                  // full hidden count.
                  final concealSet = ref
                      .read(branchCollapseProvider.notifier)
                      .collapseBranch(rootPersonId);
                  if (concealSet.isNotEmpty) {
                    ref
                        .read(proximityGraphProvider.notifier)
                        .concealPersons(personIds: concealSet);
                  }
                  // v5.159: stop any in-flight entrance fly-out for the
                  // members being concealed.
                  _cancelEntranceAnimation();
                  // v5.151+ (RACE FIX — same as the collapse dialog):
                  // DO NOT invalidate familyGraphProvider here. The
                  // collapse state + proximity conceal are PRESENTATION
                  // changes; canvas_mixin watches both providers and
                  // rebuilds synchronously. Invalidation caused an async
                  // refetch that raced the state update and wiped the
                  // re-collapse with stale data.
                },
              ),
            ),
            // ── Secondary action: Preview full names list ─────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: KinrelColors.textWhite,
                  side: BorderSide(
                    color: KinrelColors.textSecondaryDark.withValues(
                        alpha: 0.5),
                  ),
                ),
                icon: const Icon(Icons.list_alt_rounded, size: 18),
                label: const Text('Preview full names list'),
                onPressed: () {
                  // Build a temporary CollapsedBranch-like object for
                  // the names list sheet (it only needs names + rootName).
                  _showExpandedBranchNamesList(
                      sheetContext, rootName, visibleMemberNames);
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text(
                'Close',
                style:
                    TextStyle(color: KinrelColors.textSecondaryDark),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// v5.138: Names list sheet for an expanded branch (shows currently-
  /// visible members instead of hidden members).
  void _showExpandedBranchNamesList(
    BuildContext context,
    String rootName,
    List<String> names,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (listContext) {
        final height = MediaQuery.of(listContext).size.height;
        return SizedBox(
          height: height * 0.7,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "$rootName's branch · "
                              '${names.length} members',
                          style: const TextStyle(
                            color: KinrelColors.textWhite,
                            fontFamily: 'DMSans',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: KinrelColors.textSecondaryDark),
                        onPressed: () => Navigator.of(listContext).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: names.length,
                    itemBuilder: (ctx, i) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: KinrelColors.orange
                            .withValues(alpha: 0.2),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: KinrelColors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      title: Text(
                        names[i],
                        style: const TextStyle(
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// v5.140: Shows a confirmation dialog before collapsing a branch.
  ///
  /// The user must explicitly confirm — collapsing hides the branch's
  /// members and restores the '+N' chip. This prevents accidental
  /// collapses when the user meant to tap something else.
  ///
  /// v5.142: Uses manualCollapseBranch() which works for ANY node with
  /// visible descendants — not just previously-expanded branch roots.
  /// The manually-collapsed branch stays collapsed even through graph
  /// recalculations (separate from the auto-collapse system).
  void _showCollapseConfirmationDialog(
    BuildContext context,
    String rootPersonId,
    String rootPersonName,
    List<String> visibleNames,
  ) {
    // v5.145: Format the member names into a natural-language sentence.
    // ≤ 4 names: "Name1, Name2, Name3, and Name4 will be hidden."
    // > 4 names: "Name1, Name2, Name3, and N others will be hidden."
    // Fallback: "These members will be hidden again." if names empty.
    String message;
    if (visibleNames.isEmpty) {
      message = 'These members will be hidden again.';
    } else if (visibleNames.length <= 4) {
      if (visibleNames.length == 1) {
        message = '${visibleNames[0]} will be hidden.';
      } else if (visibleNames.length == 2) {
        message = '${visibleNames[0]} and ${visibleNames[1]} will be hidden.';
      } else {
        final allButLast = visibleNames.sublist(0, visibleNames.length - 1);
        final last = visibleNames.last;
        message = '${allButLast.join(", ")}, and $last will be hidden.';
      }
    } else {
      // > 4: show first 3 + count
      final first3 = visibleNames.sublist(0, 3);
      final remaining = visibleNames.length - 3;
      message = '${first3.join(", ")}, and $remaining other'
          '${remaining == 1 ? "" : "s"} will be hidden.';
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        title: const Text(
          'Collapse this branch?',
          style: TextStyle(
            color: KinrelColors.textWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: KinrelColors.textSecondaryDark,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: KinrelColors.textSecondaryDark),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KinrelColors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              // Fire the same haptic as expanding (symmetric feel).
              GraphHaptics.branchExpand(context);

              // v5.142: Build the childrenOf adjacency map needed by
              // manualCollapseBranch. allEdges is optional (null) —
              // hidden edges will be computed from childrenOf only.
              final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;
              if (flat == null) return;

              // v5.146: Use the shared buildChildrenOf which handles BOTH
              // parent-type and child-type relationship directions.
              final childrenOf = BranchCollapseNotifier.buildChildrenOf(flat.relationships);

              String personNameOf(String id) {
                for (final p in flat.persons) {
                  if ((p['id'] ?? '').toString() == id) {
                    return ((p['name'] as String?) ?? '').trim();
                  }
                }
                return '';
              }

              // v5.142: If this was an auto-expanded branch, use collapseBranch
              // (removes from expandedBranchRoots). Otherwise, use
              // manualCollapseBranch (adds to manuallyCollapsedRoots).
              // v5.159 (RE-COLLAPSE): for auto-expanded branches,
              // collapseBranch returns the conceal set — the members this
              // branch's expansion(s) revealed. Conceal them from the
              // proximity set so they lose positions and the next density
              // pass re-zones them under the root, RESTORING the "+N"
              // bubble. Manual collapse does not need concealment — the
              // branch entry itself carries the hidden-member set that
              // filters the render.
              final collapseState = ref.read(branchCollapseProvider);
              if (collapseState.expandedBranchRoots.contains(rootPersonId)) {
                // Auto-expanded branch — just undo the expansion.
                final concealSet = ref
                    .read(branchCollapseProvider.notifier)
                    .collapseBranch(rootPersonId);
                if (concealSet.isNotEmpty) {
                  ref
                      .read(proximityGraphProvider.notifier)
                      .concealPersons(personIds: concealSet);
                }
                _cancelEntranceAnimation();
              } else {
                // Manually collapse — works for ANY node with descendants.
                ref.read(branchCollapseProvider.notifier)
                    .manualCollapseBranch(
                      rootPersonId: rootPersonId,
                      childrenOf: childrenOf,
                      personNameOf: personNameOf,
                    );
              }

              // v5.151: DO NOT invalidate familyGraphProvider here.
              // The collapse state is PRESENTATION state — the canvas_mixin
              // already watches branchCollapseProvider and will rebuild when
              // it changes. Invalidating familyGraphProvider causes an ASYNC
              // refetch that races with the collapse state update: the first
              // rebuild after invalidation uses STALE graph data, and
              // computeDensityCollapse on that rebuild may not correctly
              // preserve the manual branches because the childrenOf map is
              // built from stale data. This race is why the first tap
              // appeared to do nothing — the collapse was applied but then
              // immediately wiped by the stale-data rebuild.
              //
              // The canvas_mixin's build method already reads
              // branchCollapseProvider (line 576) and applies the hidden
              // IDs (line 577-585) on every rebuild. Since
              // branchCollapseProvider is a StateNotifier, its state change
              // triggers a rebuild automatically — no invalidation needed.
            },
            child: const Text('Collapse'),
          ),
        ],
      ),
    );
  }

  /// v5.139: Resolves the display names of currently-visible members
  /// of an EXPANDED branch (the root + all descendants in the flat graph).
  /// Used by the combined node action sheet to show the "Collapse this
  /// branch" section with a name preview.
  ///
  /// v5.144: Now scopes the BFS to only return names of descendants
  /// that are CURRENTLY VISIBLE on the canvas (in [visibleIds]). This
  /// ensures the preview-names list matches exactly what "Collapse this
  /// branch" would actually hide — not the entire family dataset.
  ///
  /// Performs a BFS from [rootPersonId] through parent-type relationships
  /// (parent/father/mother/adoptive_parent/step_parent) to find all
  /// descendants. Returns their display names in BFS order, but ONLY
  /// for descendants whose IDs are in [visibleIds].
  List<String> _resolveExpandedBranchMemberNames(
    dynamic flat,
    String rootPersonId, {
    Set<String>? visibleIds,
  }) {
    final List<String> visibleMemberNames = [];
    if (flat == null) return visibleMemberNames;

    // v5.146: Use the shared buildChildrenOf which handles BOTH
    // parent-type and child-type relationship directions.
    final childrenOfSet = BranchCollapseNotifier.buildChildrenOf(flat.relationships as List);
    final childrenMap = <String, List<String>>{
      for (final entry in childrenOfSet.entries)
        entry.key: entry.value.toList(),
    };

    // Build id → name map.
    final namesById = <String, String>{};
    for (final p in flat.persons as List) {
      final id = (p['id'] ?? '').toString();
      final name = ((p['name'] as String?) ?? '').trim();
      if (id.isNotEmpty) namesById[id] = name;
    }

    // BFS from root — only traverse through visible nodes.
    final visited = <String>{rootPersonId};
    final queue = [rootPersonId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final child in childrenMap[current] ?? <String>[]) {
        if (visited.add(child)) {
          // v5.144: Only add to results if this child is currently
          // visible on the canvas. Still traverse through it to find
          // deeper visible descendants, but don't include it in the
          // names list if it's hidden.
          final isVisible = visibleIds == null || visibleIds.contains(child);
          if (isVisible) {
            final name = namesById[child];
            if (name != null && name.isNotEmpty) visibleMemberNames.add(name);
          }
          // Continue BFS through this child even if it's not visible
          // (it might have visible grandchildren that are rendered
          // because they were independently expanded or are protected).
          queue.add(child);
        }
      }
    }
    return visibleMemberNames;
  }

  /// v5.132: The scrollable full-names sheet for a collapsed branch.
  ///
  /// Lists EVERY hidden member's name (resolved via
  /// [_resolveHiddenMemberNames] — raw-ID fallbacks for members that
  /// haven't been fetched yet). This sheet is a PREVIEW ONLY: it never
  /// expands the branch on the canvas, so the user can browse who is
  /// inside the branch without changing the graph.
  void _showFullNamesList(
    BuildContext context,
    CollapsedBranch branch,
    List<String> names,
  ) {
    final rootName = branch.rootPersonName.trim().isNotEmpty
        ? branch.rootPersonName.trim()
        : branch.branchLabel;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (listContext) {
        final height = MediaQuery.of(listContext).size.height;
        return SizedBox(
          height: height * 0.7,
          child: SafeArea(
            child: Column(
              children: [
                // ── Header ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          rootName.isEmpty
                              ? 'Hidden members (${names.length})'
                              : "$rootName's branch · "
                                  '${names.length} hidden',
                          style: const TextStyle(
                            color: KinrelColors.textWhite,
                            fontFamily: 'DMSans',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: KinrelColors.textSecondaryDark),
                        onPressed: () => Navigator.of(listContext).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(
                    color: KinrelColors.textSecondaryDark, height: 1),
                // ── Scrollable names list ────────────────────────────
                Expanded(
                  child: names.isEmpty
                      ? const Center(
                          child: Text(
                            'No hidden members found.',
                            style: TextStyle(
                              color: KinrelColors.textSecondaryDark,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 20),
                          itemCount: names.length,
                          separatorBuilder: (_, __) => const SizedBox(
                              height: 2),
                          itemBuilder: (context, index) => Row(
                            children: [
                              const Icon(Icons.person_outline_rounded,
                                  size: 16,
                                  color: KinrelColors.textSecondaryDark),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  names[index],
                                  style: const TextStyle(
                                    color: KinrelColors.textWhite,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// v5.x (BUG-1 fix — REMOVE LEADER LINE): the `_BranchChipLeaderPainter`
// class that used to live here has been DELETED. The previous version
// drew a thin dashed line from the chip back to the parent node's
// center when the chip had to be placed far away. The user reported
// this looked like "a floating single-line-plus-badge in empty space
// that doesn't clearly connect to anything meaningful." The chip is
// now always attached to (overlapping) the parent node's bottom edge,
// so no visual tether is needed. The whole painter class + its
// `paint`/`shouldRepaint` methods (~80 lines) are gone.
