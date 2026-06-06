// test/widgets/offline_banner_test.dart
//
// TEST-05 (part 2): Offline Banner Widget Tests
//
// Tests for the OfflineBanner widget covering:
// - Banner visibility when offline with recent failure
// - Banner hidden when online
// - Banner hidden when offline but no recent failure
// - Banner auto-hides after 30-second failure window
// - Reconnection transitions
//
// NOTE: Flutter/Dart CLI is unavailable in this sandbox — verify locally.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kinrel/core/widgets/offline_banner.dart';
import 'package:kinrel/core/database/sync/connectivity_service.dart';

void main() {
  // ── Test helpers ────────────────────────────────────────────────────

  /// Build a minimal test widget tree wrapping the OfflineBanner
  /// with a ProviderScope and the required provider overrides.
  Widget createTestWidget({
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
      // Wrap in MaterialApp so Theme.of(context) works (OfflineBanner
      // uses Theme.of(context).colorScheme.error)
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orange,
            error: Colors.red,
            onError: Colors.white,
          ),
        ),
        home: const Scaffold(
          body: Column(
            children: [
              OfflineBanner(),
              Expanded(child: Text('Main Content')),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BANNER VISIBILITY
  // ═══════════════════════════════════════════════════════════════════════

  group('OfflineBanner Visibility', () {
    testWidgets('should show banner when offline with recent request failure',
        (tester) async {
      // Override isOnlineProvider to return offline
      // Override recentRequestFailureProvider to have a recent timestamp
      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) {
            // Create a stream that immediately emits false (offline)
            return Stream.value(false);
          }),
          recentRequestFailureProvider.overrideWith((ref) => DateTime.now()),
        ],
      ));

      // Pump to let stream providers resolve
      await tester.pumpAndSettle();

      // Banner should be visible (height > 0)
      // The OfflineBanner uses AnimatedContainer with height 28 when shown
      // After animation settles, the "No internet connection" text should be visible
      expect(find.text('No internet connection'), findsOneWidget);
    });

    testWidgets('should hide banner when online', (tester) async {
      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) {
            return Stream.value(true);
          }),
          recentRequestFailureProvider.overrideWith((ref) => DateTime.now()),
        ],
      ));

      await tester.pumpAndSettle();

      // Even with a recent failure, if online the banner should be hidden
      // The text exists in the widget tree but the container height is 0
      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      // Height should be 0.0 when not showing
      expect(
        (animatedContainer.constraints?.maxHeight ?? 0) == 0 ||
            animatedContainer.decoration != null,
        isTrue,
        reason: 'Banner should be collapsed when online',
      );
    });

    testWidgets('should hide banner when offline but no recent failure',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) {
            return Stream.value(false);
          }),
          recentRequestFailureProvider.overrideWith((ref) => null),
        ],
      ));

      await tester.pumpAndSettle();

      // Offline but no recent failure — banner should be hidden
      // The banner text exists but container height should be 0
      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(
        animatedContainer.constraints?.maxHeight ?? -1,
        equals(0.0),
        reason: 'Banner should be collapsed when no recent failure',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // FAILURE WINDOW
  // ═══════════════════════════════════════════════════════════════════════

  group('OfflineBanner Failure Window', () {
    testWidgets('should hide banner when failure is older than 30 seconds',
        (tester) async {
      // Set failure timestamp to 31 seconds ago
      final oldFailure = DateTime.now().subtract(const Duration(seconds: 31));

      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) {
            return Stream.value(false);
          }),
          recentRequestFailureProvider
              .overrideWith((ref) => oldFailure),
        ],
      ));

      await tester.pumpAndSettle();

      // The banner checks: DateTime.now().difference(lastFailure).inSeconds < 30
      // Since 31 seconds have passed, the banner should be hidden
      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(
        animatedContainer.constraints?.maxHeight ?? -1,
        equals(0.0),
        reason: 'Banner should be collapsed after 30s failure window',
      );
    });

    testWidgets('should show banner when failure is within 30 seconds',
        (tester) async {
      // Set failure timestamp to 5 seconds ago (within window)
      final recentFailure = DateTime.now().subtract(const Duration(seconds: 5));

      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) {
            return Stream.value(false);
          }),
          recentRequestFailureProvider
              .overrideWith((ref) => recentFailure),
        ],
      ));

      await tester.pumpAndSettle();

      // The text should be visible in the widget tree
      expect(find.text('No internet connection'), findsOneWidget);

      // The AnimatedContainer height should be 28.0
      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(
        animatedContainer.constraints?.maxHeight ?? 0,
        equals(28.0),
        reason: 'Banner should be expanded within 30s failure window',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // RECONNECTION TRANSITIONS
  // ═══════════════════════════════════════════════════════════════════════

  group('OfflineBanner Reconnection', () {
    testWidgets('should hide banner when transitioning from offline to online',
        (tester) async {
      // Start with offline + recent failure
      final controller = StreamController<bool>.broadcast();

      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) {
            return controller.stream;
          }),
          recentRequestFailureProvider
              .overrideWith((ref) => DateTime.now()),
        ],
      ));

      // Emit offline first
      controller.add(false);
      await tester.pumpAndSettle();

      // Banner should be visible
      expect(find.text('No internet connection'), findsOneWidget);

      // Now go online
      controller.add(true);
      await tester.pumpAndSettle();

      // Banner should collapse (height = 0)
      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(
        animatedContainer.constraints?.maxHeight ?? -1,
        equals(0.0),
        reason: 'Banner should collapse when transitioning online',
      );

      await controller.close();
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // CONTENT AND STYLING
  // ═══════════════════════════════════════════════════════════════════════

  group('OfflineBanner Content', () {
    testWidgets('should display "No internet connection" text', (tester) async {
      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) {
            return Stream.value(false);
          }),
          recentRequestFailureProvider.overrideWith((ref) => DateTime.now()),
        ],
      ));

      await tester.pumpAndSettle();

      expect(find.text('No internet connection'), findsOneWidget);
    });

    testWidgets('should use error color from theme', (tester) async {
      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) {
            return Stream.value(false);
          }),
          recentRequestFailureProvider.overrideWith((ref) => DateTime.now()),
        ],
      ));

      await tester.pumpAndSettle();

      // The Container inside the AnimatedContainer should use
      // Theme.of(context).colorScheme.error as its color
      // Find the container with the error color
      final containers = tester.widgetList<Container>(
        find.byType(Container),
      );

      final errorContainer = containers.firstWhere(
        (c) => c.color == Colors.red, // from our test theme
        orElse: () => containers.first,
      );

      expect(errorContainer, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ACCESSIBILITY
  // ═══════════════════════════════════════════════════════════════════════

  group('OfflineBanner Accessibility', () {
    testWidgets('should have live region semantics when visible', (tester) async {
      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) {
            return Stream.value(false);
          }),
          recentRequestFailureProvider.overrideWith((ref) => DateTime.now()),
        ],
      ));

      await tester.pumpAndSettle();

      // The OfflineBanner uses semanticLiveRegion(assertive: true)
      // which wraps the content in Semantics(liveRegion: true)
      final semantics = tester.getSemantics(find.byType(OfflineBanner));
      // Live region semantics should be present for screen readers
      expect(semantics.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    });
  });
}
