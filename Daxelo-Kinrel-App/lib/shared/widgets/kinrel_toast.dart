// lib/shared/widgets/kinrel_toast.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  KINREL TOAST — branded, animated, haptic-enhanced toasts            │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// Bare SnackBars are functional but inconsistent. Every screen in the
// app constructs SnackBars differently: different colors, different
// durations, different behavior (floating vs fixed). This makes the
// app feel like 20 different apps stitched together.
//
// Billion-dollar apps (Slack, Linear, Notion, Cash App) have ONE toast
// style that's consistent everywhere. It slides in from the top or
// bottom, has a brand-colored icon, a clear message, an optional action,
// and auto-dismisses after a duration calibrated to the message length.
//
// This service gives the whole app a single toast vocabulary:
//   • success  — green check, 2.5s, success haptic
//   • error    — red X, 4s (longer so the user can read), error haptic
//   • warning  — amber !, 3s, warning haptic
//   • info     — brand orange dot, 2.5s, no haptic (info is neutral)
//
// PSYCHOLOGICAL PRINCIPLE: CONSISTENCY + PROCESSING FLUENCY
// ─────────────────────────────────────────────────────────────────────
//   • Consistency: the user learns one toast language. After 3 toasts
//     they know green = good, red = bad, no need to read the icon.
//   • Processing Fluency: a familiar layout is processed faster, so
//     the message lands sooner.
//
// PERFORMANCE
// ───────────
//   • Uses ScaffoldMessenger under the hood (no new overlay system).
//   • Animated via flutter_animate (slide + fade), GPU-composited.
//   • Haptics are fire-and-forget (unawaited).
//   • SnackBarBehavior.floating so it doesn't cover the bottom nav.
//
// USAGE
// ─────
//   // Replace this:
//   ScaffoldMessenger.of(context).showSnackBar(
//     SnackBar(content: Text('Saved!'), backgroundColor: Colors.green),
//   );
//
//   // With this:
//   KinrelToast.show(context, 'Saved!', type: KinrelToastType.success);
//
//   // With an action:
//   KinrelToast.show(
//     context,
//     'Welcome to the family, Ravi!',
//     type: KinrelToastType.success,
//     actionLabel: 'UNDO',
//     onAction: () => _undo(),
//   );

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';
import '../../core/services/haptic_service.dart';

/// The type of toast to show. Determines color, icon, duration, and haptic.
enum KinrelToastType {
  /// Green check icon. 2.5s duration. Fires [HapticService.success].
  success,

  /// Red X icon. 4s duration (longer so the user can read the error).
  /// Fires [HapticService.error].
  error,

  /// Amber ! icon. 3s duration. Fires [HapticService.warning].
  warning,

  /// Brand-orange dot icon. 2.5s duration. No haptic (info is neutral —
  /// the user didn't do anything, so no feedback is needed).
  info,
}

/// Shows branded, animated, haptic-enhanced toasts.
///
/// Use [KinrelToast.show] instead of `ScaffoldMessenger.of(context).showSnackBar`
/// for consistent toast UX across the app.
class KinrelToast {
  KinrelToast._();

  /// Shows a toast. If a toast is already showing, it's dismissed first
  /// (so the user sees the latest message, not a queue).
  static void show(
    BuildContext context,
    String message, {
    KinrelToastType type = KinrelToastType.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    // Clear any existing toast so the new one shows immediately.
    messenger.clearSnackBars();

    // Fire the haptic for this toast type (fire-and-forget).
    switch (type) {
      case KinrelToastType.success:
        HapticService.success();
        break;
      case KinrelToastType.error:
        HapticService.error();
        break;
      case KinrelToastType.warning:
        HapticService.warning();
        break;
      case KinrelToastType.info:
        // No haptic for info — the user didn't trigger an action.
        break;
    }

    final config = _ToastConfig.forType(type);
    final effectiveDuration = duration ?? config.duration;

    messenger.showSnackBar(
      SnackBar(
        content: _ToastContent(
          message: message,
          icon: config.icon,
          iconColor: config.iconColor,
          backgroundColor: config.backgroundColor,
        ),
        duration: effectiveDuration,
        backgroundColor: config.backgroundColor,
        behavior: SnackBarBehavior.floating,
        elevation: 0, // we draw our own shadow via the content container
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        margin: const EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 90, // sit above the bottom nav
        ),
        padding: EdgeInsets.zero, // content handles its own padding
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  /// Convenience methods for the four types.
  static void success(BuildContext context, String message,
          {String? actionLabel, VoidCallback? onAction}) =>
      show(context, message,
          type: KinrelToastType.success,
          actionLabel: actionLabel,
          onAction: onAction);

  static void error(BuildContext context, String message) =>
      show(context, message, type: KinrelToastType.error);

  static void warning(BuildContext context, String message) =>
      show(context, message, type: KinrelToastType.warning);

  static void info(BuildContext context, String message) =>
      show(context, message, type: KinrelToastType.info);
}

/// Per-type configuration: icon, colors, duration.
class _ToastConfig {

  const _ToastConfig({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.duration,
  });
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Duration duration;

  static _ToastConfig forType(KinrelToastType type) {
    switch (type) {
      case KinrelToastType.success:
        return const _ToastConfig(
          icon: Icons.check_circle_rounded,
          iconColor: Color(0xFF4ADE80), // green-400
          backgroundColor: Color(0xFF1A2E1F), // dark green tint
          duration: const Duration(milliseconds: 2500),
        );
      case KinrelToastType.error:
        return const _ToastConfig(
          icon: Icons.error_outline_rounded,
          iconColor: Color(0xFFF87171), // red-400
          backgroundColor: Color(0xFF2E1A1A), // dark red tint
          duration: const Duration(milliseconds: 4000),
        );
      case KinrelToastType.warning:
        return const _ToastConfig(
          icon: Icons.warning_amber_rounded,
          iconColor: Color(0xFFFBBF24), // amber-400
          backgroundColor: Color(0xFF2E261A), // dark amber tint
          duration: const Duration(milliseconds: 3000),
        );
      case KinrelToastType.info:
        return const _ToastConfig(
          icon: Icons.info_outline_rounded,
          iconColor: KinrelColors.orange,
          backgroundColor: Color(0xFF1A1F2E), // dark blue tint
          duration: Duration(milliseconds: 2500),
        );
    }
  }
}

/// The visual content of the toast: icon + message in a rounded container.
class _ToastContent extends StatelessWidget {
  const _ToastContent({
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
  });

  final String message;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .slideY(begin: 0.3, end: 0, duration: 250.ms, curve: Curves.easeOutCubic);
  }
}
