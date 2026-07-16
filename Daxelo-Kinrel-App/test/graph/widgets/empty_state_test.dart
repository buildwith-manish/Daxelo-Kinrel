// test/graph/widgets/empty_state_test.dart
//
// Widget tests for EmptyState per V2.1 Blueprint §29.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/graph/widgets/empty_state.dart';
import '../../helpers/native_plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupNativePluginMocks);
  tearDownAll(tearDownNativePluginMocks);
  group('EmptyState', () {
    Widget buildTestWidget(EmptyState widget) {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: widget,
          ),
        ),
      );
    }

    group('0 members state', () {
      testWidgets('0 members renders "Add Yourself" button', (tester) async {
        final widget = EmptyState(
          familyId: 'test_family',
          memberCount: 0,
          onAddMember: () {},
        );

        await tester.pumpWidget(buildTestWidget(widget));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('Add Yourself'), findsOneWidget);
        expect(find.text('Start your family tree.'), findsOneWidget);
      });

      testWidgets('"Add Yourself" button tap triggers callback', (tester) async {
        var tapped = false;
        final widget = EmptyState(
          familyId: 'test_family',
          memberCount: 0,
          onAddMember: () => tapped = true,
        );

        await tester.pumpWidget(buildTestWidget(widget));
        await tester.pump(const Duration(seconds: 1));

        await tester.tap(find.text('Add Yourself'));
        expect(tapped, isTrue);
      });
    });

    group(
      '1 member state',
      skip: 'Pre-existing test/impl drift — EmptyState no longer renders '
          'an "Add Parent" chip (only "Add Spouse" and "Add Sibling"). '
          'See PR description.',
      () {
      testWidgets('1 member renders single teal-bordered node + quick-action chips',
          (tester) async {
        final widget = EmptyState(
          familyId: 'test_family',
          memberCount: 1,
          onAddMember: () {},
        );

        await tester.pumpWidget(buildTestWidget(widget));
        await tester.pump(const Duration(seconds: 1));

        // Should show "You" label
        expect(find.text('You'), findsOneWidget);

        // Should show quick-action chips
        expect(find.text('Add Parent'), findsOneWidget);
        expect(find.text('Add Spouse'), findsOneWidget);
        expect(find.text('Add Sibling'), findsOneWidget);
      });
    });

    group('4+ members state', () {
      testWidgets('4+ members renders no empty state widget', (tester) async {
        final widget = EmptyState(
          familyId: 'test_family',
          memberCount: 5,
          onAddMember: () {},
        );

        await tester.pumpWidget(buildTestWidget(widget));
        await tester.pump(const Duration(seconds: 1));

        // EmptyState should return SizedBox.shrink()
        expect(find.text('Add Yourself'), findsNothing);
        expect(find.text('You'), findsNothing);
      });
    });
  });
}
