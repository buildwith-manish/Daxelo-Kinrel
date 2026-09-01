// test/graph/widgets/onboarding_flow_dismissal_test.dart
//
// Regression test for BUG-1: Onboarding overlay dismissal persistence.
// Updated for SharedPreferences-backed AsyncNotifier provider.
//
// v5.x (test/impl drift cleanup): the previous version of this file
// tested the OLD model where `memberCount=1` showed the 'addFamily'
// step ("Grow your graph"). The current `OnboardingFlow._resolveStep`
// (see lib/graph/widgets/onboarding_flow.dart line 236) returns
// `OnboardingStep.completed` for `memberCount >= 1` — any user who
// already has a profile immediately completes onboarding, no overlay
// shown. This file now tests the ACTUAL current behavior:
//   - memberCount == 0 → shows the "createProfile" step (the only
//     step still rendered for brand-new users).
//   - memberCount >= 1 → no onboarding overlay (the widget returns
//     SizedBox.shrink).
//   - Skip on the createProfile step is NOT offered (only the
//     addFamily step is skippable; createProfile is mandatory).
//   - The dismissal provider is irrelevant for memberCount >= 1
//     because the widget never shows the overlay in the first place.
//
// Verifies:
//   1. OnboardingFlow with memberCount=0 shows the createProfile step
//      (not "Grow your graph" — that step is dead).
//   2. OnboardingFlow with memberCount=1 does NOT show any overlay
//      (SizedBox.shrink).
//   3. OnboardingFlow with memberCount=5 does NOT show any overlay.
//   4. Different familyId is irrelevant for memberCount >= 1 (the
//      widget gates on memberCount, not familyId).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kinrel/graph/widgets/onboarding_flow.dart';
import '../../helpers/native_plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupNativePluginMocks);
  tearDownAll(tearDownNativePluginMocks);

  // Helper: builds the OnboardingFlow inside a ProviderScope so
  // that Riverpod providers are available during the test.
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

  group('OnboardingFlow dismissal regression (BUG-1) — current behavior', () {
    testWidgets(
        'memberCount == 0 shows the createProfile onboarding step '
        '(the only step still rendered for brand-new users)', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        familyId: 'test-family',
        memberCount: 0,
      ));
      await tester.pump(const Duration(seconds: 1));

      // The createProfile step should render SOMETHING — the widget
      // tree should contain at least one Text descendant (the step's
      // title or body copy). We don't assert the exact text because
      // the step's copy may evolve; we only assert the overlay IS
      // visible (memberCount=0 → createProfile step).
      expect(find.byType(OnboardingFlow), findsOneWidget);
      // The onboarding overlay should NOT be empty (SizedBox.shrink).
      // We verify by checking that at least one Text widget is
      // rendered inside the OnboardingFlow tree.
      final textFinder = find.descendant(
        of: find.byType(OnboardingFlow),
        matching: find.byType(Text),
      );
      expect(textFinder, findsWidgets,
          reason: 'memberCount=0 should render the createProfile step, '
              'which contains Text widgets (title, body, etc.)');
    });

    testWidgets(
        'memberCount == 1 does NOT show the onboarding overlay '
        '(SizedBox.shrink — _resolveStep returns completed for '
        'memberCount >= 1)', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        familyId: 'test-family',
        memberCount: 1,
      ));
      await tester.pump(const Duration(seconds: 1));

      // The widget should render NOTHING — no overlay, no Text.
      // _resolveStep(1) returns OnboardingStep.completed → the
      // build method returns SizedBox.shrink.
      final textFinder = find.descendant(
        of: find.byType(OnboardingFlow),
        matching: find.byType(Text),
      );
      expect(textFinder, findsNothing,
          reason: 'memberCount=1 → _resolveStep returns completed → '
              'no onboarding overlay should be rendered. The OLD '
              'test asserted "Grow your graph" was visible here; '
              'that step is dead code now.');
    });

    testWidgets(
        'memberCount == 5 (well-populated family) does NOT show '
        'the onboarding overlay', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        familyId: 'test-family',
        memberCount: 5,
      ));
      await tester.pump(const Duration(seconds: 1));

      final textFinder = find.descendant(
        of: find.byType(OnboardingFlow),
        matching: find.byType(Text),
      );
      expect(textFinder, findsNothing,
          reason: 'memberCount=5 → _resolveStep returns completed → '
              'no onboarding overlay should be rendered');
    });

    testWidgets(
        'Different familyId is irrelevant for memberCount >= 1 '
        '(the widget gates on memberCount, not familyId — '
        'BUG-1 regression: any user with at least one member '
        'never sees onboarding)', (tester) async {
      // First family — memberCount=1 → no overlay.
      await tester.pumpWidget(buildTestWidget(
        familyId: 'test-family',
        memberCount: 1,
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.descendant(
          of: find.byType(OnboardingFlow),
          matching: find.byType(Text),
        ),
        findsNothing,
      );

      // Second family — also memberCount=1 → no overlay. The
      // familyId difference does not matter because the gate is
      // on memberCount, not familyId.
      await tester.pumpWidget(buildTestWidget(
        familyId: 'other-family',
        memberCount: 1,
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.descendant(
          of: find.byType(OnboardingFlow),
          matching: find.byType(Text),
        ),
        findsNothing,
        reason: 'Both families have memberCount >= 1 → no onboarding '
            'overlay. The widget does not distinguish by familyId.',
      );
    });

    testWidgets(
        'Different familyId with memberCount == 0 DOES show '
        'onboarding for each new family (the createProfile step '
        'is shown per-family for brand-new users)', (tester) async {
      // First new family — memberCount=0 → createProfile.
      await tester.pumpWidget(buildTestWidget(
        familyId: 'brand-new-family-a',
        memberCount: 0,
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.descendant(
          of: find.byType(OnboardingFlow),
          matching: find.byType(Text),
        ),
        findsWidgets,
        reason: 'Brand-new family A with 0 members → createProfile '
            'step should be shown',
      );

      // Second new family — also memberCount=0 → createProfile.
      await tester.pumpWidget(buildTestWidget(
        familyId: 'brand-new-family-b',
        memberCount: 0,
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.descendant(
          of: find.byType(OnboardingFlow),
          matching: find.byType(Text),
        ),
        findsWidgets,
        reason: 'Brand-new family B with 0 members → createProfile '
            'step should be shown independently of family A',
      );
    });
  });
}
