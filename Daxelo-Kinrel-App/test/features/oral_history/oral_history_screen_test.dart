// test/features/oral_history/oral_history_screen_test.dart
//
// Widget tests for the Oral History screen's animated preview card (v95).
//
// These tests pump the full OralHistoryScreen in a ProviderScope (with
// supabaseProvider overridden to null so the notifier starts empty —
// the production default) and verify:
//   1. The animated preview card renders in the empty state (with
//      generic, clearly-illustrative placeholder content)
//   2. The category tag cycles through Family → Recipe → Wisdom every
//      ~5 seconds when reduced-motion is OFF
//   3. Reduced-motion shows a single static category (no cycling)
//   4. The preview uses generic neutral copy (not real-looking) —
//      no fake narrator name, "0:00" duration, generic title
//
// The OralHistoryScreen requires the `record` and `permission_handler`
// plugins which are mocked via the `native_plugin_mocks` helper.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/core/services/supabase_service.dart';
import 'package:kinrel/features/oral_history/presentation/oral_history_screen.dart';
import '../../helpers/native_plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupNativePluginMocks);
  tearDownAll(tearDownNativePluginMocks);

  // Override supabaseProvider to return null so the notifier starts
  // empty (production default) — the screen renders the zero-stories
  // empty state with the animated preview card.
  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          supabaseProvider.overrideWithValue(null),
        ],
      );

  group('OralHistoryScreen — animated preview card (v95)', () {
    testWidgets('renders the animated preview card in the empty state',
        (tester) async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OralHistoryScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The preview card title — generic, clearly-illustrative.
      expect(
        find.text('A story waiting to be told'),
        findsOneWidget,
        reason: 'The animated preview card should render in the empty '
            'state, showing the generic placeholder title.',
      );

      // The "invitation to act" copy from KinrelEmptyState stays.
      expect(find.text('No Stories Yet'), findsOneWidget);
      expect(find.text('Record First Story'), findsOneWidget);
    });

    testWidgets('preview card shows "0:00" duration (not a fake time)',
        (tester) async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OralHistoryScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The duration badge shows "0:00" — clearly a placeholder, not
      // a fake specific duration like "12:34" that could read as real
      // data.
      expect(
        find.text('0:00'),
        findsOneWidget,
        reason: 'The preview card duration badge should show "0:00" '
            '(a clearly-generic placeholder), not a fake specific '
            'duration.',
      );
    });

    testWidgets(
        'category tag cycles through Family → Recipe → Wisdom after ~5s',
        (tester) async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OralHistoryScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Initially shows the first category (Family → shortLabel "Family").
      expect(find.text('Family'), findsOneWidget);

      // Pump past the 5s category cycle interval.
      await tester.pump(const Duration(milliseconds: 5000));
      await tester.pump(const Duration(milliseconds: 200));

      // After the cycle, the second category (Recipe) should be visible.
      expect(
        find.text('Recipe'),
        findsOneWidget,
        reason: 'After ~5s the preview card should cycle to the '
            'Recipe category tag.',
      );
      // And the first category should be gone.
      expect(find.text('Family'), findsNothing);
    });

    testWidgets(
        'reduced-motion shows a single static category (no cycling)',
        (tester) async {
      final container = makeContainer();
      addTearDown(container.dispose);

      // Wrap with MediaQuery(disableAnimations: true) to simulate the
      // platform reduced-motion accessibility setting — this is what
      // AppMotion.reducedMotion(context) checks internally.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: OralHistoryScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The first category (Family) is still visible — the card
      // renders, just doesn't cycle.
      expect(find.text('Family'), findsOneWidget);

      // Pump well past the 5s cycle interval — the Timer should not
      // be running in reduced-motion mode, so the category should NOT
      // change.
      await tester.pump(const Duration(milliseconds: 6000));
      await tester.pump(const Duration(milliseconds: 200));

      // Still the first category — no cycling in reduced-motion mode.
      expect(
        find.text('Family'),
        findsOneWidget,
        reason: 'In reduced-motion mode the preview card should show a '
            'single static category, not cycle through them.',
      );
      expect(
        find.text('Recipe'),
        findsNothing,
        reason: 'The Recipe category should NOT appear in reduced-motion '
            'mode — the cycle is suppressed.',
      );
    });

    testWidgets('preview card uses generic neutral copy (not real-looking)',
        (tester) async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OralHistoryScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The preview card title should be generic and non-specific
      // ("A story waiting to be told") — NOT a specific fabricated
      // story title that could be mistaken for real seed content.
      expect(find.text('A story waiting to be told'), findsOneWidget);

      // The description should also be generic, demonstrating the
      // breadth of what can be recorded.
      expect(
        find.textContaining('Grandma\'s recipe'),
        findsOneWidget,
      );

      // The duration badge should show "0:00" — not a fake specific
      // duration.
      expect(find.text('0:00'), findsOneWidget);

      // The category tag should be one of the real categories (Family,
      // Recipe, Wisdom) — NOT a fabricated category name.
      expect(find.text('Family'), findsOneWidget);
    });

    testWidgets('preview card does NOT show real narrator names',
        (tester) async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OralHistoryScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // None of the demo narrator names should appear in the empty
      // state — the preview card uses a generic placeholder, not a
      // real-looking name.
      expect(find.text('Suresh Kumar Sharma'), findsNothing);
      expect(find.text('Kamla Sharma'), findsNothing);
      expect(find.text('Saroj Devi'), findsNothing);
      expect(find.text('Ravi Sharma'), findsNothing);
      expect(find.text('Sunita Sharma'), findsNothing);
    });

    testWidgets('preview card does NOT show real demo story titles',
        (tester) async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OralHistoryScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // None of the user-mentioned seeded demo titles should appear
      // in the empty state — the preview card uses a generic title
      // ("A story waiting to be told"), not a real-looking one.
      expect(find.text('How Dada Built Sharma Haveli'), findsNothing);
      expect(find.text("Dadi's Secret Ghevar Recipe"), findsNothing);
      expect(find.text('The Night We Left Lahore'), findsNothing);
      expect(find.text('Why We Light the Akhand Jyot on Diwali'),
          findsNothing);
      expect(find.text("Nani Ma's Wisdom on Raising Children"),
          findsNothing);
      expect(find.text("Arjun & Priya's Wedding — The Full Story"),
          findsNothing);
    });
  });
}
