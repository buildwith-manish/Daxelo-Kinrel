// lib/app.dart
//
// DAXELO KINREL — Root Application Widget
//
// ARCHITECTURE: main.dart does ONLY 4 things (ensureInitialized,
// Firebase init, onBackgroundMessage, runApp). All other initialization
// runs here via postFrameCallback → appInitProvider (background
// bootstrap) + ServiceOrchestrator (deferred services). The splash
// screen NEVER awaits any init — it navigates after 2s.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/routing/app_router.dart';
import 'core/services/crashlytics_service.dart';
import 'core/services/rating_service.dart';
import 'core/services/supabase_service.dart';
import 'core/database/sync/background_sync_manager.dart';
import 'core/network/socket_service.dart';
import 'core/theme/theme_provider.dart';
import 'core/storage/secure_storage.dart';
import 'core/widgets/offline_banner.dart';

import 'core/bootstrap/service_orchestrator.dart';
import 'core/bootstrap/app_init_provider.dart';

// Generated localization imports (flutter gen-l10n) — class name 'S' per l10n.yaml
import 'package:kinrel/l10n/app_localizations.dart';

class KinrelApp extends ConsumerStatefulWidget {
  const KinrelApp({super.key});

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

    // Load saved language preference — deferred to avoid synchronous
    // platform channel initialization (SecureStorage) during the first
    // frame build, which can block the main thread on cold starts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedLocale();
    });

    // Listen to theme changes and update system UI overlay accordingly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listen(themeModeProvider, (_, themeMode) {
        _updateSystemUIOverlay();
      });
      // Also call once on init
      _updateSystemUIOverlay();
    });

    // ── DEFERRED INIT: non-critical services after first frame ───
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // Trigger background bootstrap (Drift, Firebase, Crashlytics, Supabase, etc.)
        // Nobody awaits this — splash navigates after 2s regardless.
        ref.read(appInitProvider);
        // Start deferred services (auth listener, connectivity, sync, etc.)
        ServiceOrchestrator.startDeferredServices(ref);
      } catch (e) {
        debugPrint('🔴 ServiceOrchestrator start failed: $e');
      }
    });
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

  /// Handle app resume with staggered, non-blocking operations.
  /// Yields between each heavy operation to prevent ANR.
  Future<void> _handleAppResumed() async {
    // Yield first to let the framework process the resume event
    await Future.delayed(Duration.zero);

    // Silently refresh the session in the background
    if (isSupabaseInitialized) {
      try {
        final client = ref.read(supabaseProvider);
        if (client != null && client.auth.currentSession != null) {
          // ANR FIX: Use timeout on refreshSession to prevent blocking
          await client.auth.refreshSession().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('⚠️ Session refresh timed out on resume');
              return AuthResponse(session: null, user: null);
            },
          ).catchError((_) {
            return AuthResponse(session: null, user: null);
          });

          // Yield between operations
          await Future.delayed(Duration.zero);

          // Reconnect socket if not connected
          try {
            final socketService = ref.read(socketServiceProvider);
            if (!socketService.isConnected) {
              socketService.connect();
            }
          } catch (_) {}

          // Yield before triggering sync
          await Future.delayed(Duration.zero);

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

      // ANR FIX: Defer heavy resume operations to prevent blocking the main
      // thread. Session refresh, socket reconnect, and background sync are
      // staggered with yields so the Android message queue can process
      // pending touch/lifecycle events between each operation.
      unawaited(_handleAppResumed());
    } else if (state == AppLifecycleState.paused) {
      logActionBreadcrumb('app_background');
      sendUnsentReports();
      RatingService.instance.onBackground();

      // ANR FIX: Stop periodic sync in background (fire-and-forget, no await needed)
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
      localizationsDelegates: [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      locale: ref.watch(localeProvider),
      builder: (context, child) {
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
