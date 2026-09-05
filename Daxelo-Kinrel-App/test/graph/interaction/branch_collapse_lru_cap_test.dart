// test/graph/interaction/branch_collapse_lru_cap_test.dart
//
// DAXELO KINREL — v5.161 ACCEPTANCE TEST
//
// Verifies the user's "auto-collapse stale expanded branches" fix:
//
//   "if more than a certain number of branches are expanded at once,
//    let older/less-recently-tapped branches auto-collapse (or prompt
//    the user), so the screen doesn't get crowded with dozens of open
//    branches at the same time."

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/branch_collapse_state.dart';

void main() {
  group('v5.161 — BranchCollapseNotifier LRU cap', () {
    test(
        'CRITERION 1: expanding more than kMaxSimultaneouslyExpandedBranches '
        'auto-collapses the OLDEST expanded branch (LRU eviction)',
        () {
      final notifier = BranchCollapseNotifier();

      // The cap is 6 (kMaxSimultaneouslyExpandedBranches). Expand 6
      // branches — all should be in expandedBranchRoots.
      for (var i = 1; i <= 6; i++) {
        final conceal = notifier.expandBranch('root$i', revealedIds: {'r${i}_a'});
        expect(conceal, isEmpty,
            reason: 'No LRU eviction should happen until the cap is exceeded.');
      }
      expect(notifier.state.expandedBranchRoots.length, 6);
      expect(notifier.state.expandedBranchRoots.contains('root1'), isTrue);
      expect(notifier.state.expandedBranchRoots.contains('root6'), isTrue);

      // Now expand a 7th — the OLDEST (root1) should be auto-collapsed.
      final concealSet = notifier.expandBranch('root7', revealedIds: {'r7_a'});

      // The conceal set should contain root1's revealed members.
      expect(concealSet, contains('r1_a'),
          reason: 'The oldest expanded branch (root1) must be auto-collapsed '
              'and its revealed members returned for concealment.');

      // root1 is gone, root7 is in.
      expect(notifier.state.expandedBranchRoots.contains('root1'), isFalse,
          reason: 'root1 (oldest) was auto-collapsed by LRU eviction.');
      expect(notifier.state.expandedBranchRoots.contains('root7'), isTrue,
          reason: 'root7 (newest) is in the expanded set.');
      expect(notifier.state.expandedBranchRoots.length, 6,
          reason: 'The expanded count must stay at the cap (6).');
    });

    test(
        'CRITERION 2: expanding the SAME branch twice does NOT trigger '
        'LRU eviction (it is already in the set)',
        () {
      final notifier = BranchCollapseNotifier();

      // Expand 5 branches (under the cap of 6).
      for (var i = 1; i <= 5; i++) {
        notifier.expandBranch('root$i', revealedIds: {'r${i}_a'});
      }
      expect(notifier.state.expandedBranchRoots.length, 5);

      // Expand root3 AGAIN — no-op for the set (already there),
      // no LRU eviction.
      final conceal = notifier.expandBranch('root3', revealedIds: {'r3_b'});
      expect(conceal, isEmpty,
          reason: 'Re-expanding an already-expanded branch must not trigger '
              'LRU eviction.');
      expect(notifier.state.expandedBranchRoots.length, 5,
          reason: 'Re-expanding does not grow the set.');
    });

    test(
        'CRITERION 3: the cap is enforced across multiple evictions — '
        'each new expansion evicts the next-oldest',
        () {
      final notifier = BranchCollapseNotifier();

      // Fill the cap.
      for (var i = 1; i <= 6; i++) {
        notifier.expandBranch('root$i', revealedIds: {'r${i}_a'});
      }

      // Expand root7 → evicts root1 (oldest).
      notifier.expandBranch('root7', revealedIds: {'r7_a'});
      expect(notifier.state.expandedBranchRoots.contains('root1'), isFalse);
      expect(notifier.state.expandedBranchRoots.contains('root7'), isTrue);

      // Expand root8 → evicts root2 (next oldest).
      notifier.expandBranch('root8', revealedIds: {'r8_a'});
      expect(notifier.state.expandedBranchRoots.contains('root2'), isFalse);
      expect(notifier.state.expandedBranchRoots.contains('root8'), isTrue);

      // Expand root9 → evicts root3 (next oldest).
      notifier.expandBranch('root9', revealedIds: {'r9_a'});
      expect(notifier.state.expandedBranchRoots.contains('root3'), isFalse);
      expect(notifier.state.expandedBranchRoots.contains('root9'), isTrue);

      // The count never exceeds 6.
      expect(notifier.state.expandedBranchRoots.length, 6);
    });

    test(
        'CRITERION 4: LRU eviction reveals the OLDEST expanded branch '
        'first (insertion-order semantics)',
        () {
      final notifier = BranchCollapseNotifier();

      // Expand 6 branches in order root1..root6. Insertion order is
      // root1, root2, ..., root6. root1 is the OLDEST.
      for (var i = 1; i <= 6; i++) {
        notifier.expandBranch('root$i', revealedIds: {'r${i}_a'});
      }

      // Expand root7 → root1 (oldest) is evicted.
      final conceal1 = notifier.expandBranch('root7', revealedIds: {'r7_a'});
      expect(conceal1, contains('r1_a'));

      // Expand root8 → root2 (next oldest) is evicted.
      final conceal2 = notifier.expandBranch('root8', revealedIds: {'r8_a'});
      expect(conceal2, contains('r2_a'),
          reason: 'LRU eviction must remove the OLDEST remaining branch, '
              'which is root2 after root1 was evicted.');
    });
  });
}
