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
///
/// NOTE: This is a `part`-file EXTENSION that splits the State class's
/// methods out of family_graph_engine_view.dart. The `setState` calls
/// below run against a live `_FamilyGraphEngineViewState` instance, so
/// the protected-member contract is satisfied at runtime — the analyzer
/// just cannot verify that through an extension, hence the per-line
/// ignores.
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
            boxShadow: KinrelFx.shadows([
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 6,
                offset: const Offset(1, 2),
              ),
            ]),
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
    // ignore: invalid_use_of_protected_member
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
          <({String fromId, String toId, String edgeId, String relationshipKey, String? labelAtoB})>[
        for (final Map<String, dynamic> r in edgesSrc)
          if (r['fromPersonId'] != null &&
              r['toPersonId'] != null &&
              r['id'] != null)
            (
              fromId: r['fromPersonId'].toString(),
              toId: r['toPersonId'].toString(),
              edgeId: r['id'].toString(),
              relationshipKey: (r['relationshipKey'] as String?) ?? '',
              labelAtoB: r['labelAtoB'] as String?,
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
    //
    // v5.210 (POSITION RESTORE): for MANUAL branches, BEFORE invalidating
    // the layout provider, we MERGE the pre-collapse snapshot positions
    // back into lastLayoutPositionsProvider. The subsequent layout pass
    // therefore runs with preservePositions=true AND a complete
    // previousPositions map (including the just-revealed descendants'
    // original positions) — every previously-placed node KEEPS its
    // pre-collapse position. This eliminates the overlap bug where a
    // fresh layout recompute placed newly-revealed descendants at the
    // same ring slot as pre-existing ring nodes.
    var restoredFromSnapshot = false;
    if (revealedIds.isNotEmpty) {
      final collapseState = ref.read(branchCollapseProvider);
      if (collapseState.manuallyCollapsedRoots
          .contains(branch.rootPersonId)) {
        ref.read(branchCollapseProvider.notifier)
            .expandManualBranch(branch.rootPersonId);

        // v5.210: Restore pre-collapse positions for manual branches.
        // Merge the snapshot into lastLayoutPositionsProvider so the
        // next layout pass uses preservePositions=true with the
        // complete previousPositions map.
        //
        // v5.212 (BRANCH-EXPAND FLAG): set justRestoredFromSnapshotProvider
        // to true so the next graphLayoutProvider pass can log the
        // appropriate debug message (BRANCH-EXPAND vs. other layout
        // passes). The flag is auto-reset by graphLayoutProvider after
        // it reads it, so it only fires once per restore.
        final snapshot = ref.read(
            preCollapseLayoutSnapshotProvider(widget.familyId));
        // [BUG-TRACE-v2] Issue 1: log the EXACT rootPersonId at lookup
        // time + the snapshot's stored keys + whether the snapshot's
        // stored root matches the lookup root byte-for-byte. This
        // directly addresses the user's question: "verify the rootPersonId
        // used at capture time in the 'Collapse this Branch' confirm
        // handler is the exact same ID used at lookup time in the expand
        // handler."
        //
        // We also log hashCode + length of the ID string so a subtle
        // difference (e.g. trailing whitespace, casing) is detectable
        // even when the printed strings look identical.
        final lookupRoot = branch.rootPersonId;
        final lookupRootHash = lookupRoot.hashCode;
        final lookupRootLen = lookupRoot.length;
        final snapshotKeys = snapshot?.keys.toList() ?? <String>[];
        final snapshotKeyHashes = snapshotKeys.isEmpty
            ? <String, int>{}
            : {for (final k in snapshotKeys) k: k.hashCode};
        // Find the stored key that MOST CLOSELY matches the lookup root
        // (case-insensitive, trimmed) so we can report whether the
        // difference is whitespace/casing vs. completely different IDs.
        String? bestMatchKey;
        var bestMatchReason = 'no snapshot';
        if (snapshot != null && snapshotKeys.isNotEmpty) {
          for (final k in snapshotKeys) {
            if (k == lookupRoot) {
              bestMatchKey = k;
              bestMatchReason = 'EXACT MATCH';
              break;
            }
            if (k.trim().toLowerCase() == lookupRoot.trim().toLowerCase()) {
              bestMatchKey ??= k;
              bestMatchReason = 'matches after trim+lowercase (whitespace/case difference)';
            }
          }
          if (bestMatchKey == null) {
            bestMatchReason = 'no match — lookup root is NOT in snapshot';
          }
        }
        debugPrint(
            '[BUG-TRACE-v2] EXPAND-RESTORE-LOOKUP root=$lookupRoot '
            'rootHash=$lookupRootLen chars/$lookupRootHash '
            'snapshotNull=${snapshot == null} '
            'snapshotKeys=$snapshotKeys '
            'snapshotKeyHashes=$snapshotKeyHashes '
            'snapshotContainsRootExact=${snapshot?.containsKey(lookupRoot) ?? false} '
            'bestMatchKey=$bestMatchKey '
            'bestMatchReason=$bestMatchReason');
        // [BUG-TRACE] Diagnostic case 1 + 2: log whether
        // restoredFromSnapshot will end up true or false for THIS
        // specific branch expand, and — if false — log the EXACT reason
        // (snapshot NULL vs snapshot exists but missing rootPersonId key
        // vs revealedIds empty). This pinpoints which of the three
        // diagnostic cases the user described is firing.
        debugPrint(
            '[BUG-TRACE] EXPAND-RESTORE root=${branch.rootPersonId} '
            'revealedIdsCount=${revealedIds.length} '
            'isManualBranch=${collapseState.manuallyCollapsedRoots.contains(branch.rootPersonId)} '
            'snapshotNull=${snapshot == null} '
            'snapshotKeys=${snapshot?.keys.toList() ?? []} '
            'snapshotContainsRoot=${snapshot?.containsKey(branch.rootPersonId) ?? false} '
            'restoredPositionsCount=${snapshot?[branch.rootPersonId]?.length ?? 0}');
        if (snapshot != null &&
            snapshot.containsKey(branch.rootPersonId)) {
          final restoredPositions = snapshot[branch.rootPersonId]!;
          // Start with current cached positions (for nodes that became
          // visible after the collapse via other mechanisms like search
          // jump), then overlay the snapshot positions for the
          // descendants that are about to be re-revealed.
          final currentPositions =
              ref.read(lastLayoutPositionsProvider(widget.familyId)) ??
                  <String, Offset>{};
          final merged = <String, Offset>{
            ...currentPositions,
            ...restoredPositions,
          };
          ref.read(lastLayoutPositionsProvider(widget.familyId).notifier)
              .state = merged;
          // v5.212: Set the branch-expand flow flag BEFORE invalidating
          // graphLayoutProvider so the layout pass can detect this is
          // a branch-expand recompute (vs. initial load, family switch,
          // realtime invalidation, or relationship-create).
          ref
              .read(justRestoredFromSnapshotProvider(widget.familyId)
                  .notifier)
              .state = true;
          // Remove the consumed snapshot entry so a subsequent collapse
          // of the same branch captures a fresh snapshot.
          final newSnapshot =
              Map<String, Map<String, Offset>>.from(snapshot)
            ..remove(branch.rootPersonId);
          ref.read(preCollapseLayoutSnapshotProvider(widget.familyId)
                  .notifier)
              .state = newSnapshot.isEmpty ? null : newSnapshot;
          restoredFromSnapshot = true;
          // [BUG-TRACE] Case 1 outcome: restoredFromSnapshot=true path.
          // Log a few sample restored positions to confirm keys + values
          // are non-degenerate before they reach the layout pass.
          final sampleRestored = restoredPositions.entries.take(3).map(
              (e) => '${e.key}=${e.value}').join(', ');
          debugPrint(
              '[BUG-TRACE] EXPAND-RESTORE OK: restoredFromSnapshot=true, '
              'mergedCount=${merged.length}, sampleRestored=[$sampleRestored]');
        } else {
          // [BUG-TRACE] Case 1 outcome: restoredFromSnapshot=false.
          // Log the precise reason this expand will fall through to the
          // cache-clear branch below — which forces a fresh global
          // layout (the original overlap-prone behavior).
          final reason = snapshot == null
              ? 'snapshot is NULL (collapse never captured one for this family)'
              : (snapshot.containsKey(branch.rootPersonId)
                  ? 'IMPOSSIBLE — containsKey returned true above'
                  : 'snapshot exists with ${snapshot.length} key(s) '
                      '${snapshot.keys.toList()} but MISSING rootPersonId=${branch.rootPersonId}');
          debugPrint(
              '[BUG-TRACE] EXPAND-RESTORE FAIL: restoredFromSnapshot=false, '
              'reason=$reason — layout pass will clear cache + fresh global recompute');
        }
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

    // v5.210 (POSITION RESTORE): when we successfully restored a
    // pre-collapse snapshot, SKIP the v5.207 cache-clear — we WANT
    // the layout engine to use preservePositions=true with the merged
    // previousPositions. Clearing the cache would defeat the restore
    // and force a fresh layout (the original overlap-prone behavior).
    //
    // For auto-branches and manual branches without a snapshot, fall
    // back to the v5.207 behavior: clear the cache + invalidate for a
    // fresh global layout (the only safe option when no pre-collapse
    // positions are available).
    if (mounted) {
      if (!restoredFromSnapshot) {
        // v5.213 (CASE 1 HARDENING): when restoredFromSnapshot is false
        // (snapshot was missing or didn't contain rootPersonId), the
        // original v5.207 path ALWAYS cleared the cache and forced a
        // fresh global layout recompute. That fresh layout sometimes
        // placed newly-revealed descendants at the same ring slot as
        // pre-existing ring nodes — re-introducing the overlap bug.
        //
        // With the v5.213 case 2 fix, this branch should be rarer (the
        // collapse path now falls back to lastLayoutPositionsProvider
        // when currentLayout is null). But it can still occur if the
        // cache was empty at BOTH capture time AND now.
        //
        // HARDENING: only clear the cache if it doesn't contain
        // positions for any of the about-to-be-revealed descendants.
        // If the cache DOES have positions for the descendants (e.g.
        // they were positioned before the collapse and the cache wasn't
        // cleared), preserve those positions — preservePositions=true
        // will keep them stable, and the layout engine will only need
        // to place any genuinely-new nodes (which the v5.211/v5.212
        // guard + radial_layout.dart's local-expansion path handle).
        final existingCache = ref.read(
            lastLayoutPositionsProvider(widget.familyId));
        // If the cache has positions for ANY of the about-to-be-revealed
        // descendants, preserve the cache. Otherwise, clear it (v5.207).
        final cacheHasAnyRevealed = existingCache != null
            ? revealedIds.any(existingCache.containsKey)
            : false;
        if (cacheHasAnyRevealed) {
          final cache = existingCache;
          debugPrint(
              '[BUG-TRACE] EXPAND-PRESERVE-CACHE: restoredFromSnapshot=false '
              'but lastLayoutPositionsProvider cache already has positions for '
              '${revealedIds.where(cache.containsKey).length} of '
              '${revealedIds.length} revealed descendants — PRESERVING cache '
              'instead of clearing. Avoids the fresh-layout overlap bug.');
          // Do NOT clear — let the layout pass use preservePositions=true
          // with the existing cache.
        } else {
          // v5.207: Clear cached positions so the layout provider does a
          // fresh global ring-fill instead of preserving old positions.
          debugPrint(
              '[BUG-TRACE] EXPAND-CLEAR-CACHE: restoredFromSnapshot=false AND '
              'cache has no positions for any revealed descendant — clearing '
              'cache + fresh layout. This is the original overlap-prone path '
              'but unavoidable here (we have no positions to restore).');
          ref.read(lastLayoutPositionsProvider(widget.familyId).notifier)
              .state = null;
        }
      }
      // Invalidate the layout provider to trigger a recomputation.
      // For restored manual branches, this triggers a layout pass that
      // uses preservePositions=true with the merged snapshot — keeping
      // pre-collapse positions stable for both previously-visible and
      // newly-revealed nodes.
      ref.invalidate(graphLayoutProvider(widget.familyId));
      // Trigger a canvas rebuild to pick up the new layout.
      // ignore: invalid_use_of_protected_member
      setState(() {});
    }
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
            ({String fromId, String toId, String edgeId, String relationshipKey, String? labelAtoB})>
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

              // WEDGE MODE: collapse is owned by the wedge view state —
              // the person's paged children leave the layout (the
              // loaded data stays in the proximity set for instant
              // re-expansion). Identical positions are restored on
              // re-expand (deterministic wedge re-division).
              if (kUseViewerWedgeLayout) {
                ref
                    .read(wedgeViewProvider.notifier)
                    .collapsePerson(rootPersonId);
                _cancelEntranceAnimation();
                ref.invalidate(graphLayoutProvider(widget.familyId));
                return;
              }

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
                // v5.210 (POSITION SNAPSHOT): BEFORE the manual collapse
                // hides the descendants, snapshot the CURRENT layout
                // positions for ALL visible nodes. These positions will
                // be RESTORED on the subsequent expand so the layout
                // engine keeps pre-collapse positions stable via
                // preservePositions=true — preventing the overlap bug
                // that occurred when a fresh layout recompute placed
                // newly-revealed descendants at the same ring slot as
                // pre-existing ring nodes.
                //
                // v5.212 (SNAPSHOT VALIDATION): validate positions AT
                // CAPTURE TIME before saving. If any node's position is
                // degenerate (at origin (0,0), or a duplicate of another
                // node's position), correct it BEFORE saving so bad data
                // never enters the snapshot. This is the "fix bad data
                // at the source" approach — a restored snapshot can
                // never again introduce overlapping positions because
                // the snapshot itself was already validated.
                //
                // Repairs applied:
                //   1. Origin (0,0): replace with a tiny radial offset
                //      (0.5px in X) so the node has a unique coordinate.
                //   2. Duplicate pair: nudge the LATER node (by insertion
                //      order) by 180px in X — same minHorizontal used by
                //      the de-overlap pass. This guarantees every node
                //      in the snapshot has a unique (x, y).
                final currentLayout = ref
                    .read(graphLayoutProvider(widget.familyId))
                    .valueOrNull;
                // v5.213 (CASE 2 FIX): FALLBACK when currentLayout is null
                // or its positions map is empty. The original v5.210/v5.212
                // path silently SKIPPED the snapshot save when
                // currentLayout was null — this is the root cause of the
                // "snapshot missing rootPersonId key" branch-expand case.
                // The expand path then fell through to clearing
                // lastLayoutPositionsProvider and forcing a fresh global
                // layout recompute, which re-introduces the overlap bug
                // that v5.210 was specifically designed to fix.
                //
                // Common scenarios where currentLayout is null at collapse
                // time:
                //   - User collapsed a branch DURING the initial layout
                //     (graphLayoutProvider still AsyncLoading).
                //   - A recent invalidation is still in-flight (e.g.
                //     proximity changed, familyGraphProvider refetched).
                //   - The provider errored and valueOrNull returns null.
                //
                // FIX: when currentLayout is null/empty, fall back to the
                // lastLayoutPositionsProvider cache. This cache holds the
                // positions from the LAST SUCCESSFUL layout pass — which
                // is exactly what we want to restore on the subsequent
                // expand. If even the cache is null/empty, we genuinely
                // cannot capture a snapshot (no positions exist anywhere)
                // — but that's a degenerate state we can't help with
                // here.
                final cacheFallback = ref.read(
                    lastLayoutPositionsProvider(widget.familyId));
                // [BUG-TRACE] Diagnostic case 2: log snapshot-capture
                // conditions at the moment "Collapse this Branch" is
                // confirmed. If currentLayout is null or its positions
                // map is empty, the snapshot for this rootPersonId will
                // NEVER be saved — which is the root cause of the
                // "snapshot missing rootPersonId key" branch-expand case.
                debugPrint(
                    '[BUG-TRACE-v2] COLLAPSE-CAPTURE-LOOKUP root=$rootPersonId '
                    'rootHash=${rootPersonId.length} chars/${rootPersonId.hashCode} '
                    'currentLayout=${currentLayout == null ? "NULL" : "OK"} '
                    'positionsCount=${currentLayout?.positions.length ?? 0} '
                    'positionsKeys=${currentLayout?.positions.keys.toList().take(5).toList()} '
                    'cacheFallbackCount=${cacheFallback?.length ?? 0} '
                    'cacheFallbackKeys=${cacheFallback?.keys.toList().take(5).toList() ?? []}');
                // Pick the positions source: prefer currentLayout, fall
                // back to cache, give up if both are empty.
                final Map<String, Offset>? positionsSource;
                if (currentLayout != null &&
                    currentLayout.positions.isNotEmpty) {
                  positionsSource = currentLayout.positions;
                } else if (cacheFallback != null &&
                    cacheFallback.isNotEmpty) {
                  positionsSource = cacheFallback;
                  debugPrint(
                      '[BUG-TRACE] COLLAPSE-CAPTURE FALLBACK: currentLayout was null/empty — '
                      'using lastLayoutPositionsProvider cache with ${cacheFallback.length} entries '
                      'as the snapshot source. This prevents the "snapshot missing rootPersonId" '
                      'expand-time failure that was re-introducing the overlap bug.');
                } else {
                  positionsSource = null;
                  debugPrint(
                      '[BUG-TRACE] COLLAPSE-CAPTURE NO-SOURCE: both currentLayout AND '
                      'lastLayoutPositionsProvider cache are null/empty — cannot snapshot. '
                      'The subsequent expand will fall through to cache-clear + fresh layout.');
                }
                if (positionsSource != null &&
                    positionsSource.isNotEmpty) {
                  // [BUG-TRACE] Confirm the rootPersonId is actually KEYED
                  // in the snapshot positions map (a sanity check — the
                  // root itself should always have a position from the
                  // layout pass; if it doesn't, the snapshot will be
                  // missing the most important key).
                  debugPrint(
                      '[BUG-TRACE] COLLAPSE-CAPTURE rootInPositions=${positionsSource.containsKey(rootPersonId)} '
                      'rootPos=${positionsSource[rootPersonId]}');
                  // v5.212: Validate + repair positions BEFORE snapshot.
                  final validatedPositions = Map<String, Offset>.from(
                      positionsSource);
                  var repairCount = 0;
                  final entries = validatedPositions.entries.toList();
                  // Repair 1: any node at (0,0) gets nudged to (0.5, 0).
                  // (0,0) is the canvas origin — distinct nodes should
                  // never be there since radial layout places the
                  // anchor at (maxRadius + padding, maxRadius + padding).
                  for (final entry in entries) {
                    if (entry.value.dx == 0.0 && entry.value.dy == 0.0) {
                      validatedPositions[entry.key] =
                          const Offset(0.5, 0.0);
                      repairCount++;
                    }
                  }
                  // Repair 2: any duplicate pair gets nudged.
                  final repairedEntries =
                      validatedPositions.entries.toList();
                  for (var i = 0; i < repairedEntries.length; i++) {
                    for (var j = i + 1; j < repairedEntries.length; j++) {
                      final idA = repairedEntries[i].key;
                      final idB = repairedEntries[j].key;
                      final a = validatedPositions[idA]!;
                      final b = validatedPositions[idB]!;
                      if ((a.dx - b.dx).abs() <= 1.0 &&
                          (a.dy - b.dy).abs() <= 1.0) {
                        // Nudge B by 180px in X (minHorizontal spacing).
                        validatedPositions[idB] =
                            Offset(b.dx + 180.0, b.dy);
                        repairCount++;
                      }
                    }
                  }
                  if (repairCount > 0) {
                    debugPrint(
                        '[BRANCH-COLLAPSE] v5.212: repaired $repairCount '
                        'degenerate position(s) at SNAPSHOT-CAPTURE time '
                        '(root=$rootPersonId) — bad data prevented from '
                        'entering the snapshot.');
                  }
                  // Save the VALIDATED positions into the snapshot.
                  final snapshot = Map<String, Map<String, Offset>>.from(
                    ref.read(preCollapseLayoutSnapshotProvider(
                        widget.familyId)) ??
                        {},
                  );
                  snapshot[rootPersonId] = validatedPositions;
                  ref
                      .read(preCollapseLayoutSnapshotProvider(
                          widget.familyId).notifier)
                      .state = snapshot;
                  // [BUG-TRACE-v2] Issue 1: confirm the snapshot was
                  // actually saved, with the EXACT rootPersonId used as
                  // the key. This + the EXPAND-RESTORE-LOOKUP log above
                  // closes the loop: if both logs print the same
                  // rootPersonId + hashCode, capture and lookup agree.
                  debugPrint(
                      '[BUG-TRACE-v2] COLLAPSE-CAPTURE-SAVED root=$rootPersonId '
                      'rootHash=${rootPersonId.length} chars/${rootPersonId.hashCode} '
                      'positionsCount=${validatedPositions.length} '
                      'snapshotTotalKeys=${snapshot.length}');
                }

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

  // ── WEDGE LAYOUT: reserved "+N" page chips ─────────────────────────
  //
  // The viewer-centered wedge layout reserves ONE extra leaf slot for
  // the "+N" chip whenever an expanded person has more children than
  // the current page shows. The slots (canvas-space centres + counts)
  // come from wedgeChipSlotsProvider — written by graphLayoutProvider's
  // wedge path. The chip VISUAL is byte-for-byte the existing collapsed
  // branch chip (Container + radius 14 + accent border + Icon + Text)
  // — only the tap behaviour differs: it turns to the NEXT PAGE of that
  // person's children (fetching any not-yet-loaded members first).

  /// Builds the positioned "+N" page chips at their reserved slot
  /// centres. Renders NOTHING when the wedge layout reported no slots.
  ///
  /// Each chip is a professional circular bubble (Ø52, inside its
  /// reserved 84×84 layout slot) with a DASHED ring in the hub's edge
  /// colour and "+N" in the display font — the same visual family +
  /// brand colours as the legacy chips. While the lazy fetch runs, a
  /// small spinner replaces the number and extra taps are ignored.
  /// When a hub has nothing left to reveal, its bubble fades out (the
  /// ghost is rendered for one short fade cycle — see
  /// [_wedgeFadingChips]).
  List<Widget> _buildWedgePageChips() {
    if (!kUseViewerWedgeLayout) return const [];
    final chips =
        ref.watch(wedgeChipSlotsProvider(widget.familyId));

    final result = <Widget>[];
    final Map<String, WedgePageChip> liveChips;
    if (chips == null || chips.isEmpty) {
      liveChips = const <String, WedgePageChip>{};
    } else {
      liveChips = chips;
    }

    // Fade-out bookkeeping: a hub that STILL has an expansion but whose
    // chip just vanished has paged to the very end ("when nothing
    // remains, the bubble fades out"). Track it as a ghost for one
    // short fade cycle at its last reserved slot.
    final wedgeState = ref.read(wedgeViewProvider);
    final previous = _lastSeenWedgeChipSlots;
    if (previous != null) {
      for (final entry in previous.entries) {
        if (!liveChips.containsKey(entry.key) &&
            wedgeState.expandedRoots.contains(entry.key)) {
          _wedgeFadingChips[entry.key] = entry.value;
        }
      }
    }
    _lastSeenWedgeChipSlots = Map<String, WedgePageChip>.of(liveChips);
    if (_wedgeFadingChips.isNotEmpty && _wedgeFadeCleanupTimer == null) {
      _wedgeFadeCleanupTimer = Timer(const Duration(milliseconds: 400), () {
        _wedgeFadeCleanupTimer?.cancel();
        _wedgeFadeCleanupTimer = null;
        if (_wedgeFadingChips.isEmpty) return;
        _wedgeFadingChips.clear();
        // ignore: invalid_use_of_protected_member
        setState(() {});
      });
    }

    // Deterministic render order: slot angle then owner id.
    final entries = liveChips.values.toList()
      ..sort((a, b) {
        final byAngle =
            a.slotCenter.direction.compareTo(b.slotCenter.direction);
        if (byAngle != 0) return byAngle;
        return a.personId.compareTo(b.personId);
      });

    final l10n = S.of(context);
    // WEDGE GLIDE — chip slot lerp: while the wedge glide animation is
    // active, lerp each live chip's slot centre from its previous
    // position to the new one. Chips with no previous slot (brand-new
    // hubs that just gained a +N bubble) keep their new slot centre
    // — they "pop in" at the new spot (the entrance animation for the
    // hub's children already moves the new children into place, so
    // the bubble appearing in its final spot reads naturally).
    final bool chipGlideActive = _wedgeGlideActive &&
        _wedgeGlideFromChipSlots != null &&
        _branchAnimationProgress < 1.0;
    final double chipT = _branchAnimationProgress.clamp(0.0, 1.0);
    Offset resolveChipSlotCenter(WedgePageChip chip) {
      if (!chipGlideActive) return chip.slotCenter;
      final prev = _wedgeGlideFromChipSlots![chip.personId];
      if (prev == null) return chip.slotCenter;
      return Offset(
        prev.slotCenter.dx * (1.0 - chipT) + chip.slotCenter.dx * chipT,
        prev.slotCenter.dy * (1.0 - chipT) + chip.slotCenter.dy * chipT,
      );
    }

    for (final chip in entries) {
      final slotCenter = resolveChipSlotCenter(chip);
      result.add(Positioned(
        left: slotCenter.dx,
        top: slotCenter.dy,
        child: _WedgePageChipBubble(
          remainingCount: chip.remainingCount,
          accentColor: _wedgeChipAccentColor(chip.personId),
          loading: _optimisticLoadingChipRootId == chip.personId,
          semanticLabel:
              l10n?.graphMorePeople(chip.remainingCount) ??
              'Show ${chip.remainingCount} more family members. '
                  'Double-tap to show the next page.',
          onTap: () {
            GraphHaptics.branchExpand(context);
            _expandWedgePageChip(chip.personId);
          },
        ),
      ));
    }

    // Ghost bubbles — fading out at their last reserved slots.
    final ghosts = _wedgeFadingChips.values.toList()
      ..sort((a, b) => a.personId.compareTo(b.personId));
    for (final ghost in ghosts) {
      result.add(Positioned(
        left: ghost.slotCenter.dx,
        top: ghost.slotCenter.dy,
        child: _WedgeChipFadeOut(
          // Fade out with the count the user saw when they tapped (the
          // ghost entry is the chip's LAST non-empty frame).
          child: _WedgePageChipBubble(
            remainingCount: ghost.remainingCount,
            accentColor: _wedgeChipAccentColor(ghost.personId),
            loading: false,
            semanticLabel: '',
            onTap: null,
          ),
        ),
      ));
    }
    return result;
  }

  /// The accent colour for a wedge page chip: the chip owner's kinship
  /// category colour (via the authoritative per-person category cache
  /// the canvas computes). Falls back to the orange the legacy chips
  /// use when the owner has no category yet.
  Color _wedgeChipAccentColor(String personId) {
    final cats = _cachedRelationCategories;
    final category = cats?[personId];
    if (category == null || category == KinshipEdgeCategory.self) {
      return KinrelColors.orange;
    }
    return KinshipEdgeStyleResolver.styleForCategory(category).color;
  }

  /// WEDGE CHIP TAP: shows the NEXT page of [personId]'s children.
  ///
  /// 1. Optimistically advances the page (wedgeViewProvider) — already
  ///    loaded children appear immediately.
  /// 2. Lazily fetches the branch (the existing get_member_branch RPC
  ///    merge) so not-yet-loaded members of the next page appear when
  ///    the fetch lands.
  /// 3. Reveals the loaded children into the proximity set + marks the
  ///    entrance animation + invalidates the layout provider.
  Future<void> _expandWedgePageChip(String personId) async {
    if (personId.isEmpty) return;
    // While a bubble's lazy fetch is in flight its number is replaced
    // by a spinner and EXTRA TAPS ARE IGNORED (one page turn at a
    // time — the fetch + layout recompute must land first).
    if (_optimisticLoadingChipRootId != null) return;

    // Optimistic feedback + page turn.
    // ignore: invalid_use_of_protected_member
    setState(() {
      _optimisticLoadingChipRootId = personId;
    });
    ref.read(wedgeViewProvider.notifier).advancePage(personId);

    final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;

    // Reveal every LOADED child of [personId] into the proximity set
    // (the ones the next page will render). Data-level: identical to
    // the legacy chip flow's revealPersons step.
    final rawEdges = flat?.allRelationships ?? flat?.relationships;
    if (flat != null && rawEdges != null) {
      final loadedIds = <String>{
        for (final p in flat.persons) (p['id'] ?? '').toString(),
      };
      final childIds = <String>{};
      for (final Map<String, dynamic> r in rawEdges) {
        final from = (r['fromPersonId'] ?? '').toString();
        final to = (r['toPersonId'] ?? '').toString();
        if (from == personId && loadedIds.contains(to)) {
          childIds.add(to);
        } else if (to == personId && loadedIds.contains(from)) {
          childIds.add(from);
        }
      }
      if (childIds.isNotEmpty) {
        ref.read(proximityGraphProvider.notifier).revealPersons(
              personIds: childIds,
              allPersons: loadedIds,
            );
        // Entrance animation: fly the page's children out from the
        // chip owner's current position.
        final layout =
            ref.read(graphLayoutProvider(widget.familyId)).valueOrNull;
        _markNodesForEntrance(
          childIds,
          origin: layout?.positions[personId],
        );
      }
    }

    // Lazy fetch: brings the not-yet-loaded members of the next page
    // into the provider state (the merge itself invalidates the layout
    // provider; the invalidation below covers the no-fetch path).
    try {
      await ref.read(familyGraphProvider(widget.familyId).notifier)
          .fetchBranchAndMerge(
        rootPersonId: personId,
        branchType: 'generic',
        depth: 2,
      );
    } catch (e) {
      debugPrint('[WedgePageChip] branch fetch failed for $personId: $e');
    }

    // ignore: invalid_use_of_protected_member
    setState(() {
      _optimisticLoadingChipRootId = null;
    });
    ref.invalidate(graphLayoutProvider(widget.familyId));
  }

  /// WEDGE NODE TAP: expands [personId] (shows page 1 of their
  /// children), revealing + lazily fetching as needed. Mirrors the
  /// semantics of the legacy node-tap expansion, but the wedge layout
  /// pages the children (top 8) instead of revealing everything.
  Future<void> _expandWedgeNode(String personId) async {
    if (personId.isEmpty) return;
    ref.read(wedgeViewProvider.notifier).expandPerson(personId);

    final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;
    if (flat == null) {
      ref.invalidate(graphLayoutProvider(widget.familyId));
      return;
    }

    final loadedIds = <String>{
      for (final p in flat.persons) (p['id'] ?? '').toString(),
    };
    final rawEdges = flat.allRelationships ?? flat.relationships;

    // Every neighbour over the FULL edge list (loaded or not) — the
    // fetch below will load the rest.
    final allNeighborIds = <String>{};
    final loadedNeighborIds = <String>{};
    for (final Map<String, dynamic> r in rawEdges) {
      final from = (r['fromPersonId'] ?? '').toString();
      final to = (r['toPersonId'] ?? '').toString();
      String? neighbor;
      if (from == personId) {
        neighbor = to;
      } else if (to == personId) {
        neighbor = from;
      }
      if (neighbor == null || neighbor.isEmpty || neighbor == personId) {
        continue;
      }
      allNeighborIds.add(neighbor);
      if (loadedIds.contains(neighbor)) {
        loadedNeighborIds.add(neighbor);
      }
    }

    if (loadedNeighborIds.isNotEmpty) {
      ref.read(proximityGraphProvider.notifier).revealPersons(
            personIds: loadedNeighborIds,
            allPersons: loadedIds,
          );
      final layout =
          ref.read(graphLayoutProvider(widget.familyId)).valueOrNull;
      _markNodesForEntrance(
        loadedNeighborIds,
        origin: layout?.positions[personId],
      );
    }

    // Lazy fetch ONLY when some children are not loaded yet.
    final hasUnloadedNeighbors =
        allNeighborIds.any((id) => !loadedIds.contains(id));
    if (hasUnloadedNeighbors) {
      try {
        await ref.read(familyGraphProvider(widget.familyId).notifier)
            .fetchBranchAndMerge(
          rootPersonId: personId,
          branchType: 'generic',
          depth: 2,
        );
      } catch (e) {
        debugPrint('[WedgeNode] branch fetch failed for $personId: $e');
      }
    }

    ref.invalidate(graphLayoutProvider(widget.familyId));
  }

  // ── WEDGE LAYOUT: node tap state machine ──────────────────────────
  //
  // The approved-preview tap rules (all state changes funnel through
  // wedgeViewProvider so the layout, chips, and camera-fit animation
  // all recompute from ONE intent source):
  //
  //   • collapsed person        → expand in place (first 8) + focus
  //   • expanded, NOT focused   → focus them (camera fits the branch)
  //   • focused + expanded      → collapse them + focus their parent
  //
  // "Focus" here is the WEDGE focus (WedgeViewState.focusedPersonId) —
  // a browsing focus that never dims the graph. If the isolate-style
  // graphFocusProvider focus happens to be active (e.g. after a search
  // jump), a wedge tap exits it first — browsing takes over.

  /// WEDGE NODE TAP: the full tap state machine (see the block comment
  /// above). Called from event_helpers._maybeExpandFromPerson.
  void _handleWedgeNodeTap(String personId) {
    final wedge = ref.read(wedgeViewProvider);
    final viewerId =
        ref.read(viewerPersonIdProvider(widget.familyId)).valueOrNull;

    // Exit any isolate-connections focus (search jump / "Isolate
    // connections") — an active wedge browse supersedes it. Focus mode
    // dims the rest of the graph to 18%, which fights the wedge
    // overview; clearing it here never moves the camera by itself.
    if (ref.read(graphFocusProvider).focusedPersonId != null) {
      ref.read(graphFocusProvider.notifier).clearFocus();
    }

    // The viewer/root is ALWAYS expanded and never collapses — tapping
    // it just (re-)focuses the root branch (top-8 + its parent fit).
    if (personId == viewerId) {
      ref.read(wedgeViewProvider.notifier).focusPerson(personId);
      return;
    }

    final isExpanded = wedge.expandedRoots.contains(personId);

    if (!isExpanded) {
      // Case 1 — collapsed person: expand in place with their first 8
      // connections, focus them, and fit the camera to them + their
      // children + their parent (the fit rides the wedge revision
      // change that _expandWedgeNode's expansion triggers).
      _focusWedgePerson(personId);
      _expandWedgeNode(personId);
      return;
    }

    if (wedge.focusedPersonId != personId) {
      // Case 2 — expanded but not focused: focus them and fit the
      // camera to their branch (focusPerson bumps the revision with
      // lastActionPersonId = the person → _maybeFitCameraOnWedgeChange
      // fits them + their children + their parent).
      ref.read(wedgeViewProvider.notifier).focusPerson(personId);
      return;
    }

    // Case 3 — focused + expanded: collapse them and focus their
    // parent. The camera fit rides the collapse's revision change
    // (lastActionPersonId = the collapsed person, whose fit set
    // includes their parent).
    final summary =
        ref.read(wedgeLayoutSummaryProvider(widget.familyId));
    final parent = summary?.parentOf[personId];
    ref
        .read(wedgeViewProvider.notifier)
        .collapseAndFocusParent(personId, parent);
    _cancelEntranceAnimation();
    ref.invalidate(graphLayoutProvider(widget.familyId));
  }

  /// Sets the WEDGE browsing focus on [personId] (WedgeViewState, not
  /// the isolate-style graphFocusProvider). Side-effect free apart from
  /// the state write — no dimming, no camera move (the camera fit rides
  /// the wedge revision change like every other wedge action).
  void _focusWedgePerson(String personId) {
    ref.read(wedgeViewProvider.notifier).focusPerson(personId);
  }

  // ── WEDGE LAYOUT: collapsed-person count badges ───────────────────
  //
  // Collapsed people who have connections show a small count badge
  // ("+11") overlaying the top-right of their node — drawn by this chip
  // layer (NOT by GraphNode, which stays untouched) using the
  // precomputed connection-degree map from canvas_mixin. Tapping the
  // badge OR the node expands it (the same _handleWedgeNodeTap flow).
  // The badge colour is the person's relationship colour.

  /// Builds positioned "+N" count badges for every VISIBLE, COLLAPSED
  /// person that has at least one connection. Renders nothing in
  /// radial mode or when no counts are cached yet.
  List<Widget> _buildWedgeCountBadges() {
    if (!kUseViewerWedgeLayout) return const [];
    final counts = _cachedConnectionCountById;
    if (counts == null || counts.isEmpty) return const [];

    final wedge = ref.watch(wedgeViewProvider);
    final layout =
        ref.watch(graphLayoutProvider(widget.familyId)).valueOrNull;
    if (layout == null || layout.positions.isEmpty) return const [];

    final viewerId =
        ref.read(viewerPersonIdProvider(widget.familyId)).valueOrNull;

    // Deterministic order: angle around the canvas origin, then id.
    final entries = layout.positions.entries.where((entry) {
      return shouldShowWedgeCountBadge(
        personId: entry.key,
        viewerId: viewerId,
        expandedRoots: wedge.expandedRoots,
        connectionCounts: counts,
      );
    }).toList()
      ..sort((a, b) {
        final byAngle = a.value.direction.compareTo(b.value.direction);
        if (byAngle != 0) return byAngle;
        return a.key.compareTo(b.key);
      });

    final l10n = S.of(context);
    final result = <Widget>[];
    for (final entry in entries) {
      final count = counts[entry.key] ?? 0;
      if (count <= 0) continue;
      final pos = entry.value;
      // Node visual: the Positioned box is 140×176 centred on pos with
      // the avatar circle at its top. Anchor the badge INSIDE the
      // node's top-right corner so it never leaves the node's reserved
      // footprint (no new overlap risk) — the classic notification
      // badge look. The anchor is the badge CENTRE (dx, dy from pos).
      result.add(Positioned(
        left: pos.dx + _kWedgeBadgeAnchor.dx,
        top: pos.dy + _kWedgeBadgeAnchor.dy,
        child: _WedgeCountBadge(
          count: count,
          color: _wedgeChipAccentColor(entry.key),
          semanticLabel: l10n?.graphMorePeople(count) ??
              '$count more people, double tap to show',
          onTap: () => _handleWedgeNodeTap(entry.key),
        ),
      ));
    }
    return result;
  }
}

/// The count-badge centre offset from the node centre: inside the
/// top-right of the 124×128 node footprint (avatar circle area),
/// clear of the name label below the circle.
const Offset _kWedgeBadgeAnchor = Offset(46.0, -46.0);

// v5.x (BUG-1 fix — REMOVE LEADER LINE): the `_BranchChipLeaderPainter`
// class that used to live here has been DELETED. The previous version
// drew a thin dashed line from the chip back to the parent node's
// center when the chip had to be placed far away. The user reported
// this looked like "a floating single-line-plus-badge in empty space
// that doesn't clearly connect to anything meaningful." The chip is
// now always attached to (overlapping) the parent node's bottom edge,
// so no visual tether is needed. The whole painter class + its
// `paint`/`shouldRepaint` methods (~80 lines) are gone.

// ── WEDGE LAYOUT: bubble + badge widgets ────────────────────────────
//
// The "+N" page bubble: a NODE — not a chip. The bubble uses the
// EXACT SAME Pseudo3DNodePainter as a real GraphNode, so it has the
// same shadow, extruded wall, face fill, rim, bevel, and specular
// highlight as a person node. The only differences from a person
// node:
//   • border color = KinshipEdgeColors.extended (the neutral grey
//     token used for extended/step relations and nodes with no
//     category — never the hub's category colour, never a hardcoded
//     hex value)
//   • content = "+N" (same Outfit bold font/weight as node initials)
//   • onTap = the page-advance handler (not node selection)
//
// The reserved layout slot is 124×128 (WedgeLayoutConfig.chipFootprint
// == nodeFootprint), so the node-sized bubble (Ø72) + its shadow
// reserve the full space and never overlap a neighbour.
//
// Press feedback: the bubble scales to ~0.95 while pressed (with the
// existing GraphHaptics.branchExpand firing on tap). While the lazy
// fetch is in flight a small spinner replaces the "+N" text. When a
// hub has nothing left to reveal, its bubble shrinks and fades out
// (see [_WedgeChipFadeOut]).

/// The circular "+N" page bubble (see the block comment above).
///
/// The [accentColor] parameter is kept for backward compatibility with
/// the existing call sites but is NO LONGER used for the ring — the
/// ring always uses [KinshipEdgeColors.extended] (the neutral grey
/// token) per the spec ("do not use the hub's category colour and do
/// not hardcode a hex value"). The parameter is retained so the
/// caller signature stays stable; it MAY be used for the spinner's
/// tint during a fetch (a subtle nod to the hub's category that
/// doesn't bleed into the ring's neutral contract).
class _WedgePageChipBubble extends StatefulWidget {
  const _WedgePageChipBubble({
    required this.remainingCount,
    required this.accentColor,
    required this.loading,
    required this.semanticLabel,
    required this.onTap,
  });

  final int remainingCount;
  final Color accentColor;
  final bool loading;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  State<_WedgePageChipBubble> createState() => _WedgePageChipBubbleState();
}

class _WedgePageChipBubbleState extends State<_WedgePageChipBubble> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Node-sized circle: Ø72 matches GraphNode's default nodeSize.
    // The bubble now uses the EXACT SAME Pseudo3DNodePainter as a real
    // GraphNode — same shadow, extruded wall, face fill, rim, bevel,
    // specular highlight — so it reads as a NODE, not a chip. The only
    // differences from a person node:
    //   • border color = KinshipEdgeColors.extended (the neutral grey
    //     used for extended/step relations and nodes with no category)
    //   • content = "+N" instead of initials
    //   • onTap = the page-advance handler (not node selection)
    // The dashed ring is GONE — the user said "it should not be a chip
    // anymore even it should feel like node with grey color". A real
    // node has a SOLID border ring, not a dashed one.
    const circleDiameter = 72.0;
    // Node initials use diameter * 0.28 — same scale here so "+N"
    // reads as the same visual weight as a 2-letter initials glyph.
    const numberFontSize = circleDiameter * 0.28; // ≈ 20.2

    // Build the Pseudo3DNodeParams exactly like GraphNode does for a
    // regular (non-anchor, non-immediate-family) node — see
    // graph_node.dart line 1087-1094. The border color is the neutral
    // grey token (KinshipEdgeColors.extended) instead of the hub's
    // category color.
    final nodeParams = Pseudo3DNodeParams(
      diameter: circleDiameter,
      borderColor: KinshipEdgeColors.extended,
      // GraphNode's default borderWidth for non-anchor non-immediate-
      // family nodes is 3.0 (see graph_node.dart line 1090-1094:
      // isAnchor ? 4.5 : isImmediateFamily ? 3.5 : _borderWidth where
      // _borderWidth defaults to 3.0).
      borderWidth: 3.0,
      generationIndex: 0,
      isAnchor: false,
      nodeState: _pressed ? NodeState.hover : NodeState.normal,
      tintColor: KinshipEdgeColors.extended.withValues(alpha: 0.08),
      showTint: _pressed,
    );

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FractionalTranslation(
        // Centre the circle on the reserved slot. FractionalTranslation
        // never expands (unlike Center, it cannot eat the canvas' taps).
        translation: const Offset(-0.5, -0.5),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => setState(() => _pressed = true),
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // While loading, taps are ignored (the spinner is showing).
            onTap: widget.loading ? null : widget.onTap,
            child: AnimatedScale(
              scale: _pressed ? 0.95 : 1.0,
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              child: SizedBox(
                width: circleDiameter,
                height: circleDiameter,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // The pseudo-3D node painter — renders the EXACT
                    // same visual as a real GraphNode (shadow, wall,
                    // face, rim, bevel, specular). This is what makes
                    // the bubble "feel like a node" instead of a chip.
                    CustomPaint(
                      size: const Size(circleDiameter, circleDiameter),
                      painter: Pseudo3DNodePainter(nodeParams),
                    ),
                    // Content layer: "+N" (or spinner during fetch).
                    // Same font family + weight as node initials.
                    if (widget.loading)
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          // The spinner uses the hub's category colour
                          // as a subtle nod — the node's border stays
                          // neutral grey, but the spinner's tint hints
                          // at which hub is loading.
                          valueColor: AlwaysStoppedAnimation<Color>(
                            widget.accentColor,
                          ),
                        ),
                      )
                    else
                      Text(
                        '+${widget.remainingCount}',
                        // SAME font family + weight as node initials
                        // (KinrelTypography.displayFont = 'Outfit',
                        // FontWeight.bold = w700). Same color
                        // (KinrelColors.textWhite) so the "+N" reads
                        // exactly like a person's initials.
                        style: const TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: numberFontSize,
                          fontWeight: FontWeight.bold,
                          color: KinrelColors.textWhite,
                          height: 1.0,
                        ),
                        maxLines: 1,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a just-emptied bubble and fades it out over ~260 ms
/// ("when nothing remains, the bubble fades out").
class _WedgeChipFadeOut extends StatelessWidget {
  const _WedgeChipFadeOut({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // PER THE APPROVED-PREVIEW CONTRACT: "When nothing remains, the
    // bubble shrinks and fades out." We run BOTH a scale-down (1.0 → 0.0)
    // AND an opacity fade (1.0 → 0.0) over 280ms easeOut — slightly
    // longer than the prior 260ms so the shrink reads as a deliberate
    // gesture (the user just paged to the end), not a flicker.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1.0, end: 0.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      builder: (context, t, child) => IgnorePointer(
        child: Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.6 + 0.4 * t, // shrinks from 1.0 to 0.6 as it fades
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// The small "+N" connection-count badge overlaying the top-right of a
/// COLLAPSED person's node (see _buildWedgeCountBadges). It's a CORNER
/// BADGE (not a bubble) — a small rounded pill in the NEUTRAL GREY
/// token (KinshipEdgeColors.extended — the same slate used for
/// extended/step relations and for nodes with no category), NOT the
/// person's category colour. The number is at least 14px (readable
/// at arm's length); the badge height is ~28px (compact enough to
/// sit on the node's circle without crowding the name). The tap
/// target is 48×48 (the accessibility minimum), centred on the badge
/// — tapping it expands the person, exactly like tapping the node.
class _WedgeCountBadge extends StatefulWidget {
  const _WedgeCountBadge({
    required this.count,
    required this.color,
    required this.semanticLabel,
    required this.onTap,
  });

  final int count;
  /// IGNORED — kept for backward compatibility with the existing call
  /// sites. The badge now always uses the neutral grey token
  /// (KinshipEdgeColors.extended) per the spec ("neutral grey instead
  /// of the person's category colour"). The person's category colour
  /// is never used for the badge fill.
  final Color color;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  State<_WedgeCountBadge> createState() => _WedgeCountBadgeState();
}

class _WedgeCountBadgeState extends State<_WedgeCountBadge> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => setState(() => _pressed = true),
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _pressed ? 0.95 : 1.0,
              duration: const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              // 48×48 tap target — the accessibility minimum. The
              // visual badge sits centred inside this transparent
              // hit area.
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                color: Colors.transparent,
                child: Container(
                  // ~28px tall badge — compact enough to sit on the
                  // node's circle without crowding the name, large
                  // enough to be readable. The width auto-sizes to
                  // the content (number + horizontal padding).
                  height: 28,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    // Neutral grey fill — the SAME token used for
                    // extended/step relations and the +N page bubble
                    // ring. Never the person's category colour.
                    color: KinshipEdgeColors.extended,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: KinrelColors.darkBackground
                          .withValues(alpha: 0.9),
                      width: 1.2,
                    ),
                    boxShadow: KinrelFx.shadows([
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]),
                  ),
                  child: Center(
                    child: Text(
                      '+${widget.count}',
                      // Number at least 14px (readable at arm's length).
                      // Same font family as the node initials (Outfit),
                      // bold weight, dark-on-grey for contrast.
                      style: const TextStyle(
                        color: KinrelColors.darkBackground,
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
