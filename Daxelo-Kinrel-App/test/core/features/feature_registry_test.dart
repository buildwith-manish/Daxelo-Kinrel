// test/core/features/feature_registry_test.dart
//
// Phase 1 unit test — verifies the Feature Registry contract:
//
//   • All defaults are `true` in Phase 1 (no visible change).
//   • Resolution order: debug override > Remote Config > default.
//   • Dependency cascade: parent OFF forces child OFF, even when the
//     child's own value is ON.
//   • Activities master switch rule: turning `activities` OFF hides
//     both `memories` AND `memberTimeline`.
//   • `isRouteDisabled` correctly resolves route prefixes through
//     the longest-prefix match (e.g. /memory-vault → memories,
//     /family/123/games → games).
//   • Every AppFeature has a matching `feature_<name>` Remote Config
//     default key (so the registry can never read a missing key).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/core/features/feature_registry.dart';
import 'package:kinrel/core/services/remote_config_service.dart';

void main() {
  // Make sure no debug overrides leak between tests.
  setUp(() async {
    // Clear any in-memory overrides from a prior test.
    for (final f in AppFeature.values) {
      if (Features.hasDebugOverride(f)) {
        await Features.clearDebugOverride(f);
      }
    }
  });

  group('Phase 4 lean defaults — ON set (20)', () {
    // The daily-use surface per the Phase 4 spec. Mirrors the `_defaults`
    // map in feature_registry.dart — if either side drifts, this test
    // catches it.
    const expectedOn = <AppFeature>{
      // Top-level nav surfaces
      AppFeature.home,
      AppFeature.familyMap,
      AppFeature.kinrel,
      AppFeature.sparqTray,
      AppFeature.feed,
      AppFeature.chat,
      AppFeature.familyChat,
      AppFeature.members,
      AppFeature.calendar,
      AppFeature.profile,
      AppFeature.profileEditing,
      AppFeature.findOnKinrel,
      // Activities cluster (master switch + children)
      AppFeature.activities,
      AppFeature.memories,
      AppFeature.memberTimeline,
      // HighlightsRow extras
      AppFeature.oralHistory,
      // Top-bar
      AppFeature.topBarNotifications,
      AppFeature.topBarSettings,
      // Home
      AppFeature.todaysQuestion,
      AppFeature.inviteBanner,
    };

    test('exactly 20 features are in the lean ON set', () {
      expect(expectedOn.length, 20);
      // Every entry must be a real AppFeature (sanity).
      for (final f in expectedOn) {
        expect(AppFeature.values.contains(f), isTrue);
      }
    });

    test('every lean-ON feature defaults to true', () {
      for (final f in expectedOn) {
        expect(
          Features.defaultOf(f),
          isTrue,
          reason: '${f.name} should default to true (lean ON set)',
        );
      }
    });

    test('every lean-ON feature is resolved ON at runtime', () {
      // Without RC initialized and without debug overrides, each lean-
      // ON feature should resolve to its compiled default (true), and
      // (for the activities cluster) the parent cascade should also
      // keep the children ON.
      for (final f in expectedOn) {
        expect(
          Features.isOn(f),
          isTrue,
          reason: '${f.name} should be ON (lean defaults)',
        );
      }
    });
  });

  group('Phase 4 lean defaults — OFF set (44)', () {
    // Everything not in the lean ON set and not `unifiedTimeline`.
    // Mirrors the `_defaults` map in feature_registry.dart.
    const expectedOff = <AppFeature>{
      AppFeature.familyJourney,
      AppFeature.sparqRunNavigation,
      AppFeature.circle,
      AppFeature.communities,
      AppFeature.games,
      AppFeature.gameInvitePush,
      AppFeature.achievements,
      AppFeature.lists,
      AppFeature.governanceTimeline,
      AppFeature.heroFamilyMap,
      AppFeature.heroKinrel,
      AppFeature.heroFindOnKinrel,
      AppFeature.heroAddMember,
      AppFeature.cameoFallback,
      AppFeature.live3DCameo,
      AppFeature.cameoStudio,
      AppFeature.voiceMessages,
      AppFeature.scheduledMessages,
      AppFeature.chatMentions,
      AppFeature.chatBlockReport,
      AppFeature.chatReactions,
      AppFeature.chatTypingIndicator,
      AppFeature.chatGallery,
      AppFeature.graphShareExport,
      AppFeature.photoPicker,
      AppFeature.qrJoin,
      AppFeature.languagePicker,
      AppFeature.audioPronunciation,
      AppFeature.autoKinshipInference,
      AppFeature.kinshipRingRow,
      AppFeature.paywall,
      AppFeature.premiumInsights,
      AppFeature.premiumExport,
      AppFeature.premiumAiKinship,
      AppFeature.memoryVault,
      AppFeature.memoryVaultFreeMonthlyCap,
      AppFeature.maxFreeMembers,
      AppFeature.maxFreeFamilies,
      AppFeature.coinPool,
      AppFeature.predictionBattle,
      AppFeature.pushGameInvite,
      AppFeature.pushReEngagement,
      AppFeature.pushMention,
      AppFeature.pushScheduledMessage,
      AppFeature.referralOnProfile,
      AppFeature.retentionNudge,
      AppFeature.aiSuggestions,
      AppFeature.onboarding,
    };

    test('exactly 44 features are in the lean OFF set', () {
      expect(expectedOff.length, 44);
    });

    test('every lean-OFF feature defaults to false', () {
      for (final f in expectedOff) {
        expect(
          Features.defaultOf(f),
          isFalse,
          reason: '${f.name} should default to false (lean OFF set)',
        );
      }
    });

    test('every lean-OFF feature is resolved OFF at runtime', () {
      for (final f in expectedOff) {
        expect(
          Features.isOn(f),
          isFalse,
          reason: '${f.name} should be OFF (lean defaults)',
        );
      }
    });

    test('ON + OFF + unifiedTimeline = enum size (sanity)', () {
      // 20 ON + 44 OFF + 1 untouched (unifiedTimeline) = 65.
      // If this fails, the enum has grown without the test being
      // updated — add the new feature to either the ON set, the OFF
      // set, or document why it's left untouched.
      const leanOnCount = 20;
      const leanOffCount = 44;
      const untouchedCount = 1;
      expect(
        AppFeature.values.length,
        leanOnCount + leanOffCount + untouchedCount,
        reason: 'enum size must equal ON + OFF + untouched counts',
      );
    });
  });

  group('Phase 4 — unifiedTimeline left untouched', () {
    test('unifiedTimeline default stays true (no UI surface, leave alone)', () {
      expect(Features.defaultOf(AppFeature.unifiedTimeline), isTrue);
      expect(Features.isOn(AppFeature.unifiedTimeline), isTrue);
    });
  });

  group('Remote Config key coverage', () {
    test('every AppFeature has a feature_<name> RC default key', () {
      // Mirrors the const _defaults map in remote_config_service.dart.
      // If a feature is missing here, Features.isOn will silently fall
      // back to the compiled default instead of honoring a server-side
      // flip — which is a regression risk we want to catch at test
      // time, not in production.
      const expectedKeys = <String>{
        'feature_home',
        'feature_family_map',
        'feature_family_journey',
        'feature_kinrel',
        'feature_sparq_tray',
        'feature_sparq_run_navigation',
        'feature_feed',
        'feature_chat',
        'feature_circle',
        'feature_communities',
        'feature_profile',
        'feature_profile_editing',
        'feature_find_on_kinrel',
        'feature_games',
        'feature_game_invite_push',
        'feature_family_chat',
        'feature_members',
        'feature_calendar',
        'feature_activities',
        'feature_memories',
        'feature_member_timeline',
        'feature_oral_history',
        'feature_achievements',
        'feature_lists',
        'feature_governance_timeline',
        'feature_unified_timeline',
        'feature_hero_family_map',
        'feature_hero_kinrel',
        'feature_hero_find_on_kinrel',
        'feature_hero_add_member',
        'feature_top_bar_notifications',
        'feature_top_bar_settings',
        'feature_cameo_fallback',
        'feature_live3d_cameo',
        'feature_cameo_studio',
        'feature_todays_question',
        'feature_voice_messages',
        'feature_scheduled_messages',
        'feature_chat_mentions',
        'feature_chat_block_report',
        'feature_chat_reactions',
        'feature_chat_typing_indicator',
        'feature_chat_gallery',
        'feature_graph_share_export',
        'feature_photo_picker',
        'feature_qr_join',
        'feature_language_picker',
        'feature_audio_pronunciation',
        'feature_auto_kinship_inference',
        'feature_kinship_ring_row',
        'feature_paywall',
        'feature_premium_insights',
        'feature_premium_export',
        'feature_premium_ai_kinship',
        'feature_memory_vault',
        'feature_memory_vault_free_monthly_cap',
        'feature_max_free_members',
        'feature_max_free_families',
        'feature_coin_pool',
        'feature_prediction_battle',
        'feature_push_game_invite',
        'feature_push_re_engagement',
        'feature_push_mention',
        'feature_push_scheduled_message',
        'feature_invite_banner',
        'feature_referral_on_profile',
        'feature_retention_nudge',
        'feature_ai_suggestions',
        'feature_onboarding',
      };

      // Sanity: the expected set covers every AppFeature exactly once.
      final expectedFromEnum = AppFeature.values
          .map((f) => 'feature_${f.name}')
          .toSet();
      expect(expectedKeys.length, AppFeature.values.length,
          reason: 'Test set length must match enum length');
      expect(
        expectedKeys.difference(expectedFromEnum),
        isEmpty,
        reason: 'Test set has keys not derivable from enum',
      );
      expect(
        expectedFromEnum.difference(expectedKeys),
        isEmpty,
        reason: 'Enum has features missing from test set',
      );

      // Each key must be present in the compiled RC defaults.
      for (final key in expectedKeys) {
        expect(
          RemoteConfigService.instance.hasKey(key),
          isTrue,
          reason: '$key missing from RemoteConfigService._defaults',
        );
      }
    });
  });

  group('Dependency map structure', () {
    test('parents map contains the six documented rules', () {
      final parents = Features.parentsMap;
      expect(parents[AppFeature.predictionBattle],
          AppFeature.coinPool);
      expect(parents[AppFeature.gameInvitePush], AppFeature.games);
      expect(parents[AppFeature.premiumInsights], AppFeature.paywall);
      expect(parents[AppFeature.familyJourney], AppFeature.familyMap);
      expect(parents[AppFeature.memories], AppFeature.activities);
      expect(parents[AppFeature.memberTimeline],
          AppFeature.activities);
    });

    test('no orphan parents — every parent is itself a feature', () {
      for (final entry in Features.parentsMap.entries) {
        final parent = entry.value;
        expect(AppFeature.values.contains(parent), isTrue,
            reason:
                'parent ${parent.name} of ${entry.key.name} is not in AppFeature');
      }
    });
  });

  group('Dependency cascade — parent OFF forces child OFF', () {
    // NOTE: setDebugOverride only takes effect in debug builds, so we
    // gate these tests on kDebugMode. In release builds the override
    // map is always empty and the registry cannot be exercised in
    // the same way at unit-test time; CI runs tests in debug.
    final isDebug = kDebugMode;

    test('activities OFF forces memories OFF and memberTimeline OFF', () {
      if (!isDebug) return;
      // Sanity baseline.
      expect(Features.isOn(AppFeature.activities), isTrue);
      expect(Features.isOn(AppFeature.memories), isTrue);
      expect(Features.isOn(AppFeature.memberTimeline), isTrue);

      // Flip activities OFF via debug override.
      Features.setDebugOverride(AppFeature.activities, false);

      // Both children must now read OFF, even though their own
      // values (default true) are unchanged.
      expect(Features.isOn(AppFeature.activities), isFalse);
      expect(Features.isOn(AppFeature.memories), isFalse,
          reason:
              'memories must be OFF when its parent activities is OFF');
      expect(Features.isOn(AppFeature.memberTimeline), isFalse,
          reason:
              'memberTimeline must be OFF when its parent activities is OFF');

      // Restore.
      Features.clearDebugOverride(AppFeature.activities);
      expect(Features.isOn(AppFeature.memories), isTrue);
      expect(Features.isOn(AppFeature.memberTimeline), isTrue);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('coinPool OFF forces predictionBattle OFF', () {
      if (!isDebug) return;
      Features.setDebugOverride(AppFeature.coinPool, false);
      expect(Features.isOn(AppFeature.coinPool), isFalse);
      expect(Features.isOn(AppFeature.predictionBattle), isFalse,
          reason:
              'predictionBattle must be OFF when coinPool is OFF');
      Features.clearDebugOverride(AppFeature.coinPool);
      expect(Features.isOn(AppFeature.predictionBattle), isTrue);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('games OFF forces gameInvitePush OFF', () {
      if (!isDebug) return;
      Features.setDebugOverride(AppFeature.games, false);
      expect(Features.isOn(AppFeature.games), isFalse);
      expect(Features.isOn(AppFeature.gameInvitePush), isFalse);
      Features.clearDebugOverride(AppFeature.games);
      expect(Features.isOn(AppFeature.gameInvitePush), isTrue);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('paywall OFF forces premiumInsights OFF', () {
      if (!isDebug) return;
      Features.setDebugOverride(AppFeature.paywall, false);
      expect(Features.isOn(AppFeature.paywall), isFalse);
      expect(Features.isOn(AppFeature.premiumInsights), isFalse);
      Features.clearDebugOverride(AppFeature.paywall);
      expect(Features.isOn(AppFeature.premiumInsights), isTrue);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('familyMap OFF forces familyJourney OFF', () {
      if (!isDebug) return;
      Features.setDebugOverride(AppFeature.familyMap, false);
      expect(Features.isOn(AppFeature.familyMap), isFalse);
      expect(Features.isOn(AppFeature.familyJourney), isFalse);
      Features.clearDebugOverride(AppFeature.familyMap);
      expect(Features.isOn(AppFeature.familyJourney), isTrue);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('child override ON does NOT override parent OFF', () {
      // Even if a debug override forces memories ON, the parent
      // cascade must still hide it when activities is OFF.
      if (!isDebug) return;
      Features.setDebugOverride(AppFeature.memories, true);
      Features.setDebugOverride(AppFeature.activities, false);
      expect(Features.isOn(AppFeature.memories), isFalse,
          reason:
              "Parent cascade must override the child's own debug override");
      Features.clearDebugOverride(AppFeature.memories);
      Features.clearDebugOverride(AppFeature.activities);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);
  });

  group('Route guard (Phase 3 wiring — declared in Phase 1)', () {
    test('unknown routes are not disabled', () {
      expect(Features.isRouteDisabled('/unknown-route-xyz'), isFalse);
      expect(Features.isRouteDisabled('/some/random/path'), isFalse);
    });

    test('Phase 1 — no route is disabled because all features are ON', () {
      // Sanity: in Phase 1 the registry should not disable any route.
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
        '/timeline',
        '/member-timeline',
        '/kinrel',
        '/sparq',
        '/feed',
        '/chat',
        '/circle',
        '/communities',
        '/profile',
        '/find-on-kinrel',
        '/games',
        '/game-invite',
        '/coin-pool',
        '/prediction-battle',
        '/todays-question',
        '/studio',
        '/paywall',
        '/premium',
        '/settings',
        '/notifications',
      ];
      for (final r in knownRoutes) {
        expect(Features.isRouteDisabled(r), isFalse,
            reason: 'Phase 1 — route $r should not be disabled');
      }
    });

    test('longest-prefix match picks the most specific feature', () {
      // /family/123/games must resolve to family/games → games,
      // not family → familyMap.
      expect(routeFeatureMap['family/games'], AppFeature.games);
      expect(routeFeatureMap['family'], AppFeature.familyMap);
      // /memory-vault must resolve to memories (so the entire memory
      // surface area is gated together).
      expect(routeFeatureMap['memory-vault'], AppFeature.memories);
      expect(routeFeatureMap['memories'], AppFeature.memories);
      expect(routeFeatureMap['memory'], AppFeature.memories);
    });
  });

  group('Resolution order', () {
    test('debug override takes precedence over default', () {
      if (!kDebugMode) return;
      // Default for kinrel is true. Force a debug override to false.
      Features.setDebugOverride(AppFeature.kinrel, false);
      expect(Features.isOn(AppFeature.kinrel), isFalse);
      Features.clearDebugOverride(AppFeature.kinrel);
      expect(Features.isOn(AppFeature.kinrel), isTrue);
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);

    test('clearing override reverts to compiled default', () {
      if (!kDebugMode) return;
      Features.setDebugOverride(AppFeature.cameoFallback, false);
      expect(Features.isOn(AppFeature.cameoFallback), isFalse);
      Features.clearDebugOverride(AppFeature.cameoFallback);
      expect(Features.isOn(AppFeature.cameoFallback),
          Features.defaultOf(AppFeature.cameoFallback));
    }, skip: !kDebugMode ? 'debug-override tests run only in debug' : null);
  });
}
