// lib/core/bootstrap/app_initializer.dart
//
// DAXELO KINREL — App Initializer
//
// Called fire-and-forget from main.dart (no await, no blocking).
// Sets up SystemChrome, device tier, and other lightweight config
// that doesn't block the first frame.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../config/app_environment.dart';
import '../utils/device_tier.dart';
import 'error_handler.dart';

/// Debug-only log. Eliminates __vfprintf/__sfvwrite overhead in release builds
/// that causes ANR when the main thread blocks on I/O during startup.
void _log(String msg) {
  if (kDebugMode) debugPrint(msg);
}

class AppInitializer {
  static bool _initialized = false;

  /// Perform lightweight initialization.
  /// Called fire-and-forget from main.dart — does NOT block the main thread.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // ── 1. Initialize environment (CPU-bound, fast) ──────────────────
    try {
      AppEnvironmentConfig.initialize();
    } catch (e) {
      _log('⚠️ AppEnvironmentConfig.initialize failed: $e');
    }

    // ── 2. Set up global error handlers ───────────────────────────────
    ErrorHandler.setup();

    // ── 3. Set system UI overlay (fire-and-forget) ────────────────────
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF121212),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // ── 4. Set preferred orientations (with timeout) ──────────────────
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

    // ── 5. Detect Device Tier (CPU-bound, fast) ──────────────────────
    try {
      final binding = WidgetsBinding.instance;
      final view = binding.platformDispatcher.views.first;
      final physicalSize = view.physicalSize;
      final pixelRatio = view.devicePixelRatio;
      final screenWidth = physicalSize.width / pixelRatio;
      DeviceTierCache.instance.initialize(screenWidth, pixelRatio);
    } catch (e) {
      _log('⚠️ Device tier detection failed: $e');
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
        _log('⚠️ Desktop window setup failed: $e');
      }
    }
  }
}
