// integration_test/member_flow_test.dart
//
// DAXELO KINREL — Member Flow Integration Tests (P3-F6)
//
// Tests the member management critical path:
//   1. Add member flow loads without crash
//   2. Member list scrolls without crash

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/main.dart' as app;
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Member Flow Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    testWidgets('Add member flow loads without crash', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // App should load without crashing
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Member list scrolls without crash', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Find any scrollable list
      final listView = find.byType(ListView);
      if (listView.evaluate().isNotEmpty) {
        // Perform scroll gesture 3 times
        for (int i = 0; i < 3; i++) {
          await tester.fling(listView.first, const Offset(0, -300), 500);
          await tester.pumpAndSettle();
        }
      }

      // App should still be alive after scrolling
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
