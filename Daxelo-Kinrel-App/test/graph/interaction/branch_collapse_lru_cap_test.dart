// test/graph/interaction/branch_collapse_lru_cap_test.dart
//
// DAXELO KINREL — v5.171 ACCEPTANCE TEST
//
// v5.171: the LRU cap was DISABLED (set to 0). Branches now stay
// expanded until the user manually collapses them — no auto-collapse.
// These tests verify the disabled cap behavior.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/branch_collapse_state.dart';

void main() {
  group('v5.171 — BranchCollapseNotifier LRU cap (DISABLED)', () {
    test(
        'CRITERION 1: expanding more than 6 branches does NOT auto-collapse '
        'any branch (cap is disabled)',
        () {
      final notifier = BranchCollapseNotifier();

      // Expand 8 branches — with the cap disabled, ALL should stay.
      for (var i = 1; i <= 8; i++) {
        final conceal = notifier.expandBranch('root$i', revealedIds: {'r${i}_a'});
        expect(conceal, isEmpty,
            reason: 'No LRU eviction should happen — cap is disabled.');
      }
      expect(notifier.state.expandedBranchRoots.length, 8,
          reason: 'All 8 branches should remain expanded.');
      expect(notifier.state.expandedBranchRoots.contains('root1'), isTrue);
      expect(notifier.state.expandedBranchRoots.contains('root8'), isTrue);
    });

    test(
        'CRITERION 2: expanding the SAME branch twice does NOT trigger '
        'LRU eviction (it is already in the set)',
        () {
      final notifier = BranchCollapseNotifier();

      for (var i = 1; i <= 5; i++) {
        notifier.expandBranch('root$i', revealedIds: {'r${i}_a'});
      }
      expect(notifier.state.expandedBranchRoots.length, 5);

      // Expand root3 AGAIN — no-op for the set, no LRU eviction.
      final conceal = notifier.expandBranch('root3', revealedIds: {'r3_b'});
      expect(conceal, isEmpty);
      expect(notifier.state.expandedBranchRoots.length, 5);
    });

    test(
        'CRITERION 3: all branches remain expanded regardless of count',
        () {
      final notifier = BranchCollapseNotifier();

      // Expand 10 branches.
      for (var i = 1; i <= 10; i++) {
        notifier.expandBranch('root$i', revealedIds: {'r${i}_a'});
      }

      // All 10 should remain — no auto-collapse.
      expect(notifier.state.expandedBranchRoots.length, 10);
      for (var i = 1; i <= 10; i++) {
        expect(notifier.state.expandedBranchRoots.contains('root$i'), isTrue,
            reason: 'root$i should still be expanded.');
      }
    });
  });
}
