// test/graph/engine/branch_expand_isolate_overlap_test.dart
//
// [BUG-TRACE] DIAGNOSTIC TEST — ISOLATE PATH
//
// Reproduces the user-reported manual-branch-expand overlap bug WITH a
// large enough graph (16+ nodes) to trigger the isolate layout path
// (nodeCount > 15). The isolate path uses `previousPositionsPrimitive`
// (Map<String, List<double>>) serialization — if there's any precision
// loss or key mismatch in the round-trip, the bug would manifest HERE
// but NOT in the small-graph sync path.
//
// Test scenario:
//   - 20 nodes total: anchor + 2 children + 2 grandchildren (branch
//     under c1) + 15 filler nodes on ring 1 to push past the 15-node
//     isolate threshold.
//   - Layout 20 nodes → snapshot.
//   - Collapse (hide 2 grandchildren) → layout 18 nodes with snapshot.
//   - Expand (re-add 2 grandchildren) → layout 20 nodes with merged
//     cache.
//   - Assert ZERO overlap.
//
// This addresses case 3 (downstream isolate serialization).

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
  group('[BUG-TRACE] Isolate-path collapse → expand', () {
    test('20-node graph (isolate path) — collapse → expand produces ZERO overlap', () {
      // ── Build a 20-node graph: anchor + 17 children on ring 1 +
      // 2 grandchildren on ring 2 (under c1). ────────────────────
      final persons = <GraphPerson>[
        _person('anchor', gen: 0, isAnchor: true, name: 'Anchor'),
        _person('c1', gen: 1, name: 'Child 1'),
        _person('c2', gen: 1, name: 'Child 2'),
      ];
      final rels = <GraphRelationship>[
        // c1 is parent, anchor is child? NO — codebase convention:
        // labelAtoB='son' means fromPerson IS the parent, toPerson
        // IS the child. So edge (anchor → c1) with labelAtoB='son'
        // means anchor is parent, c1 is child.
        _rel('r1', 'anchor', 'c1', 'parent', labelAtoB: 'son'),
        _rel('r2', 'anchor', 'c2', 'parent', labelAtoB: 'daughter'),
      ];
      // 15 filler children of anchor to push past 15-node isolate
      // threshold.
      for (var i = 3; i <= 17; i++) {
        persons.add(_person('c$i', gen: 1, name: 'Child $i'));
        rels.add(_rel('rf$i', 'anchor', 'c$i', 'parent',
            labelAtoB: i % 2 == 0 ? 'son' : 'daughter'));
      }
      // 2 grandchildren under c1 — this is the branch we'll collapse.
      persons.add(_person('gc1', gen: 2, name: 'Grandchild 1'));
      persons.add(_person('gc2', gen: 2, name: 'Grandchild 2'));
      rels.add(_rel('rg1', 'c1', 'gc1', 'parent', labelAtoB: 'son'));
      rels.add(_rel('rg2', 'c1', 'gc2', 'parent', labelAtoB: 'daughter'));

      // Total: 20 nodes (anchor + 17 children + 2 grandchildren).
      expect(persons.length, 20,
          reason: 'Need 20 nodes to exceed 15-node isolate threshold.');
      print('━━━ [ISOLATE TEST] nodeCount=${persons.length} (should trigger isolate path) ━━━');

      final layout = RadialLayout();

      // ── Step 1: INITIAL layout (20 nodes, all visible) ─────────
      final resultInitial = layout.compute(
        persons: persons,
        relationships: rels,
        anchorPersonId: 'anchor',
      );
      print('━━━ [STEP 1] INITIAL layout — ${resultInitial.positions.length} positions ━━━');
      for (final entry in resultInitial.positions.entries) {
        print('  ${entry.key}: (${entry.value.dx.toStringAsFixed(1)}, '
            '${entry.value.dy.toStringAsFixed(1)})');
      }
      expect(resultInitial.positions.length, 20);

      // ── Step 2: SNAPSHOT capture (mimics branch_affordance.dart
      // L1389-1446) — save full positions map keyed by branch root.
      final snapshot = Map<String, Offset>.from(resultInitial.positions);
      print('━━━ [STEP 2] SNAPSHOT captured (root=c1, ${snapshot.length} entries) ━━━');

      // ── Step 3: COLLAPSE — hide gc1 + gc2, layout 18 nodes ────
      final personsCollapsed = persons
          .where((p) => p.id != 'gc1' && p.id != 'gc2')
          .toList();
      final relsCollapsed = rels
          .where((r) =>
              r.fromPersonId != 'gc1' && r.fromPersonId != 'gc2' &&
              r.toPersonId != 'gc1' && r.toPersonId != 'gc2')
          .toList();
      expect(personsCollapsed.length, 18);

      final resultCollapsed = layout.compute(
        persons: personsCollapsed,
        relationships: relsCollapsed,
        anchorPersonId: 'anchor',
        preservePositions: true,
        previousPositions: snapshot,
      );
      print('━━━ [STEP 3] COLLAPSE layout — ${resultCollapsed.positions.length} positions ━━━');
      // ── Step 4: EXPAND — re-add gc1 + gc2, layout 20 nodes ────
      // Mimics branch_affordance.dart L520-554: merge current cache
      // with snapshot, pass as previousPositions with preservePositions=true.
      final mergedCache = <String, Offset>{
        ...resultCollapsed.positions,
        ...snapshot,
      };
      print('━━━ [STEP 4] EXPAND — merged cache has ${mergedCache.length} entries ━━━');
      print('  gc1 in merged: ${mergedCache.containsKey('gc1')} → ${mergedCache['gc1']}');
      print('  gc2 in merged: ${mergedCache.containsKey('gc2')} → ${mergedCache['gc2']}');

      final resultExpanded = layout.compute(
        persons: persons,
        relationships: rels,
        anchorPersonId: 'anchor',
        preservePositions: true,
        previousPositions: mergedCache,
      );
      print('━━━ [STEP 5] EXPAND OUTPUT — ${resultExpanded.positions.length} positions ━━━');
      for (final entry in resultExpanded.positions.entries) {
        print('  ${entry.key}: (${entry.value.dx.toStringAsFixed(1)}, '
            '${entry.value.dy.toStringAsFixed(1)})');
      }
      expect(resultExpanded.positions.length, 20);

      // ── Step 6: OVERLAP CHECK ─────────────────────────────────
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
      for (final p in overlappingPairs) {
        print('  OVERLAP: $p');
      }

      // ── Step 7: POSITION RESTORATION CHECK ────────────────────
      final gc1Initial = resultInitial.positions['gc1']!;
      final gc1Expanded = resultExpanded.positions['gc1']!;
      final drift = (gc1Initial - gc1Expanded).distance;
      print('━━━ [STEP 7] RESTORATION CHECK ━━━');
      print('  gc1 initial=$gc1Initial expanded=$gc1Expanded drift=${drift.toStringAsFixed(1)}px');

      // ── ASSERT: zero overlap ──────────────────────────────────
      expect(overlappingPairs, isEmpty,
          reason: 'BUG REPRODUCED (isolate path): overlapping pairs found '
              'in expand output — ${overlappingPairs.join(", ")}.');
    });
  });
}
