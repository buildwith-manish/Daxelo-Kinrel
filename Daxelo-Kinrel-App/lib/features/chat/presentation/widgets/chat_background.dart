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
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/device_tier.dart';
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
    // PERF (Part E4): read lowRam ONCE per build. Low-RAM phones get a
    // single RadialGradient layer (skip the accent glow + vignette);
    // strong phones keep the original 3-layer stack unchanged.
    final bool lowRam = DeviceTierCache.instance.lowRam;

    return Stack(
      children: [
        // PERF (Part C2): wrap the static background layers (1-4) in a
        // RepaintBoundary so the message-list child's repaints don't
        // force the gradient + blurred wallpaper to repaint too. The
        // child itself is intentionally outside the RepaintBoundary —
        // it must repaint freely as the user scrolls. The wallpaper's
        // ImageFiltered blur is also wrapped in its own RepaintBoundary
        // inside _BlurredWallpaperImage so its expensive saveLayer is
        // cached as a separate layer and not re-rasterized per frame.
        RepaintBoundary(
          child: Stack(
            children: [
              // ── Layer 4 (bottom): custom image wallpaper ───────────────
              // Rendered first so all other layers composite on top. Heavy
              // blur + darkening ensures it reads as atmosphere, not as a
              // photo behind text. ImageErrorSilently swallowed — if the
              // image fails to load (deleted file, broken data URI), the
              // theme layers below still render correctly.
              if (hasImage)
                Positioned.fill(
                  child: _BlurredWallpaperImage(imagePath: stored, lowRam: lowRam),
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
              //
              // PERF (Part E4): skipped on low-RAM phones (single
              // RadialGradient layer keeps the cost low). Strong phones
              // keep the original look.
              if (!lowRam)
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
              //
              // PERF (Part E4): skipped on low-RAM phones (single
              // RadialGradient layer keeps the cost low). Strong phones
              // keep the original look.
              if (!lowRam)
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
            ],
          ),
        ),

        // ── Child content ──────────────────────────────────────────
        // The messages list (or whatever else is wrapped). Rendered
        // above all background layers so bubbles are always the
        // primary focus. Outside the background's RepaintBoundary so
        // it can repaint freely during scroll.
        child,
      ],
    );
  }
}

/// Renders a custom wallpaper image with a heavy blur + darkening
/// overlay so it reads as atmosphere rather than a photo.
///
/// The blur is intentionally strong (sigma = 24 on strong phones, 8 on
/// low-RAM phones) — anything less and recognizable shapes in the image
/// would compete with message bubbles for attention. At sigma 24, even
/// a busy photo becomes an abstract wash of color.
class _BlurredWallpaperImage extends StatelessWidget {
  const _BlurredWallpaperImage({required this.imagePath, required this.lowRam});

  final String imagePath;
  // PERF (Part E4): when true, blur sigma is 8 instead of 24.
  final bool lowRam;

  @override
  Widget build(BuildContext context) {
    // Data URIs (web) are always valid. File paths (native) are
    // validated by the wallpaper provider before being stored.
    final isDataUri = imagePath.startsWith('data:');

    // PERF (Tier A1 → Tier E): On Flutter Web, ImageFilter.blur at sigma 24
    // produces a 75+ ms/frame Raster average because the blurred
    // layer re-rasterizes every time the chat list rebuilds (which
    // happens on every new message from the realtime Supabase
    // channel + every typing-indicator tick). Capping sigma at 6
    // on web is visually equivalent at the wallpaper's role
    // (ambient wash of color behind messages) and ~4x cheaper.
    // Native keeps the original sigma for visual parity with iOS
    // and Android production builds.
    //
    // Tier E: now reads from the central RasterBudget.blurSigma API
    // (device_tier.dart) instead of an inline kIsWeb ternary. Same
    // value (6 on web, 24 on native strong-phone, 8 on native low-RAM).
    final double effectiveSigma = DeviceTierCache.instance.rasterBudget.blurSigma
        .clamp(0.0, lowRam ? 8.0 : 24.0);

    if (isDataUri) {
      // NOTE (perf pass step 3): the Image.network below is intentionally
      // left as-is. This branch only runs on web where the wallpaper
      // path is a base64 `data:` URI (already in memory). CachedNetworkImage
      // cannot fetch `data:` URIs (its HttpFileService uses an HTTP
      // client), so converting this call would silently break wallpaper
      // rendering on web (the errorWidget would always fire and show
      // SizedBox.shrink). The native branch below already uses
      // Image.file via the platform helper. There is no HTTP network
      // URL case in this file, so CachedNetworkImage buys us nothing.
      // Same rationale as `wallpaper_image_web.dart` (skipped per spec).
      //
      // PERF (Part C2): wrap the ImageFiltered in a RepaintBoundary so
      // its expensive saveLayer (the ImageFilter.blur) is cached as a
      // separate layer in the rasterizer. The image itself doesn't
      // animate, so this layer is rasterized once and reused.
      //
      // PERF (Tier A1): sigma capped at 6 on web (see effectiveSigma
      // above) — visually equivalent at wallpaper role, 4x cheaper.
      //
      // PERF (Tier B3): cacheWidth=1080 / cacheHeight=1920 caps the
      // decode resolution so a 4K wallpaper data URI never rasterizes
      // at full size — saves ~12MB of pixel buffer per wallpaper.
      return RepaintBoundary(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
              sigmaX: effectiveSigma, sigmaY: effectiveSigma),
          child: Image.network(
            imagePath,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: kIsWeb ? 1080 : null,
            cacheHeight: kIsWeb ? 1920 : null,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
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

    // PERF (Part C2): same RepaintBoundary wrap as the data-URI branch
    // above — cache the expensive ImageFiltered saveLayer as a separate
    // rasterized layer.
    // PERF (Tier A1): sigma capped at 6 on web (effectiveSigma above).
    return RepaintBoundary(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
            sigmaX: effectiveSigma, sigmaY: effectiveSigma),
        child: image,
      ),
    );
  }
}
