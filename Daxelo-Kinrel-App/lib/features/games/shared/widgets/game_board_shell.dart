// lib/features/games/shared/widgets/game_board_shell.dart
//
// DAXELO KINREL — Premium board presentation kit for all games.
//
// GridView boards (Tic-Tac-Toe, SOS, Chess, Checkers, Bingo, Ludo) used
// flat `Container(color: darkCard)` surfaces. This kit lifts every board
// to the same "casino-grade table" finish:
//
//   GameBoardShell      — layered board frame: accent rim, beveled edge,
//                          inner top-light, soft inner shadow, optional
//                          felt/slate texture, accent under-glow.
//   GamePiece3D         — circular playing piece with radial gradient,
//                          specular highlight, rim and drop shadow.
//   boardSquareShade    — alternating square gradient for checkered
//                          boards (chess/checkers) so squares read as
//                          lit from the top-left.
//
// Everything is plain Flutter — no packages, device-tier aware.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/utils/device_tier.dart';

/// Surface material of the board playing area.
enum BoardSurface {
  /// Deep felt-green/teal table (casino). Good for bingo, SOS.
  felt,

  /// Cool dark slate with a faint diagonal grain. Good for abstract
  /// grids — tic-tac-toe, SOS.
  slate,

  /// Warm dark wood (classic board games). Good for chess, checkers,
  /// ludo, carrom-adjacent boards.
  wood,
}

/// The board frame used by every GridView game board.
///
/// Wrap the existing GridView in this shell and the board instantly
/// gets a beveled rim, textured surface and accent glow:
///
///   GameBoardShell(
///     accent: KinrelColors.orange,
///     surface: BoardSurface.slate,
///     child: GridView.builder(...),
///   )
class GameBoardShell extends StatelessWidget {
  const GameBoardShell({
    super.key,
    required this.child,
    this.accent = KinrelColors.orange,
    this.surface = BoardSurface.slate,
    this.radius = 26,
    this.padding = 10,
    this.glow = true,
    this.texture = true,
  });

  final Widget child;

  /// The game's accent color — drives the rim and under-glow.
  final Color accent;

  /// Table material of the playing surface.
  final BoardSurface surface;

  /// Corner radius of the outer frame.
  final double radius;

  /// Padding between the frame and the playing surface.
  final double padding;

  /// Whether to cast an accent under-glow beneath the board.
  final bool glow;

  /// Whether to paint the micro-texture (disabled on low-tier devices).
  final bool texture;

  @override
  Widget build(BuildContext context) {
    final tier = DeviceTierCache.instance.tier;
    final useTexture = texture && tier != DeviceTier.low;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.22),
                  blurRadius: 34,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          foregroundPainter: _BoardBevelPainter(
            accent: accent,
            radius: radius,
            texture: useTexture,
            surface: surface,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: _surfaceGradient(),
              borderRadius: BorderRadius.circular(radius),
            ),
            padding: EdgeInsets.all(padding),
            child: CustomPaint(
              foregroundPainter: _InnerShadowPainter(radius: radius - padding),
              child: ClipRRect(
                borderRadius: BorderRadius.circular((radius - padding).clamp(4, 20)),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  LinearGradient _surfaceGradient() {
    switch (surface) {
      case BoardSurface.felt:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14342E), Color(0xFF0E2622)],
        );
      case BoardSurface.wood:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF241A12), Color(0xFF171008)],
        );
      case BoardSurface.slate:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF20233A), Color(0xFF14162A)],
        );
    }
  }
}

/// Paints the beveled frame: accent rim, top-edge light, bottom shade
/// and the micro-texture of the chosen material.
class _BoardBevelPainter extends CustomPainter {
  _BoardBevelPainter({
    required this.accent,
    required this.radius,
    required this.texture,
    required this.surface,
  });

  final Color accent;
  final double radius;
  final bool texture;
  final BoardSurface surface;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    // Accent rim — a hairline inner stroke that reads as a metal band.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.85),
          accent.withValues(alpha: 0.35),
          accent.withValues(alpha: 0.65),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rrect.deflate(1.2), rim);

    // Top bevel light — soft white streak along the top edge.
    final bevel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rrect.deflate(3.5), bevel);

    if (texture) {
      _paintTexture(canvas, size, rrect);
    }
  }

  void _paintTexture(Canvas canvas, Size size, RRect clip) {
    final rng = math.Random(7); // Fixed seed — stable across repaints.
    final dots = Paint()..color = Colors.white.withValues(alpha: 0.022);
    final grain = Paint()..color = Colors.black.withValues(alpha: 0.05);

    canvas.save();
    canvas.clipRRect(clip);

    switch (surface) {
      case BoardSurface.felt:
        // Felt = dense fine speckle.
        for (var i = 0; i < size.width * size.height / 90; i++) {
          canvas.drawCircle(
            Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
            0.7,
            dots,
          );
        }
        break;
      case BoardSurface.slate:
        // Slate = sparse speckle + faint diagonal grain.
        for (var i = 0; i < size.width * size.height / 240; i++) {
          canvas.drawCircle(
            Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
            0.9,
            dots,
          );
        }
        for (var y = -size.height; y < size.height; y += 9) {
          canvas.drawLine(
            Offset(0, y),
            Offset(size.width, y + size.height),
            grain..strokeWidth = 1,
          );
        }
        break;
      case BoardSurface.wood:
        // Wood = horizontal grain streaks of varying weight.
        for (var y = 0; y < size.height; y += 7 + rng.nextInt(5)) {
          canvas.drawLine(
            Offset(0, y.toDouble()),
            Offset(size.width, y.toDouble()),
            grain..strokeWidth = 0.8 + rng.nextDouble() * 1.4,
          );
        }
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardBevelPainter oldDelegate) =>
      oldDelegate.accent != accent ||
      oldDelegate.surface != surface ||
      oldDelegate.texture != texture;
}

/// Soft inner shadow pressed into the playing surface — makes the grid
/// area read as inset into the frame.
class _InnerShadowPainter extends CustomPainter {
  _InnerShadowPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    canvas.clipRRect(rrect);

    // Shadow: stroke inside the top edge.
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawRRect(rrect.deflate(4), shadow);

    // Top sheen inside the inset.
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          Colors.white.withValues(alpha: 0.06),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rrect, sheen);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InnerShadowPainter oldDelegate) => false;
}

/// A circular 3D playing piece — radial-lit disc with specular
/// highlight, dark rim and a grounded drop shadow.
///
/// Used for checkers pieces, ludo tokens and any game that wants its
/// counters to feel like physical chips.
class GamePiece3D extends StatelessWidget {
  const GamePiece3D({
    super.key,
    required this.color,
    this.size = 34,
    this.child,
    this.glow = false,
    this.ring,
  });

  /// Base chip color.
  final Color color;

  /// Diameter of the piece.
  final double size;

  /// Optional content rendered on top of the chip (glyph, crown, …).
  final Widget? child;

  /// Whether to cast a colored glow around the piece (win/king/capture).
  final bool glow;

  /// Optional contrasting ring around the chip face.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(color, Colors.white, 0.55)!;
    final dark = Color.lerp(color, Colors.black, 0.45)!;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (glow)
            BoxShadow(
              color: color.withValues(alpha: 0.65),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 6,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _ChipFacePainter(light: light, base: color, dark: dark, ring: ring),
        child: Center(child: child),
      ),
    );
  }
}

/// The lit face of a [GamePiece3D]: radial gradient, specular dot and
/// dark rim.
class _ChipFacePainter extends CustomPainter {
  _ChipFacePainter({
    required this.light,
    required this.base,
    required this.dark,
    this.ring,
  });

  final Color light;
  final Color base;
  final Color dark;
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = rect.shortestSide / 2;

    // Body — lit from top-left.
    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.5, -0.55),
        radius: 1.35,
        colors: [light, base, dark],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, body);

    // Dark rim.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, radius * 0.09)
        ..color = dark.withValues(alpha: 0.9),
    );

    // Optional contrasting ring inset.
    if (ring != null) {
      canvas.drawCircle(
        center,
        radius * 0.76,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, radius * 0.07)
          ..color = ring!,
      );
    }

    // Specular highlight.
    final spec = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.42, -0.5),
        radius: 0.5,
        colors: [
          Colors.white.withValues(alpha: 0.65),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius * 0.92, spec);
  }

  @override
  bool shouldRepaint(_ChipFacePainter oldDelegate) =>
      oldDelegate.base != base || oldDelegate.ring != ring;
}

/// Alternating checkered-square gradient used by chess/checkers boards.
///
/// Returns a gradient where [light] squares brighten toward the
/// top-left, so the whole board reads as lit from one direction.
List<BoxDecoration> boardSquareShades({
  required Color lightSquare,
  required Color darkSquare,
  Color? lastMoveTint,
}) {
  return [
    BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(lightSquare, Colors.white, 0.06)!,
          lightSquare,
          Color.lerp(lightSquare, Colors.black, 0.08)!,
        ],
      ),
    ),
    BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(darkSquare, Colors.white, 0.05)!,
          darkSquare,
          Color.lerp(darkSquare, Colors.black, 0.12)!,
        ],
      ),
    ),
    if (lastMoveTint != null)
      BoxDecoration(color: lastMoveTint.withValues(alpha: 0.28)),
  ];
}

/// A pill that shows whose turn it is, with a pulsing status dot and
/// the player's accent — consistent turn language across all games.
class GameTurnPill extends StatelessWidget {
  const GameTurnPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.active = false,
    this.trailing,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool active;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(KinrelRadius.full),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.8) : KinrelColors.border,
          width: active ? 1.4 : 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active) ...[
            _PulsingDot(color: color),
            const SizedBox(width: 8),
          ] else if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? KinrelColors.textWhite : KinrelColors.textDim,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.75, end: 1.15).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.7),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
