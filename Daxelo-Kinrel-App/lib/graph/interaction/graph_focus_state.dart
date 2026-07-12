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

import 'package:flutter/material.dart' show Offset;
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

/// The state of the focus subsystem.
@immutable
class GraphFocusState {
  const GraphFocusState({
    this.focusedPersonId,
    this.history = const <FocusHistoryEntry>[],
    this.firstDegreeIds = const <String>{},
    this.secondDegreeIds = const <String>{},
    this.revision = 0,
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

  static const GraphFocusState empty = GraphFocusState();

  GraphFocusState copyWith({
    String? focusedPersonId,
    List<FocusHistoryEntry>? history,
    Set<String>? firstDegreeIds,
    Set<String>? secondDegreeIds,
    int? revision,
  }) {
    return GraphFocusState(
      focusedPersonId: focusedPersonId ?? this.focusedPersonId,
      history: history ?? this.history,
      firstDegreeIds: firstDegreeIds ?? this.firstDegreeIds,
      secondDegreeIds: secondDegreeIds ?? this.secondDegreeIds,
      revision: revision ?? this.revision,
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
    final (first, second) = _computeNeighbours(personId, edges);

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
      firstDegreeIds: first,
      secondDegreeIds: second,
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

  /// Recompute neighbour sets for the current focused person. Called
  /// when the graph data changes (e.g. a relationship was added) but
  /// the focus person stays the same.
  void recomputeNeighbours(List<({String fromId, String toId})> edges) {
    final focused = state.focusedPersonId;
    if (focused == null) return;
    final (first, second) = _computeNeighbours(focused, edges);
    state = state.copyWith(
      firstDegreeIds: first,
      secondDegreeIds: second,
      revision: state.revision + 1,
    );
  }

  /// Compute first-degree and second-degree neighbour sets via a
  /// depth-2 BFS walk. O(E) per degree — cheap, and only runs when
  /// focus changes or graph data changes.
  ({Set<String> first, Set<String> second}) _computeNeighbours(
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

    return (first: first, second: second);
  }
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
