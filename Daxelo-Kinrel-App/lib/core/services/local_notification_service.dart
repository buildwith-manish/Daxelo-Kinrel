// lib/core/services/local_notification_service.dart
//
// DAXELO KINREL — Local Notification Service (P3-F3)
//
// Displays foreground FCM messages as local notifications
// using flutter_local_notifications. Required because FCM
// does NOT automatically show notifications when the app
// is in the foreground on Android/iOS.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/crashlytics_service.dart';

// ═══════════════════════════════════════════════════════════════════════
// Notification Channel Constants
// ═══════════════════════════════════════════════════════════════════════

/// Default notification channel ID for FCM foreground messages.
const String defaultChannelId = 'kinrel_notifications';

/// Default notification channel name.
const String defaultChannelName = 'KINREL Notifications';

/// Default notification channel description.
const String defaultChannelDescription =
    'Notifications for family events, birthdays, and updates';

// ═══════════════════════════════════════════════════════════════════════
// Local Notification Service
// ═══════════════════════════════════════════════════════════════════════

/// Service for displaying local notifications when FCM messages
/// arrive while the app is in the foreground.
///
/// FCM automatically shows notifications when the app is in the
/// background or terminated. But when the app is foregrounded,
/// we must manually display a local notification.
///
/// Usage:
/// ```dart
/// final service = LocalNotificationService();
/// await service.initialize();
/// service.showNotification(title: 'Hello', body: 'World', payload: '/member/123');
/// ```
class LocalNotificationService {
  LocalNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Whether the service has been successfully initialized.
  bool get isInitialized => _initialized;

  // ── Initialization ─────────────────────────────────────────────

  /// Initialize the local notification plugin.
  ///
  /// Must be called before [showNotification].
  /// Configures platform-specific initialization settings and
  /// creates the default Android notification channel.
  Future<void> initialize() async {
    if (_initialized) return;

    // Only supported on Android and iOS
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint(
        '⏭️ LocalNotificationService skipped — not a mobile platform',
      );
      return;
    }

    try {
      // Android initialization settings
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );

      // iOS initialization settings
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false, // FCM handles permission request
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );

      _initialized = true;
      debugPrint('✅ LocalNotificationService initialized');
    } catch (e, st) {
      logError(
        e,
        st,
        reason: 'LocalNotificationService initialization failed',
      );
      debugPrint('⚠️ LocalNotificationService init failed: $e');
    }
  }

  // ── Show Notification ──────────────────────────────────────────

  /// Display a local notification for a foreground FCM message.
  ///
  /// [title] — notification title
  /// [body] — notification body text
  /// [payload] — optional deep link payload (e.g., '/member/abc123')
  /// [notificationType] — the FCM notification type for channel selection
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    String? notificationType,
  }) async {
    if (!_initialized) {
      debugPrint('⚠️ LocalNotificationService not initialized, skipping show');
      return;
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        _channelIdForType(notificationType),
        _channelNameForType(notificationType),
        channelDescription: _channelDescriptionForType(notificationType),
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        // Use app icon as small icon
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

      // Use a hash of the payload as a unique ID to avoid duplicates
      final id = payload?.hashCode ?? DateTime.now().millisecond;

      await _plugin.show(id, title, body, details, payload: payload);

      logActionBreadcrumb('local_notification_shown', {
        'title': title,
        'type': notificationType ?? 'unknown',
        'payload': payload ?? 'none',
      });
    } catch (e, st) {
      logError(e, st, reason: 'Failed to show local notification');
    }
  }

  // ── Notification Tap Handler ───────────────────────────────────

  /// Callback invoked when a local notification is tapped.
  /// Set by PushNotificationService to handle deep linking.
  static void Function(NotificationResponse)? onNotificationTap;

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    debugPrint('📬 Local notification tapped — payload: $payload');

    logActionBreadcrumb('local_notification_tapped', {
      'payload': payload ?? 'none',
      'notificationResponseType': response.notificationResponseType.name,
    });

    // Delegate to the external handler (set by PushNotificationService)
    if (onNotificationTap != null && payload != null) {
      onNotificationTap!(response);
    }
  }

  // ── Channel Selection ──────────────────────────────────────────

  /// Map notification type to Android channel ID.
  String _channelIdForType(String? type) {
    switch (type) {
      case 'birthday_reminder':
        return 'kinrel_birthdays';
      case 'new_family_member':
        return 'kinrel_members';
      case 'family_event':
        return 'kinrel_events';
      default:
        return defaultChannelId;
    }
  }

  /// Map notification type to Android channel name.
  String _channelNameForType(String? type) {
    switch (type) {
      case 'birthday_reminder':
        return 'Birthday Reminders';
      case 'new_family_member':
        return 'Family Members';
      case 'family_event':
        return 'Family Events';
      default:
        return defaultChannelName;
    }
  }

  /// Map notification type to Android channel description.
  String _channelDescriptionForType(String? type) {
    switch (type) {
      case 'birthday_reminder':
        return 'Reminders for upcoming family birthdays';
      case 'new_family_member':
        return 'Notifications about new family members';
      case 'family_event':
        return 'Updates about family events and celebrations';
      default:
        return defaultChannelDescription;
    }
  }

  // ── Cancel ─────────────────────────────────────────────────────

  /// Cancel a specific notification by ID.
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  /// Cancel all active notifications.
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Riverpod Provider
// ═══════════════════════════════════════════════════════════════════════

/// Riverpod provider for the LocalNotificationService singleton.
final localNotificationServiceProvider = Provider<LocalNotificationService>((ref) {
  final service = LocalNotificationService();
  ref.onDispose(() => service.cancelAll());
  return service;
});
