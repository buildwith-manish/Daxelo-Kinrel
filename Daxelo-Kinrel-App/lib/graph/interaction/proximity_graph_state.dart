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
/// If the 2-hop neighborhood would exceed this, only ring 1 is shown.
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
  /// Computes ring 1 (direct neighbors) and ring 2 (neighbors of neighbors).
  /// If ring 1 + ring 2 + anchor exceeds [kProximityNodeBudget], only
  /// ring 1 is included.
  void initialize({
    required String anchorId,
    required Set<String> allPersons,
    required Map<String, Set<String>> adjacency,
  }) {
    if (!allPersons.contains(anchorId)) {
      state = const ProximityGraphState();
      return;
    }

    final visible = <String>{anchorId};
    final ring1 = adjacency[anchorId] ?? <String>{};
    visible.addAll(ring1.where((id) => allPersons.contains(id)));

    // Try to add ring 2 (neighbors of ring 1).
    final ring2 = <String>{};
    for (final r1Id in ring1) {
      final r1Neighbors = adjacency[r1Id] ?? <String>{};
      for (final r2Id in r1Neighbors) {
        if (!visible.contains(r2Id) && allPersons.contains(r2Id)) {
          ring2.add(r2Id);
        }
      }
    }

    // If ring 2 fits within the budget, add it. Otherwise stop at ring 1.
    if (visible.length + ring2.length <= kProximityNodeBudget) {
      visible.addAll(ring2);
    }

    state = ProximityGraphState(
      anchorId: anchorId,
      visibleIds: visible,
      expandedPersonIds: {anchorId},
    );
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
