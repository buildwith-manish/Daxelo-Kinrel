// lib/features/chat/presentation/widgets/constellation_pattern.dart
//
// DAXELO KINREL — Constellation Wallpaper Pattern (Kin Thread / PR2 T4)
//
// The "Constellation" wallpaper preset: a 320×480 dp tile of 14 dots
// and 9 thin connecting lines (the family-graph motif) drawn ONCE
// into a cached ui.Image and tiled with an ImageShader — one drawRect
// per frame, no per-tile widgets, no gradient, no blur.
//
// Spec geometry (chat UI reference D13):
//   • Base color: chatBackground #131416 (painted by ChatBackground
//     beneath this pattern).
//   • Lines: 1 dp, #1A1C27.
//   • Dots: #1F2230.
//   • Dots (x, y, radius):
//     (30,50,3) (90,90,4) (150,60,3) (110,160,3) (230,100,3)
//     (290,140,4) (270,210,3) (40,270,3) (100,310,4) (170,350,3)
//     (250,340,3) (300,400,3) (60,420,3) (130,450,4)
//   • Lines (x1,y1 → x2,y2):
//     30,50→90,90; 90,90→150,60; 90,90→110,160; 230,100→290,140;
//     290,140→270,210; 40,270→100,310; 100,310→170,350;
//     250,340→300,400; 60,420→130,450
//
// Performance notes:
//   • The tile is rasterized at logical 320×480 × devicePixelRatio and
//     cached per DPR bucket (static map) — generation happens once per
//     device, then every chat shares the same GPU texture.
//   • The painter is a single canvas.drawRect with a repeated
//     ImageShader and shouldRepaint keyed on the image — effectively
//     free (the GPU just tiles the cached texture).
//   • Fixed coordinate tables → the identical pattern on every device
//     and restart (deterministic, no RNG).
//   • Decorative only: excluded from semantics.
//
// Used by: ChatBackground when the resolved theme id is 'constellation'.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Logical size of one repeating tile (spec D13).
const double _kTileW = 320.0;
const double _kTileH = 480.0;

/// Line color — #1A1C27 at 1 dp.
const Color _kLineColor = Color(0xFF1A1C27);

/// Dot color — #1F2230.
const Color _kDotColor = Color(0xFF1F2230);

/// The 14 dots: (x, y, radius).
const List<(double, double, double)> _kDots = [
  (30, 50, 3),
  (90, 90, 4),
  (150, 60, 3),
  (110, 160, 3),
  (230, 100, 3),
  (290, 140, 4),
  (270, 210, 3),
  (40, 270, 3),
  (100, 310, 4),
  (170, 350, 3),
  (250, 340, 3),
  (300, 400, 3),
  (60, 420, 3),
  (130, 450, 4),
];

/// The 9 lines: (x1, y1, x2, y2).
const List<(double, double, double, double)> _kLines = [
  (30, 50, 90, 90),
  (90, 90, 150, 60),
  (90, 90, 110, 160),
  (230, 100, 290, 140),
  (290, 140, 270, 210),
  (40, 270, 100, 310),
  (100, 310, 170, 350),
  (250, 340, 300, 400),
  (60, 420, 130, 450),
];

/// Static per-DPR image cache (shared across all chats).
final Map<int, ui.Image> _constellationCache = <int, ui.Image>{};

/// True while a decode/generation is in flight (guards double loads).
bool _constellationLoading = false;

/// Builds (once) and returns the cached tile image for [dprBucket].
Future<ui.Image?> _tileImageFor(int dprBucket) async {
  final cached = _constellationCache[dprBucket];
  if (cached != null) return cached;
  if (_constellationLoading) return null; // another load in flight
  _constellationLoading = true;
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _paintTile(canvas);
    final picture = recorder.endRecording();
    final px = (_kTileW * dprBucket).round();
    final py = (_kTileH * dprBucket).round();
    final image = await picture.toImage(px, py);
    _constellationCache[dprBucket] = image;
    return image;
  } catch (_) {
    return null;
  } finally {
    _constellationLoading = false;
  }
}

/// Paints one 320×480 tile of the constellation motif onto [canvas].
/// Transparent background — the base color layer sits beneath.
void _paintTile(Canvas canvas) {
  final dotPaint = Paint()..color = _kDotColor;
  final linePaint = Paint()
    ..color = _kLineColor
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  for (final (x1, y1, x2, y2) in _kLines) {
    canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
  }
  for (final (x, y, r) in _kDots) {
    canvas.drawCircle(Offset(x, y), r, dotPaint);
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
/// ImageShader. One drawRect; shouldRepaint is keyed on the image so
/// it is cached by the raster cache behind the RepaintBoundary.
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
