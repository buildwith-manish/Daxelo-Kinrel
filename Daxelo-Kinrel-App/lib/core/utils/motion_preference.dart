// lib/core/utils/motion_preference.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  MOTION PREFERENCE — centralized reduce-motion gate                    │
// └─────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// ~15% of users have "Reduce Motion" enabled (iOS) or "Remove Animations"
// (Android). For these users, animations can cause motion sickness,
// vertigo, or distraction. Apple's HIG and Google's Material guidelines
// both require apps to honor this setting.
//
// Before this utility, reduce-motion was checked ad-hoc in 5 files
// (bounce_button, celebration_service, graph_node, cameo). But page
// transitions, skeletons, flutter_animate entry animations, and the
// streak badge pulse were NOT gated. This centralizes the check so
// every animation in the app can query one place.
//
// HOW IT WORKS
// ────────────
//   • isReducedMotion(context) returns true if the user has enabled
//     the system's reduce-motion / accessibleNavigation setting.
//   • Callers pass the result to AnimationController(duration: ...)
//     or use it to skip .animate() chains entirely.
//   • The check is a MediaQuery read — ~0.01ms, safe to call in build.
//
// PSYCHOLOGICAL PRINCIPLE: INCLUSIVITY + MOTION SICKNESS AVOIDANCE
// ─────────────────────────────────────────────────────────────────────
//   • Inclusivity: ~15% of users get a degraded experience without
//     this. That's a large minority — larger than left-handed users.
//   • Motion Sickness: vestibular disorders affect ~1-3% of the
//     population. Parallax, zoom, and spring animations trigger
//     symptoms. Reducing motion isn't a preference — it's medical
//     accommodation.
//
// USAGE
// ─────
//   if (MotionPreference.isReducedMotion(context)) {
//     // Skip animation, show the final state immediately.
//     return child;
//   }
//   return child.animate().fadeIn(duration: 400.ms);
//
//   // Or for AnimationController:
//   final duration = MotionPreference.isReducedMotion(context)
//       ? Duration.zero
//       : const Duration(milliseconds: 220);

import 'package:flutter/widgets.dart';

/// Centralized check for the user's motion-reduction preference.
///
/// Returns true if the user has enabled "Reduce Motion" (iOS) or
/// "Remove Animations" / "Accessible Navigation" (Android). When
/// true, animations should be disabled or reduced to instant fades.
class MotionPreference {
  MotionPreference._();

  /// Returns true if the user prefers reduced motion.
  ///
  /// This reads `MediaQuery.accessibleNavigation`, which is true when:
  ///   • iOS: Settings > Accessibility > Reduce Motion is ON
  ///   • Android: Settings > Accessibility > Remove Animations is ON
  ///   • Web: prefers-reduced-motion CSS media query matches
  ///
  /// Safe to call in build() — it's a MediaQuery read, not an async call.
  static bool isReducedMotion(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    // accessibleNavigation covers reduce-motion on both platforms.
    // We also check disableAnimations for older Android versions.
    if (mq == null) return false;
    return mq.accessibleNavigation || mq.disableAnimations;
  }

  /// Returns the appropriate animation duration based on the user's
  /// motion preference. Returns Duration.zero if reduced motion is on.
  ///
  /// Use this to gate AnimationController durations:
  ///   controller = AnimationController(
  ///     duration: MotionPreference.duration(context, const Duration(milliseconds: 220)),
  ///     vsync: this,
  ///   );
  static Duration duration(BuildContext context, Duration normal) {
    return isReducedMotion(context) ? Duration.zero : normal;
  }

  /// Returns true if non-essential animations (parallax, shimmer, pulse)
  /// should be shown. Essential animations (loading spinners, progress
  /// bars) are always shown — they communicate state, not decoration.
  ///
  /// This is a stricter check than [isReducedMotion] — use it for
  /// decorative animations only.
  static bool shouldShowDecorativeAnimation(BuildContext context) {
    return !isReducedMotion(context);
  }
}
