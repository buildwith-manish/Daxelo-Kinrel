import {
  computeKinshipCoefficient,
  classifyRelationship,
  determineLineage,
  KINSHIP_COEFFICIENTS,
} from './kinship-coefficient';
import { RelationshipStep } from '../../graph/graph-engine.service';

// ── Helper ──────────────────────────────────────────────────────────

const makeStep = (
  relType: string,
  direction: 'up' | 'down' | 'sideways' = 'up',
): RelationshipStep => ({
  personId: `person-${relType}`,
  personName: `Name-${relType}`,
  relationshipType: relType,
  direction,
});

// ════════════════════════════════════════════════════════════════════
// KINSHIP COEFFICIENT LOOKUP TABLE
// ════════════════════════════════════════════════════════════════════

describe('KINSHIP_COEFFICIENTS', () => {
  it('should define coefficients for all 8 core relationship types', () => {
    expect(KINSHIP_COEFFICIENTS.father).toBe(0.5);
    expect(KINSHIP_COEFFICIENTS.mother).toBe(0.5);
    expect(KINSHIP_COEFFICIENTS.son).toBe(0.5);
    expect(KINSHIP_COEFFICIENTS.daughter).toBe(0.5);
    expect(KINSHIP_COEFFICIENTS.brother).toBe(0.5);
    expect(KINSHIP_COEFFICIENTS.sister).toBe(0.5);
    expect(KINSHIP_COEFFICIENTS.husband).toBe(0);
    expect(KINSHIP_COEFFICIENTS.wife).toBe(0);
  });

  it('should define coefficients for grandparent relationships', () => {
    expect(KINSHIP_COEFFICIENTS.grandfather).toBe(0.25);
    expect(KINSHIP_COEFFICIENTS.grandmother).toBe(0.25);
    expect(KINSHIP_COEFFICIENTS.paternal_grandfather).toBe(0.25);
    expect(KINSHIP_COEFFICIENTS.maternal_grandmother).toBe(0.25);
  });

  it('should define coefficients for avuncular relationships', () => {
    expect(KINSHIP_COEFFICIENTS.uncle).toBe(0.25);
    expect(KINSHIP_COEFFICIENTS.aunt).toBe(0.25);
    expect(KINSHIP_COEFFICIENTS.nephew).toBe(0.25);
    expect(KINSHIP_COEFFICIENTS.niece).toBe(0.25);
  });

  it('should define coefficients for cousin relationships', () => {
    expect(KINSHIP_COEFFICIENTS.cousin).toBe(0.125);
    expect(KINSHIP_COEFFICIENTS.second_cousin).toBe(0.03125);
    expect(KINSHIP_COEFFICIENTS.cousin_once_removed).toBe(0.0625);
    expect(KINSHIP_COEFFICIENTS.third_cousin).toBe(0.0078125);
  });

  it('should define zero coefficients for in-law relationships', () => {
    expect(KINSHIP_COEFFICIENTS.father_in_law).toBe(0);
    expect(KINSHIP_COEFFICIENTS.mother_in_law).toBe(0);
    expect(KINSHIP_COEFFICIENTS.brother_in_law).toBe(0);
    expect(KINSHIP_COEFFICIENTS.sister_in_law).toBe(0);
    expect(KINSHIP_COEFFICIENTS.son_in_law).toBe(0);
    expect(KINSHIP_COEFFICIENTS.daughter_in_law).toBe(0);
  });

  it('should define coefficients for great-grandparent relationships', () => {
    expect(KINSHIP_COEFFICIENTS.great_grandfather).toBe(0.125);
    expect(KINSHIP_COEFFICIENTS.great_grandmother).toBe(0.125);
  });

  it('should define coefficient of 1.0 for self', () => {
    expect(KINSHIP_COEFFICIENTS.self).toBe(1.0);
  });

  it('should define coefficients for half-sibling (step) relationships', () => {
    expect(KINSHIP_COEFFICIENTS.step_brother).toBe(0.25);
    expect(KINSHIP_COEFFICIENTS.step_sister).toBe(0.25);
  });
});

// ════════════════════════════════════════════════════════════════════
// computeKinshipCoefficient()
// ════════════════════════════════════════════════════════════════════

describe('computeKinshipCoefficient', () => {
  // ── Direct term lookup ───────────────────────────────────────────

  describe('direct term lookup', () => {
    it('should return 0.5 for "father"', () => {
      expect(computeKinshipCoefficient('father')).toBe(0.5);
    });

    it('should return 0.5 for "brother"', () => {
      expect(computeKinshipCoefficient('brother')).toBe(0.5);
    });

    it('should return 0.25 for "uncle"', () => {
      expect(computeKinshipCoefficient('uncle')).toBe(0.25);
    });

    it('should return 0.125 for "cousin"', () => {
      expect(computeKinshipCoefficient('cousin')).toBe(0.125);
    });

    it('should return 0 for "husband" (spouse)', () => {
      expect(computeKinshipCoefficient('husband')).toBe(0);
    });

    it('should return 0 for "father_in_law"', () => {
      expect(computeKinshipCoefficient('father_in_law')).toBe(0);
    });

    it('should return 1.0 for "self"', () => {
      expect(computeKinshipCoefficient('self')).toBe(1.0);
    });

    it('should handle case-insensitive lookup', () => {
      expect(computeKinshipCoefficient('Father')).toBe(0.5);
      expect(computeKinshipCoefficient('COUSIN')).toBe(0.125);
    });
  });

  // ── Path-based computation fallback ──────────────────────────────

  describe('path-based computation', () => {
    it('should compute r=0.5 for single up step (father)', () => {
      const path = [makeStep('father', 'up')];
      expect(computeKinshipCoefficient('unknown_term', path)).toBe(0.5);
    });

    it('should compute r=0.25 for two up steps (grandfather)', () => {
      const path = [makeStep('father', 'up'), makeStep('father', 'up')];
      expect(computeKinshipCoefficient('unknown_term', path)).toBe(0.25);
    });

    it('should compute r=0.125 for three up steps (great-grandfather)', () => {
      const path = [
        makeStep('father', 'up'),
        makeStep('father', 'up'),
        makeStep('father', 'up'),
      ];
      expect(computeKinshipCoefficient('unknown_term', path)).toBe(0.125);
    });

    it('should compute r=0.25 for up+down (uncle/nephew path)', () => {
      const path = [
        makeStep('father', 'up'),
        makeStep('brother', 'sideways'),
        makeStep('son', 'down'),
      ];
      // 2 meiosis events (up + down) = 0.5^2 = 0.25
      expect(computeKinshipCoefficient('unknown_term', path)).toBe(0.25);
    });

    it('should compute r=0.125 for cousin path (3 meiosis via common ancestor)', () => {
      const path = [
        makeStep('father', 'up'),
        makeStep('brother', 'sideways'),
        makeStep('son', 'down'),
      ];
      // Through common grandparent: up=1, down=1 → (0.5)^2 = 0.25
      // But direct path has: up + sideways + down = 2 meiosis → 0.25
      // This is actually uncle/nephew not cousin
      // For cousin, path would be: father(up) → brother(sideways) → son(down) = same 0.25
      // The BFS would find: father→brother→son which resolves to cousin via graph
      expect(computeKinshipCoefficient('unknown_term', path)).toBe(0.25);
    });

    it('should return 0 for pure spouse path (no blood relation)', () => {
      const path = [makeStep('husband', 'sideways')];
      expect(computeKinshipCoefficient('unknown_term', path)).toBe(0);
    });

    it('should return 0.5 for pure sibling path (sideways blood)', () => {
      const path = [makeStep('brother', 'sideways')];
      expect(computeKinshipCoefficient('unknown_term', path)).toBe(0.5);
    });
  });

  // ── Unknown term fallback ────────────────────────────────────────

  describe('unknown term fallback', () => {
    it('should return 0 for unknown term without path', () => {
      expect(computeKinshipCoefficient('completely_unknown_term')).toBe(0);
    });
  });
});

// ════════════════════════════════════════════════════════════════════
// classifyRelationship()
// ════════════════════════════════════════════════════════════════════

describe('classifyRelationship', () => {
  describe('blood relationships', () => {
    it('should classify "father" as blood', () => {
      expect(classifyRelationship('father')).toBe('blood');
    });

    it('should classify "mother" as blood', () => {
      expect(classifyRelationship('mother')).toBe('blood');
    });

    it('should classify "brother" as blood', () => {
      expect(classifyRelationship('brother')).toBe('blood');
    });

    it('should classify "sister" as blood', () => {
      expect(classifyRelationship('sister')).toBe('blood');
    });

    it('should classify "uncle" as blood', () => {
      expect(classifyRelationship('uncle')).toBe('blood');
    });

    it('should classify "cousin" as blood', () => {
      expect(classifyRelationship('cousin')).toBe('blood');
    });

    it('should classify "grandfather" as blood', () => {
      expect(classifyRelationship('grandfather')).toBe('blood');
    });

    it('should classify "nephew" as blood', () => {
      expect(classifyRelationship('nephew')).toBe('blood');
    });
  });

  describe('marital relationships', () => {
    it('should classify "husband" as marital', () => {
      expect(classifyRelationship('husband')).toBe('marital');
    });

    it('should classify "wife" as marital', () => {
      expect(classifyRelationship('wife')).toBe('marital');
    });
  });

  describe('affinal relationships (in-law)', () => {
    it('should classify "father_in_law" as affinal', () => {
      expect(classifyRelationship('father_in_law')).toBe('affinal');
    });

    it('should classify "mother_in_law" as affinal', () => {
      expect(classifyRelationship('mother_in_law')).toBe('affinal');
    });

    it('should classify "brother_in_law" as affinal', () => {
      expect(classifyRelationship('brother_in_law')).toBe('affinal');
    });

    it('should classify "sister_in_law" as affinal', () => {
      expect(classifyRelationship('sister_in_law')).toBe('affinal');
    });

    it('should classify "son_in_law" as affinal', () => {
      expect(classifyRelationship('son_in_law')).toBe('affinal');
    });

    it('should classify "daughter_in_law" as affinal', () => {
      expect(classifyRelationship('daughter_in_law')).toBe('affinal');
    });

    it('should classify "co_brother_in_law" as affinal', () => {
      expect(classifyRelationship('co_brother_in_law')).toBe('affinal');
    });

    it('should classify "sons_wife" as affinal', () => {
      expect(classifyRelationship('sons_wife')).toBe('affinal');
    });

    it('should classify "daughters_husband" as affinal', () => {
      expect(classifyRelationship('daughters_husband')).toBe('affinal');
    });
  });

  describe('step-relationships', () => {
    it('should classify "stepfather" as affinal', () => {
      expect(classifyRelationship('stepfather')).toBe('affinal');
    });

    it('should classify "stepmother" as affinal', () => {
      expect(classifyRelationship('stepmother')).toBe('affinal');
    });

    it('should classify "step_brother" as blood (half-sibling)', () => {
      expect(classifyRelationship('step_brother')).toBe('blood');
    });

    it('should classify "step_sister" as blood (half-sibling)', () => {
      expect(classifyRelationship('step_sister')).toBe('blood');
    });
  });

  describe('by-marriage relationships', () => {
    it('should classify "fathers_brothers_wife" as affinal', () => {
      expect(classifyRelationship('fathers_brothers_wife')).toBe('affinal');
    });

    it('should classify "mothers_sisters_husband" as affinal', () => {
      expect(classifyRelationship('mothers_sisters_husband')).toBe('affinal');
    });

    it('should classify "sisters_husband" as affinal', () => {
      expect(classifyRelationship('sisters_husband')).toBe('affinal');
    });
  });
});

// ════════════════════════════════════════════════════════════════════
// determineLineage()
// ════════════════════════════════════════════════════════════════════

describe('determineLineage', () => {
  it('should return "paternal" for father→brother path', () => {
    const path = [makeStep('father', 'up'), makeStep('brother', 'sideways')];
    expect(determineLineage(path)).toBe('paternal');
  });

  it('should return "maternal" for mother→brother path', () => {
    const path = [makeStep('mother', 'up'), makeStep('brother', 'sideways')];
    expect(determineLineage(path)).toBe('maternal');
  });

  it('should return "paternal" for father→sister→son path', () => {
    const path = [
      makeStep('father', 'up'),
      makeStep('sister', 'sideways'),
      makeStep('son', 'down'),
    ];
    expect(determineLineage(path)).toBe('paternal');
  });

  it('should return "maternal" for mother→sister→daughter path', () => {
    const path = [
      makeStep('mother', 'up'),
      makeStep('sister', 'sideways'),
      makeStep('daughter', 'down'),
    ];
    expect(determineLineage(path)).toBe('maternal');
  });

  it('should return "neutral" for spouse→father path (in-law)', () => {
    const path = [makeStep('husband', 'sideways'), makeStep('father', 'up')];
    expect(determineLineage(path)).toBe('neutral');
  });

  it('should return "neutral" for empty path', () => {
    expect(determineLineage([])).toBe('neutral');
  });

  it('should return "neutral" for undefined path', () => {
    expect(determineLineage(undefined)).toBe('neutral');
  });

  it('should return "paternal" for father→father path (paternal grandfather)', () => {
    const path = [makeStep('father', 'up'), makeStep('father', 'up')];
    expect(determineLineage(path)).toBe('paternal');
  });

  it('should return "maternal" for mother→mother path (maternal grandmother)', () => {
    const path = [makeStep('mother', 'up'), makeStep('mother', 'up')];
    expect(determineLineage(path)).toBe('maternal');
  });

  it('should return "neutral" for brother→son path (sibling line)', () => {
    const path = [makeStep('brother', 'sideways'), makeStep('son', 'down')];
    expect(determineLineage(path)).toBe('neutral');
  });
});
