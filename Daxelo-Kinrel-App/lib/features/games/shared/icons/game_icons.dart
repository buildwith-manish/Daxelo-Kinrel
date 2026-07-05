// lib/features/games/shared/icons/game_icons.dart
//
// Game icons — loads glossy 3D PNG assets (generated via z.ai image generation)
// with fallback to custom-painted line icons if the asset is missing.
//
// All 18 game icons are 1024×1024 PNGs in assets/icons/games/{game-id}.png
// Generated with a consistent style: rounded squircle, glossy 3D, solid
// background matching GameIconTokens.colors, professional app store quality.

import 'package:flutter/material.dart';

/// Base widget for all game icons.
/// Tries to load the PNG asset first; falls back to CustomPainter if missing.
class GameIcon extends StatelessWidget {
  const GameIcon({super.key, required this.gameId, this.size = 24, this.color});
  final String gameId;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Try PNG asset first
    final assetPath = 'assets/icons/games/$gameId.png';
    // Use Image.asset with errorBuilder fallback to CustomPainter
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to custom-painted icon
          final c = color ?? _colorFor(gameId);
          return CustomPaint(
            size: Size(size, size),
            painter: _painterFor(gameId, c),
          );
        },
      ),
    );
  }

  Color _colorFor(String id) {
    const map = <String, Color>{
      'ghost-painter': Color(0xFFEC4899), 'freeze-dash': Color(0xFF10B981),
      'sos': Color(0xFFF59E0B), 'antakshari': Color(0xFF8B5CF6),
      'bingo': Color(0xFF06B6D4), 'checkers': Color(0xFF6366F1),
      'ludo': Color(0xFFE11D48), 'carrom': Color(0xFFF59E0B),
      'chess': Color(0xFF64748B), 'chitmatch': Color(0xFFEC4899),
      'nameplace': Color(0xFF10B981), 'tictactoe': Color(0xFF8B5CF6),
      'truthordare': Color(0xFFEF4444), 'twotruths': Color(0xFFD946EF),
      'dotsboxes': Color(0xFF06B6D4), 'hot-seat': Color(0xFFF59E0B),
      'relation-riddles': Color(0xFF8B5CF6), 'truth-streak': Color(0xFFE8612A),
    };
    return map[id] ?? const Color(0xFFE8612A);
  }

  CustomPainter _painterFor(String id, Color color) {
    switch (id) {
      case 'ghost-painter':    return _GhostPainterIcon(color);
      case 'freeze-dash':      return _FreezeDashIcon(color);
      case 'sos':              return _SosIcon(color);
      case 'antakshari':       return _AntakshariIcon(color);
      case 'bingo':            return _BingoIcon(color);
      case 'checkers':         return _CheckersIcon(color);
      case 'ludo':             return _LudoIcon(color);
      case 'carrom':           return _CarromIcon(color);
      case 'chess':            return _ChessIcon(color);
      case 'chitmatch':        return _TripleMatchIcon(color);
      case 'nameplace':        return _NamePlaceIcon(color);
      case 'tictactoe':        return _TicTacToeIcon(color);
      case 'truthordare':      return _TruthOrDareIcon(color);
      case 'twotruths':        return _TwoTruthsIcon(color);
      case 'dotsboxes':        return _DotsBoxesIcon(color);
      case 'hot-seat':         return _HotSeatIcon(color);
      case 'relation-riddles':  return _RiddleIcon(color);
      case 'truth-streak':     return _TruthStreakIcon(color);
      default:                 return _DefaultGameIcon(color);
    }
  }
}

// ── Base painter with common helpers ──────────────────────────────

abstract class _GameIconPainter extends CustomPainter {
  _GameIconPainter(this.color);
  final Color color;

  Paint get fillPaint => Paint()..color = color..style = PaintingStyle.fill;
  Paint get strokePaint => Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
  Paint get whitePaint => Paint()..color = Colors.white..style = PaintingStyle.fill;
}

// ── Ghost Painter: brush with motion trail ────────────────────────

class _GhostPainterIcon extends _GameIconPainter {
  _GhostPainterIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Brush handle (diagonal)
    canvas.drawLine(Offset(s * 0.2, s * 0.8), Offset(s * 0.55, s * 0.45), strokePaint..strokeWidth = s * 0.08);
    // Brush tip
    final tip = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(s * 0.6, s * 0.4), s * 0.08, tip);
    // Motion trail (3 dots getting smaller)
    canvas.drawCircle(Offset(s * 0.72, s * 0.28), s * 0.05, tip);
    canvas.drawCircle(Offset(s * 0.82, s * 0.18), s * 0.035, tip);
    canvas.drawCircle(Offset(s * 0.9, s * 0.1), s * 0.02, tip);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Freeze & Dash: running figure with frost ──────────────────────

class _FreezeDashIcon extends _GameIconPainter {
  _FreezeDashIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Head
    canvas.drawCircle(Offset(s * 0.55, s * 0.2), s * 0.1, fillPaint);
    // Body (lean forward)
    canvas.drawLine(Offset(s * 0.5, s * 0.3), Offset(s * 0.45, s * 0.6), strokePaint..strokeWidth = s * 0.06);
    // Front leg
    canvas.drawLine(Offset(s * 0.45, s * 0.6), Offset(s * 0.7, s * 0.8), strokePaint..strokeWidth = s * 0.06);
    // Back leg
    canvas.drawLine(Offset(s * 0.45, s * 0.6), Offset(s * 0.25, s * 0.75), strokePaint..strokeWidth = s * 0.06);
    // Arm forward
    canvas.drawLine(Offset(s * 0.48, s * 0.4), Offset(s * 0.7, s * 0.35), strokePaint..strokeWidth = s * 0.05);
    // Frost accent (small snowflake near feet)
    final frost = Paint()..color = Color(0xFF93C5FD)..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(s * 0.75, s * 0.85), s * 0.06, frost);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── SOS: three connected dots diagonal ─────────────────────────────

class _SosIcon extends _GameIconPainter {
  _SosIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Three dots in diagonal
    canvas.drawCircle(Offset(s * 0.25, s * 0.75), s * 0.12, fillPaint);
    canvas.drawCircle(Offset(s * 0.5, s * 0.5), s * 0.12, fillPaint);
    canvas.drawCircle(Offset(s * 0.75, s * 0.25), s * 0.12, fillPaint);
    // Connecting line
    canvas.drawLine(Offset(s * 0.25, s * 0.75), Offset(s * 0.75, s * 0.25), strokePaint..strokeWidth = s * 0.03);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Antakshari: musical note with chain ────────────────────────────

class _AntakshariIcon extends _GameIconPainter {
  _AntakshariIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Note head
    canvas.drawCircle(Offset(s * 0.3, s * 0.7), s * 0.12, fillPaint);
    // Note stem
    canvas.drawLine(Offset(s * 0.4, s * 0.7), Offset(s * 0.4, s * 0.25), strokePaint..strokeWidth = s * 0.05);
    // Note flag
    final path = Path()..moveTo(s * 0.4, s * 0.25)..quadraticBezierTo(s * 0.6, s * 0.25, s * 0.6, s * 0.4);
    canvas.drawPath(path, strokePaint..strokeWidth = s * 0.05);
    // Chain link accent (small circle)
    canvas.drawCircle(Offset(s * 0.7, s * 0.65), s * 0.08, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = s * 0.04);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Bingo: ticket with filled dots ─────────────────────────────────

class _BingoIcon extends _GameIconPainter {
  _BingoIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Ticket outline (rounded rect)
    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.15, s * 0.2, s * 0.7, s * 0.6), Radius.circular(s * 0.08));
    canvas.drawRRect(rrect, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = s * 0.04);
    // Filled dots inside
    canvas.drawCircle(Offset(s * 0.32, s * 0.35), s * 0.06, fillPaint);
    canvas.drawCircle(Offset(s * 0.5, s * 0.35), s * 0.06, fillPaint);
    canvas.drawCircle(Offset(s * 0.68, s * 0.35), s * 0.06, fillPaint);
    canvas.drawCircle(Offset(s * 0.32, s * 0.6), s * 0.06, fillPaint);
    canvas.drawCircle(Offset(s * 0.68, s * 0.6), s * 0.06, fillPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Checkers: two overlapping discs ────────────────────────────────

class _CheckersIcon extends _GameIconPainter {
  _CheckersIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Filled disc (back)
    canvas.drawCircle(Offset(s * 0.38, s * 0.38), s * 0.28, fillPaint);
    // Outlined disc (front)
    canvas.drawCircle(Offset(s * 0.62, s * 0.62), s * 0.28, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = s * 0.06);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Ludo: die with pips + token ────────────────────────────────────

class _LudoIcon extends _GameIconPainter {
  _LudoIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Die (rounded square)
    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.15, s * 0.15, s * 0.5, s * 0.5), Radius.circular(s * 0.06));
    canvas.drawRRect(rrect, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = s * 0.04);
    // Pips (3 diagonal)
    canvas.drawCircle(Offset(s * 0.25, s * 0.25), s * 0.04, fillPaint);
    canvas.drawCircle(Offset(s * 0.4, s * 0.4), s * 0.04, fillPaint);
    canvas.drawCircle(Offset(s * 0.55, s * 0.55), s * 0.04, fillPaint);
    // Token (small circle beside die)
    canvas.drawCircle(Offset(s * 0.78, s * 0.7), s * 0.1, fillPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Carrom: striker disc mid-flick ─────────────────────────────────

class _CarromIcon extends _GameIconPainter {
  _CarromIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Striker (large disc)
    canvas.drawCircle(Offset(s * 0.35, s * 0.5), s * 0.2, fillPaint);
    // Coin (small disc)
    canvas.drawCircle(Offset(s * 0.75, s * 0.3), s * 0.1, fillPaint);
    // Motion line from striker to coin
    canvas.drawLine(Offset(s * 0.5, s * 0.42), Offset(s * 0.68, s * 0.32), strokePaint..strokeWidth = s * 0.03);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Chess: simplified knight silhouette ───────────────────────────

class _ChessIcon extends _GameIconPainter {
  _ChessIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Knight head silhouette (simplified)
    final path = Path()
      ..moveTo(s * 0.3, s * 0.8)  // bottom left
      ..lineTo(s * 0.3, s * 0.5)   // up neck
      ..lineTo(s * 0.25, s * 0.4)  // curve out
      ..quadraticBezierTo(s * 0.2, s * 0.25, s * 0.4, s * 0.15) // top of head
      ..lineTo(s * 0.6, s * 0.15)  // forehead
      ..quadraticBezierTo(s * 0.7, s * 0.2, s * 0.65, s * 0.35) // nose
      ..lineTo(s * 0.55, s * 0.45) // chin
      ..lineTo(s * 0.7, s * 0.5)   // base right
      ..lineTo(s * 0.7, s * 0.8)   // bottom right
      ..close();
    canvas.drawPath(path, fillPaint);
    // Base line
    canvas.drawRect(Rect.fromLTWH(s * 0.25, s * 0.78, s * 0.5, s * 0.06), fillPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── TripleMatch: three matching tiles in triangle ──────────────────

class _TripleMatchIcon extends _GameIconPainter {
  _TripleMatchIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Three small rounded squares in triangle
    final rrect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s * 0.5, s * 0.25), width: s * 0.28, height: s * 0.22), Radius.circular(s * 0.04));
    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s * 0.28, s * 0.65), width: s * 0.28, height: s * 0.22), Radius.circular(s * 0.04)), fillPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s * 0.72, s * 0.65), width: s * 0.28, height: s * 0.22), Radius.circular(s * 0.04)), fillPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Name-Place-Animal-Thing: letter tile ───────────────────────────

class _NamePlaceIcon extends _GameIconPainter {
  _NamePlaceIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Rounded square tile
    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.2, s * 0.2, s * 0.6, s * 0.6), Radius.circular(s * 0.1));
    canvas.drawRRect(rrect, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = s * 0.05);
    // Letter "A" inside (simplified)
    canvas.drawLine(Offset(s * 0.35, s * 0.65), Offset(s * 0.5, s * 0.3), strokePaint..strokeWidth = s * 0.06);
    canvas.drawLine(Offset(s * 0.5, s * 0.3), Offset(s * 0.65, s * 0.65), strokePaint..strokeWidth = s * 0.06);
    canvas.drawLine(Offset(s * 0.4, s * 0.52), Offset(s * 0.6, s * 0.52), strokePaint..strokeWidth = s * 0.04);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Tic-Tac-Toe: 3x3 grid with X and O ─────────────────────────────

class _TicTacToeIcon extends _GameIconPainter {
  _TicTacToeIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Grid lines
    canvas.drawLine(Offset(s * 0.38, s * 0.1), Offset(s * 0.38, s * 0.9), strokePaint..strokeWidth = s * 0.03);
    canvas.drawLine(Offset(s * 0.62, s * 0.1), Offset(s * 0.62, s * 0.9), strokePaint..strokeWidth = s * 0.03);
    canvas.drawLine(Offset(s * 0.1, s * 0.38), Offset(s * 0.9, s * 0.38), strokePaint..strokeWidth = s * 0.03);
    canvas.drawLine(Offset(s * 0.1, s * 0.62), Offset(s * 0.9, s * 0.62), strokePaint..strokeWidth = s * 0.03);
    // X in top-left cell
    final xStroke = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = s * 0.04..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s * 0.15, s * 0.15), Offset(s * 0.33, s * 0.33), xStroke);
    canvas.drawLine(Offset(s * 0.33, s * 0.15), Offset(s * 0.15, s * 0.33), xStroke);
    // O in center cell
    canvas.drawCircle(Offset(s * 0.5, s * 0.5), s * 0.09, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = s * 0.04);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Truth or Dare: spinning bottle (top-down) ──────────────────────

class _TruthOrDareIcon extends _GameIconPainter {
  _TruthOrDareIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Bottle body (ellipse, viewed from slight top-down)
    canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.5, s * 0.5), width: s * 0.6, height: s * 0.18), fillPaint);
    // Bottle neck (narrower ellipse)
    canvas.drawOval(Rect.fromCenter(center: Offset(s * 0.5, s * 0.5), width: s * 0.15, height: s * 0.06), whitePaint);
    // Spin indicator (curved arrow above)
    final path = Path()..moveTo(s * 0.3, s * 0.25)..quadraticBezierTo(s * 0.5, s * 0.1, s * 0.7, s * 0.25);
    canvas.drawPath(path, strokePaint..strokeWidth = s * 0.03);
    // Arrow head
    canvas.drawLine(Offset(s * 0.7, s * 0.25), Offset(s * 0.65, s * 0.2), strokePaint..strokeWidth = s * 0.03);
    canvas.drawLine(Offset(s * 0.7, s * 0.25), Offset(s * 0.65, s * 0.3), strokePaint..strokeWidth = s * 0.03);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Two Truths and a Lie: 2-of-3 dot pattern ───────────────────────

class _TwoTruthsIcon extends _GameIconPainter {
  _TwoTruthsIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Two filled dots (truths)
    canvas.drawCircle(Offset(s * 0.3, s * 0.3), s * 0.12, fillPaint);
    canvas.drawCircle(Offset(s * 0.7, s * 0.3), s * 0.12, fillPaint);
    // One outlined dot with X (lie)
    canvas.drawCircle(Offset(s * 0.5, s * 0.7), s * 0.12, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = s * 0.04);
    final xs = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = s * 0.03..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s * 0.44, s * 0.64), Offset(s * 0.56, s * 0.76), xs);
    canvas.drawLine(Offset(s * 0.56, s * 0.64), Offset(s * 0.44, s * 0.76), xs);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Dots and Boxes: dot grid with one filled box ───────────────────

class _DotsBoxesIcon extends _GameIconPainter {
  _DotsBoxesIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // 3x3 dot grid
    for (int r = 0; r < 3; r++) for (int c = 0; c < 3; c++) {
      canvas.drawCircle(Offset(s * (0.2 + c * 0.3), s * (0.2 + r * 0.3)), s * 0.04, fillPaint);
    }
    // One completed box (top-left)
    final boxRect = Rect.fromLTWH(s * 0.2, s * 0.2, s * 0.3, s * 0.3);
    canvas.drawRect(boxRect, Paint()..color = color.withValues(alpha: 0.25)..style = PaintingStyle.fill);
    // Box border lines
    canvas.drawRect(boxRect, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = s * 0.03);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Hot Seat: flame on seat ────────────────────────────────────────

class _HotSeatIcon extends _GameIconPainter {
  _HotSeatIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Flame (teardrop shape)
    final path = Path()
      ..moveTo(s * 0.5, s * 0.15)
      ..quadraticBezierTo(s * 0.65, s * 0.35, s * 0.6, s * 0.5)
      ..quadraticBezierTo(s * 0.55, s * 0.55, s * 0.5, s * 0.55)
      ..quadraticBezierTo(s * 0.45, s * 0.55, s * 0.4, s * 0.5)
      ..quadraticBezierTo(s * 0.35, s * 0.35, s * 0.5, s * 0.15)
      ..close();
    canvas.drawPath(path, fillPaint);
    // Seat (simple stool base)
    canvas.drawRect(Rect.fromLTWH(s * 0.25, s * 0.65, s * 0.5, s * 0.08), fillPaint);
    // Legs
    canvas.drawLine(Offset(s * 0.3, s * 0.73), Offset(s * 0.3, s * 0.9), strokePaint..strokeWidth = s * 0.04);
    canvas.drawLine(Offset(s * 0.7, s * 0.73), Offset(s * 0.7, s * 0.9), strokePaint..strokeWidth = s * 0.04);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Relation Riddles: puzzle piece ─────────────────────────────────

class _RiddleIcon extends _GameIconPainter {
  _RiddleIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Puzzle piece (simplified)
    final path = Path()
      ..moveTo(s * 0.25, s * 0.25)
      ..lineTo(s * 0.45, s * 0.25)
      ..quadraticBezierTo(s * 0.5, s * 0.15, s * 0.55, s * 0.25) // tab top
      ..lineTo(s * 0.75, s * 0.25)
      ..lineTo(s * 0.75, s * 0.45)
      ..quadraticBezierTo(s * 0.85, s * 0.5, s * 0.75, s * 0.55) // tab right
      ..lineTo(s * 0.75, s * 0.75)
      ..lineTo(s * 0.25, s * 0.75)
      ..close();
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = s * 0.05..strokeJoin = StrokeJoin.round);
    // Question mark dot inside
    canvas.drawCircle(Offset(s * 0.5, s * 0.6), s * 0.04, fillPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Truth Streak: flame with streak lines ──────────────────────────

class _TruthStreakIcon extends _GameIconPainter {
  _TruthStreakIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Flame
    final path = Path()
      ..moveTo(s * 0.5, s * 0.1)
      ..quadraticBezierTo(s * 0.7, s * 0.35, s * 0.6, s * 0.55)
      ..quadraticBezierTo(s * 0.55, s * 0.6, s * 0.5, s * 0.6)
      ..quadraticBezierTo(s * 0.45, s * 0.6, s * 0.4, s * 0.55)
      ..quadraticBezierTo(s * 0.3, s * 0.35, s * 0.5, s * 0.1)
      ..close();
    canvas.drawPath(path, fillPaint);
    // Streak lines (3 horizontal)
    canvas.drawLine(Offset(s * 0.15, s * 0.75), Offset(s * 0.4, s * 0.75), strokePaint..strokeWidth = s * 0.03);
    canvas.drawLine(Offset(s * 0.2, s * 0.85), Offset(s * 0.5, s * 0.85), strokePaint..strokeWidth = s * 0.03);
    canvas.drawLine(Offset(s * 0.6, s * 0.8), Offset(s * 0.85, s * 0.8), strokePaint..strokeWidth = s * 0.03);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Default fallback ───────────────────────────────────────────────

class _DefaultGameIcon extends _GameIconPainter {
  _DefaultGameIcon(super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawCircle(Offset(s * 0.5, s * 0.5), s * 0.3, fillPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
