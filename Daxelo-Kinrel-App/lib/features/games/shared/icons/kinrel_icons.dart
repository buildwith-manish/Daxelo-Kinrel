// lib/features/games/shared/icons/kinrel_icons.dart
//
// Kinrel custom icon system — the single visual language for every game
// surface (Family Arena hub, Game Lobby, Results, Challenges, Milestones,
// Achievements, Family Moments).
//
// WHY: the app used emoji glyphs (🔥 🏆 🎮 🎯 ❤️ 🎉 …) for stat chips,
// podiums, empty states and banners. Emojis render differently on every
// platform, clash with the premium dark-glass design language, and break
// brand consistency. This file replaces ALL of them with hand-drawn
// vector icons painted on a 24×24 grid with rounded caps/joins — the
// same geometry style as the Kinrel brand marks.
//
// Usage:
//   const KinrelIcon(KinrelIconData.flame, size: 20, color: …)
//
// Server data (activity feed icons, badge icons) still arrives as emoji
// strings — map them at render time with [kinrelIconFromEmoji] so the UI
// never shows a raw emoji glyph again.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';

/// Every icon in the Kinrel games icon system.
enum KinrelIconData {
  /// 🔥 streaks, intensity, most-taps
  flame,

  /// 🏆 cups, wins, season banner
  trophy,

  /// 🎮 games played, game fallbacks
  controller,

  /// 🏅 badges, ranks (pair with a rank number in a Stack)
  medal,

  /// ✨ family moments, magic reveals
  sparkle,

  /// 🎯 challenges, goals
  flag,

  /// leaderboard top-3 podium
  podium,

  /// 👑 host / reigning champion
  crown,

  /// 💚❤️ sportsmanship, love, care
  heart,

  /// 🤝 draws and handshakes
  handshake,

  /// accuracy / precision
  target,

  /// 🧠 memory, smarts
  brain,

  /// ⚡ fastest, speed
  zap,

  /// 📈 progress, growth charts
  chart,

  /// 🌱 early growth tiers
  seedling,

  /// 🔌 offline / connection errors
  plugOff,

  /// ✅ completed / all done
  checkCircle,

  /// 📜 match history
  scroll,

  /// 👨‍👩‍👧‍👦 family, members
  users,

  /// 🎉 celebrations
  party,

  /// 🧭 journey / milestones
  compass,

  /// 🗺️ exploration
  map,

  /// ⭐ top performer / featured
  star,

  /// ⏱ fastest-win timing
  clock,

  /// 😂 laughter (chat quick chip)
  laugh,

  /// 🏁 finish line / season end
  finish,
}

/// Maps emoji strings that arrive from server data (activity feed icons,
/// badge icons, superlative icons) to Kinrel custom icons. Returns null
/// for unrecognized strings so callers can pick a sensible fallback.
KinrelIconData? kinrelIconFromEmoji(String? emoji) {
  if (emoji == null) return null;
  switch (emoji.trim()) {
    case '🔥':
      return KinrelIconData.flame;
    case '🏆':
    case '🥇':
      return KinrelIconData.trophy;
    case '🎮':
      return KinrelIconData.controller;
    case '🏅':
    case '🥈':
    case '🥉':
      return KinrelIconData.medal;
    case '✨':
    case '🌟':
      return KinrelIconData.sparkle;
    case '🎯':
      return KinrelIconData.target;
    case '👑':
      return KinrelIconData.crown;
    case '💚':
    case '💛':
    case '❤️':
      return KinrelIconData.heart;
    case '🤝':
      return KinrelIconData.handshake;
    case '👏':
      return KinrelIconData.party;
    case '🎉':
      return KinrelIconData.party;
    case '🧠':
      return KinrelIconData.brain;
    case '⚡':
      return KinrelIconData.zap;
    case '📈':
      return KinrelIconData.chart;
    case '🌱':
      return KinrelIconData.seedling;
    case '🔌':
      return KinrelIconData.plugOff;
    case '✅':
      return KinrelIconData.checkCircle;
    case '📜':
      return KinrelIconData.scroll;
    case '👨‍👩‍👧‍👦':
    case '👥':
      return KinrelIconData.users;
    case '🏁':
      return KinrelIconData.finish;
    case '🧭':
      return KinrelIconData.compass;
    case '🗺️':
    case '🗺':
      return KinrelIconData.map;
    case '⭐':
      return KinrelIconData.star;
    case '⏱':
      return KinrelIconData.clock;
    case '😂':
      return KinrelIconData.laugh;
    case '♟️':
    case '♟':
      // Board Classics category — "timeless favourites".
      return KinrelIconData.scroll;
    case '🇮🇳':
      // Indian Classics category.
      return KinrelIconData.flag;
    default:
      return null;
  }
}

/// A single Kinrel custom icon, painted as a vector on a 24×24 grid.
class KinrelIcon extends StatelessWidget {
  const KinrelIcon(
    this.data, {
    super.key,
    this.size = 24,
    this.color,
  });

  final KinrelIconData data;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? KinrelColors.orange;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size.square(size),
        painter: _KinrelIconPainter(data, c),
      ),
    );
  }
}

class _KinrelIconPainter extends CustomPainter {
  _KinrelIconPainter(this.data, this.color);

  final KinrelIconData data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    if (s <= 0) return;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    void path(Iterable<String> ops, {Paint? p}) {
      canvas.drawPath(_parse(ops, s), p ?? stroke);
    }

    void line(double x1, double y1, double x2, double y2, {Paint? p}) {
      canvas.drawLine(Offset(x1 * s, y1 * s), Offset(x2 * s, y2 * s), p ?? stroke);
    }

    void circle(double cx, double cy, double r, Paint p) {
      canvas.drawCircle(Offset(cx * s, cy * s), r * s, p);
    }

    switch (data) {
      case KinrelIconData.flame:
        // Outer flame body (filled) + inner cutout for depth.
        path([
          'M12 21.4',
          'C8.2 21.4 5.4 18.7 5.4 15.2',
          'C5.4 12.4 7.1 10.6 8.5 8.9',
          'C9.3 7.9 10 6.9 10.4 5.7',
          'C10.6 5 11.2 4.6 11.9 4.8',
          'C12.6 5 13 5.6 12.9 6.3',
          'C12.7 7.5 12.9 8.5 13.5 9.2',
          'C13.9 9.7 14.5 10 15.2 10.1',
          'C16.6 10.3 18.6 12 18.6 15.2',
          'C18.6 18.7 15.8 21.4 12 21.4',
          'Z',
        ], p: fill);
        // Inner flame highlight.
        path([
          'M12 18.6',
          'C10.6 18.6 9.6 17.6 9.6 16.3',
          'C9.6 15.1 10.4 14.3 11.2 13.4',
          'C11.5 13.1 11.8 12.7 12 12.3',
          'C12.2 12.7 12.5 13.1 12.8 13.4',
          'C13.6 14.3 14.4 15.1 14.4 16.3',
          'C14.4 17.6 13.4 18.6 12 18.6',
          'Z',
        ], p: Paint()..color = color.withValues(alpha: 0.45)..style = PaintingStyle.fill);
        break;

      case KinrelIconData.trophy:
        // Cup.
        path([
          'M8 3.5 h8 v5 a4 4 0 0 1 -8 0 Z',
        ], p: fill);
        // Handles.
        path([
          'M8 5 H5.5 a3 3 0 0 0 3 3',
        ]);
        path([
          'M16 5 h2.5 a3 3 0 0 1 -3 3',
        ]);
        // Stem + base.
        line(12, 12.5, 12, 16.5);
        path(['M8.5 20 h7', 'M9.5 20 v-1.8 h5 v1.8']);
        // Star on the cup.
        _star(canvas, Offset(12 * s, 6.6 * s), 1.5 * s,
            Paint()..color = Colors.white.withValues(alpha: 0.85));
        break;

      case KinrelIconData.controller:
        path([
          'M7 8.2 h10 a4.6 4.6 0 0 1 4.5 5.6 l-.7 3.2',
          'a2.5 2.5 0 0 1 -4.4 1.1 L14.6 16.4 H9.4',
          'L7.6 18.1 a2.5 2.5 0 0 1 -4.4 -1.1 l-.7 -3.2',
          'A4.6 4.6 0 0 1 7 8.2 Z',
        ]);
        // D-pad.
        line(8.6, 11.2, 8.6, 13.6);
        line(7.4, 12.4, 9.8, 12.4);
        // Buttons.
        circle(15.2, 11.6, 0.95, fill);
        circle(17.4, 13.4, 0.95, fill);
        break;

      case KinrelIconData.medal:
        // Ribbons.
        path(['M8.6 2.6 l2.5 5.6', 'M15.4 2.6 l-1.7 3.8']);
        // Medal disc.
        circle(12, 14.6, 5.2, Paint()..color = color.withValues(alpha: 0.18)..style = PaintingStyle.fill);
        circle(12, 14.6, 5.2, stroke);
        // Star in the middle.
        _star(canvas, Offset(12 * s, 14.6 * s), 2.3 * s, fill);
        break;

      case KinrelIconData.sparkle:
        path([
          'M10.2 3.2 l1.7 4.9 4.9 1.7 -4.9 1.7 -1.7 4.9 -1.7 -4.9 -4.9 -1.7 4.9 -1.7 Z',
        ], p: fill);
        path([
          'M17.8 14.2 l.9 2.4 2.4 .9 -2.4 .9 -.9 2.4 -.9 -2.4 -2.4 -.9 2.4 -.9 Z',
        ], p: fill);
        break;

      case KinrelIconData.flag:
        // Pole.
        line(6.2, 21, 6.2, 3.8);
        // Pennant (filled).
        path([
          'M6.2 4.6 h11.4',
          'l-2.9 3.4 2.9 3.4',
          'H6.2 Z',
        ], p: fill);
        break;

      case KinrelIconData.podium:
        // 2nd / 1st / 3rd columns.
        path([
          'M4 21 v-8 a1.2 1.2 0 0 1 1.2 -1.2 h2.6 A1.2 1.2 0 0 1 9 13 v8 Z',
        ], p: Paint()
            ..color = color.withValues(alpha: 0.55)
            ..style = PaintingStyle.fill);
        path([
          'M9.9 21 V6.8 a1.2 1.2 0 0 1 1.2 -1.2 h1.8 a1.2 1.2 0 0 1 1.2 1.2 V21 Z',
        ], p: fill);
        path([
          'M14.8 21 v-5.4 a1.2 1.2 0 0 1 1.2 -1.2 h2.6 a1.2 1.2 0 0 1 1.2 1.2 V21 Z',
        ], p: Paint()
            ..color = color.withValues(alpha: 0.35)
            ..style = PaintingStyle.fill);
        line(3.4, 21, 20.6, 21);
        break;

      case KinrelIconData.crown:
        path([
          'M4.4 17.8 h15.2',
        ]);
        path([
          'M4.4 17.8 L3.2 8.6 l5 3.4 L12 5.2 l3.8 6.8 5 -3.4 -1.2 9.2 Z',
        ], p: Paint()..color = color.withValues(alpha: 0.25)..style = PaintingStyle.fill);
        path([
          'M4.4 17.8 L3.2 8.6 l5 3.4 L12 5.2 l3.8 6.8 5 -3.4 -1.2 9.2 Z',
        ]);
        circle(12, 14, 1.1, fill);
        break;

      case KinrelIconData.heart:
        path([
          'M12 20.4',
          'C6.8 16.6 3.8 13.5 3.8 9.9',
          'C3.8 7.4 5.8 5.4 8.2 5.4',
          'C9.7 5.4 11.1 6.2 12 7.4',
          'C12.9 6.2 14.3 5.4 15.8 5.4',
          'C18.2 5.4 20.2 7.4 20.2 9.9',
          'C20.2 13.5 17.2 16.6 12 20.4 Z',
        ], p: fill);
        break;

      case KinrelIconData.handshake:
        path([
          'M2.8 12.4 L7.2 8 l3.4 3.2 a1.7 1.7 0 0 0 2.4 0',
          'L16.8 7.6 l4.4 4.8 -3.6 3.6 -2 -2',
        ]);
        path([
          'M9.4 16.8 l2 2 1.6 -1.6',
        ]);
        break;

      case KinrelIconData.target:
        circle(12, 12, 8.4, stroke);
        circle(12, 12, 4.9, stroke);
        circle(12, 12, 1.6, fill);
        break;

      case KinrelIconData.brain:
        // Two mirrored lobes + central divide, pure cubic curves.
        path([
          'M11.5 4.4',
          'C9.1 4.4 7.2 6.2 7.2 8.5',
          'C5.4 9 4 10.6 4 12.5',
          'C4 13.9 4.8 15.2 6 15.9',
          'C5.8 16.4 5.7 16.9 5.7 17.5',
          'C5.7 19.6 7.4 21.3 9.5 21.3',
          'C10.3 21.3 11 21 11.5 20.6',
        ]);
        path([
          'M11.5 4.4',
          'C13.9 4.4 15.8 6.2 15.8 8.5',
          'C17.6 9 19 10.6 19 12.5',
          'C19 13.9 18.2 15.2 17 15.9',
          'C17.2 16.4 17.3 16.9 17.3 17.5',
          'C17.3 19.6 15.6 21.3 13.5 21.3',
          'C12.7 21.3 12 21 11.5 20.6',
        ]);
        // Central divide.
        path(['M11.5 4.4 V20.6']);
        // Cortical squiggles.
        path(['M8.5 9.7 q1.2 -.8 2.4 0']);
        path(['M13.1 14.7 q1.2 .8 2.4 0']);
        break;

      case KinrelIconData.zap:
        path([
          'M13.2 2.4 L4.6 13.6 h6.2 L10.8 21.6 19.4 10.4 h-6.2 Z',
        ], p: fill);
        break;

      case KinrelIconData.chart:
        // Axis (L-shape).
        line(4, 3.8, 4, 20);
        line(4, 20, 20, 20);
        path(['M7 15.2 l3.4 -4 3 2.6 4.6 -6']);
        path(['M14.8 7.8 h3.2 v3.2']);
        break;

      case KinrelIconData.seedling:
        line(12, 21, 12, 12.6);
        path([
          'M12 13.2 C12 9.6 9.2 7.4 5.6 7.4 c0 3.8 2.6 5.8 6.4 5.8 Z',
        ], p: fill);
        path([
          'M12 10.9 C12 8.1 14.3 6.1 17.6 6.1 c0 3.2 -2.3 5.1 -5.6 5.1 Z',
        ], p: fill);
        break;

      case KinrelIconData.plugOff:
        // Prongs.
        line(9, 3, 9, 6.4);
        line(15, 3, 15, 6.4);
        // Plug body + cord.
        path([
          'M7 6.4 h10 v3.4 a5 5 0 0 1 -5 5 5 5 0 0 1 -5 -5 Z',
        ]);
        path(['M12 14.8 v2.4 a2.6 2.6 0 0 0 2.6 2.6 h1.2']);
        // Disconnected slash.
        line(3.6, 3.6, 20.4, 20.4, p: Paint()
          ..color = color
          ..strokeWidth = 2.0 * s
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke);
        break;

      case KinrelIconData.checkCircle:
        circle(12, 12, 8.6, stroke);
        path(['M8.3 12.4 l2.5 2.5 4.9 -5.4']);
        break;

      case KinrelIconData.scroll:
        path([
          'M7 3.6 h10 a2 2 0 0 1 2 2 v12.8 a2 2 0 0 1 -2 2 H7 a2 2 0 0 1 -2 -2 V5.6 a2 2 0 0 1 2 -2 Z',
        ]);
        line(9, 8.4, 15, 8.4);
        line(9, 12, 15, 12);
        line(9, 15.6, 13, 15.6);
        break;

      case KinrelIconData.users:
        circle(9.2, 8.2, 3.2, fill);
        path([
          'M3.4 19.6 a5.8 5.8 0 0 1 11.6 0',
        ]);
        circle(16.8, 9, 2.5, fill);
        path([
          'M15.6 13.9 a5.2 5.2 0 0 1 5 3.4',
        ]);
        break;

      case KinrelIconData.party:
        // Cone (filled, opening to the top-right).
        path([
          'M3.8 20.6 L8.9 4.6 L12.9 16 Z',
        ], p: fill);
        // Streamers bursting out of the cone mouth.
        path(['M14.4 5.6 l1.9 -1.9']);
        path(['M17.5 9.3 l2.4 -.9']);
        path(['M16 13.1 l2.5 1.5']);
        // Confetti dots.
        circle(14.4, 10, 0.85, fill);
        circle(19.8, 5.4, 0.85, fill);
        circle(20, 16.4, 0.85, fill);
        break;

      case KinrelIconData.compass:
        circle(12, 12, 8.8, stroke);
        path([
          'M15.2 8.8 l-1.8 4.6 -4.6 1.8 1.8 -4.6 Z',
        ], p: fill);
        break;

      case KinrelIconData.map:
        path([
          'M9 4 3.8 6 v14 L9 18 l6 2 5.2 -2 V4 L15 6 9 4 Z',
        ]);
        line(9, 4, 9, 18);
        line(15, 6, 15, 20);
        break;

      case KinrelIconData.star:
        _star(canvas, Offset(12 * s, 12 * s), 8.6 * s, fill);
        break;

      case KinrelIconData.clock:
        circle(12, 12, 8.6, stroke);
        path(['M12 7.4 V12 l3.2 2.2']);
        break;

      case KinrelIconData.laugh:
        circle(12, 12, 8.8, stroke);
        // Happy closed eyes.
        path(['M8.2 10.4 q1.1 -1.4 2.2 0']);
        path(['M13.6 10.4 q1.1 -1.4 2.2 0']);
        // Big smile.
        path(['M7.8 13.6 q4.2 4 8.4 0'], p: Paint()
            ..color = color
            ..strokeWidth = 2.2 * s
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke);
        break;

      case KinrelIconData.finish:
        // Checkered finish flag.
        line(5.8, 21, 5.8, 3.8);
        path([
          'M5.8 4.4 h12.6 v8.4 H5.8 Z',
        ]);
        // Checker squares.
        _checker(canvas, s, 5.8, 4.4);
        _checker(canvas, s, 11.0, 4.4);
        _checker(canvas, s, 8.4, 8.6);
        _checker(canvas, s, 13.6, 8.6);
        break;
    }
  }

  void _checker(Canvas canvas, double s, double x, double y) {
    final rect = Rect.fromLTWH(x * s, y * s, 2.6 * s, 2.1 * s);
    canvas.drawRect(rect, Paint()..color = color);
  }

  /// Parses a compact SVG-like command stream.
  ///
  /// Supported: M/L/H/V/C/Q/A/Z in absolute and relative forms, plus
  /// the SVG "implicit repetition" rule — a command with more numbers
  /// than it consumes repeats itself for each argument group
  /// (e.g. 'l1 2 3 4' is two line segments). Each element of [ops]
  /// may hold one command or a whole run.
  static Path _parse(Iterable<String> ops, double s) {
    final p = Path();
    double cx = 0, cy = 0, startX = 0, startY = 0;
    var hasMoved = false;

    void apply(String cmd, List<double> a) {
      switch (cmd) {
        case 'M':
        case 'm':
          if (cmd == 'm' && hasMoved) {
            cx += a[0];
            cy += a[1];
          } else {
            cx = a[0];
            cy = a[1];
          }
          hasMoved = true;
          startX = cx;
          startY = cy;
          p.moveTo(cx * s, cy * s);
          break;
        case 'L':
          cx = a[0];
          cy = a[1];
          p.lineTo(cx * s, cy * s);
          break;
        case 'l':
          cx += a[0];
          cy += a[1];
          p.lineTo(cx * s, cy * s);
          break;
        case 'H':
          cx = a[0];
          p.lineTo(cx * s, cy * s);
          break;
        case 'h':
          cx += a[0];
          p.lineTo(cx * s, cy * s);
          break;
        case 'V':
          cy = a[0];
          p.lineTo(cx * s, cy * s);
          break;
        case 'v':
          cy += a[0];
          p.lineTo(cx * s, cy * s);
          break;
        case 'C':
          p.cubicTo(a[0] * s, a[1] * s, a[2] * s, a[3] * s, a[4] * s,
              a[5] * s);
          cx = a[4];
          cy = a[5];
          break;
        case 'c':
          p.relativeCubicTo(a[0] * s, a[1] * s, a[2] * s, a[3] * s,
              a[4] * s, a[5] * s);
          cx += a[4];
          cy += a[5];
          break;
        case 'Q':
          p.quadraticBezierTo(a[0] * s, a[1] * s, a[2] * s, a[3] * s);
          cx = a[2];
          cy = a[3];
          break;
        case 'q':
          p.relativeQuadraticBezierTo(a[0] * s, a[1] * s, a[2] * s,
              a[3] * s);
          cx += a[2];
          cy += a[3];
          break;
        case 'A':
          _ellipticalArc(p, s, cx, cy, a[0], a[1], a[2], a[3] == 1,
              a[4] == 1, a[5], a[6]);
          cx = a[5];
          cy = a[6];
          break;
        case 'a':
          final x2 = cx + a[5];
          final y2 = cy + a[6];
          _ellipticalArc(p, s, cx, cy, a[0], a[1], a[2], a[3] == 1,
              a[4] == 1, x2, y2);
          cx = x2;
          cy = y2;
          break;
      }
    }

    const argCounts = <String, int>{
      'M': 2, 'L': 2, 'l': 2, 'H': 1, 'h': 1, 'V': 1, 'v': 1,
      'C': 6, 'c': 6, 'Q': 4, 'q': 4, 'A': 7, 'a': 7,
    };
    final cmdRe =
        RegExp(r'([MLHVCSQTAZmlhvcsqtaz])((?:[^MLHVCSQTAZmlhvcsqtaz])*)');

    for (final raw in ops) {
      for (final m in cmdRe.allMatches(raw.trim())) {
        final cmd = m.group(1)!;
        if (cmd == 'Z' || cmd == 'z') {
          p.close();
          cx = startX;
          cy = startY;
          continue;
        }
        final argStr = m.group(2)?.trim() ?? '';
        if (argStr.isEmpty) continue;
        final args = argStr
            .split(RegExp(r'[\s,]+'))
            .map(double.parse)
            .toList();
        final want = argCounts[cmd]!;
        // After a moveto, extra argument pairs are implicit line
        // segments (absolute M -> L, relative m -> l).
        final implicit = cmd == 'M'
            ? 'L'
            : cmd == 'm'
                ? 'l'
                : cmd;
        var i = 0;
        while (i + want <= args.length) {
          apply(i == 0 ? cmd : implicit, args.sublist(i, i + want));
          i += want;
        }
      }
    }
    return p;
  }

  /// Converts one SVG elliptical arc (x-axis rotation assumed 0 — every
  /// hand-authored icon path uses unrotated arcs) into a sequence of
  /// cubic Bézier segments (≤ 90° each), using the standard
  /// center-parameterization algorithm (SVG spec F.6.5).
  static void _ellipticalArc(Path p, double s, double x0, double y0,
      double rx, double ry, double xRot, bool largeArc, bool sweep,
      double x1, double y1) {
    if (rx == 0 || ry == 0 || (x0 == x1 && y0 == y1)) {
      p.lineTo(x1 * s, y1 * s);
      return;
    }
    rx = rx.abs();
    ry = ry.abs();

    // Step 1: compute the center in the scaled-ellipse frame.
    final dx2 = (x0 - x1) / 2;
    final dy2 = (y0 - y1) / 2;
    final lambda = (dx2 * dx2) / (rx * rx) + (dy2 * dy2) / (ry * ry);
    if (lambda > 1) {
      final scale = math.sqrt(lambda);
      rx *= scale;
      ry *= scale;
    }
    final sign = largeArc != sweep ? 1 : -1;
    final num = rx * rx * ry * ry - rx * rx * dy2 * dy2 - ry * ry * dx2 * dx2;
    final den = rx * rx * dy2 * dy2 + ry * ry * dx2 * dx2;
    final co = sign * math.sqrt(num < 0 ? 0 : num / den);
    final cxp = co * rx * dy2 / ry;
    final cyp = -co * ry * dx2 / rx;
    final cx = cxp + (x0 + x1) / 2;
    final cy = cyp + (y0 + y1) / 2;

    // Step 2: start/end angles on the ellipse.
    double angle(double ux, double uy, double vx, double vy) {
      final dot = ux * vx + uy * vy;
      final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
      var a = math.acos((dot / len).clamp(-1.0, 1.0));
      if (ux * vy - uy * vx < 0) a = -a;
      return a;
    }

    final theta1 =
        angle(1, 0, (dx2 - cxp) / rx, (dy2 - cyp) / ry);
    var dTheta = angle((dx2 - cxp) / rx, (dy2 - cyp) / ry,
        (-dx2 - cxp) / rx, (-dy2 - cyp) / ry);
    if (!sweep && dTheta > 0) dTheta -= 2 * math.pi;
    if (sweep && dTheta < 0) dTheta += 2 * math.pi;

    // Step 3: emit ≤ 90° cubic segments.
    final segments = (dTheta.abs() / (math.pi / 2)).ceil();
    final delta = dTheta / segments;
    const k = 4 / 3;
    final tanQuarter = math.tan(delta / 4);
    var th = theta1;
    for (var i = 0; i < segments; i++) {
      final th2 = th + delta;
      final c1 = math.cos(th), s1 = math.sin(th);
      final c2 = math.cos(th2), s2 = math.sin(th2);
      // Control points in ellipse space (rotation 0).
      final cp1x = cx + rx * (c1 - k * tanQuarter * s1);
      final cp1y = cy + ry * (s1 + k * tanQuarter * c1);
      final cp2x = cx + rx * (c2 + k * tanQuarter * s2);
      final cp2y = cy + ry * (s2 - k * tanQuarter * c2);
      final ex = cx + rx * c2;
      final ey = cy + ry * s2;
      p.cubicTo(cp1x * s, cp1y * s, cp2x * s, cp2y * s, ex * s, ey * s);
      th = th2;
    }
  }

  static void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final radius = i.isEven ? r : r * 0.45;
      final point = Offset(
        c.dx + radius * math.cos(angle),
        c.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _KinrelIconPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.color != color;
}
