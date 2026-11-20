// server/src/modules/notifications/timezone-utils.spec.ts
//
// Step 5 — Tests for the IST helpers used by the notification scheduler
// and the user-engagement service. Verifies that `getIstHour` /
// `getIstDay` / `isInIstQuietHours` produce the correct values across
// the UTC↔IST boundary.

import {
  getIstHour,
  getIstDay,
  isInIstQuietHours,
  istToday,
  isInQuietHoursInTz,
  resolveTimeZone,
} from './timezone-utils';

describe('Step 5 — IST helpers', () => {
  describe('getIstHour', () => {
    test('00:00 UTC = 05:30 IST → 5', () => {
      const utc = new Date(Date.UTC(2026, 8, 21, 0, 0, 0));   // 00:00 UTC
      expect(getIstHour(utc)).toBe(5);                          // 05:30 IST → hour 5
    });
    test('18:30 UTC = 00:00 IST (next day) → 0', () => {
      const utc = new Date(Date.UTC(2026, 8, 21, 18, 30, 0)); // 18:30 UTC
      expect(getIstHour(utc)).toBe(0);                          // 00:00 IST → hour 0
    });
    test('12:00 UTC = 17:30 IST → 17', () => {
      const utc = new Date(Date.UTC(2026, 8, 21, 12, 0, 0));   // 12:00 UTC
      expect(getIstHour(utc)).toBe(17);                         // 17:30 IST → hour 17
    });
    test('19:00 UTC = 00:30 IST next day → 0', () => {
      const utc = new Date(Date.UTC(2026, 8, 21, 19, 0, 0));   // 19:00 UTC
      expect(getIstHour(utc)).toBe(0);                          // 00:30 IST next day → hour 0
    });
    test('15:00 UTC = 20:30 IST → 20 (Prediction Battle close boundary)', () => {
      const utc = new Date(Date.UTC(2026, 8, 21, 15, 0, 0));   // 15:00 UTC
      expect(getIstHour(utc)).toBe(20);                         // 20:30 IST → hour 20
    });
  });

  describe('getIstDay', () => {
    test('Monday 18:00 UTC = Monday 23:30 IST → 1 (Mon)', () => {
      // 2026-09-21 is a Monday
      const utc = new Date(Date.UTC(2026, 8, 21, 18, 0, 0));   // Mon 18:00 UTC
      expect(getIstDay(utc)).toBe(1);                          // Mon 23:30 IST → day 1 (Mon)
    });
    test('Monday 18:30 UTC = Tuesday 00:00 IST → 2 (Tue)', () => {
      // 18:30 UTC on Mon = 00:00 IST on Tue
      const utc = new Date(Date.UTC(2026, 8, 21, 18, 31, 0));  // Mon 18:31 UTC
      expect(getIstDay(utc)).toBe(2);                          // Tue 00:01 IST → day 2 (Tue)
    });
    test('Sunday 18:30 UTC = Monday 00:00 IST → 1 (Mon, weekday rollover)', () => {
      // 2026-09-20 is a Sunday
      const utc = new Date(Date.UTC(2026, 8, 20, 18, 31, 0));  // Sun 18:31 UTC
      expect(getIstDay(utc)).toBe(1);                          // Mon 00:01 IST → day 1 (Mon)
    });
  });

  describe('isInIstQuietHours', () => {
    test('returns false when quietStart or quietEnd is null', () => {
      const now = new Date('2026-09-21T10:00:00Z');
      expect(isInIstQuietHours(now, null, '22:00')).toBe(false);
      expect(isInIstQuietHours(now, '22:00', null)).toBe(false);
      expect(isInIstQuietHours(now, null, null)).toBe(false);
    });

    test('returns false for malformed input', () => {
      const now = new Date('2026-09-21T10:00:00Z');
      expect(isInIstQuietHours(now, 'bad', '22:00')).toBe(false);
      expect(isInIstQuietHours(now, '22:00', 'bad')).toBe(false);
    });

    test('inside non-overnight window (08:00–22:00): 12:00 IST → true', () => {
      // 12:00 IST = 06:30 UTC
      const now = new Date(Date.UTC(2026, 8, 21, 6, 30, 0));
      expect(isInIstQuietHours(now, '08:00', '22:00')).toBe(true);
    });

    test('outside non-overnight window (08:00–22:00): 07:00 IST → false', () => {
      // 07:00 IST = 01:30 UTC
      const now = new Date(Date.UTC(2026, 8, 21, 1, 30, 0));
      expect(isInIstQuietHours(now, '08:00', '22:00')).toBe(false);
    });

    test('outside non-overnight window (08:00–22:00): 23:00 IST → false', () => {
      // 23:00 IST = 17:30 UTC
      const now = new Date(Date.UTC(2026, 8, 21, 17, 30, 0));
      expect(isInIstQuietHours(now, '08:00', '22:00')).toBe(false);
    });

    test('inside overnight window (22:00–08:00): 23:00 IST → true', () => {
      // 23:00 IST = 17:30 UTC
      const now = new Date(Date.UTC(2026, 8, 21, 17, 30, 0));
      expect(isInIstQuietHours(now, '22:00', '08:00')).toBe(true);
    });

    test('inside overnight window (22:00–08:00): 02:00 IST → true (after midnight)', () => {
      // 02:00 IST = 20:30 UTC (previous day in UTC)
      const now = new Date(Date.UTC(2026, 8, 21, 20, 30, 0));
      expect(isInIstQuietHours(now, '22:00', '08:00')).toBe(true);
    });

    test('outside overnight window (22:00–08:00): 12:00 IST → false', () => {
      // 12:00 IST = 06:30 UTC
      const now = new Date(Date.UTC(2026, 8, 21, 6, 30, 0));
      expect(isInIstQuietHours(now, '22:00', '08:00')).toBe(false);
    });

    test('boundary: exactly at start of non-overnight window → inside (inclusive)', () => {
      // 08:00 IST = 02:30 UTC
      const now = new Date(Date.UTC(2026, 8, 21, 2, 30, 0));
      expect(isInIstQuietHours(now, '08:00', '22:00')).toBe(true);
    });

    test('boundary: exactly at end of non-overnight window → inside (inclusive)', () => {
      // 22:00 IST = 16:30 UTC
      const now = new Date(Date.UTC(2026, 8, 21, 16, 30, 0));
      expect(isInIstQuietHours(now, '08:00', '22:00')).toBe(true);
    });
  });

  describe('istToday', () => {
    test('returns the UTC instant of IST midnight for a UTC instant inside the IST day', () => {
      // 2026-09-21 12:00 UTC = 2026-09-21 17:30 IST
      // IST midnight = 2026-09-21 00:00 IST = 2026-09-20 18:30 UTC
      const now = new Date(Date.UTC(2026, 8, 21, 12, 0, 0));
      const istMidnight = istToday(now);
      expect(istMidnight.toISOString()).toBe('2026-09-20T18:30:00.000Z');
    });

    test('crosses IST-midnight correctly (UTC 19:00 on Sep 21 = Sep 22 00:30 IST)', () => {
      const now = new Date(Date.UTC(2026, 8, 21, 19, 0, 0));
      const istMidnight = istToday(now);
      // IST midnight for Sep 22 IST = Sep 21 18:30 UTC
      expect(istMidnight.toISOString()).toBe('2026-09-21T18:30:00.000Z');
    });
  });
});

describe('Phase A-5 — per-timezone quiet hours', () => {
  const utc = (y: number, mo: number, d: number, h: number, mi = 0) =>
    new Date(Date.UTC(y, mo - 1, d, h, mi, 0));

  describe('resolveTimeZone', () => {
    test('valid IANA name is kept', () => {
      expect(resolveTimeZone('America/New_York')).toBe('America/New_York');
    });
    test('null / empty / unknown fall back to Asia/Kolkata', () => {
      expect(resolveTimeZone(null)).toBe('Asia/Kolkata');
      expect(resolveTimeZone(undefined)).toBe('Asia/Kolkata');
      expect(resolveTimeZone('')).toBe('Asia/Kolkata');
      expect(resolveTimeZone('Mars/Phobos')).toBe('Asia/Kolkata');
    });
  });

  describe('isInQuietHoursInTz (22:00-08:00 overnight window)', () => {
    test('uses the recipient timezone: 17:00 UTC is 22:30 IST (quiet) but 12:00 New York (not quiet)', () => {
      const now = utc(2026, 11, 20, 17, 0);
      expect(isInQuietHoursInTz(now, '22:00', '08:00', 'Asia/Kolkata')).toBe(true);
      expect(isInQuietHoursInTz(now, '22:00', '08:00', 'America/New_York')).toBe(false);
    });

    test('start minute is inside the window', () => {
      // 22:00 IST = 16:30 UTC
      expect(isInQuietHoursInTz(utc(2026, 11, 20, 16, 30), '22:00', '08:00', 'Asia/Kolkata')).toBe(true);
      expect(isInQuietHoursInTz(utc(2026, 11, 20, 16, 29), '22:00', '08:00', 'Asia/Kolkata')).toBe(false);
    });

    test('end minute is NOT inside the window (08:00 IST = 02:30 UTC)', () => {
      expect(isInQuietHoursInTz(utc(2026, 11, 21, 2, 29), '22:00', '08:00', 'Asia/Kolkata')).toBe(true);
      expect(isInQuietHoursInTz(utc(2026, 11, 21, 2, 30), '22:00', '08:00', 'Asia/Kolkata')).toBe(false);
    });

    test('same-day window (09:00-17:00 Tokyo; 00:00 UTC = 09:00 JST)', () => {
      expect(isInQuietHoursInTz(utc(2026, 11, 20, 0, 0), '09:00', '17:00', 'Asia/Tokyo')).toBe(true);
      expect(isInQuietHoursInTz(utc(2026, 11, 20, 8, 0), '09:00', '17:00', 'Asia/Tokyo')).toBe(false); // 17:00 JST
    });

    test('DST: 08:00 end boundary follows the local offset (New York)', () => {
      // Winter (EST, UTC-5): 12:00 UTC = 07:00 local -> still quiet
      expect(isInQuietHoursInTz(utc(2026, 1, 15, 12, 0), '22:00', '08:00', 'America/New_York')).toBe(true);
      // Summer (EDT, UTC-4): 12:00 UTC = 08:00 local -> quiet is over
      expect(isInQuietHoursInTz(utc(2026, 7, 15, 12, 0), '22:00', '08:00', 'America/New_York')).toBe(false);
    });

    test('unset / malformed start or end -> false', () => {
      const now = utc(2026, 11, 20, 17, 0);
      expect(isInQuietHoursInTz(now, null, '08:00', 'Asia/Kolkata')).toBe(false);
      expect(isInQuietHoursInTz(now, '22:00', undefined, 'Asia/Kolkata')).toBe(false);
      expect(isInQuietHoursInTz(now, 'bad', '08:00', 'Asia/Kolkata')).toBe(false);
      expect(isInQuietHoursInTz(now, '25:00', '08:00', 'Asia/Kolkata')).toBe(false);
    });

    test('start === end is an empty window', () => {
      expect(isInQuietHoursInTz(utc(2026, 11, 20, 17, 0), '22:00', '22:00', 'Asia/Kolkata')).toBe(false);
    });

    test('invalid timezone falls back to IST', () => {
      // 17:00 UTC = 22:30 IST -> quiet under the IST fallback
      expect(isInQuietHoursInTz(utc(2026, 11, 20, 17, 0), '22:00', '08:00', 'Not/AZone')).toBe(true);
    });
  });
});
