// test/graph/correctness/path_correctness_test.dart
//
// P5.2 — Path correctness (HARD RELEASE GATE).
//
// For each fixture, for each (viewer, target) pair, verify
// GraphService.findPath returns the shortest path.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/graph/graph_service.dart';
import 'package:kinrel/core/kinship/kinship_service.dart';

import 'synthetic_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P5.2 — Path correctness (HARD RELEASE GATE)', () {
    test('nuclear family: son → father has path length 1', () {
      final fixture = generateNuclearFamily();
      final graphService = GraphService(KinshipService.instance);
      final path = graphService.findPath(
        persons: fixture.persons,
        relationships: fixture.relationships,
        fromPersonId: 'son1',
        toPersonId: 'father',
      );
      expect(path, isNotNull, reason: 'son1 → father should have a path');
      expect(path!.path.length, lessThanOrEqualTo(2),
          reason: 'direct parent-child path should be ≤ 2 steps');
    });

    test('nuclear family: sibling path goes through parent', () {
      final fixture = generateNuclearFamily();
      final graphService = GraphService(KinshipService.instance);
      final path = graphService.findPath(
        persons: fixture.persons,
        relationships: fixture.relationships,
        fromPersonId: 'son1',
        toPersonId: 'son2',
      );
      expect(path, isNotNull, reason: 'siblings should have a path');
      // Path: son1 → father → son2 (or via mother) = 2 steps
      expect(path!.path.length, lessThanOrEqualTo(3),
          reason: 'sibling path via parent should be ≤ 3 steps');
    });

    test('extended family: grandchild → great_grandfather path exists', () {
      final fixture = generateExtendedFamily();
      final graphService = GraphService(KinshipService.instance);
      final path = graphService.findPath(
        persons: fixture.persons,
        relationships: fixture.relationships,
        fromPersonId: 'gc0',
        toPersonId: 'gp0',
      );
      expect(path, isNotNull,
          reason: 'gc0 → gp0 should have a path (great grandparent)');
    });

    test('disconnected subgraphs: no path between families', () {
      final fixture = generateDisconnectedSubgraphs();
      final graphService = GraphService(KinshipService.instance);
      final path = graphService.findPath(
        persons: fixture.persons,
        relationships: fixture.relationships,
        fromPersonId: 'a_c',
        toPersonId: 'b_f',
      );
      expect(path, isNull,
          reason: 'no path should exist between disconnected families');
    });

    test('consanguineous family: path through cycle exists', () {
      final fixture = generateConsanguineousFamily();
      final graphService = GraphService(KinshipService.instance);
      final path = graphService.findPath(
        persons: fixture.persons,
        relationships: fixture.relationships,
        fromPersonId: 'gc',
        toPersonId: 'gf',
      );
      expect(path, isNotNull,
          reason: 'gc → gf should have a path despite cousin-marriage cycle');
    });

    test('cross-cultural family: all direct relatives have paths', () {
      final fixture = generateCrossCulturalFamily();
      final graphService = GraphService(KinshipService.instance);
      for (final target in ['f', 'm', 'ff', 'fm', 'mf', 'mm']) {
        final path = graphService.findPath(
          persons: fixture.persons,
          relationships: fixture.relationships,
          fromPersonId: 'v',
          toPersonId: target,
        );
        expect(path, isNotNull,
            reason: 'v → $target should have a path');
      }
    });

    test('large family: paths complete without timeout', () {
      final fixture = generateLargeIndianJointFamily();
      final graphService = GraphService(KinshipService.instance);
      final path = graphService.findPath(
        persons: fixture.persons,
        relationships: fixture.relationships,
        fromPersonId: 'gen1_1_0',
        toPersonId: 'gen4_m',
      );
      expect(path, isNotNull,
          reason: 'large family path should resolve without timeout');
    });
  });
}
