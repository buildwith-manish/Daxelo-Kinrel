// lib/features/games/memorymatch/memorymatch_card_faces.dart
//
// Memory Match — reusable image-based card face system.
//
// Every card face is a hand-drawn VECTOR illustration (CustomPainter)
// rendered in a normalized 100x100 coordinate space, so the exact same
// art stays crisp at every board size:
//   • 4x4 Easy   (16 cards, big tiles)
//   • 5x4 Medium (20 cards)
//   • 6x4 Hard   (24 cards)
//   • 6x6 Expert (36 cards, small tiles)
//   • leaderboard chips + pack previews (16-24 px)
//
// Design language: Kinrel flat-premium — rounded friendly silhouettes,
// two-tone fills, a soft top-left highlight, and a grounded shadow
// ellipse. No emojis are used anywhere in gameplay.
//
// The symbol KEYS match the server deck (fn_memorymatch_start SQL) —
// the server still deals keys; this file maps key -> vector art.

import 'dart:math' as math;

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────

class MemoryFacePalette {
  const MemoryFacePalette({
    required this.base,
    required this.accent,
    required this.detail,
    this.highlight = const Color(0xFFFFFFFF),
  });

  final Color base;
  final Color accent;
  final Color detail;
  final Color highlight;
}

// ─────────────────────────────────────────────────────────────────────
// Face spec + registry
// ─────────────────────────────────────────────────────────────────────

typedef MemoryFacePainter = void Function(Canvas c, MemoryFacePalette p);

class MemoryFaceSpec {
  const MemoryFaceSpec({
    required this.key,
    required this.label,
    required this.palette,
    required this.painter,
  });

  final String key;
  final String label;
  final MemoryFacePalette palette;
  final MemoryFacePainter painter;
}

/// All card faces, keyed by pack id -> symbol key -> spec.
/// Keys are in sync with the SQL deck builder (fn_memorymatch_start).
class MemoryCardFaces {
  MemoryCardFaces._();

  static const String fallbackKey = 'sparkle';

  static MemoryFaceSpec specFor(String? packId, String? symbolKey) {
    final pack = _packs[packId] ?? _packs['classic']!;
    return pack[symbolKey] ?? _packs['classic']![fallbackKey]!;
  }

  /// A representative face for pack chips / lobby previews.
  static MemoryFaceSpec previewSpecFor(String? packId) {
    switch (packId) {
      case 'family':
        return specFor('family', 'bigfamily');
      case 'food':
        return specFor('food', 'pizza');
      case 'animals':
        return specFor('animals', 'panda');
      default:
        return specFor('classic', 'star');
    }
  }

  static final Map<String, Map<String, MemoryFaceSpec>> _packs = {
    'classic': _classic,
    'family': _family,
    'food': _food,
    'animals': _animals,
  };

  // ── filled below, per pack ────────────────────────────────────────

  static final Map<String, MemoryFaceSpec> _classic = _buildClassic();
  static final Map<String, MemoryFaceSpec> _family = _buildFamily();
  static final Map<String, MemoryFaceSpec> _food = _buildFood();
  static final Map<String, MemoryFaceSpec> _animals = _buildAnimals();

  static Map<String, MemoryFaceSpec> _buildClassic() => {
        for (final s in _classicList) s.key: s,
      };
  static Map<String, MemoryFaceSpec> _buildFamily() => {
        for (final s in _familyList) s.key: s,
      };
  static Map<String, MemoryFaceSpec> _buildFood() => {
        for (final s in _foodList) s.key: s,
      };
  static Map<String, MemoryFaceSpec> _buildAnimals() => {
        for (final s in _animalsList) s.key: s,
      };
}

// ─────────────────────────────────────────────────────────────────────
// The scaling widget — THE reusable card-face renderer.
// Give it any box; it paints the 100x100 art scaled to fit (uniform,
// centered). Works from 16 px chips to full-card tiles.
// ─────────────────────────────────────────────────────────────────────

class MemoryCardFaceIcon extends StatelessWidget {
  const MemoryCardFaceIcon({
    super.key,
    required this.symbolKey,
    this.packId,
    this.dimmed = false,
  });

  final String symbolKey;
  final String? packId;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.hasBoundedWidth ? constraints.maxWidth : 48.0;
        final h = constraints.hasBoundedHeight ? constraints.maxHeight : 48.0;
        return CustomPaint(
          size: Size(w, h),
          painter: _ScaledFacePainter(
            spec: MemoryCardFaces.specFor(packId, symbolKey),
            dimmed: dimmed,
          ),
        );
      },
    );
  }
}

class _ScaledFacePainter extends CustomPainter {
  _ScaledFacePainter({required this.spec, required this.dimmed});

  final MemoryFaceSpec spec;
  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final scale = size.shortestSide / 100.0;
    canvas.save();
    canvas.translate(
      (size.width - 100 * scale) / 2.0,
      (size.height - 100 * scale) / 2.0,
    );
    canvas.scale(scale, scale);
    if (dimmed) {
      canvas.saveLayer(const Rect.fromLTWH(-20, -20, 140, 140), Paint()..color = Colors.white70);
      spec.painter(canvas, spec.palette);
      canvas.restore();
    } else {
      spec.painter(canvas, spec.palette);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScaledFacePainter oldDelegate) =>
      oldDelegate.spec != spec || oldDelegate.dimmed != dimmed;
}

// ─────────────────────────────────────────────────────────────────────
// Shared drawing helpers — all coordinates in the 100x100 space.
// Style: flat fills, rounded corners, highlight dot, ground shadow.
// ─────────────────────────────────────────────────────────────────────

void _groundShadow(Canvas c, [Color? color]) {
  final p = Paint()
    ..color = color ?? const Color(0x1A000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  c.drawOval(const Rect.fromLTWH(24, 88, 52, 8), p);
}

void _hl(Canvas c, Offset center, double r) {
  final p = Paint()..color = Colors.white.withValues(alpha: 0.55);
  c.drawCircle(center, r, p);
}

void _rrect(Canvas c, Rect r, double radius, Color color) {
  final p = Paint()..color = color;
  c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), p);
}

void _circle(Canvas c, Offset center, double r, Color color) {
  final p = Paint()..color = color;
  c.drawCircle(center, r, p);
}

void _oval(Canvas c, Rect r, Color color) {
  final p = Paint()..color = color;
  c.drawOval(r, p);
}

void _path(Canvas c, Path path, Color color) {
  final p = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  c.drawPath(path, p);
}

void _stroke(Canvas c, Path path, Color color, double width) {
  final p = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  c.drawPath(path, p);
}

/// 5-pointed star centered at (cx, cy).
Path _starPath(double cx, double cy, double outer, double inner) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? outer : inner;
    final a = -math.pi / 2 + i * math.pi / 5;
    final x = cx + r * _cos(a);
    final y = cy + r * _sin(a);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

/// 4-point sparkle (concave star).
Path _sparklePath(double cx, double cy, double outer, double inner) {
  final path = Path();
  for (var i = 0; i < 8; i++) {
    final r = i.isEven ? outer : inner;
    final a = -math.pi / 2 + i * math.pi / 4;
    final x = cx + r * _cos(a);
    final y = cy + r * _sin(a);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

double _cos(double a) => math.cos(a);
double _sin(double a) => math.sin(a);
const double _math_pi = math.pi;

// ─────────────────────────────────────────────────────────────────────
// CLASSIC CHARMS pack
// ─────────────────────────────────────────────────────────────────────

final List<MemoryFaceSpec> _classicList = [
  MemoryFaceSpec(
    key: 'star',
    label: 'Star',
    palette: const MemoryFacePalette(
        base: Color(0xFFFFC940), accent: Color(0xFFF59240), detail: Color(0xFFE8862A)),
    painter: _faceStar,
  ),
  MemoryFaceSpec(
    key: 'heart',
    label: 'Heart',
    palette: const MemoryFacePalette(
        base: Color(0xFFFF6B81), accent: Color(0xFFE84393), detail: Color(0xFFC44569)),
    painter: _faceHeart,
  ),
  MemoryFaceSpec(
    key: 'moon',
    label: 'Moon',
    palette: const MemoryFacePalette(
        base: Color(0xFFFFE08A), accent: Color(0xFFD4AF37), detail: Color(0xFFB8912E)),
    painter: _faceMoon,
  ),
  MemoryFaceSpec(
    key: 'sun',
    label: 'Sun',
    palette: const MemoryFacePalette(
        base: Color(0xFFFFD54F), accent: Color(0xFFF59240), detail: Color(0xFFE8862A)),
    painter: _faceSun,
  ),
  MemoryFaceSpec(
    key: 'crown',
    label: 'Crown',
    palette: const MemoryFacePalette(
        base: Color(0xFFFFD54F), accent: Color(0xFFE8612A), detail: Color(0xFFB8912E)),
    painter: _faceCrown,
  ),
  MemoryFaceSpec(
    key: 'gem',
    label: 'Gem',
    palette: const MemoryFacePalette(
        base: Color(0xFF6FD8E8), accent: Color(0xFF3BA8C9), detail: Color(0xFF2C7E9E)),
    painter: _faceGem,
  ),
  MemoryFaceSpec(
    key: 'rocket',
    label: 'Rocket',
    palette: const MemoryFacePalette(
        base: Color(0xFFE8EDF5), accent: Color(0xFFE8612A), detail: Color(0xFF3E4A5E)),
    painter: _faceRocket,
  ),
  MemoryFaceSpec(
    key: 'balloon',
    label: 'Balloon',
    palette: const MemoryFacePalette(
        base: Color(0xFFFF8FA3), accent: Color(0xFFE84393), detail: Color(0xFFC44569)),
    painter: _faceBalloon,
  ),
  MemoryFaceSpec(
    key: 'rainbow',
    label: 'Rainbow',
    palette: const MemoryFacePalette(
        base: Color(0xFFFF6B81), accent: Color(0xFF6FD8E8), detail: Color(0xFF9B8CFF)),
    painter: _faceRainbow,
  ),
  MemoryFaceSpec(
    key: 'bolt',
    label: 'Bolt',
    palette: const MemoryFacePalette(
        base: Color(0xFFFFD54F), accent: Color(0xFFF59240), detail: Color(0xFFE8862A)),
    painter: _faceBolt,
  ),
  MemoryFaceSpec(
    key: 'flame',
    label: 'Flame',
    palette: const MemoryFacePalette(
        base: Color(0xFFF59240), accent: Color(0xFFFFC940), detail: Color(0xFFE8432A)),
    painter: _faceFlame,
  ),
  MemoryFaceSpec(
    key: 'snow',
    label: 'Snowflake',
    palette: const MemoryFacePalette(
        base: Color(0xFFBFE8F5), accent: Color(0xFF8FD4E8), detail: Color(0xFF6FB8D4)),
    painter: _faceSnow,
  ),
  MemoryFaceSpec(
    key: 'target',
    label: 'Target',
    palette: const MemoryFacePalette(
        base: Color(0xFFE8612A), accent: Color(0xFFFFFFFF), detail: Color(0xFFC44A18)),
    painter: _faceTarget,
  ),
  MemoryFaceSpec(
    key: 'gift',
    label: 'Gift',
    palette: const MemoryFacePalette(
        base: Color(0xFF9B8CFF), accent: Color(0xFFFFC940), detail: Color(0xFF7A6BD4)),
    painter: _faceGift,
  ),
  MemoryFaceSpec(
    key: 'puzzle',
    label: 'Puzzle',
    palette: const MemoryFacePalette(
        base: Color(0xFF6FD8A8), accent: Color(0xFF3EA87E), detail: Color(0xFF2C7E5E)),
    painter: _facePuzzle,
  ),
  MemoryFaceSpec(
    key: 'sparkle',
    label: 'Sparkle',
    palette: const MemoryFacePalette(
        base: Color(0xFFFFE08A), accent: Color(0xFFF59240), detail: Color(0xFFD4AF37)),
    painter: _faceSparkle,
  ),
  MemoryFaceSpec(
    key: 'crystal',
    label: 'Crystal',
    palette: const MemoryFacePalette(
        base: Color(0xFFB79BFF), accent: Color(0xFF8F6FE8), detail: Color(0xFF6B4FD4)),
    painter: _faceCrystal,
  ),
  MemoryFaceSpec(
    key: 'butterfly',
    label: 'Butterfly',
    palette: const MemoryFacePalette(
        base: Color(0xFF8FD4E8), accent: Color(0xFFE84393), detail: Color(0xFF5E6B8C)),
    painter: _faceButterfly,
  ),
];

void _faceStar(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  _path(c, _starPath(50, 50, 34, 14), p.base);
  _path(c, _starPath(44, 44, 14, 6), p.highlight);
}

void _faceHeart(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  final path = Path()
    ..moveTo(50, 84)
    ..cubicTo(10, 56, 14, 20, 50, 34)
    ..cubicTo(86, 20, 90, 56, 50, 84)
    ..close();
  _path(c, path, p.base);
  final shine = Path()
    ..moveTo(32, 36)
    ..cubicTo(24, 44, 26, 52, 34, 56)
    ..cubicTo(30, 46, 32, 40, 38, 34)
    ..close();
  _path(c, shine, p.highlight);
}

void _faceMoon(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  final outer = Path()
    ..addOval(const Rect.fromLTWH(18, 14, 68, 68));
  final cut = Path()
    ..addOval(const Rect.fromLTWH(38, 8, 62, 62));
  final moon = Path.combine(PathOperation.difference, outer, cut);
  _path(c, moon, p.base);
  _circle(c, const Offset(62, 30), 4, p.highlight);
  _circle(c, const Offset(54, 48), 3, p.highlight);
}

void _faceSun(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  for (var i = 0; i < 12; i++) {
    final a = i * _math_pi / 6;
    final stroke = Path()
      ..moveTo(50 + 36 * _cos(a), 50 + 36 * _sin(a))
      ..lineTo(50 + 46 * _cos(a), 50 + 46 * _sin(a));
    _stroke(c, stroke, p.accent, 6);
  }
  _circle(c, const Offset(50, 50), 28, p.base);
  _circle(c, const Offset(42, 42), 7, p.highlight);
}

void _faceCrown(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  final body = Path()
    ..moveTo(20, 74)
    ..lineTo(20, 40)
    ..lineTo(32, 54)
    ..lineTo(50, 26)
    ..lineTo(68, 54)
    ..lineTo(80, 40)
    ..lineTo(80, 74)
    ..close();
  _path(c, body, p.base);
  _rrect(c, const Rect.fromLTWH(16, 72, 68, 10), 4, p.detail);
  _circle(c, const Offset(50, 22), 5, p.accent);
  _circle(c, const Offset(20, 38), 4, p.accent);
  _circle(c, const Offset(80, 38), 4, p.accent);
  _hl(c, const Offset(40, 62), 4);
}

void _faceGem(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  final body = Path()
    ..moveTo(50, 16)
    ..lineTo(78, 42)
    ..lineTo(50, 84)
    ..lineTo(22, 42)
    ..close();
  _path(c, body, p.base);
  _path(c, Path()..moveTo(50, 16)..lineTo(62, 42)..lineTo(50, 84)..lineTo(50, 16), p.accent);
  final facet = Path()
    ..moveTo(22, 42)
    ..lineTo(78, 42)
    ..lineTo(62, 58)
    ..lineTo(38, 58)
    ..close();
  _path(c, facet, p.detail);
  _hl(c, const Offset(40, 34), 5);
}

void _faceRocket(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // fins
  _path(c, Path()..moveTo(34, 56)..lineTo(20, 80)..lineTo(38, 72)..close(), p.accent);
  _path(c, Path()..moveTo(66, 56)..lineTo(80, 80)..lineTo(62, 72)..close(), p.accent);
  // body
  final body = Path()
    ..moveTo(50, 10)
    ..cubicTo(64, 26, 66, 48, 62, 70)
    ..lineTo(38, 70)
    ..cubicTo(34, 48, 36, 26, 50, 10)
    ..close();
  _path(c, body, p.base);
  _circle(c, const Offset(50, 38), 9, p.detail);
  _circle(c, const Offset(50, 38), 5, p.accent);
  // flame
  _path(c, Path()..moveTo(42, 72)..quadraticBezierTo(50, 92, 58, 72)..close(), p.accent);
  _hl(c, const Offset(43, 26), 4);
}

void _faceBalloon(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  _oval(c, const Rect.fromLTWH(26, 12, 48, 58), p.base);
  _path(c, Path()..moveTo(44, 70)..lineTo(56, 70)..lineTo(50, 78)..close(), p.detail);
  _stroke(c, Path()..moveTo(50, 78)..quadraticBezierTo(60, 86, 54, 94), p.detail, 2.5);
  _hl(c, const Offset(40, 30), 7);
}

void _faceRainbow(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  final colors = [p.base, p.accent, p.detail];
  for (var i = 0; i < 3; i++) {
    final arc = Path()
      ..addArc(Rect.fromLTWH(16 + i * 12, 22 + i * 12, 68 - i * 24, 68 - i * 24),
          _math_pi, _math_pi);
    _stroke(c, arc, colors[i], 11);
  }
  _rrect(c, const Rect.fromLTWH(12, 86, 14, 6), 3, p.detail);
  _rrect(c, const Rect.fromLTWH(74, 86, 14, 6), 3, p.detail);
  // tiny cloud
  _circle(c, const Offset(24, 90), 7, Colors.white);
  _circle(c, const Offset(32, 88), 6, Colors.white);
  _circle(c, const Offset(76, 90), 7, Colors.white);
  _circle(c, const Offset(68, 88), 6, Colors.white);
}

void _faceBolt(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  final path = Path()
    ..moveTo(56, 10)
    ..lineTo(28, 54)
    ..lineTo(46, 54)
    ..lineTo(40, 90)
    ..lineTo(72, 42)
    ..lineTo(52, 42)
    ..lineTo(62, 10)
    ..close();
  _path(c, path, p.base);
  _path(c, Path()..moveTo(56, 10)..lineTo(44, 30)..lineTo(52, 32)..close(), p.highlight);
}

void _faceFlame(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  final outer = Path()
    ..moveTo(50, 8)
    ..cubicTo(68, 28, 82, 44, 76, 64)
    ..cubicTo(70, 84, 58, 90, 50, 90)
    ..cubicTo(42, 90, 30, 84, 24, 64)
    ..cubicTo(18, 44, 32, 28, 50, 8)
    ..close();
  _path(c, outer, p.base);
  final inner = Path()
    ..moveTo(50, 40)
    ..cubicTo(60, 52, 64, 62, 60, 72)
    ..cubicTo(57, 80, 52, 82, 50, 82)
    ..cubicTo(48, 82, 43, 80, 40, 72)
    ..cubicTo(36, 62, 40, 52, 50, 40)
    ..close();
  _path(c, inner, p.accent);
}

void _faceSnow(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  for (var i = 0; i < 6; i++) {
    final a = i * _math_pi / 3;
    final arm = Path()
      ..moveTo(50, 50)
      ..lineTo(50 + 38 * _cos(a), 50 + 38 * _sin(a));
    _stroke(c, arm, p.base, 7);
    for (final side in [-1.0, 1.0]) {
      final tipX = 50 + 26 * _cos(a);
      final tipY = 50 + 26 * _sin(a);
      final ba = a + side * 0.6;
      final twig = Path()
        ..moveTo(tipX, tipY)
        ..lineTo(tipX + 12 * _cos(ba), tipY + 12 * _sin(ba));
      _stroke(c, twig, p.accent, 5);
    }
  }
  _circle(c, const Offset(50, 50), 6, p.detail);
}

void _faceTarget(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  _circle(c, const Offset(50, 50), 36, p.base);
  _circle(c, const Offset(50, 50), 24, p.accent);
  _circle(c, const Offset(50, 50), 12, p.base);
  _circle(c, const Offset(50, 50), 4, p.accent);
  // arrow
  _stroke(c, Path()..moveTo(78, 22)..lineTo(56, 44), p.detail, 4);
  _path(c, Path()..moveTo(82, 12)..lineTo(84, 30)..lineTo(68, 26)..close(), p.detail);
}

void _faceGift(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  _rrect(c, const Rect.fromLTWH(18, 38, 64, 48), 6, p.base);
  _rrect(c, const Rect.fromLTWH(14, 30, 72, 14), 5, p.detail);
  _rrect(c, const Rect.fromLTWH(44, 30, 12, 56), 3, p.accent);
  final bow = Path()
    ..moveTo(50, 30)
    ..cubicTo(36, 14, 22, 18, 30, 30)
    ..cubicTo(22, 42, 36, 44, 50, 30)
    ..close();
  _path(c, bow, p.accent);
  final bow2 = Path()
    ..moveTo(50, 30)
    ..cubicTo(64, 14, 78, 18, 70, 30)
    ..cubicTo(78, 42, 64, 44, 50, 30)
    ..close();
  _path(c, bow2, p.accent);
  _hl(c, const Offset(28, 46), 5);
}

void _facePuzzle(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  final body = Path()
    ..moveTo(24, 28)
    ..lineTo(42, 28)
    ..arcToPoint(const Offset(52, 18), radius: const Radius.circular(9), clockwise: false)
    ..arcToPoint(const Offset(62, 28), radius: const Radius.circular(9), clockwise: true)
    ..lineTo(78, 28)
    ..lineTo(78, 46)
    ..arcToPoint(const Offset(88, 56), radius: const Radius.circular(9), clockwise: false)
    ..arcToPoint(const Offset(78, 66), radius: const Radius.circular(9), clockwise: true)
    ..lineTo(78, 82)
    ..lineTo(24, 82)
    ..close();
  _path(c, body, p.base);
  _rrect(c, const Rect.fromLTWH(30, 40, 12, 8), 3, p.accent);
  _rrect(c, const Rect.fromLTWH(58, 62, 12, 8), 3, p.accent);
  _hl(c, const Offset(30, 34), 4);
}

void _faceSparkle(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  _path(c, _sparklePath(46, 46, 32, 10), p.base);
  _path(c, _sparklePath(70, 68, 14, 5), p.accent);
  _hl(c, const Offset(40, 38), 5);
}

void _faceCrystal(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  _circle(c, const Offset(50, 50), 34, p.base);
  final orb = Path()
    ..moveTo(50, 16)
    ..lineTo(74, 50)
    ..lineTo(50, 84)
    ..lineTo(26, 50)
    ..close();
  _path(c, orb, p.accent.withValues(alpha: 200));
  _path(c, _sparklePath(38, 34, 8, 3), Colors.white);
  _stroke(c, Path()..moveTo(26, 50)..lineTo(74, 50), p.detail, 2.5);
}

void _faceButterfly(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // upper wings
  _path(c, Path()..moveTo(48, 48)..cubicTo(24, 14, 8, 26, 18, 46)..cubicTo(24, 58, 38, 54, 48, 50)..close(), p.base);
  _path(c, Path()..moveTo(52, 48)..cubicTo(76, 14, 92, 26, 82, 46)..cubicTo(76, 58, 62, 54, 52, 50)..close(), p.base);
  // lower wings
  _path(c, Path()..moveTo(48, 52)..cubicTo(30, 62, 20, 80, 34, 84)..cubicTo(44, 86, 48, 68, 48, 56)..close(), p.accent);
  _path(c, Path()..moveTo(52, 52)..cubicTo(70, 62, 80, 80, 66, 84)..cubicTo(56, 86, 52, 68, 52, 56)..close(), p.accent);
  // body
  _rrect(c, const Rect.fromLTWH(46, 34, 8, 44), 4, p.detail);
  _stroke(c, Path()..moveTo(50, 34)..lineTo(44, 22), p.detail, 2.5);
  _stroke(c, Path()..moveTo(50, 34)..lineTo(56, 22), p.detail, 2.5);
  _circle(c, const Offset(50, 32), 5, p.detail);
}

// ─────────────────────────────────────────────────────────────────────
// FAMILY pack — family members, pets, activities and family objects,
// drawn as warm friendly portrait/object illustrations.
// ─────────────────────────────────────────────────────────────────────

// Shared person-face helper: round head + eyes + smile in the
// 100x100 space. `skin` and `hair` colors come from the palette.
void _personFace(Canvas c, MemoryFacePalette p,
    {required void Function(Canvas) hair}) {
  _groundShadow(c);
  _circle(c, const Offset(50, 52), 30, p.base); // head
  hair(c); // hair shape on top
  // eyes
  _circle(c, const Offset(40, 50), 3.6, p.detail);
  _circle(c, const Offset(60, 50), 3.6, p.detail);
  // rosy cheeks
  _circle(c, const Offset(34, 60), 4.5, p.accent.withValues(alpha: 0.45));
  _circle(c, const Offset(66, 60), 4.5, p.accent.withValues(alpha: 0.45));
  // smile
  _stroke(
      c,
      Path()
        ..moveTo(42, 62)
        ..quadraticBezierTo(50, 69, 58, 62),
      p.detail,
      3);
}

final List<MemoryFaceSpec> _familyList = [
  MemoryFaceSpec(
    key: 'mom',
    label: 'Mom',
    palette: const MemoryFacePalette(
        base: Color(0xFFF2C9A8), accent: Color(0xFFE8798A), detail: Color(0xFF5E4638)),
    painter: _faceMom,
  ),
  MemoryFaceSpec(
    key: 'dad',
    label: 'Dad',
    palette: const MemoryFacePalette(
        base: Color(0xFFEBB68E), accent: Color(0xFF4A6FA8), detail: Color(0xFF2E2A26)),
    painter: _faceDad,
  ),
  MemoryFaceSpec(
    key: 'brother',
    label: 'Brother',
    palette: const MemoryFacePalette(
        base: Color(0xFFF2C9A8), accent: Color(0xFF3EA87E), detail: Color(0xFF2E2A26)),
    painter: _faceBrother,
  ),
  MemoryFaceSpec(
    key: 'sister',
    label: 'Sister',
    palette: const MemoryFacePalette(
        base: Color(0xFFF5D1B4), accent: Color(0xFFE84393), detail: Color(0xFF6B4A2E)),
    painter: _faceSister,
  ),
  MemoryFaceSpec(
    key: 'grandmother',
    label: 'Grandma',
    palette: const MemoryFacePalette(
        base: Color(0xFFF2C9A8), accent: Color(0xFF9B8CFF), detail: Color(0xFF8C8C99)),
    painter: _faceGrandmother,
  ),
  MemoryFaceSpec(
    key: 'grandfather',
    label: 'Grandpa',
    palette: const MemoryFacePalette(
        base: Color(0xFFEBB68E), accent: Color(0xFF6FA8C9), detail: Color(0xFFB9BDC9)),
    painter: _faceGrandfather,
  ),
  MemoryFaceSpec(
    key: 'cousin',
    label: 'Cousin',
    palette: const MemoryFacePalette(
        base: Color(0xFFD9A06B), accent: Color(0xFFF59240), detail: Color(0xFF2E2A26)),
    painter: _faceCousin,
  ),
  MemoryFaceSpec(
    key: 'uncle',
    label: 'Uncle',
    palette: const MemoryFacePalette(
        base: Color(0xFFC98E62), accent: Color(0xFF5E8A5E), detail: Color(0xFF2E2A26)),
    painter: _faceUncle,
  ),
  MemoryFaceSpec(
    key: 'aunt',
    label: 'Aunt',
    palette: const MemoryFacePalette(
        base: Color(0xFFEBB68E), accent: Color(0xFFE8862A), detail: Color(0xFF4A2E1E)),
    painter: _faceAunt,
  ),
  MemoryFaceSpec(
    key: 'baby',
    label: 'Baby',
    palette: const MemoryFacePalette(
        base: Color(0xFFF7DCC2), accent: Color(0xFF8FD4E8), detail: Color(0xFF5E4638)),
    painter: _faceBaby,
  ),
  MemoryFaceSpec(
    key: 'elder',
    label: 'Elder',
    palette: const MemoryFacePalette(
        base: Color(0xFFDCB18A), accent: Color(0xFFD4AF37), detail: Color(0xFF9C9CA8)),
    painter: _faceElder,
  ),
  MemoryFaceSpec(
    key: 'bigfamily',
    label: 'Family',
    palette: const MemoryFacePalette(
        base: Color(0xFFF2C9A8), accent: Color(0xFFE8612A), detail: Color(0xFF2E2A26)),
    painter: _faceBigFamily,
  ),
  MemoryFaceSpec(
    key: 'hug',
    label: 'Hug',
    palette: const MemoryFacePalette(
        base: Color(0xFFF2C9A8), accent: Color(0xFF9B8CFF), detail: Color(0xFF4A6FA8)),
    painter: _faceHug,
  ),
  MemoryFaceSpec(
    key: 'home',
    label: 'Home',
    palette: const MemoryFacePalette(
        base: Color(0xFFE8A05C), accent: Color(0xFFC44A18), detail: Color(0xFF5E8A5E)),
    painter: _faceHome,
  ),
  MemoryFaceSpec(
    key: 'petdog',
    label: 'Pet Dog',
    palette: const MemoryFacePalette(
        base: Color(0xFFD9A96B), accent: Color(0xFF8C6239), detail: Color(0xFF2E2A26)),
    painter: _facePetDog,
  ),
  MemoryFaceSpec(
    key: 'homefood',
    label: 'Home Food',
    palette: const MemoryFacePalette(
        base: Color(0xFFF5EEE0), accent: Color(0xFFE8862A), detail: Color(0xFFC44A18)),
    painter: _faceHomeFood,
  ),
  MemoryFaceSpec(
    key: 'picnic',
    label: 'Picnic',
    palette: const MemoryFacePalette(
        base: Color(0xFFD9A05C), accent: Color(0xFFE84393), detail: Color(0xFF5E8A5E)),
    painter: _facePicnic,
  ),
  MemoryFaceSpec(
    key: 'storytime',
    label: 'Story Time',
    palette: const MemoryFacePalette(
        base: Color(0xFF6FA8C9), accent: Color(0xFFFFC940), detail: Color(0xFF3E5E7E)),
    painter: _faceStoryTime,
  ),
];

void _faceMom(Canvas c, MemoryFacePalette p) {
  _personFace(c, p, hair: (c2) {
    // long hair framing the face
    _path(
        c2,
        Path()
          ..moveTo(50, 18)
          ..cubicTo(26, 18, 18, 36, 20, 58)
          ..lineTo(30, 44)
          ..cubicTo(34, 34, 40, 30, 50, 30)
          ..cubicTo(60, 30, 66, 34, 70, 44)
          ..lineTo(80, 58)
          ..cubicTo(82, 36, 74, 18, 50, 18)
          ..close(),
        p.detail);
  });
}

void _faceDad(Canvas c, MemoryFacePalette p) {
  _personFace(c, p, hair: (c2) {
    // short crop
    _path(
        c2,
        Path()
          ..moveTo(22, 48)
          ..cubicTo(20, 26, 34, 18, 50, 18)
          ..cubicTo(66, 18, 80, 26, 78, 48)
          ..lineTo(74, 40)
          ..cubicTo(66, 30, 58, 28, 50, 28)
          ..cubicTo(42, 28, 34, 30, 26, 40)
          ..close(),
        p.detail);
  });
}

void _faceBrother(Canvas c, MemoryFacePalette p) {
  _personFace(c, p, hair: (c2) {
    // spiky hair
    _path(
        c2,
        Path()
          ..moveTo(24, 46)
          ..lineTo(30, 26)
          ..lineTo(38, 38)
          ..lineTo(44, 20)
          ..lineTo(52, 36)
          ..lineTo(58, 20)
          ..lineTo(64, 38)
          ..lineTo(72, 26)
          ..lineTo(76, 46)
          ..cubicTo(66, 32, 34, 32, 24, 46)
          ..close(),
        p.detail);
  });
}

void _faceSister(Canvas c, MemoryFacePalette p) {
  _personFace(c, p, hair: (c2) {
    // pigtails + bangs
    _path(
        c2,
        Path()
          ..moveTo(50, 16)
          ..cubicTo(28, 16, 20, 30, 22, 48)
          ..cubicTo(26, 36, 34, 30, 50, 30)
          ..cubicTo(66, 30, 74, 36, 78, 48)
          ..cubicTo(80, 30, 72, 16, 50, 16)
          ..close(),
        p.detail);
    _oval(c2, const Rect.fromLTWH(8, 44, 20, 30), p.detail);
    _oval(c2, const Rect.fromLTWH(72, 44, 20, 30), p.detail);
    _circle(c2, const Offset(18, 40), 5, p.accent);
    _circle(c2, const Offset(82, 40), 5, p.accent);
  });
}

void _faceGrandmother(Canvas c, MemoryFacePalette p) {
  _personFace(c, p, hair: (c2) {
    // bun + grey side hair
    _circle(c2, const Offset(50, 16), 10, p.detail);
    _path(
        c2,
        Path()
          ..moveTo(24, 46)
          ..cubicTo(22, 28, 34, 20, 50, 20)
          ..cubicTo(66, 20, 78, 28, 76, 46)
          ..cubicTo(70, 34, 62, 30, 50, 30)
          ..cubicTo(38, 30, 30, 34, 24, 46)
          ..close(),
        p.detail);
    // glasses
    _stroke(c2, Path()..moveTo(34, 50)..lineTo(66, 50), p.detail, 2);
    _stroke(c2, Path()..addOval(const Rect.fromLTWH(33, 44, 15, 12)), p.detail, 2);
    _stroke(c2, Path()..addOval(const Rect.fromLTWH(52, 44, 15, 12)), p.detail, 2);
  });
}

void _faceGrandfather(Canvas c, MemoryFacePalette p) {
  _personFace(c, p, hair: (c2) {
    // bald top + side puffs + mustache
    _oval(c2, const Rect.fromLTWH(14, 42, 16, 18), p.detail);
    _oval(c2, const Rect.fromLTWH(70, 42, 16, 18), p.detail);
    _path(
        c2,
        Path()
          ..moveTo(38, 58)
          ..cubicTo(42, 52, 58, 52, 62, 58)
          ..cubicTo(58, 64, 42, 64, 38, 58)
          ..close(),
        Colors.white);
  });
}

void _faceCousin(Canvas c, MemoryFacePalette p) {
  _personFace(c, p, hair: (c2) {
    // cap
    _path(
        c2,
        Path()
          ..moveTo(22, 44)
          ..cubicTo(22, 24, 36, 16, 50, 16)
          ..cubicTo(64, 16, 78, 24, 78, 44)
          ..close(),
        p.accent);
    _rrect(c2, const Rect.fromLTWH(16, 42, 68, 8), 4, p.accent);
    _circle(c2, const Offset(50, 14), 5, p.detail);
  });
}

void _faceUncle(Canvas c, MemoryFacePalette p) {
  _personFace(c, p, hair: (c2) {
    // short hair + mustache
    _path(
        c2,
        Path()
          ..moveTo(22, 48)
          ..cubicTo(20, 26, 34, 18, 50, 18)
          ..cubicTo(66, 18, 80, 26, 78, 48)
          ..cubicTo(70, 32, 30, 32, 22, 48)
          ..close(),
        p.detail);
    _path(
        c2,
        Path()
          ..moveTo(36, 60)
          ..cubicTo(42, 55, 58, 55, 64, 60)
          ..cubicTo(58, 66, 42, 66, 36, 60)
          ..close(),
        p.accent);
  });
}

void _faceAunt(Canvas c, MemoryFacePalette p) {
  _personFace(c, p, hair: (c2) {
    // curly hair — cluster of circles
    for (final (dx, dy) in [
      (30, 26), (42, 20), (58, 20), (70, 26), (76, 38),
      (24, 38), (78, 50), (22, 50),
    ]) {
      _circle(c2, Offset(dx.toDouble(), dy.toDouble()), 9, p.detail);
    }
    _circle(c2, const Offset(50, 22), 9, p.detail);
  });
}

void _faceBaby(Canvas c, MemoryFacePalette p) {
  _personFace(c, p, hair: (c2) {
    // single curl
    _stroke(
        c2,
        Path()
          ..moveTo(50, 24)
          ..quadraticBezierTo(56, 16, 62, 20),
        p.detail,
        4);
  });
  // pacifier
  _circle(c, const Offset(50, 66), 6, p.accent);
  _stroke(c, Path()..moveTo(44, 62)..lineTo(56, 62), p.detail, 2);
}

void _faceElder(Canvas c, MemoryFacePalette p) {
  _personFace(c, p, hair: (c2) {
    // white swept-back hair
    _path(
        c2,
        Path()
          ..moveTo(24, 46)
          ..cubicTo(22, 26, 36, 18, 52, 20)
          ..cubicTo(68, 22, 78, 30, 76, 46)
          ..cubicTo(66, 30, 36, 30, 24, 46)
          ..close(),
        p.detail);
    // wisdom lines
    _stroke(c2, Path()..moveTo(36, 42)..quadraticBezierTo(40, 40, 44, 42), Colors.white, 1.8);
    _stroke(c2, Path()..moveTo(56, 42)..quadraticBezierTo(60, 40, 64, 42), Colors.white, 1.8);
  });
}

void _faceBigFamily(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // three heads — big, medium, small — huddled together
  _circle(c, const Offset(30, 46), 18, p.base);
  _circle(c, const Offset(68, 44), 17, p.base);
  _circle(c, const Offset(50, 66), 20, p.base);
  // hair caps
  _path(c, Path()..addArc(const Rect.fromLTWH(15, 30, 30, 24), math.pi, math.pi), p.detail);
  _path(c, Path()..addArc(const Rect.fromLTWH(54, 28, 28, 22), math.pi, math.pi), p.accent);
  _path(c, Path()..addArc(const Rect.fromLTWH(34, 52, 32, 22), math.pi, math.pi), p.detail);
  // faces
  _circle(c, const Offset(24, 46), 2.4, p.detail);
  _circle(c, const Offset(36, 46), 2.4, p.detail);
  _circle(c, const Offset(63, 44), 2.2, p.detail);
  _circle(c, const Offset(74, 44), 2.2, p.detail);
  _circle(c, const Offset(44, 66), 2.6, p.detail);
  _circle(c, const Offset(56, 66), 2.6, p.detail);
  _stroke(c, Path()..moveTo(26, 52)..quadraticBezierTo(30, 55, 34, 52), p.detail, 2);
  _stroke(c, Path()..moveTo(65, 50)..quadraticBezierTo(69, 53, 72, 50), p.detail, 2);
  _stroke(c, Path()..moveTo(46, 72)..quadraticBezierTo(50, 75, 54, 72), p.detail, 2);
}

void _faceHug(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // two figures leaning in, arms wrapping
  _circle(c, const Offset(36, 38), 15, p.base);
  _circle(c, const Offset(64, 38), 15, p.base);
  _path(c, Path()..addArc(const Rect.fromLTWH(22, 26, 28, 22), math.pi, math.pi), p.detail);
  _path(c, Path()..addArc(const Rect.fromLTWH(50, 26, 28, 22), math.pi, math.pi), p.accent);
  // bodies
  _path(c, Path()..moveTo(36, 52)..cubicTo(22, 56, 20, 76, 22, 86)..lineTo(48, 86)..lineTo(48, 54)..close(), p.detail);
  _path(c, Path()..moveTo(64, 52)..cubicTo(78, 56, 80, 76, 78, 86)..lineTo(52, 86)..lineTo(52, 54)..close(), p.accent);
  // wrapping arms
  _stroke(c, Path()..moveTo(44, 56)..quadraticBezierTo(58, 50, 70, 58), p.base, 7);
  _stroke(c, Path()..moveTo(56, 56)..quadraticBezierTo(42, 50, 30, 58), p.base, 7);
  // hearts
  _path(c, _smallHeart(50, 20, 8), const Color(0xFFFF6B81));
  _circle(c, const Offset(31, 38), 2.6, p.detail);
  _circle(c, const Offset(41, 38), 2.6, p.detail);
  _circle(c, const Offset(59, 38), 2.6, p.detail);
  _circle(c, const Offset(69, 38), 2.6, p.detail);
}

Path _smallHeart(double cx, double cy, double s) {
  return Path()
    ..moveTo(cx, cy + s)
    ..cubicTo(cx - s * 1.6, cy - s * 0.4, cx - s * 0.8, cy - s * 1.4, cx, cy - s * 0.5)
    ..cubicTo(cx + s * 0.8, cy - s * 1.4, cx + s * 1.6, cy - s * 0.4, cx, cy + s)
    ..close();
}

void _faceHome(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // walls
  _rrect(c, const Rect.fromLTWH(24, 44, 52, 42), 4, p.base);
  // roof
  _path(c, Path()..moveTo(16, 46)..lineTo(50, 18)..lineTo(84, 46)..close(), p.accent);
  // door
  _rrect(c, const Rect.fromLTWH(43, 58, 14, 28), 6, p.detail);
  _circle(c, const Offset(53, 72), 1.8, p.highlight);
  // windows
  _rrect(c, const Rect.fromLTWH(30, 54, 10, 10), 2, p.highlight);
  _rrect(c, const Rect.fromLTWH(60, 54, 10, 10), 2, p.highlight);
  // chimney + smoke
  _rrect(c, const Rect.fromLTWH(66, 24, 8, 14), 2, p.detail);
  _stroke(c, Path()..moveTo(70, 20)..quadraticBezierTo(76, 14, 72, 8), Colors.white, 2.5);
}

void _facePetDog(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // floppy ears
  _oval(c, const Rect.fromLTWH(16, 36, 18, 34), p.accent);
  _oval(c, const Rect.fromLTWH(66, 36, 18, 34), p.accent);
  // head
  _circle(c, const Offset(50, 50), 28, p.base);
  // muzzle
  _oval(c, const Rect.fromLTWH(38, 52, 24, 18), Colors.white);
  _circle(c, const Offset(50, 58), 5, p.detail);
  // eyes + brows
  _circle(c, const Offset(40, 44), 3.4, p.detail);
  _circle(c, const Offset(60, 44), 3.4, p.detail);
  // tongue
  _path(c, Path()..moveTo(46, 66)..quadraticBezierTo(50, 76, 54, 66)..close(), const Color(0xFFE8798A));
  // collar
  _stroke(c, Path()..moveTo(34, 68)..quadraticBezierTo(50, 78, 66, 68), p.accent, 5);
  _circle(c, const Offset(50, 74), 3, const Color(0xFFFFC940));
}

void _faceHomeFood(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // bowl
  _path(c, Path()..moveTo(20, 52)..quadraticBezierTo(24, 82, 50, 82)..quadraticBezierTo(76, 82, 80, 52)..close(), p.accent);
  // foot
  _rrect(c, const Rect.fromLTWH(38, 82, 24, 8), 3, p.detail);
  // rim
  _oval(c, const Rect.fromLTWH(18, 46, 64, 12), p.base);
  // steam curls
  _stroke(c, Path()..moveTo(38, 38)..quadraticBezierTo(34, 30, 38, 24), Colors.white, 3);
  _stroke(c, Path()..moveTo(50, 36)..quadraticBezierTo(46, 27, 50, 20), Colors.white, 3);
  _stroke(c, Path()..moveTo(62, 38)..quadraticBezierTo(58, 30, 62, 24), Colors.white, 3);
  // highlight
  _stroke(c, Path()..moveTo(28, 60)..quadraticBezierTo(30, 70, 36, 75), Colors.white, 3);
}

void _facePicnic(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // checkered blanket
  _rrect(c, const Rect.fromLTWH(12, 62, 76, 22), 6, p.base);
  for (var i = 0; i < 5; i++) {
    for (var j = 0; j < 2; j++) {
      if ((i + j).isEven) {
        _rrect(c, Rect.fromLTWH(14 + i * 14.4, 64 + j * 10, 14.4, 10), 1, p.accent);
      }
    }
  }
  // basket
  _path(c, Path()..moveTo(30, 40)..quadraticBezierTo(32, 64, 50, 64)..quadraticBezierTo(68, 64, 70, 40)..close(), p.detail);
  _stroke(c, Path()..moveTo(30, 42)..quadraticBezierTo(50, 50, 70, 42), p.base, 3);
  _stroke(c, Path()..moveTo(50, 44)..quadraticBezierTo(50, 34, 58, 32)..quadraticBezierTo(64, 31, 62, 38), p.base, 3);
  // bread + apple peeking
  _oval(c, const Rect.fromLTWH(34, 30, 14, 10), Colors.white);
  _circle(c, const Offset(62, 34), 6, const Color(0xFFE84393));
  _path(c, Path()..moveTo(62, 27)..quadraticBezierTo(64, 23, 66, 24), const Color(0xFF5E8A5E), );
}

void _faceStoryTime(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // open book
  _path(c, Path()..moveTo(50, 36)..cubicTo(40, 28, 24, 28, 16, 32)..lineTo(16, 72)..cubicTo(24, 68, 40, 68, 50, 76)..close(), p.base);
  _path(c, Path()..moveTo(50, 36)..cubicTo(60, 28, 76, 28, 84, 32)..lineTo(84, 72)..cubicTo(76, 68, 60, 68, 50, 76)..close(), p.base);
  // pages
  _stroke(c, Path()..moveTo(50, 40)..cubicTo(42, 33, 28, 33, 21, 36), Colors.white, 2.5);
  _stroke(c, Path()..moveTo(50, 48)..cubicTo(42, 41, 28, 41, 21, 44), Colors.white, 2.5);
  _stroke(c, Path()..moveTo(50, 56)..cubicTo(42, 49, 28, 49, 21, 52), Colors.white, 2.5);
  _stroke(c, Path()..moveTo(50, 40)..cubicTo(58, 33, 72, 33, 79, 36), Colors.white, 2.5);
  _stroke(c, Path()..moveTo(50, 48)..cubicTo(58, 41, 72, 41, 79, 44), Colors.white, 2.5);
  _stroke(c, Path()..moveTo(50, 56)..cubicTo(58, 49, 72, 49, 79, 52), Colors.white, 2.5);
  _stroke(c, Path()..moveTo(50, 36)..lineTo(50, 76), p.detail, 3);
  // sparkle above
  _path(c, _sparklePath(50, 18, 10, 3.5), p.accent);
  _path(c, _sparklePath(34, 14, 6, 2), p.accent);
  _path(c, _sparklePath(66, 12, 6, 2), p.accent);
}

// ─────────────────────────────────────────────────────────────────────
// FOOD pack — appetizing flat illustrations.
// ─────────────────────────────────────────────────────────────────────

final List<MemoryFaceSpec> _foodList = [
  MemoryFaceSpec(
    key: 'pizza',
    label: 'Pizza',
    palette: const MemoryFacePalette(
        base: Color(0xFFF5C04E), accent: Color(0xFFE8612A), detail: Color(0xFFC44A18)),
    painter: _facePizza,
  ),
  MemoryFaceSpec(
    key: 'burger',
    label: 'Burger',
    palette: const MemoryFacePalette(
        base: Color(0xFFF0B45E), accent: Color(0xFF5E8A3E), detail: Color(0xFF6B3E28)),
    painter: _faceBurger,
  ),
  MemoryFaceSpec(
    key: 'icecream',
    label: 'Ice Cream',
    palette: const MemoryFacePalette(
        base: Color(0xFFF7DCC2), accent: Color(0xFFE8798A), detail: Color(0xFFC98E62)),
    painter: _faceIceCream,
  ),
  MemoryFaceSpec(
    key: 'cake',
    label: 'Cake',
    palette: const MemoryFacePalette(
        base: Color(0xFFF7DCC2), accent: Color(0xFFE8798A), detail: Color(0xFFC44A18)),
    painter: _faceCake,
  ),
  MemoryFaceSpec(
    key: 'apple',
    label: 'Apple',
    palette: const MemoryFacePalette(
        base: Color(0xFFE84393), accent: Color(0xFF5E8A3E), detail: Color(0xFFC44569)),
    painter: _faceApple,
  ),
  MemoryFaceSpec(
    key: 'fish',
    label: 'Fish',
    palette: const MemoryFacePalette(
        base: Color(0xFF6FD8E8), accent: Color(0xFF3E5E7E), detail: Color(0xFF2C7E9E)),
    painter: _faceFish,
  ),
  MemoryFaceSpec(
    key: 'coffee',
    label: 'Coffee',
    palette: const MemoryFacePalette(
        base: Color(0xFF8C6239), accent: Color(0xFFF5EEE0), detail: Color(0xFF5E4630)),
    painter: _faceCoffee,
  ),
  MemoryFaceSpec(
    key: 'donut',
    label: 'Donut',
    palette: const MemoryFacePalette(
        base: Color(0xFFC08E66), accent: Color(0xFF8FD4E8), detail: Color(0xFFC98E62)),
    painter: _faceDonut,
  ),
  MemoryFaceSpec(
    key: 'banana',
    label: 'Banana',
    palette: const MemoryFacePalette(
        base: Color(0xFFFFE08A), accent: Color(0xFFE8A05C), detail: Color(0xFFC98E2E)),
    painter: _faceBanana,
  ),
  MemoryFaceSpec(
    key: 'grapes',
    label: 'Grapes',
    palette: const MemoryFacePalette(
        base: Color(0xFF9B8CFF), accent: Color(0xFF6B4FD4), detail: Color(0xFF5E8A3E)),
    painter: _faceGrapes,
  ),
  MemoryFaceSpec(
    key: 'taco',
    label: 'Taco',
    palette: const MemoryFacePalette(
        base: Color(0xFFF0B45E), accent: Color(0xFF5E8A3E), detail: Color(0xFFE84393)),
    painter: _faceTaco,
  ),
  MemoryFaceSpec(
    key: 'noodles',
    label: 'Noodles',
    palette: const MemoryFacePalette(
        base: Color(0xFFF5EEE0), accent: Color(0xFFE8A05C), detail: Color(0xFFC44A18)),
    painter: _faceNoodles,
  ),
  MemoryFaceSpec(
    key: 'sushi',
    label: 'Sushi',
    palette: const MemoryFacePalette(
        base: Color(0xFFF5EEE0), accent: Color(0xFFE8798A), detail: Color(0xFF2E3A2E)),
    painter: _faceSushi,
  ),
  MemoryFaceSpec(
    key: 'cookie',
    label: 'Cookie',
    palette: const MemoryFacePalette(
        base: Color(0xFFD9A05C), accent: Color(0xFF6B3E28), detail: Color(0xFFC98E62)),
    painter: _faceCookie,
  ),
  MemoryFaceSpec(
    key: 'cupcake',
    label: 'Cupcake',
    palette: const MemoryFacePalette(
        base: Color(0xFFF7DCC2), accent: Color(0xFF9B8CFF), detail: Color(0xFFE8798A)),
    painter: _faceCupcake,
  ),
  MemoryFaceSpec(
    key: 'strawberry',
    label: 'Strawberry',
    palette: const MemoryFacePalette(
        base: Color(0xFFE84393), accent: Color(0xFF5E8A3E), detail: Color(0xFFFFC940)),
    painter: _faceStrawberry,
  ),
  MemoryFaceSpec(
    key: 'avocado',
    label: 'Avocado',
    palette: const MemoryFacePalette(
        base: Color(0xFF6FB861), accent: Color(0xFFF5E6A8), detail: Color(0xFF4E7E42)),
    painter: _faceAvocado,
  ),
  MemoryFaceSpec(
    key: 'popcorn',
    label: 'Popcorn',
    palette: const MemoryFacePalette(
        base: Color(0xFFF5EEE0), accent: Color(0xFFE8432A), detail: Color(0xFFC98E62)),
    painter: _facePopcorn,
  ),
];

void _facePizza(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // slice
  _path(c, Path()..moveTo(50, 88)..lineTo(16, 20)..lineTo(84, 20)..close(), p.base);
  // crust
  _path(c, Path()..moveTo(14, 16)..quadraticBezierTo(50, 4, 86, 16)..lineTo(84, 24)..quadraticBezierTo(50, 12, 16, 24)..close(), p.accent);
  // pepperoni
  _circle(c, const Offset(42, 38), 6, p.detail);
  _circle(c, const Offset(60, 40), 6, p.detail);
  _circle(c, const Offset(50, 58), 6, p.detail);
  _circle(c, const Offset(36, 58), 5, p.detail);
}

void _faceBurger(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // bottom bun
  _path(c, Path()..moveTo(20, 66)..quadraticBezierTo(24, 86, 50, 86)..quadraticBezierTo(76, 86, 80, 66)..close(), p.base);
  // patty
  _rrect(c, const Rect.fromLTWH(18, 56, 64, 12), 6, p.detail);
  // cheese
  _path(c, Path()..moveTo(18, 54)..lineTo(82, 54)..lineTo(74, 62)..lineTo(66, 55)..lineTo(58, 63)..lineTo(50, 55)..lineTo(42, 63)..lineTo(34, 55)..lineTo(26, 63)..close(), const Color(0xFFFFC940));
  // lettuce
  _path(c, Path()..moveTo(18, 44)..quadraticBezierTo(26, 52, 34, 44)..quadraticBezierTo(42, 52, 50, 44)..quadraticBezierTo(58, 52, 66, 44)..quadraticBezierTo(74, 52, 82, 44)..lineTo(82, 38)..lineTo(18, 38)..close(), p.accent);
  // top bun
  _path(c, Path()..moveTo(18, 40)..quadraticBezierTo(20, 12, 50, 12)..quadraticBezierTo(80, 12, 82, 40)..close(), p.base);
  // sesame
  _oval(c, const Rect.fromLTWH(36, 20, 7, 4), Colors.white);
  _oval(c, const Rect.fromLTWH(52, 18, 7, 4), Colors.white);
  _oval(c, const Rect.fromLTWH(44, 28, 7, 4), Colors.white);
}

void _faceIceCream(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // cone
  _path(c, Path()..moveTo(32, 48)..lineTo(50, 92)..lineTo(68, 48)..close(), p.detail);
  // waffle lines
  _stroke(c, Path()..moveTo(36, 56)..lineTo(62, 50), p.base, 2);
  _stroke(c, Path()..moveTo(42, 68)..lineTo(58, 54), p.base, 2);
  _stroke(c, Path()..moveTo(48, 78)..lineTo(55, 58), p.base, 2);
  // scoops
  _circle(c, const Offset(38, 36), 15, p.base);
  _circle(c, const Offset(62, 36), 15, p.accent);
  _circle(c, const Offset(50, 24), 14, p.base);
  // cherry
  _circle(c, const Offset(50, 10), 5, const Color(0xFFE84393));
}

void _faceCake(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // plate
  _oval(c, const Rect.fromLTWH(16, 80, 68, 10), Colors.white);
  // base tier
  _rrect(c, const Rect.fromLTWH(24, 52, 52, 30), 4, p.base);
  // top tier
  _rrect(c, const Rect.fromLTWH(32, 30, 36, 24), 4, p.base);
  // frosting drips
  _path(c, Path()..moveTo(32, 32)..lineTo(68, 32)..lineTo(68, 40)..quadraticBezierTo(64, 46, 60, 40)..quadraticBezierTo(56, 48, 52, 40)..quadraticBezierTo(48, 46, 44, 40)..quadraticBezierTo(40, 48, 36, 40)..quadraticBezierTo(34, 44, 32, 42)..close(), p.accent);
  _path(c, Path()..moveTo(24, 54)..lineTo(76, 54)..lineTo(76, 62)..quadraticBezierTo(70, 70, 64, 62)..quadraticBezierTo(58, 70, 50, 62)..quadraticBezierTo(44, 70, 36, 62)..quadraticBezierTo(30, 68, 24, 64)..close(), p.accent);
  // candle
  _rrect(c, const Rect.fromLTWH(47, 14, 6, 16), 2, p.detail);
  _path(c, Path()..moveTo(50, 4)..quadraticBezierTo(55, 8, 50, 12)..quadraticBezierTo(45, 8, 50, 4)..close(), const Color(0xFFF59240));
}

void _faceApple(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // body
  _path(c, Path()..moveTo(50, 26)..cubicTo(30, 12, 12, 26, 16, 52)..cubicTo(19, 74, 34, 86, 50, 84)..cubicTo(66, 86, 81, 74, 84, 52)..cubicTo(88, 26, 70, 12, 50, 26)..close(), p.base);
  // leaf
  _path(c, Path()..moveTo(52, 20)..quadraticBezierTo(64, 4, 78, 10)..quadraticBezierTo(70, 24, 52, 20)..close(), p.accent);
  // stem
  _stroke(c, Path()..moveTo(50, 24)..quadraticBezierTo(50, 16, 46, 10), p.detail, 4);
  _hl(c, const Offset(34, 40), 6);
}

void _faceFish(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // tail
  _path(c, Path()..moveTo(70, 50)..lineTo(88, 32)..lineTo(88, 68)..close(), p.accent);
  // body
  _oval(c, const Rect.fromLTWH(12, 28, 64, 44), p.base);
  // fin
  _path(c, Path()..moveTo(38, 30)..quadraticBezierTo(46, 14, 56, 28)..close(), p.accent);
  // eye
  _circle(c, const Offset(28, 44), 5, Colors.white);
  _circle(c, const Offset(29, 44), 2.5, p.detail);
  // gill
  _stroke(c, Path()..moveTo(38, 38)..quadraticBezierTo(42, 50, 38, 62), p.accent, 3);
  // bubbles
  _stroke(c, Path()..addOval(const Rect.fromLTWH(14, 18, 7, 7)), Colors.white, 2);
  _stroke(c, Path()..addOval(const Rect.fromLTWH(24, 10, 5, 5)), Colors.white, 2);
}

void _faceCoffee(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // cup
  _path(c, Path()..moveTo(22, 38)..quadraticBezierTo(24, 78, 50, 78)..quadraticBezierTo(76, 78, 78, 38)..close(), p.base);
  // rim
  _oval(c, const Rect.fromLTWH(20, 32, 60, 12), p.detail);
  _oval(c, const Rect.fromLTWH(24, 34, 52, 8), p.accent);
  // handle
  _stroke(c, Path()..addOval(const Rect.fromLTWH(74, 44, 16, 20)), p.base, 5);
  // steam
  _stroke(c, Path()..moveTo(40, 24)..quadraticBezierTo(36, 16, 40, 8), Colors.white, 3);
  _stroke(c, Path()..moveTo(52, 22)..quadraticBezierTo(48, 13, 52, 5), Colors.white, 3);
  _stroke(c, Path()..moveTo(63, 24)..quadraticBezierTo(59, 16, 63, 8), Colors.white, 3);
}

void _faceDonut(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // dough
  _circle(c, const Offset(50, 50), 34, p.base);
  // frosting
  _path(c, Path()..moveTo(50, 16)..cubicTo(28, 16, 16, 30, 18, 46)..cubicTo(20, 60, 30, 52, 36, 58)..cubicTo(42, 64, 44, 72, 56, 74)..cubicTo(72, 76, 84, 62, 84, 46)..cubicTo(84, 28, 70, 16, 50, 16)..close(), p.accent);
  // hole
  _circle(c, const Offset(50, 52), 10, p.detail);
  // sprinkles
  _stroke(c, Path()..moveTo(34, 34)..lineTo(40, 38), Colors.white, 3);
  _stroke(c, Path()..moveTo(56, 26)..lineTo(62, 30), Colors.white, 3);
  _stroke(c, Path()..moveTo(64, 44)..lineTo(70, 48), Colors.white, 3);
  _stroke(c, Path()..moveTo(30, 50)..lineTo(36, 54), Colors.white, 3);
  _stroke(c, Path()..moveTo(52, 36)..lineTo(58, 40), const Color(0xFFE84393), 3);
}

void _faceBanana(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // crescent
  _path(c, Path()..moveTo(14, 30)..cubicTo(12, 58, 34, 84, 66, 86)..cubicTo(78, 87, 86, 82, 88, 74)..cubicTo(76, 78, 66, 76, 58, 68)..cubicTo(44, 56, 38, 44, 38, 30)..cubicTo(38, 20, 30, 14, 20, 16)..cubicTo(16, 20, 14, 25, 14, 30)..close(), p.base);
  // tip
  _rrect(c, const Rect.fromLTWH(12, 16, 10, 10), 3, p.detail);
  _stroke(c, Path()..moveTo(24, 38)..cubicTo(28, 54, 40, 68, 56, 74), p.accent, 2.5);
}

void _faceGrapes(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // cluster
  for (final (x, y) in [(36, 36), (50, 34), (64, 36), (28, 50), (43, 50), (57, 50), (71, 50), (36, 64), (50, 64), (64, 64), (50, 78)]) {
    _circle(c, Offset(x.toDouble(), y.toDouble()), 9, p.base);
  }
  // stems
  _stroke(c, Path()..moveTo(50, 26)..lineTo(50, 14), p.detail, 3);
  _path(c, Path()..moveTo(50, 16)..quadraticBezierTo(62, 8, 72, 12)..quadraticBezierTo(64, 22, 50, 16)..close(), p.accent);
  // shine
  _circle(c, const Offset(32, 33), 2.5, Colors.white);
  _circle(c, const Offset(46, 31), 2.5, Colors.white);
}

void _faceTaco(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // shell
  _path(c, Path()..moveTo(10, 70)..quadraticBezierTo(14, 24, 50, 22)..quadraticBezierTo(86, 24, 90, 70)..quadraticBezierTo(70, 62, 50, 62)..quadraticBezierTo(30, 62, 10, 70)..close(), p.base);
  // filling
  _path(c, Path()..moveTo(16, 60)..quadraticBezierTo(20, 30, 50, 28)..quadraticBezierTo(80, 30, 84, 60)..quadraticBezierTo(70, 54, 62, 58)..quadraticBezierTo(56, 62, 50, 56)..quadraticBezierTo(42, 62, 36, 56)..quadraticBezierTo(28, 60, 16, 60)..close(), p.accent);
  // tomato bits
  _circle(c, const Offset(34, 42), 4, p.detail);
  _circle(c, const Offset(52, 38), 4, p.detail);
  _circle(c, const Offset(66, 44), 4, p.detail);
}

void _faceNoodles(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // bowl
  _path(c, Path()..moveTo(14, 50)..quadraticBezierTo(18, 82, 50, 82)..quadraticBezierTo(82, 82, 86, 50)..close(), p.base);
  // stripes
  _stroke(c, Path()..moveTo(28, 62)..lineTo(30, 78), p.accent, 3);
  _stroke(c, Path()..moveTo(50, 66)..lineTo(50, 82), p.accent, 3);
  _stroke(c, Path()..moveTo(72, 62)..lineTo(70, 78), p.accent, 3);
  // noodle loops peeking
  _stroke(c, Path()..moveTo(22, 48)..cubicTo(28, 38, 36, 38, 40, 48), p.accent, 4);
  _stroke(c, Path()..moveTo(44, 46)..cubicTo(50, 36, 58, 36, 62, 46), p.accent, 4);
  _stroke(c, Path()..moveTo(66, 48)..cubicTo(72, 40, 78, 40, 80, 48), p.accent, 4);
  // chopsticks
  _stroke(c, Path()..moveTo(34, 40)..lineTo(78, 8), p.detail, 3.5);
  _stroke(c, Path()..moveTo(44, 42)..lineTo(84, 14), p.detail, 3.5);
  // steam
  _stroke(c, Path()..moveTo(30, 26)..quadraticBezierTo(26, 18, 30, 10), Colors.white, 2.5);
}

void _faceSushi(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // rice base
  _rrect(c, const Rect.fromLTWH(18, 46, 64, 30), 14, p.base);
  // salmon top
  _rrect(c, const Rect.fromLTWH(18, 26, 64, 24), 10, p.accent);
  // salmon streaks
  _stroke(c, Path()..moveTo(28, 34)..quadraticBezierTo(36, 30, 44, 34), Colors.white, 2.5);
  _stroke(c, Path()..moveTo(52, 34)..quadraticBezierTo(60, 30, 68, 34), Colors.white, 2.5);
  // nori band
  _rrect(c, const Rect.fromLTWH(40, 20, 20, 58), 4, p.detail);
  // rice grains
  _stroke(c, Path()..moveTo(30, 58)..lineTo(35, 60), p.detail, 2);
  _stroke(c, Path()..moveTo(62, 62)..lineTo(67, 64), p.detail, 2);
}

void _faceCookie(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // cookie with a bite taken out (path difference)
  final body = Path()..addOval(const Rect.fromLTWH(16, 16, 68, 68));
  final bite = Path()..addOval(const Rect.fromLTWH(70, 18, 26, 26));
  _path(c, Path.combine(PathOperation.difference, body, bite), p.base);
  // chips
  _circle(c, const Offset(38, 40), 6, p.accent);
  _circle(c, const Offset(56, 34), 5, p.accent);
  _circle(c, const Offset(50, 58), 6, p.accent);
  _circle(c, const Offset(34, 62), 4.5, p.accent);
  _circle(c, const Offset(62, 56), 4.5, p.accent);
  _hl(c, const Offset(38, 30), 4);
}

void _faceCupcake(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // wrapper
  _path(c, Path()..moveTo(28, 54)..lineTo(34, 88)..lineTo(66, 88)..lineTo(72, 54)..close(), p.base);
  // wrapper pleats
  _stroke(c, Path()..moveTo(40, 56)..lineTo(43, 86), p.detail, 2);
  _stroke(c, Path()..moveTo(50, 56)..lineTo(50, 88), p.detail, 2);
  _stroke(c, Path()..moveTo(60, 56)..lineTo(57, 86), p.detail, 2);
  // frosting swirl
  _path(c, Path()..moveTo(26, 54)..quadraticBezierTo(22, 42, 34, 40)..quadraticBezierTo(32, 28, 46, 28)..quadraticBezierTo(48, 14, 62, 18)..quadraticBezierTo(76, 20, 74, 34)..quadraticBezierTo(82, 40, 74, 54)..close(), p.accent);
  // cherry
  _circle(c, const Offset(56, 12), 5, p.detail);
  _stroke(c, Path()..moveTo(56, 7)..quadraticBezierTo(60, 2, 64, 4), p.detail, 2);
}

void _faceStrawberry(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // body
  _path(c, Path()..moveTo(50, 88)..cubicTo(24, 72, 14, 52, 18, 38)..cubicTo(22, 24, 38, 18, 50, 18)..cubicTo(62, 18, 78, 24, 82, 38)..cubicTo(86, 52, 76, 72, 50, 88)..close(), p.base);
  // seeds
  for (final (x, y) in [(34, 44), (50, 42), (66, 44), (40, 58), (56, 58), (48, 72), (62, 70), (34, 70)]) {
    _oval(c, Rect.fromLTWH(x - 1.5, y - 2.2, 3, 4.4), p.detail);
  }
  // leaves
  _path(c, Path()..moveTo(50, 20)..lineTo(34, 10)..lineTo(44, 22)..lineTo(50, 8)..lineTo(56, 22)..lineTo(66, 10)..close(), p.accent);
  _stroke(c, Path()..moveTo(50, 18)..lineTo(50, 26), p.accent, 3);
}

void _faceAvocado(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // half avocado (skin)
  _path(c, Path()..moveTo(50, 10)..cubicTo(28, 14, 16, 34, 18, 56)..cubicTo(20, 78, 36, 90, 50, 90)..cubicTo(64, 90, 80, 78, 82, 56)..cubicTo(84, 34, 72, 14, 50, 10)..close(), p.detail);
  // flesh
  _path(c, Path()..moveTo(50, 18)..cubicTo(32, 22, 23, 38, 25, 56)..cubicTo(27, 73, 39, 82, 50, 82)..cubicTo(61, 82, 73, 73, 75, 56)..cubicTo(77, 38, 68, 22, 50, 18)..close(), p.base);
  // pit
  _circle(c, const Offset(50, 56), 14, p.accent);
  _hl(c, const Offset(44, 50), 4);
}

void _facePopcorn(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // striped box
  _path(c, Path()..moveTo(26, 44)..lineTo(32, 88)..lineTo(68, 88)..lineTo(74, 44)..close(), p.accent);
  _stroke(c, Path()..moveTo(38, 46)..lineTo(41, 86), Colors.white, 3);
  _stroke(c, Path()..moveTo(50, 46)..lineTo(50, 88), Colors.white, 3);
  _stroke(c, Path()..moveTo(62, 46)..lineTo(59, 86), Colors.white, 3);
  // popped kernels
  for (final (x, y, r) in [(30, 34, 9), (44, 26, 10), (58, 24, 9), (70, 34, 9), (38, 18, 7), (54, 14, 7), (66, 18, 7)]) {
    _circle(c, Offset(x.toDouble(), y.toDouble()), r.toDouble(), p.base);
  }
  // kernel details
  _circle(c, const Offset(44, 26), 4, p.detail);
  _circle(c, const Offset(58, 24), 3.5, p.detail);
  _circle(c, const Offset(30, 34), 3.5, p.detail);
}

// ─────────────────────────────────────────────────────────────────────
// ANIMALS pack — friendly animal portraits.
// ─────────────────────────────────────────────────────────────────────

// Shared animal-face scaffold: round head + eyes + snout + smile.
void _animalFace(Canvas c, MemoryFacePalette p,
    {required void Function(Canvas) features}) {
  _groundShadow(c);
  _circle(c, const Offset(50, 52), 28, p.base);
  features(c);
}

// Standard eyes + snout + smile used by most animals.
void _animalEyes(Canvas c, MemoryFacePalette p) {
  _circle(c, const Offset(39, 44), 3.8, p.detail);
  _circle(c, const Offset(61, 44), 3.8, p.detail);
  _circle(c, const Offset(44, 38), 1.4, Colors.white);
  _circle(c, const Offset(66, 38), 1.4, Colors.white);
}

void _animalSnout(Canvas c, MemoryFacePalette p) {
  _oval(c, const Rect.fromLTWH(38, 54, 24, 16), Colors.white);
  _circle(c, const Offset(50, 58), 3.2, p.detail);
  _stroke(c, Path()..moveTo(50, 61)..lineTo(50, 65), p.detail, 2);
  _stroke(c, Path()..moveTo(45, 66)..quadraticBezierTo(50, 70, 55, 66), p.detail, 2.5);
}

final List<MemoryFaceSpec> _animalsList = [
  MemoryFaceSpec(
    key: 'dog',
    label: 'Dog',
    palette: const MemoryFacePalette(
        base: Color(0xFFD9A96B), accent: Color(0xFF8C6239), detail: Color(0xFF2E2A26)),
    painter: _faceADog,
  ),
  MemoryFaceSpec(
    key: 'cat',
    label: 'Cat',
    palette: const MemoryFacePalette(
        base: Color(0xFFF0B45E), accent: Color(0xFFE8862A), detail: Color(0xFF2E2A26)),
    painter: _faceACat,
  ),
  MemoryFaceSpec(
    key: 'lion',
    label: 'Lion',
    palette: const MemoryFacePalette(
        base: Color(0xFFD9A05C), accent: Color(0xFFC9822E), detail: Color(0xFF5E4630)),
    painter: _faceALion,
  ),
  MemoryFaceSpec(
    key: 'tiger',
    label: 'Tiger',
    palette: const MemoryFacePalette(
        base: Color(0xFFF59240), accent: Color(0xFF2E2A26), detail: Color(0xFFC44A18)),
    painter: _faceATiger,
  ),
  MemoryFaceSpec(
    key: 'elephant',
    label: 'Elephant',
    palette: const MemoryFacePalette(
        base: Color(0xFF9BA8C4), accent: Color(0xFF7E8BA8), detail: Color(0xFF5A6478)),
    painter: _faceAElephant,
  ),
  MemoryFaceSpec(
    key: 'rabbit',
    label: 'Rabbit',
    palette: const MemoryFacePalette(
        base: Color(0xFFF5EEE0), accent: Color(0xFFFFC9D4), detail: Color(0xFF5E4638)),
    painter: _faceARabbit,
  ),
  MemoryFaceSpec(
    key: 'panda',
    label: 'Panda',
    palette: const MemoryFacePalette(
        base: Color(0xFFF5F5F5), accent: Color(0xFF2E2A30), detail: Color(0xFF1E1E24)),
    painter: _faceAPanda,
  ),
  MemoryFaceSpec(
    key: 'bear',
    label: 'Bear',
    palette: const MemoryFacePalette(
        base: Color(0xFFB07845), accent: Color(0xFF8C5A2E), detail: Color(0xFF3E2E1E)),
    painter: _faceABear,
  ),
  MemoryFaceSpec(
    key: 'fox',
    label: 'Fox',
    palette: const MemoryFacePalette(
        base: Color(0xFFE8762A), accent: Color(0xFFFFF5EE), detail: Color(0xFF5E2E14)),
    painter: _faceAFox,
  ),
  MemoryFaceSpec(
    key: 'koala',
    label: 'Koala',
    palette: const MemoryFacePalette(
        base: Color(0xFFB8BCC9), accent: Color(0xFFE8EAEE), detail: Color(0xFF4E5462)),
    painter: _faceAKoala,
  ),
  MemoryFaceSpec(
    key: 'cow',
    label: 'Cow',
    palette: const MemoryFacePalette(
        base: Color(0xFFF5F0EE), accent: Color(0xFF2E2A26), detail: Color(0xFFE8A0B4)),
    painter: _faceACow,
  ),
  MemoryFaceSpec(
    key: 'pig',
    label: 'Pig',
    palette: const MemoryFacePalette(
        base: Color(0xFFF7B8C4), accent: Color(0xFFE892A4), detail: Color(0xFF6B3E4A)),
    painter: _faceAPig,
  ),
  MemoryFaceSpec(
    key: 'monkey',
    label: 'Monkey',
    palette: const MemoryFacePalette(
        base: Color(0xFFB07845), accent: Color(0xFFF5D1B4), detail: Color(0xFF4A2E18)),
    painter: _faceAMonkey,
  ),
  MemoryFaceSpec(
    key: 'hen',
    label: 'Hen',
    palette: const MemoryFacePalette(
        base: Color(0xFFF5EEE0), accent: Color(0xFFE8432A), detail: Color(0xFFFFC940)),
    painter: _faceAHen,
  ),
  MemoryFaceSpec(
    key: 'unicorn',
    label: 'Unicorn',
    palette: const MemoryFacePalette(
        base: Color(0xFFF5F0F8), accent: Color(0xFF9B8CFF), detail: Color(0xFF4E4678)),
    painter: _faceAUnicorn,
  ),
  MemoryFaceSpec(
    key: 'turtle',
    label: 'Turtle',
    palette: const MemoryFacePalette(
        base: Color(0xFF6FB861), accent: Color(0xFF4E7E42), detail: Color(0xFF2E4A26)),
    painter: _faceATurtle,
  ),
  MemoryFaceSpec(
    key: 'frog',
    label: 'Frog',
    palette: const MemoryFacePalette(
        base: Color(0xFF7ECB6B), accent: Color(0xFF5EA84E), detail: Color(0xFF2E4A26)),
    painter: _faceAFrog,
  ),
  MemoryFaceSpec(
    key: 'owl',
    label: 'Owl',
    palette: const MemoryFacePalette(
        base: Color(0xFF9B7E5E), accent: Color(0xFFF5E6C8), detail: Color(0xFF4A3626)),
    painter: _faceAOwl,
  ),
];

void _faceADog(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // floppy ears behind
    _oval(c2, const Rect.fromLTWH(14, 34, 18, 36), p.accent);
    _oval(c2, const Rect.fromLTWH(68, 34, 18, 36), p.accent);
    _circle(c2, const Offset(50, 52), 28, p.base);
    _animalEyes(c2, p);
    // patch over one eye
    _circle(c2, const Offset(61, 44), 7, p.accent.withValues(alpha: 0.5));
    _circle(c2, const Offset(61, 44), 3.8, p.detail);
    _animalSnout(c2, p);
    // tongue
    _path(c2, Path()..moveTo(46, 68)..quadraticBezierTo(50, 78, 54, 68)..close(), const Color(0xFFE8798A));
    // brows
    _stroke(c2, Path()..moveTo(34, 36)..quadraticBezierTo(39, 33, 44, 36), p.accent, 2.5);
    _stroke(c2, Path()..moveTo(56, 36)..quadraticBezierTo(61, 33, 66, 36), p.accent, 2.5);
  });
}

void _faceACat(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // triangle ears
    _path(c2, Path()..moveTo(26, 34)..lineTo(30, 12)..lineTo(48, 26)..close(), p.base);
    _path(c2, Path()..moveTo(74, 34)..lineTo(70, 12)..lineTo(52, 26)..close(), p.base);
    _path(c2, Path()..moveTo(31, 28)..lineTo(33, 18)..lineTo(42, 25)..close(), p.accent);
    _path(c2, Path()..moveTo(69, 28)..lineTo(67, 18)..lineTo(58, 25)..close(), p.accent);
    _circle(c2, const Offset(50, 52), 28, p.base);
    _animalEyes(c2, p);
    _animalSnout(c2, p);
    // whiskers
    _stroke(c2, Path()..moveTo(20, 54)..lineTo(34, 56), p.detail, 2);
    _stroke(c2, Path()..moveTo(20, 62)..lineTo(34, 62), p.detail, 2);
    _stroke(c2, Path()..moveTo(80, 54)..lineTo(66, 56), p.detail, 2);
    _stroke(c2, Path()..moveTo(80, 62)..lineTo(66, 62), p.detail, 2);
  });
}

void _faceALion(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // mane — ring of fluff
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      _circle(c2, Offset(50 + 31 * math.cos(a), 52 + 31 * math.sin(a)), 9, p.accent);
    }
    _circle(c2, const Offset(50, 52), 26, p.base);
    _animalEyes(c2, p);
    _animalSnout(c2, p);
    // mane tuft on top
    _path(c2, Path()..moveTo(50, 18)..quadraticBezierTo(58, 8, 66, 12)..quadraticBezierTo(58, 16, 56, 24)..close(), p.accent);
  });
}

void _faceATiger(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // round ears
    _circle(c2, const Offset(28, 28), 10, p.base);
    _circle(c2, const Offset(72, 28), 10, p.base);
    _circle(c2, const Offset(50, 52), 28, p.base);
    // stripes
    _stroke(c2, Path()..moveTo(50, 24)..lineTo(50, 34), p.detail, 4);
    _stroke(c2, Path()..moveTo(36, 28)..quadraticBezierTo(40, 36, 38, 40), p.detail, 3.5);
    _stroke(c2, Path()..moveTo(64, 28)..quadraticBezierTo(60, 36, 62, 40), p.detail, 3.5);
    _stroke(c2, Path()..moveTo(24, 52)..quadraticBezierTo(30, 50, 32, 46), p.detail, 3.5);
    _stroke(c2, Path()..moveTo(76, 52)..quadraticBezierTo(70, 50, 68, 46), p.detail, 3.5);
    _animalEyes(c2, p);
    _animalSnout(c2, p);
  });
}

void _faceAElephant(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // big ears
    _oval(c2, const Rect.fromLTWH(6, 30, 26, 38), p.accent);
    _oval(c2, const Rect.fromLTWH(68, 30, 26, 38), p.accent);
    _circle(c2, const Offset(50, 50), 28, p.base);
    // trunk
    _path(c2, Path()..moveTo(44, 56)..quadraticBezierTo(38, 72, 46, 82)..quadraticBezierTo(54, 88, 60, 82)..quadraticBezierTo(52, 78, 50, 70)..quadraticBezierTo(50, 62, 56, 56)..close(), p.base);
    // eyes
    _circle(c2, const Offset(38, 44), 3.8, p.detail);
    _circle(c2, const Offset(62, 44), 3.8, p.detail);
    // tusks
    _path(c2, Path()..moveTo(38, 62)..quadraticBezierTo(34, 70, 38, 74)..quadraticBezierTo(41, 69, 41, 63)..close(), Colors.white);
    _path(c2, Path()..moveTo(62, 62)..quadraticBezierTo(66, 70, 62, 74)..quadraticBezierTo(59, 69, 59, 63)..close(), Colors.white);
  });
}

void _faceARabbit(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // long ears
    _oval(c2, const Rect.fromLTWH(30, 4, 14, 38), p.base);
    _oval(c2, const Rect.fromLTWH(56, 4, 14, 38), p.base);
    _oval(c2, const Rect.fromLTWH(34, 10, 7, 26), p.accent);
    _oval(c2, const Rect.fromLTWH(60, 10, 7, 26), p.accent);
    _circle(c2, const Offset(50, 56), 26, p.base);
    _animalEyes(c2, p);
    _animalSnout(c2, p);
    // buck teeth
    _rrect(c2, const Rect.fromLTWH(47, 66, 6, 7), 1.5, Colors.white);
  });
}

void _faceAPanda(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // round ears
    _circle(c2, const Offset(28, 28), 10, p.accent);
    _circle(c2, const Offset(72, 28), 10, p.accent);
    _circle(c2, const Offset(50, 52), 28, p.base);
    // eye patches (tilted ovals)
    _oval(c2, const Rect.fromLTWH(31, 38, 16, 12), p.accent);
    _oval(c2, const Rect.fromLTWH(53, 38, 16, 12), p.accent);
    _circle(c2, const Offset(39, 44), 3.5, Colors.white);
    _circle(c2, const Offset(61, 44), 3.5, Colors.white);
    // nose
    _circle(c2, const Offset(50, 58), 4, p.accent);
    _stroke(c2, Path()..moveTo(50, 61)..quadraticBezierTo(50, 66, 45, 67), p.accent, 2.5);
    _stroke(c2, Path()..moveTo(50, 61)..quadraticBezierTo(50, 66, 55, 67), p.accent, 2.5);
  });
}

void _faceABear(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // round ears
    _circle(c2, const Offset(28, 28), 11, p.base);
    _circle(c2, const Offset(72, 28), 11, p.base);
    _circle(c2, const Offset(28, 28), 6, p.accent);
    _circle(c2, const Offset(72, 28), 6, p.accent);
    _circle(c2, const Offset(50, 52), 28, p.base);
    _animalEyes(c2, p);
    _oval(c2, const Rect.fromLTWH(38, 54, 24, 16), p.accent);
    _circle(c2, const Offset(50, 58), 4, p.detail);
    _stroke(c2, Path()..moveTo(45, 66)..quadraticBezierTo(50, 70, 55, 66), p.detail, 2.5);
  });
}

void _faceAFox(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // pointy ears
    _path(c2, Path()..moveTo(24, 36)..lineTo(28, 10)..lineTo(46, 28)..close(), p.base);
    _path(c2, Path()..moveTo(76, 36)..lineTo(72, 10)..lineTo(54, 28)..close(), p.base);
    _path(c2, Path()..moveTo(29, 28)..lineTo(31, 17)..lineTo(40, 26)..close(), p.detail);
    _path(c2, Path()..moveTo(71, 28)..lineTo(69, 17)..lineTo(60, 26)..close(), p.detail);
    _circle(c2, const Offset(50, 52), 27, p.base);
    // white muzzle mask
    _path(c2, Path()..moveTo(23, 52)..quadraticBezierTo(28, 72, 50, 74)..quadraticBezierTo(72, 72, 77, 52)..quadraticBezierTo(64, 64, 50, 64)..quadraticBezierTo(36, 64, 23, 52)..close(), p.accent);
    _animalEyes(c2, p);
    _circle(c2, const Offset(50, 58), 4, p.detail);
    _stroke(c2, Path()..moveTo(45, 66)..quadraticBezierTo(50, 70, 55, 66), p.detail, 2.5);
  });
}

void _faceAKoala(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // big fuzzy ears
    _circle(c2, const Offset(22, 40), 15, p.base);
    _circle(c2, const Offset(78, 40), 15, p.base);
    _circle(c2, const Offset(22, 40), 8, p.accent);
    _circle(c2, const Offset(78, 40), 8, p.accent);
    _circle(c2, const Offset(50, 52), 26, p.base);
    // oval nose (koala signature)
    _oval(c2, const Rect.fromLTWH(44, 50, 12, 20), p.detail);
    _circle(c2, const Offset(39, 42), 3.5, p.detail);
    _circle(c2, const Offset(61, 42), 3.5, p.detail);
  });
}

void _faceACow(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // horns
    _path(c2, Path()..moveTo(30, 26)..quadraticBezierTo(22, 14, 14, 16)..quadraticBezierTo(22, 20, 28, 32)..close(), p.detail);
    _path(c2, Path()..moveTo(70, 26)..quadraticBezierTo(78, 14, 86, 16)..quadraticBezierTo(78, 20, 72, 32)..close(), p.detail);
    // ears
    _oval(c2, const Rect.fromLTWH(10, 34, 18, 10), p.accent);
    _oval(c2, const Rect.fromLTWH(72, 34, 18, 10), p.accent);
    _circle(c2, const Offset(50, 52), 28, p.base);
    // spot
    _path(c2, Path()..moveTo(58, 26)..quadraticBezierTo(74, 28, 72, 42)..quadraticBezierTo(64, 40, 58, 34)..close(), p.accent);
    _animalEyes(c2, p);
    // big pink muzzle
    _oval(c2, const Rect.fromLTWH(34, 52, 32, 22), p.detail);
    _circle(c2, const Offset(44, 58), 3, p.accent);
    _circle(c2, const Offset(56, 58), 3, p.accent);
    _stroke(c2, Path()..moveTo(45, 66)..quadraticBezierTo(50, 70, 55, 66), p.accent, 2.5);
  });
}

void _faceAPig(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // pointy ears
    _path(c2, Path()..moveTo(26, 34)..lineTo(30, 16)..lineTo(44, 28)..close(), p.base);
    _path(c2, Path()..moveTo(74, 34)..lineTo(70, 16)..lineTo(56, 28)..close(), p.base);
    _circle(c2, const Offset(50, 52), 28, p.base);
    _animalEyes(c2, p);
    // snout
    _oval(c2, const Rect.fromLTWH(36, 52, 28, 20), p.accent);
    _circle(c2, const Offset(44, 61), 3.2, p.detail);
    _circle(c2, const Offset(56, 61), 3.2, p.detail);
    _stroke(c2, Path()..moveTo(45, 74)..quadraticBezierTo(50, 78, 55, 74), p.detail, 2.5);
  });
}

void _faceAMonkey(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // round ears
    _circle(c2, const Offset(22, 48), 12, p.base);
    _circle(c2, const Offset(78, 48), 12, p.base);
    _circle(c2, const Offset(22, 48), 6, p.accent);
    _circle(c2, const Offset(78, 48), 6, p.accent);
    _circle(c2, const Offset(50, 52), 28, p.base);
    // face plate
    _path(c2, Path()..moveTo(32, 46)..quadraticBezierTo(32, 72, 50, 74)..quadraticBezierTo(68, 72, 68, 46)..quadraticBezierTo(58, 36, 50, 36)..quadraticBezierTo(42, 36, 32, 46)..close(), p.accent);
    _animalEyes(c2, p);
    // nostrils + smile
    _circle(c2, const Offset(46, 58), 1.8, p.detail);
    _circle(c2, const Offset(54, 58), 1.8, p.detail);
    _stroke(c2, Path()..moveTo(43, 64)..quadraticBezierTo(50, 70, 57, 64), p.detail, 2.5);
    // hair tuft
    _stroke(c2, Path()..moveTo(50, 22)..quadraticBezierTo(46, 14, 52, 10), p.detail, 3);
  });
}

void _faceAHen(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // head
    _circle(c2, const Offset(50, 52), 26, p.base);
    // comb
    _circle(c2, const Offset(42, 26), 7, p.accent);
    _circle(c2, const Offset(52, 22), 8, p.accent);
    _circle(c2, const Offset(62, 27), 6, p.accent);
    // beak
    _path(c2, Path()..moveTo(66, 52)..lineTo(82, 57)..lineTo(66, 62)..close(), p.detail);
    // wattle
    _path(c2, Path()..moveTo(62, 64)..quadraticBezierTo(66, 74, 58, 74)..quadraticBezierTo(54, 70, 58, 64)..close(), p.accent);
    // eye
    _circle(c2, const Offset(54, 46), 4, p.detail);
    _circle(c2, const Offset(55, 45), 1.4, Colors.white);
    // wing hint
    _stroke(c2, Path()..moveTo(30, 56)..quadraticBezierTo(36, 64, 44, 66), p.accent, 3);
  });
}

void _faceAUnicorn(Canvas c, MemoryFacePalette p) {
  _animalFace(c, p, features: (c2) {
    // ears
    _path(c2, Path()..moveTo(30, 32)..lineTo(34, 16)..lineTo(44, 28)..close(), p.base);
    _path(c2, Path()..moveTo(70, 32)..lineTo(66, 16)..lineTo(56, 28)..close(), p.base);
    _circle(c2, const Offset(50, 54), 26, p.base);
    // horn (striped)
    _path(c2, Path()..moveTo(50, 26)..lineTo(42, 34)..lineTo(50, 32)..close(), p.accent);
    _path(c2, Path()..moveTo(50, 18)..lineTo(60, 28)..lineTo(50, 26)..close(), p.detail);
    _stroke(c2, Path()..moveTo(46, 32)..lineTo(54, 28), p.base, 2);
    // mane
    for (final (x, y) in [(32, 40), (30, 52), (32, 62), (70, 40), (72, 52)]) {
      _circle(c2, Offset(x.toDouble(), y.toDouble()), 7, p.accent);
    }
    // flower
    for (var i = 0; i < 5; i++) {
      final a = i * 2 * math.pi / 5;
      _circle(c2, Offset(34 + 5 * math.cos(a), 68 + 5 * math.sin(a)), 3.2, p.accent);
    }
    _circle(c2, const Offset(34, 68), 2.6, const Color(0xFFFFC940));
    // eyes + smile
    _circle(c2, const Offset(40, 50), 3.5, p.detail);
    _circle(c2, const Offset(60, 50), 3.5, p.detail);
    _stroke(c2, Path()..moveTo(45, 62)..quadraticBezierTo(50, 66, 55, 62), p.detail, 2.5);
  });
}

void _faceATurtle(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // flippers
  _oval(c, const Rect.fromLTWH(8, 52, 18, 12), p.accent);
  _oval(c, const Rect.fromLTWH(74, 52, 18, 12), p.accent);
  // head
  _circle(c, const Offset(50, 24), 13, p.accent);
  _circle(c, const Offset(45, 22), 2.6, p.detail);
  _circle(c, const Offset(55, 22), 2.6, p.detail);
  _stroke(c, Path()..moveTo(46, 29)..quadraticBezierTo(50, 32, 54, 29), p.detail, 2);
  // shell
  _circle(c, const Offset(50, 58), 30, p.base);
  // shell pattern
  _circle(c, const Offset(50, 58), 21, p.accent);
  for (var i = 0; i < 6; i++) {
    final a = i * math.pi / 3 + math.pi / 6;
    _circle(c, Offset(50 + 14 * math.cos(a), 58 + 14 * math.sin(a)), 6, p.base);
  }
  _circle(c, const Offset(50, 58), 6, p.detail);
}

void _faceAFrog(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // eyes on top
  _circle(c, const Offset(34, 26), 12, p.base);
  _circle(c, const Offset(66, 26), 12, p.base);
  _circle(c, const Offset(34, 26), 6, Colors.white);
  _circle(c, const Offset(66, 26), 6, Colors.white);
  _circle(c, const Offset(34, 26), 3, p.detail);
  _circle(c, const Offset(66, 26), 3, p.detail);
  // head
  _oval(c, const Rect.fromLTWH(18, 30, 64, 48), p.base);
  // cheeks
  _circle(c, const Offset(32, 56), 6, p.accent.withValues(alpha: 0.6));
  _circle(c, const Offset(68, 56), 6, p.accent.withValues(alpha: 0.6));
  // wide smile
  _stroke(c, Path()..moveTo(34, 54)..quadraticBezierTo(50, 68, 66, 54), p.detail, 3);
  // nostrils
  _circle(c, const Offset(46, 44), 2, p.detail);
  _circle(c, const Offset(54, 44), 2, p.detail);
}

void _faceAOwl(Canvas c, MemoryFacePalette p) {
  _groundShadow(c);
  // ear tufts
  _path(c, Path()..moveTo(28, 30)..lineTo(30, 14)..lineTo(42, 26)..close(), p.base);
  _path(c, Path()..moveTo(72, 30)..lineTo(70, 14)..lineTo(58, 26)..close(), p.base);
  // body
  _oval(c, const Rect.fromLTWH(20, 24, 60, 62), p.base);
  // belly
  _oval(c, const Rect.fromLTWH(34, 50, 32, 34), p.accent);
  // big eyes
  _circle(c, const Offset(38, 42), 11, p.accent);
  _circle(c, const Offset(62, 42), 11, p.accent);
  _circle(c, const Offset(38, 42), 8, Colors.white);
  _circle(c, const Offset(62, 42), 8, Colors.white);
  _circle(c, const Offset(38, 42), 4, p.detail);
  _circle(c, const Offset(62, 42), 4, p.detail);
  // beak
  _path(c, Path()..moveTo(50, 48)..lineTo(56, 56)..lineTo(50, 62)..lineTo(44, 56)..close(), p.detail);
  // wings
  _stroke(c, Path()..moveTo(24, 46)..quadraticBezierTo(20, 62, 30, 72), p.detail, 4);
  _stroke(c, Path()..moveTo(76, 46)..quadraticBezierTo(80, 62, 70, 72), p.detail, 4);
}
