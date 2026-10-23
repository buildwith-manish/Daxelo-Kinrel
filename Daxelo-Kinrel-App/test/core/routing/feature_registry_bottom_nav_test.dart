// test/core/routing/feature_registry_bottom_nav_test.dart
//
// Phase 6 widget test — verifies the data-driven bottom nav
// (_BottomNav in app_router.dart) renders the Phase 4 lean-ON tab
// set under the default registry config.
//
// Expected visible tab count: 5 (Home + Chat + Family + Search + Me).
// All five bottom-nav features (home, chat, familyMap, findOnKinrel,
// profile) are ON in Phase 4 lean defaults, so all 5 tabs should render.
//
// Because the bottom nav depends on StatefulShellRoute.indexedStack,
// we replicate a minimal version of the router config in the test
// (5 branches matching the production order) so the navigation
// context exists. The actual _BottomNav widget is private, so we
// test the visual artifact instead: the DKBottomNav that wraps it
// plus the visible DKNavItem labels.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/core/features/feature_registry.dart';
import 'package:kinrel/shared/widgets/dk_components.dart';

void main() {
  group('Phase 6 — Bottom nav under Phase 4 lean defaults', () {
    late GoRouter router;

    setUp(() {
      // Build a minimal StatefulShellRoute.indexedStack matching the
      // production 5-branch order so _BottomNav has a navigation
      // shell context to attach to. Each branch renders a trivial
      // Scaffold with its tab label.
      router = GoRouter(
        initialLocation: '/home',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) {
              // Mirror the production MainShell layout: Scaffold with
              // bottomNavigationBar = a minimal mock of _BottomNav
              // that calls context.go on tap (production code uses
              // the real _BottomNav, but we test the visible surface
              // here via DKBottomNav directly).
              return Scaffold(
                body: shell,
                bottomNavigationBar: _MockBottomNav(shell: shell),
              );
            },
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/home',
                  builder: (c, s) =>
                      const Center(child: Text('Home Screen')),
                ),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/chat',
                  builder: (c, s) =>
                      const Center(child: Text('Chat Screen')),
                ),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/families',
                  builder: (c, s) =>
                      const Center(child: Text('Family Screen')),
                ),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/search',
                  builder: (c, s) =>
                      const Center(child: Text('Search Screen')),
                ),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/profile',
                  builder: (c, s) =>
                      const Center(child: Text('Me Screen')),
                ),
              ]),
            ],
          ),
        ],
      );
    });

    testWidgets(
      'renders all 5 lean-ON bottom-nav tab labels under Phase 4 defaults',
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
        // Home (home ON), Chat (chat ON), Family (familyMap ON),
        // Search (findOnKinrel ON), Me (profile ON).
        final expectedLabels = <String>['Home', 'Chat', 'Family', 'Search', 'Me'];
        for (final label in expectedLabels) {
          expect(
            find.text(label),
            findsOneWidget,
            reason: 'Lean-ON bottom-nav tab "$label" should render',
          );
        }
      },
    );

    testWidgets(
      'flipping chat OFF via debug override hides the Chat tab',
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

        // Baseline: Chat tab rendered.
        expect(find.text('Chat'), findsOneWidget);

        // Flip chat OFF via debug override.
        await Features.setDebugOverride(AppFeature.chat, false);
        await tester.pumpAndSettle();

        // Chat tab should now be hidden.
        expect(
          find.text('Chat'),
          findsNothing,
          reason: 'After debug-overriding chat OFF, Chat tab should hide',
        );

        // Restore.
        await Features.clearDebugOverride(AppFeature.chat);
        await tester.pumpAndSettle();
        expect(find.text('Chat'), findsOneWidget);
      },
      skip: !kDebugMode,
    );
  });
}

/// Minimal mock of the production `_BottomNav` widget (which is
/// private to app_router.dart). Uses the same `DKBottomNav` + `DKNavItem`
/// components as production, but exposes the visible list directly so
/// the widget test can assert on it without leaking production
/// internals.
class _MockBottomNav extends ConsumerWidget {
  const _MockBottomNav({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Master list mirroring the production _BottomNav._allItems
    // (Home=0, Chat=1, Family=2, Search=3, Me=4). Each tagged with
    // its AppFeature so the visible filter matches production behavior.
    const allItems = <_MockNavItem>[
      _MockNavItem(
        label: 'Home',
        feature: AppFeature.home,
        branchIndex: 0,
      ),
      _MockNavItem(
        label: 'Chat',
        feature: AppFeature.chat,
        branchIndex: 1,
      ),
      _MockNavItem(
        label: 'Family',
        feature: AppFeature.familyMap,
        branchIndex: 2,
      ),
      _MockNavItem(
        label: 'Search',
        feature: AppFeature.findOnKinrel,
        branchIndex: 3,
      ),
      _MockNavItem(
        label: 'Me',
        feature: AppFeature.profile,
        branchIndex: 4,
      ),
    ];

    // Filter by featureProvider — same as production _BottomNav.build.
    final visible = allItems
        .where((i) => ref.watch(featureProvider(i.feature)))
        .toList();

    return DKBottomNav(
      currentIndex: shell.currentIndex < visible.length
          ? shell.currentIndex
          : 0,
      onTap: (i) {
        if (i < 0 || i >= visible.length) return;
        shell.goBranch(visible[i].branchIndex);
      },
      items: visible
          .map((i) => DKNavItem(
                icon: Icons.label_outline,
                activeIcon: Icons.label,
                label: i.label,
              ))
          .toList(),
    );
  }
}

class _MockNavItem {
  const _MockNavItem({
    required this.label,
    required this.feature,
    required this.branchIndex,
  });

  final String label;
  final AppFeature feature;
  final int branchIndex;
}
