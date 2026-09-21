// test/core/utils/app_time_test.dart
//
// Step 1 — Tests for the shared time utility lib/core/utils/app_time.dart.
//
// Verifies:
//   - nowServerAccurate() returns device UTC when not synced.
//   - nowServerAccurate() applies the server-offset when synced
//     (device clock ahead of server → result is earlier; device clock
//     behind server → result is later).
//   - nowIst() = nowServerAccurate() + 5h30m.
//   - toLocalDisplay() converts UTC → viewer-local (uses Flutter's
//     toLocal() which on the test VM is UTC, so the conversion is a
//     no-op — but the API still exercises the path).
//   - formatIst() appends "IST" suffix and formats the wall-clock time
//     in IST (not UTC).
//   - formatIstWindow() formats a window with a single IST suffix.
//   - isInsidePredictionWindow():
//       * 5:59 AM IST → false (before open)
//       * 6:00 AM IST → true (exactly at open)
//       * 7:30 AM IST → true (mid window)
//       * 7:59 PM IST → true (just before close)
//       * 8:00 PM IST → false (exactly at close — exclusive)
//       * 9:00 PM IST → false (after close)
//   - nextIstMidnightUtc() returns the UTC instant corresponding to
//     the next midnight IST.
//   - istDate() returns IST year/month/day.
//   - parseHttpDate() handles standard RFC 1123 / IMF-fixdate strings.

import 'package:flutter_test/flutter_test.dart';
import 'package:kinrel/core/utils/app_time.dart';

void main() {
  // Each test must reset the singleton state so prior tests don't leak
  // server-offset values into later tests.
  setUp(AppTime.resetForTest);

  group('AppTime.initialize', () {
    test('is safe to call multiple times (no-ops on subsequent calls)', () async {
      await AppTime.initialize();
      await AppTime.initialize();
      await AppTime.initialize();
      // No exception thrown — pass.
    });
  });

  group('AppTime.nowServerAccurate', () {
    test('returns device UTC when not synced', () {
      final before = DateTime.now().toUtc();
      final result = AppTime.nowServerAccurate();
      final after = DateTime.now().toUtc();
      expect(result.isUtc, isTrue);
      // Within the (before, after) window.
      expect(!result.isBefore(before), isTrue);
      expect(!result.isAfter(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('subtracts the server offset when synced (device ahead of server)',
        () {
      // Device is 60 seconds ahead of the server. nowServerAccurate
      // must subtract 60s from the device clock.
      AppTime.setServerOffsetForTest(const Duration(seconds: 60));
      final before = DateTime.now().toUtc();
      final result = AppTime.nowServerAccurate();
      final after = DateTime.now().toUtc();
      // The returned instant should be ~60s earlier than device now.
      expect(result.isBefore(before), isTrue);
      expect(result.isBefore(after), isTrue);
      // Roughly 60s delta.
      final delta = before.difference(result).inSeconds;
      expect(delta, inInclusiveRange(58, 62));
    });

    test('subtracts a negative offset (device behind of server)', () {
      // Device is 120 seconds behind the server. nowServerAccurate
      // must ADD 120s to the device clock (subtract negative offset).
      AppTime.setServerOffsetForTest(const Duration(seconds: -120));
      final before = DateTime.now().toUtc();
      final result = AppTime.nowServerAccurate();
      // The returned instant should be ~120s later than device now.
      expect(result.isAfter(before), isTrue);
      final delta = result.difference(before).inSeconds;
      expect(delta, inInclusiveRange(118, 122));
    });
  });

  group('AppTime.nowIst', () {
    test('is nowServerAccurate() + 5h30m', () {
      AppTime.setServerOffsetForTest(Duration.zero);
      final utc = AppTime.nowServerAccurate();
      final ist = AppTime.nowIst();
      // IST is UTC+5:30.
      final expectedIst = utc.add(const Duration(hours: 5, minutes: 30));
      // The wall-clock reading should be identical (5:30 ahead).
      expect(ist.year, expectedIst.year);
      expect(ist.month, expectedIst.month);
      expect(ist.day, expectedIst.day);
      expect(ist.hour, expectedIst.hour);
      expect(ist.minute, expectedIst.minute);
    });
  });

  group('AppTime.toLocalDisplay', () {
    test('converts a UTC instant to local (no-op on test VM where local=UTC)',
        () {
      final utc = DateTime.utc(2026, 9, 21, 10, 30, 0);
      final local = AppTime.toLocalDisplay(utc);
      // On the flutter test VM, DateTime.now().timeZoneName is 'UTC' so
      // toLocal() is a no-op. We just verify the API path runs.
      expect(local.year, utc.year);
      expect(local.month, utc.month);
      expect(local.day, utc.day);
      expect(local.hour, utc.hour);
    });

    test('handles a naive timestamp (treated as UTC)', () {
      final naive = DateTime(2026, 9, 21, 10, 30, 0);
      final local = AppTime.toLocalDisplay(naive);
      // Should be treated as UTC and converted to local (no-op on VM).
      expect(local.year, 2026);
      expect(local.hour, 10);
    });
  });

  group('AppTime.formatIst', () {
    test('formats a UTC instant as IST with suffix', () {
      final utc = DateTime.utc(2026, 9, 21, 0, 30, 0); // 00:30 UTC = 06:00 IST
      final result = AppTime.formatIst(utc, 'h:mm a');
      // Should show "6:00 AM IST".
      expect(result, '6:00 AM IST');
    });

    test('formats afternoon IST correctly', () {
      final utc = DateTime.utc(2026, 9, 21, 14, 30, 0); // 14:30 UTC = 20:00 IST
      final result = AppTime.formatIst(utc, 'h:mm a');
      expect(result, '8:00 PM IST');
    });

    test('handles midnight boundary', () {
      final utc = DateTime.utc(2026, 9, 21, 18, 30, 0); // 18:30 UTC = 00:00 IST next day
      final result = AppTime.formatIst(utc, 'MMM d, h:mm a');
      expect(result, 'Sep 22, 12:00 AM IST');
    });
  });

  group('AppTime.formatIstWindow', () {
    test('formats a window with a single IST suffix', () {
      // 6 AM - 8 PM IST = 00:30 UTC - 14:30 UTC
      final start = DateTime.utc(2026, 9, 21, 0, 30, 0);
      final end = DateTime.utc(2026, 9, 21, 14, 30, 0);
      final result = AppTime.formatIstWindow(start, end, 'h:mm a');
      expect(result, '6:00 AM – 8:00 PM IST');
    });
  });

  group('AppTime.isInsidePredictionWindow', () {
    test('5:59 AM IST is OUTSIDE (just before open)', () {
      // 5:59 AM IST = 00:29 UTC
      final utc = DateTime.utc(2026, 9, 21, 0, 29, 0);
      expect(AppTime.isInsidePredictionWindow(utc), isFalse);
    });

    test('6:00 AM IST is INSIDE (exactly at open, inclusive)', () {
      // 6:00 AM IST = 00:30 UTC
      final utc = DateTime.utc(2026, 9, 21, 0, 30, 0);
      expect(AppTime.isInsidePredictionWindow(utc), isTrue);
    });

    test('7:30 AM IST is INSIDE (mid-window)', () {
      // 7:30 AM IST = 02:00 UTC
      final utc = DateTime.utc(2026, 9, 21, 2, 0, 0);
      expect(AppTime.isInsidePredictionWindow(utc), isTrue);
    });

    test('7:59 PM IST is INSIDE (just before close)', () {
      // 7:59 PM IST = 14:29 UTC
      final utc = DateTime.utc(2026, 9, 21, 14, 29, 0);
      expect(AppTime.isInsidePredictionWindow(utc), isTrue);
    });

    test('8:00 PM IST is OUTSIDE (exactly at close, exclusive)', () {
      // 8:00 PM IST = 14:30 UTC
      final utc = DateTime.utc(2026, 9, 21, 14, 30, 0);
      expect(AppTime.isInsidePredictionWindow(utc), isFalse);
    });

    test('9:00 PM IST is OUTSIDE (after close)', () {
      // 9:00 PM IST = 15:30 UTC
      final utc = DateTime.utc(2026, 9, 21, 15, 30, 0);
      expect(AppTime.isInsidePredictionWindow(utc), isFalse);
    });

    test('11:00 PM IST is OUTSIDE (late night)', () {
      // 11:00 PM IST = 17:30 UTC
      final utc = DateTime.utc(2026, 9, 21, 17, 30, 0);
      expect(AppTime.isInsidePredictionWindow(utc), isFalse);
    });

    test('2:00 AM IST is OUTSIDE (early morning)', () {
      // 2:00 AM IST = 20:30 UTC (previous day in UTC)
      final utc = DateTime.utc(2026, 9, 20, 20, 30, 0);
      expect(AppTime.isInsidePredictionWindow(utc), isFalse);
    });

    test('honors custom open/close hours', () {
      // 9 AM IST = 03:30 UTC
      final utc = DateTime.utc(2026, 9, 21, 3, 30, 0);
      // Default 6 AM–8 PM IST: 9 AM IST is inside.
      expect(AppTime.isInsidePredictionWindow(utc), isTrue);
      // Custom 10 AM–11 AM IST: 9 AM IST is outside.
      expect(AppTime.isInsidePredictionWindow(utc, openHour: 10, closeHour: 11), isFalse);
    });
  });

  group('AppTime.nextIstMidnightUtc', () {
    test('returns next midnight IST as a UTC instant', () {
      // 2026-09-21 10:00 UTC = 15:30 IST on the same day. Next IST
      // midnight = 2026-09-22 00:00 IST = 2026-09-21 18:30 UTC.
      final utc = DateTime.utc(2026, 9, 21, 10, 0, 0);
      final result = AppTime.nextIstMidnightUtc(utc);
      expect(result, DateTime.utc(2026, 9, 21, 18, 30, 0));
    });

    test('handles IST-midnight-adjacent instant', () {
      // 2026-09-21 18:00 UTC = 23:30 IST. Next IST midnight = 30 minutes
      // later = 2026-09-21 18:30 UTC.
      final utc = DateTime.utc(2026, 9, 21, 18, 0, 0);
      final result = AppTime.nextIstMidnightUtc(utc);
      expect(result, DateTime.utc(2026, 9, 21, 18, 30, 0));
    });
  });

  group('AppTime.istDate', () {
    test('returns IST year/month/day', () {
      // 2026-09-21 20:00 UTC = 2026-09-22 01:30 IST (next day in IST).
      final utc = DateTime.utc(2026, 9, 21, 20, 0, 0);
      final result = AppTime.istDate(utc);
      expect(result.year, 2026);
      expect(result.month, 9);
      expect(result.day, 22);
    });

    test('same IST date when UTC is well inside IST day', () {
      // 2026-09-21 10:00 UTC = 15:30 IST (same IST day).
      final utc = DateTime.utc(2026, 9, 21, 10, 0, 0);
      final result = AppTime.istDate(utc);
      expect(result.year, 2026);
      expect(result.month, 9);
      expect(result.day, 21);
    });
  });

  group('AppTime.istWeekday', () {
    test('returns ISO weekday (1=Mon..7=Sun) in IST', () {
      // 2026-09-21 20:00 UTC = 2026-09-22 01:30 IST. 2026-09-22 is a
      // Tuesday → weekday 2.
      final utc = DateTime.utc(2026, 9, 21, 20, 0, 0);
      expect(AppTime.istWeekday(utc), 2);
    });
  });

  group('AppTime.parseHttpDate', () {
    test('parses a standard IMF-fixdate (RFC 7231) string', () {
      final result = AppTime.parseHttpDate('Sun, 06 Nov 1994 08:49:37 GMT');
      expect(result, DateTime.utc(1994, 11, 6, 8, 49, 37));
    });

    test('parses a recent date string', () {
      final result = AppTime.parseHttpDate('Mon, 21 Sep 2026 14:30:00 GMT');
      expect(result, DateTime.utc(2026, 9, 21, 14, 30, 0));
    });

    test('returns null on malformed input', () {
      expect(AppTime.parseHttpDate('not a date'), isNull);
      expect(AppTime.parseHttpDate(''), isNull);
    });
  });
}
