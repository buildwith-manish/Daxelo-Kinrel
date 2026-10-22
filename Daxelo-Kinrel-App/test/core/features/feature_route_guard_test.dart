// test/core/features/feature_route_guard_test.dart
//
// Phase 3 unit test — exercises `Features.isRouteDisabled(path)` for
// every entry in `routeFeatureMap`, plus the longest-prefix-match rule
// and the Phase 1 contract (no route disabled while all features ON).
//
// Also exercises the activities master-switch rule by toggling the
// `activities` feature off via debug override and confirming that
// /memories + /memory-vault routes are disabled together (because
// they're both mapped to AppFeature.memories which depends on
// activities in the `_parents` map).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/core/features/feature_registry.dart';

void main() {
  setUp(() async {
    // Clear any debug overrides from prior tests.
    for (final f in AppFeature.values) {
      if (Features.hasDebugOverride(f)) {
        await Features.clearDebugOverride(f);
      }
    }
  });

  group('Phase 3 route guard — Phase 1 contract', () {
    test('no known route is disabled while all features are ON', () {
      // Phase 1's all-true defaults → no route should redirect.
      const knownRoutes = <String>[
        '/home',
        '/family',
        '/family/123',
        '/family/123/games',
        '/family/123/chat',
        '/family/123/members',
        '/family/123/calendar',
        '/memories',
        '/memory-vault',
        '/memory-vault/456',
        '/memory',
        '/memory/create',
        '/timeline',
        '/member-timeline',
        '/governance',
        '/oral-history',
        '/achievements',
        '/lists',
        '/kinrel',
        '/sparq',
        '/sparq/family/abc',
        '/feed',
        '/chat',
        '/chat/dm/abc',
        '/circle',
        '/circle/abc',
        '/communities',
        '/profile',
        '/profile/settings',
        '/profile/alarms',
        '/find-on-kinrel',
        '/games',
        '/game-invite',
        '/game-invite/abc',
        '/coin-pool',
        '/prediction-battle',
        '/prediction-battle/abc',
        '/todays-question',
        '/studio',
        '/paywall',
        '/premium',
        '/settings',
        '/notifications',
      ];
      for (final route in knownRoutes) {
        expect(
          Features.isRouteDisabled(route),
          isFalse,
          reason:
              'Phase 1 — route $route should NOT be disabled (all features ON)',
        );
      }
    });

    test('unknown routes are never disabled', () {
      // Routes not in routeFeatureMap return false (allowed).
      expect(Features.isRouteDisabled('/totally-unknown-route'), isFalse);
      expect(Features.isRouteDisabled('/some/random/path'), isFalse);
      expect(Features.isRouteDisabled('/'), isFalse);
      expect(Features.isRouteDisabled(''), isFalse);
    });

    test('debug routes are skipped even when activities is OFF', () {
      // The debug feature-switches screen must remain reachable so
      // a feature can be toggled back ON. Phase 3's redirect skips
      // /debug + /debug/features explicitly.
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.activities, false);
      expect(Features.isRouteDisabled('/debug/features'), isFalse);
      expect(Features.isRouteDisabled('/debug'), isFalse);
      Features.clearDebugOverride(AppFeature.activities);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);
  });

  group('Phase 3 route guard — longest-prefix match', () {
    test('/family/123/games resolves to games (not family)', () {
      // The map has both 'family' and 'family/games'. The route
      // /family/123/games must match family/games (the longer prefix)
      // so its feature is games, not familyMap.
      //
      // Phase 1 (all ON) → not disabled, but the underlying lookup
      // must still resolve correctly. We exercise this by toggling
      // games OFF and confirming /family/123/games is disabled while
      // /family/123 itself is NOT (familyMap is still ON).
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.games, false);

      expect(Features.isRouteDisabled('/family/123/games'), isTrue,
          reason: '/family/123/games must resolve to games feature');
      expect(Features.isRouteDisabled('/family/123'), isFalse,
          reason: '/family/123 must resolve to familyMap, not games');
      expect(Features.isRouteDisabled('/families'), isFalse,
          reason: '/families must NOT be affected by games toggle');

      Features.clearDebugOverride(AppFeature.games);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('/memory-vault + /memories + /memory all map to memories', () {
      // All three surface-area prefixes route to AppFeature.memories.
      // Phase 1 contract: all are NOT disabled. We exercise the
      // shared gate by toggling memories OFF and confirming all
      // three are disabled together.
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.memories, false);

      expect(Features.isRouteDisabled('/memories'), isTrue);
      expect(Features.isRouteDisabled('/memory-vault'), isTrue);
      expect(Features.isRouteDisabled('/memory'), isTrue);
      expect(Features.isRouteDisabled('/memory-vault/abc'), isTrue);
      expect(Features.isRouteDisabled('/memory/create'), isTrue);

      Features.clearDebugOverride(AppFeature.memories);
      expect(Features.isRouteDisabled('/memories'), isFalse);
      expect(Features.isRouteDisabled('/memory-vault'), isFalse);
      expect(Features.isRouteDisabled('/memory'), isFalse);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);
  });

  group('Phase 3 — activities master-switch rule', () {
    test(
        'turning activities OFF disables /memories + /memory-vault routes '
        '(memories depends on activities)', () {
      // The user's clarification: "turn on activities means memories
      // and timeline feature." When activities is OFF, memories (its
      // child in the dependency map) is forced OFF, which in turn
      // disables the memories + memory-vault routes via the
      // routeFeatureMap.
      if (!kDebugMode) return;

      // Sanity baseline.
      expect(Features.isOn(AppFeature.activities), isTrue);
      expect(Features.isOn(AppFeature.memories), isTrue);
      expect(Features.isRouteDisabled('/memories'), isFalse);
      expect(Features.isRouteDisabled('/memory-vault'), isFalse);

      // Flip activities OFF via debug override.
      Features.setDebugOverride(AppFeature.activities, false);

      // memories cascades OFF (parent OFF → child forced OFF).
      expect(Features.isOn(AppFeature.activities), isFalse);
      expect(Features.isOn(AppFeature.memories), isFalse,
          reason: 'memories must be OFF when parent activities is OFF');

      // Routes map to memories → disabled.
      expect(Features.isRouteDisabled('/memories'), isTrue,
          reason: '/memories must be disabled when activities is OFF');
      expect(Features.isRouteDisabled('/memory-vault'), isTrue,
          reason: '/memory-vault must be disabled when activities is OFF');
      expect(Features.isRouteDisabled('/memory'), isTrue,
          reason: '/memory must be disabled when activities is OFF');

      // memberTimeline also depends on activities — its routes
      // (/timeline + /member-timeline) must be disabled too.
      expect(Features.isOn(AppFeature.memberTimeline), isFalse,
          reason: 'memberTimeline must be OFF when activities is OFF');
      expect(Features.isRouteDisabled('/timeline'), isTrue);
      expect(Features.isRouteDisabled('/member-timeline'), isTrue);

      // Restore.
      Features.clearDebugOverride(AppFeature.activities);
      expect(Features.isRouteDisabled('/memories'), isFalse);
      expect(Features.isRouteDisabled('/memory-vault'), isFalse);
      expect(Features.isRouteDisabled('/timeline'), isFalse);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);
  });

  group('Phase 3 — other dependency cascades via routes', () {
    test('games OFF disables /games route (gameInvitePush cascades)', () {
      // gameInvitePush depends on games. When games is OFF,
      // gameInvitePush is forced OFF too. Both /games and
      // /game-invite routes must be disabled.
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.games, false);

      expect(Features.isRouteDisabled('/games'), isTrue);
      expect(Features.isRouteDisabled('/game-invite'), isTrue);
      expect(Features.isRouteDisabled('/game-invite/abc'), isTrue);

      Features.clearDebugOverride(AppFeature.games);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('coinPool OFF disables /coin-pool + /prediction-battle routes', () {
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.coinPool, false);

      expect(Features.isRouteDisabled('/coin-pool'), isTrue);
      expect(Features.isRouteDisabled('/prediction-battle'), isTrue);

      Features.clearDebugOverride(AppFeature.coinPool);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('paywall OFF disables /paywall + /premium routes', () {
      // premiumInsights depends on paywall.
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.paywall, false);

      expect(Features.isRouteDisabled('/paywall'), isTrue);
      expect(Features.isRouteDisabled('/premium'), isTrue);

      Features.clearDebugOverride(AppFeature.paywall);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('familyMap OFF disables /family route (familyJourney cascades)', () {
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.familyMap, false);

      expect(Features.isRouteDisabled('/family'), isTrue);
      expect(Features.isRouteDisabled('/family-journey'), isTrue);

      Features.clearDebugOverride(AppFeature.familyMap);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);
  });
}
