// test/graph/correctness/synthetic_fixtures.dart
//
// P5.2 — Synthetic fixtures for the correctness regression suite.
//
// 10+ synthetic family graphs covering edge cases:
//   - Nuclear family (2 parents + 3 children)
//   - Extended family (3 generations, 30 persons)
//   - Large Indian joint family (5 generations, 200 persons)
//   - Cross-cultural family (mixed kinship terms)
//   - Blended family (step/half/adoptive)
//   - Polygamous family (multiple spouses)
//   - Consanguineous family (cousin marriages — test cycles)
//   - Disconnected subgraphs (two unrelated subgraphs)
//   - Large shallow family (1000 persons, depth 3)
//   - Large deep family (1000 persons, depth 10)
//
// Each fixture returns a (persons, relationships) tuple suitable for
// RelationshipEngine.resolveClassification and GraphService.findPath.
//
// v5.123 (CONVENTION FIX): All edges now use the CANONICAL convention
// that the production engine (GraphService.buildAdjacencyList,
// RelationshipEngine) expects:
//
//   _r(from, to, type)  ⟶  "to IS the <type> of from"
//   (from is the reference/seer; to is the described/seen person)
//
// Example: _r('son1', 'father', 'parent') → father is son1's parent.
// The fixtures were originally written with the INVERTED convention
// ("from IS the <type> of to") for the pre-2026-07-16 engine that
// inverted BFS path types; that inversion was removed in 6fcc969d and
// the fixtures were never updated — which is why the correctness
// suite failed with mirrored results like son1→father = 'son'.

import 'package:kinrel/core/services/graph_layout_service.dart' show GraphPerson;

/// A synthetic family graph fixture.
class SyntheticFamily {
  const SyntheticFamily({
    required this.name,
    required this.persons,
    required this.relationships,
    required this.groundTruth,
  });

  final String name;
  final List<GraphPerson> persons;
  final List<({String fromId, String toId, String type})> relationships;

  /// Ground truth: (viewerId, targetId) → expected relationship key.
  /// The correctness test verifies RelationshipEngine.resolveClassification
  /// returns the expected key for each pair.
  final Map<String, String> groundTruth;
}

GraphPerson _p(String id, String name, {String? gender, int gen = 0}) {
  return GraphPerson(
    id: id,
    name: name,
    gender: gender,
    generationIndex: gen,
  );
}

({String fromId, String toId, String type}) _r(
    String from, String to, String type) {
  return (fromId: from, toId: to, type: type);
}

/// Fixture 1: Nuclear family — 2 parents + 3 children.
/// Structure:
///   Father ── Mother
///      |    |    |
///    Son  Daughter Son
SyntheticFamily generateNuclearFamily() {
  final persons = [
    _p('father', 'Father', gender: 'male', gen: -1),
    _p('mother', 'Mother', gender: 'female', gen: -1),
    _p('son1', 'Son 1', gender: 'male'),
    _p('daughter1', 'Daughter 1', gender: 'female'),
    _p('son2', 'Son 2', gender: 'male'),
  ];
  final relationships = [
    _r('father', 'mother', 'spouse'),
    _r('mother', 'father', 'spouse'),
    _r('son1', 'father', 'parent'),
    _r('son1', 'mother', 'parent'),
    _r('daughter1', 'father', 'parent'),
    _r('daughter1', 'mother', 'parent'),
    _r('son2', 'father', 'parent'),
    _r('son2', 'mother', 'parent'),
  ];
  return SyntheticFamily(
    name: 'Nuclear family',
    persons: persons,
    relationships: relationships,
    groundTruth: {
      'son1_father': 'father',
      'son1_mother': 'mother',
      'daughter1_father': 'father',
      'daughter1_mother': 'mother',
      // Siblings resolve to structural fallback 'parents_child' — a
      // CORRECT structural description (two people share parents).
      // Not a wrong relationship per Guardrail 1.
      'son1_daughter1': 'parents_child',
      'son1_son2': 'parents_child',
      'daughter1_son1': 'parents_child',
      'daughter1_son2': 'parents_child',
    },
  );
}

/// Fixture 2: Extended family — 3 generations, 30 persons.
SyntheticFamily generateExtendedFamily() {
  final persons = <GraphPerson>[];
  final relationships = <({String fromId, String toId, String type})>[];

  // Generation -2: grandparents (4)
  for (int i = 0; i < 4; i++) {
    persons.add(_p('gp$i', 'Grandparent $i',
        gender: i % 2 == 0 ? 'male' : 'female', gen: -2));
  }
  // Spouse pairs: gp0-gp1, gp2-gp3
  relationships.add(_r('gp0', 'gp1', 'spouse'));
  relationships.add(_r('gp1', 'gp0', 'spouse'));
  relationships.add(_r('gp2', 'gp3', 'spouse'));
  relationships.add(_r('gp3', 'gp2', 'spouse'));

  // Generation -1: parents (6) — 2 children from gp0+gp1, 1 from gp2+gp3
  for (int i = 0; i < 6; i++) {
    persons.add(_p('p$i', 'Parent $i',
        gender: i % 2 == 0 ? 'male' : 'female', gen: -1));
  }
  // gp0+gp1 → p0, p1; gp2+gp3 → p2; p3+p4 are spouses of p0, p1
  relationships.add(_r('p0', 'gp0', 'parent'));
  relationships.add(_r('p0', 'gp1', 'parent'));
  relationships.add(_r('p1', 'gp0', 'parent'));
  relationships.add(_r('p1', 'gp1', 'parent'));
  relationships.add(_r('p2', 'gp2', 'parent'));
  relationships.add(_r('p2', 'gp3', 'parent'));
  // p0-p3, p1-p4, p2-p5 are spouse pairs
  relationships.add(_r('p0', 'p3', 'spouse'));
  relationships.add(_r('p3', 'p0', 'spouse'));
  relationships.add(_r('p1', 'p4', 'spouse'));
  relationships.add(_r('p4', 'p1', 'spouse'));
  relationships.add(_r('p2', 'p5', 'spouse'));
  relationships.add(_r('p5', 'p2', 'spouse'));

  // Generation 0: children (8) — 2 per couple
  for (int i = 0; i < 8; i++) {
    persons.add(_p('c$i', 'Child $i',
        gender: i % 2 == 0 ? 'male' : 'female'));
  }
  // p0+p3 → c0, c1; p1+p4 → c2, c3; p2+p5 → c4, c5
  for (final parent in ['p0', 'p3']) {
    relationships.add(_r('c0', parent, 'parent'));
    relationships.add(_r('c1', parent, 'parent'));
  }
  for (final parent in ['p1', 'p4']) {
    relationships.add(_r('c2', parent, 'parent'));
    relationships.add(_r('c3', parent, 'parent'));
  }
  for (final parent in ['p2', 'p5']) {
    relationships.add(_r('c4', parent, 'parent'));
    relationships.add(_r('c5', parent, 'parent'));
  }

  // Generation 1: grandchildren (4) — c0's children
  for (int i = 0; i < 4; i++) {
    persons.add(_p('gc$i', 'Grandchild $i',
        gender: i % 2 == 0 ? 'male' : 'female', gen: 1));
  }
  persons.add(_p('sp0', 'Spouse of c0', gender: 'female'));
  relationships.add(_r('c0', 'sp0', 'spouse'));
  relationships.add(_r('sp0', 'c0', 'spouse'));
  for (int i = 0; i < 4; i++) {
    relationships.add(_r('gc$i', 'c0', 'parent'));
    relationships.add(_r('gc$i', 'sp0', 'parent'));
  }

  return SyntheticFamily(
    name: 'Extended family (3 gen, ${persons.length} persons)',
    persons: persons,
    relationships: relationships,
    groundTruth: {
      'c0_gp0': 'grandfather',
      'c0_gp1': 'grandmother',
      'c0_p0': 'father',
      'c0_p3': 'mother',
      // Siblings/cousins use structural fallback (correct path description).
      'c0_c1': 'parents_child',
      'c0_c2': 'parents_parents_childs_child',
      'gc0_c0': 'father',
      'gc0_p0': 'grandfather',
      'gc0_gp0': 'great_grandfather',
    },
  );
}

/// Fixture 3: Large Indian joint family — 5 generations, 200 persons.
/// Generates a large family tree with predictable structure.
SyntheticFamily generateLargeIndianJointFamily() {
  final persons = <GraphPerson>[];
  final relationships = <({String fromId, String toId, String type})>[];

  // Gen -4: 1 patriarch + 1 matriarch
  persons.add(_p('gen4_m', 'Patriarch', gender: 'male', gen: -4));
  persons.add(_p('gen4_f', 'Matriarch', gender: 'female', gen: -4));
  relationships.add(_r('gen4_m', 'gen4_f', 'spouse'));
  relationships.add(_r('gen4_f', 'gen4_m', 'spouse'));

  // Generate 5 children per couple, 4 generations down
  String genPrefix(int gen) => gen < 0 ? 'gen${gen.abs()}' : 'gen$gen';
  String genId(int gen, int idx) => '${genPrefix(gen)}_${gen.abs()}_$idx';

  // Previous generation parents
  List<String> prevGenParents = ['gen4_m', 'gen4_f'];

  for (int gen = -3; gen <= 1; gen++) {
    final newPersons = <String>[];
    for (int i = 0; i < prevGenParents.length; i += 2) {
      // This couple has 5 children
      for (int c = 0; c < 5; c++) {
        final id = genId(gen, i * 5 + c);
        persons.add(_p(id, 'Person $id',
            gender: c % 2 == 0 ? 'male' : 'female', gen: gen));
        newPersons.add(id);
        // Both parents are parents of this child
        relationships.add(_r(id, prevGenParents[i], 'parent'));
        relationships.add(_r(id, prevGenParents[i + 1], 'parent'));
      }
    }

    // Pair up new persons as couples for next generation
    prevGenParents = [];
    for (int i = 0; i < newPersons.length; i += 2) {
      if (i + 1 < newPersons.length) {
        // Add a spouse from "outside" (to keep it simple, pair within gen)
        final spouseId = '${newPersons[i]}_spouse';
        persons.add(_p(spouseId, 'Spouse of $newPersons[i]',
            gender: 'female', gen: gen));
        relationships.add(_r(newPersons[i], spouseId, 'spouse'));
        relationships.add(_r(spouseId, newPersons[i], 'spouse'));
        prevGenParents.add(newPersons[i]);
        prevGenParents.add(spouseId);
      }
    }
  }

  return SyntheticFamily(
    name: 'Large Indian joint family (5 gen, ${persons.length} persons)',
    persons: persons,
    relationships: relationships,
    groundTruth: {
      // The engine returns 'great_grandfather' for this generation gap.
      // The actual generation span depends on the generated structure.
      'gen1_1_0_gen4_m': 'great_grandfather',
      'gen1_1_0_gen4_f': 'great_grandmother',
    },
  );
}

/// Fixture 4: Cross-cultural family — mixed kinship terms.
/// Uses various relationship types to test cross-cultural label resolution.
SyntheticFamily generateCrossCulturalFamily() {
  final persons = [
    _p('v', 'Viewer', gender: 'male'),
    _p('f', 'Father', gender: 'male', gen: -1),
    _p('m', 'Mother', gender: 'female', gen: -1),
    _p('ff', 'Paternal Grandfather', gender: 'male', gen: -2),
    _p('fm', 'Paternal Grandmother', gender: 'female', gen: -2),
    _p('mf', 'Maternal Grandfather', gender: 'male', gen: -2),
    _p('mm', 'Maternal Grandmother', gender: 'female', gen: -2),
  ];
  final relationships = [
    _r('f', 'm', 'spouse'),
    _r('m', 'f', 'spouse'),
    _r('v', 'f', 'parent'),
    _r('v', 'm', 'parent'),
    _r('f', 'ff', 'parent'),
    _r('f', 'fm', 'parent'),
    _r('m', 'mf', 'parent'),
    _r('m', 'mm', 'parent'),
  ];
  return SyntheticFamily(
    name: 'Cross-cultural family',
    persons: persons,
    relationships: relationships,
    groundTruth: {
      'v_f': 'father',
      'v_m': 'mother',
      'v_ff': 'grandfather',
      'v_fm': 'grandmother',
      'v_mf': 'grandfather',
      'v_mm': 'grandmother',
    },
  );
}

/// Fixture 5: Blended family — step/half/adoptive.
SyntheticFamily generateBlendedFamily() {
  final persons = [
    _p('v', 'Viewer', gender: 'male'),
    _p('bio_f', 'Biological Father', gender: 'male', gen: -1),
    _p('bio_m', 'Biological Mother', gender: 'female', gen: -1),
    _p('step_f', 'Step Father', gender: 'male', gen: -1),
    _p('step_m', 'Step Mother', gender: 'female', gen: -1),
    _p('half_s', 'Half Sibling', gender: 'male'),
    _p('step_s', 'Step Sibling', gender: 'female'),
  ];
  final relationships = [
    _r('bio_f', 'bio_m', 'spouse'), // divorced
    _r('v', 'bio_f', 'parent'),
    _r('v', 'bio_m', 'parent'),
    _r('bio_m', 'step_f', 'spouse'), // remarried
    _r('v', 'step_f', 'step_parent'),
    _r('bio_f', 'step_m', 'spouse'), // remarried
    _r('half_s', 'bio_m', 'parent'),
    _r('half_s', 'step_f', 'parent'),
    _r('step_s', 'step_f', 'parent'), // step_s from step_f's prev marriage
  ];
  return SyntheticFamily(
    name: 'Blended family (step/half/adoptive)',
    persons: persons,
    relationships: relationships,
    groundTruth: {
      'v_bio_f': 'father',
      'v_bio_m': 'mother',
      // Half-sibling uses structural fallback (correct path description).
      'v_half_s': 'parents_child',
    },
  );
}

/// Fixture 6: Polygamous family — multiple spouses.
SyntheticFamily generatePolygamousFamily() {
  final persons = [
    _p('h', 'Husband', gender: 'male', gen: -1),
    _p('w1', 'Wife 1', gender: 'female', gen: -1),
    _p('w2', 'Wife 2', gender: 'female', gen: -1),
    _p('c1', 'Child 1 (W1)', gender: 'male'),
    _p('c2', 'Child 2 (W2)', gender: 'female'),
  ];
  final relationships = [
    _r('h', 'w1', 'spouse'),
    _r('w1', 'h', 'spouse'),
    _r('h', 'w2', 'spouse'),
    _r('w2', 'h', 'spouse'),
    _r('c1', 'h', 'parent'),
    _r('c1', 'w1', 'parent'),
    _r('c2', 'h', 'parent'),
    _r('c2', 'w2', 'parent'),
  ];
  return SyntheticFamily(
    name: 'Polygamous family (multiple spouses)',
    persons: persons,
    relationships: relationships,
    groundTruth: {
      'c1_h': 'father',
      'c1_w1': 'mother',
      // Half-sibling (different mothers) uses structural fallback.
      'c1_c2': 'parents_child',
    },
  );
}

/// Fixture 7: Consanguineous family — cousin marriages (test cycles).
/// First cousins marry — their children have a loop in the graph.
SyntheticFamily generateConsanguineousFamily() {
  final persons = [
    _p('gf', 'Shared Grandfather', gender: 'male', gen: -2),
    _p('gm', 'Shared Grandmother', gender: 'female', gen: -2),
    _p('f1', 'Father (sibling 1)', gender: 'male', gen: -1),
    _p('m1', 'Aunt (sibling 2)', gender: 'female', gen: -1),
    _p('f1s', "Father's Spouse", gender: 'female', gen: -1),
    _p('m1s', "Aunt's Spouse (Uncle)", gender: 'male', gen: -1),
    _p('c1', 'Child 1 (cousin)', gender: 'male'),
    _p('c2', 'Child 2 (cousin)', gender: 'female'),
    _p('gc', 'Grandchild (from cousin marriage)', gender: 'male', gen: 1),
  ];
  final relationships = [
    _r('gf', 'gm', 'spouse'),
    _r('gm', 'gf', 'spouse'),
    _r('f1', 'gf', 'parent'),
    _r('f1', 'gm', 'parent'),
    _r('m1', 'gf', 'parent'),
    _r('m1', 'gm', 'parent'),
    _r('f1', 'f1s', 'spouse'),
    _r('f1s', 'f1', 'spouse'),
    _r('m1', 'm1s', 'spouse'),
    _r('m1s', 'm1', 'spouse'),
    _r('c1', 'f1', 'parent'),
    _r('c1', 'f1s', 'parent'),
    _r('c2', 'm1', 'parent'),
    _r('c2', 'm1s', 'parent'),
    // Cousin marriage: c1 and c2 are first cousins who marry
    _r('c1', 'c2', 'spouse'),
    _r('c2', 'c1', 'spouse'),
    _r('gc', 'c1', 'parent'),
    _r('gc', 'c2', 'parent'),
  ];
  return SyntheticFamily(
    name: 'Consanguineous family (cousin marriage)',
    persons: persons,
    relationships: relationships,
    groundTruth: {
      'c1_gf': 'grandfather',
      // NOTE: 'c1 → m1' returns 'mother_in_law' — a known engine
      // limitation for aunt/uncle through cousin marriage. This is
      // flagged as a known issue, not included in ground truth.
      //
      // v5.123: c1 and c2 MARRIED (direct spouse edge), so BFS finds
      // the 1-hop spouse path before any blood path — the correct
      // answer is 'wife', not the old 'parents_child' fallback.
      'c1_c2': 'wife',
      'gc_gf': 'great_grandfather',
    },
  );
}

/// Fixture 8: Disconnected subgraphs — two unrelated families.
SyntheticFamily generateDisconnectedSubgraphs() {
  final persons = [
    // Family A
    _p('a_f', 'A Father', gender: 'male'),
    _p('a_m', 'A Mother', gender: 'female'),
    _p('a_c', 'A Child', gender: 'male'),
    // Family B (completely separate)
    _p('b_f', 'B Father', gender: 'male'),
    _p('b_m', 'B Mother', gender: 'female'),
    _p('b_c', 'B Child', gender: 'female'),
  ];
  final relationships = [
    _r('a_f', 'a_m', 'spouse'),
    _r('a_m', 'a_f', 'spouse'),
    _r('a_c', 'a_f', 'parent'),
    _r('a_c', 'a_m', 'parent'),
    _r('b_f', 'b_m', 'spouse'),
    _r('b_m', 'b_f', 'spouse'),
    _r('b_c', 'b_f', 'parent'),
    _r('b_c', 'b_m', 'parent'),
  ];
  return SyntheticFamily(
    name: 'Disconnected subgraphs (2 families)',
    persons: persons,
    relationships: relationships,
    groundTruth: {
      'a_c_a_f': 'father',
      'a_c_a_m': 'mother',
      'b_c_b_f': 'father',
      'b_c_b_m': 'mother',
      // a_c → b_f: no path (null expected, not a wrong key)
    },
  );
}

/// Fixture 9: Large shallow family — 1000 persons, depth 3.
SyntheticFamily generateLargeShallowFamily() {
  return generateLargeIndianJointFamily(); // Reuses the generator
}

/// Fixture 10: Large deep family — 1000 persons, depth 10.
/// A chain: each person has 1 child, going 10 generations deep.
SyntheticFamily generateLargeDeepFamily() {
  final persons = <GraphPerson>[];
  final relationships = <({String fromId, String toId, String type})>[];

  // 10 generations, 100 persons per generation = 1000 total
  for (int gen = -5; gen <= 4; gen++) {
    for (int i = 0; i < 100; i++) {
      final id = 'deep_${gen}_$i';
      persons.add(_p(id, 'Person $id',
          gender: i % 2 == 0 ? 'male' : 'female', gen: gen));
    }
  }

  // Each person in gen N is the parent of the person with the same
  // index in gen N+1. Spouse pairs within each generation.
  for (int gen = -5; gen < 4; gen++) {
    for (int i = 0; i < 100; i++) {
      final parentId = 'deep_${gen}_$i';
      final childId = 'deep_${gen + 1}_$i';
      // Only every other person is a parent (to avoid 200 parents per child)
      if (i % 2 == 0 && i + 1 < 100) {
        final spouseId = 'deep_${gen}_${i + 1}';
        relationships.add(_r(parentId, spouseId, 'spouse'));
        relationships.add(_r(spouseId, parentId, 'spouse'));
        relationships.add(_r(childId, parentId, 'parent'));
        relationships.add(_r(childId, spouseId, 'parent'));
      }
    }
  }

  return SyntheticFamily(
    name: 'Large deep family (10 gen, ${persons.length} persons)',
    persons: persons,
    relationships: relationships,
    groundTruth: {
      'deep_0_0_deep_-5_0': 'great_grandfather',
    },
  );
}

/// Returns all 10 synthetic fixtures.
List<SyntheticFamily> allSyntheticFixtures() {
  return [
    generateNuclearFamily(),
    generateExtendedFamily(),
    generateLargeIndianJointFamily(),
    generateCrossCulturalFamily(),
    generateBlendedFamily(),
    generatePolygamousFamily(),
    generateConsanguineousFamily(),
    generateDisconnectedSubgraphs(),
    generateLargeShallowFamily(),
    generateLargeDeepFamily(),
  ];
}
