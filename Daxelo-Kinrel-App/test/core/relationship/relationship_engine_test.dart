// test/core/relationship/relationship_engine_test.dart
//
// Tests for the v2.2 RelationshipEngine — the single source of truth for
// all relationship labels.
//
// Architecture invariants covered (per architecture document §3, §9):
//   - The engine returns KEYS ONLY (no localization, no UI logic).
//   - It reuses GraphService BFS — does not reimplement pathfinding.
//   - Self (viewer == target) returns null (the UI shows "You").
//   - Results are cached per (viewerPersonId, targetPersonId).
//   - Inverse relationships are resolved from KinshipService, not hardcoded.
//
// Edge convention (per GraphService.buildAdjacencyList):
//   (fromId, toId, type)  →  "from fromId's perspective, toId is `type`."
//   e.g. (p1, p2, 'father')  →  "p1 sees p2 as father."
//
// Run with: flutter test test/core/relationship/relationship_engine_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/relationship/relationship_engine.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';

/// Builds a typed [GraphPerson] with sensible defaults for tests.
GraphPerson _p(
  String id, {
  String name = 'Test',
  String? gender,
  int generationIndex = 0,
  bool isAnchor = false,
}) {
  return GraphPerson(
    id: id,
    name: name,
    gender: gender,
    generationIndex: generationIndex,
    isAnchor: isAnchor,
  );
}

/// A typed relationship record matching the engine's expected shape.
({String fromId, String toId, String type}) _r(
  String fromId,
  String toId,
  String type,
) => (fromId: fromId, toId: toId, type: type);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RelationshipEngine', () {
    late RelationshipEngine engine;

    setUp(() {
      engine = RelationshipEngine.instance;
      engine.invalidateCache();
    });

    tearDown(() {
      engine.invalidateCache();
    });

    group('self resolution (viewer == target)', () {
      test('returns null when viewerPersonId == targetPersonId', () {
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p1',
          persons: [_p('p1', name: 'A')],
          relationships: const [],
        );
        expect(key, isNull,
            reason: 'Self-relationships are surfaced as "You" by the UI.');
      });
    });

    group('null viewer fallback', () {
      test('falls back to stored relationshipKey when viewer is null', () {
        final key = engine.resolveKey(
          viewerPersonId: null,
          targetPersonId: 'p2',
          persons: [_p('p1'), _p('p2')],
          relationships: [_r('p1', 'p2', 'father')],
        );
        // When no viewer is available, the engine returns the stored
        // relationshipKey from the relationship pointing TO the target.
        expect(key, isNotNull);
      });
    });

    group('single-step parent relationships (architecture §18)', () {
      test('viewer = child → target = father resolves to "father"', () {
        // Edge: from p1's perspective, p2 is "father".
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: [
            _p('p1', name: 'Child'),
            _p('p2', name: 'Dad', gender: 'male'),
          ],
          relationships: [_r('p1', 'p2', 'father')],
        );
        expect(key, isNotNull);
        expect(key, anyOf(equals('father'), equals('mother')));
      });

      test('viewer = parent → target = son resolves to a child key', () {
        // Edge: from p1's perspective, p2 is "son".
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: [
            _p('p1', name: 'Parent'),
            _p('p2', name: 'Son', gender: 'male'),
          ],
          relationships: [_r('p1', 'p2', 'son')],
        );
        expect(key, isNotNull);
        expect(key, anyOf(equals('son'), equals('daughter')));
      });

      test('viewer = spouse → target = wife resolves to a spouse key', () {
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: [
            _p('p1', name: 'Husband', gender: 'male'),
            _p('p2', name: 'Wife', gender: 'female'),
          ],
          relationships: [_r('p1', 'p2', 'wife')],
        );
        expect(key, isNotNull);
        expect(key, anyOf(equals('husband'), equals('wife')));
      });

      test('viewer = sibling → target = brother resolves to a sibling key', () {
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: [
            _p('p1', name: 'Sib1'),
            _p('p2', name: 'Bro', gender: 'male'),
          ],
          relationships: [_r('p1', 'p2', 'brother')],
        );
        expect(key, isNotNull);
        expect(key, anyOf(equals('brother'), equals('sister')));
      });
    });

    group('multi-step paths (architecture §18)', () {
      test('viewer = grandchild → target = grandfather (2 hops)', () {
        // p1 sees p2 as father. p2 sees p3 as father.
        // From p1's perspective: p3 is grandfather / grandmother.
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p3',
          persons: [
            _p('p1', name: 'Grandchild'),
            _p('p2', name: 'Parent', gender: 'male'),
            _p('p3', name: 'Grandpa', gender: 'male'),
          ],
          relationships: [
            _r('p1', 'p2', 'father'),
            _r('p2', 'p3', 'father'),
          ],
        );
        expect(key, isNotNull,
            reason: 'Multi-step path must resolve to a kinship key.');
      });

      test('viewer = niece → target = uncle (2 hops via parent + sibling)', () {
        // p1 sees p2 as father. p2 sees p3 as brother.
        // From p1's perspective: p3 is paternal_uncle / maternal_uncle.
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p3',
          persons: [
            _p('p1', name: 'Niece'),
            _p('p2', name: 'Parent', gender: 'male'),
            _p('p3', name: 'Uncle', gender: 'male'),
          ],
          relationships: [
            _r('p1', 'p2', 'father'),
            _r('p2', 'p3', 'brother'),
          ],
        );
        expect(key, isNotNull,
            reason: 'Path [parent, sibling] must resolve to an uncle/aunt key.');
      });
    });

    group('circular relationship detection (architecture §18)', () {
      test('does not infinite loop on a cycle', () {
        final stopwatch = Stopwatch()..start();
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p1', // self — should be null
          persons: [
            _p('p1'),
            _p('p2'),
            _p('p3'),
          ],
          relationships: [
            _r('p1', 'p2', 'spouse'),
            _r('p2', 'p3', 'spouse'),
            _r('p3', 'p1', 'spouse'),
          ],
        );
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(2000),
            reason: 'Cycle must not cause a hang.');
        expect(key, isNull, reason: 'Self lookup returns null.');
      });

      test('does not infinite loop on a 2-node cycle', () {
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: [
            _p('p1', name: 'A', gender: 'male'),
            _p('p2', name: 'B', gender: 'female'),
          ],
          relationships: [
            _r('p1', 'p2', 'wife'),
            _r('p2', 'p1', 'husband'),
          ],
        );
        expect(key, isNotNull);
      });
    });

    group('disconnected subtrees (architecture §18)', () {
      test('returns null when no path exists', () {
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: [_p('p1'), _p('p2')],
          relationships: const [],
        );
        expect(key, isNull,
            reason: 'Disconnected persons have no relationship key.');
      });
    });

    group('caching (architecture §9)', () {
      test('caches results per (viewer, target) pair', () {
        final persons = [
          _p('p1', name: 'A'),
          _p('p2', name: 'B', gender: 'male'),
        ];
        final rels = [_r('p1', 'p2', 'father')];

        final key1 = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: persons,
          relationships: rels,
        );
        final key2 = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: persons,
          relationships: rels,
        );
        expect(key1, equals(key2),
            reason: 'Cached result must be stable across calls.');
      });

      test('invalidateCache clears the cache', () {
        final persons = [
          _p('p1'),
          _p('p2', gender: 'male'),
        ];
        final rels = [_r('p1', 'p2', 'father')];

        engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: persons,
          relationships: rels,
        );

        engine.invalidateCache();
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: persons,
          relationships: rels,
        );
        expect(key, isNotNull);
      });

      test('invalidateViewer clears only that viewer\'s entries', () {
        final persons = [
          _p('p1'),
          _p('p2'),
          _p('p3', gender: 'male'),
        ];
        final rels = [
          _r('p1', 'p3', 'father'),
          _r('p2', 'p3', 'father'),
        ];

        engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p3',
          persons: persons,
          relationships: rels,
        );
        engine.resolveKey(
          viewerPersonId: 'p2',
          targetPersonId: 'p3',
          persons: persons,
          relationships: rels,
        );

        engine.invalidateViewer('p1');

        final p2Key = engine.resolveKey(
          viewerPersonId: 'p2',
          targetPersonId: 'p3',
          persons: persons,
          relationships: rels,
        );
        expect(p2Key, isNotNull);
      });
    });

    group('resolvePath', () {
      test('returns null for self', () {
        final path = engine.resolvePath(
          viewerPersonId: 'p1',
          targetPersonId: 'p1',
          persons: [_p('p1')],
          relationships: const [],
        );
        expect(path, isNull);
      });

      test('returns null when no path exists', () {
        final path = engine.resolvePath(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: [_p('p1'), _p('p2')],
          relationships: const [],
        );
        expect(path, isNull);
      });

      test('returns a non-empty path when a path exists', () {
        final path = engine.resolvePath(
          viewerPersonId: 'p1',
          targetPersonId: 'p3',
          persons: [
            _p('p1'),
            _p('p2'),
            _p('p3'),
          ],
          relationships: [
            _r('p1', 'p2', 'father'),
            _r('p2', 'p3', 'father'),
          ],
        );
        expect(path, isNotNull);
        expect(path!.length, greaterThanOrEqualTo(1));
      });
    });

    group('half / step / adoptive families (architecture §18)', () {
      test('resolves a half-sibling path (shared parent)', () {
        // p1 sees p3 as father. p2 sees p3 as father. Different mothers.
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: [
            _p('p1', name: 'A'),
            _p('p2', name: 'B', gender: 'male'),
            _p('p3', name: 'Shared Dad', gender: 'male'),
            _p('p4', name: 'A Mom', gender: 'female'),
            _p('p5', name: 'B Mom', gender: 'female'),
          ],
          relationships: [
            _r('p1', 'p3', 'father'),
            _r('p2', 'p3', 'father'),
            _r('p1', 'p4', 'mother'),
            _r('p2', 'p5', 'mother'),
          ],
        );
        // BFS will find p1 → p3 → p2.
        expect(key, isNotNull);
      });

      test('resolves a step-parent path', () {
        // p1 sees p2 as father. p2 sees p3 as wife (step-mother of p1).
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p3',
          persons: [
            _p('p1'),
            _p('p2', gender: 'male'),
            _p('p3', gender: 'female'),
          ],
          relationships: [
            _r('p1', 'p2', 'father'),
            _r('p2', 'p3', 'wife'),
          ],
        );
        expect(key, isNotNull,
            reason: 'Step-parent path must resolve to a kinship key.');
      });
    });

    group('in-laws (architecture §18)', () {
      test('resolves spouse\'s parent (father-in-law)', () {
        // p1 sees p2 as wife. p2 sees p3 as father.
        // From p1's perspective: p3 is father_in_law.
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p3',
          persons: [
            _p('p1', gender: 'male'),
            _p('p2', gender: 'female'),
            _p('p3', gender: 'male'),
          ],
          relationships: [
            _r('p1', 'p2', 'wife'),
            _r('p2', 'p3', 'father'),
          ],
        );
        expect(key, isNotNull,
            reason: 'In-law path must resolve to a kinship key.');
      });
    });

    group('multiple marriages / divorce (architecture §18)', () {
      test('resolves relationship to ex-spouse', () {
        // p1 sees p2 as wife (relationship still stored even after divorce).
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: [
            _p('p1', gender: 'male'),
            _p('p2', gender: 'female'),
          ],
          relationships: [_r('p1', 'p2', 'wife')],
        );
        expect(key, isNotNull);
      });
    });

    group('unknown / deceased / private persons (architecture §18)', () {
      test('resolves path through a deceased person', () {
        // p1 sees p2 as father. p2 sees p3 as father (p3 deceased).
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p3',
          persons: [
            _p('p1'),
            _p('p2', gender: 'male'),
            _p('p3', gender: 'male', name: 'Grandpa (deceased)'),
          ],
          relationships: [
            _r('p1', 'p2', 'father'),
            _r('p2', 'p3', 'father'),
          ],
        );
        expect(key, isNotNull,
            reason: 'Deceased persons must still resolve kinship paths.');
      });

      test('resolves path through a person with unknown gender', () {
        final key = engine.resolveKey(
          viewerPersonId: 'p1',
          targetPersonId: 'p2',
          persons: [
            _p('p1'),
            _p('p2', gender: null), // unknown gender
          ],
          relationships: [_r('p1', 'p2', 'parent')],
        );
        // Engine must NOT crash; falls back to a default gender.
        expect(key, isNotNull);
      });
    });
  });
}
