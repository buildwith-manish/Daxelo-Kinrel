// test/features/festival_theme/festival_theme_test.dart
//
// P8.2b — Festival theming tests.
// Verifies the overlay is OFF by default and must be opted into.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/festival_theme/festival_theme_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P8.2b — FestivalThemeController', () {
    test('overlay is OFF by default (no surprise visual change)', () {
      final c = FestivalThemeController();
      expect(c.state.isOverlayEnabled, isFalse);
      expect(c.state.isOverlayActive, isFalse);
      expect(c.state.activeTheme, isNull);
      c.dispose();
    });

    test('selecting a theme does NOT auto-enable the overlay', () {
      final c = FestivalThemeController();
      c.selectTheme('diwali');
      expect(c.state.activeTheme?.id, 'diwali');
      expect(c.state.isOverlayEnabled, isFalse);
      expect(c.state.isOverlayActive, isFalse);
      c.dispose();
    });

    test('overlay only active when enabled AND a theme is selected', () {
      final c = FestivalThemeController();
      c.selectTheme('eid');
      c.enableOverlay();
      expect(c.state.isOverlayActive, isTrue);
      c.disableOverlay();
      expect(c.state.isOverlayActive, isFalse);
      c.dispose();
    });

    test('toggle flips the master switch', () {
      final c = FestivalThemeController();
      c.toggleOverlay();
      expect(c.state.isOverlayEnabled, isTrue);
      c.toggleOverlay();
      expect(c.state.isOverlayEnabled, isFalse);
      c.dispose();
    });

    test('unknown theme id is a no-op', () {
      final c = FestivalThemeController();
      c.selectTheme('does-not-exist');
      expect(c.state.activeTheme, isNull);
      c.dispose();
    });

    test('reset clears selection and overlay', () {
      final c = FestivalThemeController();
      c.selectTheme('onam');
      c.enableOverlay();
      c.reset();
      expect(c.state.activeTheme, isNull);
      expect(c.state.isOverlayEnabled, isFalse);
      c.dispose();
    });

    test('default theme catalogue is non-empty and neutral', () {
      final c = FestivalThemeController();
      expect(c.state.available, isNotEmpty);
      for (final t in c.state.available) {
        expect(t.id, isNotEmpty);
        expect(t.name, isNotEmpty);
        expect(t.motif, isNotEmpty);
      }
      c.dispose();
    });
  });
}
