// lib/features/chat/presentation/widgets/constellation_pattern.dart
//
// DAXELO KINREL — Constellation Wallpaper Pattern (v143 redesign)
//
// Sparse, premium constellation background matching the reference
// image. 5 connection paths (some 2-node, one 3-node chain) with
// 7 nodes, distributed asymmetrically to avoid the center where
// message bubbles sit.
//
// v143 wallpaper system: now accepts an optional [WallpaperPalette]
// (default = the neutral standard palette). The geometry (node
// positions, connections) is UNCHANGED — only the colors/alphas/
// stroke width come from the palette.
//
// Implementation:
//   • Single CustomPainter (no tiling) with normalized coordinates.
//   • Fixed positions (not random).
//   • shouldRepaint: true only when the palette changes.
//   • RepaintBoundary isolates from chat scroll rebuilds.
//   • Decorative only: excluded from semantics.

import 'package:flutter/material.dart';

import '../chat_ui_tokens.dart';
import 'wallpaper_palette.dart';

/// 7 fixed node positions in normalized coordinates (0.0–1.0).
/// Distributed asymmetrically — avoids the center where message
/// bubbles sit. Edges and corners preferred.
/// DO NOT change these — they are the approved geometry.
const List<Offset> _kNodes = [
  Offset(0.08, 0.10),  // 0: top-left corner
  Offset(0.26, 0.05),  // 1: top-center-left
  Offset(0.70, 0.14),  // 2: top-right area
  Offset(0.14, 0.35),  // 3: left-center-upper
  Offset(0.88, 0.40),  // 4: right-center
  Offset(0.22, 0.72),  // 5: bottom-left
  Offset(0.62, 0.88),  // 6: bottom-right
];

/// 5 connection paths — irregular constellation fragments.
/// DO NOT change these — they are the approved geometry.
const List<List<int>> _kConnections = [
  [0, 1, 2],  // top chain (3 nodes)
  [3, 4],     // center horizontal pair
  [5, 6],     // bottom pair
  [1, 3],     // short diagonal upper-left
  [2, 4],     // short diagonal upper-right
];

/// Sparse constellation pattern drawn with normalized coordinates.
/// Accepts an optional [palette] to tint the colors (default = neutral
/// standard). The geometry is always the approved 7-node, 5-path layout.
class ConstellationPattern extends StatelessWidget {
  const ConstellationPattern({
    super.key,
    this.palette = WallpaperPalette.standard,
  });

  final WallpaperPalette palette;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ConstellationPainter(palette: palette),
        size: Size.infinite,
      ),
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  const _ConstellationPainter({required this.palette});
  final WallpaperPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = palette.resolvedLineColor
      ..strokeWidth = palette.strokeWidth
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()..color = palette.resolvedDotColor;

    // Convert normalized positions to pixel positions.
    final nodes = _kNodes
        .map((n) => Offset(n.dx * size.width, n.dy * size.height))
        .toList();

    // Draw connection paths.
    for (final conn in _kConnections) {
      for (var i = 0; i < conn.length - 1; i++) {
        canvas.drawLine(nodes[conn[i]], nodes[conn[i + 1]], linePaint);
      }
    }

    // Draw the nodes.
    for (final node in nodes) {
      canvas.drawCircle(node, palette.dotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter old) => old.palette != palette;
}
