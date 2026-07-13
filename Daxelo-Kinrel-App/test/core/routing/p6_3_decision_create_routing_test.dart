// test/core/routing/p6_3_decision_create_routing_test.dart
//
// P6.3 — Wire Decision Create into GoRouter.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P6.3 — Decision Create wired into GoRouter', () {
    test('app_router.dart imports DecisionCreateScreen', () {
      final file = File('lib/core/routing/app_router.dart');
      final content = file.readAsStringSync();
      expect(
        content.contains(
            "import '../../features/trackc/presentation/screens/decision_create_screen.dart';"),
        isTrue,
      );
    });

    test('app_router.dart has decision-create route', () {
      final file = File('lib/core/routing/app_router.dart');
      final content = file.readAsStringSync();
      expect(content.contains("path: 'create'"), isTrue);
      expect(content.contains("name: 'trackc-decision-create'"), isTrue);
    });

    test('decisions_list_screen.dart uses context.push for navigation', () {
      final file = File(
          'lib/features/trackc/presentation/screens/decisions_list_screen.dart');
      final content = file.readAsStringSync();
      expect(content.contains("context.push<bool>"), isTrue);
    });

    test('decisions_list_screen.dart does NOT use MaterialPageRoute for create',
        () {
      final file = File(
          'lib/features/trackc/presentation/screens/decisions_list_screen.dart');
      final content = file.readAsStringSync();
      expect(content.contains("MaterialPageRoute"), isFalse);
    });

    test('route is deep-linkable via /family/:id/governance/decisions/create',
        () {
      final file = File('lib/core/routing/app_router.dart');
      final content = file.readAsStringSync();
      // The route path 'create' is a child of 'decisions' which is a child
      // of 'governance' which is a child of '/family/:id'
      expect(content.contains("path: 'create'"), isTrue);
      expect(content.contains("path: 'decisions'"), isTrue);
      expect(content.contains("path: '/family/:id/governance'"), isTrue);
    });
  });
}
