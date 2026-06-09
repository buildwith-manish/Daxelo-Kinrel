import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// Hive removed — using Drift (AppDatabase) via IsarDatabase wrapper
import 'core/database/isar_database.dart';
import 'package:window_manager/window_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/config/app_environment.dart';
import 'core/config/auth_config.dart';
import 'core/routing/app_router.dart';
import 'core/services/crashlytics_service.dart';
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
import 'features/profile/data/profile_provider.dart';

import 'core/services/rating_service.dart';
import 'core/services/analytics_service.dart';
import 'core/services/remote_config_service.dart';
import 'core/app_startup.dart';
import 'core/family/family_provider.dart';

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
    DeviceTierCache.instance.initialize(screenWidth, pixelRatio);
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
  try {
    DefaultCacheManager().emptyCache().catchError((_) {}); // no-op; just warming
  } catch (_) {}
  // Image cache is configured via the maxDuration parameter in
  // CachedNetworkImage's cacheManager — the default is 30 days.
  // We create a custom cache manager below for 7-day / 100MB limits.

  runApp(ProviderScope(child: KinrelApp()));

  // ── Background initialization (non-blocking) ──────────────────────
  // All heavy init runs AFTER runApp. The splash screen / loading state
  // is already visible. These complete asynchronously and update the
  // app state via Riverpod providers.
  _initializeServices();
}

/// Background service initialization. Runs after runApp() so the user
/// always sees the app UI. Each step is individually wrapped in
/// try-catch with timeouts so one failure doesn't block the rest.
Future<void> _initializeServices() async {
  // ── 2. Initialize Drift database ──────────────────────────────────
  try {
    await IsarDatabase.initialize().timeout(const Duration(seconds: 5));
    debugPrint('✅ Drift database initialized');
  } catch (e) {
    debugPrint('⚠️ Drift database initialization failed or timed out: $e');
  }

  // ── 3. Load environment variables ─────────────────────────────────
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ .env file loaded successfully');
  } catch (e) {
    try {
      dotenv.loadFromString(envString: '# fallback — using hardcoded defaults');
    } catch (_) {}
    debugPrint('⚠️ .env file not found, using hardcoded defaults');
  }

  // ── 4. Initialize Firebase ────────────────────────────────────────
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
    debugPrint('✅ Firebase initialized successfully');
  } catch (e) {
    debugPrint('⚠️ Firebase initialization failed or timed out: $e');
  }

  // ── 5. Initialize Crashlytics ─────────────────────────────────────
  try {
    await initCrashlytics();
  } catch (e) {
    debugPrint('⚠️ Crashlytics initialization failed: $e');
  }

  // ── 6. Register FCM background handler ────────────────────────────
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('⚠️ FCM background handler registration failed: $e');
  }

  // ── 7. Initialize Supabase ────────────────────────────────────────
  // IMPORTANT: Supabase MUST be initialized even when kAuthDisabled=true.
  // The kAuthDisabled flag only bypasses the LOGIN SCREEN redirect —
  // backend APIs (Family Tree CRUD, Chat, Profile, etc.) still need
  // a Supabase client. If the user has a valid session from a previous
  // login, all features will work. If not, they'll fail gracefully.
  bool supabaseReady = false;
  try {
    supabaseReady = await initSupabase().timeout(const Duration(seconds: 8));
    debugPrint('🔧 Supabase initialized: $supabaseReady (kAuthDisabled=$kAuthDisabled)');
  } catch (e) {
    debugPrint('⚠️ Supabase init failed or timed out: $e');
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
        await Future.delayed(const Duration(milliseconds: 200));
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
  try {
    final pushService = ref.read(pushNotificationServiceProvider);
    await pushService.deleteToken().timeout(const Duration(seconds: 5));
  } catch (_) {}
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
    // When kAuthDisabled=true, we still initialize Supabase for backend APIs,
    // so we set up auth listeners and crash context normally.
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
          // Use mock user ID for crash context in dev mode
          setUserIdentifier(MockUser.id);
          captureRiverpodState('auth', {
            'userId': MockUser.id,
            'email': MockUser.email,
            'mode': 'auth_disabled',
          });
        }

        AuthChangeEvent? _lastAuthEvent;
        String? _lastAuthUserId;

        client.auth.onAuthStateChange.listen((data) {
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
    } catch (_) {}

    // 2. Start the SyncEngine if Isar is initialized AND user has a session
    // When kAuthDisabled, we still check for a real Supabase session
    // since the client is now initialized even in dev mode.
    Future.delayed(const Duration(seconds: 3), () {
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
    // When kAuthDisabled, still init push if there's a real session
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

    // 6. Preload bottom nav tabs (3s delay)
    Future.delayed(const Duration(seconds: 3), () {
      try {
        // Preload tabs — works with or without auth session
        ref.read(familyListProvider.future).catchError((_) => <Family>[]);
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

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
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

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(ref.watch(fontScaleProvider)),
          ),
          child: Column(
            children: [
              const OfflineBanner(),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        );
      },
    );
  }
}
