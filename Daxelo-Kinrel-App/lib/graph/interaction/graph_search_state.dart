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
// This is LOCAL graph interaction state. It does NOT modify
// relationship data, node positions, or canonical topology.

import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The state of the graph search subsystem.
@immutable
class GraphSearchState {
  const GraphSearchState({
    this.query = '',
    this.matchIds = const <String>[],
    this.currentIndex = -1,
    this.isActive = false,
    this.revision = 0,
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

  GraphSearchState copyWith({
    String? query,
    List<String>? matchIds,
    int? currentIndex,
    bool? isActive,
    int? revision,
  }) {
    return GraphSearchState(
      query: query ?? this.query,
      matchIds: matchIds ?? this.matchIds,
      currentIndex: currentIndex ?? this.currentIndex,
      isActive: isActive ?? this.isActive,
      revision: revision ?? this.revision,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphSearchState && other.revision == revision;

  @override
  int get hashCode => revision.hashCode;

  @override
  String toString() =>
      'GraphSearchState(query="$query", matches=${matchIds.length}, '
      'current=$currentIndex, active=$isActive, rev=$revision)';
}

/// StateNotifier that owns the graph search state.
class GraphSearchNotifier extends StateNotifier<GraphSearchState> {
  GraphSearchNotifier() : super(GraphSearchState.empty);

  /// Set the search query + match results. Called by the search bar
  /// when the user types or when filters change.
  ///
  /// [matchIds] is the ordered list of person IDs matching the query,
  /// ranked by relevance (same order as the search result list).
  void setResults(String query, List<String> matchIds) {
    final wasActive = state.isActive;
    final newIsActive = query.trim().isNotEmpty;

    state = GraphSearchState(
      query: query,
      matchIds: List.unmodifiable(matchIds),
      currentIndex: matchIds.isEmpty ? -1 : 0,
      isActive: newIsActive,
      revision: state.revision + 1,
    );

    // If search just became inactive, clear the state entirely.
    if (wasActive && !newIsActive) {
      state = GraphSearchState.empty;
    }
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
  void clear() {
    if (state == GraphSearchState.empty) return;
    state = GraphSearchState.empty;
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
