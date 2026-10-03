// test/features/memories/memories_screen_test.dart
//
// Widget + unit tests for the Memories & Timeline screen — covering the
// audit fixes:
//   1. Demo data is NOT loaded by default (production default = empty)
//   2. Empty state renders correctly when memory count is zero
//   3. Filter pills render with correct active/inactive visual state
//   4. Pin-count badge is wired to filter pinned memories
//   5. Pin toggle on a card updates the count badge
//   6. `loadDemoData()` is still available for tests/debug
//
// Tests run headlessly via the `native_plugin_mocks` helper.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinrel/features/memories/presentation/memories_screen.dart';
import 'package:kinrel/features/memories/providers/memories_provider.dart';
import '../../helpers/native_plugin_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupNativePluginMocks);
  tearDownAll(tearDownNativePluginMocks);

  group('MemoriesNotifier — production default', () {
    test('MemoriesNotifier starts EMPTY (no demo data) by default', () {
      final notifier = MemoriesNotifier();
      expect(notifier.state.events, isEmpty,
          reason:
              'A brand-new MemoriesNotifier must not contain the seeded '
              '"Sharma family" demo data — real families start empty so '
              'they see the proper invitation-to-act empty state.');
      expect(notifier.state.onThisDayMemories, isEmpty);
      expect(notifier.state.hasMemories, isFalse);
      expect(notifier.state.filteredEvents, isEmpty);
      expect(notifier.state.hasPinnedMemories, isFalse);
      expect(notifier.state.pinnedCount, 0);
      notifier.dispose();
    });

    test('loadDemoData() populates the seeded demo events for tests', () {
      final notifier = MemoriesNotifier();
      notifier.loadDemoData();
      expect(notifier.state.events, isNotEmpty,
          reason:
              'loadDemoData() must populate the demo events so tests can '
              'render the screen with known data.');
      expect(notifier.state.onThisDayMemories, isNotEmpty);
      expect(notifier.state.hasMemories, isTrue);
      notifier.dispose();
    });

    test('demoMemoryEvents contains the documented seed entries', () {
      // Pin down the seeded data so a refactor that accidentally
      // removes one of the user-mentioned entries is caught.
      final titles = demoMemoryEvents.map((e) => e.title).toSet();
      expect(titles, contains('Aarav Sharma was born'));
      expect(titles, contains("Rajesh & Meera's Wedding"));
      expect(titles, contains('Ravi received Padma Shri Award'));
      expect(titles, contains('Neha graduated from AIIMS'));
      expect(titles, contains('Holi at the Farmhouse'));
    });
  });

  group('MemoriesFilter — showPinnedOnly', () {
    test('default filter has showPinnedOnly=false', () {
      const filter = MemoriesFilter();
      expect(filter.showPinnedOnly, isFalse);
      expect(filter.isClear, isTrue);
      expect(filter.pillsActive, isFalse);
    });

    test('showPinnedOnly=true makes filter not clear, but pills still inactive', () {
      const filter = MemoriesFilter(showPinnedOnly: true);
      expect(filter.isClear, isFalse);
      expect(filter.pillsActive, isFalse,
          reason:
              'pillsActive reports the year/type/member pill filters only — '
              'showPinnedOnly is a separate toggle and should NOT inflate '
              'pillsActive (it has its own banner).');
    });

    test('clearPinnedOnly resets showPinnedOnly but keeps pills', () {
      const filter = MemoriesFilter(
        selectedYear: 2024,
        showPinnedOnly: true,
      );
      final cleared = filter.copyWith(clearPinnedOnly: true);
      expect(cleared.showPinnedOnly, isFalse);
      expect(cleared.selectedYear, 2024,
          reason: 'Clearing pinned-only must preserve pill filters.');
    });

    test('activePillCount counts year/type/member only', () {
      const noFilters = MemoriesFilter();
      expect(noFilters.activePillCount, 0);

      const oneFilter = MemoriesFilter(selectedYear: 2024);
      expect(oneFilter.activePillCount, 1);

      const twoFilters = MemoriesFilter(
        selectedYear: 2024,
        selectedType: MemoryEventType.marriage,
      );
      expect(twoFilters.activePillCount, 2);

      const threeFilters = MemoriesFilter(
        selectedYear: 2024,
        selectedType: MemoryEventType.marriage,
        selectedMember: 'Arjun Sharma',
      );
      expect(threeFilters.activePillCount, 3);

      // showPinnedOnly does NOT add to the pill count.
      const pinnedOnly = MemoriesFilter(showPinnedOnly: true);
      expect(pinnedOnly.activePillCount, 0);
    });
  });

  group('MemoriesNotifier — togglePinnedOnly', () {
    test('togglePinnedOnly flips showPinnedOnly back and forth', () {
      final notifier = MemoriesNotifier();
      notifier.loadDemoData();
      expect(notifier.state.filter.showPinnedOnly, isFalse);

      notifier.togglePinnedOnly();
      expect(notifier.state.filter.showPinnedOnly, isTrue);
      // The filtered list should now contain only pinned events.
      final pinned = notifier.state.events.where((e) => e.isPinned).toList();
      expect(notifier.state.filteredEvents.length, pinned.length);
      expect(
        notifier.state.filteredEvents.every((e) => e.isPinned),
        isTrue,
      );

      notifier.togglePinnedOnly();
      expect(notifier.state.filter.showPinnedOnly, isFalse);
      // All events should be visible again.
      expect(
        notifier.state.filteredEvents.length,
        notifier.state.events.length,
      );
      notifier.dispose();
    });

    test('togglePin on a card updates pinnedCount', () {
      final notifier = MemoriesNotifier();
      notifier.loadDemoData();
      final initialPinned = notifier.state.pinnedCount;
      expect(initialPinned, greaterThan(0),
          reason: 'Demo data has at least one pinned event by default.');

      // Find a NON-pinned event to pin.
      final nonPinned = notifier.state.events.firstWhere((e) => !e.isPinned);
      notifier.togglePin(nonPinned.id);
      expect(notifier.state.pinnedCount, initialPinned + 1);

      // Toggling again unpins it.
      notifier.togglePin(nonPinned.id);
      expect(notifier.state.pinnedCount, initialPinned);
      notifier.dispose();
    });

    test('togglePin on the last pinned memory does NOT auto-clear showPinnedOnly',
        () {
      // If the user unpins the LAST pinned memory while
      // showPinnedOnly is active, the filtered list goes empty.
      // We intentionally do NOT auto-clear the filter — the
      // "no pinned memories" empty state handles that UX with a
      // "View all" affordance.
      final notifier = MemoriesNotifier();
      // Construct a single-pinned-event state.
      final event = MemoryEvent(
        id: 'only-pinned',
        title: 'Test pinned',
        type: MemoryEventType.custom,
        date: DateTime(2024, 1, 1),
        isPinned: true,
      );
      // Replace the demo events with this single pinned event.
      // (Using addEvent on an empty notifier.)
      final empty = MemoriesNotifier();
      empty.addEvent(event);
      empty.togglePinnedOnly();
      expect(empty.state.filter.showPinnedOnly, isTrue);
      expect(empty.state.filteredEvents.length, 1);

      empty.togglePin('only-pinned');
      expect(empty.state.pinnedCount, 0);
      expect(empty.state.filter.showPinnedOnly, isTrue,
          reason:
              'Unpinning the last pinned memory must NOT auto-clear the '
              'pinned-only filter — the empty state handles the UX.');
      expect(empty.state.filteredEvents, isEmpty);
      empty.dispose();
      notifier.dispose();
    });
  });

  group('MemoriesScreen — empty state (zero memories)', () {
    testWidgets('renders the invitation-to-act empty state by default',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: MemoriesScreen()),
        ),
      );
      // Pump once to render the initial frame, plus a tiny delay for
      // any animations (flutter_animate fade-in).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The "invitation to act" copy from KinrelEmptyState.
      expect(find.text('No Memories Yet'), findsOneWidget);
      expect(find.text('Add First Memory'), findsOneWidget);
      // The teaching subtitle text.
      expect(
        find.textContaining("Capture your family's first moment"),
        findsOneWidget,
      );
    });

    testWidgets(
        'does NOT render the filter pills when there are zero memories',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: MemoriesScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The default pill labels — should NOT be present.
      expect(find.text('Year'), findsNothing);
      expect(find.text('Event Type'), findsNothing);
      expect(find.text('Member'), findsNothing);
    });

    testWidgets('does NOT render the demo seeded data by default',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: MemoriesScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // None of the user-mentioned seeded demo titles should render.
      expect(find.text('Aarav Sharma was born'), findsNothing);
      expect(find.text("Rajesh & Meera's Wedding"), findsNothing);
      expect(find.text('Ravi received Padma Shri Award'), findsNothing);
      expect(find.text('Neha graduated from AIIMS'), findsNothing);
      expect(find.text('Holi at the Farmhouse'), findsNothing);
    });
  });

  group('MemoriesScreen — filter pill visual states', () {
    testWidgets('renders all three pills in inactive state by default',
        (tester) async {
      // Use an override to load demo data for this test.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(memoriesProvider.notifier).loadDemoData();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MemoriesScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // All three default labels present.
      expect(find.text('Year'), findsOneWidget);
      expect(find.text('Event Type'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
      // The "Clear filters" link should NOT be visible with no active filter.
      expect(find.text('Clear filters'), findsNothing);
    });

    testWidgets('year filter pill shows active label and "Clear filters" link',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(memoriesProvider.notifier).loadDemoData();
      container.read(memoriesProvider.notifier).setYearFilter(2024);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MemoriesScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The Year pill now shows "2024" instead of "Year".
      expect(find.text('2024'), findsOneWidget);
      expect(find.text('Year'), findsNothing);
      // "Clear filters" link is visible.
      expect(find.text('Clear filters'), findsOneWidget);
    });

    testWidgets('clear filters resets the pills to their default state',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(memoriesProvider.notifier).loadDemoData();
      container.read(memoriesProvider.notifier).setYearFilter(2024);
      container.read(memoriesProvider.notifier).clearFilters();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MemoriesScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Year'), findsOneWidget);
      expect(find.text('2024'), findsNothing);
      expect(find.text('Clear filters'), findsNothing);
    });
  });

  group('MemoriesScreen — pin-count badge', () {
    testWidgets('pin-count badge is hidden when there are no pinned memories',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Add a single NON-pinned event so the screen has memories but
      // none pinned → badge should be hidden.
      container.read(memoriesProvider.notifier).addEvent(MemoryEvent(
            id: 'no-pin',
            title: 'Unpinned test',
            type: MemoryEventType.custom,
            date: DateTime(2024, 1, 1),
          ));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MemoriesScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The pin-count badge is hidden when no pinned memories exist.
      // Look for the Tooltip text used by the badge.
      expect(find.byTooltip('Tap to show pinned only'), findsNothing);
      expect(find.byTooltip('Showing pinned only — tap to view all'),
          findsNothing);
    });

    testWidgets(
        'tapping the pin-count badge filters to pinned-only and shows the "view all" banner',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(memoriesProvider.notifier).loadDemoData();
      final pinnedCount = container.read(memoriesProvider).pinnedCount;
      expect(pinnedCount, greaterThan(0),
          reason: 'Demo data has at least one pinned event by default.');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MemoriesScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap the pin-count badge — it's the widget with the tooltip
      // "Tap to show pinned only".
      final badge = find.byTooltip('Tap to show pinned only');
      expect(badge, findsOneWidget);
      await tester.tap(badge);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // After tap: filter is active, "showing pinned only" banner visible,
      // and the badge itself flips to the active tooltip.
      expect(find.textContaining('Showing pinned only'), findsOneWidget);
      expect(find.byTooltip('Showing pinned only — tap to view all'),
          findsOneWidget);

      // Tap again to clear.
      await tester.tap(
          find.byTooltip('Showing pinned only — tap to view all'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Showing pinned only'), findsNothing);
    });
  });
}
