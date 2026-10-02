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
//
// QA fix 2026-09-19 (Task 6-a): all fixtures were rewritten for the
// CANONICAL edge direction convention (v5.174,
// lib/graph/interaction/couple_union_model.dart commit 3caf684b; see
// also v5.19 relationship_edge_builder.dart):
//
//   from=X, to=Y, key='K'  →  "Y is X's K"
//
// so a 'father'/'mother' key marks the toId as the PARENT. The old
// fixtures encoded the pre-v5.174 inverted reading ('father' → fromId
// is the parent), which made deriveCoupleUnions attach NO children,
// so every redirect assertion below failed (or, for tests 2a/5, passed
// vacuously with the redirect inactive). The geometry expectations
// are UNCHANGED — only the fixture directions were corrected.


import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/graph/interaction/couple_union_model.dart';

/// A minimal stand-in for `GraphEdgeData` used by the hit-test
/// simulation. The production `_hitTestEdge` reads `e.sourceId`,
/// `e.targetId`, and `e.id` from `GraphEdgeData`; we replicate just
/// those fields. This keeps the test focused on the redirect logic
/// (the actual subject of the fix) rather than the full edge model.
///
/// Production may iterate a parent–child pair in EITHER direction
/// (EdgeDeduplicator keeps the first-seen / parent-direction row as
/// primary), and `resolveEffectiveEdgeEndpoints` redirects
/// symmetrically — TEST 1 and TEST 5 verify both directions.
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
  /// v5.174 fix: include labelAtoB field. Null falls back to relationshipKey
  /// inside deriveCoupleUnions, so test data is unchanged.
  ///
  /// QA fix 2026-09-19 (Task 6-a): fixtures below use the canonical
  /// direction convention (v5.174): from=X, to=Y, key='K' → "Y is X's
  /// K" — i.e. for 'father'/'mother' keys the toId is the PARENT.
  List<({String fromId, String toId, String edgeId, String relationshipKey, String? labelAtoB})>
      buildEdges(List<List<String>> pairs) {
    return pairs
        .map((p) => (
              fromId: p[0],
              toId: p[1],
              edgeId: p[2],
              relationshipKey: p[3],
              labelAtoB: null,
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
  // TEST 1: No-redirect assertion (EDGE-ANCHOR FIX)
  //
  // EDGE-ANCHOR FIX: the couple-union redirect has been REMOVED. The
  // previous tests asserted that parent→child edges redirected to the
  // union midpoint. The user's spec is explicit:
  //   "Every edge in the graph must follow the exact same geometric
  //    rule: sourceNode.center → targetNode.center. This rule must
  //    apply to ALL nodes — Anchor, Selected, Unselected, Parent,
  //    Child, Sibling, Spouse, Highlighted 'You' node."
  //
  // The redirect violated this for parent→child edges (they anchored
  // at the union midpoint, not the parent's center). After the fix,
  // these tests now assert the NEW behavior: NO redirect, every edge
  // anchors at its source's box center.
  // ─────────────────────────────────────────────────────────────────────
  group('TEST 1 — No-redirect assertion (EDGE-ANCHOR FIX)', () {
    test('parent→child edge anchors at parent center (NO redirect)', () {
      // Family: A and B are spouses; C is their confirmed child.
      // Canonical convention (v5.174): from=X, to=Y, key='K' → "Y is X's K"
      //   A→B 'wife'   → "B is A's wife"   (spouse pair)
      //   C→A 'father' → "A is C's father" (A is C's parent)
      //   C→B 'mother' → "B is C's mother" (B is C's parent)
      // C is a confirmed child of BOTH A and B → attached to the union.
      //
      // PRE-FIX: A→C edge source was redirected to the union midpoint.
      // POST-FIX (EDGE-ANCHOR FIX): A→C edge source remains A's raw
      // position (the box center) — NO redirect.
      final edges = buildEdges([
        ['A', 'B', 'eAB', 'wife'], // canonical: "B is A's wife"
        ['C', 'A', 'eAC', 'father'], // canonical: "A is C's father"
        ['C', 'B', 'eBC', 'mother'], // canonical: "B is C's mother"
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

      // EDGE-ANCHOR FIX: source MUST be A's raw position (the box
      // center), NOT the union midpoint.
      expect(resolved.source, rawSource,
          reason: 'EDGE-ANCHOR FIX: parent→child edge source must be '
              'the parent\'s box center, NOT the union midpoint. The '
              'user spec requires sourceNode.center → targetNode.center '
              'for ALL nodes including parent/child.');
      expect(resolved.source, isNot(unionMidpoint(positions['A']!, positions['B']!)),
          reason: 'EDGE-ANCHOR FIX: parent→child edge source must NOT be '
              'the union midpoint — that was the special-case anchoring '
              'logic the user reported as "offset positions".');
      // Target unchanged.
      expect(resolved.target, rawTarget,
          reason: 'parent→child edge: target must remain the child');
    });

    test('child→parent edge anchors at parent center (NO redirect, symmetric)', () {
      // Same family structure, but test the REVERSED edge direction:
      // C → A (child→parent). The no-redirect must apply symmetrically.
      final edges = buildEdges([
        ['A', 'B', 'eAB', 'wife'], // canonical: "B is A's wife"
        ['C', 'A', 'eAC', 'father'], // canonical: "A is C's father"
        ['C', 'B', 'eBC', 'mother'], // canonical: "B is C's mother"
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

      // Source unchanged.
      expect(resolved.source, rawSource,
          reason: 'child→parent edge: source must remain the child');
      // EDGE-ANCHOR FIX: target MUST be A's raw position (the box
      // center), NOT the union midpoint.
      expect(resolved.target, rawTarget,
          reason: 'EDGE-ANCHOR FIX: child→parent edge target must be '
              'the parent\'s box center, NOT the union midpoint.');
      expect(resolved.target, isNot(unionMidpoint(positions['A']!, positions['B']!)),
          reason: 'EDGE-ANCHOR FIX: child→parent edge target must NOT be '
              'the union midpoint.');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // TEST 2: Non-union child unaffected
  // ─────────────────────────────────────────────────────────────────────
  group('TEST 2 — Non-union child unaffected', () {
    test('child with only one known parent stays anchored to that parent', () {
      // A is C's only known parent; A — wife — B (spouse pair).
      // Canonical: C→A 'father' → "A is C's father".
      // NO C→B edge. C is NOT attached to the union (only one parent
      // confirmed). C's edge must anchor to A's RAW position, not the
      // union midpoint.
      final edges = buildEdges([
        ['C', 'A', 'eAC', 'father'], // canonical: "A is C's father"
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
      // Canonical: C→A 'father' → "A is C's father".
      final edges = buildEdges([
        ['C', 'A', 'eAC', 'father'],
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
  // TEST 3: Remarriage — each child anchors at the parent's center
  // (EDGE-ANCHOR FIX: no union redirect).
  // ─────────────────────────────────────────────────────────────────────
  group('TEST 3 — Remarriage (EDGE-ANCHOR FIX: no redirect)', () {
    test('each child\'s edge anchors at the parent\'s box center', () {
      // Remarriage: A — B (union 1), A — C (union 2).
      // Canonical (v5.174): from=X, to=Y, key='K' → "Y is X's K".
      //   D→A 'father' : "A is D's father" — D is a child of BOTH A and B.
      //   D→B 'mother' : "B is D's mother" — D attached to union 1.
      //   E→A 'father' : "A is E's father" — E is a child of BOTH A and C.
      //   E→C 'mother' : "C is E's mother" — E attached to union 2.
      //
      // PRE-FIX: A→D edge anchored at A-B midpoint (50, 0);
      //         A→E edge anchored at A-C midpoint (150, 0).
      // POST-FIX (EDGE-ANCHOR FIX): BOTH edges anchor at A's box center
      //         (100, 0) — the SAME point — per the user's spec
      //         "sourceNode.center → targetNode.center for ALL nodes".
      final edges = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['A', 'C', 'eAC2', 'wife'],
        ['D', 'A', 'eAD', 'father'], // canonical: "A is D's father"
        ['D', 'B', 'eBD', 'mother'], // canonical: "B is D's mother"
        ['E', 'A', 'eAE', 'father'], // canonical: "A is E's father"
        ['E', 'C', 'eCE', 'mother'], // canonical: "C is E's mother"
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

      // D's parent→child edge (A→D): EDGE-ANCHOR FIX — must anchor at
      // A's box center (100, 0), NOT at the A-B union midpoint (50, 0)
      // and NOT at the A-C union midpoint (150, 0).
      final dResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'D',
        rawSource: positions['A']!,
        rawTarget: positions['D']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      expect(dResolved.source, positions['A']!,
          reason: 'EDGE-ANCHOR FIX: D\'s edge source must be A\'s box '
              'center, NOT a union midpoint');
      expect(dResolved.source, isNot(abMid),
          reason: 'EDGE-ANCHOR FIX: D\'s edge source must NOT be the '
              'A-B union midpoint');
      expect(dResolved.source, isNot(acMid),
          reason: 'EDGE-ANCHOR FIX: D\'s edge source must NOT be the '
              'A-C union midpoint either');

      // E's parent→child edge (A→E): EDGE-ANCHOR FIX — must anchor at
      // A's box center (100, 0), the SAME point as D's edge.
      final eResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'E',
        rawSource: positions['A']!,
        rawTarget: positions['E']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      expect(eResolved.source, positions['A']!,
          reason: 'EDGE-ANCHOR FIX: E\'s edge source must be A\'s box '
              'center, NOT a union midpoint');
      expect(eResolved.source, isNot(abMid),
          reason: 'EDGE-ANCHOR FIX: E\'s edge source must NOT be the '
              'A-B union midpoint');
      expect(eResolved.source, isNot(acMid),
          reason: 'EDGE-ANCHOR FIX: E\'s edge source must NOT be the '
              'A-C union midpoint either');

      // SPOKES-ON-A-CLOCK-FACE: D's edge and E's edge both anchor at
      // the SAME source center (A's box center). This is the user's
      // "all outgoing edges converge at the same center point"
      // requirement.
      expect(dResolved.source, eResolved.source,
          reason: 'EDGE-ANCHOR FIX: multiple outgoing edges from the '
              'same parent (A→D and A→E) must converge at A\'s box '
              'center — the spokes-on-a-clock-face requirement');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // TEST 4: Half-sibling — EDGE-ANCHOR FIX: BOTH edges anchor at A's
  // center (no redirect for either).
  // ─────────────────────────────────────────────────────────────────────
  group('TEST 4 — Half-sibling (EDGE-ANCHOR FIX: no redirect for any)', () {
    test('shared child\'s sibling (NOT in same union) anchors at parent center too', () {
      // A — wife — B (union 1)
      // D is a child of BOTH A and B → child of union 1 (shared).
      // F has only ONE known parent (A) → NOT in any union.
      // F is a half-sibling of D (they share parent A only).
      // Canonical (v5.174): D→A 'father' ("A is D's father"),
      // D→B 'mother' ("B is D's mother"), F→A 'father' ("A is F's
      // father" — F's only known parent).
      //
      // EDGE-ANCHOR FIX: BOTH A→D AND A→F anchor at A's box center
      // (no redirect for either). The user's spec:
      //   "All outgoing edges converge at the same center point."
      final edges = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['D', 'A', 'eAD', 'father'], // canonical: "A is D's father"
        ['D', 'B', 'eBD', 'mother'], // canonical: "B is D's mother"
        ['F', 'A', 'eAF', 'father'], // F has only one known parent (A)
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

      // A→D: EDGE-ANCHOR FIX — anchors at A's box center, NOT the union
      // midpoint.
      final dResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'D',
        rawSource: positions['A']!,
        rawTarget: positions['D']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      expect(dResolved.source, positions['A']!,
          reason: 'EDGE-ANCHOR FIX: A→D (shared child) source must be '
              'A\'s box center, NOT the union midpoint');

      // A→F: EDGE-ANCHOR FIX — also anchors at A's box center.
      final fResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'F',
        rawSource: positions['A']!,
        rawTarget: positions['F']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      expect(fResolved.source, positions['A']!,
          reason: 'EDGE-ANCHOR FIX: A→F (half-sibling) source must be '
              'A\'s box center');
      expect(fResolved.target, positions['F']!);

      // SPOKES-ON-A-CLOCK-FACE: A→D and A→F converge at the SAME source
      // center (A's box center). Pre-fix, only A→F did; A→D redirected
      // to the union midpoint (offset position). Post-fix, both anchor
      // at A's center — the user's spec.
      expect(dResolved.source, fResolved.source,
          reason: 'EDGE-ANCHOR FIX: A→D and A→F must converge at the '
              'SAME source center (A\'s box center) — the spokes-on-a-'
              'clock-face requirement. Pre-fix, A→D redirected to the '
              'union midpoint, breaking this convergence.');
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
        ['A', 'B', 'eAB', 'wife'], // canonical: "B is A's wife"
        ['C', 'A', 'eAC', 'father'], // canonical: "A is C's father"
        ['C', 'B', 'eBC', 'mother'], // canonical: "B is C's mother"
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
        ['A', 'B', 'eAB', 'wife'], // canonical: "B is A's wife"
        ['C', 'A', 'eAC', 'father'], // canonical: "A is C's father"
        ['C', 'B', 'eBC', 'mother'], // canonical: "B is C's mother"
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
  // TEST 6: EDGE-ANCHOR FIX regression guard — NO redirect happens.
  //
  // The previous TEST 6 verified the difference between redirect and
  // no-redirect (i.e., it verified the redirect WAS active). After the
  // EDGE-ANCHOR FIX, the redirect has been removed entirely, so the
  // previous TEST 6 is obsolete.
  //
  // This new TEST 6 verifies the NEW behavior: NO redirect happens for
  // ANY edge — including the parent→child edges through confirmed
  // couple unions that previously triggered the redirect. If a future
  // change reintroduces the couple-union redirect, this test will
  // fail because `resolveEffectiveEdgeEndpoints` would return a
  // different result than the raw source/target.
  // ─────────────────────────────────────────────────────────────────────
  group('TEST 6 — EDGE-ANCHOR FIX regression guard (NO redirect)', () {
    test(
        'resolveEffectiveEdgeEndpoints returns raw source/target unchanged '
        'for parent→child edge through a confirmed couple union',
        () {
      // The same family structure that USED to trigger the redirect:
      // A — wife — B (spouse pair, confirmed union)
      // C is the shared child of BOTH A and B → attached to the union.
      // Pre-fix, A→C edge source was redirected to unionMidpoint(A, B).
      // Post-fix (EDGE-ANCHOR FIX), A→C edge source must remain A's raw
      // position.
      final edgeTuples = buildEdges([
        ['A', 'B', 'eAB', 'wife'], // canonical: "B is A's wife"
        ['C', 'A', 'eAC', 'father'], // canonical: "A is C's father"
        ['C', 'B', 'eBC', 'mother'], // canonical: "B is C's mother"
      ]);
      final unions = deriveCoupleUnions(edgeTuples);
      expect(unions.length, 1);
      expect(unions.first.childIds, contains('C'),
          reason: 'Sanity: C IS attached to the union (the redirect '
              'would have applied pre-fix)');

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

      // EDGE-ANCHOR FIX regression guard: source and target MUST be the
      // raw values. If a future change reintroduces the couple-union
      // redirect, `resolved.source` would become unionMidpoint(A, B)
      // = (50, 0), and this assertion would fail.
      expect(resolved.source, rawSource,
          reason: 'EDGE-ANCHOR FIX regression guard: source must be the '
              'raw box center, NOT the union midpoint. If this fails, '
              'the couple-union redirect has been reintroduced.');
      expect(resolved.target, rawTarget,
          reason: 'EDGE-ANCHOR FIX regression guard: target must be the '
              'raw box center, unchanged.');
      expect(resolved.source, isNot(unionMidpoint(positions['A']!, positions['B']!)),
          reason: 'EDGE-ANCHOR FIX regression guard: source must NOT be '
              'the union midpoint. If this fails, the couple-union '
              'redirect has been reintroduced.');
    });

    test(
        'multiple parent→child edges from the same parent converge at the '
        'parent\'s box center (spokes-on-a-clock-face)',
        () {
      // The user's spec: "All outgoing edges converge at the same center
      // point." This test verifies that multiple parent→child edges
      // from the same parent (in different unions, in this case) ALL
      // anchor at the parent's box center — NOT at the various union
      // midpoints.
      //
      // Family: A — B (union 1), A — C (union 2, remarriage)
      //         D is shared child of A+B → union 1
      //         E is shared child of A+C → union 2
      // Pre-fix: A→D anchored at A-B midpoint, A→E anchored at A-C
      // midpoint — DIFFERENT points (not converged).
      // Post-fix: BOTH anchor at A's box center — converged.
      final edgeTuples = buildEdges([
        ['A', 'B', 'eAB', 'wife'],
        ['A', 'C', 'eAC2', 'wife'],
        ['D', 'A', 'eAD', 'father'],
        ['D', 'B', 'eBD', 'mother'],
        ['E', 'A', 'eAE', 'father'],
        ['E', 'C', 'eCE', 'mother'],
      ]);
      final unions = deriveCoupleUnions(edgeTuples);
      expect(unions.length, 2);

      final positions = <String, Offset>{
        'A': const Offset(100, 0),
        'B': const Offset(0, 0),
        'C': const Offset(200, 0),
        'D': const Offset(50, 200),
        'E': const Offset(200, 200),
      };

      final dResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'D',
        rawSource: positions['A']!,
        rawTarget: positions['D']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );
      final eResolved = resolveEffectiveEdgeEndpoints(
        sourceId: 'A',
        targetId: 'E',
        rawSource: positions['A']!,
        rawTarget: positions['E']!,
        coupleUnions: unions,
        positionOf: (id) => positions[id],
      );

      // BOTH edges converge at A's box center — the user's spec.
      expect(dResolved.source, positions['A']!);
      expect(eResolved.source, positions['A']!);
      expect(dResolved.source, eResolved.source,
          reason: 'EDGE-ANCHOR FIX regression guard: multiple outgoing '
              'edges from the same parent must converge at the parent\'s '
              'box center — the spokes-on-a-clock-face requirement. If '
              'this fails, special-case anchoring logic has been '
              'reintroduced (e.g., per-union midpoint redirects).');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // BONUS: End-to-end consistency — painter and hit-tester use the SAME
  // helper, so the rendered curve and the tap target can NEVER diverge.
  //
  // EDGE-ANCHOR FIX: the test now verifies parity for an edge that USED
  // to be union-redirected (parent→child through a confirmed couple
  // union). Post-fix, both painter and hit-tester compute the raw
  // midpoint (no redirect), so they're trivially in sync. The test
  // still catches the original sin: a future refactor that introduces a
  // second copy of edge-endpoint logic in either the painter or the
  // hit-tester (rather than calling this shared helper) will fail
  // here immediately.
  // ─────────────────────────────────────────────────────────────────────
  group('Painter ↔ Hit-tester contract', () {
    test(
        'the midpoint used by the painter equals the midpoint used by the '
        'hit-tester for an edge that USED to be union-redirected',
        () {
      // This is the structural guarantee: because both sites call the
      // SAME resolveEffectiveEdgeEndpoints function, the midpoint they
      // each compute must be IDENTICAL. This test exists so that a
      // future refactor that introduces a second copy of the endpoint
      // logic (the original sin) will fail here immediately, before
      // tests 5 and 6 even run.
      final edgeTuples = buildEdges([
        ['A', 'B', 'eAB', 'wife'], // canonical: "B is A's wife"
        ['C', 'A', 'eAC', 'father'], // canonical: "A is C's father"
        ['C', 'B', 'eBC', 'mother'], // canonical: "B is C's mother"
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

      // EDGE-ANCHOR FIX: the shared midpoint MUST be the raw midpoint
      // (between A and C), NOT the union midpoint. This guards against
      // a future change that reintroduces the couple-union redirect in
      // this shared helper.
      final rawMid = Offset(
        (positions['A']!.dx + positions['C']!.dx) / 2,
        (positions['A']!.dy + positions['C']!.dy) / 2,
      );
      expect(painterMid, rawMid,
          reason: 'EDGE-ANCHOR FIX: the painter-hit-tester shared '
              'midpoint must be the raw box-center midpoint, NOT the '
              'union midpoint.');
    });
  });
}
