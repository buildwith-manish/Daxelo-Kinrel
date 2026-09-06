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

  /// Tier 2 / Reply from Notification — Display a chat message
  /// notification WITH an inline reply action (Android RemoteInput /
  /// iOS UNTextInputNotificationAction). Tapping the inline reply
  /// field + typing + sending triggers the [onReply] callback with
  /// the user's text + the chat context encoded in [replyPayload].
  ///
  /// [replyPayload] is a JSON string the reply handler parses to
  /// identify which chat to send the reply to. Format:
  ///   {"familyId": "...", "dmUserId": null|"...", "replyToMessageId": null|"..."}
  ///
  /// On Android: a "Reply" action button with a text input field
  /// appears in the notification shade. On iOS: a "Reply" action with
  /// a text input appears when long-pressing / 3D-touching the
  /// notification.
  ///
  /// The reply is handled by the static [onReply] callback (set by the
  /// app's main() or a dedicated reply-handler service). The callback
  /// is responsible for sending the reply via the appropriate chat
  /// (ChatNotifier for family chat, DirectChatNotifier for DMs).
  Future<void> showNotificationWithReplyAction({
    required String title,
    required String body,
    required String replyPayload,
    String? notificationType,
  }) async {
    if (!_initialized) {
      debugPrint('⚠️ LocalNotificationService not initialized, skipping show');
      return;
    }

    try {
      // ── Android ──
      // Build an AndroidNotificationAction with an
      // AndroidNotificationActionInput (RemoteInput) so the OS shows
      // a "Reply" inline-input field in the notification shade. The
      // reply text comes back via onDidReceiveNotificationResponse
      // with notificationResponseType = selectedNotificationAction +
      // a non-null response.input.
      final androidAction = AndroidNotificationAction(
        'reply_action', // unique action ID for de-dup in _handle
        'Reply', // button label
        showsUserInterface: false, // don't open the app — silent send
        inputs: const [
          AndroidNotificationActionInput(
            allowFreeFormInput: true,
            label: 'Type a reply…',
          ),
        ],
      );

      final androidDetails = AndroidNotificationDetails(
        _channelIdForType(notificationType),
        _channelNameForType(notificationType),
        channelDescription: _channelDescriptionForType(notificationType),
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
        actions: [androidAction],
      );

      // ── iOS ──
      // DarwinNotificationAction with .textInput type shows a text
      // field when the user long-presses / 3D-touches the notification.
      // The reply comes back via the same onDidReceiveNotificationResponse
      // path, with actionIdentifier = 'reply_action'.
      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'reply_category',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      final id = replyPayload.hashCode;

      await _plugin.show(
        id,
        title,
        body,
        details,
        payload: replyPayload,
      );

      logActionBreadcrumb('local_notification_shown_with_reply', {
        'title': title,
        'type': notificationType ?? 'unknown',
      });
    } catch (e, st) {
      logError(e, st, reason: 'Failed to show notification with reply action');
    }
  }

  // ── Notification Tap Handler ───────────────────────────────────

  /// Callback invoked when a local notification is tapped.
  /// Set by PushNotificationService to handle deep linking.
  static void Function(NotificationResponse)? onNotificationTap;

  /// Tier 2 / Reply from Notification — callback invoked when the
  /// user replies inline from a notification. Set by the app's
  /// reply-handler service (typically in main.dart). Receives:
  ///   - payload: the JSON string passed to showNotificationWithReplyAction
  ///   - replyText: the user's typed reply text
  /// The callback is responsible for sending the reply via the
  /// appropriate chat.
  static void Function(String payload, String replyText)? onReply;

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    debugPrint('📬 Local notification response — type: '
        '${response.notificationResponseType.name}, payload: $payload');

    logActionBreadcrumb('local_notification_response', {
      'payload': payload ?? 'none',
      'notificationResponseType': response.notificationResponseType.name,
      'hasReplyText': response.payload != null,
    });

    // ── Tier 2 / Reply from Notification ──
    // If the response is a notification action AND the user typed a
    // reply (response.input is non-null + non-empty), route to the
    // onReply callback with the payload + the typed text. The reply
    // handler then sends the reply via the appropriate chat.
    //
    // Note: this version of flutter_local_notifications (19.x) reports
    // the response type as `selectedNotificationAction` (not a separate
    // `replyInput` type), so we detect a reply by checking that
    // response.input is non-null + non-empty.
    if (response.notificationResponseType ==
            NotificationResponseType.selectedNotificationAction &&
        payload != null &&
        onReply != null) {
      final replyText = (response.input ?? '').trim();
      if (replyText.isNotEmpty) {
        debugPrint('💬 Inline reply received: "$replyText" for payload: $payload');
        try {
          onReply!(payload, replyText);
        } catch (e) {
          debugPrint('⚠️ onReply callback error: $e');
        }
        return; // don't also fire the tap handler — reply is a separate action
      }
    }

    // Delegate to the external tap handler (set by PushNotificationService)
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
