// lib/features/chat/presentation/widgets/constellation_pattern.dart
//
// DAXELO KINREL — Constellation Wallpaper Pattern (Chat UI Reference
// D13, v143 redesign)
//
// Sparse, elegant constellation background: 4-5 thin blue-purple
// connection lines, 5-7 small nodes, generous empty space.
//
// The tile is drawn ONCE into a cached ui.Image and tiled with an
// ImageShader — one drawRect per frame, no per-tile widgets, no
// gradient, no blur.
//
// v143 redesign:
//   • Tile: 400×600 logical pixels (was 320×480 — larger tile means
//     fewer tiles visible at once → sparser pattern).
//   • 6 nodes at fixed normalized positions (was 14 random).
//   • 4 connection lines between selected node pairs (was 9).
//   • Colors: wallDot #3A3270 (brighter blue-purple), wallLine #252D50
//     (subtle blue-purple), on chatBackground #0B1020 (dark navy).
//   • Fixed positions (not seeded random) → predictable, balanced
//     layout on every device.
//
// Performance notes:
//   • The tile is rasterized at logical 400×600 × devicePixelRatio and
//     cached per DPR bucket (static map) — generation happens once per
//     device, then every chat shares the same GPU texture.
//   • The painter is a single canvas.drawRect with a repeated
//     ImageShader and shouldRepaint: false — effectively free.
//   • Decorative only: excluded from semantics.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../chat_ui_tokens.dart';

/// Logical size of one repeating tile — 400×600 (v143: larger for
/// sparser pattern).
const Size _kTileSize = Size(400, 600);

/// Fixed node positions in normalized coordinates (0.0–1.0).
/// 6 nodes distributed naturally across the tile with generous spacing.
const List<Offset> _kNodes = [
  Offset(0.12, 0.18), // top-left
  Offset(0.38, 0.10), // top-center
  Offset(0.72, 0.28), // right-upper
  Offset(0.22, 0.52), // left-center
  Offset(0.55, 0.68), // bottom-center
  Offset(0.85, 0.82), // bottom-right
];

/// Fixed connection pairs (indices into _kNodes).
/// 4 lines — fragments of a constellation, not a complete graph.
/// Some connect 2 nodes, one connects 3 (chain 3→4→5).
const List<List<int>> _kConnections = [
  [0, 1], // top horizontal
  [1, 2], // top-right diagonal
  [3, 4], // center horizontal
  [4, 5], // bottom-right diagonal (chain)
];

/// Static per-DPR image cache (shared across all chats).
final Map<int, ui.Image> _constellationCache = <int, ui.Image>{};

/// True while a decode/generation is in flight (guards double loads).
bool _constellationLoading = false;

/// Builds (once) and returns the cached tile image for [dprBucket].
Future<ui.Image?> _tileImageFor(int dprBucket) async {
  final cached = _constellationCache[dprBucket];
  if (cached != null) return cached;
  if (_constellationLoading) return null;
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

/// Paints one 400×600 tile of the sparse constellation motif onto
/// [canvas]. Transparent background — the base color layer sits
/// beneath.
void _paintTile(Canvas canvas, Size tile) {
  final linePaint = Paint()
    ..color = ChatUi.wallLine
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  final dotPaint = Paint()..color = ChatUi.wallDot;

  // Convert normalized positions to pixel positions.
  final nodes = _kNodes
      .map((n) => Offset(n.dx * tile.width, n.dy * tile.height))
      .toList();

  // Draw connection lines.
  for (final conn in _kConnections) {
    for (var i = 0; i < conn.length - 1; i++) {
      canvas.drawLine(nodes[conn[i]], nodes[conn[i + 1]], linePaint);
    }
  }

  // Draw the nodes — small circles (1.5 dp radius).
  for (final node in nodes) {
    canvas.drawCircle(node, 1.5, dotPaint);
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
