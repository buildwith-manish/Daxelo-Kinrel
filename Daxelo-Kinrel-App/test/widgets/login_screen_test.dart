// test/widgets/login_screen_test.dart
//
// Login Screen Widget Tests
//
// Tests for the SignInScreen widget covering:
// - Rendering of email and password fields
// - Validation errors on empty submit
// - Basic widget structure verification
//
// NOTE: These tests use simplified provider overrides to avoid
// dependencies on Supabase/Firebase initialization.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/features/auth/presentation/sign_in_screen.dart';
import 'package:kinrel/core/services/supabase_service.dart';

void main() {
  Widget createTestWidget({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => child,
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) =>
              const Scaffold(body: Text('Home Screen')),
        ),
        GoRoute(
          path: '/sign-up',
          builder: (context, state) =>
              const Scaffold(body: Text('Sign Up Screen')),
        ),
        GoRoute(
          path: '/2fa-verify',
          builder: (context, state) =>
              const Scaffold(body: Text('2FA Screen')),
        ),
      ],
    );

    return ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData.dark(),
      ),
    );
  }

  group('SignInScreen Rendering', () {
    testWidgets('should render email and password fields', (tester) async {
      await tester.pumpWidget(createTestWidget(
        child: SignInScreen(),
      ));

      // Verify email field exists with hint text
      expect(find.text('Email or username'), findsOneWidget);

      // Verify password field exists with hint text
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('should render Sign In button', (tester) async {
      await tester.pumpWidget(createTestWidget(
        child: SignInScreen(),
      ));

      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('should render KINREL wordmark', (tester) async {
      await tester.pumpWidget(createTestWidget(
        child: SignInScreen(),
      ));

      expect(find.text('KINREL'), findsOneWidget);
    });

    testWidgets('should have password visibility toggle', (tester) async {
      await tester.pumpWidget(createTestWidget(
        child: SignInScreen(),
      ));

      // Password field should start obscured
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });
  });

  group('SignInScreen Validation', () {
    testWidgets('should show validation errors on empty submit',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        child: SignInScreen(),
      ));

      // Tap Sign In button without entering any data
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // Should show email required error
      expect(find.text('Email is required'), findsOneWidget);

      // Should show password required error
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('should toggle password visibility', (tester) async {
      await tester.pumpWidget(createTestWidget(
        child: SignInScreen(),
      ));

      // Initially password is obscured
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // Tap visibility toggle
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      // Password should now be visible
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });
  });

  group('SignInScreen Error Handling', () {
    testWidgets(
        'should return to non-loading state after auth service error',
        (tester) async {
      // Override authServiceProvider to throw an error
      final authServiceProviderOverride =
          authServiceProvider.overrideWith((ref) {
        return AuthService(null);
      });

      await tester.pumpWidget(createTestWidget(
        child: SignInScreen(),
        overrides: [authServiceProviderOverride],
      ));

      // Enter credentials and submit
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email or username').first,
        'test@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password').first,
        'password123',
      );

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // After error, should return to non-loading state
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Signing in...'), findsNothing);
    });
  });
}
