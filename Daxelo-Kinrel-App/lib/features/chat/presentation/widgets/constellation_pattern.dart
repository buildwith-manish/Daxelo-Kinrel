// lib/features/chat/presentation/widgets/constellation_pattern.dart
//
// DAXELO KINREL — Constellation Wallpaper Pattern (v143 redesign)
//
// Sparse, premium constellation background matching the reference
// image. 5 connection paths (some 2-node, one 3-node chain) with
// 7 nodes, distributed asymmetrically to avoid the center where
// message bubbles sit.
//
// Visual style (from reference analysis):
//   • Background: #0F111A (dark navy-blue, subtle blue undertone).
//   • Lines: #30385F (restrained blue-indigo), 1.4 dp thick, ~50%
//     alpha — clearly visible but never distracting.
//   • Nodes: #4A5275 (brighter blue-indigo), 2.5 dp radius, ~70%
//     alpha — small, elegant, slightly brighter than the lines.
//   • Pattern: irregular constellation fragments, NOT a complete
//     graph. Some paths connect 2 nodes, one connects 3. No long
//     diagonals crossing behind message bubbles.
//
// Implementation:
//   • Single CustomPainter (no tiling) with normalized coordinates
//     (0.0–1.0) → same pattern on every screen size.
//   • Fixed positions (not random) → predictable, balanced layout.
//   • shouldRepaint: false → zero per-frame cost after first paint.
//   • RepaintBoundary isolates from chat scroll rebuilds.
//   • Decorative only: excluded from semantics.

import 'package:flutter/material.dart';

import '../chat_ui_tokens.dart';

/// 7 fixed node positions in normalized coordinates (0.0–1.0).
/// Distributed asymmetrically — avoids the center (0.4–0.6, 0.4–0.6)
/// where message bubbles sit. Edges and corners preferred.
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
/// [0,1,2] is a 3-node chain across the top. The rest are pairs.
/// No long diagonals crossing the center.
const List<List<int>> _kConnections = [
  [0, 1, 2],  // top chain (3 nodes)
  [3, 4],     // center horizontal pair
  [5, 6],     // bottom pair
  [1, 3],     // short diagonal upper-left
  [2, 4],     // short diagonal upper-right
];

/// Sparse constellation pattern drawn with normalized coordinates.
class ConstellationPattern extends StatelessWidget {
  const ConstellationPattern({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: const _ConstellationPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _ConstellationPainter extends CustomPainter {
  const _ConstellationPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Lines: #30385F at ~50% alpha, 1.4 dp thick — clearly visible
    // but subtle against the dark navy background.
    final linePaint = Paint()
      ..color = ChatUi.wallLine.withValues(alpha: 0.5)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    // Nodes: #4A5275 at ~70% alpha, 2.5 dp radius — small, elegant,
    // slightly brighter than the lines.
    final dotPaint = Paint()
      ..color = ChatUi.wallDot.withValues(alpha: 0.7);

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
      canvas.drawCircle(node, 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter oldDelegate) => false;
}
