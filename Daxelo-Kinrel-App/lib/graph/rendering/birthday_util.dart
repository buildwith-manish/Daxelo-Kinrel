// lib/graph/rendering/birthday_util.dart
//
// DAXELO KINREL — Birthday Glow Helpers (P3.3)
//
// Per Vision §6 #3 (WOW 8) — nodes whose birthday is within 7 days
// get a soft pulsing ember ring. This file holds the pure date math
// used by both the graph provider (to flag near-birthday persons) and
// the painter (to pick the correct glow color: ember for living,
// amber for deceased).
//
// Pure functions, no Flutter deps — trivially unit-testable.

/// The number of days before a birthday that the glow appears.
const kBirthdayGlowWindowDays = 7;

/// Returns true if [dateOfBirth] is within [kBirthdayGlowWindowDays]
/// days of [now] (inclusive of today).
///
/// Rules:
///   - null dateOfBirth → false (no glow).
///   - Birthday TODAY (daysUntil == 0) → true (glow at max).
///   - Birthday within 7 days (1..7) → true (glow pulsing).
///   - Birthday passed this year (daysUntil < 0) → false (no glow;
///     could add a "was recently" glow in a future iteration).
///   - Leap-year Feb 29 birthday on a non-leap year → use March 1.
///
/// [now] is overridable for deterministic tests. Defaults to
/// `DateTime.now()`.
bool isNearBirthday(DateTime? dateOfBirth, {DateTime? now}) {
  if (dateOfBirth == null) return false;
  final n = now ?? DateTime.now();
  // Compute this year's birthday, handling Feb 29 → March 1 on
  // non-leap years.
  final birthMonth = dateOfBirth.month;
  final birthDay = dateOfBirth.day;
  final int effectiveDay;
  if (birthMonth == 2 && birthDay == 29 && !_isLeapYear(n.year)) {
    effectiveDay = 1; // March 1
  } else {
    effectiveDay = birthDay;
  }
  final int effectiveMonth = (birthMonth == 2 && birthDay == 29 && !_isLeapYear(n.year))
      ? 3 // March
      : birthMonth;
  final thisYearBirthday = DateTime(n.year, effectiveMonth, effectiveDay);
  final daysUntil = thisYearBirthday.difference(DateTime(n.year, n.month, n.day)).inDays;
  return daysUntil >= 0 && daysUntil <= kBirthdayGlowWindowDays;
}

/// Returns the number of days until the next occurrence of the
/// birthday, or null if [dateOfBirth] is null.
///
/// Returns 0 if the birthday is today. Returns a negative number if
/// the birthday has already passed this year (counting toward next
/// year's occurrence is not done here — callers should treat negative
/// as "not near-birthday this year").
int? daysUntilBirthday(DateTime? dateOfBirth, {DateTime? now}) {
  if (dateOfBirth == null) return null;
  final n = now ?? DateTime.now();
  final birthMonth = dateOfBirth.month;
  final birthDay = dateOfBirth.day;
  final int effectiveDay;
  final int effectiveMonth;
  if (birthMonth == 2 && birthDay == 29 && !_isLeapYear(n.year)) {
    effectiveDay = 1;
    effectiveMonth = 3;
  } else {
    effectiveDay = birthDay;
    effectiveMonth = birthMonth;
  }
  final thisYearBirthday = DateTime(n.year, effectiveMonth, effectiveDay);
  return thisYearBirthday.difference(DateTime(n.year, n.month, n.day)).inDays;
}

bool _isLeapYear(int year) {
  if (year % 4 != 0) return false;
  if (year % 100 != 0) return true;
  return year % 400 == 0;
}
