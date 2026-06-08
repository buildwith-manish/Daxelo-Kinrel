import { KinshipService, KinshipTerm } from './kinship.service';

describe('KinshipService', () => {
  let service: KinshipService;

  beforeEach(() => {
    service = new KinshipService();
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  // ── 1. Basic Lookup by Key ─────────────────────────────────────────

  describe('lookup by key', () => {
    it('should find "father" by key with correct Hindi translation', () => {
      const results = service.lookup({ key: 'father' });
      expect(results).toHaveLength(1);
      expect(results[0].relationshipKey).toBe('father');
      expect(results[0].translations.hi.native).toBe('पिता');
      expect(results[0].translations.hi.latin).toBe('Pita');
    });

    it('should find "mother" by key with correct Hindi translation', () => {
      const results = service.lookup({ key: 'mother' });
      expect(results).toHaveLength(1);
      expect(results[0].relationshipKey).toBe('mother');
      expect(results[0].translations.hi.native).toBe('माता');
      expect(results[0].translations.hi.latin).toBe('Mata');
    });

    it('should find "brother" with correct Marathi translation', () => {
      const results = service.lookup({ key: 'brother' });
      expect(results).toHaveLength(1);
      expect(results[0].translations.mr.native).toBe('भाऊ');
      expect(results[0].translations.mr.latin).toBe('Bhau');
    });

    it('should find "sister" with correct Tamil translation', () => {
      const results = service.lookup({ key: 'sister' });
      expect(results).toHaveLength(1);
      expect(results[0].translations.ta.native).toBe('சகோதரி');
      expect(results[0].translations.ta.latin).toBe('Sagothari');
    });

    it('should return empty array for invalid relationshipKey', () => {
      const results = service.lookup({ key: 'nonexistent_key' });
      expect(results).toEqual([]);
    });

    it('should find extended family terms like "fathers_brother"', () => {
      const results = service.lookup({ key: 'fathers_brother' });
      expect(results).toHaveLength(1);
      expect(results[0].englishTerm).toContain('Uncle');
      expect(results[0].translations.hi.native).toBe('चाचा');
    });

    it('should find in-law terms like "father_in_law"', () => {
      const results = service.lookup({ key: 'father_in_law' });
      expect(results).toHaveLength(1);
      expect(results[0].relationshipCategory).toBe('in_laws');
      expect(results[0].translations.hi.native).toBe('ससुर');
    });

    it('should find "grandfather_paternal" with correct Hindi translation', () => {
      const results = service.lookup({ key: 'grandfather_paternal' });
      expect(results).toHaveLength(1);
      expect(results[0].translations.hi.native).toBe('दादा');
    });
  });

  // ── 2. Search by Term ──────────────────────────────────────────────

  describe('search by term and language', () => {
    it('should find "father" by Hindi native term "पिता"', () => {
      const results = service.searchByTermAndLang('पिता', 'hi', 20);
      expect(results.length).toBeGreaterThanOrEqual(1);
      const father = results.find((t) => t.relationshipKey === 'father');
      expect(father).toBeDefined();
      expect(father!.translations.hi.native).toBe('पिता');
    });

    it('should find "father" by Latin transliteration "Pita"', () => {
      const results = service.searchByTermAndLang('Pita', 'hi', 20);
      expect(results.length).toBeGreaterThanOrEqual(1);
      const father = results.find((t) => t.relationshipKey === 'father');
      expect(father).toBeDefined();
    });

    it('should find "father" by alias "papa"', () => {
      const results = service.searchByTermAndLang('papa', 'hi', 20);
      expect(results.length).toBeGreaterThanOrEqual(1);
      const father = results.find((t) => t.relationshipKey === 'father');
      expect(father).toBeDefined();
    });

    it('should find "grandfather_paternal" by Hindi native "दादा"', () => {
      const results = service.searchByTermAndLang('दादा', 'hi', 20);
      expect(results.length).toBeGreaterThanOrEqual(1);
      const grandfather = results.find((t) => t.relationshipKey === 'grandfather_paternal');
      expect(grandfather).toBeDefined();
    });

    it('should return empty array for non-existent term', () => {
      const results = service.searchByTermAndLang('xyznonexistent', 'hi', 20);
      expect(results).toEqual([]);
    });

    it('should filter by language — only return terms with requested language', () => {
      const results = service.searchByTermAndLang('father', 'hi', 20);
      expect(results.length).toBeGreaterThanOrEqual(1);
      for (const term of results) {
        expect(term.translations.hi).toBeDefined();
      }
    });

    it('should not filter when lang is "en"', () => {
      const results = service.searchByTermAndLang('father', 'en', 20);
      // "en" should skip the language filter, returning all matching terms
      expect(results.length).toBeGreaterThanOrEqual(1);
    });

    it('should respect the limit parameter', () => {
      const results = service.searchByTermAndLang('a', 'hi', 3);
      expect(results.length).toBeLessThanOrEqual(3);
    });

    it('should handle empty string search gracefully', () => {
      const results = service.searchByTermAndLang('', 'hi', 20);
      // Empty search should return all terms (since lookup with empty search does not filter)
      expect(results.length).toBeGreaterThanOrEqual(1);
    });

    it('should search case-insensitively', () => {
      const upper = service.searchByTermAndLang('PAPA', 'hi', 20);
      const lower = service.searchByTermAndLang('papa', 'hi', 20);
      expect(upper.length).toBe(lower.length);
    });
  });

  // ── 3. getByKey ────────────────────────────────────────────────────

  describe('getByKey', () => {
    it('should return the correct term for "father"', () => {
      const term = service.getByKey('father');
      expect(term).toBeDefined();
      expect(term!.relationshipKey).toBe('father');
      expect(term!.englishTerm).toBe('Father');
    });

    it('should return undefined for non-existent key', () => {
      const term = service.getByKey('nonexistent_key');
      expect(term).toBeUndefined();
    });

    it('should return term with all expected fields', () => {
      const term = service.getByKey('mother');
      expect(term).toBeDefined();
      expect(term!.relationshipKey).toBe('mother');
      expect(term!.englishTerm).toBe('Mother');
      expect(term!.gender).toBe('female');
      expect(term!.lineage).toBe('neutral');
      expect(term!.relationshipCategory).toBe('immediate_family');
      expect(term!.translations).toBeDefined();
      expect(term!.aliases).toBeDefined();
    });

    it('should return correct term for complex key like "brother_in_law_wifes_brother"', () => {
      const term = service.getByKey('brother_in_law_wifes_brother');
      expect(term).toBeDefined();
      expect(term!.translations.hi.native).toBe('साला');
    });
  });

  // ── 4. Free-text Search ────────────────────────────────────────────

  describe('search (free-text)', () => {
    it('should find terms matching English term', () => {
      const results = service.search('Father');
      expect(results.length).toBeGreaterThanOrEqual(1);
      expect(results.some((t) => t.relationshipKey === 'father')).toBe(true);
    });

    it('should find terms matching relationship key', () => {
      const results = service.search('father_in_law');
      expect(results.length).toBeGreaterThanOrEqual(1);
      expect(results.some((t) => t.relationshipKey === 'father_in_law')).toBe(true);
    });

    it('should find terms matching alias', () => {
      const results = service.search('bhabhi');
      expect(results.length).toBeGreaterThanOrEqual(1);
      // "bhabhi" is an alias for multiple terms
    });

    it('should find terms matching native translation', () => {
      const results = service.search('माता');
      expect(results.length).toBeGreaterThanOrEqual(1);
      expect(results.some((t) => t.relationshipKey === 'mother')).toBe(true);
    });

    it('should find terms matching latin transliteration', () => {
      const results = service.search('Chacha');
      expect(results.length).toBeGreaterThanOrEqual(1);
      expect(results.some((t) => t.relationshipKey === 'fathers_brother')).toBe(true);
    });

    it('should return empty for non-matching search', () => {
      const results = service.search('zzzznonexistent');
      expect(results).toEqual([]);
    });

    it('should be case-insensitive', () => {
      const upper = service.search('FATHER');
      const lower = service.search('father');
      expect(upper.length).toBe(lower.length);
    });

    it('should handle partial matches', () => {
      const results = service.search('grand');
      expect(results.length).toBeGreaterThanOrEqual(1);
      // Should match grandfather, grandmother, grandson, granddaughter, etc.
      expect(results.some((t) => t.relationshipKey.includes('grand'))).toBe(true);
    });
  });

  // ── 5. Lookup with Filters (category, gender, lineage) ─────────────

  describe('lookup with filters', () => {
    it('should filter by category "in_laws"', () => {
      const results = service.lookup({ category: 'in_laws' });
      expect(results.length).toBeGreaterThanOrEqual(1);
      for (const term of results) {
        expect(term.relationshipCategory).toBe('in_laws');
      }
    });

    it('should filter by category "extended_paternal"', () => {
      const results = service.lookup({ category: 'extended_paternal' });
      expect(results.length).toBeGreaterThanOrEqual(1);
      for (const term of results) {
        expect(term.relationshipCategory).toBe('extended_paternal');
      }
    });

    it('should filter by category "extended_maternal"', () => {
      const results = service.lookup({ category: 'extended_maternal' });
      expect(results.length).toBeGreaterThanOrEqual(1);
      for (const term of results) {
        expect(term.relationshipCategory).toBe('extended_maternal');
      }
    });

    it('should return empty for invalid category', () => {
      const results = service.lookup({ category: 'nonexistent_category' });
      expect(results).toEqual([]);
    });

    it('should filter by gender "male"', () => {
      const results = service.lookup({ gender: 'male' });
      expect(results.length).toBeGreaterThanOrEqual(1);
      for (const term of results) {
        expect(term.gender).toBe('male');
      }
    });

    it('should filter by gender "female"', () => {
      const results = service.lookup({ gender: 'female' });
      expect(results.length).toBeGreaterThanOrEqual(1);
      for (const term of results) {
        expect(term.gender).toBe('female');
      }
    });

    it('should filter by lineage "paternal"', () => {
      const results = service.lookup({ lineage: 'paternal' });
      expect(results.length).toBeGreaterThanOrEqual(1);
      for (const term of results) {
        expect(term.lineage).toBe('paternal');
      }
    });

    it('should filter by lineage "maternal"', () => {
      const results = service.lookup({ lineage: 'maternal' });
      expect(results.length).toBeGreaterThanOrEqual(1);
      for (const term of results) {
        expect(term.lineage).toBe('maternal');
      }
    });

    it('should combine search and category filter', () => {
      const results = service.lookup({ search: 'uncle', category: 'extended_paternal' });
      expect(results.length).toBeGreaterThanOrEqual(1);
      for (const term of results) {
        expect(term.relationshipCategory).toBe('extended_paternal');
      }
    });

    it('should combine search, gender, and lineage filters', () => {
      const results = service.lookup({ search: 'cousin', gender: 'male', lineage: 'paternal' });
      for (const term of results) {
        expect(term.gender).toBe('male');
        expect(term.lineage).toBe('paternal');
        // All results should match "cousin" in some field
      }
    });

    it('should return all terms when no filters are applied', () => {
      const results = service.lookup({});
      expect(results.length).toBeGreaterThan(30); // The database has ~40 terms
    });
  });

  // ── 6. Supported Languages ─────────────────────────────────────────

  describe('getSupportedLanguages', () => {
    it('should return array with "hi" (Hindi)', () => {
      const langs = service.getSupportedLanguages();
      const hindi = langs.find((l) => l.code === 'hi');
      expect(hindi).toBeDefined();
      expect(hindi!.name).toBe('Hindi');
    });

    it('should return array with "mr" (Marathi)', () => {
      const langs = service.getSupportedLanguages();
      const marathi = langs.find((l) => l.code === 'mr');
      expect(marathi).toBeDefined();
      expect(marathi!.name).toBe('Marathi');
    });

    it('should return at least 7 languages', () => {
      const langs = service.getSupportedLanguages();
      expect(langs.length).toBeGreaterThanOrEqual(7);
    });

    it('should include Tamil, Telugu, Kannada, Bengali, Gujarati', () => {
      const langs = service.getSupportedLanguages();
      const codes = langs.map((l) => l.code);
      expect(codes).toContain('ta');
      expect(codes).toContain('te');
      expect(codes).toContain('kn');
      expect(codes).toContain('bn');
      expect(codes).toContain('gu');
    });

    it('should have each language code as a 2-letter ISO 639-1 code', () => {
      const langs = service.getSupportedLanguages();
      for (const lang of langs) {
        expect(lang.code).toMatch(/^[a-z]{2}$/);
      }
    });

    it('should have a name for every language code', () => {
      const langs = service.getSupportedLanguages();
      for (const lang of langs) {
        expect(lang.name).toBeTruthy();
        expect(lang.name.length).toBeGreaterThan(0);
      }
    });
  });

  // ── 7. Categories ──────────────────────────────────────────────────

  describe('getCategories', () => {
    it('should return an array of categories', () => {
      const categories = service.getCategories();
      expect(Array.isArray(categories)).toBe(true);
      expect(categories.length).toBeGreaterThanOrEqual(1);
    });

    it('should include "immediate_family" category', () => {
      const categories = service.getCategories();
      expect(categories).toContain('immediate_family');
    });

    it('should include "in_laws" category', () => {
      const categories = service.getCategories();
      expect(categories).toContain('in_laws');
    });

    it('should include "by_marriage" category', () => {
      const categories = service.getCategories();
      expect(categories).toContain('by_marriage');
    });

    it('should have no duplicate categories', () => {
      const categories = service.getCategories();
      const unique = new Set(categories);
      expect(unique.size).toBe(categories.length);
    });
  });

  // ── 8. getByCategory ───────────────────────────────────────────────

  describe('getByCategory', () => {
    it('should return terms for "immediate_family"', () => {
      const terms = service.getByCategory('immediate_family');
      expect(terms.length).toBeGreaterThanOrEqual(8);
      for (const term of terms) {
        expect(term.relationshipCategory).toBe('immediate_family');
      }
    });

    it('should return terms for "in_laws"', () => {
      const terms = service.getByCategory('in_laws');
      expect(terms.length).toBeGreaterThanOrEqual(6);
      for (const term of terms) {
        expect(term.relationshipCategory).toBe('in_laws');
      }
    });

    it('should return terms for "by_marriage"', () => {
      const terms = service.getByCategory('by_marriage');
      expect(terms.length).toBeGreaterThanOrEqual(4);
      for (const term of terms) {
        expect(term.relationshipCategory).toBe('by_marriage');
      }
    });

    it('should return empty array for non-existent category', () => {
      const terms = service.getByCategory('nonexistent_category');
      expect(terms).toEqual([]);
    });

    it('should not include terms from other categories', () => {
      const inLawTerms = service.getByCategory('in_laws');
      for (const term of inLawTerms) {
        expect(term.relationshipCategory).not.toBe('immediate_family');
        expect(term.relationshipCategory).not.toBe('extended_paternal');
        expect(term.relationshipCategory).not.toBe('extended_maternal');
      }
    });

    it('should include expected relationship types in "immediate_family"', () => {
      const terms = service.getByCategory('immediate_family');
      const keys = terms.map((t) => t.relationshipKey);
      expect(keys).toContain('father');
      expect(keys).toContain('mother');
      expect(keys).toContain('son');
      expect(keys).toContain('daughter');
    });
  });

  // ── 9. getRandomTerms ──────────────────────────────────────────────

  describe('getRandomTerms', () => {
    it('should return the requested number of terms', () => {
      const terms = service.getRandomTerms(5);
      expect(terms).toHaveLength(5);
    });

    it('should return 0 terms when count is 0', () => {
      const terms = service.getRandomTerms(0);
      expect(terms).toHaveLength(0);
    });

    it('should return at most available terms when count exceeds database size', () => {
      const terms = service.getRandomTerms(1000);
      const allTerms = service.getAllTerms();
      expect(terms.length).toBe(allTerms.length);
    });

    it('should filter by category when provided', () => {
      const terms = service.getRandomTerms(10, 'in_laws');
      expect(terms.length).toBeLessThanOrEqual(10);
      for (const term of terms) {
        expect(term.relationshipCategory).toBe('in_laws');
      }
    });

    it('should return empty for non-existent category', () => {
      const terms = service.getRandomTerms(5, 'nonexistent_category');
      expect(terms).toHaveLength(0);
    });

    it('should return different results on multiple calls (randomness)', () => {
      // Call getRandomTerms many times and verify not all results are identical
      const results = new Set<string>();
      for (let i = 0; i < 20; i++) {
        const terms = service.getRandomTerms(5);
        results.add(terms.map((t) => t.relationshipKey).join(','));
      }
      // With 40+ terms and Fisher-Yates, 20 calls should produce at least 2 different orderings
      expect(results.size).toBeGreaterThanOrEqual(2);
    });

    it('should not mutate the original database', () => {
      const before = service.getAllTerms();
      service.getRandomTerms(5);
      const after = service.getAllTerms();
      expect(before.length).toBe(after.length);
    });
  });

  // ── 10. findByNativeTerm ───────────────────────────────────────────

  describe('findByNativeTerm', () => {
    it('should find exact native match with high confidence (0.95)', () => {
      const results = service.findByNativeTerm('पिता');
      expect(results.length).toBeGreaterThanOrEqual(1);
      const father = results.find((t) => t.relationshipKey === 'father');
      expect(father).toBeDefined();
      expect(father!.confidence).toBeGreaterThanOrEqual(0.95);
    });

    it('should find Latin exact match with confidence (0.9)', () => {
      const results = service.findByNativeTerm('Pita');
      expect(results.length).toBeGreaterThanOrEqual(1);
      const father = results.find((t) => t.relationshipKey === 'father');
      expect(father).toBeDefined();
      expect(father!.confidence).toBeGreaterThanOrEqual(0.9);
    });

    it('should find alias exact match with confidence (0.95)', () => {
      const results = service.findByNativeTerm('papa');
      expect(results.length).toBeGreaterThanOrEqual(1);
      const father = results.find((t) => t.relationshipKey === 'father');
      expect(father).toBeDefined();
      expect(father!.confidence).toBeGreaterThanOrEqual(0.95);
    });

    it('should return results sorted by confidence descending', () => {
      const results = service.findByNativeTerm('maa');
      for (let i = 1; i < results.length; i++) {
        expect(results[i - 1].confidence).toBeGreaterThanOrEqual(results[i].confidence);
      }
    });

    it('should return empty for completely non-matching term', () => {
      const results = service.findByNativeTerm('xyznonexistent');
      expect(results).toEqual([]);
    });

    it('should find English term exact match with confidence 0.9', () => {
      const results = service.findByNativeTerm('Father');
      expect(results.length).toBeGreaterThanOrEqual(1);
      const father = results.find((t) => t.relationshipKey === 'father');
      expect(father).toBeDefined();
      expect(father!.confidence).toBeGreaterThanOrEqual(0.9);
    });

    it('should find partial English term match with lower confidence', () => {
      const results = service.findByNativeTerm('Fath');
      expect(results.length).toBeGreaterThanOrEqual(1);
      const father = results.find((t) => t.relationshipKey === 'father');
      expect(father).toBeDefined();
      expect(father!.confidence).toBeGreaterThanOrEqual(0.7);
    });

    it('should handle case-insensitive search', () => {
      const upper = service.findByNativeTerm('PAPA');
      const lower = service.findByNativeTerm('papa');
      expect(upper.length).toBe(lower.length);
    });

    it('should trim whitespace from input', () => {
      const withSpaces = service.findByNativeTerm('  papa  ');
      const withoutSpaces = service.findByNativeTerm('papa');
      expect(withSpaces.length).toBe(withoutSpaces.length);
    });
  });

  // ── 11. getAllTerms ────────────────────────────────────────────────

  describe('getAllTerms', () => {
    it('should return all terms in the database', () => {
      const terms = service.getAllTerms();
      expect(terms.length).toBeGreaterThan(30);
    });

    it('should return a copy (not the original array)', () => {
      const terms1 = service.getAllTerms();
      const terms2 = service.getAllTerms();
      expect(terms1).not.toBe(terms2); // Different array references
      expect(terms1.length).toBe(terms2.length);
    });
  });

  // ── 12. Data Integrity ─────────────────────────────────────────────

  describe('data integrity', () => {
    it('every kinship term should have a relationshipKey', () => {
      const terms = service.getAllTerms();
      for (const term of terms) {
        expect(term.relationshipKey).toBeDefined();
        expect(typeof term.relationshipKey).toBe('string');
        expect(term.relationshipKey.length).toBeGreaterThan(0);
      }
    });

    it('every kinship term should have an englishTerm', () => {
      const terms = service.getAllTerms();
      for (const term of terms) {
        expect(term.englishTerm).toBeDefined();
        expect(typeof term.englishTerm).toBe('string');
        expect(term.englishTerm.length).toBeGreaterThan(0);
      }
    });

    it('every kinship term should have a valid gender value', () => {
      const terms = service.getAllTerms();
      const validGenders = ['male', 'female', 'neutral'];
      for (const term of terms) {
        expect(validGenders).toContain(term.gender);
      }
    });

    it('every kinship term should have a valid lineage value', () => {
      const terms = service.getAllTerms();
      const validLineages = ['paternal', 'maternal', 'neutral'];
      for (const term of terms) {
        expect(validLineages).toContain(term.lineage);
      }
    });

    it('every kinship term should have a relationshipCategory', () => {
      const terms = service.getAllTerms();
      for (const term of terms) {
        expect(term.relationshipCategory).toBeDefined();
        expect(typeof term.relationshipCategory).toBe('string');
        expect(term.relationshipCategory.length).toBeGreaterThan(0);
      }
    });

    it('all relationshipKeys should be unique', () => {
      const terms = service.getAllTerms();
      const keys = terms.map((t) => t.relationshipKey);
      const uniqueKeys = new Set(keys);
      expect(uniqueKeys.size).toBe(keys.length);
    });

    it('every kinship term should have at least one translation', () => {
      const terms = service.getAllTerms();
      for (const term of terms) {
        const langCodes = Object.keys(term.translations);
        expect(langCodes.length).toBeGreaterThanOrEqual(1);
      }
    });

    it('every translation should have both native and latin fields', () => {
      const terms = service.getAllTerms();
      for (const term of terms) {
        for (const [code, translation] of Object.entries(term.translations)) {
          expect(translation.native).toBeDefined();
          expect(translation.latin).toBeDefined();
          expect(typeof translation.native).toBe('string');
          expect(typeof translation.latin).toBe('string');
          expect(translation.native.length).toBeGreaterThan(0);
          expect(translation.latin.length).toBeGreaterThan(0);
        }
      }
    });
  });

  // ── 13. Edge Cases ─────────────────────────────────────────────────

  describe('edge cases', () => {
    it('should handle undefined key in lookup gracefully', () => {
      const results = service.lookup({ key: undefined as any });
      // When key is undefined/falsy, lookup falls through to search/filter logic
      expect(results).toBeDefined();
      expect(Array.isArray(results)).toBe(true);
    });

    it('should handle very long search string without crashing', () => {
      const longString = 'a'.repeat(1000);
      expect(() => service.search(longString)).not.toThrow();
      const results = service.search(longString);
      expect(Array.isArray(results)).toBe(true);
    });

    it('should handle special characters in search term', () => {
      expect(() => service.search('!@#$%^&*()')).not.toThrow();
      const results = service.search('!@#$%^&*()');
      expect(Array.isArray(results)).toBe(true);
    });

    it('should handle lookup with empty params object', () => {
      const results = service.lookup({});
      expect(results.length).toBeGreaterThan(30);
    });

    it('should handle getByKey with empty string', () => {
      const term = service.getByKey('');
      expect(term).toBeUndefined();
    });

    it('should handle searchByTermAndLang with limit 0', () => {
      const results = service.searchByTermAndLang('father', 'hi', 0);
      expect(results).toHaveLength(0);
    });

    it('should handle findByNativeTerm with empty string', () => {
      const results = service.findByNativeTerm('');
      // Empty string should match everything since includes('') is always true
      expect(results).toBeDefined();
      expect(Array.isArray(results)).toBe(true);
    });
  });
});
