// lib/core/bootstrap/app_initializer.dart
//
// DAXELO KINREL — App Initializer
//
// ANR FIX: This is now called AFTER runApp() renders the first frame,
// from inside KinrelApp.initState(). Zero blocking work happens before
// the first frame is painted.
//
// Previous approach: await initialize() → runApp() (blocked main thread → ANR)
// New approach: runApp() → first frame painted → initialize() in background

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../config/app_environment.dart';
import '../utils/device_tier.dart';
import 'error_handler.dart';

class AppInitializer {
  static bool _initialized = false;

  /// Perform initialization AFTER the first frame has rendered.
  /// Called from KinrelApp.initState() via addPostFrameCallback.
  /// Each step yields to the event loop to prevent ANR.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // ── 1. Initialize environment (CPU-bound, fast) ──────────────────
    try {
      AppEnvironmentConfig.initialize();
    } catch (e) {
      debugPrint('⚠️ AppEnvironmentConfig.initialize failed: $e');
    }

    // Yield to let Android process pending messages
    await Future.delayed(Duration.zero);

    // ── 2. Set up global error handlers ───────────────────────────────
    ErrorHandler.setup();

    // ── 3. Set system UI overlay (fire-and-forget, non-blocking) ─────
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF121212),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // Yield again
    await Future.delayed(Duration.zero);

    // ── 4. Set preferred orientations (with timeout) ──────────────────
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('⚠️ setPreferredOrientations timed out');
        },
      );
    } catch (_) {}

    // Yield
    await Future.delayed(Duration.zero);

    // ── 5. Detect Device Tier (CPU-bound, fast) ──────────────────────
    try {
      final binding = WidgetsBinding.instance;
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

    debugPrint('✅ AppInitializer.initialize() complete');
  }
}
