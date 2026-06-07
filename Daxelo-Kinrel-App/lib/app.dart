// lib/app.dart
//
// DAXELO KINREL — Root Application Widget
//
// Contains the KinrelApp ConsumerStatefulWidget and its state.
// Moved from main.dart as part of CQ-01 (split main.dart).

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

    // ── Stage 1: Load locale (after first frame, non-blocking) ────
    // Uses Future.delayed to yield to the event loop first, preventing
    // ANR from SecureStorage platform channel calls blocking the UI thread.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _loadSavedLocale();
      });
    });

    // ── Stage 2: Theme listener (after first frame, lightweight) ──
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listen(themeModeProvider, (_, themeMode) {
        _updateSystemUIOverlay();
      });
      // Also call once on init
      _updateSystemUIOverlay();
    });

    // ── Stage 3: Heavy init (deferred to avoid ANR) ───────────────
    // Delays by 100ms to ensure the first frame has fully rendered and
    // the Android message queue is drained. This prevents the ANR that
    // occurs when Dart native code blocks the main thread during cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        try {
          // Trigger core init provider (Drift, Firebase, Supabase)
          // This will start async — splash screen watches appInitProvider
          ref.read(appInitProvider);
          // Start deferred services (auth listener, connectivity, etc.)
          ServiceOrchestrator.startDeferredServices(ref);
        } catch (e) {
          debugPrint('🔴 ServiceOrchestrator start failed: $e');
        }
      });
    });
  }

  Future<void> _loadSavedLocale() async {
    try {
      final storage = SecureStorageService();
      // Add a yield before the platform channel call to let the
      // Android message queue process pending touch/lifecycle events.
      await Future.delayed(Duration.zero);
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
