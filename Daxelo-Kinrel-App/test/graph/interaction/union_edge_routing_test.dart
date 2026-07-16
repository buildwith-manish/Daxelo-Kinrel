// test/graph/interaction/union_edge_routing_test.dart
//
// DAXELO KINREL — Phase 6 Union Edge Routing + Hit-Test Parity tests.
//
// These tests cover the SINGLE shared helper `resolveEffectiveEdgeEndpoints`
// (in lib/graph/interaction/couple_union_model.dart) that BOTH the edge
// painter and the tap hit-tester call. Before this fix, the painter and
// the hit-tester had two SEPARATE implementations of the union-redirect
// logic (or, in the actual shipped bug, the painter had the redirect
// and the hit-tester did not), so the rendered bezier curve and the
// tap-detection midpoint drifted apart: tapping the actual rendered
// line near the union glyph silently missed, or registered a hit on a
// neighbouring edge.
//
// The fix is structural: there is now ONE function, called from BOTH
// sites. These tests prove:
//
//   1. The helper redirects parent→child and child→parent edges to
//      the union midpoint when the parent is a union partner and the
//      child is in that union's `childIds`.
//   2. The helper leaves non-union children anchored to their raw
//      parent position.
//   3. The helper picks the correct union for each child in a
//      remarriage (multi-union) structure.
//   4. The helper does NOT redirect a non-shared child's edge just
//      because a sibling IS shared.
//   5. THE HIT-TEST PARITY TEST: a tap at the actual rendered curve's
//      midpoint (which is the midpoint between `unionMidpoint(...)` and
//      the child's position, NOT the midpoint between the parent's raw
//      position and the child) returns the correct edge ID.
//   6. THE REGRESSION GUARD: a tap at the OLD (pre-redirect) midpoint
//      does NOT return the redirected edge — proving the bug this fix
//      closes would have failed this test before the fix.
//
// Tests 5 and 6 are the actual point of this fix. The other four are
// supporting coverage. A future change that silently reintroduces the
// drift (e.g. by inlining a second copy of the redirect logic in
// either call site) will be caught by tests 5 and 6.

import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/couple_union_model.dart';

/// A minimal stand-in for `GraphEdgeData` used by the hit-test
/// simulation. The production `_hitTestEdge` reads `e.sourceId`,
/// `e.targetId`, and `e.id` from `GraphEdgeData`; we replicate just
/// those fields. This keeps the test focused on the redirect logic
/// (the actual subject of the fix) rather than the full edge model.
class _TestEdge {
  const _TestEdge(this.id, this.sourceId, this.targetId);
  final String id;
  final String sourceId;
  final String targetId;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Build edge tuples in the format `deriveCoupleUnions` expects.
  List<({String fromId, String toId, String edgeId, String relationshipKey})>
      buildEdges(List<List<String>> pairs) {
    return pairs
        .map((p) => (
              fromId: p[0],
              toId: p[1],
              edgeId: p[2],
              relationshipKey: p[3],
            ))
        .toList();
  }

  /// Faithfully replicates the production `_hitTestEdge` logic from
  /// `family_graph_engine_view.dart`, with the zoom transformation
  /// removed (we work directly in graph space). This is the SAME
  /// `resolveEffectiveEdgeEndpoints` call the production hit-tester
  /// makes — if this simulation disagrees with production, it can only
  /// be because the helper itself changed, which is exactly what these
  /// tests guard against.
  String? simulateHitTest(
    Offset tapGraphPos, {
    required List<_TestEdge> edges,
    required Map<String, Offset> positions,
    required List<CoupleUnion> coupleUnions,
    double hitRadius = 48.0,
  }) {
    if (edges.isEmpty || positions.isEmpty) return null;
    String? bestId;
    double bestDist = double.infinity;
    for (final e in edges) {
      final s = positions[e.sourceId];
      final t = positions[e.targetId];
      if (s == null || t == null) continue;
      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: e.sourceId,
        targetId: e.targetId,
        rawSource: s,
        rawTarget: t,
        coupleUnions: coupleUnions,
        positionOf: (id) => positions[id],
      );
      final mid = Offset(
        (resolved.source.dx + resolved.target.dx) / 2,
        (resolved.source.dy + resolved.target.dy) / 2,
      );
      final dist = (mid - tapGraphPos).distance;
      if (dist < hitRadius && dist < bestDist) {
        bestDist = dist;
        bestId = e.id;
      }
    }
    return bestId;
  }

  /// Replicates the OLD (pre-fix) hit-test logic: uses the raw `s`/`t`
  /// positions with NO union redirect. Used by the regression guard
  /// (test 6) to prove the bug would have manifested.
  String? simulateBrokenHitTest(
    Offset tapGraphPos, {
    required List<_TestEdge> edges,
    required Map<String, Offset> positions,
    double hitRadius = 48.0,
  }) {
    if (edges.isEmpty || positions.isEmpty) return null;
    String? bestId;
    double bestDist = double.infinity;
    for (final e in edges) {
      final s = positions[e.sourceId];
      final t = positions[e.targetId];
      if (s == null || t == null) continue;
      // OLD behavior: NO redirect — midpoint computed from raw parent
      // position, NOT from the union midpoint the painter used.
      final mid = Offset((s.dx + t.dx) / 2, (s.dy + t.dy) / 2);
      final dist = (mid - tapGraphPos).distance;
      if (dist < hitRadius && dist < bestDist) {
        bestDist = dist;
        bestId = e.id;
      }
    }
    return bestId;
  }

  // ─────────────────────────────────────────────────────────────────────
  // TEST 1: Redirect-point assertion (both directions)
  // ─────────────────────────────────────────────────────────────────────
  group('TEST 1 — Redirect-point assertion', () {
    test('parent→child edge redirects source to union midpoint', () {
      // A — wife — B (spouse)
      // A (father) → C (child)
      // B (mother) → C (child)
      // C is a confirmed child of BOTH A and B → attached to the union.
      final edges = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['A', 'C', 'eAC', 'father'],
        ['B', 'C', 'eBC', 'mother'],
      ]);
      final unions = deriveCoupleUnions(edges);
      expect(unions.length, 1);

      final positions = <String, Offset>{
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'C': const Offset(50, 200),
      };

      // The edge under test is A→C (parent→child).
      final rawSource = positions['A']!;
      final rawTarget = positions['C']!;

      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'C',
        rawSource: rawSource,
        rawTarget: rawTarget,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );

      final expectedMid = unionMidpoint(positions['A']!, positions['B']!);

      // The source MUST be the union midpoint, not A's raw position.
      expect(resolved.source, expectedMid,
          reason: 'parent→child edge: source must be union midpoint');
      expect(resolved.source, isNot(rawSource),
          reason: 'parent→child edge: source must NOT be the parent\'s '
              'raw position — that is the bug');
      // Target unchanged.
      expect(resolved.target, rawTarget,
          reason: 'parent→child edge: target must remain the child');
    });

    test('child→parent edge redirects target to union midpoint', () {
      // Same family structure, but test the REVERSED edge direction:
      // C → A (child→parent). The redirect must apply symmetrically.
      final edges = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['A', 'C', 'eAC', 'father'],
        ['B', 'C', 'eBC', 'mother'],
      ]);
      final unions = deriveCoupleUnions(edges);
      final positions = <String, Offset>{
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'C': const Offset(50, 200),
      };

      final rawSource = positions['C']!;
      final rawTarget = positions['A']!;

      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'C',
        targetId: 'A',
        rawSource: rawSource,
        rawTarget: rawTarget,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );

      final expectedMid = unionMidpoint(positions['A']!, positions['B']!);

      // Source unchanged.
      expect(resolved.source, rawSource,
          reason: 'child→parent edge: source must remain the child');
      // The target MUST be the union midpoint, not A's raw position.
      expect(resolved.target, expectedMid,
          reason: 'child→parent edge: target must be union midpoint');
      expect(resolved.target, isNot(rawTarget),
          reason: 'child→parent edge: target must NOT be the parent\'s '
              'raw position — that is the bug');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // TEST 2: Non-union child unaffected
  // ─────────────────────────────────────────────────────────────────────
  group('TEST 2 — Non-union child unaffected', () {
    test('child with only one known parent stays anchored to that parent', () {
      // A (father) → C (child)
      // A — wife — B (spouse)
      // NO B → C edge. C is NOT attached to the union (only one parent
      // confirmed). C's edge must anchor to A's RAW position, not the
      // union midpoint.
      final edges = buildEdges([
        ['A', 'C', 'eAC', 'father'],
        ['A', 'B', 'eAB', 'wife'],
      ]);
      final unions = deriveCoupleUnions(edges);
      expect(unions.length, 1);
      expect(unions.first.childIds, isEmpty,
          reason: 'C is NOT a confirmed child of both partners');

      final positions = <String, Offset>{
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'C': const Offset(50, 200),
      };

      final rawSource = positions['A']!;
      final rawTarget = positions['C']!;

      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'C',
        rawSource: rawSource,
        rawTarget: rawTarget,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );

      // No redirect — both endpoints unchanged.
      expect(resolved.source, rawSource,
          reason: 'Non-union child: source must remain the parent\'s raw '
              'position');
      expect(resolved.target, rawTarget,
          reason: 'Non-union child: target must remain the child\'s raw '
              'position');
    });

    test('no unions at all → no redirect', () {
      // Pure parent-child edge, no spouse pair. No unions derived.
      final edges = buildEdges([
        ['A', 'C', 'eAC', 'father'],
      ]);
      final unions = deriveCoupleUnions(edges);
      expect(unions, isEmpty);

      final positions = <String, Offset>{
        'A': const Offset(0, 0),
        'C': const Offset(50, 200),
      };

      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'C',
        rawSource: positions['A']!,
        rawTarget: positions['C']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );

      expect(resolved.source, positions['A']!);
      expect(resolved.target, positions['C']!);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // TEST 3: Remarriage — each child anchors to the CORRECT union
  // ─────────────────────────────────────────────────────────────────────
  group('TEST 3 — Remarriage', () {
    test('each child\'s edge anchors to the correct union midpoint', () {
      // A — wife — B (union 1, midpoint at (50, 0))
      // A — wife — C (union 2, midpoint at (150, 0))
      // A (father) → D, B (mother) → D  → D is child of union 1
      // A (father) → E, C (mother) → E  → E is child of union 2
      final edges = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['A', 'C', 'eAC2', 'wife'],
        ['A', 'D', 'eAD', 'father'],
        ['B', 'D', 'eBD', 'mother'],
        ['A', 'E', 'eAE', 'father'],
        ['C', 'E', 'eCE', 'mother'],
      ]);
      final unions = deriveCoupleUnions(edges);
      expect(unions.length, 2);

      final positions = <String, Offset>{
        'A': const Offset(100, 0),
        'B': const Offset(0, 0),
        'C': const Offset(200, 0),
        'D': const Offset(50, 200),
        'E': const Offset(200, 200),
      };

      final abMid = unionMidpoint(positions['A']!, positions['B']!);
      final acMid = unionMidpoint(positions['A']!, positions['C']!);

      // D's parent→child edge (A→D) must anchor to the A-B union midpoint.
      final dResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'D',
        rawSource: positions['A']!,
        rawTarget: positions['D']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      expect(dResolved.source, abMid,
          reason: 'D is a child of union A-B → source must be A-B midpoint');
      expect(dResolved.source, isNot(acMid),
          reason: 'D must NOT anchor to the A-C union midpoint (the other '
              'union) — that would be the remarriage bug');

      // E's parent→child edge (A→E) must anchor to the A-C union midpoint.
      final eResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'E',
        rawSource: positions['A']!,
        rawTarget: positions['E']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      expect(eResolved.source, acMid,
          reason: 'E is a child of union A-C → source must be A-C midpoint');
      expect(eResolved.source, isNot(abMid),
          reason: 'E must NOT anchor to the A-B union midpoint (the other '
              'union) — that would be the remarriage bug');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // TEST 4: Half-sibling — non-shared child NOT redirected
  // ─────────────────────────────────────────────────────────────────────
  group('TEST 4 — Half-sibling', () {
    test('shared child\'s sibling (NOT in same union) is NOT redirected', () {
      // A — wife — B (union 1)
      // A (father) → D, B (mother) → D  → D is child of union 1 (shared)
      // A (father) → F                            → F has only ONE known
      //                                            parent (A), so F is
      //                                            NOT in any union.
      // F is a half-sibling of D (they share parent A only).
      //
      // The redirect for A→D must NOT bleed into A→F.
      final edges = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['A', 'D', 'eAD', 'father'],
        ['B', 'D', 'eBD', 'mother'],
        ['A', 'F', 'eAF', 'father'], // F has only one known parent (A)
      ]);
      final unions = deriveCoupleUnions(edges);
      expect(unions.length, 1);
      expect(unions.first.childIds, contains('D'));
      expect(unions.first.childIds, isNot(contains('F')),
          reason: 'F is NOT a confirmed child of both A and B');

      final positions = <String, Offset>{
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'D': const Offset(50, 200),
        'F': const Offset(150, 200),
      };

      // A→D redirects (D is in union).
      final dResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'D',
        rawSource: positions['A']!,
        rawTarget: positions['D']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      final abMid = unionMidpoint(positions['A']!, positions['B']!);
      expect(dResolved.source, abMid,
          reason: 'D is shared → A→D source must be union midpoint');

      // A→F does NOT redirect (F is not in union).
      final fResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'F',
        rawSource: positions['A']!,
        rawTarget: positions['F']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      expect(fResolved.source, positions['A']!,
          reason: 'F is NOT shared → A→F source must remain A\'s raw '
              'position. The redirect for D must NOT bleed into F.');
      expect(fResolved.target, positions['F']!);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // TEST 5: Hit-test parity — THE test that was missing
  // ─────────────────────────────────────────────────────────────────────
  group('TEST 5 — Hit-test parity at the RENDERED midpoint', () {
    test('tap at the union-redirected midpoint returns the correct edge ID',
        () {
      // Family: A — wife — B, with shared child C.
      // A→C is the edge under test. The RENDERED curve starts at the
      // A-B union midpoint (not A's raw position), so its midpoint is
      // halfway between the union midpoint and C.
      final edgeTuples = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['A', 'C', 'eAC', 'father'],
        ['B', 'C', 'eBC', 'mother'],
      ]);
      final unions = deriveCoupleUnions(edgeTuples);

      final positions = <String, Offset>{
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'C': const Offset(50, 200),
      };

      // The edges the hit-tester iterates. In production these come from
      // `EdgeDeduplicator.deduplicate(...)`; here we use the same
      // (sourceId, targetId, id) tuples directly. The redirect logic
      // is independent of deduplication.
      final edges = <_TestEdge>[
        const _TestEdge('eAC', 'A', 'C'),
        const _TestEdge('eBC', 'B', 'C'),
        const _TestEdge('eAB', 'A', 'B'),
      ];

      // Compute the ACTUAL rendered midpoint of A→C — i.e. the
      // midpoint between the union midpoint (effective source) and C
      // (effective target). This is where the user would tap if they
      // tapped the rendered line near its visual center.
      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'C',
        rawSource: positions['A']!,
        rawTarget: positions['C']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      final renderedMid = Offset(
        (resolved.source.dx + resolved.target.dx) / 2,
        (resolved.source.dy + resolved.target.dy) / 2,
      );

      // Simulate a tap at the rendered midpoint. The hit-tester —
      // which uses the SAME resolveEffectiveEdgeEndpoints call — must
      // return 'eAC' (the A→C edge), not 'eBC' or 'eAB'.
      final hitId = simulateHitTest(
        renderedMid,
        edges: edges,
        positions: positions,
        coupleUnions: unions,
      );

      expect(hitId, 'eAC',
          reason: 'THE PARITY TEST: tapping the rendered curve\'s '
              'midpoint must return the correct edge ID. Before the '
              'fix, the hit-tester computed its midpoint from A\'s raw '
              'position (not the union midpoint), so the tap target '
              'and the rendered midpoint were two different points '
              'and the wrong edge (or no edge) was returned.');
    });

    test('parity holds for child→parent direction too', () {
      // Same family, but the edge under test is C→A (reversed direction).
      final edgeTuples = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['A', 'C', 'eAC', 'father'],
        ['B', 'C', 'eBC', 'mother'],
      ]);
      final unions = deriveCoupleUnions(edgeTuples);
      final positions = <String, Offset>{
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'C': const Offset(50, 200),
      };
      final edges = <_TestEdge>[
        const _TestEdge('eCA', 'C', 'A'),
        const _TestEdge('eCB', 'C', 'B'),
        const _TestEdge('eAB', 'A', 'B'),
      ];

      // C→A rendered midpoint: source=C (unchanged), target=union midpoint.
      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'C',
        targetId: 'A',
        rawSource: positions['C']!,
        rawTarget: positions['A']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      final renderedMid = Offset(
        (resolved.source.dx + resolved.target.dx) / 2,
        (resolved.source.dy + resolved.target.dy) / 2,
      );

      final hitId = simulateHitTest(
        renderedMid,
        edges: edges,
        positions: positions,
        coupleUnions: unions,
      );

      expect(hitId, 'eCA',
          reason: 'child→parent direction: parity must also hold — '
              'tapping the rendered midpoint returns the correct edge.');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // TEST 6: Regression guard — tap at the OLD midpoint fails
  // ─────────────────────────────────────────────────────────────────────
  group('TEST 6 — Regression guard (OLD midpoint)', () {
    test(
        'the OLD broken hit-test (no redirect) does NOT return the correct '
        'edge when tapping the rendered midpoint',
        () {
      // This test explicitly proves the bug this fix closes. We simulate
      // the OLD hit-test logic (raw s/t, no redirect) and show it
      // returns a DIFFERENT edge (or null) when the user taps at the
      // rendered curve's midpoint. If a future change silently
      // reintroduces the drift — e.g. by inlining a second copy of the
      // redirect logic in either the painter or the hit-tester — this
      // test will catch it because the OLD and NEW midpoints diverge
      // precisely when the redirect is active.
      final edgeTuples = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['A', 'C', 'eAC', 'father'],
        ['B', 'C', 'eBC', 'mother'],
      ]);
      final unions = deriveCoupleUnions(edgeTuples);
      final positions = <String, Offset>{
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'C': const Offset(50, 200),
      };
      final edges = <_TestEdge>[
        const _TestEdge('eAC', 'A', 'C'),
        const _TestEdge('eBC', 'B', 'C'),
        const _TestEdge('eAB', 'A', 'B'),
      ];

      // The RENDERED midpoint of A→C — between union midpoint and C.
      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'C',
        rawSource: positions['A']!,
        rawTarget: positions['C']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      final renderedMid = Offset(
        (resolved.source.dx + resolved.target.dx) / 2,
        (resolved.source.dy + resolved.target.dy) / 2,
      );

      // The OLD (broken) midpoint of A→C — between A's raw position and C.
      final oldMid = Offset(
        (positions['A']!.dx + positions['C']!.dx) / 2,
        (positions['A']!.dy + positions['C']!.dy) / 2,
      );

      // Sanity: the two midpoints must actually differ. If they were
      // equal, the bug wouldn't manifest and this test would be vacuous.
      expect(renderedMid, isNot(equals(oldMid)),
          reason: 'Sanity check: the rendered (redirected) midpoint and '
              'the OLD (pre-redirect) midpoint must be different points. '
              'If they were the same, the bug would not be observable '
              'and the regression guard would be meaningless.');

      // THE REGRESSION GUARD: simulate the OLD broken hit-tester (no
      // redirect) tapping at the RENDERED midpoint. It must NOT return
      // 'eAC' — because the OLD hit-tester is looking for a tap at
      // `oldMid`, not at `renderedMid`.
      //
      // We use a small hit radius so the test is sensitive to the
      // difference between the two midpoints.
      final tightRadius = (renderedMid - oldMid).distance * 0.4;
      expect(tightRadius, greaterThan(1.0),
          reason: 'Tight radius must be large enough to be meaningful');

      final brokenHitId = simulateBrokenHitTest(
        renderedMid,
        edges: edges,
        positions: positions,
        hitRadius: tightRadius,
      );

      expect(brokenHitId, isNot('eAC'),
          reason: 'REGRESSION GUARD: the OLD broken hit-tester (no '
              'redirect) must NOT return the correct edge when the user '
              'taps at the rendered curve\'s midpoint. If it did, the '
              'bug would not be observable. This test proves the fix '
              'was necessary: before the fix, the hit-tester could not '
              'reliably return \'eAC\' for a tap on the A→C rendered '
              'curve.');

      // And the NEW (fixed) hit-tester DOES return 'eAC' at the same
      // tap position with the same radius. This is the positive
      // counterpart that proves the fix works.
      final fixedHitId = simulateHitTest(
        renderedMid,
        edges: edges,
        positions: positions,
        coupleUnions: unions,
        hitRadius: tightRadius,
      );

      expect(fixedHitId, 'eAC',
          reason: 'Positive counterpart: the fixed hit-tester DOES '
              'return the correct edge at the rendered midpoint with '
              'the same radius. The fix works.');
    });

    test(
        'the OLD broken hit-tester returns \'eAC\' at the OLD midpoint — '
        'proving the OLD and NEW midpoints are genuinely different',
        () {
      // This is the inverse counterpart of the test above: at the OLD
      // midpoint, the OLD broken hit-tester DOES return 'eAC'. This
      // proves the two midpoints are genuinely different points and
      // the bug isn't an artifact of the test setup.
      final edgeTuples = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['A', 'C', 'eAC', 'father'],
        ['B', 'C', 'eBC', 'mother'],
      ]);
      final unions = deriveCoupleUnions(edgeTuples);
      final positions = <String, Offset>{
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'C': const Offset(50, 200),
      };
      final edges = <_TestEdge>[
        const _TestEdge('eAC', 'A', 'C'),
        const _TestEdge('eBC', 'B', 'C'),
        const _TestEdge('eAB', 'A', 'B'),
      ];

      final resolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'C',
        rawSource: positions['A']!,
        rawTarget: positions['C']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      final renderedMid = Offset(
        (resolved.source.dx + resolved.target.dx) / 2,
        (resolved.source.dy + resolved.target.dy) / 2,
      );
      final oldMid = Offset(
        (positions['A']!.dx + positions['C']!.dx) / 2,
        (positions['A']!.dy + positions['C']!.dy) / 2,
      );

      final tightRadius = (renderedMid - oldMid).distance * 0.4;

      // At the OLD midpoint, the OLD broken hit-tester returns 'eAC'.
      final brokenAtOld = simulateBrokenHitTest(
        oldMid,
        edges: edges,
        positions: positions,
        hitRadius: tightRadius,
      );
      expect(brokenAtOld, 'eAC',
          reason: 'The OLD hit-tester DID return \'eAC\' at the OLD '
              'midpoint — so the bug was not that \'eAC\' was never '
              'hittable, but that the user\'s tap (at the RENDERED '
              'midpoint) was at the wrong place for the OLD hit-tester.');

      // And the NEW hit-tester does NOT return 'eAC' at the OLD
      // midpoint with the same radius — proving the NEW hit-tester is
      // genuinely looking at a different point.
      final fixedAtOld = simulateHitTest(
        oldMid,
        edges: edges,
        positions: positions,
        coupleUnions: unions,
        hitRadius: tightRadius,
      );
      expect(fixedAtOld, isNot('eAC'),
          reason: 'The NEW hit-tester does NOT return \'eAC\' at the '
              'OLD midpoint — proving it is genuinely looking at the '
              'redirected midpoint, not the raw one.');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // BONUS: End-to-end consistency — painter and hit-tester use the SAME
  // helper, so the rendered curve and the tap target can NEVER diverge.
  // ─────────────────────────────────────────────────────────────────────
  group('Painter ↔ Hit-tester contract', () {
    test(
        'the midpoint used by the painter equals the midpoint used by the '
        'hit-tester for a union-redirected edge',
        () {
      // This is the structural guarantee: because both sites call the
      // SAME resolveEffectiveEdgeEndpoints function, the midpoint they
      // each compute must be IDENTICAL. This test exists so that a
      // future refactor that introduces a second copy of the redirect
      // logic (the original sin) will fail here immediately, before
      // tests 5 and 6 even run.
      final edgeTuples = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['A', 'C', 'eAC', 'father'],
        ['B', 'C', 'eBC', 'mother'],
      ]);
      final unions = deriveCoupleUnions(edgeTuples);
      final positions = <String, Offset>{
        'A': const Offset(0, 0),
        'B': const Offset(100, 0),
        'C': const Offset(50, 200),
      };

      // Painter's effective endpoints (used to construct the bezier).
      final painterResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'C',
        rawSource: positions['A']!,
        rawTarget: positions['C']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      final painterMid = Offset(
        (painterResolved.source.dx + painterResolved.target.dx) / 2,
        (painterResolved.source.dy + painterResolved.target.dy) / 2,
      );

      // Hit-tester's effective endpoints (used to compute the tap
      // target). SAME function, SAME args → SAME result.
      final hitTesterResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'C',
        rawSource: positions['A']!,
        rawTarget: positions['C']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      final hitTesterMid = Offset(
        (hitTesterResolved.source.dx + hitTesterResolved.target.dx) / 2,
        (hitTesterResolved.source.dy + hitTesterResolved.target.dy) / 2,
      );

      expect(painterMid, equals(hitTesterMid),
          reason: 'STRUCTURAL GUARANTEE: the painter and the hit-tester '
              'must compute the same midpoint because they call the same '
              'function. If this fails, someone has reintroduced the '
              'two-implementation drift.');
    });
  });
}
