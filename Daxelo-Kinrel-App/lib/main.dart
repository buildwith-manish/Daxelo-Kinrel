import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'core/database/isar_database.dart';
import 'core/database/sync/sync_service.dart';
import 'core/network/socket_service.dart';
import 'core/utils/device_tier.dart';
import 'core/utils/a11y_checker.dart';
import 'core/utils/memory_monitor.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'core/widgets/offline_banner.dart';
import 'features/profile/data/profile_provider.dart';
import 'core/database/repositories/offline_family_repository.dart';
import 'core/services/rating_service.dart';
import 'core/family/family_provider.dart';
import 'features/family/providers/member_detail_provider.dart';

// Generated localization imports (flutter gen-l10n)
import 'package:kinrel/l10n/app_localizations.dart';

void main() async {
  // ── P3-F1: runZonedGuarded wraps everything ──────────────────────
  // This catches ALL uncaught async errors, even those that
  // PlatformDispatcher.onError misses (Timer, Future callbacks, etc.)

  // Initialize environment FIRST — determines dev/staging/prod
  AppEnvironmentConfig.initialize();

  // ── P3-F3: Register FCM background handler BEFORE runApp() ────────
  // Must be a top-level function, registered as early as possible
  // so background isolates can handle messages from the start.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Run the rest inside a guarded zone
  runWithCrashGuard(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // ── P4-F7: Global error widget — prevents red screen of death ──
    ErrorWidget.builder = (FlutterErrorDetails details) {
      try {
        FirebaseCrashlytics.instance.recordFlutterError(details);
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
                const Text('Tap to go home',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
    };

    // ── CRITICAL PATH: only essentials before runApp() ─────────────
    // These are needed before the first frame renders.
    // Everything else is deferred via addPostFrameCallback.

    // Load environment variables from .env file
    // CRITICAL: dotenv MUST be initialized before anyone calls dotenv.env[]
    try {
      await dotenv.load(fileName: '.env');
      debugPrint('✅ .env file loaded successfully');
    } catch (e) {
      try {
        dotenv.loadFromString(envString: '# fallback — using hardcoded defaults');
      } catch (_) {}
      debugPrint('⚠️ .env file not found or empty, using fallback defaults');
    }

    // Set initial system UI overlay style
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

    // Initialize Hive for local caching
    await Hive.initFlutter();

    // Initialize Isar database for offline-first caching
    try {
      await IsarDatabase.initialize();
      debugPrint('✅ Isar database initialized');
    } catch (e) {
      debugPrint('⚠️ Isar initialization failed, continuing without offline cache: $e');
    }

    // Disable Google Fonts runtime fetching — we bundle key fonts instead
    GoogleFonts.config.allowRuntimeFetching = false;

    // ── Detect Device Tier ──────────────────────────────────────────────
    // Initialize DeviceTierCache from the first available MediaQuery data.
    // This must happen before runApp() so that all providers and widgets
    // can access the tier during their first build.
    final binding = WidgetsFlutterBinding.ensureInitialized();
    final view = binding.platformDispatcher.views.first;
    final physicalSize = view.physicalSize;
    final pixelRatio = view.devicePixelRatio;
    final screenWidth = physicalSize.width / pixelRatio;
    DeviceTierCache.instance.initialize(screenWidth, pixelRatio);

    // ── Log environment info for crash context ─────────────────────
    logNavigationBreadcrumb('/splash');
    logActionBreadcrumb('app_start', {
      'env': AppEnvironmentConfig.current.label,
      'device_tier': DeviceTierCache.instance.tier.name,
    });

    runApp(ProviderScope(child: KinrelApp()));
  });
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
    // These run after the first frame renders, so the user sees
    // the splash screen instantly instead of waiting for services.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initDeferredServices();
    });
  }

  /// Initialize services that are NOT required for the first frame.
  /// Runs after the widget tree is built, so the splash screen
  /// appears immediately while these load in the background.
  Future<void> _initDeferredServices() async {
    // 1. Firebase Crashlytics (non-critical — catches crashes AFTER init)
    await initCrashlytics();

    // 2. Local cache service (Hive-based, used alongside Isar)
    final cacheService = LocalCacheService();
    await cacheService.init();

    // 3. Initialize Supabase — will ALWAYS succeed with hardcoded fallbacks
    final supabaseReady = await initSupabase();
    debugPrint('🔧 Supabase initialized: $supabaseReady');

    // ── P3-F1: Capture auth state for crash context ───────────────
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
        client.auth.onAuthStateChange.listen((event) {
          final user = event.session?.user;
          if (user != null) {
            setUserIdentifier(user.id);
            captureRiverpodState('auth', {
              'userId': user.id,
              'email': user.email ?? 'unknown',
              'event': event.event.name,
            });

            // ── P3-F3: Re-sync FCM token on sign-in ──────────────────
            // When the user signs in (or token refreshes), ensure the
            // FCM token is synced to the backend.
            if (event.event == AuthChangeEvent.signedIn) {
              try {
                final pushService = ref.read(pushNotificationServiceProvider);
                if (!pushService.isInitialized) {
                  pushService.onDeepLink = (route) {
                    try {
                      final router = ref.read(routerProvider);
                      router.push(route);
                    } catch (_) {}
                  };
                  pushService.initialize();
                } else {
                  pushService.resyncToken();
                }
              } catch (_) {}
            }
          } else {
            captureRiverpodState('auth', {'status': 'signed_out'});

            // ── P3-F3: Delete FCM token on sign-out ───────────────────
            // Prevent notifications from being delivered after sign-out.
            try {
              final pushService = ref.read(pushNotificationServiceProvider);
              pushService.deleteToken();
              pushService.dispose();
            } catch (_) {}
          }
        });
      }
    } catch (_) {}

    // 4. Start the sync service if Isar is initialized
    if (IsarDatabase.isInitialized) {
      try {
        final syncService = ref.read(syncServiceProvider);
        syncService.start();
        debugPrint('🔄 SyncService started');
      } catch (e) {
        debugPrint('⚠️ SyncService start failed: $e');
      }
    }

    // 5. Start the Socket.IO service if authenticated
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

    // ── P3-F3: Initialize Push Notifications if authenticated ─────
    // Only register FCM when the user is signed in.
    // Token sync requires a valid Supabase JWT for the NestJS backend.
    try {
      final client = ref.read(supabaseProvider);
      if (client != null && client.auth.currentSession != null) {
        final pushService = ref.read(pushNotificationServiceProvider);
        // Set up deep link handler to navigate via GoRouter
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

    // 6. Preload bottom nav tabs (500ms delay to not compete with initial load)
    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        // Warm up providers for tabs the user hasn't opened yet
        ref.read(familyListProvider.future); // Graph tab
        ref.read(profileProvider.notifier).loadProfile(); // Profile tab
        ref.read(profileProvider.notifier).loadStats(); // Profile tab
        debugPrint('🚀 Bottom nav tabs preloaded');
      } catch (e) {
        debugPrint('⚠️ Bottom nav preload failed: $e');
      }
    });

    // 7. Birthday preload — check for upcoming birthdays in the next 7 days
    if (IsarDatabase.isInitialized) {
      try {
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
                  // Preload this member's profile silently
                  debugPrint('🎂 Birthday preload: ${member.name} in $daysUntil days');
                  try {
                    unawaited(ref.read(memberDetailProvider(member.id).future));
                  } catch (_) {
                    // Silently ignore — best-effort preload
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Birthday preload failed: $e');
      }
    }

    // ── P4-F2: Initialize Rating Service ────────────────────────
    RatingService.instance.init();

    // ── P3-F5: Accessibility audit (debug only)
    A11yChecker.runAudit();

    // ── P4-F7: Memory monitor (debug only) ─────────────────────────
    MemoryMonitor.start();

    // ── P3-F1: Capture provider state for crash context ───────────
    try {
      // Listen to family list provider state
      ref.listen(familyListProvider, (_, next) {
        captureRiverpodState('familyList', {
          'count': next.value?.length ?? 0,
          'isLoading': next.isLoading,
          'hasError': next.hasError,
        });
      });
    } catch (_) {}

    // ── P3-F2: Initialize Deep Link Service ─────────────────────────
    // Listens for incoming deep links (cold start + warm start) and
    // navigates to the correct screen using GoRouter.
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

      // Silently refresh the session in the background WITHOUT triggering
      // a navigation reset.
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
          }
        } catch (_) {}
      }

      // ── P3-F1: Log app resume action ─────────────────────────────
      logActionBreadcrumb('app_resume');

      // ── P4-F2: Rating service foreground tracking ───────
      RatingService.instance.onForeground();
    } else if (state == AppLifecycleState.paused) {
      // ── P3-F1: Log app background action ─────────────────────────
      logActionBreadcrumb('app_background');
      // Force-send any pending crash reports while we have a chance
      sendUnsentReports();

      // ── P4-F2: Rating service background tracking ───────
      RatingService.instance.onBackground();
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
      locale: ref.watch(localeProvider), // Saved language preference or system default
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
            // Respect platform brightness — do NOT force dark mode
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
