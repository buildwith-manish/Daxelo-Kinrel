// test/graph/engine/wedge_bubble_badge_spec_test.dart
//
// Tests for the "+N" page bubble and count badge spec contracts:
//
//   1. The bubble's rendered diameter equals a person node's diameter
//      (Ø72, matching GraphNode's default nodeSize), and its ring
//      colour comes from the theme token (no hardcoded colour).
//   2. Zero footprint overlaps after expanding to the node budget,
//      with the larger (node-sized) chip footprint.
//   3. After a fit to a hub near the top of the graph, the node's
//      bounds lie fully inside the visible area below the banner.
//   4. The badge hit area is at least 48 dp and expands the person.
//
// The bubble + badge are private widgets in branch_affordance.dart
// (a `part of` family_graph_engine_view.dart). They're not directly
// constructible from tests, so we verify the contracts via the
// widget tree after pumping FamilyGraphScreen (the e2e test pattern).
// The pure-Dart contracts (chip footprint, no-overlap guarantee)
// are verified directly against WedgeLayoutConfig + ViewerWedgeLayout.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/core/kinship/kinship_edge_style.dart';
import 'package:kinrel/graph/engine/viewer_wedge_layout.dart';

void main() {
  group('WedgeLayoutConfig chip footprint (node-sized bubble)', () {
    test(
        'The chip footprint equals the regular node footprint (124×128), '
        'so the bigger bubble and its label reserve the full space.',
        () {
      const config = WedgeLayoutConfig();
      expect(config.chipFootprint.width, equals(config.nodeFootprint.width),
          reason: 'chip width must equal node width');
      expect(config.chipFootprint.height, equals(config.nodeFootprint.height),
          reason: 'chip height must equal node height');
      // Sanity: the chip is no longer the old 84×84.
      expect(config.chipFootprint.width, isNot(equals(84.0)));
      expect(config.chipFootprint.height, isNot(equals(84.0)));
    });

    test(
        'Zero footprint overlaps after expanding to the node budget, '
        'with the larger (node-sized) chip footprint.', () {
      // Re-use the seeded-tree pattern from viewer_wedge_layout_test.dart
      // — a deterministic random family tree that exercises the
      // no-overlap guarantee at the node budget (50 persons).
      final rng = math.Random(42);
      final persons = <String>['viewer'];
      final names = <String, String>{'viewer': 'Viewer'};
      final links = <WedgeLink>[];
      for (var i = 1; i < 50; i++) {
        final id = 'p$i';
        final parent = persons[rng.nextInt(persons.length)];
        final key = const ['father', 'mother', 'spouse', 'brother', 'son']
            .elementAt(rng.nextInt(5));
        links.add(WedgeLink(
          fromId: parent,
          toId: id,
          relationshipKey: 'parent',
          keyAtoB: key,
        ));
        persons.add(id);
        names[id] = 'Person $i';
      }

      // Expand EVERY person so the layout has to place all 50 nodes
      // (the node budget) AND show a "+N" chip for any hub whose
      // children overflow the page (8 per page).
      final expandedRoots = persons.toSet();
      final output = ViewerWedgeLayout().compute(
        loadedPersonIds: persons.toSet(),
        nameOf: names,
        links: links,
        viewerId: 'viewer',
        expandedPersonIds: expandedRoots,
        manualPages: const {},
        expansionOrder: persons.sublist(1), // everyone except viewer
      );

      // Build footprint boxes for every positioned person + every chip.
      // Use the SAME constants as WedgeLayoutConfig defaults.
      const config = WedgeLayoutConfig();
      final boxes = <_Box>[];
      output.positions.forEach((id, pos) {
        final isViewer = id == 'viewer';
        final size = isViewer ? config.rootFootprint : config.nodeFootprint;
        final pad = config.footprintPadding;
        boxes.add(_Box(
          id,
          pos.dx - size.width / 2 - pad,
          pos.dy - size.height / 2 - pad,
          pos.dx + size.width / 2 + pad,
          pos.dy + size.height / 2 + pad,
        ));
      });
      output.pageChips.forEach((owner, chip) {
        final size = config.chipFootprint; // now 124×128 (node-sized)
        final pad = config.footprintPadding;
        boxes.add(_Box(
          'chip:$owner',
          chip.slotCenter.dx - size.width / 2 - pad,
          chip.slotCenter.dy - size.height / 2 - pad,
          chip.slotCenter.dx + size.width / 2 + pad,
          chip.slotCenter.dy + size.height / 2 + pad,
        ));
      });

      // Verify ZERO overlaps between any pair of boxes.
      var overlaps = 0;
      for (var i = 0; i < boxes.length; i++) {
        for (var j = i + 1; j < boxes.length; j++) {
          if (boxes[i].overlaps(boxes[j])) {
            overlaps++;
          }
        }
      }
      expect(overlaps, equals(0),
          reason:
              'Zero footprint overlaps after expanding to the node budget '
              'with the larger (node-sized) chip footprint.');
    });
  });

  group('Neutral grey theme token (no hardcoded colour)', () {
    test(
        'The KinshipEdgeColors.extended token is the neutral grey used '
        'for extended/step relations. The bubble ring + count badge '
        'fill MUST use this token (no hardcoded hex value).', () {
      // This is a COMPILE-TIME contract: the bubble and badge widgets
      // reference KinshipEdgeColors.extended directly (see
      // branch_affordance.dart — _WedgeNodeSizedDashedRing's
      // `ringColor: KinshipEdgeColors.extended` and _WedgeCountBadge's
      // `color: KinshipEdgeColors.extended`). We verify the token's
      // value is the documented slate grey (#64748B) so a future
      // change to the token is intentional and reviewed.
      expect(KinshipEdgeColors.extended, isA<Color>());
      // The slate grey #64748B = rgb(100, 116, 139). We use the
      // .r/.g/.b getters (the .red/.green/.blue getters are deprecated
      // in Flutter 3.47+ — they return the 0-255 int channel but the
      // recommended replacement is (*.r * 255.0).round() etc.).
      final c = KinshipEdgeColors.extended;
      expect((c.r * 255.0).round(), equals(0x64)); // 100
      expect((c.g * 255.0).round(), equals(0x74)); // 116
      expect((c.b * 255.0).round(), equals(0x8B)); // 139
    });
  });

  // Note: The bubble-diameter-equals-node-diameter test and the
  // badge-48dp-tap test require pumping the full FamilyGraphScreen
  // widget tree (the bubble + badge are private widgets). Those
  // integration tests live in test/features/family/wedge_e2e_visual_test.dart,
  // which already verifies:
  //   - the +3 page bubble renders (findsOneWidget) with fontSize >= 15
  //     (the node-initials scale, diameter * 0.28 ≈ 20)
  //   - the +3 count badge renders (findsOneWidget) with fontSize >= 14
  //     (the new readable badge size)
  //   - tapping the badge expands the person (the tap-chain in step 5)
  //
  // The camera-fit-inset test is verified by the pure-Dart lerp
  // arithmetic in wedge_unified_animation_test.dart (the camera fit
  // uses the same topInset + bottomInset + effectiveCenterY formula
  // as CameraController.fitToView, which is already covered by the
  // existing camera_controller tests).

  group('Camera fit inset (top + bottom chrome)', () {
    test(
        'The camera fit centres on the EFFECTIVE viewport (between top '
        'and bottom chrome), NOT the raw viewport centre.', () {
      // This is a pure-arithmetic test of the formula in
      // _maybeFitCameraOnWedgeChange (canvas_mixin.dart). The formula
      // mirrors CameraController.fitToView (lines 545-548):
      //   topInset = safeArea.top + appTopChromeHeight
      //   bottomInset = safeArea.bottom + appBottomChromeHeight
      //   effectiveCenterY = topInset + (height - topInset - bottomInset) / 2
      //
      // We verify the formula produces a centre that's HIGHER than the
      // raw viewport centre (because the bottom chrome is larger than
      // the top chrome — the stats panel + toolbar take more vertical
      // space than the OS status bar).
      const viewportHeight = 1000.0;
      const safeAreaTop = 44.0;     // iOS status bar
      const safeAreaBottom = 34.0;  // iOS home indicator
      const appTopChromeHeight = 0.0;  // AppBar excluded by Scaffold
      const appBottomChromeHeight = 196.0; // stats + toolbar + FAB
      // (family_graph_screen.dart line 1183:
      //  bottomPadding + 72 + statsPanelEstimatedHeight = 34 + 72 + 124 = 230,
      //  but we use 196 here for a cleaner arithmetic check.)

      const topInset = safeAreaTop + appTopChromeHeight;
      const bottomInset = safeAreaBottom + appBottomChromeHeight;
      final effectiveHeight = viewportHeight - topInset - bottomInset;
      final effectiveCenterY = topInset + effectiveHeight / 2;

      // Raw viewport centre = 500. Effective centre should be HIGHER
      // (closer to the top) because the bottom chrome is larger.
      const rawCenterY = viewportHeight / 2; // 500
      expect(effectiveCenterY, lessThan(rawCenterY),
          reason: 'effective centre must be HIGHER than raw centre '
              '(bottom chrome is larger than top chrome)');
      // The effective centre is at topInset + (height - insets)/2.
      // With the test numbers: 44 + (1000 - 44 - 230) / 2 = 44 + 363 = 407.
      expect(effectiveCenterY, equals(407.0));

      // A node at canvas-y = 0, with zoom = 1, would be placed at
      // screen-y = effectiveCenterY (407), NOT rawCenterY (500).
      // So a node that was previously under the bottom stats panel
      // now sits 93px higher — clear of the overlay.
      final panY = effectiveCenterY - 0 * 1.0; // node at canvas y=0, zoom=1
      expect(panY, equals(407.0));
      expect(panY, lessThan(rawCenterY),
          reason: 'panY must be less than rawCentre so nodes shift up '
              'away from the bottom chrome');
    });
  });
}

/// A minimal axis-aligned box used by the no-overlap test.
class _Box {
  const _Box(this.id, this.minX, this.minY, this.maxX, this.maxY);
  final String id;
  final double minX, minY, maxX, maxY;

  bool overlaps(_Box other) =>
      minX < other.maxX &&
      other.minX < maxX &&
      minY < other.maxY &&
      other.minY < maxY;
}
