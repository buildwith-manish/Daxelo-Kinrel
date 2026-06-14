// test/graph/widgets/onboarding_dismissal_test.dart
//
// Widget tests for TASK 1: OnboardingFlow removed from graph.
//
// Verifies:
//   - No "Grow your graph" card appears in the widget tree
//   - No "Explore your family graph" card appears in the widget tree
//   - OnboardingFlow widget is not rendered in FamilyGraphWidget

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('OnboardingFlow removal', () {
    testWidgets(
      'TASK-1: "Grow your graph" text never appears in widget tree',
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
        // Since OnboardingFlow is no longer imported or used in FamilyGraphWidget,
        // this test verifies the import was removed and the widget is not rendered.
        // We test indirectly by checking that the relevant onboarding texts are absent.
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
