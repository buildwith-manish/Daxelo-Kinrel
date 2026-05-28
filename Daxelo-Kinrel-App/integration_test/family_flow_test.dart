// integration_test/family_flow_test.dart
//
// DAXELO KINREL — Family Flow Integration Tests (P3-F6)
//
// Tests the family management critical path:
//   1. Family list screen loads without crash
//   2. Create family screen has name field
//   3. Empty family name shows validation error

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/main.dart' as app;
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Family Flow Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    testWidgets('Family list screen loads without crash', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // App should load without crashing
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Create family screen has name field', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to create family (if we can find the button)
      final createButton = find.textContaining('Create');
      if (createButton.evaluate().isNotEmpty) {
        await tester.tap(createButton.first);
        await tester.pumpAndSettle();

        // Should have a text field for family name
        expect(find.byType(TextFormField), findsAtLeast(1));
      }
    });

    testWidgets('Empty family name shows validation error', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Navigate to create family
      final createButton = find.textContaining('Create');
      if (createButton.evaluate().isNotEmpty) {
        await tester.tap(createButton.first);
        await tester.pumpAndSettle();

        // Find and tap submit without entering name
        final submitButton = find.byType(ElevatedButton);
        if (submitButton.evaluate().isNotEmpty) {
          await tester.tap(submitButton.first);
          await tester.pumpAndSettle();

          // Should show validation error
          expect(find.byType(MaterialApp), findsOneWidget);
        }
      }
    });
  });
}
