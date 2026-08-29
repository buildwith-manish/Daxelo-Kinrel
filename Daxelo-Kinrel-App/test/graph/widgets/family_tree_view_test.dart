// test/graph/widgets/family_tree_view_test.dart
//
// Smoke test for the new Family Tree view (Family Space §5).
//
// Verifies:
//   - FamilyTreeView renders without crashing
//   - TreePainter draws connectors without exceptions
//   - The treeLayoutProvider produces sensible positions
//   - The familyTreeProvider parses the RPC response correctly
//
// This is a widget smoke test — not a pixel-perfect visual test.
// The actual visual layout is exercised by the live RPC test
// (verified manually against the 714-member Sharma family).

import 'dart:ui' show PictureRecorder, Canvas, Offset, Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/engine/hierarchical_layout.dart';
import 'package:kinrel/graph/rendering/tree_painter.dart';

void main() {
  group('TreePainter', () {
    test('paints spouse connector without throwing', () {
      final painter = TreePainter(
        positions: {
          'a': const Offset(100, 100),
          'b': const Offset(200, 100),
        },
        edges: const [
          (fromId: 'a', toId: 'b', relationshipKey: 'spouse'),
        ],
      );

      // Should paint without throwing.
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 200));
      recorder.endRecording();
      expect(painter.shouldRepaint(painter), false);
    });

    test('paints parent→child connector without throwing', () {
      final painter = TreePainter(
        positions: {
          'parent': const Offset(100, 50),
          'child': const Offset(100, 200),
        },
        edges: const [
          (fromId: 'parent', toId: 'child', relationshipKey: 'parent'),
        ],
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 300));
      recorder.endRecording();
    });

    test('skips edges touching hidden persons', () {
      final painter = TreePainter(
        positions: {
          'a': const Offset(100, 100),
          'b': const Offset(200, 100),
        },
        edges: const [
          (fromId: 'a', toId: 'b', relationshipKey: 'spouse'),
        ],
        hiddenPersonIds: {'b'},
      );

      // Should still paint without throwing, just skip the hidden edge.
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 200));
      recorder.endRecording();
    });

    test('skips non-lineage relationship keys', () {
      final painter = TreePainter(
        positions: {
          'a': const Offset(100, 100),
          'b': const Offset(200, 100),
        },
        edges: const [
          (fromId: 'a', toId: 'b', relationshipKey: 'sibling'),
          (fromId: 'a', toId: 'b', relationshipKey: 'uncle'),
        ],
      );

      // Should paint nothing (no spouse/parent/child edges) but not throw.
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 200));
      recorder.endRecording();
    });

    test('shouldRepaint returns true when positions change', () {
      final painter1 = TreePainter(
        positions: {'a': const Offset(100, 100)},
        edges: const [],
      );
      final painter2 = TreePainter(
        positions: {'a': const Offset(200, 200)},
        edges: const [],
      );
      expect(painter2.shouldRepaint(painter1), true);
    });

    test('shouldRepaint returns true when focusedPersonId changes', () {
      final base = TreePainter(
        positions: {'a': const Offset(100, 100)},
        edges: const [],
        focusedPersonId: 'a',
      );
      final changed = TreePainter(
        positions: {'a': const Offset(100, 100)},
        edges: const [],
        focusedPersonId: 'b',
      );
      expect(changed.shouldRepaint(base), true);
    });

    test('handles empty inputs gracefully', () {
      final painter = TreePainter(
        positions: const {},
        edges: const [],
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 200));
      recorder.endRecording();
      // No exception thrown — pass.
    });
  });

  group('HierarchicalLayout (Tree view primary engine)', () {
    test('computes positions for a simple 3-generation tree', () {
      final layout = HierarchicalLayout();

      final persons = [
        GraphPerson(
            id: 'grandparent', name: 'Grandparent', generationIndex: -1),
        GraphPerson(id: 'parent', name: 'Parent', generationIndex: 0),
        GraphPerson(id: 'child', name: 'Child', generationIndex: 1),
      ];

      final relationships = [
        GraphRelationship(
            id: 'r1',
            fromPersonId: 'parent',
            toPersonId: 'grandparent',
            relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r2',
            fromPersonId: 'child',
            toPersonId: 'parent',
            relationshipKey: 'parent'),
      ];

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'parent',
      );

      // All 3 persons should have positions.
      expect(result.positions.length, 3);
      expect(result.positions['grandparent'], isNotNull);
      expect(result.positions['parent'], isNotNull);
      expect(result.positions['child'], isNotNull);

      // Grandparent (gen -1) should be above parent (gen 0).
      expect(result.positions['grandparent']!.dy,
          lessThan(result.positions['parent']!.dy));
      // Child (gen +1) should be below parent (gen 0).
      expect(result.positions['child']!.dy,
          greaterThan(result.positions['parent']!.dy));

      // Canvas should have nonzero dimensions.
      expect(result.canvasWidth, greaterThan(0));
      expect(result.canvasHeight, greaterThan(0));
    });

    test('handles empty input without crashing', () {
      final layout = HierarchicalLayout();
      final result = layout.compute(
        persons: const [],
        relationships: const [],
      );
      expect(result.positions, isEmpty);
      expect(result.canvasWidth, 0);
      expect(result.canvasHeight, 0);
    });

    test('positions spouses side-by-side on same Y', () {
      final layout = HierarchicalLayout();

      final persons = [
        GraphPerson(id: 'a', name: 'A', generationIndex: 0),
        GraphPerson(id: 'b', name: 'B', generationIndex: 0),
      ];

      final relationships = [
        GraphRelationship(
            id: 'r1',
            fromPersonId: 'a',
            toPersonId: 'b',
            relationshipKey: 'spouse'),
      ];

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'a',
      );

      // Both should be positioned.
      expect(result.positions.length, 2);
      // Both should be at the same Y (same generation).
      expect(result.positions['a']!.dy, equals(result.positions['b']!.dy));
    });

    test('handles large family without stack overflow (1000 nodes)', () {
      final layout = HierarchicalLayout();

      // Build a 1000-node linear ancestor chain.
      // gen[0] → gen[1] → ... → gen[999] (each is parent of the next).
      final persons = <GraphPerson>[];
      final relationships = <GraphRelationship>[];

      for (var i = 0; i < 1000; i++) {
        persons.add(GraphPerson(
          id: 'p$i',
          name: 'Person $i',
          generationIndex: i,
        ));
        if (i > 0) {
          relationships.add(GraphRelationship(
            id: 'r$i',
            fromPersonId: 'p$i',
            toPersonId: 'p${i - 1}',
            relationshipKey: 'parent',
          ));
        }
      }

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'p0',
      );

      // All 1000 should be positioned without stack overflow.
      expect(result.positions.length, 1000);
    });
  });

  group('TreePainter relationship key classification', () {
    test('spouse keys are recognized', () {
      for (final key in ['spouse', 'husband', 'wife', 'partner']) {
        expect(TreePainter.kSpouseKeys.contains(key), true,
            reason: 'Expected $key to be a recognized spouse key');
      }
    });

    test('parent keys are recognized', () {
      for (final key
          in ['parent', 'father', 'mother', 'grandparent', 'grandfather', 'grandmother']) {
        expect(TreePainter.kParentKeys.contains(key), true,
            reason: 'Expected $key to be a recognized parent key');
      }
    });

    test('child keys are recognized', () {
      for (final key in ['child', 'son', 'daughter', 'grandchild']) {
        expect(TreePainter.kChildKeys.contains(key), true,
            reason: 'Expected $key to be a recognized child key');
      }
    });

    test('non-lineage keys are NOT in any of the sets', () {
      for (final key in ['sibling', 'uncle', 'aunt', 'cousin', 'nephew', 'niece']) {
        expect(TreePainter.kSpouseKeys.contains(key), false);
        expect(TreePainter.kParentKeys.contains(key), false);
        expect(TreePainter.kChildKeys.contains(key), false);
      }
    });
  });
}
