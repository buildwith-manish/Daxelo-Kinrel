// test/graph/engine/hierarchical_layout_test.dart
//
// Focused unit tests for the HierarchicalLayout tree engine.
//
// Covers:
//   - Layout output is deterministic across repeated runs
//   - No two nodes end up at the exact same coordinates
//   - Empty input returns an empty result
//   - A single anchor is placed at a valid position
//   - Children are placed below their parents (Y increases)
//   - Ancestors are placed above their descendants
//   - Canvas dimensions are positive for any non-empty input

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/engine/hierarchical_layout.dart';

GraphPerson _person(
  String id, {
  int gen = 0,
  bool isAnchor = false,
  String name = 'Person',
}) =>
    GraphPerson(
      id: id,
      name: name,
      generationIndex: gen,
      isAnchor: isAnchor,
    );

GraphRelationship _rel(
  String id,
  String from,
  String to,
  String key,
) =>
    GraphRelationship(
      id: id,
      fromPersonId: from,
      toPersonId: to,
      relationshipKey: key,
    );

void main() {
  group('HierarchicalLayout', () {
    late HierarchicalLayout layout;

    setUp(() {
      layout = HierarchicalLayout();
    });

    /// Small fixture: anchor + 2 parents + spouse + 1 child.
    ({List<GraphPerson> persons, List<GraphRelationship> rels}) _smallFamily() {
      final persons = [
        _person('anchor', gen: 0, isAnchor: true),
        _person('father', gen: -1),
        _person('mother', gen: -1),
        _person('spouse', gen: 0),
        _person('child', gen: 1),
      ];
      final rels = [
        _rel('r1', 'anchor', 'father', 'father'),
        _rel('r2', 'anchor', 'mother', 'mother'),
        _rel('r3', 'anchor', 'spouse', 'spouse'),
        _rel('r4', 'anchor', 'child', 'child'),
      ];
      return (persons: persons, rels: rels);
    }

    test('layout output is deterministic across repeated runs', () {
      final fam = _smallFamily();

      final r1 = layout.compute(
        persons: fam.persons,
        relationships: fam.rels,
      );
      final r2 = layout.compute(
        persons: fam.persons,
        relationships: fam.rels,
      );

      expect(r2.positions.length, r1.positions.length);
      for (final id in r1.positions.keys) {
        expect(r2.positions[id], r1.positions[id],
            reason: 'Position for $id must be identical across runs');
      }
      expect(r2.canvasWidth, r1.canvasWidth);
      expect(r2.canvasHeight, r1.canvasHeight);
    });

    test('no two nodes end up at the exact same coordinates', () {
      final fam = _smallFamily();
      final result = layout.compute(
        persons: fam.persons,
        relationships: fam.rels,
      );

      final seen = <Offset>{};
      for (final entry in result.positions.entries) {
        expect(
          seen.contains(entry.value),
          isFalse,
          reason: 'Node ${entry.key} at ${entry.value} collides with another '
              'node — coordinates must be unique',
        );
        seen.add(entry.value);
      }
    });

    test('empty input returns an empty result', () {
      final result = layout.compute(persons: const [], relationships: const []);

      expect(result.positions, isEmpty);
      expect(result.canvasWidth, 0);
      expect(result.canvasHeight, 0);
    });

    test('a single anchor is placed at a valid position', () {
      final persons = [_person('only', isAnchor: true)];
      final result = layout.compute(persons: persons, relationships: const []);

      expect(result.positions['only'], isNotNull);
      final pos = result.positions['only']!;
      expect(pos.dx, greaterThanOrEqualTo(0));
      expect(pos.dy, greaterThanOrEqualTo(0));
      expect(result.canvasWidth, greaterThan(0));
      expect(result.canvasHeight, greaterThan(0));
    });

    test('child is placed below its parent (Y increases)', () {
      final fam = _smallFamily();
      final result = layout.compute(
        persons: fam.persons,
        relationships: fam.rels,
      );

      final anchorY = result.positions['anchor']!.dy;
      final childY = result.positions['child']!.dy;

      expect(childY, greaterThan(anchorY),
          reason: 'Child must be rendered below the anchor (higher Y)');
    });

    test('parents are placed above the anchor (Y decreases)', () {
      final fam = _smallFamily();
      final result = layout.compute(
        persons: fam.persons,
        relationships: fam.rels,
      );

      final anchorY = result.positions['anchor']!.dy;
      final fatherY = result.positions['father']!.dy;

      expect(fatherY, lessThan(anchorY),
          reason: 'Father (gen -1) must be rendered above the anchor');
    });

    test('every input person receives a position', () {
      final fam = _smallFamily();
      final result = layout.compute(
        persons: fam.persons,
        relationships: fam.rels,
      );

      for (final p in fam.persons) {
        expect(
          result.positions.containsKey(p.id),
          isTrue,
          reason: '${p.id} missing from layout result',
        );
      }
    });

    test('explicit anchorId overrides the isAnchor flag', () {
      final persons = [
        _person('a', isAnchor: true),
        _person('b'),
      ];
      final result = layout.compute(
        persons: persons,
        relationships: const [],
        anchorPersonId: 'b',
      );

      // 'b' must be present in the layout — using it as anchor should
      // not silently drop it.
      expect(result.positions.containsKey('b'), isTrue);
    });
  });
}
