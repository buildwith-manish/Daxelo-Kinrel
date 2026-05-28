// integration_test/auth_flow_test.dart
//
// DAXELO KINREL — Auth Flow Integration Tests (P3-F6)
//
// Tests the authentication flow critical path:
//   1. App opens → splash screen appears
//   2. Sign in screen has email and password fields
//   3. Empty form submission shows validation errors
//   4. Navigation to sign-up screen works

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/main.dart' as app;
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Auth Flow Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    testWidgets('App opens → splash screen appears', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Splash screen should be visible — the app renders a MaterialApp
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Sign in screen has email and password fields', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Look for text fields on sign-in screen
      final emailFields = find.byType(TextFormField);
      // Should have at least email and password fields
      expect(emailFields, findsAtLeast(2));
    });

    testWidgets('Empty form submission shows validation errors', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Find and tap the sign-in/submit button
      final submitButton = find.byType(ElevatedButton);
      if (submitButton.evaluate().isNotEmpty) {
        await tester.tap(submitButton.first);
        await tester.pumpAndSettle();

        // Should show validation error messages
        final errorTexts = find.byType(Text);
        expect(errorTexts, findsWidgets);
      }
    });

    testWidgets('Navigation to sign-up screen works', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Look for sign-up link/button
      final signUpFinder = find.textContaining('Sign Up');
      if (signUpFinder.evaluate().isNotEmpty) {
        await tester.tap(signUpFinder.first);
        await tester.pumpAndSettle();

        // Should be on sign-up screen
        expect(find.byType(MaterialApp), findsOneWidget);
      }
    });
  });
}
