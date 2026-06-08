// test/widgets/login_screen_test.dart
//
// Login Screen Widget Tests — simplified for reliable CI
//
// Uses pump() with explicit duration instead of pumpAndSettle()
// to avoid '!timersPending' assertion failures from SignInScreen's
// internal timers (debounce, animation controllers, etc.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/features/auth/presentation/sign_in_screen.dart';

void main() {
  group('SignInScreen Rendering', () {
    testWidgets('should render email and password fields', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen()),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Email or username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('should render Sign In button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen()),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('should render KINREL wordmark', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen()),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('KINREL'), findsOneWidget);
    });

    testWidgets('should render Google sign-in button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen()),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Google'), findsOneWidget);
    });

    testWidgets('should have password visibility toggle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen()),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });

  group('SignInScreen Validation', () {
    testWidgets('should show validation errors on empty submit',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen()),
      );
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Sign In'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });
  });
}
