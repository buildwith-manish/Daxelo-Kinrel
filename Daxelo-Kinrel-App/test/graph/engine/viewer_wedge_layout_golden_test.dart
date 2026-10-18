// test/graph/engine/viewer_wedge_layout_golden_test.dart
//
// Golden vectors produced by running the approved preview's layout math
// (see the chat). The viewer has 20 direct connections r0..r19 (ranked in
// that order); every other person has exactly 9 children named
// <parent>.0 .. <parent>.8. Page size is 8. Tolerance 0.5 world units.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/engine/viewer_wedge_layout.dart';

const _viewer = 'root';

class _Fixture {
  _Fixture() {
    final padded = (int i) => i.toString().padLeft(2, '0');
    for (var i = 0; i < 20; i++) {
      final id = 'r$i';
      ids.add(id);
      nameOf[id] = 'n${padded(i)}'; // keeps rank order == r0..r19
      links.add(WedgeLink(
        fromId: _viewer,
        toId: id,
        relationshipKey: 'sibling',
      ));
      for (var j = 0; j < 9; j++) {
        final child = '$id.$j';
        ids.add(child);
        nameOf[child] = 'c${padded(i)}${j}';
        links.add(WedgeLink(
          fromId: id,
          toId: child,
          relationshipKey: 'sibling',
        ));
      }
    }
    ids.add(_viewer);
    nameOf[_viewer] = 'Viewer';
  }

  final ids = <String>{};
  final nameOf = <String, String>{};
  final links = <WedgeLink>[];

  WedgeLayoutOutput compute({
    Set<String> expanded = const {},
    List<String> order = const [],
    Map<String, int> pages = const {},
    Set<String>? loaded,
    int budget = 150,
  }) {
    return ViewerWedgeLayout().compute(
      loadedPersonIds: loaded ?? ids,
      nameOf: nameOf,
      links: links,
      viewerId: _viewer,
      expandedPersonIds: expanded,
      manualPages: pages,
      expansionOrder: order,
      nodeBudget: budget,
    );
  }
}

void _expectAt(WedgeLayoutOutput out, String id, double x, double y) {
  final p = out.positions[id];
  expect(p, isNotNull, reason: 'missing position for $id');
  expect(p!.dx, closeTo(x, 0.5), reason: '$id x');
  expect(p.dy, closeTo(y, 0.5), reason: '$id y');
}

void _expectChip(WedgeLayoutOutput out, String owner, double x, double y,
    int remaining) {
  final chip = out.pageChips[owner];
  expect(chip, isNotNull, reason: 'missing chip for $owner');
  expect(chip!.slotCenter.dx, closeTo(x, 0.5), reason: '$owner chip x');
  expect(chip.slotCenter.dy, closeTo(y, 0.5), reason: '$owner chip y');
  expect(chip.remainingCount, remaining, reason: '$owner chip remaining');
}

/// Footprint overlap count using the same boxes as the engine
/// (node 124x128, viewer 124x140, chip 124x128, padding 6 per side).
int _overlaps(WedgeLayoutOutput out) {
  const pad = 6.0;
  final boxes = <List<double>>[];
  out.positions.forEach((id, p) {
    final h = id == _viewer ? 140.0 : 128.0;
    boxes.add([p.dx - 62 - pad, p.dy - h / 2 - pad, p.dx + 62 + pad,
      p.dy + h / 2 + pad]);
  });
  out.pageChips.forEach((_, c) {
    boxes.add([c.slotCenter.dx - 62 - pad, c.slotCenter.dy - 64 - pad,
      c.slotCenter.dx + 62 + pad, c.slotCenter.dy + 64 + pad]);
  });
  var n = 0;
  for (var i = 0; i < boxes.length; i++) {
    for (var j = i + 1; j < boxes.length; j++) {
      final a = boxes[i], b = boxes[j];
      if (a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3]) n++;
    }
  }
  return n;
}

void main() {
  group('ViewerWedgeLayout golden vectors (approved preview)', () {
    test('Case A: first view, viewer + 8 + one +12 chip', () {
      final out = _Fixture().compute();
      expect(out.positions.length, 9); // viewer + 8 people
      expect(out.pageChips.length, 1);
      _expectAt(out, 'root', 0, 0);
      _expectAt(out, 'r0', 98.0, -269.2);
      _expectAt(out, 'r1', 248.1, -143.2);
      _expectAt(out, 'r2', 282.1, 49.7);
      _expectAt(out, 'r3', 184.1, 219.5);
      _expectAt(out, 'r4', 0.0, 286.5);
      _expectAt(out, 'r5', -184.1, 219.5);
      _expectAt(out, 'r6', -282.1, 49.7);
      _expectAt(out, 'r7', -248.1, -143.2);
      _expectChip(out, 'root', -98.0, -269.2, 12);
      expect(_overlaps(out), 0);
    });

    test('Case B: r0 expanded -> radii 541.1 / 741.1, chip +1', () {
      final out = _Fixture().compute(expanded: {'r0'}, order: ['r0']);
      expect(out.positions.length, 17); // viewer + 8 + 8
      _expectAt(out, 'r0', 538.8, 49.9);
      _expectAt(out, 'r0.0', 136.2, -728.5);
      _expectAt(out, 'r0.1', 390.2, -630.1);
      _expectAt(out, 'r0.2', 591.4, -446.6);
      _expectAt(out, 'r0.3', 712.8, -202.8);
      _expectAt(out, 'r0.4', 738.0, 68.4);
      _expectAt(out, 'r0.5', 663.4, 330.3);
      _expectAt(out, 'r0.6', 499.3, 547.7);
      _expectAt(out, 'r0.7', 267.7, 691.1);
      _expectAt(out, 'r1', -195.5, 504.6);
      _expectAt(out, 'r2', -364.6, 399.9);
      _expectAt(out, 'r3', -484.4, 241.2);
      _expectAt(out, 'r4', -538.8, 49.9);
      _expectAt(out, 'r5', -520.5, -148.1);
      _expectAt(out, 'r6', -431.8, -326.1);
      _expectAt(out, 'r7', -284.9, -460.1);
      _expectChip(out, 'r0', 0.0, 741.1, 1);
      _expectChip(out, 'root', -99.4, -531.9, 12);
      expect(_overlaps(out), 0);
    });

    test('Case C: r0 and r4 expanded -> radii 795.8 / 995.8', () {
      final out = _Fixture()
          .compute(expanded: {'r0', 'r4'}, order: ['r0', 'r4']);
      expect(out.positions.length, 25);
      _expectAt(out, 'r0', 720.0, -338.8);
      _expectAt(out, 'r4', -671.9, 426.4);
      _expectAt(out, 'r4.0', 0.0, 995.8);
      _expectAt(out, 'r4.4', -840.8, 533.6);
      _expectChip(out, 'r4', -901.0, -424.0, 1);
      _expectChip(out, 'root', -99.7, -789.5, 12);
      expect(_overlaps(out), 0);
    });
  });

  group('behaviour', () {
    test('deterministic: same input gives the same output', () {
      final f = _Fixture();
      final a = f.compute(expanded: {'r0', 'r4'}, order: ['r0', 'r4']);
      final b = f.compute(expanded: {'r0', 'r4'}, order: ['r0', 'r4']);
      a.positions.forEach((id, p) => expect(b.positions[id], p));
    });

    test('collapse then re-expand restores identical positions', () {
      final f = _Fixture();
      final first = f.compute(expanded: {'r0'}, order: ['r0']);
      f.compute(); // collapsed
      final again = f.compute(expanded: {'r0'}, order: ['r0']);
      first.positions.forEach((id, p) => expect(again.positions[id], p));
    });

    test('paging is cumulative: +N adds people, nobody disappears', () {
      final f = _Fixture();
      final p0 = f.compute();
      final p1 = f.compute(pages: {'root': 1});
      expect(p1.positions.length, 17); // viewer + 16
      for (var i = 0; i < 8; i++) {
        expect(p1.positions.containsKey('r$i'), isTrue,
            reason: 'r$i must stay after +N');
      }
      expect(p1.pageChips['root']!.remainingCount, 4);
      expect(p0.pageChips['root']!.remainingCount, 12);
      final p2 = f.compute(pages: {'root': 2});
      expect(p2.positions.length, 21); // everyone, no chip
      expect(p2.pageChips.containsKey('root'), isFalse);
    });

    test('unloaded people are reported, never positioned', () {
      final f = _Fixture();
      final loaded = {...f.ids}..remove('r3');
      final out = f.compute(loaded: loaded);
      expect(out.positions.containsKey('r3'), isFalse);
      expect(out.pendingLoadIds['root'], contains('r3'));
      // "+N" still counts the person that is not shown yet.
      expect(out.pageChips['root']!.remainingCount, 13);
    });

    test('no overlaps while expanding everything up to the budget', () {
      final f = _Fixture();
      final expanded = <String>{};
      final order = <String>[];
      for (var i = 0; i < 20; i++) {
        expanded.add('r$i');
        order.add('r$i');
        final out = f.compute(expanded: expanded, order: order, budget: 150);
        expect(_overlaps(out), 0, reason: 'after expanding r$i');
        expect(out.positions.length <= 150, isTrue);
      }
    });
  });
}
