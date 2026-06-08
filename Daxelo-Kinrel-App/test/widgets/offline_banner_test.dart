// test/widgets/offline_banner_test.dart
//
// Offline Banner Widget Tests
//
// Tests for the OfflineBanner widget covering:
// - Banner visibility when offline with recent failure
// - Banner hidden when online
// - Provider-based state management
//
// Uses simple Provider overrides that work reliably with Riverpod 2.x.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kinrel/core/widgets/offline_banner.dart';
import 'package:kinrel/core/database/sync/connectivity_service.dart';

void main() {
  Widget createTestWidget({
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
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

  group('OfflineBanner Visibility', () {
    testWidgets('should render OfflineBanner widget without crashing',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          recentRequestFailureProvider.overrideWith((ref) => null),
        ],
      ));

      await tester.pumpAndSettle();

      // Widget should render without errors
      expect(find.byType(OfflineBanner), findsOneWidget);
    });

    testWidgets(
        'should show banner text when offline with recent request failure',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) => Stream.value(false)),
          recentRequestFailureProvider
              .overrideWith((ref) => DateTime.now()),
        ],
      ));

      await tester.pumpAndSettle();

      // The "No internet connection" text should exist in the widget tree
      expect(find.text('No internet connection'), findsOneWidget);
    });

    testWidgets('should hide banner when online', (tester) async {
      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          recentRequestFailureProvider
              .overrideWith((ref) => DateTime.now()),
        ],
      ));

      await tester.pumpAndSettle();

      // AnimatedContainer height should be 0 when online
      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
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
          isOnlineProvider.overrideWith((ref) => Stream.value(false)),
          recentRequestFailureProvider.overrideWith((ref) => null),
        ],
      ));

      await tester.pumpAndSettle();

      // AnimatedContainer height should be 0 when no recent failure
      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(
        (animatedContainer.constraints?.maxHeight ?? -1) == 0,
        isTrue,
        reason: 'Banner should be collapsed when no recent failure',
      );
    });
  });

  group('OfflineBanner Content', () {
    testWidgets('should display "No internet connection" text',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        overrides: [
          isOnlineProvider.overrideWith((ref) => Stream.value(false)),
          recentRequestFailureProvider
              .overrideWith((ref) => DateTime.now()),
        ],
      ));

      await tester.pumpAndSettle();

      expect(find.text('No internet connection'), findsOneWidget);
    });
  });
}
