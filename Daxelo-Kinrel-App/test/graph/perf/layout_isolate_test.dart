// test/graph/perf/layout_isolate_test.dart
//
// v5.146 (STEP 5): Verifies the RadialLayout runs in an isolate
// (v5.145) and produces correct results. This is the test that
// catches "layout blocks the UI thread on expand" regressions.
//
// Run:  flutter test test/graph/perf/layout_isolate_test.dart

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/engine/radial_layout.dart';

// Mirror of the private _RadialLayoutIsolateInput from
// family_graph_provider.dart. We duplicate it here because the
// original is private. If the original changes, update this to match.
class _TestLayoutInput {
  final List<GraphPerson> persons;
  final List<GraphRelationship> relationships;
  final String anchorPersonId;
  final double ringSpacing;
  final double compactSpacing;
  final double spouseAngularOffset;
  final double canvasPadding;
  final double baseRadius;
  final bool compact;
  final double minAngularGap;

  const _TestLayoutInput({
    required this.persons,
    required this.relationships,
    required this.anchorPersonId,
    required this.ringSpacing,
    required this.compactSpacing,
    required this.spouseAngularOffset,
    required this.canvasPadding,
    required this.baseRadius,
    required this.compact,
    required this.minAngularGap,
  });
}

/// Mirror of the private _radialLayoutIsolateEntry.
GraphLayoutResult _testLayoutIsolateEntry(_TestLayoutInput input) {
  final layout = RadialLayout(
    config: RadialLayoutConfig(
      ringSpacing: input.ringSpacing,
      compactSpacing: input.compactSpacing,
      spouseAngularOffset: input.spouseAngularOffset,
      canvasPadding: input.canvasPadding,
      baseRadius: input.baseRadius,
      compact: input.compact,
      minAngularGap: input.minAngularGap,
    ),
  );
  return layout.compute(
    persons: input.persons,
    relationships: input.relationships,
    anchorPersonId: input.anchorPersonId,
  );
}

void main() {
  group('RadialLayout isolate (Step 5)', () {
    test('isolate produces identical result to sync layout', () async {
      // Build a small family: anchor + 5 children + 2 spouses.
      final persons = <GraphPerson>[
        GraphPerson(id: 'anchor', name: 'Anchor', isAnchor: true),
        GraphPerson(id: 'c1', name: 'Child 1'),
        GraphPerson(id: 'c2', name: 'Child 2'),
        GraphPerson(id: 'c3', name: 'Child 3'),
        GraphPerson(id: 'c4', name: 'Child 4'),
        GraphPerson(id: 'c5', name: 'Child 5'),
        GraphPerson(id: 's1', name: 'Spouse 1'),
        GraphPerson(id: 's2', name: 'Spouse 2'),
      ];
      final relationships = <GraphRelationship>[
        GraphRelationship(
            id: 'r1', fromPersonId: 'anchor', toPersonId: 'c1', relationshipKey: 'child'),
        GraphRelationship(
            id: 'r2', fromPersonId: 'anchor', toPersonId: 'c2', relationshipKey: 'child'),
        GraphRelationship(
            id: 'r3', fromPersonId: 'anchor', toPersonId: 'c3', relationshipKey: 'child'),
        GraphRelationship(
            id: 'r4', fromPersonId: 'anchor', toPersonId: 'c4', relationshipKey: 'child'),
        GraphRelationship(
            id: 'r5', fromPersonId: 'anchor', toPersonId: 'c5', relationshipKey: 'child'),
        GraphRelationship(
            id: 'r6', fromPersonId: 'anchor', toPersonId: 's1', relationshipKey: 'spouse'),
        GraphRelationship(
            id: 'r7', fromPersonId: 'c1', toPersonId: 's2', relationshipKey: 'spouse'),
      ];

      // Sync layout.
      final syncLayout = RadialLayout(
        config: const RadialLayoutConfig(
          ringSpacing: 320.0,
          compactSpacing: 260.0,
          spouseAngularOffset: 90.0,
          canvasPadding: 120.0,
          baseRadius: 280.0,
        ),
      );
      final syncResult = syncLayout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'anchor',
      );

      // Isolate layout.
      final isolateResult = await compute(
        _testLayoutIsolateEntry,
        _TestLayoutInput(
          persons: persons,
          relationships: relationships,
          anchorPersonId: 'anchor',
          ringSpacing: 320.0,
          compactSpacing: 260.0,
          spouseAngularOffset: 90.0,
          canvasPadding: 120.0,
          baseRadius: 280.0,
          compact: false,
          minAngularGap: 0.02,
        ),
      );

      // Results must be identical.
      expect(isolateResult.positions.length, syncResult.positions.length,
          reason: 'Isolate layout should produce the same number of '
              'positions as sync layout.');
      for (final id in syncResult.positions.keys) {
        expect(isolateResult.positions.containsKey(id), isTrue,
            reason: 'Isolate layout missing position for $id.');
        final syncPos = syncResult.positions[id]!;
        final isolatePos = isolateResult.positions[id]!;
        expect((isolatePos.dx - syncPos.dx).abs(), lessThan(0.01),
            reason: 'X position mismatch for $id.');
        expect((isolatePos.dy - syncPos.dy).abs(), lessThan(0.01),
            reason: 'Y position mismatch for $id.');
      }
    });

    test('isolate handles 50-node expand without blocking', () async {
      // Simulate a branch expand to 50 nodes. The isolate should
      // complete without error and return positions for all 50.
      final persons = <GraphPerson>[
        GraphPerson(id: 'anchor', name: 'Anchor', isAnchor: true),
        for (var i = 1; i < 50; i++)
          GraphPerson(id: 'p$i', name: 'Person $i'),
      ];
      final relationships = <GraphRelationship>[
        for (var i = 1; i < 50; i++)
          GraphRelationship(
              id: 'r$i',
              fromPersonId: 'anchor',
              toPersonId: 'p$i',
              relationshipKey: 'child'),
      ];

      final sw = Stopwatch()..start();
      final result = await compute(
        _testLayoutIsolateEntry,
        _TestLayoutInput(
          persons: persons,
          relationships: relationships,
          anchorPersonId: 'anchor',
          ringSpacing: 320.0,
          compactSpacing: 260.0,
          spouseAngularOffset: 90.0,
          canvasPadding: 120.0,
          baseRadius: 280.0,
          compact: false,
          minAngularGap: 0.02,
        ),
      );
      sw.stop();

      expect(result.positions.length, 50,
          reason: 'All 50 nodes should get positions.');
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: '50-node layout in isolate should complete in <500ms. '
              'Got ${sw.elapsedMilliseconds}ms. If this is slow, the '
              'de-overlap O(n²) × 20 iterations is the bottleneck.');
    });

    test('isolate handles empty graph gracefully', () async {
      final result = await compute(
        _testLayoutIsolateEntry,
        _TestLayoutInput(
          persons: <GraphPerson>[],
          relationships: <GraphRelationship>[],
          anchorPersonId: 'none',
          ringSpacing: 320.0,
          compactSpacing: 260.0,
          spouseAngularOffset: 90.0,
          canvasPadding: 120.0,
          baseRadius: 280.0,
          compact: false,
          minAngularGap: 0.02,
        ),
      );

      expect(result.positions, isEmpty);
      expect(result.canvasWidth, 0);
      expect(result.canvasHeight, 0);
    });
  });
}
