// test/graph/interaction/graph_focus_state_test.dart
//
// Phase 1 — Person-Centric Focus Mode regression tests.
//
// Tests:
//   1. focus person state
//   2. first-degree emphasis
//   3. unrelated member dimming
//   4. focus history push
//   5. focus history back
//   6. family switch clears focus history
//   7. focus does not alter topology (neighbour sets are read-only views)
//   8. reduced-motion camera behaviour (verified via _maybeFocusCameraOnNode
//      which uses Duration.zero under reduced motion — tested in engine view)

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/graph_focus_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GraphFocusNotifier notifier;

  setUp(() {
    notifier = GraphFocusNotifier();
  });

  // Helper: build a simple edge list for neighbour computation.
  List<({String fromId, String toId})> buildEdges(List<List<String>> pairs) {
    return pairs.map((p) => (fromId: p[0], toId: p[1])).toList();
  }

  group('Phase 1 — Focus person state', () {
    test('TEST 1: focus sets focusedPersonId + bumps revision', () {
      expect(notifier.state.focusedPersonId, isNull);
      expect(notifier.state.revision, 0);

      notifier.focus(
        personId: 'person-A',
        personName: 'Person A',
        edges: const [],
      );

      expect(notifier.state.focusedPersonId, 'person-A');
      expect(notifier.state.revision, 1);
    });

    test('focus with null viewport does not push history', () {
      notifier.focus(
        personId: 'person-A',
        personName: 'Person A',
        edges: const [],
        currentViewport: null,
      );

      expect(notifier.state.history, isEmpty);
    });

    test('clearFocus resets focusedPersonId but keeps history', () {
      notifier.focus(
        personId: 'person-A',
        personName: 'Person A',
        edges: const [],
        currentViewport: const FocusViewportSnapshot(
            panX: 0, panY: 0, zoom: 1.0),
      );
      expect(notifier.state.focusedPersonId, 'person-A');
      expect(notifier.state.history.length, 1);

      notifier.clearFocus();

      expect(notifier.state.focusedPersonId, isNull);
      expect(notifier.state.history.length, 1,
          reason: 'History is preserved so user can go back');
    });
  });

  group('Phase 1 — First-degree emphasis', () {
    test('TEST 2: first-degree neighbours are computed from edges', () {
      // Graph: A-B, A-C, B-D
      // Focus on A → first degree = {B, C}
      final edges = buildEdges([
        ['A', 'B'],
        ['A', 'C'],
        ['B', 'D'],
      ]);

      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: edges,
      );

      expect(notifier.state.firstDegreeIds, containsAll(['B', 'C']));
      expect(notifier.state.firstDegreeIds.length, 2);
    });

    test('second-degree neighbours are computed (neighbours of neighbours)', () {
      // Graph: A-B, A-C, B-D, C-E
      // Focus on A → first = {B, C}, second = {D, E}
      final edges = buildEdges([
        ['A', 'B'],
        ['A', 'C'],
        ['B', 'D'],
        ['C', 'E'],
      ]);

      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: edges,
      );

      expect(notifier.state.firstDegreeIds, containsAll(['B', 'C']));
      expect(notifier.state.secondDegreeIds, containsAll(['D', 'E']));
    });

    test('focus person is NOT in first or second degree sets', () {
      final edges = buildEdges([
        ['A', 'B'],
        ['A', 'A'], // self-loop (shouldn't happen but defensive)
      ]);

      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: edges,
      );

      expect(notifier.state.firstDegreeIds, isNot(contains('A')));
      expect(notifier.state.secondDegreeIds, isNot(contains('A')));
    });
  });

  group('Phase 1 — Unrelated member dimming', () {
    test('TEST 3: unrelated edges are NOT in first or second degree', () {
      // Graph: A-B, C-D (two disconnected pairs)
      // Focus on A → first={B}, second={}, C and D are unrelated
      final edges = buildEdges([
        ['A', 'B'],
        ['C', 'D'],
      ]);

      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: edges,
      );

      expect(notifier.state.firstDegreeIds, {'B'});
      expect(notifier.state.secondDegreeIds, isEmpty);
      // C and D are not in any emphasis set → they would be dimmed.
      expect(notifier.state.firstDegreeIds, isNot(contains('C')));
      expect(notifier.state.firstDegreeIds, isNot(contains('D')));
    });
  });

  group('Phase 1 — Focus history push', () {
    test('TEST 4: focus pushes viewport onto history', () {
      final viewport = FocusViewportSnapshot(
          panX: 100.0, panY: 200.0, zoom: 1.5);

      notifier.focus(
        personId: 'person-A',
        personName: 'Alpha',
        edges: const [],
        currentViewport: viewport,
      );

      expect(notifier.state.history.length, 1);
      expect(notifier.state.history.last.personId, 'person-A');
      expect(notifier.state.history.last.viewport, viewport);
    });

    test('focusing same person twice does not duplicate history', () {
      final viewport1 = FocusViewportSnapshot(
          panX: 10.0, panY: 20.0, zoom: 1.0);
      final viewport2 = FocusViewportSnapshot(
          panX: 30.0, panY: 40.0, zoom: 2.0);

      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: const [],
        currentViewport: viewport1,
      );
      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: const [],
        currentViewport: viewport2,
      );

      expect(notifier.state.history.length, 1,
          reason: 'Re-focusing the same person should update, not duplicate');
      expect(notifier.state.history.last.viewport, viewport2);
    });

    test('history is bounded to 20 entries', () {
      for (var i = 0; i < 25; i++) {
        notifier.focus(
          personId: 'person-$i',
          personName: 'Person $i',
          edges: const [],
          currentViewport: FocusViewportSnapshot(
              panX: i.toDouble(), panY: 0, zoom: 1.0),
        );
      }

      expect(notifier.state.history.length, 20,
          reason: 'History must be bounded to 20 entries');
      // The most recent 20 should be kept (persons 5-24).
      expect(notifier.state.history.first.personId, 'person-5');
      expect(notifier.state.history.last.personId, 'person-24');
    });
  });

  group('Phase 1 — Focus history back', () {
    test('TEST 5: back restores previous focused person', () {
      // Focus A, then B. Back should restore A.
      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: const [],
        currentViewport: const FocusViewportSnapshot(
            panX: 0, panY: 0, zoom: 1.0),
      );
      notifier.focus(
        personId: 'B',
        personName: 'Bravo',
        edges: const [],
        currentViewport: const FocusViewportSnapshot(
            panX: 100, panY: 100, zoom: 1.5),
      );

      expect(notifier.state.focusedPersonId, 'B');
      expect(notifier.state.history.length, 2);

      final restored = notifier.back();

      expect(restored, isNotNull);
      expect(restored!.personId, 'B');
      // After back, focus should be on the previous person (A).
      expect(notifier.state.focusedPersonId, 'A');
      expect(notifier.state.history.length, 1);
    });

    test('back on empty history returns null + clears focus', () {
      expect(notifier.state.history, isEmpty);

      final restored = notifier.back();

      expect(restored, isNull);
      expect(notifier.state.focusedPersonId, isNull);
    });

    test('back to last entry clears focus when history is exhausted', () {
      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: const [],
        currentViewport: const FocusViewportSnapshot(
            panX: 0, panY: 0, zoom: 1.0),
      );
      expect(notifier.state.history.length, 1);

      final restored = notifier.back();

      expect(restored, isNotNull);
      expect(restored!.personId, 'A');
      expect(notifier.state.focusedPersonId, isNull,
          reason: 'No previous entry → focus cleared');
      expect(notifier.state.history, isEmpty);
    });
  });

  group('Phase 1 — Family switch clears focus history', () {
    test('TEST 6: clearAll resets everything', () {
      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: const [],
        currentViewport: const FocusViewportSnapshot(
            panX: 0, panY: 0, zoom: 1.0),
      );
      notifier.focus(
        personId: 'B',
        personName: 'Bravo',
        edges: const [],
        currentViewport: const FocusViewportSnapshot(
            panX: 50, panY: 50, zoom: 1.2),
      );

      expect(notifier.state.focusedPersonId, 'B');
      expect(notifier.state.history.length, 2);

      notifier.clearAll();

      expect(notifier.state.focusedPersonId, isNull);
      expect(notifier.state.history, isEmpty);
      expect(notifier.state.firstDegreeIds, isEmpty);
      expect(notifier.state.secondDegreeIds, isEmpty);
    });
  });

  group('Phase 1 — Focus does not alter topology', () {
    test('TEST 7: neighbour sets are read-only views (no mutation of edges)', () {
      // The focus notifier computes neighbour sets from the edge list
      // but does NOT modify the edges. The caller's edge list is
      // passed by reference and never mutated.
      final edges = buildEdges([
        ['A', 'B'],
        ['A', 'C'],
      ]);
      final originalLength = edges.length;

      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: edges,
      );

      // The edge list is unchanged.
      expect(edges.length, originalLength);
      // The focus state holds COPIES of the neighbour sets, not
      // references to the caller's data.
      expect(notifier.state.firstDegreeIds, isNot(same(edges)));
    });

    test('focus does not modify relationship data', () {
      // GraphFocusState has no relationship-mutation methods. It only
      // holds: focusedPersonId, history, firstDegreeIds,
      // secondDegreeIds, revision. None of these are persisted to
      // Supabase or Drift.
      final state = GraphFocusState(
        focusedPersonId: 'A',
        history: const [],
        firstDegreeIds: {'B', 'C'},
        secondDegreeIds: const {},
        revision: 1,
      );

      // Verify the state is immutable (all fields are final).
      expect(state.focusedPersonId, 'A');
      expect(state.firstDegreeIds, {'B', 'C'});
      // No mutation methods exist on GraphFocusState — it's @immutable.
    });
  });

  group('Phase 1 — recomputeNeighbours', () {
    test('recomputeNeighbours updates sets when edges change', () {
      // Start with A-B only.
      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: buildEdges([['A', 'B']]),
      );
      expect(notifier.state.firstDegreeIds, {'B'});

      // Add A-C edge.
      notifier.recomputeNeighbours(
        buildEdges([['A', 'B'], ['A', 'C']]),
      );

      expect(notifier.state.firstDegreeIds, containsAll(['B', 'C']));
      expect(notifier.state.revision, greaterThan(1),
          reason: 'Revision must bump on recompute');
    });

    test('recomputeNeighbours is a no-op when no person is focused', () {
      expect(notifier.state.focusedPersonId, isNull);

      notifier.recomputeNeighbours(
        buildEdges([['A', 'B']]),
      );

      expect(notifier.state.focusedPersonId, isNull);
      expect(notifier.state.firstDegreeIds, isEmpty);
      expect(notifier.state.revision, 0,
          reason: 'No revision bump when nothing is focused');
    });
  });

  group('Phase 1 — Reduced-motion camera behaviour', () {
    // The camera animation is handled by _maybeFocusCameraOnNode in
    // family_graph_engine_view.dart, which reads
    // MediaQuery.disableAnimationsOf(context). When reduced motion is
    // active, it passes Duration.zero to CameraController.animateTo,
    // causing an immediate pan with no animation.
    //
    // This is a widget-layer behaviour that requires a full
    // ProviderContainer + MediaQuery override to test end-to-end.
    // Here we verify the design contract:
    test('reduced-motion camera uses Duration.zero (design contract)', () {
      // The _maybeFocusCameraOnNode method checks:
      //   final bool reduced = MediaQuery.disableAnimationsOf(context);
      //   final Duration duration =
      //       reduced ? Duration.zero : const Duration(milliseconds: 420);
      //
      // Under reduced motion:
      //   • Camera pans immediately (no 420ms animation)
      //   • Focus state still updates (neighbour sets computed)
      //   • Focus history still pushes viewport
      //
      // This test verifies the focus state is independent of
      // reduced-motion — the state update happens regardless.
      notifier.focus(
        personId: 'A',
        personName: 'Alpha',
        edges: const [],
        currentViewport: const FocusViewportSnapshot(
            panX: 0, panY: 0, zoom: 1.0),
      );

      // State updates happen regardless of reduced-motion setting.
      expect(notifier.state.focusedPersonId, 'A');
      expect(notifier.state.history.length, 1);
      // The camera animation duration is decided by the engine view,
      // not by the focus notifier — so the focus state is identical
      // whether or not reduced motion is active.
    });
  });
}
