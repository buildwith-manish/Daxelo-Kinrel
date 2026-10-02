// test/features/family/family_engagement_state_test.dart
//
// Layout-restoration brief: tests for the family engagement state
// provider + section ordering function.
//
// Verifies the fixed layout order:
//   1. Prediction Battle is ALWAYS the first content card (regardless
//      of engagement state — the order is no longer dynamic).
//   2. Family Pulse comes after Prediction Battle.
//   3. Premium Insights comes after Prediction Battle and Family Pulse
//      (free-value content before the paywall).
//   4. No standalone Coin Pool section (it's part of Prediction Battle).
//   5. No standalone Family Graph preview card (removed from the feed).
//   6. All expected sections are present exactly once.
//
// The pure helper `classifyEngagementState` is still tested for
// correct classification (the engagement state is still computed for
// analytics/future use even though the layout is now fixed).

import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/family/presentation/providers/family_engagement_state_provider.dart';

void main() {
  group('classifyEngagementState — pure classification helper', () {
    final now = DateTime(2026, 10, 2, 12, 0, 0);

    test('newSmall: member count < 3 regardless of activity', () {
      expect(
        classifyEngagementState(
          memberCount: 0,
          recentActivityTimestamps: const [],
          now: now,
        ),
        FamilyEngagementState.newSmall,
      );
      expect(
        classifyEngagementState(
          memberCount: 1,
          recentActivityTimestamps: const [],
          now: now,
        ),
        FamilyEngagementState.newSmall,
      );
      expect(
        classifyEngagementState(
          memberCount: 2,
          recentActivityTimestamps: [now.subtract(const Duration(hours: 1))],
          now: now,
        ),
        FamilyEngagementState.newSmall,
      );
    });

    test(
        'establishedLowActivity: member count >= 3 AND no activity in '
        'the last 7 days', () {
      expect(
        classifyEngagementState(
          memberCount: 3,
          recentActivityTimestamps: const [],
          now: now,
        ),
        FamilyEngagementState.establishedLowActivity,
      );
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
      );
    });

    test(
        'establishedActive: member count >= 3 AND at least one activity '
        'event in the last 7 days', () {
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
      expect(
        classifyEngagementState(
          memberCount: 10,
          recentActivityTimestamps: [
            now.subtract(const Duration(days: 6, hours: 23)),
          ],
          now: now,
        ),
        FamilyEngagementState.establishedActive,
      );
    });
  });

  group('sectionOrderFor — FIXED order (content-hierarchy refinement)', () {
    // The order is now FIXED — the same for all engagement states.
    // Flow: PB (engagement) → Thinking of You (emotion) → Pulse (updates)
    // → Premium Insights → remaining.
    for (final state in FamilyEngagementState.values) {
      test('${state.name}: Prediction Battle is the FIRST content section',
          () {
        final order = sectionOrderFor(state);
        expect(order.first, FamilySection.predictionBattle,
            reason: 'Prediction Battle must ALWAYS be the first content '
                'card below the header, regardless of engagement state. '
                'State $state produced order: $order');
      });

      test(
          '${state.name}: Thinking of You is directly below Prediction Battle '
          '(position 2, above Family Pulse)', () {
        final order = sectionOrderFor(state);
        final pbIdx = order.indexOf(FamilySection.predictionBattle);
        final toyIdx = order.indexOf(FamilySection.thinkingOfYou);
        final pulseIdx = order.indexOf(FamilySection.familyPulse);

        expect(toyIdx, pbIdx + 1,
            reason: 'Thinking of You must be DIRECTLY below Prediction '
                'Battle (position 2). State $state produced order: $order');
        expect(toyIdx, lessThan(pulseIdx),
            reason: 'Thinking of You must come ABOVE Family Pulse. '
                'State $state produced order: $order');
      });

      test('${state.name}: Family Pulse comes after Thinking of You', () {
        final order = sectionOrderFor(state);
        final toyIdx = order.indexOf(FamilySection.thinkingOfYou);
        final pulseIdx = order.indexOf(FamilySection.familyPulse);
        expect(pulseIdx, greaterThan(toyIdx),
            reason: 'Family Pulse must come after Thinking of You. '
                'State $state produced order: $order');
      });

      test(
          '${state.name}: Premium Insights comes after Prediction Battle, '
          'Thinking of You, and Family Pulse', () {
        final order = sectionOrderFor(state);
        final premiumIdx = order.indexOf(FamilySection.premiumInsights);
        final pbIdx = order.indexOf(FamilySection.predictionBattle);
        final toyIdx = order.indexOf(FamilySection.thinkingOfYou);
        final pulseIdx = order.indexOf(FamilySection.familyPulse);

        expect(premiumIdx, greaterThan(pbIdx),
            reason: 'Premium Insights must come after Prediction Battle.');
        expect(premiumIdx, greaterThan(toyIdx),
            reason: 'Premium Insights must come after Thinking of You.');
        expect(premiumIdx, greaterThan(pulseIdx),
            reason: 'Premium Insights must come after Family Pulse.');
      });
    }
  });

  group('sectionOrderFor — removed sections (no duplicates)', () {
    // The invite-UX refinement removed three sections from the body
    // feed:
    //   • coinPool (duplicate — kept only the one with Prediction Battle)
    //   • miniGraphPreview (standalone Family Graph card removed)
    //   • invite (large InviteButton card removed — Invite now lives
    //     in the AppBar as a compact icon next to Settings)
    for (final state in FamilyEngagementState.values) {
      test('${state.name}: no standalone Coin Pool section in the order',
          () {
        final order = sectionOrderFor(state);
        // The coinPool enum value was removed entirely, so this is a
        // compile-time guarantee — but we verify the ordering function
        // output doesn't contain any unexpected sections.
        expect(order.any((s) => s.name == 'coinPool'), isFalse,
            reason: 'Standalone Coin Pool section was removed. '
                'State $state produced order: $order');
      });

      test('${state.name}: no standalone Family Graph preview section', () {
        final order = sectionOrderFor(state);
        expect(order.any((s) => s.name == 'miniGraphPreview'), isFalse,
            reason: 'Standalone Family Graph preview card was removed. '
                'State $state produced order: $order');
      });

      test('${state.name}: no standalone Invite section in the order', () {
        final order = sectionOrderFor(state);
        expect(order.any((s) => s.name == 'invite'), isFalse,
            reason: 'Standalone Invite section was removed from the body '
                'feed. Invite now lives in the AppBar as a compact icon '
                'next to Settings. State $state produced order: $order');
      });
    }
  });

  group('sectionOrderFor — all expected sections are present', () {
    // Sanity check: every ordering function output must contain ALL
    // five content sections exactly once (no missing sections, no
    // duplicates). The expected sections are: predictionBattle,
    // thinkingOfYou, familyPulse, premiumInsights, recentMoments.
    // (invite was removed — it's now an AppBar icon, not a body section.)
    for (final state in FamilyEngagementState.values) {
      test('${state.name}: contains all 5 sections exactly once', () {
        final order = sectionOrderFor(state);
        expect(order.length, FamilySection.values.length,
            reason: 'Every section must be present exactly once. '
                'State $state produced order: $order');
        expect(order.toSet().length, order.length,
            reason: 'No duplicate sections allowed. '
                'State $state produced order: $order');
      });

      test('${state.name}: order is identical across all states (fixed)', () {
        // The order is fixed — all states produce the same order.
        // Invite-UX refinement: PB → Thinking of You → Pulse
        // → Premium Insights → Recent Moments (no Invite section).
        final order = sectionOrderFor(state);
        const expectedOrder = [
          FamilySection.predictionBattle,
          FamilySection.thinkingOfYou,
          FamilySection.familyPulse,
          FamilySection.premiumInsights,
          FamilySection.recentMoments,
        ];
        expect(order, orderedEquals(expectedOrder),
            reason: 'The order must be fixed (identical for all states). '
                'State $state produced order: $order');
      });
    }
  });
}
