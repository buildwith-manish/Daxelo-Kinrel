import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/services/analytics_service.dart';
import '../../../shared/widgets/dk_components.dart';

// ═══════════════════════════════════════════════════════════════════════
// Onboarding Screen — Redesigned
// 4 onboarding pages → sign-in (Quick Setup removed; login first)
// ═══════════════════════════════════════════════════════════════════════

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;

  static const int _onboardingPageCount = 4;

  @override
  void initState() {
    super.initState();

    // P5-F1: Track onboarding start
    AnalyticsService.instance.logOnboardingStart();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage < _onboardingPageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Skip Quick Setup — go directly to sign-in.
      // Name and family setup happen AFTER login.
      _completeOnboarding();
    }
  }

  void _onSkip() => _completeOnboarding();

  Future<void> _completeOnboarding() async {
    final storage = SecureStorageService();
    await storage.setOnboardingComplete(true);

    // P5-F1: Track onboarding completion
    AnalyticsService.instance.logOnboardingComplete();

    if (mounted) context.go('/sign-in');
  }

  @override
  Widget build(BuildContext context) {
    return DKScaffold(
      backgroundColor: const Color(0xFF13141E),
      body: _buildOnboardingFlow(),
    );
  }

  // ── Onboarding Flow ─────────────────────────────────────────────

  Widget _buildOnboardingFlow() {
    return Column(
      children: [
        // Skip button — only visible on pages 1-3 (not last page)
        Visibility(
          visible: _currentPage < _onboardingPageCount - 1,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: TextButton(
                onPressed: _onSkip,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFFC9B4A8),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Page content
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            itemCount: _onboardingPageCount,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              return _OnboardingPageWrapper(
                index: index,
                currentPage: _currentPage,
              );
            },
          ),
        ),

        // Page indicators + button
        Padding(
          padding: const EdgeInsets.fromLTRB(
            KinrelSpacing.base,
            0,
            KinrelSpacing.base,
            KinrelSpacing.xxl + 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dot indicators
              SmoothPageIndicator(
                controller: _pageController,
                count: _onboardingPageCount,
                effect: ScrollingDotsEffect(
                  activeDotColor: KinrelColors.orange,
                  dotColor: const Color(0xFF202338),
                  dotHeight: 8,
                  dotWidth: 8,
                  activeDotScale: 1.4,
                  spacing: 8,
                ),
              ),
              const SizedBox(height: 24),

              // Next / Get Started button
              _IgniteButton(
                label: _currentPage == _onboardingPageCount - 1
                    ? 'Get Started'
                    : 'Next',
                onPressed: _onNext,
              ),
            ],
          ),
        ),
      ],
    );
  }


}

// ═══════════════════════════════════════════════════════════════════════
// Page Wrapper — Routes to correct onboarding page
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingPageWrapper extends StatelessWidget {
  const _OnboardingPageWrapper({
    required this.index,
    required this.currentPage,
  });

  final int index;
  final int currentPage;

  @override
  Widget build(BuildContext context) {
    final isActive = currentPage == index;
    switch (index) {
      case 0:
        return _OnboardingPage1(isActive: isActive);
      case 1:
        return _OnboardingPage2(isActive: isActive);
      case 2:
        return _OnboardingPage3(isActive: isActive);
      case 3:
        return _OnboardingPage4(isActive: isActive);
      default:
        return const SizedBox.shrink();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Ignite Gradient Button
// Full-width rounded pill, Ignite gradient (#E8612A → #F59240)
// ═══════════════════════════════════════════════════════════════════════

class _IgniteButton extends StatefulWidget {
  const _IgniteButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_IgniteButton> createState() => _IgniteButtonState();
}

class _IgniteButtonState extends State<_IgniteButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: 56,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: KinrelGradients.igniteGradient,
            borderRadius: BorderRadius.circular(KinrelRadius.full),
            boxShadow: [
              BoxShadow(
                color: KinrelColors.orange.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Text(
              widget.label,
              style: const TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Onboarding Page 1 — "Your Family, Your Story"
// Animated K-graph with 3 pulsing nodes, 4th appears showing growth
// Faint silhouettes of family words at 8% opacity
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingPage1 extends StatefulWidget {
  const _OnboardingPage1({required this.isActive});
  final bool isActive;

  @override
  State<_OnboardingPage1> createState() => _OnboardingPage1State();
}

class _OnboardingPage1State extends State<_OnboardingPage1>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── K-Graph Illustration ────────────────────────────────
          SizedBox(
            height: 260,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Orange radial glow behind graph
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        KinrelColors.orange.withValues(alpha: 0.15),
                        KinrelColors.orange.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                      radius: 0.7,
                    ),
                  ),
                ),
                // Animated K-graph
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size(260, 220),
                      painter: _KGraphPainter(_controller.value),
                    );
                  },
                ),
                // Faint family word silhouettes
                ..._buildFamilyWords(),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // ── Headline ────────────────────────────────────────────
          const Text(
                'Your Family, Your Story',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                  height: 1.2,
                ),
              )
              .animate(target: widget.isActive ? 1 : 0)
              .fadeIn(duration: 500.ms, delay: 200.ms)
              .slideY(begin: 0.15, end: 0),

          const SizedBox(height: 16),

          // ── Body ────────────────────────────────────────────────
          const Text(
                'Kinrel maps every relationship in your family — from your grandparents to your grandchildren, in the language you grew up with.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFFC9B4A8),
                  height: 1.55,
                ),
              )
              .animate(target: widget.isActive ? 1 : 0)
              .fadeIn(duration: 500.ms, delay: 400.ms),
        ],
      ),
    );
  }

  List<Widget> _buildFamilyWords() {
    const words = [
      ('चाचा', Alignment(-1.3, -0.6)),
      ('मामा', Alignment(1.3, -0.4)),
      ('दादा', Alignment(-1.1, 0.8)),
      ('दादी', Alignment(1.2, 0.7)),
    ];

    return words.map((w) {
      return Align(
        alignment: w.$2,
        child: Text(
          w.$1,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: KinrelColors.orange.withValues(alpha: 0.08),
          ),
        ),
      );
    }).toList();
  }
}

/// Custom painter for the K-graph on Page 1
/// 3 base pulsing nodes + 4th that appears showing growth
class _KGraphPainter extends CustomPainter {
  _KGraphPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Node positions: 3 base
    final nodes = [
      Offset(cx, cy - 50), // Top (parent)
      Offset(cx - 70, cy + 30), // Bottom-left
      Offset(cx + 70, cy + 30), // Bottom-right
    ];

    // 4th node appears showing growth
    final growthT = ((progress * 2) % 1.0).clamp(0.0, 1.0);
    final fourthNode = Offset(
      cx + 120 * growthT,
      cy - 20 + 10 * math.sin(progress * math.pi * 2),
    );

    final allNodes = [...nodes, fourthNode];

    // Draw edges
    final edgePaint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Connect top to bottom-left and bottom-right
    canvas.drawLine(nodes[0], nodes[1], edgePaint);
    canvas.drawLine(nodes[0], nodes[2], edgePaint);
    canvas.drawLine(nodes[1], nodes[2], edgePaint);

    // Connect to growth node
    if (growthT > 0.3) {
      final alpha = ((growthT - 0.3) / 0.7).clamp(0.0, 1.0);
      edgePaint.color = KinrelColors.orange.withValues(alpha: 0.3 * alpha);
      canvas.drawLine(nodes[2], fourthNode, edgePaint);
    }

    // Draw nodes
    for (int i = 0; i < allNodes.length; i++) {
      final node = allNodes[i];
      final isGrowthNode = i == 3;
      final pulsePhase = (progress * 2 + i * 0.25) % 1.0;
      final pulseScale = 1.0 + 0.15 * math.sin(pulsePhase * math.pi * 2);
      final baseRadius = isGrowthNode ? 10.0 * growthT : 12.0;
      final radius = baseRadius * pulseScale;

      // Glow
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            KinrelColors.orange.withValues(alpha: 0.25),
            Colors.transparent,
          ],
          radius: 0.6,
        ).createShader(Rect.fromCircle(center: node, radius: radius * 3));

      canvas.drawCircle(node, radius * 3, glowPaint);

      // Node fill
      final fillPaint = Paint()
        ..color = isGrowthNode
            ? KinrelColors.amber.withValues(alpha: growthT)
            : KinrelColors.orange;
      canvas.drawCircle(node, radius, fillPaint);

      // Node border
      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(node, radius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _KGraphPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════
// Onboarding Page 2 — "Names That Feel Like Home"
// Animated cascade of kinship cards floating/falling
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingPage2 extends StatefulWidget {
  const _OnboardingPage2({required this.isActive});
  final bool isActive;

  @override
  State<_OnboardingPage2> createState() => _OnboardingPage2State();
}

class _OnboardingPage2State extends State<_OnboardingPage2>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Kinship Cards Cascade ───────────────────────────────
          SizedBox(
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Background glow
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        KinrelColors.orange.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                      radius: 0.7,
                    ),
                  ),
                ),
                // Floating kinship cards
                _KinshipCard(
                  top: 10,
                  left: 16,
                  hindi: 'चाचा',
                  english: "Father's younger brother",
                  delay: 0,
                  controller: _controller,
                ),
                _KinshipCard(
                  top: 75,
                  right: 8,
                  hindi: 'मामा',
                  english: "Mother's brother",
                  delay: 0.2,
                  controller: _controller,
                ),
                _KinshipCard(
                  top: 140,
                  left: 32,
                  hindi: 'भाभी',
                  english: "Elder brother's wife",
                  delay: 0.4,
                  controller: _controller,
                ),
                _KinshipCard(
                  top: 200,
                  right: 24,
                  hindi: 'फूफा',
                  english: "Father's sister's husband",
                  delay: 0.6,
                  controller: _controller,
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // ── Headline ────────────────────────────────────────────
          const Text(
                'Names That Feel Like Home',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                  height: 1.2,
                ),
              )
              .animate(target: widget.isActive ? 1 : 0)
              .fadeIn(duration: 500.ms, delay: 200.ms)
              .slideY(begin: 0.15, end: 0),

          const SizedBox(height: 16),

          // ── Body ────────────────────────────────────────────────
          const Text(
                "Not just 'uncle' and 'aunt' — Kinrel knows the difference between your Chacha, Mama, Fufa, and Tauji. In Hindi, Tamil, Bengali, Telugu, and 11+ more languages.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFFC9B4A8),
                  height: 1.55,
                ),
              )
              .animate(target: widget.isActive ? 1 : 0)
              .fadeIn(duration: 500.ms, delay: 400.ms),
        ],
      ),
    );
  }
}

/// A single floating kinship card used on Page 2
class _KinshipCard extends StatelessWidget {
  const _KinshipCard({
    this.top = 0,
    this.left,
    this.right,
    required this.hindi,
    required this.english,
    required this.delay,
    required this.controller,
  });

  final double top;
  final double? left;
  final double? right;
  final String hindi;
  final String english;
  final double delay;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final phase = (controller.value + delay) % 1.0;
          final floatOffset = math.sin(phase * math.pi * 2) * 4;
          return Transform.translate(
            offset: Offset(0, floatOffset),
            child: _buildCard(),
          );
        },
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF202338).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: KinrelColors.orange.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orange.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hindi,
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KinrelColors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '— $english',
            style: const TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: Color(0xFFC9B4A8),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Onboarding Page 3 — "See the Big Picture"
// Mini family graph with ~8 nodes, auto-rotate/pan
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingPage3 extends StatefulWidget {
  const _OnboardingPage3({required this.isActive});
  final bool isActive;

  @override
  State<_OnboardingPage3> createState() => _OnboardingPage3State();
}

class _OnboardingPage3State extends State<_OnboardingPage3>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Mini Family Graph ───────────────────────────────────
          SizedBox(
            height: 260,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Glow
                Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        KinrelColors.orange.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      radius: 0.8,
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size(280, 240),
                      painter: _FamilyGraphPainter(_controller.value),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // ── Headline ────────────────────────────────────────────
          const Text(
                'See the Big Picture',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                  height: 1.2,
                ),
              )
              .animate(target: widget.isActive ? 1 : 0)
              .fadeIn(duration: 500.ms, delay: 200.ms)
              .slideY(begin: 0.15, end: 0),

          const SizedBox(height: 16),

          // ── Body ────────────────────────────────────────────────
          const Text(
                'Your entire family as a beautiful, interactive graph. Zoom in, explore connections, discover relationships you never knew existed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFFC9B4A8),
                  height: 1.55,
                ),
              )
              .animate(target: widget.isActive ? 1 : 0)
              .fadeIn(duration: 500.ms, delay: 400.ms),
        ],
      ),
    );
  }
}

/// Custom painter for the family graph on Page 3
/// ~8 nodes with auto-rotate/pan animation
class _FamilyGraphPainter extends CustomPainter {
  _FamilyGraphPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final angle = progress * math.pi * 2 * 0.15; // Slow auto-rotate

    // Define 8 node positions (relative to center)
    final relativePositions = [
      const Offset(0, -80), // Grandfather
      const Offset(-50, -40), // Grandmother
      const Offset(50, -40), // Father
      const Offset(-80, 20), // Mother
      const Offset(20, 20), // Uncle
      const Offset(80, 20), // Aunt
      const Offset(-40, 70), // You
      const Offset(40, 70), // Sibling
    ];

    // Apply rotation
    final rotatedPositions = relativePositions.map((p) {
      final rx = p.dx * math.cos(angle) - p.dy * math.sin(angle);
      final ry = p.dx * math.sin(angle) + p.dy * math.cos(angle);
      return Offset(cx + rx, cy + ry);
    }).toList();

    // Define edges (connections)
    const edges = [
      (0, 1),
      (0, 2),
      (1, 3),
      (2, 4),
      (2, 5),
      (3, 6),
      (4, 7),
      (6, 7),
    ];

    // Draw edges
    final edgePaint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.25)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      canvas.drawLine(
        rotatedPositions[edge.$1],
        rotatedPositions[edge.$2],
        edgePaint,
      );
    }

    // Draw nodes
    for (int i = 0; i < rotatedPositions.length; i++) {
      final node = rotatedPositions[i];
      final pulsePhase = (progress * 3 + i * 0.3) % 1.0;
      final pulseScale = 1.0 + 0.1 * math.sin(pulsePhase * math.pi * 2);
      final radius = 8.0 * pulseScale;

      // Glow
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            KinrelColors.orange.withValues(alpha: 0.2),
            Colors.transparent,
          ],
          radius: 0.5,
        ).createShader(Rect.fromCircle(center: node, radius: radius * 3));

      canvas.drawCircle(node, radius * 3, glowPaint);

      // Fill
      final isYou = i == 6;
      final fillPaint = Paint()
        ..color = isYou ? KinrelColors.amber : KinrelColors.orange;
      canvas.drawCircle(node, radius, fillPaint);

      // Border
      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawCircle(node, radius, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FamilyGraphPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════
// Onboarding Page 4 — "Find Any Relationship Instantly"
// Two nodes on opposite sides with animated dotted path
// Relationship label appears with particle trail
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingPage4 extends StatefulWidget {
  const _OnboardingPage4({required this.isActive});
  final bool isActive;

  @override
  State<_OnboardingPage4> createState() => _OnboardingPage4State();
}

class _OnboardingPage4State extends State<_OnboardingPage4>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Path Finding Illustration ───────────────────────────
          SizedBox(
            height: 260,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Glow
                Container(
                  width: 280,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.circular(20),
                    gradient: RadialGradient(
                      colors: [
                        KinrelColors.orange.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      radius: 0.8,
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) {
                    return CustomPaint(
                      size: const Size(300, 240),
                      painter: _PathFinderPainter(_controller.value),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // ── Headline ────────────────────────────────────────────
          const Text(
                'Find Any Relationship Instantly',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                  height: 1.2,
                ),
              )
              .animate(target: widget.isActive ? 1 : 0)
              .fadeIn(duration: 500.ms, delay: 200.ms)
              .slideY(begin: 0.15, end: 0),

          const SizedBox(height: 16),

          // ── Body ────────────────────────────────────────────────
          const Text(
                "Select any two family members — Kinrel's AI calculates the exact relationship name in your language. Even 5th cousins twice removed.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFFC9B4A8),
                  height: 1.55,
                ),
              )
              .animate(target: widget.isActive ? 1 : 0)
              .fadeIn(duration: 500.ms, delay: 400.ms),
        ],
      ),
    );
  }
}

/// Custom painter for the path-finding illustration on Page 4
/// Two nodes with animated dotted path connecting them
/// Relationship label appears when path is complete
class _PathFinderPainter extends CustomPainter {
  _PathFinderPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final leftNode = Offset(50, size.height / 2);
    final rightNode = Offset(size.width - 50, size.height / 2);

    // Draw progress (path draws in cyclically)
    final drawProgress = (progress * 1.5).clamp(0.0, 1.0);
    final pathMidY = size.height / 2;

    // Bezier control points for a curved path
    final cp1 = Offset(size.width * 0.35, pathMidY - 60);
    final cp2 = Offset(size.width * 0.65, pathMidY + 60);
    final path = Path();
    path.moveTo(leftNode.dx, leftNode.dy);
    path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, rightNode.dx, rightNode.dy);

    // Draw dotted path with animation
    final pathPaint = Paint()
      ..color = KinrelColors.orange.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Measure path and draw up to drawProgress
    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      final extractedPath = metric.extractPath(0, metric.length * drawProgress);
      canvas.drawPath(_dashPath(extractedPath, 6, 4), pathPaint);
    }

    // Particle trail along the path
    if (drawProgress > 0.1) {
      for (final metric in pathMetrics) {
        final particleT = (progress * 2) % 1.0;
        final tangent = metric.getTangentForOffset(
          metric.length * particleT.clamp(0.0, drawProgress),
        );

        if (tangent != null) {
          final pos = tangent.position;

          // Glow
          final glowPaint = Paint()
            ..shader = RadialGradient(
              colors: [
                KinrelColors.orange.withValues(alpha: 0.5),
                Colors.transparent,
              ],
              radius: 0.5,
            ).createShader(Rect.fromCircle(center: pos, radius: 16));

          canvas.drawCircle(pos, 16, glowPaint);
          canvas.drawCircle(pos, 4, Paint()..color = KinrelColors.amber);
        }
      }
    }

    // Draw left node ("You")
    _drawNode(canvas, leftNode, 'You');
    // Draw right node ("चाचा")
    _drawNode(canvas, rightNode, 'चाचा');

    // Relationship label that appears after path is drawn
    if (drawProgress > 0.7) {
      final labelAlpha = ((drawProgress - 0.7) / 0.3).clamp(0.0, 1.0);
      final labelCenter = Offset(size.width / 2, pathMidY + 80);

      final labelPaint = Paint()
        ..color = const Color(0xFF202338).withValues(alpha: 0.9 * labelAlpha);
      final labelBorderPaint = Paint()
        ..color = KinrelColors.orange.withValues(alpha: 0.3 * labelAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      final textSpan = TextSpan(
        children: [
          TextSpan(
            text: 'चाचा भतीजा',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: KinrelColors.orange.withValues(alpha: labelAlpha),
            ),
          ),
          TextSpan(
            text: "\n(Father's brother's son)",
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: const Color(0xFFC9B4A8).withValues(alpha: labelAlpha),
            ),
          ),
        ],
      );

      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 200);

      final labelRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: labelCenter,
          width: textPainter.width + 24,
          height: textPainter.height + 16,
        ),
        const Radius.circular(10),
      );

      canvas.drawRRect(labelRect, labelPaint);
      canvas.drawRRect(labelRect, labelBorderPaint);
      textPainter.paint(
        canvas,
        Offset(
          labelCenter.dx - textPainter.width / 2,
          labelCenter.dy - textPainter.height / 2,
        ),
      );
    }
  }

  void _drawNode(Canvas canvas, Offset center, String label) {
    // Glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          KinrelColors.orange.withValues(alpha: 0.3),
          Colors.transparent,
        ],
        radius: 0.5,
      ).createShader(Rect.fromCircle(center: center, radius: 40));

    canvas.drawCircle(center, 40, glowPaint);

    // Fill
    canvas.drawCircle(center, 16, Paint()..color = KinrelColors.orange);

    // Border
    canvas.drawCircle(
      center,
      16,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Label below node
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFFC9B4A8),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy + 24));
  }

  /// Creates a dashed version of a path
  Path _dashPath(Path source, double dashWidth, double dashGap) {
    final result = Path();
    final metrics = source.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      bool draw = true;
      while (distance < metric.length) {
        final length = draw ? dashWidth : dashGap;
        if (distance + length > metric.length) {
          if (draw) {
            result.addPath(
              metric.extractPath(distance, metric.length),
              Offset.zero,
            );
          }
          break;
        }
        if (draw) {
          result.addPath(
            metric.extractPath(distance, distance + length),
            Offset.zero,
          );
        }
        distance += length;
        draw = !draw;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _PathFinderPainter oldDelegate) => true;
}

