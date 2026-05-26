import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/storage/secure_storage.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  final _pages = const [
    _OnboardingPageData(
      icon: Icons.hub_rounded,
      illustration: _IllustrationType.familyNodes,
      title: 'Your Family, Your Story',
      tagline: 'Build your family graph, discover your roots',
      gradient: [KinrelColors.orange, KinrelColors.amber],
    ),
    _OnboardingPageData(
      icon: Icons.people_outline_rounded,
      illustration: _IllustrationType.relationshipLinks,
      title: 'Smart Relationships',
      tagline:
          'Connect family members with intelligent Indian kinship mapping',
      gradient: [KinrelColors.amber, Color(0xFFF5C842)],
    ),
    _OnboardingPageData(
      icon: Icons.share_rounded,
      illustration: _IllustrationType.familyShare,
      title: 'Share & Grow',
      tagline:
          'Invite family members to collaborate on your family tree',
      gradient: [KinrelColors.ember, KinrelColors.orange],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _onSkip() => _completeOnboarding();

  Future<void> _completeOnboarding() async {
    final storage = SecureStorageService();
    await storage.setOnboardingComplete(true);
    if (mounted) context.go('/sign-in');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [KinrelColors.darkBackground, KinrelColors.darkCard],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _onSkip,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: KinrelColors.textSilver,
                      fontFamily: KinrelTypography.bodyFont,
                    ),
                  ),
                ),
              ),

              // KINREL branding
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
                child: ShaderMask(
                  shaderCallback: (bounds) => KinrelGradients.wordmarkGradient
                      .createShader(bounds),
                  child: Text(
                    'KINREL',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Page content
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return _OnboardingPageContent(
                      data: page,
                      isActive: _currentPage == index,
                    );
                  },
                ),
              ),

              // Page indicators + button
              Padding(
                padding: const EdgeInsets.all(KinrelSpacing.base),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Dots
                    ...List.generate(
                      _pages.length,
                      (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? KinrelColors.orange
                              : KinrelColors.textDim.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                          .animate(target: _currentPage == i ? 1 : 0)
                          .scale(duration: 300.ms),
                    ),

                    const SizedBox(width: 32),

                    // Next / Get Started button
                    FilledButton(
                      onPressed: _onNext,
                      style: FilledButton.styleFrom(
                        backgroundColor: KinrelColors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(KinrelSpacing.radiusSm),
                        ),
                      ),
                      child: Text(
                        _currentPage == _pages.length - 1
                            ? 'Get Started'
                            : 'Next',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Data Model ────────────────────────────────────────────────────

enum _IllustrationType { familyNodes, relationshipLinks, familyShare }

class _OnboardingPageData {
  final IconData icon;
  final _IllustrationType illustration;
  final String title;
  final String tagline;
  final List<Color> gradient;

  const _OnboardingPageData({
    required this.icon,
    required this.illustration,
    required this.title,
    required this.tagline,
    required this.gradient,
  });
}

// ── Page Content ──────────────────────────────────────────────────

class _OnboardingPageContent extends StatelessWidget {
  final _OnboardingPageData data;
  final bool isActive;

  const _OnboardingPageContent({
    required this.data,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration
          SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: _FamilyGraphIllustration(
                type: data.illustration,
                gradient: data.gradient,
              ),
            ),
          ).animate().scale(
                duration: 600.ms,
                curve: Curves.elasticOut,
              ),

          const SizedBox(height: 40),

          // Title
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
              height: 1.2,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 200.ms)
              .slideY(begin: 0.2, end: 0),

          const SizedBox(height: 16),

          // Tagline
          Text(
            data.tagline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 16,
              color: KinrelColors.textSilver,
              height: 1.5,
            ),
          ).animate().fadeIn(duration: 500.ms, delay: 400.ms),
        ],
      ),
    );
  }
}

// ── Custom Illustration Painter ───────────────────────────────────

class _FamilyGraphIllustration extends CustomPainter {
  final _IllustrationType type;
  final List<Color> gradient;

  _FamilyGraphIllustration({
    required this.type,
    required this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final nodeRadius = size.width * 0.06;

    switch (type) {
      case _IllustrationType.familyNodes:
        _paintFamilyNodes(canvas, size, cx, cy, nodeRadius);
      case _IllustrationType.relationshipLinks:
        _paintRelationshipLinks(canvas, size, cx, cy, nodeRadius);
      case _IllustrationType.familyShare:
        _paintFamilyShare(canvas, size, cx, cy, nodeRadius);
    }
  }

  void _paintFamilyNodes(
      Canvas canvas, Size size, double cx, double cy, double r) {
    // Central node (you)
    final centerPaint = Paint()
      ..shader = LinearGradient(
        colors: gradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.5));
    canvas.drawCircle(Offset(cx, cy), r * 1.5, centerPaint);

    // Glow
    final glowPaint = Paint()
      ..color = gradient.first.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(Offset(cx, cy), r * 3, glowPaint);

    // Surrounding nodes (family members)
    final nodePositions = <Offset>[];
    final count = 6;
    final orbitRadius = size.width * 0.3;
    for (int i = 0; i < count; i++) {
      nodePositions.add(Offset(
        cx + orbitRadius * (i.isEven ? 0.8 : 1.0) * (i % 3 == 0 ? 1 : 0.7) *
            (i < 3 ? 1 : -1) *
            (i.isEven ? 1 : 0.85),
        cy + orbitRadius * (i < 3 ? -0.7 : 0.7) *
            ((i % 3 - 1).toDouble()),
      ));
    }

    // Better layout: concentric rings
    nodePositions.clear();
    // Inner ring: 2 nodes
    final innerR = size.width * 0.18;
    for (int i = 0; i < 2; i++) {
      nodePositions.add(Offset(cx + innerR * (i == 0 ? -0.9 : 0.9),
          cy + innerR * (i == 0 ? -0.6 : -0.6)));
    }
    // Outer ring: 4 nodes
    final outerR = size.width * 0.35;
    for (int i = 0; i < 4; i++) {
      nodePositions.add(Offset(
        cx + outerR * 0.9 * (i < 2 ? -1 : 1),
        cy + outerR * 0.7 * (i.isEven ? -1 : 1),
      ));
    }

    // Lines from center to each node
    final linePaint = Paint()
      ..color = gradient.first.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Cross connections
    final crossLinePaint = Paint()
      ..color = gradient.last.withValues(alpha: 0.15)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < nodePositions.length; i++) {
      canvas.drawLine(Offset(cx, cy), nodePositions[i], linePaint);
      if (i > 0 && i < nodePositions.length - 1) {
        canvas.drawLine(
            nodePositions[i], nodePositions[i + 1], crossLinePaint);
      }
    }
    // Connect inner ring
    if (nodePositions.length >= 2) {
      canvas.drawLine(nodePositions[0], nodePositions[1], crossLinePaint);
    }

    // Draw nodes
    final nodePaint = Paint()
      ..color = KinrelColors.darkElevated
      ..style = PaintingStyle.fill;
    final nodeBorderPaint = Paint()
      ..shader = LinearGradient(colors: gradient).createShader(
          Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final pos in nodePositions) {
      canvas.drawCircle(pos, r, nodePaint);
      canvas.drawCircle(pos, r, nodeBorderPaint);
    }

    // Center node icon dot
    final dotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), r * 0.4, dotPaint);
  }

  void _paintRelationshipLinks(
      Canvas canvas, Size size, double cx, double cy, double r) {
    // Two groups connected by a highlighted path
    final leftGroup = <Offset>[];
    final rightGroup = <Offset>[];

    // Left group
    leftGroup.add(Offset(cx - size.width * 0.3, cy - size.height * 0.15));
    leftGroup.add(Offset(cx - size.width * 0.2, cy + size.height * 0.15));
    leftGroup.add(Offset(cx - size.width * 0.35, cy + size.height * 0.05));

    // Right group
    rightGroup.add(Offset(cx + size.width * 0.3, cy - size.height * 0.1));
    rightGroup.add(Offset(cx + size.width * 0.2, cy + size.height * 0.18));
    rightGroup.add(Offset(cx + size.width * 0.35, cy + size.height * 0.1));

    // Intra-group lines
    final faintLine = Paint()
      ..color = gradient.first.withValues(alpha: 0.2)
      ..strokeWidth = 1.2;
    for (int i = 0; i < leftGroup.length; i++) {
      for (int j = i + 1; j < leftGroup.length; j++) {
        canvas.drawLine(leftGroup[i], leftGroup[j], faintLine);
      }
    }
    for (int i = 0; i < rightGroup.length; i++) {
      for (int j = i + 1; j < rightGroup.length; j++) {
        canvas.drawLine(rightGroup[i], rightGroup[j], faintLine);
      }
    }

    // Highlighted link between groups
    final linkPaint = Paint()
      ..shader = LinearGradient(colors: gradient).createShader(
          Rect.fromLTWH(cx - size.width * 0.3, cy, size.width * 0.6, 1))
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(leftGroup[0], rightGroup[0], linkPaint);

    // Animated dash effect - dashed line
    final dashPaint = Paint()
      ..color = gradient.last.withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    _drawDashedLine(canvas, leftGroup[1], rightGroup[1], dashPaint);
    _drawDashedLine(canvas, leftGroup[2], rightGroup[2], dashPaint);

    // Draw nodes
    final nodePaint = Paint()..color = KinrelColors.darkElevated;
    final leftBorderPaint = Paint()
      ..color = gradient.first
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rightBorderPaint = Paint()
      ..color = gradient.last
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final pos in leftGroup) {
      canvas.drawCircle(pos, r, nodePaint);
      canvas.drawCircle(pos, r, leftBorderPaint);
    }
    for (final pos in rightGroup) {
      canvas.drawCircle(pos, r, nodePaint);
      canvas.drawCircle(pos, r, rightBorderPaint);
    }

    // Link icon in center
    final linkBgPaint = Paint()
      ..shader = LinearGradient(colors: gradient).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.8));
    canvas.drawCircle(Offset(cx, cy), r * 1.8, linkBgPaint);

    final iconPaint = Paint()..color = Colors.white;
    // Draw a simple link icon (two overlapping circles)
    canvas.drawCircle(Offset(cx - r * 0.5, cy), r * 0.6, iconPaint);
    canvas.drawCircle(Offset(cx + r * 0.5, cy), r * 0.6, iconPaint);
    // Punch out centers
    final punchPaint = Paint()..color = KinrelColors.orange;
    canvas.drawCircle(Offset(cx - r * 0.5, cy), r * 0.3, punchPaint);
    canvas.drawCircle(Offset(cx + r * 0.5, cy), r * 0.3, punchPaint);
  }

  void _paintFamilyShare(
      Canvas canvas, Size size, double cx, double cy, double r) {
    // Central tree with sharing ripples
    // Draw tree trunk
    final trunkPaint = Paint()
      ..color = gradient.first.withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx, cy + r * 2), Offset(cx, cy - r), trunkPaint);

    // Branches with nodes
    final branches = <Offset>[
      Offset(cx - size.width * 0.2, cy - size.height * 0.15),
      Offset(cx + size.width * 0.2, cy - size.height * 0.15),
      Offset(cx - size.width * 0.3, cy + size.height * 0.05),
      Offset(cx + size.width * 0.3, cy + size.height * 0.05),
    ];

    for (final branch in branches) {
      canvas.drawLine(Offset(cx, cy - r * 0.5), branch, trunkPaint);
    }

    // Ripple circles (sharing effect)
    final ripplePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 1; i <= 3; i++) {
      ripplePaint.color =
          gradient.first.withValues(alpha: 0.3 / i);
      canvas.drawCircle(Offset(cx, cy), r * 2.5 * i, ripplePaint);
    }

    // Node circles at branch ends
    final nodePaint = Paint()..color = KinrelColors.darkElevated;
    final nodeBorderPaint = Paint()
      ..color = gradient.first
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final branch in branches) {
      canvas.drawCircle(branch, r * 0.9, nodePaint);
      canvas.drawCircle(branch, r * 0.9, nodeBorderPaint);
    }

    // Center node
    final centerPaint = Paint()
      ..shader = LinearGradient(colors: gradient)
          .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawCircle(Offset(cx, cy), r * 1.2, centerPaint);

    // Share arrows from center going outward
    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final branch in branches) {
      final dir = Offset(
        (branch.dx - cx) * 0.4,
        (branch.dy - cy) * 0.4,
      );
      final tip = Offset(cx + dir.dx, cy + dir.dy);
      canvas.drawLine(Offset(cx, cy), tip, arrowPaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(covariant _FamilyGraphIllustration oldDelegate) =>
      oldDelegate.type != type || oldDelegate.gradient != gradient;
}
