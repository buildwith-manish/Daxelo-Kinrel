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

    // ── 1. Initialize environment ────────────────────────────────────
    try {
      AppEnvironmentConfig.initialize();
    } catch (e) {
      debugPrint('⚠️ AppEnvironmentConfig.initialize failed: $e');
    }

    // ── 2. Set up global error handlers ───────────────────────────────
    ErrorHandler.setup();

    // ── 3. Set system UI overlay (fast, non-blocking) ────────────────
    try {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
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

    // ── 4. Detect Device Tier (fast) ─────────────────────────────────
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

    // ── 5. Desktop window setup (only on desktop platforms) ──────────
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
