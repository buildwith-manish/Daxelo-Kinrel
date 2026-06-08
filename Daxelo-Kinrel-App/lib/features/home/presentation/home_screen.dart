// lib/features/home/presentation/home_screen.dart
//
// DAXELO KINREL — Home Dashboard Screen (The Command Center)
//
// Orange K-Graph DNA redesign:
//   • Sticky Header: K-graph mini icon + time-based greeting + @username + avatar
//   • Family Switcher: horizontal scroll with + Add + family avatars (Ignite gradient)
//   • Hero Family Card: radial gradient bg, orange glow, dotted K-graph pattern
//   • Family Feed: Instagram-style vertical feed (replaces Recent Activity + Family at a Glance)
//
// Uses KinrelColors (orange #E8612A / amber #F59240 / ember #C44A18),
// KinrelTypography, KinrelSpacing, KinrelGradients, flutter_animate.
// Dark mode is the primary experience.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/config/auth_config.dart';
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/kinrel_icon.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../feed/presentation/family_feed.dart';
import '../../feed/providers/feed_provider.dart';
import '../../stories/providers/stories_provider.dart';
import '../../stories/presentation/stories_viewer_screen.dart';
import '../../stories/presentation/add_story_sheet.dart';
import '../../../core/utils/accessibility_utils.dart';

// ── Color shortcuts for the Command Center ──────────────────────
const _cOrange = KinrelColors.orange; // #E8612A
const _cBg = KinrelColors.darkBackground; // #131416
const _cCard = KinrelColors.darkCard; // #191B2C
const _cElevated = KinrelColors.darkElevated; // #202338
const _cTextPrimary = KinrelColors.textWhite; // #F5F0EE
const _cTextSecondary = KinrelColors.textSilver; // #C9B4A8
const _cTextDim = KinrelColors.textDim; // #8A7A72

class HomeScreen extends ConsumerStatefulWidget {
  HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required by AutomaticKeepAliveClientMixin
    final familiesAsync = ref.watch(familyListProvider);
    final user = ref.watch(currentUserProvider);

    return DKScaffold(
      backgroundColor: _cBg,
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

  // ── Loading state — shimmer placeholders ──────────────────────
  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 24),
          // Header shimmer
          Row(
            children: [
              KinrelIcon(size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DKLoadingShimmer(width: 80, height: 12),
                    SizedBox(height: 6),
                    DKLoadingShimmer(width: 140, height: 18),
                  ],
                ),
              ),
              DKLoadingShimmer(width: 36, height: 36, radius: 18),
            ],
          ),
          SizedBox(height: 24),
          // Family switcher shimmer
          SizedBox(
            height: 76,
            child: Row(
              children: List.generate(
                5,
                (_) => Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: DKLoadingShimmer(width: 52, height: 52, radius: 26),
                ),
              ),
            ),
          ),
          SizedBox(height: 24),
          // Hero card shimmer
          DKLoadingShimmer(width: double.infinity, height: 160, radius: 18),
          SizedBox(height: 20),
          // Feed shimmer
          DKLoadingShimmer(width: 120, height: 18),
          SizedBox(height: 12),
          ...List.generate(
            2,
            (_) => Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: DKLoadingShimmer(
                width: double.infinity,
                height: 280,
                radius: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── No families — empty state ─────────────────────────────────
  Widget _buildNoFamiliesView(dynamic user) {
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: [
          const SizedBox(height: 24),
          _StickyHeader(user: user),
          const SizedBox(height: 48),
          DKEmptyState(
            icon: Icons.family_restroom_outlined,
            title: 'No Families Yet',
            subtitle:
                'Create your first family to start building your kinship graph',
            actionLabel: 'Create Family',
            onAction: () => context.push('/families/create'),
          ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
          SizedBox(height: 16),
          semanticLink(
            label: 'Join an existing family with a code',
            child: TextButton(
              onPressed: () => _showJoinFamilyDialog(context),
              child: Text(
                'Or join an existing family with a code',
                style: TextStyle(
                  color: _cOrange,
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                  decorationColor: _cOrange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Has families — show Command Center with Feed ──────────────
  Widget _buildFamiliesView(dynamic user, List<Family> families) {
    final primaryFamily = families.first;
    final detailAsync = ref.watch(familyDetailProvider(primaryFamily.id));

    return RefreshIndicator(
      color: _cOrange,
      backgroundColor: _cCard,
      onRefresh: () async {
        ref.invalidate(familyListProvider);
        ref.invalidate(familyMembersProvider(primaryFamily.id));
        ref.invalidate(familyRelationshipsProvider(primaryFamily.id));
        // familyDetailProvider auto-rebuilds via ref.watch on above providers
        ref.invalidate(feedProvider);
        ref.invalidate(storiesProvider(primaryFamily.id));
      },
      child: CustomScrollView(
        physics: BouncingScrollPhysics(),
        slivers: [
          // Sticky Header
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(user: user),
          ),

          // Main content
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Family Switcher
                _FamilySwitcherRow(families: families)
                    .animate()
                    .fadeIn(duration: 350.ms, delay: 50.ms)
                    .slideX(begin: -0.05, end: 0),

                SizedBox(height: 20),

                // Stories Row (Instagram-style circles)
                _StoriesRow(familyId: primaryFamily.id)
                    .animate()
                    .fadeIn(duration: 350.ms, delay: 75.ms)
                    .slideY(begin: -0.05, end: 0),

                SizedBox(height: 20),

                // Hero Family Card (avatar is tappable → opens stories)
                _HeroFamilyCard(
                  family: primaryFamily,
                  detailAsync: detailAsync,
                  familyId: primaryFamily.id,
                )
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 100.ms)
                    .slideY(begin: 0.08, end: 0),

                SizedBox(height: 20),

                // ✅ REMOVED (BUG-10): _QuickActionsRow removed from home screen
                // — Add Member / Share / Find Path actions remain available
                // inside the family detail screen's floating bottom action bar

                // Feed section header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KinrelSpacing.base,
                  ),
                  child: semanticHeader(
                    label: 'Family Feed',
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 18,
                          color: _cOrange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Family Feed',
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _cTextPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 350.ms, delay: 200.ms),

                SizedBox(height: 12),
              ],
            ),
          ),

          // Family Feed (sliver that takes remaining space)
          SliverFillRemaining(
            hasScrollBody: true,
            child: FamilyFeed(
              familyId: primaryFamily.id,
            ).animate().fadeIn(duration: 350.ms, delay: 250.ms),
          ),
        ],
      ),
    );
  }

  void _showJoinFamilyDialog(BuildContext context) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.dialog),
          side: BorderSide(color: _cOrange.withValues(alpha: 0.15)),
        ),
        title: Text(
          'Join Family',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            color: _cTextPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the family code shared with you',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: _cTextSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: _cTextPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'e.g., sharma-family-2a3b',
                hintStyle: TextStyle(color: _cTextDim),
                filled: true,
                fillColor: _cElevated,
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
            child: Text('Cancel', style: TextStyle(color: _cTextSecondary)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Join family coming soon!')),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: _cOrange),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Sticky Header (60px)
// ═══════════════════════════════════════════════════════════════════════

/// Time-of-day contextual emoji.
String _greetingEmoji() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return '☀️';
  if (hour >= 12 && hour < 17) return '🌤️';
  if (hour >= 17 && hour < 21) return '🌅';
  return '🌙';
}

/// Time-of-day greeting prefix.
String _greetingPrefix() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  if (hour >= 17 && hour < 21) return 'Good evening';
  return 'Good night';
}

class _StickyHeader extends StatelessWidget {
  const _StickyHeader({required this.user});

  final dynamic user;

  @override
  Widget build(BuildContext context) {
    final userName = kAuthDisabled
        ? 'Manish'
        : (user?.email?.split('@').first ?? 'Welcome');
    final userUsername = kAuthDisabled
        ? 'manish'
        : (user?.userMetadata?['username'] as String?);
    final isProfileIncomplete = kAuthDisabled
        ? false
        : (user?.userMetadata?['name'] == null);

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: BoxDecoration(
        color: _cBg,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // K-graph mini icon (20px)
          KinrelIcon(size: 20),
          const SizedBox(width: 12),
          // Greeting with @username
          Expanded(
            child: semanticHeader(
              label: '${_greetingPrefix()} $userName',
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_greetingPrefix()} ${_greetingEmoji()}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: _cTextDim,
                    ),
                  ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        userName,
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _cTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (userUsername != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '@$userUsername',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: _cOrange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          ),
          // User Avatar (36px, orange ring if profile incomplete)
          Semantics(
            button: true,
            label: 'User profile${isProfileIncomplete ? ', complete your profile' : ''}',
            hint: 'Double tap to open profile',
            child: minimumTapTarget(
              child: GestureDetector(
                onTap: () => context.go('/profile'),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isProfileIncomplete
                        ? KinrelGradients.igniteGradient
                        : null,
                    color: isProfileIncomplete ? null : _cElevated,
                    boxShadow: isProfileIncomplete
                        ? [
                            BoxShadow(
                              color: _cOrange.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  padding: EdgeInsets.all(isProfileIncomplete ? 2.0 : 0),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _cCard,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _cOrange,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// SliverPersistentHeaderDelegate for a sticky 60px header.
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({required this.user});

  final dynamic user;

  @override
  double get minExtent => 60;

  @override
  double get maxExtent => 60;

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) =>
      oldDelegate.user != user;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return _StickyHeader(user: user);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Family Switcher (horizontal scroll)
// ═══════════════════════════════════════════════════════════════════════

class _FamilySwitcherRow extends StatelessWidget {
  const _FamilySwitcherRow({required this.families});

  final List<Family> families;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: families.length + 1, // +1 for "Add" button
        separatorBuilder: (_, __) => SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _AddFamilyCircle(
              onTap: () => context.push('/families/create'),
            );
          }
          final family = families[index - 1];
          final isActive = index == 1; // First family is active
          return _FamilySwitchAvatar(
            family: family,
            isActive: isActive,
            onTap: () => context.push('/family/${family.id}'),
          );
        },
      ),
    );
  }
}

/// "+" dashed circle with "Add" label
class _AddFamilyCircle extends StatelessWidget {
  const _AddFamilyCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // Accessibility: semantic button label for screen readers
      child: semanticButton(
        label: 'Add family',
        hint: 'Double tap to create a new family',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomPaint(
              size: Size(52, 52),
              painter: _DashedCirclePainter(
                color: _cOrange.withValues(alpha: 0.5),
                dashWidth: 4,
                dashGap: 4,
                strokeWidth: 2,
              ),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Center(
                  child: Icon(Icons.add_rounded, color: _cOrange, size: 22),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _cTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Family tree avatar (52px circle, initial letter, Ignite gradient bg)
class _FamilySwitchAvatar extends StatelessWidget {
  const _FamilySwitchAvatar({
    required this.family,
    required this.isActive,
    required this.onTap,
  });

  final Family family;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Show @username if available, else family name
    final displayName = family.familyCode ?? family.name;

    return GestureDetector(
      onTap: onTap,
      // Accessibility: semantic button for family switch
      child: semanticButton(
        label: '$displayName family${isActive ? ', currently selected' : ''}',
        hint: 'Double tap to open ${family.name} family',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Active: 2px orange border ring with subtle glow
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: isActive ? Border.all(color: _cOrange, width: 2) : null,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: _cOrange.withValues(alpha: 0.25),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              padding: isActive ? EdgeInsets.all(2) : EdgeInsets.zero,
              child: Container(
                width: isActive ? 46 : 52,
                height: isActive ? 46 : 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: KinrelGradients.igniteGradient,
                ),
                child: Center(
                  child: Text(
                    family.name.isNotEmpty ? family.name[0].toUpperCase() : 'F',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 52,
              child: Text(
                '@${displayName.length > 8 ? displayName.substring(0, 8) : displayName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 9,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? _cOrange : _cTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for dashed circle border.
class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({
    required this.color,
    this.dashWidth = 5,
    this.dashGap = 5,
    this.strokeWidth = 2,
  });

  final Color color;
  final double dashWidth;
  final double dashGap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final circumference = 2 * 3.14159265 * radius;
    final totalDashWidth = dashWidth + dashGap;
    final dashCount = (circumference / totalDashWidth).floor();

    final anglePerDash = totalDashWidth / radius;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * anglePerDash;
      final sweepAngle = dashWidth / radius;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.dashGap != dashGap;
}

// ═══════════════════════════════════════════════════════════════════════
// Stories Row (Instagram-style story circles)
// ═══════════════════════════════════════════════════════════════════════

class _StoriesRow extends ConsumerWidget {
  const _StoriesRow({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(storiesProvider(familyId));

    return storiesAsync.when(
      loading: () => SizedBox(
        height: 84,
        child: Row(
          children: [
            SizedBox(width: KinrelSpacing.base),
            ...List.generate(
              4,
              (_) => Padding(
                padding: const EdgeInsets.only(right: 14),
                child: DKLoadingShimmer(width: 60, height: 84, radius: 12),
              ),
            ),
          ],
        ),
      ),
      error: (_, __) => const SizedBox.shrink(), // Fail silently
      data: (storyGroups) {
        if (storyGroups.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
            itemCount: storyGroups.length + 1, // +1 for "Add" story
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return _AddStoryCircle(
                  onTap: () => showAddStorySheet(
                    context,
                    familyId: familyId,
                    ref: ref,
                  ),
                );
              }
              final group = storyGroups[index - 1];
              return _StoryCircle(
                storyGroup: group,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StoriesViewerScreen(
                        storyGroups: storyGroups,
                        initialGroupIndex: index - 1,
                        familyId: familyId,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// "+" dashed circle with "Your Story" label — opens add story sheet
class _AddStoryCircle extends StatelessWidget {
  const _AddStoryCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: semanticButton(
        label: 'Add story',
        hint: 'Double tap to add a new story',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomPaint(
              size: Size(56, 56),
              painter: _DashedCirclePainter(
                color: _cOrange.withValues(alpha: 0.6),
                dashWidth: 5,
                dashGap: 4,
                strokeWidth: 2,
              ),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: Icon(Icons.add_rounded, color: _cOrange, size: 24),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your\nStory',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: _cTextSecondary,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Story circle for a user with stories — shows avatar with orange ring if unviewed
class _StoryCircle extends StatelessWidget {
  const _StoryCircle({
    required this.storyGroup,
    required this.onTap,
  });

  final StoryGroup storyGroup;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: semanticButton(
        label: '${storyGroup.userName} stories',
        hint: 'Double tap to view ${storyGroup.userName}\'s stories',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar with orange ring if hasUnviewed
            Container(
              width: 56,
              height: 56,
              padding: EdgeInsets.all(storyGroup.hasUnviewed ? 3 : 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: storyGroup.hasUnviewed
                    ? KinrelGradients.igniteGradient
                    : null,
                border: storyGroup.hasUnviewed
                    ? null
                    : Border.all(
                        color: Colors.white24,
                        width: 1,
                      ),
                boxShadow: storyGroup.hasUnviewed
                    ? [
                        BoxShadow(
                          color: _cOrange.withValues(alpha: 0.25),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Container(
                width: storyGroup.hasUnviewed ? 48 : 52,
                height: storyGroup.hasUnviewed ? 48 : 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _cElevated,
                  border: Border.all(
                    color: _cBg,
                    width: 2,
                  ),
                  image: storyGroup.userAvatarUrl != null
                      ? DecorationImage(
                          image: NetworkImage(storyGroup.userAvatarUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: storyGroup.userAvatarUrl == null
                    ? Center(
                        child: Text(
                          storyGroup.initials,
                          style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _cOrange,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 60,
              child: Text(
                storyGroup.userName.split(' ').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 9,
                  fontWeight: storyGroup.hasUnviewed
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: storyGroup.hasUnviewed ? _cOrange : _cTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Hero Family Card
// ═══════════════════════════════════════════════════════════════════════

class _HeroFamilyCard extends ConsumerWidget {
  const _HeroFamilyCard({required this.family, required this.detailAsync, required this.familyId});

  final Family family;
  final AsyncValue<FamilyDetail?> detailAsync;
  final String familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(storiesProvider(familyId));
    final hasStories = storiesAsync.valueOrNull?.isNotEmpty ?? false;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: semanticButton(
        label: '${family.name} family card',
        hint: 'Double tap to open ${family.name} family details',
        child: GestureDetector(
          onTap: () => context.push('/family/${family.id}'),
          child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _cOrange.withValues(alpha: 0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _cOrange.withValues(alpha: 0.12),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // Radial gradient background #13141E → #191B2C with orange glow
                Container(
                  // ✅ FIX (BUG-07): Use minHeight instead of fixed height
                  // to prevent BOTTOM OVERFLOWED BY 18 PIXELS when content
                  // (username, stats) is taller than the fixed 160px
                  constraints: const BoxConstraints(minHeight: 160),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topRight,
                      radius: 1.2,
                      colors: [Color(0xFF191B2C), Color(0xFF13141E)],
                      stops: [0.0, 1.0],
                    ),
                  ),
                ),

                // Subtle dotted K-graph pattern (low opacity)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DottedKGraphPainter(
                      color: _cOrange.withValues(alpha: 0.04),
                    ),
                  ),
                ),

                // Content
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Family avatar + name
                        Center(
                          child: Column(
                            children: [
                              // Family initial avatar (48px, Ignite gradient bg)
                            // — Tappable: opens stories viewer for this family
                            // — Eye icon glow indicates stories are available
                            GestureDetector(
                              onTap: () {
                                if (hasStories) {
                                  final groups = storiesAsync.valueOrNull ?? [];
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => StoriesViewerScreen(
                                        storyGroups: groups,
                                        familyId: familyId,
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: KinrelGradients.igniteGradient,
                                      boxShadow: hasStories
                                          ? [
                                              BoxShadow(
                                                color: _cOrange.withValues(alpha: 0.4),
                                                blurRadius: 12,
                                                spreadRadius: 2,
                                              ),
                                              // Extra glow ring when stories exist
                                              BoxShadow(
                                                color: _cOrange.withValues(alpha: 0.15),
                                                blurRadius: 20,
                                                spreadRadius: 4,
                                              ),
                                            ]
                                          : [
                                              BoxShadow(
                                                color: _cOrange.withValues(alpha: 0.4),
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
                                        style: TextStyle(
                                          fontFamily: KinrelTypography.displayFont,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Small eye icon hint when stories are available
                                  if (hasStories)
                                    Positioned(
                                      right: -2,
                                      bottom: -2,
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _cOrange,
                                          border: Border.all(
                                            color: _cBg,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.visibility_rounded,
                                          size: 10,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                              const SizedBox(height: 12),
                              // Family name (Heading Large, #F5F0EE)
                              Text(
                                family.name,
                                style: TextStyle(
                                  fontFamily: KinrelTypography.displayFont,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: _cTextPrimary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              // Family @username
                              if (family.familyCode != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '@${family.familyCode}',
                                  style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 12,
                                    color: _cOrange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              // Stats: Members · Links · Generations (Body Small, #C9B4A8)
                              detailAsync.when(
                                data: (detail) {
                                  final members =
                                      detail?.members.length ??
                                      family.memberCount;
                                  final links =
                                      detail?.relationships.length ?? 0;
                                  final generations = family.generationCount;
                                  return Text(
                                    '$members Members · $links Links · $generations Generations',
                                    style: TextStyle(
                                      fontFamily: KinrelTypography.bodyFont,
                                      fontSize: 12,
                                      color: _cTextSecondary,
                                    ),
                                  );
                                },
                                loading: () => SizedBox(
                                  height: 18,
                                  child: Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _cOrange,
                                      ),
                                    ),
                                  ),
                                ),
                                error: (_, __) => SizedBox.shrink(),
                              ),
                            ],
                          ),
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
      ),
    );
  }
}

/// Subtle dotted K-graph pattern for hero card background.
class _DottedKGraphPainter extends CustomPainter {
  _DottedKGraphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw a subtle node-and-edge pattern
    final nodes = [
      Offset(size.width * 0.15, size.height * 0.25),
      Offset(size.width * 0.35, size.height * 0.15),
      Offset(size.width * 0.55, size.height * 0.3),
      Offset(size.width * 0.75, size.height * 0.2),
      Offset(size.width * 0.85, size.height * 0.4),
      Offset(size.width * 0.25, size.height * 0.55),
      Offset(size.width * 0.5, size.height * 0.65),
      Offset(size.width * 0.7, size.height * 0.7),
      Offset(size.width * 0.4, size.height * 0.85),
      Offset(size.width * 0.8, size.height * 0.85),
    ];

    final edges = [
      [0, 1],
      [1, 2],
      [2, 3],
      [3, 4],
      [0, 5],
      [5, 6],
      [6, 7],
      [2, 6],
      [5, 8],
      [7, 9],
    ];

    // Draw edges
    for (final edge in edges) {
      canvas.drawLine(nodes[edge[0]], nodes[edge[1]], paint);
    }

    // Draw dots at nodes
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final node in nodes) {
      canvas.drawCircle(node, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DottedKGraphPainter oldDelegate) =>
      oldDelegate.color != color;
}
