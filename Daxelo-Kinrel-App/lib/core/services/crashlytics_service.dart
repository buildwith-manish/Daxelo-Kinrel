// lib/core/services/crashlytics_service.dart
//
// DAXELO KINREL — Firebase Crashlytics Service (P3-F1 Enhanced)
//
// Centralizes all crash reporting and error logging.
// Only initializes on Android/iOS — gracefully skips on web/desktop.
// If Firebase is not configured, logs a warning and the app still runs.
//
// P3-F1 Enhancements:
// - runZonedGuarded wrapper for catching async errors
// - Riverpod state capture at crash time for context
// - Environment tagging (dev/staging/prod) for separated crash reports
// - Breadcrumb logging for navigation + user actions

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../firebase_options.dart';
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
/// Call this early in `main()` before `runApp()`.
/// - Only runs on Android/iOS (Firebase Crashlytics doesn't support web/desktop)
/// - If Firebase is not configured (missing google-services.json), logs a warning
/// - The app always runs regardless — crash reporting is optional
Future<void> initCrashlytics() async {
  // Only init Firebase on mobile platforms
  if (!Platform.isAndroid && !Platform.isIOS) {
    debugPrint('⏭️ Firebase Crashlytics skipped — not a mobile platform');
    return;
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
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
      // Capture Riverpod state at crash time for context
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
    // Dev: disabled (noise), Staging/Prod: enabled
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
    debugPrint('   To enable crash reporting:');
    debugPrint('   1. Run: flutterfire configure --project=daxelo-kinrel');
    debugPrint('   2. Ensure google-services.json is in android/app/');
    debugPrint('   3. Ensure GoogleService-Info.plist is in ios/Runner/');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// runZonedGuarded Wrapper
// ═══════════════════════════════════════════════════════════════════════

/// Run the app inside a guarded zone that catches all uncaught async errors.
///
/// This is the P3-F1 way to start the app:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   // ... init code ...
///   runWithCrashGuard(() => runApp(KinrelApp()));
/// }
/// ```
///
/// Catches:
/// - Uncaught async errors in zones (Future.then, Timer, etc.)
/// - Errors in event handlers that aren't wrapped in try/catch
/// - Microtask errors
void runWithCrashGuard(void Function() callback) {
  runZonedGuarded<Future<void>>(
    () async {
      callback();
    },
    (error, stack) {
      // Attach state context before recording
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
///
/// Call this from providers when state changes significantly.
/// The last captured state is attached to crash reports.
///
/// Example:
/// ```dart
/// ref.listen(familyListProvider, (_, next) {
///   captureRiverpodState('familyList', {
///     'count': next.value?.length ?? 0,
///     'isLoading': next.isLoading,
///     'hasError': next.hasError,
///   });
/// });
/// ```
void captureRiverpodState(String key, Map<String, dynamic> state) {
  _lastKnownState[key] = state;
  // Keep only the last 10 state snapshots
  if (_lastKnownState.length > 10) {
    _lastKnownState.remove(_lastKnownState.keys.first);
  }
}

/// Attach captured Riverpod state + breadcrumbs to a Crashlytics report.
void _attachStateContext(String errorContext) {
  if (!_firebaseInitialized) return;

  try {
    // Attach environment
    FirebaseCrashlytics.instance.setCustomKey(
      'crash_environment',
      AppEnvironmentConfig.current.label,
    );

    // Attach last known state as a structured log
    if (_lastKnownState.isNotEmpty) {
      final stateSummary = _lastKnownState.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('; ');
      FirebaseCrashlytics.instance.log('Riverpod state: $stateSummary');
    }

    // Attach navigation breadcrumbs
    if (_navigationBreadcrumbs.isNotEmpty) {
      FirebaseCrashlytics.instance.log(
        'Navigation: ${_navigationBreadcrumbs.take(10).join(' → ')}',
      );
    }

    // Attach action breadcrumbs
    if (_actionBreadcrumbs.isNotEmpty) {
      FirebaseCrashlytics.instance.log(
        'Recent actions: ${_actionBreadcrumbs.take(5).join(', ')}',
      );
    }

    // Attach state keys
    FirebaseCrashlytics.instance.setCustomKey(
      'active_providers',
      _lastKnownState.keys.join(','),
    );
    FirebaseCrashlytics.instance.setCustomKey(
      'nav_depth',
      _navigationBreadcrumbs.length,
    );
  } catch (_) {
    // Never let state capture crash the app
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Breadcrumb Logging
// ═══════════════════════════════════════════════════════════════════════

/// Log a navigation breadcrumb for crash context.
///
/// Call this in GoRouter redirect or screen initState:
/// ```dart
/// logNavigationBreadcrumb('/family/${familyId}');
/// ```
void logNavigationBreadcrumb(String route) {
  _navigationBreadcrumbs.add(route);
  // Keep only last 20
  if (_navigationBreadcrumbs.length > 20) {
    _navigationBreadcrumbs.removeAt(0);
  }
  // Also log to Crashlytics as a breadcrumb
  if (_firebaseInitialized) {
    FirebaseCrashlytics.instance.log('Navigation → $route');
  }
}

/// Log a user action breadcrumb for crash context.
///
/// Call this for significant user actions:
/// ```dart
/// logActionBreadcrumb('add_member', {'familyId': familyId});
/// ```
void logActionBreadcrumb(String action, [Map<String, dynamic>? params]) {
  final entry = params != null
      ? '$action(${params.entries.map((e) => '${e.key}=${e.value}').join(',')})'
      : action;
  _actionBreadcrumbs.add(entry);
  // Keep only last 20
  if (_actionBreadcrumbs.length > 20) {
    _actionBreadcrumbs.removeAt(0);
  }
  // Also log to Crashlytics as a breadcrumb
  if (_firebaseInitialized) {
    FirebaseCrashlytics.instance.log('Action → $entry');
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Error Logging Helpers
// ═══════════════════════════════════════════════════════════════════════

/// Log a non-fatal error to Crashlytics.
///
/// Use this for caught exceptions that should be tracked
/// but don't crash the app.
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
///
/// Call this after sign-in to associate crash reports with users.
void setUserIdentifier(String userId) {
  if (!_firebaseInitialized) return;
  FirebaseCrashlytics.instance.setUserIdentifier(userId);
}

/// Set a custom key-value pair for Crashlytics reports.
///
/// Useful for adding context (e.g., selected family, current screen).
void setCustomKey(String key, dynamic value) {
  if (!_firebaseInitialized) return;
  FirebaseCrashlytics.instance.setCustomKey(key, value);
}

/// Force-send all pending crash reports.
///
/// Call when the user triggers a "report bug" action or
/// before the app is about to terminate gracefully.
Future<void> sendUnsentReports() async {
  if (!_firebaseInitialized) return;
  try {
    await FirebaseCrashlytics.instance.sendUnsentReports();
  } catch (_) {
    // Never let this crash the app
  }
}
