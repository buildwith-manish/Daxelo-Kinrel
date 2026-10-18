// test/graph/interaction/wedge_tap_state_test.dart
//
// The approved-preview TAP rules, verified at the wedge view-state
// level (the exact notifier methods _handleWedgeNodeTap calls in
// branch_affordance.dart):
//
//   • tap a collapsed person        → expand in place + focus them
//   • tap an expanded, unfocused    → focus them
//   • tap the focused, expanded      → collapse them + focus their parent
//   • tap the +N bubble             → load the next 8 (advance the page)
//   • the +N bubble disappears when nothing remains
//   • collapsed people with connections show a count badge (rule)
//
// The layout-level "+N disappears when empty" and "the bubble
// footprint never overlaps a node" properties are covered by
// test/graph/engine/viewer_wedge_layout_test.dart (the _expectZeroOverlaps
// helper includes chip footprints).

import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/graph/interaction/wedge_view_state.dart';

void main() {
  group('WedgeViewNotifier tap rules', () {
    late WedgeViewNotifier notifier;

    setUp(() {
      notifier = WedgeViewNotifier();
    });

    test('tapping a collapsed person expands them in place', () {
      expect(notifier.state.expandedRoots, isEmpty);
      notifier.expandPerson('a1');
      expect(notifier.state.expandedRoots, contains('a1'));
      expect(notifier.state.lastActionPersonId, 'a1');
      expect(notifier.state.expansionOrder, ['a1']);
    });

    test('the expansion of a collapsed person pages their first 8 '
        '(the layout shows at most 8 children per page)', () {
      // The paging itself is enforced by ViewerWedgeLayout (covered in
      // viewer_wedge_layout_test.dart); here we verify the page index
      // starts at 0 (the FIRST 8).
      notifier.expandPerson('a1');
      expect(notifier.state.pages, isNot(contains('a1')));
    });

    test('tapping a collapsed person also focuses them '
        '(expand + focus sequence, as _handleWedgeNodeTap runs it)', () {
      // Case 1 sequence: focus first, then expand.
      notifier.focusPerson('a1');
      notifier.expandPerson('a1');
      expect(notifier.state.focusedPersonId, 'a1');
      expect(notifier.state.expandedRoots, contains('a1'));
      expect(notifier.state.lastActionPersonId, 'a1');
      // One shared revision change per action — the camera fit rides it.
      expect(notifier.state.revision, 2);
    });

    test('tapping an expanded person who is NOT focused focuses them '
        '(no re-expansion, no page reset)', () {
      notifier.expandPerson('a1');
      final revisionAfterExpand = notifier.state.revision;
      notifier.focusPerson('a1');
      expect(notifier.state.focusedPersonId, 'a1');
      expect(notifier.state.expandedRoots, contains('a1'));
      expect(notifier.state.revision, revisionAfterExpand + 1);
    });

    test('tapping the FOCUSED, expanded person collapses them and '
        'focuses their parent', () {
      notifier.expandPerson('child1');
      notifier.focusPerson('child1');
      // A page was advanced for child1 — collapsing must clear it.
      notifier.advancePage('child1');
      expect(notifier.state.pages['child1'], 1);

      notifier.collapseAndFocusParent('child1', 'parent1');
      expect(notifier.state.expandedRoots, isNot(contains('child1')));
      expect(notifier.state.expansionOrder, isNot(contains('child1')));
      expect(notifier.state.pages, isNot(contains('child1')));
      expect(notifier.state.focusedPersonId, 'parent1');
      // The collapsed person stays the camera-fit target (their fit set
      // includes the parent they just focused).
      expect(notifier.state.lastActionPersonId, 'child1');
    });

    test('collapsing the focused person with an UNKNOWN parent clears '
        'the focus instead of crashing', () {
      notifier.expandPerson('child1');
      notifier.focusPerson('child1');
      notifier.collapseAndFocusParent('child1', null);
      expect(notifier.state.expandedRoots, isEmpty);
      expect(notifier.state.focusedPersonId, isNull);
    });

    test('the viewer (root) never collapses — focus only', () {
      // The root is never stored in expandedRoots (implicitly expanded),
      // so the tap machine's root guard maps to focusPerson only.
      expect(notifier.state.expandedRoots, isNot(contains('viewer')));
      notifier.focusPerson('viewer');
      expect(notifier.state.focusedPersonId, 'viewer');
    });

    test('tapping the +N bubble loads the next 8 (advances the page '
        'and bumps the shared revision)', () {
      notifier.expandPerson('a1');
      final revision = notifier.state.revision;
      notifier.advancePage('a1');
      expect(notifier.state.pages['a1'], 1);
      expect(notifier.state.lastActionPersonId, 'a1');
      expect(notifier.state.revision, revision + 1);
    });

    test('a +N tap on ANOTHER hub advances the page '
        '(focus is off by default — kWedgeTapFocusEnabled=false)', () {
      notifier.expandPerson('a1');
      notifier.expandPerson('a2');
      notifier.advancePage('a2');
      expect(notifier.state.focusedPersonId, isNull,
          reason: 'focus is not set when kWedgeTapFocusEnabled=false');
      expect(notifier.state.lastActionPersonId, 'a2');
    });

    test('re-expanding a collapsed person restores nothing stale '
        '(pages cleared, order re-recorded)', () {
      notifier.expandPerson('a1');
      notifier.advancePage('a1');
      notifier.collapseAndFocusParent('a1', 'viewer');
      expect(notifier.state.pages, isNot(contains('a1')));
      notifier.expandPerson('a1');
      // Page starts fresh at 0 (the first 8), order re-recorded.
      expect(notifier.state.pages, isNot(contains('a1')));
      expect(notifier.state.expansionOrder, ['a1']);
    });
  });

  group('+N count-badge rule (shouldShowWedgeCountBadge)', () {
    test('a collapsed person with connections shows the badge', () {
      expect(
        shouldShowWedgeCountBadge(
          personId: 'p1',
          viewerId: 'viewer',
          expandedRoots: const {},
          connectionCounts: const {'p1': 11},
        ),
        isTrue,
      );
    });

    test('the viewer never shows a badge (always expanded)', () {
      expect(
        shouldShowWedgeCountBadge(
          personId: 'viewer',
          viewerId: 'viewer',
          expandedRoots: const {},
          connectionCounts: const {'viewer': 40},
        ),
        isFalse,
      );
    });

    test('an EXPANDED person never shows a badge '
        '(their children are already on the canvas)', () {
      expect(
        shouldShowWedgeCountBadge(
          personId: 'p1',
          viewerId: 'viewer',
          expandedRoots: const {'p1'},
          connectionCounts: const {'p1': 11},
        ),
        isFalse,
      );
    });

    test('a person with zero connections shows no badge', () {
      expect(
        shouldShowWedgeCountBadge(
          personId: 'p1',
          viewerId: 'viewer',
          expandedRoots: const {},
          connectionCounts: const {'p1': 0},
        ),
        isFalse,
      );
      // Missing from the counts map entirely (isolated person).
      expect(
        shouldShowWedgeCountBadge(
          personId: 'p2',
          viewerId: 'viewer',
          expandedRoots: const {},
          connectionCounts: const {'p1': 3},
        ),
        isFalse,
      );
    });
  });
}
