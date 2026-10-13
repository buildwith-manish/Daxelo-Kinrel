// lib/features/chat/presentation/widgets/wallpaper_patterns.dart
//
// DAXELO KINREL — Additional Wallpaper Patterns (TASK 2)
//
// Three new pattern painters + a Kolam tile, all using normalized
// coordinates and a shared [WallpaperPalette]. The approved
// Constellation pattern stays in constellation_pattern.dart.
//
// Draw operation counts per frame:
//   Branches:  6 drawPath (cubic curves) + 5 drawCircle = 11 ops
//   Contours:  6 drawPath (wave paths) = 6 ops
//   Kolam:     1 drawRect (ImageShader tile) = 1 op (after initial
//              tile generation, which happens once)
//
// All patterns: const painter, shouldRepaint compares palette only,
// RepaintBoundary, no animation.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/utils/device_tier.dart';
import '../chat_ui_tokens.dart';
import 'wallpaper_palette.dart';

// ═══════════════════════════════════════════════════════════════════════
// Branches — cubic paths + tip dots (11 draw ops per frame)
// ═══════════════════════════════════════════════════════════════════════

class BranchesPattern extends StatelessWidget {
  const BranchesPattern({super.key, this.palette = WallpaperPalette.standard});

  final WallpaperPalette palette;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BranchesPainter(palette: palette),
        size: Size.infinite,
      ),
    );
  }
}

class _BranchesPainter extends CustomPainter {
  const _BranchesPainter({required this.palette});
  final WallpaperPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final linePaint = Paint()
      ..color = palette.resolvedLineColor
      ..strokeWidth = palette.strokeWidth
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..color = palette.resolvedDotColor;

    // Helper to convert normalized coords.
    Offset p(double nx, double ny) => Offset(nx * w, ny * h);

    // Trunk: (0.5,1.0) → (0.5,0.4)
    final trunk = Path();
    trunk.moveTo(p(0.5, 1.0).dx, p(0.5, 1.0).dy);
    trunk.cubicTo(
      p(0.5, 0.789).dx, p(0.5, 0.789).dy,
      p(0.475, 0.632).dx, p(0.475, 0.632).dy,
      p(0.5, 0.4).dx, p(0.5, 0.4).dy,
    );
    canvas.drawPath(trunk, linePaint);

    // Branch paths — 5 branches, each a cubic curve.
    // Each entry: [startX, startY, c1x, c1y, c2x, c2y, endX, endY]
    const branches = [
      [0.5, 0.789, 0.625, 0.737, 0.7, 0.674, 0.775, 0.558],
      [0.5, 0.663, 0.3875, 0.611, 0.3125, 0.547, 0.275, 0.442],
      [0.5, 0.526, 0.6, 0.484, 0.6625, 0.421, 0.6875, 0.316],
      [0.4875, 0.463, 0.4125, 0.411, 0.3875, 0.347, 0.3875, 0.263],
      [0.5, 0.4, 0.5125, 0.326, 0.55, 0.274, 0.5875, 0.211],
    ];

    for (final b in branches) {
      final path = Path();
      path.moveTo(p(b[0], b[1]).dx, p(b[0], b[1]).dy);
      path.cubicTo(
        p(b[2], b[3]).dx, p(b[2], b[3]).dy,
        p(b[4], b[5]).dx, p(b[4], b[5]).dy,
        p(b[6], b[7]).dx, p(b[6], b[7]).dy,
      );
      canvas.drawPath(path, linePaint);
      // Tip dot at the branch end.
      canvas.drawCircle(p(b[6], b[7]), palette.dotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_BranchesPainter old) => old.palette != palette;
}

// ═══════════════════════════════════════════════════════════════════════
// Contours — 6 wave paths, no dots (6 draw ops per frame)
// ═══════════════════════════════════════════════════════════════════════

class ContoursPattern extends StatelessWidget {
  const ContoursPattern({super.key, this.palette = WallpaperPalette.standard});

  final WallpaperPalette palette;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ContoursPainter(palette: palette),
        size: Size.infinite,
      ),
    );
  }
}

class _ContoursPainter extends CustomPainter {
  const _ContoursPainter({required this.palette});
  final WallpaperPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final linePaint = Paint()
      ..color = palette.resolvedLineColor
      ..strokeWidth = palette.strokeWidth
      ..style = PaintingStyle.stroke;

    Offset p(double nx, double ny) => Offset(nx * w, ny * h);

    for (var k = 0; k < 6; k++) {
      final y0 = 0.158 + 0.147 * k;
      // M(-0.0625, y0) C(0.1875, y0-0.095) (0.375, y0+0.105)
      // (0.625, y0-0.010) S(0.9375, y0-0.042) (1.094, y0+0.010)
      // The S command's implicit first control point is the reflection
      // of the C's second control point about the C's endpoint.
      final c2 = p(0.375, y0 + 0.105); // C's second control point
      final endPoint = p(0.625, y0 - 0.010); // C's endpoint
      // Reflection of c2 about endPoint.
      final s1 = Offset(
        2 * endPoint.dx - c2.dx,
        2 * endPoint.dy - c2.dy,
      );

      final path = Path();
      path.moveTo(p(-0.0625, y0).dx, p(-0.0625, y0).dy);
      path.cubicTo(
        p(0.1875, y0 - 0.095).dx, p(0.1875, y0 - 0.095).dy,
        c2.dx, c2.dy,
        endPoint.dx, endPoint.dy,
      );
      // Smooth continuation (S = reflected first control + explicit
      // second control + endpoint).
      path.cubicTo(
        s1.dx, s1.dy,
        p(0.9375, y0 - 0.042).dx, p(0.9375, y0 - 0.042).dy,
        p(1.094, y0 + 0.010).dx, p(1.094, y0 + 0.010).dy,
      );
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(_ContoursPainter old) => old.palette != palette;
}

// ═══════════════════════════════════════════════════════════════════════
// Kolam lattice — 36 dp tile, ImageShader repeat (1 draw op per frame)
// ═══════════════════════════════════════════════════════════════════════

class KolamPattern extends StatefulWidget {
  const KolamPattern({super.key, this.palette = WallpaperPalette.standard});

  final WallpaperPalette palette;

  @override
  State<KolamPattern> createState() => _KolamPatternState();
}

class _KolamPatternState extends State<KolamPattern> {
  ui.Image? _tile;
  static const _tileSize = 36.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _generateTile();
  }

  @override
  void didUpdateWidget(KolamPattern oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.palette != widget.palette) {
      _tile = null;
      _generateTile();
    }
  }

  Future<void> _generateTile() async {
    // Don't render Kolam on low-RAM phones — fall back.
    if (DeviceTierCache.instance.lowRam) return;
    if (_tile != null) return;

    try {
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = const Size(_tileSize, _tileSize);

      final linePaint = Paint()
        ..color = widget.palette.resolvedLineColor
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      final dotPaint = Paint()..color = widget.palette.resolvedDotColor;

      // Five dots: corners + center.
      const dotR = 1.8;
      const corners = [
        Offset(5, 5),
        Offset(31, 5),
        Offset(31, 31),
        Offset(5, 31),
        Offset(18, 18),
      ];
      for (final c in corners) {
        canvas.drawCircle(c, dotR, dotPaint);
      }

      // Diamond path: (18,5) (31,18) (18,31) (5,18) closed.
      final diamond = Path()
        ..moveTo(18, 5)
        ..lineTo(31, 18)
        ..lineTo(18, 31)
        ..lineTo(5, 18)
        ..close();
      canvas.drawPath(diamond, linePaint);

      final picture = recorder.endRecording();
      final px = (_tileSize * dpr).round();
      final image = await picture.toImage(px, px);
      if (mounted) setState(() => _tile = image);
    } catch (_) {
      // Tile generation failed — the solid base shows through.
    }
  }

  @override
  void dispose() {
    _tile?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _tile;
    if (image == null) {
      // Tile not ready — the solid base color shows through.
      return const SizedBox.expand();
    }
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final scale = 1.0 / dpr;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _KolamTilePainter(image: image, scale: scale),
        size: Size.infinite,
      ),
    );
  }
}

class _KolamTilePainter extends CustomPainter {
  const _KolamTilePainter({required this.image, required this.scale});
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
  bool shouldRepaint(_KolamTilePainter old) =>
      old.image != image || old.scale != scale;
}
