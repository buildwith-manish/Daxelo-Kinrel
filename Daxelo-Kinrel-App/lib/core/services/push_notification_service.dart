// lib/core/services/push_notification_service.dart
//
// DAXELO KINREL — Push Notification Service (P3-F3)
//
// Full-featured Firebase Cloud Messaging service that:
// - Requests notification permissions on Android/iOS
// - Registers FCM token and syncs to NestJS backend
// - Handles 3 notification types: birthday_reminder, new_family_member, family_event
// - Deep links notification taps to the relevant screen
// - Handles foreground, background, and terminated app states
// - Listens for FCM token refresh and syncs new token to backend
// - Uses crashlytics service for logging errors

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../services/crashlytics_service.dart';
import '../services/local_notification_service.dart';
import '../networking/dio_client.dart';

// ═══════════════════════════════════════════════════════════════════════
// Background Message Handler (Top-Level Function)
// ═══════════════════════════════════════════════════════════════════════

/// Top-level background message handler for FCM.
/// Must be a top-level function (not a class method or closure)
/// so it can be called from a separate isolate.
///
/// This handler is called when a message arrives while the app
/// is in the background (not terminated). The system automatically
/// displays the notification — we just log it for crashlytics.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase for the background isolate
  // (Required for any Firebase operations in background handlers)
  try {
    // Note: We can't use crashlytics_service.dart here because
    // it depends on Firebase being initialized in the main isolate.
    // Just log to debug for now.
    debugPrint('📬 [BG] FCM message received: ${message.messageId}');
    debugPrint('   Type: ${message.data['type']}');
    debugPrint('   Title: ${message.notification?.title}');
  } catch (e) {
    debugPrint('⚠️ [BG] FCM background handler error: $e');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Deep Link Routes
// ═══════════════════════════════════════════════════════════════════════

/// Maps notification type + data to a deep link route.
///
/// Notification types and their routes:
/// - birthday_reminder → /member/:memberId
/// - new_family_member → /family/:familyId
/// - family_event → /family/:familyId
String? resolveDeepLink(Map<String, dynamic> data) {
  final type = data['type'] as String?;

  switch (type) {
    case 'birthday_reminder':
      final memberId = data['memberId'] as String?;
      if (memberId != null && memberId.isNotEmpty) {
        return '/member/$memberId';
      }
      return null;

    case 'new_family_member':
      final familyId = data['familyId'] as String?;
      if (familyId != null && familyId.isNotEmpty) {
        return '/family/$familyId';
      }
      return null;

    case 'family_event':
      final familyId = data['familyId'] as String?;
      if (familyId != null && familyId.isNotEmpty) {
        return '/family/$familyId';
      }
      return null;

    default:
      // Unknown type — try to extract any usable deep link
      final deepLink = data['deepLink'] as String?;
      if (deepLink != null && deepLink.isNotEmpty) {
        return deepLink;
      }
      return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Push Notification Service
// ═══════════════════════════════════════════════════════════════════════

/// Full-featured FCM push notification service.
///
/// Handles the complete notification lifecycle:
/// 1. Permission request (Android 13+, iOS)
/// 2. FCM token acquisition and backend sync
/// 3. Foreground message → local notification display
/// 4. Background message → system notification + tap via onMessageOpenedApp
/// 5. Terminated state → getInitialMessage() processes tap
/// 6. Token refresh → automatic backend re-sync
/// 7. Deep linking → navigates to relevant screen on tap
class PushNotificationService {
  PushNotificationService(this._ref);

  final Ref _ref;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;

  String? _currentToken;
  bool _initialized = false;

  /// Whether the service has been successfully initialized.
  bool get isInitialized => _initialized;

  /// The current FCM token (null if not registered).
  String? get currentToken => _currentToken;

  /// Callback invoked when a notification tap requires deep linking.
  /// Set by the app to navigate to the appropriate route.
  ///
  /// Usage in main.dart:
  /// ```dart
  /// pushNotificationService.onDeepLink = (route) {
  ///   router.push(route);
  /// };
  /// ```
  void Function(String route)? onDeepLink;

  // ── Initialization ─────────────────────────────────────────────

  /// Initialize the push notification service.
  ///
  /// Should only be called when the user is authenticated.
  /// Steps:
  /// 1. Request notification permissions
  /// 2. Register background message handler
  /// 3. Set up foreground/background/terminated message handlers
  /// 4. Listen for token refresh (fire-and-forget token acquisition)
  ///
  /// ANR FIX: getToken() is now fire-and-forget instead of awaited.
  /// The native Firebase SDK's blockingGetToken() uses CountDownLatch.await()
  /// which blocks the Android platform thread. A Dart .timeout() CANNOT
  /// interrupt a native blocking call. By making token acquisition
  /// fire-and-forget and relying on onTokenRefresh for backend sync,
  /// we prevent the platform thread from being blocked during startup.
  Future<void> initialize() async {
    if (_initialized) return;

    // Only supported on Android and iOS
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint('⏭️ PushNotificationService skipped — not a mobile platform');
      return;
    }

    try {
      logActionBreadcrumb('push_notification_init_start');

      // 1. Request notification permissions
      final authorized = await _requestPermissions();
      if (!authorized) {
        debugPrint('⚠️ Notification permissions not granted');
        logActionBreadcrumb('push_notification_permission_denied');
        // Still continue — the user may grant permissions later
      }

      // 2. Background message handler is registered in main.dart before runApp()
      // to ensure it's available immediately for background isolates.

      // 3. Initialize local notification service for foreground messages
      final localService = _ref.read(localNotificationServiceProvider);
      await localService.initialize();

      // Set up local notification tap handler to route through our deep link logic
      LocalNotificationService.onNotificationTap = (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          debugPrint('📬 Local notification tap — payload: $payload');
          _handleDeepLink(payload);
        }
      };

      // 4. Handle notification taps for all 3 app states
      //    Set these up BEFORE acquiring the token so taps aren't missed.
      _setupForegroundHandler();
      _setupBackgroundTapHandler();
      _setupTerminatedTapHandlerFireAndForget();

      // 5. Listen for token refresh FIRST — this ensures we sync the token
      //    to the backend whenever it arrives (even from the fire-and-forget
      //    _acquireToken call below or from a native refresh).
      _setupTokenRefreshListener();

      // 6. Acquire FCM token FIRE-AND-FORGET — do NOT await.
      //    The native blockingGetToken() blocks the platform thread,
      //    and a Dart .timeout() cannot interrupt it. By not awaiting,
      //    we let the token arrive asynchronously and rely on
      //    onTokenRefresh + the fire-and-forget _syncTokenToBackend
      //    to sync it to the backend when ready.
      _acquireTokenFireAndForget();

      _initialized = true;
      debugPrint('✅ PushNotificationService initialized (token acquisition deferred)');
      logActionBreadcrumb('push_notification_init_complete', {
        'hasToken': _currentToken != null,
      });
    } catch (e, st) {
      logError(e, st, reason: 'PushNotificationService initialization failed');
      debugPrint('⚠️ PushNotificationService init failed: $e');
    }
  }

  // ── Permission Request ─────────────────────────────────────────

  /// Request notification permissions from the OS.
  ///
  /// On Android 13+ (API 33), this requests the POST_NOTIFICATIONS
  /// runtime permission. On older Android, permissions are granted
  /// at install time. On iOS, this shows the system permission dialog.
  ///
  /// Returns true if permissions are granted.
  Future<bool> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ Notification permission request timed out');
          return NotificationSettings(
            authorizationStatus: AuthorizationStatus.notDetermined,
            alert: AppleNotificationSetting.disabled,
            announcement: AppleNotificationSetting.disabled,
            badge: AppleNotificationSetting.disabled,
            carPlay: AppleNotificationSetting.disabled,
            lockScreen: AppleNotificationSetting.disabled,
            notificationCenter: AppleNotificationSetting.disabled,
            showPreviews: AppleShowPreviewSetting.never,
            sound: AppleNotificationSetting.disabled,
            timeSensitive: AppleNotificationSetting.disabled,
            criticalAlert: AppleNotificationSetting.disabled,
            providesAppNotificationSettings: AppleNotificationSetting.disabled,
          );
        },
      );

      debugPrint('📬 Notification permission status: ${settings.authorizationStatus}');

      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e, st) {
      logError(e, st, reason: 'Failed to request notification permissions');
      return false;
    }
  }

  // ── FCM Token Management ───────────────────────────────────────

  /// Acquire FCM token FIRE-AND-FORGET — does NOT block the caller.
  ///
  /// ANR FIX: _messaging.getToken() calls the native Android SDK's
  /// blockingGetToken() which uses CountDownLatch.await(). This blocks
  /// the platform thread and cannot be interrupted by Dart .timeout().
  /// By making this fire-and-forget, we prevent ANR during startup.
  ///
  /// The token will be synced to the backend via onTokenRefresh listener
  /// or directly in this method when it resolves.
  void _acquireTokenFireAndForget() {
    // Check connectivity first (advisory only)
    Connectivity().checkConnectivity().then((connectivityResult) {
      final hasConnection = connectivityResult.any(
        (c) => c != ConnectivityResult.none,
      );
      if (!hasConnection) {
        debugPrint('⚠️ No connectivity — skipping FCM token acquisition');
        return;
      }

      // Fire-and-forget: don't await getToken()
      _messaging.getToken().then((token) {
        if (token != null && token.isNotEmpty) {
          _currentToken = token;
          debugPrint('📬 FCM token acquired (async): ${token.substring(0, 20)}...');
          // Sync to backend fire-and-forget
          _syncTokenToBackend(token).catchError((e) {
            debugPrint('⚠️ FCM token sync failed (async): $e');
          });
        } else {
          debugPrint('⚠️ FCM token is null or empty (async)');
        }
      }).catchError((e) {
        debugPrint('⚠️ FCM getToken failed (async): $e');
        logError(e, StackTrace.current, reason: 'FCM getToken failed (fire-and-forget)');
      });
    }).catchError((e) {
      debugPrint('⚠️ Connectivity check failed: $e');
    });
  }

  /// Acquire FCM token and sync it to the NestJS backend.
  /// Used by resyncToken() for manual re-sync (not during startup).
  Future<void> _acquireAndSyncToken() async {
    try {
      // Check connectivity before attempting
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResult.any(
        (c) => c != ConnectivityResult.none,
      );
      if (!hasConnection) {
        debugPrint('⚠️ No connectivity — skipping FCM token sync');
        return;
      }

      final token = await _messaging.getToken().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ FCM getToken timed out — will retry on token refresh');
          return null;
        },
      );
      if (token != null && token.isNotEmpty) {
        _currentToken = token;
        debugPrint('📬 FCM token acquired: ${token.substring(0, 20)}...');
        await _syncTokenToBackend(token);
      } else {
        debugPrint('⚠️ FCM token is null or empty');
      }
    } catch (e, st) {
      logError(e, st, reason: 'Failed to acquire FCM token');
    }
  }

  /// Sync the FCM token to the NestJS backend.
  ///
  /// POST /api/users/me/fcm-token
  /// Body: { "fcmToken": "..." }
  ///
  /// Uses the existing Dio client which automatically injects
  /// the Supabase JWT via the _AuthInterceptor.
  Future<void> _syncTokenToBackend(String token) async {
    try {
      final dio = _ref.read(dioProvider);
      await dio.post(
        '/api/users/me/fcm-token',
        data: {'fcmToken': token},
      );
      debugPrint('📬 FCM token synced to backend');
      logActionBreadcrumb('fcm_token_synced', {
        'tokenPrefix': token.substring(0, 10),
      });
    } on DioException catch (e, st) {
      // 401 means the auth token expired — don't log as error
      // since the auth state listener will re-sync when refreshed
      if (e.response?.statusCode == 401) {
        debugPrint('📬 FCM token sync skipped — auth token expired');
        return;
      }
      // 404 means the endpoint doesn't exist on this server version
      // Don't log as error — this is expected for older server versions
      if (e.response?.statusCode == 404) {
        debugPrint('📬 FCM token sync skipped — endpoint not available on this server');
        return;
      }
      logError(e, st, reason: 'Failed to sync FCM token to backend');
      debugPrint('⚠️ FCM token sync failed: ${e.message}');
    } catch (e, st) {
      logError(e, st, reason: 'Failed to sync FCM token to backend');
      debugPrint('⚠️ FCM token sync failed: $e');
    }
  }

  // ── Token Refresh Listener ─────────────────────────────────────

  /// Listen for FCM token refresh events and sync the new token
  /// to the backend. Token refresh can happen when:
  /// - The app is restored on a new device
  /// - The user uninstalls/reinstalls the app
  /// - Firebase invalidates the token for security reasons
  void _setupTokenRefreshListener() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (newToken) {
        debugPrint('📬 FCM token refreshed: ${newToken.substring(0, 20)}...');
        _currentToken = newToken;
        _syncTokenToBackend(newToken);
        logActionBreadcrumb('fcm_token_refreshed');
      },
      onError: (e) {
        logError(e, StackTrace.current, reason: 'FCM token refresh error');
      },
    );
  }

  // ── Foreground Handler ─────────────────────────────────────────

  /// Handle FCM messages received while the app is in the foreground.
  ///
  /// When the app is foregrounded, FCM does NOT automatically display
  /// a notification. We must manually show a local notification
  /// using flutter_local_notifications.
  void _setupForegroundHandler() {
    _onMessageSubscription?.cancel();
    _onMessageSubscription = FirebaseMessaging.onMessage.listen(
      (RemoteMessage message) {
        debugPrint('📬 [FG] FCM message received: ${message.messageId}');

        final notification = message.notification;
        final data = message.data;

        if (notification != null) {
          // Show local notification
          final localService = _ref.read(localNotificationServiceProvider);
          localService.showNotification(
            title: notification.title ?? 'KINREL',
            body: notification.body ?? '',
            payload: resolveDeepLink(data),
            notificationType: data['type'] as String?,
          );
        }

        logActionBreadcrumb('fcm_foreground_message', {
          'messageId': message.messageId ?? 'unknown',
          'type': data['type'] ?? 'unknown',
        });
      },
      onError: (e) {
        logError(e, StackTrace.current, reason: 'FCM onMessage error');
      },
    );
  }

  // ── Background Tap Handler ─────────────────────────────────────

  /// Handle notification taps when the app was in the background
  /// (not terminated). The system displays the notification automatically,
  /// and when the user taps it, the app comes to the foreground
  /// and this handler fires.
  void _setupBackgroundTapHandler() {
    _onMessageOpenedAppSubscription?.cancel();
    _onMessageOpenedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen(
      (RemoteMessage message) {
        debugPrint('📬 [BG→FG] Notification tapped: ${message.messageId}');
        final deepLink = resolveDeepLink(message.data);
        if (deepLink != null) {
          _handleDeepLink(deepLink);
        }

        logActionBreadcrumb('fcm_background_tap', {
          'messageId': message.messageId ?? 'unknown',
          'type': message.data['type'] ?? 'unknown',
          'deepLink': deepLink ?? 'none',
        });
      },
      onError: (e) {
        logError(e, StackTrace.current, reason: 'FCM onMessageOpenedApp error');
      },
    );
  }

  // ── Terminated Tap Handler ─────────────────────────────────────

  /// Handle notification taps when the app was terminated (not running).
  ///
  /// getInitialMessage() returns the message that launched the app,
  /// or null if the app was launched normally (e.g., by tapping the icon).
  Future<void> _setupTerminatedTapHandler() async {
    try {
      final initialMessage = await _messaging.getInitialMessage().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ getInitialMessage timed out — skipping terminated tap handling');
          return null;
        },
      );
      if (initialMessage != null) {
        debugPrint(
          '📬 [TERMINATED→FG] Notification tapped: ${initialMessage.messageId}',
        );
        final deepLink = resolveDeepLink(initialMessage.data);
        if (deepLink != null) {
          _handleDeepLink(deepLink);
        }

        logActionBreadcrumb('fcm_terminated_tap', {
          'messageId': initialMessage.messageId ?? 'unknown',
          'type': initialMessage.data['type'] ?? 'unknown',
          'deepLink': deepLink ?? 'none',
        });
      }
    } catch (e, st) {
      logError(e, st, reason: 'Failed to get initial FCM message');
    }
  }

  /// Fire-and-forget version of terminated tap handler.
  /// ANR FIX: getInitialMessage() can also block the platform thread
  /// on some devices. By making it fire-and-forget, we don't block
  /// the initialization sequence.
  void _setupTerminatedTapHandlerFireAndForget() {
    _messaging.getInitialMessage().then((initialMessage) {
      if (initialMessage != null) {
        debugPrint(
          '📬 [TERMINATED→FG] Notification tapped: ${initialMessage.messageId}',
        );
        final deepLink = resolveDeepLink(initialMessage.data);
        if (deepLink != null) {
          _handleDeepLink(deepLink);
        }

        logActionBreadcrumb('fcm_terminated_tap', {
          'messageId': initialMessage.messageId ?? 'unknown',
          'type': initialMessage.data['type'] ?? 'unknown',
          'deepLink': deepLink ?? 'none',
        });
      }
    }).catchError((e) {
      debugPrint('⚠️ getInitialMessage failed (async): $e');
    });
  }

  // ── Deep Link Navigation ───────────────────────────────────────

  /// Handle deep link navigation from a notification tap.
  ///
  /// Delegates to the [onDeepLink] callback which is set by the app
  /// to navigate using GoRouter.
  void _handleDeepLink(String route) {
    debugPrint('🔗 Deep link: $route');
    logNavigationBreadcrumb(route);
    logActionBreadcrumb('notification_deep_link', {'route': route});

    if (onDeepLink != null) {
      onDeepLink!(route);
    } else {
      debugPrint('⚠️ No onDeepLink handler set — cannot navigate to $route');
    }
  }

  // ── Public API ─────────────────────────────────────────────────

  /// Manually re-sync the FCM token to the backend.
  ///
  /// Useful after network connectivity is restored or after
  /// the user re-authenticates.
  Future<void> resyncToken() async {
    if (_currentToken != null) {
      await _syncTokenToBackend(_currentToken!);
    } else {
      await _acquireAndSyncToken();
    }
  }

  /// Delete the current FCM token.
  ///
  /// Call this when the user signs out to prevent notifications
  /// from being delivered to a device where the user is no longer
  /// authenticated.
  ///
  /// ANR FIX: Made fire-and-forget to prevent blockingGetToken-style
  /// ANR on the native side. deleteToken() also uses CountDownLatch
  /// internally and can block the platform thread.
  Future<void> deleteToken() async {
    _currentToken = null;
    // Fire-and-forget — don't await the native call
    _messaging.deleteToken().then((_) {
      debugPrint('📬 FCM token deleted');
      logActionBreadcrumb('fcm_token_deleted');
    }).catchError((e) {
      debugPrint('⚠️ FCM deleteToken failed (async): $e');
    });
  }

  // ── Cleanup ────────────────────────────────────────────────────

  /// Dispose all subscriptions and clean up resources.
  ///
  /// Call this when the user signs out or the service is no longer needed.
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _onMessageSubscription?.cancel();
    _onMessageSubscription = null;
    _onMessageOpenedAppSubscription?.cancel();
    _onMessageOpenedAppSubscription = null;
    _initialized = false;
    debugPrint('📬 PushNotificationService disposed');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Riverpod Provider
// ═══════════════════════════════════════════════════════════════════════

/// Riverpod provider for the PushNotificationService singleton.
///
/// Lazily created — only instantiated when first read.
/// Automatically disposes when the provider is no longer needed.
final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  final service = PushNotificationService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
