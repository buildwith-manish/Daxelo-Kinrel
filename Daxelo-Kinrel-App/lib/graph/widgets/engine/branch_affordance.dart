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
  /// v102 (BUG-2 FIX) + v5.123 (Step 3): Builds positioned chips for
  /// each collapsed branch.
  ///
  /// Every [CollapsedBranch] renders a PERSISTENTLY VISIBLE chip at its
  /// attachment point on the canvas — a direct child of the graph Stack,
  /// never hidden inside a menu and never gated on the filter panel.
  /// The chip LEADS with "+{count}" (the number of hidden members) and
  /// appends a short label (the branch root's name, e.g. "Mother")
  /// when space permits (width-capped, single line, ellipsized).
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
  ) {
    if (collapseState.collapsedBranches.isEmpty) return const [];

    // v5.105: Track placed chip positions to avoid overlap.
    // If two chips would overlap, offset the second one vertically.
    final placedRects = <Rect>[];
    final chips = <Widget>[];

    for (final branch in collapseState.collapsedBranches) {
      final pos = layout.positions[branch.rootPersonId];
      if (pos == null) continue;

      // Position the chip slightly below and to the right of the root node.
      final chipLeft = pos.dx + 40;
      var chipTop =
          pos.dy + _FamilyGraphEngineViewState._kCircleCenterYOffset + 40;

      // v5.105: Collision avoidance — if this chip would overlap an
      // already-placed chip, push it down by 30px increments until it fits.
      const chipWidth = 200.0; // approximate
      const chipHeight = 32.0;  // approximate
      while (placedRects.any((r) => r.overlaps(
          Rect.fromLTWH(chipLeft, chipTop, chipWidth, chipHeight)))) {
        chipTop += 36; // stack vertically
      }
      placedRects.add(Rect.fromLTWH(chipLeft, chipTop, chipWidth, chipHeight));

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

      chips.add(Positioned(
        left: chipLeft,
        top: chipTop,
        child: Semantics(
          button: true,
          label:
              'Expand ${shortLabel.isEmpty ? 'collapsed' : shortLabel} branch: '
              '${branch.hiddenCount} hidden family members. '
              'Double-tap to expand. Long-press for branch details and '
              'the full names list.',
          child: GestureDetector(
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
                  // Gives sub-100ms visual feedback without needing a
                  // Material ancestor for CircularProgressIndicator.
                  Icon(
                    _optimisticLoadingChipRootId == branch.rootPersonId
                        ? Icons.hourglass_top
                        : Icons.unfold_more,
                    size: 14,
                    color: chipAccentColor,
                  ),
                  const SizedBox(width: 6),
                  // v5.123 (Step 3): Lead with "+{count}", then append the
                  // short label when space permits (single line,
                  // ellipsized). The generation depth stays available via
                  // the branch tooltip semantics below.
                  Flexible(
                    child: Text(
                      shortLabel.isEmpty
                          ? '+${branch.hiddenCount}'
                          : '+${branch.hiddenCount} · $shortLabel',
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
          ),
        ),
      ));
    }
    return chips;
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

    // Map the relationship key to a branch type for the RPC. Never
    // null: unrecognized keys resolve to the 'generic' BFS fallback.
    final branchType = FamilyGraphNotifier.branchTypeForRelationshipKey(
        branch.relationshipKey);
    // Fetch only this branch's nodes/edges from Supabase. For
    // unrecognized relationship keys this hits the 'generic' branch
    // type which does a BFS up to depth=2 hops regardless of label
    // (migration 20260831120000).
    await ref.read(familyGraphProvider(widget.familyId).notifier)
        .fetchBranchAndMerge(
      rootPersonId: branch.rootPersonId,
      branchType: branchType,
      depth: 2,
    );

    // v5.143: Clear the optimistic loading state — data has arrived.
    _optimisticLoadingChipRootId = null;

    // v5.123 (Step 3): Reveal the branch's members in the proximity
    // set FIRST (incremental — only this branch's hidden members plus
    // the root's own subtree context) so the layout provider gives
    // them positions and the expansion is actually VISIBLE.
    final flat = ref.read(familyGraphProvider(widget.familyId)).valueOrNull;
    if (flat != null) {
      ref.read(proximityGraphProvider.notifier).revealPersons(
            personIds: {
              branch.rootPersonId,
              ...branch.hiddenMemberIds,
            },
            allPersons: {
              for (final p in flat.persons) (p['id'] ?? '').toString(),
            },
          );
    }

    // Expand the branch in the collapse state — removes it from the
    // collapsed set and adds the root to expandedBranchRoots so it
    // won't be auto-collapsed again.
    // v5.142: If this is a manually-collapsed branch, use expandManualBranch
    // (removes from manuallyCollapsedRoots instead of expandedBranchRoots).
    final collapseState = ref.read(branchCollapseProvider);
    if (collapseState.manuallyCollapsedRoots.contains(branch.rootPersonId)) {
      ref.read(branchCollapseProvider.notifier)
          .expandManualBranch(branch.rootPersonId);
    } else {
      ref.read(branchCollapseProvider.notifier)
          .expandBranch(branch.rootPersonId);
    }

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
            // ── Summary: hidden count + generation depth ──────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                hasDepth
                    ? '${branch.hiddenCount} hidden members · '
                        '$depth generation${depth == 1 ? '' : 's'} deep'
                    : '${branch.hiddenCount} hidden members',
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
            // ── Actions ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.unfold_more_rounded, size: 18),
                label: const Text('Expand this branch'),
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
      // Find all persons that are descendants of rootPersonId (the branch
      // members). We use the relationships to find children recursively.
      final childrenMap = <String, List<String>>{};
      for (final r in flat.relationships) {
        final fromId = (r['fromPersonId'] ?? '').toString();
        final toId = (r['toPersonId'] ?? '').toString();
        final key = (r['relationshipKey'] ?? '').toString();
        // parent-type relationship: from is child, to is parent
        if (key == 'parent' || key == 'father' || key == 'mother' ||
            key == 'adoptive_parent' || key == 'step_parent') {
          childrenMap.putIfAbsent(toId, () => []).add(fromId);
        }
      }
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
                  // Collapse the branch — re-hides members + restores chip.
                  ref.read(branchCollapseProvider.notifier)
                      .collapseBranch(rootPersonId);
                  // Invalidate the graph provider so the layout recomputes.
                  ref.invalidate(familyGraphProvider(widget.familyId));
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

              final childrenOf = <String, Set<String>>{};
              for (final r in flat.relationships) {
                final fromId = (r['fromPersonId'] ?? '').toString();
                final toId = (r['toPersonId'] ?? '').toString();
                final key = (r['relationshipKey'] ?? '').toString();
                // parent-type: from is child, to is parent
                if (key == 'parent' || key == 'father' || key == 'mother' ||
                    key == 'adoptive_parent' || key == 'step_parent') {
                  childrenOf.putIfAbsent(toId, () => <String>{}).add(fromId);
                }
              }

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
              final collapseState = ref.read(branchCollapseProvider);
              if (collapseState.expandedBranchRoots.contains(rootPersonId)) {
                // Auto-expanded branch — just undo the expansion.
                ref.read(branchCollapseProvider.notifier)
                    .collapseBranch(rootPersonId);
              } else {
                // Manually collapse — works for ANY node with descendants.
                ref.read(branchCollapseProvider.notifier)
                    .manualCollapseBranch(
                      rootPersonId: rootPersonId,
                      childrenOf: childrenOf,
                      personNameOf: personNameOf,
                    );
              }

              // Invalidate the graph provider so the layout recomputes.
              ref.invalidate(familyGraphProvider(widget.familyId));
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

    // Build children map from relationships.
    final childrenMap = <String, List<String>>{};
    final relationships = flat.relationships as List;
    for (final r in relationships) {
      final fromId = (r['fromPersonId'] ?? '').toString();
      final toId = (r['toPersonId'] ?? '').toString();
      final key = (r['relationshipKey'] ?? '').toString();
      // parent-type: from is child, to is parent
      if (key == 'parent' || key == 'father' || key == 'mother' ||
          key == 'adoptive_parent' || key == 'step_parent') {
        childrenMap.putIfAbsent(toId, () => []).add(fromId);
      }
    }

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
