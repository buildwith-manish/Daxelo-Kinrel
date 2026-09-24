// lib/core/utils/shader_warmup.dart
//
// Pre-warms the Skia/SkSL shaders used by the Prediction Battle v1 card
// + reveal screen so the first frame that paints them doesn't drop.
//
// Why
// ---
// On low-end Android (Android 7–9, Mali-400 class GPUs), the first time
// a `LinearGradient` is painted, Skia has to compile a fragment shader
// from the gradient description. This takes 30–80ms per unique gradient
// (color-stop count, tile mode, blend mode). The user sees this as a
// single dropped frame on the family hub when the prediction card
// scrolls into view for the first time.
//
// The fix: paint the gradient into an off-screen `Picture` during app
// startup, then let Skia cache the compiled SkSL. The next time the
// gradient appears (which uses the same shader key), Skia reuses the
// cached compilation — no jank.
//
// What this warms
// ---------------
// The Prediction Battle v1 card uses:
//   - A 3-color LinearGradient (topLeft → bottomRight)
//   - A `Border` (no shader needed — vector stroke)
//   - Two `BoxShadow`s (the blur kernel IS shader-compiled)
//
// We reproduce all three here. If the card's gradient changes, update
// the colors below.
//
// How to use
// ----------
// Call `warmupPredictionShaders()` from `main()` after
// `WidgetsFlutterBinding.ensureInitialized()` and before `runApp()`.
// The function is sync and returns a `Picture` that the caller can
// discard — the side effect (compiled SkSL in the Skia cache) is what
// we want. Painting is a CPU operation; the actual shader compile
// happens when the picture is rasterized, so we also rasterize the
// picture into a throwaway `Image` to trigger the compile.

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Pre-compiles the shaders used by the Prediction Battle v1 card.
/// Call from `main()` after `WidgetsFlutterBinding.ensureInitialized()`
/// and before `runApp()`. Safe to call on web — Flutter's web backend
/// does not use Skia for gradients, so the call is a no-op there.
///
/// Returns the rasterized `ui.Image` for the caller to dispose. Most
/// callers should just discard the return value.
Future<ui.Image?> warmupPredictionShaders() async {
  // Bail on web — Skia warm-up is a no-op there.
  // ignore: avoid_classes_with_only_static_members
  if (kIsWeb) return null;

  try {
    final pictureRecorder = ui.PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    const cardWidth = 360.0;
    const cardHeight = 220.0;

    // Paint the same 3-color gradient as the card.
    final rect = const Offset(0, 0) & const Size(cardWidth, cardHeight);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF241208),
          Color(0xFF1A0E05),
          Color(0xFF1A1410), // matches KinrelColors.darkCard visually
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // Paint two box shadows to warm the blur shader. The exact shadow
    // color/blur radius used by the card is fine — Skia caches by
    // shader key, not by exact parameters.
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
    // BoxShadow.toPaint creates a MaskFilter shader; we paint it on the
    // same canvas to warm the blur compilation.
    canvas.drawRect(rect.deflate(8), shadow1.toPaint());
    canvas.drawRect(rect.deflate(8), shadow2.toPaint());
    canvas.restore();

    final picture = pictureRecorder.endRecording();

    // Rasterize the picture into a throwaway image — this is what
    // actually triggers the SkSL compile.
    final image = await picture.toImage(cardWidth.toInt(), cardHeight.toInt());
    picture.dispose();
    return image;
  } catch (_) {
    return null;
  }
}
