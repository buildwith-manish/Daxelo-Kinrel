import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'family_tree_model.dart';

/// Pixel-perfect CustomPainter replicating the Daxelo Kinrel family tree UI.
/// Features: glowing node rings, animated dashed connecting lines,
/// 3-line labels (role / name / nickname), self-highlight node.
///
/// Performance optimizations:
/// - Viewport culling: off-screen nodes and connections are skipped
/// - Cached Paint objects: created once as static finals instead of per-frame
/// - Proper shouldRepaint: checks members/connections identity changes
class FamilyTreePainter extends CustomPainter {
  final List<FamilyMember> members;
  final List<FamilyConnection> connections;
  final double pulseValue;   // 0.0 → 1.0 looping (for glow pulse)
  final double lineProgress; // 0.0 → 1.0 looping (for animated dash)
  final double orbitProgress; // 0.0 → 1.0 looping (for orbit ring spin)
  final bool focusMode;

  // ── Design tokens ─────────────────────────────────────────────
  static const Color _bg          = Color(0xFF0A0E1A);
  static const Color _glowBlue    = Color(0xFF4FC3F7); // accent ring
  static const Color _glowGold    = Color(0xFFFFB300); // self ring
  static const Color _nodeFill    = Color(0xFF0D1F35);
  static const Color _selfFill    = Color(0xFF0F2040);
  static const Color _lineColor   = Color(0xFF4FC3F7);
  static const Color _roleColor   = Color(0xFFFFFFFF);
  static const Color _nameColor   = Color(0xFFCFD8DC);
  static const Color _nickColor   = Color(0xFF78909C);
  static const double _nodeRadius = 42.0;
  static const double _selfRadius = 48.0;

  // ── Cached Paint objects (created once, reused every frame) ──────
  static final Paint _bgPaint = Paint()..color = _bg;
  static final Paint _lineGlowPaint = Paint()
    ..color = _lineColor.withOpacity(0.15)
    ..strokeWidth = 4
    ..style = PaintingStyle.stroke
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  static final Paint _dashPaint = Paint()
    ..color = _lineColor.withOpacity(0.7)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;
  static final Paint _arrowPaint = Paint()
    ..color = _lineColor.withOpacity(0.8)
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  FamilyTreePainter({
    required this.members,
    required this.connections,
    required this.pulseValue,
    required this.lineProgress,
    this.orbitProgress = 0.0,
    required this.focusMode,
  });

  // ── Build a lookup map for member positions ────────────────────
  Map<String, FamilyMember> get _memberMap =>
      {for (final m in members) m.id: m};

  @override
  void paint(Canvas canvas, Size size) {
    // Background fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      _bgPaint,
    );

    final map = _memberMap;

    // Compute visible rect for viewport culling (with padding for labels/glow)
    const viewportPadding = 80.0;
    final visibleRect = Rect.fromLTWH(
      -viewportPadding,
      -viewportPadding,
      size.width + viewportPadding * 2,
      size.height + viewportPadding * 2,
    );

    // 1. Draw connections first (under nodes) — with viewport culling
    for (final conn in connections) {
      final from = map[conn.fromId];
      final to   = map[conn.toId];
      if (from == null || to == null) continue;
      // Skip connections where both endpoints are off-screen
      if (!_isVisible(from.position, visibleRect, _nodeRadius + 20) &&
          !_isVisible(to.position, visibleRect, _nodeRadius + 20)) {
        continue;
      }
      _drawAnimatedLine(canvas, from.position, to.position);
    }

    // 2. Draw nodes — with viewport culling
    for (final member in members) {
      final radius = member.isSelf ? _selfRadius : _nodeRadius;
      // Skip off-screen nodes (including label space below)
      if (!_isVisible(member.position, visibleRect, radius + 50)) {
        continue;
      }
      _drawNode(canvas, member);
    }
  }

  /// Check if a point is within the visible viewport (with padding)
  bool _isVisible(Offset position, Rect visibleRect, double padding) {
    final nodeRect = Rect.fromCircle(center: position, radius: padding);
    return visibleRect.overlaps(nodeRect);
  }

  // ── Animated dashed arrow line ─────────────────────────────────
  void _drawAnimatedLine(Canvas canvas, Offset from, Offset to) {
    final dir = (to - from);
    final dist = dir.distance;
    if (dist == 0) return;
    final unit = dir / dist;

    // Shorten line so it doesn't overlap node circles
    final r = _nodeRadius + 4;
    final start = from + unit * r;
    final end   = to   - unit * r;

    // Glow underline (cached paint)
    canvas.drawLine(start, end, _lineGlowPaint);

    // Dashed animated line (cached paint)
    _drawDashedLine(canvas, start, end, _dashPaint, lineProgress);

    // Arrowhead
    _drawArrow(canvas, end, unit);
  }

  void _drawDashedLine(
      Canvas canvas, Offset start, Offset end, Paint paint, double progress) {
    const dashLen  = 8.0;
    const gapLen   = 6.0;
    const period   = dashLen + gapLen;

    final total = (end - start).distance;
    if (total == 0) return;
    final unit  = (end - start) / total;

    // Offset the dash pattern by progress to animate
    double offset = progress * period;
    double drawn   = -offset;

    while (drawn < total) {
      final dashStart = math.max(drawn, 0.0);
      final dashEnd   = math.min(drawn + dashLen, total);
      if (dashEnd > 0) {
        canvas.drawLine(
          start + unit * dashStart,
          start + unit * dashEnd,
          paint,
        );
      }
      drawn += period;
    }
  }

  void _drawArrow(Canvas canvas, Offset tip, Offset dir) {
    const arrowLen   = 8.0;
    const arrowAngle = 0.45; // radians

    final left  = _rotateOffset(dir, arrowAngle)  * arrowLen;
    final right = _rotateOffset(dir, -arrowAngle) * arrowLen;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((tip - left).dx,  (tip - left).dy)
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((tip - right).dx, (tip - right).dy);

    canvas.drawPath(path, _arrowPaint);
  }

  Offset _rotateOffset(Offset o, double angle) {
    return Offset(
      o.dx * math.cos(angle) - o.dy * math.sin(angle),
      o.dx * math.sin(angle) + o.dy * math.cos(angle),
    );
  }

  // ── Node drawing ───────────────────────────────────────────────
  void _drawNode(Canvas canvas, FamilyMember member) {
    final center = member.position;
    final radius = member.isSelf ? _selfRadius : _nodeRadius;
    final accent = member.isSelf ? _glowGold : _glowBlue;

    // In focus mode, dim non-self nodes
    if (focusMode && !member.isSelf) {
      final dimRadius = radius * 0.8;
      canvas.drawCircle(
        center,
        dimRadius,
        Paint()..color = _nodeFill.withOpacity(0.4),
      );
      canvas.drawCircle(
        center,
        dimRadius,
        Paint()
          ..color = accent.withOpacity(0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      // Dimmed labels
      _drawLabels(canvas, member, center, dimRadius, dimmed: true);
      return;
    }

    // Outer glow layers (pulse animation)
    // Note: MaskFilter.blur is GPU-expensive; keep at 2 layers instead of 3
    final glowStrength = 0.08 + pulseValue * 0.07;
    for (int i = 2; i >= 1; i--) {
      canvas.drawCircle(
        center,
        radius + (5.0 * i),
        Paint()
          ..color = accent.withOpacity(glowStrength * i * 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6.0 * i),
      );
    }

    // Dark fill circle
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = member.isSelf ? _selfFill : _nodeFill,
    );

    // Avatar placeholder (gradient face silhouette)
    _drawAvatarPlaceholder(canvas, center, radius, member);

    // Glowing border ring (single blur layer instead of two)
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = accent.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = member.isSelf ? 2.8 : 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Solid ring on top of glow (no blur — cheap)
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = accent.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Labels below node
    _drawLabels(canvas, member, center, radius);
  }

  void _drawAvatarPlaceholder(
      Canvas canvas, Offset center, double radius, FamilyMember member) {
    // Gradient background inside circle
    final gradient = RadialGradient(
      center: Alignment.topCenter,
      radius: 1.2,
      colors: [
        const Color(0xFF1A3A5C),
        const Color(0xFF0A1A2E),
      ],
    );

    final rect = Rect.fromCircle(center: center, radius: radius - 2);
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()..shader = gradient.createShader(rect),
    );

    // Simple silhouette (head + shoulders)
    final headRadius = radius * 0.32;
    final headCenter = center - Offset(0, radius * 0.18);

    // Head
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()..color = const Color(0xFF37607A).withOpacity(0.8),
    );

    // Shoulders arc
    final shoulderPaint = Paint()
      ..color = const Color(0xFF37607A).withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final shoulderPath = Path();
    final shoulderTop = center + Offset(0, radius * 0.25);
    shoulderPath.addOval(Rect.fromCenter(
      center: shoulderTop,
      width: radius * 1.1,
      height: radius * 0.65,
    ));
    canvas.drawPath(shoulderPath, shoulderPaint);
  }

  void _drawLabels(
      Canvas canvas, FamilyMember member, Offset center, double radius,
      {bool dimmed = false}) {
    final labelTop = center.dy + radius + 8;
    final alpha = dimmed ? 0.3 : 1.0;

    // Role — white bold
    _drawText(
      canvas,
      member.role,
      Offset(center.dx, labelTop),
      TextStyle(
        color: _roleColor.withOpacity(alpha),
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );

    // Name — light grey
    _drawText(
      canvas,
      member.name,
      Offset(center.dx, labelTop + 14),
      TextStyle(
        color: _nameColor.withOpacity(alpha),
        fontSize: 10,
        fontWeight: FontWeight.w400,
      ),
    );

    // Nickname (Hindi kinship) — muted
    if (member.nickname.isNotEmpty) {
      _drawText(
        canvas,
        member.nickname,
        Offset(center.dx, labelTop + 26),
        TextStyle(
          color: _nickColor.withOpacity(alpha),
          fontSize: 9.5,
          fontStyle: FontStyle.italic,
        ),
      );
    }
  }

  void _drawText(Canvas canvas, String text, Offset position, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 120);

    tp.paint(
      canvas,
      Offset(position.dx - tp.width / 2, position.dy),
    );
  }

  @override
  bool shouldRepaint(FamilyTreePainter old) =>
      old.pulseValue != pulseValue ||
      old.lineProgress != lineProgress ||
      old.orbitProgress != orbitProgress ||
      old.focusMode != focusMode ||
      !identical(old.members, members) ||
      !identical(old.connections, connections);
}
