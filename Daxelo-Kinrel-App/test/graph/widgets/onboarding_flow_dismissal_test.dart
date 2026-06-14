// test/graph/widgets/onboarding_flow_dismissal_test.dart
//
// AGENT-08 (Quality & Testing) — Regression test for BUG-1:
// Onboarding overlay dismissal persistence.
//
// Verifies that:
//   1. OnboardingFlow with memberCount=1 shows "Grow your graph"
//   2. Tapping "Skip" dismisses the overlay (widget → SizedBox.shrink)
//   3. After dismissal, the overlay does NOT reappear on re-pump
//   4. onboardingDismissedProvider persists 'test-family' in its Set

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kinrel/graph/widgets/onboarding_flow.dart';

void main() {
  group('OnboardingFlow dismissal regression (BUG-1)', () {
    /// Helper: builds the OnboardingFlow inside a ProviderScope so
    /// that Riverpod providers are available during the test.
    Widget buildTestWidget({
      required String familyId,
      required int memberCount,
      List<Override> overrides = const [],
    }) {
      return ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Scaffold(
            body: OnboardingFlow(
              familyId: familyId,
              memberCount: memberCount,
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Step 1: OnboardingFlow with memberCount=1 shows "Grow your graph"',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          familyId: 'test-family',
          memberCount: 1,
        ));
        await tester.pumpAndSettle();

        // memberCount=1 → step addFamily → title is "Grow your graph"
        expect(find.text('Grow your graph'), findsOneWidget);
      },
    );

    testWidgets(
      'Step 2-5: Tapping Skip dismisses the overlay (SizedBox.shrink)',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          familyId: 'test-family',
          memberCount: 1,
        ));
        await tester.pumpAndSettle();

        // Verify overlay is visible before skip
        expect(find.text('Grow your graph'), findsOneWidget);

        // Find and tap the Skip button
        final skipFinder = find.text('Skip');
        expect(skipFinder, findsOneWidget, reason: 'Skip button must be present for addFamily step');
        await tester.tap(skipFinder);

        // Allow state rebuild after tap
        await tester.pump();

        // After skip, _permanentlyDismissed is set to true and the widget
        // returns SizedBox.shrink, so "Grow your graph" must be gone
        expect(
          find.text('Grow your graph'),
          findsNothing,
          reason: 'Overlay must disappear after Skip is tapped',
        );
      },
    );

    testWidgets(
      'Step 6-7: Re-pumping the widget from scratch does not show overlay '
      'because onboardingDismissedProvider contains the familyId',
      (tester) async {
        // First: show and skip the overlay so the provider records dismissal
        await tester.pumpWidget(buildTestWidget(
          familyId: 'test-family',
          memberCount: 1,
        ));
        await tester.pumpAndSettle();
        expect(find.text('Grow your graph'), findsOneWidget);

        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();

        // Verify dismissed
        expect(find.text('Grow your graph'), findsNothing);

        // Now read the provider state via the ProviderScope container
        final container = ProviderScope.containerOf(
          tester.element(find.byType(Scaffold)),
        );
        final dismissedSet = container.read(onboardingDismissedProvider);
        expect(
          dismissedSet.contains('test-family'),
          isTrue,
          reason: 'onboardingDismissedProvider must contain "test-family" after skip',
        );

        // Re-pump the widget from scratch with same familyId
        // The provider already has 'test-family' in its dismissed set,
        // so the widget should check _isDismissedForFamily → true → SizedBox.shrink
        await tester.pumpWidget(buildTestWidget(
          familyId: 'test-family',
          memberCount: 1,
        ));
        await tester.pumpAndSettle();

        // The overlay must NOT reappear
        expect(
          find.text('Grow your graph'),
          findsNothing,
          reason: 'Overlay must not reappear after dismissal is persisted in provider',
        );
      },
    );

    testWidgets(
      'BUG-1 regression: Different familyId shows onboarding independently',
      (tester) async {
        // Dismiss 'test-family'
        await tester.pumpWidget(buildTestWidget(
          familyId: 'test-family',
          memberCount: 1,
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();

        // Now pump a different familyId — should show onboarding
        await tester.pumpWidget(buildTestWidget(
          familyId: 'other-family',
          memberCount: 1,
        ));
        await tester.pumpAndSettle();

        expect(
          find.text('Grow your graph'),
          findsOneWidget,
          reason: 'Different familyId should show onboarding independently',
        );
      },
    );
  });
}
