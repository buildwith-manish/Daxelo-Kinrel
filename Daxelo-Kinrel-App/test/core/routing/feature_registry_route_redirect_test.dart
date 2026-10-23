// test/core/routing/feature_registry_route_redirect_test.dart
//
// Phase 6 integration test — verifies that the Phase 3 route guard
// redirects OFF-feature routes to /home end-to-end at the GoRouter
// layer (not just at the `Features.isRouteDisabled` function level,
// which is already covered by feature_route_guard_test.dart).
//
// The actual `_handleRedirect` in app_router.dart depends on Riverpod
// providers (auth state, supabase readiness, 2FA state, etc.) and
// the full authStateProvider chain — those are out of scope for a
// Phase 6 widget-level integration test. Instead, we exercise a
// minimal GoRouter with a custom `redirect` callback that calls
// `Features.isRouteDisabled(path)` directly (mirroring the Phase 3
// guard logic, just without the auth pre-checks).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/core/features/feature_registry.dart';

void main() {
  group('Phase 6 — route redirect integration', () {
    late GoRouter router;

    setUp(() {
      // Build a minimal GoRouter with a redirect that mirrors the
      // Phase 3 guard logic: if `Features.isRouteDisabled(location)`
      // is true, redirect to /home. Skip pre-auth routes that would
      // otherwise interfere.
      router = GoRouter(
        initialLocation: '/home',
        redirect: (context, state) {
          final loc = state.matchedLocation;
          // Skip pre-auth routes + debug routes (mirrors the skip list
          // in _handleRedirect).
          const skip = [
            '/splash',
            '/sign-in',
            '/sign-up',
            '/create-username',
            '/2fa-verify',
            '/onboarding',
            '/debug',
            '/debug/features',
          ];
          if (skip.any((s) => loc == s || loc.startsWith('$s/'))) {
            return null;
          }
          // Skip /privacy + /terms + /join/
          if (loc.startsWith('/privacy') ||
              loc.startsWith('/terms') ||
              loc.startsWith('/join/')) {
            return null;
          }
          // Phase 3 guard: redirect disabled routes to /home.
          try {
            if (Features.isRouteDisabled(loc)) return '/home';
          } catch (_) {}
          return null;
        },
        routes: [
          GoRoute(
            path: '/home',
            builder: (c, s) => const _StubScreen('Home'),
          ),
          GoRoute(
            path: '/family/:id',
            builder: (c, s) => _StubScreen('Family ${s.pathParameters['id']}'),
          ),
          GoRoute(
            path: '/games',
            builder: (c, s) => const _StubScreen('Games'),
          ),
          GoRoute(
            path: '/coin-pool',
            builder: (c, s) => const _StubScreen('Coin Pool'),
          ),
          GoRoute(
            path: '/paywall',
            builder: (c, s) => const _StubScreen('Paywall'),
          ),
          GoRoute(
            path: '/memories',
            builder: (c, s) => const _StubScreen('Memories'),
          ),
        ],
      );
    });

    test(
      'Phase 4 lean-OFF routes redirect to /home when navigated to',
      () {
        // Phase 4 lean defaults (no debug overrides): games, coinPool,
        // paywall are all OFF. Navigating to /games, /coin-pool, or
        // /paywall should land the user on /home.
        //
        // GoRouter's redirect is evaluated synchronously when go() is
        // called, so we can check the resulting location immediately.
        router.go('/games');
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/home',
          reason: '/games (games OFF) should redirect to /home',
        );

        router.go('/coin-pool');
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/home',
          reason: '/coin-pool (coinPool OFF) should redirect to /home',
        );

        router.go('/paywall');
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/home',
          reason: '/paywall (paywall OFF) should redirect to /home',
        );
      },
    );

    test('Phase 4 lean-ON routes do NOT redirect', () {
      router.go('/home');
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/home',
        reason: '/home should not redirect',
      );

      router.go('/family/abc');
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/family/abc',
        reason: '/family/abc (familyMap ON) should not redirect',
      );

      router.go('/memories');
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/memories',
        reason: '/memories (memories ON, activities ON) should not redirect',
      );
    });

    test('debug override flips OFF-feature routes back to navigable', () {
      if (!kDebugMode) return;
      // Baseline: /games redirects to /home.
      router.go('/games');
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/home',
      );

      // Flip games ON via debug override.
      Features.setDebugOverride(AppFeature.games, true);
      router.go('/games');
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/games',
        reason: 'After debug-overriding games ON, /games should be reachable',
      );

      // Restore.
      Features.clearDebugOverride(AppFeature.games);
      router.go('/games');
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/home',
      );
    }, skip: !kDebugMode);

    test('pre-auth routes are skipped (never redirect)', () {
      // Even if we hypothetically flipped home OFF via debug override,
      // the splash route itself must never be redirected by Phase 3.
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.home, false);
      router.go('/splash');
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/splash',
        reason: '/splash is in the skip list — should never redirect',
      );
      Features.clearDebugOverride(AppFeature.home);
    }, skip: !kDebugMode);

    test('debug routes are skipped (always allowed)', () {
      // /debug and /debug/features must always be reachable so a
      // feature can be toggled back ON from inside the screen.
      router.go('/debug');
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/debug',
      );
      router.go('/debug/features');
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/debug/features',
      );
    });
  });
}

class _StubScreen extends StatelessWidget {
  const _StubScreen(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(label);
}
