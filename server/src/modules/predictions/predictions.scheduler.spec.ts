// server/src/modules/predictions/predictions.scheduler.spec.ts
//
// Unit tests for the pure helpers in predictions.scheduler.ts.
// We don't unit-test the scheduler's cron flow directly (it depends on
// Supabase + Prisma + FCM) — instead we test the pure helper functions
// that are extracted at the bottom of the file.

import { computeDistance, truncate, isInStreakDangerWindowAt, isWeeklyRecapWindowAt } from './predictions.scheduler';

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

  describe('isInStreakDangerWindowAt', () => {
    // The window is 8:30 PM IST to 9:00 PM IST (exclusive).
    // 8:30 PM IST = 15:00 UTC (since IST = UTC + 5:30, so UTC = IST - 5:30).
    // 9:00 PM IST = 15:30 UTC.
    // So the window in UTC is 15:00–15:30.

    it('returns true at 8:30 PM IST (15:00 UTC)', () => {
      // 15:00 UTC = 20:30 IST — exactly the start of the window
      const dt = new Date('2026-09-23T15:00:00.000Z');
      expect(isInStreakDangerWindowAt(dt)).toBe(true);
    });

    it('returns true at 8:45 PM IST (15:15 UTC)', () => {
      const dt = new Date('2026-09-23T15:15:00.000Z');
      expect(isInStreakDangerWindowAt(dt)).toBe(true);
    });

    it('returns true at 8:59 PM IST (15:29 UTC)', () => {
      // Just before 9:00 PM IST — still in window
      const dt = new Date('2026-09-23T15:29:59.000Z');
      expect(isInStreakDangerWindowAt(dt)).toBe(true);
    });

    it('returns false at 9:00 PM IST (15:30 UTC) — exclusive end', () => {
      // 9:00 PM IST = 15:30 UTC. The window is [20:30, 21:00) IST,
      // so 21:00 is NOT in window.
      const dt = new Date('2026-09-23T15:30:00.000Z');
      expect(isInStreakDangerWindowAt(dt)).toBe(false);
    });

    it('returns false at 8:29 PM IST (14:59 UTC) — just before start', () => {
      const dt = new Date('2026-09-23T14:59:59.000Z');
      expect(isInStreakDangerWindowAt(dt)).toBe(false);
    });

    it('returns false at 8:00 PM IST (14:30 UTC) — well before start', () => {
      const dt = new Date('2026-09-23T14:30:00.000Z');
      expect(isInStreakDangerWindowAt(dt)).toBe(false);
    });

    it('returns false at 10:00 PM IST (16:30 UTC) — after end', () => {
      const dt = new Date('2026-09-23T16:30:00.000Z');
      expect(isInStreakDangerWindowAt(dt)).toBe(false);
    });

    it('returns false at 12:00 PM IST (06:30 UTC) — noon', () => {
      const dt = new Date('2026-09-23T06:30:00.000Z');
      expect(isInStreakDangerWindowAt(dt)).toBe(false);
    });

    it('returns false at 8:00 AM IST (02:30 UTC) — morning', () => {
      const dt = new Date('2026-09-23T02:30:00.000Z');
      expect(isInStreakDangerWindowAt(dt)).toBe(false);
    });

    it('returns false at midnight UTC (05:30 IST) — early morning IST', () => {
      const dt = new Date('2026-09-23T00:00:00.000Z');
      expect(isInStreakDangerWindowAt(dt)).toBe(false);
    });

    it('handles different dates — window is daily, not date-specific', () => {
      // Same time on a different day should still be in window
      const dt1 = new Date('2026-09-22T15:15:00.000Z');
      const dt2 = new Date('2026-09-23T15:15:00.000Z');
      const dt3 = new Date('2026-10-01T15:15:00.000Z');
      expect(isInStreakDangerWindowAt(dt1)).toBe(true);
      expect(isInStreakDangerWindowAt(dt2)).toBe(true);
      expect(isInStreakDangerWindowAt(dt3)).toBe(true);
    });
  });

  describe('isWeeklyRecapWindowAt', () => {
    // The window is Sundays 10:00–10:15 AM IST (15-min window).
    // 10:00 AM IST = 04:30 UTC (since IST = UTC + 5:30, UTC = IST - 5:30).
    // 10:15 AM IST = 04:45 UTC.
    // Sunday in IST = Sunday in UTC for these times (since 04:30 UTC is
    // still the same calendar day as 10:00 IST).

    it('returns true on Sunday at 10:00 AM IST (04:30 UTC)', () => {
      // 2026-09-27 is a Sunday
      const dt = new Date('2026-09-27T04:30:00.000Z');
      expect(isWeeklyRecapWindowAt(dt)).toBe(true);
    });

    it('returns true on Sunday at 10:10 AM IST (04:40 UTC)', () => {
      const dt = new Date('2026-09-27T04:40:00.000Z');
      expect(isWeeklyRecapWindowAt(dt)).toBe(true);
    });

    it('returns true on Sunday at 10:14 AM IST (04:44 UTC)', () => {
      const dt = new Date('2026-09-27T04:44:59.000Z');
      expect(isWeeklyRecapWindowAt(dt)).toBe(true);
    });

    it('returns false on Sunday at 10:15 AM IST (04:45 UTC) — exclusive end', () => {
      const dt = new Date('2026-09-27T04:45:00.000Z');
      expect(isWeeklyRecapWindowAt(dt)).toBe(false);
    });

    it('returns false on Sunday at 9:59 AM IST (04:29 UTC) — just before start', () => {
      const dt = new Date('2026-09-27T04:29:59.000Z');
      expect(isWeeklyRecapWindowAt(dt)).toBe(false);
    });

    it('returns false on Sunday at 11:00 AM IST (05:30 UTC) — after end', () => {
      const dt = new Date('2026-09-27T05:30:00.000Z');
      expect(isWeeklyRecapWindowAt(dt)).toBe(false);
    });

    it('returns false on Monday at 10:05 AM IST — wrong day', () => {
      // 2026-09-28 is a Monday
      const dt = new Date('2026-09-28T04:35:00.000Z');
      expect(isWeeklyRecapWindowAt(dt)).toBe(false);
    });

    it('returns false on Saturday at 10:05 AM IST — wrong day', () => {
      // 2026-09-26 is a Saturday
      const dt = new Date('2026-09-26T04:35:00.000Z');
      expect(isWeeklyRecapWindowAt(dt)).toBe(false);
    });

    it('returns false on Sunday at 8:00 PM IST — wrong time of day', () => {
      // 8:00 PM IST = 14:30 UTC — same calendar Sunday in both zones
      const dt = new Date('2026-09-27T14:30:00.000Z');
      expect(isWeeklyRecapWindowAt(dt)).toBe(false);
    });

    it('returns false on Sunday at midnight IST — wrong time', () => {
      // Midnight IST = 18:30 UTC the previous day
      const dt = new Date('2026-09-26T18:30:00.000Z');
      expect(isWeeklyRecapWindowAt(dt)).toBe(false);
    });

    it('handles week boundary — different Sundays all match', () => {
      const sunday1 = new Date('2026-09-27T04:35:00.000Z'); // Sep 27
      const sunday2 = new Date('2026-10-04T04:35:00.000Z'); // Oct 4
      const sunday3 = new Date('2026-11-01T04:35:00.000Z'); // Nov 1
      expect(isWeeklyRecapWindowAt(sunday1)).toBe(true);
      expect(isWeeklyRecapWindowAt(sunday2)).toBe(true);
      expect(isWeeklyRecapWindowAt(sunday3)).toBe(true);
    });
  });
});

