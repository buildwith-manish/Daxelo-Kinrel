// lib/core/services/local_notification_scheduler.dart
//
// DAXELO KINREL — Local Notification Scheduler (P5-F4)
//
// Schedules retention-focused local notifications using
// flutter_local_notifications. Three notification types:
//
//   1. Inactive 3 days — if no app open for 3 days, show at 7 PM
//   2. Incomplete profile nudge — if < 5 members after 7 days, show once
//   3. Weekly family digest — every Sunday at 10 AM
//
// All notifications use the existing 'daxelo_family' channel.
// Called once on app startup via scheduleAll().

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'retention_service.dart';
import 'crashlytics_service.dart';

// ── Notification IDs ────────────────────────────────────────────────
const int _idInactiveNudge = 5001;
const int _idProfileNudge = 5002;
const int _idWeeklyDigest = 5003;
// Birthday/anniversary reminders use IDs 6000–6999 (offset by person index)
const int _idBirthdayBase = 6000;
const int _idAnniversaryBase = 6500;

// ── Channel ─────────────────────────────────────────────────────────
const String _channelId = 'daxelo_family';
const String _channelName = 'KINREL Family';
const String _channelDescription =
    'Family updates, reminders, and weekly digest';

class LocalNotificationScheduler {
  LocalNotificationScheduler._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  // ── Initialize ───────────────────────────────────────────────────

  /// Initialize the plugin. Must be called before scheduleAll().
  static Future<void> initialize() async {
    if (_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(initSettings);
      _initialized = true;
      debugPrint('✅ LocalNotificationScheduler initialized');
    } catch (e, st) {
      logError(e, st, reason: 'LocalNotificationScheduler init failed');
    }
  }

  // ── Birthday & Anniversary Reminders ──────────────────────────────

  /// Schedule birthday reminders for all family members.
  /// Reminders are scheduled 1 day before the birthday at 9:00 AM local time.
  ///
  /// [members] is a list of maps with 'id', 'name', and 'dateOfBirth' keys.
  static Future<void> scheduleBirthdayReminders(
      List<Map<String, dynamic>> members) async {
    if (!_initialized) {
      await initialize();
      if (!_initialized) return;
    }

    // Cancel any previously scheduled birthday reminders
    for (int i = 0; i < 100; i++) {
      await _cancel(_idBirthdayBase + i);
    }

    final now = DateTime.now();
    int index = 0;

    for (final member in members) {
      if (index >= 500) break; // Safety limit

      final dobStr = member['dateOfBirth'] as String?;
      if (dobStr == null) continue;

      final dob = DateTime.tryParse(dobStr);
      if (dob == null) continue;

      // Calculate this year's birthday
      var thisYearBirthday = DateTime(now.year, dob.month, dob.day);

      // If the birthday already passed this year, schedule for next year
      if (thisYearBirthday.isBefore(now)) {
        thisYearBirthday = DateTime(now.year + 1, dob.month, dob.day);
      }

      // Schedule 1 day before at 9:00 AM
      final reminderDate = DateTime(
        thisYearBirthday.year,
        thisYearBirthday.month,
        thisYearBirthday.day - 1,
        9,
        0,
      );

      // If the reminder date is in the past, skip
      if (reminderDate.isBefore(now)) continue;

      final name = member['name'] as String? ?? 'Someone';

      await _scheduleNotification(
        id: _idBirthdayBase + index,
        title: '🎂 Birthday tomorrow: $name',
        body:
            '$name\'s birthday is tomorrow! Send them a Kinrel greeting.',
        scheduledDate: reminderDate,
        isRepeating: false,
      );

      index++;
    }

    debugPrint('📬 Scheduled $index birthday reminders');
  }

  /// Schedule anniversary reminders for all couples in families.
  /// Reminders are scheduled 1 day before the anniversary at 9:00 AM local time.
  ///
  /// [anniversaries] is a list of maps with 'names', 'date', and 'familyName' keys.
  static Future<void> scheduleAnniversaryReminders(
      List<Map<String, dynamic>> anniversaries) async {
    if (!_initialized) {
      await initialize();
      if (!_initialized) return;
    }

    // Cancel any previously scheduled anniversary reminders
    for (int i = 0; i < 100; i++) {
      await _cancel(_idAnniversaryBase + i);
    }

    final now = DateTime.now();
    int index = 0;

    for (final ann in anniversaries) {
      if (index >= 500) break; // Safety limit

      final dateStr = ann['date'] as String?;
      if (dateStr == null) continue;

      final annDate = DateTime.tryParse(dateStr);
      if (annDate == null) continue;

      // Calculate this year's anniversary
      var thisYearAnniversary = DateTime(now.year, annDate.month, annDate.day);

      // If already passed, schedule for next year
      if (thisYearAnniversary.isBefore(now)) {
        thisYearAnniversary = DateTime(now.year + 1, annDate.month, annDate.day);
      }

      // Schedule 1 day before at 9:00 AM
      final reminderDate = DateTime(
        thisYearAnniversary.year,
        thisYearAnniversary.month,
        thisYearAnniversary.day - 1,
        9,
        0,
      );

      if (reminderDate.isBefore(now)) continue;

      final names = ann['names'] as String? ?? 'Couple';
      final familyName = ann['familyName'] as String? ?? '';

      await _scheduleNotification(
        id: _idAnniversaryBase + index,
        title: '💍 Anniversary tomorrow: $names',
        body:
            '$names celebrate their anniversary tomorrow${familyName.isNotEmpty ? ' in the $familyName family' : ''}!',
        scheduledDate: reminderDate,
        isRepeating: false,
      );

      index++;
    }

    debugPrint('📬 Scheduled $index anniversary reminders');
  }

  // ── Schedule All ─────────────────────────────────────────────────

  /// Schedule all retention notifications based on current engagement data.
  ///
  /// Should be called once after the user signs in and the
  /// engagement data is available. Safe to call multiple times —
  /// existing scheduled notifications are replaced.
  static Future<void> scheduleAll() async {
    if (!_initialized) {
      await initialize();
      if (!_initialized) return;
    }

    try {
      await _scheduleInactiveNudge();
      await _scheduleProfileNudge();
      await _scheduleWeeklyDigest();
      debugPrint('📬 All retention notifications scheduled');
    } catch (e, st) {
      logError(e, st, reason: 'LocalNotificationScheduler.scheduleAll failed');
    }
  }

  /// Schedule all notifications including birthday/anniversary reminders.
  /// Call this after loading family members data.
  static Future<void> scheduleAllWithReminders({
    List<Map<String, dynamic>>? members,
    List<Map<String, dynamic>>? anniversaries,
  }) async {
    await scheduleAll();

    if (members != null) {
      await scheduleBirthdayReminders(members);
    }
    if (anniversaries != null) {
      await scheduleAnniversaryReminders(anniversaries);
    }
  }

  // ── 1. Inactive 3 Days Nudge ────────────────────────────────────

  /// Schedule a nudge at 7 PM today (or tomorrow if already past 7 PM)
  /// if the user hasn't opened the app in 3+ days.
  static Future<void> _scheduleInactiveNudge() async {
    // Only schedule if inactive for 3+ days
    if (!await RetentionService.isInactiveForDays(3)) {
      // Cancel any previously scheduled nudge
      await _cancel(_idInactiveNudge);
      return;
    }

    final scheduledDate = _nextOccurrence(19, 0); // 7 PM today/tomorrow

    await _scheduleNotification(
      id: _idInactiveNudge,
      title: 'We miss you! 🧡',
      body: 'Your family tree is waiting. Come back and add new members!',
      scheduledDate: scheduledDate,
      isRepeating: false,
    );
  }

  // ── 2. Incomplete Profile Nudge ─────────────────────────────────

  /// Schedule a one-time nudge if the user has < 5 members after 7 days
  /// since first app open. Uses the 'profile_nudge_shown' key to
  /// ensure it only fires once.
  static Future<void> _scheduleProfileNudge() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if we already showed this nudge
      final alreadyShown = prefs.getBool('profile_nudge_shown') ?? false;
      if (alreadyShown) {
        await _cancel(_idProfileNudge);
        return;
      }

      // Check if user has been active for 7+ days
      final lastOpenStr = prefs.getString('last_open');
      if (lastOpenStr == null) return;

      final firstOpen = DateTime.tryParse(lastOpenStr);
      if (firstOpen == null) return;

      final daysSinceFirst = DateTime.now().difference(firstOpen).inDays;
      if (daysSinceFirst < 7) return;

      // Check if user has fewer than 5 members
      final membersAdded = await RetentionService.getMembersAdded();
      if (membersAdded >= 5) return;

      // Schedule for tomorrow at 10 AM
      final scheduledDate = _nextOccurrence(10, 0);

      await _scheduleNotification(
        id: _idProfileNudge,
        title: 'Grow your family tree! 🌳',
        body:
            'You\'ve added $membersAdded member${membersAdded == 1 ? '' : 's'} so far. '
            'Try adding more relatives to unlock the full experience!',
        scheduledDate: scheduledDate,
        isRepeating: false,
      );

      // Mark as shown so it doesn't reschedule
      await prefs.setBool('profile_nudge_shown', true);
    } catch (e, st) {
      logError(e, st, reason: 'LocalNotificationScheduler._scheduleProfileNudge failed');
    }
  }

  // ── 3. Weekly Family Digest ─────────────────────────────────────

  /// Schedule a weekly notification every Sunday at 10 AM.
  static Future<void> _scheduleWeeklyDigest() async {
    final nextSunday = _nextDayOfWeek(DateTime.sunday, 10, 0);

    await _scheduleNotification(
      id: _idWeeklyDigest,
      title: 'Your weekly family digest 📋',
      body: 'See what\'s new in your family tree this week.',
      scheduledDate: nextSunday,
      isRepeating: true,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────

  static Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required bool isRepeating,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final tzDateTime = tz.TZDateTime.from(
      scheduledDate,
      tz.local,
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzDateTime,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents:
          isRepeating ? DateTimeComponents.dayOfWeekAndTime : null,
    );
  }

  static Future<void> _cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  /// Get the next occurrence of a specific hour:minute today or tomorrow.
  static DateTime _nextOccurrence(int hour, int minute) {
    final now = DateTime.now();
    var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Get the next occurrence of a specific day of week at hour:minute.
  static DateTime _nextDayOfWeek(int dayOfWeek, int hour, int minute) {
    var date = _nextOccurrence(hour, minute);
    while (date.weekday != dayOfWeek) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  // ── Test Notification (debug only) ───────────────────────────────

  /// Show an immediate test notification (debug/dev only).
  static Future<void> showTestNotification() async {
    if (!_initialized) {
      await initialize();
      if (!_initialized) return;
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      9999,
      'Test Notification 🧪',
      'This is a test notification from the engagement dashboard.',
      details,
    );
  }
}
