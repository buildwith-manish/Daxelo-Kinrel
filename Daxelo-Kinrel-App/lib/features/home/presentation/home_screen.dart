import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/kinrel_icon.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _staggerController.forward();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  CurvedAnimation _sectionCurve(int sectionIndex) {
    final delays = [0.0, 0.10, 0.20, 0.30, 0.40];
    final start = delays[sectionIndex];
    const duration = 0.60;
    return CurvedAnimation(
      parent: _staggerController,
      curve: Interval(start, (start + duration).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metaAsync = ref.watch(kinshipMetaProvider);
    final user = ref.watch(currentUserProvider);

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
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Header ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: _StaggeredSection(
                  animation: _sectionCurve(0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base,
                      vertical: KinrelSpacing.xl,
                    ),
                    child: Row(
                      children: [
                        const KinrelIcon(size: KinrelSpacing.logoSm),
                        const SizedBox(width: KinrelSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Good day 👋',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: KinrelColors.textDim,
                                ),
                              ),
                              Text(
                                user?.email?.split('@').first ?? 'Explorer',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.displayFont,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: KinrelColors.textWhite,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        PressDown(
                          onTap: () => context.go('/settings'),
                          child: Container(
                            width: KinrelSpacing.iconButtonSize,
                            height: KinrelSpacing.iconButtonSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: KinrelColors.orange.withValues(alpha: 0.4),
                                width: 2,
                              ),
                              color: KinrelColors.darkElevated,
                            ),
                            child: Icon(
                              Icons.person_outline,
                              color: KinrelColors.orange,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Hero Banner ─────────────────────────────────────
              SliverToBoxAdapter(
                child: _StaggeredSection(
                  animation: _sectionCurve(0),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base),
                    child: _HeroBanner(metaAsync: metaAsync),
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                  child: SizedBox(height: KinrelSpacing.xxl)),

              // ── Search Bar ──────────────────────────────────────
              SliverToBoxAdapter(
                child: _StaggeredSection(
                  animation: _sectionCurve(1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base),
                    child: PressDown(
                      onTap: () => context.go('/search'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: KinrelColors.darkElevated,
                          borderRadius:
                              BorderRadius.circular(KinrelSpacing.radiusMd),
                          border: Border.all(
                            color: KinrelColors.darkSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search,
                                color: KinrelColors.orange, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Search 5,359 relationships...',
                                style: TextStyle(
                                  color: KinrelColors.textDim,
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    KinrelColors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: KinrelColors.orange
                                      .withValues(alpha: 0.25),
                                ),
                              ),
                              child: Text(
                                '⌘K',
                                style: TextStyle(
                                  fontFamily: KinrelTypography.monoFont,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: KinrelColors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                  child: SizedBox(height: KinrelSpacing.xxl)),

              // ── Stats Row ───────────────────────────────────────
              SliverToBoxAdapter(
                child: _StaggeredSection(
                  animation: _sectionCurve(2),
                  child: metaAsync.when(
                    data: (meta) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: KinrelSpacing.base),
                      child: Row(
                        children: [
                          _StatCard(
                            icon: Icons.diversity_3,
                            label:
                                '${meta['totalRelationships'] ?? 5359}'.toString(),
                            subtitle: 'Relationships',
                            accentColor: KinrelColors.orange,
                          ),
                          const SizedBox(width: 10),
                          _StatCard(
                            icon: Icons.translate,
                            label:
                                '${(meta['supportedLanguages'] as List?)?.length ?? 15}',
                            subtitle: 'Languages',
                            accentColor: KinrelColors.amber,
                          ),
                          const SizedBox(width: 10),
                          _StatCard(
                            icon: Icons.account_tree,
                            label: '4',
                            subtitle: 'Generations',
                            accentColor: KinrelColors.success,
                          ),
                        ],
                      ),
                    ),
                    loading: () => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: KinrelSpacing.base),
                      child: Row(
                        children: List.generate(
                            3,
                            (_) => Expanded(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 5),
                                    child: _ShimmerBlock(
                                      height: 88,
                                      borderRadius:
                                          BorderRadius.circular(KinrelSpacing.radiusMd),
                                    ),
                                  ),
                                )),
                      ),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                  child: SizedBox(height: KinrelSpacing.xxxl)),

              // ── Quick Actions ───────────────────────────────────
              SliverToBoxAdapter(
                child: _StaggeredSection(
                  animation: _sectionCurve(3),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base),
                    child: Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: _StaggeredSection(
                  animation: _sectionCurve(3),
                  child: Padding(
                    padding: const EdgeInsets.all(KinrelSpacing.base),
                    child: Row(
                      children: [
                        _QuickActionCard(
                          icon: Icons.group_add_rounded,
                          title: 'Create Family',
                          subtitle: 'Build your tree',
                          color: KinrelColors.orange,
                          onTap: () => context.go('/families'),
                        ),
                        const SizedBox(width: 10),
                        _QuickActionCard(
                          icon: Icons.explore_rounded,
                          title: 'Explore Kinship',
                          subtitle: '15 languages',
                          color: KinrelColors.amber,
                          onTap: () => context.go('/search'),
                        ),
                        const SizedBox(width: 10),
                        _QuickActionCard(
                          icon: Icons.route_rounded,
                          title: 'Find Path',
                          subtitle: 'How are we related?',
                          color: KinrelColors.info,
                          onTap: () => context.go('/families'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                  child: SizedBox(height: KinrelSpacing.xxxl)),

              // ── Categories ──────────────────────────────────────
              SliverToBoxAdapter(
                child: _StaggeredSection(
                  animation: _sectionCurve(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Categories',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                        PressDown(
                          onTap: () => context.go('/search'),
                          child: Text(
                            'See All',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: KinrelColors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              metaAsync.when(
                data: (meta) {
                  final categories =
                      (meta['categories'] as List?)?.cast<String>() ?? [];
                  return SliverToBoxAdapter(
                    child: _StaggeredSection(
                      animation: _sectionCurve(4),
                      child: SizedBox(
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: KinrelSpacing.base),
                          itemCount: categories.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final cat = categories[index];
                            return PressDown(
                              onTap: () {
                                ref
                                    .read(kinshipCategoryProvider.notifier)
                                    .state = cat;
                                context.go('/search');
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: KinrelColors.darkElevated,
                                  borderRadius: BorderRadius.circular(
                                      KinrelSpacing.radiusSm),
                                  border: Border.all(
                                    color: KinrelColors.orange
                                        .withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Text(
                                  cat.replaceAll('_', ' ').toUpperCase(),
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: KinrelColors.textSilver,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                loading: () => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.base, vertical: 8),
                    child: SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: List.generate(
                          6,
                          (_) => Padding(
                            padding:
                                const EdgeInsets.only(right: 8),
                            child: _ShimmerBlock(
                              width: 100,
                              height: 44,
                              borderRadius: BorderRadius.circular(
                                  KinrelSpacing.radiusSm),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                error: (_, __) =>
                    const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// HERO BANNER
// ══════════════════════════════════════════════════════════════════════════

class _HeroBanner extends ConsumerWidget {
  final AsyncValue<Map<String, dynamic>> metaAsync;
  const _HeroBanner({required this.metaAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PressDown(
      onTap: () => context.go('/search'),
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusLg),
          gradient: LinearGradient(
            colors: [
              KinrelColors.darkElevated,
              KinrelColors.darkCard,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Radial glow
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      KinrelColors.orange.withValues(alpha: 0.15),
                      KinrelColors.orange.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(KinrelSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: KinrelColors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: KinrelColors.orange.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🇮🇳', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        metaAsync.when(
                          data: (meta) => Text(
                            '${(meta['supportedLanguages'] as List?)?.length ?? 15} Languages',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: KinrelColors.orange,
                            ),
                          ),
                          loading: () => _ShimmerBlock(
                            width: 80,
                            height: 12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          error: (_, __) => Text(
                            '15 Languages',
                            style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: KinrelColors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Headline + CTA row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Discover your\nfamily roots',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: KinrelColors.textWhite,
                            height: 1.2,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: KinrelColors.igniteGradient,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: KinrelColors.orange.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Explore',
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward,
                                size: 16, color: Colors.white),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// STAT CARD
// ══════════════════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color accentColor;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(KinrelSpacing.md),
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Icon pill
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// QUICK ACTION CARD
// ══════════════════════════════════════════════════════════════════════════

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: PressDown(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.18),
                color.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            children: [
              // Icon in rounded container
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// STAGGERED SECTION (Fade + Slide-Up)
// ══════════════════════════════════════════════════════════════════════════

class _StaggeredSection extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _StaggeredSection({
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// PRESS DOWN (Scale feedback on tap)
// ══════════════════════════════════════════════════════════════════════════

class PressDown extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const PressDown({super.key, required this.child, this.onTap});

  @override
  State<PressDown> createState() => _PressDownState();
}

class _PressDownState extends State<PressDown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _controller.forward();
  void _onTapUp(TapUpDetails _) => _controller.reverse();
  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? _onTapDown : null,
      onTapUp: widget.onTap != null ? _onTapUp : null,
      onTapCancel: widget.onTap != null ? _onTapCancel : null,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SHIMMER (Custom — no external package)
// ══════════════════════════════════════════════════════════════════════════

class _ShimmerBlock extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const _ShimmerBlock({
    this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  State<_ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<_ShimmerBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + (_controller.value * 2.0), 0),
              end: Alignment(1.0 + (_controller.value * 2.0), 0),
              colors: [
                KinrelColors.darkElevated,
                KinrelColors.darkSurface.withValues(alpha: 0.6),
                KinrelColors.darkElevated,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}
