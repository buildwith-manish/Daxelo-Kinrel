// test/graph/engine/radial_layout_stability_test.dart
//
// DAXELO KINREL — v5.161 ACCEPTANCE TEST
//
// Verifies the user's cluttered-graph-layout fix:
//
//   1. preservePositions: when true, the de-overlap pass NEVER moves a
//      previously-placed node — only newly-added nodes get pushed.
//      This is the "expand only the local area, don't reposition
//      everything" requirement.
//   2. Minimum spacing: every pair of nodes is at least 132dp apart
//      (72dp diameter + 60dp label padding) so nodes/labels never
//      overlap, regardless of family size.
//   3. Auto-grow canvas: as node count increases, the canvas grows
//      (more padding) so density stays consistent.
//   4. Anchor pinning: the anchor is always at the canvas center,
//      never moved by any pass.

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
  group('v5.161 — RadialLayout stability', () {
    test(
        'CRITERION 1: preservePositions=true keeps previously-placed '
        'nodes at their original positions when new nodes are added',
        () {
      // Initial layout: anchor + 2 children.
      final persons1 = [
        _person('anchor', gen: 0, isAnchor: true),
        _person('c1', gen: 1, name: 'Child 1'),
        _person('c2', gen: 1, name: 'Child 2'),
      ];
      final rels1 = [
        _rel('r1', 'c1', 'anchor', 'parent'),
        _rel('r2', 'c2', 'anchor', 'parent'),
      ];

      final layout = RadialLayout();
      final result1 = layout.compute(
        persons: persons1,
        relationships: rels1,
        anchorPersonId: 'anchor',
      );

      // Capture the initial positions of c1 and c2.
      final c1Pos = result1.positions['c1']!;
      final c2Pos = result1.positions['c2']!;
      expect(c1Pos, isNot(equals(Offset.zero)));
      expect(c2Pos, isNot(equals(Offset.zero)));

      // Now add 3 MORE children — this should NOT move c1 or c2.
      final persons2 = [
        ...persons1,
        _person('c3', gen: 1, name: 'Child 3'),
        _person('c4', gen: 1, name: 'Child 4'),
        _person('c5', gen: 1, name: 'Child 5'),
      ];
      final rels2 = [
        ...rels1,
        _rel('r3', 'c3', 'anchor', 'parent'),
        _rel('r4', 'c4', 'anchor', 'parent'),
        _rel('r5', 'c5', 'anchor', 'parent'),
      ];

      final result2 = layout.compute(
        persons: persons2,
        relationships: rels2,
        anchorPersonId: 'anchor',
        preservePositions: true,
        previousPositions: result1.positions,
      );

      // c1 and c2 MUST be at their previous positions (translated
      // relative to the anchor, which doesn't move in this test —
      // the canvas center is computed from ring radii which don't
      // change because all children are on gen 1).
      expect(result2.positions['c1'], equals(c1Pos),
          reason: 'c1 must NOT move when new siblings are added '
              '(preservePositions=true).');
      expect(result2.positions['c2'], equals(c2Pos),
          reason: 'c2 must NOT move when new siblings are added.');

      // The new children must be placed (not at zero).
      for (final id in ['c3', 'c4', 'c5']) {
        expect(result2.positions[id], isNotNull);
        expect(result2.positions[id]!, isNot(equals(Offset.zero)));
      }
    });

    test(
        'CRITERION 2: minimum spacing — every pair of nodes is at least '
        '132dp apart (so labels never overlap)',
        () {
      // Build a 30-node graph: anchor + 29 children on gen 1.
      final persons = <GraphPerson>[
        _person('anchor', gen: 0, isAnchor: true),
        for (var i = 1; i <= 29; i++)
          _person('c$i', gen: 1, name: 'Child $i'),
      ];
      final rels = <GraphRelationship>[
        for (var i = 1; i <= 29; i++)
          _rel('r$i', 'c$i', 'anchor', 'parent'),
      ];

      final layout = RadialLayout();
      final result = layout.compute(
        persons: persons,
        relationships: rels,
        anchorPersonId: 'anchor',
      );

      // Check EVERY pair of nodes — minimum distance must be ≥ 132.
      const minDistance = 132.0;
      final ids = result.positions.keys.toList();
      var minFound = double.infinity;
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final a = result.positions[ids[i]]!;
          final b = result.positions[ids[j]]!;
          final dx = b.dx - a.dx;
          final dy = b.dy - a.dy;
          final dist = sqrt(dx * dx + dy * dy);
          if (dist < minFound) minFound = dist;
        }
      }
      expect(minFound, greaterThanOrEqualTo(minDistance),
          reason: 'Every pair of nodes must be at least $minDistance dp '
              'apart so labels never overlap. Found min=$minFound.');
    });

    test(
        'CRITERION 3: auto-grow canvas — node count growth increases '
        'canvas dimensions (more breathing room)',
        () {
      // Small graph: anchor + 10 children.
      final smallPersons = <GraphPerson>[
        _person('anchor', gen: 0, isAnchor: true),
        for (var i = 1; i <= 10; i++) _person('c$i', gen: 1),
      ];
      final smallRels = <GraphRelationship>[
        for (var i = 1; i <= 10; i++) _rel('r$i', 'c$i', 'anchor', 'parent'),
      ];

      // Large graph: anchor + 100 children.
      final largePersons = <GraphPerson>[
        _person('anchor', gen: 0, isAnchor: true),
        for (var i = 1; i <= 100; i++) _person('c$i', gen: 1),
      ];
      final largeRels = <GraphRelationship>[
        for (var i = 1; i <= 100; i++) _rel('r$i', 'c$i', 'anchor', 'parent'),
      ];

      final layout = RadialLayout();
      final smallResult = layout.compute(
        persons: smallPersons,
        relationships: smallRels,
        anchorPersonId: 'anchor',
      );
      final largeResult = layout.compute(
        persons: largePersons,
        relationships: largeRels,
        anchorPersonId: 'anchor',
      );

      // The large graph's canvas MUST be larger than the small graph's
      // (more padding = more breathing room per the user's spec).
      expect(largeResult.canvasWidth, greaterThan(smallResult.canvasWidth),
          reason: 'Canvas must auto-grow as nodes are added so density '
              'stays consistent.');
      expect(largeResult.canvasHeight, greaterThan(smallResult.canvasHeight),
          reason: 'Canvas must auto-grow as nodes are added.');
    });

    test(
        'CRITERION 4: anchor pinning — the anchor is always at the canvas '
        'center (relative to the ring radii), never moved by any pass',
        () {
      final persons = <GraphPerson>[
        _person('anchor', gen: 0, isAnchor: true),
        for (var i = 1; i <= 20; i++) _person('c$i', gen: 1),
      ];
      final rels = <GraphRelationship>[
        for (var i = 1; i <= 20; i++) _rel('r$i', 'c$i', 'anchor', 'parent'),
      ];

      final layout = RadialLayout();
      final result = layout.compute(
        persons: persons,
        relationships: rels,
        anchorPersonId: 'anchor',
      );

      final anchorPos = result.positions['anchor']!;
      // The anchor is placed at the original center computed from
      // ringRadii + base canvasPadding. The canvas may grow beyond
      // this (auto-grow padding), but the anchor stays at a STABLE
      // position relative to the rings — it is NOT moved by the
      // de-overlap pass or any other pass.
      //
      // Verify: anchor position equals (maxRingRadius + canvasPadding,
      // maxRingRadius + canvasPadding) — the geometric center of the
      // concentric ring system.
      final maxRingRadius = result.ringRadii.values.fold(0.0, max);
      const canvasPadding = 120.0; // default RadialLayoutConfig.canvasPadding
      final expectedCenter = maxRingRadius + canvasPadding;
      expect((anchorPos.dx - expectedCenter).abs(), lessThan(1.0),
          reason: 'Anchor X must be at the geometric center of the rings, '
              'not moved by any layout pass.');
      expect((anchorPos.dy - expectedCenter).abs(), lessThan(1.0),
          reason: 'Anchor Y must be at the geometric center of the rings.');
    });

    test(
        'CRITERION 5: when preservePositions=true and the SAME graph is '
        'recomputed, every position is identical (idempotent)',
        () {
      final persons = <GraphPerson>[
        _person('anchor', gen: 0, isAnchor: true),
        for (var i = 1; i <= 10; i++) _person('c$i', gen: 1),
      ];
      final rels = <GraphRelationship>[
        for (var i = 1; i <= 10; i++) _rel('r$i', 'c$i', 'anchor', 'parent'),
      ];

      final layout = RadialLayout();
      final result1 = layout.compute(
        persons: persons,
        relationships: rels,
        anchorPersonId: 'anchor',
      );
      final result2 = layout.compute(
        persons: persons,
        relationships: rels,
        anchorPersonId: 'anchor',
        preservePositions: true,
        previousPositions: result1.positions,
      );

      // Every node's position must be identical (the previous positions
      // are translated relative to the anchor, which doesn't move).
      for (final id in result1.positions.keys) {
        expect(result2.positions[id], equals(result1.positions[id]),
            reason: 'Recomputing the SAME graph with preservePositions '
                'must yield identical positions for $id.');
      }
    });
  });
}
