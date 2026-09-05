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

  /// Bumped whenever collapse state changes. Used by the painter's
  /// shouldRepaint.
  final int revision;

  static const BranchCollapseState empty = BranchCollapseState();

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
    int? revision,
  }) {
    return BranchCollapseState(
      collapsedBranches: collapsedBranches ?? this.collapsedBranches,
      expandedBranchRoots: expandedBranchRoots ?? this.expandedBranchRoots,
      manuallyCollapsedRoots: manuallyCollapsedRoots ?? this.manuallyCollapsedRoots,
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
  void expandBranch(String rootPersonId) {
    final newBranches = state.collapsedBranches
        .where((b) => b.rootPersonId != rootPersonId)
        .toList();
    final newExpanded = Set<String>.from(state.expandedBranchRoots)
      ..add(rootPersonId);
    state = BranchCollapseState(
      collapsedBranches: newBranches,
      expandedBranchRoots: newExpanded,
      manuallyCollapsedRoots: state.manuallyCollapsedRoots,
      revision: state.revision + 1,
    );
    // v5.123 (Step 5): persist the user's expansion choice.
    onExpansionChanged?.call(rootPersonId, true);
  }

  /// Collapse a branch — re-collapses the subtree under [rootPersonId].
  /// Removes the root from [expandedBranchRoots].
  void collapseBranch(String rootPersonId) {
    final newExpanded = Set<String>.from(state.expandedBranchRoots)
      ..remove(rootPersonId);
    state = state.copyWith(
      expandedBranchRoots: newExpanded,
      manuallyCollapsedRoots: state.manuallyCollapsedRoots,
      revision: state.revision + 1,
    );
    // The actual re-collapse happens on the next computeCollapse call.
    // v5.123 (Step 5): persist the user's re-collapse choice.
    onExpansionChanged?.call(rootPersonId, false);
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

    state = BranchCollapseState(
      collapsedBranches: [...newCollapsedBranches, manualBranch],
      expandedBranchRoots: newExpanded,
      manuallyCollapsedRoots: newManual,
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
  bool hasVisibleDescendants(
    String personId,
    Map<String, Set<String>> childrenOf,
    Set<String> visibleIds,
  ) {
    final children = childrenOf[personId];
    if (children == null || children.isEmpty) return false;
    for (final child in children) {
      if (visibleIds.contains(child)) return true;
      // Recursively check grandchildren.
      if (hasVisibleDescendants(child, childrenOf, visibleIds)) return true;
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

  /// Density-driven collapse: if [visibleNodeIds] exceeds [kNodeBudget],
  /// collapse subtrees (largest first) until the visible count is at or
  /// under budget.
  ///
  /// This is the UNIFIED rule that works at any scale:
  ///   - Small trees (≤ 50 candidates): zero collapsing (no regression)
  ///   - Medium (50-500): partial collapsing of large branches
  ///   - Large (500-10,000+): heavy recursive collapsing
  ///
  /// v5.123 (CONVERGENCE FIX): [visibleNodeIds] must be the FULL
  /// rendered candidate set (positions ∩ expand/collapse allow-list),
  /// NOT the count with the current hidden set subtracted. Feeding the
  /// post-hiding count made this pass clear the very branches it had
  /// just created on the next build — an infinite rebuild oscillation.
  /// With the full candidate set the computation is a deterministic
  /// fixed point: the same inputs produce the same branches, so the
  /// idempotency check (`_branchesEqual`) no-ops and the pipeline
  /// converges.
  ///
  /// Parameters:
  /// [visibleNodeIds] — ALL rendered candidate nodes (pre-collapse).
  /// [childrenOf] — adjacency: personId → children IDs (for subtree sizing).
  /// [personNameOf] — resolves personId → display name for labels.
  /// [allEdges] — all edges (for computing hidden edge IDs).
  /// [protectedIds] — v5.123: persons that must NEVER be hidden (focus
  ///   person, first/second-degree neighbours, active path, search
  ///   matches, selection). Roots inside this set are skipped and the
  ///   members are excluded from hidden subtrees — this absorbs the
  ///   focus-protection the canvas used to get from computeCollapse.
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
    // v5.155 (FIX 2): Reworked bypass. The old check
    // `if (visibleNodeIds.length <= kNodeBudget) return;` ALWAYS fired
    // because the proximity RPC returns ≤50 nodes (kProximityHardNodeBudget
    // == kNodeBudget == 50). This meant zero branches were ever created,
    // zero bubbles ever rendered — the 664 hidden members were invisible
    // with no expansion controls.
    //
    // New logic: compute the TRUE family size by walking the FULL
    // childrenOf adjacency (built from allEdges, which contains every
    // active edge in the family). If the true family size exceeds the
    // budget, create branches for visible roots that have hidden
    // descendants — even when the visible set itself is ≤50.
    //
    // This ensures: visible members + members in branch bubbles =
    // total family members. Every hidden member belongs to at least
    // one visible branch bubble.

    // Compute true subtree sizes against the FULL adjacency.
    final subtreeSizes = <String, int>{};
    for (final id in visibleNodeIds) {
      subtreeSizes[id] = _subtreeSizeBFS(id, childrenOf, visibleNodeIds);
    }
    // Count total reachable members (visible + hidden descendants).
    final totalReachable = visibleNodeIds.length +
        subtreeSizes.values.fold<int>(0, (a, b) => a + b);

    // Bypass ONLY when the true family size fits the budget.
    if (totalReachable <= kNodeBudget) {
      final manualBranches = state.collapsedBranches
          .where((b) => state.manuallyCollapsedRoots.contains(b.rootPersonId))
          .toList();
      if (state.collapsedBranches.length != manualBranches.length) {
        state = BranchCollapseState(
          collapsedBranches: manualBranches,
          expandedBranchRoots: state.expandedBranchRoots,
          manuallyCollapsedRoots: state.manuallyCollapsedRoots,
          revision: state.revision + 1,
        );
      }
      return;
    }

    // The true family size exceeds the budget. We need to create
    // branch bubbles for visible roots that have hidden descendants,
    // even if the visible set itself is ≤50.
    final protected = protectedIds ?? const <String>{};

    final remaining = Set<String>.from(visibleNodeIds);
    final newBranches = <CollapsedBranch>[];

    // Find roots: visible nodes that have children in the FULL adjacency
    // (not just visible set). This catches roots whose entire subtree is
    // unpositioned — the primary case for branch bubbles.
    final roots = visibleNodeIds.where((id) {
      if (protected.contains(id)) return false;
      final children = childrenOf[id] ?? {};
      // v5.155: A root is a candidate if it has ANY children in the full
      // graph (not just visible ones). This ensures branches are created
      // for roots whose descendants are all unpositioned.
      return children.isNotEmpty;
    }).toList();

    // Sort roots by subtree size, largest first.
    roots.sort((a, b) =>
        (subtreeSizes[b] ?? 0).compareTo(subtreeSizes[a] ?? 0));

    // v5.155: Create a branch bubble for EVERY visible root that has
    // hidden descendants (subtreeMembers.length > 0), not just until
    // the visible set is under budget. The visible set IS already
    // under budget (proximity cap = 50). The goal is to create bubbles
    // representing the hidden members, not to reduce the visible set.
    for (final rootId in roots) {
      // Skip if user has manually expanded this root.
      if (state.expandedBranchRoots.contains(rootId)) continue;
      // v5.142: Skip if manually collapsed — don't touch it.
      if (state.manuallyCollapsedRoots.contains(rootId)) continue;

      // Compute the subtree to collapse (BFS through FULL childrenOf).
      final subtreeMembers = <String>{};
      _collectSubtreeBFS(rootId, childrenOf, remaining, subtreeMembers);
      subtreeMembers.remove(rootId); // root stays visible
      // v5.123: protected persons stay visible even inside a hidden
      // subtree (their branch is partially collapsed around them).
      subtreeMembers.removeAll(protected);

      // v5.155: Skip if no hidden descendants. This is the key filter —
      // we only create bubbles for roots that HAVE hidden members.
      if (subtreeMembers.isEmpty) continue;

      // Compute hidden edges.
      final hiddenEdgeIds = <String>{};
      for (final e in allEdges) {
        if (subtreeMembers.contains(e.fromId) &&
            (subtreeMembers.contains(e.toId) || e.toId == rootId)) {
          hiddenEdgeIds.add(e.edgeId);
        } else if (subtreeMembers.contains(e.toId) &&
            (subtreeMembers.contains(e.fromId) || e.fromId == rootId)) {
          hiddenEdgeIds.add(e.edgeId);
        }
      }

      final rootName = personNameOf(rootId);
      final label = _generateBranchLabel(rootName, subtreeMembers.length);

      // v5.106: Compute dominant kinship category among subtree members.
      // This is used for the chip's accent color instead of hardcoded orange.
      final dominantKey = _dominantCategoryKey(subtreeMembers, categoryOf);

      // v5.106: Recursive sub-clustering. If the subtree is so large
      // that even after collapsing it, its own children would exceed
      // kNodeBudget, recurse into the subtree's children to create
      // nested sub-branches. This ensures the budget holds at 10k+ scale.
      final subBranches = subtreeMembers.length > kNodeBudget
          ? _computeSubBranches(
              rootId: rootId,
              subtreeMembers: subtreeMembers,
              childrenOf: childrenOf,
              personNameOf: personNameOf,
              allEdges: allEdges,
              categoryOf: categoryOf,
            )
          : const <CollapsedBranch>[];

      newBranches.add(CollapsedBranch(
        id: '${rootId}_branch',
        rootPersonId: rootId,
        rootPersonName: rootName,
        hiddenMemberIds: Set.unmodifiable(subtreeMembers),
        hiddenEdgeIds: Set.unmodifiable(hiddenEdgeIds),
        visibleMemberCount: 1,
        hiddenGenerationDepth: _maxDepth(rootId, childrenOf, subtreeMembers),
        branchLabel: label,
        relationshipKey: dominantKey,  // v5.106: was '' — now dominant category
        subBranches: subBranches,       // v5.106: recursive sub-branches
      ));

      // v5.155: Do NOT remove subtreeMembers from remaining — they're
      // unpositioned members, not visible nodes. Removing them would
      // have no effect (they're not in remaining) but could cause
      // confusion in future audits.
    }

    // Idempotent update.
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

  /// Compute subtree size via BFS.
  ///
  /// v5.154 (BRANCH BUBBLE FIX): Previously only counted nodes in
  /// [visible] — so the "largest subtree" sort used to pick collapse
  /// roots was wrong (it picked subtrees with many VISIBLE descendants
  /// instead of subtrees with many TOTAL descendants). Now counts ALL
  /// descendants so the largest true subtrees get collapsed first.
  int _subtreeSizeBFS(
    String rootId,
    Map<String, Set<String>> childrenOf,
    Set<String> visible,
  ) {
    final visited = <String>{};
    final queue = <String>[rootId];
    int count = 0;
    while (queue.isNotEmpty) {
      final n = queue.removeLast();
      if (visited.contains(n)) continue;
      visited.add(n);
      if (n != rootId) count++; // count ALL descendants
      // v5.154: Walk ALL children, not just visible ones.
      for (final child in childrenOf[n] ?? const <String>{}) {
        if (!visited.contains(child)) queue.add(child);
      }
    }
    return count;
  }

  /// Collect all subtree members via BFS.
  ///
  /// v5.154 (BRANCH BUBBLE FIX): Previously only collected nodes in
  /// [visible] — so branch bubbles only counted the ~50 positioned
  /// nodes, NOT the 664 unpositioned descendants. The user saw ~50
  /// nodes + a few tiny "+3" bubbles instead of bubbles showing the
  /// true hidden count (e.g. "+38").
  ///
  /// Now walks the FULL adjacency (all children, positioned or not)
  /// so each branch bubble's hiddenMemberIds reflects the TRUE subtree
  /// size in the canonical graph. The [visible] parameter is kept for
  /// the budget check (only positioned roots get chips) but is NOT
  /// used to filter subtree traversal.
  void _collectSubtreeBFS(
    String rootId,
    Map<String, Set<String>> childrenOf,
    Set<String> visible,
    Set<String> members,
  ) {
    final visited = <String>{};
    final queue = <String>[rootId];
    while (queue.isNotEmpty) {
      final n = queue.removeLast();
      if (visited.contains(n)) continue;
      visited.add(n);
      if (n != rootId) members.add(n); // collect ALL descendants
      // v5.154: Walk ALL children, not just visible ones. This is the
      // key fix — the 664 unpositioned members are reachable through
      // the full childrenOf map (built from flat.relationships).
      for (final child in childrenOf[n] ?? const <String>{}) {
        if (!visited.contains(child)) queue.add(child);
      }
    }
  }

  /// Compute the descendant subtree of [root], excluding any person
  /// in [excludeSet]. Cycle-safe via visited set.
  Set<String> _descendantsExcluding(
    String root,
    Map<String, Set<String>> childrenOf,
    Set<String> excludeSet,
  ) {
    final result = <String>{};
    final queue = <String>[...?childrenOf[root]];
    while (queue.isNotEmpty) {
      final n = queue.removeLast();
      if (result.add(n) && !excludeSet.contains(n)) {
        queue.addAll(childrenOf[n] ?? const <String>{});
      }
    }
    // Remove excluded persons that snuck in before the exclude check.
    result.removeAll(excludeSet);
    return result;
  }

  /// Compute the max generation depth of the hidden subtree.
  int _maxDepth(
    String root,
    Map<String, Set<String>> childrenOf,
    Set<String> hiddenSet,
  ) {
    int maxDepth = 0;
    void walk(String node, int depth) {
      if (depth > maxDepth) maxDepth = depth;
      for (final child in childrenOf[node] ?? const <String>{}) {
        if (hiddenSet.contains(child)) {
          walk(child, depth + 1);
        }
      }
    }

    walk(root, 0);
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

  /// v5.106: Recursively compute sub-branches for a large collapsed
  /// subtree. When a single branch has > kNodeBudget members, its
  /// direct children are each evaluated as potential sub-branch roots.
  /// This ensures the budget holds at 10k/100k+ scale.
  List<CollapsedBranch> _computeSubBranches({
    required String rootId,
    required Set<String> subtreeMembers,
    required Map<String, Set<String>> childrenOf,
    required String Function(String) personNameOf,
    required List<({String fromId, String toId, String edgeId, String relationshipKey})> allEdges,
    Map<String, String>? categoryOf,
  }) {
    // Find the root's direct children that are in the subtree.
    final directChildren = (childrenOf[rootId] ?? <String>{})
        .where((c) => subtreeMembers.contains(c))
        .toList();

    if (directChildren.isEmpty) return const [];

    // Compute subtree size for each child.
    final childSubtreeSizes = <String, int>{};
    for (final child in directChildren) {
      final childSubtree = <String>{};
      _collectSubtreeBFS(child, childrenOf, subtreeMembers, childSubtree);
      childSubtreeSizes[child] = childSubtree.length;
    }

    // Sort children by subtree size, largest first.
    directChildren.sort((a, b) =>
        (childSubtreeSizes[b] ?? 0).compareTo(childSubtreeSizes[a] ?? 0));

    final subBranches = <CollapsedBranch>[];
    final subHidden = <String>{};

    for (final childId in directChildren) {
      // Collect this child's subtree.
      final childSubtree = <String>{};
      _collectSubtreeBFS(childId, childrenOf, subtreeMembers, childSubtree);
      childSubtree.remove(childId); // child stays visible as sub-branch root

      if (childSubtree.length < 3) continue; // too small to sub-cluster

      // Compute hidden edges for this sub-branch.
      final subHiddenEdges = <String>{};
      for (final e in allEdges) {
        if (childSubtree.contains(e.fromId) &&
            (childSubtree.contains(e.toId) || e.toId == childId)) {
          subHiddenEdges.add(e.edgeId);
        } else if (childSubtree.contains(e.toId) &&
            (childSubtree.contains(e.fromId) || e.fromId == childId)) {
          subHiddenEdges.add(e.edgeId);
        }
      }

      final childName = personNameOf(childId);
      final subLabel = _generateBranchLabel(childName, childSubtree.length);
      final subDominantKey = _dominantCategoryKey(childSubtree, categoryOf);

      // Recurse if this sub-branch is still too large.
      final subSubBranches = childSubtree.length > kNodeBudget
          ? _computeSubBranches(
              rootId: childId,
              subtreeMembers: childSubtree,
              childrenOf: childrenOf,
              personNameOf: personNameOf,
              allEdges: allEdges,
              categoryOf: categoryOf,
            )
          : const <CollapsedBranch>[];

      subBranches.add(CollapsedBranch(
        id: '${childId}_subbranch',
        rootPersonId: childId,
        rootPersonName: childName,
        hiddenMemberIds: Set.unmodifiable(childSubtree),
        hiddenEdgeIds: Set.unmodifiable(subHiddenEdges),
        visibleMemberCount: 1,
        hiddenGenerationDepth: _maxDepth(childId, childrenOf, childSubtree),
        branchLabel: subLabel,
        relationshipKey: subDominantKey,
        subBranches: subSubBranches,
      ));

      subHidden.addAll(childSubtree);
    }

    return subBranches;
  }
}

/// Riverpod provider for the branch-collapse subsystem.
final branchCollapseProvider =
    StateNotifierProvider<BranchCollapseNotifier, BranchCollapseState>(
  (ref) => BranchCollapseNotifier(),
);
