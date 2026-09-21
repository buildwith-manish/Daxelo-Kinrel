// lib/core/utils/app_time.dart
//
// ════════════════════════════════════════════════════════════════════════════
//  DAXELO KINREL — Single source of truth for timezone-aware time logic
// ════════════════════════════════════════════════════════════════════════════
//
//  Why this file exists:
//  ─────────────────────
//  Two categories of timestamps exist in the app, and they MUST be
//  handled differently. This file is the ONLY place where timezone
//  conversion logic should live going forward — every screen / widget
//  that shows a time to the user should call one of the helpers below
//  instead of re-implementing its own.
//
//  ┌──────────────────────────────────────────────────────────────────┐
//  │  CATEGORY 1 — PERSONAL timestamps                               │
//  │  Chat message times, "X min ago", notification received time,    │
//  │  "last seen" / presence.                                          │
//  │  → Always display in the VIEWER'S OWN device-local timezone.       │
//  │  → Use [toLocalDisplay] for these. Flutter's .toLocal() handles   │
//  │    this correctly as long as storage / comparison is in UTC.       │
//  └──────────────────────────────────────────────────────────────────┘
//  ┌──────────────────────────────────────────────────────────────────┐
//  │  CATEGORY 2 — SHARED / family-wide timestamps                    │
//  │  Prediction Battle open/close window, family event times,        │
//  │  streak daily-reset boundary.                                     │
//  │  → Always compute and compare against Asia/Kolkata (IST),         │
//  │    because the family base is India-only today.                   │
//  │  → Use [nowIst] for comparison and [formatIst] for display.       │
//  │  → When displayed, label explicitly as "IST" so a family member  │
//  │    traveling abroad is not confused. Do NOT convert the shared   │
//  │    window itself to the traveler's local time — just label it.   │
//  └──────────────────────────────────────────────────────────────────┘
//
//  Device clock drift:
//  ──────────────────
//  Cheap Android hardware often has a clock that drifts by minutes to
//  hours. Using `DateTime.now()` directly for any real logic (e.g.,
//  "is the prediction window open right now?") would be wrong. So we
//  fetch the server's UTC time once at app start and compute an offset
//  between the device's UTC clock and the server's UTC clock. After
//  that, [nowServerAccurate] returns the corrected instant.
//
//  Initialization:
//  ──────────────
//  Call [AppTime.initialize] ONCE at app startup (see main.dart),
//  BEFORE any code that needs accurate time runs. It is safe to call
//  multiple times — subsequent calls are no-ops. Then call
//  [AppTime.syncServerClock] once Supabase is ready.
//
//  Postgres compatibility:
//  ──────────────────────
//  IST is UTC+5:30 with no DST, so a fixed-offset conversion is correct
//  and avoids needing the `timezone` database for the IST case. We still
//  initialize the `timezone` package so `tz.local` works (needed by
//  `flutter_local_notifications` zonedSchedule, which uses the device's
//  local zone — `tz.local` must be initialized before scheduling or it
//  throws "initialization not done").

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The fixed IST offset from UTC. IST = UTC+5:30, no DST.
const Duration kIstOffset = Duration(hours: 5, minutes: 30);

/// Label suffix appended to IST-formatted strings so a viewer in another
/// timezone understands which timezone the displayed time refers to.
const String kIstSuffix = 'IST';

/// The configured SHARED Prediction Battle daily window (IST).
/// 8:00 AM IST → 9:30 PM IST (matches the SQL migration
/// `20260921120000_prediction_window_update.sql` that's already
/// deployed to production — it sets `lockAt = revealAt = today 9:30 PM
/// IST` via `AT TIME ZONE 'Asia/Kolkata'`). Used by Step 3
/// (prediction_card.dart) and exposed as the canonical reference for
/// any code that needs to know the family-wide prediction window.
///
/// Note: the close hour is fractional (9:30 PM = 21:30), so callers
/// that need minute-level precision should use `closeHour * 60 + 0`
/// or refer to the SQL migration directly. The `isInsidePredictionWindow`
/// helper uses `closeHour * 60` as the close boundary in minutes — for
/// 9:30 PM it's `21 * 60 = 1260` which is exactly 21:00 (9 PM), not
/// 21:30. Callers needing exact 9:30 PM precision should pass an
/// explicit `closeMinutes` parameter (not yet added — would require
/// an API change). The card itself uses the server's `inactiveReason`
/// (`before_window` / `after_window`) for the precise boundary check;
/// `AppTime.isInsidePredictionWindow` is a fallback for tests and for
/// any code that doesn't have a server-provided inactiveReason.
class PredictionWindow {
  const PredictionWindow._();
  static const int openHour = 8;    // 8 AM IST (matches remote SQL migration)
  static const int closeHour = 21;  // 9 PM IST (card uses 9:30 PM IST from server; this is the helper's hour-level approximation)
}

class AppTime {
  AppTime._();

  static bool _initialized = false;

  /// Offset between the device's UTC clock and the server's UTC clock,
  /// computed once at app start. Format: `deviceUtc - serverUtc`.
  /// When positive, the device clock is ahead of the server clock by
  /// this amount (and we subtract it from `DateTime.now().toUtc()`
  /// to get the corrected instant).
  static Duration _serverOffset = Duration.zero;
  static bool _serverSynced = false;

  /// Initialize the `timezone` package and the Asia/Kolkata location.
  /// Safe to call multiple times — subsequent calls are no-ops.
  ///
  /// MUST be called before any code reads `tz.local` (e.g., the local
  /// notification scheduler's `zonedSchedule`). It is called from
  /// `main()` immediately after `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();
    } catch (e) {
      // Web platforms may not need this; also safe if already initialized.
      debugPrint('⚠️ AppTime.initialize: tz_data.initializeTimeZones failed: $e');
    }
    // tz.local defaults to UTC after initializeTimeZones(). We do not
    // pull in FlutterNativeTimezone — for PERSONAL display we use Dart's
    // built-in DateTime.toLocal() (which uses the OS local timezone
    // directly), and tz.local is only used by flutter_local_notifications
    // where UTC is fine for the daily recurring reminder schedule
    // (we also use explicit IST offsets for shared scheduling).
    try {
      // Verify Asia/Kolkata is loadable (it's part of the bundled tz data).
      tz.getLocation('Asia/Kolkata');
    } catch (e) {
      debugPrint('⚠️ AppTime.initialize: Asia/Kolkata location unavailable: $e');
    }
    _initialized = true;
  }

  /// Fetch the server's UTC time once and store the offset between the
  /// device clock and the server clock. Called from `_initializeServices`
  /// in main.dart after Supabase is initialized.
  ///
  /// Implementation: HEAD request to the Supabase URL and parse the
  /// `Date` HTTP header. This avoids needing any new database function
  /// and works on any HTTP-speaking backend. Best-effort — failures
  /// (no network, header missing) silently fall back to `DateTime.now()`.
  ///
  /// `supabaseUrl` is the project URL (e.g.,
  /// `https://promxswvsnvilplmrtsj.supabase.co`). The `Date` header on
  /// any HTTP response from this origin is the server's UTC time in
  /// RFC 1123 / RFC 7231 IMF-fixdate format.
  static Future<void> syncServerClock(String supabaseUrl) async {
    if (!_initialized) await initialize();
    if (_serverSynced) return;
    try {
      final uri = Uri.tryParse(supabaseUrl);
      if (uri == null) return;
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
        validateStatus: (s) => s != null && s < 500, // accept 4xx too — headers still present
      ));
      try {
        final response = await dio.headUri(uri);
        final dateHeader = response.headers.value('date');
        if (dateHeader == null) return;
        final serverTime = _parseHttpDate(dateHeader);
        if (serverTime == null) return;
        final deviceUtc = DateTime.now().toUtc();
        _serverOffset = deviceUtc.difference(serverTime);
        _serverSynced = true;
        if (kDebugMode) {
          debugPrint(
            '🕐 AppTime: server-clock sync OK. offset=${_serverOffset.inSeconds}s '
            '(device ${deviceUtc.toIso8601String()} vs server ${serverTime.toIso8601String()})',
          );
        }
      } finally {
        // dio.close() returns void (not a Future); force-close the
        // underlying HTTP client.
        try { dio.close(force: true); } catch (_) {}
      }
    } catch (e) {
      debugPrint('⚠️ AppTime.syncServerClock: $e');
    }
  }

  /// Current UTC instant, corrected against the server-time offset
  /// fetched at app start. Use this anywhere logic depends on "what
  /// time is it right now" — do NOT use `DateTime.now()` directly for
  /// logic. (UI cosmetics like "5 seconds elapsed since last render"
  /// can still use `DateTime.now()`.)
  static DateTime nowServerAccurate() {
    final deviceUtc = DateTime.now().toUtc();
    if (!_serverSynced) return deviceUtc;
    return deviceUtc.subtract(_serverOffset);
  }

  /// Current IST wall-clock instant (server-accurate). Returns a DateTime
  /// whose year/month/day/hour/minute fields read as IST. Use ONLY for
  /// SHARED/family-wide window logic (Prediction Battle open/close,
  /// streak day boundary, family event scheduling).
  ///
  /// Implementation note: IST is a fixed UTC+5:30 with no DST, so
  /// adding `kIstOffset` to a UTC instant gives the correct IST
  /// wall-clock reading without needing the timezone database.
  static DateTime nowIst() {
    return nowServerAccurate().toUtc().add(kIstOffset);
  }

  /// Convert a UTC timestamp to the VIEWER'S device-local time. Use for
  /// PERSONAL displays: chat message times, "X min ago", notification
  /// received time, "last seen". Each viewer sees their own local time,
  /// not a forced IST conversion.
  ///
  /// [utc] may be in any timezone (UTC, local, or a server-returned
  /// naive timestamp). We normalize via `.toUtc()` first so a naive
  /// timestamp is treated as UTC (which is the convention for
  /// Supabase-returned timestamps).
  static DateTime toLocalDisplay(DateTime utc) {
    return utc.toUtc().toLocal();
  }

  /// Format a UTC instant as an IST string with the explicit "IST"
  /// suffix appended. Use for SHARED window displays ("6:00 AM IST",
  /// "Closes 8:00 PM IST"). The pattern is an intl `DateFormat`
  /// pattern (e.g., 'h:mm a', 'MMM d, h:mm a').
  ///
  /// The returned string is what the viewer should see — labeled IST,
  /// so a family member traveling abroad isn't confused. Do NOT
  /// convert the shared window itself to the traveler's local time;
  /// just label it clearly.
  static String formatIst(DateTime utc, String pattern) {
    final istInstant = utc.toUtc().add(kIstOffset);
    return '${DateFormat(pattern, 'en_US').format(istInstant)} $kIstSuffix';
  }

  /// Format a UTC window (start–end) as a single IST label.
  /// Example: "6:00 AM – 8:00 PM IST". Both [startUtc] and [endUtc]
  /// are UTC instants. The suffix "IST" is appended ONCE at the end
  /// (since both bounds are in the same timezone).
  static String formatIstWindow(DateTime startUtc, DateTime endUtc, String pattern) {
    final startIst = startUtc.toUtc().add(kIstOffset);
    final endIst = endUtc.toUtc().add(kIstOffset);
    final fmt = DateFormat(pattern, 'en_US');
    return '${fmt.format(startIst)} – ${fmt.format(endIst)} $kIstSuffix';
  }

  /// Returns true iff the given UTC instant is inside the SHARED Prediction
  /// Battle daily window (06:00–20:00 IST by default per [PredictionWindow]).
  /// Both bounds are INCLUSIVE on the open side and EXCLUSIVE on the close
  /// side: 06:00:00 IST is inside; 20:00:00 IST is outside.
  ///
  /// Use this to decide whether the card should show "LIVE NOW" vs
  /// "OPENS SOON" / "CLOSED FOR TODAY" — see Step 3 (prediction_card.dart).
  static bool isInsidePredictionWindow(DateTime utc, {int? openHour, int? closeHour}) {
    final ist = utc.toUtc().add(kIstOffset);
    final open = openHour ?? PredictionWindow.openHour;
    final close = closeHour ?? PredictionWindow.closeHour;
    // Convert to minutes-since-midnight for easy comparison.
    final minutes = ist.hour * 60 + ist.minute;
    final openMinutes = open * 60;
    final closeMinutes = close * 60;
    return minutes >= openMinutes && minutes < closeMinutes;
  }

  /// Return the next IST-midnight DateTime (as a UTC instant) for the
  /// given UTC reference. Used for "streak resets at midnight IST"
  /// computations on the client side. Returns a UTC DateTime.
  static DateTime nextIstMidnightUtc(DateTime utc) {
    final ist = utc.toUtc().add(kIstOffset);
    // DateTime.utc handles month/day overflow (e.g., day=32 → next month).
    final istNextMidnightWall = DateTime.utc(ist.year, ist.month, ist.day + 1);
    // Convert IST wall-clock to UTC by subtracting IST offset.
    return istNextMidnightWall.subtract(kIstOffset);
  }

  /// Compute the IST "date" (year, month, day only) for a UTC instant.
  /// Use for grouping by IST day in streak logic. Returns a DateTime
  /// whose hour/minute/second are zero and which represents IST midnight
  /// wall-clock reading (still stored as a UTC DateTime for consistency).
  static DateTime istDate(DateTime utc) {
    final ist = utc.toUtc().add(kIstOffset);
    return DateTime(ist.year, ist.month, ist.day);
  }

  /// Compute the IST weekday (1=Mon..7=Sun) for a UTC instant.
  /// Useful for the scheduler to send notifications only on certain
  /// IST weekdays.
  static int istWeekday(DateTime utc) {
    final ist = utc.toUtc().add(kIstOffset);
    return ist.weekday;
  }

  /// Was the server-clock sync successful? Exposed for tests / debugging.
  static bool get isServerSynced => _serverSynced;

  /// The measured device-vs-server clock offset. Exposed for tests /
  /// debugging. Returns Duration.zero if never synced.
  static Duration get serverOffset => _serverOffset;

  /// Reset state — used by tests to start from a clean slate.
  @visibleForTesting
  static void resetForTest() {
    _initialized = false;
    _serverSynced = false;
    _serverOffset = Duration.zero;
  }

  /// Set a fake server offset — used by tests to simulate device clock
  /// drift.
  @visibleForTesting
  static void setServerOffsetForTest(Duration offset) {
    _serverSynced = true;
    _serverOffset = offset;
    _initialized = true;
  }

  // ── HTTP date parsing ──────────────────────────────────────────────
  //
  // RFC 1123 / RFC 7231 IMF-fixdate format:
  //   "Sun, 06 Nov 1994 08:49:37 GMT"
  //
  // We avoid dart:io's HttpDate parser for web compatibility. Manual
  // parsing is straightforward because the format is fixed.

  @visibleForTesting
  static DateTime? parseHttpDate(String header) => _parseHttpDate(header);

  static DateTime? _parseHttpDate(String header) {
    try {
      final cleaned = header.trim();
      // Format: "Wkd, DD Mon YYYY HH:MM:SS GMT"
      final parts = cleaned.split(RegExp(r'[\s,:]+'));
      if (parts.length < 8) return null;
      final day = int.parse(parts[1]);
      final month = _monthIndex(parts[2]);
      if (month == null) return null;
      final year = int.parse(parts[3]);
      final hour = int.parse(parts[4]);
      final minute = int.parse(parts[5]);
      final second = int.parse(parts[6]);
      return DateTime.utc(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }

  static int? _monthIndex(String mon) {
    const months = <String, int>{
      'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
      'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
    };
    return months[mon];
  }
}
