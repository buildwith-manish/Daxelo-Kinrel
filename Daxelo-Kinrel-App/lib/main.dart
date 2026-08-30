import 'dart:async';
// dart:io Platform is only used for desktop window setup (Windows/Linux/macOS).
// On web, dart:io is unavailable — use conditional import to avoid pulling
// in native-only code on the web build.
import 'dart:io'
    if (dart.library.html) 'core/utils/io_platform_stub.dart'
    show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// Hive removed — using Drift (AppDatabase) via IsarDatabase wrapper
import 'core/database/isar_database.dart';
import 'features/family_map/config/map_quality_tier.dart';
// Conditional import: window_manager doesn't support web, so we use a
// no-op stub on web platforms. This prevents the app from crashing on
// startup when the window_manager package's native code is loaded.
import 'package:window_manager/window_manager.dart'
    if (dart.library.html) 'core/utils/window_manager_stub.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/config/app_environment.dart';
import 'core/kinship/kinship_edge_style.dart' show kinshipEdgeStyleRegistryCheck;
import 'core/routing/app_router.dart';
import 'core/services/crashlytics_service.dart';
import 'core/services/multi_account_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/push_notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/services/supabase_service.dart';
import 'core/storage/local_cache.dart';
import 'core/storage/secure_storage.dart';
import 'core/theme/theme_provider.dart';
import 'core/database/sync/background_sync_manager.dart';
import 'core/network/socket_service.dart';
import 'core/network/supabase_realtime_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'core/utils/device_tier.dart';
import 'core/utils/a11y_checker.dart';
import 'core/utils/memory_monitor.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'core/widgets/offline_banner.dart';
import 'core/widgets/global_error_widget.dart';
import 'core/kinship/kinship_service.dart';
import 'features/family/presentation/providers/family_graph_provider.dart';
import 'features/profile/data/profile_provider.dart';

import 'core/services/rating_service.dart';
import 'core/services/analytics_service.dart';
import 'core/services/remote_config_service.dart';
import 'core/app_startup.dart';
import 'core/family/family_provider.dart';
import 'core/viewer/viewer_provider.dart' show invalidateViewerCache;
import 'features/games/shared/widgets/game_invite_listener.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Generated localization imports (flutter gen-l10n)
import 'package:kinrel/l10n/app_localizations.dart';

/// Global reference to the ProviderContainer so background initialization
/// can update Riverpod providers (e.g., supabaseReadyStateProvider).
ProviderContainer? _globalContainer;

void main() async {
  // ── CRITICAL: Ensure Flutter binding BEFORE any async work ────────
  WidgetsFlutterBinding.ensureInitialized();

  // v52.7: Anti-tree-shake — force dart2js to retain all kinship edge
  // colors and the style resolver. Without this, dart2js strips the
  // color constants from the release build, causing edges to render
  // with no color (invisible) on Flutter Web.
  kinshipEdgeStyleRegistryCheck();

  // ── 1. Initialize environment ────────────────────────────────────
  try {
    AppEnvironmentConfig.initialize();
  } catch (e) {
    debugPrint('⚠️ AppEnvironmentConfig.initialize failed: $e');
  }

  // ── P6: Global error widget — branded, themed, prevents red screen of death ──
  ErrorWidget.builder = (FlutterErrorDetails details) {
    try {
      if (isCrashlyticsAvailable) {
        FirebaseCrashlytics.instance.recordFlutterError(details);
      }
    } catch (_) {}
    return GlobalErrorWidget(
      severity: GlobalErrorSeverity.crash,
      errorDetails: details,
    );
  };

  // ── P6: Flutter framework error handler ─────────────────────────────
  // Catches errors that don't reach the widget tree (e.g., image decoding,
  // layout overflow in release mode). Reports to Crashlytics and logs.
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    // Forward to Crashlytics
    try {
      if (isCrashlyticsAvailable) {
        FirebaseCrashlytics.instance.recordFlutterError(details);
      }
    } catch (_) {}
    // Call original handler (shows red bar in debug, etc.)
    originalOnError?.call(details);
    // In release mode, also log to console
    if (kReleaseMode) {
      debugPrint('🔴 FlutterError: ${details.exceptionAsString()}');
    }
  };

  // ── P6: Platform-level error handler ────────────────────────────────
  // Catches errors from async callbacks, isolates, and platform channels
  // that are outside the Flutter framework's error zone.
  PlatformDispatcher.instance.onError = (error, stack) {
    try {
      if (isCrashlyticsAvailable) {
        FirebaseCrashlytics.instance.recordError(error, stack);
      }
    } catch (_) {}
    debugPrint('🔴 PlatformDispatcher error: $error');
    return true; // Handled — prevents default error printing
  };

  // ═══════════════════════════════════════════════════════════════════
  // CRITICAL FIX: Call runApp() FIRST, then initialize services.
  //
  // Previously, ALL initialization (Drift, Firebase, Supabase, Sentry)
  // happened BEFORE runApp(). If ANY of these hung or timed out, the
  // user saw a BLACK SCREEN because the Flutter engine never rendered
  // the first frame.
  //
  // Now: runApp() is called immediately. The KinrelApp shows a loading
  // state while services initialize in the background via
  // _appInitializationProvider. This guarantees the user always sees
  // SOMETHING — even if initialization fails completely.
  // ═══════════════════════════════════════════════════════════════════

  // ── Quick, non-blocking setup ─────────────────────────────────────

  // ── Pre-warm Drift database for <100ms cached data loading ────────
  // This ensures Drift is ready before the first provider reads from it.
  // Takes typically < 20ms. Must happen BEFORE runApp().
  await AppStartupService.preWarmDrift();

  // ── Set system UI (fast, non-blocking) ─────────────────────────────
  try {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF121212),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (_) {}

  // ── Detect Device Tier (fast, non-blocking) ────────────────────────
  try {
    final binding = WidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.views.first;
    final physicalSize = view.physicalSize;
    final pixelRatio = view.devicePixelRatio;
    final screenWidth = physicalSize.width / pixelRatio;
    // Part 1 fix — initialize() now returns false when screenWidth or
    // pixelRatio is 0 (which happens on web before the first frame is
    // laid out, when view.physicalSize is Size.zero). In that case we
    // schedule a post-frame callback to call initializeFromView() once
    // the view has a real size. This fixes the timing race where web
    // devices were wrongly classified as 'low' tier (screenWidth=0 < 360),
    // which hid the 3D Buildings toggle and forced 2D mode.
    final detected =
        DeviceTierCache.instance.initialize(screenWidth, pixelRatio);
    if (!detected) {
      debugPrint('🔧 DeviceTier: detection deferred — scheduling post-frame retry');
      // Schedule the retry on the next frame. Using addPostFrameCallback
      // ensures the view has been laid out by the time we read its size.
      // If the view STILL has no size (extremely rare — e.g., the platform
      // view hasn't attached yet), initializeFromView() will log and
      // return without committing; we'd need another retry, but in
      // practice one post-frame retry is always sufficient.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        DeviceTierCache.instance.initializeFromView();
      });
    }
    // Phase B v1.0: initialize MapQualityTier from DeviceTier.
    // Must run AFTER DeviceTierCache.initialize() since it reads the tier.
    // Safe to call before app runs — controller is a singleton.
    // Part 1 fix — MapQualityTierController is now a ChangeNotifier that
    // listens to DeviceTierCache. If DeviceTierCache is deferred (web),
    // the controller will pick up the resolved tier via the listener
    // and notify its own listeners (e.g., FamilyMapScreen) to rebuild.
    MapQualityTierController.instance.initialize();
  } catch (e) {
    debugPrint('⚠️ Device tier detection failed: $e');
  }

  // ═══════════════════════════════════════════════════════════════════
  // RUN APP IMMEDIATELY — don't wait for heavy initialization!
  // The app will show a loading screen while services initialize.
  // ═══════════════════════════════════════════════════════════════════

  // Desktop window setup (only on desktop platforms)
  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(900, 600),
      center: true,
      title: 'Daxelo Kinrel',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // ── Call runApp FIRST — services init in background ────────────────
  // ── Configure CachedNetworkImage global settings ────────────────────
  // 7-day disk cache, 100MB max size, scaled-down decoded images to save RAM
  // WEB: DefaultCacheManager uses path_provider which doesn't work on web.
  // Skip on web — images will load from network without disk caching.
  if (!kIsWeb) {
    try {
      DefaultCacheManager().emptyCache().catchError((_) {}); // no-op; just warming
    } catch (_) {}
  }
  // Image cache is configured via the maxDuration parameter in
  // CachedNetworkImage's cacheManager — the default is 30 days.
  // We create a custom cache manager below for 7-day / 100MB limits.

  runApp(ProviderScope(child: KinrelApp()));

  // ── Background initialization ─────────────────────────────────────
  // Awaited so the app doesn't accept user interaction before Supabase,
  // Drift, and socket service are ready. The splash/loading screen is
  // shown during this time. If init fails, the app shows an error state.
  await _initializeServices();
}

/// Background service initialization. Runs after runApp() so the user
/// always sees the app UI. Each step is individually wrapped in
/// try-catch with timeouts so one failure doesn't block the rest.
Future<void> _initializeServices() async {
  // ── 1. Load environment variables (fast, needed by Supabase) ───────
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ .env file loaded successfully');
  } catch (e) {
    try {
      dotenv.loadFromString(envString: '# fallback — using hardcoded defaults');
    } catch (_) {}
    debugPrint('⚠️ .env file not found, using hardcoded defaults');
  }

  // ── 2. Initialize Firebase + Supabase IN PARALLEL ─────────────────
  // PERF: Previously these ran sequentially (Firebase → Supabase), adding
  // 5-8s of latency on cold starts. Running them in parallel with
  // Future.wait cuts that to the max of the two (~3-4s).
  bool supabaseReady = false;
  final results = await Future.wait([
    // Firebase init
    () async {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(const Duration(seconds: 5));
        debugPrint('✅ Firebase initialized successfully');
      } catch (e) {
        debugPrint('⚠️ Firebase initialization failed or timed out: $e');
      }
    }(),
    // Supabase init
    () async {
      try {
        final ready = await initSupabase().timeout(const Duration(seconds: 8));
        debugPrint('🔧 Supabase initialized: $ready');
        return ready;
      } catch (e) {
        debugPrint('⚠️ Supabase init failed or timed out: $e');
        return false;
      }
    }().then((r) => supabaseReady = r),
    // Drift database init (lazy — only needed for offline cache)
    // PERF: Initialize in parallel but don't block Supabase/Firebase on it.
    () async {
      try {
        await IsarDatabase.initialize().timeout(const Duration(seconds: 5));
        debugPrint('✅ Drift database initialized');
      } catch (e) {
        debugPrint('⚠️ Drift database initialization failed or timed out: $e');
      }
    }(),
  ]);
  // Suppress unused variable warning
  // ignore: unused_local_variable
  final _ = results;

  // ── 3. Initialize Crashlytics + FCM (after Firebase) ──────────────
  try {
    await initCrashlytics();
  } catch (e) {
    debugPrint('⚠️ Crashlytics initialization failed: $e');
  }
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('⚠️ FCM background handler registration failed: $e');
  }

  // ── 7b. Notify Riverpod that Supabase is ready ──────────────────
  // The supabaseProvider is now reactive (watches supabaseReadyStateProvider).
  // We must update it so all providers that depend on supabaseProvider
  // get the correct value instead of null.
  // Retry a few times because the widget tree might not be built yet.
  for (int attempt = 0; attempt < 5; attempt++) {
    try {
      final container = _globalContainer;
      if (container != null) {
        notifySupabaseReady(container);
        debugPrint('🔧 Notified Riverpod: Supabase ready = $supabaseReady (attempt ${attempt + 1})');
        break;
      }
      // Widget tree not built yet — wait a bit
      if (attempt < 4) {
        debugPrint('🔧 Waiting for ProviderContainer... (attempt ${attempt + 1})');
        await Future.delayed(const Duration(milliseconds: 50));
      } else {
        debugPrint('⚠️ No global container available after 5 attempts — Supabase providers may not update');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to notify Supabase ready state: $e');
      break;
    }
  }

  // ── Log environment info for crash context ────────────────────────
  try {
    logNavigationBreadcrumb('/splash');
    logActionBreadcrumb('app_start', {
      'env': AppEnvironmentConfig.current.label,
      'device_tier': DeviceTierCache.instance.tier.name,
    });
  } catch (_) {}

  // ── Debug: log resolved AppConfig values ───────────────────────────
  debugPrint('🔧 AppConfig SUPABASE_URL: ${AppConfig.supabaseUrl}');
  debugPrint(
    '🔧 AppConfig SUPABASE_ANON_KEY: ${AppConfig.supabaseAnonKey.isNotEmpty ? "SET (length: ${AppConfig.supabaseAnonKey.length})" : "EMPTY"}',
  );
  debugPrint(
    '🔧 AppConfig isSupabaseConfigured: ${AppConfig.isSupabaseConfigured}',
  );

  // ── Notify the app that initialization is complete ─────────────────
  // This is handled by the _appInitCompleteProvider in the widget tree.
  // The splash screen checks this and navigates accordingly.
  _appInitComplete = true;
  _initCompleter?.complete();
}

/// Global flag + completer to track initialization state
bool _appInitComplete = false;
Completer<void>? _initCompleter;

/// Provider that completes when background initialization is done
final appInitCompleteProvider = FutureProvider<void>((ref) async {
  if (_appInitComplete) return;
  _initCompleter ??= Completer<void>();
  await _initCompleter!.future;
});

/// Handle sign-out operations (fire-and-forget).
/// Called from the auth state listener — MUST NOT throw.
Future<void> _handleSignOut(WidgetRef ref) async {
  // Clear the pending 2FA flag so the next user on this device
  // isn't incorrectly routed to /2fa-verify.
  try {
    ref.read(pending2FAProvider.notifier).state = false;
  } catch (_) {}
  try {
    final pushService = ref.read(pushNotificationServiceProvider);
    await pushService.deleteToken().timeout(const Duration(seconds: 5));
  } catch (_) {}
  // v5.4: Clear the viewer cache so the next user gets a fresh graph
  // render from THEIR perspective, not the previous user's.
  try {
    invalidateViewerCache();
    debugPrint('🔐 _handleSignOut: viewer cache cleared');
  } catch (_) {}
  // v5.135: Clear the ENTIRE graph cache on sign-out. The previous code
  // only cleared the viewer cache but left FamilyGraphNotifier's in-memory
  // _cache intact. When a different account signs in on the same device
  // (or the same account re-signs in after an RLS policy change), the
  // stale cached graph data from the previous session could be served,
  // causing a mismatch between the stats panel (which re-fetches) and
  // the graph engine view (which may use the stale cache).
  try {
    FamilyGraphNotifier.clearAllCache();
    debugPrint('🔐 _handleSignOut: graph cache cleared');
  } catch (e) {
    debugPrint('🔐 _handleSignOut: graph cache clear failed: $e');
  }
}

class KinrelApp extends ConsumerStatefulWidget {
  KinrelApp({super.key});

  @override
  ConsumerState<KinrelApp> createState() => _KinrelAppState();
}

class _KinrelAppState extends ConsumerState<KinrelApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Save the ProviderContainer for background initialization
    // to update Riverpod providers (e.g., supabaseReadyStateProvider).
    // Use addPostFrameCallback to ensure the context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          _globalContainer = ProviderScope.containerOf(context);
          debugPrint('🔧 Global ProviderContainer captured');
        } catch (e) {
          debugPrint('⚠️ Could not capture ProviderContainer: $e');
        }
      }
    });
    // Register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // Load saved language preference — deferred to avoid synchronous
    // platform channel initialization (SecureStorage) during the first
    // frame build, which can block the main thread on cold starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedLocale();
    });

    // ── DEFERRED INIT: non-critical services after first frame ───
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _initDeferredServices();
      } catch (e) {
        debugPrint('🔴 _initDeferredServices failed: $e');
      }
    });
  }

  /// Initialize services that are NOT required for the first frame.
  Future<void> _initDeferredServices() async {
    try {
    // 1. Local cache service
    try {
      final cacheService = LocalCacheService();
      await cacheService.init();
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
        }

        AuthChangeEvent? _lastAuthEvent;
        String? _lastAuthUserId;

        client.auth.onAuthStateChange.listen((data) async {
          final event = data.event;
          final session = data.session;

          try {
            final userId = session?.user.id;
            if (event == AuthChangeEvent.signedIn &&
                _lastAuthEvent == AuthChangeEvent.signedIn &&
                _lastAuthUserId == userId) {
              debugPrint('⏭️ Auth listener: skipping duplicate signedIn event');
              return;
            }
            _lastAuthEvent = event;
            _lastAuthUserId = userId;

            if (event == AuthChangeEvent.signedIn && session != null) {
              try {
                setUserIdentifier(session.user.id);
              } catch (_) {}
              // Save session for multi-account support
              try {
                await MultiAccountService.instance.saveCurrentSession();
              } catch (_) {}
              try {
                captureRiverpodState('auth', {
                  'userId': session.user.id,
                  'email': session.user.email ?? 'unknown',
                  'event': event.name,
                });
              } catch (_) {}

              // BUG FIX (families-not-loading-after-login): Invalidate any
              // family-related providers that may have been preloaded (and
              // cached as empty) before the user signed in. The 3-second
              // preload in this file (search for "Preload bottom nav tabs")
              // calls `ref.read(familyListProvider.future)` which evaluates
              // the provider with no session and caches `[]`. Without this
              // invalidation, the home screen keeps showing "No Families Yet"
              // until the user manually triggers create-family.
              //
              // `familyListProvider` now also watches `currentUserProvider`
              // (see lib/core/family/family_provider.dart), so it would
              // rebuild on its own — but invalidating here is belt-and-
              // suspenders: it guarantees a fresh fetch on every sign-in,
              // including token-refresh/`SIGNED_IN` events emitted by
              // Supabase when recovering a persisted session on app start.
              try {
                ref.invalidate(familyListProvider);
                ref.invalidate(archivedFamiliesProvider);
                // v5.78 (AUTH FIX): Invalidate authStateProvider +
                // currentUserProvider on signedIn. This guarantees these
                // providers are fresh even if the initial init-race left
                // them stuck on Stream.empty() / null. Without this, the
                // graph screen shows "Auth User ID: NULL" because the
                // providers were cached before Supabase was ready.
                ref.invalidate(authStateProvider);
                ref.invalidate(currentUserProvider);
                // v5.4: Invalidate viewer + graph providers so the graph
                // re-renders from the NEW user's perspective on account switch.
                // Without this, the graph keeps showing the previous user's
                // "You" node and perspective labels.
                invalidateViewerCache();
                debugPrint('🔐 Auth listener: signedIn — familyListProvider + viewerCache + authState invalidated');
              } catch (e) {
                debugPrint('⚠️ Auth listener: failed to invalidate family providers: $e');
              }

              debugPrint('🔐 Auth listener: signedIn — navigation handled by router');
            } else if (event == AuthChangeEvent.signedOut) {
              try {
                captureRiverpodState('auth', {'status': 'signed_out'});
              } catch (_) {}
              unawaited(_handleSignOut(ref));
              debugPrint('🔐 Auth listener: signedOut');
            }
          } catch (e) {
            debugPrint('⚠️ Auth state listener error: $e');
          }
        });
      }
    } catch (_) {}

    // 2. Start the SyncEngine if Isar is initialized AND user has a session
    // PERF: Reduced from 3s to 2s — starts sync 1 second earlier
    Future.delayed(const Duration(seconds: 2), () {
      if (IsarDatabase.isInitialized) {
        try {
          final client = ref.read(supabaseProvider);
          final hasSession = client?.auth.currentSession != null;
          if (hasSession) {
            final bgSyncManager = ref.read(backgroundSyncManagerProvider);
            bgSyncManager.init();
            bgSyncManager.start();
            debugPrint('🔄 SyncEngine + BackgroundSyncManager started (delayed)');
          } else {
            debugPrint('⏭️ SyncEngine skipped — no auth session');
          }
        } catch (e) {
          debugPrint('⚠️ SyncEngine start failed: $e');
        }
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

      // 3b. Start Supabase Realtime subscriptions if authenticated
      try {
        final client = ref.read(supabaseProvider);
        if (client != null && client.auth.currentSession != null) {
          final realtimeService = ref.read(supabaseRealtimeProvider);
          realtimeService.initialize();
          realtimeService.subscribeToAllUserFamilies();
          debugPrint('📡 SupabaseRealtime started (delayed)');
        }
      } catch (e) {
        debugPrint('⚠️ SupabaseRealtime start failed: $e');
      }
    });

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
        await pushService.initialize();
        debugPrint('📬 PushNotificationService initialized');
      } else {
        debugPrint('⏭️ PushNotificationService skipped — no auth session');
      }
    } catch (e) {
      debugPrint('⚠️ PushNotificationService init failed: $e');
    }

    // 5. Initialize AppStartupService for background sync & provider refresh
    try {
      // Pass the global ProviderContainer — it provides ref.read() capability
      // The container is captured via ProviderScope.containerOf in initState
      final container = _globalContainer;
      if (container != null) {
        // Create a lightweight Ref adapter from the container
        AppStartupService.instance.initializeFromContainer(container);
        debugPrint('🚀 AppStartupService initialized');
      } else {
        debugPrint('⚠️ AppStartupService skipped — no global container');
      }
    } catch (e) {
      debugPrint('⚠️ AppStartupService init failed: $e');
    }

    // 6. Preload bottom nav tabs
    // PERF: Reduced from 3s to 500ms — warms familyListProvider 2.5s
    // earlier so cached data is ready by the time the user navigates
    // to the Home tab.
    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        // BUG FIX (families-not-loading-after-login): Only preload
        // `familyListProvider` when there is an active auth session.
        //
        // Previously this call ran unconditionally ("works with or without
        // auth session"), which meant that if the user was still on the
        // sign-in screen 3 seconds after app launch, the provider would
        // evaluate with `currentSession == null` and cache `[]`. The home
        // screen would then show "No Families Yet" after the user signed
        // in, because the cached empty result kept being returned. The
        // families only appeared after the user triggered create-family
        // (which calls `ref.invalidate(familyListProvider)`).
        //
        // The empty cache is now also recovered by:
        //   • `familyListProvider` watching `currentUserProvider` (auto-
        //     rebuild on sign-in), AND
        //   • the auth state listener in this file invalidating the
        //     provider on `signedIn`.
        // But skipping the preload entirely when unauthenticated avoids
        // caching a known-empty result in the first place.
        final client = ref.read(supabaseProvider);
        final hasSession = client?.auth.currentSession != null;
        if (hasSession) {
          ref.read(familyListProvider.future).catchError((_) => <Family>[]);
        } else {
          debugPrint('⏭️ familyListProvider preload skipped — no auth session');
        }
        ref.read(profileProvider.notifier).loadProfile().catchError((_) {});
        ref.read(profileProvider.notifier).loadStats().catchError((_) {});
        debugPrint('🚀 Bottom nav tabs preloaded');
      } catch (e) {
        debugPrint('⚠️ Bottom nav preload failed: $e');
      }
    });

    // ── Initialize Analytics Service ────────────────────────────────
    try {
      await AnalyticsService.instance.init();
    } catch (e) {
      debugPrint('⚠️ Analytics init failed: $e');
    }

    // ── Initialize Remote Config Service ──────────────────────────
    try {
      await RemoteConfigService.instance.init();
      debugPrint('✅ Remote Config initialized');
    } catch (e) {
      debugPrint('⚠️ Remote Config init failed, using defaults: $e');
    }

    // ── Record app open for retention tracking ──────────────────────
    try {
      if (IsarDatabase.isInitialized) {
        final db = IsarDatabase.instance;
        final opensStr = await db.getSetting('app_opens');
        final opens = int.tryParse(opensStr ?? '0') ?? 0;
        await db.setSetting('app_opens', '${opens + 1}');
        await db.setSetting('last_open', DateTime.now().toIso8601String());
      }
    } catch (_) {}

    // ── Initialize Rating Service ────────────────────────────────
    RatingService.instance.init();

    // ── Accessibility audit (debug only) ────────────────────────────
    A11yChecker.runAudit();

    // ── Memory monitor (debug only) ─────────────────────────────────
    MemoryMonitor.start();

    // ── Capture provider state for crash context ───────────────────
    try {
      ref.listen(familyListProvider, (_, next) {
        captureRiverpodState('familyList', {
          'count': next.value?.length ?? 0,
          'isLoading': next.isLoading,
          'hasError': next.hasError,
        });
      });
    } catch (_) {}

    // ── Initialize Deep Link Service ────────────────────────────────
    try {
      final deepLinkService = ref.read(deepLinkServiceProvider);
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
      );
    } catch (e) {
      debugPrint('⚠️ Deep link service init failed: $e');
    }
    } catch (e, st) {
      debugPrint('🔴 _initDeferredServices top-level error: $e');
      debugPrint('   Stack: $st');
    }
  }

  Future<void> _loadSavedLocale() async {
    try {
      final storage = SecureStorageService();
      final lang = await storage.getPreferredLanguage();
      if (lang != null && lang.isNotEmpty) {
        ref.read(localeProvider.notifier).state = Locale(lang);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app comes back to foreground, update system UI overlay
    if (state == AppLifecycleState.resumed) {
      _updateSystemUIOverlay();

      // Silently refresh the session in the background
      if (isSupabaseInitialized) {
        try {
          final client = ref.read(supabaseProvider);
          if (client != null && client.auth.currentSession != null) {
            client.auth.refreshSession().catchError((_) {
              return AuthResponse();
            });

            // Reconnect socket if not connected
            try {
              final socketService = ref.read(socketServiceProvider);
              if (!socketService.isConnected) {
                socketService.connect();
              }
            } catch (_) {}

            // Trigger background sync on app resume
            try {
              final bgSyncManager = ref.read(backgroundSyncManagerProvider);
              bgSyncManager.onAppResumed();
            } catch (_) {}
          }
        } catch (_) {}
      }

      logActionBreadcrumb('app_resume');
      RatingService.instance.onForeground();
    } else if (state == AppLifecycleState.paused) {
      logActionBreadcrumb('app_background');
      sendUnsentReports();
      RatingService.instance.onBackground();

      // Stop periodic sync while in background
      try {
        final bgSyncManager = ref.read(backgroundSyncManagerProvider);
        bgSyncManager.stop();
      } catch (_) {}
    }
  }

  /// Update system UI overlay style to match the current theme brightness.
  void _updateSystemUIOverlay() {
    final themeMode = ref.read(themeModeProvider);
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: isDark
            ? const Color(0xFF121212)
            : const Color(0xFFF5F7FA),
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final lightTheme = ref.watch(lightThemeProvider);
    final darkTheme = ref.watch(darkThemeProvider);
    final router = ref.watch(routerProvider);

    return _KinshipInitializer(
      child: MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      // v47 FIX: Allow touch, mouse, trackpad, and stylus gestures everywhere.
      // Without this, Android touch events can get routed to the scroll system
      // instead of the graph's ScaleGestureRecognizer, causing pinch-zoom and
      // node taps to fail on Android while working on Web (mouse events bypass
      // the scroll behavior entirely).
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      ),
      // Support both light and dark themes
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      // Localization — 15 languages
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      locale: ref.watch(localeProvider),
      builder: (context, child) {
        // Update system UI overlay when theme changes
        final brightness = MediaQuery.of(context).platformBrightness;
        final effectiveDark =
            themeMode == ThemeMode.dark ||
            (themeMode == ThemeMode.system && brightness == Brightness.dark);

        // Set system UI overlay on every build to stay in sync
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: effectiveDark
                ? Brightness.light
                : Brightness.dark,
            statusBarBrightness: effectiveDark
                ? Brightness.dark
                : Brightness.light,
            systemNavigationBarColor: effectiveDark
                ? const Color(0xFF121212)
                : const Color(0xFFF5F7FA),
            systemNavigationBarIconBrightness: effectiveDark
                ? Brightness.light
                : Brightness.dark,
          ),
        );

        // Bug fix (split-screen / keyboard white-screen):
        //
        // ROOT CAUSE: The previous builder returned a bare `Column`
        // wrapping [OfflineBanner] + [Expanded(child)]. The Column
        // itself has no background color, so when the keyboard opens
        // or the viewport shrinks in split-screen/half-screen mode,
        // any gap between the child's bottom and the viewport's bottom
        // (caused by `Scaffold.resizeToAvoidBottomInset` shrinking the
        // body) exposed the default white Material background — a
        // jarring flash of white in an otherwise dark app.
        //
        // FIX:
        // 1. Wrap the entire Column in a `ColoredBox` using the
        //    effective scaffold background color (dark or light). This
        //    guarantees NO white ever shows through, regardless of how
        //    the child sizes itself.
        // 2. The Column + Expanded pattern is kept (OfflineBanner
        //    pinned to top, child fills the rest) — this is correct
        //    because Scaffold.resizeToAvoidBottomInset handles the
        //    keyboard inset INSIDE the child's own Scaffold, not here.
        // 3. The ColoredBox fills the full screen, so even if the
        //    child's Scaffold has `resizeToAvoidBottomInset: false`
        //    (graph screen) and leaves a gap below the keyboard, that
        //    gap is the dark color, not white.
        final scaffoldBg = effectiveDark
            ? const Color(0xFF131416) // KinrelColors.darkBackground
            : const Color(0xFFF5F7FA); // light scaffold bg

        return ColoredBox(
          color: scaffoldBg,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(ref.watch(fontScaleProvider)),
            ),
            // v109.8: Use Expanded+Column pattern inside a SafeArea-like
            // structure. The Column + Expanded ensures the child fills
            // the available space WITHOUT overflow when the viewport
            // changes (keyboard, split-screen, resize). The ColoredBox
            // behind it guarantees no white gaps.
            child: Column(
              children: [
                const OfflineBanner(),
                Expanded(
                  child: GameInviteListener(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      ),
    );
  }
}

/// v74: Replaces the deleted KinshipAssetGate. Simply loads
/// kinship_core.json (bundled, ~115KB, instant) on startup.
/// No background download — the full 5,363-entry const map
/// (kinship_category_map.dart) is compiled into the binary and
/// needs no I/O.
class _KinshipInitializer extends StatefulWidget {
  final Widget child;
  const _KinshipInitializer({required this.child});

  @override
  State<_KinshipInitializer> createState() => _KinshipInitializerState();
}

class _KinshipInitializerState extends State<_KinshipInitializer> {
  @override
  void initState() {
    super.initState();
    _loadKinship();
  }

  Future<void> _loadKinship() async {
    try {
      await KinshipService.instance.load();
      debugPrint('✅ Kinship core data loaded: ${KinshipService.instance.totalRelationships} relationships');
    } catch (e) {
      debugPrint('⚠️ Failed to load kinship core data: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
// v74: English-only kinship — no download needed

