// lib/core/bootstrap/app_init_provider.dart
//
// DAXELO KINREL — App Initialization Provider
//
// Replaces global mutable state (_globalContainer, _appInitComplete,
// _initCompleter) with a Riverpod AsyncNotifier that tracks
// initialization state in a reactive, testable way.
//
// ANR FIX: Added `await Future.delayed(Duration.zero)` yields between
// each heavy init step to let the Android message queue process pending
// touch/lifecycle events. Without these yields, the Dart isolate blocks
// the native main thread → ANR.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../firebase_options.dart';
import '../config/app_config.dart';
import '../config/app_environment.dart';
import '../config/auth_config.dart';
import '../database/app_database_service.dart';
import '../services/crashlytics_service.dart';
import '../services/push_notification_service.dart';
import '../services/supabase_service.dart';
import '../utils/device_tier.dart';

/// Yield to the Android message queue between heavy operations.
/// Uses a 16ms delay (one frame) to let the native main thread process
/// pending touch/lifecycle events. Duration.zero only yields to the Dart
/// microtask queue, which isn't sufficient to prevent ANR on slow devices.
Future<void> _yield() => Future.delayed(const Duration(milliseconds: 16));

/// AsyncNotifier that performs core service initialization.
///
/// When first watched, it runs all heavy initialization (Drift, Firebase,
/// Supabase, Crashlytics, FCM). The AsyncValue transitions from
/// AsyncLoading → AsyncData when complete, allowing the splash screen
/// to reactively await initialization.
class AppInitNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    await _startCoreServices();
  }

  /// Initialize core services that MUST complete before the app
  /// can function (Drift, Firebase, Supabase, etc.).
  Future<void> _startCoreServices() async {
    await _yield(); // ANR fix: yield before first heavy operation

    // ── 2. Initialize Drift database ────────────────────────────────
    try {
      await AppDatabaseService.initialize()
          .timeout(const Duration(seconds: 5));
      debugPrint('✅ Drift database initialized');
    } catch (e) {
      debugPrint('⚠️ Drift database initialization failed or timed out: $e');
    }

    await _yield(); // ANR fix: yield after Drift init

    // ── 3. Environment variables loaded at compile time ─────────────
    debugPrint('✅ Environment variables from compile-time --dart-define');

    // ── 4. Initialize Firebase ──────────────────────────────────────
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 5));
      debugPrint('✅ Firebase initialized successfully');
    } catch (e) {
      debugPrint('⚠️ Firebase initialization failed or timed out: $e');
    }

    await _yield(); // ANR fix: yield after Firebase init

    // ── 5. Initialize Crashlytics ───────────────────────────────────
    try {
      await initCrashlytics();
    } catch (e) {
      debugPrint('⚠️ Crashlytics initialization failed: $e');
    }

    // ── 6. FCM background handler already registered in main.dart ──
    // FirebaseMessaging.onBackgroundMessage() must be called before
    // runApp() per Firebase docs — moved to main.dart top-level.

    await _yield(); // ANR fix: yield after FCM setup
    await _yield(); // ANR fix: extra yield after FCM setup
    await _yield(); // ANR fix: extra yield after FCM setup

    // ── 7. Initialize Supabase ──────────────────────────────────────
    bool supabaseReady = false;
    try {
      supabaseReady = await initSupabase().timeout(const Duration(seconds: 5));
      debugPrint(
        '🔧 Supabase initialized: $supabaseReady (kAuthDisabled=$kAuthDisabled)',
      );
    } catch (e) {
      debugPrint('⚠️ Supabase init failed or timed out: $e');
    }

    await _yield(); // ANR fix: yield after Supabase init

    // ── 7b. Notify Riverpod that Supabase is ready ──────────────────
    // Use ref directly — no need for _globalContainer since we're
    // inside a Riverpod provider.
    try {
      notifySupabaseReady(ref);
      debugPrint(
        '🔧 Notified Riverpod: Supabase ready = $supabaseReady',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to notify Supabase ready state: $e');
    }

    // ── Log environment info for crash context ──────────────────────
    try {
      logNavigationBreadcrumb('/splash');
      logActionBreadcrumb('app_start', {
        'env': AppEnvironmentConfig.current.label,
        'device_tier': DeviceTierCache.instance.tier.name,
      });
    } catch (_) {}

    // ── Debug: log resolved AppConfig values ────────────────────────
    debugPrint('🔧 AppConfig SUPABASE_URL: ${AppConfig.supabaseUrl}');
    debugPrint(
      '🔧 AppConfig SUPABASE_ANON_KEY: ${AppConfig.supabaseAnonKey.isNotEmpty ? "SET (length: ${AppConfig.supabaseAnonKey.length})" : "EMPTY"}',
    );
    debugPrint(
      '🔧 AppConfig isSupabaseConfigured: ${AppConfig.isSupabaseConfigured}',
    );
  }
}

/// Provider that tracks core app initialization state.
/// Watches this to know when services (Drift, Firebase, Supabase) are ready.
final appInitProvider = AsyncNotifierProvider<AppInitNotifier, void>(
  AppInitNotifier.new,
);
