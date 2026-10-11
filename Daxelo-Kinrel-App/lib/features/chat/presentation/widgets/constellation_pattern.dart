// lib/features/chat/presentation/widgets/constellation_pattern.dart
//
// DAXELO KINREL — Constellation Wallpaper Pattern (Kin Thread / PR2 T4)
//
// A tiny pattern of ~40 dots and thin lines (the family-graph motif)
// drawn ONCE into a cached ui.Image and tiled with an ImageShader —
// one drawRect per frame, no per-tile widgets, no gradient, no blur.
//
// Contrast: the pattern color is ~6% lighter than the brand
// darkBackground (#131416), i.e. ~#212224 — visible enough to read as
// "quiet starfield / kin graph", dark enough to never compete with
// message bubbles.
//
// Performance notes:
//   • The tile is rasterized at logical 280×280 × devicePixelRatio and
//     cached per DPR bucket (static map) — generation happens once per
//     device, then every chat shares the same GPU texture.
//   • The painter is a single canvas.drawRect with a repeated
//     ImageShader and shouldRepaint: false — effectively free (~0.1ms
//     CPU; the GPU just tiles the cached texture).
//   • Seeded RNG → the identical pattern on every device and restart.
//   • Decorative only: excluded from semantics.
//
// Used by: ChatBackground when the resolved theme id is 'constellation'.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';

/// Logical size of one repeating tile.
const double _kTileSize = 280.0;

/// Total dots per tile (the "about 40" from the spec).
const int _kDotCount = 40;

/// Static per-DPR image cache (shared across all chats).
final Map<int, ui.Image> _constellationCache = <int, ui.Image>{};

/// True while a decode/generation is in flight (guards double loads).
bool _constellationLoading = false;

/// The pattern color: ~6% lighter than darkBackground.
Color get _patternColor =>
    Color.lerp(KinrelColors.darkBackground, Colors.white, 0.06)!;

/// Builds (once) and returns the cached tile image for [dpr].
Future<ui.Image?> _tileImageFor(int dprBucket) async {
  final cached = _constellationCache[dprBucket];
  if (cached != null) return cached;
  if (_constellationLoading) return null; // another load in flight
  _constellationLoading = true;
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _paintTile(canvas, _kTileSize);
    final picture = recorder.endRecording();
    final px = (_kTileSize * dprBucket).round();
    final image = await picture.toImage(px, px);
    _constellationCache[dprBucket] = image;
    return image;
  } catch (_) {
    return null;
  } finally {
    _constellationLoading = false;
  }
}

/// Paints one tile of the constellation motif onto [canvas].
/// Transparent background — the base color layer sits beneath.
void _paintTile(Canvas canvas, double tile) {
  final dotPaint = Paint()..color = _patternColor;
  final linePaint = Paint()
    ..color = _patternColor.withValues(alpha: 0.55)
    ..strokeWidth = 0.6
    ..style = PaintingStyle.stroke;

  // Deterministic layout: the same seed everywhere.
  final rng = math.Random(7);

  final dots = <Offset>[];
  for (var i = 0; i < _kDotCount; i++) {
    dots.add(Offset(rng.nextDouble() * tile, rng.nextDouble() * tile));
  }

  // Thin "constellation" lines: connect nearby pairs (≤ 90px apart),
  // a few per cluster — reads as the family graph, not a grid.
  final maxLineLength = tile * 0.32;
  var linesDrawn = 0;
  final maxLines = 14;
  for (var i = 0; i < dots.length && linesDrawn < maxLines; i++) {
    // Nearest neighbor of dot i.
    Offset? nearest;
    var nearestDist = double.infinity;
    for (var j = 0; j < dots.length; j++) {
      if (i == j) continue;
      final d = (dots[i] - dots[j]).distance;
      if (d < nearestDist) {
        nearestDist = d;
        nearest = dots[j];
      }
    }
    if (nearest != null && nearestDist <= maxLineLength) {
      canvas.drawLine(dots[i], nearest, linePaint);
      linesDrawn++;
    }
  }

  // The dots themselves — a mix of "star" sizes (1.0–2.2 radius).
  for (var i = 0; i < dots.length; i++) {
    final r = 1.0 + rng.nextDouble() * 1.2;
    canvas.drawCircle(dots[i], r, dotPaint);
  }
}

/// Tiled constellation pattern. Loads the cached tile image async in
/// initState, then renders a single shader-rect. Sized by its parent
/// (ChatBackground positions it with Positioned.fill).
class ConstellationPattern extends StatefulWidget {
  const ConstellationPattern({super.key});

  @override
  State<ConstellationPattern> createState() => _ConstellationPatternState();
}

class _ConstellationPatternState extends State<ConstellationPattern> {
  ui.Image? _image;
  int _dprBucket = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final bucket = dpr.round().clamp(1, 4).toInt();
    if (bucket != _dprBucket || _image == null) {
      _dprBucket = bucket;
      _load(bucket);
    }
  }

  Future<void> _load(int bucket) async {
    final image = await _tileImageFor(bucket);
    if (!mounted || image == null) return;
    if (_image != image) {
      setState(() => _image = image);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      // Tile not rasterized yet — the flat base color already shows
      // through; nothing else to render.
      return const SizedBox.expand();
    }
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ConstellationTilePainter(
          image: image,
          scale: 1.0 / _dprBucket,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Paints the repeated tile across the whole available area with an
/// ImageShader. One drawRect; shouldRepaint is false so it is cached
/// by the raster cache behind the RepaintBoundary.
class _ConstellationTilePainter extends CustomPainter {
  const _ConstellationTilePainter({
    required this.image,
    required this.scale,
  });

  final ui.Image image;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    // diagonal3Values is a long-stable constructor: [scale,0,0,0,
    // 0,scale,0,0, 0,0,1,0, 0,0,0,1].
    final matrix = Matrix4.diagonal3Values(scale, scale, 1.0);
    final shader = ImageShader(
      image,
      TileMode.repeated,
      TileMode.repeated,
      matrix.storage,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_ConstellationTilePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.scale != scale;
}
