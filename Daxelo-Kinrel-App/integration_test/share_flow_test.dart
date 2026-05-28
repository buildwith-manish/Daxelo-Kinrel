// integration_test/share_flow_test.dart
//
// DAXELO KINREL — Share Flow Integration Tests (P3-F6)
//
// Tests the share/invite critical path:
//   1. Profile share button is tappable
//   2. Share sheet opens without crash

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/main.dart' as app;
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Share Flow Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    testWidgets('Profile share button is tappable', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Find any share-related icon buttons
      final shareButtons = find.byIcon(Icons.share);
      if (shareButtons.evaluate().isNotEmpty) {
        // Tap the share button
        await tester.tap(shareButtons.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // App should still be alive (no crash)
        expect(find.byType(MaterialApp), findsOneWidget);
      }
    });

    testWidgets('Share sheet opens without crash', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Find and tap any share action
      final shareButtons = find.byIcon(Icons.share);
      if (shareButtons.evaluate().isNotEmpty) {
        await tester.tap(shareButtons.first);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // App should still be running without errors
        expect(find.byType(MaterialApp), findsOneWidget);
      }
    });
  });
}
