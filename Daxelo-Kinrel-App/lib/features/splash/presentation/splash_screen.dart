import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/database/isar_database.dart';
import '../../../core/database/collections/cached_profile.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/storage/secure_storage.dart';

// ─────────────────────────────────────────────────────────────────────
// KINREL Splash Screen — Animated K-Graph Experience
//
// Animation sequence (1.5–2.0 s total):
//   Phase 1  0–300 ms    Radial glow fades in from center
//   Phase 2  300–600 ms  Center "You" node scale-in + heartbeat glow
//   Phase 3  600–900 ms  Edges draw outward → nodes appear
//   Phase 4  900–1200 ms Orbit ring draws in + halo pulse
//   Phase 5  1200–1500 ms "KINREL" fades up (gradient) + "BY DAXELO"
//   Phase 6  1500–1800 ms Hold → fade out → navigate
//
// FAST STARTUP: Reads Isar cache instantly to determine if user
// has a cached profile. If so, navigates to /home immediately
// after the animation without waiting for full Supabase auth.
// ─────────────────────────────────────────────────────────────────────

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  bool _navigated = false;
  bool _initComplete = false;
  bool _hasCachedProfile = false;

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
      if (!_initComplete && mounted) {
        _breathingController.repeat(reverse: true);
      }
    });

    _initialize();
  }

  @override
  void dispose() {
    _introController.dispose();
    _breathingController.dispose();
    _fadeOutController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // Initialization — runs in parallel with animation
  // ─────────────────────────────────────────────────────────────────
  Future<void> _initialize() async {
    // FAST STARTUP: Check Isar cache INSTANTLY for cached profile.
    // If we have one, the user is likely authenticated — we can
    // navigate to home immediately without waiting for Supabase.
    _checkIsarCache();

    // Preload kinship data in the background (5 300+ terms, ~15 MB JSON)
    unawaited(ref.read(kinshipInitializedProvider.future).catchError((_) {}));

    // Start Supabase session restoration in the background.
    // We do NOT await this — it may take 30+ seconds on a cold Supabase.
    // Instead, we navigate based on cached/local state and let the
    // session restoration complete in the background.
    unawaited(_restoreSession());

    // Shorter hold if we have cached data — user sees app faster
    final holdMs = _hasCachedProfile ? 1200 : 1800;
    await Future.delayed(Duration(milliseconds: holdMs));

    if (!mounted || _navigated) return;

    // Read navigation state from LOCAL sources only — don't block on network.
    // If Supabase is already initialized, use its auth state; otherwise
    // fall back to cached profile presence to decide where to go.
    final isAuthenticated = ref.read(isAuthenticatedProvider);
    final secureStorage = SecureStorageService();
    final onboardingComplete = await secureStorage.isOnboardingComplete();

    if (!mounted || _navigated) return;

    // Signal complete — stop breathing
    _initComplete = true;
    _breathingController.stop();

    // Fade out the splash, then navigate
    await _fadeOutController.forward();

    if (!mounted || _navigated) return;

    _navigated = true;

    // If user is authenticated OR has cached profile, go to home.
    // The home screen will show cached data instantly while
    // refreshing in the background.
    // IMPORTANT: Even if Supabase isn't ready yet, we still navigate.
    // If we have a cached profile, the user was previously logged in,
    // so go to home. If not, go to sign-in. This ensures the user
    // NEVER sees a blank screen waiting for Supabase.
    if (!onboardingComplete) {
      // Onboarding not complete — redirect to onboarding flow
      context.go('/onboarding');
    } else if (isAuthenticated || _hasCachedProfile) {
      final lastRoute = await getLastRoute();
      if (!mounted || _navigated) return;
      if (lastRoute != null && lastRoute != '/splash' && mounted) {
        context.go(lastRoute);
        return;
      }
      context.go('/home');
    } else {
      // Not authenticated and no cached profile — go to sign-in
      context.go('/sign-in');
    }
  }

  /// Check Isar cache for a cached user profile.
  /// If found, set _hasCachedProfile = true so we can navigate faster.
  void _checkIsarCache() {
    if (!IsarDatabase.isInitialized) return;
    // TODO: Re-enable Isar cache check once generated code is available.
    // The cachedProfiles getter on Isar requires running build_runner
    // to generate the .g.dart file for CachedProfile.
    debugPrint('📦 Isar cache check skipped — generated code not available');
  }

  /// Restore Supabase session (important for app resume & cold starts).
  /// This runs in the background (fire-and-forget) and should NOT block
  /// splash screen navigation. If Supabase isn't initialized yet, skip.
  Future<void> _restoreSession() async {
    try {
      if (isSupabaseInitialized) {
        final client = ref.read(supabaseProvider);
        if (client != null) {
          final session = client.auth.currentSession;
          if (session == null) {
            try {
              await client.auth.onAuthStateChange.first.timeout(
                const Duration(seconds: 3),
              );
            } catch (_) {
              // Timeout — no session, will redirect to sign-in
            }
          }
          // Let auth state propagate to providers
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }
    } catch (_) {
      // Ignore restoration errors — will redirect to sign-in
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: AnimatedBuilder(
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
//
// Draws the animated K-graph network:
//   7 nodes  — Center (You), Top (Parent), Bottom (Child),
//              Left (Spouse), UpperRight (Uncle),
//              LowerRight (Aunt), FarRight (Cousin)
//   6 edges  — Center↔Top, Center↔Bottom, Center↔Left,
//              Center↔UpperRight, Center↔LowerRight,
//              UpperRight↔FarRight
//   1 orbit  — Thin circle around all nodes
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
  // Positions as fractions of half-width (s). Centre of canvas = (0, 0).
  static const _nodes = <_SplashNode>[
    _SplashNode(0.00, -0.42, 0.048, KinrelColors.brightViolet, 'Parent'), // Top
    _SplashNode(
      0.00,
      0.42,
      0.048,
      KinrelColors.brightViolet,
      'Child',
    ), // Bottom
    _SplashNode(-0.42, 0.00, 0.048, KinrelColors.deepPurple, 'Spouse'), // Left
    _SplashNode(
      0.40,
      -0.24,
      0.044,
      KinrelColors.brightViolet,
      'Uncle',
    ), // UpperRight
    _SplashNode(
      0.40,
      0.24,
      0.044,
      KinrelColors.deepPurple,
      'Aunt',
    ), // LowerRight
    _SplashNode(
      0.68,
      -0.24,
      0.044,
      KinrelColors.brightViolet,
      'Cousin',
    ), // FarRight
  ];

  // ── Edge definitions (from-index, to-index into _nodes) ──────────
  // Index -1 = centre node (not in the list; drawn separately)
  static const _edges = <_SplashEdge>[
    _SplashEdge(-1, 0, 0), // Centre → Top (Parent)
    _SplashEdge(-1, 1, 0), // Centre → Bottom (Child)
    _SplashEdge(-1, 2, 1), // Centre → Left (Spouse)
    _SplashEdge(-1, 3, 1), // Centre → UpperRight (Uncle)
    _SplashEdge(-1, 4, 1), // Centre → LowerRight (Aunt)
    _SplashEdge(3, 5, 2), // UpperRight → FarRight (Cousin)
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.width / 2; // half-size for positioning

    // ── Phase 1: Radial glow (behind everything) ───────────────────
    if (glowProgress > 0) {
      _drawGlowCore(canvas, size, cx, cy);
    }

    // ── Phase 4: Orbit ring + halo (behind nodes, in front of glow) ─
    if (orbitProgress > 0) {
      _drawOrbitAndHalo(canvas, cx, cy, s);
    }

    // ── Phase 3: Edges + outer nodes ───────────────────────────────
    if (edgesProgress > 0) {
      _drawEdgesAndNodes(canvas, cx, cy, s);
    }

    // ── Phase 2: Centre node (on top of everything) ────────────────
    if (centerNodeProgress > 0) {
      _drawCenterNode(canvas, cx, cy, s);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Phase 1 — Radial glow core
  // ─────────────────────────────────────────────────────────────────
  void _drawGlowCore(Canvas canvas, Size size, double cx, double cy) {
    final alpha = (0.28 * glowProgress).clamp(0.0, 1.0);
    final glowPaint = Paint()
      ..shader =
          RadialGradient(
            center: const Alignment(-0.4, -0.4), // 30 % 30 %
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

  // ─────────────────────────────────────────────────────────────────
  // Phase 2 — Centre "You" node with heartbeat glow
  // ─────────────────────────────────────────────────────────────────
  void _drawCenterNode(Canvas canvas, double cx, double cy, double s) {
    final baseRadius = s * 0.075;
    final scale = centerNodeProgress; // easeOutBack gives a slight overshoot
    final radius = baseRadius * scale;

    if (radius <= 0) return;

    final center = Offset(cx, cy);

    // Heartbeat glow — double-pulse like a real heartbeat
    final glowIntensity = _heartbeatGlow(centerNodeProgress);

    // Outer glow ring
    if (glowIntensity > 0) {
      final glowPaint = Paint()
        ..color = KinrelColors.purple.withValues(alpha: glowIntensity * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, radius * 3.0, glowPaint);
    }

    // Soft inner glow
    final innerGlow = Paint()
      ..color = KinrelColors.purple.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius * 1.8, innerGlow);

    // Node body
    final nodePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(-0.3, -0.3),
        colors: [
          KinrelColors.brightViolet, // #F59240 amber highlight
          KinrelColors.purple, // #E8612A orange
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, nodePaint);

    // Specular highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(
      Offset(cx - radius * 0.28, cy - radius * 0.28),
      radius * 0.32,
      highlightPaint,
    );
  }

  /// Double-pulse heartbeat curve: two quick peaks then settle.
  static double _heartbeatGlow(double t) {
    // t ranges 0→1 over the centre-node phase
    if (t < 0.15) return 0.0;
    if (t < 0.40) return math.sin(math.pi * (t - 0.15) / 0.25); // first beat
    if (t < 0.50) return 0.0;
    if (t < 0.75) {
      return 0.6 *
          math.sin(math.pi * (t - 0.50) / 0.25); // second beat (softer)
    }
    return 0.0;
  }

  // ─────────────────────────────────────────────────────────────────
  // Phase 3 — Edges draw outward + outer nodes appear
  // ─────────────────────────────────────────────────────────────────
  void _drawEdgesAndNodes(Canvas canvas, double cx, double cy, double s) {
    final center = Offset(cx, cy);

    // Tier timing within edgesProgress (0→1):
    //   Tier 0: 0.00–0.40  Centre→Top, Centre→Bottom
    //   Tier 1: 0.25–0.65  Centre→Left, Centre→UpperRight, Centre→LowerRight
    //   Tier 2: 0.55–1.00  UpperRight→FarRight

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

      // Resolve positions
      final Offset from;
      if (edge.from == -1) {
        from = center;
      } else {
        final n = _nodes[edge.from];
        from = Offset(cx + n.x * s, cy + n.y * s);
      }
      final toN = _nodes[edge.to];
      final to = Offset(cx + toN.x * s, cy + toN.y * s);

      // Draw edge with progress
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

      // Node appears when its edge is ~80 % drawn
      if (progress > 0.75) {
        final nodeOpacity = ((progress - 0.75) / 0.25).clamp(0.0, 1.0);
        _drawNode(canvas, to, toN.r * s, toN.color, nodeOpacity);
      }
    }
  }

  /// Draw a single outer node with glow + specular highlight.
  void _drawNode(
    Canvas canvas,
    Offset pos,
    double radius,
    Color color,
    double opacity,
  ) {
    if (radius <= 0 || opacity <= 0) return;

    // Glow halo
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.18 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(pos, radius * 2.2, glowPaint);

    // Node body
    final nodePaint = Paint()..color = color.withValues(alpha: opacity);
    canvas.drawCircle(pos, radius, nodePaint);

    // Specular highlight
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

  // ─────────────────────────────────────────────────────────────────
  // Phase 4 — Orbit ring + halo pulse
  // ─────────────────────────────────────────────────────────────────
  void _drawOrbitAndHalo(Canvas canvas, double cx, double cy, double s) {
    final orbitRadius = s * 0.72;
    final center = Offset(cx, cy);

    // Orbit ring: circular path animation (arc grows from top)
    final sweepAngle = 2 * math.pi * orbitProgress;
    final orbitPaint = Paint()
      ..color = KinrelColors.purple.withValues(alpha: 0.22)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: orbitRadius),
      -math.pi / 2, // start from top
      sweepAngle,
      false,
      orbitPaint,
    );

    // Dashed secondary orbit (subtle, behind the main one)
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

    // Halo pulse: one soft glow pulse behind the whole icon
    final haloAlpha = 0.18 * math.sin(math.pi * orbitProgress);
    if (haloAlpha > 0) {
      final haloPaint = Paint()
        ..color = KinrelColors.purple.withValues(alpha: haloAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
      canvas.drawCircle(center, s * 0.9, haloPaint);
    }
  }

  // ── Utility: Dashed Circle ────────────────────────────────────────
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

  /// X position as fraction of half-width (0 = centre).
  final double x;

  /// Y position as fraction of half-height (0 = centre).
  final double y;

  /// Radius as fraction of half-width.
  final double r;

  /// Fill colour.
  final Color color;

  /// Debug label (not rendered).
  final String label;
}

class _SplashEdge {
  const _SplashEdge(this.from, this.to, this.tier);

  /// From-node index (-1 = centre "You" node).
  final int from;

  /// To-node index into _SplashNode list.
  final int to;

  /// Draw tier (0 = first, 1 = second, 2 = third).
  final int tier;
}
