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
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import 'retention_service.dart';
import 'crashlytics_service.dart';

// ── Notification IDs ────────────────────────────────────────────────
const int _idInactiveNudge = 5001;
const int _idProfileNudge = 5002;
const int _idWeeklyDigest = 5003;

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

  // ── Schedule All ─────────────────────────────────────────────────

  /// Schedule all retention notifications based on current engagement data.
  ///
  /// Should be called once after the user signs in and the
  /// engagement box is available. Safe to call multiple times —
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

  // ── 1. Inactive 3 Days Nudge ────────────────────────────────────

  /// Schedule a nudge at 7 PM today (or tomorrow if already past 7 PM)
  /// if the user hasn't opened the app in 3+ days.
  static Future<void> _scheduleInactiveNudge() async {
    // Only schedule if inactive for 3+ days
    if (!RetentionService.isInactiveForDays(3)) {
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
      final box = Hive.box('engagement');

      // Check if we already showed this nudge
      final alreadyShown =
          box.get('profile_nudge_shown', defaultValue: false) as bool;
      if (alreadyShown) {
        await _cancel(_idProfileNudge);
        return;
      }

      // Check if user has been active for 7+ days
      final lastOpenStr = box.get('last_open') as String?;
      if (lastOpenStr == null) return;

      final firstOpen = DateTime.tryParse(lastOpenStr);
      if (firstOpen == null) return;

      final daysSinceFirst = DateTime.now().difference(firstOpen).inDays;
      if (daysSinceFirst < 7) return;

      // Check if user has fewer than 5 members
      final membersAdded = RetentionService.getMembersAdded();
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
      await box.put('profile_nudge_shown', true);
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
