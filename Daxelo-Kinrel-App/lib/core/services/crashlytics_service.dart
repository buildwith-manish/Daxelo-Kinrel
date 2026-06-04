// lib/core/services/crashlytics_service.dart
//
// DAXELO KINREL — Firebase Crashlytics Service (P3-F1 Enhanced)
//
// Centralizes all crash reporting and error logging.
// Only initializes on Android/iOS — gracefully skips on web/desktop.
// If Firebase is not configured, logs a warning and the app still runs.
//
// IMPORTANT: Firebase.initializeApp() MUST be called BEFORE this
// service's initCrashlytics() method. The main.dart file handles
// Firebase init at the top of main().

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../config/app_environment.dart';

/// Whether Firebase has been successfully initialized.
bool _firebaseInitialized = false;

/// Whether crash reporting is available on this platform.
bool get isCrashlyticsAvailable => _firebaseInitialized;

/// Last known Riverpod state snapshot (captured before crash).
/// Populated by [captureRiverpodState].
Map<String, dynamic> _lastKnownState = {};

/// Navigation breadcrumb trail (last 20 routes).
final List<String> _navigationBreadcrumbs = [];

/// User action breadcrumb trail (last 20 actions).
final List<String> _actionBreadcrumbs = [];

// ═══════════════════════════════════════════════════════════════════════
// Initialization
// ═══════════════════════════════════════════════════════════════════════

/// Initialize Firebase Crashlytics.
///
/// IMPORTANT: Firebase.initializeApp() MUST be called BEFORE this method.
/// In main.dart, Firebase.initializeApp() is called at the top of main().
///
/// This method configures Crashlytics error handlers and sets up
/// environment tagging. It does NOT call Firebase.initializeApp() again.
Future<void> initCrashlytics() async {
  // Only init on mobile platforms
  if (!Platform.isAndroid && !Platform.isIOS) {
    debugPrint('⏭️ Firebase Crashlytics skipped — not a mobile platform');
    return;
  }

  try {
    // Check if Firebase is already initialized (it should be, from main.dart)
    try {
      // If Firebase.apps is empty, Firebase hasn't been initialized yet
      if (Firebase.apps.isEmpty) {
        debugPrint('⚠️ Firebase not initialized before initCrashlytics() — skipping');
        return;
      }
    } catch (e) {
      debugPrint('⚠️ Firebase apps check failed: $e');
      return;
    }

    _firebaseInitialized = true;

    // ── Tag with environment ────────────────────────────────────────
    final env = AppEnvironmentConfig.current;
    await FirebaseCrashlytics.instance.setCustomKey('environment', env.label);
    await FirebaseCrashlytics.instance.setCustomKey(
      'app_version',
      '1.0.0',
    );

    // ── Pass all uncaught Flutter framework errors to Crashlytics ───
    FlutterError.onError = (details) {
      _attachStateContext(details.exception.toString());
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };

    // ── Pass all uncaught async errors outside Flutter to Crashlytics ─
    PlatformDispatcher.instance.onError = (error, stack) {
      _attachStateContext(error.toString());
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // ── Enable collection based on environment ──────────────────────
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      env.shouldReportCrashes,
    );

    debugPrint(
      '✅ Firebase Crashlytics initialized (env: ${env.label}, '
      'collection: ${env.shouldReportCrashes})',
    );
  } catch (e) {
    // Firebase not configured — app still works, just no crash reporting
    debugPrint('⚠️ Firebase Crashlytics not initialized: $e');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// runZonedGuarded Wrapper (DEPRECATED — use runZonedGuarded directly)
// ═══════════════════════════════════════════════════════════════════════

/// Run the app inside a guarded zone that catches all uncaught async errors.
///
/// DEPRECATED: main.dart now uses runZonedGuarded directly for better
/// control over the initialization order. This function is kept for
/// backward compatibility but should not be used in new code.
void runWithCrashGuard(void Function() callback) {
  runZonedGuarded<Future<void>>(
    () async {
      callback();
    },
    (error, stack) {
      _attachStateContext(error.toString());

      if (_firebaseInitialized) {
        FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          reason: 'Uncaught async error in guarded zone',
          fatal: true,
        );
      } else {
        debugPrint('🔴 [Uncaught async error]: $error');
        debugPrint('   Stack: $stack');
      }
    },
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Riverpod State Capture
// ═══════════════════════════════════════════════════════════════════════

/// Capture current Riverpod state for crash context.
void captureRiverpodState(String key, Map<String, dynamic> state) {
  _lastKnownState[key] = state;
  if (_lastKnownState.length > 10) {
    _lastKnownState.remove(_lastKnownState.keys.first);
  }
}

/// Attach captured Riverpod state + breadcrumbs to a Crashlytics report.
void _attachStateContext(String errorContext) {
  if (!_firebaseInitialized) return;

  try {
    FirebaseCrashlytics.instance.setCustomKey(
      'crash_environment',
      AppEnvironmentConfig.current.label,
    );

    if (_lastKnownState.isNotEmpty) {
      final stateSummary = _lastKnownState.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('; ');
      FirebaseCrashlytics.instance.log('Riverpod state: $stateSummary');
    }

    if (_navigationBreadcrumbs.isNotEmpty) {
      FirebaseCrashlytics.instance.log(
        'Navigation: ${_navigationBreadcrumbs.take(10).join(' → ')}',
      );
    }

    if (_actionBreadcrumbs.isNotEmpty) {
      FirebaseCrashlytics.instance.log(
        'Recent actions: ${_actionBreadcrumbs.take(5).join(', ')}',
      );
    }

    FirebaseCrashlytics.instance.setCustomKey(
      'active_providers',
      _lastKnownState.keys.join(','),
    );
    FirebaseCrashlytics.instance.setCustomKey(
      'nav_depth',
      _navigationBreadcrumbs.length,
    );
  } catch (_) {}
}

// ═══════════════════════════════════════════════════════════════════════
// Breadcrumb Logging
// ═══════════════════════════════════════════════════════════════════════

/// Log a navigation breadcrumb for crash context.
void logNavigationBreadcrumb(String route) {
  _navigationBreadcrumbs.add(route);
  if (_navigationBreadcrumbs.length > 20) {
    _navigationBreadcrumbs.removeAt(0);
  }
  if (_firebaseInitialized) {
    FirebaseCrashlytics.instance.log('Navigation → $route');
  }
}

/// Log a user action breadcrumb for crash context.
void logActionBreadcrumb(String action, [Map<String, dynamic>? params]) {
  final entry = params != null
      ? '$action(${params.entries.map((e) => '${e.key}=${e.value}').join(',')})'
      : action;
  _actionBreadcrumbs.add(entry);
  if (_actionBreadcrumbs.length > 20) {
    _actionBreadcrumbs.removeAt(0);
  }
  if (_firebaseInitialized) {
    FirebaseCrashlytics.instance.log('Action → $entry');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Error Logging Helpers
// ═══════════════════════════════════════════════════════════════════════

/// Log a non-fatal error to Crashlytics.
void logError(
  dynamic error,
  StackTrace? stack, {
  String? reason,
  bool fatal = false,
}) {
  if (!_firebaseInitialized) {
    debugPrint('🔴 [Crashlytics not init] Error: $error');
    return;
  }

  if (reason != null) {
    FirebaseCrashlytics.instance.log(reason);
  }

  FirebaseCrashlytics.instance.recordError(
    error,
    stack,
    reason: reason,
    fatal: fatal,
  );
}

/// Log a custom message to Crashlytics (appears in crash logs).
void log(String message) {
  if (!_firebaseInitialized) return;
  FirebaseCrashlytics.instance.log(message);
}

/// Set a user identifier for Crashlytics reports.
void setUserIdentifier(String userId) {
  if (!_firebaseInitialized) return;
  FirebaseCrashlytics.instance.setUserIdentifier(userId);
}

/// Set a custom key-value pair for Crashlytics reports.
void setCustomKey(String key, dynamic value) {
  if (!_firebaseInitialized) return;
  FirebaseCrashlytics.instance.setCustomKey(key, value);
}

/// Force-send all pending crash reports.
Future<void> sendUnsentReports() async {
  if (!_firebaseInitialized) return;
  try {
    await FirebaseCrashlytics.instance.sendUnsentReports();
  } catch (_) {}
}
