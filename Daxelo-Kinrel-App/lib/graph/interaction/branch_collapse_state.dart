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
    this.revision = 0,
  });

  /// All currently-collapsed branches.
  final List<CollapsedBranch> collapsedBranches;

  /// Branch roots that the user has explicitly expanded (should NOT
  /// be auto-collapsed again). Tracked per family.
  final Set<String> expandedBranchRoots;

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
    int? revision,
  }) {
    return BranchCollapseState(
      collapsedBranches: collapsedBranches ?? this.collapsedBranches,
      expandedBranchRoots: expandedBranchRoots ?? this.expandedBranchRoots,
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
  /// [familyMemberCount] — total member count (for small-family bypass).
  ///
  /// Rules:
  ///   • Small families (< 30 members) → no collapse.
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
    // Small family bypass — don't collapse small graphs.
    if (familyMemberCount < 30) {
      if (state.collapsedBranches.isNotEmpty) {
        state = BranchCollapseState(
          collapsedBranches: const [],
          expandedBranchRoots: state.expandedBranchRoots,
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

    state = BranchCollapseState(
      collapsedBranches: newBranches,
      expandedBranchRoots: state.expandedBranchRoots,
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
      revision: state.revision + 1,
    );
  }

  /// Collapse a branch — re-collapses the subtree under [rootPersonId].
  /// Removes the root from [expandedBranchRoots].
  void collapseBranch(String rootPersonId) {
    final newExpanded = Set<String>.from(state.expandedBranchRoots)
      ..remove(rootPersonId);
    state = state.copyWith(
      expandedBranchRoots: newExpanded,
      revision: state.revision + 1,
    );
    // The actual re-collapse happens on the next computeCollapse call.
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
  ///   - Small trees (<50 visible): zero collapsing (no regression)
  ///   - Medium (50-500): partial collapsing of large branches
  ///   - Large (500-10,000+): heavy recursive collapsing
  ///
  /// Parameters:
  /// [visibleNodeIds] — nodes that passed viewport culling (pre-collapse).
  /// [childrenOf] — adjacency: personId → children IDs (for subtree sizing).
  /// [personNameOf] — resolves personId → display name for labels.
  /// [allEdges] — all edges (for computing hidden edge IDs).
  void computeDensityCollapse({
    required Set<String> visibleNodeIds,
    required Map<String, Set<String>> childrenOf,
    required String Function(String) personNameOf,
    required List<({String fromId, String toId, String edgeId, String relationshipKey})> allEdges,
  }) {
    // Small-set bypass: if within budget, clear any existing branches.
    if (visibleNodeIds.length <= kNodeBudget) {
      if (state.collapsedBranches.isNotEmpty) {
        state = BranchCollapseState(
          collapsedBranches: const [],
          expandedBranchRoots: state.expandedBranchRoots,
          revision: state.revision + 1,
        );
      }
      return;
    }

    // We need to collapse. Find roots with the largest subtrees.
    final remaining = Set<String>.from(visibleNodeIds);
    final newBranches = <CollapsedBranch>[];

    // Compute subtree sizes for all visible nodes.
    final subtreeSizes = <String, int>{};
    for (final id in visibleNodeIds) {
      subtreeSizes[id] = _subtreeSizeBFS(id, childrenOf, remaining);
    }

    // Find roots: visible nodes that have children also in the visible set.
    final roots = visibleNodeIds.where((id) {
      final children = childrenOf[id] ?? {};
      return children.any((c) => remaining.contains(c));
    }).toList();

    // Sort roots by subtree size, largest first.
    roots.sort((a, b) =>
        (subtreeSizes[b] ?? 0).compareTo(subtreeSizes[a] ?? 0));

    // Collapse subtrees until we're within budget.
    for (final rootId in roots) {
      if (remaining.length <= kNodeBudget) break;

      // Skip if user has manually expanded this root.
      if (state.expandedBranchRoots.contains(rootId)) continue;

      // Compute the subtree to collapse (BFS through childrenOf).
      final subtreeMembers = <String>{};
      _collectSubtreeBFS(rootId, childrenOf, remaining, subtreeMembers);
      subtreeMembers.remove(rootId); // root stays visible

      if (subtreeMembers.length < 3) continue; // too small to cluster

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

      newBranches.add(CollapsedBranch(
        id: '${rootId}_branch',
        rootPersonId: rootId,
        rootPersonName: rootName,
        hiddenMemberIds: Set.unmodifiable(subtreeMembers),
        hiddenEdgeIds: Set.unmodifiable(hiddenEdgeIds),
        visibleMemberCount: 1,
        hiddenGenerationDepth: _maxDepth(rootId, childrenOf, subtreeMembers),
        branchLabel: label,
        relationshipKey: '',
      ));

      remaining.removeAll(subtreeMembers);
    }

    // Idempotent update.
    if (_branchesEqual(newBranches, state.collapsedBranches)) {
      return;
    }

    state = BranchCollapseState(
      collapsedBranches: newBranches,
      expandedBranchRoots: state.expandedBranchRoots,
      revision: state.revision + 1,
    );
  }

  /// Compute subtree size via BFS (only counting nodes in [visible]).
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
      if (visible.contains(n)) count++;
      for (final child in childrenOf[n] ?? const <String>{}) {
        if (visible.contains(child)) queue.add(child);
      }
    }
    return count;
  }

  /// Collect all subtree members via BFS (only nodes in [visible]).
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
      if (visible.contains(n)) members.add(n);
      for (final child in childrenOf[n] ?? const <String>{}) {
        if (visible.contains(child)) queue.add(child);
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
      return "$rootName's branch · $hiddenCount";
    }
    return 'Branch · $hiddenCount';
  }
}

/// Riverpod provider for the branch-collapse subsystem.
final branchCollapseProvider =
    StateNotifierProvider<BranchCollapseNotifier, BranchCollapseState>(
  (ref) => BranchCollapseNotifier(),
);
