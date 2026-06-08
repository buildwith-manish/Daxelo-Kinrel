// test/widgets/offline_banner_test.dart
//
// Offline Banner Widget Tests — simplified for reliable CI

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kinrel/core/widgets/offline_banner.dart';
import 'package:kinrel/core/database/sync/connectivity_service.dart';

void main() {
  group('OfflineBanner Provider Tests', () {
    test('recentRequestFailureProvider starts as null', () {
      final container = ProviderContainer();
      final value = container.read(recentRequestFailureProvider);
      expect(value, isNull);
      container.dispose();
    });

    test('recentRequestFailureProvider can be set to a DateTime', () {
      final container = ProviderContainer();
      final now = DateTime.now();
      container.read(recentRequestFailureProvider.notifier).state = now;
      expect(container.read(recentRequestFailureProvider), equals(now));
      container.dispose();
    });

    test('recentRequestFailureProvider can be reset to null', () {
      final container = ProviderContainer();
      container.read(recentRequestFailureProvider.notifier).state = DateTime.now();
      container.read(recentRequestFailureProvider.notifier).state = null;
      expect(container.read(recentRequestFailureProvider), isNull);
      container.dispose();
    });
  });

  group('OfflineBanner Widget', () {
    testWidgets('renders without crashing when online', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isOnlineProvider.overrideWith((ref) => Stream.value(true)),
            recentRequestFailureProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            home: const Scaffold(
              body: Column(
                children: [
                  OfflineBanner(),
                  Expanded(child: Text('Content')),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(OfflineBanner), findsOneWidget);
    });

    testWidgets('shows banner text when offline with recent failure',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isOnlineProvider.overrideWith((ref) => Stream.value(false)),
            recentRequestFailureProvider
                .overrideWith((ref) => DateTime.now()),
          ],
          child: MaterialApp(
            home: const Scaffold(
              body: Column(
                children: [
                  OfflineBanner(),
                  Expanded(child: Text('Content')),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('No internet connection'), findsOneWidget);
    });
  });
}
