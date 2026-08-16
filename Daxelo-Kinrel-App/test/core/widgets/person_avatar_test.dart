// test/core/widgets/person_avatar_test.dart
//
// v5.15 TEST: Shared PersonAvatar widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/widgets/person_avatar.dart';

void main() {
  group('v5.15 PersonAvatar', () {
    testWidgets('TEST 1: Shows initial when no photoUrl', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonAvatar(name: 'Alice', size: 40),
          ),
        ),
      );
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('TEST 2: Shows ? for empty name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonAvatar(name: '', size: 40),
          ),
        ),
      );
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('TEST 3: Custom colors render', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonAvatar(
              name: 'Bob',
              size: 36,
              backgroundColor: Colors.red,
              textColor: Colors.white,
            ),
          ),
        ),
      );
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('TEST 4: Custom size affects font', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonAvatar(name: 'Charlie', size: 64),
          ),
        ),
      );
      expect(find.text('C'), findsOneWidget);
      final text = tester.widget<Text>(find.text('C'));
      expect(text.style?.fontSize, closeTo(25.6, 0.1));
    });

    testWidgets('TEST 5: onTap callback fires', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonAvatar(
              name: 'Dave',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(PersonAvatar));
      expect(tapped, isTrue);
    });
  });
}
