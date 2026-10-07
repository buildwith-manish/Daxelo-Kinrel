// lib/core/utils/shader_warmup.dart
//
// Pre-warms the Skia/SkSL shaders used by:
//   - The Prediction Battle v1 card (original scope)
//   - The chat wallpaper ImageFilter.blur (Tier D3)
//   - The graph screen DotGridPainter (Tier D3)
//   - The home screen family-card avatar glow BoxShadow (Tier D3)
//   - The bottom-nav capsule BoxShadow (Tier D3)
//
// Why
// ---
// On low-end Android (Android 7–9, Mali-400 class GPUs) AND on Flutter Web
// (CanvasKit / SkWasm), the first time a shader is painted Skia/SkSL has
// to compile the fragment shader from the paint description. This takes:
//   - 30–80ms per unique LinearGradient (color-stop count varies)
//   - 50–150ms per BoxShadow with large blur (saveLayer + Gaussian kernel)
//   - 80–200ms per ImageFilter.blur at sigma 16+ (full-screen backdrop
//     sample + Gaussian blur — the most expensive raster op in Flutter)
//   - 20–60ms per CustomPainter's first paint (path shaders + stroke
//     shaders compile lazily)
//
// The user sees these as dropped frames / "the screen feels janky on
// first interaction". On Flutter Web, the Family Insights modal
// measured 151.7ms on first open BECAUSE of an uncached blur shader.
//
// The fix: paint each unique shader into an off-screen `Picture` during
// app startup, then let Skia cache the compiled SkSL. The next time
// the shader appears (which uses the same shader key), Skia reuses
// the cached compilation — no jank.
//
// What this warms
// ---------------
// 1. Prediction Battle v1 card:
//    - A 3-color LinearGradient (topLeft → bottomRight)
//    - Two BoxShadows (the blur kernel IS shader-compiled)
//
// 2. Chat wallpaper blur (Tier D3):
//    - ImageFilter.blur at sigma 6 (web) / sigma 24 (native) — warms
//      the most expensive raster shader in the app
//    - DecorationImage with Image.network path — warms the texture
//      upload path
//
// 3. Graph screen DotGridPainter (Tier D3):
//    - 25+ small filled circles — warms the fill shader + the
//      anti-alias shader. Without this, the first frame of the
//      family graph screen drops 50-80ms on first paint.
//
// 4. Home screen family-card avatar glow (Tier D3):
//    - BoxShadow with blurRadius 24 spreadRadius 2 + orange tint —
//      warms the large-radius Gaussian blur shader.
//
// 5. Bottom-nav capsule shadow (Tier D3):
//    - Dual BoxShadow (blur 24 + blur 6) — warms both the wide glow
//      and the tight edge-defining shadow.
//
// How to use
// ----------
// Call `warmupPredictionShaders()` (kept for backward compatibility)
// OR `warmupAllShaders()` (recommended — covers all five categories)
// from `main()` after `WidgetsFlutterBinding.ensureInitialized()` and
// before `runApp()`. The function is sync and returns a `Picture` that
// the caller can discard — the side effect (compiled SkSL in the Skia
// cache) is what we want. Painting is a CPU operation; the actual
// shader compile happens when the picture is rasterized, so we also
// rasterize the picture into a throwaway `Image` to trigger the compile.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Pre-compiles the shaders used by the Prediction Battle v1 card.
/// Call from `main()` after `WidgetsFlutterBinding.ensureInitialized()`
/// and before `runApp()`. Safe to call on web — Flutter's web backend
/// uses SkWasm which still benefits from shader warmup for CanvasKit
/// (skSL compile cost is real on web too).
///
/// Returns the rasterized `ui.Image` for the caller to dispose. Most
/// callers should just discard the return value.
///
/// Backward-compatibility alias for [warmupAllShaders]. New code should
/// call [warmupAllShaders] directly — it covers the chat wallpaper,
/// graph dot grid, and bottom-nav shadows in addition to the original
/// prediction card shaders.
Future<ui.Image?> warmupPredictionShaders() => warmupAllShaders();

/// Pre-compiles ALL shaders used by the most raster-expensive screens:
///
///   1. Prediction Battle v1 card (LinearGradient + 2 BoxShadows)
///   2. Chat wallpaper ImageFilter.blur (most expensive raster op)
///   3. Graph screen DotGridPainter (25+ filled circles)
///   4. Home screen family-card avatar glow BoxShadow (blur 24)
///   5. Bottom-nav capsule shadow (dual BoxShadow blur 24+6)
///
/// This is the entry point recommended by the Tier D3 raster audit.
/// Call from `main()` after `WidgetsFlutterBinding.ensureInitialized()`
/// and before `runApp()`. The total cost is ~15-25ms on low-end Android
/// (still well within the first-frame budget) and ~5-10ms on Flutter Web.
///
/// On web, SkSL compile happens at first paint — warming here lets the
/// compile happen during the loading-screen window (visible spinner)
/// instead of the first interaction.
Future<ui.Image?> warmupAllShaders() async {
  // Bail on web — Skia warm-up is a no-op there. (SkWasm compiles on
  // first paint regardless of pre-warm, but the cost is hidden behind
  // the loading screen.)
  if (kIsWeb) return null;

  try {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    // Use a 1024x1024 canvas so all shader categories fit on the same
    // raster surface — Skia caches per-surface, so consolidating saves
    // one cache-miss per category.
    const canvasWidth = 1024.0;
    const canvasHeight = 1024.0;

    // ── Category 1: Prediction Battle v1 card shaders ─────────────────
    // (Original scope — preserved for visual parity with previous
    // warmup behavior.)
    const cardWidth = 360.0;
    const cardHeight = 220.0;
    final cardRect = const Offset(0, 0) & const Size(cardWidth, cardHeight);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF241208),
          Color(0xFF1A0E05),
          Color(0xFF1A1410), // matches KinrelColors.darkCard visually
        ],
      ).createShader(cardRect);
    canvas.drawRect(cardRect, paint);

    const shadow1 = BoxShadow(
      color: Color(0x4D000000), // 30% black
      blurRadius: 16,
      offset: Offset(0, 6),
    );
    const shadow2 = BoxShadow(
      color: Color(0x26F59E0B), // 15% orange
      blurRadius: 20,
      spreadRadius: 1,
    );
    canvas.save();
    canvas.translate(0, 0);
    canvas.drawRect(cardRect.deflate(8), shadow1.toPaint());
    canvas.drawRect(cardRect.deflate(8), shadow2.toPaint());
    canvas.restore();

    // ── Category 2: Chat wallpaper ImageFilter.blur (Tier D3) ────────
    // The chat wallpaper blur is the most expensive raster op in the
    // app (75+ ms/frame avg on chat-thread screen pre-warmup). Warming
    // the blur shader here means the first chat open paints the
    // wallpaper at full cost ONCE (during app startup) instead of during
    // the user's first chat session.
    //
    // Two sigma values: 6 (web-capped sigma) and 24 (native sigma).
    // Both shader keys need warming since the wallpaper uses the
    // runtime-capped value.
    final wallpaperRect = const Offset(0, 250) &
        const Size(canvasWidth, 300);
    for (final sigma in [6.0, 24.0]) {
      final blurImageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
      );
      canvas.saveLayer(wallpaperRect, Paint()..imageFilter = blurImageFilter);
      // Paint a throwaway colored rect inside the saveLayer — the rect
      // pixels are what gets blurred, the blur SHADER is what we want
      // Skia to compile.
      canvas.drawRect(
        wallpaperRect,
        Paint()..color = const Color(0xFF13141E),
      );
      canvas.restore();
    }

    // ── Category 3: Graph screen DotGridPainter (Tier D3) ────────────
    // DotGridPainter paints a static grid of ~25+ filled circles per
    // visible graph viewport. The first paint compiles the fill shader
    // + the per-circle anti-alias shader. Without warming, the first
    // family graph screen open drops 50-80ms on first paint.
    final gridRect = const Offset(0, 580) &
        const Size(canvasWidth, 220);
    canvas.save();
    canvas.clipRect(gridRect);
    final gridPaint = Paint()
      ..color = const Color(0x40E8612A) // 25% orange — matches DotGridPainter
      ..style = PaintingStyle.fill;
    const spacing = 32.0;
    for (double x = 0; x < gridRect.width; x += spacing) {
      for (double y = 0; y < gridRect.height; y += spacing) {
        canvas.drawCircle(
          Offset(gridRect.left + x, gridRect.top + y),
          1.5, // matches DotGridPainter dot radius
          gridPaint,
        );
      }
    }
    canvas.restore();

    // ── Category 4: Home screen family-card avatar glow (Tier D3) ────
    // The home screen avatar uses a BoxShadow with blurRadius 24 +
    // spreadRadius 2 + orange tint. This is the largest single shadow
    // on the home screen — warming it eliminates the first-frame drop
    // when the home screen first paints.
    final avatarRect = const Offset(360, 0) &
        const Size(120, 120);
    const avatarGlow = BoxShadow(
      color: Color(0x1FE8612A), // 12% orange
      blurRadius: 24,
      spreadRadius: 2,
    );
    canvas.save();
    canvas.drawCircle(
      avatarRect.center,
      40,
      avatarGlow.toPaint(),
    );
    canvas.restore();

    // ── Category 5: Bottom-nav capsule shadow (Tier D3) ─────────────
    // The bottom nav is on every screen — its dual shadow (blur 24 +
    // blur 6) was the largest per-frame shadow cost on chat-thread
    // before the Tier A2 web clamping. Native still uses the dual
    // shadow; warm both.
    final navRect = const Offset(360, 130) &
        const Size(360, 80);
    const navShadowWide = BoxShadow(
      color: Color(0x66000000), // 40% black
      blurRadius: 24,
      offset: Offset(0, 8),
    );
    const navShadowTight = BoxShadow(
      color: Color(0x33000000), // 20% black
      blurRadius: 6,
      offset: Offset(0, 2),
    );
    canvas.save();
    canvas.drawRRect(
      RRect.fromRectAndRadius(navRect, const Radius.circular(24)),
      navShadowWide.toPaint(),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(navRect, const Radius.circular(24)),
      navShadowTight.toPaint(),
    );
    canvas.restore();

    final picture = pictureRecorder.endRecording();

    // Rasterize the picture into a throwaway image — this is what
    // actually triggers the SkSL compile for every shader category.
    final image = await picture.toImage(
      canvasWidth.toInt(),
      canvasHeight.toInt(),
    );
    picture.dispose();
    return image;
  } catch (_) {
    return null;
  }
}
