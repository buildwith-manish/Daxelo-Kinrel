// test/widgets/login_screen_test.dart
//
// Login Screen Widget Tests — simplified for reliable CI
//
// Only tests rendering and basic validation that don't depend on
// external services (Supabase, Firebase) being initialized.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/auth/presentation/sign_in_screen.dart';

void main() {
  group('SignInScreen Rendering', () {
    testWidgets('should render email and password fields', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(),
        ),
      );

      // Verify email field exists with hint text
      expect(find.text('Email or username'), findsOneWidget);

      // Verify password field exists with hint text
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('should render Sign In button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(),
        ),
      );

      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('should render KINREL wordmark', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(),
        ),
      );

      expect(find.text('KINREL'), findsOneWidget);
    });

    testWidgets('should render Google sign-in button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(),
        ),
      );

      expect(find.text('Google'), findsOneWidget);
    });

    testWidgets('should have password visibility toggle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(),
        ),
      );

      // Password field should start obscured
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });

    testWidgets('should toggle password visibility on tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(),
        ),
      );

      // Tap visibility toggle
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      // Password should now be visible
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('SignInScreen Validation', () {
    testWidgets('should show validation errors on empty submit',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(),
        ),
      );

      // Tap Sign In button without entering any data
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // Should show email required error
      expect(find.text('Email is required'), findsOneWidget);

      // Should show password required error
      expect(find.text('Password is required'), findsOneWidget);
    });
  });
}
