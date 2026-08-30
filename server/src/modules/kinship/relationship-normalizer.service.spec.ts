import { RelationshipNormalizerService } from './relationship-normalizer.service';
import { CanonicalIdService } from './canonical-id.service';

describe('RelationshipNormalizerService (v3.0 §8)', () => {
  let service: RelationshipNormalizerService;

  beforeEach(() => {
    service = new RelationshipNormalizerService(new CanonicalIdService());
  });

  describe('normalize — fundamental terms', () => {
    it('maps "father" → parent edge (forward direction)', () => {
      const r = service.normalize('father', 'en');
      expect(r.fundamentalEdge).toBe('parent');
      expect(r.direction).toBe('forward');
      expect(r.isDerived).toBe(false);
      expect(r.isUnknown).toBe(false);
    });

    it('maps "son" → parent edge (reverse direction)', () => {
      const r = service.normalize('son', 'en');
      expect(r.fundamentalEdge).toBe('parent');
      expect(r.direction).toBe('reverse');
    });

    it('maps "daughter" → parent edge (reverse direction)', () => {
      const r = service.normalize('daughter', 'en');
      expect(r.fundamentalEdge).toBe('parent');
      expect(r.direction).toBe('reverse');
    });

    it('maps "husband" → spouse edge (bidirectional)', () => {
      const r = service.normalize('husband', 'en');
      expect(r.fundamentalEdge).toBe('spouse');
      expect(r.direction).toBe('bidirectional');
    });

    it('maps "wife" → spouse edge (bidirectional)', () => {
      const r = service.normalize('wife', 'en');
      expect(r.fundamentalEdge).toBe('spouse');
      expect(r.direction).toBe('bidirectional');
    });

    it('maps "adoptive father" → adoptive_parent edge', () => {
      const r = service.normalize('adoptive father', 'en');
      expect(r.fundamentalEdge).toBe('adoptive_parent');
    });

    it('maps "step mother" → step_parent edge', () => {
      const r = service.normalize('step mother', 'en');
      expect(r.fundamentalEdge).toBe('step_parent');
    });

    it('maps Hindi "पिता" → parent edge (forward)', () => {
      const r = service.normalize('पिता', 'hi');
      expect(r.fundamentalEdge).toBe('parent');
    });

    it('maps Tamil "அப்பா" → parent edge (forward)', () => {
      const r = service.normalize('அப்பா', 'ta');
      expect(r.fundamentalEdge).toBe('parent');
    });
  });

  describe('normalize — derived terms', () => {
    it('returns fundamentalEdge=null for "grandfather" + missingEdges hint', () => {
      const r = service.normalize('grandfather', 'en');
      expect(r.fundamentalEdge).toBeNull();
      expect(r.isDerived).toBe(true);
      expect(r.missingEdges.length).toBeGreaterThan(0);
      expect(r.missingEdges[0].edge).toBe('parent');
    });

    it('returns fundamentalEdge=null for "uncle"', () => {
      const r = service.normalize('uncle', 'en');
      expect(r.fundamentalEdge).toBeNull();
      expect(r.isDerived).toBe(true);
    });

    it('returns fundamentalEdge=null for "cousin"', () => {
      const r = service.normalize('cousin', 'en');
      expect(r.fundamentalEdge).toBeNull();
      expect(r.isDerived).toBe(true);
    });

    it('returns fundamentalEdge=null for "brother" (must add shared parent)', () => {
      const r = service.normalize('brother', 'en');
      expect(r.fundamentalEdge).toBeNull();
      expect(r.isDerived).toBe(true);
      expect(r.missingEdges[0].edge).toBe('parent');
    });

    it('returns fundamentalEdge=null for "father in law" with spouse hint', () => {
      const r = service.normalize('father in law', 'en');
      expect(r.fundamentalEdge).toBeNull();
      expect(r.missingEdges[0].edge).toBe('spouse');
    });

    it('returns fundamentalEdge=null for Hindi "दादा" (grandfather)', () => {
      const r = service.normalize('दादा', 'hi');
      expect(r.fundamentalEdge).toBeNull();
      expect(r.isDerived).toBe(true);
    });
  });

  describe('normalize — unknown input', () => {
    it('returns isUnknown=true for unrecognized term', () => {
      const r = service.normalize('xyzzy', 'en');
      expect(r.isUnknown).toBe(true);
      expect(r.fundamentalEdge).toBeNull();
    });

    it('returns isUnknown=true for empty input', () => {
      const r = service.normalize('', 'en');
      expect(r.isUnknown).toBe(true);
    });
  });

  describe('isFundamentalEdge', () => {
    it('returns true for parent, spouse, adoptive_parent, step_parent', () => {
      expect(service.isFundamentalEdge('parent')).toBe(true);
      expect(service.isFundamentalEdge('spouse')).toBe(true);
      expect(service.isFundamentalEdge('adoptive_parent')).toBe(true);
      expect(service.isFundamentalEdge('step_parent')).toBe(true);
    });

    it('returns false for derived / legacy keys', () => {
      expect(service.isFundamentalEdge('father')).toBe(false);
      expect(service.isFundamentalEdge('grandfather')).toBe(false);
      expect(service.isFundamentalEdge('uncle')).toBe(false);
      expect(service.isFundamentalEdge('cousin')).toBe(false);
    });
  });

  describe('listFundamentalEdges', () => {
    it('returns the 4 fundamental edges', () => {
      expect(service.listFundamentalEdges()).toEqual([
        'parent', 'spouse', 'adoptive_parent', 'step_parent',
      ]);
    });
  });

  describe('inverseEdge (static)', () => {
    it('returns the same edge type (all 4 are symmetric in inverse)', () => {
      expect(RelationshipNormalizerService.inverseEdge('parent')).toBe('parent');
      expect(RelationshipNormalizerService.inverseEdge('spouse')).toBe('spouse');
      expect(RelationshipNormalizerService.inverseEdge('adoptive_parent')).toBe('adoptive_parent');
      expect(RelationshipNormalizerService.inverseEdge('step_parent')).toBe('step_parent');
    });
  });
});
