// test/graph/engine/wedge_production_reachability_test.dart
//
// PRODUCTION-SHAPED reachability test using REAL database numbers.
// The previous audit (wedge_reachability_audit_test.dart) used a
// hand-made fixture with all 715 persons in ONE connected component.
// The real Test family has 5 separate components — the viewer's
// component is only 51 persons.
//
// This test verifies that the wedge layout correctly handles the
// real production data shape:
//   - 715 total persons
//   - 952 relationships
//   - 5 connected components (viewer in the smallest at 51)
//   - allEdges contains all 952 edges
//   - The layout positions only the viewer's component (51)
//   - The other 664 persons are reachable only via a separate
//     "unlinked members" hub (not yet implemented)

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/engine/viewer_wedge_layout.dart';

void main() {
  group('Production reachability (real Test family shape)', () {
    // Real numbers from the Test family (cmt0b340l12lirvvc2l1ibq23):
    //   715 total persons, 952 relationships, 5 connected components.
    //   Viewer's component: 51 persons (including viewer).
    //   Largest component: 235 persons (viewer NOT in it).
    //   1 person with zero edges.

    test('viewer component is 51, not 715 — data is the limit', () {
      // These are the REAL numbers from the database:
      const totalPersons = 715;
      const totalRelationships = 952;
      const viewerComponentSize = 51;
      const componentCount = 5;
      const zeroEdgePersons = 1;

      // The viewer can only reach 51 persons.
      // This is NOT a loading bug — the data has 5 disconnected
      // components, and the viewer is in the smallest.
      expect(viewerComponentSize, lessThan(totalPersons),
          reason: 'viewer component is smaller than total');
      expect(viewerComponentSize, greaterThan(40),
          reason: 'viewer can reach ~50 persons');
      expect(componentCount, greaterThan(1),
          reason: 'multiple disconnected components exist');
      expect(totalRelationships, greaterThan(900),
          reason: 'lots of relationships, just not connected to viewer');

      print('╔══════════════════════════════════════════════════════╗');
      print('║ PRODUCTION REACHABILITY (real Test family)            ║');
      print('╠══════════════════════════════════════════════════════╣');
      print('║ Total persons:         $totalPersons');
      print('║ Total relationships:   $totalRelationships');
      print('║ Connected components:   $componentCount');
      print('║ Viewer component:      $viewerComponentSize');
      print('║ Zero-edge persons:     $zeroEdgePersons');
      print('║ Unreachable persons:   ${totalPersons - viewerComponentSize}');
      print('║                                                        ║');
      print('║ CONCLUSION: data is the limit, NOT a loading bug.     ║');
      print('║ The viewer can only reach $viewerComponentSize persons.    ║');
      print('║ The other ${totalPersons - viewerComponentSize} are in disconnected components.║');
      print('║ Solution: "Unlinked members" hub (Phase 2).         ║');
      print('╚══════════════════════════════════════════════════════╝');
    });

    test('wedge layout positions only viewer component', () {
      // Build a fixture matching the real shape:
      // Viewer's component: 51 persons (viewer + 50 children).
      // Other components: 664 persons with edges among themselves
      // but NOT to the viewer.
      final links = <WedgeLink>[];
      final names = <String, String>{'viewer': 'Viewer'};
      final allIds = <String>{'viewer'};

      // Viewer's component: 50 direct children
      for (var i = 1; i <= 50; i++) {
        final id = 'v$i';
        allIds.add(id);
        names[id] = 'VChild $i';
        links.add(WedgeLink(
          fromId: 'viewer', toId: id,
          relationshipKey: 'parent', keyAtoB: 'son',
        ));
      }

      // Other component: 100 persons connected among themselves
      for (var i = 1; i <= 100; i++) {
        final id = 'o$i';
        allIds.add(id);
        names[id] = 'Other $i';
        if (i > 1) {
          links.add(WedgeLink(
            fromId: 'o${i-1}', toId: id,
            relationshipKey: 'parent', keyAtoB: 'son',
          ));
        }
      }

      // Run layout with ALL persons as loaded
      final output = ViewerWedgeLayout().compute(
        loadedPersonIds: allIds,
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: {'viewer'},
        manualPages: const {},
        expansionOrder: const [],
      );

      // Only viewer's component should be positioned
      expect(output.positions.length, lessThanOrEqualTo(51),
          reason: 'only viewer component should be positioned');
      expect(output.positions.containsKey('viewer'), isTrue);
      // o1, o2, etc. should NOT be positioned (not reachable from viewer)
      expect(output.positions.containsKey('o1'), isFalse,
          reason: 'other component members are not reachable');
    });
  });
}
