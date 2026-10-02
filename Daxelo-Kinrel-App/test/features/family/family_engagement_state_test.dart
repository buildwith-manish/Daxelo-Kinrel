// test/features/family/family_engagement_state_test.dart
//
// Phase (family-state-aware-home-screen): tests for the family
// engagement state provider + section ordering function.
//
// Verifies the three required behaviours per the design brief:
//
//   1. familyEngagementStateProvider correctly returns:
//        - newSmall                  for a family with < 3 members
//        - establishedLowActivity    for >= 3 members with no recent activity
//        - establishedActive         for >= 3 members with recent activity
//
//   2. sectionOrderFor changes the FIRST content section based on the
//      state:
//        - newSmall                → Invite
//        - establishedLowActivity  → FamilyPulse
//        - establishedActive       → PredictionBattle
//
//   3. Premium Insights never renders before Invite / Prediction
//      Battle / Family Pulse in any state — it is always LAST among
//      the dynamic content sections.
//
//   4. INVARIANT: Invite is always within the first 1–2 sections in
//      every state (never demoted far down).
//
// The pure helper `classifyEngagementState` is used for the
// classification tests so they don't need Riverpod wiring. The
// `sectionOrderFor` tests are pure-function tests over the enum.

import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/family/presentation/providers/family_engagement_state_provider.dart';

void main() {
  group('classifyEngagementState — pure classification helper', () {
    final now = DateTime(2026, 10, 2, 12, 0, 0);

    test('newSmall: member count < 3 regardless of activity', () {
      // 0 members
      expect(
        classifyEngagementState(
          memberCount: 0,
          recentActivityTimestamps: const [],
          now: now,
        ),
        FamilyEngagementState.newSmall,
        reason: '0 members → newSmall',
      );

      // 1 member
      expect(
        classifyEngagementState(
          memberCount: 1,
          recentActivityTimestamps: const [],
          now: now,
        ),
        FamilyEngagementState.newSmall,
        reason: '1 member → newSmall',
      );

      // 2 members — even with very recent activity, still newSmall
      // (member count is the gating factor).
      expect(
        classifyEngagementState(
          memberCount: 2,
          recentActivityTimestamps: [now.subtract(const Duration(hours: 1))],
          now: now,
        ),
        FamilyEngagementState.newSmall,
        reason: '2 members → newSmall even with recent activity',
      );
    });

    test(
        'establishedLowActivity: member count >= 3 AND no activity in '
        'the last 7 days', () {
      // 3 members, no activity at all
      expect(
        classifyEngagementState(
          memberCount: 3,
          recentActivityTimestamps: const [],
          now: now,
        ),
        FamilyEngagementState.establishedLowActivity,
      );

      // 5 members, activity older than 7 days
      expect(
        classifyEngagementState(
          memberCount: 5,
          recentActivityTimestamps: [
            now.subtract(const Duration(days: 8)),
            now.subtract(const Duration(days: 30)),
          ],
          now: now,
        ),
        FamilyEngagementState.establishedLowActivity,
        reason: 'Activity older than 7 days counts as low activity',
      );

      // Edge: activity EXACTLY 7 days ago should NOT count as recent
      // (isAfter is strict — exactly 7 days ago is not after the cutoff).
      expect(
        classifyEngagementState(
          memberCount: 4,
          recentActivityTimestamps: [
            now.subtract(const Duration(days: 7)),
          ],
          now: now,
        ),
        FamilyEngagementState.establishedLowActivity,
        reason: 'Activity exactly 7 days ago is NOT within the last 7 days '
            '(isAfter is strict).',
      );
    });

    test(
        'establishedActive: member count >= 3 AND at least one activity '
        'event in the last 7 days', () {
      // 3 members, activity 1 hour ago
      expect(
        classifyEngagementState(
          memberCount: 3,
          recentActivityTimestamps: [
            now.subtract(const Duration(hours: 1)),
          ],
          now: now,
        ),
        FamilyEngagementState.establishedActive,
      );

      // 10 members, activity 6 days ago (just within the window)
      expect(
        classifyEngagementState(
          memberCount: 10,
          recentActivityTimestamps: [
            now.subtract(const Duration(days: 6, hours: 23)),
          ],
          now: now,
        ),
        FamilyEngagementState.establishedActive,
        reason: 'Activity 6d23h ago is within the 7-day window',
      );

      // 3 members, mix of old + recent activity → establishedActive
      // (any single recent event is enough)
      expect(
        classifyEngagementState(
          memberCount: 3,
          recentActivityTimestamps: [
            now.subtract(const Duration(days: 30)), // old
            now.subtract(const Duration(minutes: 5)), // recent
          ],
          now: now,
        ),
        FamilyEngagementState.establishedActive,
      );
    });
  });

  group('sectionOrderFor — first content section matches design brief', () {
    test('newSmall → Invite is the FIRST content section', () {
      final order = sectionOrderFor(FamilyEngagementState.newSmall);
      expect(order.first, FamilySection.invite,
          reason: 'New/small family should see Invite first to grow the '
              'family.');
    });

    test(
        'establishedLowActivity → FamilyPulse is the FIRST content section',
        () {
      final order =
          sectionOrderFor(FamilyEngagementState.establishedLowActivity);
      expect(order.first, FamilySection.familyPulse,
          reason: 'Quiet established family should see Recent Activity '
              'first to nudge re-engagement.');
    });

    test(
        'establishedActive → PredictionBattle is the FIRST content section',
        () {
      final order = sectionOrderFor(FamilyEngagementState.establishedActive);
      expect(order.first, FamilySection.predictionBattle,
          reason: 'Active established family should see time-sensitive '
              'Prediction Battle first.');
    });
  });

  group(
      'sectionOrderFor — Premium Insights never renders before Invite / '
      'Prediction Battle / Family Pulse', () {
    // The design brief: Premium Insights must render AFTER all free-value
    // content sections (Invite, Thinking of You, Prediction Battle, Coin
    // Pool, Family Pulse, Memories/shortcut content) — i.e., it should
    // be one of the LAST things a user scrolls to.
    //
    // We verify this for all three engagement states.
    for (final state in FamilyEngagementState.values) {
      test('${state.name}: Premium Insights is the LAST section in the order',
          () {
        final order = sectionOrderFor(state);
        expect(order.last, FamilySection.premiumInsights,
            reason: 'Premium Insights must always be the LAST section in '
                'every engagement state. State $state produced order: $order');
      });

      test(
          '${state.name}: Premium Insights never appears before Invite, '
          'PredictionBattle, or FamilyPulse', () {
        final order = sectionOrderFor(state);
        final premiumIdx = order.indexOf(FamilySection.premiumInsights);
        final inviteIdx = order.indexOf(FamilySection.invite);
        final pbIdx = order.indexOf(FamilySection.predictionBattle);
        final pulseIdx = order.indexOf(FamilySection.familyPulse);

        expect(premiumIdx, greaterThan(inviteIdx),
            reason: 'Premium Insights must come after Invite.');
        expect(premiumIdx, greaterThan(pbIdx),
            reason: 'Premium Insights must come after Prediction Battle.');
        expect(premiumIdx, greaterThan(pulseIdx),
            reason: 'Premium Insights must come after Family Pulse.');
      });
    }
  });

  group('sectionOrderFor — Invite is always within the first 1–2 sections', () {
    // The design brief: Invite Family Member remains visible and reachable
    // within the first 1–2 screen scrolls regardless of state — it should
    // never be demoted far down regardless of state; only its exact
    // position (first vs. second/third section) changes by state.
    test('newSmall: Invite is first (index 0)', () {
      final order = sectionOrderFor(FamilyEngagementState.newSmall);
      expect(order.indexOf(FamilySection.invite), 0);
    });

    test('establishedLowActivity: Invite is within first 2 sections', () {
      final order =
          sectionOrderFor(FamilyEngagementState.establishedLowActivity);
      final inviteIdx = order.indexOf(FamilySection.invite);
      expect(inviteIdx, lessThanOrEqualTo(1),
          reason: 'Invite must be within first 2 sections in low-activity '
              'state. Got index $inviteIdx in order: $order');
    });

    test('establishedActive: Invite is within first 2 sections', () {
      final order = sectionOrderFor(FamilyEngagementState.establishedActive);
      final inviteIdx = order.indexOf(FamilySection.invite);
      expect(inviteIdx, lessThanOrEqualTo(1),
          reason: 'Invite must be within first 2 sections in active state. '
              'Got index $inviteIdx in order: $order');
    });
  });

  group('sectionOrderFor — MiniGraphPreview positioned before PremiumInsights', () {
    // The design brief: the mini graph preview card is a new section to
    // insert into the ordering, reasonably placed after Memories/Activity
    // content, before Premium Insights.
    for (final state in FamilyEngagementState.values) {
      test('${state.name}: miniGraphPreview comes before premiumInsights', () {
        final order = sectionOrderFor(state);
        final graphIdx = order.indexOf(FamilySection.miniGraphPreview);
        final premiumIdx = order.indexOf(FamilySection.premiumInsights);

        expect(graphIdx, greaterThanOrEqualTo(0),
            reason: 'MiniGraphPreview must be present in every state\'s '
                'section order.');
        expect(graphIdx, lessThan(premiumIdx),
            reason: 'MiniGraphPreview must come before PremiumInsights. '
                'State $state produced order: $order');
      });
    }
  });

  group('sectionOrderFor — all expected sections are present', () {
    // Sanity check: every ordering function output must contain ALL
    // seven content sections exactly once (no missing sections, no
    // duplicates).
    for (final state in FamilyEngagementState.values) {
      test('${state.name}: contains all 7 sections exactly once', () {
        final order = sectionOrderFor(state);
        expect(order.length, FamilySection.values.length,
            reason: 'Every section must be present exactly once. '
                'State $state produced order: $order');
        // No duplicates: set size equals list size
        expect(order.toSet().length, order.length,
            reason: 'No duplicate sections allowed. '
                'State $state produced order: $order');
      });
    }
  });
}
