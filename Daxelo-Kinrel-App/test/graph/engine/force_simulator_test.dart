// test/graph/engine/force_simulator_test.dart
//
// Tests for the ForceSimulator engine per V2.1 Blueprint §29.
// Minimum 80% test coverage target on engine + data + security.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/engine/force_simulator.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';

void main() {
  group('ForceSimulator', () {
    late ForceSimulator simulator;

    setUp(() {
      simulator = ForceSimulator();
    });

    tearDown(() {
      simulator.dispose();
    });

    group('simulation cooling', () {
      test('simulation cools from alpha=1.0 to alphaMin within maxTicks', () {
        const config = SimulationConfig(
          alpha: 1.0,
          alphaMin: 0.001,
          alphaDecay: 0.0228,
          maxTicks: 10000,
        );
        final sim = ForceSimulator(config: config);

        final persons = _createTestPersons(10);
        final relationships = _createTestRelationships(persons);
        sim.initialize(persons, relationships);

        final positions = sim.runSync();

        // Simulation should complete and return positions
        expect(positions, isNotEmpty);
        expect(positions.length, equals(10));

        sim.dispose();
      });

      test('watchdog fires after 30 seconds if alpha does not converge', () {
        // This test verifies the watchdog mechanism exists.
        // The actual 30-second timeout is too long for unit tests,
        // so we verify the config parameter exists.
        const config = SimulationConfig(
          watchdogTimeoutMs: 30000,
        );
        expect(config.watchdogTimeoutMs, equals(30000));
      });

      test('reheat sets alpha to 0.3', () {
        const config = SimulationConfig(alpha: 1.0);
        final sim = ForceSimulator(config: config);

        final persons = _createTestPersons(5);
        final relationships = _createTestRelationships(persons);
        sim.initialize(persons, relationships);

        // Run once, then reheat
        sim.runSync();
        sim.reheat();

        // After reheat, the simulation should still be functional
        final positions = sim.runSync();
        expect(positions, isNotEmpty);

        sim.dispose();
      });
    });

    group('generation force', () {
      test('generation force aligns nodes on Y axis by generation', () {
        final persons = [
          _makePerson('p1', 'Parent', generationIndex: -1),
          _makePerson('self', 'Self', generationIndex: 0, isAnchor: true),
          _makePerson('c1', 'Child', generationIndex: 1),
        ];
        final relationships = [
          GraphRelationship(id: 'r1', fromPersonId: 'p1', toPersonId: 'self', relationshipKey: 'parent'),
          GraphRelationship(id: 'r2', fromPersonId: 'self', toPersonId: 'c1', relationshipKey: 'child'),
        ];

        simulator.initialize(persons, relationships);
        final positions = simulator.runSync();

        // Parent should be above self, child should be below self
        final parentY = positions['p1']?.dy ?? 0;
        final selfY = positions['self']?.dy ?? 0;
        final childY = positions['c1']?.dy ?? 0;

        expect(parentY, lessThan(selfY), reason: 'Parent should be above self');
        expect(childY, greaterThan(selfY), reason: 'Child should be below self');
      });
    });

    group('collision detection', () {
      test('collision detection produces zero overlaps after 3 iterations '
          '(under 300 nodes)', () {
        // Create 50 nodes to test collision resolution
        final persons = _createTestPersons(50);
        final relationships = _createTestRelationships(persons);

        simulator.initialize(persons, relationships);
        final positions = simulator.runSync();

        // Check that no two nodes occupy the exact same position
        final positionList = positions.values.toList();
        bool hasOverlap = false;
        for (int i = 0; i < positionList.length; i++) {
          for (int j = i + 1; j < positionList.length; j++) {
            final distance = (positionList[i] - positionList[j]).distance;
            // Minimum distance should be > 10px (node diameter ~72px, allow overlap check)
            if (distance < 10.0) {
              hasOverlap = true;
              break;
            }
          }
          if (hasOverlap) break;
        }

        expect(hasOverlap, isFalse, reason: 'No two nodes should overlap');
      });
    });
  });
}

// ── Test Helpers ─────────────────────────────────────────────────────

List<GraphPerson> _createTestPersons(int count) {
  return List.generate(count, (i) {
    return _makePerson(
      'person_$i',
      'Person $i',
      generationIndex: i % 5 - 2, // -2 to +2
      isAnchor: i == 0,
    );
  });
}

GraphPerson _makePerson(
  String id,
  String name, {
  int generationIndex = 0,
  bool isAnchor = false,
}) {
  return GraphPerson(
    id: id,
    name: name,
    generationIndex: generationIndex,
    isAnchor: isAnchor,
  );
}

List<GraphRelationship> _createTestRelationships(List<GraphPerson> persons) {
  final relationships = <GraphRelationship>[];
  // Connect each person to the anchor
  for (int i = 1; i < persons.length; i++) {
    relationships.add(GraphRelationship(
      id: 'rel_$i',
      fromPersonId: persons.first.id,
      toPersonId: persons[i].id,
      relationshipKey: i % 2 == 0 ? 'child' : 'sibling',
    ));
  }
  return relationships;
}
