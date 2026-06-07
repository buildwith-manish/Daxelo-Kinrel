// lib/core/bootstrap/app_init_provider.dart
//
// DAXELO KINREL — Background Bootstrap Provider
//
// ARCHITECTURE REWRITE: This provider runs ALL service initialization
// in the background. The splash screen NEVER awaits this provider.
// It is triggered by KinrelApp's postFrameCallback and runs
// independently while the user sees the splash animation.
//
// Init order:
//   1. AppEnvironmentConfig (compile-time env)
//   2. SystemChrome (UI overlay + orientations)
//   3. DeviceTierCache (screen classification)
//   4. Drift database (local storage)
//   5. Firebase safety net (if main() init failed)
//   6. Crashlytics (error reporting)
//   7. Supabase (auth + API)
//   8. Crash context logging
//   9. Desktop window setup
//
// Every step is followed by _yield() to let the Android message
// queue process touch/lifecycle events. All logging uses _log()
// which is gated by kDebugMode — zero overhead in release builds.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:window_manager/window_manager.dart';

import '../../firebase_options.dart';
import '../config/app_config.dart';
import '../config/app_environment.dart';
import '../config/auth_config.dart';
import '../database/app_database_service.dart';
import '../services/crashlytics_service.dart';
import '../services/supabase_service.dart';
import '../utils/device_tier.dart';

/// Debug-only log. Zero overhead in release builds — kDebugMode is
/// compile-time constant so the call is tree-shaken by dart2js/AOT.
void _log(String msg) {
  if (kDebugMode) debugPrint(msg);
}

/// Yield to the Android message queue between heavy operations.
/// 16ms = one frame — lets the native main thread process pending
/// touch/lifecycle events. Duration.zero only yields to the Dart
/// microtask queue, insufficient to prevent ANR on slow devices.
Future<void> _yield() => Future.delayed(const Duration(milliseconds: 16));

/// AsyncNotifier that performs ALL core service initialization.
/// Nobody awaits this — it runs independently in the background.
/// Triggered by `ref.read(appInitProvider)` in KinrelApp's
/// postFrameCallback.
class AppInitNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    await _bootstrap();
  }

  /// Run all initialization steps with yields between each.
  /// Total worst-case: ~3s (3s × Drift timeout) + ~3s (Supabase)
  /// + 8×16ms yields ≈ 6.1s if everything times out.
  /// Splash navigates after 2s regardless — services catch up later.
  Future<void> _bootstrap() async {
    final sw = Stopwatch()..start();
    try {
      await _yield(); // Yield before first heavy operation

      // ── 1. Environment config ─────────────────────────────────────
      try {
        AppEnvironmentConfig.initialize();
        _log('✅ AppEnvironmentConfig initialized');
      } catch (e) {
        _log('⚠️ AppEnvironmentConfig failed: $e');
      }

      await _yield();

      // ── 2. System Chrome overlay ──────────────────────────────────
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Color(0xFF121212),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );

      await _yield();

      // ── 3. Preferred orientations ─────────────────────────────────
      try {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]).timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            _log('⚠️ setPreferredOrientations timed out');
          },
        );
      } catch (_) {}

      await _yield();

      // ── 4. Device tier detection ──────────────────────────────────
      try {
        final binding = WidgetsBinding.instance;
        final view = binding.platformDispatcher.views.first;
        final physicalSize = view.physicalSize;
        final pixelRatio = view.devicePixelRatio;
        final screenWidth = physicalSize.width / pixelRatio;
        DeviceTierCache.instance.initialize(screenWidth, pixelRatio);
        _log('✅ Device tier: ${DeviceTierCache.instance.tier.name}');
      } catch (e) {
        _log('⚠️ Device tier detection failed: $e');
      }

      await _yield();

      // ── 5. Drift database ─────────────────────────────────────────
      try {
        await AppDatabaseService.initialize()
            .timeout(const Duration(seconds: 3));
        _log('✅ Drift database initialized');
      } catch (e) {
        _log('⚠️ Drift database failed or timed out: $e');
      }

      await _yield();

      // ── 6. Firebase safety net ────────────────────────────────────
      // Firebase was initialized in main() before onBackgroundMessage().
      // This is a safety net for cases where main() init failed.
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          ).timeout(const Duration(seconds: 3));
          _log('✅ Firebase initialized (safety net)');
        } else {
          _log('✅ Firebase already initialized from main()');
        }
      } catch (e) {
        _log('⚠️ Firebase safety net failed: $e');
      }

      await _yield();

      // ── 7. Crashlytics ────────────────────────────────────────────
      try {
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
        await FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(!kDebugMode);
        await initCrashlytics();
        _log('✅ Crashlytics initialized');
      } catch (e) {
        _log('⚠️ Crashlytics failed: $e');
      }

      await _yield();

      // ── 8. Supabase ───────────────────────────────────────────────
      try {
        final ready =
            await initSupabase().timeout(const Duration(seconds: 3));
        notifySupabaseReady(ref);
        _log('🔧 Supabase initialized: $ready (kAuthDisabled=$kAuthDisabled)');
      } catch (e) {
        _log('⚠️ Supabase failed or timed out: $e');
      }

      await _yield();

      // ── 9. Log crash context ──────────────────────────────────────
      try {
        logNavigationBreadcrumb('/splash');
        logActionBreadcrumb('app_start', {
          'env': AppEnvironmentConfig.current.label,
          'device_tier': DeviceTierCache.instance.tier.name,
        });
      } catch (_) {}

      await _yield();

      // ── 10. AppConfig debug ───────────────────────────────────────
      _log('🔧 AppConfig SUPABASE_URL: ${AppConfig.supabaseUrl}');
      _log(
        '🔧 AppConfig SUPABASE_ANON_KEY: ${AppConfig.supabaseAnonKey.isNotEmpty ? "SET (length: ${AppConfig.supabaseAnonKey.length})" : "EMPTY"}',
      );
      _log(
        '🔧 AppConfig isSupabaseConfigured: ${AppConfig.isSupabaseConfigured}',
      );

      await _yield();

      // ── 11. Desktop window setup ──────────────────────────────────
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        try {
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
          _log('✅ Desktop window initialized');
        } catch (e) {
          _log('⚠️ Desktop window setup failed: $e');
        }
      }
    } finally {
      sw.stop();
      _log('⏱️ Bootstrap completed in ${sw.elapsedMilliseconds}ms');
    }
  }
}

/// Provider that tracks background service initialization.
/// Splash does NOT depend on this — it navigates after 2s regardless.
/// KinrelApp triggers this in postFrameCallback via ref.read(appInitProvider).
final appInitProvider = AsyncNotifierProvider<AppInitNotifier, void>(
  AppInitNotifier.new,
);
