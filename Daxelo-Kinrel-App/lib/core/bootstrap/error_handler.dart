// lib/core/bootstrap/error_handler.dart
//
// DAXELO KINREL — Error Handler Bootstrap
//
// Sets up global error handlers to prevent red screen of death
// and report errors to Crashlytics when available.

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../services/crashlytics_service.dart';
import '../widgets/global_error_widget.dart';

class ErrorHandler {
  /// Set up all global error handlers.
  /// Must be called after WidgetsFlutterBinding.ensureInitialized().
  static void setup() {
    // ── P6: Global error widget — branded, themed, prevents red screen of death ──
    ErrorWidget.builder = (FlutterErrorDetails details) {
      try {
        if (isCrashlyticsAvailable) {
          FirebaseCrashlytics.instance.recordFlutterError(details);
        }
      } catch (_) {}
      return GlobalErrorWidget(
        severity: GlobalErrorSeverity.crash,
        errorDetails: details,
      );
    };

    // ── P6: Flutter framework error handler ─────────────────────────────
    // Catches errors that don't reach the widget tree (e.g., image decoding,
    // layout overflow in release mode). Reports to Crashlytics and logs.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      // Forward to Crashlytics
      try {
        if (isCrashlyticsAvailable) {
          FirebaseCrashlytics.instance.recordFlutterError(details);
        }
      } catch (_) {}
      // Call original handler (shows red bar in debug, etc.)
      originalOnError?.call(details);
      // In release mode, also log to console
      if (kReleaseMode) {
        debugPrint('🔴 FlutterError: ${details.exceptionAsString()}');
      }
    };

    // ── P6: Platform-level error handler ────────────────────────────────
    // Catches errors from async callbacks, isolates, and platform channels
    // that are outside the Flutter framework's error zone.
    PlatformDispatcher.instance.onError = (error, stack) {
      try {
        if (isCrashlyticsAvailable) {
          FirebaseCrashlytics.instance.recordError(error, stack);
        }
      } catch (_) {}
      debugPrint('🔴 PlatformDispatcher error: $error');
      return true; // Handled — prevents default error printing
    };
  }
}
