// lib/features/home/presentation/home_screen.dart
//
// DAXELO KINREL — Home Dashboard Screen
//
// Instagram-style family home with:
//   • Header: KinrelIcon + greeting + profile avatar (gold border in dark)
//   • Story-style family avatars (horizontal scroll, purple gradient border)
//   • Main family hero card (gradient overlay, glow shadow, purple accent)
//   • Quick Actions row (Add Member, Share, Find Path) with gradient borders
//   • Recent Activity section (icons, titles, timestamps)
//   • Your Families horizontal scroll
//
// Uses DK* widget library, KinrelColors (purple #5D5FEF / gold #D4AF37),
// KinrelTypography, KinrelSpacing, flutter_animate.
// Both light and dark mode support.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/kinrel_icon.dart';
import '../../../shared/widgets/dk_components.dart';

class HomeScreen extends ConsumerStatefulWidget {
  HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final familiesAsync = ref.watch(familyListProvider);
    final user = ref.watch(currentUserProvider);

    return DKScaffold(
      body: familiesAsync.when(
        loading: () => _buildLoadingState(),
        error: (error, _) => DKErrorState(
          message: 'Failed to load families',
          onRetry: () => ref.invalidate(familyListProvider),
        ),
        data: (families) {
          if (families.isEmpty) {
            return _buildNoFamiliesView(user);
          }
          return _buildFamiliesView(user, families);
        },
      ),
    );
  }

  /// Loading state — DKLoadingShimmer placeholders
  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          // Header shimmer
          const Row(
            children: [
              const KinrelIcon(size: 36),
              const SizedBox(width: 12),
              const Expanded(
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DKLoadingShimmer(width: 80, height: 12),
                    const SizedBox(height: 6),
                    const DKLoadingShimmer(width: 140, height: 18),
                  ],
                ),
              ),
              const DKLoadingShimmer(width: 40, height: 40, radius: 20),
            ],
          ),
          const SizedBox(height: 24),
          // Story row shimmer
          SizedBox(
            height: 88,
            child: Row(
              children: List.generate(
                5,
                (_) => const Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: const DKLoadingShimmer(width: 56, height: 72, radius: 28),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Hero card shimmer
          const DKLoadingShimmer(width: double.infinity, height: 220, radius: 20),
          const SizedBox(height: 20),
          // Quick actions shimmer
          Row(
            children: List.generate(
              3,
              (_) => const Expanded(
                child: const Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: const DKLoadingShimmer(width: double.infinity, height: 100, radius: 16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Recent activity shimmer
          const DKLoadingShimmer(width: 120, height: 18),
          const SizedBox(height: 12),
          ...List.generate(
            3,
            (_) => const Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: const DKLoadingShimmer(width: double.infinity, height: 64, radius: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// No families — show empty state with DKEmptyState
  Widget _buildNoFamiliesView(dynamic user) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: [
          const SizedBox(height: 24),
          _Header(user: user),
          SizedBox(height: 48),
          DKEmptyState(
            icon: Icons.family_restroom_outlined,
            title: 'No Families Yet',
            subtitle: 'Create your first family to start building your kinship graph',
            actionLabel: 'Create Family',
            onAction: () => context.push('/families/create'),
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.1, end: 0),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => _showJoinFamilyDialog(context),
            child: Text(
              'Or join an existing family with a code',
              style: const TextStyle(
                color: KinrelColors.purple,
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Has families — show Instagram-style family home
  Widget _buildFamiliesView(dynamic user, List<Family> families) {
    final primaryFamily = families.first;
    final detailAsync = ref.watch(familyDetailProvider(primaryFamily.id));

    return RefreshIndicator(
      color: KinrelColors.purple,
      backgroundColor: DKColors.cardColor(context),
      onRefresh: () async {
        ref.invalidate(familyListProvider);
        ref.invalidate(familyDetailProvider(primaryFamily.id));
      },
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _Header(user: user)
                .animate()
                .fadeIn(duration: 300.ms),

            const SizedBox(height: 16),

            // Story-style family avatars
            _FamilyStoriesRow(families: families)
                .animate()
                .fadeIn(duration: 350.ms, delay: 50.ms)
                .slideX(begin: -0.05, end: 0),

            const SizedBox(height: 24),

            // Main family hero card
            _PrimaryFamilyHeroCard(
              family: primaryFamily,
              detailAsync: detailAsync,
            )
                .animate()
                .fadeIn(duration: 400.ms, delay: 100.ms)
                .slideY(begin: 0.08, end: 0),

            const SizedBox(height: 20),

            // Quick Actions row
            _QuickActions(familyId: primaryFamily.id)
                .animate()
                .fadeIn(duration: 350.ms, delay: 150.ms),

            const SizedBox(height: 24),

            // Recent Activity section
            _RecentActivitySection(familyId: primaryFamily.id)
                .animate()
                .fadeIn(duration: 350.ms, delay: 200.ms)
                .slideY(begin: 0.05, end: 0),

            const SizedBox(height: 24),

            // Your Families horizontal scroll
            _YourFamiliesSection(families: families)
                .animate()
                .fadeIn(duration: 350.ms, delay: 250.ms)
                .slideY(begin: 0.05, end: 0),

            SizedBox(height: 100),
          ],
        ),
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
        title: Text(
          'Join Family',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: DKColors.textPrimary(context),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the family code shared with you',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: DKColors.textSecondary(context),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: codeController,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: DKColors.textPrimary(context),
              ),
              decoration: InputDecoration(
                hintText: 'e.g., sharma-family-2a3b',
                hintStyle: TextStyle(color: DKColors.textSecondary(context)),
                filled: true,
                fillColor: DKColors.elevatedColor(context),
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
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Join family coming soon!')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: KinrelColors.purple,
            ),
            child: Text('Join'),
          ),
        ],
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.user});

  final dynamic user;

  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: KinrelSpacing.md),
      child: Row(children: [
        const KinrelIcon(size: 36),
        SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Good day 👋',
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: DKColors.textSecondary(context))),
                Text(
                    user?.email?.split('@').first ?? 'Welcome',
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: DKColors.textPrimary(context))),
              ]),
        ),
        GestureDetector(
          onTap: () => context.go('/profile'),
          child: DKAvatar(
            initials: user?.email?.isNotEmpty == true
                ? user!.email![0].toUpperCase()
                : '?',
            size: DKAvatarSize.md,
            borderColor: isLight
                ? KinrelColors.purple
                : DKColors.brandGold,
            showGlow: !isLight,
          ),
        ),
      ]),
    );
  }
}

// ── Story-style Family Avatars ───────────────────────────────────
class _FamilyStoriesRow extends StatelessWidget {
  const _FamilyStoriesRow({required this.families});

  final List<Family> families;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: families.length + 1, // +1 for "Add" button
        separatorBuilder: (_, __) => SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _AddFamilyStory(onTap: () => context.push('/families/create'));
          }
          final family = families[index - 1];
          return _FamilyStoryAvatar(
            family: family,
            onTap: () => context.push('/family/${family.id}'),
          );
        },
      ),
    );
  }
}

class _AddFamilyStory extends StatelessWidget {
  const _AddFamilyStory({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: DKColors.brandPurple.withValues(alpha: 0.4),
                width: 2,
              ),
              color: DKColors.brandPurple.withValues(alpha: 0.1),
            ),
            child: const Icon(
              Icons.add_rounded,
              color: DKColors.brandPurple,
              size: 24,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Add',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: DKColors.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyStoryAvatar extends StatelessWidget {
  const _FamilyStoryAvatar({required this.family, required this.onTap});

  final Family family;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          // Instagram-style gradient ring
          Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [DKColors.brandPurple, DKColors.brandViolet, DKColors.brandCoral],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: DKColors.brandPurple.withValues(alpha: 0.25),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DKColors.cardColor(context),
              ),
              padding: EdgeInsets.all(2),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      DKColors.brandPurple.withValues(alpha: 0.3),
                      DKColors.brandViolet.withValues(alpha: 0.15),
                    ],
                  ),
                ),
                child: Center(
                  child: Text(
                    family.name.isNotEmpty
                        ? family.name[0].toUpperCase()
                        : 'F',
                    style: const TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: DKColors.brandPurple,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 56,
            child: Text(
              family.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: DKColors.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Primary Family Hero Card ─────────────────────────────────────
class _PrimaryFamilyHeroCard extends StatelessWidget {
  const _PrimaryFamilyHeroCard({
    required this.family,
    required this.detailAsync,
  });

  final Family family;
  final AsyncValue<FamilyDetail?> detailAsync;


  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: GestureDetector(
        onTap: () => context.push('/family/${family.id}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: DKColors.brandPurple.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: DKColors.brandPurple.withValues(alpha: isLight ? 0.15 : 0.35),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Gradient background
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: isLight
                        ? LinearGradient(
                            colors: [
                              DKColors.brandPurple.withValues(alpha: 0.15),
                          DKColors.brandViolet.withValues(alpha: 0.08),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : LinearGradient(
                            colors: [
                              DKColors.brandDeepPurple,
                              KinrelColors.darkSurface,
                              KinrelColors.darkCard,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                  ),
                ),

                // Glass overlay content
                Positioned.fill(
                  child: DKGlassCard(
                    padding: 20,
                    radius: 20,
                    blurSigma: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Family name centered
                        Center(
                          child: Column(
                            children: [
                              // Family avatar circle
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: KinrelGradients.igniteGradient,
                                  boxShadow: [
                                    BoxShadow(
                                      color: DKColors.brandPurple.withValues(alpha: 0.4),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    family.name.isNotEmpty
                                        ? family.name[0].toUpperCase()
                                        : 'F',
                                    style: const TextStyle(
                                      fontFamily: KinrelTypography.displayFont,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                family.name,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.displayFont,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: DKColors.textPrimary(context),
                                ),
                              ),
                              SizedBox(height: 4),
                              // Stats row
                              detailAsync.when(
                                data: (detail) {
                                  final members = detail?.members ?? [];
                                  final relationships = detail?.relationships ?? [];
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      DKStatChip(
                                        icon: Icons.people_outline_rounded,
                                        value: '${members.length}',
                                        label: 'Members',
                                        color: DKColors.brandPurple,
                                      ),
                                      SizedBox(width: 12),
                                      DKStatChip(
                                        icon: Icons.link_rounded,
                                        value: '${relationships.length}',
                                        label: 'Links',
                                        color: const DKColors.brandViolet,
                                      ),
                                    ],);const },
                                loading: () => SizedBox(
                                  height: 28,const child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: DKColors.brandPurple,
                                      ),
                                    ),
                                  ),
                                ),
                                error: (_, __) => const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),

                        Spacer(),

                        // View Full Graph CTA button with gradient
                        DKButton(
                          label: 'View Full Graph →',
                          variant: DKButtonVariant.gradient,
                          size: DKButtonSize.md,
                          fullWidth: true,
                          onPressed: () => context.push('/family/${family.id}'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Quick Actions ────────────────────────────────────────────────
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context) {
    final isLight = DKColors.isLight(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(children: [
        // Add Member
        Expanded(
          child: _GradientBorderCard(
            isLight: isLight,
            gradientColors: [DKColors.brandPurple, DKColors.brandViolet],
            onTap: () => context.push('/family/$familyId/add-person'),
            icon: Icons.person_add_rounded,
            iconColor: DKColors.brandPurple,
            iconBgColor: DKColors.brandPurple.withValues(alpha: 0.15),
            title: 'Add Member',
            subtitle: 'Expand your tree',
          ),
        ),
        const SizedBox(width: 10),
        // Share
        Expanded(
          child: _GradientBorderCard(
            isLight: isLight,
            gradientColors: const [DKColors.brandGold, DKColors.brandBrightGold],
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Share coming soon!')),
              );
            },
            icon: Icons.share_rounded,
            iconColor: DKColors.brandGold,
            iconBgColor: DKColors.brandGold.withValues(alpha: 0.15),
            title: 'Share',
            subtitle: 'Invite family',
          ),
        ),
        const SizedBox(width: 10),
        // Find Path
        Expanded(
          child: _GradientBorderCard(
            isLight: isLight,
            gradientColors: [DKColors.brandCoral, DKColors.brandViolet],
            onTap: () => context.push('/family/$familyId/path-finder'),
            icon: Icons.route_rounded,
            iconColor: DKColors.brandCoral,
            iconBgColor: DKColors.brandCoral.withValues(alpha: 0.15),
            title: 'Find Path',
            subtitle: 'Relationship finder',
          ),
        ),
      ]),
    );
  }
}

/// Quick Action card with gradient border effect
class _GradientBorderCard extends StatelessWidget {
  const _GradientBorderCard({
    required this.isLight,
    required this.gradientColors,
    required this.onTap,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.subtitle,
  });

  final bool isLight;
  final List<Color> gradientColors;
  final VoidCallback onTap;
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String subtitle;


  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(1.5), // border thickness
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DKColors.cardColor(context),
            borderRadius: BorderRadius.circular(14.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: iconBgColor,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(height: 10),
              Text(title,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DKColors.textPrimary(context),
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: DKColors.textSecondary(context),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Recent Activity Section ──────────────────────────────────────
class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({required this.familyId});

  final String familyId;

  // Static recent activity data for demo
  static _activities = [
    (
      icon: Icons.person_add_rounded,
      iconColor: DKColors.brandPurple,
      iconBg: DKColors.brandPurple,
      title: 'New member added',
      subtitle: 'Priya Sharma joined the family',
      time: '2h ago',
    ),
    (
      icon: Icons.link_rounded,
      iconColor: DKColors.brandGold,
      iconBg: DKColors.brandGold,
      title: 'Relationship linked',
      subtitle: 'Father → Daughter connection added',
      time: '5h ago',
    ),
    (
      icon: Icons.auto_awesome_rounded,
      iconColor: DKColors.brandCoral,
      iconBg: DKColors.brandCoral,
      title: 'Kinship discovered',
      subtitle: 'New kinship term found: Chacha',
      time: '1d ago',
    ),
    (
      icon: Icons.share_rounded,
      iconColor: DKColors.brandViolet,
      iconBg: DKColors.brandViolet,
      title: 'Family code shared',
      subtitle: 'Invite link generated',
      time: '2d ago',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Row(
            children: [
              Text('Recent Activity',
                  style: KinrelTypography.sectionHeader.copyWith(
                    color: DKColors.textPrimary(context),
                  )),
              const SizedBox(width: 8),
              Icon(Icons.history_rounded,
                  size: 16,
                  color: DKColors.brandPurple.withValues(alpha: 0.6)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ..._activities.map((activity) => Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.base, vertical: 4),
              child: DKCard(
                onTap: () {},
                padding: 12,
                radius: 14,
                child: Row(
                  children: [
                    // Icon circle
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: activity.iconBg.withValues(alpha: 0.15),
                      ),
                      child: Icon(activity.icon,
                          size: 18, color: activity.iconColor),
                    ),
                    const SizedBox(width: 12),
                    // Text content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(activity.title,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: DKColors.textPrimary(context),
                              )),
                          const SizedBox(height: 2),
                          Text(activity.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 11,
                                color: DKColors.textSecondary(context),
                              )),
                        ],
                      ),
                    ),
                    // Timestamp
                    Text(activity.time,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10,
                          color: DKColors.textSecondary(context),
                        )),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}

// ── Your Families Section ────────────────────────────────────────
class _YourFamiliesSection extends StatelessWidget {
  const _YourFamiliesSection({required this.families});

  final List<Family> families;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('Your Families',
                      style: KinrelTypography.sectionHeader.copyWith(
                        color: DKColors.textPrimary(context),
                      )),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: DKColors.brandPurple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${families.length}',
                        style: const TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                       fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: DKColors.brandPurple,
                        )),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => context.go('/families'),
                child: Text('See All',
                    style: TextStyle(
                      color: KinrelColors.purple,
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
            itemCount: families.length,
            separatorBuilder: (_, __) => SizedBox(width: 10),
            itemBuilder: (context, index) {
              final family = families[index];
              return _FamilyScrollCard(
                family: family,
                onTap: () => context.push('/family/${family.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FamilyScrollCard extends StatelessWidget {
  _FamilyScrollCard({
    required this.family,
    required this.onTap,
  });

  final Family family;
  final VoidCallback onTap;


  @override
  Widget build(BuildContext context) {
    return DKCard(
      onTap: onTap,
      padding: 14,
      radius: 16,
      borderColor: DKColors.brandPurple.withValues(alpha: 0.2),
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            DKAvatar(
              initials: family.name.isNotEmpty
                  ? family.name[0].toUpperCase()
                  : 'F',
              size: DKAvatarSize.sm,
              borderColor: DKColors.brandPurple,
            ),
            const SizedBox(height: 10),
            Text(family.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DKColors.textPrimary(context),
                )),
            SizedBox(height: 2),
            Text('Family',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: DKColors.textSecondary(context),
                )),
          ],
        ),
      ),
    );
  }
}
