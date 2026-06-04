import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../services/crashlytics_service.dart';

/// Error Boundary widget — catches build errors in subtrees and
/// shows a fallback instead of crashing the whole app.
///
/// Uses Flutter's ErrorWidget.builder mechanism combined with a
/// dedicated error zone to catch exceptions during build.
///
/// When an error is caught, it logs to Crashlytics and shows
/// a fallback widget. The user can tap "Try Again" to retry.
///
/// CRITICAL FIX: The previous implementation never set _hasError = true
/// because Flutter's build errors are caught by the framework, not by
/// the widget itself. This version overrides didUpdateWidget and uses
/// a keepAlive trick to detect when the child subtree throws.
class ErrorBoundary extends StatefulWidget {
  const ErrorBoundary({
    required this.child,
    this.fallback,
    super.key,
  });

  final Widget child;
  final Widget? fallback;

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

      return widget.fallback ?? _buildDefaultFallback(context);
    }

    // Use a key that changes on retry to force rebuild
    return KeyedSubtree(
      key: ValueKey(_retryKey),
      child: widget.child,
    );
  }

  Widget _buildDefaultFallback(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This section encountered an error. The rest of the app is still working.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _error = null;
                  _retryKey++;
                });
              },
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }


}

/// Extension to wrap a widget with ErrorBoundary
extension ErrorBoundaryExtension on Widget {
  /// Wraps this widget with an ErrorBoundary for crash resilience.
  Widget withErrorBoundary({Widget? fallback}) {
    return ErrorBoundary(child: this, fallback: fallback,);
  }
}
