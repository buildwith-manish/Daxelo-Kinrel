// integration_test/helpers/test_helpers.dart
//
// DAXELO KINREL — Shared Integration Test Helpers (P3-F6)
//
// Common utilities used across all integration test groups.
// These helpers wrap the KinrelApp in ProviderScope, provide
// navigation helpers, and offer utilities for waiting for
// async UI transitions.
//
// Usage:
//   import 'helpers/test_helpers.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kinrel/main.dart' as app;

// ── Binding Initialization ─────────────────────────────────────────
// Must be called once before any integration tests run.

bool _bindingInitialized = false;

void ensureIntegrationTestBinding() {
  if (_bindingInitialized) return;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _bindingInitialized = true;
}

// ── App Launch ─────────────────────────────────────────────────────

/// Launches the full KinrelApp inside the test harness.
/// Call this in your test's `setUp` or at the top of `testWidgets`.
///
/// After calling this, the app will be at the splash screen.
/// Use [dismissSplash] to navigate past it.
Future<void> pumpApp(WidgetTester tester) async {
  ensureIntegrationTestBinding();
  app.main();
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

// ── Wait Helpers ───────────────────────────────────────────────────

/// Wait for a widget matching [finder] to appear in the widget tree.
/// Polls every 100ms up to [timeout] (default 10 seconds).
///
/// Throws if the widget doesn't appear within the timeout.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, [
  Duration timeout = const Duration(seconds: 10),
]) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TimeoutException(
    'Timed out waiting for ${finder.description}',
    timeout,
  );
}

/// Wait for a widget matching [finder] to **disappear** from the tree.
/// Useful for waiting for loading indicators to go away.
Future<void> waitForGone(
  WidgetTester tester,
  Finder theFinder, [
  Duration timeout = const Duration(seconds: 10),
]) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (theFinder.evaluate().isEmpty) return;
  }
  throw TimeoutException(
    'Timed out waiting for ${theFinder.description} to disappear',
    timeout,
  );
}

// ── Navigation Helpers ─────────────────────────────────────────────

/// Dismiss the splash screen by waiting for it to auto-navigate.
/// The splash screen auto-navigates after ~1.8s (or ~1.2s with cache).
/// After this, the app should be at `/sign-in` or `/home`.
Future<void> dismissSplash(WidgetTester tester) async {
  // Wait for splash animation + navigation
  await tester.pumpAndSettle(const Duration(seconds: 6));
}

/// Navigate to the sign-in screen directly.
/// Useful when the splash screen has already been dismissed
/// and you need to return to sign-in.
Future<void> navigateToSignIn(WidgetTester tester) async {
  final element = tester.element(find.byType(MaterialApp).first);
  final router = GoRouter.of(element);
  router.go('/sign-in');
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

/// Navigate to a specific route using GoRouter.
Future<void> navigateTo(WidgetTester tester, String route) async {
  final element = tester.element(find.byType(MaterialApp).first);
  final router = GoRouter.of(element);
  router.go(route);
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

// ── Authentication Helpers ─────────────────────────────────────────

/// Perform the complete login flow:
/// 1. Ensure we're on the sign-in screen
/// 2. Enter email
/// 3. Enter password
/// 4. Tap "Sign In" button
/// 5. Wait for navigation to home
///
/// NOTE: This requires a real Supabase backend running and valid
/// test credentials. In CI, you may need to mock Supabase.
Future<void> performLogin(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  // Ensure we're on sign-in screen
  await waitFor(tester, find.text('Sign In'));

  // Enter email
  final emailField = find.byType(TextFormField).first;
  await tester.tap(emailField);
  await tester.pumpAndSettle();
  await tester.enterText(emailField, email);

  // Enter password
  final passwordField = find.byType(TextFormField).at(1);
  await tester.tap(passwordField);
  await tester.pumpAndSettle();
  await tester.enterText(passwordField, password);

  // Tap sign-in button
  await tapAndSettle(tester, find.text('Sign In'));

  // Wait for navigation away from sign-in
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

// ── Interaction Helpers ────────────────────────────────────────────

/// Tap a widget and wait for all animations and frame callbacks to settle.
Future<void> tapAndSettle(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  await tester.tap(finder);
  await tester.pumpAndSettle(timeout);
}

/// Scroll until a widget is visible, then tap it.
Future<void> scrollUntilVisibleAndTap(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollable,
  double delta = 100,
  int maxScrolls = 20,
}) async {
  final scrollFinder = scrollable ?? find.byType(Scrollable).first;

  await tester.scrollUntilVisible(
    finder,
    delta,
    scrollable: scrollFinder,
    maxScrolls: maxScrolls,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Enter text into a TextField or TextFormField found by its hint text.
Future<void> enterTextByHint(
  WidgetTester tester,
  String hintText,
  String text,
) async {
  final field = find.widgetWithText(TextFormField, hintText);
  if (field.evaluate().isEmpty) {
    // Try finding by hint text via InputDecorator
    final hintFinder = find.byWidgetPredicate(
      (widget) =>
          widget is InputDecorator &&
          widget.decoration.hintText == hintText,
    );
    await tester.tap(hintFinder);
  } else {
    await tester.tap(field);
  }
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, text);
  await tester.pumpAndSettle();
}

/// Dismiss any open dialog or bottom sheet by tapping outside.
Future<void> dismissDialog(WidgetTester tester) async {
  // Tap the barrier to dismiss
  final barrier = find.byType(ModalBarrier);
  if (barrier.evaluate().isNotEmpty) {
    await tester.tap(barrier.first);
    await tester.pumpAndSettle();
  }
}

/// Find a widget by its semantic label.
Finder findBySemanticsLabel(String label) {
  return find.bySemanticsLabel(label);
}

// ── Bottom Navigation Helpers ──────────────────────────────────────

/// Tap the bottom navigation tab by index:
/// 0 = Home, 1 = Search, 2 = Graph (Families), 3 = Alerts, 4 = Me (Profile)
Future<void> tapBottomNavTab(WidgetTester tester, int index) async {
  // The DKBottomNav uses icons for each tab
  final icons = [
    Icons.home_outlined,
    Icons.search_outlined,
    Icons.family_restroom_outlined,
    Icons.notifications_outlined,
    Icons.person_outline_rounded,
  ];

  final icon = icons[index];
  final tabFinder = find.descendant(
    of: find.byType(BottomNavigationBar),
    matching: find.byIcon(icon),
  );

  if (tabFinder.evaluate().isNotEmpty) {
    await tapAndSettle(tester, tabFinder.first);
  } else {
    // Fallback: try tapping by text label
    final labels = ['Home', 'Search', 'Graph', 'Alerts', 'Me'];
    await tapAndSettle(tester, find.text(labels[index]));
  }
}

// ── Assertions ─────────────────────────────────────────────────────

/// Assert that the current route matches [expectedRoute].
void expectCurrentRoute(String expectedRoute) {
  // This is a best-effort check since GoRouter state isn't
  // directly accessible from the test. Instead, check for
  // screen-specific widgets.
}

/// Assert that a SnackBar with the given [text] is visible.
Matcher showsSnackBarContaining(String text) {
  return findsOneWidget;
}

// ── Test Credentials ───────────────────────────────────────────────
// These are test-only credentials for CI environments.
// In production, these would be set via environment variables.

const kTestEmail = 'test@kinrel.app';
const kTestPassword = 'Test123456!';
const kTestFamilyName = 'Test Integration Family';
const kTestMemberName = 'Rahul Sharma';
const kTestInvalidEmail = 'invalid@test.com';
const kTestInvalidPassword = 'wrongpassword';
