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
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/config/app_environment.dart';
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
import 'core/utils/device_tier.dart';
import 'core/utils/a11y_checker.dart';
import 'core/utils/memory_monitor.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'core/widgets/offline_banner.dart';
import 'features/profile/data/profile_provider.dart';
import 'core/database/repositories/offline_family_repository.dart';
import 'core/services/rating_service.dart';
import 'core/services/analytics_service.dart';
import 'core/services/remote_config_service.dart';
import 'core/family/family_provider.dart';
import 'features/family/providers/member_detail_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Generated localization imports (flutter gen-l10n)
import 'package:kinrel/l10n/app_localizations.dart';

void main() async {
  // ── CRITICAL: Ensure Flutter binding BEFORE any async work ────────
  WidgetsFlutterBinding.ensureInitialized();

  // ── 1. Initialize environment ────────────────────────────────────
  try {
    AppEnvironmentConfig.initialize();
  } catch (e) {
    debugPrint('⚠️ AppEnvironmentConfig.initialize failed: $e');
  }

  // ── P4-F7: Global error widget — prevents red screen of death ──
  ErrorWidget.builder = (FlutterErrorDetails details) {
    try {
      if (isCrashlyticsAvailable) {
        FirebaseCrashlytics.instance.recordFlutterError(details);
      }
    } catch (_) {}
    return Material(
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48,
                  color: Colors.red.shade700),
              const SizedBox(height: 16),
              const Text('Something went wrong',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Please restart the app',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  };

  // ── 2. Initialize Drift database (replaces Hive) ──
  try {
    await IsarDatabase.initialize();
    debugPrint('✅ Drift database initialized (replaces Hive)');
  } catch (e) {
    debugPrint('⚠️ Drift database initialization failed: $e');
    // Continue — DB failures should not prevent the app from starting
  }

  // ── 3. Load environment variables (with safe fallback) ────────────
  // The .env file may not exist in release builds — always wrap in try-catch.
  // AppConfig has hardcoded fallbacks for all env vars, so this is safe.
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('✅ .env file loaded successfully');
  } catch (e) {
    // .env missing is EXPECTED on release builds — don't crash.
    // Load an empty string so dotenv.isInitialized is true and
    // dotenv.env[] calls don't throw NotInitializedError.
    try {
      dotenv.loadFromString(envString: '# fallback — using hardcoded defaults');
    } catch (_) {}
    debugPrint('⚠️ .env file not found, using hardcoded defaults');
  }

  // ── 4. Initialize Firebase (wrapped in try-catch) ────────────────
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase initialized successfully');
  } catch (e) {
    debugPrint('⚠️ Firebase initialization failed: $e');
    // Continue — app works without Firebase (no crashlytics/push)
  }

  // ── 5. Initialize Crashlytics (NOW in try-catch!) ────────────────
  // Previously NOT in try-catch — this was a crash risk if Firebase
  // failed to initialize. Now safe.
  try {
    await initCrashlytics();
  } catch (e) {
    debugPrint('⚠️ Crashlytics initialization failed: $e');
  }

  // ── 6. Register FCM background handler (safe) ────────────────────
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('⚠️ FCM background handler registration failed: $e');
  }

  // ── 7. Set system UI ─────────────────────────────────────────────
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

  // ── 8. Drift database already initialized in step 2 ──

  // ── 9. Initialize Supabase BEFORE runApp ─────────────────────────
  // CRITICAL: Supabase MUST be initialized before runApp so that
  // isAuthenticatedProvider works correctly when splash navigates.
  // BUT: We limit retries to avoid blocking startup for 30+ seconds
  // on cold Supabase free tier. If init fails, the app still starts
  // and the splash screen handles navigation gracefully.
  try {
    final supabaseReady = await initSupabase();
    debugPrint('🔧 Supabase initialized before runApp: $supabaseReady');
  } catch (e) {
    debugPrint('⚠️ Supabase init failed before runApp: $e');
    // Continue — app will redirect to sign-in
  }

  // ── 10. Disable Google Fonts runtime fetching ────────────────────
  GoogleFonts.config.allowRuntimeFetching = false;

  // ── 11. Detect Device Tier (safe) ────────────────────────────────
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

  // ── Log environment info for crash context ────────────────────────
  try {
    logNavigationBreadcrumb('/splash');
    logActionBreadcrumb('app_start', {
      'env': AppEnvironmentConfig.current.label,
      'device_tier': DeviceTierCache.instance.tier.name,
    });
  } catch (_) {}

  // ── Desktop window setup ──────────────────────────────────────────
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

  // ── Run app with Sentry crash reporting ────────────────────────────
  // IMPORTANT: We ALWAYS call runApp() — no matter what failed above.
  // A broken app is better than a blank screen.
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment(
        'SENTRY_DSN',
        defaultValue: '',
      );
      options.tracesSampleRate = 0.1;
      options.environment = const String.fromEnvironment(
        'ENV',
        defaultValue: 'development',
      );
    },
    appRunner: () => runZonedGuarded<Future<void>>(
      () async {
        runApp(ProviderScope(child: KinrelApp()));
      },
      (error, stack) {
        try {
          _attachStateContext(error.toString());
          if (isCrashlyticsAvailable) {
            FirebaseCrashlytics.instance.recordError(
              error,
              stack,
              reason: 'Uncaught async error in guarded zone',
              fatal: true,
            );
          }
        } catch (_) {}
        debugPrint('🔴 [Uncaught async error]: $error');
        debugPrint('   Stack: $stack');
      },
    ),
  );
}

/// Attach captured Riverpod state + breadcrumbs to a Crashlytics report.
void _attachStateContext(String errorContext) {
  if (!isCrashlyticsAvailable) return;
  try {
    FirebaseCrashlytics.instance.setCustomKey(
      'crash_environment',
      AppEnvironmentConfig.current.label,
    );
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
    // Register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // Load saved language preference
    _loadSavedLocale();

    // ── DEFERRED INIT: non-critical services after first frame ───
    // These run after the widget tree is built, so the splash screen
    // appears immediately while these load in the background.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initDeferredServices();
    });
  }

  /// Initialize services that are NOT required for the first frame.
  /// Runs after the widget tree is built, so the splash screen
  /// appears immediately while these load in the background.
  Future<void> _initDeferredServices() async {
    // 1. Local cache service (Hive-based, used alongside Isar)
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

        // Listen for auth state changes to update crash context
        client.auth.onAuthStateChange.listen((event) async {
          try {
            final user = event.session?.user;
            if (user != null) {
              setUserIdentifier(user.id);
              captureRiverpodState('auth', {
                'userId': user.id,
                'email': user.email ?? 'unknown',
                'event': event.event.name,
              });

              // ── Re-sync FCM token on sign-in ──────────────────────
              if (event.event == AuthChangeEvent.signedIn) {
                // Set user properties for analytics
                try {
                  final familyList = await ref.read(familyListProvider.future);
                  final primaryFamily = familyList.isNotEmpty ? familyList.first : null;
                  final profileState = ref.read(profileProvider);
                  await AnalyticsService.instance.setUserProperties(
                    userId: user.id,
                    familyId: primaryFamily?.id ?? '',
                    memberCount: profileState.stats?.membersAdded ?? 0,
                    preferredLanguage: profileState.profile?.preferredLanguage ?? 'en',
                    isPremium: false,
                  );
                } catch (_) {}

                try {
                  final pushService = ref.read(pushNotificationServiceProvider);
                  if (!pushService.isInitialized) {
                    pushService.onDeepLink = (route) {
                      try {
                        final router = ref.read(routerProvider);
                        router.push(route);
                      } catch (_) {}
                    };
                    // CRITICAL: MUST await initialize() — if not awaited,
                    // errors become unhandled async errors that crash the app.
                    await pushService.initialize();
                  } else {
                    await pushService.resyncToken();
                  }
                } catch (_) {}
              }
            } else {
              captureRiverpodState('auth', {'status': 'signed_out'});

              // ── Delete FCM token on sign-out ───────────────────────
              // LOGIN BYPASSED: Skip FCM cleanup — login is disabled
              // TODO: Re-enable when login is restored
              /*
              try {
                final pushService = ref.read(pushNotificationServiceProvider);
                await pushService.deleteToken();
                pushService.dispose();
              } catch (_) {}
              */
            }
          } catch (e) {
            debugPrint('⚠️ Auth state listener error: $e');
          }
        });
      }
    } catch (_) {}

    // 2. Start the SyncEngine if Isar is initialized AND user has a session
    // LOGIN BYPASSED: Only start sync if there's a real auth session.
    // Without a session, sync will fail and may cause background errors.
    if (IsarDatabase.isInitialized) {
      try {
        final client = ref.read(supabaseProvider);
        final hasSession = client?.auth.currentSession != null;
        if (hasSession) {
          final bgSyncManager = ref.read(backgroundSyncManagerProvider);
          bgSyncManager.init();
          bgSyncManager.start();
          debugPrint('🔄 SyncEngine + BackgroundSyncManager started');
        } else {
          debugPrint('⏭️ SyncEngine skipped — no auth session (LOGIN BYPASSED)');
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
        debugPrint('🔌 SocketService started');
      }
    } catch (e) {
      debugPrint('⚠️ SocketService start failed: $e');
    }

    // 4. Initialize Push Notifications if authenticated
    // LOGIN BYPASSED: Skip push notifications when no session exists.
    // Push notifications require a valid auth token to sync FCM token
    // to the backend. Without a session, _syncTokenToBackend would
    // get 401/404 errors and log non-fatal Crashlytics reports.
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
        debugPrint('⏭️ PushNotificationService skipped — no auth session (LOGIN BYPASSED)');
      }
    } catch (e) {
      debugPrint('⚠️ PushNotificationService init failed: $e');
    }

    // Debug: log resolved AppConfig values
    debugPrint('🔧 AppConfig SUPABASE_URL: ${AppConfig.supabaseUrl}');
    debugPrint(
      '🔧 AppConfig SUPABASE_ANON_KEY: ${AppConfig.supabaseAnonKey.isNotEmpty ? "SET (length: ${AppConfig.supabaseAnonKey.length})" : "EMPTY"}',
    );
    debugPrint(
      '🔧 AppConfig isSupabaseConfigured: ${AppConfig.isSupabaseConfigured}',
    );

    // 5. Preload bottom nav tabs (500ms delay to not compete with initial load)
    // CRITICAL: Each async call MUST have .catchError() — if these throw
    // without being caught, the error escapes the try-catch as an uncaught
    // async error in the guarded zone, causing a crash (blank screen).
    // LOGIN BYPASSED: Skip API preloading when there's no auth session.
    // Without a session, these calls will fail with 401/404 and generate
    // non-fatal Crashlytics reports. The providers already handle the
    // no-session case gracefully by returning empty data.
    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        final client = ref.read(supabaseProvider);
        final hasSession = client?.auth.currentSession != null;
        if (hasSession) {
          ref.read(familyListProvider.future).catchError((_) => <Family>[]);
          ref.read(profileProvider.notifier).loadProfile().catchError((_) {});
          ref.read(profileProvider.notifier).loadStats().catchError((_) {});
          debugPrint('🚀 Bottom nav tabs preloaded');
        } else {
          debugPrint('⏭️ Bottom nav preload skipped — no auth session (LOGIN BYPASSED)');
        }
      } catch (e) {
        debugPrint('⚠️ Bottom nav preload failed: $e');
      }
    });

    // 6. Birthday preload
    // LOGIN BYPASSED: Skip birthday preload when no session — repo queries
    // may fail or return stale data from a previous session.
    if (IsarDatabase.isInitialized) {
      try {
        final client = ref.read(supabaseProvider);
        final hasSession = client?.auth.currentSession != null;
        if (hasSession) {
          final repo = ref.read(offlineFamilyRepositoryProvider);
          final families = await repo.getFamilies();
          final now = DateTime.now();
          for (final family in families) {
            final members = await repo.getFamilyMembers(family.id);
            for (final member in members) {
              if (member.dateOfBirth != null) {
                final dob = DateTime.tryParse(member.dateOfBirth!);
                if (dob != null) {
                  final thisYearBirthday = DateTime(now.year, dob.month, dob.day);
                  final daysUntil = thisYearBirthday.difference(now).inDays;
                  if (daysUntil >= 0 && daysUntil <= 7) {
                    debugPrint('🎂 Birthday preload: ${member.name} in $daysUntil days');
                    try {
                      unawaited(ref.read(memberDetailProvider(member.id).future));
                    } catch (_) {}
                  }
                }
              }
            }
          }
        } else {
          debugPrint('⏭️ Birthday preload skipped — no auth session (LOGIN BYPASSED)');
        }
      } catch (e) {
        debugPrint('⚠️ Birthday preload failed: $e');
      }
    }

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

      // Stop periodic sync while in background (connectivity listener remains)
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
