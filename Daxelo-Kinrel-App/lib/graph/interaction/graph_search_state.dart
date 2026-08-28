// lib/graph/interaction/graph_search_state.dart
//
// DAXELO KINREL — Integrated Graph Search (Phase 5)
//
// Wires Kinrel's existing client-side search into the graph canvas.
// When search is active:
//   • matching nodes are highlighted
//   • non-matching nodes are dimmed
//   • collapsed branches containing matches are marked
//   • next/previous navigation cycles through matches
//   • selecting a result animates the camera to that node
//   • if the result is inside a collapsed branch, the branch auto-expands
//
// v5.125 (Step 4): selecting a result that is NOT in the visible/
//   proximity set AT ALL (not loaded — not merely collapsed) reveals
//   the shortest relationship path from the proximity anchor to them
//   via [GraphSearchNotifier.revealOffscreenMatch] — see that method
//   for the reuse contract (existing BFS + existing proximity
//   expansion, no second path algorithm).
//
// This is LOCAL graph interaction state. It does NOT modify
// relationship data, node positions, or canonical topology.

import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/relationship/relationship_engine.dart'
    show RelationshipEngine;
import '../../core/services/graph_layout_service.dart' show GraphPerson;
import 'proximity_graph_state.dart'
    show ProximityGraphNotifier, buildAdjacency;

/// The state of the graph search subsystem.
@immutable
class GraphSearchState {
  const GraphSearchState({
    this.query = '',
    this.matchIds = const <String>[],
    this.currentIndex = -1,
    this.isActive = false,
    this.revision = 0,
    this.revealedPathIds = const <String>{},
  });

  /// The current search query string.
  final String query;

  /// Ordered list of person IDs that match the current query.
  /// The order is the same as the search result list (ranked).
  final List<String> matchIds;

  /// The index of the currently-selected match in [matchIds].
  /// -1 when no match is selected. 0-based.
  final int currentIndex;

  /// True when search is active (search bar is open + query is non-empty).
  final bool isActive;

  /// Bumped whenever search state changes. Used by the painter's
  /// shouldRepaint to trigger a repaint.
  final int revision;

  /// v5.125 (Step 4): Person IDs revealed by the LAST search jump to an
  /// offscreen match — the direct path (anchor → … → target) plus the
  /// target's immediate neighborhood. Empty when the last selection
  /// needed no reveal (target already visible / proximity not ready).
  ///
  /// The canvas's density-collapse pass includes these in its
  /// protected-ID set so the node budget never re-hides the very nodes
  /// the search jump just revealed.
  final Set<String> revealedPathIds;

  static const GraphSearchState empty = GraphSearchState();

  /// The currently-selected match ID, or null if none.
  String? get currentMatchId =>
      currentIndex >= 0 && currentIndex < matchIds.length
          ? matchIds[currentIndex]
          : null;

  /// The set of all match IDs (for dim/highlight logic).
  Set<String> get matchIdSet => matchIds.toSet();

  /// True when [personId] is a search match.
  bool isMatch(String personId) => matchIdSet.contains(personId);

  /// True when [personId] is the currently-selected match.
  bool isCurrentMatch(String personId) => personId == currentMatchId;

  /// True when this state is semantically "empty" — no query, no
  /// matches, not active. The revision is NOT compared because it
  /// is a monotonically-increasing counter, not a semantic field.
  bool get isEmpty =>
      query.isEmpty &&
      matchIds.isEmpty &&
      !isActive &&
      currentIndex == -1 &&
      revealedPathIds.isEmpty;

  GraphSearchState copyWith({
    String? query,
    List<String>? matchIds,
    int? currentIndex,
    bool? isActive,
    int? revision,
    Set<String>? revealedPathIds,
  }) {
    return GraphSearchState(
      query: query ?? this.query,
      matchIds: matchIds ?? this.matchIds,
      currentIndex: currentIndex ?? this.currentIndex,
      isActive: isActive ?? this.isActive,
      revision: revision ?? this.revision,
      revealedPathIds: revealedPathIds ?? this.revealedPathIds,
    );
  }

  @override
  /// Two states are equal when their SEMANTIC fields match (query,
  /// matchIds, currentIndex, isActive). The revision is a paint-loop
  /// counter and is NOT compared — it would make two semantically-
  /// identical states with different revisions unequal, breaking
  /// `clear()` which bumps revision but should still produce a state
  /// that equals `GraphSearchState.empty`.
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphSearchState &&
          other.query == query &&
          _listEquals(other.matchIds, matchIds) &&
          other.currentIndex == currentIndex &&
          other.isActive == isActive &&
          _setEquals(other.revealedPathIds, revealedPathIds);

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  @override
  int get hashCode => Object.hash(
      query, matchIds.length, currentIndex, isActive, revealedPathIds.length);

  @override
  String toString() =>
      'GraphSearchState(query="$query", matches=${matchIds.length}, '
      'current=$currentIndex, active=$isActive, '
      'revealed=${revealedPathIds.length}, rev=$revision)';
}

/// StateNotifier that owns the graph search state.
class GraphSearchNotifier extends StateNotifier<GraphSearchState> {
  GraphSearchNotifier() : super(GraphSearchState.empty);

  /// Set the search query + match results. Called by the search bar
  /// when the user types or when filters change.
  ///
  /// [matchIds] is the ordered list of person IDs matching the query,
  /// ranked by relevance (same order as the search result list).
  ///
  /// BUG FIX: `isActive` is true ONLY when the query is non-empty AND
  /// there is at least one match. Previously, a query with zero matches
  /// kept `isActive = true`, which left the graph in a dimmed state
  /// with no highlighted nodes — confusing the user.
  void setResults(String query, List<String> matchIds) {
    final newIsActive = query.trim().isNotEmpty && matchIds.isNotEmpty;

    state = GraphSearchState(
      query: query,
      matchIds: List.unmodifiable(matchIds),
      currentIndex: matchIds.isEmpty ? -1 : 0,
      isActive: newIsActive,
      revision: state.revision + 1,
      // v5.125 (Step 4): a new query does NOT undo the last jump's
      // reveal — the revealed path members are already in the proximity
      // visible set, and dropping their collapse protection here could
      // let the density budget re-hide them mid-session.
      revealedPathIds: state.revealedPathIds,
    );
  }

  /// Move to the next match. Wraps around to the first match if at
  /// the end. Does nothing if there are no matches.
  void nextMatch() {
    if (state.matchIds.isEmpty) return;
    final next = (state.currentIndex + 1) % state.matchIds.length;
    state = state.copyWith(
      currentIndex: next,
      revision: state.revision + 1,
    );
  }

  /// Move to the previous match. Wraps around to the last match if at
  /// the beginning. Does nothing if there are no matches.
  void previousMatch() {
    if (state.matchIds.isEmpty) return;
    final prev = state.currentIndex <= 0
        ? state.matchIds.length - 1
        : state.currentIndex - 1;
    state = state.copyWith(
      currentIndex: prev,
      revision: state.revision + 1,
    );
  }

  /// Select a specific match by person ID. If [personId] is not in
  /// the match list, does nothing.
  void selectMatch(String personId) {
    final index = state.matchIds.indexOf(personId);
    if (index < 0) return;
    state = state.copyWith(
      currentIndex: index,
      revision: state.revision + 1,
    );
  }

  /// Clear the search — restores the graph to its normal emphasis state.
  ///
  /// BUG FIX: Previously, `clear()` set `state = GraphSearchState.empty`,
  /// which has `revision = 0`. This meant the revision went DOWN (e.g.
  /// from 1 to 0), so the painter's `shouldRepaint` (which checks
  /// `old.revision != new.revision`) would fire — but the revision
  /// counter was lost, making future comparisons unreliable.
  ///
  /// Now, `clear()` preserves the revision counter and bumps it by 1,
  /// so the painter always sees a monotonically increasing revision.
  void clear() {
    if (state.query.isEmpty &&
        state.matchIds.isEmpty &&
        !state.isActive &&
        // v5.125 (Step 4): a lingering reveal-path protection set must
        // also be clearable.
        state.revealedPathIds.isEmpty) {
      return; // Already cleared — no-op.
    }
    state = GraphSearchState(
      query: '',
      matchIds: const [],
      currentIndex: -1,
      isActive: false,
      revision: state.revision + 1,
      // v5.125 (Step 4): clearing the search ends the jump session —
      // the reveal-path protection goes with it. (The revealed members
      // STAY in the proximity visible set — only the density-collapse
      // protection is dropped.)
      revealedPathIds: const {},
    );
  }

  // ── v5.125 (Step 4): Offscreen-match reveal ─────────────────────────

  /// Reveals a search match that is OUTSIDE the current visible /
  /// proximity set — i.e. not rendered by the canvas at all (not
  /// loaded), as opposed to merely hidden inside a collapsed branch,
  /// which the collapse pipeline's protected-ID set already handles.
  ///
  /// Reuse contract (NO second path algorithm):
  ///   • Path-finding REUSES `RelationshipEngine.instance.resolvePath` —
  ///     the exact BFS that powers `GraphPathFocusNotifier.resolve`
  ///     (graph_kinship_path_focus.dart) and the "How we're connected"
  ///     trace (graph_path_trace_controller.dart via the interaction
  ///     mixin's `_resolvePathFocus`).
  ///   • The reveal goes through the EXISTING proximity-expansion
  ///     mechanisms: [ProximityGraphNotifier.revealPersons] (the bulk
  ///     sibling of tap-to-expand's `expandFromPerson`) plus
  ///     [ProximityGraphNotifier.expandFromPerson] for the target's
  ///     immediate neighborhood — the same semantics as a user tap.
  ///
  /// Scope: ONLY the direct path's nodes (anchor → … → target) plus
  /// that neighborhood are added. No unrelated branch is expanded or
  /// collapsed. When no path exists (disconnected / data gap) the
  /// target alone is revealed so the result still renders and the
  /// camera can center on them.
  ///
  /// The revealed IDs are recorded in [GraphSearchState.revealedPathIds]
  /// so the canvas's density-collapse pass protects them from the node
  /// budget. Returns the revealed set (empty when no reveal was
  /// needed — target already visible, proximity not initialized, or
  /// no anchor).
  Set<String> revealOffscreenMatch({
    required String targetPersonId,
    required List<GraphPerson> persons,
    required List<({String fromId, String toId, String edgeId, String relationshipKey})>
        edges,
    required ProximityGraphNotifier proximityNotifier,
  }) {
    final proximity = proximityNotifier.state;
    if (!proximity.isInitialized) {
      return const <String>{};
    }
    // Already in the visible/proximity set (rendered — possibly behind
    // a collapse chip, which the canvas's protected IDs handle).
    if (proximity.visibleIds.contains(targetPersonId)) {
      _recordRevealedPath(const <String>{});
      return const <String>{};
    }

    final anchorId = proximity.anchorId;
    if (anchorId == null || anchorId == targetPersonId) {
      return const <String>{};
    }

    final allPersonIds = <String>{
      for (final p in persons) p.id,
    };

    // REUSED BFS: shortest relationship path anchor → target.
    final pathSteps = RelationshipEngine.instance.resolvePath(
      viewerPersonId: anchorId,
      targetPersonId: targetPersonId,
      persons: persons,
      relationships: [
        for (final e in edges)
          (fromId: e.fromId, toId: e.toId, type: e.relationshipKey),
      ],
    );

    if (pathSteps == null || pathSteps.isEmpty) {
      // No path from the anchor — reveal the target alone so the
      // search result at least renders and the camera can center on
      // them.
      proximityNotifier.revealPersons(
        personIds: {targetPersonId},
        allPersons: allPersonIds,
      );
      final revealed = <String>{
        if (allPersonIds.contains(targetPersonId)) targetPersonId,
      };
      _recordRevealedPath(revealed);
      return revealed;
    }

    // Reveal ONLY the nodes on the direct path (anchor included for
    // continuity — revealPersons skips already-visible IDs).
    final pathIds = <String>{
      anchorId,
      for (final step in pathSteps) step.personId,
    };
    proximityNotifier.revealPersons(
      personIds: pathIds,
      allPersons: allPersonIds,
    );

    // The target's immediate neighborhood — the same incremental
    // semantics as the existing tap-to-expand, so the jumped-to person
    // is not an isolated dot.
    final adjacency = buildAdjacency(edges);
    proximityNotifier.expandFromPerson(
      personId: targetPersonId,
      adjacency: adjacency,
      allPersons: allPersonIds,
    );

    final revealed = <String>{
      ...pathIds,
      ...?adjacency[targetPersonId],
    };
    revealed.retainAll(allPersonIds);
    _recordRevealedPath(revealed);
    return revealed;
  }

  /// Records [ids] as the current reveal-path protection set.
  void _recordRevealedPath(Set<String> ids) {
    state = state.copyWith(
      revealedPathIds: Set.unmodifiable(ids),
      revision: state.revision + 1,
    );
  }
}

/// Riverpod provider for the graph search subsystem.
///
/// Watch this to get the current `GraphSearchState` (match IDs, current
/// index, active flag). The search bar drives it by calling
/// `ref.read(graphSearchProvider.notifier).setResults(...)`.
final graphSearchProvider =
    StateNotifierProvider<GraphSearchNotifier, GraphSearchState>(
  (ref) => GraphSearchNotifier(),
);
