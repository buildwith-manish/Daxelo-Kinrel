import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/supported_languages.dart';
import '../../../core/family/family_provider.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../core/utils/device_tier.dart';
import '../../../presentation/widgets/skeletons/family_list_skeleton.dart';

class FamilyListScreen extends ConsumerStatefulWidget {
  FamilyListScreen({super.key});

  @override
  ConsumerState<FamilyListScreen> createState() => _FamilyListScreenState();
}

class _FamilyListScreenState extends ConsumerState<FamilyListScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final familiesAsync = ref.watch(familyListProvider);

    return DKScaffold(
      body: familiesAsync.when(
        loading: () => const _FamilyListLoadingWidget(),
        error: (error, _) => DKErrorState(
          message: 'Failed to load families',
          onRetry: () => ref.invalidate(familyListProvider),
        ),
        data: (families) {
          return CustomScrollView(
            cacheExtent: 500,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(child: _Header(familyCount: families.length)),
              SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Join Family card
              SliverToBoxAdapter(
                child: _JoinFamilyCard(
                  onJoin: () => _showJoinFamilyDialog(context),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 20)),

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
                    horizontal: KinrelSpacing.base,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final family = families[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _FamilyCard(
                          family: family,
                          index: index,
                          onTap: () => context.push('/family/${family.id}'),
                        ),
                      );
                    }, childCount: families.length),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
      floatingActionButton:
          Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: DKColors.brandGold, width: 2.5),
                  color: DKColors.brandPurple.withValues(alpha: 0.1),
                ),
                child: IconButton(
                  onPressed: () => context.push('/families/create'),
                  icon: Icon(Icons.add_rounded, size: 28),
                  color: DKColors.brandPurple,
                  tooltip: 'Create family',
                ),
              )
              .maybeAnimate(onPlay: (c) => c.forward())
              .fadeIn(duration: 500.ms)
              .scale(
                begin: const Offset(0.5, 0.5),
                end: const Offset(1.0, 1.0),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
    );
  }

  void _showJoinFamilyDialog(BuildContext context) {
    final codeController = TextEditingController();

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
              child: Icon(
                Icons.link_rounded,
                color: DKColors.brandPurple,
                size: 20,
              ),
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
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: DKColors.textSecondary(context),
                  size: 20,
                ),
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
            child: Text(
              'Cancel',
              style: TextStyle(color: DKColors.textSecondary(context)),
            ),
          ),
          DKButton(
            label: 'Join',
            variant: DKButtonVariant.primary,
            size: DKButtonSize.sm,
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Join family coming soon!')),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Loading Widget (extracted for zero-rebuild optimization) ─────

class _FamilyListLoadingWidget extends ConsumerWidget {
  const _FamilyListLoadingWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const FamilyListSkeleton(itemCount: 4);
  }
}

// ── Header ───────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.familyCount});

  final int familyCount;

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
        .maybeAnimate(onPlay: (c) => c.forward())
        .fadeIn(duration: 300.ms)
        .slideX(begin: -0.1, end: 0, duration: 300.ms);
  }
}

// ── Join Family Card ─────────────────────────────────────────────

class _JoinFamilyCard extends StatelessWidget {
  const _JoinFamilyCard({required this.onJoin});

  final VoidCallback onJoin;

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
                  child: Icon(
                    Icons.mail_outline_rounded,
                    color: DKColors.brandGold,
                    size: 20,
                  ),
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
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: DKColors.brandGold,
                ),
              ],
            ),
          ),
        )
        .maybeAnimate(onPlay: (c) => c.forward())
        .fadeIn(duration: 400.ms, delay: 100.ms);
  }
}

// ── Family Card ──────────────────────────────────────────────────

class _FamilyCard extends ConsumerWidget {
  const _FamilyCard({
    required this.family,
    required this.index,
    required this.onTap,
  });

  final Family family;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberCountAsync = ref.watch(familyMemberCountProvider(family.id));
    final languageName = family.primaryLanguage != null
        ? SupportedLanguage.fromCode(family.primaryLanguage!).name
        : 'English';

    final slug = family.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final idSuffix = family.id.length >= 4
        ? family.id.substring(0, 4)
        : family.id;
    // Show @username if available, otherwise fallback to slug
    final familyCode = family.username != null
        ? '@${family.username}'
        : 'kinrel.co/f/$slug-$idSuffix';

    return DKCard(
          borderColor: DKColors.brandPurple.withValues(alpha: 0.2),
          onTap: onTap,
          onLongPress: () => _showFamilyQuickActions(context, ref),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            family.name,
                            style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: DKColors.textPrimary(context),
                            ),
                          ),
                        ),
                        // Creator badge
                        if (_isCreator(ref))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: KinrelColors.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: KinrelColors.gold.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  size: 10,
                                  color: KinrelColors.gold,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Creator',
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: KinrelColors.gold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      familyCode,
                      style: TextStyle(
                        fontFamily: family.username != null
                            ? KinrelTypography.bodyFont
                            : KinrelTypography.monoFont,
                        fontSize: 10,
                        color: family.username != null
                            ? DKColors.brandPurple
                            : DKColors.textSecondary(
                                context,
                              ).withValues(alpha: 0.7),
                        fontWeight: family.username != null
                            ? FontWeight.w600
                            : FontWeight.w400,
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
                          loading: () => SizedBox(width: 80, height: 20),
                          error: (_, __) => SizedBox(width: 80, height: 20),
                        ),
                        const SizedBox(width: 10),
                        // Language
                        Icon(
                          Icons.translate_rounded,
                          size: 13,
                          color: DKColors.textSecondary(
                            context,
                          ).withValues(alpha: 0.6),
                        ),
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

              Icon(
                Icons.chevron_right,
                color: DKColors.brandPurple.withValues(alpha: 0.6),
              ),
            ],
          ),
        )
        .maybeAnimate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: 400.ms,
          delay: Duration(milliseconds: 100 + index * 60),
        )
        .slideX(begin: 0.1, end: 0, duration: 400.ms);
  }

  bool _isCreator(WidgetRef ref) {
    final currentUserId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    return family.createdBy != null && family.createdBy == currentUserId;
  }

  void _showFamilyQuickActions(BuildContext context, WidgetRef ref) {
    final isCreator = _isCreator(ref);

    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.bottomSheet),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(KinrelSpacing.base),
              child: Row(
                children: [
                  DKAvatar(
                    initials: family.name.isNotEmpty
                        ? family.name[0].toUpperCase()
                        : 'F',
                    size: DKAvatarSize.md,
                    backgroundColor: DKColors.brandPurple,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      family.name,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: KinrelColors.textWhite,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: KinrelColors.border, height: 1),
            ListTile(
              leading: Icon(
                Icons.visibility_outlined,
                color: KinrelColors.textSilver,
                size: 20,
              ),
              title: Text(
                'View Family',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textWhite,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/family/${family.id}');
              },
            ),
            if (isCreator)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: KinrelColors.coral,
                  size: 20,
                ),
                title: Text(
                  'Delete Family',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.coral,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteFromList(context, ref);
                },
              ),
            if (!isCreator)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.base,
                  vertical: KinrelSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: KinrelColors.textDim,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Only the family creator can delete this family',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteFromList(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: KinrelColors.error,
              size: 24,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Delete "${family.name}"?',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will permanently delete this family and all its members, relationships, and data.',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KinrelColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: KinrelColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: KinrelColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone.',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: KinrelColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textSilver,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _performDeleteFromList(context, ref);
            },
            child: Text(
              'Delete Family',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontWeight: FontWeight.w600,
                color: KinrelColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeleteFromList(
    BuildContext context,
    WidgetRef ref,
  ) async {
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: CircularProgressIndicator(color: KinrelColors.purple),
        ),
      ),
    );

    try {
      await deleteFamily(ref: ref, familyId: family.id);

      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${family.name} deleted'),
            backgroundColor: KinrelColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to delete: ${e.toString().split('\n').first}',
            ),
            backgroundColor: KinrelColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
