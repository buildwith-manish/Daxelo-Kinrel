import { CanonicalIdService } from './canonical-id.service';

describe('CanonicalIdService (v3.0 §4)', () => {
  let service: CanonicalIdService;

  beforeEach(() => {
    service = new CanonicalIdService();
  });

  describe('normalizeToCanonical — English (en)', () => {
    it('maps "father" to PARENT (forward)', () => {
      const r = service.normalizeToCanonical('father', 'en');
      expect(r.canonicalId).toBe('PARENT');
      expect(r.direction).toBe('forward');
      expect(r.isDerived).toBe(false);
      expect(r.englishLabel).toBe('Father');
    });

    it('maps "dad", "papa", "pop" aliases to PARENT', () => {
      for (const term of ['dad', 'papa', 'pop', 'pa']) {
        const r = service.normalizeToCanonical(term, 'en');
        expect(r.canonicalId).toBe('PARENT');
      }
    });

    it('maps "mother" to PARENT (forward)', () => {
      const r = service.normalizeToCanonical('mother', 'en');
      expect(r.canonicalId).toBe('PARENT');
      expect(r.direction).toBe('forward');
      expect(r.englishLabel).toBe('Mother');
    });

    it('maps "son" to PARENT (reverse direction)', () => {
      const r = service.normalizeToCanonical('son', 'en');
      expect(r.canonicalId).toBe('PARENT');
      expect(r.direction).toBe('reverse');
      expect(r.englishLabel).toBe('Son');
    });

    it('maps "daughter" to PARENT (reverse direction)', () => {
      const r = service.normalizeToCanonical('daughter', 'en');
      expect(r.canonicalId).toBe('PARENT');
      expect(r.direction).toBe('reverse');
    });

    it('maps "husband" and "wife" to SPOUSE', () => {
      expect(service.normalizeToCanonical('husband', 'en').canonicalId).toBe('SPOUSE');
      expect(service.normalizeToCanonical('wife', 'en').canonicalId).toBe('SPOUSE');
    });

    it('maps "adoptive father" to ADOPTIVE_PARENT', () => {
      const r = service.normalizeToCanonical('adoptive father', 'en');
      expect(r.canonicalId).toBe('ADOPTIVE_PARENT');
      expect(r.direction).toBe('forward');
    });

    it('maps "step mother" to STEP_PARENT', () => {
      const r = service.normalizeToCanonical('step mother', 'en');
      expect(r.canonicalId).toBe('STEP_PARENT');
      expect(r.direction).toBe('forward');
    });

    it('maps "stepfather" (one word) to STEP_PARENT', () => {
      expect(service.normalizeToCanonical('stepfather', 'en').canonicalId).toBe('STEP_PARENT');
    });
  });

  describe('normalizeToCanonical — Derived terms (must NOT be stored)', () => {
    it('maps "grandfather" to DERIVED with missingEdges hint', () => {
      const r = service.normalizeToCanonical('grandfather', 'en');
      expect(r.canonicalId).toBe('DERIVED');
      expect(r.isDerived).toBe(true);
      expect(r.missingEdges?.length).toBeGreaterThan(0);
      expect(r.missingEdges?.[0].edge).toBe('parent');
    });

    it('maps "uncle" to DERIVED with missingEdges hint', () => {
      const r = service.normalizeToCanonical('uncle', 'en');
      expect(r.canonicalId).toBe('DERIVED');
      expect(r.isDerived).toBe(true);
      expect(r.missingEdges?.[0].edge).toBe('parent');
    });

    it('maps "cousin" to DERIVED', () => {
      const r = service.normalizeToCanonical('cousin', 'en');
      expect(r.canonicalId).toBe('DERIVED');
      expect(r.isDerived).toBe(true);
    });

    it('maps "brother" and "sister" to DERIVED (must add shared parent)', () => {
      expect(service.normalizeToCanonical('brother', 'en').canonicalId).toBe('DERIVED');
      expect(service.normalizeToCanonical('sister', 'en').canonicalId).toBe('DERIVED');
    });

    it('maps "father in law" to DERIVED with spouse-then-parent hint', () => {
      const r = service.normalizeToCanonical('father in law', 'en');
      expect(r.canonicalId).toBe('DERIVED');
      expect(r.missingEdges?.[0].edge).toBe('spouse');
    });

    it('maps "nephew" and "niece" to DERIVED', () => {
      expect(service.normalizeToCanonical('nephew', 'en').canonicalId).toBe('DERIVED');
      expect(service.normalizeToCanonical('niece', 'en').canonicalId).toBe('DERIVED');
    });
  });

  describe('normalizeToCanonical — Multi-locale fallback', () => {
    it('maps Hindi "पिता" → PARENT', () => {
      expect(service.normalizeToCanonical('पिता', 'hi').canonicalId).toBe('PARENT');
    });

    it('maps Hindi "पापा" → PARENT', () => {
      expect(service.normalizeToCanonical('पापा', 'hi').canonicalId).toBe('PARENT');
    });

    it('maps Hindi "माता" → PARENT', () => {
      expect(service.normalizeToCanonical('माता', 'hi').canonicalId).toBe('PARENT');
    });

    it('maps Tamil "அப்பா" → PARENT', () => {
      expect(service.normalizeToCanonical('அப்பா', 'ta').canonicalId).toBe('PARENT');
    });

    it('maps Tamil "அம்மா" → PARENT', () => {
      expect(service.normalizeToCanonical('அம்மா', 'ta').canonicalId).toBe('PARENT');
    });

    it('falls back to English when term not found in requested locale', () => {
      // 'dad' is in English synonyms but not Hindi — should fall back.
      expect(service.normalizeToCanonical('dad', 'hi').canonicalId).toBe('PARENT');
    });

    it('falls back to English when locale is unknown', () => {
      expect(service.normalizeToCanonical('father', 'fr').canonicalId).toBe('PARENT');
    });

    it('maps Hindi "दादा" → DERIVED (paternal grandfather)', () => {
      const r = service.normalizeToCanonical('दादा', 'hi');
      expect(r.canonicalId).toBe('DERIVED');
      expect(r.isDerived).toBe(true);
    });
  });

  describe('normalizeToCanonical — Unknown input', () => {
    it('returns UNKNOWN for empty input', () => {
      const r = service.normalizeToCanonical('', 'en');
      expect(r.canonicalId).toBe('UNKNOWN');
      expect(r.isDerived).toBe(false);
    });

    it('returns UNKNOWN for unrecognized term', () => {
      const r = service.normalizeToCanonical('xyzzy_not_a_term', 'en');
      expect(r.canonicalId).toBe('UNKNOWN');
    });
  });

  describe('listFundamentalCanonicalIds', () => {
    it('returns the 4 fundamental IDs', () => {
      const ids = service.listFundamentalCanonicalIds();
      expect(ids).toEqual(['PARENT', 'SPOUSE', 'ADOPTIVE_PARENT', 'STEP_PARENT']);
    });
  });

  describe('listSupportedLocales', () => {
    it('includes en, hi, ta, te, kn, bn, mr, gu', () => {
      const locales = service.listSupportedLocales();
      expect(locales).toContain('en');
      expect(locales).toContain('hi');
      expect(locales).toContain('ta');
      expect(locales).toContain('te');
      expect(locales).toContain('kn');
      expect(locales).toContain('bn');
      expect(locales).toContain('mr');
      expect(locales).toContain('gu');
    });
  });
});
