// lib/graph/interaction/proximity_graph_state.dart
//
// DAXELO KINREL — v5.114 Ego-Centric Proximity Graph
//
// Manages the VISIBLE SUBSET of the family graph — the anchor person
// plus their 2-hop neighborhood (parents, spouse, children, grandparents,
// siblings, in-laws, spouse's parents).
//
// This is PRESENTATION state — the underlying FlatGraphResult (fetched
// in full by familyGraphProvider) is never modified. The proximity set
// is a client-side filter that determines WHICH nodes are positioned
// and rendered on the canvas.
//
// DEFAULT BEHAVIOR:
//   On graph open, the visible set = anchor + ring 1 + ring 2.
//   If ring 2 would push the total over ~30, stop at ring 1.
//
// TAP-TO-EXPAND:
//   Tapping a person on the outermost visible ring adds THEIR immediate
//   neighborhood (spouse + children + parents + siblings) to the visible
//   set. This is incremental — only the newly revealed nodes are added,
//   the rest of the graph is unchanged.
//
// The positioning is handled by RadialLayout (lib/graph/engine/radial_layout.dart)
// which places the anchor at center and each relationship-distance ring
// on a concentric circle.

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/graph/graph_service.dart' show inverseTypeMap;
import '../../core/kinship/kinship_edge_style.dart' show KinshipEdgeCategory;
import '../../core/kinship/structural_kinship_classifier.dart'
    show StructuralKinshipClassifier;
import 'branch_collapse_state.dart' show kNodeBudget;

/// The SOFT target for visible nodes in the default ego-centric view.
/// v5.121d: Reduced from 50 to 30 — at 50 nodes the zoom was too far
/// out, making nodes too small to read. 30 nodes fills the view at
/// a comfortable zoom where initials are legible.
///
/// v5.123 (Step 2): This is now a SOFT budget, not a hard cut. Rings
/// 1 and 2 always fill IN FULL (most families' ring 1+2 is under
/// ~40 nodes) even when that exceeds this number, and deeper rings
/// complete as whole rings. Partial-ring truncation happens ONLY at
/// [kProximityHardNodeBudget].
///
/// v5.151 (SPARSENESS FIX): Raised from 30 back to 50. The user
/// reported the default view felt "too sparse" — only 30 nodes
/// visible on a 700-member family. Matching kNodeBudget (50) means
/// rings 1+2 fill up to 50 nodes by default instead of stopping at
/// 30. The hard cap (kProximityHardNodeBudget) is ALSO 50, so the
/// soft and hard budgets are now aligned — no more "soft 30, hard 50"
/// confusion. When ring 1+2 exceeds 50, the category-priority
/// truncation (kProximityCategoryKeepPriority) keeps closer
/// relationships (spouse/parent/child/sibling) and collapses distant
/// ones (in-law/extended) into branch chips first.
const int kProximityNodeBudget = 50;

/// The HARD cap for the default ego-centric view. v5.123 (Step 2):
/// Matches [kNodeBudget] (the Show-All-path budget) WITHOUT changing
/// it — the proximity default simply borrows the same legibility
/// ceiling. When filling a ring would push the visible count past
/// this cap, the ring is truncated, preferring closer relationship
/// categories over farther ones (see
/// [kProximityCategoryKeepPriority]).
const int kProximityHardNodeBudget = kNodeBudget;

/// v5.123 (Step 2): Keep-priority used when the proximity set must be
/// truncated at [kProximityHardNodeBudget]. Lower rank = kept first.
///
/// Built on the EXISTING [KinshipEdgeCategory] enum (no new
/// categorization): immediate family first (spouse/parent/child/
/// sibling), then blood ancestors and collaterals by distance, then
/// marriage-affiliated relatives (in-laws), then step/ceremonial and
/// indirect connections last. This encodes "keep siblings/children
/// before distant in-laws".
const Map<KinshipEdgeCategory, int> kProximityCategoryKeepPriority = {
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

/// Manages the visible subset of the family graph.
///
/// This is the SINGLE SOURCE OF TRUTH for which nodes are visible on
/// the canvas. The layout provider reads this to know which nodes to
/// position; the node layer reads this to know which nodes to render.
class ProximityGraphNotifier extends StateNotifier<ProximityGraphState> {
  ProximityGraphNotifier() : super(const ProximityGraphState());

  /// Initialize the proximity set from the anchor + N-hop neighborhood.
  ///
  /// [anchorId] — the viewer's person ID (or family anchor).
  /// [allPersons] — all person IDs in the family.
  /// [adjacency] — adjacency map: personId → set of directly-connected person IDs.
  /// [edges] — the raw edge list (with relationship keys). Optional;
  /// when provided it powers the kinship-category keep-priority used
  /// when truncating at the hard cap. Without it, truncation falls
  /// back to BFS discovery order (the old behaviour).
  ///
  /// Computes ring 1 (direct neighbors), ring 2 (neighbors of neighbors),
  /// and ring 3+ (expanding outward until the soft budget is reached).
  /// This ensures the default view always shows up to
  /// [kProximityNodeBudget] nodes (hard-capped at
  /// [kProximityHardNodeBudget]), even when the anchor has very few
  /// direct connections.
  ///
  /// v5.123: The default-set computation is extracted into
  /// [computeDefaultVisibleIds] so callers that must NOT mutate this
  /// notifier (e.g. graphLayoutProvider — Riverpod forbids providers
  /// modifying other providers during their initialization) can compute
  /// the same deterministic set without writing state.
  void initialize({
    required String anchorId,
    required Set<String> allPersons,
    required Map<String, Set<String>> adjacency,
    List<({String fromId, String toId, String edgeId, String relationshipKey})>? edges,
  }) {
    if (!allPersons.contains(anchorId)) {
      state = const ProximityGraphState();
      return;
    }

    final visible = computeDefaultVisibleIds(
      anchorId: anchorId,
      allPersons: allPersons,
      adjacency: adjacency,
      edges: edges,
    );

    state = ProximityGraphState(
      anchorId: anchorId,
      visibleIds: visible,
      expandedPersonIds: {anchorId},
    );
  }

  /// Resolves the proximity anchor the same way graphLayoutProvider
  /// resolves its layout center person: the viewer's own node when
  /// linked (and present in the graph), otherwise the isAnchor-flagged
  /// person, otherwise the first person in the family.
  ///
  /// v5.123: Extracted so the widget-layer initialization (canvas_mixin)
  /// and the layout provider agree on WHICH person seeds the default
  /// ego-centric view — they must never diverge, or the rendered layout
  /// and the expansion state would center on different people.
  static String? resolveDefaultAnchor({
    required List<Map<String, dynamic>> persons,
    String? viewerPersonId,
  }) {
    if (viewerPersonId != null && viewerPersonId.isNotEmpty) {
      for (final p in persons) {
        if (p['id'] == viewerPersonId) {
          return viewerPersonId;
        }
      }
    }
    for (final p in persons) {
      if (p['isAnchor'] == true) {
        return (p['id'] ?? '').toString();
      }
    }
    if (persons.isNotEmpty) {
      return (persons.first['id'] ?? '').toString();
    }
    return null;
  }

  /// Pure (non-mutating) computation of the default visible set.
  ///
  /// v5.121: BFS expansion from the anchor, adding nodes ring by ring
  /// until we reach kProximityNodeBudget. This handles the case where
  /// the anchor has very few direct connections — instead of falling
  /// back to ALL 714 nodes (which makes the canvas too big), we expand
  /// to ring 3, 4, 5... until we have enough nodes to fill the view.
  ///
  /// v5.123 (Step 2 — ADAPTIVE BUDGET): The single fixed cap is now a
  /// soft/hard range:
  ///   • Rings 1 and 2 ALWAYS fill in full — even when that exceeds
  ///     the soft budget (most families' ring 1+2 is under ~40 nodes).
  ///   • Deeper rings fill as COMPLETE rings while the total is below
  ///     the soft budget [kProximityNodeBudget].
  ///   • Truncation (a partial ring) happens ONLY at the hard cap
  ///     [kProximityHardNodeBudget] (default 50, matching kNodeBudget).
  ///   • When truncation IS needed, candidates are kept by kinship
  ///     proximity — closer relationship categories over farther ones
  ///     (siblings/children before distant in-laws), classified with
  ///     the EXISTING KinshipEdgeCategory enum via the existing
  ///     StructuralKinshipClassifier over each candidate's BFS path —
  ///     NOT strictly by BFS discovery order.
  ///
  /// [edges] powers the kinship-category keep-priority. Without it,
  /// truncation falls back to BFS discovery order (the old behaviour).
  ///
  /// v5.123: Also extracted so the layout provider can compute the
  /// SAME default set synchronously without mutating this notifier
  /// (which Riverpod forbids during provider initialization — the root
  /// cause of the "Providers are not allowed to modify other providers
  /// during their initialization" crash in family_graph_screen_fab_test).
  static Set<String> computeDefaultVisibleIds({
    required String anchorId,
    required Set<String> allPersons,
    required Map<String, Set<String>> adjacency,
    List<({String fromId, String toId, String edgeId, String relationshipKey})>? edges,
  }) {
    if (!allPersons.contains(anchorId)) {
      return const <String>{};
    }

    // Direction-aware key lookup, matching GraphService's adjacency
    // convention: traversing from→to keeps the stored key ("to is the
    // from's <key>"); traversing to→from yields the inverse key.
    final keyTo = <String, Map<String, String>>{};
    if (edges != null) {
      for (final e in edges) {
        if (e.fromId.isEmpty || e.toId.isEmpty) continue;
        keyTo.putIfAbsent(e.fromId, () => <String, String>{})[e.toId] =
            e.relationshipKey;
        keyTo.putIfAbsent(e.toId, () => <String, String>{})[e.fromId] =
            inverseTypeMap[e.relationshipKey] ?? e.relationshipKey;
      }
    }

    final visible = <String>{anchorId};
    // Discovery chain: for each node, the BFS parent it was reached
    // through + the edge key in the parent→node direction. Used to
    // classify each candidate's relationship to the ANCHOR.
    final parentOf = <String, String>{};
    final keyFromParent = <String, String>{};

    var ringIndex = 0; // ring being expanded (0 = the anchor itself)
    var currentRing = <String>[anchorId]; // ordered → deterministic

    while (currentRing.isNotEmpty) {
      final nextRing = <String>[];
      final pending = <String>{};
      for (final ringId in currentRing) {
        final neighbors = adjacency[ringId] ?? const <String>{};
        for (final neighborId in neighbors) {
          if (!visible.contains(neighborId) &&
              !pending.contains(neighborId) &&
              allPersons.contains(neighborId)) {
            pending.add(neighborId);
            nextRing.add(neighborId);
            parentOf[neighborId] = ringId;
            keyFromParent[neighborId] = keyTo[ringId]?[neighborId] ?? '';
          }
        }
      }
      if (nextRing.isEmpty) break;

      // Hard cap: adding this ring (or part of it) is the ONLY place
      // truncation happens. Keep the kinship-closest candidates.
      if (visible.length + nextRing.length > kProximityHardNodeBudget) {
        final capacity = kProximityHardNodeBudget - visible.length;
        visible.addAll(_keepClosestByCategory(
          candidates: nextRing,
          capacity: capacity,
          parentOf: parentOf,
          keyFromParent: keyFromParent,
        ));
        break;
      }

      // Soft budget: rings 1 and 2 ALWAYS complete (ringIndex < 2 when
      // adding ring 1 / ring 2). Deeper rings complete only while the
      // soft budget hasn't been reached — but once added, they are
      // never partially cut (only the hard cap truncates).
      if (ringIndex >= 2 && visible.length >= kProximityNodeBudget) {
        break;
      }

      visible.addAll(nextRing);
      currentRing = nextRing;
      ringIndex++;
    }

    // v5.x (BUG-2 fix — spouse-pair invariant): always include
    // spouses of every visible node. Genealogical invariant: you
    // never show one spouse without the other. Without this post-
    // pass, the BFS budget can cut a node's spouse out of the
    // visible set (e.g. Yakshitha — wife of Vivek Patel — when
    // Vivek is in ring 2 and Yakshitha is in ring 3, ring 3 may
    // not be added because the soft budget is hit). The user
    // reported: "Yakshitha only appears when I tap Vivek Patel"
    // — because the tap triggered _maybeExpandFromPerson(Vivek)
    // which added his direct neighbors (including Yakshitha) to
    // the proximity set, finally giving her a layout position.
    //
    // The fix: walk every visible node's edges and add any spouse
    // (key ∈ {spouse, wife, husband, partner}) that's in allPersons.
    // This is O(visible × adjacency), runs once at init, no per-
    // frame cost. The added spouses are NOT themselves expanded
    // (their own non-spouse neighbors are not auto-added) — this
    // is a targeted spouse-pair fix, not a general expansion.
    if (edges != null) {
      final spouseKeys = const {'spouse', 'wife', 'husband', 'partner'};
      // Build a quick edge lookup: fromId → [toId] for spouse-keyed
      // edges only. We do this once (not per visible node) to keep
      // the cost linear in the edge count.
      final spouseEdges = <String, List<String>>{};
      for (final e in edges) {
        if (e.fromId.isEmpty || e.toId.isEmpty) continue;
        // The stored key is from→to; the inverse is to→from.
        // Both directions can be spouse (wife ↔ spouse, husband ↔
        // spouse, spouse ↔ spouse).
        final inverseKey = inverseTypeMap[e.relationshipKey] ??
            e.relationshipKey;
        if (spouseKeys.contains(e.relationshipKey) ||
            spouseKeys.contains(inverseKey)) {
          spouseEdges.putIfAbsent(e.fromId, () => []).add(e.toId);
          spouseEdges.putIfAbsent(e.toId, () => []).add(e.fromId);
        }
      }
      // For every visible node, add its spouse(s) if they're in
      // allPersons and not already visible.
      // Iterate over a SNAPSHOT of visible (we're mutating it).
      final visibleSnapshot = visible.toList();
      for (final id in visibleSnapshot) {
        final spouses = spouseEdges[id];
        if (spouses == null) continue;
        for (final spouseId in spouses) {
          if (allPersons.contains(spouseId) && !visible.contains(spouseId)) {
            visible.add(spouseId);
          }
        }
      }
    }

    return visible;
  }

  /// v5.123 (Step 2): Picks the [capacity] kinship-closest candidates
  /// from [candidates], ranking by [kProximityCategoryKeepPriority]
  /// (ties broken by BFS discovery order for determinism).
  ///
  /// Each candidate's category is resolved by the EXISTING
  /// [StructuralKinshipClassifier] — the same classifier
  /// RelationshipEngine uses — over the candidate's BFS path keys
  /// (anchor → … → candidate). A sibling therefore outranks a
  /// sibling-in-law; a child outranks a distant in-law.
  static List<String> _keepClosestByCategory({
    required List<String> candidates,
    required int capacity,
    required Map<String, String> parentOf,
    required Map<String, String> keyFromParent,
  }) {
    if (capacity <= 0) return const <String>[];
    if (capacity >= candidates.length) return candidates;

    // Rank candidates: (category priority, discovery order).
    final ranked = <(int, int, String)>[];
    for (var i = 0; i < candidates.length; i++) {
      final id = candidates[i];
      final category = _classifyCandidate(
        id,
        parentOf: parentOf,
        keyFromParent: keyFromParent,
      );
      final rank = kProximityCategoryKeepPriority[category] ??
          kProximityCategoryKeepPriority[KinshipEdgeCategory.extended]!;
      ranked.add((rank, i, id));
    }
    ranked.sort((a, b) {
      final byRank = a.$1.compareTo(b.$1);
      if (byRank != 0) return byRank;
      return a.$2.compareTo(b.$2); // stable: BFS discovery order
    });

    return [for (final r in ranked.take(capacity)) r.$3];
  }

  /// Classifies [id]'s relationship to the anchor by composing the
  /// BFS path keys (anchor → … → id) through the EXISTING
  /// [StructuralKinshipClassifier]. Returns [KinshipEdgeCategory.extended]
  /// when no path keys are available (missing edge keys degrade to the
  /// old BFS-order behaviour).
  static KinshipEdgeCategory _classifyCandidate(
    String id, {
    required Map<String, String> parentOf,
    required Map<String, String> keyFromParent,
  }) {
    // Walk the parent chain from `id` up to the anchor, collecting
    // the step keys, then reverse → anchor-to-id order.
    final pathKeys = <String>[];
    var current = id;
    while (parentOf.containsKey(current)) {
      final key = keyFromParent[current];
      if (key == null) break;
      pathKeys.add(key);
      current = parentOf[current]!;
    }
    if (pathKeys.isEmpty) return KinshipEdgeCategory.extended;
    return StructuralKinshipClassifier.classify(
      path: pathKeys.reversed.toList(),
    ).category;
  }

  /// Tap-to-expand: add a person's immediate neighborhood to the visible set.
  ///
  /// When the user taps a person on the outermost ring, this fetches
  /// (from the in-memory adjacency, not Supabase) that person's direct
  /// neighbors and adds them to the visible set.
  ///
  /// This is INCREMENTAL — only the newly revealed nodes are added.
  /// The rest of the graph is unchanged.
  void expandFromPerson({
    required String personId,
    required Map<String, Set<String>> adjacency,
    required Set<String> allPersons,
  }) {
    if (!allPersons.contains(personId)) return;

    final current = state;
    final newVisible = Set<String>.from(current.visibleIds);
    final neighbors = adjacency[personId] ?? <String>{};

    for (final neighborId in neighbors) {
      if (allPersons.contains(neighborId)) {
        newVisible.add(neighborId);
      }
    }

    final newExpanded = Set<String>.from(current.expandedPersonIds);
    newExpanded.add(personId);

    state = ProximityGraphState(
      anchorId: current.anchorId,
      visibleIds: newVisible,
      expandedPersonIds: newExpanded,
    );
  }

  /// v5.123 (Step 3): Bulk reveal — adds a set of persons to the visible
  /// set in one incremental step (used when a collapsed branch is
  /// expanded so its members actually render).
  ///
  /// Semantics mirror [expandFromPerson] (the existing tap-to-expand
  /// mechanism): purely INCREMENTAL — only adds IDs, never removes, and
  /// records the revealed persons in [ProximityGraphState.expandedPersonIds]
  /// so they are not treated as un-expanded outermost-ring nodes.
  /// Deterministic and safe to call with IDs that are already visible.
  void revealPersons({
    required Set<String> personIds,
    required Set<String> allPersons,
  }) {
    final current = state;
    if (personIds.isEmpty) return;

    final newVisible = Set<String>.from(current.visibleIds);
    var added = false;
    for (final id in personIds) {
      if (allPersons.contains(id) && !newVisible.contains(id)) {
        newVisible.add(id);
        added = true;
      }
    }
    if (!added) return; // Nothing new — no state change, no rebuild.

    final newExpanded = Set<String>.from(current.expandedPersonIds)
      ..addAll(personIds.where(allPersons.contains));

    state = ProximityGraphState(
      anchorId: current.anchorId,
      visibleIds: newVisible,
      expandedPersonIds: newExpanded,
    );
  }

  /// v5.123 (Step 5): Reveals an entire branch subtree (the root plus
  /// all its descendants) — used when a PERSISTED expanded branch is
  /// re-applied on graph load, so the previously-expanded branch's
  /// members render immediately instead of waiting behind a chip.
  ///
  /// [childrenOf] is the parent→children adjacency (the same map the
  /// density-collapse computation builds). Purely INCREMENTAL, like
  /// [revealPersons]. Unknown root → no-op.
  void revealBranchSubtree({
    required String rootId,
    required Map<String, Set<String>> childrenOf,
    required Set<String> allPersons,
  }) {
    if (!allPersons.contains(rootId)) return;

    // Collect the subtree via BFS through childrenOf (cycle-safe).
    final subtree = <String>{};
    final queue = <String>[rootId];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      if (!subtree.add(current)) continue;
      for (final child in childrenOf[current] ?? const <String>{}) {
        if (allPersons.contains(child) && !subtree.contains(child)) {
          queue.add(child);
        }
      }
    }
    if (subtree.isEmpty) return;

    revealPersons(personIds: subtree, allPersons: allPersons);
  }

  /// Reset to the default 2-hop view (clears all expansions).
  void reset() {
    state = const ProximityGraphState();
  }

  /// Check if a person is currently visible.
  bool isVisible(String personId) {
    return state.visibleIds.contains(personId);
  }

  /// Check if a person has already been expanded (their neighbors revealed).
  bool isExpanded(String personId) {
    return state.expandedPersonIds.contains(personId);
  }
}

/// Immutable state for the proximity graph.
@immutable
class ProximityGraphState {
  const ProximityGraphState({
    this.anchorId,
    this.visibleIds = const {},
    this.expandedPersonIds = const {},
  });

  /// The anchor person ID (viewer's own node, or family anchor).
  final String? anchorId;

  /// The set of person IDs currently visible on the canvas.
  final Set<String> visibleIds;

  /// The set of person IDs whose immediate neighborhood has been revealed.
  /// Used to determine which nodes are "expandable" (on the outermost ring).
  final Set<String> expandedPersonIds;

  /// Whether the proximity set has been initialized.
  bool get isInitialized => anchorId != null;

  /// Whether a person is on the outermost ring (expandable).
  ///
  /// A person is on the outermost ring if they are visible but their
  /// neighbors have NOT all been revealed (i.e., they haven't been
  /// expanded yet).
  bool isOutermost(String personId, Map<String, Set<String>> adjacency) {
    if (!visibleIds.contains(personId)) return false;
    if (expandedPersonIds.contains(personId)) return false;
    return true;
  }
}

/// Provider for the proximity graph state.
final proximityGraphProvider =
    StateNotifierProvider<ProximityGraphNotifier, ProximityGraphState>(
  (ref) => ProximityGraphNotifier(),
);

/// Builds an adjacency map from the flat graph's relationship list.
///
/// Returns a map: personId → set of directly-connected person IDs.
/// This is used by the proximity notifier to compute ring 1 / ring 2.
Map<String, Set<String>> buildAdjacency(
  List<({String fromId, String toId, String edgeId, String relationshipKey})> edges,
) {
  final adjacency = <String, Set<String>>{};
  for (final e in edges) {
    adjacency.putIfAbsent(e.fromId, () => <String>{}).add(e.toId);
    adjacency.putIfAbsent(e.toId, () => <String>{}).add(e.fromId);
  }
  return adjacency;
}
