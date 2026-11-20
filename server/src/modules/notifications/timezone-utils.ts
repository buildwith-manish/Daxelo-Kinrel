// server/src/modules/notifications/timezone-utils.ts
//
// ════════════════════════════════════════════════════════════════════════════
//  DAXELO KINREL — Server-side IST helpers (Step 5)
// ════════════════════════════════════════════════════════════════════════════
//
//  Single source of truth for Asia/Kolkata (IST) timezone logic on the
//  server. Step 5 fixes the UTC-hour approximation in the notification
//  scheduler and the user-engagement histogram — both now use explicit
//  IST for hour-of-day and weekday.
//
//  Why IST?
//  ────────
//  The family base is India-only today, so the SHARED "best send hour"
//  for notifications is best expressed in IST. The previous code used
//  `new Date().getHours()` (server-local, which is UTC in production)
//  as a proxy for the user's local hour — which only works if every
//  user is in the same timezone as the server (UTC). For an IST user
//  (UTC+5:30), a "9 AM UTC" notification arrives at 2:30 PM IST — wrong
//  by 5.5 hours.
//
//  Future per-user timezone support is intentionally NOT built here.
//  The existing TODO in notifications.scheduler.ts already documents
//  this. The fix in this file is the "good enough today" version that
//  makes the scheduler IST-accurate.
//
//  Why date-fns-tz?
//  ────────────────
//  We pull in `date-fns-tz` v3 for `toZonedTime(date, tz)`, which
//  returns a Date with a hidden Symbol marking the target timezone.
//  Pairing that with `date-fns`'s `getHours` / `getDay` functions
//  (which respect the Symbol) gives us the IST hour and weekday
//  without manipulating UTC offsets manually. The fixed-offset
//  approach (UTC + 5:30) would also work for IST (no DST), but using
//  `date-fns-tz` is the right pattern if/when per-user timezones are
//  added later.

import { toZonedTime } from 'date-fns-tz';
import { getHours, getDay, getDate, getMonth, getYear } from 'date-fns';

/// The fixed timezone for SHARED family-wide scheduling. Today the
/// family base is India-only, so this is hard-coded. If/when per-user
/// timezones land, this becomes the default fallback for users
/// without an explicit `User.timezone`.
export const IST_TZ = 'Asia/Kolkata';

/// Get the IST hour (0-23) for the given UTC Date.
/// Equivalent to `new Date().getHours()` if the server were running
/// in IST.
export function getIstHour(date: Date): number {
  const zoned = toZonedTime(date, IST_TZ);
  return getHours(zoned);
}

/// Get the IST weekday (0=Sunday..6=Saturday) for the given UTC Date.
/// Matches the semantics of `Date.getDay()` so the existing 7-entry
/// engagement-weekday histogram array keeps working without
/// re-indexing.
export function getIstDay(date: Date): number {
  const zoned = toZonedTime(date, IST_TZ);
  return getDay(zoned);
}

/// Get the IST day-of-month (1-31) for the given UTC Date.
/// Useful for "is it the user's birthday today in IST?" checks.
export function getIstDateOfMonth(date: Date): number {
  const zoned = toZonedTime(date, IST_TZ);
  return getDate(zoned);
}

/// Get the IST month (0-11) for the given UTC Date.
/// Matches `Date.getMonth()` semantics.
export function getIstMonth(date: Date): number {
  const zoned = toZonedTime(date, IST_TZ);
  return getMonth(zoned);
}

/// Get the IST full year (e.g. 2026) for the given UTC Date.
export function getIstYear(date: Date): number {
  const zoned = toZonedTime(date, IST_TZ);
  return getYear(zoned);
}

/// Compute the IST "today" as a Date object whose UTC instant
/// corresponds to IST midnight. Useful for `daysUntil` comparisons
/// against birthdays stored as `Date` objects.
export function istToday(date: Date = new Date()): Date {
  const zoned = toZonedTime(date, IST_TZ);
  // Construct IST midnight wall-clock as a UTC instant by subtracting
  // the IST offset. We use toZonedTime's wall-clock reading so the
  // year/month/day are IST values.
  // IST = UTC+5:30, no DST. So IST midnight = UTC - 5:30 of the same
  // IST wall-clock date.
  // Construct as UTC at 00:00 of the IST wall-clock date, then subtract
  // 5:30 to get the UTC instant of IST midnight.
  return new Date(
    Date.UTC(
      getYear(zoned),
      getMonth(zoned),
      getDate(zoned),
      0,
      0,
      0,
    ) - 5.5 * 60 * 60 * 1000,
  );
}

/// Returns true iff the given UTC Date is inside the SHARED quiet
/// hours window (quietStart..quietEnd are "HH:MM" in IST). Used by
/// the notification scheduler to suppress push notifications during
/// the user's quiet hours. Handles overnight windows (e.g.
/// 22:00–08:00) correctly.
export function isInIstQuietHours(
  now: Date,
  quietStart: string | null | undefined,
  quietEnd: string | null | undefined,
): boolean {
  if (!quietStart || !quietEnd) return false;
  try {
    const zoned = toZonedTime(now, IST_TZ);
    const currentMinutes = getHours(zoned) * 60 + zoned.getMinutes();

    const [startH, startM] = quietStart.split(':').map(Number);
    const [endH, endM] = quietEnd.split(':').map(Number);

    if (isNaN(startH) || isNaN(startM) || isNaN(endH) || isNaN(endM)) {
      return false;
    }

    const startMinutes = startH * 60 + startM;
    const endMinutes = endH * 60 + endM;

    if (startMinutes <= endMinutes) {
      // e.g. 08:00 - 22:00
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    } else {
      // e.g. 22:00 - 08:00 (overnight — wraps midnight)
      return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    }
  } catch {
    return false;
  }
}

/// Returns `tz` if it is a valid IANA timezone name, otherwise the IST
/// default. `NotificationPreference.quietHoursTimezone` is a free-form
/// String column (default 'Asia/Kolkata'), so a bad/empty value must not
/// throw inside a scheduler.
export function resolveTimeZone(tz: string | null | undefined): string {
  if (!tz) return IST_TZ;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return tz;
  } catch {
    return IST_TZ;
  }
}

/// Returns true iff `now` falls inside the quiet-hours window
/// [quietStart, quietEnd) read as wall-clock "HH:MM" in the IANA timezone
/// `timeZone` (the recipient's `NotificationPreference.quietHoursTimezone`).
/// DST is handled by the timezone database, not by fixed offsets.
///
///  - The START minute is inside the window, the END minute is not
///    (22:00-08:00 is quiet at 22:00 and no longer quiet at 08:00).
///  - Overnight windows (start > end) wrap midnight.
///  - start === end is an empty window (never quiet).
///  - Missing or malformed start/end -> false (no quiet hours configured).
///  - Missing/invalid timezone -> IST (the column default).
///
/// NOTE: `isInIstQuietHours` above treats the END minute as inside the
/// window and is fixed to IST; it is left unchanged for its existing caller.
export function isInQuietHoursInTz(
  now: Date,
  quietStart: string | null | undefined,
  quietEnd: string | null | undefined,
  timeZone: string | null | undefined,
): boolean {
  const start = parseHhMm(quietStart);
  const end = parseHhMm(quietEnd);
  if (start === null || end === null) return false;

  const zoned = toZonedTime(now, resolveTimeZone(timeZone));
  const current = getHours(zoned) * 60 + zoned.getMinutes();

  if (start <= end) {
    return current >= start && current < end;
  }
  return current >= start || current < end;
}

/// "HH:MM" -> minutes since midnight, or null if absent/malformed.
function parseHhMm(value: string | null | undefined): number | null {
  if (!value) return null;
  const m = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}
