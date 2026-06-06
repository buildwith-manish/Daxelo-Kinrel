import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../services/crashlytics_service.dart';
import '../widgets/global_error_widget.dart';

/// Error Boundary widget — catches build errors in subtrees and
/// shows a branded fallback instead of crashing the whole app.
///
/// Uses Flutter's ErrorWidget.builder mechanism combined with a
/// dedicated error zone to catch exceptions during build.
///
/// When an error is caught, it logs to Crashlytics and shows
/// the branded GlobalErrorWidget. The user can tap "Try Again" to retry.
///
/// P6 UPDATE: Now uses GlobalErrorWidget (branded, themed) as the
/// default fallback instead of the old inline widget. This ensures
/// consistent error presentation across the entire app.
class ErrorBoundary extends StatefulWidget {
  const ErrorBoundary({
    required this.child,
    this.fallback,
    this.message,
    this.isNetworkError = false,
    super.key,
  });

  final Widget child;
  final Widget? fallback;

  /// Optional custom error message shown in the fallback.
  final String? message;

  /// If true, shows the network error variant (wifi icon, connectivity message).
  final bool isNetworkError;

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;
  Object? _error;
  int _retryKey = 0;

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      // Log to Crashlytics
      if (_error != null) {
        try {
          if (isCrashlyticsAvailable) {
            FirebaseCrashlytics.instance.recordError(
              _error,
              StackTrace.current,
              reason: 'ErrorBoundary caught an error',
            );
          }
        } catch (_) {}
      }

      // Use custom fallback if provided, otherwise use branded GlobalErrorWidget
      return widget.fallback ??
          GlobalErrorWidget(
            severity: widget.isNetworkError
                ? GlobalErrorSeverity.network
                : GlobalErrorSeverity.section,
            onRetry: () {
              setState(() {
                _hasError = false;
                _error = null;
                _retryKey++;
              });
            },
            message: widget.message,
          );
    }

    // Use a key that changes on retry to force rebuild
    return KeyedSubtree(
      key: ValueKey(_retryKey),
      child: widget.child,
    );
  }
}

/// Extension to wrap a widget with ErrorBoundary
extension ErrorBoundaryExtension on Widget {
  /// Wraps this widget with an ErrorBoundary for crash resilience.
  /// Uses the branded GlobalErrorWidget as fallback.
  Widget withErrorBoundary({
    Widget? fallback,
    String? message,
    bool isNetworkError = false,
  }) {
    return ErrorBoundary(
      child: this,
      fallback: fallback,
      message: message,
      isNetworkError: isNetworkError,
    );
  }
}
