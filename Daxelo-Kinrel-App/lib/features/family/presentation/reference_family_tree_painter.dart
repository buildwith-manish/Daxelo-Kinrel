import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:kinrel/presentation/screens/family_tree/family_tree_model.dart';

/// 100% pixel-perfect CustomPainter for Daxelo Kinrel family tree.
/// Additions v2:
///   • Outer animated dashed orbit ring around every node
///   • Real photo rendering via ui.Image (loaded externally)
///   • Scaled node sizes (grandparents slightly larger)
class FamilyTreePainter extends CustomPainter {
  final List<FamilyMember> members;
  final List<FamilyConnection> connections;
  final double pulseValue;    // 0.0→1.0 repeat reverse — glow pulse
  final double lineProgress;  // 0.0→1.0 repeat — dash animation
  final double orbitProgress; // 0.0→1.0 repeat — orbit ring spin
  final bool focusMode;

  // ── Design tokens ──────────────────────────────────────────────
  static const Color _glowBlue  = Color(0xFF4FC3F7);
  static const Color _glowGold  = Color(0xFFFFB300);
  static const Color _nodeFill  = Color(0xFF0D1F35);
  static const Color _selfFill  = Color(0xFF0F2040);
  static const Color _lineColor = Color(0xFF4FC3F7);
  static const Color _roleColor = Color(0xFFFFFFFF);
  static const Color _nameColor = Color(0xFFCFD8DC);
  static const Color _nickColor = Color(0xFF78909C);

  static const double _baseRadius = 42.0;
  static const double _selfRadius = 50.0;

  FamilyTreePainter({
    required this.members,
    required this.connections,
    required this.pulseValue,
    required this.lineProgress,
    required this.orbitProgress,
    required this.focusMode,
  });

  Map<String, FamilyMember> get _map => {for (final m in members) m.id: m};

  double _radius(FamilyMember m) =>
      m.isSelf ? _selfRadius : _baseRadius * (m.nodeScale);

  // ══════════════════════════════════════════════════════════════
  @override
  void paint(Canvas canvas, Size size) {
    final map = _map;

    // 1. Connections (below nodes)
    for (final c in connections) {
      final from = map[c.fromId];
      final to   = map[c.toId];
      if (from == null || to == null) continue;
      _drawConnection(canvas, from, to);
    }

    // 2. Nodes
    for (final m in members) {
      _drawNode(canvas, m);
    }
  }

  // ── Connection line ────────────────────────────────────────────
  void _drawConnection(Canvas canvas, FamilyMember from, FamilyMember to) {
    final dir  = to.position - from.position;
    final dist = dir.distance;
    if (dist < 1) return;
    final unit = dir / dist;

    final start = from.position + unit * (_radius(from) + 6);
    final end   = to.position   - unit * (_radius(to)   + 6);

    // Soft glow behind line
    canvas.drawLine(
      start, end,
      Paint()
        ..color = _lineColor.withOpacity(0.12)
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Animated dashed line
    _drawDashes(canvas, start, end, _lineColor.withOpacity(0.75), lineProgress);

    // Arrowhead
    _drawArrow(canvas, end, unit);
  }

  void _drawDashes(
      Canvas canvas, Offset start, Offset end, Color color, double progress) {
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

  void _drawArrow(Canvas canvas, Offset tip, Offset dir) {
    const len   = 8.0;
    const angle = 0.45;
    final l = _rotate(dir, angle)  * len;
    final r = _rotate(dir, -angle) * len;
    final paint = Paint()
      ..color = _lineColor.withOpacity(0.85)
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

  // ── Node ───────────────────────────────────────────────────────
  void _drawNode(Canvas canvas, FamilyMember member) {
    final c      = member.position;
    final r      = _radius(member);
    final accent = member.isSelf ? _glowGold : _glowBlue;
    final glow   = 0.07 + pulseValue * 0.08;

    // ① Soft outer glow halos
    for (int i = 3; i >= 1; i--) {
      canvas.drawCircle(
        c, r + 5.0 * i,
        Paint()
          ..color = accent.withOpacity(glow * i * 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7.0 * i),
      );
    }

    // ② Dark filled circle
    canvas.drawCircle(c, r,
        Paint()..color = member.isSelf ? _selfFill : _nodeFill);

    // ③ Avatar (photo or silhouette)
    _drawAvatar(canvas, c, r, member);

    // ④ Inner glowing border ring
    canvas.drawCircle(
      c, r,
      Paint()
        ..color = accent.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = member.isSelf ? 3.0 : 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      c, r,
      Paint()
        ..color = accent.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ⑤ Outer animated orbit dashed ring  ← NEW
    _drawOrbitRing(canvas, c, r, accent);

    // ⑥ Labels
    _drawLabels(canvas, member, c, r);
  }

  // ── Orbit ring (animated spinning dashes) ─────────────────────
  void _drawOrbitRing(Canvas canvas, Offset center, double r, Color accent) {
    final orbitR = r + 10.0 + pulseValue * 2.0; // breathes slightly
    const totalDashes = 20;
    const dashAngle   = 0.18; // radians per dash
    const gapAngle    = (2 * math.pi / totalDashes) - dashAngle;

    final paint = Paint()
      ..color = accent.withOpacity(0.30)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final spinOffset = orbitProgress * 2 * math.pi; // full rotation

    for (int i = 0; i < totalDashes; i++) {
      final startAngle = spinOffset + i * (dashAngle + gapAngle);
      final path = Path();
      // Draw arc segment
      final rect = Rect.fromCircle(center: center, radius: orbitR);
      path.addArc(rect, startAngle, dashAngle);
      canvas.drawPath(path, paint);
    }
  }

  // ── Avatar ─────────────────────────────────────────────────────
  void _drawAvatar(Canvas canvas, Offset c, double r, FamilyMember member) {
    // Clip to circle
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r - 2)));

    if (member.loadedImage != null) {
      // Real photo
      final img  = member.loadedImage!;
      final imgR = Rect.fromCenter(
          center: c,
          width: (r - 2) * 2,
          height: (r - 2) * 2);
      final srcR = Rect.fromLTWH(
          0, 0, img.width.toDouble(), img.height.toDouble());
      canvas.drawImageRect(img, srcR, imgR, Paint());
    } else {
      // Gradient silhouette placeholder
      final grad = RadialGradient(
        center: Alignment.topCenter,
        radius: 1.3,
        colors: [const Color(0xFF1E4060), const Color(0xFF091525)],
      );
      canvas.drawRect(
        Rect.fromCircle(center: c, radius: r),
        Paint()
          ..shader =
              grad.createShader(Rect.fromCircle(center: c, radius: r - 2)),
      );
      // Head
      canvas.drawCircle(
        c - Offset(0, r * 0.15),
        r * 0.33,
        Paint()..color = const Color(0xFF3A6680).withOpacity(0.85),
      );
      // Shoulders
      canvas.drawOval(
        Rect.fromCenter(
            center: c + Offset(0, r * 0.28),
            width: r * 1.15,
            height: r * 0.65),
        Paint()..color = const Color(0xFF3A6680).withOpacity(0.60),
      );
    }

    canvas.restore();
  }

  // ── Labels ─────────────────────────────────────────────────────
  void _drawLabels(Canvas canvas, FamilyMember m, Offset c, double r) {
    final top = c.dy + r + 9;

    _text(canvas, m.role, Offset(c.dx, top),
        const TextStyle(
            color: _roleColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3));

    _text(canvas, m.name, Offset(c.dx, top + 14),
        const TextStyle(color: _nameColor, fontSize: 10));

    _text(canvas, m.nickname, Offset(c.dx, top + 26),
        const TextStyle(
            color: _nickColor,
            fontSize: 9.5,
            fontStyle: FontStyle.italic));
  }

  void _text(Canvas canvas, String s, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 110);
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy));
  }

  @override
  bool shouldRepaint(FamilyTreePainter old) =>
      old.pulseValue   != pulseValue   ||
      old.lineProgress != lineProgress ||
      old.orbitProgress != orbitProgress ||
      old.focusMode    != focusMode;
}
