// test/graph/widgets/fab_presence_test.dart
//
// Widget tests for TASK 2: FAB removed, Add Member moved to AppBar.
//
// Verifies:
//   - No FloatingActionButton exists in FamilyGraphScreen
//   - "Add Member" icon (person_add_alt_1_rounded) exists in AppBar actions
//   - Zoom in/out icons exist in AppBar actions

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/features/family/presentation/family_graph_screen.dart';

void main() {
  group('FamilyGraphScreen AppBar actions', () {
    GoRouter _buildTestRouter() {
      return GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const FamilyGraphScreen(
              familyId: 'test_family',
              familyName: 'Test Family',
            ),
          ),
          GoRoute(
            path: '/family/:familyId/add-person',
            builder: (context, state) => const Scaffold(
              body: Text('Add Person Sheet'),
            ),
          ),
        ],
      );
    }

    testWidgets(
      'TASK-2: No FloatingActionButton exists in the graph screen',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: _buildTestRouter(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No FAB should be present
        expect(find.byType(FloatingActionButton), findsNothing);
      },
    );

    testWidgets(
      'TASK-2: Add Member icon exists in AppBar actions',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: _buildTestRouter(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The person_add icon should exist (in AppBar actions)
        expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'TASK-2: Zoom In icon exists in AppBar actions',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: _buildTestRouter(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.zoom_in_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'TASK-2: Zoom Out icon exists in AppBar actions',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: _buildTestRouter(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.zoom_out_rounded), findsOneWidget);
      },
    );
  });
}
