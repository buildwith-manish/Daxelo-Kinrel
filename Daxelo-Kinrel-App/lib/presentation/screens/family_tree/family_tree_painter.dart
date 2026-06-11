import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'family_tree_model.dart';

class FamilyTreePainter extends CustomPainter {
  final List<FamilyMember> members;
  final List<FamilyConnection> connections;
  final double pulseValue;
  final double lineProgress;
  final double orbitProgress;
  final bool focusMode;

  static const Color _bg        = Color(0xFF0A0E1A);
  static const Color _glowBlue  = Color(0xFF4FC3F7);
  static const Color _glowGold  = Color(0xFFFFB300);
  static const Color _nodeFill  = Color(0xFF0D1F35);
  static const Color _selfFill  = Color(0xFF0F2040);
  static const Color _lineColor = Color(0xFFFF8C42);   // orange dashes
  static const Color _dotColor  = Color(0xFFFF6D00);   // midpoint dot
  static const Color _roleColor = Color(0xFFFFFFFF);
  static const Color _nameColor = Color(0xFFCFD8DC);
  static const Color _nickColor = Color(0xFF78909C);
  static const double _nodeRadius = 42.0;
  static const double _selfRadius = 50.0;

  FamilyTreePainter({
    required this.members,
    required this.connections,
    required this.pulseValue,
    required this.lineProgress,
    this.orbitProgress = 0.0,
    required this.focusMode,
  });

  Map<String, FamilyMember> get _memberMap =>
      {for (final m in members) m.id: m};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = _bg,
    );

    final map = _memberMap;

    // Draw edges first (under nodes)
    for (final conn in connections) {
      final from = map[conn.fromId];
      final to   = map[conn.toId];
      if (from == null || to == null) continue;
      _drawEdge(canvas, from.position, to.position);
    }

    // Draw nodes on top
    for (final member in members) {
      _drawNode(canvas, member);
    }
  }

  // ── Edge: animated dashes + glowing orange midpoint dot ─────────────
  void _drawEdge(Canvas canvas, Offset from, Offset to) {
    final dir  = to - from;
    final dist = dir.distance;
    if (dist < 1) return;
    final unit = dir / dist;

    // Trim endpoints so lines don't overlap node circles
    final trim = _nodeRadius + 6.0;
    final start = from + unit * trim;
    final end   = to   - unit * trim;
    if ((end - start).distance < 1) return;

    // Soft glow underlay
    canvas.drawLine(
      start, end,
      Paint()
        ..color = _lineColor.withOpacity(0.12)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Animated dashes
    _drawDashedLine(canvas, start, end,
      Paint()
        ..color = _lineColor.withOpacity(0.75)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Glowing midpoint dot
    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

    // Outer glow ring
    canvas.drawCircle(mid, 10.0,
      Paint()
        ..color = _dotColor.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    // Solid filled dot
    canvas.drawCircle(mid, 5.5, Paint()..color = _dotColor);
    // Bright white center
    canvas.drawCircle(mid, 2.2, Paint()..color = Colors.white.withOpacity(0.85));
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const double dashLen = 9.0;
    const double gapLen  = 7.0;
    const double period  = dashLen + gapLen;

    final total = (end - start).distance;
    if (total == 0) return;
    final unit  = (end - start) / total;

    double drawn = -(lineProgress * period);
    while (drawn < total) {
      final s = math.max(drawn, 0.0);
      final e = math.min(drawn + dashLen, total);
      if (e > 0 && e > s) {
        canvas.drawLine(start + unit * s, start + unit * e, paint);
      }
      drawn += period;
    }
  }

  // ── Node ─────────────────────────────────────────────────────────────
  void _drawNode(Canvas canvas, FamilyMember member) {
    final c      = member.position;
    final radius = member.isSelf ? _selfRadius : _nodeRadius;
    final accent = member.isSelf ? _glowGold : _glowBlue;

    if (focusMode && !member.isSelf) {
      final dr = radius * 0.8;
      canvas.drawCircle(c, dr, Paint()..color = _nodeFill.withOpacity(0.4));
      canvas.drawCircle(c, dr,
        Paint()
          ..color = accent.withOpacity(0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0);
      _drawLabels(canvas, member, c, dr, dimmed: true);
      return;
    }

    // Pulse glow rings
    final gs = 0.08 + pulseValue * 0.07;
    for (int i = 3; i >= 1; i--) {
      canvas.drawCircle(c, radius + 5.0 * i,
        Paint()
          ..color = accent.withOpacity(gs * i * 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6.0 * i));
    }

    // Fill
    canvas.drawCircle(c, radius, Paint()..color = member.isSelf ? _selfFill : _nodeFill);

    // Avatar placeholder
    _drawAvatar(canvas, c, radius);

    // Glow ring
    canvas.drawCircle(c, radius,
      Paint()
        ..color = accent.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = member.isSelf ? 3.0 : 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));

    // Solid ring
    canvas.drawCircle(c, radius,
      Paint()
        ..color = accent.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);

    // Self: extra outer pulsing ring
    if (member.isSelf) {
      final extra = radius + 8 + pulseValue * 4;
      canvas.drawCircle(c, extra,
        Paint()
          ..color = accent.withOpacity(0.2 + pulseValue * 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }

    _drawLabels(canvas, member, c, radius);
  }

  void _drawAvatar(Canvas canvas, Offset c, double radius) {
    final rect = Rect.fromCircle(center: c, radius: radius - 2);
    canvas.drawCircle(c, radius - 2,
      Paint()..shader = const RadialGradient(
        center: Alignment.topCenter,
        radius: 1.2,
        colors: [Color(0xFF1A3A5C), Color(0xFF0A1A2E)],
      ).createShader(rect));

    final headR = radius * 0.32;
    final headC = c - Offset(0, radius * 0.18);
    canvas.drawCircle(headC, headR,
      Paint()..color = const Color(0xFF37607A).withOpacity(0.8));

    final shoulderPath = Path()
      ..addOval(Rect.fromCenter(
        center: c + Offset(0, radius * 0.25),
        width: radius * 1.1,
        height: radius * 0.65,
      ));
    canvas.drawPath(shoulderPath,
      Paint()..color = const Color(0xFF37607A).withOpacity(0.6));
  }

  void _drawLabels(Canvas canvas, FamilyMember member, Offset c, double radius,
      {bool dimmed = false}) {
    final top = c.dy + radius + 9;
    final a   = dimmed ? 0.3 : 1.0;

    // Name (large, prominent)
    _drawText(canvas, member.name, Offset(c.dx, top),
      TextStyle(color: _roleColor.withOpacity(a), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3));

    // Role / relationship
    if (member.role.isNotEmpty) {
      _drawText(canvas, member.role, Offset(c.dx, top + 14),
        TextStyle(
          color: member.isSelf
              ? const Color(0xFF4FC3F7).withOpacity(a)
              : _nameColor.withOpacity(a),
          fontSize: 10,
          fontWeight: FontWeight.w400,
        ));
    }

    // Hindi nickname
    if (member.nickname.isNotEmpty) {
      _drawText(canvas, member.nickname, Offset(c.dx, top + 27),
        TextStyle(color: _nickColor.withOpacity(a), fontSize: 9.5, fontStyle: FontStyle.italic));
    }
  }

  void _drawText(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 110);
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy));
  }

  @override
  bool shouldRepaint(FamilyTreePainter old) =>
      old.pulseValue    != pulseValue  ||
      old.lineProgress  != lineProgress ||
      old.focusMode     != focusMode;
}
