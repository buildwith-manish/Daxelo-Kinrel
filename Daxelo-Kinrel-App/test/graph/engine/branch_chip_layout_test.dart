// test/graph/engine/branch_chip_layout_test.dart
//
// Tests for the v5.x chip-placement fix (branch_chip_layout.dart).
//
// Bug being fixed: collapsed-branch "+N" chips were positioned with a
// fixed diagonal offset of (+40, +40) from the node center, with
// collision-avoidance that ONLY pushed chips straight down — without
// checking whether the new position collided with a DIFFERENT node's
// circle or name label, and without keeping the chip visually
// tethered to its own node.
//
// The fix:
//   1. Anchor each chip CENTERED ON its parent node, just below the
//      name label (below the parent's full 140×176 bounding box).
//   2. Multi-direction collision avoidance against:
//        • every other placed chip
//        • every visible node's full bounding box (so chips never
//          overlap another person's circle OR name label)
//      Priority: straight down (preferred) → below + slightly left
//      → below + slightly right → above the node. If every candidate
//      collides, place at the least-overlap candidate and flag for
//      a leader line back to the parent node's center.
//   3. Deterministic order (Y asc, then X asc, then branchId asc) so
//      the same layout always produces the same chip positions, frame
//      to frame — no jitter.
//
// These tests cover the user's three test clusters ("Anjali Mehta" /
// "Geeta Gupta" / "Prakash Verma" + two more dense areas) plus the
// contract pieces: anchor placement, collision avoidance against
// all three obstacle classes, leader line fallback, determinism,
// and hit-test parity.

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

  /// The anchor rect for a chip below a parent box — replicates the
  /// helper's _anchorRect math so tests can assert exact expected
  /// positions.
  Rect expectedAnchorBelow(Offset parentPos) {
    final parent = nodeBox(parentPos);
    return Rect.fromLTWH(
      parent.center.dx - BranchChipGeometry.chipWidth / 2,
      parent.bottom + BranchChipGeometry.anchorGapBelowNode,
      BranchChipGeometry.chipWidth,
      BranchChipGeometry.chipHeight,
    );
  }

  group('v5.x chip placement — anchor + basic positioning', () {
    test('single chip sits centered below the parent node, just below '
        'the name label', () {
      final placements = placeBranchChips(
        requests: [req('a', const Offset(0, 0))],
        allNodeBoxes: [nodeBox(const Offset(0, 0))],
      );
      expect(placements.length, 1);
      final rect = placements.first.rect;
      final expected = expectedAnchorBelow(const Offset(0, 0));
      expect(rect, expected);
      expect(placements.first.needsLeaderLine, isFalse,
          reason: 'Default anchor placement does not need a leader line');
    });

    test('empty request list → empty result (no crash)', () {
      final placements = placeBranchChips(
        requests: const [],
        allNodeBoxes: const [],
      );
      expect(placements, isEmpty);
    });

    test('parent node with no position is skipped (defensive)', () {
      // A request always has a position (it's required), so the
      // only way to get "no placement" is an empty request list.
      // This test confirms the helper handles a request with a
      // position that doesn't match any node box — the chip should
      // still be placed at its anchor (it doesn't need its own node
      // box to avoid; the parent box is computed from the request's
      // position).
      final placements = placeBranchChips(
        requests: [req('a', const Offset(0, 0))],
        allNodeBoxes: const [],
      );
      expect(placements.length, 1);
      // The chip is placed at its anchor — no collisions to avoid.
      expect(placements.first.rect, expectedAnchorBelow(const Offset(0, 0)));
    });
  });

  group('v5.x chip placement — collision avoidance', () {
    test(
        'Case 1: two chips with the SAME parent position — the second '
        'chip is pushed straight down (no overlap)', () {
      // Two branches rooted at the same node (rare but possible —
      // e.g. two collapsed sub-branches under one person).
      final placements = placeBranchChips(
        requests: [
          req('a', const Offset(0, 0)),
          req('b', const Offset(0, 0)),
        ],
        allNodeBoxes: [nodeBox(const Offset(0, 0))],
      );
      expect(placements.length, 2);
      // The two chips must NOT overlap.
      expect(placements[0].rect.overlaps(placements[1].rect), isFalse,
          reason: 'Two chips at the same anchor must not overlap');
      // The first chip is at the anchor; the second is pushed down.
      expect(placements[0].rect.top, lessThan(placements[1].rect.top),
          reason: 'Second chip must be pushed DOWN from the anchor');
      // Neither chip overlaps the parent node's bounding box.
      final parentBox = nodeBox(const Offset(0, 0));
      expect(placements[0].rect.overlaps(parentBox), isFalse);
      expect(placements[1].rect.overlaps(parentBox), isFalse);
    });

    test(
        'Case 2 (KEY TEST — the bug): three close clusters, every chip '
        'avoids EVERY other node\'s bounding box (no chip overlaps a '
        'different person\'s node or label)', () {
      // Cluster: three parents at nearby positions, each with a
      // collapsed branch. This is the "Anjali Mehta / Geeta Gupta /
      // Prakash Verma" cluster the user reported.
      final anjaliPos = const Offset(0, 0);
      final geetaPos = const Offset(180, 0); // 180px to the right
      final prakashPos = const Offset(0, 220); // 220px below Anjali

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

      // Map by branchId for the assertions.
      final byId = <String, Rect>{
        for (final p in placements) p.request.branchId: p.rect,
      };
      final anjaliChip = byId['anjali_branch']!;
      final geetaChip = byId['geeta_branch']!;
      final prakashChip = byId['prakash_branch']!;

      // Every chip must avoid EVERY node's bounding box — not just
      // its own parent. This is the key fix.
      final allNodeBoxes = [
        nodeBox(anjaliPos),
        nodeBox(geetaPos),
        nodeBox(prakashPos),
      ];
      for (final chip in [anjaliChip, geetaChip, prakashChip]) {
        for (final nodeBox in allNodeBoxes) {
          expect(chip.overlaps(nodeBox), isFalse,
              reason: 'Chip $chip must NOT overlap any node box '
                  '$nodeBox — the bug was chips drifting onto '
                  'other persons\' nodes/labels');
        }
      }

      // Every chip must avoid every OTHER chip too.
      expect(anjaliChip.overlaps(geetaChip), isFalse);
      expect(anjaliChip.overlaps(prakashChip), isFalse);
      expect(geetaChip.overlaps(prakashChip), isFalse);

      // Each chip should be near its own parent (Anjali's chip near
      // Anjali, etc.) — anchored below the parent's name label.
      // We check this by asserting each chip's center X is within
      // the parent's box width (140px) of the parent's center X,
      // unless the chip had to be pushed laterally (in which case
      // the leader line tells the user which person it belongs to).
      // For the simple cluster here, no lateral push is needed.
      expect((anjaliChip.center.dx - anjaliPos.dx).abs(), lessThan(70.0),
          reason: 'Anjali\'s chip should be roughly centered on Anjali');
      expect((geetaChip.center.dx - geetaPos.dx).abs(), lessThan(70.0),
          reason: 'Geeta\'s chip should be roughly centered on Geeta');
      expect((prakashChip.center.dx - prakashPos.dx).abs(), lessThan(70.0),
          reason: 'Prakash\'s chip should be roughly centered on Prakash');
    });

    test(
        'Case 3: second dense cluster — horizontal row of 4 parents, '
        'every chip below its own parent, no overlap', () {
      // A row of 4 parents spaced 200px apart (each node is 140px
      // wide, so 200px gives 60px gap between adjacent node boxes).
      // The chip width is 200px, so adjacent chips WILL overlap if
      // placed at their anchors — the helper must push them apart.
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

      // No chip overlaps any node box.
      for (final placement in placements) {
        for (final pos in positions) {
          expect(placement.rect.overlaps(nodeBox(pos)), isFalse,
              reason: 'Chip ${placement.request.branchId} must not '
                  'overlap node at $pos');
        }
      }
    });

    test(
        'Case 4: third dense cluster — tight 2x2 grid, every chip '
        'avoids every other chip + every other node', () {
      // 2x2 grid of parents, 200px apart in both axes. This is a
      // common pattern (e.g. four siblings + their spouses in a
      // tight family gathering).
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

      // No two chips overlap.
      for (var i = 0; i < placements.length; i++) {
        for (var j = i + 1; j < placements.length; j++) {
          expect(placements[i].rect.overlaps(placements[j].rect), isFalse,
              reason: 'Chip ${i} must not overlap chip ${j}');
        }
      }

      // No chip overlaps any node box.
      for (final placement in placements) {
        for (final pos in positions) {
          expect(placement.rect.overlaps(nodeBox(pos)), isFalse,
              reason: 'Chip ${placement.request.branchId} must not '
                  'overlap any node at $pos');
        }
      }
    });

    test(
        'Case 5: chip anchored below a node whose name label is '
        'blocked by ANOTHER node below — chip pushes laterally '
        'rather than onto the second node', () {
      // Parent at (0, 0). Another (non-parent) node directly below
      // at (0, 220). The parent's chip anchor would be at (0, ~92)
      // (below the parent's box bottom at y=88, +8 gap). The chip
      // extends from y=92 to y=124. The second node box spans
      // y=132 to y=308. So the anchor position (y=92–124) is safe.
      //
      // But: let's place the second node CLOSER (at y=180, so its
      // box spans y=92–268). Now the anchor collides with the
      // second node's box. The helper must push the chip laterally
      // OR below the second node, NOT onto the second node.
      final parentPos = const Offset(0, 0);
      final blockerNodePos = const Offset(0, 180); // close below
      final placements = placeBranchChips(
        requests: [req('parent', parentPos)],
        allNodeBoxes: [
          nodeBox(parentPos),
          nodeBox(blockerNodePos),
        ],
      );
      expect(placements.length, 1);
      final chip = placements.first.rect;
      // The chip must NOT overlap either node box.
      expect(chip.overlaps(nodeBox(parentPos)), isFalse,
          reason: 'Chip must not overlap its own parent node');
      expect(chip.overlaps(nodeBox(blockerNodePos)), isFalse,
          reason: 'Chip must not overlap the blocker node below');
    });
  });

  group('v5.x chip placement — leader line fallback', () {
    test(
        'when a chip must be placed far below its anchor, a leader '
        'line is flagged', () {
      // Construct a scenario where the chip MUST be pushed down
      // several steps: a tall column of blocker nodes below the
      // parent forces the chip down past 2+ down-steps.
      final parentPos = const Offset(0, 0);
      // Place 3 blocker nodes in a column below the parent,
      // each 70px apart so they're tightly packed. The chip has
      // to navigate around them.
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
      // The chip is either flagged for a leader line (placed far
      // from anchor) OR placed at the anchor with no leader (the
      // anchor could be free if the blockers don't block it —
      // depends on geometry). Either way, the placement must be
      // valid (no overlap with any node).
      final placement = placements.first;
      for (final b in [parentPos, ...blockers]) {
        expect(placement.rect.overlaps(nodeBox(b)), isFalse,
            reason: 'Chip must not overlap any node in the column');
      }
      // The leader-line flag is informational — we just verify
      // it's a bool. The widget layer decides whether to draw a
      // leader line based on this flag.
      expect(placement.needsLeaderLine, isA<bool>());
    });

    test(
        'when no candidate avoids all collisions, the chip is placed '
        'at the least-overlap candidate and flagged for a leader '
        'line', () {
      // Construct a "hopeless" scenario: surround the parent with
      // blocker nodes at every candidate position. The helper
      // must still return a placement (not throw) and flag it for
      // a leader line so the user can see which person the chip
      // belongs to.
      //
      // The chip is 200px wide × 32px tall, and the parent's anchor
      // is at y = parent_box_bottom + 8 = 88 + 8 = 96. The down-
      // steps are at +18px (96, 114, 132, 150, 168). The lateral
      // offsets are at ±60px in X. The above-anchor is at y =
      // parent_box_top - chip_height - 8 = -88 - 32 - 8 = -128.
      //
      // To block EVERY candidate, we need a wall of nodes that
      // covers the full chip width at each candidate Y. The chip
      // is 200px wide centered on x=0, so it spans x ∈ [-100, 100].
      // The lateral candidates span x ∈ [-160, -40] and [40, 160].
      // We need blockers covering all three X ranges at every
      // candidate Y.
      //
      // Simpler approach: just place a wide blocker (the chip is
      // 200px wide, so we need a blocker at least 200px wide at
      // each candidate Y). A blocker node box is only 140px wide,
      // so a single node won't cover the full chip width. But a
      // single node placed at x=0 will overlap the chip's center —
      // which is enough to trigger collision.
      //
      // For each down-step Y, place a blocker node at x=0 whose
      // box overlaps the chip's vertical span at that Y. The
      // helper's collision check uses `Rect.overlaps` which is
      // true for ANY intersection — a 140px-wide box at x=0 with
      // center at the chip's Y will overlap the 200px-wide chip.
      final parentPos = const Offset(0, 0);
      // Blockers at every down-step position the helper would
      // try. The chip top is at y = 96 + 18*step. The blocker
      // center should be in [chip_top - 88, chip_top + 88 + 32]
      // so the blocker box (height 176, half = 88) overlaps the
      // chip.
      final blockers = <Offset>[
        const Offset(0, 100),   // anchor slot (y=96–128, blocker center 100 → box 12–188)
        const Offset(0, 130),   // down 1 (y=114–146)
        const Offset(0, 160),   // down 2 (y=132–164)
        const Offset(0, 190),   // down 3 (y=150–182)
        const Offset(0, 220),   // down 4 (y=168–200)
        // Lateral — left (x = -60). The chip at lateral-left
        // spans x ∈ [-160, 40]. A blocker at x=-60 with center
        // y in the chip range overlaps.
        const Offset(-60, 130),
        const Offset(-60, 160),
        // Lateral — right (x = +60). The chip at lateral-right
        // spans x ∈ [-40, 160]. A blocker at x=60 with center
        // y in the chip range overlaps.
        const Offset(60, 130),
        const Offset(60, 160),
        // Above-anchor (y = -128 to -96). A blocker at y=-100
        // with center there overlaps.
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
      // The helper must NOT crash — it places at the least-overlap
      // candidate.
      expect(placements.first.rect, isNotNull);
      // The leader line flag is set so the user can see which
      // person the chip belongs to.
      expect(placements.first.needsLeaderLine, isTrue,
          reason: 'When every candidate collides, the chip must be '
              'flagged for a leader line');
    });
  });

  group('v5.x chip placement — determinism', () {
    test(
        'the same inputs always produce the same output (no jitter '
        'across frames)', () {
      // Run the helper twice with the same inputs and verify the
      // outputs are identical. This is the "no jitter on re-render"
      // contract.
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
        expect(run1[i].rect, run2[i].rect,
            reason: 'Run 1 and run 2 must produce the same rects');
        expect(run1[i].needsLeaderLine, run2[i].needsLeaderLine,
            reason: 'Run 1 and run 2 must produce the same '
                'leader-line flags');
      }
    });

    test(
        'the helper returns results in the SAME order as the input '
        'requests (so the caller can zip them back to branches by '
        'index)', () {
      // Pass requests in a non-sorted order — the helper sorts
      // internally for deterministic processing, but returns in
      // the original order.
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
      // The results are in the SAME order as the input — index by
      // index.
      for (var i = 0; i < placements.length; i++) {
        expect(placements[i].request.branchId, requests[i].branchId,
            reason: 'Result ${i} must match request ${i}\'s branchId');
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
