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
// ── Platform behaviour ──────────────────────────────────────────────
//
// - **Web:** the stored "path" is a "data:image/...;base64,..." URI.
//   Rendered via Image.network (which Flutter web resolves to an
//   in-memory image). No filesystem access needed.
//
// - **Native:** the stored path is an absolute file path. Rendered via
//   Image.file. The file's existence is validated before rendering —
//   if the file was deleted (e.g. app data cleared), the wallpaper
//   silently falls back to transparent (parent's backgroundColor).
//
// Used by both the group chat screen and the DM screen to wrap just the
// messages list area — the AppBar and input bar stay clean.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
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

    // ── Web: data URI → Image.network ────────────────────────────
    if (kIsWeb || path.startsWith('data:')) {
      return Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              path,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, error, ___) {
                debugPrint(
                    '[ChatWallpaperBuilder] Web: failed to render data URI '
                    'for chatId="$chatId": $error');
                return const SizedBox.shrink();
              },
            ),
          ),
          child,
        ],
      );
    }

    // ── Native: file path → Image.file ───────────────────────────
    // Validate the file exists before attempting to render. If it was
    // deleted (app data cleared, user wiped cache, etc.), silently fall
    // back to transparent rather than showing a broken-image icon.
    final file = File(path);
    if (!file.existsSync()) {
      debugPrint(
          '[ChatWallpaperBuilder] Native: wallpaper file does not exist at '
          '$path — falling back to transparent for chatId="$chatId".');
      return child;
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Image.file(
            file,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, error, ___) {
              debugPrint(
                  '[ChatWallpaperBuilder] Native: Image.file failed to render '
                  '$path for chatId="$chatId": $error');
              return const SizedBox.shrink();
            },
          ),
        ),
        child,
      ],
    );
  }
}
