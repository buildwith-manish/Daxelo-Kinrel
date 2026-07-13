// test/graph/perf/path_resolution_benchmark_test.dart
// P2.1: Performance benchmark for path resolution.
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/relationship/relationship_engine.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';

void main() {
  group('P2.1 Path resolution benchmark', () {
    test('resolves a path on a 500-node graph', () {
      final persons = <GraphPerson>[];
      final relationships = <({String fromId, String toId, String type})>[];
      for (int i = 0; i < 500; i++) {
        persons.add(GraphPerson(
          id: 'p' + i.toString(),
          name: 'Person ' + i.toString(),
          gender: i % 2 == 0 ? 'male' : 'female',
          generationIndex: (i / 3).floor(),
          isAnchor: i == 0,
          photoUrl: null,
          isDeceased: false,
        ));
      }
      for (int i = 0; i < 500; i++) {
        for (int c = 1; c <= 3; c++) {
          final childIdx = i * 3 + c;
          if (childIdx >= 500) break;
          relationships.add((
            fromId: 'p' + i.toString(),
            toId: 'p' + childIdx.toString(),
            type: 'child',
          ));
        }
      }
      final stopwatch = Stopwatch()..start();
      final result = RelationshipEngine.instance.resolvePath(
        viewerPersonId: 'p0',
        targetPersonId: 'p364',
        persons: persons,
        relationships: relationships,
      );
      stopwatch.stop();
      expect(result, isNotNull);
      expect(result.length, greaterThan(0));
      expect(stopwatch.elapsedMilliseconds, lessThan(150));
    });
  });
}
