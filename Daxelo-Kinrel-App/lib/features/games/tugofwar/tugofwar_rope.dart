// lib/features/games/tugofwar/tugofwar_rope.dart
//
// Tug of War — rope physics + arena painter.
//
// The server sends authoritative rope positions at up to ~6 Hz (throttled
// inside fn_tugofwar_pull). RopePhysicsController turns that stream into a
// 60 fps critically-damped spring so the flag glides; local taps add small
// impulses for sub-100 ms perceived latency. TugRopePainter renders the
// arena: braided sagging rope, waving pennant, victory lines and team glows.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/constants/brand_colors.dart';

/// Spring-driven interpolation of the authoritative rope position.
class RopePhysicsController extends ChangeNotifier {
  RopePhysicsController(TickerProvider vsync) {
    _ticker = vsync.createTicker(_tick);
  }

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  /// Authoritative position from the game row (-1 .. +1).
  double _target = 0;

  /// Animated position rendered by the painter.
  double _display = 0;

  /// Spring velocity (positions/sec) — drives tension + dust effects.
  double _velocity = 0;

  double get display => _display;
  double get velocity => _velocity;
  double get target => _target;
  Duration get elapsed => _last;

  static const double _stiffness = 46;
  static const double _damping = 9.5;

  void start() {
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void stop() {
    _ticker.stop();
  }

  /// New authoritative sample from Realtime.
  void setTarget(double value) {
    _target = value.clamp(-1.0, 1.0);
  }

  /// Snap (e.g. first paint after load).
  void snapTo(double value) {
    _target = value.clamp(-1.0, 1.0);
    _display = _target;
    _velocity = 0;
    notifyListeners();
  }

  /// Local tap feedback: a tiny nudge toward the tapper's side. The spring
  /// re-converges to the authoritative target, so impulses never drift.
  void impulse(TugSide side) {
    const nudge = 0.010;
    _display = (_display + (side == TugSide.a ? nudge : -nudge))
        .clamp(-1.08, 1.08);
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    final dt =
        ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _last = elapsed;
    if (dt <= 0) return;

    _velocity += ((_target - _display) * _stiffness - _velocity * _damping) *
        dt;
    _display += _velocity * dt;

    if (_display.clamp(-1.0, 1.0) != _display &&
        (_target - _display).abs() < 0.02) {
      _display = _display.clamp(-1.0, 1.0);
      _velocity = 0;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

enum TugSide { a, b }

/// The arena: track, rope, flag, victory lines, team glows.
///
/// DIRECTION CONTRACT (keep in sync with fn_tugofwar_pull):
///   • Team A (Ember) ALWAYS renders on the LEFT, Team B (Azure) on the
///     RIGHT — same anchoring as the lobby columns, team cards and the
///     advantage meter.
///   • `position` is the authoritative rope value: POSITIVE = Team A
///     advantage. The flag therefore moves LEFT as A pulls and RIGHT as
///     B pulls — every tap drags the rope toward the tapper's OWN side.
///   • A wins at position = +1 (flag rests on A's LEFT victory line),
///     B wins at position = -1 (flag rests on B's RIGHT victory line).
class TugRopePainter extends CustomPainter {
  TugRopePainter({
    required this.position,
    required this.velocity,
    required this.elapsed,
    required this.teamAColor,
    required this.teamBColor,
    this.wonSide,
  });

  /// -1 .. +1 (+ = Team A advantage → flag LEFT toward A's side).
  final double position;
  final double velocity;
  final Duration elapsed;
  final Color teamAColor;
  final Color teamBColor;

  /// Set once the match completes — saturates the winning side.
  final TugSide? wonSide;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final t = elapsed.inMilliseconds / 1000.0;

    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(18),
    );

    // ── Ground ───────────────────────────────────────────────────────
    canvas.save();
    canvas.clipRRect(trackRect);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF15161C),
    );

    // Team side washes — intensity follows the advantage share.
    final advantage = (position.clamp(-1.0, 1.0) + 1) / 2; // 0=B .. 1=A
    final aGlow = (advantage * 0.55).clamp(0.06, 0.55);
    final bGlow = ((1 - advantage) * 0.55).clamp(0.06, 0.55);
    if (wonSide == TugSide.a) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w / 2, h),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [teamAColor.withValues(alpha: 0.5), Colors.transparent],
          ).createShader(Offset.zero & size),
      );
    } else if (wonSide == TugSide.b) {
      canvas.drawRect(
        Rect.fromLTWH(w / 2, 0, w / 2, h),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [teamBColor.withValues(alpha: 0.5), Colors.transparent],
          ).createShader(Offset.zero & size),
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w / 2, h),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [teamAColor.withValues(alpha: aGlow), Colors.transparent],
          ).createShader(Offset.zero & size),
      );
      canvas.drawRect(
        Rect.fromLTWH(w / 2, 0, w / 2, h),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [teamBColor.withValues(alpha: bGlow), Colors.transparent],
          ).createShader(Offset.zero & size),
      );
    }

    // ── Field markings ───────────────────────────────────────────────
    final markings = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var i = -4; i <= 4; i++) {
      if (i == 0) continue;
      final x = w / 2 + (i / 5) * (w / 2 - 14);
      canvas.drawLine(Offset(x, 10), Offset(x, h - 10), markings);
    }

    // Center line.
    final centerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 2;
    canvas.drawLine(
        Offset(w / 2, 8), Offset(w / 2, h - 8), centerPaint);

    // Victory lines (pulse when the flag gets close).
    //
    // flagX is the SINGLE source of truth for the position→screen mapping:
    // positive position (Team A pulling) moves the flag LEFT toward A's
    // own victory line, negative moves it RIGHT toward B's line. Both the
    // rope rendering and the closeness pulse below must use it so they can
    // never disagree about which side the flag is on.
    double flagX(double pos) => w / 2 - pos * (w / 2 - 18);

    void drawVictoryLine(TugSide side, double edgeX, Color color) {
      final closeness =
          (1 - (flagX(position) - edgeX).abs() / (w / 2)).clamp(0.0, 1.0);
      final pulse = wonSide != null
          ? 0.9
          : (0.35 + 0.45 * closeness * (0.5 + 0.5 * math.sin(t * 2).abs()));
      final p = Paint()
        ..color = color.withValues(alpha: pulse.clamp(0.3, 0.95))
        ..strokeWidth = 3;
      canvas.drawLine(Offset(edgeX, 6), Offset(edgeX, h - 6), p);
      // soft halo
      final halo = Paint()
        ..color = color.withValues(alpha: 0.12 * pulse)
        ..strokeWidth = 9;
      canvas.drawLine(Offset(edgeX, 6), Offset(edgeX, h - 6), halo);
    }
    drawVictoryLine(TugSide.a, 14, teamAColor);
    drawVictoryLine(TugSide.b, w - 14, teamBColor);

    // ── The rope ─────────────────────────────────────────────────────
    // Positive position (A pulling) → rope/flag shift LEFT toward A.
    final midX = flagX(position);
    final sagBase = h * 0.16;
    final tension = (velocity.abs() / 3.2).clamp(0.0, 1.0);
    final sag = sagBase * (1 - 0.45 * tension);
    final anchorAY = h * 0.42;
    final ropeWave = math.sin(t * 2.4) * 2.0;

    final ropePath = Path()
      ..moveTo(10, anchorAY)
      ..quadraticBezierTo(
        midX,
        anchorAY + sag + ropeWave,
        w - 10,
        anchorAY,
      );

    // Braided texture: three offset strands.
    for (var i = 0; i < 3; i++) {
      final strandPath = Path()
        ..moveTo(10, anchorAY + i * 2.4 - 2.4)
        ..quadraticBezierTo(
          midX,
          anchorAY + sag + ropeWave + i * 2.4 - 2.4,
          w - 10,
          anchorAY + i * 2.4 - 2.4,
        );
      canvas.drawPath(
        strandPath,
        Paint()
          ..color = i == 1
              ? const Color(0xFFC9B08A)
              : const Color(0xFFA98F6B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );
    }
    canvas.drawPath(
      ropePath,
      Paint()
        ..color = const Color(0xFF8A7350)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );

    // Grip marks along the rope.
    final grip = Paint()
      ..color = const Color(0xFF6B5738)
      ..strokeWidth = 1.4;
    for (var i = 1; i < 16; i++) {
      final frac = i / 16;
      final gx = _lerp(10, w - 10, frac);
      final gy = _bezierY(10, anchorAY, midX,
          anchorAY + sag + ropeWave, frac);
      canvas.drawLine(
        Offset(gx - 3, gy - 3),
        Offset(gx + 3, gy + 3),
        grip,
      );
    }

    // ── The pennant flag at the rope's midpoint ──────────────────────
    final flagY = _bezierY(10, anchorAY, midX,
        anchorAY + sag + ropeWave, 0.5);
    final poleTop = flagY - h * 0.30;
    final wave = math.sin(t * 6);

    // Pole.
    canvas.drawLine(
      Offset(midX, flagY + 6),
      Offset(midX, poleTop),
      Paint()
        ..color = const Color(0xFFD8CBB6)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    // Pennant (waving triangle). The pennant streams AWAY from the pull
    // direction (like a flag on a moving rope): when A drags the rope
    // leftward, the cloth points right, and vice versa.
    final flagW = w * 0.085;
    final flagH = h * 0.11;
    final leading = position >= 0 ? 1.0 : -1.0;
    final flagPath = Path()
      ..moveTo(midX + 2, poleTop + 2)
      ..lineTo(midX + 2 + flagW * leading, poleTop + 2 + flagH * 0.5 + wave * 3)
      ..lineTo(midX + 2, poleTop + 2 + flagH)
      ..close();
    canvas.drawPath(
      flagPath,
      Paint()..color = KinrelColors.gold,
    );
    canvas.drawPath(
      flagPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Star on the flag.
    _drawStar(
      canvas,
      Offset(midX + 2 + flagW * 0.42 * leading, poleTop + 2 + flagH * 0.5),
      flagH * 0.22,
      Paint()..color = const Color(0xFF1E1608),
    );

    // ── Chalk dust when the rope is flying ───────────────────────────
    // Positive velocity = flag moving LEFT (A pulling), so the dust term
    // (+velocity*8) trails the motion to the RIGHT of the flag.
    if (tension > 0.25 && wonSide == null) {
      final dust = Paint()..color = Colors.white.withValues(alpha: 0.14);
      for (var i = 0; i < 6; i++) {
        final seed = ((t * 3 + i * 1.7) % 1.0);
        final dx = ((i * 37) % 21 - 10) * 1.6;
        canvas.drawCircle(
          Offset(midX + dx + velocity * 8 * seed,
              h - 12 - seed * h * 0.16),
          2.2 + seed * 2.4,
          dust,
        );
      }
    }

    canvas.restore();

    // ── Arena border ─────────────────────────────────────────────────
    canvas.drawRRect(
      trackRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _bezierY(
      double x0, double y0, double cx, double cy, double t) {
    final mt = 1 - t;
    return mt * mt * y0 + 2 * mt * t * cy + t * t * y0;
  }

  static void _drawStar(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final radius = i.isEven ? r : r * 0.45;
      final p = Offset(
        c.dx + radius * math.cos(angle),
        c.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(TugRopePainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.velocity != velocity ||
      oldDelegate.elapsed != elapsed ||
      oldDelegate.wonSide != wonSide;
}
