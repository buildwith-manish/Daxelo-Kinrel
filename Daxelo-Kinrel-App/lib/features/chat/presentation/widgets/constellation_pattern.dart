// lib/features/chat/presentation/widgets/constellation_pattern.dart
//
// DAXELO KINREL — Constellation Wallpaper Pattern (Chat UI Reference
// D13, v143 redesign)
//
// Sparse, elegant constellation background: exactly 4 thin blue-purple
// connection lines, 6 small nodes, generous empty space. Drawn with
// normalized coordinates (0.0–1.0) so the SAME 6 nodes and 4 lines
// appear on every screen size — no tiling, no repetition, no dense
// clusters.
//
// v143 redesign:
//   • Single CustomPainter (no ImageShader tiling) — draws exactly
//     6 nodes + 4 lines for the whole viewport, every time.
//   • Normalized coordinates scale to any screen size.
//   • Colors: wallDot #3A3270 (brighter blue-purple), wallLine
//     #252D50 (subtle blue-purple), on chatBackground #0B1020 (dark
//     navy).
//   • Fixed positions (not random) → predictable, balanced layout.
//   • shouldRepaint: false → zero per-frame cost after first paint.
//
// Performance:
//   • 4 drawLine + 6 drawCircle = 10 canvas ops per paint. Trivial.
//   • No image caching, no async image generation, no ImageShader.
//   • RepaintBoundary wrapper in build() isolates it from chat
//     scroll rebuilds.
//   • Decorative only: excluded from semantics.

import 'package:flutter/material.dart';

import '../chat_ui_tokens.dart';

/// Fixed node positions in normalized coordinates (0.0–1.0).
/// 6 nodes distributed naturally with generous spacing — fragments
/// of a constellation, not a complete graph.
const List<Offset> _kNodes = [
  Offset(0.10, 0.15), // top-left
  Offset(0.32, 0.08), // top-center
  Offset(0.68, 0.22), // right-upper
  Offset(0.18, 0.48), // left-center
  Offset(0.52, 0.62), // bottom-center
  Offset(0.82, 0.78), // bottom-right
];

/// Fixed connection pairs (indices into _kNodes).
/// 4 lines — each connects 2 nodes, reading as fragments.
const List<List<int>> _kConnections = [
  [0, 1], // top horizontal
  [1, 2], // top-right diagonal
  [3, 4], // center horizontal
  [4, 5], // bottom-right diagonal
];

/// Sparse constellation pattern drawn with normalized coordinates.
/// Renders exactly 6 nodes + 4 lines for the whole viewport — no
/// tiling, no repetition. Sized by its parent (ChatBackground
/// positions it with Positioned.fill).
class ConstellationPattern extends StatelessWidget {
  const ConstellationPattern({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ConstellationPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  const _ConstellationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = ChatUi.wallLine
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()..color = ChatUi.wallDot;

    // Convert normalized positions to pixel positions.
    final nodes = _kNodes
        .map((n) => Offset(n.dx * size.width, n.dy * size.height))
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

  @override
  bool shouldRepaint(_ConstellationPainter oldDelegate) => false;
}
