// lib/features/chat/presentation/widgets/chat_background.dart
//
// DAXELO KINREL — Premium Chat Background (v132)
//
// Replaces ChatWallpaperBuilder with a multi-layer atmosphere that
// gives the chat space depth and warmth without competing with
// message bubbles. Three layers are always rendered, plus an optional
// fourth when a custom image wallpaper is set.
//
// Layer 1 — Base ambient gradient (ALWAYS)
//   A radial gradient from the theme's center color outward to the
//   edge color. Creates the "illuminated from within" feeling the
//   design calls for. NEVER a flat single color — even the default
//   Midnight theme has subtle hue variation.
//
// Layer 2 — Accent corner glow (ALWAYS)
//   A single soft radial highlight positioned at the theme's
//   accentAlignment. 12% alpha. Suggests a distant window or
//   reflected light — adds spatial interest without distracting.
//
// Layer 3 — Vignette (ALWAYS)
//   A subtle darkening at the very edges (8% alpha) that frames the
//   conversation. Creates the "designed environment" feeling the
//   brief asks for — messages exist within a space, not on a flat
//   surface.
//
// Layer 4 — Custom wallpaper image (OPTIONAL, when set)
//   When a user has chosen a custom image wallpaper (data URI on web,
//   file path on native), it's rendered as the BOTTOM layer with a
//   heavy blur + darkening overlay so it never competes with message
//   readability. The blur also softens low-quality images into an
//   atmospheric wash.
//
// Theme vs image wallpaper:
//   - If the stored value is "theme:<id>", we render that theme
//     (layers 1-3) and skip layer 4.
//   - If the stored value is an image path/URI, we render the default
//     theme (layers 1-3) as a fallback base, then composite the
//     blurred image (layer 4) on top.
//   - If no value is stored, we render the default Midnight theme.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chat_wallpaper_provider.dart';
import 'chat_background_theme.dart';
// Conditional import: web vs native image rendering for custom wallpapers.
import 'wallpaper_image_web.dart' if (dart.library.io) 'wallpaper_image_native.dart'
    as platform;

/// A premium multi-layer chat background.
///
/// Wrap the chat messages list (or any child) with this widget to give
/// the conversation a curated atmosphere. Watches
/// [wallpaperPathProvider] for the active chatId and re-renders when
/// the user changes theme or wallpaper.
class ChatBackground extends ConsumerWidget {
  const ChatBackground({
    super.key,
    required this.chatId,
    required this.child,
  });

  /// The chat whose wallpaper/theme should be applied.
  final String chatId;

  /// The content (typically the messages ListView) rendered on top.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(wallpaperPathProvider(chatId));
    final theme = ChatBackgroundTheme.fromStoredValue(stored);
    final hasImage = stored != null &&
        stored.isNotEmpty &&
        !ChatBackgroundTheme.isThemeValue(stored);

    return Stack(
      children: [
        // ── Layer 4 (bottom): custom image wallpaper ───────────────
        // Rendered first so all other layers composite on top. Heavy
        // blur + darkening ensures it reads as atmosphere, not as a
        // photo behind text. ImageErrorSilently swallowed — if the
        // image fails to load (deleted file, broken data URI), the
        // theme layers below still render correctly.
        if (hasImage)
          Positioned.fill(
            child: _BlurredWallpaperImage(imagePath: stored!),
          ),

        // ── Layer 1: base ambient gradient ─────────────────────────
        // RadialGradient gives the "softly illuminated from within"
        // feeling. Center is the lightest base color; edge is the
        // darkest. The radius is large (1.4) so the gradient is very
        // gradual — no obvious "spotlight" effect.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.4,
                colors: theme.baseColors,
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),

        // ── Layer 2: accent corner glow ────────────────────────────
        // A soft radial highlight at the theme's accent corner. 12%
        // alpha so it's felt, not seen. Creates the impression of a
        // light source without drawing a visible circle.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: theme.accentAlignment,
                radius: 0.9,
                colors: [
                  theme.accentColor.withValues(alpha: 0.12),
                  theme.accentColor.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),

        // ── Layer 3: edge vignette ─────────────────────────────────
        // A subtle darkening at the edges that frames the
        // conversation. 8% alpha. Creates the "designed environment"
        // feeling — messages exist within a space, not on a flat
        // surface. The vignette is RADIAL so the readable center
        // stays bright.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.85,
                colors: [
                  Colors.transparent,
                  theme.vignetteColor.withValues(alpha: 0.0),
                  theme.vignetteColor.withValues(alpha: 0.35),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),

        // ── Child content ──────────────────────────────────────────
        // The messages list (or whatever else is wrapped). Rendered
        // above all background layers so bubbles are always the
        // primary focus.
        child,
      ],
    );
  }
}

/// Renders a custom wallpaper image with a heavy blur + darkening
/// overlay so it reads as atmosphere rather than a photo.
///
/// The blur is intentionally strong (sigma = 24) — anything less and
/// recognizable shapes in the image would compete with message
/// bubbles for attention. At sigma 24, even a busy photo becomes an
/// abstract wash of color.
class _BlurredWallpaperImage extends StatelessWidget {
  const _BlurredWallpaperImage({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    // Data URIs (web) are always valid. File paths (native) are
    // validated by the wallpaper provider before being stored.
    final isDataUri = imagePath.startsWith('data:');

    if (isDataUri) {
      return ImageFiltered(
        // ImageFiltered wraps Image.network (works for data: URIs on
        // both web and native) and applies a sigma-24 blur via
        // ImageFilter. We don't use BackdropFilter because the image
        // needs to be its own layer, not a backdrop to existing
        // content.
        imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Image.network(
          imagePath,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }

    // Native file path — delegate to the platform-specific helper.
    // The helper returns null if the file doesn't exist (stale entry),
    // in which case we render nothing and the theme layers show through.
    final image = platform.buildWallpaperImageFromFile(
      imagePath,
      width: double.infinity,
      height: double.infinity,
      fallback: const SizedBox.shrink(),
    );

    if (image == null) return const SizedBox.shrink();

    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: image,
    );
  }
}
