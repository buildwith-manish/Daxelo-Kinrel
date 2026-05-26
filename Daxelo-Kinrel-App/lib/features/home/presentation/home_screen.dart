// lib/features/home/presentation/home_screen.dart
//
// DAXELO KINREL — Home Dashboard Screen (The Command Center)
//
// Orange K-Graph DNA redesign:
//   • Sticky Header: K-graph mini icon + time-based greeting + avatar (orange ring)
//   • Family Switcher: horizontal scroll with + Add + family avatars (Ignite gradient)
//   • Hero Family Card: radial gradient bg, orange glow, dotted K-graph pattern
//   • Quick Actions Row: 3 cards (Add Member, Share, Find Path) orange icons
//   • Recent Activity: clock icon orange, activity items (green/orange/blue icons)
//   • Family Insights Card: "Family at a Glance" with sparkle icon
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
import '../../../core/family/family_provider.dart';
import '../../../shared/widgets/kinrel_icon.dart';
import '../../../shared/widgets/dk_components.dart';

// ── Color shortcuts for the Command Center ──────────────────────
const _cOrange = KinrelColors.orange;       // #E8612A
const _cAmber = KinrelColors.amber;         // #F59240
const _cEmber = KinrelColors.ember;         // #C44A18
const _cBg = KinrelColors.darkBackground;   // #131416
const _cCard = KinrelColors.darkCard;       // #191B2C
const _cElevated = KinrelColors.darkElevated; // #202338
const _cTextPrimary = KinrelColors.textWhite;  // #F5F0EE
const _cTextSecondary = KinrelColors.textSilver; // #C9B4A8
const _cTextDim = KinrelColors.textDim;     // #8A7A72
const _cSuccess = KinrelColors.success;     // #4CAF7A
const _cInfo = KinrelColors.info;           // #60A5FA

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
          DKLoadingShimmer(width: double.infinity, height: 220, radius: 18),
          SizedBox(height: 20),
          // Quick actions shimmer
          Row(
            children: List.generate(
              3,
              (_) => Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: DKLoadingShimmer(width: double.infinity, height: 100, radius: 14),
                ),
              ),
            ),
          ),
          SizedBox(height: 20),
          // Recent activity shimmer
          DKLoadingShimmer(width: 120, height: 18),
          SizedBox(height: 12),
          ...List.generate(
            3,
            (_) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: DKLoadingShimmer(width: double.infinity, height: 64, radius: 14),
            ),
          ),
          SizedBox(height: 20),
          // Insights shimmer
          DKLoadingShimmer(width: double.infinity, height: 120, radius: 14),
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
            subtitle: 'Create your first family to start building your kinship graph',
            actionLabel: 'Create Family',
            onAction: () => context.push('/families/create'),
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.1, end: 0),
          SizedBox(height: 16),
          TextButton(
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
        ],
      ),
    );
  }

  // ── Has families — show Command Center ────────────────────────
  Widget _buildFamiliesView(dynamic user, List<Family> families) {
    final primaryFamily = families.first;
    final detailAsync = ref.watch(familyDetailProvider(primaryFamily.id));

    return RefreshIndicator(
      color: _cOrange,
      backgroundColor: _cCard,
      onRefresh: () async {
        ref.invalidate(familyListProvider);
        ref.invalidate(familyDetailProvider(primaryFamily.id));
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

                SizedBox(height: 24),

                // Hero Family Card
                _HeroFamilyCard(
                  family: primaryFamily,
                  detailAsync: detailAsync,
                )
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 100.ms)
                    .slideY(begin: 0.08, end: 0),

                SizedBox(height: 20),

                // Quick Actions Row
                _QuickActionsRow(familyId: primaryFamily.id)
                    .animate()
                    .fadeIn(duration: 350.ms, delay: 150.ms),

                SizedBox(height: 24),

                // Recent Activity
                _RecentActivitySection(familyId: primaryFamily.id)
                    .animate()
                    .fadeIn(duration: 350.ms, delay: 200.ms)
                    .slideY(begin: 0.05, end: 0),

                SizedBox(height: 24),

                // Family Insights Card (NEW)
                _FamilyInsightsCard(
                  families: families,
                  detailAsync: detailAsync,
                )
                    .animate()
                    .fadeIn(duration: 350.ms, delay: 250.ms)
                    .slideY(begin: 0.05, end: 0),

                SizedBox(height: 100),
              ],
            ),
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
            child: Text('Cancel',
                style: TextStyle(color: _cTextSecondary)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Join family coming soon!')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: _cOrange,
            ),
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
    final userName = user?.email?.split('@').first ?? 'Welcome';
    final isProfileIncomplete = user?.userMetadata?['name'] == null;

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
          // Greeting
          Expanded(
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
                Text(
                  userName,
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
          // User Avatar (36px, orange ring if profile incomplete)
          GestureDetector(
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
      BuildContext context, double shrinkOffset, bool overlapsContent) {
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
                child: Icon(
                  Icons.add_rounded,
                  color: _cOrange,
                  size: 22,
                ),
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
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Active: 2px orange border ring with subtle glow
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: isActive
                  ? Border.all(color: _cOrange, width: 2)
                  : null,
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
                  family.name.isNotEmpty
                      ? family.name[0].toUpperCase()
                      : 'F',
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
              family.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? _cTextPrimary : _cTextSecondary,
              ),
            ),
          ),
        ],
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
// Hero Family Card
// ═══════════════════════════════════════════════════════════════════════

class _HeroFamilyCard extends StatelessWidget {
  const _HeroFamilyCard({
    required this.family,
    required this.detailAsync,
  });

  final Family family;
  final AsyncValue<FamilyDetail?> detailAsync;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
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
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topRight,
                      radius: 1.2,
                      colors: [
                        Color(0xFF191B2C),
                        Color(0xFF13141E),
                      ],
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Family avatar + name
                        Center(
                          child: Column(
                            children: [
                              // Family initial avatar (48px, Ignite gradient bg)
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: KinrelGradients.igniteGradient,
                                  boxShadow: [
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
                              const SizedBox(height: 4),
                              // Stats: Members · Links · Generations (Body Small, #C9B4A8)
                              detailAsync.when(
                                data: (detail) {
                                  final members = detail?.members.length ?? family.memberCount;
                                  final links = detail?.relationships.length ?? 0;
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

                        Spacer(),

                        // View Full Graph button (Ignite gradient, white text, 12px radius, 48px height)
                        _buildViewGraphButton(family),
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

  Widget _buildViewGraphButton(Family family) {
    return GestureDetector(
      onTap: () => context.push('/family/${family.id}'),
      child: Container(
        height: 48,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: KinrelGradients.igniteGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _cOrange.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'View Full Graph',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
            SizedBox(width: 6),
            Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
          ],
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
      [0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [2, 6], [5, 8], [7, 9],
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

// ═══════════════════════════════════════════════════════════════════════
// Quick Actions Row (3 cards)
// ═══════════════════════════════════════════════════════════════════════

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.familyId});

  final String familyId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(
        children: [
          Expanded(
            child: _QuickActionCard(
              icon: Icons.person_add_rounded,
              iconColor: _cOrange,
              title: 'Add Member',
              subtitle: 'Expand your tree',
              onTap: () => context.push('/family/$familyId/add-person'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.share_rounded,
              iconColor: _cOrange,
              title: 'Share Family',
              subtitle: 'Invite family',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Share coming soon!')),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickActionCard(
              icon: Icons.route_rounded,
              iconColor: _cOrange,
              title: 'Find Path',
              subtitle: 'Find relationships',
              onTap: () => context.push('/family/$familyId/path-finder'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single quick action card — #191B2C bg, 1px border rgba(255,255,255,0.08), radius 14px
class _QuickActionCard extends StatefulWidget {
  const _QuickActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isPressed
                ? _cOrange.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: _isPressed
              ? [
                  BoxShadow(
                    color: _cOrange.withValues(alpha: 0.08),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon circle
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: _cOrange.withValues(alpha: 0.12),
              ),
              child: Icon(widget.icon, color: widget.iconColor, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              widget.title,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _cTextPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.subtitle,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                color: _cTextDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Recent Activity Section
// ═══════════════════════════════════════════════════════════════════════

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({required this.familyId});

  final String familyId;

  // Static demo activity data with orange palette
  static const _activities = [
    (
      icon: Icons.person_add_rounded,
      iconColor: _cSuccess,    // green for added
      name: 'Priya Sharma',
      action: 'joined the family',
      time: '2h ago',
    ),
    (
      icon: Icons.link_rounded,
      iconColor: _cOrange,     // orange for linked
      name: 'Father → Daughter',
      action: 'connection added',
      time: '5h ago',
    ),
    (
      icon: Icons.auto_awesome_rounded,
      iconColor: _cInfo,       // blue for updated
      name: 'Chacha',
      action: 'kinship term discovered',
      time: '1d ago',
    ),
    (
      icon: Icons.share_rounded,
      iconColor: _cOrange,     // orange for linked
      name: 'Invite link',
      action: 'family code shared',
      time: '2d ago',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: clock icon (orange) + "Recent Activity" + "See All" (orange)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
          child: Row(
            children: [
              Icon(Icons.schedule_rounded,
                  size: 16, color: _cOrange),
              const SizedBox(width: 6),
              Text('Recent Activity',
                  style: KinrelTypography.sectionHeader.copyWith(
                    color: _cTextPrimary,
                  )),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/activity'),
                child: Text('See All',
                    style: TextStyle(
                      color: _cOrange,
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Activity items
        ..._activities.map((activity) => _ActivityItem(activity: activity)),
      ],
    );
  }
}

/// Single activity item with icon + bold name + action text + relative time
class _ActivityItem extends StatelessWidget {
  const _ActivityItem({required this.activity});

  final ({IconData icon, Color iconColor, String name, String action, String time}) activity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.base, vertical: 4),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: activity.iconColor.withValues(alpha: 0.12),
              ),
              child: Icon(activity.icon,
                  size: 18, color: activity.iconColor),
            ),
            const SizedBox(width: 12),
            // Text content: bold name + action text
            Expanded(
              child: RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: _cTextSecondary,
                  ),
                  children: [
                    TextSpan(
                      text: activity.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _cTextPrimary,
                      ),
                    ),
                    TextSpan(
                      text: ' ${activity.action}',
                    ),
                  ],
                ),
              ),
            ),
            // Timestamp
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                activity.time,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: _cTextDim,
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
// Family Insights Card (NEW)
// ═══════════════════════════════════════════════════════════════════════

class _FamilyInsightsCard extends StatelessWidget {
  const _FamilyInsightsCard({
    required this.families,
    required this.detailAsync,
  });

  final List<Family> families;
  final AsyncValue<FamilyDetail?> detailAsync;

  @override
  Widget build(BuildContext context) {
    // Compute insights from available data
    final totalMembers = families.fold<int>(
      0,
      (sum, f) => sum + f.memberCount,
    );

    final totalGenerations = families.fold<int>(
      0,
      (sum, f) => sum + f.generationCount,
    );

    // Find most connected member from detail
    String mostConnected = '—';
    String oldestAncestor = '—';

    detailAsync.whenData((detail) {
      if (detail == null) return;
      final members = detail.members;
      final relationships = detail.relationships;

      // Most connected = person with most relationships
      final connectionCount = <String, int>{};
      for (final rel in relationships) {
        connectionCount[rel.fromPersonId] =
            (connectionCount[rel.fromPersonId] ?? 0) + 1;
        connectionCount[rel.toPersonId] =
            (connectionCount[rel.toPersonId] ?? 0) + 1;
      }
      if (connectionCount.isNotEmpty) {
        final mostConnectedId = connectionCount.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
        final person = members.where((m) => m.id == mostConnectedId).firstOrNull;
        if (person != null) mostConnected = person.name;
      }

      // Oldest recorded ancestor (earliest birthYear)
      final withBirthYear = members.where((m) => m.birthYear != null).toList();
      if (withBirthYear.isNotEmpty) {
        withBirthYear.sort((a, b) => a.birthYear!.compareTo(b.birthYear!));
        oldestAncestor = '${withBirthYear.first.name} (${withBirthYear.first.birthYear})';
      }
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: sparkle icon (orange) + "Family at a Glance"
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 18, color: _cOrange),
                const SizedBox(width: 8),
                Text(
                  'Family at a Glance',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _cTextPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Total members across all trees (large number in Outfit Bold)
            _InsightRow(
              icon: Icons.people_outline_rounded,
              label: 'Total Members',
              value: '$totalMembers',
              valueStyle: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: _cOrange,
              ),
            ),
            const SizedBox(height: 16),

            // Oldest recorded ancestor
            _InsightRow(
              icon: Icons.elderly_rounded,
              label: 'Oldest Ancestor',
              value: oldestAncestor,
            ),
            const SizedBox(height: 16),

            // Most connected member
            _InsightRow(
              icon: Icons.hub_rounded,
              label: 'Most Connected',
              value: mostConnected,
            ),
            const SizedBox(height: 12),

            // Generations count
            _InsightRow(
              icon: Icons.account_tree_rounded,
              label: 'Generations',
              value: '$totalGenerations',
            ),
          ],
        ),
      ),
    );
  }
}

/// Single insight row within the Family Insights Card.
class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final IconData icon;
  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: _cOrange.withValues(alpha: 0.1),
          ),
          child: Icon(icon, size: 16, color: _cOrange),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: _cTextDim,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: valueStyle ??
                    TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _cTextPrimary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
