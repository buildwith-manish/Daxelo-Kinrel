// test/graph/engine/wedge_layout_golden_test.dart
//
// Golden test vectors for the ViewerWedgeLayout — verifies the layout
// produces the EXACT positions specified by the approved preview's
// layout math (ported to Dart). Tolerance: 0.5 units.
//
// Fixture: viewer has 20 direct connections (r0..r19). Every other
// person has exactly 9 children (parentid.0 .. parentid.8). Page size 8.
//
// Cases:
//   A — first view (viewer expanded only): 10 nodes, ring 1 = 286.5
//   B — also r0 expanded: 19 nodes, rings 541.1, 741.1
//   C — also r4 expanded: 28 nodes, rings 795.8, 995.8

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/engine/viewer_wedge_layout.dart';

const _tolerance = 0.5;

/// Build the fixture: viewer with 20 direct connections (r0..r19),
/// every other person with 9 children (parentid.0 .. parentid.8).
List<WedgeLink> _buildFixtureLinks() {
  final links = <WedgeLink>[];
  // Viewer → r0..r19
  for (var i = 0; i < 20; i++) {
    links.add(WedgeLink(
      fromId: 'viewer',
      toId: 'r$i',
      relationshipKey: 'parent',
      keyAtoB: 'son',
    ));
  }
  // Every person r0..r19 has 9 children: rN.0 .. rN.8
  for (var i = 0; i < 20; i++) {
    for (var j = 0; j < 9; j++) {
      links.add(WedgeLink(
        fromId: 'r$i',
        toId: 'r$i.$j',
        relationshipKey: 'parent',
        keyAtoB: 'son',
      ));
    }
  }
  // Every grandchild rN.M also has 9 children (so deeper expansions work)
  for (var i = 0; i < 20; i++) {
    for (var j = 0; j < 9; j++) {
      for (var k = 0; k < 9; k++) {
        links.add(WedgeLink(
          fromId: 'r$i.$j',
          toId: 'r$i.$j.$k',
          relationshipKey: 'parent',
          keyAtoB: 'son',
        ));
      }
    }
  }
  return links;
}

Map<String, String> _buildNames() {
  final names = <String, String>{'viewer': 'Viewer'};
  for (var i = 0; i < 20; i++) {
    names['r$i'] = 'R$i';
    for (var j = 0; j < 9; j++) {
      names['r$i.$j'] = 'R$i.$j';
      for (var k = 0; k < 9; k++) {
        names['r$i.$j.$k'] = 'R$i.$j.$k';
      }
    }
  }
  return names;
}

Set<String> _allPersonIds() {
  final ids = <String>{'viewer'};
  for (var i = 0; i < 20; i++) {
    ids.add('r$i');
    for (var j = 0; j < 9; j++) {
      ids.add('r$i.$j');
      for (var k = 0; k < 9; k++) {
        ids.add('r$i.$j.$k');
      }
    }
  }
  return ids;
}

void main() {
  final links = _buildFixtureLinks();
  final names = _buildNames();
  final allIds = _allPersonIds();

  group('Golden test vectors (approved preview layout math)', () {
    test('Case A: first view (viewer expanded only) — 10 nodes, ring 1 = 286.5', () {
      final output = ViewerWedgeLayout().compute(
        loadedPersonIds: allIds,
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: {'viewer'},
        manualPages: const {},
        expansionOrder: const [],
      );

      // 10 positioned items: viewer + r0..r7 + root chip = 10.
      // (positions map has 9 entries — viewer + r0..r7. The chip is
      // in pageChips, not positions. So positions.length == 9 and
      // pageChips.length == 1, total = 10.)
      expect(output.positions.length, equals(9),
          reason: 'viewer + r0..r7 = 9 positioned persons');
      expect(output.pageChips.length, equals(1),
          reason: 'one +N chip for the root');
      expect(output.pageChips['viewer']!.remainingCount, equals(12),
          reason: 'root chip shows +12 (20 - 8 = 12)');

      // Ring 1 radius: the first non-zero position's distance from origin.
      final r0Pos = output.positions['r0']!;
      final r0Radius = r0Pos.distance;
      expect(r0Radius, closeTo(286.5, _tolerance),
          reason: 'Ring 1 radius must be 286.5 (was ${r0Radius.toStringAsFixed(1)})');

      // Verify exact positions.
      expect(output.positions['viewer']!, equals(const Offset(0, 0)));
      _expectPos(output.positions, 'r0', 98.0, -269.2);
      _expectPos(output.positions, 'r1', 248.1, -143.2);
      _expectPos(output.positions, 'r2', 282.1, 49.7);
      _expectPos(output.positions, 'r3', 184.1, 219.5);
      _expectPos(output.positions, 'r4', 0.0, 286.5);
      _expectPos(output.positions, 'r5', -184.1, 219.5);
      _expectPos(output.positions, 'r6', -282.1, 49.7);
      _expectPos(output.positions, 'r7', -248.1, -143.2);

      // Root chip position.
      final chip = output.pageChips['viewer']!;
      expect(chip.slotCenter.dx, closeTo(-98.0, _tolerance));
      expect(chip.slotCenter.dy, closeTo(-269.2, _tolerance));

      // Zero overlaps.
      expect(_countOverlaps(output), equals(0));
    });

    test('Case B: also r0 expanded — 19 nodes, rings 541.1, 741.1', () {
      final output = ViewerWedgeLayout().compute(
        loadedPersonIds: allIds,
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: {'viewer', 'r0'},
        manualPages: const {},
        expansionOrder: const ['r0'],
      );

      // 19 positioned items: viewer + r0..r7 + r0.0..r0.7 = 17 persons
      // + 2 chips (root chip +12, r0 chip +1) = 19 total.
      expect(output.positions.length, equals(17),
          reason: 'viewer + r0..r7 + r0.0..r0.7 = 17 persons');
      expect(output.pageChips.length, equals(2),
          reason: 'root chip (+12) + r0 chip (+1)');
      expect(output.pageChips['viewer']!.remainingCount, equals(12));
      expect(output.pageChips['r0']!.remainingCount, equals(1));

      // Ring radii.
      final r0Pos = output.positions['r0']!;
      expect(r0Pos.distance, closeTo(541.1, _tolerance),
          reason: 'Ring 2 (r0) radius must be 541.1');

      // r0.0 is at ring 3.
      final r00Pos = output.positions['r0.0']!;
      expect(r00Pos.distance, closeTo(741.1, _tolerance),
          reason: 'Ring 3 (r0.0) radius must be 741.1');

      // Verify key positions.
      expect(output.positions['viewer']!, equals(const Offset(0, 0)));
      _expectPos(output.positions, 'r0', 538.8, 49.9);
      _expectPos(output.positions, 'r0.0', 136.2, -728.5);
      _expectPos(output.positions, 'r0.1', 390.2, -630.1);
      _expectPos(output.positions, 'r0.2', 591.4, -446.6);
      _expectPos(output.positions, 'r0.3', 712.8, -202.8);
      _expectPos(output.positions, 'r0.4', 738.0, 68.4);
      _expectPos(output.positions, 'r0.5', 663.4, 330.3);
      _expectPos(output.positions, 'r0.6', 499.3, 547.7);
      _expectPos(output.positions, 'r0.7', 267.7, 691.1);
      _expectPos(output.positions, 'r1', -195.5, 504.6);
      _expectPos(output.positions, 'r2', -364.6, 399.9);
      _expectPos(output.positions, 'r3', -484.4, 241.2);
      _expectPos(output.positions, 'r4', -538.8, 49.9);
      _expectPos(output.positions, 'r5', -520.5, -148.1);
      _expectPos(output.positions, 'r6', -431.8, -326.1);
      _expectPos(output.positions, 'r7', -284.9, -460.1);

      // r0 chip.
      final r0Chip = output.pageChips['r0']!;
      expect(r0Chip.slotCenter.dx, closeTo(0.0, _tolerance));
      expect(r0Chip.slotCenter.dy, closeTo(741.1, _tolerance));

      // Root chip.
      final rootChip = output.pageChips['viewer']!;
      expect(rootChip.slotCenter.dx, closeTo(-99.4, _tolerance));
      expect(rootChip.slotCenter.dy, closeTo(-531.9, _tolerance));

      // Zero overlaps.
      expect(_countOverlaps(output), equals(0));
    });

    test('Case C: also r4 expanded — 28 nodes, rings 795.8, 995.8', () {
      final output = ViewerWedgeLayout().compute(
        loadedPersonIds: allIds,
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: {'viewer', 'r0', 'r4'},
        manualPages: const {},
        expansionOrder: const ['r0', 'r4'],
      );

      // 28 items: viewer + r0..r7 (8) + r0.0..r0.7 (8) + r4.0..r4.7 (8)
      // = 25 persons + 3 chips (root, r0, r4) = 28.
      expect(output.positions.length, equals(25),
          reason: 'viewer + 8 + 8 + 8 = 25 persons');
      expect(output.pageChips.length, equals(3),
          reason: 'root + r0 + r4 chips');

      // Ring radii: r0 is at ring 2, r4 is at ring 2, their children at ring 3/4.
      final r0Pos = output.positions['r0']!;
      expect(r0Pos.distance, closeTo(795.8, _tolerance),
          reason: 'Ring 2 (r0) radius must be 795.8');

      final r4Pos = output.positions['r4']!;
      expect(r4Pos.distance, closeTo(795.8, _tolerance),
          reason: 'Ring 2 (r4) radius must be 795.8');

      // r4.0 at ring 3.
      final r40Pos = output.positions['r4.0']!;
      expect(r40Pos.distance, closeTo(995.8, _tolerance),
          reason: 'Ring 3 (r4.0) radius must be 995.8');

      // Spot-check key positions.
      _expectPos(output.positions, 'r0', 720.0, -338.8);
      _expectPos(output.positions, 'r4', -671.9, 426.4);
      _expectPos(output.positions, 'r4.0', 0.0, 995.8);
      _expectPos(output.positions, 'r4.4', -840.8, 533.6);

      // Chips.
      final r4Chip = output.pageChips['r4']!;
      expect(r4Chip.slotCenter.dx, closeTo(-901.0, _tolerance));
      expect(r4Chip.slotCenter.dy, closeTo(-424.0, _tolerance));

      final rootChip = output.pageChips['viewer']!;
      expect(rootChip.slotCenter.dx, closeTo(-99.7, _tolerance));
      expect(rootChip.slotCenter.dy, closeTo(-789.5, _tolerance));

      // Zero overlaps.
      expect(_countOverlaps(output), equals(0));
    });

    test('Determinism: same input → same output', () {
      final a = ViewerWedgeLayout().compute(
        loadedPersonIds: allIds,
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: {'viewer'},
        manualPages: const {},
        expansionOrder: const [],
      );
      final b = ViewerWedgeLayout().compute(
        loadedPersonIds: allIds,
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: {'viewer'},
        manualPages: const {},
        expansionOrder: const [],
      );
      expect(a.positions, equals(b.positions));
    });

    test('Collapse then re-expand restores identical positions', () {
      final expanded = ViewerWedgeLayout().compute(
        loadedPersonIds: allIds,
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: {'viewer', 'r0'},
        manualPages: const {},
        expansionOrder: const ['r0'],
      );
      final collapsed = ViewerWedgeLayout().compute(
        loadedPersonIds: allIds,
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: {'viewer'},
        manualPages: const {},
        expansionOrder: const [],
      );
      final reExpanded = ViewerWedgeLayout().compute(
        loadedPersonIds: allIds,
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: {'viewer', 'r0'},
        manualPages: const {},
        expansionOrder: const ['r0'],
      );
      // The positions that exist in both expanded states must match.
      for (final id in expanded.positions.keys) {
        if (reExpanded.positions.containsKey(id)) {
          expect(reExpanded.positions[id], equals(expanded.positions[id]),
              reason: 'Position of $id must be identical after collapse+re-expand');
        }
      }
    });

    test('Parents on shortest paths from viewer', () {
      final output = ViewerWedgeLayout().compute(
        loadedPersonIds: allIds,
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: {'viewer', 'r0'},
        manualPages: const {},
        expansionOrder: const ['r0'],
      );
      // r0's parent must be viewer.
      expect(output.parentOf['r0'], equals('viewer'));
      // r0.0's parent must be r0.
      expect(output.parentOf['r0.0'], equals('r0'));
      // r0.0's depth must be 2 (viewer=0, r0=1, r0.0=2).
      expect(output.depthById['r0.0'], equals(2));
    });
  });
}

void _expectPos(Map<String, Offset> positions, String id, double x, double y) {
  final pos = positions[id];
  expect(pos, isNotNull, reason: 'Position for $id must exist');
  expect(pos!.dx, closeTo(x, _tolerance),
      reason: '$id x: expected $x, got ${pos.dx.toStringAsFixed(1)}');
  expect(pos.dy, closeTo(y, _tolerance),
      reason: '$id y: expected $y, got ${pos.dy.toStringAsFixed(1)}');
}

int _countOverlaps(WedgeLayoutOutput output) {
  const config = WedgeLayoutConfig();
  final boxes = <_Box>[];
  output.positions.forEach((id, pos) {
    final isViewer = id == 'viewer';
    final size = isViewer ? config.rootFootprint : config.nodeFootprint;
    final pad = config.footprintPadding;
    boxes.add(_Box(
      pos.dx - size.width / 2 - pad,
      pos.dy - size.height / 2 - pad,
      pos.dx + size.width / 2 + pad,
      pos.dy + size.height / 2 + pad,
    ));
  });
  output.pageChips.forEach((_, chip) {
    final size = config.chipFootprint;
    final pad = config.footprintPadding;
    boxes.add(_Box(
      chip.slotCenter.dx - size.width / 2 - pad,
      chip.slotCenter.dy - size.height / 2 - pad,
      chip.slotCenter.dx + size.width / 2 + pad,
      chip.slotCenter.dy + size.height / 2 + pad,
    ));
  });
  var count = 0;
  for (var i = 0; i < boxes.length; i++) {
    for (var j = i + 1; j < boxes.length; j++) {
      if (boxes[i].overlaps(boxes[j])) count++;
    }
  }
  return count;
}

class _Box {
  const _Box(this.minX, this.minY, this.maxX, this.maxY);
  final double minX, minY, maxX, maxY;
  bool overlaps(_Box o) =>
      minX < o.maxX && o.minX < maxX && minY < o.maxY && o.minY < maxY;
}
