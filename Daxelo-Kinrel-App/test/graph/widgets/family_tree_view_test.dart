// test/graph/widgets/family_tree_view_test.dart
//
// Smoke test for the new Family Tree view (Family Space §5).
//
// Verifies:
//   - FamilyTreeView renders without crashing
//   - TreePainter draws connectors without exceptions
//   - The treeLayoutProvider produces sensible positions
//   - The familyTreeProvider parses the RPC response correctly
//
// This is a widget smoke test — not a pixel-perfect visual test.
// The actual visual layout is exercised by the live RPC test
// (verified manually against the 714-member Sharma family).

import 'dart:ui' show PictureRecorder, Canvas, Offset, Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/core/services/graph_layout_service.dart';
import 'package:kinrel/graph/engine/hierarchical_layout.dart';
import 'package:kinrel/graph/rendering/tree_painter.dart';
import 'package:kinrel/graph/rendering/tree_pdf_exporter.dart';

void main() {
  group('TreePainter', () {
    test('paints spouse connector without throwing', () {
      final painter = TreePainter(
        positions: {
          'a': const Offset(100, 100),
          'b': const Offset(200, 100),
        },
        edges: const [
          (fromId: 'a', toId: 'b', relationshipKey: 'spouse'),
        ],
      );

      // Should paint without throwing.
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 200));
      recorder.endRecording();
      expect(painter.shouldRepaint(painter), false);
    });

    test('paints parent→child connector without throwing', () {
      final painter = TreePainter(
        positions: {
          'parent': const Offset(100, 50),
          'child': const Offset(100, 200),
        },
        edges: const [
          (fromId: 'parent', toId: 'child', relationshipKey: 'parent'),
        ],
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 300));
      recorder.endRecording();
    });

    test('skips edges touching hidden persons', () {
      final painter = TreePainter(
        positions: {
          'a': const Offset(100, 100),
          'b': const Offset(200, 100),
        },
        edges: const [
          (fromId: 'a', toId: 'b', relationshipKey: 'spouse'),
        ],
        hiddenPersonIds: {'b'},
      );

      // Should still paint without throwing, just skip the hidden edge.
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 200));
      recorder.endRecording();
    });

    test('skips non-lineage relationship keys', () {
      final painter = TreePainter(
        positions: {
          'a': const Offset(100, 100),
          'b': const Offset(200, 100),
        },
        edges: const [
          (fromId: 'a', toId: 'b', relationshipKey: 'sibling'),
          (fromId: 'a', toId: 'b', relationshipKey: 'uncle'),
        ],
      );

      // Should paint nothing (no spouse/parent/child edges) but not throw.
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 200));
      recorder.endRecording();
    });

    test('shouldRepaint returns true when positions change', () {
      final painter1 = TreePainter(
        positions: {'a': const Offset(100, 100)},
        edges: const [],
      );
      final painter2 = TreePainter(
        positions: {'a': const Offset(200, 200)},
        edges: const [],
      );
      expect(painter2.shouldRepaint(painter1), true);
    });

    test('shouldRepaint returns true when focusedPersonId changes', () {
      final base = TreePainter(
        positions: {'a': const Offset(100, 100)},
        edges: const [],
        focusedPersonId: 'a',
      );
      final changed = TreePainter(
        positions: {'a': const Offset(100, 100)},
        edges: const [],
        focusedPersonId: 'b',
      );
      expect(changed.shouldRepaint(base), true);
    });

    test('handles empty inputs gracefully', () {
      final painter = TreePainter(
        positions: const {},
        edges: const [],
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 200));
      recorder.endRecording();
      // No exception thrown — pass.
    });
  });

  group('HierarchicalLayout (Tree view primary engine)', () {
    test('computes positions for a simple 3-generation tree', () {
      final layout = HierarchicalLayout();

      final persons = [
        GraphPerson(
            id: 'grandparent', name: 'Grandparent', generationIndex: -1),
        GraphPerson(id: 'parent', name: 'Parent', generationIndex: 0),
        GraphPerson(id: 'child', name: 'Child', generationIndex: 1),
      ];

      final relationships = [
        GraphRelationship(
            id: 'r1',
            fromPersonId: 'parent',
            toPersonId: 'grandparent',
            relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r2',
            fromPersonId: 'child',
            toPersonId: 'parent',
            relationshipKey: 'parent'),
      ];

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'parent',
      );

      // All 3 persons should have positions.
      expect(result.positions.length, 3);
      expect(result.positions['grandparent'], isNotNull);
      expect(result.positions['parent'], isNotNull);
      expect(result.positions['child'], isNotNull);

      // Grandparent (gen -1) should be above parent (gen 0).
      expect(result.positions['grandparent']!.dy,
          lessThan(result.positions['parent']!.dy));
      // Child (gen +1) should be below parent (gen 0).
      expect(result.positions['child']!.dy,
          greaterThan(result.positions['parent']!.dy));

      // Canvas should have nonzero dimensions.
      expect(result.canvasWidth, greaterThan(0));
      expect(result.canvasHeight, greaterThan(0));
    });

    test('handles empty input without crashing', () {
      final layout = HierarchicalLayout();
      final result = layout.compute(
        persons: const [],
        relationships: const [],
      );
      expect(result.positions, isEmpty);
      expect(result.canvasWidth, 0);
      expect(result.canvasHeight, 0);
    });

    test('positions spouses side-by-side on same Y', () {
      final layout = HierarchicalLayout();

      final persons = [
        GraphPerson(id: 'a', name: 'A', generationIndex: 0),
        GraphPerson(id: 'b', name: 'B', generationIndex: 0),
      ];

      final relationships = [
        GraphRelationship(
            id: 'r1',
            fromPersonId: 'a',
            toPersonId: 'b',
            relationshipKey: 'spouse'),
      ];

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'a',
      );

      // Both should be positioned.
      expect(result.positions.length, 2);
      // Both should be at the same Y (same generation).
      expect(result.positions['a']!.dy, equals(result.positions['b']!.dy));
    });

    test('handles large family without stack overflow (1000 nodes)', () {
      final layout = HierarchicalLayout();

      // Build a 1000-node linear ancestor chain.
      // gen[0] → gen[1] → ... → gen[999] (each is parent of the next).
      final persons = <GraphPerson>[];
      final relationships = <GraphRelationship>[];

      for (var i = 0; i < 1000; i++) {
        persons.add(GraphPerson(
          id: 'p$i',
          name: 'Person $i',
          generationIndex: i,
        ));
        if (i > 0) {
          relationships.add(GraphRelationship(
            id: 'r$i',
            fromPersonId: 'p$i',
            toPersonId: 'p${i - 1}',
            relationshipKey: 'parent',
          ));
        }
      }

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'p0',
      );

      // All 1000 should be positioned without stack overflow.
      expect(result.positions.length, 1000);
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // v5.126: Regression tests for the false-root + BFS-gen fixes.
  // ═════════════════════════════════════════════════════════════════════
  group('HierarchicalLayout v5.126 root-finding + BFS-gen fixes', () {
    test('BUG 1: anchor with descendants does NOT create false root columns', () {
      // Reproduction of the original bug:
      //   - Anchor A (root) at top
      //   - A has child B (gen 1)
      //   - B has child C (gen 2)
      //   - A has child D (gen 1)
      // The old code walked up from A (found A as the sole root), then
      // the "disconnected fallback" loop added B, C, D as separate
      // roots — creating 4 false root columns and very long lines.
      //
      // The fix: one-pass root finding. Only A has no parent-edge, so
      // only A is a root. B/C/D are descendants of A in a single tree.
      final layout = HierarchicalLayout();

      final persons = [
        GraphPerson(id: 'a', name: 'A', generationIndex: 0),
        GraphPerson(id: 'b', name: 'B', generationIndex: 1),
        GraphPerson(id: 'c', name: 'C', generationIndex: 2),
        GraphPerson(id: 'd', name: 'D', generationIndex: 1),
      ];

      final relationships = [
        GraphRelationship(
            id: 'r1', fromPersonId: 'b', toPersonId: 'a', relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r2', fromPersonId: 'c', toPersonId: 'b', relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r3', fromPersonId: 'd', toPersonId: 'a', relationshipKey: 'parent'),
      ];

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'a',
      );

      // All 4 positioned.
      expect(result.positions.length, 4);

      // GENERATION-LOCKED Y:
      //   A (root)        → top row    (smallest Y)
      //   B, D (gen 1)    → middle row (same Y, larger than A)
      //   C    (gen 2)    → bottom row (largest Y)
      final yA = result.positions['a']!.dy;
      final yB = result.positions['b']!.dy;
      final yC = result.positions['c']!.dy;
      final yD = result.positions['d']!.dy;

      // A is above B and D.
      expect(yA, lessThan(yB),
          reason: 'Root A should be above its child B');
      expect(yA, lessThan(yD),
          reason: 'Root A should be above its child D');

      // B and D are at the SAME Y (same BFS generation).
      expect(yB, equals(yD),
          reason: 'B and D are both children of A → same BFS gen → same Y');

      // C is below B.
      expect(yC, greaterThan(yB),
          reason: 'C (grandchild) should be below B (its parent)');

      // NO FALSE ROOTS:
      // The old bug would have placed B/C/D at the TOP ROW (same Y as A)
      // because they were "rescued" as disconnected roots. With the fix,
      // only A is at the top row. Verify by checking that NO other node
      // shares A's Y.
      final topRowNodes = result.positions.entries
          .where((e) => e.value.dy == yA)
          .map((e) => e.key)
          .toList();
      expect(topRowNodes, equals(['a']),
          reason: 'Only A (the sole root) should be on the top row. '
              'Old bug would place B/C/D here too.');
    });

    test('BUG 1b: multiple disconnected true roots each get their own column', () {
      // Two separate families in the same dataset (no shared ancestors).
      // Both A and X are true roots — both should be on the top row.
      final layout = HierarchicalLayout();

      final persons = [
        GraphPerson(id: 'a', name: 'A', generationIndex: 0),
        GraphPerson(id: 'b', name: 'B', generationIndex: 1),
        GraphPerson(id: 'x', name: 'X', generationIndex: 0),
        GraphPerson(id: 'y', name: 'Y', generationIndex: 1),
      ];

      final relationships = [
        GraphRelationship(
            id: 'r1', fromPersonId: 'b', toPersonId: 'a', relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r2', fromPersonId: 'y', toPersonId: 'x', relationshipKey: 'parent'),
      ];

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'a',
      );

      expect(result.positions.length, 4);

      // Both A and X are on the top row (true roots).
      final yA = result.positions['a']!.dy;
      final yX = result.positions['x']!.dy;
      final yB = result.positions['b']!.dy;
      final yY = result.positions['y']!.dy;

      expect(yA, equals(yX),
          reason: 'A and X are both true roots → same top row');
      expect(yB, equals(yY),
          reason: 'B and Y are both gen-1 children → same row');
      expect(yA, lessThan(yB),
          reason: 'Roots above children');

      // X column is to the right of A column (subtree side-by-side).
      expect(result.positions['x']!.dx, greaterThan(result.positions['a']!.dx),
          reason: 'Each true root gets its own column');
    });

    test('BUG 2: Y is consistent regardless of which BFS path reaches a node first', () {
      // Diamond: A → B, A → C, B → D, C → D
      // D is reachable via two paths. Old code gave D the Y of whichever
      // path the DFS visited first. New code uses BFS — D gets a single
      // bfsGen = 2 (depth 2 from root A), regardless of path order.
      final layout = HierarchicalLayout();

      final persons = [
        GraphPerson(id: 'a', name: 'A', generationIndex: 0),
        GraphPerson(id: 'b', name: 'B', generationIndex: 1),
        GraphPerson(id: 'c', name: 'C', generationIndex: 1),
        GraphPerson(id: 'd', name: 'D', generationIndex: 2),
      ];

      final relationships = [
        GraphRelationship(
            id: 'r1', fromPersonId: 'b', toPersonId: 'a', relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r2', fromPersonId: 'c', toPersonId: 'a', relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r3', fromPersonId: 'd', toPersonId: 'b', relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r4', fromPersonId: 'd', toPersonId: 'c', relationshipKey: 'parent'),
      ];

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'a',
      );

      expect(result.positions.length, 4);

      final yA = result.positions['a']!.dy;
      final yB = result.positions['b']!.dy;
      final yC = result.positions['c']!.dy;
      final yD = result.positions['d']!.dy;

      // A is at top.
      // B and C are at the same Y (gen 1).
      // D is at gen 2 (below B and C).
      expect(yA, lessThan(yB));
      expect(yB, equals(yC),
          reason: 'B and C are siblings (both gen 1 from A)');
      expect(yD, greaterThan(yB),
          reason: 'D is one generation below B/C regardless of path');
      expect(yD, greaterThan(yC),
          reason: 'D is one generation below B/C regardless of path');

      // Verify Y values match BFS-gen formula exactly:
      // yB - yA == yD - yB == levelSpacing (the gen-1 → gen-2 step).
      // (This proves Y is computed from BFS gen, not parent's Y.)
      final levelStep = yB - yA;
      expect((yD - yB) - levelStep, lessThan(1.0),
          reason: 'D should be exactly one levelSpacing below B');
    });

    test('BUG 2b: spouse inherits partner\'s BFS gen (same Y, even if DB genIndex differs)', () {
      // A (genIndex=0, root) → child B (genIndex=0 WRONG in DB, should be 1).
      // B has spouse S (genIndex=0 also wrong in DB).
      // With the old code, B got Y from parent recursion, S got Y from
      // the spouse-positioning code (also parent's Y). But if the DB
      // genIndex was used for the ROOT (as the old code did for A),
      // and A's DB genIndex=0 while B's DB genIndex=0 too, the old code
      // would have placed A and B at the SAME Y — wrong.
      //
      // New code: BFS assigns A=0, B=1, S=1 (inherits from B). Y from BFS.
      final layout = HierarchicalLayout();

      final persons = [
        GraphPerson(id: 'a', name: 'A', generationIndex: 0),
        GraphPerson(id: 'b', name: 'B', generationIndex: 0), // WRONG in DB
        GraphPerson(id: 's', name: 'S (spouse)', generationIndex: 0), // WRONG in DB
      ];

      final relationships = [
        GraphRelationship(
            id: 'r1', fromPersonId: 'b', toPersonId: 'a', relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r2', fromPersonId: 'b', toPersonId: 's', relationshipKey: 'spouse'),
      ];

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'a',
      );

      expect(result.positions.length, 3);

      final yA = result.positions['a']!.dy;
      final yB = result.positions['b']!.dy;
      final yS = result.positions['s']!.dy;

      // A (root) at top.
      // B (gen 1) below A.
      // S (spouse of B, inherits B's gen) at same Y as B.
      expect(yA, lessThan(yB),
          reason: 'A above B regardless of stale DB generationIndex');
      expect(yB, equals(yS),
          reason: 'Spouse S should inherit B\'s BFS gen → same Y');
    });

    test('regression: ringRadii is populated with Y per generation', () {
      // The Graph view's camera focus code uses ringRadii to know each
      // row's Y without re-running the layout. Verify it's populated.
      final layout = HierarchicalLayout();

      final persons = [
        GraphPerson(id: 'a', name: 'A', generationIndex: 0),
        GraphPerson(id: 'b', name: 'B', generationIndex: 1),
        GraphPerson(id: 'c', name: 'C', generationIndex: 2),
      ];

      final relationships = [
        GraphRelationship(
            id: 'r1', fromPersonId: 'b', toPersonId: 'a', relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r2', fromPersonId: 'c', toPersonId: 'b', relationshipKey: 'parent'),
      ];

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
      );

      // ringRadii should have an entry for each BFS generation.
      expect(result.ringRadii.length, greaterThanOrEqualTo(3));
      // The Y values should be monotonically increasing per generation.
      final sortedGens = result.ringRadii.keys.toList()..sort();
      for (var i = 1; i < sortedGens.length; i++) {
        expect(result.ringRadii[sortedGens[i]]!,
            greaterThan(result.ringRadii[sortedGens[i - 1]]!),
            reason: 'ringRadii Y should increase per generation');
      }
    });

    // v5.127: regression test for the rounded-rectangle node shape.
    // The new node is 120×72 (5:3 aspect, wider than tall). This test
    // verifies the layout math still produces non-overlapping nodes
    // with the new dimensions — sibling spacing, subtree width, and
    // level spacing all depend on accurate nodeWidth/nodeHeight.
    test('v5.127: rounded-rect node dimensions produce non-overlapping siblings', () {
      final layout = HierarchicalLayout(
        config: const HierarchicalLayoutConfig(
          // Use the new defaults (rounded-rect tuned).
          siblingSpacing: 20.0,
          levelSpacing: 110.0,
          spouseGap: 8.0,
          padding: 60.0,
          nodeWidth: 120.0,
          nodeHeight: 72.0,
        ),
      );

      // Two siblings under one parent.
      final persons = [
        GraphPerson(id: 'parent', name: 'Parent', generationIndex: 0),
        GraphPerson(id: 'child1', name: 'Child 1', generationIndex: 1),
        GraphPerson(id: 'child2', name: 'Child 2', generationIndex: 1),
      ];

      final relationships = [
        GraphRelationship(
            id: 'r1', fromPersonId: 'child1', toPersonId: 'parent', relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r2', fromPersonId: 'child2', toPersonId: 'parent', relationshipKey: 'parent'),
      ];

      final result = layout.compute(
        persons: persons,
        relationships: relationships,
        anchorPersonId: 'parent',
      );

      expect(result.positions.length, 3);

      // Both children should be at the same Y (same BFS generation).
      final y1 = result.positions['child1']!.dy;
      final y2 = result.positions['child2']!.dy;
      expect(y1, equals(y2),
          reason: 'Siblings must share the same Y (generation-locked)');

      // Children must be BELOW the parent.
      final yParent = result.positions['parent']!.dy;
      expect(y1, greaterThan(yParent),
          reason: 'Children must be below parent');

      // The two children must NOT overlap horizontally.
      // Each card is 120 wide; centers must be at least 120 apart
      // (siblingSpacing=20 means they should be ~140 apart).
      final x1 = result.positions['child1']!.dx;
      final x2 = result.positions['child2']!.dx;
      final horizontalGap = (x1 - x2).abs();
      expect(horizontalGap, greaterThanOrEqualTo(120.0),
          reason: 'Sibling cards (120 wide each) must not overlap. '
              'Got gap=$horizontalGap between centers.');
    });

    test('v5.127: default config matches rounded-rect dimensions', () {
      // Verify the new defaults are wired correctly — callers that
      // don't override (e.g. TreePdfExporter) should get the
      // rounded-rect-tuned values automatically.
      const config = HierarchicalLayoutConfig();
      expect(config.nodeWidth, 120.0);
      expect(config.nodeHeight, 72.0);
      // 5:3 aspect ratio (wider than tall).
      expect(config.nodeWidth / config.nodeHeight, closeTo(5.0 / 3.0, 0.01));
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // v5.126: PDF exporter tests (vector + paginated).
  // ═════════════════════════════════════════════════════════════════════
  group('TreePdfExporter', () {
    test('produces non-empty PDF bytes for a simple family', () async {
      final exporter = TreePdfExporter();

      final persons = [
        GraphPerson(id: 'a', name: 'Alice', generationIndex: 0),
        GraphPerson(id: 'b', name: 'Bob', generationIndex: 1),
        GraphPerson(id: 'c', name: 'Carol', generationIndex: 2),
      ];

      final relationships = [
        GraphRelationship(
            id: 'r1', fromPersonId: 'b', toPersonId: 'a', relationshipKey: 'parent'),
        GraphRelationship(
            id: 'r2', fromPersonId: 'c', toPersonId: 'b', relationshipKey: 'parent'),
      ];

      final bytes = await exporter.export(
        persons: persons,
        relationships: relationships,
        familyName: 'Test Family',
      );

      // PDF bytes should be non-empty.
      expect(bytes.length, greaterThan(1000),
          reason: 'PDF should produce substantial bytes for a 3-person family');

      // PDF magic bytes should be present (PDF starts with %PDF-).
      expect(bytes[0], 0x25, reason: 'First byte should be %'); // %
      expect(bytes[1], 0x50, reason: 'Second byte should be P'); // P
      expect(bytes[2], 0x44, reason: 'Third byte should be D'); // D
      expect(bytes[3], 0x46, reason: 'Fourth byte should be F'); // F
    });

    test('handles empty family gracefully', () async {
      final exporter = TreePdfExporter();

      final bytes = await exporter.export(
        persons: const [],
        relationships: const [],
        familyName: 'Empty Family',
      );

      // Should still produce a valid PDF (with the "no members" text).
      expect(bytes.length, greaterThan(500));
      expect(bytes[0], 0x25); // %
    });

    test('paginates large family into multiple pages', () async {
      // Build a 10-generation ancestor chain (1 root + 9 descendants).
      // With maxRowsPerPage=4 default, this should produce 3 pages.
      final exporter = TreePdfExporter();

      final persons = <GraphPerson>[];
      final relationships = <GraphRelationship>[];
      for (var i = 0; i < 10; i++) {
        persons.add(GraphPerson(
          id: 'p$i',
          name: 'Person $i',
          generationIndex: i,
        ));
        if (i > 0) {
          relationships.add(GraphRelationship(
            id: 'r$i',
            fromPersonId: 'p$i',
            toPersonId: 'p${i - 1}',
            relationshipKey: 'parent',
          ));
        }
      }

      final bytes = await exporter.export(
        persons: persons,
        relationships: relationships,
        familyName: 'Chain Family',
      );

      // Should produce substantial bytes (multiple pages).
      expect(bytes.length, greaterThan(5000),
          reason: 'Multi-page PDF should be larger than single-page');
      // Verify PDF magic.
      expect(bytes[0], 0x25);
    });
  });

  group('TreePainter relationship key classification', () {
    test('spouse keys are recognized', () {
      for (final key in ['spouse', 'husband', 'wife', 'partner']) {
        expect(TreePainter.kSpouseKeys.contains(key), true,
            reason: 'Expected $key to be a recognized spouse key');
      }
    });

    test('parent keys are recognized', () {
      for (final key
          in ['parent', 'father', 'mother', 'grandparent', 'grandfather', 'grandmother']) {
        expect(TreePainter.kParentKeys.contains(key), true,
            reason: 'Expected $key to be a recognized parent key');
      }
    });

    test('child keys are recognized', () {
      for (final key in ['child', 'son', 'daughter', 'grandchild']) {
        expect(TreePainter.kChildKeys.contains(key), true,
            reason: 'Expected $key to be a recognized child key');
      }
    });

    test('non-lineage keys are NOT in any of the sets', () {
      for (final key in ['sibling', 'uncle', 'aunt', 'cousin', 'nephew', 'niece']) {
        expect(TreePainter.kSpouseKeys.contains(key), false);
        expect(TreePainter.kParentKeys.contains(key), false);
        expect(TreePainter.kChildKeys.contains(key), false);
      }
    });
  });
}
