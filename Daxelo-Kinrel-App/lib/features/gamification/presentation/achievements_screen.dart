// lib/features/gamification/presentation/achievements_screen.dart
//
// DAXELO KINREL — Gamification & Achievements Screen
//
// Follows KINREL Global Top 1 Prompt Section 25 specs exactly:
//   - Header: "Achievements" with trophy icon in orange
//   - Profile completion ring (circular progress, 75%)
//   - Streak card with flame icon, "7 Day Streak" with orange gradient
//   - Tree completeness card: progress bar, percentage, next step
//   - "Unlocked" section: Grid of earned badges (3 columns)
//   - "Locked" section: Grid of locked badges (greyed out)
//   - "Suggested Next Steps" section: 2-3 actionable cards
//
// Badge Design:
//   Unlocked: #191B2C bg, orange glow, gold gradient ring, icon in orange
//   Locked: #191B2C bg, dim #4A4A5E icon, no glow, lock overlay
//
// Design: #13141E bg, #191B2C cards, orange/gold accents

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/gamification_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// AchievementsScreen
// ═══════════════════════════════════════════════════════════════════════

class AchievementsScreen extends ConsumerStatefulWidget {
  const AchievementsScreen({super.key});

  @override
  ConsumerState<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends ConsumerState<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: KinrelMotion.ceremonial,
    )..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gamification = ref.watch(gamificationProvider);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Header ──────────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildHeader()),

          // ── Profile Completion Ring ─────────────────────────────────
          SliverToBoxAdapter(
            child: _ProfileCompletionRing(
              completion: gamification.profileCompletion,
              animation: _animController,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Streak Card ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: _StreakCard(
              streak: gamification.streak,
              onCheckIn: () => ref.read(gamificationProvider.notifier).checkIn(),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Tree Completeness Card ──────────────────────────────────
          SliverToBoxAdapter(
            child: _TreeCompletenessCard(
              completeness: gamification.treeCompleteness,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 28)),

          // ── Unlocked Badges Section ─────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Unlocked',
              count: gamification.unlockedCount,
              icon: Icons.emoji_events_rounded,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final badge = gamification.unlockedBadges[index];
                  return _UnlockedBadgeCard(
                    badge: badge,
                    animDelay: index * 0.08,
                    controller: _animController,
                  );
                },
                childCount: gamification.unlockedBadges.length,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 28)),

          // ── Locked Badges Section ───────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Locked',
              count: gamification.lockedBadges.length,
              icon: Icons.lock_outline_rounded,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final badge = gamification.lockedBadges[index];
                  return _LockedBadgeCard(badge: badge);
                },
                childCount: gamification.lockedBadges.length,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 28)),

          // ── Suggested Next Steps ────────────────────────────────────
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: 'Suggested Next Steps',
              count: null,
              icon: Icons.lightbulb_outline_rounded,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final step = gamification.suggestedSteps[index];
                  return Padding(
                    padding: EdgeInsets.only(bottom: index < gamification.suggestedSteps.length - 1 ? 12 : 0),
                    child: _SuggestedStepCard(step: step),
                  );
                },
                childCount: gamification.suggestedSteps.length,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            // Back button
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  border: Border.all(color: const Color(0xFF3A3A4A), width: 1),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: KinrelColors.textWhite,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Trophy icon in orange
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: KinrelGradients.igniteGradient,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.orangeGlow,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Achievements',
                style: KinrelTypography.headlineLarge.copyWith(
                  color: KinrelColors.textWhite,
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
// Profile Completion Ring
// ═══════════════════════════════════════════════════════════════════════

class _ProfileCompletionRing extends StatelessWidget {
  const _ProfileCompletionRing({
    required this.completion,
    required this.animation,
  });

  final ProfileCompletion completion;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final animatedPercent = Tween<double>(begin: 0, end: completion.percentage)
        .animate(CurvedAnimation(
      parent: animation,
      curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
    ));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(color: const Color(0xFF2A2A3D), width: 1),
        ),
        child: Row(
          children: [
            // Circular progress ring
            AnimatedBuilder(
              animation: animatedPercent,
              builder: (context, child) {
                return _CircularProgressRing(
                  percentage: animatedPercent.value,
                  size: 88,
                  strokeWidth: 7,
                );
              },
            ),
            const SizedBox(width: 20),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profile Completion',
                    style: KinrelTypography.headlineSmall.copyWith(
                      color: KinrelColors.textWhite,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${completion.completedFields} of ${completion.totalFields} fields completed',
                    style: KinrelTypography.bodySmall.copyWith(
                      color: KinrelColors.textSilver,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    completion.nextStep,
                    style: KinrelTypography.bodySmall.copyWith(
                      color: KinrelColors.orange,
                      fontWeight: FontWeight.w600,
                    ),
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

/// LinkedIn-style circular progress ring with gradient stroke.
class _CircularProgressRing extends StatelessWidget {
  const _CircularProgressRing({
    required this.percentage,
    this.size = 88,
    this.strokeWidth = 7,
  });

  final double percentage;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          percentage: percentage,
          strokeWidth: strokeWidth,
          backgroundColor: const Color(0xFF2A2A3D),
          gradientColors: const [
            KinrelColors.orange,
            KinrelColors.amber,
          ],
        ),
        child: Center(
          child: Text(
            '${percentage.round()}%',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: KinrelColors.textWhite,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the circular progress ring.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.percentage,
    required this.strokeWidth,
    required this.backgroundColor,
    required this.gradientColors,
  });

  final double percentage;
  final double strokeWidth;
  final Color backgroundColor;
  final List<Color> gradientColors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background track
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    if (percentage > 0) {
      final sweepAngle = (percentage / 100) * 2 * math.pi;
      final startAngle = -math.pi / 2;

      final rect = Rect.fromCircle(center: center, radius: radius);
      final gradient = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: gradientColors,
        transform: GradientRotation(startAngle),
      );

      final progressPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.percentage != percentage;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Streak Card
// ═══════════════════════════════════════════════════════════════════════

class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.streak,
    required this.onCheckIn,
  });

  final StreakData streak;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(
            color: KinrelColors.orange.withValues(alpha: 0.3),
            width: 1.5,
          ),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF1E1412), // dark warm tint
              KinrelColors.darkCard,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: KinrelColors.orangeGlow,
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Top row: flame + streak count
            Row(
              children: [
                // Flame icon with gradient
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: KinrelGradients.igniteGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: KinrelColors.orangeGlowIntense,
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.local_fire_department_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${streak.currentStreak} Day Streak',
                            style: KinrelTypography.headlineMedium.copyWith(
                              color: KinrelColors.textWhite,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Longest: ${streak.longestStreak} days',
                        style: KinrelTypography.bodySmall.copyWith(
                          color: KinrelColors.textSilver,
                        ),
                      ),
                    ],
                  ),
                ),
                // Check-in button
                GestureDetector(
                  onTap: streak.todayCheckedIn ? null : onCheckIn,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: streak.todayCheckedIn
                          ? null
                          : KinrelGradients.igniteGradient,
                      color: streak.todayCheckedIn
                          ? KinrelColors.darkElevated
                          : null,
                      borderRadius: BorderRadius.circular(KinrelRadius.md),
                      border: streak.todayCheckedIn
                          ? Border.all(color: const Color(0xFF3A3A4A), width: 1)
                          : null,
                      boxShadow: streak.todayCheckedIn
                          ? null
                          : [
                              BoxShadow(
                                color: KinrelColors.orangeGlow,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          streak.todayCheckedIn
                              ? Icons.check_circle_rounded
                              : Icons.add_circle_outline_rounded,
                          size: 16,
                          color: streak.todayCheckedIn
                              ? KinrelColors.success
                              : Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          streak.todayCheckedIn ? 'Done' : 'Check In',
                          style: KinrelTypography.labelMedium.copyWith(
                            color: streak.todayCheckedIn
                                ? KinrelColors.success
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Streak message
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: KinrelColors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      streak.streakMessage,
                      style: KinrelTypography.bodySmall.copyWith(
                        color: KinrelColors.textSilver,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Day dots
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (index) {
                final isFilled = index < streak.currentStreak;
                return Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isFilled ? KinrelGradients.igniteGradient : null,
                        color: isFilled ? null : KinrelColors.darkElevated,
                        border: isFilled
                            ? null
                            : Border.all(
                                color: const Color(0xFF3A3A4A),
                                width: 1,
                              ),
                        boxShadow: isFilled
                            ? [
                                BoxShadow(
                                  color: KinrelColors.orangeGlow,
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: isFilled
                          ? const Icon(
                              Icons.local_fire_department_rounded,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                      style: KinrelTypography.micro.copyWith(
                        color: isFilled ? KinrelColors.orange : KinrelColors.textDim,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Tree Completeness Card
// ═══════════════════════════════════════════════════════════════════════

class _TreeCompletenessCard extends StatelessWidget {
  const _TreeCompletenessCard({
    required this.completeness,
  });

  final TreeCompleteness completeness;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: Border.all(color: const Color(0xFF2A2A3D), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: KinrelColors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  ),
                  child: const Icon(
                    Icons.account_tree_rounded,
                    color: KinrelColors.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Family Tree Completeness',
                    style: KinrelTypography.headlineSmall.copyWith(
                      color: KinrelColors.textWhite,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${completeness.percentage.round()}%',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.orange,
                    height: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(KinrelRadius.full),
              child: SizedBox(
                height: 10,
                child: Stack(
                  children: [
                    // Background
                    Container(
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius: BorderRadius.circular(KinrelRadius.full),
                      ),
                    ),
                    // Fill
                    FractionallySizedBox(
                      widthFactor: completeness.percentage / 100,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: KinrelGradients.igniteGradient,
                          borderRadius: BorderRadius.circular(KinrelRadius.full),
                          boxShadow: [
                            BoxShadow(
                              color: KinrelColors.orangeGlow,
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Stats row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _TreeStat(label: 'Members', value: '${completeness.totalMembers}'),
                _TreeStat(label: 'Generations', value: '${completeness.generations}'),
                _TreeStat(label: 'Relations', value: '${completeness.relationships}'),
              ],
            ),
            const SizedBox(height: 12),
            // Next step hint
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tips_and_updates_outlined,
                    size: 16,
                    color: KinrelColors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      completeness.fullHintText,
                      style: KinrelTypography.bodySmall.copyWith(
                        color: KinrelColors.textSilver,
                        height: 1.4,
                      ),
                    ),
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

class _TreeStat extends StatelessWidget {
  const _TreeStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: KinrelColors.textWhite,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: KinrelTypography.micro.copyWith(
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Section Header
// ═══════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.count,
    required this.icon,
  });

  final String title;
  final int? count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: KinrelColors.orange,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: KinrelTypography.headlineSmall.copyWith(
              color: KinrelColors.textWhite,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                gradient: KinrelGradients.igniteGradient,
                borderRadius: BorderRadius.circular(KinrelRadius.full),
              ),
              child: Text(
                '$count',
                style: KinrelTypography.micro.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Unlocked Badge Card
// ═══════════════════════════════════════════════════════════════════════

class _UnlockedBadgeCard extends StatelessWidget {
  const _UnlockedBadgeCard({
    required this.badge,
    required this.animDelay,
    required this.controller,
  });

  final AchievementBadge badge;
  final double animDelay;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final scaleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(
          animDelay.clamp(0.0, 0.8),
          (animDelay + 0.2).clamp(0.0, 1.0),
          curve: Curves.easeOutBack,
        ),
      ),
    );

    final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(
          animDelay.clamp(0.0, 0.8),
          (animDelay + 0.2).clamp(0.0, 1.0),
          curve: Curves.easeOut,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Opacity(
          opacity: fadeAnimation.value,
          child: Transform.scale(
            scale: scaleAnimation.value,
            child: Container(
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelRadius.lg),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.25),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.orangeGlow,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(KinrelRadius.lg),
                child: InkWell(
                  borderRadius: BorderRadius.circular(KinrelRadius.lg),
                  onTap: () => _showBadgeDetail(context, badge),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Badge icon with gold gradient ring
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: KinrelGradients.achievementGradient,
                            boxShadow: [
                              BoxShadow(
                                color: KinrelColors.orangeGlowIntense,
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Container(
                            margin: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: KinrelColors.darkCard,
                            ),
                            child: Center(
                              child: Icon(
                                badge.icon,
                                size: 24,
                                color: KinrelColors.orange,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Badge name
                        Text(
                          badge.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: KinrelTypography.labelMedium.copyWith(
                            color: KinrelColors.textWhite,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Date earned
                        Text(
                          badge.formattedUnlockDate,
                          style: KinrelTypography.micro.copyWith(
                            color: KinrelColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBadgeDetail(BuildContext context, AchievementBadge badge) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A4A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Badge icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: KinrelGradients.achievementGradient,
                boxShadow: [
                  BoxShadow(
                    color: KinrelColors.orangeGlowIntense,
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.darkCard,
                ),
                child: Center(
                  child: Icon(
                    badge.icon,
                    size: 36,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              badge.name,
              style: KinrelTypography.headlineMedium.copyWith(
                color: KinrelColors.textWhite,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Unlocked ${badge.formattedUnlockDate}',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.orange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              badge.description,
              textAlign: TextAlign.center,
              style: KinrelTypography.bodyMedium.copyWith(
                color: KinrelColors.textSilver,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Locked Badge Card
// ═══════════════════════════════════════════════════════════════════════

class _LockedBadgeCard extends StatelessWidget {
  const _LockedBadgeCard({
    required this.badge,
  });

  final AchievementBadge badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: const Color(0xFF2A2A3D),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          onTap: () => _showBadgeDetail(context, badge),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Badge icon with lock overlay
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Dim circle
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: KinrelColors.darkElevated,
                          border: Border.all(
                            color: const Color(0xFF3A3A4A),
                            width: 1.5,
                          ),
                        ),
                      ),
                      // Dimmed icon
                      Icon(
                        badge.icon,
                        size: 24,
                        color: const Color(0xFF4A4A5E),
                      ),
                      // Lock overlay
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: KinrelColors.darkCard,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF3A3A4A),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.lock_rounded,
                            size: 10,
                            color: Color(0xFF4A4A5E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Badge name (dimmed)
                Text(
                  badge.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: KinrelTypography.labelMedium.copyWith(
                    color: const Color(0xFF4A4A5E),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                // Condition text
                Text(
                  badge.condition,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: KinrelTypography.micro.copyWith(
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBadgeDetail(BuildContext context, AchievementBadge badge) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A4A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Locked icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KinrelColors.darkElevated,
                border: Border.all(
                  color: const Color(0xFF3A3A4A),
                  width: 2,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    badge.icon,
                    size: 32,
                    color: const Color(0xFF4A4A5E),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: KinrelColors.darkCard,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 12,
                        color: Color(0xFF4A4A5E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              badge.name,
              style: KinrelTypography.headlineMedium.copyWith(
                color: const Color(0xFF4A4A5E),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.full),
                border: Border.all(
                  color: const Color(0xFF3A3A4A),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: KinrelColors.textDim,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    badge.condition,
                    style: KinrelTypography.labelSmall.copyWith(
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              badge.description,
              textAlign: TextAlign.center,
              style: KinrelTypography.bodyMedium.copyWith(
                color: KinrelColors.textDim,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Suggested Next Step Card
// ═══════════════════════════════════════════════════════════════════════

class _SuggestedStepCard extends StatelessWidget {
  const _SuggestedStepCard({
    required this.step,
  });

  final SuggestedStep step;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: step.color.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          onTap: step.route != null
              ? () {
                  // Navigation would use GoRouter in production
                  // For now, just show a snackbar
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Navigate to ${step.route}'),
                      backgroundColor: KinrelColors.darkElevated,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon circle
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: step.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                  ),
                  child: Icon(
                    step.icon,
                    size: 22,
                    color: step.color,
                  ),
                ),
                const SizedBox(width: 14),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: KinrelTypography.labelLarge.copyWith(
                          color: KinrelColors.textWhite,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: KinrelTypography.bodySmall.copyWith(
                          color: KinrelColors.textSilver,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Action arrow or button
                if (step.actionLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: step.accentColor == 0xFFE8612A
                          ? KinrelGradients.igniteGradient
                          : null,
                      color: step.accentColor != 0xFFE8612A
                          ? step.color.withValues(alpha: 0.15)
                          : null,
                      borderRadius: BorderRadius.circular(KinrelRadius.sm),
                    ),
                    child: Text(
                      step.actionLabel!,
                      style: KinrelTypography.micro.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: step.color,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


