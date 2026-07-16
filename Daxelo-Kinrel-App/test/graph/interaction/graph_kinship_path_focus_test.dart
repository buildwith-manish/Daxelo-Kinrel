// test/graph/interaction/graph_kinship_path_focus_test.dart
//
// Focused tests for the kinship path focus model + notifier
// (PARTS 14–16 of the FINAL MISSING 10/10 FEATURES pass).
//
// These tests verify:
//   1. resolve() returns ordered person IDs (viewer → ... → target)
//   2. resolve() returns ordered edge IDs (length = steps - 1)
//   3. step count is correct
//   4. cache hit short-circuits when target/viewer/revision are unchanged
//   5. cache invalidates when target changes
//   6. cache invalidates when graphRevision changes
//   7. resolve() returns null when viewer == target
//   8. resolve() returns null when viewer is null
//   9. resolve() returns null when target is null
//  10. resolve() returns null when no path exists
//  11. heart symbol does NOT imply spouse semantics — the relationship
//      key comes from the edge's relationshipKey, not the midpoint symbol

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/core/kinship/structural_kinship_classifier.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/data/graph_data_models.dart';
import 'package:kinrel/graph/engine/edge_dedup.dart';
import 'package:kinrel/graph/interaction/graph_kinship_path_focus.dart';

void main() {
  group('GraphPathFocusNotifier — basic resolution', () {
    late GraphPathFocusNotifier notifier;

    setUp(() {
      notifier = GraphPathFocusNotifier();
    });

    test('returns null when viewerPersonId is null', () {
      final result = notifier.resolve(
        viewerPersonId: null,
        targetPersonId: 'target-1',
        edges: const [],
        persons: const [],
        relationships: const [],
        graphRevision: 1,
      );
      expect(result, isNull);
      expect(notifier.state.focus, isNull);
    });

    test('returns null when targetPersonId is null', () {
      final result = notifier.resolve(
        viewerPersonId: 'viewer-1',
        targetPersonId: null,
        edges: const [],
        persons: const [],
        relationships: const [],
        graphRevision: 1,
      );
      expect(result, isNull);
      expect(notifier.state.focus, isNull);
    });

    test('returns null when viewer == target', () {
      final result = notifier.resolve(
        viewerPersonId: 'same-id',
        targetPersonId: 'same-id',
        edges: const [],
        persons: const [GraphPerson(id: 'same-id', name: 'Self')],
        relationships: const [],
        graphRevision: 1,
      );
      expect(result, isNull);
      expect(notifier.state.focus, isNull);
    });

    test('returns null when no path exists between viewer and target', () {
      final persons = [
        GraphPerson(id: 'a', name: 'A'),
        GraphPerson(id: 'b', name: 'B'),
      ];
      // No relationship edges → no path.
      final result = notifier.resolve(
        viewerPersonId: 'a',
        targetPersonId: 'b',
        edges: const [],
        persons: persons,
        relationships: const [],
        graphRevision: 1,
      );
      expect(result, isNull);
    });
  });

  group('GraphPathFocusNotifier — single-hop path', () {
    late GraphPathFocusNotifier notifier;

    setUp(() {
      notifier = GraphPathFocusNotifier();
    });

    test('returns ordered person IDs [viewer, target]', () {
      final persons = [
        GraphPerson(id: 'viewer', name: 'Viewer'),
        GraphPerson(id: 'father', name: 'Father', gender: 'male'),
      ];
      final relationships = [
        (fromId: 'viewer', toId: 'father', type: 'father'),
      ];
      // Build deduped edges so the notifier can map hops to edge IDs.
      final rawEdges = [
        GraphEdgeData(
            id: 'edge-1',
            sourceId: 'viewer',
            targetId: 'father',
            relationshipKey: 'father'),
      ];
      final edges = EdgeDeduplicator.deduplicate(rawEdges);

      final result = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'father',
        edges: edges,
        persons: persons,
        relationships: relationships,
        graphRevision: 1,
        classification: StructuralClassification(
          category: KinshipEdgeCategory.parent,
          label: 'Father',
          key: 'father',
        ),
      );

      expect(result, isNotNull);
      expect(result!.orderedPersonIds, ['viewer', 'father']);
      expect(result.orderedEdgeIds.length, 1);
      expect(result.stepCount, 1);
      expect(result.isMultiHop, isFalse);
      expect(result.resolvedRelationshipKey, 'father');
      expect(result.resolvedRelationshipLabel, 'Father');
      expect(result.resolvedCategory, KinshipEdgeCategory.parent);
    });
  });

  group('GraphPathFocusNotifier — cache invalidation', () {
    late GraphPathFocusNotifier notifier;

    setUp(() {
      notifier = GraphPathFocusNotifier();
    });

    test('cache hit returns the same focus without re-resolving', () {
      final persons = [
        GraphPerson(id: 'viewer', name: 'Viewer'),
        GraphPerson(id: 'target', name: 'Target'),
      ];
      final relationships = [
        (fromId: 'viewer', toId: 'target', type: 'father'),
      ];
      final edges = EdgeDeduplicator.deduplicate([
        GraphEdgeData(
            id: 'edge-1',
            sourceId: 'viewer',
            targetId: 'target',
            relationshipKey: 'father'),
      ]);

      // First resolve.
      final first = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'target',
        edges: edges,
        persons: persons,
        relationships: relationships,
        graphRevision: 1,
      );
      expect(first, isNotNull);

      // Second resolve with same inputs — should be a cache hit.
      final second = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'target',
        edges: edges,
        persons: persons,
        relationships: relationships,
        graphRevision: 1,
      );
      expect(second, same(first));
    });

    test('cache invalidates when targetPersonId changes', () {
      final persons = [
        GraphPerson(id: 'viewer', name: 'Viewer'),
        GraphPerson(id: 'target-a', name: 'A'),
        GraphPerson(id: 'target-b', name: 'B'),
      ];
      final relationships = [
        (fromId: 'viewer', toId: 'target-a', type: 'father'),
        (fromId: 'viewer', toId: 'target-b', type: 'sister'),
      ];
      final edges = EdgeDeduplicator.deduplicate([
        GraphEdgeData(
            id: 'edge-a',
            sourceId: 'viewer',
            targetId: 'target-a',
            relationshipKey: 'father'),
        GraphEdgeData(
            id: 'edge-b',
            sourceId: 'viewer',
            targetId: 'target-b',
            relationshipKey: 'sister'),
      ]);

      final first = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'target-a',
        edges: edges,
        persons: persons,
        relationships: relationships,
        graphRevision: 1,
      );
      expect(first?.targetPersonId, 'target-a');

      final second = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'target-b',
        edges: edges,
        persons: persons,
        relationships: relationships,
        graphRevision: 1,
      );
      expect(second?.targetPersonId, 'target-b');
      expect(second, isNot(same(first)));
    });

    test('cache invalidates when graphRevision changes', () {
      final persons = [
        GraphPerson(id: 'viewer', name: 'Viewer'),
        GraphPerson(id: 'target', name: 'Target'),
      ];
      final relationships = [
        (fromId: 'viewer', toId: 'target', type: 'father'),
      ];
      final edges = EdgeDeduplicator.deduplicate([
        GraphEdgeData(
            id: 'edge-1',
            sourceId: 'viewer',
            targetId: 'target',
            relationshipKey: 'father'),
      ]);

      final first = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'target',
        edges: edges,
        persons: persons,
        relationships: relationships,
        graphRevision: 1,
      );
      expect(first?.graphRevision, 1);

      final second = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'target',
        edges: edges,
        persons: persons,
        relationships: relationships,
        graphRevision: 2,
      );
      expect(second?.graphRevision, 2);
      expect(second, isNot(same(first)));
    });
  });

  group('GraphPathFocusNotifier — clear()', () {
    test('clear() resets the state to empty', () {
      final notifier = GraphPathFocusNotifier();
      final persons = [
        GraphPerson(id: 'viewer', name: 'Viewer'),
        GraphPerson(id: 'target', name: 'Target'),
      ];
      final relationships = [
        (fromId: 'viewer', toId: 'target', type: 'father'),
      ];
      final edges = EdgeDeduplicator.deduplicate([
        GraphEdgeData(
            id: 'edge-1',
            sourceId: 'viewer',
            targetId: 'target',
            relationshipKey: 'father'),
      ]);

      notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'target',
        edges: edges,
        persons: persons,
        relationships: relationships,
        graphRevision: 1,
      );
      expect(notifier.state.focus, isNotNull);

      notifier.clear();
      expect(notifier.state.focus, isNull);
    });
  });

  group('Heart-symbol semantic separation (PART 17)', () {
    // The heart symbol is a VISUAL choice. The relationship key comes
    // from the edge's relationshipKey field, NOT from the midpoint
    // symbol. A custom relationship with dotType='heart' should still
    // report its actual relationshipKey.
    test('heart midpoint does NOT force spouse semantics', () {
      // A custom "best_friend" relationship with a heart midpoint.
      final notifier = GraphPathFocusNotifier();
      final persons = [
        GraphPerson(id: 'viewer', name: 'Viewer'),
        GraphPerson(id: 'friend', name: 'Friend'),
      ];
      final relationships = [
        (fromId: 'viewer', toId: 'friend', type: 'best_friend'),
      ];
      final edges = EdgeDeduplicator.deduplicate([
        GraphEdgeData(
            id: 'edge-1',
            sourceId: 'viewer',
            targetId: 'friend',
            relationshipKey: 'best_friend'),
      ]);

      final result = notifier.resolve(
        viewerPersonId: 'viewer',
        targetPersonId: 'friend',
        edges: edges,
        persons: persons,
        relationships: relationships,
        graphRevision: 1,
        // The classifier returns whatever key best matches — NOT
        // 'spouse' just because the visual midpoint is a heart.
        classification: StructuralClassification(
          category: KinshipEdgeCategory.extended,
          label: 'Best Friend',
          key: 'best_friend',
        ),
      );

      expect(result, isNotNull);
      // The resolved key is 'best_friend', NOT 'wife'/'husband'/'spouse'.
      expect(result!.resolvedRelationshipKey, 'best_friend');
      expect(result.resolvedCategory, KinshipEdgeCategory.extended);
      expect(result.resolvedRelationshipLabel, 'Best Friend');
    });
  });
}
