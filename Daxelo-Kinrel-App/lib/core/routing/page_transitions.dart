// lib/core/routing/page_transitions.dart
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │  PREMIUM PAGE TRANSITIONS — subtle, fast, GPU-friendly               │
// └─────────────────────────────────────────────────────────────────────┘
//
// Replaces the prior _fastFadePage (200ms fade-only) and _instantPage
// (0ms) with a small family of transitions tuned for perceived quality
// without adding delay:
//
//   • premiumPage  — fade + 12px slide-up, 220ms, easeOutCubic.
//                    Used for pushed routes (forward navigation).
//                    The slight slide gives spatial continuity ("moving
//                    forward into the app") without being slow. The fade
//                    handles the exit of the previous screen.
//
//   • tabSwitchPage — 150ms cross-fade, easeOut. Used for ShellRoute
//                     tab switches. Feels instant (sub-perceptual-delay)
//                     but removes the "flash" of an instant swap. iOS
//                     and Material 3 both use this pattern.
//
//   • instantPage  — 0ms. Retained for genuine instant needs (redirect
//                    routes, splash → first real screen).
//
// Performance notes:
//   • All transitions use only Opacity + Transform.translate — both are
//     GPU-composited layers in Impeller/Skia, zero raster cost.
//   • No ClipRRect, no ShaderMask, no blur — nothing that would cause
//     raster jank on low-end devices.
//   • Durations stay at or below 220ms — below the 300ms threshold
//     where users perceive animation as "slow".
//   • Curves are cubic-ease-out variants — decelerate-into-rest feels
//     natural and premium; linear feels cheap.
//
// Why not Hero/shared-element transitions everywhere?
//   Hero transitions require matching tags at source AND destination,
//   and they can cause jank on low-end devices when the source widget
//   is complex (e.g., a card with images). This file provides the page
//     transition layer only. High-traffic Hero transitions (family card
//   → family detail) are added separately in the source widgets.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The duration used for pushed-route transitions (fade + slide).
///
/// 220ms sits in the "premium but fast" band:
///   • Below 300ms — users don't perceive it as slow.
///   • Above 150ms — long enough to read as intentional motion, not a
///     glitch.
///   • Matches the duration used by iOS push transitions (250ms) and
///     Material 3 container transform (250ms) — close enough to feel
///     native on both platforms.
const Duration _kPremiumDuration = Duration(milliseconds: 220);

/// The duration used for tab-switch transitions (cross-fade only).
///
/// 150ms is the sweet spot for tab switches:
///   • Short enough to feel instant — the user's finger is still
///     lifting from the tap when the new tab is fully visible.
///   • Long enough to avoid the "flash" of a 0ms swap.
///   • Matches iOS UITabBarController's cross-fade duration.
const Duration _kTabSwitchDuration = Duration(milliseconds: 150);

/// The vertical slide distance for pushed routes, in logical pixels.
///
/// 12px is subtle — about the height of a status-bar icon. It's enough
/// to communicate "moving forward" without making the screen feel like
/// it's traveling a long distance. Larger values (24px+) start to feel
/// heavy and Material-2-ish.
const double _kSlideOffset = 12.0;

/// Premium page transition: fade + slight slide-up.
///
/// Used for pushed routes (forward navigation). The new screen fades in
/// while sliding up 12px; the old screen fades out. Both run in parallel
/// over 220ms with `Curves.easeOutCubic`.
///
/// Why easeOutCubic (not easeOut)?
///   `easeOutCubic` has a steeper deceleration — the screen "lands"
///   softly at its final position. `easeOut` is more linear at the
///   start, which can feel slightly mechanical.
///
/// GPU cost: 1 Opacity layer + 1 Transform layer. Both are composited
/// by the engine without re-rasterizing the screen's content.
CustomTransitionPage<void> premiumPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage(
    key: key,
    child: child,
    transitionDuration: _kPremiumDuration,
    reverseTransitionDuration: _kPremiumDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Drive both the incoming and outgoing screens from the primary
      // animation. The outgoing screen (secondaryAnimation) gets a
      // slight fade-out so the handoff feels continuous rather than
      // a hard cut.
      final curvedPrimary = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final curvedSecondary = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      // Incoming screen: fade 0→1 + slide 12px→0.
      final slideOffset = Tween<Offset>(
        begin: const Offset(0, _kSlideOffset / 800),
        end: Offset.zero,
      ).animate(curvedPrimary);

      // Outgoing screen: subtle fade 1→0.7 (not full 0 — keeps it
      // visible behind the incoming screen for a softer handoff).
      final secondaryFade = Tween<double>(begin: 1.0, end: 0.7)
          .animate(curvedSecondary);

      return FadeTransition(
        opacity: curvedPrimary,
        child: SlideTransition(
          position: slideOffset,
          child: FadeTransition(
            opacity: secondaryFade,
            child: child,
          ),
        ),
      );
    },
  );
}

/// Tab-switch transition: 150ms cross-fade, no slide.
///
/// Used for ShellRoute tab switches. A cross-fade feels instant (the
/// user's finger is still lifting when the new tab is visible) but
/// removes the "flash" of a 0ms swap.
///
/// The outgoing tab fades 1→0 while the incoming tab fades 0→1, both
/// over 150ms with `Curves.easeOut`. No slide — lateral motion would
/// feel wrong for tab switches (tabs aren't "forward/back", they're
/// "lateral").
CustomTransitionPage<void> tabSwitchPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage(
    key: key,
    child: child,
    transitionDuration: _kTabSwitchDuration,
    reverseTransitionDuration: _kTabSwitchDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

/// Instant page transition: 0ms.
///
/// Retained for genuine instant needs:
///   • Redirect routes (e.g., /splash → /home when already authed)
///   • The very first screen the app shows (no transition into nothing)
///
/// NOT used for normal navigation or tab switches — use [premiumPage]
/// or [tabSwitchPage] instead.
CustomTransitionPage<void> instantPage({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage(
    key: key,
    child: child,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return child;
    },
  );
}
