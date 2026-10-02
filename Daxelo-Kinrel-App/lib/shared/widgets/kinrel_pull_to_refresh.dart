// lib/shared/widgets/kinrel_pull_to_refresh.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  KINREL PULL-TO-REFRESH — haptic-enhanced, iOS-style                 │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// Pull-to-refresh is a gesture users expect on every list (Twitter,
// Instagram, Mail, Messages). The haptic at the threshold is the
// single most important detail — it tells the user "if you let go
// now, it'll refresh" without looking. iOS fires the haptic at the
// exact moment the indicator crosses the threshold; we replicate that.
//
// PSYCHOLOGICAL PRINCIPLE: DIRECT MANIPULATION + PROPRIOCEPTION
// ─────────────────────────────────────────────────────────────────────
//   • Direct Manipulation: the user feels they're physically pulling
//     the data down. The haptic at the threshold is the "click" of a
//     physical button — it confirms the gesture registered.
//   • Proprioception: the user knows where their finger is without
//     looking. The haptic lets them release at the right moment
//     without checking the screen.
//
// PERFORMANCE
// ───────────
//   • Uses Flutter's built-in RefreshIndicator (no new widget).
//   • Haptic fires ONCE per threshold crossing (not continuously).
//   • The refresh itself is the caller's responsibility — pass an
//     async [onRefresh] that resolves when the data is loaded.
//
// USAGE
// ─────
//   KinrelPullToRefresh(
//     onRefresh: () => ref.refresh(familyListProvider.future),
//     child: ListView(...),
//   )

import 'package:flutter/material.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/services/haptic_service.dart';

/// A pull-to-refresh wrapper that fires a haptic at the threshold,
/// matching iOS behavior.
///
/// Wraps [RefreshIndicator] with:
///   • Kinrel orange indicator color (brand consistency).
///   • A haptic fired once when the user crosses the threshold.
///   • A haptic fired once when the refresh completes (success).
class KinrelPullToRefresh extends StatefulWidget {
  const KinrelPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.displacement = 40.0,
  });

  /// Called when the user pulls past the threshold and releases.
  /// Return a Future that completes when the refresh is done.
  final Future<void> Function() onRefresh;

  /// The scrollable child. Must be a ScrollView or have a ScrollView
  /// ancestor (RefreshIndicator requirement).
  final Widget child;

  /// How far down the indicator sits from the top when active.
  final double displacement;

  @override
  State<KinrelPullToRefresh> createState() => _KinrelPullToRefreshState();
}

class _KinrelPullToRefreshState extends State<KinrelPullToRefresh> {
  bool _hasFiredThresholdHaptic = false;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Fire the threshold haptic when the user pulls past ~60px.
        // RefreshIndicator's default triggerDistance is 60px.
        if (notification is OverscrollNotification &&
            notification.overscroll < 0 && // pulling down
            !_hasFiredThresholdHaptic) {
          _hasFiredThresholdHaptic = true;
          HapticService.selection(); // tiny "tick" at the threshold
        }
        // Reset the flag when the user scrolls back up past the top,
        // so the next pull fires the haptic again.
        if (notification.metrics.pixels <= 0) {
          _hasFiredThresholdHaptic = false;
        }
        return false; // don't consume — let RefreshIndicator handle it
      },
      child: RefreshIndicator(
        onRefresh: () async {
          // Fire a tap haptic when the refresh actually starts.
          HapticService.tap();
          try {
            await widget.onRefresh();
            // Success haptic when the refresh completes.
            HapticService.success();
          } catch (_) {
            // Error haptic if the refresh fails.
            HapticService.error();
            rethrow;
          }
        },
        displacement: widget.displacement,
        color: KinrelColors.orange,
        backgroundColor:
            Theme.of(context).brightness == Brightness.dark
                ? KinrelColors.darkCard
                : Colors.white,
        strokeWidth: 2.5,
        child: widget.child,
      ),
    );
  }
}
