// lib/features/chat/presentation/widgets/constellation_pattern.dart
//
// DAXELO KINREL — Constellation Wallpaper Pattern (Chat UI Reference
// D13)
//
// The quiet family-graph motif behind the chat. The tile is drawn ONCE
// into a cached ui.Image and tiled with an ImageShader — one drawRect
// per frame, no per-tile widgets, no gradient, no blur.
//
// Exact geometry (D13):
//   • Tile: 320×480 logical pixels, tiled edge-to-edge.
//   • 14 dots, color #1F2230 (ChatUi.wallDot).
//   • 9 lines, color #1A1C27 (ChatUi.wallLine), 1 dp wide.
//   • Deterministic placement (seeded) — the identical pattern on
//     every device and restart.
//
// Contrast: both colors sit a few percent above chatBackground
// (#131416) — visible enough to read as "quiet starfield / kin
// graph", dark enough to never compete with message bubbles.
//
// Performance notes:
//   • The tile is rasterized at logical 320×480 × devicePixelRatio and
//     cached per DPR bucket (static map) — generation happens once per
//     device, then every chat shares the same GPU texture.
//   • The painter is a single canvas.drawRect with a repeated
//     ImageShader and shouldRepaint: false — effectively free (~0.1ms
//     CPU; the GPU just tiles the cached texture).
//   • Decorative only: excluded from semantics.
//
// Used by: ChatBackground when the resolved theme id is 'constellation'.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../chat_ui_tokens.dart';

/// Logical size of one repeating tile — 320×480 (D13).
const Size _kTileSize = Size(320, 480);

/// Dots per tile (D13: 14).
const int _kDotCount = 14;

/// Lines per tile (D13: 9), 1 dp wide.
const int _kLineCount = 9;

/// Static per-DPR image cache (shared across all chats).
final Map<int, ui.Image> _constellationCache = <int, ui.Image>{};

/// True while a decode/generation is in flight (guards double loads).
bool _constellationLoading = false;

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
    final px = (_kTileSize.width * dprBucket).round();
    final py = (_kTileSize.height * dprBucket).round();
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
void _paintTile(Canvas canvas, Size tile) {
  final dotPaint = Paint()..color = ChatUi.wallDot;
  final linePaint = Paint()
    ..color = ChatUi.wallLine
    ..strokeWidth =
        1 // D13: 1 dp lines
    ..style = PaintingStyle.stroke;

  // Deterministic layout: the same seed everywhere.
  final rng = math.Random(13);

  final dots = <Offset>[];
  for (var i = 0; i < _kDotCount; i++) {
    dots.add(
      Offset(rng.nextDouble() * tile.width, rng.nextDouble() * tile.height),
    );
  }

  // Exactly _kLineCount constellation lines: connect each dot (in
  // order) to its nearest neighbour, skipping duplicates — reads as
  // the family graph, not a grid.
  final connected = <int>{};
  var linesDrawn = 0;
  for (var i = 0; i < dots.length && linesDrawn < _kLineCount; i++) {
    Offset? nearest;
    var nearestIdx = -1;
    var nearestDist = double.infinity;
    for (var j = 0; j < dots.length; j++) {
      if (i == j) continue;
      final d = (dots[i] - dots[j]).distance;
      if (d < nearestDist) {
        nearestDist = d;
        nearest = dots[j];
        nearestIdx = j;
      }
    }
    if (nearest != null && !connected.contains(i * 100 + nearestIdx)) {
      canvas.drawLine(dots[i], nearest, linePaint);
      connected.add(i * 100 + nearestIdx);
      connected.add(nearestIdx * 100 + i);
      linesDrawn++;
    }
  }

  // The dots themselves — a quiet mix of "star" sizes (1.2–2.4 radius).
  for (var i = 0; i < dots.length; i++) {
    final r = 1.2 + rng.nextDouble() * 1.2;
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
  const _ConstellationTilePainter({required this.image, required this.scale});

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
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ConstellationTilePainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.scale != scale;
}
