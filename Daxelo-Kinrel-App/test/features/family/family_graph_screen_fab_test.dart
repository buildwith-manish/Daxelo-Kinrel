// test/features/family/family_graph_screen_fab_test.dart
//
// v10 Fix #4: Reconciled conflicting FAB tests.
//
// The active code only renders a FloatingActionButton in the EMPTY state
// (family_graph_screen.dart). The 4-member FAB test was therefore expected
// to fail. Per the fix prompt, we:
//   - Changed the 4-member assertion to findsNothing (FAB only in empty state)
//   - Renamed the test to reflect the new expectation
//   - Kept the empty-state test asserting findsOneWidget (FAB present)
//
// Verifies:
//   1. FamilyGraphScreen with 4 members does NOT show a FAB (AppBar "Add" button is used instead)
//   2. FamilyGraphScreen with 0 members (empty state) DOES show a FAB
//   3. The FAB uses Icons.person_add_alt_1_rounded

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/features/family/presentation/family_graph_screen.dart';
import 'package:kinrel/features/family/presentation/providers/family_graph_provider.dart';

void main() {
  group('FamilyGraphScreen FAB presence', () {
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

    /// Builds a GoRouter that maps '/' to FamilyGraphScreen.
    GoRouter _buildTestRouter() {
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
      'v10: 4-member graph does NOT show FAB (FAB only in empty state)',
      (tester) async {
        final graphData = _buildFourMemberGraph();

        tester.view.physicalSize = const Size(1080, 1920);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

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

        // v10 Fix #4: FAB should NOT be present in the data state.
        // The AppBar "Add" button is used instead.
        expect(
          find.byType(FloatingActionButton),
          findsNothing,
          reason: 'FamilyGraphScreen with data should NOT have a FAB — '
              'the AppBar "Add" button is used instead',
        );
      },
    );

    testWidgets(
      'v10: Empty graph (0 members) DOES show FAB',
      (tester) async {
        final emptyGraph = FlatGraphResult(
          persons: [],
          relationships: [],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              familyGraphProvider.overrideWith(
                () => _FakeFamilyGraphNotifier(emptyGraph),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: _buildTestRouter(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // FAB must be present in the empty state (0 members)
        expect(
          find.byType(FloatingActionButton),
          findsOneWidget,
          reason: 'FAB must be present in the empty state (0 members)',
        );
        expect(
          find.byIcon(Icons.person_add_alt_1_rounded),
          findsOneWidget,
          reason: 'FAB icon must be visible in the empty state',
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
