// lib/graph/interaction/graph_focus_state.dart
//
// DAXELO KINREL — Person-Centric Focus Mode (Phase 1)
//
// A SEPARATE focus concept from transient selection.
//
//   SELECTION — a temporary interaction target (selectedNodeProvider).
//   FOCUS     — the person currently defining graph context.
//   PATH ENDPOINT — a person selected for relationship-path comparison.
//
// Before this file, focus was OVERLOADED onto selectedNodeProvider.
// This made it impossible to distinguish "user tapped a node to see
// its details" from "user wants the graph to revolve around this
// person." Phase 1 introduces a dedicated focus provider so the two
// concepts can coexist:
//
//   • Tapping a node → selection (shows quick actions, highlights node)
//   • "Focus on person" action → sets focusedPersonProvider (camera
//     centers, unrelated branches dim, focus history pushed)
//
// The focus provider is LOCAL graph interaction state. It does NOT
// modify relationship data, node positions, canonical topology, or
// family membership.

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A snapshot of the camera viewport, saved when focus changes so the
/// user can return to their previous view via focus-history back.
@immutable
class FocusViewportSnapshot {
  const FocusViewportSnapshot({
    required this.panX,
    required this.panY,
    required this.zoom,
  });

  final double panX;
  final double panY;
  final double zoom;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusViewportSnapshot &&
          other.panX == panX &&
          other.panY == panY &&
          other.zoom == zoom;

  @override
  int get hashCode => Object.hash(panX, panY, zoom);

  @override
  String toString() =>
      'FocusViewportSnapshot(pan=$panX,$panY zoom=$zoom)';
}

/// One entry in the focus history stack.
@immutable
class FocusHistoryEntry {
  const FocusHistoryEntry({
    required this.personId,
    required this.personName,
    required this.viewport,
  });

  final String personId;
  final String personName;
  final FocusViewportSnapshot viewport;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FocusHistoryEntry && other.personId == personId;

  @override
  int get hashCode => personId.hashCode;

  @override
  String toString() =>
      'FocusHistoryEntry($personId, $personName, $viewport)';
}

/// P2.1: Path-select mode phases for the "How We're Connected" flow.
///
/// The user taps the FAB → [awaitingFrom] → taps node A → [awaitingTo] →
/// taps node B → [tracing] → path resolves + animates → [complete] →
/// user taps Done → [idle].
enum PathSelectPhase {
  /// Path-select mode is not active. Normal tap behavior.
  idle,

  /// Mode entered; waiting for the user to tap the first node.
  awaitingFrom,

  /// First node selected; waiting for the second node.
  awaitingTo,

  /// Both nodes selected; path is being resolved + animated.
  tracing,

  /// Path trace complete; result bottom sheet is showing.
  complete,
}

/// The state of the focus subsystem.
@immutable
class GraphFocusState {
  const GraphFocusState({
    this.focusedPersonId,
    this.history = const <FocusHistoryEntry>[],
    this.firstDegreeIds = const <String>{},
    this.secondDegreeIds = const <String>{},
    this.revision = 0,
    // P2.1: path-select mode state
    this.pathSelectPhase = PathSelectPhase.idle,
    this.pathSelectFromId,
    this.pathSelectToId,
  });

  /// The person currently defining graph context, or null when no
  /// person is focused (default state).
  final String? focusedPersonId;

  /// Bounded focus history (max 20 entries). The last entry is the
  /// most recent focus. `back()` pops the last entry and restores
  /// its viewport.
  final List<FocusHistoryEntry> history;

  /// First-degree graph neighbours of [focusedPersonId] — persons
  /// directly connected by one relationship edge. Computed when focus
  /// changes, NOT during paint. Kept at full or near-full opacity.
  final Set<String> firstDegreeIds;

  /// Second-degree graph neighbours — persons connected via one
  /// intermediary (neighbour of a neighbour). Modestly reduced
  /// emphasis. Computed when focus changes.
  final Set<String> secondDegreeIds;

  /// Bumped whenever focus or neighbour sets change. Used by the
  /// painter's shouldRepaint to trigger a repaint without deep
  /// comparison.
  final int revision;

  // ── P2.1: Path-select mode ("How We're Connected") ───────────────────

  /// Current phase of the path-select flow. [PathSelectPhase.idle] when
  /// the mode is not active.
  final PathSelectPhase pathSelectPhase;

  /// The first node selected in path-select mode ("from").
  final String? pathSelectFromId;

  /// The second node selected in path-select mode ("to").
  final String? pathSelectToId;

  static const GraphFocusState empty = GraphFocusState();

  GraphFocusState copyWith({
    String? focusedPersonId,
    List<FocusHistoryEntry>? history,
    Set<String>? firstDegreeIds,
    Set<String>? secondDegreeIds,
    int? revision,
    PathSelectPhase? pathSelectPhase,
    String? pathSelectFromId,
    String? pathSelectToId,
  }) {
    return GraphFocusState(
      focusedPersonId: focusedPersonId ?? this.focusedPersonId,
      history: history ?? this.history,
      firstDegreeIds: firstDegreeIds ?? this.firstDegreeIds,
      secondDegreeIds: secondDegreeIds ?? this.secondDegreeIds,
      revision: revision ?? this.revision,
      pathSelectPhase: pathSelectPhase ?? this.pathSelectPhase,
      pathSelectFromId: pathSelectFromId ?? this.pathSelectFromId,
      pathSelectToId: pathSelectToId ?? this.pathSelectToId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphFocusState &&
          other.focusedPersonId == focusedPersonId &&
          other.revision == revision;

  @override
  int get hashCode => Object.hash(focusedPersonId, revision);

  @override
  String toString() =>
      'GraphFocusState(focused=$focusedPersonId, '
      'first=${firstDegreeIds.length}, second=${secondDegreeIds.length}, '
      'history=${history.length}, rev=$revision)';
}

/// StateNotifier that owns the focus state + history + neighbour sets.
///
/// Neighbour sets are computed HERE (not in paint) when focus changes.
/// The caller passes the current edge list so the notifier can do a
/// depth-2 BFS walk without holding a reference to the graph data.
///
/// Focus history is bounded to 20 entries. Switching to another family
/// clears the history + focus entirely via [clearAll].
class GraphFocusNotifier extends StateNotifier<GraphFocusState> {
  GraphFocusNotifier() : super(GraphFocusState.empty);

  static const int _maxHistory = 20;

  /// Focus on [personId]. Pushes the current viewport onto the history
  /// stack so the user can go back.
  ///
  /// [edges] is the current deduped edge list — used to compute
  /// first-degree + second-degree neighbour sets. Pass an empty list
  /// if edges aren't available; neighbour sets will be empty.
  ///
  /// [currentViewport] is the camera viewport to save for later
  /// restore. Pass null if you don't want to save the viewport (e.g.
  /// programmatic focus without a back button).
  void focus({
    required String personId,
    required String personName,
    required List<({String fromId, String toId})> edges,
    FocusViewportSnapshot? currentViewport,
  }) {
    // Compute neighbour sets.
    final neighbours = _computeNeighbours(personId, edges);

    // Push the current viewport onto history (if provided).
    var newHistory = state.history;
    if (currentViewport != null) {
      // If the person is already in history, remove the old entry
      // (avoid duplicates — focusing the same person twice should
      // not stack).
      newHistory = newHistory
          .where((e) => e.personId != personId)
          .toList();
      newHistory = [
        ...newHistory,
        FocusHistoryEntry(
          personId: personId,
          personName: personName,
          viewport: currentViewport,
        ),
      ];
      // Bound to _maxHistory (keep the most recent).
      if (newHistory.length > _maxHistory) {
        newHistory = newHistory.sublist(newHistory.length - _maxHistory);
      }
    }

    state = GraphFocusState(
      focusedPersonId: personId,
      history: newHistory,
      firstDegreeIds: neighbours.first,
      secondDegreeIds: neighbours.second,
      revision: state.revision + 1,
    );
  }

  /// Go back to the previous focused person. Returns the entry to
  /// restore (person + viewport), or null if history is empty.
  ///
  /// The caller is responsible for animating the camera to the
  /// restored viewport — this method only updates the focus state.
  FocusHistoryEntry? back() {
    if (state.history.isEmpty) return null;

    // Pop the last entry.
    final newHistory = List<FocusHistoryEntry>.from(state.history);
    final popped = newHistory.removeLast();

    // If there's a previous entry, focus on it (without pushing again).
    if (newHistory.isNotEmpty) {
      final previous = newHistory.last;
      state = GraphFocusState(
        focusedPersonId: previous.personId,
        history: newHistory,
        firstDegreeIds: const {},
        secondDegreeIds: const {},
        revision: state.revision + 1,
      );
      // The caller should re-compute neighbour sets by calling
      // focus() with the previous person's edges. But for the simple
      // case we just restore the focus ID.
      return previous;
    }

    // No previous entry — clear focus.
    state = GraphFocusState(
      focusedPersonId: null,
      history: newHistory,
      firstDegreeIds: const {},
      secondDegreeIds: const {},
      revision: state.revision + 1,
    );
    return popped;
  }

  /// Clear focus but keep history (e.g. user tapped empty canvas).
  void clearFocus() {
    if (state.focusedPersonId == null) return;
    state = state.copyWith(
      focusedPersonId: null,
      firstDegreeIds: const {},
      secondDegreeIds: const {},
      revision: state.revision + 1,
    );
  }

  /// Clear everything — focus + history. Called when leaving the
  /// family or switching to another family graph.
  void clearAll() {
    if (state == GraphFocusState.empty) return;
    state = GraphFocusState.empty;
  }

  // ── P2.1: Path-select mode ("How We're Connected") ───────────────────

  /// Enter path-select mode. The next node tap selects the "from" node.
  void enterPathSelectMode() {
    state = state.copyWith(
      pathSelectPhase: PathSelectPhase.awaitingFrom,
      pathSelectFromId: null,
      pathSelectToId: null,
    );
  }

  /// Set the "from" node. Transitions to [PathSelectPhase.awaitingTo].
  void setPathSelectFrom(String personId) {
    if (state.pathSelectPhase != PathSelectPhase.awaitingFrom) return;
    state = state.copyWith(
      pathSelectPhase: PathSelectPhase.awaitingTo,
      pathSelectFromId: personId,
    );
  }

  /// Set the "to" node. Transitions to [PathSelectPhase.tracing].
  /// Returns true if the transition was valid (different from "from").
  bool setPathSelectTo(String personId) {
    if (state.pathSelectPhase != PathSelectPhase.awaitingTo) return false;
    // Same node tapped twice — reject.
    if (personId == state.pathSelectFromId) return false;
    state = state.copyWith(
      pathSelectPhase: PathSelectPhase.tracing,
      pathSelectToId: personId,
    );
    return true;
  }

  /// Mark the path trace as complete. The result bottom sheet shows.
  void markPathSelectComplete() {
    if (state.pathSelectPhase != PathSelectPhase.tracing) return;
    state = state.copyWith(pathSelectPhase: PathSelectPhase.complete);
  }

  /// Exit path-select mode entirely. Clears all path-select state.
  void exitPathSelectMode() {
    if (state.pathSelectPhase == PathSelectPhase.idle) return;
    state = state.copyWith(
      pathSelectPhase: PathSelectPhase.idle,
      pathSelectFromId: null,
      pathSelectToId: null,
    );
  }

  /// Recompute neighbour sets for the current focused person. Called
  /// when the graph data changes (e.g. a relationship was added) but
  /// the focus person stays the same.
  ///
  /// v98 (Phase 1): IDEMPOTENT — if the computed neighbour sets are
  /// identical to the current state, returns without mutating state
  /// or bumping revision. This prevents the rebuild-mutate-rebuild
  /// cycle that occurred when the engine view called this every
  /// rebuild while watching the same provider.
  void recomputeNeighbours(List<({String fromId, String toId})> edges) {
    final focused = state.focusedPersonId;
    if (focused == null) return;
    final neighbours = _computeNeighbours(focused, edges);

    // v98: Idempotency check — only mutate if the sets actually changed.
    if (_setEquals(neighbours.first, state.firstDegreeIds) &&
        _setEquals(neighbours.second, state.secondDegreeIds)) {
      return; // No change → no revision bump → no rebuild cycle.
    }

    state = state.copyWith(
      firstDegreeIds: neighbours.first,
      secondDegreeIds: neighbours.second,
      revision: state.revision + 1,
    );
  }

  /// Lightweight set equality (avoids allocating iterators).
  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  /// Compute first-degree and second-degree neighbour sets via a
  /// depth-2 BFS walk. O(E) per degree — cheap, and only runs when
  /// focus changes or graph data changes.
  ///
  /// Returns a [NeighbourSets] (a simple class — NOT a record type,
  /// because dart2js has trouble destructuring named records).
  NeighbourSets _computeNeighbours(
    String personId,
    List<({String fromId, String toId})> edges,
  ) {
    // First degree: directly connected persons.
    final first = <String>{};
    for (final e in edges) {
      if (e.fromId == personId) {
        first.add(e.toId);
      } else if (e.toId == personId) {
        first.add(e.fromId);
      }
    }

    // Second degree: neighbours of first-degree (excluding self +
    // already-first-degree).
    final second = <String>{};
    for (final e in edges) {
      // If one endpoint is a first-degree neighbour, the other is
      // second-degree (unless it's the focus person or already first).
      if (first.contains(e.fromId)) {
        if (e.toId != personId && !first.contains(e.toId)) {
          second.add(e.toId);
        }
      } else if (first.contains(e.toId)) {
        if (e.fromId != personId && !first.contains(e.fromId)) {
          second.add(e.fromId);
        }
      }
    }

    return NeighbourSets(first: first, second: second);
  }
}

/// Simple container for first-degree + second-degree neighbour sets.
///
/// We use a class instead of a record type `({Set<String> first, Set<String> second})`
/// because dart2js has trouble destructuring named records in some
/// contexts. A plain class with field access is 100% dart2js-safe.
class NeighbourSets {
  const NeighbourSets({required this.first, required this.second});
  final Set<String> first;
  final Set<String> second;
}

/// Riverpod provider for the person-centric focus subsystem.
///
/// Watch this to get the current `GraphFocusState` (focused person,
/// neighbour sets, history). The engine view drives focus by calling
/// `ref.read(graphFocusProvider.notifier).focus(...)` from the
/// "Focus on person" action.
final graphFocusProvider =
    StateNotifierProvider<GraphFocusNotifier, GraphFocusState>(
  (ref) => GraphFocusNotifier(),
);
