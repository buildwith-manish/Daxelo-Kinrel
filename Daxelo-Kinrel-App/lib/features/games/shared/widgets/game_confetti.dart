// lib/features/games/shared/widgets/game_confetti.dart
//
// DAXELO KINREL — Physics-based confetti particle system for all games.
//
// A dependency-free (CustomPainter + Ticker) celebration engine that
// replaces the old static "orbiting emoji" confetti with a real
// particle simulation:
//
//   • Corner cannons + center pop launch patterns
//   • Gravity, air drag and terminal flutter physics
//   • 3D card-flip illusion (scaleY oscillation)
//   • Four shapes: confetti strips, dots, stars, waving streamers
//   • Kinrel celebration palette (orange / amber / gold / teal / coral)
//   • Device-tier aware: low-end devices get fewer particles,
//     MediaQuery.disableAnimations disables the system entirely.
//
// Usage:
//   Stack(
//     fit: StackFit.expand,
//     children: [
//       yourContent,
//       const GameConfetti(),          // one-shot, auto-fires 3 bursts
//     ],
//   )
//
//   // Or with a custom palette + more bursts:
//   GameConfetti(colors: [Colors.pink, Colors.cyan], burstCount: 4)

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/utils/device_tier.dart';
import '../../game_motion_tokens.dart';

/// The kind of paper a single confetti particle is cut from.
enum ConfettiShape {
  /// Classic paper strip — flips in 3D while falling.
  strip,

  /// Round dot — punch-card style confetti.
  dot,

  /// Five-point star — celebration sparkle.
  star,

  /// Long waving ribbon trailing from the particle.
  streamer,
}

/// One simulated confetti particle. Pure value object — the simulation
/// lives in [GameConfettiController].
class ConfettiParticle {
  ConfettiParticle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.shape,
    required this.size,
    required this.maxLife,
    required this.angle,
    required this.angularVelocity,
    required this.flipPhase,
    required this.flipFrequency,
    required this.wobblePhase,
    required this.wobbleFrequency,
    required this.wobbleAmplitude,
  });

  Offset position;
  Offset velocity;
  final Color color;
  final ConfettiShape shape;
  final double size;
  final double maxLife;
  double life = 0; // seconds lived

  double angle;
  final double angularVelocity;

  // 3D flip illusion: scaleY = cos(flipPhase + t * flipFrequency)
  final double flipPhase;
  final double flipFrequency;

  // Lateral flutter while falling.
  final double wobblePhase;
  final double wobbleFrequency;
  final double wobbleAmplitude;

  bool get isDead => life >= maxLife;
  double get progress => (life / maxLife).clamp(0.0, 1.0);
}

/// Simulation engine. Owns one [Ticker] and a particle pool; notifies
/// painters via the [ChangeNotifier] protocol (`super(repaint: ...)`).
class GameConfettiController extends ChangeNotifier {
  GameConfettiController({required TickerProvider vsync, this.maxParticles = 220}) {
    _ticker = vsync.createTicker(_onTick);
  }

  final int maxParticles;
  late final Ticker _ticker;
  final List<ConfettiParticle> _particles = <ConfettiParticle>[];
  Duration _last = Duration.zero;
  final math.Random _rng = math.Random();

  List<ConfettiParticle> get particles => List.unmodifiable(_particles);
  bool get isAnimating => _ticker.isActive;
  bool get hasLiveParticles => _particles.isNotEmpty;

  static const List<Color> _celebrationPalette = [
    KinrelColors.orange,
    KinrelColors.amber,
    KinrelColors.gold,
    KinrelColors.brightGold,
    KinrelColors.tealAccent,
    KinrelColors.coral,
  ];

  /// Fires a celebratory volley.
  ///
  /// [origin] defaults to the bottom center of the overlay. [count]
  /// particles are launched in a cone around [direction] (radians,
  /// 0 = right, -PI/2 = up) with [spread] radians of randomness.
  void burst({
    required Size size,
    Offset? origin,
    int count = 36,
    List<Color>? colors,
    double direction = -math.pi / 2,
    double spread = math.pi / 3,
    double power = 760,
  }) {
    if (!_ticker.isTicking) {
      _ticker.start();
    }
    final palette = colors ?? _celebrationPalette;
    final o = origin ?? Offset(size.width / 2, size.height * 0.72);
    for (var i = 0; i < count; i++) {
      if (_particles.length >= maxParticles) break;
      _particles.add(_makeParticle(o, palette, direction, spread, power));
    }
    notifyListeners();
  }

  /// The signature Kinrel celebration: two corner cannons + a center pop.
  void celebrate(Size size, {List<Color>? colors, int density = 1}) {
    final tier = DeviceTierCache.instance;
    final scale = tier.tier == DeviceTier.low
        ? 0.4
        : tier.tier == DeviceTier.mid
            ? 0.7
            : 1.0;
    final n = (density * scale).round().clamp(1, 3);

    burst(
      size: size,
      origin: Offset(-8, size.height * 0.9),
      count: 26 * n,
      colors: colors,
      direction: -math.pi / 3.2,
      spread: math.pi / 5,
      power: 900,
    );
    burst(
      size: size,
      origin: Offset(size.width + 8, size.height * 0.9),
      count: 26 * n,
      colors: colors,
      direction: -math.pi + math.pi / 3.2,
      spread: math.pi / 5,
      power: 900,
    );
    burst(
      size: size,
      origin: Offset(size.width / 2, size.height * 0.62),
      count: 30 * n,
      colors: colors,
      direction: -math.pi / 2,
      spread: math.pi / 2.2,
      power: 620,
    );
  }

  ConfettiParticle _makeParticle(
    Offset origin,
    List<Color> palette,
    double direction,
    double spread,
    double power,
  ) {
    final angle = direction + (_rng.nextDouble() - 0.5) * spread;
    final speed = power * (0.55 + _rng.nextDouble() * 0.65);
    final shapeRoll = _rng.nextDouble();
    final shape = shapeRoll < 0.5
        ? ConfettiShape.strip
        : shapeRoll < 0.72
            ? ConfettiShape.dot
            : shapeRoll < 0.88
                ? ConfettiShape.star
                : ConfettiShape.streamer;

    return ConfettiParticle(
      position: origin,
      velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
      color: palette[_rng.nextInt(palette.length)],
      shape: shape,
      size: shape == ConfettiShape.streamer ? 4.5 : 5.5 + _rng.nextDouble() * 5,
      maxLife: 2.6 + _rng.nextDouble() * 1.8,
      angle: _rng.nextDouble() * math.pi * 2,
      angularVelocity: (_rng.nextDouble() - 0.5) * 9,
      flipPhase: _rng.nextDouble() * math.pi * 2,
      flipFrequency: 5 + _rng.nextDouble() * 7,
      wobblePhase: _rng.nextDouble() * math.pi * 2,
      wobbleFrequency: 1.6 + _rng.nextDouble() * 2.6,
      wobbleAmplitude: 26 + _rng.nextDouble() * 34,
    );
  }

  void _onTick(Duration elapsed) {
    if (_last == Duration.zero) _last = elapsed;
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    if (dt > 0.05) {
      // Long frame (tab switch / jank) — clamp so particles don't teleport.
      _step(0.016);
    } else {
      _step(dt);
    }

    if (_particles.isEmpty) {
      _ticker.stop();
      _last = Duration.zero;
    }
    notifyListeners();
  }

  void _step(double dt) {
    const gravity = 980.0;
    const drag = 0.88;
    for (final p in _particles) {
      p.life += dt;

      // Air resistance — exponential decay.
      final decay = math.pow(drag, dt).toDouble();
      p.velocity = Offset(p.velocity.dx * decay, p.velocity.dy * decay);

      // Gravity, softened once terminal flutter kicks in.
      final flutterK = p.life > 0.55 ? 0.35 : 1.0;
      p.velocity = p.velocity +
          Offset(0, gravity * flutterK * dt) -
          Offset(0, p.velocity.dy * 0.55 * dt);

      // Lateral flutter.
      final wob =
          math.sin(p.wobblePhase + p.life * p.wobbleFrequency) * p.wobbleAmplitude;
      p.position = p.position +
          Offset((p.velocity.dx + wob) * dt, p.velocity.dy * dt);

      p.angle += p.angularVelocity * dt;
    }
    _particles.removeWhere((p) => p.isDead || p.position.dy > 2400);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void stop() {
    _ticker.stop();
    _last = Duration.zero;
  }
}

/// Painter that renders the particle field. Pass the controller as
/// `repaint` so the painter repaints every simulation tick.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required GameConfettiController controller})
      : _controller = controller,
        super(repaint: controller);

  final GameConfettiController _controller;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _controller.particles) {
      final opacity = _opacityFor(p);
      final paint = Paint()..color = p.color.withValues(alpha: opacity);

      final flip =
          math.cos(p.flipPhase + p.life * p.flipFrequency).abs().clamp(0.18, 1.0);

      canvas.save();
      canvas.translate(p.position.dx, p.position.dy);
      canvas.rotate(p.angle);

      switch (p.shape) {
        case ConfettiShape.strip:
          final w = p.size;
          final h = p.size * 1.7 * flip;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: w, height: h),
              const Radius.circular(1.6),
            ),
            paint,
          );
          break;
        case ConfettiShape.dot:
          final r = p.size * 0.42 * (0.6 + 0.4 * flip);
          canvas.drawCircle(Offset.zero, r, paint);
          break;
        case ConfettiShape.star:
          _drawStar(canvas, p.size * 0.95 * flip, paint);
          break;
        case ConfettiShape.streamer:
          _drawStreamer(canvas, p, paint);
          break;
      }
      canvas.restore();
    }
  }

  double _opacityFor(ConfettiParticle p) {
    // Fade in fast (pop), fade out over the last 30% of life.
    if (p.progress < 0.06) return p.progress / 0.06;
    if (p.progress > 0.7) return (1 - p.progress) / 0.3;
    return 1;
  }

  void _drawStar(Canvas canvas, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? radius : radius * 0.42;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = math.cos(a) * r;
      final y = math.sin(a) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawStreamer(Canvas canvas, ConfettiParticle p, Paint paint) {
    final wave = math.sin(p.wobblePhase + p.life * p.wobbleFrequency * 1.4);
    final length = p.size * 7;
    final path = Path()..moveTo(0, 0);
    for (var i = 1; i <= 3; i++) {
      final t = i / 3;
      path.quadraticBezierTo(
        wave * 6 * t * (1 - t) * 4,
        length * t - length * 0.083,
        wave * 10 * t,
        length * t,
      );
    }
    paint.strokeWidth = p.size * 0.55;
    paint.strokeCap = StrokeCap.round;
    paint.style = PaintingStyle.stroke;
    canvas.drawPath(path, paint);
    paint.style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => true;
}

/// One-shot confetti overlay. Drop it in a [Stack] and it fires the
/// signature celebration automatically, then hibernates (ticker stops)
/// once every particle has died — zero idle cost.
class GameConfetti extends StatefulWidget {
  const GameConfetti({
    super.key,
    this.colors,
    this.burstCount = 3,
    this.burstInterval = const Duration(milliseconds: 450),
    this.enabled = true,
    this.density = 1,
  });

  /// Custom palette. Defaults to the Kinrel celebration palette.
  final List<Color>? colors;

  /// Number of celebration volleys fired in sequence.
  final int burstCount;

  /// Delay between volleys.
  final Duration burstInterval;

  /// Set false to render nothing (callers gate this on context).
  final bool enabled;

  /// Particle density multiplier (1 = standard celebration).
  final int density;

  @override
  State<GameConfetti> createState() => _GameConfettiState();
}

class _GameConfettiState extends State<GameConfetti>
    with SingleTickerProviderStateMixin {
  GameConfettiController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respect the OS "remove animations" accessibility setting.
    final animationsEnabled =
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    final active = widget.enabled && animationsEnabled;

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!active ||
              !constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight) {
            return const SizedBox.shrink();
          }

          _controller ??= GameConfettiController(vsync: this);
          final controller = _controller!;
          final size = Size(constraints.maxWidth, constraints.maxHeight);

          // Fire the volleys once we know our size. The pending count
          // lives in state so rebuilds don't re-trigger the celebration.
          if (_volleysFired == 0) {
            _volleysFired = 1;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              GameMotionTokens.celebrate();
              controller.celebrate(size, colors: widget.colors, density: widget.density);
              for (var i = 1; i < widget.burstCount; i++) {
                Future.delayed(widget.burstInterval * i, () {
                  if (!mounted) return;
                  controller.celebrate(size, colors: widget.colors, density: widget.density);
                });
              }
            });
          }

          return CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(controller: controller),
            willChange: true,
          );
        },
      ),
    );
  }

  int _volleysFired = 0;
}

/// Reusable celebration palette tinted with a game's accent color.
List<Color> confettiPaletteFor(Color accent) {
  return [
    accent,
    KinrelColors.orange,
    KinrelColors.amber,
    KinrelColors.gold,
    KinrelColors.brightGold,
    KinrelColors.tealAccent,
    KinrelColors.coral,
  ];
}
