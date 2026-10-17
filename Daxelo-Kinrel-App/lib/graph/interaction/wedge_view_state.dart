// lib/graph/interaction/wedge_view_state.dart
//
// DAXELO KINREL — Viewer-Centered Wedge View State
//
// Presentation-state companion to ViewerWedgeLayout
// (lib/graph/engine/viewer_wedge_layout.dart). Owns the UI intent that
// the wedge layout needs: which persons are EXPANDED (their children
// shown, paged 8 at a time), the per-person PAGE index advanced by the
// "+N" chips, the root category FILTER (filter chips), the search
// REVEAL target, and the expansion ORDER used by the node budget's
// LRU collapse (the branch opened longest ago collapses first).
//
// This file stores INTENT ONLY — every layout decision is recomputed
// deterministically by ViewerWedgeLayout from this state plus the
// current graph data. No positions live here.

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/kinship/kinship_edge_style.dart'
    show KinshipEdgeCategory;

/// Immutable state for the viewer-centered wedge view.
@immutable
class WedgeViewState {
  const WedgeViewState({
    this.expandedRoots = const <String>{},
    this.pages = const <String, int>{},
    this.expansionOrder = const <String>[],
    this.filter,
    this.revealTarget,
    this.lastActionPersonId,
    this.focusedPersonId,
    this.revision = 0,
  });

  /// Persons whose children are shown (paged). The viewer is ALWAYS
  /// implicitly expanded — never stored here.
  final Set<String> expandedRoots;

  /// User-driven page indexes per person ("+N" chip taps). Page 0 is
  /// the default; missing = page 0.
  final Map<String, int> pages;

  /// Expansion order, OLDEST first — the LRU list for the node budget.
  final List<String> expansionOrder;

  /// Root category filter (filter chips). Null = All.
  final KinshipEdgeCategory? filter;

  /// The search-reveal target whose full path from the viewer must be
  /// expanded and paged into view. Null when no reveal is active.
  final String? revealTarget;

  /// The person most recently expanded / paged (drives the camera
  /// fit-to-branch animation). Null when no action has occurred.
  final String? lastActionPersonId;

  /// The WEDGE tap-focus ("tap an expanded person → focus them; tap
  /// the focused, expanded person → collapse them"). This is the
  /// browsing focus of the wedge view — deliberately SEPARATE from
  /// graphFocusProvider (the isolate-connections focus that dims the
  /// rest of the graph to 18%). The wedge focus never dims anything;
  /// it drives the tap state machine, the camera fit, and the layout's
  /// protected-id set. Null = nobody focused.
  final String? focusedPersonId;

  /// Bumped on every state change.
  final int revision;

  WedgeViewState copyWith({
    Set<String>? expandedRoots,
    Map<String, int>? pages,
    List<String>? expansionOrder,
    Object? filter = _sentinel,
    Object? revealTarget = _sentinel,
    Object? lastActionPersonId = _sentinel,
    Object? focusedPersonId = _sentinel,
    int? revision,
  }) {
    return WedgeViewState(
      expandedRoots: expandedRoots ?? this.expandedRoots,
      pages: pages ?? this.pages,
      expansionOrder: expansionOrder ?? this.expansionOrder,
      filter: identical(filter, _sentinel) ? this.filter : filter as KinshipEdgeCategory?,
      revealTarget: identical(revealTarget, _sentinel)
          ? this.revealTarget
          : revealTarget as String?,
      lastActionPersonId: identical(lastActionPersonId, _sentinel)
          ? this.lastActionPersonId
          : lastActionPersonId as String?,
      focusedPersonId: identical(focusedPersonId, _sentinel)
          ? this.focusedPersonId
          : focusedPersonId as String?,
      revision: revision ?? this.revision,
    );
  }

  static const _sentinel = Object();
}

/// The wedge count-badge rule (pure, for tests): a person shows a
/// "+N" connection-count badge when they are VISIBLE on the canvas,
/// COLLAPSED (not the viewer — the root is always implicitly expanded
/// — and not in the expanded set), and have at least [minCount]
/// connections (1 by default).
bool shouldShowWedgeCountBadge({
  required String personId,
  required String? viewerId,
  required Set<String> expandedRoots,
  required Map<String, int> connectionCounts,
  int minCount = 1,
}) {
  if (personId == viewerId) return false;
  if (expandedRoots.contains(personId)) return false;
  return (connectionCounts[personId] ?? 0) >= minCount;
}

/// StateNotifier for the wedge view intent.
class WedgeViewNotifier extends StateNotifier<WedgeViewState> {
  WedgeViewNotifier() : super(const WedgeViewState());

  /// Marks [personId] expanded (shows page 1 of their children) and
  /// records the expansion for the LRU budget order.
  void expandPerson(String personId) {
    if (personId.isEmpty) return;
    final roots = Set<String>.from(state.expandedRoots);
    final isNew = roots.add(personId);
    final order = List<String>.from(state.expansionOrder);
    if (isNew) {
      order.add(personId);
    } else {
      // Re-expansion refreshes nothing in the order — the LRU age of a
      // branch is when it was FIRST opened. (Deterministic.)
    }
    state = state.copyWith(
      expandedRoots: roots,
      expansionOrder: order,
      lastActionPersonId: personId,
      revision: state.revision + 1,
    );
  }

  /// Focuses [personId] (the wedge tap-focus) and makes them the
  /// camera-fit target — without touching the expansion state. Used
  /// by "tap an expanded person who is not focused → focus them and
  /// fit the camera".
  void focusPerson(String personId) {
    if (personId.isEmpty) return;
    state = state.copyWith(
      focusedPersonId: personId,
      lastActionPersonId: personId,
      revision: state.revision + 1,
    );
  }

  /// Collapses [personId]'s paged children and moves the wedge focus
  /// to [parent] (their layout-tree parent, when known). Used by
  /// "tap the focused, expanded person → collapse them and focus their
  /// parent". The camera fit still centres on the collapsed person's
  /// branch (lastActionPersonId), which includes the parent.
  void collapseAndFocusParent(String personId, String? parent) {
    if (personId.isEmpty) return;
    final roots = Set<String>.from(state.expandedRoots)..remove(personId);
    final order = List<String>.from(state.expansionOrder)..remove(personId);
    final pages = Map<String, int>.from(state.pages)..remove(personId);
    state = state.copyWith(
      expandedRoots: roots,
      expansionOrder: order,
      pages: pages,
      lastActionPersonId: personId,
      focusedPersonId:
          (parent == null || parent.isEmpty || parent == personId)
              ? null
              : parent,
      revision: state.revision + 1,
    );
  }

  /// Collapses [personId]'s children from the view (its descendants that
  /// no other expanded person needs).
  void collapsePerson(String personId) {
    if (personId.isEmpty) return;
    final roots = Set<String>.from(state.expandedRoots)..remove(personId);
    final order = List<String>.from(state.expansionOrder)..remove(personId);
    final pages = Map<String, int>.from(state.pages)..remove(personId);
    state = state.copyWith(
      expandedRoots: roots,
      expansionOrder: order,
      pages: pages,
      lastActionPersonId: personId,
      revision: state.revision + 1,
    );
  }

  /// "+N" chip tap: shows the NEXT page of [personId]'s children and
  /// focuses the hub (the approved-preview "+N" tap: load next 8,
  /// focus the hub, fit the camera — the camera fit rides the
  /// lastActionPersonId/revision this bumps).
  void advancePage(String personId) {
    if (personId.isEmpty) return;
    final pages = Map<String, int>.from(state.pages);
    pages[personId] = (pages[personId] ?? 0) + 1;
    state = state.copyWith(
      pages: pages,
      lastActionPersonId: personId,
      focusedPersonId: personId,
      revision: state.revision + 1,
    );
  }

  /// Filter-chip selection. Selecting a category resets the root's
  /// page back to 1 (page 0) of that category; null = All.
  void setFilter(KinshipEdgeCategory? category, {String? viewerId}) {
    final pages = Map<String, int>.from(state.pages);
    // The root's page is owned by the filter selection.
    if (viewerId != null) pages.remove(viewerId);
    state = state.copyWith(
      filter: category,
      pages: pages,
      revision: state.revision + 1,
    );
  }

  /// Search reveal: force-shows [personId] plus its full path from the
  /// viewer (the layout pages each ancestor onto the page containing
  /// the path child). Also resets the owning hub filter to All.
  void revealPerson(String personId, {String? viewerId}) {
    final pages = Map<String, int>.from(state.pages);
    if (viewerId != null) pages.remove(viewerId);
    state = state.copyWith(
      revealTarget: personId,
      filter: null,
      pages: pages,
      lastActionPersonId: personId,
      revision: state.revision + 1,
    );
  }

  /// Clears the reveal target (e.g. the user pans away or closes focus).
  void clearReveal() {
    if (state.revealTarget == null) return;
    state = state.copyWith(
      revealTarget: null,
      revision: state.revision + 1,
    );
  }

  /// Full reset (family switch / graph reopen).
  void reset() {
    state = WedgeViewState(revision: state.revision + 1);
  }
}

/// The wedge view intent provider. Watched by graphLayoutProvider —
/// any change recomputes the wedge layout.
final wedgeViewProvider =
    StateNotifierProvider<WedgeViewNotifier, WedgeViewState>(
  (ref) => WedgeViewNotifier(),
);
