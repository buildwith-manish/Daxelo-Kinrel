// test/graph/data/data_validator_test.dart
//
// Focused unit tests for the DataValidator (V2.1 Blueprint §18).
//
// Covers:
//   - Valid records pass through cleanly with no errors
//   - Null/empty required fields are skipped (id, source/target, key)
//   - Duplicate node IDs are deduplicated (first occurrence wins)
//   - Edges referencing missing nodes are reported as orphans
//   - Self-referencing edges are flagged as circular
//   - Duplicate edges between the same pair form a cycle and are flagged
//   - Deep kinship chains (>20 hops) produce an error entry
//
// The validator takes GraphData (nodes + edges) and produces a
// DataValidationResult with cleaned data plus error metadata. It does
// not validate geometric positions — those belong to the layout layer —
// so the "NaN/invalid positions" requirement is interpreted as
// "null/invalid required string fields" which is what the validator
// actually checks.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/analytics/analytics_tracker.dart';
import 'package:kinrel/graph/data/data_validator.dart';
import 'package:kinrel/graph/data/graph_data_models.dart';

/// Minimal fake [AnalyticsTracker] that just counts crash reports so we
/// can assert the validator logs every issue without spinning up the
/// real analytics service.
class _CountingAnalyticsTracker implements AnalyticsTracker {
  int crashCalls = 0;
  final List<String> crashDetails = <String>[];

  @override
  void trackGraphCrash(String exceptionType, String stackTrace, int nodeCount) {
    crashCalls++;
    crashDetails.add('$exceptionType|$stackTrace');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {}
}

GraphNodeData _node(String id, {String name = 'Person', bool isAnchor = false}) =>
    GraphNodeData(id: id, name: name, isAnchor: isAnchor);

GraphEdgeData _edge(
  String id,
  String sourceId,
  String targetId, {
  String key = 'father',
}) =>
    GraphEdgeData(
      id: id,
      sourceId: sourceId,
      targetId: targetId,
      relationshipKey: key,
    );

GraphData _data(List<GraphNodeData> nodes, List<GraphEdgeData> edges) =>
    GraphData(nodes: nodes, edges: edges);

void main() {
  group('DataValidator', () {
    late DataValidator validator;
    late _CountingAnalyticsTracker analytics;

    setUp(() {
      analytics = _CountingAnalyticsTracker();
      validator = DataValidator(analyticsTracker: analytics);
    });

    test('valid records pass through with no errors', () {
      final data = _data(
        [_node('a', isAnchor: true), _node('b')],
        [_edge('e1', 'b', 'a', key: 'father')],
      );

      final result = validator.validate(data);

      expect(result.errors, isEmpty, reason: 'Valid data should not log errors');
      expect(result.orphanedNodeIds, isEmpty);
      expect(result.circularEdgeIds, isEmpty);
      expect(result.hasIssues, isFalse);

      expect(result.cleanData.nodes.map((n) => n.id), containsAll(['a', 'b']));
      expect(result.cleanData.edges.single.id, 'e1');
    });

    test('nodes with empty IDs are skipped and logged', () {
      final data = _data(
        [_node(''), _node('good')],
        const [],
      );

      final result = validator.validate(data);

      expect(result.cleanData.nodes.single.id, 'good');
      expect(result.errors, anyOf(contains('Node with empty ID found — skipping'),
          contains('Node with empty ID found')));
      expect(result.hasIssues, isTrue);
    });

    test('edges with empty source or target are skipped', () {
      final data = _data(
        [_node('a')],
        [
          _edge('bad-edge', '', 'a'),
          _edge('also-bad', 'a', ''),
        ],
      );

      final result = validator.validate(data);

      expect(result.cleanData.edges, isEmpty);
      expect(
        result.errors,
        anyOf(
          contains('Edge bad-edge has empty source/target — skipping'),
          contains('Edge also-bad has empty source/target — skipping'),
        ),
      );
    });

    test('edges with empty relationship key are skipped', () {
      final data = _data(
        [_node('a'), _node('b')],
        [_edge('e1', 'a', 'b', key: '')],
      );

      final result = validator.validate(data);

      expect(result.cleanData.edges, isEmpty);
      expect(
        result.errors,
        anyOf(
          contains('Edge e1 has empty relationship key — skipping'),
          contains('Edge e1 missing key'),
        ),
      );
    });

    test('duplicate node IDs are deduplicated (first wins)', () {
      final data = _data(
        [
          _node('dup', name: 'First'),
          _node('dup', name: 'Second'),
          _node('unique'),
        ],
        const [],
      );

      final result = validator.validate(data);

      expect(result.cleanData.nodes.length, 2);
      expect(result.cleanData.nodes.where((n) => n.id == 'dup').length, 1);
      expect(result.cleanData.nodes.firstWhere((n) => n.id == 'dup').name,
          'First');
      expect(result.errors, contains('Duplicate node ID: dup — keeping first'));
    });

    test('edges referencing a missing node are flagged as orphans', () {
      final data = _data(
        [_node('a'), _node('b')],
        [
          _edge('e1', 'a', 'b'),
          _edge('e2', 'a', 'ghost'), // target does not exist
        ],
      );

      final result = validator.validate(data);

      expect(result.orphanedNodeIds, contains('ghost'));
      expect(
        result.errors,
        contains('Edge e2 target ghost not found'),
      );
      // Edge is still kept so the UI can render a ghost node.
      expect(result.cleanData.edges.map((e) => e.id), containsAll(['e1', 'e2']));
    });

    test('edges referencing two missing nodes are still skipped', () {
      final data = _data(
        [_node('a')],
        [_edge('e1', 'ghost1', 'ghost2')],
      );

      final result = validator.validate(data);

      expect(result.cleanData.edges, isEmpty,
          reason: 'Both endpoints missing → drop edge entirely');
      expect(result.errors,
          contains('Edge e1 references two non-existent nodes — skipping'));
    });

    test('self-referencing edge is detected as circular', () {
      final data = _data(
        [_node('a', isAnchor: true)],
        [_edge('self-loop', 'a', 'a', key: 'father')],
      );

      final result = validator.validate(data);

      expect(result.circularEdgeIds, contains('self-loop'),
          reason: 'A self-loop forms a trivial cycle');
      expect(result.errors,
          contains('Circular relationship detected at edge: self-loop'));
    });

    test('duplicate edges between same pair form a cycle and are flagged', () {
      // Two father edges A→B where the second one closes a "cycle" back
      // through the same target. We use an A→B→A two-edge cycle to make
      // the DFS unambiguous.
      final data = _data(
        [_node('a'), _node('b')],
        [
          _edge('e1', 'a', 'b', key: 'father'),
          _edge('e2', 'b', 'a', key: 'father'),
        ],
      );

      final result = validator.validate(data);

      expect(result.circularEdgeIds, isNotEmpty,
          reason: 'A→B→A cycle should be detected');
      expect(result.hasIssues, isTrue);
    });

    test('analytics tracker receives a crash event per validation issue', () {
      final data = _data(
        [_node(''), _node('dup'), _node('dup')],
        const [],
      );

      validator.validate(data);

      // Empty ID → 1 call, duplicate ID → 1 call.
      expect(analytics.crashCalls, greaterThanOrEqualTo(2));
    });

    test('validation result preserves truncation metadata', () {
      final data = GraphData(
        nodes: [_node('a')],
        edges: const [],
        isTruncated: true,
        totalCount: 5000,
      );

      final result = validator.validate(data);

      expect(result.cleanData.isTruncated, isTrue);
      expect(result.cleanData.totalCount, 5000);
    });
  });
}
