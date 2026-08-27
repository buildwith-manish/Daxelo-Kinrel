// test/graph/engine/graph_layout_force_relaxation_test.dart
//
// v5.123 (Step 1) — Force relaxation is an EXPLICIT opt-in.
//
// GraphLayoutService.computeLayout used to enable the _forceRelax
// physics pass implicitly via `n > 60 && n <= 1000`, which pulled
// nodes OFF their assigned ring radii at normal (~20-40 node) view
// sizes and produced crossed/messy edges. The pass is now gated
// behind the `allowForceRelaxation` parameter (default FALSE) — only
// the "Show All Branches" / Level 4 path opts in.
//
// This regression test pins:
//   1. The default (> 60 nodes, no opt-in) is deterministic and keeps
//      every generation on a single Y band (pure radial + band
//      placement, no physics drift).
//   2. Passing allowForceRelaxation: true actually engages the physics
//      pass for a > 60 node graph (the output differs from the
//      default run).
//   3. The parameter is accepted and produces finite positions for
//      small graphs too (no-op path).

import 'package:flutter/material.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/services/graph_layout_service.dart';

GraphPerson _p(String id, {bool isAnchor = false}) => GraphPerson(
      id: id,
      name: 'Person $id',
      isAnchor: isAnchor,
    );

GraphRelationship _r(String id, String from, String to) =>
    GraphRelationship(
      id: id,
      fromPersonId: from,
      toPersonId: to,
      relationshipKey: 'parent',
    );

void main() {
  // Asymmetric family: anchor + 12 children, where child i has
  // (i + 3) children of their own. Subtree sizes deliberately differ so
  // the force field is asymmetric. Total = 1 + 12 + (3+4+...+14) = 115
  // persons — comfortably above the old implicit `n > 60` trigger.
  final persons = <GraphPerson>[_p('anchor', isAnchor: true)];
  final relationships = <GraphRelationship>[];
  var edgeId = 0;
  for (var child = 0; child < 12; child++) {
    final childId = 'child$child';
    persons.add(_p(childId));
    // Canonical: from=child, to=anchor, key='parent' → anchor is the
    // child's parent (one generation above).
    relationships.add(_r('e${edgeId++}', childId, 'anchor'));
    final grandchildCount = child + 3;
    for (var gc = 0; gc < grandchildCount; gc++) {
      final gcId = 'gc_${child}_$gc';
      persons.add(_p(gcId));
      relationships.add(_r('e${edgeId++}', gcId, childId));
    }
  }

  test('default (>60 nodes, no opt-in) is deterministic — no physics '
      'drift between runs', () {
    final service = GraphLayoutService();
    final r1 = service.computeLayout(
      persons: persons,
      relationships: relationships,
      anchorPersonId: 'anchor',
    );
    final r2 = service.computeLayout(
      persons: persons,
      relationships: relationships,
      anchorPersonId: 'anchor',
    );

    expect(r1.positions.length, persons.length);
    for (final id in r1.positions.keys) {
      expect(r2.positions[id], r1.positions[id],
          reason: 'Default layout must be fully deterministic '
              '(no relaxation, no jitter at this size): $id differs');
    }
  });

  test('default keeps every generation on a single Y band (nodes stay '
      'on their ring structure)', () {
    final service = GraphLayoutService();
    final result = service.computeLayout(
      persons: persons,
      relationships: relationships,
      anchorPersonId: 'anchor',
    );

    // All 12 direct children share generation +1 → after the
    // hierarchical Y-band pass they MUST share one identical Y value.
    final childYs = <double>{
      for (var i = 0; i < 12; i++) result.positions['child$i']!.dy,
    };
    expect(childYs.length, 1,
        reason: 'All gen-1 nodes must sit on the same Y band — '
            'force relaxation must NOT have scattered them');

    // Grandchildren share generation +2 → one identical Y, strictly
    // below the children band.
    final gcYs = <double>{
      for (var c = 0; c < 12; c++)
        for (var g = 0; g < c + 3; g++)
          result.positions['gc_${c}_$g']!.dy,
    };
    expect(gcYs.length, 1,
        reason: 'All gen-2 nodes must sit on the same Y band');
    expect(gcYs.first, greaterThan(childYs.first),
        reason: 'Descendant band must be below the parent band');
  });

  test('allowForceRelaxation: true engages the physics pass for >60 '
      'nodes (output differs from the default run)', () {
    final service = GraphLayoutService();
    final withoutRelax = service.computeLayout(
      persons: persons,
      relationships: relationships,
      anchorPersonId: 'anchor',
    );
    final withRelax = service.computeLayout(
      persons: persons,
      relationships: relationships,
      anchorPersonId: 'anchor',
      allowForceRelaxation: true,
    );

    expect(withRelax.positions.length, persons.length);

    // The relaxation pass must have moved at least one node — the old
    // implicit behaviour, now only reachable via the explicit opt-in.
    var differences = 0;
    for (final id in withRelax.positions.keys) {
      if (withRelax.positions[id] != withoutRelax.positions[id]) {
        differences++;
      }
    }
    expect(differences, greaterThan(0),
        reason: 'allowForceRelaxation: true with ${persons.length} nodes '
            'must run the physics pass and change the layout');
  });

  test('parameter is safe for small graphs (finite positions, no-op)', () {
    final smallPersons = [_p('a', isAnchor: true), _p('b')];
    final smallRels = [_r('r1', 'b', 'a')];
    final service = GraphLayoutService();
    final result = service.computeLayout(
      persons: smallPersons,
      relationships: smallRels,
      anchorPersonId: 'a',
      allowForceRelaxation: true,
    );

    expect(result.positions.length, 2);
    for (final pos in result.positions.values) {
      expect(pos.dx.isFinite, isTrue);
      expect(pos.dy.isFinite, isTrue);
    }
    // 'a' sees 'b' as parent → 'b' is one ring out from the anchor.
    expect(
      (result.positions['b']! - result.positions['a']!).distance,
      greaterThan(0),
    );
  });

  test('small graph without opt-in ignores the old node-count trigger '
      '(deterministic across runs)', () {
    final smallPersons = [_p('a', isAnchor: true), _p('b')];
    final smallRels = [_r('r1', 'b', 'a')];
    final service = GraphLayoutService();
    final r1 = service.computeLayout(
      persons: smallPersons,
      relationships: smallRels,
      anchorPersonId: 'a',
    );
    final r2 = service.computeLayout(
      persons: smallPersons,
      relationships: smallRels,
      anchorPersonId: 'a',
    );
    expect(r2.positions['b'], r1.positions['b']);
    expect(Offset(r2.positions['a']!.dx, r2.positions['a']!.dy),
        r1.positions['a']);
  });
}
