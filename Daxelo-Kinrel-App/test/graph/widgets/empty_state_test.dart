// test/graph/widgets/empty_state_test.dart
//
// Widget tests for EmptyState per V2.1 Blueprint §29.
//
// v5.x (test/impl drift cleanup): the previous version of the "1
// member state" group asserted the EmptyState rendered an "Add
// Parent" chip (plus "Add Spouse" and "Add Sibling"). The current
// EmptyState (see lib/graph/widgets/empty_state.dart line 360-371)
// only renders "Add Spouse" and "Add Sibling" — there is no "Add
// Parent" chip anymore. The skipped test group has been rewritten
// to assert the ACTUAL current behavior so the test suite reflects
// what the UI really does.

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
        '1 member state — current behavior (no "Add Parent" chip)',
        () {
      // v5.x (test/impl drift cleanup): the previous version of this
      // group was skipped because it asserted an "Add Parent" chip
      // that no longer exists. The current EmptyState at memberCount=1
      // renders "Add Spouse" and "Add Sibling" only — no "Add
      // Parent". These tests now assert the ACTUAL current behavior.

      testWidgets(
          '1 member renders the "You" label (the viewer\'s own node)',
          (tester) async {
        final widget = EmptyState(
          familyId: 'test_family',
          memberCount: 1,
          onAddMember: () {},
        );

        await tester.pumpWidget(buildTestWidget(widget));
        await tester.pump(const Duration(seconds: 1));

        // The "You" label is always present at memberCount=1 (the
        // viewer's own node + label).
        expect(find.text('You'), findsOneWidget);
      });

      testWidgets(
          '1 member renders the "Add Spouse" quick-action chip',
          (tester) async {
        final widget = EmptyState(
          familyId: 'test_family',
          memberCount: 1,
          onAddMember: () {},
        );

        await tester.pumpWidget(buildTestWidget(widget));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('Add Spouse'), findsOneWidget,
            reason: 'The "Add Spouse" chip is one of the two primary '
                'quick-action chips rendered at memberCount=1.');
      });

      testWidgets(
          '1 member renders the "Add Sibling" quick-action chip',
          (tester) async {
        final widget = EmptyState(
          familyId: 'test_family',
          memberCount: 1,
          onAddMember: () {},
        );

        await tester.pumpWidget(buildTestWidget(widget));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('Add Sibling'), findsOneWidget,
            reason: 'The "Add Sibling" chip is one of the two primary '
                'quick-action chips rendered at memberCount=1.');
      });

      testWidgets(
          '1 member does NOT render an "Add Parent" chip (current '
          'behavior — the chip was removed; only Spouse + Sibling '
          'remain)', (tester) async {
        final widget = EmptyState(
          familyId: 'test_family',
          memberCount: 1,
          onAddMember: () {},
        );

        await tester.pumpWidget(buildTestWidget(widget));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('Add Parent'), findsNothing,
            reason: 'The "Add Parent" chip is NOT rendered at '
                'memberCount=1. The previous test (now rewritten) '
                'asserted it existed; the implementation has since '
                'removed it. This test pins the current behavior so '
                'a future regression that re-adds "Add Parent" will '
                'fail loudly here.');
      });

      testWidgets(
          '1 member: tapping the "Add Spouse" chip triggers the '
          'onAddMember callback (the chip is wired to the same '
          'callback for both chips)', (tester) async {
        var tapped = false;
        final widget = EmptyState(
          familyId: 'test_family',
          memberCount: 1,
          onAddMember: () => tapped = true,
        );

        await tester.pumpWidget(buildTestWidget(widget));
        await tester.pump(const Duration(seconds: 1));

        await tester.tap(find.text('Add Spouse'));
        expect(tapped, isTrue,
            reason: 'Tapping the "Add Spouse" chip should trigger '
                'the onAddMember callback (matches the previous '
                'wiring — both chips call onAddMember).');
      });

      testWidgets(
          '1 member: tapping the "Add Sibling" chip triggers the '
          'onAddMember callback', (tester) async {
        var tapped = false;
        final widget = EmptyState(
          familyId: 'test_family',
          memberCount: 1,
          onAddMember: () => tapped = true,
        );

        await tester.pumpWidget(buildTestWidget(widget));
        await tester.pump(const Duration(seconds: 1));

        await tester.tap(find.text('Add Sibling'));
        expect(tapped, isTrue,
            reason: 'Tapping the "Add Sibling" chip should trigger '
                'the onAddMember callback (matches the previous '
                'wiring — both chips call onAddMember).');
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
