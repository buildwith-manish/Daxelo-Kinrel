// lib/features/chat/presentation/widgets/chat_background.dart
//
// DAXELO KINREL — Chat Background (flat)
//
// Flat mode (default, KinrelFx.rich == false):
//   - Single solid color background (the darkest theme base color).
//   - If a user wallpaper image is set, draw the image WITHOUT blur,
//     with a 50% dark overlay for readability.
//   - No radial gradient layers, no accent corner glow, no edge vignette.
//
// Rich mode (--dart-define=RICH_FX=true):
//   - Restores the original 3-layer atmosphere (radial base gradient +
//     accent corner glow + edge vignette) plus the blurred wallpaper
//     image when one is set.
//
// Theme vs image wallpaper:
//   - If the stored value is "theme:<id>", we render that theme
//     (solid color in flat mode; layers 1-3 in rich mode) and skip
//     layer 4.
//   - If the stored value is an image path/URI, we render the image
//     (no blur in flat mode; blurred in rich mode) on top of the
//     solid color base.
//   - If no value is stored, we render the default Midnight theme.

import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/kinrel_fx.dart';
import '../../../../core/utils/device_tier.dart';
import '../../data/chat_wallpaper_provider.dart';
import 'chat_background_theme.dart';
// Conditional import: web vs native image rendering for custom wallpapers.
import 'wallpaper_image_web.dart' if (dart.library.io) 'wallpaper_image_native.dart'
    as platform;

/// Chat background. Flat by default; rich mode restores the original
/// decorated multi-layer atmosphere.
class ChatBackground extends ConsumerWidget {
  const ChatBackground({
    super.key,
    required this.chatId,
    required this.child,
  });

  final String chatId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(wallpaperPathProvider(chatId));
    final theme = ChatBackgroundTheme.fromStoredValue(stored);
    final hasImage = stored != null &&
        stored.isNotEmpty &&
        !ChatBackgroundTheme.isThemeValue(stored);
    final bool lowRam = DeviceTierCache.instance.lowRam;

    if (KinrelFx.rich) {
      return _RichBackground(
        theme: theme,
        hasImage: hasImage,
        imagePath: stored,
        lowRam: lowRam,
        child: child,
      );
    }

    // Flat mode: single solid color + optional unblurred image with overlay.
    final Color baseColor = theme.baseColors.last;
    return Stack(
      children: [
        // Solid color base — always rendered as the bottom layer.
        Positioned.fill(child: ColoredBox(color: baseColor, child: const SizedBox.expand())),

        // Optional wallpaper image — rendered WITHOUT blur. A 50% dark
        // overlay keeps messages readable over any photo. Image is
        // cached at 1080×1920 to bound the decode size.
        if (hasImage)
          Positioned.fill(
            child: _FlatWallpaperImage(imagePath: stored),
          ),

        // Child (messages list). Outside the static layers so it can
        // repaint freely during scroll.
        child,
      ],
    );
  }
}

/// Renders the original decorated 3-layer atmosphere + optional
/// blurred wallpaper image. Used only when KinrelFx.rich == true.
class _RichBackground extends StatelessWidget {
  const _RichBackground({
    required this.theme,
    required this.hasImage,
    required this.imagePath,
    required this.lowRam,
    required this.child,
  });

  final ChatBackgroundTheme theme;
  final bool hasImage;
  final String? imagePath;
  final bool lowRam;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // PERF (Part C2): wrap the static background layers (1-4) in a
        // RepaintBoundary so the message-list child's repaints don't
        // force the gradient + blurred wallpaper to repaint too.
        RepaintBoundary(
          child: Stack(
            children: [
              if (hasImage && imagePath != null)
                Positioned.fill(
                  child: _BlurredWallpaperImage(
                      imagePath: imagePath!, lowRam: lowRam),
                ),

              // Layer 1: base ambient gradient.
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

              // Layer 2: accent corner glow (skipped on low-RAM).
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

              // Layer 3: edge vignette (skipped on low-RAM).
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
        child,
      ],
    );
  }
}

/// Flat wallpaper image — renders the image without blur, with a 50%
/// dark overlay for readability. Cache caps bound the decode size.
class _FlatWallpaperImage extends StatelessWidget {
  const _FlatWallpaperImage({required this.imagePath});
  final String imagePath;

  @override
  Widget build(BuildContext context) {
    final isDataUri = imagePath.startsWith('data:');
    if (isDataUri) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            imagePath,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: 1080,
            cacheHeight: 1920,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          // 50% dark overlay for readability.
          ColoredBox(
            color: Colors.black.withValues(alpha: 0.5),
            child: const SizedBox.expand(),
          ),
        ],
      );
    }
    final image = platform.buildWallpaperImageFromFile(
      imagePath,
      width: double.infinity,
      height: double.infinity,
      fallback: const SizedBox.shrink(),
    );
    if (image == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        ColoredBox(
          color: Colors.black.withValues(alpha: 0.5),
          child: const SizedBox.expand(),
        ),
      ],
    );
  }
}

/// Renders a custom wallpaper image with a heavy blur + darkening
/// overlay so it reads as atmosphere rather than a photo. Used only
/// in rich mode (KinrelFx.rich == true).
class _BlurredWallpaperImage extends StatelessWidget {
  const _BlurredWallpaperImage({required this.imagePath, required this.lowRam});
  final String imagePath;
  final bool lowRam;

  @override
  Widget build(BuildContext context) {
    final isDataUri = imagePath.startsWith('data:');
    final double effectiveSigma = DeviceTierCache.instance.rasterBudget.blurSigma
        .clamp(0.0, lowRam ? 8.0 : 24.0);

    if (isDataUri) {
      return RepaintBoundary(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
              sigmaX: effectiveSigma, sigmaY: effectiveSigma),
          child: Image.network(
            imagePath,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: 1080,
            cacheHeight: 1920,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      );
    }

    final image = platform.buildWallpaperImageFromFile(
      imagePath,
      width: double.infinity,
      height: double.infinity,
      fallback: const SizedBox.shrink(),
    );
    if (image == null) return const SizedBox.shrink();
    return RepaintBoundary(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
            sigmaX: effectiveSigma, sigmaY: effectiveSigma),
        child: image,
      ),
    );
  }
}
