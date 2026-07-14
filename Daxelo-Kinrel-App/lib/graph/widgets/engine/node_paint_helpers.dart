// lib/graph/widgets/engine/node_paint_helpers.dart
// Extracted from graph_node.dart.
//
// Contains visual/paint helpers shared by GraphNode:
//   - ShimmerPainter: loading-state shimmer gradient sweep.
//   - kFullSepiaMatrix / kLightSepiaMatrix: P3.6 heritage/sepia
//     ColorFilter matrices for ancestor nodes.
//
// Extracted so graph_node.dart stays under 1,500 lines.

import 'package:flutter/material.dart';

// ── P3.6: Sepia matrices ──────────────────────────────────────────────
//
// ColorFilter matrices for the heritage/sepia wash on ancestor nodes.
// Ancestors (generationIndex <= -2) get full sepia; parents (-1) get a
// 50% mix between original color and full sepia. The matrices apply
// the classic sepia tone transform:
//   R' = 0.393*R + 0.769*G + 0.189*B
//   G' = 0.349*R + 0.686*G + 0.168*B
//   B' = 0.272*R + 0.534*G + 0.131*B
//
// The 50% mix for parents is achieved by lerping each matrix coefficient
// toward the identity matrix by 50%.

const List<double> kFullSepiaMatrix = [
  0.393, 0.769, 0.189, 0, 0,
  0.349, 0.686, 0.168, 0, 0,
  0.272, 0.534, 0.131, 0, 0,
  0,     0,     0,     1, 0,
];

const List<double> kLightSepiaMatrix = [
  // 50% mix between identity and full sepia.
  // identity[0]=1, sepia[0]=0.393 → 0.5*(1+0.393) = 0.6965
  // identity[1]=0, sepia[1]=0.769 → 0.5*(0+0.769) = 0.3845
  // etc.
  0.6965, 0.3845, 0.0945, 0, 0,
  0.1745, 0.8430, 0.0840, 0, 0,
  0.1360, 0.2670, 0.5655, 0, 0,
  0,      0,      0,      1, 0,
];

// ═══════════════════════════════════════════════════════════════════════
// SHIMMER PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// CustomPainter that renders a shimmer gradient sweep for the loading state.
class ShimmerPainter extends CustomPainter {
  ShimmerPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(value - 1, 0),
        end: Alignment(value, 0),
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant ShimmerPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}
