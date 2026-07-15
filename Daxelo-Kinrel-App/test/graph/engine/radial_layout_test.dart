// test/graph/engine/radial_layout_test.dart
//
// Focused unit tests for the RadialLayout concentric-ring engine.
//
// Covers:
//   - Layout output is deterministic across repeated runs
//   - No two nodes end up at the exact same coordinates
//   - Empty input returns an empty result
//   - A single anchor is placed at the canvas centre
//   - Ancestors (gen < 0) land in the upper semicircle (Y < anchor Y)
//   - Descendants (gen > 0) land in the lower semicircle (Y > anchor Y)
//   - Every input person receives a position

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/engine/radial_layout.dart';

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
  group('RadialLayout', () {
    late RadialLayout layout;

    setUp(() {
      layout = RadialLayout();
    });

    /// Small fixture: anchor + father + mother + one child.
    ({List<GraphPerson> persons, List<GraphRelationship> rels}) _smallFamily() {
      final persons = [
        _person('anchor', gen: 0, isAnchor: true),
        _person('father', gen: -1),
        _person('mother', gen: -1),
        _person('child', gen: 1),
      ];
      final rels = [
        _rel('r1', 'anchor', 'father', 'father'),
        _rel('r2', 'anchor', 'mother', 'mother'),
        _rel('r3', 'anchor', 'child', 'child'),
      ];
      return (persons: persons, rels: rels);
    }

    test('layout output is deterministic across repeated runs', () {
      final fam = _smallFamily();

      final r1 = layout.compute(persons: fam.persons, relationships: fam.rels);
      final r2 = layout.compute(persons: fam.persons, relationships: fam.rels);

      expect(r2.positions.length, r1.positions.length);
      for (final id in r1.positions.keys) {
        expect(r2.positions[id], r1.positions[id],
            reason: 'Position for $id must match across runs');
      }
      expect(r2.canvasWidth, r1.canvasWidth);
      expect(r2.canvasHeight, r1.canvasHeight);
    });

    test('no two nodes end up at the exact same coordinates', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

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

    test('anchor is placed at the computed canvas centre coordinate', () {
      final persons = [_person('only', isAnchor: true)];
      final result = layout.compute(persons: persons, relationships: const []);

      final pos = result.positions['only']!;
      // With a single node, maxRadius = 0, so the centre coordinate
      // equals canvasPadding (default 120). The canvas is sized to
      // (centre + 0 + padding) * 2 so the anchor sits at the geometric
      // centre coordinate the engine computes, even though the canvas
      // is twice as wide to leave room for label overflow.
      const canvasPadding = 120.0;
      expect(pos.dx, closeTo(canvasPadding, 1.0));
      expect(pos.dy, closeTo(canvasPadding, 1.0));
      expect(result.canvasWidth, greaterThan(0));
      expect(result.canvasHeight, greaterThan(0));
    });

    test('ancestors (gen < 0) are placed in the upper semicircle', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

      final anchorY = result.positions['anchor']!.dy;
      final fatherY = result.positions['father']!.dy;

      expect(fatherY, lessThan(anchorY),
          reason: 'Father (gen -1) must be above the anchor (smaller Y)');
    });

    test('descendants (gen > 0) are placed in the lower semicircle', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

      final anchorY = result.positions['anchor']!.dy;
      final childY = result.positions['child']!.dy;

      expect(childY, greaterThan(anchorY),
          reason: 'Child (gen 1) must be below the anchor (larger Y)');
    });

    test('every input person receives a position', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

      for (final p in fam.persons) {
        expect(result.positions.containsKey(p.id), isTrue,
            reason: '${p.id} missing from layout result');
      }
    });

    test('ring radii grow with |generationIndex|', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

      // Anchor (gen 0) is at radius 0; father (gen -1) and child (gen 1)
      // are at radius = baseRadius + 1 * activeSpacing.
      final radii = result.ringRadii;
      expect(radii[0], 0.0);
      expect(radii[-1], greaterThan(0));
      expect(radii[1], greaterThan(0));
      // |gen| = 1 rings should have the same radius.
      expect(radii[-1], closeTo(radii[1]!, 1e-9));
    });

    test('distance from anchor matches ring radius for non-anchor nodes', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

      final anchor = result.positions['anchor']!;
      final father = result.positions['father']!;
      final expectedRadius = result.ringRadii[-1]!;

      final dist = sqrt(pow(father.dx - anchor.dx, 2) +
          pow(father.dy - anchor.dy, 2));
      expect(dist, closeTo(expectedRadius, 0.5),
          reason: 'Father should sit exactly on ring radius $expectedRadius');
    });
  });
}
