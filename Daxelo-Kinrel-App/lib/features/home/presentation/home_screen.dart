import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/kinship/kinship_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/kinrel_icon.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            slivers: [
              // App bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base,
                    vertical: KinrelSpacing.md,
                  ),
                  child: Row(
                    children: [
                      const KinrelIcon(size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Welcome${user?.email != null ? '' : ''}!',
                          style: const TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                      ),
                      CircleAvatar(
                        backgroundColor: KinrelColors.orange.withValues(alpha: 0.2),
                        child: Icon(
                          Icons.person,
                          color: KinrelColors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Search bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
                  child: GestureDetector(
                    onTap: () => context.go('/search'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
                        border: Border.all(color: KinrelColors.darkSurface.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: KinrelColors.textDim, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            'Search 523+ relationships...',
                            style: TextStyle(
                              color: KinrelColors.textDim,
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // Stats row
              SliverToBoxAdapter(
                child: metaAsync.when(
                  data: (meta) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
                    child: Row(
                      children: [
                        _StatChip(
                          icon: Icons.diversity_3,
                          label: '${meta['totalRelationships']}+',
                          subtitle: 'Relationships',
                        ),
                        const SizedBox(width: 12),
                        _StatChip(
                          icon: Icons.translate,
                          label: '${(meta['supportedLanguages'] as List?)?.length ?? 14}',
                          subtitle: 'Languages',
                        ),
                        const SizedBox(width: 12),
                        _StatChip(
                          icon: Icons.category,
                          label: '${(meta['categories'] as List?)?.length ?? 9}',
                          subtitle: 'Categories',
                        ),
                      ],
                    ),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),

              // Quick actions
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
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

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(KinrelSpacing.base),
                  child: Row(
                    children: [
                      _QuickActionCard(
                        icon: Icons.family_restroom,
                        label: 'Create Family',
                        color: KinrelColors.orange,
                        onTap: () => context.go('/families'),
                      ),
                      const SizedBox(width: 12),
                      _QuickActionCard(
                        icon: Icons.search,
                        label: 'Explore Kinship',
                        color: KinrelColors.amber,
                        onTap: () => context.go('/search'),
                      ),
                      const SizedBox(width: 12),
                      _QuickActionCard(
                        icon: Icons.route,
                        label: 'Find Path',
                        color: KinrelColors.ember,
                        onTap: () => context.go('/families'),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),

              // Categories
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
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
                      TextButton(
                        onPressed: () => context.go('/search'),
                        child: Text(
                          'See All',
                          style: TextStyle(color: KinrelColors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Category chips
              metaAsync.when(
                data: (meta) {
                  final categories = (meta['categories'] as List?)?.cast<String>() ?? [];
                  return SliverToBoxAdapter(
                    child: SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
                        itemCount: categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final cat = categories[index];
                          return ActionChip(
                            label: Text(
                              cat.replaceAll('_', ' ').toUpperCase(),
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            backgroundColor: KinrelColors.darkElevated,
                            side: BorderSide(color: KinrelColors.orange.withValues(alpha: 0.3)),
                            labelStyle: TextStyle(color: KinrelColors.textSilver),
                            onPressed: () {
                              ref.read(kinshipCategoryProvider.notifier).state = cat;
                              context.go('/search');
                            },
                          );
                        },
                      ),
                    ),
                  );
                },
                loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;

  const _StatChip({required this.icon, required this.label, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
          border: Border.all(color: KinrelColors.darkSurface.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: KinrelColors.orange, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(KinrelSpacing.radiusMd),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textSilver,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
