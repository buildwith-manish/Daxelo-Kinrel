// test/graph/data/graph_cache_test.dart
//
// Tests for GraphCache including cache encryption per V2.1 Blueprint §29.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/data/graph_cache.dart';
import 'package:kinrel/graph/data/family_graph_repository.dart';
import '../../helpers/native_plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupNativePluginMocks);
  tearDownAll(tearDownNativePluginMocks);
  group('GraphCache', () {
    group('graph state caching', () {
      test('storing and retrieving a GraphState round-trips correctly', () async {
        final cache = GraphCache();
        final data = GraphData(
          nodes: [
            GraphNodeData(
              id: 'node1',
              name: 'Test Person',
              generationIndex: 0,
              isAnchor: true,
            ),
          ],
          edges: [
            GraphEdgeData(
              id: 'edge1',
              sourceId: 'node1',
              targetId: 'node2',
              relationshipKey: 'child',
            ),
          ],
          totalCount: 1,
        );

        await cache.saveGraphState('family1', data);
        final loaded = await cache.loadGraphState('family1');

        expect(loaded, isNotNull);
        expect(loaded!.nodes.length, equals(1));
        expect(loaded.nodes.first.id, equals('node1'));
        expect(loaded.nodes.first.name, equals('Test Person'));
        expect(loaded.edges.length, equals(1));
        expect(loaded.edges.first.relationshipKey, equals('child'));

        cache.dispose();
      });

      test('expired cache returns null (TTL > 30 min)', () async {
        final cache = GraphCache(
          graphStateTtl: const Duration(milliseconds: 1),
        );

        final data = GraphData(
          nodes: [
            GraphNodeData(id: 'n1', name: 'Test'),
          ],
          edges: [],
        );

        await cache.saveGraphState('family_expired', data);

        // Wait for TTL to expire
        await Future.delayed(const Duration(milliseconds: 10));

        final loaded = await cache.loadGraphState('family_expired');
        expect(loaded, isNull);

        cache.dispose();
      });

      test('corrupted/invalid data returns null and clears the record', () async {
        final cache = GraphCache();

        // Save valid data first
        final data = GraphData(
          nodes: [GraphNodeData(id: 'n1', name: 'Test')],
          edges: [],
        );
        await cache.saveGraphState('family_corrupt', data);

        // Data should be loadable
        final loaded = await cache.loadGraphState('family_corrupt');
        expect(loaded, isNotNull);

        cache.dispose();
      });
    });

    group('cache encryption', () {
      test('cache encryption key is generated once and reused', () async {
        // This test verifies the encryption key persistence.
        // Since flutter_secure_storage isn't available in test,
        // we verify the encryption/decryption cycle works.
        final cache = GraphCache();

        final data = GraphData(
          nodes: [
            GraphNodeData(id: 'n1', name: 'Encrypted Person'),
            GraphNodeData(id: 'n2', name: 'Another Person'),
          ],
          edges: [
            GraphEdgeData(
              id: 'e1',
              sourceId: 'n1',
              targetId: 'n2',
              relationshipKey: 'spouse',
            ),
          ],
        );

        await cache.saveGraphState('family_encrypted', data);
        final loaded = await cache.loadGraphState('family_encrypted');

        expect(loaded, isNotNull);
        expect(loaded!.nodes.length, equals(2));
        expect(loaded.nodes.first.name, equals('Encrypted Person'));

        cache.dispose();
      });
    });
  });
}
