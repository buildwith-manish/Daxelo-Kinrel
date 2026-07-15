// test/features/trackc/p6_2_trackc_theme_test.dart
//
// P6.2 — Re-theme Trackc to match dark KinrelColors.
// Verifies that all Trackc presentation screens use KinrelColors.darkBackground
// as their Scaffold background color.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final trackcScreens = [
    'lib/features/trackc/presentation/screens/trackc_hub_screen.dart',
    'lib/features/trackc/presentation/screens/decision_detail_screen.dart',
    'lib/features/trackc/presentation/screens/decision_create_screen.dart',
    'lib/features/trackc/presentation/screens/decisions_list_screen.dart',
    'lib/features/trackc/presentation/screens/timeline_screen.dart',
    'lib/features/trackc/presentation/screens/analytics_screen.dart',
    'lib/features/trackc/presentation/screens/constitution_screen.dart',
    'lib/features/trackc/presentation/screens/learning_profile_screen.dart',
    'lib/features/trackc/presentation/screens/search_screen.dart',
    'lib/features/trackc/presentation/screens/secretary_screen.dart',
  ];

  group('P6.2 — Trackc screens use dark KinrelColors theme', () {
    for (final screenPath in trackcScreens) {
      test('${screenPath.split('/').last} imports KinrelColors', () {
        final file = File(screenPath);
        expect(file.existsSync(), isTrue,
            reason: '$screenPath should exist');
        final content = file.readAsStringSync();
        expect(
          content.contains("import '../../../../core/constants/brand_colors.dart';"),
          isTrue,
          reason: '$screenPath must import KinrelColors (brand_colors.dart)',
        );
      });

      test('${screenPath.split('/').last} uses KinrelColors.darkBackground', () {
        final file = File(screenPath);
        final content = file.readAsStringSync();
        expect(
          content.contains('KinrelColors.darkBackground'),
          isTrue,
          reason: '$screenPath must use KinrelColors.darkBackground as Scaffold bg',
        );
      });
    }

    test('all 10 Trackc screens are re-themed', () {
      var themedCount = 0;
      for (final screenPath in trackcScreens) {
        final file = File(screenPath);
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          if (content.contains('KinrelColors.darkBackground')) {
            themedCount++;
          }
        }
      }
      expect(themedCount, equals(10),
          reason: 'All 10 Trackc screens must be re-themed');
    });
  });
}
