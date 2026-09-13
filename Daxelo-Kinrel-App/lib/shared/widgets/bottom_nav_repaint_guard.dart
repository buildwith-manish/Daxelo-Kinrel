// lib/shared/widgets/bottom_nav_repaint_guard.dart
//
// DAXELO KINREL — Bottom Nav Repaint Guard
//
// Fixes a recurring bug where the bottom navigation/action bar (either
// the global DKBottomNav used by MainShell, or the FamilySpaceFloatingNav
// used by family-scoped screens) renders INVISIBLE for the first 1-2
// seconds after a screen loads, only appearing after the user taps
// elsewhere on the screen.
//
// ROOT CAUSE
// ----------
// Both bottom-nav widgets use `BackdropFilter` to produce a frosted-glass
// effect over the body content. On Flutter Web (and on some native
// transitions), the compositing layer that backs the `BackdropFilter`
// does NOT reliably re-sample the freshly-painted backdrop on the first
// frame after the widget mounts. The widget is in the tree, it has been
// laid out, but the `BackdropFilter`'s cached backdrop sample is empty /
// stale, so it paints as fully transparent. The container's 92%-opaque
// background color helps in theory, but the compositing layer may not
// even have been painted yet on the first frame.
//
// An unrelated tap anywhere on the screen causes Flutter to rebuild the
// widget tree, which invalidates the `BackdropFilter`'s compositing
// layer, which triggers a fresh backdrop sample — and the bar suddenly
// becomes visible. This matches the symptom precisely.
//
// FIX
// ---
// Wrap the bottom nav in this widget. The guard:
//   1. Schedules an explicit setState() on the next frame after mount,
//      which invalidates the `BackdropFilter`'s compositing layer and
//      forces a fresh backdrop sample — making the bar visible on the
//      second frame even if Flutter doesn't naturally trigger a rebuild.
//   2. Wraps the child in a [RepaintBoundary] so the bottom nav is
//      its own compositing layer. This makes backdrop-sampling
//      deterministic (the layer's bounds are well-defined) and also
//      improves repaint performance — only the bottom nav repaints
//      when its own state (e.g. active tab) changes, not the whole
//      screen.
//   3. Listens to app lifecycle changes via [WidgetsBindingObserver]
//      and forces a repaint on app resume. After backgrounding, the
//      `BackdropFilter`'s cached backdrop is stale and the bar can
//      re-appear invisible until the next interaction.
//
// WHY THIS IS A SHARED WIDGET, NOT PER-SCREEN
// -------------------------------------------
// The bug is in the bottom nav components themselves (DKBottomNav and
// FamilySpaceFloatingNav), not in any individual screen. Both widgets
// are reused across many screens, so fixing the shared widget fixes
// every screen at once. This guard is the single point of truth for
// "make the bottom nav repaint correctly after mount".
//
// USAGE
// -----
// ```dart
// BottomNavRepaintGuard(
//   child: DKBottomNav(...),  // or FamilySpaceFloatingNav(...)
// )
// ```

import 'package:flutter/material.dart';

/// A wrapper that forces its child to repaint after the first frame on
/// mount and on app resume.
///
/// See the file-level docstring for the full rationale.
class BottomNavRepaintGuard extends StatefulWidget {
  const BottomNavRepaintGuard({super.key, required this.child});

  final Widget child;

  @override
  State<BottomNavRepaintGuard> createState() => _BottomNavRepaintGuardState();
}

class _BottomNavRepaintGuardState extends State<BottomNavRepaintGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Listen for app lifecycle changes so we can force a repaint on
    // resume (the BackdropFilter's cached backdrop is stale after
    // backgrounding).
    WidgetsBinding.instance.addObserver(this);

    // Schedule a rebuild on the next frame. This is the core of the fix:
    // even if Flutter doesn't naturally trigger a rebuild after the
    // first frame (because the widget's own data — theme, layout, route
    // location — is already resolved on the first frame), we force one.
    // The setState invalidates the BackdropFilter's compositing layer
    // and triggers a fresh backdrop sample, making the bottom nav
    // visible immediately on the second frame instead of waiting for an
    // unrelated user tap.
    //
    // We guard with `mounted` because the post-frame callback can fire
    // after the widget has been removed from the tree (e.g., very fast
    // navigation away from the screen).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On app resume, the BackdropFilter's cached backdrop may be stale
    // (the screen was off / the app was backgrounded). Force a repaint
    // so the bottom nav becomes visible again without requiring a tap.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  @override
  void didHaveMemoryPressure() {
    // Under memory pressure, Flutter may have evicted compositing layer
    // resources (including the BackdropFilter's cached backdrop). Force
    // a repaint so the bottom nav is restored.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary gives the bottom nav its own compositing layer.
    // This makes backdrop-sampling deterministic (the layer's bounds
    // are well-defined) and isolates the bottom nav's repaints from
    // the rest of the screen — improving both correctness and perf.
    return RepaintBoundary(child: widget.child);
  }
}
