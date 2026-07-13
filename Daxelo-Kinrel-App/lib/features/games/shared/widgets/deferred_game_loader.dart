// lib/features/games/shared/widgets/deferred_game_loader.dart
//
// DAXELO KINREL — Deferred Game Loader (P5.3)
//
// Per Vision §5 Layer 4 — deferred imports for the 15 games. Game
// modules are loaded lazily (only when the user navigates to a game)
// to reduce the initial bundle size and improve first paint.
//
// Usage in GoRouter:
//   GoRoute(
//     path: '/games/ghost-painter/:id',
//     builder: (context, state) => DeferredGameLoader(
//       libraryLoader: () => games_ghost_painter.loadLibrary(),
//       screenBuilder: () => games_ghost_painter.GhostPainterDrawScreen(
//         familyId: state.pathParameters['id']!,
//       ),
//     ),
//   )
//
// The loader shows a spinner while the library downloads, then renders
// the game screen. For web, this splits the game code into a separate
// JS chunk loaded on demand.

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';

/// A widget that loads a deferred game library, then renders the game
/// screen. Shows a loading spinner while the library downloads.
class DeferredGameLoader extends StatefulWidget {
  const DeferredGameLoader({
    super.key,
    required this.libraryLoader,
    required this.screenBuilder,
  });

  /// The deferred library load function (e.g., `() => myLib.loadLibrary()`).
  final Future<void> Function() libraryLoader;

  /// Builds the game screen after the library is loaded.
  /// The library's types are only available inside this closure.
  final Widget Function() screenBuilder;

  @override
  State<DeferredGameLoader> createState() => _DeferredGameLoaderState();
}

class _DeferredGameLoaderState extends State<DeferredGameLoader> {
  late Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = widget.libraryLoader();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return Scaffold(
              backgroundColor: KinrelColors.darkBackground,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: KinrelColors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load game',
                      style: const TextStyle(color: KinrelColors.textWhite),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() {
                        _loadFuture = widget.libraryLoader();
                      }),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          return widget.screenBuilder();
        }
        return Scaffold(
          backgroundColor: KinrelColors.darkBackground,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: KinrelColors.tealAccent,
                ),
                const SizedBox(height: 16),
                Text(
                  'Loading game...',
                  style: const TextStyle(color: KinrelColors.textDim),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
