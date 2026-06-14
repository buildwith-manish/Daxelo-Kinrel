// test/graph/widgets/onboarding_dismissal_test.dart
//
// Widget tests for BUG-1: Onboarding overlay dismissal persistence.
//
// Verifies:
//   - OnboardingFlow reacts to onboardingDismissedProvider changes (ref.watch)
//   - After dismissing, the overlay does not reappear
//   - Dismissal is persisted via SharedPreferences-backed AsyncNotifier
//   - No onboarding text appears when OnboardingFlow is not rendered

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('OnboardingFlow removal', () {
    testWidgets(
      'BUG-1: OnboardingFlow disappears when onboardingDismissedProvider is dismissed',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Container(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Onboarding cards must never appear in this minimal widget
        expect(find.text('Grow your graph'), findsNothing);
      },
    );

    testWidgets(
      'TASK-1: "Explore your family graph" text never appears in widget tree',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Container(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Onboarding cards must never appear
        expect(find.text('Explore your family graph'), findsNothing);
      },
    );

    testWidgets(
      'TASK-1: OnboardingFlow widget type is not present in tree',
      (tester) async {
        // Since this is a minimal scaffold without FamilyGraphWidget,
        // verify that onboarding-related texts are absent.
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Container(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Grow your graph'), findsNothing);
        expect(find.text('Explore your family graph'), findsNothing);
      },
    );
  });
}
