import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/dk_components.dart';

class FamilyListScreen extends ConsumerStatefulWidget {
  const FamilyListScreen({super.key});

  @override
  ConsumerState<FamilyListScreen> createState() => _FamilyListScreenState();
}

class _FamilyListScreenState extends ConsumerState<FamilyListScreen> {
  @override
  Widget build(BuildContext context) {
    final familiesAsync = ref.watch(familyListProvider);

    return DKScaffold(
      body: familiesAsync.when(
        loading: () => _buildLoadingState(),
        error: (error, _) => DKErrorState(
          message: 'Failed to load families',
          onRetry: () => ref.invalidate(familyListProvider),
        ),
        data: (families) {
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: _Header(familyCount: families.length),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Join Family card
              SliverToBoxAdapter(
                child: _JoinFamilyCard(
                  onJoin: () => _showJoinFamilyDialog(context),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // Family cards or empty state
              if (families.isEmpty)
                SliverToBoxAdapter(
                  child: DKEmptyState(
                    icon: Icons.family_restroom_rounded,
                    title: 'No Families Yet',
                    subtitle:
                        'Create your first family tree to start exploring relationships and kinship terms.',
                    actionLabel: 'Create Family',
                    onAction: () => context.push('/families/create'),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.base),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final family = families[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _FamilyCard(
                            family: family,
                            index: index,
                            onTap: () =>
                                context.push('/family/${family.id}'),
                          ),
                        );
                      },
                      childCount: families.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
      floatingActionButton: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: DKColors.brandGold,
            width: 2.5,
          ),
          color: DKColors.brandPurple.withValues(alpha: 0.1),
        ),
        child: IconButton(
          onPressed: () => context.push('/families/create'),
          icon: const Icon(Icons.add_rounded, size: 28),
          color: DKColors.brandPurple,
        ),
      )
          .animate(onPlay: (c) => c.forward())
          .fadeIn(duration: 500.ms)
          .scale(
            begin: const Offset(0.5, 0.5),
            end: const Offset(1.0, 1.0),
            duration: 400.ms,
            curve: Curves.easeOutBack,
          ),
    );
  }

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        const SizedBox(height: 60),
        Row(
          children: [
            DKLoadingShimmer(width: 160, height: 28),
            const SizedBox(width: 10),
            DKLoadingShimmer(width: 36, height: 24, radius: 12),
          ],
        ),
        const SizedBox(height: 20),
        DKLoadingShimmer(width: double.infinity, height: 72, radius: KinrelRadius.card),
        const SizedBox(height: 12),
        DKLoadingShimmer(width: double.infinity, height: 72, radius: KinrelRadius.card),
        const SizedBox(height: 12),
        DKLoadingShimmer(width: double.infinity, height: 72, radius: KinrelRadius.card),
      ],
    );
  }

  void _showJoinFamilyDialog(BuildContext context) {
    final codeController = TextEditingController();
    final isLight = DKColors.isLight(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DKColors.cardColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: BorderSide(color: DKColors.borderColor(context)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DKColors.brandPurple.withValues(alpha: 0.15),
              ),
              child: Icon(Icons.link_rounded,
                  color: DKColors.brandPurple, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Join Family',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                color: DKColors.textPrimary(context),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the family code shared with you to join an existing family.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: DKColors.textSecondary(context),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 14,
                color: DKColors.textPrimary(context),
              ),
              decoration: InputDecoration(
                hintText: 'e.g., sharma-family-2a3b',
                hintStyle: TextStyle(
                  color: DKColors.textSecondary(context).withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: DKColors.elevatedColor(context),
                prefixIcon: Icon(Icons.search_rounded,
                    color: DKColors.textSecondary(context), size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.input),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: DKColors.textSecondary(context))),
          ),
          DKButton(
            label: 'Join',
            variant: DKButtonVariant.primary,
            size: DKButtonSize.sm,
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Join family coming soon!')),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int familyCount;
  const _Header({required this.familyCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.md,
      ),
      child: Row(
        children: [
          Text(
            'My Families',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: DKColors.textPrimary(context),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: DKColors.brandPurple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$familyCount',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: DKColors.brandPurple,
              ),
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 300.ms)
        .slideX(begin: -0.1, end: 0, duration: 300.ms);
  }
}

// ── Join Family Card ─────────────────────────────────────────────

class _JoinFamilyCard extends StatelessWidget {
  final VoidCallback onJoin;
  const _JoinFamilyCard({required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: DKCard(
        borderColor: DKColors.brandGold.withValues(alpha: 0.3),
        backgroundColor: DKColors.brandGold.withValues(alpha: 0.06),
        onTap: onJoin,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DKColors.brandGold.withValues(alpha: 0.15),
              ),
              child: Icon(Icons.mail_outline_rounded,
                  color: DKColors.brandGold, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Join Family by Code',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: DKColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Enter a family code to join an existing family',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: DKColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: DKColors.brandGold),
          ],
        ),
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: 400.ms, delay: 100.ms);
  }
}

// ── Family Card ──────────────────────────────────────────────────

class _FamilyCard extends ConsumerWidget {
  final Family family;
  final int index;
  final VoidCallback onTap;

  const _FamilyCard({
    required this.family,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberCountAsync =
        ref.watch(familyMemberCountProvider(family.id));
    final languageName = family.primaryLanguage != null
        ? SupportedLanguage.fromCode(family.primaryLanguage!).name
        : 'English';

    final slug = family.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final idSuffix =
        family.id.length >= 4 ? family.id.substring(0, 4) : family.id;
    final familyCode = 'kinrel.co/f/$slug-$idSuffix';

    return DKCard(
      borderColor: DKColors.brandPurple.withValues(alpha: 0.2),
      onTap: onTap,
      child: Row(
        children: [
          // Purple gradient avatar with initial
          DKAvatar(
            initials: family.name.isNotEmpty
                ? family.name[0].toUpperCase()
                : 'F',
            size: DKAvatarSize.lg,
            backgroundColor: DKColors.brandPurple,
            borderColor: DKColors.brandGold.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  family.name,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: DKColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  familyCode,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    color: DKColors.textSecondary(context).withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Member count
                    memberCountAsync.when(
                      data: (count) => DKStatChip(
                        icon: Icons.people_outline_rounded,
                        value: '$count',
                        label: 'members',
                        color: DKColors.brandPurple,
                      ),
                      loading: () => const SizedBox(width: 80, height: 20),
                      error: (_, __) => const SizedBox(width: 80, height: 20),
                    ),
                    const SizedBox(width: 10),
                    // Language
                    Icon(Icons.translate_rounded,
                        size: 13,
                        color: DKColors.textSecondary(context).withValues(alpha: 0.6)),
                    const SizedBox(width: 4),
                    Text(
                      languageName,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        color: DKColors.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Icon(Icons.chevron_right,
              color: DKColors.brandPurple.withValues(alpha: 0.6)),
        ],
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: 400.ms,
          delay: Duration(milliseconds: 100 + index * 60),
        )
        .slideX(begin: 0.1, end: 0, duration: 400.ms);
  }
}
