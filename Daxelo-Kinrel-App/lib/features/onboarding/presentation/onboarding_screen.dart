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

  final _pages = [
    _OnboardingPageData(
      icon: Icons.diversity_3_rounded,
      title: '523+ Indian Relationships',
      subtitle: 'From Bua to Mausi, Chacha to Jethani — discover every kinship term across Indian culture.',
      gradient: [KinrelColors.orange, KinrelColors.amber],
    ),
    _OnboardingPageData(
      icon: Icons.translate_rounded,
      title: '14 Indian Languages',
      subtitle: 'Hindi, Bengali, Tamil, Telugu, Marathi, and 9 more — with native scripts and transliterations.',
      gradient: [KinrelColors.amber, const Color(0xFFF5C842)],
    ),
    _OnboardingPageData(
      icon: Icons.account_tree_rounded,
      title: 'Family Graph Intelligence',
      subtitle: 'Map your family tree, find relationship paths, and explore connections like never before.',
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

              // Page content
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (context, index) {
                    final page = _pages[index];
                    return _OnboardingPageContent(data: page);
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
                    ...List.generate(_pages.length, (i) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == i ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == i
                          ? KinrelColors.orange
                          : KinrelColors.textDim.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ).animate(target: _currentPage == i ? 1 : 0)
                      .scale(duration: 300.ms)),

                    const SizedBox(width: 32),

                    // Next / Get Started button
                    FilledButton(
                      onPressed: _onNext,
                      style: FilledButton.styleFrom(
                        backgroundColor: KinrelColors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(KinrelSpacing.radiusSm),
                        ),
                      ),
                      child: Text(
                        _currentPage == _pages.length - 1 ? 'Get Started' : 'Next',
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

class _OnboardingPageData {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;

  const _OnboardingPageData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
  });
}

class _OnboardingPageContent extends StatelessWidget {
  final _OnboardingPageData data;

  const _OnboardingPageContent({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: data.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: data.gradient.first.withValues(alpha: 0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              data.icon,
              size: 56,
              color: Colors.white,
            ),
          ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),

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
          ).animate().fadeIn(duration: 500.ms, delay: 200.ms).slideY(begin: 0.2, end: 0),

          const SizedBox(height: 16),

          // Subtitle
          Text(
            data.subtitle,
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
