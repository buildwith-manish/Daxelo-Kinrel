// test/graph/engine/branch_chip_layout_test.dart
//
// Tests for the v5.x chip-placement fix (branch_chip_layout.dart),
// UPDATED for the BUG-1 fix (remove floating leader line).
//
// Bug being fixed (original): collapsed-branch "+N" chips were
// positioned with a fixed diagonal offset (+40, +40) from the node
// center, with collision-avoidance that ONLY pushed chips straight
// down — without checking whether the new position collided with a
// DIFFERENT node's circle or name label.
//
// Bug being fixed (BUG-1, this iteration): the previous fix added a
// leader line drawn from the chip back to the parent node when the
// chip had to be placed far away. The user reported this looked like
// "a floating single-line-plus-badge in empty space that doesn't
// clearly connect to anything meaningful." The leader line has been
// REMOVED — the chip is now ALWAYS attached to (overlapping) its
// parent node's bottom edge. No leader line is ever drawn.
//
// The fix:
//   1. The chip's vertical center sits at the parent node's bottom
//      edge — half the chip overlaps the parent's bottom half (the
//      name label area, fine since the chip is a compact badge),
//      half is below. The chip reads as a label ATTACHED to the
//      node, not a disconnected floating element.
//   2. The chip is ALLOWED to overlap its OWN parent (the parent
//      overlap is intentional — the chip is attached to the parent).
//      It must still avoid OTHER nodes and OTHER chips.
//   3. `needsLeaderLine` is now ALWAYS false. The field is kept for
//      API compatibility with existing callers/tests but is unused.
//   4. Multi-direction collision avoidance against OTHER nodes +
//      other placed chips. Priority: attached anchor (preferred),
//      straight down, below + slightly left, below + slightly right,
//      above the node.
//   5. Deterministic order (Y asc, then X asc, then branchId asc).

import 'package:flutter/material.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/engine/branch_chip_layout.dart';

void main() {
  // ── Helpers ────────────────────────────────────────────────────────

  /// Build a request with a stable branchId.
  BranchChipPlacementRequest req(String id, Offset pos) =>
      BranchChipPlacementRequest(
        branchId: '${id}_branch',
        rootPersonId: id,
        rootPosition: pos,
      );

  /// The full node-box rect for a position — matches the helper's
  /// 140×176 box centered on the node.
  Rect nodeBox(Offset pos) => nodeBoxForPosition(pos);

  /// The anchor rect for a chip ATTACHED to a parent box — the chip's
  /// vertical center sits at the parent's bottom edge (was: just below
  /// it). Half the chip overlaps the parent's bottom half, half is
  /// below.
  ///
  /// v5.x (BUG-1 fix): the anchor's vertical center is now AT the
  /// parent's bottom edge (was: just below it + 8px gap).
  Rect expectedAnchorBelow(Offset parentPos) {
    final parent = nodeBox(parentPos);
    return Rect.fromLTWH(
      parent.center.dx - BranchChipGeometry.chipWidth / 2,
      parent.bottom - BranchChipGeometry.chipHeight / 2,
      BranchChipGeometry.chipWidth,
      BranchChipGeometry.chipHeight,
    );
  }

  group('v5.x chip placement — anchor + basic positioning', () {
    test('single chip is ATTACHED to the parent node (vertical center '
        'at the parent\'s bottom edge — no floating gap, no leader '
        'line)', () {
      final placements = placeBranchChips(
        requests: [req('a', const Offset(0, 0))],
        allNodeBoxes: [nodeBox(const Offset(0, 0))],
      );
      expect(placements.length, 1);
      final rect = placements.first.rect;
      final expected = expectedAnchorBelow(const Offset(0, 0));
      expect(rect, expected);
      expect(placements.first.needsLeaderLine, isFalse,
          reason: 'v5.x (BUG-1 fix): needsLeaderLine is now ALWAYS '
              'false — no leader line is ever drawn. The chip is '
              'attached to its parent, no visual tether needed.');
    });

    test('empty request list → empty result (no crash)', () {
      final placements = placeBranchChips(
        requests: const [],
        allNodeBoxes: const [],
      );
      expect(placements, isEmpty);
    });

    test('parent node with no position is skipped (defensive)', () {
      final placements = placeBranchChips(
        requests: [req('a', const Offset(0, 0))],
        allNodeBoxes: const [],
      );
      expect(placements.length, 1);
      expect(placements.first.rect, expectedAnchorBelow(const Offset(0, 0)));
    });

    test('v5.x (BUG-1 fix): chip is ALLOWED to overlap its own parent '
        'node — that\'s the point of attachment', () {
      final placements = placeBranchChips(
        requests: [req('a', const Offset(0, 0))],
        allNodeBoxes: [nodeBox(const Offset(0, 0))],
      );
      expect(placements.length, 1);
      final chip = placements.first.rect;
      final parentBox = nodeBox(const Offset(0, 0));
      expect(chip.overlaps(parentBox), isTrue,
          reason: 'v5.x (BUG-1 fix): the chip is ATTACHED to its '
              'parent — it intentionally overlaps the parent\'s '
              'bottom half. The previous version required no overlap '
              'with any node box (including the parent); the new '
              'version allows the parent overlap (the chip is a '
              'label attached to the node, like a sticky note).');
    });
  });

  group('v5.x chip placement — collision avoidance', () {
    test(
        'Case 1: two chips with the SAME parent position — the second '
        'chip is pushed straight down (no overlap with the first chip)',
        () {
      final placements = placeBranchChips(
        requests: [
          req('a', const Offset(0, 0)),
          req('b', const Offset(0, 0)),
        ],
        allNodeBoxes: [nodeBox(const Offset(0, 0))],
      );
      expect(placements.length, 2);
      expect(placements[0].rect.overlaps(placements[1].rect), isFalse,
          reason: 'Two chips at the same anchor must not overlap each '
              'other');
      expect(placements[0].rect.top, lessThan(placements[1].rect.top),
          reason: 'Second chip must be pushed DOWN from the anchor');
      // v5.x (BUG-1 fix): needsLeaderLine always false.
      expect(placements[0].needsLeaderLine, isFalse);
      expect(placements[1].needsLeaderLine, isFalse);
    });

    test(
        'Case 2 (KEY TEST — the bug): three close clusters, every chip '
        'avoids EVERY OTHER node\'s bounding box (chips may overlap '
        'their OWN parent — that\'s the attachment — but must not '
        'overlap a DIFFERENT person\'s node or label)', () {
      final anjaliPos = const Offset(0, 0);
      final geetaPos = const Offset(180, 0);
      final prakashPos = const Offset(0, 220);

      final placements = placeBranchChips(
        requests: [
          req('anjali', anjaliPos),
          req('geeta', geetaPos),
          req('prakash', prakashPos),
        ],
        allNodeBoxes: [
          nodeBox(anjaliPos),
          nodeBox(geetaPos),
          nodeBox(prakashPos),
        ],
      );
      expect(placements.length, 3);

      final byId = <String, Rect>{
        for (final p in placements) p.request.branchId: p.rect,
      };
      final anjaliChip = byId['anjali_branch']!;
      final geetaChip = byId['geeta_branch']!;
      final prakashChip = byId['prakash_branch']!;

      final anjaliBox = nodeBox(anjaliPos);
      final geetaBox = nodeBox(geetaPos);
      final prakashBox = nodeBox(prakashPos);

      // v5.x (BUG-1 fix): chips are ALLOWED to overlap their OWN parent.
      // They must NOT overlap any OTHER parent's node box.
      expect(anjaliChip.overlaps(geetaBox), isFalse);
      expect(anjaliChip.overlaps(prakashBox), isFalse);
      expect(geetaChip.overlaps(anjaliBox), isFalse);
      expect(geetaChip.overlaps(prakashBox), isFalse);
      expect(prakashChip.overlaps(anjaliBox), isFalse);
      expect(prakashChip.overlaps(geetaBox), isFalse);

      // Every chip must avoid every OTHER chip too.
      expect(anjaliChip.overlaps(geetaChip), isFalse);
      expect(anjaliChip.overlaps(prakashChip), isFalse);
      expect(geetaChip.overlaps(prakashChip), isFalse);

      // Each chip should be near its own parent.
      expect((anjaliChip.center.dx - anjaliPos.dx).abs(), lessThan(70.0));
      expect((geetaChip.center.dx - geetaPos.dx).abs(), lessThan(70.0));
      expect((prakashChip.center.dx - prakashPos.dx).abs(), lessThan(70.0));

      // v5.x (BUG-1 fix): needsLeaderLine always false.
      for (final p in placements) {
        expect(p.needsLeaderLine, isFalse);
      }
    });

    test(
        'Case 3: horizontal row of 4 parents — every chip avoids every '
        'OTHER chip + every OTHER node', () {
      final positions = [
        const Offset(0, 0),
        const Offset(200, 0),
        const Offset(400, 0),
        const Offset(600, 0),
      ];
      final placements = placeBranchChips(
        requests: [
          req('p1', positions[0]),
          req('p2', positions[1]),
          req('p3', positions[2]),
          req('p4', positions[3]),
        ],
        allNodeBoxes: [for (final p in positions) nodeBox(p)],
      );
      expect(placements.length, 4);

      // No two chips overlap.
      for (var i = 0; i < placements.length; i++) {
        for (var j = i + 1; j < placements.length; j++) {
          expect(placements[i].rect.overlaps(placements[j].rect), isFalse,
              reason: 'Chip ${i} must not overlap chip ${j}');
        }
      }

      // No chip overlaps any OTHER node box (own parent overlap
      // allowed).
      for (final placement in placements) {
        final ownPos = placement.request.rootPosition;
        for (final pos in positions) {
          if (pos == ownPos) continue;
          expect(placement.rect.overlaps(nodeBox(pos)), isFalse,
              reason: 'Chip ${placement.request.branchId} must not '
                  'overlap OTHER node at $pos (own-parent overlap '
                  'at $ownPos is allowed)');
        }
      }
    });

    test(
        'Case 4: tight 2x2 grid — every chip avoids every OTHER chip '
        '+ every OTHER node', () {
      final positions = [
        const Offset(0, 0),
        const Offset(200, 0),
        const Offset(0, 200),
        const Offset(200, 200),
      ];
      final placements = placeBranchChips(
        requests: [
          req('a', positions[0]),
          req('b', positions[1]),
          req('c', positions[2]),
          req('d', positions[3]),
        ],
        allNodeBoxes: [for (final p in positions) nodeBox(p)],
      );
      expect(placements.length, 4);

      for (var i = 0; i < placements.length; i++) {
        for (var j = i + 1; j < placements.length; j++) {
          expect(placements[i].rect.overlaps(placements[j].rect), isFalse,
              reason: 'Chip ${i} must not overlap chip ${j}');
        }
      }

      for (final placement in placements) {
        final ownPos = placement.request.rootPosition;
        for (final pos in positions) {
          if (pos == ownPos) continue;
          expect(placement.rect.overlaps(nodeBox(pos)), isFalse,
              reason: 'Chip ${placement.request.branchId} must not '
                  'overlap OTHER node at $pos');
        }
      }
    });

    test(
        'Case 5: chip attached to a parent whose name label is blocked '
        'by ANOTHER node below — chip pushes laterally rather than '
        'onto the second node', () {
      final parentPos = const Offset(0, 0);
      final blockerNodePos = const Offset(0, 180);
      final placements = placeBranchChips(
        requests: [req('parent', parentPos)],
        allNodeBoxes: [
          nodeBox(parentPos),
          nodeBox(blockerNodePos),
        ],
      );
      expect(placements.length, 1);
      final chip = placements.first.rect;
      // The chip MUST NOT overlap the blocker node.
      expect(chip.overlaps(nodeBox(blockerNodePos)), isFalse,
          reason: 'Chip must not overlap the blocker node below '
              '(different person). The chip may overlap its OWN '
              'parent — that\'s the attachment — but must avoid '
              'OTHER persons\' nodes.');
    });
  });

  group('v5.x chip placement — BUG-1 fix (no leader line)', () {
    test(
        'needsLeaderLine is ALWAYS false — even when the chip must be '
        'pushed far down for collision avoidance', () {
      final parentPos = const Offset(0, 0);
      final blockers = [
        const Offset(0, 100),
        const Offset(0, 170),
        const Offset(0, 240),
      ];
      final placements = placeBranchChips(
        requests: [req('parent', parentPos)],
        allNodeBoxes: [
          nodeBox(parentPos),
          for (final b in blockers) nodeBox(b),
        ],
      );
      expect(placements.length, 1);
      final placement = placements.first;
      expect(placement.needsLeaderLine, isFalse,
          reason: 'v5.x (BUG-1 fix): needsLeaderLine is always false.');
      // The chip must not overlap any OTHER (non-parent) node box.
      for (final b in blockers) {
        expect(placement.rect.overlaps(nodeBox(b)), isFalse,
            reason: 'Chip must not overlap blocker node at $b');
      }
    });

    test(
        'when no candidate avoids all collisions, the chip is placed '
        'at the least-overlap candidate (and needsLeaderLine is still '
        'false)', () {
      final parentPos = const Offset(0, 0);
      final blockers = <Offset>[
        const Offset(0, 100),
        const Offset(0, 130),
        const Offset(0, 160),
        const Offset(0, 190),
        const Offset(0, 220),
        const Offset(-60, 130),
        const Offset(-60, 160),
        const Offset(60, 130),
        const Offset(60, 160),
        const Offset(0, -100),
      ];
      final placements = placeBranchChips(
        requests: [req('parent', parentPos)],
        allNodeBoxes: [
          nodeBox(parentPos),
          for (final b in blockers) nodeBox(b),
        ],
      );
      expect(placements.length, 1);
      expect(placements.first.rect, isNotNull);
      expect(placements.first.needsLeaderLine, isFalse,
          reason: 'v5.x (BUG-1 fix): needsLeaderLine is always false, '
              'even in the hopeless-collision case.');
    });
  });

  group('v5.x chip placement — determinism', () {
    test(
        'the same inputs always produce the same output (no jitter '
        'across frames)', () {
      final requests = [
        req('a', const Offset(0, 0)),
        req('b', const Offset(200, 0)),
        req('c', const Offset(0, 220)),
      ];
      final allNodeBoxes = [
        nodeBox(const Offset(0, 0)),
        nodeBox(const Offset(200, 0)),
        nodeBox(const Offset(0, 220)),
      ];
      final run1 = placeBranchChips(
          requests: requests, allNodeBoxes: allNodeBoxes);
      final run2 = placeBranchChips(
          requests: requests, allNodeBoxes: allNodeBoxes);
      expect(run1.length, run2.length);
      for (var i = 0; i < run1.length; i++) {
        expect(run1[i].rect, run2[i].rect);
        expect(run1[i].needsLeaderLine, run2[i].needsLeaderLine);
      }
    });

    test(
        'the helper returns results in the SAME order as the input '
        'requests', () {
      final requests = [
        req('c', const Offset(0, 220)),
        req('a', const Offset(0, 0)),
        req('b', const Offset(200, 0)),
      ];
      final allNodeBoxes = [
        nodeBox(const Offset(0, 0)),
        nodeBox(const Offset(200, 0)),
        nodeBox(const Offset(0, 220)),
      ];
      final placements = placeBranchChips(
          requests: requests, allNodeBoxes: allNodeBoxes);
      expect(placements.length, requests.length);
      for (var i = 0; i < placements.length; i++) {
        expect(placements[i].request.branchId, requests[i].branchId);
      }
    });
  });

  group('v5.x chip placement — nodeBoxForPosition helper', () {
    test('nodeBoxForPosition returns a 140×176 rect centered on the '
        'position', () {
      final box = nodeBoxForPosition(const Offset(100, 200));
      expect(box.width, BranchChipGeometry.nodeBoxSize.width);
      expect(box.height, BranchChipGeometry.nodeBoxSize.height);
      expect(box.center, const Offset(100, 200));
    });
  });
}
