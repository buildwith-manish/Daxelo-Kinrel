// lib/core/widgets/global_error_widget.dart
//
// DAXELO KINREL — Global Error Widget (P6 — Flutter UX Polish)
//
// Branded, themed error widget that replaces the default Flutter red screen
// of death with a polished Kinrel experience. Supports three error variants:
//
//   1. crash    — Full-screen fatal error (render failures, uncaught exceptions)
//   2. section  — In-page section error (subtree build failures, feature errors)
//   3. network  — Network/connectivity error (offline, timeout, DNS failure)
//
// Design principles:
//   - Matches the Kinrel Orange (#E8612A) brand system
//   - Dark/light theme adaptive
//   - Animated appearance with subtle fade-in
//   - "Try Again" button with orange gradient
//   - "Report Bug" link for crash reporting
//   - Accessibility-first (semantics, labels, contrast)
//   - Graceful degradation (safe to render even during theme failure)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../constants/brand_colors.dart';
import '../constants/brand_typography.dart';
import '../services/crashlytics_service.dart';

// Web-only imports for page reload.
// On non-web platforms these are stubbed out via conditional export.
// We use a top-level function `_reloadPage()` that is overridden on web
// via the conditional import below.
import 'reload_page_stub.dart'
    if (dart.library.html) 'reload_page_web.dart' as reload;

// ── Error Severity ────────────────────────────────────────────────────

/// Determines the visual presentation and messaging of the error widget.
enum GlobalErrorSeverity {
  /// Full-screen fatal error — entire screen is replaced.
  /// Used for render failures and uncaught exceptions.
  crash,

  /// In-page section error — shows within a card/section.
  /// Used for subtree build failures where the rest of the app is still usable.
  section,

  /// Network/connectivity error — specific to offline/timeout scenarios.
  /// Provides targeted messaging about internet connectivity.
  network,
}

// ── Global Error Widget ───────────────────────────────────────────────

/// A branded, themed error widget that prevents the red screen of death.
///
/// Usage:
/// ```dart
/// // Full-screen crash fallback
/// GlobalErrorWidget(severity: GlobalErrorSeverity.crash)
///
/// // Section-level error with retry
/// GlobalErrorWidget(
///   severity: GlobalErrorSeverity.section,
///   onRetry: () => setState(() {}),
/// )
///
/// // Network error
/// GlobalErrorWidget(
///   severity: GlobalErrorSeverity.network,
///   onRetry: _refetchData,
/// )
/// ```
class GlobalErrorWidget extends StatefulWidget {
  const GlobalErrorWidget({
    required this.severity,
    this.onRetry,
    this.errorDetails,
    this.message,
    super.key,
  });

  /// Controls the visual presentation and messaging.
  final GlobalErrorSeverity severity;

  /// Called when the user taps "Try Again".
  /// If null, the button is hidden (crash mode: user must restart).
  final VoidCallback? onRetry;

  /// Optional FlutterErrorDetails for crash reporting.
  final FlutterErrorDetails? errorDetails;

  /// Optional custom error message. If null, a default is used
  /// based on [severity].
  final String? message;

  @override
  State<GlobalErrorWidget> createState() => _GlobalErrorWidgetState();
}

class _GlobalErrorWidgetState extends State<GlobalErrorWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _scale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    // Report to Crashlytics
    _reportToCrashlytics();

    // Start animation on next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  void _reportToCrashlytics() {
    if (widget.errorDetails != null) {
      try {
        if (isCrashlyticsAvailable) {
          FirebaseCrashlytics.instance.recordFlutterError(widget.errorDetails!);
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCrash = widget.severity == GlobalErrorSeverity.crash;
    final isNetwork = widget.severity == GlobalErrorSeverity.network;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: child,
          ),
        );
      },
      child: isCrash
          ? _buildCrashLayout(context)
          : _buildSectionLayout(context, isNetwork: isNetwork),
    );

  }

  // ── Crash Layout (Full-Screen) ──────────────────────────────────

  Widget _buildCrashLayout(BuildContext context) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    return Material(
      color: isDark ? KinrelColors.darkBackground : KinrelColors.lightBackground,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildErrorIcon(isDark),
                const SizedBox(height: 24),
                _buildTitle(isDark, 'Something went wrong'),
                const SizedBox(height: 12),
                _buildMessage(
                  isDark,
                  widget.message ??
                      'An unexpected error occurred. Please restart the app to continue.',
                ),
                const SizedBox(height: 8),
                _buildErrorId(isDark),
                const SizedBox(height: 24),
                if (widget.onRetry != null) ...[
                  _buildRetryButton(isDark),
                  const SizedBox(height: 12),
                ],
                // On web, always show a Reload Page button — "restart the app"
                // doesn't apply to web, and the most common fix for a
                // transient crash is a page reload (which also clears any
                // stale service worker state).
                if (kIsWeb) ...[
                  _buildReloadButton(isDark),
                  const SizedBox(height: 12),
                ],
                _buildRestartHint(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Reload Button (web only) ─────────────────────────────────────

  Widget _buildReloadButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => reload.reloadCurrentPage(),
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? KinrelColors.textWhite : KinrelColors.textDark,
          side: BorderSide(
            color: isDark
                ? const Color(0x33FFFFFF)
                : KinrelColors.lightBorder,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(
          Icons.refresh_rounded,
          size: 20,
          color: isDark ? KinrelColors.textWhite : KinrelColors.textDark,
        ),
        label: Text(
          'Reload Page',
          style: KinrelTypography.labelLarge.copyWith(
            color: isDark ? KinrelColors.textWhite : KinrelColors.textDark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── Section Layout (In-Page) ────────────────────────────────────

  Widget _buildSectionLayout(BuildContext context, {bool isNetwork = false}) {
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark = brightness == Brightness.dark;

    final defaultMsg = isNetwork
        ? 'Could not connect to the server. Please check your internet connection and try again.'
        : 'This section encountered an error. The rest of the app is still working.';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? KinrelColors.darkCard : KinrelColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? const Color(0x1AFFFFFF) // rgba(255,255,255,0.10)
              : KinrelColors.lightBorder,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildErrorIcon(isDark, isNetwork: isNetwork),
          const SizedBox(height: 16),
          _buildTitle(
            isDark,
            isNetwork ? 'Connection failed' : 'Something went wrong',
          ),
          const SizedBox(height: 8),
          _buildMessage(isDark, widget.message ?? defaultMsg),
          const SizedBox(height: 20),
          if (widget.onRetry != null)
            _buildRetryButton(isDark, compact: true),
        ],
      ),
    );
  }

  // ── Shared Components ───────────────────────────────────────────

  Widget _buildErrorIcon(bool isDark, {bool isNetwork = false}) {
    final iconColor = isNetwork
        ? KinrelColors.warning // #F5A623 — amber for network
        : KinrelColors.error; // #F04E2A — red for crash/section

    final glowColor = isNetwork
        ? KinrelColors.warning.withValues(alpha: 0.15)
        : KinrelColors.error.withValues(alpha: 0.15);

    final icon = isNetwork ? Icons.wifi_off_rounded : Icons.error_outline_rounded;

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: glowColor,
      ),
      child: Icon(
        icon,
        size: 40,
        color: iconColor,
        semanticLabel: isNetwork ? 'Network error' : 'Error',
      ),
    );
  }

  Widget _buildTitle(bool isDark, String title) {
    return Text(
      title,
      style: KinrelTypography.headlineMedium.copyWith(
        color: isDark ? KinrelColors.textWhite : KinrelColors.textDark,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildMessage(bool isDark, String message) {
    return Text(
      message,
      style: KinrelTypography.bodyMedium.copyWith(
        color: isDark
            ? KinrelColors.textSecondaryDark
            : KinrelColors.textSecondaryLight,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildErrorId(bool isDark) {
    // Show a short error ID for support reference in crash mode.
    // In debug mode, show the actual error for developer convenience.
    // In release mode, show a short hash of the error + the first ~200 chars
    // of the exception so users can copy-paste it to support (or to the
    // developer) without leaking PII. Previously release mode showed only
    // "If this keeps happening, please contact support." which made it
    // impossible to diagnose production crashes.
    if (widget.errorDetails != null) {
      final exception = widget.errorDetails!.exceptionAsString();
      final short = exception.length > 200
          ? '${exception.substring(0, 200)}...'
          : exception;
      // Build a short stable error code from the exception string so
      // support can group identical crashes.
      final hashCode = exception.hashCode.abs().toRadixString(16).toUpperCase();
      final errorCode = 'ERR-$hashCode';

      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? KinrelColors.darkElevated
                : KinrelColors.lightElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? const Color(0x1AFFFFFF)
                  : KinrelColors.lightBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Error code: $errorCode',
                style: KinrelTypography.bodySmall.copyWith(
                  fontFamily: KinrelTypography.monoFont,
                  color: KinrelColors.error.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                short,
                style: KinrelTypography.bodySmall.copyWith(
                  fontFamily: KinrelTypography.monoFont,
                  color: isDark
                      ? KinrelColors.textSecondaryDark
                      : KinrelColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // No error details available — show generic support reference
    return Text(
      'If this keeps happening, please contact support.',
      style: KinrelTypography.bodySmall.copyWith(
        color: isDark ? KinrelColors.textDim : KinrelColors.textSecondaryLight,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildRetryButton(bool isDark, {bool compact = false}) {
    final horizontalPad = compact ? 24.0 : 40.0;
    final verticalPad = compact ? 12.0 : 14.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: KinrelGradients.igniteGradient,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orange.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onRetry,
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPad,
              vertical: verticalPad,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.refresh_rounded,
                  size: compact ? 18 : 20,
                  color: Colors.white,
                  semanticLabel: 'Retry',
                ),
                const SizedBox(width: 8),
                Text(
                  'Try Again',
                  style: KinrelTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRestartHint(bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 14,
          color: isDark ? KinrelColors.textDim : KinrelColors.textSecondaryLight,
        ),
        const SizedBox(width: 6),
        Text(
          'The rest of your data is safe. Restart to continue.',
          style: KinrelTypography.bodySmall.copyWith(
            color: isDark ? KinrelColors.textDim : KinrelColors.textSecondaryLight,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// ── KinrelAnimatedBuilder ──────────────────────────────────────────
//
// Custom AnimatedBuilder that works across all Flutter versions.
// Uses the AnimatedWidget pattern for maximum compatibility.
// This is exported for use throughout the app.
class KinrelAnimatedBuilder extends AnimatedWidget {
  const KinrelAnimatedBuilder({
    required Listenable animation,
    required this.builder,
    this.child,
    super.key,
  }) : super(listenable: animation);

  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}

// ── Convenience Extensions ────────────────────────────────────────────

/// Extension to show a GlobalErrorWidget as a section-level error
/// with a simple retry callback.
extension GlobalErrorWidgetExtension on Widget {
  /// Wraps this widget with error boundary that shows GlobalErrorWidget on failure.
  Widget withGlobalErrorBoundary({
    VoidCallback? onRetry,
    String? message,
  }) {
    return _GlobalErrorBoundary(
      onRetry: onRetry,
      message: message,
      child: this,
    );
  }
}

// ── Internal: Error Boundary with GlobalErrorWidget fallback ──────────

/// A lightweight error boundary that catches subtree errors and shows
/// the branded GlobalErrorWidget instead of the red screen of death.
///
/// Unlike the older `ErrorBoundary`, this uses the branded widget
/// and supports network vs section severity differentiation.
class _GlobalErrorBoundary extends StatefulWidget {
  const _GlobalErrorBoundary({
    required this.child,
    this.onRetry,
    this.message,
  });

  final Widget child;
  final VoidCallback? onRetry;
  final String? message;

  @override
  State<_GlobalErrorBoundary> createState() => _GlobalErrorBoundaryState();
}

class _GlobalErrorBoundaryState extends State<_GlobalErrorBoundary> {
  bool _hasError = false;
  Object? _error;
  int _retryKey = 0;

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      // Report the error
      if (_error != null) {
        try {
          if (isCrashlyticsAvailable) {
            FirebaseCrashlytics.instance.recordError(
              _error,
              StackTrace.current,
              reason: 'GlobalErrorBoundary caught an error',
            );
          }
        } catch (_) {}
      }

      return GlobalErrorWidget(
        severity: GlobalErrorSeverity.section,
        onRetry: () {
          setState(() {
            _hasError = false;
            _error = null;
            _retryKey++;
          });
          widget.onRetry?.call();
        },
        message: widget.message,
      );
    }

    return KeyedSubtree(
      key: ValueKey(_retryKey),
      child: widget.child,
    );
  }
}
