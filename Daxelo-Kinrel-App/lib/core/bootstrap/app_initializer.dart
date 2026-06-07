// lib/core/bootstrap/app_initializer.dart
//
// DAXELO KINREL — App Initializer
//
// Quick, non-blocking setup that MUST happen before runApp().
// Heavy service initialization (Drift, Firebase, Supabase) is
// handled by ServiceOrchestrator after the first frame renders.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../config/app_environment.dart';
import '../utils/device_tier.dart';
import 'error_handler.dart';

class AppInitializer {
  /// Perform quick initialization before runApp().
  /// This MUST be fast — the user sees a black screen until runApp() is called.
  static Future<void> initialize() async {
    // ── CRITICAL: Ensure Flutter binding BEFORE any async work ────────
    WidgetsFlutterBinding.ensureInitialized();

    // ── Yield to the event loop to prevent ANR ───────────────────────
    // The Android main thread needs to process pending messages (touch
    // events, lifecycle callbacks) before we start heavy work.
    await Future.delayed(Duration.zero);

    // ── 1. Initialize environment (CPU-bound, fast) ──────────────────
    try {
      AppEnvironmentConfig.initialize();
    } catch (e) {
      debugPrint('⚠️ AppEnvironmentConfig.initialize failed: $e');
    }

    // ── 2. Set up global error handlers ───────────────────────────────
    ErrorHandler.setup();

    // ── 3. Set system UI overlay (non-blocking platform channel) ──────
    // Use unawaited to prevent blocking the main isolate while the
    // platform channel processes. The UI overlay will apply asynchronously.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF121212),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // ── Yield again before platform channel call ──────────────────────
    await Future.delayed(Duration.zero);

    // ── 4. Set preferred orientations (platform channel — can block) ──
    // Wrap in a timeout to prevent indefinite blocking on slow devices.
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('⚠️ setPreferredOrientations timed out — continuing');
        },
      );
    } catch (_) {}

    // ── Yield to event loop ──────────────────────────────────────────
    await Future.delayed(Duration.zero);

    // ── 5. Detect Device Tier (CPU-bound, fast) ──────────────────────
    try {
      final binding = WidgetsFlutterBinding.instance;
      final view = binding.platformDispatcher.views.first;
      final physicalSize = view.physicalSize;
      final pixelRatio = view.devicePixelRatio;
      final screenWidth = physicalSize.width / pixelRatio;
      DeviceTierCache.instance.initialize(screenWidth, pixelRatio);
    } catch (e) {
      debugPrint('⚠️ Device tier detection failed: $e');
    }

    // ── 6. Desktop window setup (only on desktop platforms) ──────────
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
      } catch (e) {
        debugPrint('⚠️ Desktop window setup failed: $e');
      }
    }
  }
}
