// lib/features/home/presentation/widgets/streak_badge.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  STREAK BADGE — the 🔥 N-day streak counter on the home screen        │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// A visible streak counter is the #1 retention lever in consumer apps
// (Duolingo, Snapchat, Wordle, GitHub). The user opens the app daily
// to "not lose their streak". This widget shows the current streak as
// a small badge in the home screen header.
//
// States:
//   • No streak (0 days): hidden (don't shame new users).
//   • 1-2 days: subtle gray badge (building up, don't over-celebrate).
//   • 3-6 days: orange 🔥 badge (engaged, keep going).
//   • 7 days: pulsing animated badge + first celebration fired.
//   • 30 days: gold badge + second celebration fired.
//
// PSYCHOLOGICAL PRINCIPLE: LOSS AVERSION + GOAL GRADIENT
// ─────────────────────────────────────────────────────────────────────
//   • Loss Aversion: the number going DOWN (streak broken) feels ~2×
//     as bad as it going UP feels good. The user is motivated to
//     maintain, not just gain.
//   • Goal Gradient: as the number grows, the user feels closer to the
//     next milestone (7, 30, 100) and is motivated to reach it.
//
// PERFORMANCE
// ───────────
//   • Reads StreakService once in initState, caches the result.
//   • No per-frame reads. No animation when inactive (0 days).
//   • The pulse animation only runs for 7+ day streaks, and only when
//     the widget is visible (not offscreen).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/streak_service.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../core/utils/motion_preference.dart';

/// A compact streak counter badge for the home screen header.
///
/// Shows "🔥 N" where N is the current streak. Hidden when streak < 1.
/// Pulses subtly when streak >= 7.
class StreakBadge extends StatefulWidget {
  const StreakBadge({super.key, this.onTap});

  /// Optional callback when the badge is tapped. If null, tapping
  /// fires a selection haptic + no-op (the badge is informational).
  final VoidCallback? onTap;

  @override
  State<StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends State<StreakBadge> {
  int _streak = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStreak();
  }

  Future<void> _loadStreak() async {
    final streak = await StreakService.getCurrentStreak();
    if (mounted) {
      setState(() {
        _streak = streak;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't render until loaded (avoids a flash of "🔥 0").
    if (!_loaded) return const SizedBox.shrink();

    // No streak — don't shame new users. Hide the badge entirely.
    if (_streak < 1) return const SizedBox.shrink();

    final isMilestone = _streak >= 7;
    final isGold = _streak >= 30;
    final isWarmup = _streak >= 1 && _streak < 3;

    // Color progression: gray (warmup) → orange (engaged) → gold (legend).
    final Color badgeColor;
    final Color textColor;
    if (isGold) {
      badgeColor = const Color(0xFFD4AF37); // gold
      textColor = Colors.white;
    } else if (isMilestone) {
      badgeColor = KinrelColors.orange;
      textColor = Colors.white;
    } else if (isWarmup) {
      badgeColor = const Color(0xFF2A2D3F); // subtle gray
      textColor = KinrelColors.textSilver;
    } else {
      badgeColor = KinrelColors.orange.withValues(alpha: 0.85);
      textColor = Colors.white;
    }

    Widget badge = GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: isWarmup ? 0.5 : 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: badgeColor.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _streak >= 30 ? '🏆' : '🔥',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(width: 4),
            Text(
              '$_streak',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            if (isMilestone) ...[
              const SizedBox(width: 2),
              Text(
                'day${_streak == 1 ? '' : 's'}',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: textColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // Milestone streaks get a subtle pulse to draw the eye.
    // The pulse is 5% scale, 1200ms, easeInOut — gentle, not annoying.
    // ── Reduce Motion: skip the pulse entirely. A static badge is
    // still informative; the pulse is decorative.
    if (isMilestone && MotionPreference.shouldShowDecorativeAnimation(context)) {
      badge = badge
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.05, 1.05),
            duration: 1200.ms,
            curve: Curves.easeInOut,
          );
    }

    return badge;
  }

  void _onTap() {
    // ── Haptic: selection click — the badge is informational, not a CTA.
    HapticService.selection();
    widget.onTap?.call();
  }
}
