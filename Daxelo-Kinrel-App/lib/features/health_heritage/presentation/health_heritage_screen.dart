// lib/features/health_heritage/presentation/health_heritage_screen.dart
//
// DAXELO KINREL — Family Health Heritage Screen
//
// Features:
//   - Header with medical icon in orange
//   - Risk Score Card (circular progress, animated)
//   - Health Insights Cards (horizontal scroll)
//   - Category Breakdown (grid of category cards)
//   - Conditions List (filterable, searchable)
//   - Add Condition FAB (bottom sheet)
//   - Generation Tree View toggle
//
// Design: Dark theme primary, orange/amber accents

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/health_heritage_provider.dart';

// ═══════════════════════════════════════════════════════════════════════
// HealthHeritageScreen
// ═══════════════════════════════════════════════════════════════════════

class HealthHeritageScreen extends ConsumerStatefulWidget {
  const HealthHeritageScreen({super.key});

  @override
  ConsumerState<HealthHeritageScreen> createState() =>
      _HealthHeritageScreenState();
}

class _HealthHeritageScreenState extends ConsumerState<HealthHeritageScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  bool _isTreeView = false;
  final _searchController = TextEditingController();

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
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final heritageState = ref.watch(healthHeritageProvider);
    final summary = heritageState.summary;
    final filteredConditions = ref.watch(filteredConditionsProvider);
    final insights = ref.watch(healthInsightsProvider);
    final byCategory = ref.watch(conditionsByCategoryProvider);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Header ──────────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildHeader()),

          // ── Risk Score Card ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: _RiskScoreCard(
              summary: summary,
              animation: _animController,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Health Insights ─────────────────────────────────────────
          if (insights.isNotEmpty)
            SliverToBoxAdapter(
              child: _InsightsSection(insights: insights),
            ),

          if (insights.isNotEmpty)
            const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Category Breakdown ──────────────────────────────────────
          SliverToBoxAdapter(
            child: _CategoryBreakdown(
              byCategory: byCategory,
              selectedCategory: heritageState.selectedCategory,
              onCategoryTap: (cat) {
                final current = heritageState.selectedCategory;
                ref
                    .read(healthHeritageProvider.notifier)
                    .setCategory(current == cat ? null : cat);
              },
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Search + View Toggle ────────────────────────────────────
          SliverToBoxAdapter(child: _buildSearchAndToggle(heritageState)),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ── Conditions ──────────────────────────────────────────────
          if (_isTreeView)
            _buildGenerationTree(heritageState)
          else
            _buildConditionsList(filteredConditions),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButton: _buildFAB(),
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
                  border: Border.all(
                      color: const Color(0xFF3A3A4A), width: 1),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: KinrelColors.textWhite,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Medical icon in orange
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
                Icons.local_hospital_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Family Health Heritage',
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

  // ── Search and View Toggle ──────────────────────────────────────────

  Widget _buildSearchAndToggle(HealthHeritageState heritageState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: DKSearchField(
              hint: 'Search conditions...',
              controller: _searchController,
              onChanged: (value) {
                ref
                    .read(healthHeritageProvider.notifier)
                    .setSearchQuery(value);
              },
            ),
          ),
          const SizedBox(width: 10),
          // View toggle
          GestureDetector(
            onTap: () => setState(() => _isTreeView = !_isTreeView),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isTreeView
                    ? KinrelColors.orange.withValues(alpha: 0.15)
                    : KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: _isTreeView
                      ? KinrelColors.orange.withValues(alpha: 0.4)
                      : const Color(0xFF3A3A4A),
                  width: 1,
                ),
              ),
              child: Icon(
                _isTreeView
                    ? Icons.account_tree_rounded
                    : Icons.list_rounded,
                color: _isTreeView
                    ? KinrelColors.orange
                    : KinrelColors.textSilver,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Privacy toggle
          GestureDetector(
            onTap: () {
              ref
                  .read(healthHeritageProvider.notifier)
                  .setShowPrivate(!heritageState.showPrivate);
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: heritageState.showPrivate
                    ? KinrelColors.orange.withValues(alpha: 0.15)
                    : KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: heritageState.showPrivate
                      ? KinrelColors.orange.withValues(alpha: 0.4)
                      : const Color(0xFF3A3A4A),
                  width: 1,
                ),
              ),
              child: Icon(
                heritageState.showPrivate
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
                color: heritageState.showPrivate
                    ? KinrelColors.orange
                    : KinrelColors.textSilver,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Conditions List View ────────────────────────────────────────────

  Widget _buildConditionsList(List<HealthCondition> conditions) {
    if (conditions.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Center(
            child: Text(
              'No conditions found',
              style: KinrelTypography.bodyMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final condition = conditions[index];
            return Padding(
              padding: EdgeInsets.only(
                  bottom: index < conditions.length - 1 ? 12 : 0),
              child: _ConditionCard(
                condition: condition,
                animDelay: index * 0.05,
              ),
            );
          },
          childCount: conditions.length,
        ),
      ),
    );
  }

  // ── Generation Tree View ────────────────────────────────────────────

  Widget _buildGenerationTree(HealthHeritageState heritageState) {
    final byGeneration = ref.watch(conditionsByGenerationProvider);
    final sortedGens = byGeneration.keys.toList()..sort();

    if (sortedGens.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Center(
            child: Text(
              'No conditions to display',
              style: KinrelTypography.bodyMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, genIndex) {
            final gen = sortedGens[genIndex];
            final genConditions = byGeneration[gen] ?? [];
            final genLabel = _generationLabel(gen);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Generation header
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: KinrelGradients.igniteGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: KinrelColors.orangeGlow,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '$gen',
                          style: KinrelTypography.labelSmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        genLabel,
                        style: KinrelTypography.headlineSmall.copyWith(
                          color: KinrelColors.textWhite,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: KinrelColors.darkElevated,
                        borderRadius:
                            BorderRadius.circular(KinrelRadius.full),
                        border: Border.all(
                            color: const Color(0xFF3A3A4A), width: 1),
                      ),
                      child: Text(
                        '${genConditions.length}',
                        style: KinrelTypography.micro.copyWith(
                          color: KinrelColors.textSilver,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Generation connector line
                Container(
                  margin: const EdgeInsets.only(left: 15),
                  width: 2,
                  height: genConditions.length * 16.0,
                  decoration: BoxDecoration(
                    gradient: KinrelGradients.timelineGradient,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(height: 8),
                // Conditions in this generation
                ...genConditions.map(
                  (condition) => Padding(
                    padding: const EdgeInsets.only(bottom: 10, left: 30),
                    child: _GenerationConditionCard(condition: condition),
                  ),
                ),
                if (genIndex < sortedGens.length - 1)
                  const SizedBox(height: 20),
              ],
            );
          },
          childCount: sortedGens.length,
        ),
      ),
    );
  }

  String _generationLabel(int gen) {
    switch (gen) {
      case 1:
        return 'Great-Grandparents';
      case 2:
        return 'Grandparents';
      case 3:
        return 'Parents';
      case 4:
        return 'Current Generation';
      default:
        return 'Generation $gen';
    }
  }

  // ── FAB ─────────────────────────────────────────────────────────────

  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(
        gradient: KinrelGradients.igniteGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orangeGlowIntense,
            blurRadius: 20,
            spreadRadius: 4,
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: () => _showAddConditionSheet(),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
      ),
    );
  }

  // ── Add Condition Bottom Sheet ──────────────────────────────────────

  void _showAddConditionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) => _AddConditionSheet(ref: ref),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Risk Score Card
// ═══════════════════════════════════════════════════════════════════════

class _RiskScoreCard extends StatelessWidget {
  const _RiskScoreCard({
    required this.summary,
    required this.animation,
  });

  final FamilyHealthSummary? summary;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final riskScore = summary?.riskScore ?? 0.0;
    final riskPercent = (riskScore * 100).round();
    final riskLevel = summary?.riskLevelText ?? 'Low';

    final animatedPercent =
        Tween<double>(begin: 0, end: riskScore * 100).animate(
      CurvedAnimation(
        parent: animation,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
              Color(0xFF1E1412),
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
        child: Row(
          children: [
            // Circular risk indicator
            AnimatedBuilder(
              animation: animatedPercent,
              builder: (context, child) {
                return _RiskRing(
                  percentage: animatedPercent.value,
                  size: 100,
                  strokeWidth: 8,
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
                    'Family Risk Score',
                    style: KinrelTypography.headlineSmall.copyWith(
                      color: KinrelColors.textWhite,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$riskPercent% overall risk based on ${summary?.totalConditions ?? 0} conditions',
                    style: KinrelTypography.bodySmall.copyWith(
                      color: KinrelColors.textSilver,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Risk level badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _riskLevelColor(riskLevel)
                          .withValues(alpha: 0.15),
                      borderRadius:
                          BorderRadius.circular(KinrelRadius.full),
                      border: Border.all(
                        color: _riskLevelColor(riskLevel)
                            .withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _riskLevelIcon(riskLevel),
                          size: 14,
                          color: _riskLevelColor(riskLevel),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$riskLevel Risk',
                          style: KinrelTypography.labelSmall.copyWith(
                            color: _riskLevelColor(riskLevel),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (summary?.hereditaryConditions != null &&
                      summary!.hereditaryConditions > 0)
                    Text(
                      '${summary!.hereditaryConditions} hereditary conditions detected',
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
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(duration: KinrelMotion.normal)
        .slideY(begin: 0.1, end: 0, duration: KinrelMotion.normal);
  }

  Color _riskLevelColor(String level) {
    switch (level) {
      case 'Low':
        return const Color(0xFF22C55E);
      case 'Moderate':
        return const Color(0xFFF59E0B);
      case 'High':
        return const Color(0xFFF97316);
      case 'Critical':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF22C55E);
    }
  }

  IconData _riskLevelIcon(String level) {
    switch (level) {
      case 'Low':
        return Icons.check_circle_rounded;
      case 'Moderate':
        return Icons.info_rounded;
      case 'High':
        return Icons.warning_amber_rounded;
      case 'Critical':
        return Icons.error_rounded;
      default:
        return Icons.check_circle_rounded;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Risk Ring (Circular Progress)
// ═══════════════════════════════════════════════════════════════════════

class _RiskRing extends StatelessWidget {
  const _RiskRing({
    required this.percentage,
    this.size = 100,
    this.strokeWidth = 8,
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
        painter: _RiskRingPainter(
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
              fontSize: 24,
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

class _RiskRingPainter extends CustomPainter {
  const _RiskRingPainter({
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

      canvas.drawArc(rect, startAngle, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RiskRingPainter oldDelegate) {
    return oldDelegate.percentage != percentage;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Health Insights Section
// ═══════════════════════════════════════════════════════════════════════

class _InsightsSection extends StatelessWidget {
  const _InsightsSection({required this.insights});

  final List<HealthInsight> insights;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded,
                  size: 18, color: KinrelColors.orange),
              const SizedBox(width: 8),
              Text(
                'Health Insights',
                style: KinrelTypography.headlineSmall.copyWith(
                  color: KinrelColors.textWhite,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  gradient: KinrelGradients.igniteGradient,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                ),
                child: Text(
                  '${insights.length}',
                  style: KinrelTypography.micro.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: insights.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final insight = insights[index];
              return _InsightCard(insight: insight, index: index);
            },
          ),
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.index});

  final HealthInsight insight;
  final int index;

  Color _accentColor() {
    switch (insight.type) {
      case InsightType.warning:
        return const Color(0xFFEF4444); // red/orange
      case InsightType.recommendation:
        return const Color(0xFF22C55E); // green
      case InsightType.pattern:
        return const Color(0xFF3B82F6); // blue
      case InsightType.trend:
        return const Color(0xFF8B5CF6); // purple
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor();
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: accent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(KinrelRadius.sm),
                ),
                child: Icon(insight.icon, size: 16, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  insight.title,
                  style: KinrelTypography.labelMedium.copyWith(
                    color: KinrelColors.textWhite,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              insight.description,
              style: KinrelTypography.bodySmall.copyWith(
                color: KinrelColors.textSilver,
                height: 1.4,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: KinrelMotion.normal,
          delay: Duration(milliseconds: index * 80),
        )
        .slideX(
          begin: 0.2,
          end: 0,
          duration: KinrelMotion.normal,
          delay: Duration(milliseconds: index * 80),
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Category Breakdown Grid
// ═══════════════════════════════════════════════════════════════════════

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.byCategory,
    required this.selectedCategory,
    required this.onCategoryTap,
  });

  final Map<HealthCategory, List<HealthCondition>> byCategory;
  final HealthCategory? selectedCategory;
  final ValueChanged<HealthCategory> onCategoryTap;

  @override
  Widget build(BuildContext context) {
    final activeCats = byCategory.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Row(
            children: [
              Icon(Icons.category_rounded,
                  size: 18, color: KinrelColors.orange),
              const SizedBox(width: 8),
              Text(
                'Categories',
                style: KinrelTypography.headlineSmall.copyWith(
                  color: KinrelColors.textWhite,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: activeCats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final cat = activeCats[index];
              final count = byCategory[cat]?.length ?? 0;
              final isSelected = selectedCategory == cat;
              return _CategoryCard(
                category: cat,
                count: count,
                isSelected: isSelected,
                onTap: () => onCategoryTap(cat),
                index: index,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.count,
    required this.isSelected,
    required this.onTap,
    required this.index,
  });

  final HealthCategory category;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final int index;

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(category);
    final icon = categoryIcon(category);
    final label = categoryLabel(category);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.5)
                : const Color(0xFF3A3A4A),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isSelected ? color : KinrelColors.textWhite,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KinrelTypography.micro.copyWith(
                color: isSelected ? color : KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: KinrelMotion.normal,
          delay: Duration(milliseconds: index * 50),
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Condition Card (List View)
// ═══════════════════════════════════════════════════════════════════════

class _ConditionCard extends StatelessWidget {
  const _ConditionCard({
    required this.condition,
    required this.animDelay,
  });

  final HealthCondition condition;
  final double animDelay;

  @override
  Widget build(BuildContext context) {
    final catColor = condition.categoryColorValue;
    final sevColor = condition.severityColorValue;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: condition.isHereditary
              ? KinrelColors.orange.withValues(alpha: 0.2)
              : const Color(0xFF2A2A3D),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Person avatar
          DKAvatar(
            initials: condition.diagnosedPersonName
                .split(' ')
                .map((n) => n.isNotEmpty ? n[0] : '')
                .take(2)
                .join(),
            size: DKAvatarSize.sm,
            borderColor: condition.isHereditary
                ? KinrelColors.orange.withValues(alpha: 0.6)
                : null,
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Condition name + badges
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        condition.name,
                        style: KinrelTypography.labelLarge.copyWith(
                          color: KinrelColors.textWhite,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (condition.isHereditary)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.biotech_rounded,
                          size: 14,
                          color: KinrelColors.orange,
                        ),
                      ),
                    if (condition.isPrivate)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 12,
                          color: KinrelColors.textDim,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Person name
                Text(
                  condition.diagnosedPersonName,
                  style: KinrelTypography.bodySmall.copyWith(
                    color: KinrelColors.textSilver,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                // Badges row
                Row(
                  children: [
                    // Category badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.15),
                        borderRadius:
                            BorderRadius.circular(KinrelRadius.full),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(condition.icon, size: 10, color: catColor),
                          const SizedBox(width: 3),
                          Text(
                            condition.categoryLabelValue,
                            style: KinrelTypography.micro.copyWith(
                              color: catColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Severity dot + label
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: sevColor.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(KinrelRadius.full),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: sevColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            condition.severityLabelValue,
                            style: KinrelTypography.micro.copyWith(
                              color: sevColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (condition.ageOfOnset != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: KinrelColors.darkElevated,
                          borderRadius:
                              BorderRadius.circular(KinrelRadius.full),
                          border: Border.all(
                              color: const Color(0xFF3A3A4A), width: 0.5),
                        ),
                        child: Text(
                          'Age ${condition.ageOfOnset}',
                          style: KinrelTypography.micro.copyWith(
                            color: KinrelColors.textSilver,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Generation indicator
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: KinrelColors.orange.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              KinrelColors.orange.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${condition.generation}',
                          style: KinrelTypography.micro.copyWith(
                            color: KinrelColors.orange,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: KinrelMotion.normal,
          delay: Duration(milliseconds: (animDelay * 1000).round()),
        )
        .slideY(
          begin: 0.05,
          end: 0,
          duration: KinrelMotion.normal,
          delay: Duration(milliseconds: (animDelay * 1000).round()),
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Generation Condition Card (Tree View)
// ═══════════════════════════════════════════════════════════════════════

class _GenerationConditionCard extends StatelessWidget {
  const _GenerationConditionCard({required this.condition});

  final HealthCondition condition;

  @override
  Widget build(BuildContext context) {
    final catColor = condition.categoryColorValue;
    final sevColor = condition.severityColorValue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: condition.isHereditary
              ? KinrelColors.orange.withValues(alpha: 0.2)
              : const Color(0xFF2A2A3D),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Severity dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: sevColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          // Category icon
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(KinrelRadius.xs),
            ),
            child: Icon(condition.icon, size: 12, color: catColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        condition.name,
                        style: KinrelTypography.labelSmall.copyWith(
                          color: KinrelColors.textWhite,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (condition.isHereditary)
                      Icon(
                        Icons.biotech_rounded,
                        size: 12,
                        color: KinrelColors.orange,
                      ),
                    if (condition.isPrivate)
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 10,
                          color: KinrelColors.textDim,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${condition.diagnosedPersonName}${condition.ageOfOnset != null ? ' · Age ${condition.ageOfOnset}' : ''}',
                  style: KinrelTypography.micro.copyWith(
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Add Condition Bottom Sheet
// ═══════════════════════════════════════════════════════════════════════

class _AddConditionSheet extends StatefulWidget {
  const _AddConditionSheet({required this.ref});

  final WidgetRef ref;

  @override
  State<_AddConditionSheet> createState() => _AddConditionSheetState();
}

class _AddConditionSheetState extends State<_AddConditionSheet> {
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _ageController = TextEditingController();
  HealthCategory _selectedCategory = HealthCategory.other;
  Severity _selectedSeverity = Severity.moderate;
  bool _isHereditary = false;
  bool _isPrivate = false;
  String _selectedPersonName = '';
  final _personController = TextEditingController();

  static const _commonConditions = [
    'Type 2 Diabetes',
    'Hypertension',
    'Coronary Artery Disease',
    'Asthma',
    'Thalassemia Trait',
    'Breast Cancer (BRCA1)',
    'Breast Cancer (BRCA2)',
    'Alzheimer\'s Disease',
    'Dementia',
    'Hypothyroidism',
    'Sickle Cell Trait',
    'Color Blindness',
    'Migraine',
    'Epilepsy',
    'Celiac Disease',
    'Lupus',
    'Rheumatoid Arthritis',
    'Glaucoma',
    'Osteoporosis',
    'Chronic Kidney Disease',
    'Liver Cirrhosis',
    'Depression',
    'Anxiety Disorder',
    'Parkinson\'s Disease',
  ];

  List<String> _suggestions = [];

  void _updateSuggestions(String query) {
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    setState(() {
      _suggestions = _commonConditions
          .where((c) => c.toLowerCase().contains(query.toLowerCase()))
          .take(5)
          .toList();
    });
  }

  void _submit() {
    if (_nameController.text.isEmpty || _personController.text.isEmpty) {
      return;
    }

    final condition = HealthCondition(
      id: 'hc_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text,
      category: _selectedCategory,
      severity: _selectedSeverity,
      isHereditary: _isHereditary,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
      diagnosedPersonId: 'person_custom',
      diagnosedPersonName: _personController.text,
      familyId: 'sharma_family',
      ageOfOnset:
          _ageController.text.isEmpty ? null : int.tryParse(_ageController.text),
      isPrivate: _isPrivate,
      generation: 4,
    );

    widget.ref.read(healthHeritageProvider.notifier).addCondition(condition);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _ageController.dispose();
    _personController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A4A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Text(
              'Add Health Condition',
              style: KinrelTypography.headlineMedium.copyWith(
                color: KinrelColors.textWhite,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),

            // Person name
            Text(
              'Family Member',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 6),
            _SheetTextField(
              controller: _personController,
              hint: 'e.g., Arjun Sharma',
            ),
            const SizedBox(height: 16),

            // Condition name with autocomplete
            Text(
              'Condition Name',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 6),
            _SheetTextField(
              controller: _nameController,
              hint: 'e.g., Type 2 Diabetes',
              onChanged: _updateSuggestions,
            ),
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  border: Border.all(
                      color: const Color(0xFF3A3A4A), width: 1),
                ),
                child: Column(
                  children: _suggestions.map((s) {
                    return ListTile(
                      dense: true,
                      title: Text(
                        s,
                        style: KinrelTypography.bodySmall.copyWith(
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      onTap: () {
                        _nameController.text = s;
                        setState(() => _suggestions = []);
                        // Auto-select category based on condition
                        _autoSelectCategory(s);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Category selector
            Text(
              'Category',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 6),
            _CategorySelector(
              selected: _selectedCategory,
              onSelect: (cat) => setState(() => _selectedCategory = cat),
            ),
            const SizedBox(height: 16),

            // Severity selector
            Text(
              'Severity',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 6),
            _SeveritySelector(
              selected: _selectedSeverity,
              onSelect: (sev) => setState(() => _selectedSeverity = sev),
            ),
            const SizedBox(height: 16),

            // Age of onset
            Text(
              'Age of Onset',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 6),
            _SheetTextField(
              controller: _ageController,
              hint: 'e.g., 45',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            // Toggles row
            Row(
              children: [
                // Hereditary toggle
                Expanded(
                  child: _ToggleChip(
                    label: 'Hereditary',
                    icon: Icons.biotech_rounded,
                    value: _isHereditary,
                    onChanged: (v) => setState(() => _isHereditary = v),
                  ),
                ),
                const SizedBox(width: 12),
                // Privacy toggle
                Expanded(
                  child: _ToggleChip(
                    label: 'Private',
                    icon: Icons.lock_outline_rounded,
                    value: _isPrivate,
                    onChanged: (v) => setState(() => _isPrivate = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Notes
            Text(
              'Notes',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 6),
            _SheetTextField(
              controller: _notesController,
              hint: 'Additional details...',
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            // Submit button
            DKButton(
              label: 'Add Condition',
              variant: DKButtonVariant.gradient,
              icon: Icons.add_rounded,
              fullWidth: true,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  void _autoSelectCategory(String conditionName) {
    final lower = conditionName.toLowerCase();
    if (lower.contains('diabetes')) {
      setState(() => _selectedCategory = HealthCategory.diabetes);
    } else if (lower.contains('hypertension') || lower.contains('blood pressure') || lower.contains('coronary') || lower.contains('heart')) {
      setState(() => _selectedCategory = HealthCategory.cardiovascular);
    } else if (lower.contains('cancer') || lower.contains('brca')) {
      setState(() => _selectedCategory = HealthCategory.cancer);
    } else if (lower.contains('asthma') || lower.contains('respiratory')) {
      setState(() => _selectedCategory = HealthCategory.respiratory);
    } else if (lower.contains('alzheimer') || lower.contains('dementia') || lower.contains('parkinson') || lower.contains('epilepsy')) {
      setState(() => _selectedCategory = HealthCategory.neurological);
    } else if (lower.contains('thyroid') || lower.contains('lupus') || lower.contains('arthritis') || lower.contains('celiac')) {
      setState(() => _selectedCategory = HealthCategory.autoimmune);
    } else if (lower.contains('depression') || lower.contains('anxiety')) {
      setState(() => _selectedCategory = HealthCategory.mental_health);
    } else if (lower.contains('thalassemia') || lower.contains('sickle') || lower.contains('genetic')) {
      setState(() => _selectedCategory = HealthCategory.genetic);
    } else if (lower.contains('allergy')) {
      setState(() => _selectedCategory = HealthCategory.allergy);
    } else if (lower.contains('glaucoma') || lower.contains('color blind') || lower.contains('eye')) {
      setState(() => _selectedCategory = HealthCategory.eye);
    } else if (lower.contains('osteoporosis') || lower.contains('bone')) {
      setState(() => _selectedCategory = HealthCategory.bone);
    } else if (lower.contains('kidney')) {
      setState(() => _selectedCategory = HealthCategory.kidney);
    } else if (lower.contains('liver') || lower.contains('cirrhosis')) {
      setState(() => _selectedCategory = HealthCategory.liver);
    } else if (lower.contains('migraine')) {
      setState(() => _selectedCategory = HealthCategory.neurological);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Sheet Text Field
// ═══════════════════════════════════════════════════════════════════════

class _SheetTextField extends StatelessWidget {
  const _SheetTextField({
    required this.controller,
    required this.hint,
    this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 14,
        color: KinrelColors.textWhite,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: KinrelColors.textDim,
        ),
        filled: true,
        fillColor: KinrelColors.darkElevated,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide(
              color: KinrelColors.orange.withValues(alpha: 0.5), width: 1.5),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Category Selector
// ═══════════════════════════════════════════════════════════════════════

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.selected,
    required this.onSelect,
  });

  final HealthCategory selected;
  final ValueChanged<HealthCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: HealthCategory.values.map((cat) {
        final isSelected = cat == selected;
        final color = categoryColor(cat);
        return GestureDetector(
          onTap: () => onSelect(cat),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.2)
                  : KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(KinrelRadius.full),
              border: Border.all(
                color: isSelected
                    ? color.withValues(alpha: 0.5)
                    : const Color(0xFF3A3A4A),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(categoryIcon(cat), size: 12, color: color),
                const SizedBox(width: 4),
                Text(
                  categoryLabel(cat),
                  style: KinrelTypography.micro.copyWith(
                    color: isSelected ? color : KinrelColors.textDim,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Severity Selector
// ═══════════════════════════════════════════════════════════════════════

class _SeveritySelector extends StatelessWidget {
  const _SeveritySelector({
    required this.selected,
    required this.onSelect,
  });

  final Severity selected;
  final ValueChanged<Severity> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: Severity.values.map((sev) {
        final isSelected = sev == selected;
        final color = severityColor(sev);
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelect(sev),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.2)
                    : KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: isSelected
                      ? color.withValues(alpha: 0.5)
                      : const Color(0xFF3A3A4A),
                  width: 1,
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      severityLabel(sev),
                      style: KinrelTypography.labelSmall.copyWith(
                        color: isSelected ? color : KinrelColors.textDim,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Toggle Chip
// ═══════════════════════════════════════════════════════════════════════

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? KinrelColors.orange.withValues(alpha: 0.15)
              : KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: value
                ? KinrelColors.orange.withValues(alpha: 0.4)
                : const Color(0xFF3A3A4A),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: value ? KinrelColors.orange : KinrelColors.textDim),
            const SizedBox(width: 6),
            Text(
              label,
              style: KinrelTypography.labelSmall.copyWith(
                color: value ? KinrelColors.orange : KinrelColors.textDim,
                fontWeight: value ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
