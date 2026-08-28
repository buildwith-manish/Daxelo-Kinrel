// test/graph/rendering/anchor_edge_bow_test.dart
//
// v5.125 (Step 6) — Anchor-knot edge geometry tests.
//
// With force-relaxation off, the ring layout is clean, but two visual
// problems remained around the anchor:
//   1. Ring-spanning chords (endpoints > 2 rings apart) drawn as
//      near-straight lines cut straight through the anchor knot.
//   2. Multiple anchor edges pointing into the same angular sector
//      overlapped into a single visual band.
//
// These tests verify the GEOMETRY fixes through the painter's PUBLIC
// static API (the same functions the paint loop AND the canvas
// hit-tester call — so passing these tests also proves marker/tap-target
// parity):
//   • EngineEdgePainter.computeVisualMidpoint — visual midpoint of the
//     rendered bezier (with and without the anchor bow engaged).
//   • EngineEdgePainter.computeAnchorSectorFanOuts — per-edge fan-out
//     offsets for anchor-incident edges in shared angular sectors.
//
// Edge colours / category-to-color mapping are NOT touched by Step 6 —
// geometry only — so no colour assertions are needed.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinrel/graph/widgets/engine/engine_edge_painter.dart';
import 'package:kinrel/graph/engine/edge_dedup.dart' show DedupedEdge;
import 'package:kinrel/graph/data/graph_data_models.dart'
    show GraphEdgeData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Layout geometry matching RadialLayout's standard config:
  //   ring 1 radius = 180 + 1×200 = 380, ring 2 = 580, ring 4 = 980.
  const Offset anchor = Offset(1000, 1000);
  Offset onRing(double radius, double angleDeg) => anchor +
      Offset(
        radius * math.cos(angleDeg * math.pi / 180),
        radius * math.sin(angleDeg * math.pi / 180),
      );

  group('v5.125 (Step 6) — bow around the anchor', () {
    /// Perpendicular distance of [p] from the infinite line (s → t) —
    /// measures how far a curve's midpoint bows off the straight chord.
    double perpDistFromChord(Offset s, Offset t, Offset p) {
      final d = t - s;
      final cross =
          (p.dx - s.dx) * d.dy - (p.dy - s.dy) * d.dx;
      return cross.abs() / d.distance;
    }

    test('a ring-spanning chord passing near the anchor bows AWAY from '
        'it (midpoint displaced outward)', () {
      // Ring-1 node at 200° and ring-4 node at 20° — roughly opposite
      // sides of the anchor, so the straight chord passes essentially
      // THROUGH the anchor. Radial gap 600 > kAnchorBowRingGap (400).
      final s = onRing(380, 200);
      final t = onRing(980, 20);

      final baselineMid = EngineEdgePainter.computeVisualMidpoint(s, t);
      final bowedMid =
          EngineEdgePainter.computeVisualMidpoint(s, t, anchorCenter: anchor);

      // 1. The bowed curve deviates from the straight chord far more
      //    than the default curve does (the bow is unmistakable).
      final baselinePerp = perpDistFromChord(s, t, baselineMid);
      final bowedPerp = perpDistFromChord(s, t, bowedMid);
      expect(bowedPerp, greaterThan(baselinePerp + 50),
          reason: 'The chord must visibly bow AROUND the anchor, not '
              'cut through it. baseline perp=$baselinePerp, '
              'bowed perp=$bowedPerp');

      // 2. The displacement points AWAY from the anchor (the curve
      //    pushes outward, not inward).
      final displacement = bowedMid - baselineMid;
      final outward = baselineMid - anchor;
      expect(displacement.dx * outward.dx + displacement.dy * outward.dy,
          greaterThan(0),
          reason: 'The bow must push the curve away from the anchor');

      // 3. The bowed midpoint is farther from the anchor than the
      //    default curve's midpoint.
      expect((bowedMid - anchor).distance,
          greaterThan((baselineMid - anchor).distance));
    });

    test('the bow scales with how close the line passes to the center — '
        'a chord with more clearance bows less', () {
      // Two chords with the same ring span (gap 600 > 400), both
      // passing within the 300px influence radius, but at different
      // clearances: a 160° angular spread (clearance ≈ 95px) vs a
      // 140° spread (clearance ≈ 185px).
      final nearS = onRing(380, 170);
      final nearT = onRing(980, 10);
      final farS = onRing(380, 170);
      final farT = onRing(980, 30);

      double bowBeyondBaseline(Offset s, Offset t) {
        final base = EngineEdgePainter.computeVisualMidpoint(s, t);
        final bowed =
            EngineEdgePainter.computeVisualMidpoint(s, t, anchorCenter: anchor);
        return perpDistFromChord(s, t, bowed) -
            perpDistFromChord(s, t, base);
      }

      final nearBow = bowBeyondBaseline(nearS, nearT);
      final farBow = bowBeyondBaseline(farS, farT);

      expect(nearBow, greaterThan(0));
      expect(farBow, greaterThan(0));
      // The closer-to-center chord bows more — the offset is scaled by
      // how close the line would otherwise pass to the anchor.
      expect(nearBow, greaterThan(farBow),
          reason: 'Bow magnitude must scale with center proximity: '
              'near=$nearBow, far=$farBow');
    });

    test('adjacent-ring edges (≤2 rings apart) keep the default curve',
        () {
      // Ring 1 (380) ↔ ring 2 (580): radial gap 200 ≤ 400 → no bow,
      // even though the chord passes near the anchor.
      final s = onRing(380, 200);
      final t = onRing(580, 20);

      final baselineMid = EngineEdgePainter.computeVisualMidpoint(s, t);
      final bowedMid =
          EngineEdgePainter.computeVisualMidpoint(s, t, anchorCenter: anchor);

      expect(bowedMid, baselineMid,
          reason: 'Edges that do not skip intermediate rings must keep '
              'the exact pre-Step-6 geometry');
    });

    test('a ring-spanning chord that passes FAR from the anchor keeps '
        'the default curve', () {
      // Ring 1 ↔ ring 4 on the SAME side of the anchor: the connecting
      // line stays well outside the 300px influence radius.
      final s = onRing(380, 80);
      final t = onRing(980, 100);

      final baselineMid = EngineEdgePainter.computeVisualMidpoint(s, t);
      final bowedMid =
          EngineEdgePainter.computeVisualMidpoint(s, t, anchorCenter: anchor);

      expect(bowedMid, baselineMid,
          reason: 'Chords that pass far from the anchor must not bow');
    });

    test('anchor-incident edges (an endpoint AT the anchor) keep the '
        'default curve — they fan out instead', () {
      // An edge from the anchor itself out to ring 3. It radiates from
      // the anchor; the bow is reserved for chords that CUT THROUGH it.
      final t = onRing(780, 45);

      final baselineMid = EngineEdgePainter.computeVisualMidpoint(anchor, t);
      final bowedMid = EngineEdgePainter.computeVisualMidpoint(anchor, t,
          anchorCenter: anchor);

      expect(bowedMid, baselineMid,
          reason: 'Anchor-incident edges are handled by the sector '
              'fan-out, not the bow');
    });

    test('a user-dragged midpoint (waypointDelta) ignores the anchor bow',
        () {
      final s = onRing(380, 200);
      final t = onRing(980, 20);
      const dragDelta = Offset(-40.0, 60.0);

      final withoutAnchor = EngineEdgePainter.computeVisualMidpoint(
        s, t,
        waypointDelta: dragDelta,
      );
      final withAnchor = EngineEdgePainter.computeVisualMidpoint(
        s, t,
        waypointDelta: dragDelta,
        anchorCenter: anchor,
      );

      expect(withAnchor, withoutAnchor,
          reason: 'A user-placed midpoint always wins over automatic '
              'routing (v5.62 contract)');
    });
  });

  group('v5.125 (Step 6) — anchor-sector fan-out', () {
    DedupedEdge anchorEdge(String id, String otherId) => DedupedEdge(
          edge: GraphEdgeData(
            id: id,
            sourceId: 'anchor',
            targetId: otherId,
            relationshipKey: 'child',
          ),
          lateralOffset: 0.0,
          parallelCount: 1,
        );

    test('edges to nodes in the same 30° sector fan out; other sectors '
        'stay at 0', () {
      final positions = <String, Offset>{
        'anchor': anchor,
        // Same sector (≈10–20°).
        'b1': onRing(380, 10),
        'b2': onRing(580, 15),
        'b3': onRing(980, 20),
        // Opposite sector.
        'c1': onRing(380, 180),
      };

      final fanOuts = EngineEdgePainter.computeAnchorSectorFanOuts(
        edges: [
          anchorEdge('e-b1', 'b1'),
          anchorEdge('e-b2', 'b2'),
          anchorEdge('e-b3', 'b3'),
          anchorEdge('e-c1', 'c1'),
        ],
        positions: positions,
        anchorId: 'anchor',
        anchorCenter: anchor,
      );

      // The 3-edge sector fans out in centred ±kAnchorFanStep steps.
      expect(fanOuts['e-b1'], -EngineEdgePainter.kAnchorFanStep);
      expect(fanOuts['e-b2'], 0.0);
      expect(fanOuts['e-b3'], EngineEdgePainter.kAnchorFanStep);
      // The singleton sector in another direction stays unshifted.
      expect(fanOuts['e-c1'], 0.0);
    });

    test('the fan-out produces visually distinct midpoints (no single '
        'overlapping band)', () {
      final positions = <String, Offset>{
        'anchor': anchor,
        'b1': onRing(380, 10),
        'b2': onRing(580, 15),
        'b3': onRing(980, 20),
      };
      final edges = [
        anchorEdge('e-b1', 'b1'),
        anchorEdge('e-b2', 'b2'),
        anchorEdge('e-b3', 'b3'),
      ];
      final fanOuts = EngineEdgePainter.computeAnchorSectorFanOuts(
        edges: edges,
        positions: positions,
        anchorId: 'anchor',
        anchorCenter: anchor,
      );

      // The midpoint of each fanned edge, computed exactly as the
      // painter + hit-tester compute it (lateralOffset = fan offset).
      final mids = <Offset>[
        for (final deduped in edges)
          EngineEdgePainter.computeVisualMidpoint(
            positions['anchor']!,
            positions[deduped.edge.targetId]!,
            lateralOffset: fanOuts[deduped.edge.id] ?? 0.0,
            anchorCenter: anchor,
          ),
      ];

      // Pairwise distinct — the three curves no longer collapse into
      // one visual band.
      for (var i = 0; i < mids.length; i++) {
        for (var j = i + 1; j < mids.length; j++) {
          expect((mids[i] - mids[j]).distance, greaterThan(10.0),
              reason: 'Fanned midpoints $i and $j must be separated');
        }
      }
    });

    test('sectors wrap across the ±180° seam', () {
      final positions = <String, Offset>{
        'anchor': anchor,
        // -175° and +175° are only 10° apart ACROSS the seam.
        'w1': onRing(380, -175),
        'w2': onRing(580, 175),
      };

      final fanOuts = EngineEdgePainter.computeAnchorSectorFanOuts(
        edges: [
          anchorEdge('e-w1', 'w1'),
          anchorEdge('e-w2', 'w2'),
        ],
        positions: positions,
        anchorId: 'anchor',
        anchorCenter: anchor,
      );

      // Both edges belong to ONE 2-edge sector. Adjacent edges in a
      // sector are exactly one fan step (12px) apart — for a 2-edge
      // sector that means symmetric ±6 offsets (never both 0, which
      // was the pre-fix overlapping band).
      final w1Fan = fanOuts['e-w1']!;
      final w2Fan = fanOuts['e-w2']!;
      expect((w2Fan - w1Fan).abs(), EngineEdgePainter.kAnchorFanStep,
          reason: 'The two seam-sector edges must be one full fan step '
              'apart (12px separation), not stacked on top of each '
              'other');
      expect(w1Fan, -w2Fan,
          reason: 'The 2-edge seam sector fans symmetrically around 0');
    });

    test('no anchor geometry → no fan-out (backward compatible)', () {
      final positions = <String, Offset>{
        'anchor': anchor,
        'b1': onRing(380, 10),
        'b2': onRing(580, 15),
      };

      final fanOuts = EngineEdgePainter.computeAnchorSectorFanOuts(
        edges: [
          anchorEdge('e-b1', 'b1'),
          anchorEdge('e-b2', 'b2'),
        ],
        positions: positions,
        anchorId: null,
        anchorCenter: null,
      );

      expect(fanOuts, isEmpty);
    });
  });
}
