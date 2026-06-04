import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';

// ═══════════════════════════════════════════════════════════════════════
// DATA MODELS
// ═══════════════════════════════════════════════════════════════════════

/// A node in the relationship graph picker
class RelationshipGraphNode {
  const RelationshipGraphNode({
    required this.id,
    required this.label,
    required this.hindiLabel,
    required this.icon,
    required this.position,
    this.isSelf = false,
    this.lineage,
    this.gender,
  });

  final String id;
  final String label;       // English term (e.g., "Father")
  final String hindiLabel;  // Hindi term (e.g., "पिताजी")
  final IconData icon;
  final Offset position;
  final bool isSelf;
  final String? lineage;    // 'paternal', 'maternal', 'marital'
  final String? gender;     // 'male', 'female'
}

/// A connection between two nodes
class RelationshipGraphEdge {
  const RelationshipGraphEdge({
    required this.fromId,
    required this.toId,
    this.label,
    this.isDashed = true,
  });

  final String fromId;
  final String toId;
  final String? label;
  final bool isDashed;
}

// ═══════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER
// ═══════════════════════════════════════════════════════════════════════

/// Constellation-style graph painter for relationship selection.
/// Uses Kinrel orange (#E8612A) and amber (#F59240) color scheme
/// with animated glow pulses, orbit rings, and dashed connections.
class RelationshipGraphPainter extends CustomPainter {
  final List<RelationshipGraphNode> nodes;
  final List<RelationshipGraphEdge> edges;
  final double pulseValue;    // 0.0→1.0 repeat reverse — glow pulse
  final double lineProgress;  // 0.0→1.0 repeat — dash animation
  final double orbitProgress; // 0.0→1.0 repeat — orbit ring spin
  final String? selectedNodeId;
  final String? hoveredNodeId;

  // ── Kinrel Design Tokens ─────────────────────────────────────────
  static const Color _glowOrange = Color(0xFFE8612A);
  static const Color _glowAmber  = Color(0xFFF59240);
  static const Color _nodeFill   = Color(0xFF1A1B2E);
  static const Color _selfFill   = Color(0xFF201818);
  static const Color _lineColor  = Color(0xFFE8612A);
  static const Color _roleColor  = Color(0xFFF5F0EE);
  static const Color _nameColor  = Color(0xFFC9B4A8);
  static const Color _nickColor  = Color(0xFF8A7A72);

  static const double _baseRadius = 36.0;
  static const double _selfRadius = 44.0;

  RelationshipGraphPainter({
    required this.nodes,
    required this.edges,
    required this.pulseValue,
    required this.lineProgress,
    required this.orbitProgress,
    this.selectedNodeId,
    this.hoveredNodeId,
  });

  Map<String, RelationshipGraphNode> get _map =>
      {for (final n in nodes) n.id: n};

  double _radius(RelationshipGraphNode n) =>
      n.isSelf ? _selfRadius : _baseRadius;

  Color _accentFor(RelationshipGraphNode n) {
    if (n.isSelf) return _glowAmber;
    if (n.lineage == 'paternal') return _glowOrange;
    if (n.lineage == 'maternal') return _glowAmber;
    if (n.lineage == 'marital') return const Color(0xFFD4AF37);
    if (n.gender == 'female') return const Color(0xFFFF69B4).withOpacity(0.7);
    return _glowOrange;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final map = _map;

    // 1. Background radial gradient glow
    _drawBackgroundGlow(canvas, size);

    // 2. Connections (below nodes)
    for (final e in edges) {
      final from = map[e.fromId];
      final to   = map[e.toId];
      if (from == null || to == null) continue;
      _drawConnection(canvas, from, to, e);
    }

    // 3. Nodes
    for (final n in nodes) {
      _drawNode(canvas, n);
    }
  }

  // ── Background glow ──────────────────────────────────────────────
  void _drawBackgroundGlow(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final grad = RadialGradient(
      center: Alignment.center,
      radius: 0.6,
      colors: [
        _glowOrange.withOpacity(0.06 + pulseValue * 0.03),
        _glowAmber.withOpacity(0.03),
        Colors.transparent,
      ],
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = grad.createShader(
        Rect.fromCircle(center: center, radius: size.width / 2),
      ),
    );
  }

  // ── Connection line ──────────────────────────────────────────────
  void _drawConnection(
    Canvas canvas,
    RelationshipGraphNode from,
    RelationshipGraphNode to,
    RelationshipGraphEdge edge,
  ) {
    final dir  = to.position - from.position;
    final dist = dir.distance;
    if (dist < 1) return;
    final unit = dir / dist;

    final start = from.position + unit * (_radius(from) + 6);
    final end   = to.position   - unit * (_radius(to)   + 6);

    final isSelected = selectedNodeId == from.id || selectedNodeId == to.id;

    // Soft glow behind line
    canvas.drawLine(
      start, end,
      Paint()
        ..color = _lineColor.withOpacity(isSelected ? 0.20 : 0.10)
        ..strokeWidth = isSelected ? 6 : 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Animated dashed line
    if (edge.isDashed) {
      _drawDashes(
        canvas,
        start,
        end,
        _lineColor.withOpacity(isSelected ? 0.90 : 0.60),
        lineProgress,
      );
    } else {
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = _lineColor.withOpacity(isSelected ? 0.90 : 0.60)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round,
      );
    }

    // Arrowhead
    _drawArrow(canvas, end, unit, isSelected);

    // Edge label
    if (edge.label != null) {
      final mid = Offset(
        (start.dx + end.dx) / 2,
        (start.dy + end.dy) / 2 - 8,
      );
      _drawText(
        canvas,
        edge.label!,
        mid,
        TextStyle(
          fontFamily: KinrelTypography.monoFont,
          color: _lineColor.withOpacity(0.5),
          fontSize: 8,
          letterSpacing: 0.5,
        ),
      );
    }
  }

  void _drawDashes(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double progress,
  ) {
    const dash = 8.0;
    const gap  = 6.0;
    const period = dash + gap;

    final total = (end - start).distance;
    if (total < 1) return;
    final unit  = (end - start) / total;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    double pos = -(progress * period);
    while (pos < total) {
      final s = math.max(pos, 0.0);
      final e = math.min(pos + dash, total);
      if (e > s) canvas.drawLine(start + unit * s, start + unit * e, paint);
      pos += period;
    }
  }

  void _drawArrow(Canvas canvas, Offset tip, Offset dir, bool isSelected) {
    const len   = 7.0;
    const angle = 0.45;
    final l = _rotate(dir, angle)  * len;
    final r = _rotate(dir, -angle) * len;
    final paint = Paint()
      ..color = _lineColor.withOpacity(isSelected ? 0.90 : 0.70)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(tip, tip - l, paint);
    canvas.drawLine(tip, tip - r, paint);
  }

  Offset _rotate(Offset o, double a) => Offset(
    o.dx * math.cos(a) - o.dy * math.sin(a),
    o.dx * math.sin(a) + o.dy * math.cos(a),
  );

  // ── Node ─────────────────────────────────────────────────────────
  void _drawNode(Canvas canvas, RelationshipGraphNode node) {
    final c      = node.position;
    final r      = _radius(node);
    final accent = _accentFor(node);
    final isSelected = selectedNodeId == node.id;
    final isHovered  = hoveredNodeId == node.id;
    final glow   = 0.07 + pulseValue * 0.08;

    final effectiveRadius = r + (isSelected ? 3.0 : 0.0) + (isHovered ? 2.0 : 0.0);

    // ① Soft outer glow halos
    for (int i = 3; i >= 1; i--) {
      canvas.drawCircle(
        c, effectiveRadius + 5.0 * i,
        Paint()
          ..color = accent.withOpacity(glow * i * (isSelected ? 0.6 : 0.45))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7.0 * i),
      );
    }

    // ② Dark filled circle
    canvas.drawCircle(
      c, effectiveRadius,
      Paint()..color = node.isSelf ? _selfFill : _nodeFill,
    );

    // ③ Icon in center
    _drawIconInCircle(canvas, c, effectiveRadius, node, accent);

    // ④ Inner glowing border ring
    canvas.drawCircle(
      c, effectiveRadius,
      Paint()
        ..color = accent.withOpacity(isSelected ? 1.0 : 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3.0 : 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      c, effectiveRadius,
      Paint()
        ..color = accent.withOpacity(isSelected ? 0.8 : 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ⑤ Outer animated orbit dashed ring
    _drawOrbitRing(canvas, c, effectiveRadius, accent);

    // ⑥ Selection ring (extra thick)
    if (isSelected) {
      canvas.drawCircle(
        c, effectiveRadius + 4,
        Paint()
          ..color = accent.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }

    // ⑦ Labels
    _drawLabels(canvas, node, c, effectiveRadius);
  }

  // ── Orbit ring (animated spinning dashes) ────────────────────────
  void _drawOrbitRing(Canvas canvas, Offset center, double r, Color accent) {
    final orbitR = r + 10.0 + pulseValue * 2.0;
    const totalDashes = 16;
    const dashAngle   = 0.16;
    const gapAngle    = (2 * math.pi / totalDashes) - dashAngle;

    final paint = Paint()
      ..color = accent.withOpacity(0.25)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final spinOffset = orbitProgress * 2 * math.pi;

    for (int i = 0; i < totalDashes; i++) {
      final startAngle = spinOffset + i * (dashAngle + gapAngle);
      final path = Path();
      final rect = Rect.fromCircle(center: center, radius: orbitR);
      path.addArc(rect, startAngle, dashAngle);
      canvas.drawPath(path, paint);
    }
  }

  // ── Icon rendering ───────────────────────────────────────────────
  void _drawIconInCircle(
    Canvas canvas,
    Offset c,
    double r,
    RelationshipGraphNode node,
    Color accent,
  ) {
    // Draw icon using a text-based approach with a symbol
    // Since we can't easily render IconData in CustomPainter,
    // we draw a gender/lineage symbol instead
    if (node.isSelf) {
      // "You" anchor — draw a star/diamond
      _drawStar(canvas, c, r * 0.35, accent.withOpacity(0.85), 4);
    } else {
      // Draw gender/relationship icon
      _drawRelationshipSymbol(canvas, c, r, node, accent);
    }
  }

  void _drawStar(
    Canvas canvas,
    Offset center,
    double size,
    Color color,
    int points,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    for (int i = 0; i < points * 2; i++) {
      final angle = (i * math.pi / points) - math.pi / 2;
      final r = i.isEven ? size : size * 0.45;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawRelationshipSymbol(
    Canvas canvas,
    Offset c,
    double r,
    RelationshipGraphNode node,
    Color accent,
  ) {
    final paint = Paint()
      ..color = accent.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = accent.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final symbolSize = r * 0.35;

    // Draw a simple person silhouette based on gender
    if (node.gender == 'female') {
      // Circle head + triangle body
      canvas.drawCircle(
        Offset(c.dx, c.dy - symbolSize * 0.6),
        symbolSize * 0.3,
        paint,
      );
      final triPath = Path()
        ..moveTo(c.dx, c.dy - symbolSize * 0.25)
        ..lineTo(c.dx - symbolSize * 0.5, c.dy + symbolSize * 0.6)
        ..lineTo(c.dx + symbolSize * 0.5, c.dy + symbolSize * 0.6)
        ..close();
      canvas.drawPath(triPath, fillPaint);
      canvas.drawPath(triPath, paint);
    } else {
      // Circle head + body arc
      canvas.drawCircle(
        Offset(c.dx, c.dy - symbolSize * 0.6),
        symbolSize * 0.3,
        paint,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(c.dx, c.dy + symbolSize * 0.2),
          width: symbolSize * 1.0,
          height: symbolSize * 0.9,
        ),
        math.pi,
        math.pi,
        false,
        paint,
      );
    }
  }

  // ── Labels ───────────────────────────────────────────────────────
  void _drawLabels(
    Canvas canvas,
    RelationshipGraphNode node,
    Offset c,
    double r,
  ) {
    final top = c.dy + r + 9;

    // Hindi kinship term (primary, in orange)
    _drawText(
      canvas,
      node.hindiLabel,
      Offset(c.dx, top),
      TextStyle(
        fontFamily: 'NotoSansDevanagari',
        color: _accentFor(node).withOpacity(0.9),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );

    // English term (secondary)
    _drawText(
      canvas,
      node.label,
      Offset(c.dx, top + 14),
      const TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        color: _nameColor,
        fontSize: 10,
        fontWeight: FontWeight.w500,
      ),
    );

    // Lineage badge (if any)
    if (node.lineage != null && node.lineage!.isNotEmpty) {
      _drawText(
        canvas,
        node.lineage!.toUpperCase(),
        Offset(c.dx, top + 26),
        TextStyle(
          fontFamily: KinrelTypography.monoFont,
          color: _nickColor,
          fontSize: 8,
          letterSpacing: 1.0,
        ),
      );
    }
  }

  void _drawText(Canvas canvas, String s, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 100);
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy));
  }

  @override
  bool shouldRepaint(RelationshipGraphPainter old) =>
      old.pulseValue     != pulseValue ||
      old.lineProgress   != lineProgress ||
      old.orbitProgress  != orbitProgress ||
      old.selectedNodeId != selectedNodeId ||
      old.hoveredNodeId  != hoveredNodeId;
}
