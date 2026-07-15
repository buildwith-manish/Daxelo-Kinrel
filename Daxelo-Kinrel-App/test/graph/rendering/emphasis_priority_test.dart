// test/graph/rendering/emphasis_priority_test.dart
//
// Phase 10 — Emphasis Priority Composition tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/rendering/emphasis_priority.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 10 — Emphasis priority', () {
    test('path endpoint > focused > path node > selected > search > immediate > normal > dimmed', () {
      // Verify the priority ordering is correct.
      expect(EmphasisLevel.pathEndpoint.priority, greaterThan(EmphasisLevel.focused.priority));
      expect(EmphasisLevel.focused.priority, greaterThan(EmphasisLevel.pathNode.priority));
      expect(EmphasisLevel.pathNode.priority, greaterThan(EmphasisLevel.selected.priority));
      expect(EmphasisLevel.selected.priority, greaterThan(EmphasisLevel.searchMatch.priority));
      expect(EmphasisLevel.searchMatch.priority, greaterThan(EmphasisLevel.immediateRelative.priority));
      expect(EmphasisLevel.immediateRelative.priority, greaterThan(EmphasisLevel.normal.priority));
      expect(EmphasisLevel.normal.priority, greaterThan(EmphasisLevel.dimmed.priority));
    });

    test('dimmed node gets 0.40 opacity', () {
      final level = computeEmphasisLevel(
        nodeId: 'X',
        focusActive: true,
      );
      expect(level, EmphasisLevel.dimmed);
      expect(level.opacity, 0.40);
    });

    test('focused node gets 1.0 opacity even when search active', () {
      final level = computeEmphasisLevel(
        nodeId: 'A',
        focusedPersonId: 'A',
        searchActive: true,
        focusActive: true,
      );
      expect(level, EmphasisLevel.focused);
      expect(level.opacity, 1.0);
    });

    test('path node is not dimmed when focus is active', () {
      final level = computeEmphasisLevel(
        nodeId: 'P',
        focusedPersonId: 'F',
        pathNodeIds: {'P'},
        focusActive: true,
      );
      expect(level, EmphasisLevel.pathNode);
      expect(level.opacity, 1.0);
    });

    test('search match is not dimmed when search is active', () {
      final level = computeEmphasisLevel(
        nodeId: 'S',
        searchMatchIds: {'S'},
        searchActive: true,
      );
      expect(level, EmphasisLevel.searchMatch);
      expect(level.opacity, 0.95);
    });

    test('normal node when no focus/search active gets 0.80 opacity', () {
      final level = computeEmphasisLevel(
        nodeId: 'X',
        focusActive: false,
        searchActive: false,
      );
      expect(level, EmphasisLevel.normal);
      expect(level.opacity, 0.80);
    });

    test('immediate relative is not dimmed when focus active', () {
      final level = computeEmphasisLevel(
        nodeId: 'R',
        focusedPersonId: 'F',
        firstDegreeIds: {'R'},
        focusActive: true,
      );
      expect(level, EmphasisLevel.immediateRelative);
      expect(level.opacity, 0.90);
    });

    test('selected node wins over search match', () {
      final level = computeEmphasisLevel(
        nodeId: 'A',
        selectedPersonId: 'A',
        searchMatchIds: {'A'},
        searchActive: true,
      );
      expect(level, EmphasisLevel.selected);
      expect(level.opacity, 1.0);
    });

    test('path endpoint wins over all', () {
      final level = computeEmphasisLevel(
        nodeId: 'A',
        focusedPersonId: 'A',
        selectedPersonId: 'A',
        pathNodeIds: {'A'},
        pathEndpointIds: {'A'},
        searchMatchIds: {'A'},
        firstDegreeIds: {'A'},
        searchActive: true,
        focusActive: true,
      );
      expect(level, EmphasisLevel.pathEndpoint);
      expect(level.opacity, 1.0);
    });

    test('no independent opacity multiplication (single level per node)', () {
      // The key invariant: computeEmphasisLevel returns exactly ONE
      // level. The painter applies exactly ONE opacity. There is no
      // stacking or multiplication.
      final level = computeEmphasisLevel(
        nodeId: 'A',
        focusedPersonId: 'A',
        searchMatchIds: {'A'},
        firstDegreeIds: {'A'},
        searchActive: true,
        focusActive: true,
      );
      // focused > searchMatch > immediateRelative → focused wins.
      expect(level, EmphasisLevel.focused);
      // Only ONE opacity value is applied.
      expect(level.opacity, 1.0);
    });
  });
}
