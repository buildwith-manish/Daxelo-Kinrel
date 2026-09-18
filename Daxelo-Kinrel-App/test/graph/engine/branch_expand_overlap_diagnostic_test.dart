// test/graph/engine/branch_expand_overlap_diagnostic_test.dart
//
// [BUG-TRACE] DIAGNOSTIC TEST
//
// Reproduces the user-reported manual-branch-expand overlap bug:
//   "expanding a collapsed branch bubble places the newly-revealed
//    node(s) directly on top of the anchor node instead of restoring
//    their pre-collapse position"
//
// This test simulates the FULL collapse → expand cycle through the
// RadialLayout engine itself, mirroring exactly what the provider
// flow does:
//
//   1. INITIAL layout: 5 visible nodes — anchor + 2 children + 2
//      grandchildren (one branch of 2 grandchildren under c1).
//   2. CAPTURE positions of all 5 (this is what the snapshot would
//      store at collapse time).
//   3. COLLAPSE: hide the 2 grandchildren (remove from `persons`).
//      Re-run layout WITH preservePositions=true + previousPositions
//      = the captured positions. Cache the resulting 3-node layout.
//   4. EXPAND: re-add the 2 grandchildren to `persons`. Re-run layout
//      WITH preservePositions=true + previousPositions = MERGED cache
//      (3-node cache overlaid with the 2-node snapshot from step 2).
//      This is exactly what graphLayoutProvider does on expand.
//   5. ASSERT no two nodes in the EXPAND result occupy the same
//      (x, y) within 1px in BOTH dx AND dy.
//
// The test deliberately invokes the layout engine DIRECTLY (not the
// provider) so the bug surface is precisely the radial_layout.dart
// behavior, not the provider plumbing. If overlap occurs here, it's
// case 3 (downstream in radial_layout.dart). If overlap doesn't
// occur here but does in the real app, it's case 1 or 2 (provider
// plumbing not delivering previousPositions correctly).

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/engine/radial_layout.dart';

GraphPerson _person(
  String id, {
  int gen = 0,
  bool isAnchor = false,
  String name = 'Person',
}) =>
    GraphPerson(
      id: id,
      name: name,
      generationIndex: gen,
      isAnchor: isAnchor,
    );

GraphRelationship _rel(
  String id,
  String from,
  String to,
  String key, {
  String? labelAtoB,
}) =>
    GraphRelationship(
      id: id,
      fromPersonId: from,
      toPersonId: to,
      relationshipKey: key,
      labelAtoB: labelAtoB ?? key,
    );

void main() {
  group('[BUG-TRACE] Manual-branch-expand overlap diagnostic', () {
    test('collapse → expand on a 2-node branch produces ZERO overlap', () {
      // ── Step 1: INITIAL layout (5 nodes — anchor + 2 children + 2
      // grandchildren hanging off c1) ─────────────────────────────
      final personsInitial = [
        _person('anchor', gen: 0, isAnchor: true, name: 'Anchor'),
        _person('c1', gen: 1, name: 'Child 1'),
        _person('c2', gen: 1, name: 'Child 2'),
        _person('gc1', gen: 2, name: 'Grandchild 1'),
        _person('gc2', gen: 2, name: 'Grandchild 2'),
      ];
      final relsInitial = [
        // c1, c2 are children of anchor.
        _rel('r1', 'c1', 'anchor', 'parent', labelAtoB: 'son'),
        _rel('r2', 'c2', 'anchor', 'parent', labelAtoB: 'daughter'),
        // gc1, gc2 are children of c1 (the branch we'll collapse).
        _rel('r3', 'gc1', 'c1', 'parent', labelAtoB: 'son'),
        _rel('r4', 'gc2', 'c1', 'parent', labelAtoB: 'daughter'),
      ];

      final layout = RadialLayout();
      final resultInitial = layout.compute(
        persons: personsInitial,
        relationships: relsInitial,
        anchorPersonId: 'anchor',
      );

      print('━━━ [STEP 1] INITIAL layout positions ━━━');
      for (final entry in resultInitial.positions.entries) {
        print('  ${entry.key}: (${entry.value.dx.toStringAsFixed(1)}, '
            '${entry.value.dy.toStringAsFixed(1)})');
      }
      expect(resultInitial.positions.length, 5,
          reason: 'All 5 nodes should be placed in the initial layout.');
      for (final id in ['anchor', 'c1', 'c2', 'gc1', 'gc2']) {
        expect(resultInitial.positions[id], isNotNull);
        expect(resultInitial.positions[id]!, isNot(equals(Offset.zero)),
            reason: 'Node $id must have a non-origin position.');
      }

      // ── Step 2: SNAPSHOT capture ───────────────────────────────
      // (In the real app, branch_affordance.dart saves the entire
      // positions map to preCollapseLayoutSnapshotProvider keyed by
      // the branch root — c1 in this test.)
      final snapshot = Map<String, Offset>.from(resultInitial.positions);
      print('━━━ [STEP 2] SNAPSHOT captured for branch root=c1 ━━━');
      print('  snapshot keys: ${snapshot.keys.toList()}');

      // ── Step 3: COLLAPSE — hide gc1 + gc2 (the branch under c1)
      //
      // After collapse, only anchor + c1 + c2 are visible. The layout
      // runs WITH preservePositions=true + previousPositions=snapshot
      // (so c1, c2 keep their positions; gc1/gc2 are simply filtered
      // out by `if (!currentIds.contains(entry.key)) continue;` in
      // radial_layout.dart L425).
      final personsCollapsed = [
        _person('anchor', gen: 0, isAnchor: true, name: 'Anchor'),
        _person('c1', gen: 1, name: 'Child 1'),
        _person('c2', gen: 1, name: 'Child 2'),
      ];
      final relsCollapsed = [
        _rel('r1', 'c1', 'anchor', 'parent', labelAtoB: 'son'),
        _rel('r2', 'c2', 'anchor', 'parent', labelAtoB: 'daughter'),
      ];
      final resultCollapsed = layout.compute(
        persons: personsCollapsed,
        relationships: relsCollapsed,
        anchorPersonId: 'anchor',
        preservePositions: true,
        previousPositions: snapshot,
      );
      print('━━━ [STEP 3] COLLAPSE layout positions ━━━');
      for (final entry in resultCollapsed.positions.entries) {
        print('  ${entry.key}: (${entry.value.dx.toStringAsFixed(1)}, '
            '${entry.value.dy.toStringAsFixed(1)})');
      }
      expect(resultCollapsed.positions.length, 3,
          reason: 'Only 3 nodes should be placed after collapse.');

      // ── Step 4: EXPAND — re-add gc1 + gc2 ─────────────────────
      //
      // At this point the real app:
      //   - Reads preCollapseLayoutSnapshotProvider[c1] → returns the
      //     5-node snapshot from step 2.
      //   - Merges it into lastLayoutPositionsProvider (current 3-node
      //     cache ⊕ 5-node snapshot → 5-node map since snapshot
      //     entries win for duplicate keys; gc1/gc2 keys are NEW so
      //     they get added; c1/c2/anchor are overwritten with snapshot
      //     values).
      //   - graphLayoutProvider runs WITH preservePositions=true +
      //     previousPositions = the merged 5-node map.
      final personsExpanded = personsInitial; // same as initial
      final relsExpanded = relsInitial;       // same as initial
      final mergedCache = <String, Offset>{
        // Start with current cache (3 nodes — post-collapse).
        ...resultCollapsed.positions,
        // Overlay the snapshot (5 nodes — including gc1, gc2).
        ...snapshot,
      };
      print('━━━ [STEP 4] EXPAND — merged previousPositions ━━━');
      print('  mergedCache keys: ${mergedCache.keys.toList()}');
      print('  mergedCache gc1: ${mergedCache['gc1']}');
      print('  mergedCache gc2: ${mergedCache['gc2']}');

      final resultExpanded = layout.compute(
        persons: personsExpanded,
        relationships: relsExpanded,
        anchorPersonId: 'anchor',
        preservePositions: true,
        previousPositions: mergedCache,
      );
      print('━━━ [STEP 5] EXPAND layout OUTPUT positions ━━━');
      for (final entry in resultExpanded.positions.entries) {
        print('  ${entry.key}: (${entry.value.dx.toStringAsFixed(1)}, '
            '${entry.value.dy.toStringAsFixed(1)})');
      }
      expect(resultExpanded.positions.length, 5,
          reason: 'All 5 nodes should be placed after expand.');

      // ── Step 6: OVERLAP CHECK ─────────────────────────────────
      // The user's reported bug: newly-revealed nodes (gc1, gc2) land
      // AT THE ANCHOR'S position. Verify this doesn't happen.
      final entries = resultExpanded.positions.entries.toList();
      final overlappingPairs = <String>[];
      for (var i = 0; i < entries.length; i++) {
        for (var j = i + 1; j < entries.length; j++) {
          final a = entries[i].value;
          final b = entries[j].value;
          if ((a.dx - b.dx).abs() <= 1.0 && (a.dy - b.dy).abs() <= 1.0) {
            overlappingPairs.add(
                '${entries[i].key}@(${a.dx.toStringAsFixed(1)},${a.dy.toStringAsFixed(1)})<=>${entries[j].key}@(${b.dx.toStringAsFixed(1)},${b.dy.toStringAsFixed(1)})');
          }
        }
      }
      print('━━━ [STEP 6] OVERLAP CHECK ━━━');
      print('  overlappingPairs: ${overlappingPairs.length}');
      if (overlappingPairs.isNotEmpty) {
        for (final p in overlappingPairs) {
          print('  OVERLAP: $p');
        }
      } else {
        print('  NONE — zero overlap confirmed.');
      }

      // ── Step 7: POSITION RESTORATION CHECK ────────────────────
      // The user's secondary complaint: "instead of restoring their
      // pre-collapse position". Verify gc1/gc2 returned to (or near)
      // their pre-collapse positions.
      final gc1Initial = resultInitial.positions['gc1']!;
      final gc1Expanded = resultExpanded.positions['gc1']!;
      final gc2Initial = resultInitial.positions['gc2']!;
      final gc2Expanded = resultExpanded.positions['gc2']!;
      final gc1Drift = (gc1Initial - gc1Expanded).distance;
      final gc2Drift = (gc2Initial - gc2Expanded).distance;
      print('━━━ [STEP 7] POSITION RESTORATION CHECK ━━━');
      print('  gc1 initial=$gc1Initial expanded=$gc1Expanded drift=${gc1Drift.toStringAsFixed(1)}px');
      print('  gc2 initial=$gc2Initial expanded=$gc2Expanded drift=${gc2Drift.toStringAsFixed(1)}px');

      // ── ASSERTIONS ────────────────────────────────────────────
      expect(overlappingPairs, isEmpty,
          reason: 'BUG REPRODUCED: overlapping pairs found in expand '
              'output — ${overlappingPairs.join(", ")}. This is the '
              'manual-branch-expand overlap bug.');
    });
  });
}
