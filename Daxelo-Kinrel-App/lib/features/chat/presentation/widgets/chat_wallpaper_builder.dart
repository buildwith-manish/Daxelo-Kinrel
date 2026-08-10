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
// Used by both the group chat screen and the DM screen to wrap just the
// messages list area — the AppBar and input bar stay clean.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chat_wallpaper_provider.dart';

class ChatWallpaperBuilder extends ConsumerWidget {
  const ChatWallpaperBuilder({
    super.key,
    required this.chatId,
    required this.child,
  });

  /// The chat ID to look up the wallpaper for. Family ID for group chats,
  /// "dm_<otherUserId>" for DMs, or "default" for the global fallback.
  final String chatId;

  /// The content to render on top of the wallpaper.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(wallpaperPathProvider(chatId));

    // No wallpaper set — return child directly so the parent's
    // backgroundColor shows through.
    if (path == null || path.isEmpty) return child;

    return Stack(
      children: [
        // Bottom layer: the wallpaper image, covering the full area.
        Positioned.fill(
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) {
              // If the file is missing/corrupt, render nothing — the
              // parent's backgroundColor shows through. This prevents
              // a crash if the wallpaper file was deleted.
              return const SizedBox.shrink();
            },
          ),
        ),
        // Top layer: the actual content.
        child,
      ],
    );
  }
}
