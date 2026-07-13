// test/features/home_widgets/home_widget_provider_test.dart
//
// P9.2e — Home-screen widget tests.
// Verifies refresh intervals are clamped to a battery-friendly minimum.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/home_widgets/providers/home_widget_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P9.2e — HomeWidgetNotifier', () {
    test('starts with an empty pinned list', () {
      final n = HomeWidgetNotifier();
      expect(n.state.pinned, isEmpty);
      expect(n.state.error, isNull);
      // No engagement / view-count surface.
      n.dispose();
    });

    test('pin adds a config with a stable id', () {
      final n = HomeWidgetNotifier();
      n.pin(
        kind: HomeWidgetKind.upcomingOccasion,
        title: 'Next occasion',
      );
      expect(n.state.pinned, hasLength(1));
      expect(n.state.pinned.single.kind, HomeWidgetKind.upcomingOccasion);
      expect(n.state.pinned.single.id, isNotEmpty);
      n.dispose();
    });

    test('pin with empty title is rejected neutrally', () {
      final n = HomeWidgetNotifier();
      n.pin(kind: HomeWidgetKind.dailyBrief, title: '   ');
      expect(n.state.pinned, isEmpty);
      expect(n.state.error, 'Widget needs a title.');
      n.dispose();
    });

    test('refresh interval below the minimum is clamped up', () {
      final n = HomeWidgetNotifier();
      n.pin(
        kind: HomeWidgetKind.familyNote,
        title: 'Note',
        refreshInterval: const Duration(seconds: 5),
      );
      expect(
        n.state.pinned.single.refreshInterval,
        kMinWidgetRefresh,
      );
      n.dispose();
    });

    test('updateRefreshInterval clamps too', () {
      final n = HomeWidgetNotifier();
      n.pin(
        kind: HomeWidgetKind.kinrelSymbol,
        title: 'Symbol',
        refreshInterval: const Duration(hours: 1),
      );
      final id = n.state.pinned.single.id;
      n.updateRefreshInterval(id, const Duration(seconds: 1));
      expect(n.state.pinned.single.refreshInterval, kMinWidgetRefresh);
      n.dispose();
    });

    test('unpin removes by id', () {
      final n = HomeWidgetNotifier();
      n.pin(kind: HomeWidgetKind.familyNote, title: 'a');
      n.pin(kind: HomeWidgetKind.familyNote, title: 'b');
      final first = n.state.pinned.first.id;
      n.unpin(first);
      expect(n.state.pinned, hasLength(1));
      n.dispose();
    });

    test('availableKinds is non-empty and stable', () {
      final n = HomeWidgetNotifier();
      expect(n.state.availableKinds, contains(HomeWidgetKind.upcomingOccasion));
      expect(n.state.availableKinds, contains(HomeWidgetKind.dailyBrief));
      n.dispose();
    });
  });
}
