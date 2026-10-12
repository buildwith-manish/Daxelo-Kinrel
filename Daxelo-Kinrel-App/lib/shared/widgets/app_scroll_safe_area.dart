// lib/shared/widgets/app_scroll_safe_area.dart
//
// ┌────────────────────────────────────────────────────────────────────┐
// │  APP SCROLL SAFE AREA — shared bottom-padding sliver for scroll views │
// └────────────────────────────────────────────────────────────────────┘
//
// WHY THIS EXISTS
// ───────────────
// Scrollable lists inside Scaffold bodies that ALSO host persistent chrome
// (floating nav bars, FABs, banner CTAs) need explicit bottom padding so
// the last card never clips under the chrome. Per ADR-007, hardcoded pixel
// offsets are forbidden — the offset must account for the actual device
// safe-area inset (gesture nav bar, home indicator) on top of the chrome
// height itself.
//
// This widget encodes the pattern established by the Family Space detail
// screen (lib/features/family/presentation/family_detail_screen.dart),
// generalized so EVERY screen with this layout shape can adopt it instead
// of re-implementing the math inline.
//
// USAGE
// ─────
//   CustomScrollView(
//     slivers: [
//       // ...your slivers...
//       AppScrollSafeArea.sliver(),           // ← default chrome (FAB only)
//       // or
//       AppScrollSafeArea.sliver(chromeHeight: 80),  // FAB + floating nav
//     ],
//   )
//
//   // Non-sliver (inline) variant:
//   AppScrollSafeArea(child: lastCard);
//
// OTHER SCREENS THAT SHOULD ADOPT THIS
// ────────────────────────────────────
// • Family detail screen — already uses the inline 80+24+pad+16 math; can
//   be migrated to this widget for consistency.
// • Memories & Timeline — first consumer (this PR).
// • Memory Vault, Oral History, Documents — any scroll screen with FAB.
// • Any future screen with floating chrome above scrollable content.
//
// See: docs/adr/ADR-007-safe-area-policy.md for the full rule.

import 'package:flutter/material.dart';

/// Encodes the established pattern for the bottom safe-area/scroll-padding
/// that prevents the last card in a scrollable list from clipping under
/// persistent chrome (FAB, floating nav bar, etc.).
///
/// The math:
///   total height = chromeHeight + margin + safeAreaBottom + extraSpacing
///
/// Default values match the Family Space detail screen:
///   chromeHeight = 80 (FAB + floating nav)
///   margin       = 24
///   extraSpacing = 16
///
/// For screens with only a FAB (no floating nav), use chromeHeight: 56.
class AppScrollSafeArea extends StatelessWidget {
  const AppScrollSafeArea({
    super.key,
    this.chromeHeight = 80,
    this.margin = 24,
    this.extraSpacing = 16,
    this.child,
  });

  /// A [SliverToBoxAdapter] version that can be appended directly to a
  /// [CustomScrollView]'s slivers list. Use this at the end of every
  /// scroll view with persistent chrome.
  ///
  /// Example:
  ///   slivers: [
  ///     ...contentSlivers,
  ///     AppScrollSafeArea.sliver(),
  ///   ]
  static SliverToBoxAdapter sliver({
    double chromeHeight = 80,
    double margin = 24,
    double extraSpacing = 16,
  }) {
    return SliverToBoxAdapter(
      child: _SliverSafeAreaPadding(
        chromeHeight: chromeHeight,
        margin: margin,
        extraSpacing: extraSpacing,
      ),
    );
  }

  /// Height of the persistent chrome that floats above the scrollable
  /// content. Defaults to 80 (matches Family Space: FAB + floating nav).
  /// For screens with only a FAB, pass `chromeHeight: 56`.
  final double chromeHeight;

  /// Visual spacing between the bottom of the last card and the top of
  /// the chrome. Per ADR-007, the safe-area inset is ADDED on top of this.
  final double margin;

  /// Extra spacing beyond [margin] for comfortable breathing room.
  /// Family Space uses 16; keep this non-zero to avoid edge-kissing.
  final double extraSpacing;

  /// Optional child to render inside the padded box (non-sliver variant).
  /// When null, only the padding [SizedBox] is rendered.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final total = chromeHeight + margin + bottomInset + extraSpacing;
    if (child == null) {
      return SizedBox(height: total);
    }
    return Padding(
      padding: EdgeInsets.only(bottom: total),
      child: child!,
    );
  }
}

class _SliverSafeAreaPadding extends StatelessWidget {
  const _SliverSafeAreaPadding({
    required this.chromeHeight,
    required this.margin,
    required this.extraSpacing,
  });

  final double chromeHeight;
  final double margin;
  final double extraSpacing;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final total = chromeHeight + margin + bottomInset + extraSpacing;
    return SizedBox(height: total);
  }
}
