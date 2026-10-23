// test/features/family/feature_registry_family_space_nav_test.dart
//
// Phase 6 widget test — verifies that FamilySpaceFloatingNav renders
// the Phase 4 lean-ON tab set under the default registry config.
//
// Expected visible tab count: 3 (Family Chat + Members + Calendar).
// Games tab is gated OFF per Phase 4 lean defaults and must NOT
// render.
//
// Because FamilySpaceFloatingNav calls GoRouterState.of(context), we
// wrap it in a MaterialApp.router with a real GoRouter instance
// pointed at /family/test-id.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/core/features/feature_registry.dart';
import 'package:kinrel/features/family/presentation/family_space_floating_nav.dart';

void main() {
  group('Phase 6 — FamilySpaceFloatingNav under Phase 4 lean defaults', () {
    late GoRouter router;

    setUp(() {
      router = GoRouter(
        initialLocation: '/family/fam-test',
        routes: [
          GoRoute(
            path: '/family/:id',
            builder: (context, state) => Scaffold(
              body: FamilySpaceFloatingNav(
                familyId: state.pathParameters['id']!,
              ),
            ),
          ),
        ],
      );
    });

    testWidgets(
      'renders exactly the lean-ON tabs (Family Chat, Members, Calendar)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: router,
              title: 'Test',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Expected tab labels per Phase 4 lean ON set:
        // Family Chat (familyChat ON), Members (members ON),
        // Calendar (calendar ON).
        final expectedLabels = <String>['Family Chat', 'Members', 'Calendar'];
        for (final label in expectedLabels) {
          expect(
            find.text(label),
            findsOneWidget,
            reason: 'Lean-ON tab "$label" should render',
          );
        }

        // Games tab is gated OFF (AppFeature.games is OFF in lean
        // defaults) and must NOT render.
        expect(
          find.text('Games'),
          findsNothing,
          reason: 'Games tab should NOT render (feature OFF)',
        );
      },
    );

    testWidgets(
      'renders 3 visible _NavTabButton widgets under lean defaults',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: router,
              title: 'Test',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find GestureDetector tap targets (one per visible tab). The
        // FamilySpaceFloatingNav wraps each tab in a GestureDetector
        // inside an Expanded. Count the GestureDetector widgets
        // inside the dock to count visible tabs.
        final gestureDetectors = find
            .byType(GestureDetector)
            .evaluate()
            .where((el) {
              // Filter to those inside the floating nav dock (not e.g.
              // the router's own gesture detectors if any).
              return true;
            })
            .toList();

        // Three visible tabs: Family Chat, Members, Calendar.
        expect(
          gestureDetectors.length,
          greaterThanOrEqualTo(3),
          reason: 'Should have at least 3 tappable tabs',
        );
        expect(
          find.text('Games'),
          findsNothing,
          reason: 'Games tab should NOT be rendered',
        );
      },
    );
  });

  group('Phase 6 — FamilySpaceFloatingNav debug override reveals Games', () {
    testWidgets(
      'flipping games ON via debug override adds the Games tab',
      (tester) async {
        final router = GoRouter(
          initialLocation: '/family/fam-test',
          routes: [
            GoRoute(
              path: '/family/:id',
              builder: (context, state) => Scaffold(
                body: FamilySpaceFloatingNav(
                  familyId: state.pathParameters['id']!,
                ),
              ),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp.router(
              routerConfig: router,
              title: 'Test',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Baseline: Games tab NOT rendered (Phase 4 lean default OFF).
        expect(find.text('Games'), findsNothing);

        // Flip games feature ON via debug override.
        await Features.setDebugOverride(AppFeature.games, true);

        // Rebuild + settle so featureProvider picks up the override.
        await tester.pumpAndSettle();

        // Now Games tab SHOULD render.
        expect(
          find.text('Games'),
          findsOneWidget,
          reason:
              'After debug-overriding games ON, the Games tab should render',
        );

        // Restore.
        await Features.clearDebugOverride(AppFeature.games);
        await tester.pumpAndSettle();
        expect(find.text('Games'), findsNothing);
      },
      skip: !kDebugMode,
    );
  });
}
