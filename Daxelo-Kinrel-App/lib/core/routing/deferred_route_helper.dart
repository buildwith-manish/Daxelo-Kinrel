// lib/core/routing/deferred_route_helper.dart
//
// Tier 2 #5 — Lazy-load feature modules via deferred imports.
//
// Provides a helper that wraps a GoRoute's pageBuilder to load the
// deferred library on first navigation, showing a brief loading
// indicator while the library loads. The library is cached after
// first load, so subsequent navigations are instant.
//
// Usage in app_router.dart:
//   // Change from:
//   import '../../features/games/ghost_painter/ghost_painter_draw_screen.dart';
//   ...
//   GoRoute(
//     path: '/family/:id/ghost-painter/draw',
//     pageBuilder: (context, state) => _fastFadePage(
//       key: state.pageKey,
//       child: GhostPainterDrawScreen(familyId: state.pathParameters['id']!),
//     ),
//   ),
//   // To:
//   import '../../features/games/ghost_painter/ghost_painter_draw_screen.dart'
//       deferred as ghost_painter_draw;
//   ...
//   GoRoute(
//     path: '/family/:id/ghost-painter/draw',
//     pageBuilder: (context, state) => _fastFadePage(
//       key: state.pageKey,
//       child: DeferredRouteWidget(
//         loadLibrary: ghost_painter_draw.loadLibrary,
//         builder: () => ghost_painter_draw.GhostPainterDrawScreen(
//           familyId: state.pathParameters['id']!,
//         ),
//       ),
//     ),
//   ),
//
// The first navigation to the route triggers `loadLibrary()`, shows a
// loading spinner, then swaps in the actual screen. Subsequent
// navigations are instant because the library is already loaded.

import 'package:flutter/material.dart';

/// A widget that loads a deferred library on first build, showing a
/// loading indicator while it loads. Once loaded, it renders the
/// builder's output and caches the loaded state.
///
/// Used by GoRoute pageBuilders to lazy-load heavy feature modules
/// (games, pulse, trackc, etc.) on first navigation, reducing cold
/// start time by deferring non-startup-critical code.
class DeferredRouteWidget extends StatefulWidget {
  const DeferredRouteWidget({
    super.key,
    required this.loadLibrary,
    required this.builder,
    this.loadingColor,
  });

  /// The deferred library's `loadLibrary` function.
  final Future<void> Function() loadLibrary;

  /// Builder that constructs the actual screen widget. Called
  /// after the library is loaded.
  final Widget Function() builder;

  /// Color for the loading spinner. Defaults to the app's orange.
  final Color? loadingColor;

  @override
  State<DeferredRouteWidget> createState() => _DeferredRouteWidgetState();
}

class _DeferredRouteWidgetState extends State<DeferredRouteWidget> {
  bool _loaded = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    if (_loaded || _loading) return;
    setState(() => _loading = true);
    try {
      await widget.loadLibrary();
      if (mounted) {
        setState(() {
          _loaded = true;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
      // On error, fall back to rendering the builder anyway — the
      // import may have been loaded by another path already.
      if (mounted) {
        setState(() => _loaded = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded) {
      return widget.builder();
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: CircularProgressIndicator(
          color: widget.loadingColor ?? const Color(0xFFE8612A),
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}
