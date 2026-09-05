// lib/graph/interaction/branch_collapse_state.dart
//
// DAXELO KINREL — Intelligent Family Branch Collapsing (Phase 4)
//
// A PRESENTATION-ONLY model for collapsing distant family branches
// into compact affordances. This does NOT mutate canonical topology:
//   • No relationships are deleted
//   • No family data is rewritten
//   • No synthetic branch nodes are stored as real family members
//
// Collapse state is LOCAL presentation state, separate from the
// data-layer ExpandCollapseController. The canonical graph data
// (FlatGraphResult) is never modified — collapsed branches are
// simply filtered out of the VISIBLE set at render time.
//
// DEFAULT RULES (when Focus Mode is active):
//   Always show:
//   • focus person
//   • first-degree relatives
//   • active relationship path
//   • search matches
//   • selected person
//
//   Prefer showing:
//   • second-degree relatives where graph size allows
//
//   Collapse:
//   • distant large branches
//   • branches outside relevance radius
//   • large descendant subtrees not currently explored
//
//   Do NOT aggressively collapse small graphs (< 30 members).
//
// v5.105: Density-driven budget rule. When post-cull visible nodes
// exceed kNodeBudget (50), subtrees are collapsed largest-first until
// the budget is met. This is recursive: if a single branch is so
// large that collapsing it still leaves us over budget, the algorithm
// recurses into the branch's own children. Works at any scale (10 to
// 100,000+ members) with one unified rule.

import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// v5.105: Global on-screen node budget. If the number of visible
/// (post-cull) nodes exceeds this, subtrees are collapsed until the
/// budget is met. ~50 provides a clean, legible graph at any scale.
///
/// v5.123 (Step 2): The default ego-centric proximity view now uses
/// this same value as its HARD cap (kProximityHardNodeBudget in
/// proximity_graph_state.dart) — this constant itself is UNCHANGED and
/// remains the Show-All-path budget.
const int kNodeBudget = 50;

/// v5.159 (NESTED EXPANSION): Maximum nodes revealed by ONE branch-bubble
/// tap. When the immediate next level of a branch has more hidden members
/// than this, only the first [kMaxNodesPerExpansion] are revealed (chosen
/// by kinship-category priority, then deterministic ID order); the rest
/// stay hidden and are re-zoned into sub-bubbles on the next density pass.
const int kMaxNodesPerExpansion = 15;

/// v5.159 (TRAVERSAL SAFETY): Hard upper bound on the number of queue
/// pops any single graph traversal in this file may perform. Acts as a
/// fallback guard against pathological topologies (cycles that evade
/// the visited set, corrupted adjacency maps with duplicate entries) so
/// a bad dataset can degrade into a truncated result instead of a
/// freeze. 714-member graphs use ~714 pops; the cap is orders of
/// magnitude above that but far below anything that could stall a frame.
const int kMaxGraphTraversalSteps = 100000;

/// A collapsed branch presentation entry.
///
/// Represents one branch that has been visually collapsed into a
/// compact affordance (e.g. "Mother's extended family · 38").
///
/// This is PRESENTATION state — the underlying relationship data is
/// untouched. The [hiddenMemberIds] + [hiddenEdgeIds] are filtered
/// out of the visible set at render time, but remain in the canonical
/// FlatGraphResult.
@immutable
class CollapsedBranch {
  const CollapsedBranch({
    required this.id,
    required this.rootPersonId,
    required this.rootPersonName,
    required this.hiddenMemberIds,
    required this.hiddenEdgeIds,
    required this.visibleMemberCount,
    required this.hiddenGenerationDepth,
    required this.branchLabel,
    required this.relationshipKey,
    this.representativeName,
    this.subBranches = const [],
  });

  /// Unique ID for this collapse entry (typically
  /// '${rootPersonId}_branch').
  final String id;

  /// The person ID at the root of this branch (the person whose
  /// descendants are hidden).
  final String rootPersonId;

  /// Display name of the branch root person.
  final String rootPersonName;

  /// Set of person IDs hidden by this collapse.
  final Set<String> hiddenMemberIds;

  /// Set of edge IDs hidden by this collapse (edges where both
  /// endpoints are in [hiddenMemberIds] OR one endpoint is in
  /// [hiddenMemberIds] and the other is the root).
  final Set<String> hiddenEdgeIds;

  /// Number of hidden members (hiddenMemberIds.length).
  final int visibleMemberCount;

  /// How many generations deep the hidden branch goes.
  final int hiddenGenerationDepth;

  /// Human-readable label for the branch (e.g. "Mother's extended
  /// family", "Patel branch").
  final String branchLabel;

  /// The relationship key from the root to the first hidden
  /// descendant (e.g. "mother", "father", "spouse") — used for
  /// label generation.
  final String relationshipKey;

  /// v5.106: Nested sub-branches for recursive clustering at extreme
  /// scale (10k+). When a single collapsed subtree still exceeds
  /// kNodeBudget on its own, its children are recursively collapsed
  /// into sub-branches.
  final List<CollapsedBranch> subBranches;

  /// v5.159 (RICH BUBBLES): One representative display name drawn
  /// alongside the count (e.g. "Geeta Iyer +207") so the user knows
  /// whose branch they are expanding. Primary source: the branch ROOT
  /// person's name (always available — the root is a positioned, fetched
  /// person). Fallback: the first resolvable hidden-member name (used
  /// only when the root name is unknown, e.g. gateway nodes in rarely
  /// fetched components). Null when neither is known.
  final String? representativeName;

  /// v5.159 (RICH BUBBLES): Whether the hidden members of this branch
  /// include FURTHER sub-branches (nesting) versus a flat group of
  /// direct people with no deeper levels. Derived from
  /// [hiddenGenerationDepth]: depth ≥ 2 means at least one hidden
  /// member sits 2+ hops from the root THROUGH other hidden members —
  /// i.e. expanding this branch will reveal nodes that themselves carry
  /// branch bubbles. Depth == 1 means every hidden member is a direct
  /// neighbour of the root (a "dead end" group of N direct people).
  ///
  /// The chip layer renders a distinct glyph for each state so the
  /// user can tell at a glance: "this group has more levels inside"
  /// (tree icon) vs. "this group is a dead end with N direct people"
  /// (flat chevron, ⌵).
  bool get hasNestedDescendants => hiddenGenerationDepth >= 2;

  /// The total hidden count (= hiddenMemberIds.length).
  int get hiddenCount => hiddenMemberIds.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollapsedBranch && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'CollapsedBranch($id, root=$rootPersonId, hidden=$hiddenCount, '
      'label=$branchLabel)';
}

/// The state of the branch-collapse subsystem.
@immutable
class BranchCollapseState {
  const BranchCollapseState({
    this.collapsedBranches = const <CollapsedBranch>[],
    this.expandedBranchRoots = const <String>{},
    this.manuallyCollapsedRoots = const <String>{},
    this.revealedByBranchRoot = const <String, Set<String>>{},
    this.revision = 0,
  });

  /// All currently-collapsed branches.
  final List<CollapsedBranch> collapsedBranches;

  /// Branch roots that the user has explicitly expanded (should NOT
  /// be auto-collapsed again). Tracked per family.
  final Set<String> expandedBranchRoots;

  /// v5.142: Branch roots that the user has MANUALLY collapsed via the
  /// node long-press menu. These stay collapsed even if they contain
  /// protected nodes (first-degree relatives, search matches, etc.)
  /// that the auto-algorithm would never hide. Separated from
  /// auto-collapsed branches so the two systems don't interfere.
  final Set<String> manuallyCollapsedRoots;

  /// v5.159 (RE-COLLAPSE): Person IDs revealed by each branch-root
  /// expansion, keyed by the root whose bubble the user tapped. When a
  /// branch is re-collapsed (tapping an expanded branch again), the
  /// UNION of the root's entry plus the entries of any nested expanded
  /// roots inside it is concealed from the proximity set — hiding
  /// exactly the members the expansion revealed and (via the next
  /// density pass) restoring the branch bubble with its full count.
  ///
  /// Entries are removed when the root is collapsed or manually
  /// re-collapsed; ids that later became visible through other
  /// mechanisms (search jump, path focus) are harmless no-ops at
  /// conceal time.
  final Map<String, Set<String>> revealedByBranchRoot;

  /// Bumped whenever collapse state changes. Used by the painter's
  /// shouldRepaint.
  final int revision;

  static const BranchCollapseState empty = BranchCollapseState();

  /// v5.159 (RE-COLLAPSE): Branch roots that currently support the
  /// re-collapse affordance — expanded roots with at least one recorded
  /// revealed member still tracked. The chip layer renders a collapse
  /// chip ("−N") for these roots when they have no remaining hidden
  /// zone members (the bubble flips from "+N" expand mode to "−N"
  /// collapse mode).
  Map<String, Set<String>> get collapsibleBranchRoots =>
      <String, Set<String>>{
        for (final entry in revealedByBranchRoot.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value,
      };

  /// The set of ALL hidden member IDs across all collapsed branches.
  Set<String> get allHiddenMemberIds {
    final all = <String>{};
    for (final b in collapsedBranches) {
      all.addAll(b.hiddenMemberIds);
    }
    return all;
  }

  /// The set of ALL hidden edge IDs across all collapsed branches.
  Set<String> get allHiddenEdgeIds {
    final all = <String>{};
    for (final b in collapsedBranches) {
      all.addAll(b.hiddenEdgeIds);
    }
    return all;
  }

  /// True when [personId] is hidden by any collapsed branch.
  bool isHidden(String personId) {
    for (final b in collapsedBranches) {
      if (b.hiddenMemberIds.contains(personId)) return true;
    }
    return false;
  }

  /// True when [personId] is a branch root with a collapsed branch.
  bool isBranchRoot(String personId) {
    for (final b in collapsedBranches) {
      if (b.rootPersonId == personId) return true;
    }
    return false;
  }

  /// Finds the collapsed branch for [rootPersonId], or null.
  CollapsedBranch? branchForRoot(String rootPersonId) {
    for (final b in collapsedBranches) {
      if (b.rootPersonId == rootPersonId) return b;
    }
    return null;
  }

  BranchCollapseState copyWith({
    List<CollapsedBranch>? collapsedBranches,
    Set<String>? expandedBranchRoots,
    Set<String>? manuallyCollapsedRoots,
    Map<String, Set<String>>? revealedByBranchRoot,
    int? revision,
  }) {
    return BranchCollapseState(
      collapsedBranches: collapsedBranches ?? this.collapsedBranches,
      expandedBranchRoots: expandedBranchRoots ?? this.expandedBranchRoots,
      manuallyCollapsedRoots: manuallyCollapsedRoots ?? this.manuallyCollapsedRoots,
      revealedByBranchRoot:
          revealedByBranchRoot ?? this.revealedByBranchRoot,
      revision: revision ?? this.revision,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BranchCollapseState && other.revision == revision;

  @override
  int get hashCode => revision.hashCode;
}

/// StateNotifier that owns the branch-collapse presentation state.
///
/// The collapse computation is driven by the engine view, which calls
/// [computeCollapse] with the current graph data + focus state. The
/// notifier caches the result and exposes it via [state].
///
/// Expansion state is tracked per family via [expandedBranchRoots] —
/// once a user expands a branch, it stays expanded until they
/// explicitly collapse it again.
class BranchCollapseNotifier extends StateNotifier<BranchCollapseState> {
  BranchCollapseNotifier() : super(BranchCollapseState.empty);

  // ═══════════════════════════════════════════════════════════════════
  // v5.146: SHARED childrenOf BUILDER — handles BOTH relationship directions
  // ═══════════════════════════════════════════════════════════════════

  /// v5.146: Relationship keys where the SECOND person (toPersonId) is
  /// the parent and the FIRST person (fromPersonId) is the child.
  /// e.g. "A → B, key=father" means "B is A's father" → A is child of B.
  static const Set<String> _parentTypeKeys = {
    'parent', 'father', 'mother',
    'adoptive_parent', 'adoptive_father', 'adoptive_mother',
    'adopted_father', 'adopted_mother',
    'step_parent', 'step_father', 'step_mother',
    'stepfather', 'stepmother',
    'foster_father', 'foster_mother',
    'biological_father', 'biological_mother',
  };

  /// v5.146: Relationship keys where the FIRST person (fromPersonId) is
  /// the parent and the SECOND person (toPersonId) is the child.
  /// e.g. "A → B, key=son" means "B is A's son" → B is child of A.
  static const Set<String> _childTypeKeys = {
    'child', 'son', 'daughter',
    'adoptive_son', 'adoptive_daughter',
    'adopted_son', 'adopted_daughter',
    'step_son', 'step_daughter',
    'stepson', 'stepdaughter',
    'foster_son', 'foster_daughter',
    'biological_son', 'biological_daughter',
  };

  /// v5.146: Builds a parent→children adjacency map from a list of
  /// relationship maps (as returned by FlatGraphResult.relationships).
  ///
  /// Handles BOTH relationship directions:
  /// - parent-type keys (father, mother, parent, adoptive_parent,
  ///   step_parent, etc.): toPersonId is the parent, fromPersonId is
  ///   the child.
  /// - child-type keys (son, daughter, child, adoptive_son, step_son,
  ///   etc.): fromPersonId is the parent, toPersonId is the child.
  ///
  /// This replaces 5 separate duplicated lookups that all missed the
  /// child-type direction, causing "Collapse this branch" to silently
  /// fail for nodes whose descendants were entered using son/daughter
  /// labels (e.g. Sunita Sharma).
  ///
  /// [relationships] is a List<Map<String, dynamic>> where each map has
  /// 'fromPersonId', 'toPersonId', and 'labelAtoB' (or 'relationshipKey'
  /// as fallback) fields.
  ///
  /// v5.147: Uses labelAtoB as the PRIMARY field (not relationshipKey)
  /// because labelAtoB always describes the relationship in a fixed,
  /// consistent direction (from A to B), while relationshipKey can flip
  /// depending on viewer perspective. This prevents the collapse feature
  /// from mistakenly treating the central person (Manish) as a child of
  /// the node being collapsed, which would hide his connecting line.
  ///
  /// Returns a Map<String, Set<String>> where the key is a parent's
  /// person ID and the value is the set of their children's person IDs.
  static Map<String, Set<String>> buildChildrenOf(
    List<dynamic> relationships,
  ) {
    final childrenOf = <String, Set<String>>{};
    for (final r in relationships) {
      final fromId = (r['fromPersonId'] ?? '').toString();
      final toId = (r['toPersonId'] ?? '').toString();
      if (fromId.isEmpty || toId.isEmpty) continue;
      // v5.147: labelAtoB is PRIMARY — it's always in a fixed direction
      // (A sees B as X). relationshipKey is the fallback for older
      // records that may not have labelAtoB populated.
      final key = ((r['labelAtoB'] ?? r['relationshipKey'] ?? '') as String)
          .toLowerCase()
          .trim();

      if (_parentTypeKeys.contains(key)) {
        // toPerson is the parent, fromPerson is the child
        childrenOf.putIfAbsent(toId, () => <String>{}).add(fromId);
      } else if (_childTypeKeys.contains(key)) {
        // fromPerson is the parent, toPerson is the child
        childrenOf.putIfAbsent(fromId, () => <String>{}).add(toId);
      }
    }
    return childrenOf;
  }

  /// v5.157: Builds a FULL undirected adjacency map from ALL relationship
  /// types (parent, child, spouse, sibling, etc.). Used by the
  /// v5.158 zone-assignment collapse (computeDensityCollapse +
  /// _computeZones) to traverse the ENTIRE graph — not just
  /// parent-child edges — so branch bubbles cover ALL hidden members
  /// (including spouses, siblings, and their descendants).
  ///
  /// This is separate from [buildChildrenOf] because the layout engine
  /// needs parent-child-only hierarchy for ring placement, while the
  /// bubble coverage system needs the full graph to ensure every hidden
  /// member is reachable and represented by a bubble.
  static Map<String, Set<String>> buildFullAdjacency(
    List<dynamic> relationships,
  ) {
    final adjacency = <String, Set<String>>{};
    for (final r in relationships) {
      final fromId = (r['fromPersonId'] ?? '').toString();
      final toId = (r['toPersonId'] ?? '').toString();
      if (fromId.isEmpty || toId.isEmpty) continue;
      adjacency.putIfAbsent(fromId, () => <String>{}).add(toId);
      adjacency.putIfAbsent(toId, () => <String>{}).add(fromId);
    }
    return adjacency;
  }

  /// v5.123 (Step 5): Optional persistence hook — invoked whenever a
  /// branch's expansion state changes via [expandBranch] (true) or
  /// [collapseBranch] (false). The engine view wires this to
  /// LayoutOverridesService.saveBranchExpansionState so the choice is
  /// stored keyed by (userId, familyId, branchRootId) and re-applied
  /// on the next graph load via [seedExpandedBranchRoots].
  void Function(String rootPersonId, bool expanded)? onExpansionChanged;

  /// v5.123 (Step 5): Applies PERSISTED expansion state on top of the
  /// default density-collapse computation — a branch the user
  /// previously expanded loads ALREADY-EXPANDED (its root joins
  /// [BranchCollapseState.expandedBranchRoots], so the budget rule
  /// skips it), even when the default rule would have collapsed it.
  ///
  /// Idempotent: re-seeding the same roots is a no-op (set union).
  /// Called once per family load with the roots persisted as
  /// expanded=true.
  void seedExpandedBranchRoots(Set<String> roots) {
    if (roots.isEmpty) return;
    final current = state.expandedBranchRoots;
    var added = false;
    final merged = Set<String>.from(current);
    for (final root in roots) {
      if (merged.add(root)) added = true;
    }
    if (!added) return; // Already seeded — no state change.
    state = BranchCollapseState(
      collapsedBranches: state.collapsedBranches,
      expandedBranchRoots: merged,
      manuallyCollapsedRoots: state.manuallyCollapsedRoots,
      revision: state.revision + 1,
    );
  }

  /// Compute the collapse state from the current graph data.
  ///
  /// [allPersons] — all person IDs in the family.
  /// [allEdges] — all edges as (fromId, toId, edgeId, relationshipKey) tuples.
  /// [focusPersonId] — the currently focused person (null if no focus).
  /// [firstDegreeIds] — first-degree neighbours of the focus person.
  /// [secondDegreeIds] — second-degree neighbours of the focus person.
  /// [pathNodeIds] — person IDs on the active relationship path.
  /// [searchMatchIds] — person IDs matching the current search.
  /// [selectedPersonId] — the currently selected person.
  /// [familyMemberCount] — the RENDERED node count (for the budget bypass).
  ///
  /// Rules:
  ///   • Rendered sets that fit the global budget (≤ [kNodeBudget])
  ///     → no collapse (v5.123: was `< 30`, which let the 30–50 range
  ///     hide proximity-positioned nodes and oscillate against
  ///     computeDensityCollapse's clearing pass).
  ///   • Focus person + first-degree + path + search + selected → always visible.
  ///   • Second-degree → visible where graph size allows.
  ///   • Distant branches (3+ hops from focus) → collapsed if they have ≥ 5 members.
  ///   • User-expanded branches stay expanded.
  void computeCollapse({
    required Set<String> allPersons,
    required List<({String fromId, String toId, String edgeId, String relationshipKey})> allEdges,
    String? focusPersonId,
    required Set<String> firstDegreeIds,
    required Set<String> secondDegreeIds,
    Set<String>? pathNodeIds,
    Set<String>? searchMatchIds,
    String? selectedPersonId,
    required int familyMemberCount,
    /// v102 (BUG-2 FIX): Optional callback to resolve a person ID to
    /// their display name. When provided, the CollapsedBranch's
    /// rootPersonName and branchLabel are populated with the real name
    /// (e.g. "Mother's branch · 38"). When null, they fall back to a
    /// generic label ("Branch · 38") — the old behavior.
    String Function(String personId)? personNameOf,
  }) {
    // Budget bypass — don't collapse graphs whose RENDERED set already
    // fits the global legibility budget. v5.123: aligned with
    // computeDensityCollapse's `<= kNodeBudget` invariant so the two
    // mechanisms can never fight (the old `< 30` left the 30–50 range
    // engaging this pass while the density pass cleared it — an
    // infinite rebuild oscillation that hid proximity nodes with
    // positions, the "edges ending at empty points" bug).
    if (familyMemberCount <= kNodeBudget) {
      // v5.148: Preserve manually-collapsed branches — they must survive
      // the small-graph bypass because the user explicitly collapsed them.
      final manualBranches = state.collapsedBranches
          .where((b) => state.manuallyCollapsedRoots.contains(b.rootPersonId))
          .toList();
      if (state.collapsedBranches.length != manualBranches.length) {
        state = BranchCollapseState(
          collapsedBranches: manualBranches,
          expandedBranchRoots: state.expandedBranchRoots,
          manuallyCollapsedRoots: state.manuallyCollapsedRoots,
          revealedByBranchRoot: state.revealedByBranchRoot,
          revision: state.revision + 1,
        );
      }
      return;
    }

    // The "always visible" set — these persons must NEVER be collapsed.
    final alwaysVisible = <String>{
      if (focusPersonId != null) focusPersonId,
      ...firstDegreeIds,
      ...secondDegreeIds,
      if (pathNodeIds != null) ...pathNodeIds,
      if (searchMatchIds != null) ...searchMatchIds,
      if (selectedPersonId != null) selectedPersonId,
    };

    // Build adjacency for branch detection.
    final childrenOf = <String, Set<String>>{};
    final edgeIdByPair = <String, String>{};
    for (final e in allEdges) {
      childrenOf.putIfAbsent(e.fromId, () => <String>{}).add(e.toId);
      final pair = [e.fromId, e.toId]..sort();
      edgeIdByPair['${pair[0]}|${pair[1]}'] = e.edgeId;
    }

    // Find candidate branch roots: persons who have descendants that
    // are NOT in the always-visible set and form a subtree of ≥ 5
    // members.
    // v98 (Phase 4): Fix candidate-root self-contradiction.
    // The previous code added firstDegreeIds to BOTH alwaysVisible
    // AND candidateRoots, then skipped any root already in
    // alwaysVisible — so a focused person's immediate neighbours
    // could NEVER become collapse candidates.
    //
    // Fix: alwaysVisible protects the NODE ITSELF from being hidden
    // as a descendant. But a first-degree neighbour CAN be a branch
    // ROOT — it stays visible, but its OWN descendants can be
    // collapsed. The skip at line ~292 should only skip roots that
    // are the FOCUS person itself (not all alwaysVisible members).
    final candidateRoots = <String>{};
    if (focusPersonId != null) {
      // First-degree relatives are candidate roots for their own
      // extended families. They stay visible (as alwaysVisible),
      // but their descendants can be collapsed.
      candidateRoots.addAll(firstDegreeIds);
    } else {
      candidateRoots.addAll(allPersons);
    }

    final newBranches = <CollapsedBranch>[];
    final alreadyHidden = <String>{};

    for (final rootId in candidateRoots) {
      // v98: Only skip if this is the FOCUS person itself — not
      // if it's merely in alwaysVisible. A first-degree neighbour
      // can be a branch root while still being always-visible.
      if (rootId == focusPersonId) continue;
      // Skip if the user has explicitly expanded this branch.
      if (state.expandedBranchRoots.contains(rootId)) continue;
      // v5.142: Skip if manually collapsed — the auto-algorithm must
      // NOT re-collapse or re-expand a manually-collapsed branch.
      if (state.manuallyCollapsedRoots.contains(rootId)) continue;
      // Skip if already part of another collapsed branch.
      if (alreadyHidden.contains(rootId)) continue;

      // Compute the descendant subtree of rootId, excluding
      // always-visible persons.
      final descendants = _descendantsExcluding(rootId, childrenOf, alwaysVisible);
      if (descendants.length < 5) continue; // too small to collapse

      // Compute hidden edges (edges where both endpoints are in the
      // hidden set, or one endpoint is a descendant and the other is
      // the root).
      final hiddenMemberIds = descendants;
      final hiddenEdgeIds = <String>{};
      for (final e in allEdges) {
        if (hiddenMemberIds.contains(e.fromId) &&
            (hiddenMemberIds.contains(e.toId) || e.toId == rootId)) {
          hiddenEdgeIds.add(e.edgeId);
        } else if (hiddenMemberIds.contains(e.toId) &&
            (hiddenMemberIds.contains(e.fromId) || e.fromId == rootId)) {
          hiddenEdgeIds.add(e.edgeId);
        }
      }

      // Compute generation depth.
      final depth = _maxDepth(rootId, childrenOf, hiddenMemberIds);

      // Generate a branch label.
      // v102 (BUG-2 FIX): Use the personNameOf callback to resolve the
      // real display name. The old code unconditionally returned ''
      // with a comment saying "the engine view will override" — but
      // nothing ever did, so rootPersonName was always empty and the
      // label was always "Branch · N" instead of "Mother's branch · N".
      final rootName = personNameOf?.call(rootId) ?? _personName(rootId, allPersons);
      final label = _generateBranchLabel(rootName, descendants.length);

      newBranches.add(CollapsedBranch(
        id: '${rootId}_branch',
        rootPersonId: rootId,
        rootPersonName: rootName,
        hiddenMemberIds: hiddenMemberIds,
        hiddenEdgeIds: hiddenEdgeIds,
        visibleMemberCount: 1, // just the root
        hiddenGenerationDepth: depth,
        branchLabel: label,
        relationshipKey: '', // could be populated from the edge
      ));

      alreadyHidden.addAll(hiddenMemberIds);
    }

    // v99: IDEMPOTENT state update — only bump revision if the
    // collapsed branches actually changed. Prevents a rebuild loop
    // when computeCollapse is called from the build path (same
    // inputs → same output → no revision bump → no rebuild).
    if (_branchesEqual(newBranches, state.collapsedBranches)) {
      return; // No change → no mutation → no rebuild cycle.
    }

    // v5.148: Preserve manually-collapsed branches.
    final manualBranchesToKeep = state.collapsedBranches
        .where((b) => state.manuallyCollapsedRoots.contains(b.rootPersonId) &&
            !newBranches.any((nb) => nb.rootPersonId == b.rootPersonId))
        .toList();

    state = BranchCollapseState(
      collapsedBranches: [...newBranches, ...manualBranchesToKeep],
      expandedBranchRoots: state.expandedBranchRoots,
      manuallyCollapsedRoots: state.manuallyCollapsedRoots,
      revision: state.revision + 1,
    );
  }

  /// Lightweight branch-list equality check.
  bool _branchesEqual(List<CollapsedBranch> a, List<CollapsedBranch> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].hiddenCount != b[i].hiddenCount) {
        return false;
      }
    }
    return true;
  }

  /// Expand a branch — removes it from the collapsed set + adds the
  /// root to [expandedBranchRoots] so it won't be auto-collapsed again.
  ///
  /// v5.159 (RE-COLLAPSE): [revealedIds] records WHICH members this
  /// expansion actually revealed (the immediate next level, capped at
  /// [kMaxNodesPerExpansion]). The set is merged into
  /// [BranchCollapseState.revealedByBranchRoot] so a later re-collapse
  /// (tap on the expanded branch) conceals exactly these members —
  /// nested expansions (roots inside this set) are concealed too via
  /// [collapseBranch]'s transitive union.
  void expandBranch(String rootPersonId, {Set<String>? revealedIds}) {
    final newBranches = state.collapsedBranches
        .where((b) => b.rootPersonId != rootPersonId)
        .toList();
    final newExpanded = Set<String>.from(state.expandedBranchRoots)
      ..add(rootPersonId);
    // v5.159: merge the revealed members under this root.
    final newRevealed = Map<String, Set<String>>.from(state.revealedByBranchRoot);
    if (revealedIds != null && revealedIds.isNotEmpty) {
      final merged = Set<String>.from(newRevealed[rootPersonId] ?? const <String>{})
        ..addAll(revealedIds);
      newRevealed[rootPersonId] = merged;
    }
    state = BranchCollapseState(
      collapsedBranches: newBranches,
      expandedBranchRoots: newExpanded,
      manuallyCollapsedRoots: state.manuallyCollapsedRoots,
      revealedByBranchRoot: newRevealed,
      revision: state.revision + 1,
    );
    // v5.123 (Step 5): persist the user's expansion choice.
    onExpansionChanged?.call(rootPersonId, true);
  }

  /// Collapse a branch — re-collapses the subtree under [rootPersonId].
  /// Removes the root from [expandedBranchRoots].
  ///
  /// v5.159 (RE-COLLAPSE): returns the set of person IDs that should be
  /// CONCEALED from the proximity visible set — the transitive union of
  /// this root's recorded revealed members plus the recorded revealed
  /// members of any nested expanded roots inside it. Callers pass this
  /// to ProximityGraphNotifier.concealPersons; the next density pass
  /// then re-zones the concealed members under the root, restoring the
  /// "+N" bubble with the full hidden count.
  ///
  /// (Also removes nested roots from [expandedBranchRoots] and their
  /// persisted-expansion entries so a subsequent reload does not
  /// re-reveal them.)
  Set<String> collapseBranch(String rootPersonId) {
    final newExpanded = Set<String>.from(state.expandedBranchRoots)
      ..remove(rootPersonId);
    final newRevealed = Map<String, Set<String>>.from(state.revealedByBranchRoot);

    // Transitive closure: collect this root's revealed set plus the
    // revealed sets of every nested expanded root inside it (one pass
    // per nesting level — expansions are level-by-level, but the
    // closure loop handles arbitrary depth defensively; it terminates
    // because each iteration either grows the frontier or stops).
    final concealSet = Set<String>.from(newRevealed.remove(rootPersonId) ?? const <String>{});
    var frontier = Set<String>.from(concealSet);
    var guard = 0;
    while (frontier.isNotEmpty && guard++ < kMaxGraphTraversalSteps) {
      final nextFrontier = <String>{};
      for (final nestedRoot in newRevealed.keys.toList()) {
        if (frontier.contains(nestedRoot)) {
          nextFrontier.addAll(newRevealed.remove(nestedRoot) ?? const <String>{});
          newExpanded.remove(nestedRoot);
          // v5.159: persist the nested re-collapse so a reload does not
          // re-reveal the nested branch.
          onExpansionChanged?.call(nestedRoot, false);
        }
      }
      // Only ids NOT already in the conceal set can extend the closure.
      nextFrontier.removeAll(concealSet);
      concealSet.addAll(nextFrontier);
      frontier = nextFrontier;
    }

    state = state.copyWith(
      expandedBranchRoots: newExpanded,
      manuallyCollapsedRoots: state.manuallyCollapsedRoots,
      revealedByBranchRoot: newRevealed,
      revision: state.revision + 1,
    );
    // v5.123 (Step 5): persist the user's re-collapse choice.
    onExpansionChanged?.call(rootPersonId, false);
    return concealSet;
  }

  /// v5.142: Manually collapse ANY node's descendants on demand.
  ///
  /// Unlike [collapseBranch] (which only undoes a previous auto-expand),
  /// this method works for ANY node that currently has visible descendants
  /// — including nodes that were never auto-collapsed (protected
  /// first-degree relatives, always-visible nodes, etc.).
  ///
  /// The manually-collapsed root is added to [manuallyCollapsedRoots],
  /// which is SEPARATE from the auto-collapse system. The auto-algorithm
  /// (computeCollapse/computeDensityCollapse) will NOT re-expand a
  /// manually-collapsed branch even if it contains protected nodes.
  ///
  /// [childrenOf] is the parent→children adjacency map (same one used by
  /// computeCollapse/computeDensityCollapse).
  /// [allEdges] is the full edge list (for computing hidden edges).
  /// [personNameOf] resolves a person ID to their display name.
  /// [protectedIds] are persons that should stay visible even inside a
  /// manually-collapsed subtree (the root itself is always visible).
  void manualCollapseBranch({
    required String rootPersonId,
    required Map<String, Set<String>> childrenOf,
    List<({String fromId, String toId, String edgeId, String relationshipKey})>? allEdges,
    required String Function(String personId) personNameOf,
    Set<String> protectedIds = const {},
  }) {
    // Compute the descendant subtree (same BFS as computeCollapse).
    final descendants = _descendantsExcluding(rootPersonId, childrenOf, {rootPersonId, ...protectedIds});
    if (descendants.isEmpty) return; // Nothing to collapse.

    // v5.142: Recursive collapse — remove any nested expanded branch
    // roots that are inside this subtree. This prevents orphaned inner
    // chips from being left exposed after the outer branch collapses.
    final nestedExpandedRoots = state.expandedBranchRoots
        .where((id) => descendants.contains(id))
        .toSet();
    final newExpanded = Set<String>.from(state.expandedBranchRoots)
      ..removeAll(nestedExpandedRoots);

    // Also remove any existing collapsed branches whose root is inside
    // this subtree OR whose root IS the same rootPersonId (prevents
    // duplicate chips — one '_branch' auto + one '_manual_branch').
    // v5.151: The old code only checked b.rootPersonId != rootPersonId,
    // which kept existing auto-branches with the same root, creating a
    // stray duplicate chip alongside the new manual chip.
    final newCollapsedBranches = state.collapsedBranches
        .where((b) => !descendants.contains(b.rootPersonId) && b.rootPersonId != rootPersonId)
        .toList();

    // Compute hidden edges (edges where both endpoints are in the
    // hidden set, or one endpoint is a descendant and the other is
    // the root).
    final hiddenEdgeIds = <String>{};
    if (allEdges != null) {
      for (final e in allEdges) {
        if (descendants.contains(e.fromId) &&
            (descendants.contains(e.toId) || e.toId == rootPersonId)) {
          hiddenEdgeIds.add(e.edgeId);
        } else if (descendants.contains(e.toId) &&
            (descendants.contains(e.fromId) || e.fromId == rootPersonId)) {
          hiddenEdgeIds.add(e.edgeId);
        }
      }
    }

    final rootName = personNameOf(rootPersonId);
    final depth = _maxDepth(rootPersonId, childrenOf, descendants);
    final label = _generateBranchLabel(rootName, descendants.length);

    // Create the manual collapse branch.
    final manualBranch = CollapsedBranch(
      id: '${rootPersonId}_manual_branch',
      rootPersonId: rootPersonId,
      rootPersonName: rootName,
      hiddenMemberIds: descendants,
      hiddenEdgeIds: hiddenEdgeIds,
      visibleMemberCount: 1,
      hiddenGenerationDepth: depth,
      branchLabel: label,
      relationshipKey: '',
    );

    // Add to manuallyCollapsedRoots + collapsedBranches.
    final newManual = Set<String>.from(state.manuallyCollapsedRoots)
      ..add(rootPersonId);

    // v5.159: drop recorded revealed-sets for every root inside the
    // manually-collapsed subtree (their members are re-hidden by the
    // manual branch, so the entries would be stale).
    final cleanedRevealed = <String, Set<String>>{
      for (final e in state.revealedByBranchRoot.entries)
        if (!descendants.contains(e.key) && e.key != rootPersonId)
          e.key: e.value,
    };

    state = BranchCollapseState(
      collapsedBranches: [...newCollapsedBranches, manualBranch],
      expandedBranchRoots: newExpanded,
      manuallyCollapsedRoots: newManual,
      revealedByBranchRoot: cleanedRevealed,
      revision: state.revision + 1,
    );
  }

  /// v5.142: Expand a manually-collapsed branch. Removes the root from
  /// [manuallyCollapsedRoots] and removes the manual CollapsedBranch.
  /// The descendants become visible again on the next render.
  void expandManualBranch(String rootPersonId) {
    final newManual = Set<String>.from(state.manuallyCollapsedRoots)
      ..remove(rootPersonId);
    final newBranches = state.collapsedBranches
        .where((b) => b.rootPersonId != rootPersonId || b.id != '${rootPersonId}_manual_branch')
        .toList();
    state = state.copyWith(
      collapsedBranches: newBranches,
      manuallyCollapsedRoots: newManual,
      revision: state.revision + 1,
    );
  }

  /// v5.142: Check if a node has any visible descendants on the canvas.
  /// Used to decide whether to show "Collapse this branch" in the
  /// long-press menu.
  ///
  /// v5.159 (CYCLE SAFETY): rewritten as an ITERATIVE BFS with a visited
  /// set + [kMaxGraphTraversalSteps] guard. The old recursive version
  /// had NO visited set — over an undirected adjacency map (the map
  /// buildFullAdjacency produces) any two adjacent nodes walked each
  /// other forever: an A↔B cycle meant infinite recursion and a stack
  /// overflow; a long descendant chain risked the same.
  bool hasVisibleDescendants(
    String personId,
    Map<String, Set<String>> childrenOf,
    Set<String> visibleIds,
  ) {
    final visited = <String>{personId};
    final queue = <String>[personId];
    var steps = 0;
    while (queue.isNotEmpty) {
      if (steps++ > kMaxGraphTraversalSteps) return false; // safety cap
      final current = queue.removeLast();
      final children = childrenOf[current];
      if (children == null || children.isEmpty) continue;
      for (final child in children) {
        if (visibleIds.contains(child)) return true;
        if (visited.add(child)) {
          queue.add(child);
        }
      }
    }
    return false;
  }

  /// Clear all collapse state — called when switching families.
  void clearAll() {
    if (state == BranchCollapseState.empty) return;
    state = BranchCollapseState.empty;
  }

  // ═══════════════════════════════════════════════════════════════════
  // v5.105: DENSITY-DRIVEN BUDGET COLLAPSE
  // ═══════════════════════════════════════════════════════════════════

  /// v5.158 (ZONE-ASSIGNMENT REWRITE): Branch bubbles for ALL hidden
  /// members with progressive expansion.
  ///
  /// Semantics (the user-facing contract):
  ///   • [visibleNodeIds] — every node the layout gave a position
  ///     (the ~50-node proximity set + any revealed branch members +
  ///     gateway nodes for disconnected components).
  ///   • "Hidden members" = every node in the full adjacency that is
  ///     NOT in [visibleNodeIds]. Bubbles NEVER hide a positioned node.
  ///   • Each hidden member is assigned to exactly ONE bubble — the
  ///     visible node closest to it (multi-source BFS, see
  ///     [_computeZones]). Sum of all bubble counts == hidden count.
  ///   • Tapping a bubble reveals members near its root; the next
  ///     recomputation re-zones the remaining hidden members onto the
  ///     NEW frontier — new bubbles appear inside the expanded branch.
  ///     Repeating eventually makes every member visible.
  ///
  /// Why [expandedBranchRoots] is NO LONGER skipped as a root: with
  /// zone semantics, an expanded root whose zone still has members
  /// MUST keep its bubble (with the smaller remaining count), or those
  /// members would become unreachable — the exact "missing branch
  /// bubbles" bug this rewrite fixes. The old skip made sense when
  /// expanding meant "show this subtree in full"; it is actively wrong
  /// when expanding is a progressive, multi-step fetch.
  ///
  /// v5.123 (CONVERGENCE): [visibleNodeIds] must be the FULL rendered
  /// candidate set (positions ∩ allow-list), NOT the post-hiding
  /// count. The zone computation is a deterministic fixed point — the
  /// same inputs produce the same branches, so the idempotency check
  /// (`_branchesEqual`) no-ops and the pipeline converges.
  ///
  /// Parameters:
  /// [visibleNodeIds] — ALL rendered candidate nodes (pre-collapse).
  /// [childrenOf] — FULL undirected adjacency over every family edge
  ///   (see [buildFullAdjacency]). Despite the historical name, this
  ///   is a plain neighbor map, not a parent→children map.
  /// [personNameOf] — resolves personId → display name for labels.
  /// [allEdges] — all edges (for computing hidden edge IDs).
  /// [protectedIds] — kept for API compatibility. Zones never hide
  ///   positioned nodes, so focus/search/path protection of VISIBLE
  ///   nodes is inherent. Members that are protected but not yet
  ///   fetched/positioned still belong to a zone so they stay
  ///   reachable; the search-jump reveal path makes them visible via
  ///   its own mechanism.
  void computeDensityCollapse({
    required Set<String> visibleNodeIds,
    required Map<String, Set<String>> childrenOf,
    required String Function(String) personNameOf,
    required List<({String fromId, String toId, String edgeId, String relationshipKey})> allEdges,
    /// v5.106: Map of personId → kinship category string (e.g. 'parent',
    /// 'child', 'sibling'). Used to compute the dominant category for
    /// each collapsed branch's chip color. Pass the same map that
    /// node_builders uses for node ring colors.
    Map<String, String>? categoryOf,
    Set<String>? protectedIds,
  }) {
    // ── Step 1: the hidden set — nodes in the full adjacency that are
    // not positioned/visible. Bubbles represent exactly these members.
    // NOTE: nodes appear in the adjacency as BOTH keys and set values
    // (leaf members with no outgoing edges are values-only) — collect
    // from both sides.
    final allNodes = <String>{
      for (final entry in childrenOf.entries) ...{
        entry.key,
        ...entry.value,
      },
    };
    final hidden = allNodes.difference(visibleNodeIds);

    if (hidden.isEmpty) {
      // Family fully visible — clear auto branches (manual ones stay).
      final manualBranches = state.collapsedBranches
          .where((b) => state.manuallyCollapsedRoots.contains(b.rootPersonId))
          .toList();
      if (state.collapsedBranches.length != manualBranches.length) {
        state = BranchCollapseState(
          collapsedBranches: manualBranches,
          expandedBranchRoots: state.expandedBranchRoots,
          manuallyCollapsedRoots: state.manuallyCollapsedRoots,
          revealedByBranchRoot: state.revealedByBranchRoot,
          revision: state.revision + 1,
        );
      }
      return;
    }

    // ── Step 2: partition the hidden set into zones via multi-source
    // BFS from every visible node. Every hidden member reachable from
    // the visible set lands in exactly one zone.
    final zones = _computeZones(visibleNodeIds, childrenOf);
    if (zones.isEmpty) {
      // No hidden member is reachable from any visible node. This can
      // happen transiently (e.g. the allEdges list is stale). Clear
      // auto branches so we don't keep stale chips around.
      final manualBranches = state.collapsedBranches
          .where((b) => state.manuallyCollapsedRoots.contains(b.rootPersonId))
          .toList();
      if (state.collapsedBranches.length != manualBranches.length) {
        state = BranchCollapseState(
          collapsedBranches: manualBranches,
          expandedBranchRoots: state.expandedBranchRoots,
          manuallyCollapsedRoots: state.manuallyCollapsedRoots,
          revealedByBranchRoot: state.revealedByBranchRoot,
          revision: state.revision + 1,
        );
      }
      return;
    }

    // ── Step 3: build one CollapsedBranch per non-empty zone.
    // Sort zones by size (largest first) so the branch list — and the
    // chip placement order — is stable and deterministic.
    final zoneRoots = zones.keys.toList()
      ..sort((a, b) {
        final bySize = zones[b]!.length.compareTo(zones[a]!.length);
        if (bySize != 0) return bySize;
        return a.compareTo(b); // deterministic tie-break
      });

    final newBranches = <CollapsedBranch>[];
    for (final rootId in zoneRoots) {
      final members = zones[rootId]!;
      if (members.isEmpty) continue;
      // v5.142: a manually-collapsed root keeps its MANUAL branch —
      // the auto zone branch for the same root is skipped to avoid a
      // duplicate chip (the manual branch covers that root's subtree).
      if (state.manuallyCollapsedRoots.contains(rootId)) continue;

      // Hidden edges: ANY edge that touches a hidden zone member —
      // including edges to the zone root AND edges to visible nodes
      // that are not the root (prevents "edges ending at empty
      // points": a hidden endpoint must never have a rendered edge).
      // Edges between two hidden members of different zones are added
      // to both branches; the state-level union dedupes.
      final hiddenEdgeIds = <String>{};
      for (final e in allEdges) {
        if (members.contains(e.fromId) || members.contains(e.toId)) {
          hiddenEdgeIds.add(e.edgeId);
        }
      }

      final rootName = personNameOf(rootId);
      final label = _generateBranchLabel(rootName, members.length);

      // v5.106: dominant kinship category among zone members — used
      // for the chip's accent color (falls back to 'parent').
      final dominantKey = _dominantCategoryKey(members, categoryOf);

      newBranches.add(CollapsedBranch(
        id: '${rootId}_branch',
        rootPersonId: rootId,
        rootPersonName: rootName,
        hiddenMemberIds: Set.unmodifiable(members),
        hiddenEdgeIds: Set.unmodifiable(hiddenEdgeIds),
        visibleMemberCount: 1,
        hiddenGenerationDepth: _maxDepth(rootId, childrenOf, members),
        branchLabel: label,
        relationshipKey: dominantKey,
        // v5.159 (RICH BUBBLES): representative name — the root's own
        // name when known, else the first resolvable hidden-member
        // name (sorted for determinism), else null. The chip renders
        // "<representative> +<count>".
        representativeName: _representativeNameFor(rootId, rootName, members, personNameOf),
        subBranches: const [],
      ));
    }

    // ── Step 4: idempotent update (no revision bump on identical
    // inputs — prevents rebuild loops from the build-path caller).
    if (_branchesEqual(newBranches, state.collapsedBranches)) {
      return;
    }

    // v5.148: Preserve manually-collapsed branches alongside the
    // auto-collapsed newBranches. Without this, the density collapse
    // would wipe out manually-collapsed branches on every rebuild.
    final manualBranchesToKeep = state.collapsedBranches
        .where((b) => state.manuallyCollapsedRoots.contains(b.rootPersonId) &&
            !newBranches.any((nb) => nb.rootPersonId == b.rootPersonId))
        .toList();

    state = BranchCollapseState(
      collapsedBranches: [...newBranches, ...manualBranchesToKeep],
      expandedBranchRoots: state.expandedBranchRoots,
      manuallyCollapsedRoots: state.manuallyCollapsedRoots,
      revision: state.revision + 1,
    );
  }

  /// v5.158 (ZONE ASSIGNMENT): Multi-source BFS zone computation.
  ///
  /// Assigns EVERY hidden member (a node in the full adjacency that is
  /// NOT in [visibleNodeIds]) to exactly ONE visible "gateway" node —
  /// the visible node closest to it by hop distance (BFS). Sources are
  /// seeded in sorted ID order and the queue is FIFO, so the assignment
  /// is fully DETERMINISTIC.
  ///
  /// Returns a map: visibleNodeIds → set of hidden member IDs whose
  /// nearest visible node is that key. Every hidden node reachable from
  /// ANY visible node appears in exactly one zone — which guarantees the
  /// user requirement "all hidden members must be represented through
  /// branch bubbles" (sum of all zone sizes == number of hidden nodes
  /// reachable from the visible set).
  ///
  /// Why this replaced the per-root full-subtree BFS (v5.154–v5.157):
  /// walking the FULL undirected adjacency separately from EVERY visible
  /// root made every bubble claim the same ~all reachable hidden members
  /// (39 chips each saying "+6" on the 714-member Test family), and any
  /// hidden member in a disconnected component was unreachable from
  /// every visible root — so it got NO bubble at all. Zone assignment
  /// partitions the hidden set exactly once.
  static Map<String, Set<String>> _computeZones(
    Set<String> visibleNodeIds,
    Map<String, Set<String>> adjacency,
  ) {
    final zones = <String, Set<String>>{};
    if (visibleNodeIds.isEmpty) return zones;

    // zoneOf[n] = the visible source that "owns" n (for visible seeds,
    // themselves; for hidden nodes, their nearest visible node).
    final zoneOf = <String, String>{};
    final queue = <String>[];

    // Seed all visible nodes as BFS sources (sorted → deterministic
    // tie-break: lexicographically smaller visible IDs win ties).
    final sources = visibleNodeIds.toList()..sort();
    for (final s in sources) {
      zoneOf[s] = s;
      queue.add(s);
    }

    // Standard multi-source BFS: a node's zone is inherited from the
    // source that reached it first (shortest hop distance wins).
    // v5.159 (TRAVERSAL SAFETY): a hard step cap — the visited map
    // already guarantees termination on well-formed graphs, but a
    // corrupted adjacency (e.g. duplicate queue entries injected by a
    // future bug) would otherwise loop forever. On breach we return
    // the zones computed so far — a degraded-but-safe result.
    var head = 0;
    var steps = 0;
    while (head < queue.length) {
      if (steps++ > kMaxGraphTraversalSteps) break;
      final n = queue[head++];
      final src = zoneOf[n]!;
      final neighbors = adjacency[n];
      if (neighbors == null || neighbors.isEmpty) continue;
      // Sorted iteration for deterministic discovery order.
      final sortedNeighbors = neighbors.toList()..sort();
      for (final m in sortedNeighbors) {
        if (zoneOf.containsKey(m)) continue; // already assigned
        zoneOf[m] = src;
        zones.putIfAbsent(src, () => <String>{}).add(m);
        queue.add(m);
      }
    }
    return zones;
  }

  /// v5.159 (RICH BUBBLES): Resolves the representative display name for
  /// a branch chip ("<name> +N"). Priority:
  ///   1. The branch ROOT's name when non-empty (the user always knows
  ///      whose branch they are expanding — the root is visible).
  ///   2. The first hidden-member name that resolves to a real (non-
  ///      'Unknown') value, iterating members in sorted order for
  ///      determinism (used when the root's own name is unavailable).
  ///   3. Null — the chip falls back to a bare "+N".
  static String? _representativeNameFor(
    String rootId,
    String rootName,
    Set<String> members,
    String Function(String) personNameOf,
  ) {
    if (rootName.trim().isNotEmpty && rootName != 'Unknown') return rootName;
    final sorted = members.toList()..sort();
    for (final id in sorted) {
      final name = personNameOf(id);
      if (name.trim().isNotEmpty && name != 'Unknown') return name;
    }
    return null;
  }

  /// Compute the descendant subtree of [root], excluding any person
  /// in [excludeSet]. Cycle-safe via visited set.
  /// v5.159 (TRAVERSAL SAFETY): iteration capped at
  /// [kMaxGraphTraversalSteps] as a fallback against corrupt adjacency
  /// maps — a breach returns the (partial) result collected so far.
  Set<String> _descendantsExcluding(
    String root,
    Map<String, Set<String>> childrenOf,
    Set<String> excludeSet,
  ) {
    final result = <String>{};
    final queue = <String>[...?childrenOf[root]];
    var steps = 0;
    while (queue.isNotEmpty) {
      if (steps++ > kMaxGraphTraversalSteps) break;
      final n = queue.removeLast();
      if (result.add(n) && !excludeSet.contains(n)) {
        queue.addAll(childrenOf[n] ?? const <String>{});
      }
    }
    // Remove excluded persons that snuck in before the exclude check.
    result.removeAll(excludeSet);
    return result;
  }

  /// Compute the max generation depth of the hidden zone.
  ///
  /// v5.158 (STACK OVERFLOW FIX): the old implementation used unbounded
  /// RECURSION with NO visited set. Over the FULL UNDIRECTED adjacency
  /// (buildFullAdjacency — every edge traversable both ways) any two
  /// adjacent hidden members walked each other forever, and long chains
  /// (100+ deep, common in zone members) blew the stack. Rewritten as
  /// an iterative level-by-level BFS with a visited set — O(V+E), safe
  /// for any topology.
  int _maxDepth(
    String root,
    Map<String, Set<String>> childrenOf,
    Set<String> hiddenSet,
  ) {
    if (hiddenSet.isEmpty) return 0;
    int maxDepth = 0;
    final visited = <String>{root};
    // Level 0: the hidden members adjacent to the root.
    var level = <String>{
      for (final n in childrenOf[root] ?? const <String>{})
        if (hiddenSet.contains(n)) n,
    };
    while (level.isNotEmpty) {
      maxDepth++;
      final next = <String>{};
      for (final n in level) {
        for (final m in childrenOf[n] ?? const <String>{}) {
          if (hiddenSet.contains(m) && visited.add(m)) {
            next.add(m);
          }
        }
      }
      visited.addAll(level);
      level = next;
    }
    return maxDepth;
  }

  String _personName(String personId, Set<String> allPersons) {
    // The caller passes person IDs, not names. For now, return a
    // placeholder — the engine view will override with the real name.
    return '';
  }

  String _generateBranchLabel(String rootName, int hiddenCount) {
    if (rootName.isNotEmpty) {
      if (hiddenCount >= 1000) {
        return "$rootName's branch · ${(hiddenCount / 1000).toStringAsFixed(1)}k";
      }
      return "$rootName's branch · $hiddenCount";
    }
    return 'Branch · $hiddenCount';
  }

  /// v5.106: Compute the dominant kinship category key among a set of
  /// members. Returns the category string that appears most frequently.
  /// Falls back to 'parent' if no categories are available.
  String _dominantCategoryKey(
    Set<String> members,
    Map<String, String>? categoryOf,
  ) {
    if (categoryOf == null || categoryOf.isEmpty) return 'parent';
    final counts = <String, int>{};
    for (final id in members) {
      final cat = categoryOf[id];
      if (cat != null) {
        counts[cat] = (counts[cat] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return 'parent';
    String? dominant;
    int maxCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        dominant = entry.key;
      }
    }
    return dominant ?? 'parent';
  }
}

/// Riverpod provider for the branch-collapse subsystem.
final branchCollapseProvider =
    StateNotifierProvider<BranchCollapseNotifier, BranchCollapseState>(
  (ref) => BranchCollapseNotifier(),
);
