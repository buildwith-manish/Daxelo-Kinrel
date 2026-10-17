// test/features/family/removed_branch_buttons_test.dart
//
// The approved-preview interaction model REMOVED two UI entry points:
//
//   1. The "Show All Branches" toolbar button (+ its warning dialog) —
//      everyone is revealed via "+N" paging bubbles, search reveal, and
//      the stats panel's "View all N" list instead.
//   2. The "Collapse this branch" entry in the long-press action sheet —
//      collapsing now happens by tapping the focused, expanded person.
//
// These tests pin both removals (and that the long-press sheet KEEPS
// its "Preview full names list" entry, per the spec).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/features/family/presentation/family_graph_screen.dart';
import 'package:kinrel/features/family/presentation/providers/family_graph_provider.dart';
import 'package:kinrel/graph/widgets/graph_quick_actions.dart';
import 'package:kinrel/graph/widgets/graph_relationship_labels.dart';

class _FakeFamilyGraphNotifier extends FamilyGraphNotifier {
  _FakeFamilyGraphNotifier(this._graphData);

  final FlatGraphResult _graphData;

  @override
  Future<FlatGraphResult> build(String familyId) async {
    return _graphData;
  }
}

FlatGraphResult _fourMemberGraph() {
  return const FlatGraphResult(
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

GoRouter _testRouter() {
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
        builder: (context, state) =>
            const Scaffold(body: Text('Add Person Page')),
      ),
    ],
  );
}

void main() {
  testWidgets('the "Show All Branches" toolbar button no longer renders',
      (tester) async {
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
            () => _FakeFamilyGraphNotifier(_fourMemberGraph()),
          ),
        ],
        child: MaterialApp.router(routerConfig: _testRouter()),
      ),
    );
    // Fixed pumps — the graph runs always-on animations by design
    // (ambient particles, node glow) so pumpAndSettle never settles.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byTooltip('Show All Branches'), findsNothing,
        reason: 'The toolbar button was removed — the only ways to '
            'reveal everyone are +N paging, search reveal, and the '
            '"View all" list.');
    // NOTE: Icons.account_tree_outlined is NOT asserted globally — the
    // FamilySpaceTabBar's legitimate "Graph" tab segment uses the same
    // icon. The tooltip (the button's accessible identity) is the
    // authoritative check that the Show-All entry point is gone.
  });

  testWidgets('the long-press sheet keeps "Preview full names list" but '
      'no longer renders "Collapse this branch"', (tester) async {
    // The sheet is TALL — give it a phone-sized viewport so the
    // Column of actions never overflows in the test harness.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var previewTapped = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    GraphQuickActions.show(
                      context,
                      const GraphPersonData(
                        id: 'p1',
                        name: 'Kishan',
                        gender: 'male',
                      ),
                      familyId: 'test-id',
                      branchCollapseInfo: BranchCollapseInfo(
                        onCollapse: () {},
                        onPreviewNames: () => previewTapped = true,
                      ),
                    );
                  },
                  child: const Text('Open sheet'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    // The collapse entry is GONE...
    expect(find.text('Collapse this branch'), findsNothing,
        reason: 'Collapsing now works by tapping the focused, expanded '
            'person — the sheet entry was removed.');
    // ...but the preview entry the spec keeps is still there and works.
    expect(find.text('Preview full names list'), findsOneWidget);
    await tester.tap(find.text('Preview full names list'));
    await tester.pumpAndSettle();
    expect(previewTapped, isTrue);
  });
}
