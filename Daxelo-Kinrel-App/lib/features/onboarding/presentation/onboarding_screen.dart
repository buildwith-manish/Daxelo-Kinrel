import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../shared/widgets/dk_components.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  final _pages = [
    _OnboardingPageData(
      icon: Icons.account_tree_rounded,
      title: 'Discover Your Roots',
      tagline: 'Build and visualize your family tree with intuitive tools and beautiful charts',
      gradient: [KinrelColors.purple, KinrelColors.violet],
    ),
    _OnboardingPageData(
      icon: Icons.menu_book_rounded,
      title: '5300+ Kinship Terms',
      tagline: 'Explore Indian kinship terminology across 15 languages — from Hindi to Tamil',
      gradient: [KinrelColors.violet, KinrelColors.deepPurple],
    ),
    _OnboardingPageData(
      icon: Icons.diversity_3_rounded,
      title: 'Connect Your Family',
      tagline: 'Invite relatives, share memories, and grow your family network together',
      gradient: [KinrelColors.coral, KinrelColors.purple],
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
        duration: Duration(milliseconds: 400),
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
    return DKScaffold(
      gradient: KinrelGradients.splashGradient,
      body: Column(
        children: [
          // ── Skip button ──────────────────────────────────────────────
          Align(
            alignment: Alignment.topRight,
            child: TextButton(
              onPressed: _onSkip,
              child: Text(
                'Skip',
                style: TextStyle(
                  color: KinrelColors.textWhite.withValues(alpha: 0.7),
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // ── KINREL branding ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
            child: ShaderMask(
              shaderCallback: (bounds) =>
                  KinrelGradients.wordmarkGradient.createShader(bounds),
              child: Text(
                'KINREL',
                style: const TextStyle(
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

          // ── Page content ─────────────────────────────────────────────
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

          // ── Page indicators + button ─────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
              KinrelSpacing.base,
              0,
              KinrelSpacing.base,
              KinrelSpacing.xxl + 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dot indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == i ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == i
                            ? KinrelColors.textWhite
                            : KinrelColors.textWhite.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 24),

                // Get Started / Next button
                DKButton(
                  label: _currentPage == _pages.length - 1
                      ? 'Get Started'
                      : 'Next',
                  variant: DKButtonVariant.gradient,
                  gradient: const LinearGradient(
                    colors: [KinrelColors.purple, KinrelColors.coral],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  fullWidth: true,
                  size: DKButtonSize.lg,
                  onPressed: _onNext,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data Model ────────────────────────────────────────────────────

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.tagline,
    required this.gradient,
  });

  final IconData icon;
  final String title;
  final String tagline;
  final List<Color> gradient;

}

// ── Page Content ──────────────────────────────────────────────────

class _OnboardingPageContent extends StatelessWidget {
  const _OnboardingPageContent({
    required this.data,
    required this.isActive,
  });

  final _OnboardingPageData data;
  final bool isActive;


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Illustration with glowing icon ─────────────────────────
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  data.gradient.first.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
                radius: 0.6,
              ),
              boxShadow: [
                BoxShadow(
                  color: data.gradient.first.withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Icon(
                data.icon,
                size: 64,
                color: Colors.white,
              ),
            ),
          )
              .animate(target: isActive ? 1 : 0)
              .scale(
                duration: 600.ms,
                curve: Curves.elasticOut,
                begin: const Offset(0.8, 0.8),
                end: const Offset(1, 1),
              )
              .fadeIn(duration: 400.ms),

          const SizedBox(height: 40),

          // ── Title ──────────────────────────────────────────────────
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
              .animate(target: isActive ? 1 : 0)
              .fadeIn(duration: 500.ms, delay: 200.ms)
              .slideY(begin: 0.2, end: 0),

          const SizedBox(height: 16),

          // ── Tagline ────────────────────────────────────────────────
          Text(
            data.tagline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 16,
              color: KinrelColors.textWhite.withValues(alpha: 0.75),
              height: 1.5,
            ),
          ).animate(target: isActive ? 1 : 0).fadeIn(
                duration: 500.ms,
                delay: 400.ms,
              ),
        ],
      ),
    );
  }
}
