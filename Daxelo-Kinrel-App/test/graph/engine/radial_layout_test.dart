// test/graph/engine/radial_layout_test.dart
//
// Focused unit tests for the RadialLayout concentric-ring engine.
//
// Covers:
//   - Layout output is deterministic across repeated runs
//   - No two nodes end up at the exact same coordinates
//   - Empty input returns an empty result
//   - A single anchor is placed at the canvas centre
//   - Ancestors (gen < 0) land in the upper semicircle (Y < anchor Y)
//   - Descendants (gen > 0) land in the lower semicircle (Y > anchor Y)
//   - Every input person receives a position

import 'dart:math';

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
  String key,
) =>
    GraphRelationship(
      id: id,
      fromPersonId: from,
      toPersonId: to,
      relationshipKey: key,
    );

void main() {
  group('RadialLayout', () {
    late RadialLayout layout;

    setUp(() {
      layout = RadialLayout();
    });

    /// Small fixture: anchor + father + mother + one child.
    ({List<GraphPerson> persons, List<GraphRelationship> rels}) _smallFamily() {
      final persons = [
        _person('anchor', gen: 0, isAnchor: true),
        _person('father', gen: -1),
        _person('mother', gen: -1),
        _person('child', gen: 1),
      ];
      final rels = [
        _rel('r1', 'anchor', 'father', 'father'),
        _rel('r2', 'anchor', 'mother', 'mother'),
        _rel('r3', 'anchor', 'child', 'child'),
      ];
      return (persons: persons, rels: rels);
    }

    test('layout output is deterministic across repeated runs', () {
      final fam = _smallFamily();

      final r1 = layout.compute(persons: fam.persons, relationships: fam.rels);
      final r2 = layout.compute(persons: fam.persons, relationships: fam.rels);

      expect(r2.positions.length, r1.positions.length);
      for (final id in r1.positions.keys) {
        expect(r2.positions[id], r1.positions[id],
            reason: 'Position for $id must match across runs');
      }
      expect(r2.canvasWidth, r1.canvasWidth);
      expect(r2.canvasHeight, r1.canvasHeight);
    });

    test('no two nodes end up at the exact same coordinates', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

      final seen = <Offset>{};
      for (final entry in result.positions.entries) {
        expect(
          seen.contains(entry.value),
          isFalse,
          reason: 'Node ${entry.key} at ${entry.value} collides with another '
              'node — coordinates must be unique',
        );
        seen.add(entry.value);
      }
    });

    test('empty input returns an empty result', () {
      final result = layout.compute(persons: const [], relationships: const []);

      expect(result.positions, isEmpty);
      expect(result.canvasWidth, 0);
      expect(result.canvasHeight, 0);
    });

    test('anchor is placed at the computed canvas centre coordinate', () {
      final persons = [_person('only', isAnchor: true)];
      final result = layout.compute(persons: persons, relationships: const []);

      final pos = result.positions['only']!;
      // With a single node, maxRadius = 0, so the centre coordinate
      // equals canvasPadding (default 120). The canvas is sized to
      // (centre + 0 + padding) * 2 so the anchor sits at the geometric
      // centre coordinate the engine computes, even though the canvas
      // is twice as wide to leave room for label overflow.
      const canvasPadding = 120.0;
      expect(pos.dx, closeTo(canvasPadding, 1.0));
      expect(pos.dy, closeTo(canvasPadding, 1.0));
      expect(result.canvasWidth, greaterThan(0));
      expect(result.canvasHeight, greaterThan(0));
    });

    test('ancestors (gen < 0) are placed in the upper semicircle', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

      final anchorY = result.positions['anchor']!.dy;
      final fatherY = result.positions['father']!.dy;

      expect(fatherY, lessThan(anchorY),
          reason: 'Father (gen -1) must be above the anchor (smaller Y)');
    });

    test('descendants (gen > 0) are placed in the lower semicircle', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

      final anchorY = result.positions['anchor']!.dy;
      final childY = result.positions['child']!.dy;

      expect(childY, greaterThan(anchorY),
          reason: 'Child (gen 1) must be below the anchor (larger Y)');
    });

    test('every input person receives a position', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

      for (final p in fam.persons) {
        expect(result.positions.containsKey(p.id), isTrue,
            reason: '${p.id} missing from layout result');
      }
    });

    test('ring radii grow with |generationIndex|', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

      // Anchor (gen 0) is at radius 0; father (gen -1) and child (gen 1)
      // are at radius = baseRadius + 1 * activeSpacing.
      final radii = result.ringRadii;
      expect(radii[0], 0.0);
      expect(radii[-1], greaterThan(0));
      expect(radii[1], greaterThan(0));
      // |gen| = 1 rings should have the same radius.
      expect(radii[-1], closeTo(radii[1]!, 1e-9));
    });

    test('distance from anchor matches ring radius for non-anchor nodes', () {
      final fam = _smallFamily();
      final result = layout.compute(persons: fam.persons, relationships: fam.rels);

      final anchor = result.positions['anchor']!;
      final father = result.positions['father']!;
      final expectedRadius = result.ringRadii[-1]!;

      final dist = sqrt(pow(father.dx - anchor.dx, 2) +
          pow(father.dy - anchor.dy, 2));
      expect(dist, closeTo(expectedRadius, 0.5),
          reason: 'Father should sit exactly on ring radius $expectedRadius');
    });

    // ═══════════════════════════════════════════════════════════════════
    // v5.125 (Step 7): Barycenter sort — any-relationship fallback tier.
    //
    // A person whose ONLY connection to the placed set is a
    // non-parent/child relationship key (an in-law) previously got NO
    // parentAngle and fell through to the end-of-ring fallback — the
    // "Radha Menon / Vikram Mehta floating outlier" bug. The sort now
    // falls back to ANY relationship to a placed node (tier 2) before
    // giving up (tier 3).
    //
    // Family (canonical edges: from A → to B, key X = "B is the X of A"):
    //   me (anchor)
    //   ├─ son1, son2, son3                       (ring 1)
    //   │   son1 → g1a, g1b                        (ring 2, tier-1 block)
    //   │   son2 → g2a, g2b                        (ring 2, tier-1 block)
    //   │   son3 → g3a, g3b                        (ring 2, tier-1 block)
    //   │   son1 → dil1 (wife — spouse-placed)     (ring 2 member)
    //   │   son1 → fil1 (father_in_law)  ◄── SUBJECT 1 (tier-2 only)
    //   │   son3 → mil3 (mother_in_law)  ◄── SUBJECT 2 (tier-2 only)
    //   └─ decoy: g1a → son2 (brother_in_law) — g1a ALSO has a tier-1
    //      parent (son1); the decoy must NOT steal g1a's placement.
    // ═══════════════════════════════════════════════════════════════════
    group('v5.125 (Step 7) — barycenter any-relationship fallback', () {
      ({List<GraphPerson> persons, List<GraphRelationship> rels})
          _inLawFamily() {
        final persons = [
          _person('me', gen: 0, isAnchor: true),
          _person('son1', name: 'Son One'),
          _person('son2', name: 'Son Two'),
          _person('son3', name: 'Son Three'),
          _person('g1a'),
          _person('g1b'),
          _person('g2a'),
          _person('g2b'),
          _person('g3a'),
          _person('g3b'),
          _person('dil1', name: 'Daughter-in-law'),
          _person('fil1', name: 'Father-in-law'),
          _person('mil3', name: 'Mother-in-law'),
        ];
        final rels = [
          _rel('r-s1', 'me', 'son1', 'son'),
          _rel('r-s2', 'me', 'son2', 'son'),
          _rel('r-s3', 'me', 'son3', 'son'),
          // Ring-2 grandchildren (tier-1 parent edges).
          _rel('r-g1a', 'son1', 'g1a', 'son'),
          _rel('r-g1b', 'son1', 'g1b', 'son'),
          _rel('r-g2a', 'son2', 'g2a', 'son'),
          _rel('r-g2b', 'son2', 'g2b', 'son'),
          _rel('r-g3a', 'son3', 'g3a', 'son'),
          _rel('r-g3b', 'son3', 'g3b', 'son'),
          // Non-parent/child connections (the Step 7 case).
          _rel('r-dil1', 'son1', 'dil1', 'wife'),
          _rel('r-fil1', 'son1', 'fil1', 'father_in_law'),
          _rel('r-mil3', 'son3', 'mil3', 'mother_in_law'),
          // Decoy: g1a has BOTH a tier-1 parent (son1) and this tier-2
          // in-law edge to son2. Tier 1 must win.
          _rel('r-decoy', 'g1a', 'son2', 'brother_in_law'),
        ];
        return (persons: persons, rels: rels);
      }

      /// Angle of [id]'s position about the anchor, in degrees.
      double angleOf(Map<String, Offset> positions, String id) {
        final center = positions['me']!;
        final p = positions[id]!;
        return atan2(p.dy - center.dy, p.dx - center.dx) * 180 / pi;
      }

      /// Angular separation in [0, 180] degrees.
      double angleSeparation(double a, double b) {
        var d = (a - b).abs();
        if (d > 180) d = 360 - d;
        return d;
      }

      test('every person (including both in-laws) receives a position',
          () {
        final fam = _inLawFamily();
        final result =
            layout.compute(persons: fam.persons, relationships: fam.rels);

        for (final p in fam.persons) {
          expect(result.positions.containsKey(p.id), isTrue,
              reason: '${p.id} must receive a position');
        }
      });

      test('in-laws land in their connected branch\'s angular sector, '
          'not stacked at the ring\'s end', () {
        final fam = _inLawFamily();
        final result =
            layout.compute(persons: fam.persons, relationships: fam.rels);
        final pos = result.positions;

        final fil1Angle = angleOf(pos, 'fil1');
        final mil3Angle = angleOf(pos, 'mil3');

        // PRIMARY: before the fix, both in-laws had NO parentAngle and
        // sorted to the END of the ring together (≤ 2 angular slots =
        // 36° apart). After the fix they join their connected sons'
        // blocks — son1's block and son3's block — which are always at
        // least a full branch apart (≥ 54°).
        final separation = angleSeparation(fil1Angle, mil3Angle);
        expect(separation, greaterThan(45),
            reason: 'The two in-laws belong to DIFFERENT branches '
                '(son1 and son3). Stacked at the ring end they would be '
                '≤ 36° apart; in their own sectors they are ≥ 54° apart. '
                'Actual: $separation°');

        // Each in-law sits within its connected son's angular sector
        // (one branch block = 4 slots ≈ 72° max from the son's angle).
        expect(
            angleSeparation(fil1Angle, angleOf(pos, 'son1')),
            lessThan(72),
            reason: 'fil1 (son1\'s father-in-law) must sit in son1\'s '
                'sector');
        expect(
            angleSeparation(mil3Angle, angleOf(pos, 'son3')),
            lessThan(72),
            reason: 'mil3 (son3\'s mother-in-law) must sit in son3\'s '
                'sector');
      });

      test('tier 1 (parent/child) still wins over the any-relationship '
          'fallback', () {
        final fam = _inLawFamily();
        final result =
            layout.compute(persons: fam.persons, relationships: fam.rels);
        final pos = result.positions;

        // g1a has a tier-1 parent edge to son1 AND a decoy in-law edge
        // to son2. It must stay in son1's block — the same block as
        // its sibling g1b and son1's father-in-law fil1 (the block
        // spans 4 angular slots ≈ 54°).
        final g1a = angleOf(pos, 'g1a');
        expect(angleSeparation(g1a, angleOf(pos, 'g1b')), lessThan(55),
            reason: 'Sibling g1a/g1b share the tier-1 parent (son1) and '
                'must stay in the same block despite g1a\'s decoy '
                'in-law edge to son2');
        expect(angleSeparation(g1a, angleOf(pos, 'fil1')), lessThan(55),
            reason: 'g1a (tier 1) and fil1 (tier 2, same branch via '
                'son1) must share son1\'s block');
      });
    });

    // ═══════════════════════════════════════════════════════════════════
    // v5.131 (Bug 2 fix): unreachable nodes must NOT pile up on ring 0.
    //
    // Scenario: a branch fetch returns persons whose connecting edges
    // haven't yet been merged into the visible-edge subgraph (or the
    // edges have unrecognized custom keys that BFS over `_parentKeys`
    // doesn't follow). Previously these nodes defaulted to ring 0 and
    // piled up at the anchor's position — the "fanned pile" seen with
    // step/adoptive/half/custom-key branches.
    //
    // The fix banishes unreachable nodes to a peripheral ring one hop
    // beyond the deepest reachable ring (maxHop + 1, positive direction).
    // They still render on the lower semicircle, evenly spaced — no
    // pile-up at the anchor.
    // ═══════════════════════════════════════════════════════════════════
    group('v5.131 (Bug 2 fix) — unreachable nodes go to peripheral ring', () {
      test('multiple unreachable nodes do NOT land on ring 0', () {
        // Anchor + 1 reachable child (so maxHop=1, peripheralRing=2).
        // Three unreachable persons — they must all go to ring 2,
        // NOT to ring 0 (where the anchor sits).
        final persons = [
          _person('anchor', isAnchor: true),
          _person('child'),
          _person('orphan1'),
          _person('orphan2'),
          _person('orphan3'),
        ];
        // Only the anchor→child edge exists. The orphans have NO edges.
        final rels = [
          _rel('r1', 'anchor', 'child', 'child'),
        ];

        final result = layout.compute(persons: persons, relationships: rels);

        // Sanity: every input person received a position.
        for (final p in persons) {
          expect(result.positions.containsKey(p.id), isTrue,
              reason: '${p.id} missing from layout result');
        }

        // Anchor sits at the canvas centre (ring 0).
        final anchorPos = result.positions['anchor']!;
        // Child sits on ring 1 (radius > 0, lower semicircle).
        final childPos = result.positions['child']!;
        final childDist = sqrt(
          pow(childPos.dx - anchorPos.dx, 2) +
              pow(childPos.dy - anchorPos.dy, 2),
        );
        expect(childDist, greaterThan(0),
            reason: 'Child must not sit on top of the anchor');

        // Orphans must NOT sit on top of the anchor — they go to the
        // peripheral ring (maxHop + 1 = 2). They should be at the
        // same radial distance as ring 2, which is strictly greater
        // than ring 1's distance.
        final ring1Radius = childDist;
        for (final orphanId in ['orphan1', 'orphan2', 'orphan3']) {
          final orphanPos = result.positions[orphanId]!;
          final orphanDist = sqrt(
            pow(orphanPos.dx - anchorPos.dx, 2) +
                pow(orphanPos.dy - anchorPos.dy, 2),
          );
          expect(orphanDist, greaterThan(ring1Radius),
              reason: '$orphanId must sit on the peripheral ring (radius '
                  '> ring 1), not on ring 0. Got radius $orphanDist, '
                  'ring 1 = $ring1Radius.');
        }

        // No two orphans may share the same coordinates (they must be
        // spread evenly across the peripheral ring's arc).
        final orphanPositions = [
          result.positions['orphan1']!,
          result.positions['orphan2']!,
          result.positions['orphan3']!,
        ];
        for (var i = 0; i < orphanPositions.length; i++) {
          for (var j = i + 1; j < orphanPositions.length; j++) {
            expect(
              orphanPositions[i],
              isNot(equals(orphanPositions[j])),
              reason: 'Two unreachable nodes must not share the same '
                  'coordinates — pile-up regression',
            );
          }
        }
      });

      test('an unreachable node is placed in the lower semicircle '
          '(positive peripheral ring)', () {
        // Single anchor + single orphan (no edges).
        // peripheralRing = 0 + 1 = 1. Orphan goes to ring 1, lower
        // semicircle (Y > anchor Y).
        final persons = [
          _person('anchor', isAnchor: true),
          _person('orphan'),
        ];
        final result =
            layout.compute(persons: persons, relationships: const []);

        final anchorY = result.positions['anchor']!.dy;
        final orphanY = result.positions['orphan']!.dy;

        expect(orphanY, greaterThan(anchorY),
            reason: 'Unreachable orphan must sit in the lower semicircle '
                '(positive peripheral ring), not on top of the anchor.');
      });

      test('reachable nodes are unaffected by the peripheral-ring change',
          () {
        // The original _smallFamily fixture: anchor + father + mother +
        // child. Everyone is reachable. PeripherhalRing=2 (maxHop=1, +1)
        // but no node should land there.
        final fam = _smallFamily();
        final result = layout.compute(persons: fam.persons, relationships: fam.rels);

        // Re-check the original invariants still hold.
        expect(result.positions.length, fam.persons.length);

        final anchorY = result.positions['anchor']!.dy;
        expect(result.positions['father']!.dy, lessThan(anchorY));
        expect(result.positions['mother']!.dy, lessThan(anchorY));
        expect(result.positions['child']!.dy, greaterThan(anchorY));

        // Ring radii unchanged: 0 for ring 0, equal positive value for
        // ring -1 and ring 1, and ring 2 should NOT exist in this case
        // (no unreachable nodes).
        expect(result.ringRadii[0], 0.0);
        expect(result.ringRadii[-1], greaterThan(0));
        expect(result.ringRadii[1], greaterThan(0));
        expect(result.ringRadii[-1], closeTo(result.ringRadii[1]!, 1e-9));
        expect(result.ringRadii.containsKey(2), isFalse,
            reason: 'Peripheral ring (2) must not exist when every node '
                'is reachable — it only materializes when an unreachable '
                'node is present.');
      });
    });
  });
}
