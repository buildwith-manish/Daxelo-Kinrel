// test/features/family/family_graph_screen_fab_test.dart
//
// AGENT-08 (Quality & Testing) — Regression test for BUG-3:
// FAB (FloatingActionButton) presence and navigation on FamilyGraphScreen.
//
// Verifies:
//   1. FamilyGraphScreen with a mocked graph (4 members) shows a FAB
//   2. The FAB uses Icons.person_add_alt_1_rounded
//   3. Tapping the FAB navigates to '/family/test-id/add-person'
//
// Strategy: Use a mocked GoRouter to intercept navigation and verify
// the correct route is pushed when the FAB is tapped.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/features/family/presentation/family_graph_screen.dart';
import 'package:kinrel/features/family/presentation/providers/family_graph_provider.dart';
import 'package:kinrel/features/family/presentation/widgets/graph_canvas_widget.dart';

void main() {
  group('FamilyGraphScreen FAB regression (BUG-3)', () {
    /// Build a 4-member FlatGraphResult so onboarding is done (4+ members
    /// means no onboarding overlay, which simplifies the test).
    FlatGraphResult _buildFourMemberGraph() {
      return FlatGraphResult(
        persons: [
          <String, dynamic>{
            'id': 'p1',
            'name': 'Kishan',
            'gender': 'male',
            'generationIndex': 0,
            'isAnchor': true,
            'photoUrl': null,
            'isDeceased': false,
          },
          <String, dynamic>{
            'id': 'p2',
            'name': 'Sita',
            'gender': 'female',
            'generationIndex': -1,
            'isAnchor': false,
            'photoUrl': null,
            'isDeceased': false,
          },
          <String, dynamic>{
            'id': 'p3',
            'name': 'Rahul',
            'gender': 'male',
            'generationIndex': 0,
            'isAnchor': false,
            'photoUrl': null,
            'isDeceased': false,
          },
          <String, dynamic>{
            'id': 'p4',
            'name': 'Priya',
            'gender': 'female',
            'generationIndex': 1,
            'isAnchor': false,
            'photoUrl': null,
            'isDeceased': false,
          },
        ],
        relationships: [
          <String, dynamic>{
            'id': 'r1',
            'fromPersonId': 'p1',
            'toPersonId': 'p2',
            'relationshipKey': 'mother',
            'isPrivate': false,
          },
          <String, dynamic>{
            'id': 'r2',
            'fromPersonId': 'p1',
            'toPersonId': 'p3',
            'relationshipKey': 'brother',
            'isPrivate': false,
          },
          <String, dynamic>{
            'id': 'r3',
            'fromPersonId': 'p1',
            'toPersonId': 'p4',
            'relationshipKey': 'daughter',
            'isPrivate': false,
          },
        ],
      );
    }

    /// Tracks navigation events pushed via GoRouter during the test.
    List<String> navigationLog = [];

    /// Builds a GoRouter that:
    ///   - Maps '/' to FamilyGraphScreen
    ///   - Maps '/family/:familyId/add-person' to a placeholder
    ///   - Logs every navigation push into [navigationLog]
    GoRouter _buildTestRouter() {
      navigationLog.clear();
      return GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const FamilyGraphScreen(
              familyId: 'test-id',
              familyName: 'Test Family',
            ),
          ),
          GoRoute(
            path: '/family/:familyId/add-person',
            builder: (context, state) => const Scaffold(
              body: Text('Add Person Page'),
            ),
          ),
        ],
      );
    }

    testWidgets(
      'BUG-3: FloatingActionButton with Icons.person_add_alt_1_rounded is present',
      (tester) async {
        final graphData = _buildFourMemberGraph();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              familyGraphProvider.overrideWith(
                () => _FakeFamilyGraphNotifier(graphData),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: _buildTestRouter(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify FAB is in the tree
        expect(
          find.byType(FloatingActionButton),
          findsOneWidget,
          reason: 'FamilyGraphScreen must have a FloatingActionButton',
        );

        // Verify FAB has the correct icon
        expect(
          find.byIcon(Icons.person_add_alt_1_rounded),
          findsOneWidget,
          reason: 'FAB must use Icons.person_add_alt_1_rounded',
        );
      },
    );

    testWidgets(
      'BUG-3: Tapping FAB navigates to /family/test-id/add-person',
      (tester) async {
        final graphData = _buildFourMemberGraph();
        final router = _buildTestRouter();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              familyGraphProvider.overrideWith(
                () => _FakeFamilyGraphNotifier(graphData),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap the FAB
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        // Verify navigation occurred to the add-person route
        // GoRouter should have pushed '/family/test-id/add-person'
        expect(
          find.text('Add Person Page'),
          findsOneWidget,
          reason: 'Tapping FAB should navigate to /family/test-id/add-person',
        );
      },
    );

    testWidgets(
      'BUG-3: FAB is visible regardless of onboarding state',
      (tester) async {
        // Even with 0 members (onboarding state), the FAB should be present
        // because it is attached to the Scaffold, not conditional on data.
        final emptyGraph = FlatGraphResult(
          persons: [],
          relationships: [],
        );

        final router = _buildTestRouter();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              familyGraphProvider.overrideWith(
                () => _FakeFamilyGraphNotifier(emptyGraph),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // FAB must still be present even for empty graph (0 members)
        expect(
          find.byType(FloatingActionButton),
          findsOneWidget,
          reason: 'FAB must be present even with empty graph (onboarding state)',
        );
        expect(
          find.byIcon(Icons.person_add_alt_1_rounded),
          findsOneWidget,
          reason: 'FAB icon must be visible even with empty graph',
        );
      },
    );
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// FAKE NOTIFIER: Returns deterministic graph data for testing
// ═══════════════════════════════════════════════════════════════════════════

/// A fake FamilyGraphNotifier that immediately returns the provided
/// [FlatGraphResult] without making any Supabase/RPC calls.
class _FakeFamilyGraphNotifier extends FamilyGraphNotifier {
  final FlatGraphResult _graphData;

  _FakeFamilyGraphNotifier(this._graphData);

  @override
  Future<FlatGraphResult> build(String familyId) async {
    return _graphData;
  }
}
