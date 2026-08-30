import { RelationshipValidator, ValidationInput } from './relationship.validator';

describe('RelationshipValidator (v3.0 §12)', () => {
  let validator: RelationshipValidator;

  beforeEach(() => {
    validator = new RelationshipValidator();
  });

  // Helper: build an input with no existing edges.
  function baseInput(overrides: Partial<ValidationInput>): ValidationInput {
    return {
      familyId: 'fam-1',
      fromPersonId: 'a',
      toPersonId: 'b',
      edge: 'parent',
      existingEdges: [],
      ...overrides,
    };
  }

  describe('Rule 1: Reject self-relationships', () => {
    it('rejects when fromPersonId === toPersonId', () => {
      const result = validator.validate(baseInput({
        fromPersonId: 'a',
        toPersonId: 'a',
        edge: 'parent',
      }));
      expect(result.valid).toBe(false);
      expect(result.failures.some(f => f.rule === 'NO_SELF_RELATIONSHIP')).toBe(true);
    });

    it('passes when fromPersonId !== toPersonId', () => {
      const result = validator.validate(baseInput({
        fromPersonId: 'a',
        toPersonId: 'b',
      }));
      expect(result.failures.some(f => f.rule === 'NO_SELF_RELATIONSHIP')).toBe(false);
    });
  });

  describe('Rule 2: Reject duplicate fundamental edges', () => {
    it('rejects duplicate parent edge in same direction', () => {
      const result = validator.validate(baseInput({
        fromPersonId: 'a',
        toPersonId: 'b',
        edge: 'parent',
        existingEdges: [
          { fromPersonId: 'a', toPersonId: 'b', edge: 'parent' },
        ],
      }));
      expect(result.valid).toBe(false);
      expect(result.failures.some(f => f.rule === 'NO_DUPLICATE_EDGE')).toBe(true);
    });

    it('rejects duplicate parent edge in reverse direction', () => {
      const result = validator.validate(baseInput({
        fromPersonId: 'a',
        toPersonId: 'b',
        edge: 'parent',
        existingEdges: [
          { fromPersonId: 'b', toPersonId: 'a', edge: 'parent' },
        ],
      }));
      expect(result.valid).toBe(false);
      expect(result.failures.some(f => f.rule === 'NO_DUPLICATE_EDGE')).toBe(true);
    });

    it('rejects duplicate spouse edge (any direction)', () => {
      const result = validator.validate(baseInput({
        edge: 'spouse',
        fromPersonId: 'a',
        toPersonId: 'b',
        existingEdges: [
          { fromPersonId: 'b', toPersonId: 'a', edge: 'spouse' },
        ],
      }));
      expect(result.valid).toBe(false);
      expect(result.failures.some(f => f.rule === 'NO_DUPLICATE_EDGE')).toBe(true);
    });

    it('does NOT reject non-duplicate edges', () => {
      const result = validator.validate(baseInput({
        fromPersonId: 'a',
        toPersonId: 'b',
        edge: 'parent',
        existingEdges: [
          { fromPersonId: 'a', toPersonId: 'b', edge: 'spouse' },
        ],
      }));
      expect(result.failures.some(f => f.rule === 'NO_DUPLICATE_EDGE')).toBe(false);
    });
  });

  describe('Rule 3: Reject circular ancestry', () => {
    it('rejects when toPerson already has fromPerson as ancestor', () => {
      // b's parent is a; we're now trying to make a's parent be b → cycle.
      const result = validator.validate(baseInput({
        fromPersonId: 'a',
        toPersonId: 'b',
        edge: 'parent',
        existingEdges: [
          { fromPersonId: 'b', toPersonId: 'a', edge: 'parent' }, // b's parent is a
        ],
      }));
      expect(result.valid).toBe(false);
      expect(result.failures.some(f => f.rule === 'NO_CIRCULAR_ANCESTRY')).toBe(true);
    });

    it('rejects multi-level circular ancestry', () => {
      // c→b→a parent chain. Trying to add a→c parent creates a cycle.
      const result = validator.validate(baseInput({
        fromPersonId: 'a',
        toPersonId: 'c',
        edge: 'parent',
        existingEdges: [
          { fromPersonId: 'c', toPersonId: 'b', edge: 'parent' },
          { fromPersonId: 'b', toPersonId: 'a', edge: 'parent' },
        ],
      }));
      expect(result.valid).toBe(false);
      expect(result.failures.some(f => f.rule === 'NO_CIRCULAR_ANCESTRY')).toBe(true);
    });

    it('passes when no cycle would be created', () => {
      const result = validator.validate(baseInput({
        fromPersonId: 'a',
        toPersonId: 'b',
        edge: 'parent',
        existingEdges: [
          { fromPersonId: 'c', toPersonId: 'b', edge: 'parent' }, // c is parent of b
        ],
      }));
      expect(result.failures.some(f => f.rule === 'NO_CIRCULAR_ANCESTRY')).toBe(false);
    });
  });

  describe('Rule 4: Reject invalid spouse', () => {
    it('rejects spouse to ancestor', () => {
      const result = validator.validate(baseInput({
        edge: 'spouse',
        fromPersonId: 'a',
        toPersonId: 'b',
        existingEdges: [
          { fromPersonId: 'a', toPersonId: 'b', edge: 'parent' }, // a's parent is b
        ],
      }));
      expect(result.valid).toBe(false);
      expect(result.failures.some(f => f.rule === 'NO_SPOUSE_TO_ANCESTOR_OR_DESCENDANT')).toBe(true);
    });

    it('rejects spouse to descendant', () => {
      const result = validator.validate(baseInput({
        edge: 'spouse',
        fromPersonId: 'b',
        toPersonId: 'a',
        existingEdges: [
          { fromPersonId: 'a', toPersonId: 'b', edge: 'parent' }, // a's parent is b → a is descendant of b
        ],
      }));
      expect(result.valid).toBe(false);
      expect(result.failures.some(f => f.rule === 'NO_SPOUSE_TO_ANCESTOR_OR_DESCENDANT')).toBe(true);
    });

    it('allows spouse to non-ancestor non-descendant', () => {
      const result = validator.validate(baseInput({
        edge: 'spouse',
        fromPersonId: 'a',
        toPersonId: 'b',
        existingEdges: [],
      }));
      expect(result.failures.some(f => f.rule === 'NO_SPOUSE_TO_ANCESTOR_OR_DESCENDANT')).toBe(false);
    });
  });

  describe('Rule 5: Reject contradictory relationships', () => {
    it('rejects spouse when parent edge already exists (forward)', () => {
      const result = validator.validate(baseInput({
        edge: 'spouse',
        fromPersonId: 'a',
        toPersonId: 'b',
        existingEdges: [
          { fromPersonId: 'a', toPersonId: 'b', edge: 'parent' },
        ],
      }));
      expect(result.valid).toBe(false);
      expect(result.failures.some(f => f.rule === 'NO_CONTRADICTORY_RELATIONSHIP')).toBe(true);
    });

    it('rejects parent when spouse edge already exists', () => {
      const result = validator.validate(baseInput({
        edge: 'parent',
        fromPersonId: 'a',
        toPersonId: 'b',
        existingEdges: [
          { fromPersonId: 'a', toPersonId: 'b', edge: 'spouse' },
        ],
      }));
      expect(result.valid).toBe(false);
      expect(result.failures.some(f => f.rule === 'NO_CONTRADICTORY_RELATIONSHIP')).toBe(true);
    });

    it('does not flag contradiction for unrelated edges', () => {
      const result = validator.validate(baseInput({
        edge: 'parent',
        fromPersonId: 'a',
        toPersonId: 'b',
        existingEdges: [
          { fromPersonId: 'c', toPersonId: 'd', edge: 'spouse' }, // different persons
        ],
      }));
      expect(result.failures.some(f => f.rule === 'NO_CONTRADICTORY_RELATIONSHIP')).toBe(false);
    });
  });

  describe('validateOrThrow', () => {
    it('throws BadRequestException for self-relationship', () => {
      expect(() => validator.validateOrThrow(baseInput({
        fromPersonId: 'a',
        toPersonId: 'a',
      }))).toThrow();
    });

    it('throws ConflictException for duplicate edge', () => {
      expect(() => validator.validateOrThrow(baseInput({
        fromPersonId: 'a',
        toPersonId: 'b',
        edge: 'parent',
        existingEdges: [{ fromPersonId: 'a', toPersonId: 'b', edge: 'parent' }],
      }))).toThrow();
    });

    it('does NOT throw when validation passes', () => {
      expect(() => validator.validateOrThrow(baseInput({
        fromPersonId: 'a',
        toPersonId: 'b',
        edge: 'parent',
        existingEdges: [],
      }))).not.toThrow();
    });
  });

  describe('Integration scenarios', () => {
    it('rejects a grandparent-spouse attempt (multiple failures)', () => {
      const result = validator.validate(baseInput({
        edge: 'spouse',
        fromPersonId: 'a',
        toPersonId: 'd',
        existingEdges: [
          { fromPersonId: 'a', toPersonId: 'b', edge: 'parent' }, // a's parent is b
          { fromPersonId: 'b', toPersonId: 'c', edge: 'parent' }, // b's parent is c
          { fromPersonId: 'c', toPersonId: 'd', edge: 'parent' }, // c's parent is d → d is great-grandparent of a
        ],
      }));
      expect(result.valid).toBe(false);
      // Should fail on Rule 4 (spouse to ancestor) — d is an ancestor of a.
      expect(result.failures.some(f => f.rule === 'NO_SPOUSE_TO_ANCESTOR_OR_DESCENDANT')).toBe(true);
    });
  });
});
