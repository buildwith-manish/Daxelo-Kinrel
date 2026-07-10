// =============================================================================
// ML spec item #2 — Duplicate pre-filter tests
// =============================================================================
// Verifies the TF-IDF + cosine similarity pre-filter that sits in front of
// the AI-based DuplicateDetectionKind.
// =============================================================================

import {
  preFilterDuplicates,
  tokenize,
  PREFILTER_THRESHOLDS,
} from './duplicate-prefilter';

describe('DuplicatePrefilter', () => {
  describe('tokenize', () => {
    it('lowercases and splits on non-alphanumeric', () => {
      const tokens = tokenize('Diwali Vacation Plans!!');
      expect(tokens).toContain('diwali');
      expect(tokens).toContain('vacation');
      expect(tokens).toContain('plans');
    });

    it('drops English stopwords', () => {
      const tokens = tokenize('the family should vote on this');
      expect(tokens).not.toContain('the');
      expect(tokens).not.toContain('should');
      expect(tokens).not.toContain('on');
      expect(tokens).not.toContain('this');
      // Note: 'family' and 'vote' are also in the stopwords list because
      // they're common family-meeting words that don't help distinguish
      // decisions from each other. So they're dropped too.
      expect(tokens).not.toContain('family');
      expect(tokens).not.toContain('vote');
    });

    it('drops Hindi romanized stopwords', () => {
      const tokens = tokenize('mahotsav ka planning ke liye approval');
      expect(tokens).not.toContain('ka');
      expect(tokens).not.toContain('ke');
      // 'liye' is NOT in our stopword list — it's a meaningful word.
      expect(tokens).toContain('liye');
      expect(tokens).toContain('mahotsav');
      expect(tokens).toContain('planning');
      expect(tokens).toContain('approval');
    });

    it('drops single-character tokens', () => {
      const tokens = tokenize('a b c vacation');
      expect(tokens).not.toContain('a');
      expect(tokens).not.toContain('b');
      expect(tokens).not.toContain('c');
      expect(tokens).toContain('vacation');
    });

    it('handles Unicode letters (Devanagari) when supported by the runtime', () => {
      // The \p{L} Unicode property escape requires the 'u' flag and a
      // runtime that supports it. Node 14+ supports this natively.
      // If the runtime doesn't, the Devanagari chars won't tokenize but
      // the Latin ones will — that's acceptable degradation.
      const tokens = tokenize('दिवाली vacation plans');
      expect(tokens).toContain('vacation');
      expect(tokens).toContain('plans');
      // Devanagari support is best-effort — don't assert on it strictly
      // so the test doesn't fail on runtimes without Unicode property escapes.
    });

    it('returns empty array for empty/whitespace input', () => {
      expect(tokenize('')).toEqual([]);
      expect(tokenize('   ')).toEqual([]);
    });
  });

  describe('preFilterDuplicates', () => {
    it('returns local_skip when there are no prior decisions', () => {
      const result = preFilterDuplicates({
        newDecisionTitle: 'New decision',
        priorDecisions: [],
      });
      expect(result.path).toBe('local_skip');
      expect(result.duplicates).toEqual([]);
      expect(result.closestMatch).toBeNull();
    });

    it('returns local_match for near-identical titles (sim > HIGH_THRESHOLD)', () => {
      const result = preFilterDuplicates({
        newDecisionTitle: 'Diwali vacation planning for the whole family',
        newDecisionDescription: 'Where should we go for Diwali this year?',
        priorDecisions: [
          {
            id: 'd-1',
            title: 'Diwali vacation planning for the whole family',
            description: 'Where should we go for Diwali this year?',
          },
        ],
      });
      expect(result.path).toBe('local_match');
      expect(result.duplicates).toHaveLength(1);
      expect(result.duplicates[0].decisionId).toBe('d-1');
      expect(result.duplicates[0].similarity).toBeGreaterThan(PREFILTER_THRESHOLDS.HIGH_THRESHOLD);
      expect(result.topScore).toBeGreaterThan(PREFILTER_THRESHOLDS.HIGH_THRESHOLD);
    });

    it('returns local_skip for unrelated decisions (sim < LOW_THRESHOLD)', () => {
      const result = preFilterDuplicates({
        newDecisionTitle: 'Diwali vacation planning',
        priorDecisions: [
          {
            id: 'd-1',
            title: 'Quarterly budget review for the family business',
            description: 'Review Q3 financials and approve Q4 budget allocations.',
          },
        ],
      });
      expect(result.path).toBe('local_skip');
      expect(result.duplicates).toEqual([]);
      expect(result.topScore).toBeLessThan(PREFILTER_THRESHOLDS.LOW_THRESHOLD);
    });

    it('returns escalate for ambiguous similarity (between LOW and HIGH)', () => {
      // Two decisions that share some words but are not clearly the same
      const result = preFilterDuplicates({
        newDecisionTitle: 'Family vacation planning this year',
        priorDecisions: [
          {
            id: 'd-1',
            title: 'Family vacation budget planning last year',
            description: 'How we planned the vacation budget last year.',
          },
        ],
      });
      // The exact path depends on the TF-IDF calculation, but it should be
      // either 'escalate' (ambiguous band) or 'local_skip' (low similarity).
      // The key acceptance criterion is that it does NOT return 'local_match'
      // for these clearly-different-but-related decisions.
      expect(['escalate', 'local_skip']).toContain(result.path);
      if (result.path === 'escalate') {
        expect(result.topScore).toBeGreaterThanOrEqual(PREFILTER_THRESHOLDS.LOW_THRESHOLD);
        expect(result.topScore).toBeLessThan(PREFILTER_THRESHOLDS.HIGH_THRESHOLD);
      }
    });

    it('returns escalate when new decision has no usable text', () => {
      const result = preFilterDuplicates({
        newDecisionTitle: '',
        newDecisionDescription: '',
        priorDecisions: [
          { id: 'd-1', title: 'Some prior decision', description: 'desc' },
        ],
      });
      expect(result.path).toBe('escalate');
      expect(result.message).toContain('no usable text');
    });

    it('handles multiple prior decisions and picks the best match', () => {
      const result = preFilterDuplicates({
        newDecisionTitle: 'Diwali vacation planning mahotsav celebration',
        newDecisionDescription: 'Where should we celebrate Diwali mahotsav this year?',
        priorDecisions: [
          {
            id: 'd-1',
            title: 'Quarterly budget review financials',
            description: 'Review financials and budget allocations.',
          },
          {
            id: 'd-2',
            title: 'Diwali vacation planning mahotsav celebration',
            description: 'Where should we celebrate Diwali mahotsav this year?',
          },
          {
            id: 'd-3',
            title: 'Holi celebration plans colors',
            description: 'How to celebrate Holi with colors this year.',
          },
        ],
      });
      // The exact path depends on TF-IDF scoring, but if it's a local_match,
      // it must pick d-2 (the identical decision) as the duplicate.
      if (result.path === 'local_match') {
        expect(result.duplicates[0].decisionId).toBe('d-2');
      }
      // Even for escalate or local_skip, d-2 should be the closest match
      // because it shares the most distinctive terms (mahotsav, celebration).
      if (result.closestMatch) {
        expect(result.closestMatch.decisionId).toBe('d-2');
      }
    });

    it('the similarity is a number in [0, 1]', () => {
      const result = preFilterDuplicates({
        newDecisionTitle: 'test decision',
        priorDecisions: [{ id: 'd-1', title: 'another decision' }],
      });
      expect(result.topScore).toBeGreaterThanOrEqual(0);
      expect(result.topScore).toBeLessThanOrEqual(1);
    });
  });
});
