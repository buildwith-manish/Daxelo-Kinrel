// lib/core/bootstrap/app_init_provider.dart
//
// DAXELO KINREL — App Initialization Provider
//
// Replaces global mutable state (_globalContainer, _appInitComplete,
// _initCompleter) with a Riverpod AsyncNotifier that tracks
// initialization state in a reactive, testable way.

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
    // ── 1. Initialize Drift database ────────────────────────────────
    try {
      await AppDatabaseService.initialize()
          .timeout(const Duration(seconds: 3));
      if (kDebugMode) debugPrint('✅ Drift database initialized');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Drift database initialization failed or timed out: $e');
    }

    // ── 2. Environment variables loaded at compile time ─────────────
    if (kDebugMode) debugPrint('✅ Environment variables from compile-time --dart-define');

    // ── 3. Initialize Firebase ──────────────────────────────────────
    // Safety net: Firebase was initialized in main() before onBackgroundMessage().
    // If main() init succeeded (normal path), this is a no-op.
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(const Duration(seconds: 3));
        if (kDebugMode) debugPrint('✅ Firebase initialized (safety net)');
      } else {
        if (kDebugMode) debugPrint('✅ Firebase already initialized from main()');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Firebase initialization failed or timed out: $e');
    }

    // ── 4. Initialize Crashlytics ───────────────────────────────────
    try {
      await initCrashlytics();
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Crashlytics initialization failed: $e');
    }

    // ── 5. Register FCM background handler ──────────────────────────
    // Safety net: FCM handler was registered in main() after Firebase init.
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ FCM background handler registration failed: $e');
    }

    // ── 6. Initialize Supabase ──────────────────────────────────────
    bool supabaseReady = false;
    try {
      supabaseReady = await initSupabase().timeout(const Duration(seconds: 3));
      if (kDebugMode) debugPrint(
        '🔧 Supabase initialized: $supabaseReady (kAuthDisabled=$kAuthDisabled)',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Supabase init failed or timed out: $e');
    }

    // ── 6b. Notify Riverpod that Supabase is ready ──────────────────
    try {
      notifySupabaseReady(ref);
      if (kDebugMode) debugPrint(
        '🔧 Notified Riverpod: Supabase ready = $supabaseReady',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Failed to notify Supabase ready state: $e');
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
    if (kDebugMode) debugPrint('🔧 AppConfig SUPABASE_URL: ${AppConfig.supabaseUrl}');
    if (kDebugMode) debugPrint(
      '🔧 AppConfig SUPABASE_ANON_KEY: ${AppConfig.supabaseAnonKey.isNotEmpty ? "SET (length: ${AppConfig.supabaseAnonKey.length})" : "EMPTY"}',
    );
    if (kDebugMode) debugPrint(
      '🔧 AppConfig isSupabaseConfigured: ${AppConfig.isSupabaseConfigured}',
    );
  }
}

/// Provider that tracks core app initialization state.
/// Watches this to know when services (Drift, Firebase, Supabase) are ready.
final appInitProvider = AsyncNotifierProvider<AppInitNotifier, void>(
  AppInitNotifier.new,
);
