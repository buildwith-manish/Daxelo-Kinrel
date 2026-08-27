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

/// The maximum number of visible nodes in the default ego-centric view.
/// v5.121d: Reduced from 50 to 30 — at 50 nodes the zoom was too far
/// out, making nodes too small to read. 30 nodes fills the view at
/// a comfortable zoom where initials are legible.
const int kProximityNodeBudget = 30;

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
  ///
  /// Computes ring 1 (direct neighbors), ring 2 (neighbors of neighbors),
  /// and ring 3+ (expanding outward until the budget is reached).
  /// This ensures the default view always shows up to kProximityNodeBudget
  /// nodes, even when the anchor has very few direct connections.
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
  }) {
    if (!allPersons.contains(anchorId)) {
      state = const ProximityGraphState();
      return;
    }

    final visible = computeDefaultVisibleIds(
      anchorId: anchorId,
      allPersons: allPersons,
      adjacency: adjacency,
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
  /// v5.123: Extracted from [initialize] so the layout provider can
  /// compute the SAME default set synchronously without mutating this
  /// notifier (which Riverpod forbids during provider initialization —
  /// the root cause of the "Providers are not allowed to modify other
  /// providers during their initialization" crash in
  /// family_graph_screen_fab_test).
  static Set<String> computeDefaultVisibleIds({
    required String anchorId,
    required Set<String> allPersons,
    required Map<String, Set<String>> adjacency,
  }) {
    if (!allPersons.contains(anchorId)) {
      return const <String>{};
    }

    final visible = <String>{anchorId};
    final currentRing = <String>{anchorId};

    while (visible.length < kProximityNodeBudget && currentRing.isNotEmpty) {
      final nextRing = <String>{};
      for (final ringId in currentRing) {
        final neighbors = adjacency[ringId] ?? <String>{};
        for (final neighborId in neighbors) {
          if (!visible.contains(neighborId) && allPersons.contains(neighborId)) {
            nextRing.add(neighborId);
            if (visible.length + nextRing.length >= kProximityNodeBudget) break;
          }
        }
        if (visible.length + nextRing.length >= kProximityNodeBudget) break;
      }
      visible.addAll(nextRing);
      currentRing.clear();
      currentRing.addAll(nextRing);
    }

    return visible;
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
