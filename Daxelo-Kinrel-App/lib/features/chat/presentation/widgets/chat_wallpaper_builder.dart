// lib/features/chat/presentation/widgets/chat_wallpaper_builder.dart
//
// DAXELO KINREL — Chat Wallpaper Builder
//
// Wraps a child widget with an optional wallpaper background. Watches
// [wallpaperPathProvider] for the given [chatId] — if a wallpaper path
// exists (either per-chat or the global default), it renders the image
// as a full-cover background behind [child]. If no wallpaper is set,
// it returns [child] directly (the parent Scaffold's backgroundColor
// shows through).
//
// Uses a conditional import to avoid compiling dart:io on web —
// wallpaper_image_native.dart uses Image.file, wallpaper_image_web.dart
// uses Image.network (for data: URIs).
//
// Used by both the group chat screen and the DM screen to wrap just the
// messages list area — the AppBar and input bar stay clean.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chat_wallpaper_provider.dart';
import 'wallpaper_image_web.dart' if (dart.library.io) 'wallpaper_image_native.dart'
    as platform;

class ChatWallpaperBuilder extends ConsumerWidget {
  const ChatWallpaperBuilder({
    super.key,
    required this.chatId,
    required this.child,
  });

  final String chatId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(wallpaperPathProvider(chatId));

    // No wallpaper set — return child directly.
    if (path == null || path.isEmpty) return child;

    // Data URIs (web) are always valid. File paths (native) are validated
    // inside buildWallpaperImageFromFile.
    // On web, path is always a data: URI → Image.network.
    // On native, path is a file path → Image.file (with existsSync check).
    if (path.startsWith('data:')) {
      return Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              path,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          child,
        ],
      );
    }

    // Native file path — delegate to the platform-specific helper.
    final image = platform.buildWallpaperImageFromFile(
      path,
      width: double.infinity,
      height: double.infinity,
      fallback: const SizedBox.shrink(),
    );
    if (image == null) return child;

    return Stack(
      children: [
        Positioned.fill(child: image),
        child,
      ],
    );
  }
}
