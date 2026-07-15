// test/features/unified_timeline/unified_timeline_test.dart
// P7.4d — Unified family timeline tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/features/unified_timeline/providers/unified_timeline_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P7.4d — Unified timeline', () {
    test('UnifiedTimelineEvent constructs correctly', () {
      final event = UnifiedTimelineEvent(
        id: 'e1',
        type: TimelineEventType.birth,
        date: DateTime(1990, 5, 15),
        title: 'Aarav born',
        personName: 'Aarav',
      );
      expect(event.id, equals('e1'));
      expect(event.type, equals(TimelineEventType.birth));
      expect(event.title, equals('Aarav born'));
    });

    test('colorValue is unique per type', () {
      final birthColor = UnifiedTimelineEvent(
              id: '1', type: TimelineEventType.birth, date: DateTime.now(), title: '')
          .colorValue;
      final marriageColor = UnifiedTimelineEvent(
              id: '2', type: TimelineEventType.marriage, date: DateTime.now(), title: '')
          .colorValue;
      final deathColor = UnifiedTimelineEvent(
              id: '3', type: TimelineEventType.death, date: DateTime.now(), title: '')
          .colorValue;
      expect(birthColor, isNot(equals(marriageColor)));
      expect(marriageColor, isNot(equals(deathColor)));
      expect(birthColor, isNot(equals(deathColor)));
    });

    test('sortedEvents returns events sorted by date desc', () {
      final controller = UnifiedTimelineController();
      controller.mergeEvents([
        UnifiedTimelineEvent(
            id: '1', type: TimelineEventType.birth, date: DateTime(1990), title: 'Old'),
        UnifiedTimelineEvent(
            id: '2', type: TimelineEventType.birth, date: DateTime(2020), title: 'New'),
      ]);
      final sorted = controller.state.sortedEvents;
      expect(sorted.first.title, equals('New'));
      expect(sorted.last.title, equals('Old'));
      controller.dispose();
    });

    test('filterByType returns only matching events', () {
      final controller = UnifiedTimelineController();
      controller.mergeEvents([
        UnifiedTimelineEvent(
            id: '1', type: TimelineEventType.birth, date: DateTime(1990), title: 'Birth'),
        UnifiedTimelineEvent(
            id: '2', type: TimelineEventType.marriage, date: DateTime(2020), title: 'Marriage'),
      ]);
      final births = controller.filterByType(TimelineEventType.birth);
      expect(births.length, equals(1));
      expect(births.first.title, equals('Birth'));
      controller.dispose();
    });

    test('addEvent adds to existing events', () {
      final controller = UnifiedTimelineController();
      controller.addEvent(UnifiedTimelineEvent(
          id: '1', type: TimelineEventType.birth, date: DateTime(1990), title: 'Test'));
      expect(controller.state.events.length, equals(1));
      controller.dispose();
    });

    test('TimelineEventType has 6 types', () {
      expect(TimelineEventType.values.length, equals(6));
      expect(TimelineEventType.values, contains(TimelineEventType.birth));
      expect(TimelineEventType.values, contains(TimelineEventType.marriage));
      expect(TimelineEventType.values, contains(TimelineEventType.death));
      expect(TimelineEventType.values, contains(TimelineEventType.calendar));
      expect(TimelineEventType.values, contains(TimelineEventType.memory));
      expect(TimelineEventType.values, contains(TimelineEventType.milestone));
    });
  });
}
