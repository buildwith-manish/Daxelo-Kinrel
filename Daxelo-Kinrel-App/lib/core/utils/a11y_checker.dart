// lib/core/utils/a11y_checker.dart
//
// DAXELO KINREL — Accessibility Checker Utility (P3-F5)
//
// Debug-only utility that helps identify accessibility issues.
// In debug mode, it prints guidance for running Flutter's
// built-in accessibility checks.

import 'package:flutter/foundation.dart';

class A11yChecker {
  A11yChecker._();

  /// Print accessibility audit guidance in debug mode.
  /// Call once from main.dart in debug mode only.
  static void runAudit() {
    assert(() {
      debugPrint('══════════════════════════════════════════════════');
      debugPrint('🔍 A11Y Accessibility Audit Guide');
      debugPrint('══════════════════════════════════════════════════');
      debugPrint('');
      debugPrint('Run these commands to check accessibility:');
      debugPrint('  flutter analyze --suggestions');
      debugPrint('  flutter test --tags accessibility');
      debugPrint('');
      debugPrint('Key checks:');
      debugPrint('  ✓ All IconButtons have tooltips');
      debugPrint('  ✓ All images have semanticLabel');
      debugPrint('  ✓ All tap targets ≥ 48×48 dp');
      debugPrint('  ✓ All GestureDetectors wrapped in Semantics');
      debugPrint('  ✓ CustomPainter graphs have Semantics');
      debugPrint('  ✓ Form fields have labels');
      debugPrint('');
      debugPrint('Use AccessibleIconButton widget instead of IconButton');
      debugPrint('Use semanticButton() / semanticImage() from accessibility_utils.dart');
      debugPrint('══════════════════════════════════════════════════');
      return true;
    }());
  }

  /// Log a tap target size issue in debug mode.
  static void logSmallTapTarget(String widgetName, double width, double height) {
    assert(() {
      if (width < 48 || height < 48) {
        debugPrint('⚠️ A11Y: $widgetName tap target too small '
            '(${width.toStringAsFixed(1)}×${height.toStringAsFixed(1)}dp, '
            'minimum 48×48dp)');
      }
      return true;
    }());
  }
}
