// test/graph/accessibility/graph_a11y_test.dart
//
// DAXELO KINREL — Graph Accessibility Tests
//
// Verifies:
// 1. GraphNode has correct semantics label (name + relation + deceased prefix)
// 2. GraphNode does not clip text at 200% text scale
// 3. Graph renders correctly in RTL with Hindi text like 'राजेश कुमार'
//
// Run: flutter test test/graph/accessibility/

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/widgets/graph_node.dart';
import 'package:kinrel/graph/widgets/graph_node_state.dart';

void main() {
  group('GraphNode Accessibility', () {
    testWidgets(
      'has correct semantics label with name and relation',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GraphNode(
                personId: 'p1',
                name: 'Rajesh Kumar',
                gender: 'male',
                generationIndex: 0,
                isAnchor: false,
                isAnonymous: false,
                relationshipKey: 'father',
                relationLabel: 'Father',
                nodeState: NodeState.normal,
                opacity: 1.0,
                nodeSize: 56.0,
                onTap: () {},
                onLongPress: () {},
              ),
            ),
          ),
        );

        // Find the Semantics widget
        final semantics = find.byType(Semantics);
        expect(semantics, findsWidgets);

        // Verify the semantic label contains name and relation
        final semanticsFinder = find.ancestor(
          of: find.text('Rajesh Kumar'),
          matching: find.byType(Semantics),
        );

        // Get all semantics labels in the tree
        final SemanticsNode? node = tester.getSemantics(find.byType(GraphNode));
        expect(node, isNotNull);
        expect(node!.label, contains('Rajesh Kumar'));
        expect(node.label, contains('Father'));
      },
    );

    testWidgets(
      'deceased nodes prepend "Late" to semantics label',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GraphNode(
                personId: 'p2',
                name: 'Sita Devi',
                gender: 'female',
                generationIndex: -1,
                isAnchor: false,
                isAnonymous: false,
                isDeceased: true,
                relationshipKey: 'grandmother',
                relationLabel: 'Grandmother',
                nodeState: NodeState.normal,
                opacity: 1.0,
                nodeSize: 56.0,
                onTap: () {},
                onLongPress: () {},
              ),
            ),
          ),
        );

        final SemanticsNode? node = tester.getSemantics(find.byType(GraphNode));
        expect(node, isNotNull);
        expect(node!.label, contains('Late'));
        expect(node.label, contains('Sita Devi'));
      },
    );

    testWidgets(
      'anonymous nodes have correct semantics label',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GraphNode(
                personId: 'p3',
                name: 'Unknown',
                gender: null,
                generationIndex: 1,
                isAnchor: false,
                isAnonymous: true,
                relationshipKey: '',
                relationLabel: '',
                nodeState: NodeState.normal,
                opacity: 1.0,
                nodeSize: 56.0,
                onTap: () {},
                onLongPress: () {},
              ),
            ),
          ),
        );

        final SemanticsNode? node = tester.getSemantics(find.byType(GraphNode));
        expect(node, isNotNull);
        expect(node!.label, contains('Anonymous'));
      },
    );

    testWidgets(
      'does not clip text at 200% text scale',
      (tester) async {
        // Bind with 2.0 text scale
        tester.binding.platformDispatcher.textScaleFactorTestValue = 2.0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: GraphNode(
                  personId: 'p4',
                  name: 'VeryLongNameThatShouldNotClip',
                  gender: 'male',
                  generationIndex: 0,
                  isAnchor: false,
                  isAnonymous: false,
                  relationshipKey: 'elder_brother',
                  relationLabel: 'Elder Brother',
                  nodeState: NodeState.normal,
                  opacity: 1.0,
                  nodeSize: 56.0,
                  onTap: () {},
                  onLongPress: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The FittedBox should prevent overflow — verify no RenderFlex
        // overflow errors were thrown
        expect(tester.takeException(), isNull);

        // Verify the name text is still rendered (not clipped away)
        expect(find.text('VeryLongNameThatShouldNotClip'), findsOneWidget);

        // Reset text scale
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      },
    );

    testWidgets(
      'renders correctly in RTL with Hindi text',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            // Force RTL for Hindi/Urdu locales
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: GraphNode(
                  personId: 'p5',
                  name: 'राजेश कुमार',
                  gender: 'male',
                  generationIndex: 0,
                  isAnchor: true,
                  isAnonymous: false,
                  relationshipKey: 'self',
                  relationLabel: 'स्वयं',
                  nodeState: NodeState.normal,
                  opacity: 1.0,
                  nodeSize: 56.0,
                  onTap: () {},
                  onLongPress: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify no layout exceptions
        expect(tester.takeException(), isNull);

        // Verify the Hindi name text is rendered
        expect(find.text('राजेश कुमार'), findsOneWidget);

        // Verify the Hindi relation label is rendered
        expect(find.text('स्वयं'), findsOneWidget);

        // Verify the node renders within the screen bounds
        final nodeSize = tester.getSize(find.byType(GraphNode));
        expect(nodeSize.width, greaterThan(0));
        expect(nodeSize.height, greaterThan(0));
      },
    );
  });
}
