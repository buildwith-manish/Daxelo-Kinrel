// lib/core/bootstrap/service_orchestrator.dart
//
// DAXELO KINREL — Service Orchestrator
//
// Manages deferred service initialization, auth state listeners,
// and connectivity-triggered sync flushing. Called from the
// KinrelApp widget's initState after the first frame renders.
//
// ANR FIX: Every heavy async operation is followed by
// `await Future.delayed(Duration.zero)` to yield to the Android
// message queue. Without these yields, Dart native code blocks
// the main thread from processing touch/lifecycle events → ANR.

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/auth_config.dart';
import '../database/app_database_service.dart';
import '../database/sync/background_sync_manager.dart';
import '../database/sync/connectivity_service.dart';
import '../family/family_provider.dart';
import '../network/socket_service.dart';
import '../services/analytics_service.dart';
import '../services/crashlytics_service.dart';
import '../services/deep_link_service.dart';
import '../services/push_notification_service.dart';
import '../services/rating_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../routing/app_router.dart';
import '../storage/local_cache.dart';
import '../utils/a11y_checker.dart';
import '../utils/memory_monitor.dart';
import '../../features/profile/data/profile_provider.dart';

/// Handle sign-out operations (fire-and-forget).
/// Called from the auth state listener — MUST NOT throw.
Future<void> _handleSignOut(dynamic ref) async {
  try {
    final pushService = ref.read(pushNotificationServiceProvider);
    await pushService.deleteToken().timeout(const Duration(seconds: 5));
  } catch (_) {}
}

class ServiceOrchestrator {
  /// Start deferred (non-critical) services after the first frame.
  /// These are NOT required for the app to render — they initialize
  /// in the background while the user sees the loading/splash screen.
  static void startDeferredServices(dynamic ref) {
    // Wrap the entire deferred init in an async block with top-level error handling
    unawaited(
      _initDeferredServicesAsync(ref),
    );
  }

  /// Yield to the Android message queue between heavy operations.
  /// Uses a 16ms delay (one frame) to let the native main thread process
  /// pending touch/lifecycle events. Duration.zero only yields to the Dart
  /// microtask queue, which isn't sufficient to prevent ANR on slow devices.
  static Future<void> _yield() =>
      Future.delayed(const Duration(milliseconds: 16));

  /// Async implementation of deferred service initialization.
  static Future<void> _initDeferredServicesAsync(dynamic ref) async {
    try {
      // 1. Local cache service
      try {
        final cacheService = LocalCacheService();
        await cacheService.init();
        await _yield(); // ANR fix: yield after init
      } catch (e) {
        debugPrint('⚠️ LocalCacheService init failed: $e');
      }

      // ── Capture auth state for crash context ───────────────────────
      try {
        final client = ref.read(supabaseProvider);
        if (client != null) {
          final user = client.auth.currentUser;
          if (user != null) {
            setUserIdentifier(user.id);
            captureRiverpodState('auth', {
              'userId': user.id,
              'email': user.email ?? 'unknown',
            });
          } else if (kAuthDisabled) {
            setUserIdentifier(MockUser.id);
            captureRiverpodState('auth', {
              'userId': MockUser.id,
              'email': MockUser.email,
              'mode': 'auth_disabled',
            });
          }

          _setupAuthStateListener(ref, client);
        }
      } catch (_) {}

      await _yield(); // ANR fix: yield after auth setup

      // 2. Start the SyncEngine + BackgroundSyncManager (3s delay)
      unawaited(
        Future.delayed(const Duration(seconds: 3), () async {
          try {
            if (AppDatabaseService.isInitialized) {
              final client = ref.read(supabaseProvider);
              final hasSession = client?.auth.currentSession != null;
              if (hasSession) {
                final bgSyncManager = ref.read(backgroundSyncManagerProvider);
                bgSyncManager.init();
                bgSyncManager.start();
                debugPrint(
                  '🔄 SyncEngine + BackgroundSyncManager started (delayed)',
                );
              } else {
                debugPrint('⏭️ SyncEngine skipped — no auth session');
              }
            }
          } catch (e) {
            debugPrint('⚠️ SyncEngine start failed: $e');
          }

          // 3. Start the Socket.IO service if authenticated
          try {
            final client = ref.read(supabaseProvider);
            if (client != null && client.auth.currentSession != null) {
              final socketService = ref.read(socketServiceProvider);
              socketService.connect();
              debugPrint('🔌 SocketService started (delayed)');
            }
          } catch (e) {
            debugPrint('⚠️ SocketService start failed: $e');
          }
        }),
      );

      // 4. Initialize Push Notifications if authenticated
      try {
        final client = ref.read(supabaseProvider);
        if (client != null && client.auth.currentSession != null) {
          final pushService = ref.read(pushNotificationServiceProvider);
          pushService.onDeepLink = (route) {
            try {
              final router = ref.read(routerProvider);
              router.push(route);
            } catch (e) {
              debugPrint('⚠️ Push notification deep link failed: $e');
            }
          };
          await pushService.initialize()
              .timeout(const Duration(seconds: 5), onTimeout: () {
            debugPrint('⚠️ PushNotificationService init timed out');
          });
          debugPrint('📬 PushNotificationService initialized');
        } else {
          debugPrint(
            '⏭️ PushNotificationService skipped — no auth session',
          );
        }
      } catch (e) {
        debugPrint('⚠️ PushNotificationService init failed: $e');
      }

      await _yield(); // ANR fix: yield after push init

      // 5. Preload bottom nav tabs (3s delay)
      unawaited(
        Future.delayed(const Duration(seconds: 3), () async {
          try {
            // Preload tabs — works with or without auth session
            ref.read(familyListProvider.future).catchError((_) => <Family>[]);
            ref.read(profileProvider.notifier).loadProfile().catchError((_) {});
            ref.read(profileProvider.notifier).loadStats().catchError((_) {});
            debugPrint('🚀 Bottom nav tabs preloaded');
          } catch (e) {
            debugPrint('⚠️ Bottom nav preload failed: $e');
          }
        }),
      );

      // ── Initialize Analytics Service ──────────────────────────────
      try {
        await AnalyticsService.instance.init()
            .timeout(const Duration(seconds: 3), onTimeout: () {
          debugPrint('⚠️ Analytics init timed out');
        });
      } catch (e) {
        debugPrint('⚠️ Analytics init failed: $e');
      }

      await _yield(); // ANR fix: yield after analytics

      // ── Initialize Remote Config Service ──────────────────────────
      try {
        await RemoteConfigService.instance.init()
            .timeout(const Duration(seconds: 3), onTimeout: () {
          debugPrint('⚠️ Remote Config init timed out');
        });
        debugPrint('✅ Remote Config initialized');
      } catch (e) {
        debugPrint('⚠️ Remote Config init failed, using defaults: $e');
      }

      await _yield(); // ANR fix: yield after remote config

      // ── Record app open for retention tracking ────────────────────
      try {
        if (AppDatabaseService.isInitialized) {
          final db = AppDatabaseService.instance;
          final opensStr = await db.getSetting('app_opens');
          final opens = int.tryParse(opensStr ?? '0') ?? 0;
          await db.setSetting('app_opens', '${opens + 1}');
          await db.setSetting('last_open', DateTime.now().toIso8601String());
        }
      } catch (_) {}

      await _yield(); // ANR fix: yield after DB write

      // ── Initialize Rating Service ─────────────────────────────────
      RatingService.instance.init();

      // ── Accessibility audit (debug only) ──────────────────────────
      A11yChecker.runAudit();

      // ── Memory monitor (debug only) ───────────────────────────────
      MemoryMonitor.start();

      // ── Capture provider state for crash context ──────────────────
      try {
        ref.listen(familyListProvider, (_, next) {
          captureRiverpodState('familyList', {
            'count': next.value?.length ?? 0,
            'isLoading': next.isLoading,
            'hasError': next.hasError,
          });
        });
      } catch (_) {}

      // ── Initialize Deep Link Service ──────────────────────────────
      try {
        final deepLinkService = ref.read(deepLinkServiceProvider);
        // ANR FIX: Timeout on deep link init to prevent blocking the main isolate
        await deepLinkService.init(
          onDeepLink: (location) {
            try {
              final router = ref.read(routerProvider);
              navigateToDeepLink(router, location);
              debugPrint('🔗 Deep link navigated to: $location');
            } catch (e) {
              debugPrint('⚠️ Deep link navigation failed: $e');
            }
          },
        ).timeout(const Duration(seconds: 3), onTimeout: () {
          debugPrint('⚠️ Deep link service init timed out — deep links may not work until next app start');
        });
      } catch (e) {
        debugPrint('⚠️ Deep link service init failed: $e');
      }

      await _yield(); // ANR fix: yield after deep link init

      // ── Wire connectivity listener to background sync (CARRY-07) ──
      _setupConnectivityListener(ref);
    } catch (e, st) {
      debugPrint('🔴 _initDeferredServices top-level error: $e');
      debugPrint('   Stack: $st');
    }
  }

  /// Set up auth state change listener for crash context and sign-out handling.
  static void _setupAuthStateListener(dynamic ref, SupabaseClient client) {
    AuthChangeEvent? lastAuthEvent;
    String? lastAuthUserId;

    client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      try {
        final userId = session?.user.id;
        if (event == AuthChangeEvent.signedIn &&
            lastAuthEvent == AuthChangeEvent.signedIn &&
            lastAuthUserId == userId) {
          debugPrint('⏭️ Auth listener: skipping duplicate signedIn event');
          return;
        }
        lastAuthEvent = event;
        lastAuthUserId = userId;

        if (event == AuthChangeEvent.signedIn && session != null) {
          try {
            setUserIdentifier(session.user.id);
          } catch (_) {}
          try {
            captureRiverpodState('auth', {
              'userId': session.user.id,
              'email': session.user.email ?? 'unknown',
              'event': event.name,
            });
          } catch (_) {}
          debugPrint('🔐 Auth listener: signedIn — navigation handled by router');
        } else if (event == AuthChangeEvent.signedOut) {
          try {
            captureRiverpodState('auth', {'status': 'signed_out'});
          } catch (_) {}
          if (!kAuthDisabled) {
            unawaited(_handleSignOut(ref));
          }
          debugPrint('🔐 Auth listener: signedOut');
        }
      } catch (e) {
        debugPrint('⚠️ Auth state listener error: $e');
      }
    });
  }

  /// Listen to connectivity changes and flush pending operations
  /// when connectivity is restored after being offline (CARRY-07).
  static void _setupConnectivityListener(dynamic ref) {
    try {
      ref.listen<AsyncValue<bool>>(isOnlineProvider, (prev, next) {
        next.whenData((isOnline) {
          final wasOffline = prev?.value == false;

          if (wasOffline && isOnline) {
            debugPrint(
              '🔄 Connectivity restored — flushing pending operations',
            );
            try {
              final bgSyncManager = ref.read(backgroundSyncManagerProvider);
              unawaited(
                bgSyncManager.onConnectivityRestored().catchError((e) {
                  debugPrint('⚠️ Connectivity restored sync failed: $e');
                }),
              );
            } catch (e) {
              debugPrint('⚠️ Failed to trigger connectivity sync: $e');
            }
          }
        });
      });
      debugPrint('🔧 Connectivity listener wired to BackgroundSyncManager');
    } catch (e) {
      debugPrint('⚠️ Failed to set up connectivity listener: $e');
    }
  }
}
