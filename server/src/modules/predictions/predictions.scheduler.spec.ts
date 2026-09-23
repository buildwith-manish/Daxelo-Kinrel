// server/src/modules/predictions/predictions.scheduler.spec.ts
//
// Unit tests for the pure helpers in predictions.scheduler.ts.
// We don't unit-test the scheduler's cron flow directly (it depends on
// Supabase + Prisma + FCM) — instead we test the pure helper functions
// that are extracted at the bottom of the file.

import { computeDistance, truncate } from './predictions.scheduler';

describe('predictions.scheduler pure helpers', () => {
  describe('computeDistance', () => {
    it('returns absolute difference for small correct answers', () => {
      expect(computeDistance(45, 50)).toBe(5);
      expect(computeDistance(50, 50)).toBe(0);
      expect(computeDistance(55, 50)).toBe(5);
    });

    it('returns percentage-based distance for correct answers > 1000', () => {
      // 1000 → 1100 is 10% off
      expect(computeDistance(1100, 10000)).toBeCloseTo(9, 1);
      // exact match → 0%
      expect(computeDistance(5000, 5000)).toBe(0);
      // 10% over
      expect(computeDistance(11000, 10000)).toBeCloseTo(10, 1);
    });

    it('handles boundary at 1000 exactly as absolute', () => {
      // correct_answer = 1000 is NOT > 1000, so absolute is used
      expect(computeDistance(1010, 1000)).toBe(10);
    });

    it('handles boundary at 1001 as percentage', () => {
      // correct_answer = 1001 IS > 1000, so percentage is used
      // 1011 vs 1001 → 10/1001 * 100 ≈ 0.999
      expect(computeDistance(1011, 1001)).toBeCloseTo(0.999, 2);
    });
  });

  describe('truncate', () => {
    it('returns the original string if shorter than max', () => {
      expect(truncate('hello', 10)).toBe('hello');
      expect(truncate('exactly5', 8)).toBe('exactly5');
    });

    it('returns the original string if exactly max length', () => {
      expect(truncate('1234567890', 10)).toBe('1234567890');
    });

    it('truncates and adds ellipsis if longer than max', () => {
      const result = truncate('Hello world this is a long string', 15);
      expect(result.length).toBeLessThanOrEqual(15);
      expect(result.endsWith('…')).toBe(true);
      expect(result).toBe('Hello world th…');
    });

    it('handles empty string', () => {
      expect(truncate('', 10)).toBe('');
    });

    it('handles max = 0 safely (no negative slice)', () => {
      // Should not throw — slice(0, -1) on a short string returns ''
      const result = truncate('hello', 0);
      expect(result).toBe('…');
    });
  });
});
