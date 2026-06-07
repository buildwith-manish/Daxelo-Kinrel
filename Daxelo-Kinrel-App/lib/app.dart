// lib/app.dart
//
// DAXELO KINREL — Root Application Widget
//
// ANR FIX: All initialization happens AFTER the first frame renders.
// main.dart just calls runApp() with zero blocking. The heavy init
// (SystemChrome, device tier, Drift, Firebase, Supabase) runs in
// addPostFrameCallback with yields between each step.

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

import 'core/bootstrap/app_initializer.dart';
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
    WidgetsBinding.instance.addObserver(this);

    // ── ALL initialization deferred to after first frame ─────────────
    // This is the critical ANR fix: the first frame paints BEFORE any
    // heavy work starts. Android sees the app is responsive within the
    // 5-second ANR window because the initial frame is rendered immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAfterFirstFrame();
    });
  }

  /// Runs all initialization after the first frame is painted.
  /// Each heavy step yields to the event loop to prevent ANR.
  Future<void> _initializeAfterFirstFrame() async {
    // ── Step 1: AppInitializer (SystemChrome, device tier) ───────────
    try {
      await AppInitializer.initialize();
    } catch (e) {
      debugPrint('⚠️ AppInitializer failed: $e');
    }

    if (!mounted) return;

    // ── Step 2: Theme listener (lightweight) ─────────────────────────
    ref.listen(themeModeProvider, (_, themeMode) {
      _updateSystemUIOverlay();
    });
    _updateSystemUIOverlay();

    // ── Step 3: Load saved locale ────────────────────────────────────
    unawaited(_loadSavedLocale());

    // ── Step 4: Trigger core init provider (Drift, Firebase, Supabase)
    // Splash screen watches appInitProvider to know when ready.
    ref.read(appInitProvider);

    // ── Step 5: Start deferred services ──────────────────────────────
    ServiceOrchestrator.startDeferredServices(ref);
  }

  Future<void> _loadSavedLocale() async {
    try {
      await Future.delayed(Duration.zero); // yield before platform call
      final storage = SecureStorageService();
      final lang = await storage.getPreferredLanguage()
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      if (lang != null && lang.isNotEmpty && mounted) {
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
    if (state == AppLifecycleState.resumed) {
      _updateSystemUIOverlay();

      if (isSupabaseInitialized) {
        try {
          final client = ref.read(supabaseProvider);
          if (client != null && client.auth.currentSession != null) {
            client.auth.refreshSession().catchError((_) {
              return AuthResponse();
            });

            try {
              final socketService = ref.read(socketServiceProvider);
              if (!socketService.isConnected) {
                socketService.connect();
              }
            } catch (_) {}

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

      try {
        final bgSyncManager = ref.read(backgroundSyncManagerProvider);
        bgSyncManager.stop();
      } catch (_) {}
    }
  }

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
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      routerConfig: router,
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
