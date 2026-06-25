// test/graph/widgets/relationship_edge_smoke_test.dart
//
// Smoke test for the v52 refactored RelationshipEdge painter.
// Paints a canvas with edges of every category to make sure the
// refactored code doesn't throw any exceptions during rendering.
//
// Run with: flutter test test/graph/widgets/relationship_edge_smoke_test.dart

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/graph/data/family_graph_repository.dart' show GraphEdgeData;
import 'package:kinrel/graph/widgets/relationship_edge.dart';
import '../../helpers/native_plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupNativePluginMocks);
  tearDownAll(tearDownNativePluginMocks);
  group('RelationshipEdge v52 smoke test', () {
    test('classifies all 10 categories without throwing', () {
      final keys = <String>[
        'self',
        'father',        // parent
        'son',           // child
        'brother',       // sibling
        'wife',          // spouse
        'grandfather',   // grandparent
        'uncle',         // auntUncle
        'cousin',        // cousin
        'father_in_law', // inLaw
        'stepfather',    // extended
        'indirect_connection', // indirect
        // Indian kinship compound keys:
        'fathers_elder_brother',         // auntUncle
        'fathers_elder_brothers_son',    // sibling (parallel cousin)
        'brothers_son',                  // cousin
        'husbands_father',               // inLaw
        'paternal_grandfather_wife',     // grandparent
      ];

      for (final key in keys) {
        final category = KinshipEdgeClassifier.classify(key);
        // Resolver should not throw.
        final style = KinshipEdgeStyleResolver.styleForCategory(category);
        expect(style, isNotNull);
        expect(style.color, isNotNull);
        expect(style.lineShape, isNotNull);
        expect(style.midpointSymbol, isNotNull);
        expect(style.midpointColor, isNotNull);
      }
    });

    testWidgets('painter renders edges of every category without throwing',
        (WidgetTester tester) async {
      final positions = <String, Offset>{
        'self':      const Offset(400, 400),
        'father':    const Offset(400, 200),
        'son':       const Offset(400, 600),
        'brother':   const Offset(200, 400),
        'wife':      const Offset(600, 400),
        'granddad':  const Offset(400, 50),
        'uncle':     const Offset(150, 200),
        'cousin':    const Offset(80, 600),
        'inlaw':     const Offset(700, 200),
        'stepdad':   const Offset(50, 50),
        'blocked':   const Offset(800, 600),
      };

      final edges = <GraphEdgeData>[
        GraphEdgeData(
          id: 'e1',
          sourceId: 'self',
          targetId: 'father',
          relationshipKey: 'father',
        ),
        GraphEdgeData(
          id: 'e2',
          sourceId: 'self',
          targetId: 'son',
          relationshipKey: 'son',
        ),
        GraphEdgeData(
          id: 'e3',
          sourceId: 'self',
          targetId: 'brother',
          relationshipKey: 'brother',
        ),
        GraphEdgeData(
          id: 'e4',
          sourceId: 'self',
          targetId: 'wife',
          relationshipKey: 'wife',
        ),
        GraphEdgeData(
          id: 'e5',
          sourceId: 'self',
          targetId: 'granddad',
          relationshipKey: 'grandfather',
        ),
        GraphEdgeData(
          id: 'e6',
          sourceId: 'self',
          targetId: 'uncle',
          relationshipKey: 'uncle',
        ),
        GraphEdgeData(
          id: 'e7',
          sourceId: 'self',
          targetId: 'cousin',
          relationshipKey: 'cousin',
        ),
        GraphEdgeData(
          id: 'e8',
          sourceId: 'self',
          targetId: 'inlaw',
          relationshipKey: 'father_in_law',
        ),
        GraphEdgeData(
          id: 'e9',
          sourceId: 'self',
          targetId: 'stepdad',
          relationshipKey: 'stepfather',
        ),
        GraphEdgeData(
          id: 'e10',
          sourceId: 'self',
          targetId: 'blocked',
          relationshipKey: 'indirect_connection',
        ),
        // Indian kinship compound keys:
        GraphEdgeData(
          id: 'e11',
          sourceId: 'self',
          targetId: 'uncle',
          relationshipKey: 'fathers_elder_brother',
        ),
        GraphEdgeData(
          id: 'e12',
          sourceId: 'brother',
          targetId: 'cousin',
          relationshipKey: 'fathers_elder_brothers_son',
        ),
        GraphEdgeData(
          id: 'e13',
          sourceId: 'brother',
          targetId: 'cousin',
          relationshipKey: 'brothers_son',
        ),
        GraphEdgeData(
          id: 'e14',
          sourceId: 'wife',
          targetId: 'inlaw',
          relationshipKey: 'husbands_father',
        ),
        GraphEdgeData(
          id: 'e15',
          sourceId: 'self',
          targetId: 'granddad',
          relationshipKey: 'paternal_grandfather_wife',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 1000,
              child: CustomPaint(
                size: const Size(1000, 1000),
                painter: RelationshipEdge(
                  positions: positions,
                  edges: edges,
                  zoomLevel: 1.0,
                  nodeWidth: 72.0,
                  nodeHeight: 72.0,
                ),
              ),
            ),
          ),
        ),
      );

      // Force a paint by waiting one frame.
      await tester.pump();

      // If we got here without an exception, the test passes.
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RelationshipEdge,
        ),
        findsOneWidget,
      );
    });

    testWidgets('painter handles minimal LOD (zoom < 0.4) without throwing',
        (WidgetTester tester) async {
      final positions = <String, Offset>{
        'a': const Offset(100, 100),
        'b': const Offset(300, 300),
      };

      final edges = <GraphEdgeData>[
        GraphEdgeData(
          id: 'e1',
          sourceId: 'a',
          targetId: 'b',
          relationshipKey: 'father',
        ),
        GraphEdgeData(
          id: 'e2',
          sourceId: 'a',
          targetId: 'b',
          relationshipKey: 'wife',
        ),
        GraphEdgeData(
          id: 'e3',
          sourceId: 'a',
          targetId: 'b',
          relationshipKey: 'brother',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 500,
              child: CustomPaint(
                size: const Size(500, 500),
                painter: RelationshipEdge(
                  positions: positions,
                  edges: edges,
                  zoomLevel: 0.2, // below _lodMinimalZoom
                  nodeWidth: 72.0,
                  nodeHeight: 72.0,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RelationshipEdge,
        ),
        findsOneWidget,
      );
    });

    testWidgets('painter handles selected + dimmed edges without throwing',
        (WidgetTester tester) async {
      final positions = <String, Offset>{
        'a': const Offset(100, 100),
        'b': const Offset(300, 300),
        'c': const Offset(500, 100),
      };

      final edges = <GraphEdgeData>[
        GraphEdgeData(
          id: 'e1',
          sourceId: 'a',
          targetId: 'b',
          relationshipKey: 'father',
        ),
        GraphEdgeData(
          id: 'e2',
          sourceId: 'b',
          targetId: 'c',
          relationshipKey: 'cousin',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 700,
              height: 500,
              child: CustomPaint(
                size: const Size(700, 500),
                painter: RelationshipEdge(
                  positions: positions,
                  edges: edges,
                  selectedEdgeId: 'e1',
                  zoomLevel: 1.0,
                  nodeWidth: 72.0,
                  nodeHeight: 72.0,
                  generationMap: const {'a': 0, 'b': 1, 'c': 1},
                  highlightedGeneration: 1,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is RelationshipEdge,
        ),
        findsOneWidget,
      );
    });
  });
}
