// test/graph/widgets/on_this_day_badge_test.dart
//
// P3.7 — "On this day" resurfacing in-graph.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/widgets/on_this_day_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P3.7 — OnThisDayEvent model', () {
    test('birthday event constructs with correct fields', () {
      const event = OnThisDayEvent(
        personId: 'p1',
        type: OnThisDayEventType.birthday,
        year: 1990,
        title: 'Birthday today',
      );
      expect(event.personId, equals('p1'));
      expect(event.type, equals(OnThisDayEventType.birthday));
      expect(event.year, equals(1990));
    });

    test('anniversary event constructs with correct fields', () {
      const event = OnThisDayEvent(
        personId: 'p2',
        type: OnThisDayEventType.anniversary,
        year: 2015,
      );
      expect(event.type, equals(OnThisDayEventType.anniversary));
      expect(event.year, equals(2015));
    });

    test('memory event constructs with correct fields', () {
      const event = OnThisDayEvent(
        personId: 'p3',
        type: OnThisDayEventType.memory,
        year: 2020,
        description: 'A family picnic',
      );
      expect(event.type, equals(OnThisDayEventType.memory));
      expect(event.description, equals('A family picnic'));
    });

    test('semanticsLabel is correct per type', () {
      const birthday =
          OnThisDayEvent(personId: 'p1', type: OnThisDayEventType.birthday);
      const anniversary =
          OnThisDayEvent(personId: 'p2', type: OnThisDayEventType.anniversary);
      const memory = OnThisDayEvent(
          personId: 'p3', type: OnThisDayEventType.memory, year: 2020);
      expect(birthday.semanticsLabel, equals('Birthday today'));
      expect(anniversary.semanticsLabel, equals('Anniversary today'));
      expect(memory.semanticsLabel, equals('Memory from this day in 2020'));
    });

    test('icon is correct per type', () {
      const birthday =
          OnThisDayEvent(personId: 'p1', type: OnThisDayEventType.birthday);
      const anniversary =
          OnThisDayEvent(personId: 'p2', type: OnThisDayEventType.anniversary);
      const memory =
          OnThisDayEvent(personId: 'p3', type: OnThisDayEventType.memory);
      expect(birthday.icon, equals(Icons.cake_outlined));
      expect(anniversary.icon, equals(Icons.favorite_outline));
      expect(memory.icon, equals(Icons.photo_outlined));
    });

    test('color is correct per type', () {
      const birthday =
          OnThisDayEvent(personId: 'p1', type: OnThisDayEventType.birthday);
      const anniversary =
          OnThisDayEvent(personId: 'p2', type: OnThisDayEventType.anniversary);
      const memory =
          OnThisDayEvent(personId: 'p3', type: OnThisDayEventType.memory);
      expect(birthday.color, equals(const Color(0xFFE8612A)));
      expect(anniversary.color, equals(const Color(0xFFFFD700)));
      expect(memory.color, equals(const Color(0xFF4A90E2)));
    });
  });

  group('P3.7 — onThisDayEventForPerson logic', () {
    OnThisDayEvent? computeEvent(Map<String, dynamic> p, DateTime now) {
      final personId = p['id']?.toString();
      if (personId == null || personId.isEmpty) return null;
      final dobStr = p['dateOfBirth'] as String?;
      if (dobStr != null && dobStr.isNotEmpty) {
        final dob = DateTime.tryParse(dobStr);
        if (dob != null && dob.month == now.month && dob.day == now.day) {
          return OnThisDayEvent(
            personId: personId,
            type: OnThisDayEventType.birthday,
            year: dob.year,
            title: 'Birthday today',
          );
        }
      }
      final annivStr = p['anniversaryDate'] as String?;
      if (annivStr != null && annivStr.isNotEmpty) {
        final anniv = DateTime.tryParse(annivStr);
        if (anniv != null &&
            anniv.month == now.month &&
            anniv.day == now.day) {
          return OnThisDayEvent(
            personId: personId,
            type: OnThisDayEventType.anniversary,
            year: anniv.year,
            title: 'Wedding Anniversary',
          );
        }
      }
      return null;
    }

    test('returns birthday event when today is birthday', () {
      final now = DateTime(2026, 7, 13);
      final p = <String, dynamic>{
        'id': 'p1',
        'dateOfBirth': '1990-07-13T00:00:00Z',
      };
      final event = computeEvent(p, now);
      expect(event, isNotNull);
      expect(event!.type, equals(OnThisDayEventType.birthday));
      expect(event.year, equals(1990));
    });

    test('returns anniversary event when today is anniversary', () {
      final now = DateTime(2026, 7, 13);
      final p = <String, dynamic>{
        'id': 'p2',
        'anniversaryDate': '2015-07-13T00:00:00Z',
      };
      final event = computeEvent(p, now);
      expect(event, isNotNull);
      expect(event!.type, equals(OnThisDayEventType.anniversary));
      expect(event.year, equals(2015));
    });

    test('returns null when birthday is tomorrow', () {
      final now = DateTime(2026, 7, 13);
      final p = <String, dynamic>{
        'id': 'p1',
        'dateOfBirth': '1990-07-14T00:00:00Z',
      };
      expect(computeEvent(p, now), isNull);
    });

    test('returns null when dateOfBirth is missing', () {
      final now = DateTime(2026, 7, 13);
      final p = <String, dynamic>{'id': 'p1'};
      expect(computeEvent(p, now), isNull);
    });

    test('returns null when personId is missing', () {
      final now = DateTime(2026, 7, 13);
      final p = <String, dynamic>{'dateOfBirth': '1990-07-13T00:00:00Z'};
      expect(computeEvent(p, now), isNull);
    });

    test('birthday takes priority over anniversary', () {
      final now = DateTime(2026, 7, 13);
      final p = <String, dynamic>{
        'id': 'p1',
        'dateOfBirth': '1990-07-13T00:00:00Z',
        'anniversaryDate': '2015-07-13T00:00:00Z',
      };
      final event = computeEvent(p, now);
      expect(event!.type, equals(OnThisDayEventType.birthday));
    });
  });

  group('P3.7 — Badge widget contract', () {
    testWidgets('OnThisDayBadge renders with correct icon and is tappable',
        (tester) async {
      const event = OnThisDayEvent(
        personId: 'p1',
        type: OnThisDayEventType.birthday,
        year: 1990,
      );
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnThisDayBadge(
              event: event,
              personName: 'Aarav',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.cake_outlined), findsOneWidget);
      await tester.tap(find.byType(OnThisDayBadge));
      expect(tapped, isTrue);
    });

    testWidgets('OnThisDayBadge has correct Semantics label', (tester) async {
      const event = OnThisDayEvent(
        personId: 'p1',
        type: OnThisDayEventType.anniversary,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnThisDayBadge(
              event: event,
              personName: 'Priya',
              onTap: () {},
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Priya anniversary today'),
        findsOneWidget,
      );
    });
  });
}
