import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/config/auth_config.dart';
import '../../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────
// KINREL Splash Screen — Animated K-Graph Experience
//
// ARCHITECTURE REWRITE: ZERO awaits in the splash screen.
//
// Navigation is driven by:
//   1. ref.listen() on isAuthenticatedProvider — reactive redirect
//      when auth state resolves (Supabase session restore, etc.)
//   2. Fixed 2s timer — safety navigate regardless of init state
//
// Background services (Drift, Firebase, Supabase) initialize
// independently via appInitProvider. The splash never reads or
// awaits appInitProvider.
// ─────────────────────────────────────────────────────────────────────

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  bool _navigated = false;
  bool _animationComplete = false;

  // ── Animation Controllers ────────────────────────────────────────
  late final AnimationController _introController; // 1 500 ms – main sequence
  late final AnimationController
      _breathingController; // 1 000 ms × 2 = 2 s cycle
  late final AnimationController _fadeOutController; // 400 ms – screen exit

  // ── Phase Animations (derived from _introController) ─────────────
  late final Animation<double> _glowFadeIn; // 0–300 ms
  late final Animation<double> _centerNodeScale; // 300–600 ms
  late final Animation<double> _edgesProgress; // 600–900 ms
  late final Animation<double> _orbitProgress; // 900–1 200 ms
  late final Animation<double> _textFade; // 1 200–1 500 ms

  @override
  void initState() {
    super.initState();

    // ── Intro: 1 500 ms ─────────────────────────────────────────────
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // ── Breathing: 1 000 ms per half-cycle → 2 s full ──────────────
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // ── Fade-out: 400 ms ────────────────────────────────────────────
    _fadeOutController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // ── Phase intervals ─────────────────────────────────────────────
    _glowFadeIn = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
    );
    _centerNodeScale = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.2, 0.4, curve: Curves.easeOutBack),
    );
    _edgesProgress = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.4, 0.6, curve: Curves.easeOutCubic),
    );
    _orbitProgress = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.6, 0.8, curve: Curves.easeOutCubic),
    );
    _textFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.8, 1.0, curve: Curves.easeOut),
    );

    // ── Kick off intro, then breathing if still waiting ─────────────
    _introController.forward().then((_) {
      _animationComplete = true;
      if (!_navigated && mounted) {
        _breathingController.repeat(reverse: true);
        // Auth might have already resolved during animation — try navigate
        _tryNavigate();
      }
    });

    // ── Fixed 2s safety timer ───────────────────────────────────────
    // Navigate after 2s regardless of whether init has completed.
    // ZERO awaits — just a Timer.
    Future.delayed(const Duration(seconds: 2), _onSafetyTimeout);
  }

  @override
  void dispose() {
    _introController.dispose();
    _breathingController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // Navigation — driven by ref.listen() + 2s safety timer
  // ─────────────────────────────────────────────────────────────────

  /// Safety timeout: force navigate after 2s even if auth hasn't resolved.
  void _onSafetyTimeout() {
    if (!mounted || _navigated) return;
    _navigate();
  }

  /// Try to navigate if both animation is complete AND we have auth state.
  /// Called when either animation completes or auth state changes.
  void _tryNavigate() {
    // Only navigate after animation finishes (no jarring mid-animation jump)
    if (!_animationComplete || _navigated || !mounted) return;

    // Read current auth state synchronously — no awaits
    final isAuth = _isAuthenticated();
    if (isAuth != null) {
      // Auth state is resolved — navigate now
      _navigate();
    }
    // If auth state is null (still loading), wait for either:
    //   - ref.listen() callback when auth resolves
    //   - 2s safety timeout
  }

  /// Check if user is authenticated. Returns null if auth state
  /// hasn't resolved yet (Supabase still initializing).
  bool? _isAuthenticated() {
    // AUTH DISABLED: Always treat as authenticated
    if (kAuthDisabled) return true;

    // Try Riverpod auth state (may not be ready yet)
    try {
      final isAuth = ref.read(isAuthenticatedProvider);
      return isAuth;
    } catch (_) {}

    // Try Supabase directly (bypasses Riverpod lag)
    if (isSupabaseInitialized) {
      try {
        final hasSession =
            Supabase.instance.client.auth.currentSession != null;
        return hasSession;
      } catch (_) {}
    }

    // Can't determine auth state yet — return null (still loading)
    return null;
  }

  /// Perform the actual navigation. Called exactly once.
  void _navigate() {
    if (!mounted || _navigated) return;
    _navigated = true;
    _breathingController.stop();

    final isAuth = _isAuthenticated();

    // Fade out, then navigate
    _fadeOutController.forward().then((_) {
      if (!mounted) return;

      if (isAuth == true) {
        context.go('/home');
      } else {
        // Default to sign-in when:
        //   - Not authenticated
        //   - Auth state couldn't be determined (null)
        // GoRouter redirect will move user to /home if auth resolves later
        context.go('/sign-in');
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // ── Reactive auth listener ──────────────────────────────────────
    // Drives navigation when auth state resolves. This is the PRIMARY
    // navigation trigger — the 2s timer is just a safety fallback.
    ref.listen(isAuthenticatedProvider, (prev, next) {
      _tryNavigate();
    });

    return Scaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: KinrelAnimatedBuilder(
        animation: Listenable.merge([
          _introController,
          _breathingController,
          _fadeOutController,
        ]),
        builder: (context, _) {
          final fadeOpacity = 1.0 - _fadeOutController.value;

          return Opacity(
            opacity: fadeOpacity,
            child: Container(
              color: KinrelColors.darkSurface,
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 3),
                      _buildKGraph(),
                      const SizedBox(height: 40),
                      _buildWordmark(),
                      const SizedBox(height: 10),
                      _buildByline(),
                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── K-Graph Icon ────────────────────────────────────────────────
  Widget _buildKGraph() {
    // Breathing: subtle scale pulse while waiting for init
    final breathingScale = _introController.isCompleted
        ? 1.0 + 0.02 * _breathingController.value
        : 1.0;

    return Transform.scale(
      scale: breathingScale,
      child: CustomPaint(
        size: const Size(200, 200),
        painter: _KGraphSplashPainter(
          glowProgress: _glowFadeIn.value,
          centerNodeProgress: _centerNodeScale.value,
          edgesProgress: _edgesProgress.value,
          orbitProgress: _orbitProgress.value,
        ),
      ),
    );
  }

  // ── "KINREL" Wordmark ───────────────────────────────────────────
  Widget _buildWordmark() {
    final opacity = _textFade.value.clamp(0.0, 1.0);
    final slideY = (1.0 - _textFade.value) * 12.0;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, slideY),
        child: ShaderMask(
          shaderCallback: (bounds) {
            return const LinearGradient(
              colors: [
                Color(0xFFFFFFFF), // white
                Color(0xFFE8612A), // orange
                Color(0xFFF59240), // amber
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds);
          },
          child: Text(
            'KINREL',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont, // Outfit
              fontSize: 36,
              fontWeight: FontWeight.w800, // ExtraBold
              letterSpacing: 36 * 0.16, // +0.16 em = 5.76
              height: 1.1,
              color: Colors.white, // ShaderMask needs non-transparent base
            ),
          ),
        ),
      ),
    );
  }

  // ── "BY DAXELO" Byline ──────────────────────────────────────────
  Widget _buildByline() {
    // Delayed fade: starts at textFade 0.5 → full at 1.0
    final opacity = (_textFade.value * 2.0 - 1.0).clamp(0.0, 1.0);
    final slideY = (1.0 - _textFade.value) * 8.0;

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, slideY),
        child: Text(
          'BY DAXELO',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont, // DM Mono
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: KinrelColors.textSilver, // #C9B4A8
            letterSpacing: 2.0,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// K-Graph Splash CustomPainter
// ═════════════════════════════════════════════════════════════════════

class _KGraphSplashPainter extends CustomPainter {
  const _KGraphSplashPainter({
    required this.glowProgress,
    required this.centerNodeProgress,
    required this.edgesProgress,
    required this.orbitProgress,
  });

  final double glowProgress;
  final double centerNodeProgress;
  final double edgesProgress;
  final double orbitProgress;

  // ── Node definitions ─────────────────────────────────────────────
  static const _nodes = <_SplashNode>[
    _SplashNode(0.00, -0.42, 0.048, KinrelColors.brightViolet, 'Parent'),
    _SplashNode(0.00, 0.42, 0.048, KinrelColors.brightViolet, 'Child'),
    _SplashNode(-0.42, 0.00, 0.048, KinrelColors.deepPurple, 'Spouse'),
    _SplashNode(0.40, -0.24, 0.044, KinrelColors.brightViolet, 'Uncle'),
    _SplashNode(0.40, 0.24, 0.044, KinrelColors.deepPurple, 'Aunt'),
    _SplashNode(0.68, -0.24, 0.044, KinrelColors.brightViolet, 'Cousin'),
  ];

  // ── Edge definitions (from-index, to-index into _nodes) ──────────
  static const _edges = <_SplashEdge>[
    _SplashEdge(-1, 0, 0),
    _SplashEdge(-1, 1, 0),
    _SplashEdge(-1, 2, 1),
    _SplashEdge(-1, 3, 1),
    _SplashEdge(-1, 4, 1),
    _SplashEdge(3, 5, 2),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.width / 2;

    if (glowProgress > 0) {
      _drawGlowCore(canvas, size, cx, cy);
    }

    if (orbitProgress > 0) {
      _drawOrbitAndHalo(canvas, cx, cy, s);
    }

    if (edgesProgress > 0) {
      _drawEdgesAndNodes(canvas, cx, cy, s);
    }

    if (centerNodeProgress > 0) {
      _drawCenterNode(canvas, cx, cy, s);
    }
  }

  void _drawGlowCore(Canvas canvas, Size size, double cx, double cy) {
    final alpha = (0.28 * glowProgress).clamp(0.0, 1.0);
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            center: const Alignment(-0.4, -0.4),
            radius: 0.7,
            colors: [
              Color.fromRGBO(232, 97, 42, alpha),
              KinrelColors.darkSurface,
            ],
          ).createShader(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: size.width * 1.2,
              height: size.height * 1.2,
            ),
          );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: size.width,
        height: size.height,
      ),
      glowPaint,
    );
  }

  void _drawCenterNode(Canvas canvas, double cx, double cy, double s) {
    final baseRadius = s * 0.075;
    final scale = centerNodeProgress;
    final radius = baseRadius * scale;

    if (radius <= 0) return;

    final center = Offset(cx, cy);
    final glowIntensity = _heartbeatGlow(centerNodeProgress);

    if (glowIntensity > 0) {
      final glowPaint = Paint()
        ..color = KinrelColors.purple.withValues(alpha: glowIntensity * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, radius * 3.0, glowPaint);
    }

    final innerGlow = Paint()
      ..color = KinrelColors.purple.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius * 1.8, innerGlow);

    final nodePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(-0.3, -0.3),
        colors: [
          KinrelColors.brightViolet,
          KinrelColors.purple,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, nodePaint);

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(
      Offset(cx - radius * 0.28, cy - radius * 0.28),
      radius * 0.32,
      highlightPaint,
    );
  }

  static double _heartbeatGlow(double t) {
    if (t < 0.15) return 0.0;
    if (t < 0.40) return math.sin(math.pi * (t - 0.15) / 0.25);
    if (t < 0.50) return 0.0;
    if (t < 0.75) {
      return 0.6 * math.sin(math.pi * (t - 0.50) / 0.25);
    }
    return 0.0;
  }

  void _drawEdgesAndNodes(Canvas canvas, double cx, double cy, double s) {
    final center = Offset(cx, cy);

    for (final edge in _edges) {
      final tier = edge.tier;
      final double tierStart, tierEnd;
      switch (tier) {
        case 0:
          tierStart = 0.0;
          tierEnd = 0.4;
          break;
        case 1:
          tierStart = 0.25;
          tierEnd = 0.65;
          break;
        default:
          tierStart = 0.55;
          tierEnd = 1.0;
          break;
      }

      final progress = ((edgesProgress - tierStart) / (tierEnd - tierStart))
          .clamp(0.0, 1.0);
      if (progress <= 0) continue;

      final Offset from;
      if (edge.from == -1) {
        from = center;
      } else {
        final n = _nodes[edge.from];
        from = Offset(cx + n.x * s, cy + n.y * s);
      }
      final toN = _nodes[edge.to];
      final to = Offset(cx + toN.x * s, cy + toN.y * s);

      final edgePaint = Paint()
        ..color =
            (edge.from == -1 ? KinrelColors.purple : KinrelColors.brightViolet)
                .withValues(alpha: 0.65)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final endPoint = Offset(
        from.dx + (to.dx - from.dx) * progress,
        from.dy + (to.dy - from.dy) * progress,
      );
      canvas.drawLine(from, endPoint, edgePaint);

      if (progress > 0.75) {
        final nodeOpacity = ((progress - 0.75) / 0.25).clamp(0.0, 1.0);
        _drawNode(canvas, to, toN.r * s, toN.color, nodeOpacity);
      }
    }
  }

  void _drawNode(
    Canvas canvas,
    Offset pos,
    double radius,
    Color color,
    double opacity,
  ) {
    if (radius <= 0 || opacity <= 0) return;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.18 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(pos, radius * 2.2, glowPaint);

    final nodePaint = Paint()..color = color.withValues(alpha: opacity);
    canvas.drawCircle(pos, radius, nodePaint);

    if (opacity > 0.5) {
      final hlPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
      canvas.drawCircle(
        Offset(pos.dx - radius * 0.25, pos.dy - radius * 0.25),
        radius * 0.30,
        hlPaint,
      );
    }
  }

  void _drawOrbitAndHalo(Canvas canvas, double cx, double cy, double s) {
    final orbitRadius = s * 0.72;
    final center = Offset(cx, cy);

    final sweepAngle = 2 * math.pi * orbitProgress;
    final orbitPaint = Paint()
      ..color = KinrelColors.purple.withValues(alpha: 0.22)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: orbitRadius),
      -math.pi / 2,
      sweepAngle,
      false,
      orbitPaint,
    );

    if (orbitProgress > 0.5) {
      final dashOpacity = ((orbitProgress - 0.5) * 2.0).clamp(0.0, 0.12);
      final dashPaint = Paint()
        ..color = KinrelColors.brightViolet.withValues(alpha: dashOpacity)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      _drawDashedCircle(
        canvas,
        center,
        orbitRadius * 0.88,
        dashPaint,
        dashWidth: 8,
        dashGap: 12,
      );
    }

    final haloAlpha = 0.18 * math.sin(math.pi * orbitProgress);
    if (haloAlpha > 0) {
      final haloPaint = Paint()
        ..color = KinrelColors.purple.withValues(alpha: haloAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
      canvas.drawCircle(center, s * 0.9, haloPaint);
    }
  }

  static void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required double dashWidth,
    required double dashGap,
  }) {
    final segmentAngle = (dashWidth + dashGap) / radius;
    final dashAngle = dashWidth / radius;
    double angle = 0;
    while (angle < 2 * math.pi) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        dashAngle,
        false,
        paint,
      );
      angle += segmentAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _KGraphSplashPainter old) =>
      glowProgress != old.glowProgress ||
      centerNodeProgress != old.centerNodeProgress ||
      edgesProgress != old.edgesProgress ||
      orbitProgress != old.orbitProgress;
}

// ═════════════════════════════════════════════════════════════════════
// Internal data classes for the splash painter
// ═════════════════════════════════════════════════════════════════════

class _SplashNode {
  const _SplashNode(this.x, this.y, this.r, this.color, this.label);

  final double x;
  final double y;
  final double r;
  final Color color;
  final String label;
}

class _SplashEdge {
  const _SplashEdge(this.from, this.to, this.tier);

  final int from;
  final int to;
  final int tier;
}
