// lib/features/health_heritage/presentation/health_heritage_screen.dart
//
// DAXELO KINREL — Family Health Heritage Screen
//
// Features:
//   - Header with medical icon, export & risk calc buttons
//   - Risk Score Card (circular progress, animated)
//   - Health Insights Cards (horizontal scroll, "Take Action")
//   - Inheritance Pattern Visualization
//   - Category Breakdown (grid of category cards)
//   - Search + View Toggle (list / tree / timeline)
//   - Conditions List / Generation Tree / Health Timeline
//   - Add Condition FAB (enhanced bottom sheet)
//   - Condition Detail Sheet (on tap)
//   - Genetic Risk Calculator Sheet
//   - Health Report Export
//
// Design: Dark theme primary, orange/amber accents

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/health_heritage_provider.dart';
import '../../core/utils/device_tier.dart';

// ═══════════════════════════════════════════════════════════════════════
// View mode enum
// ═══════════════════════════════════════════════════════════════════════

enum _ViewMode { list, tree, timeline }

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
  _ViewMode _viewMode = _ViewMode.list;
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
    final inheritancePatterns = ref.watch(inheritancePatternsProvider);

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── Header ──────────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildHeader()),

          // ── Risk Score Card ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: _RiskScoreCard(summary: summary, animation: _animController),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Health Insights ─────────────────────────────────────────
          if (insights.isNotEmpty)
            SliverToBoxAdapter(child: _InsightsSection(insights: insights)),

          if (insights.isNotEmpty)
            const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── Inheritance Patterns ────────────────────────────────────
          if (inheritancePatterns.isNotEmpty)
            SliverToBoxAdapter(
              child: _InheritancePatternSection(patterns: inheritancePatterns),
            ),

          if (inheritancePatterns.isNotEmpty)
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

          // ── Conditions View ─────────────────────────────────────────
          switch (_viewMode) {
            _ViewMode.list => _buildConditionsList(filteredConditions),
            _ViewMode.tree => _buildGenerationTree(heritageState),
            _ViewMode.timeline => _buildTimelineView(),
          },

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
            // Export button
            GestureDetector(
              onTap: _showExportReport,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  border: Border.all(color: const Color(0xFF3A3A4A), width: 1),
                ),
                child: const Icon(
                  Icons.ios_share_rounded,
                  color: KinrelColors.orange,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Risk calculator button
            GestureDetector(
              onTap: _showGeneticRiskSheet,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  border: Border.all(color: const Color(0xFF3A3A4A), width: 1),
                ),
                child: const Icon(
                  Icons.science_rounded,
                  color: KinrelColors.amber,
                  size: 18,
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
                ref.read(healthHeritageProvider.notifier).setSearchQuery(value);
              },
            ),
          ),
          const SizedBox(width: 8),
          // View mode toggle
          _ViewModeToggle(
            currentMode: _viewMode,
            onModeChanged: (mode) => setState(() => _viewMode = mode),
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
        delegate: SliverChildBuilderDelegate((context, index) {
          final condition = conditions[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < conditions.length - 1 ? 12 : 0,
            ),
            child: _ConditionCard(
              condition: condition,
              animDelay: index * 0.05,
              onTap: () => _showConditionDetailSheet(condition),
            ),
          );
        }, childCount: conditions.length),
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
        delegate: SliverChildBuilderDelegate((context, genIndex) {
          final gen = sortedGens[genIndex];
          final genConditions = byGeneration[gen] ?? [];
          final genLabel = _generationLabel(gen);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkElevated,
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                      border: Border.all(
                        color: const Color(0xFF3A3A4A),
                        width: 1,
                      ),
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
              ...genConditions.map(
                (condition) => Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 30),
                  child: GestureDetector(
                    onTap: () => _showConditionDetailSheet(condition),
                    child: _GenerationConditionCard(condition: condition),
                  ),
                ),
              ),
              if (genIndex < sortedGens.length - 1) const SizedBox(height: 20),
            ],
          );
        }, childCount: sortedGens.length),
      ),
    );
  }

  // ── Timeline View ───────────────────────────────────────────────────

  Widget _buildTimelineView() {
    final events = ref.watch(healthTimelineProvider);
    if (events.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Center(
            child: Text(
              'No events to display',
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
        delegate: SliverChildBuilderDelegate((context, index) {
          final event = events[index];
          return _HealthTimelineEventCard(event: event, index: index);
        }, childCount: events.length),
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
      builder: (context) => const _AddConditionSheet(),
    );
  }

  // ── Condition Detail Bottom Sheet ───────────────────────────────────

  void _showConditionDetailSheet(HealthCondition condition) {
    final allConditions = ref.read(healthHeritageProvider).conditions;
    final related = allConditions
        .where((c) => condition.relatedConditions.contains(c.id))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) => _ConditionDetailSheet(
        condition: condition,
        relatedConditions: related,
        allConditions: allConditions,
      ),
    );
  }

  // ── Genetic Risk Calculator Sheet ───────────────────────────────────

  void _showGeneticRiskSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (context) => const _GeneticRiskCalculatorSheet(),
    );
  }

  // ── Export Report ───────────────────────────────────────────────────

  void _showExportReport() {
    final heritageState = ref.read(healthHeritageProvider);
    final notifier = ref.read(healthHeritageProvider.notifier);
    final report = notifier.generateHealthReport(
      heritageState.conditions,
      heritageState.summary,
    );
    Clipboard.setData(ClipboardData(text: report));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: KinrelColors.darkElevated,
        content: Text(
          'Health report copied to clipboard!',
          style: KinrelTypography.bodyMedium.copyWith(
            color: KinrelColors.textWhite,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// View Mode Toggle
// ═══════════════════════════════════════════════════════════════════════

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({
    required this.currentMode,
    required this.onModeChanged,
  });

  final _ViewMode currentMode;
  final ValueChanged<_ViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: const Color(0xFF3A3A4A), width: 1),
      ),
      child: PopupMenuButton<_ViewMode>(
        padding: EdgeInsets.zero,
        offset: const Offset(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
        ),
        color: KinrelColors.darkElevated,
        onSelected: onModeChanged,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _ViewMode.list,
            child: Row(
              children: [
                Icon(
                  Icons.list_rounded,
                  size: 16,
                  color: currentMode == _ViewMode.list
                      ? KinrelColors.orange
                      : KinrelColors.textSilver,
                ),
                const SizedBox(width: 8),
                Text(
                  'List',
                  style: KinrelTypography.bodySmall.copyWith(
                    color: currentMode == _ViewMode.list
                        ? KinrelColors.orange
                        : KinrelColors.textWhite,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: _ViewMode.tree,
            child: Row(
              children: [
                Icon(
                  Icons.account_tree_rounded,
                  size: 16,
                  color: currentMode == _ViewMode.tree
                      ? KinrelColors.orange
                      : KinrelColors.textSilver,
                ),
                const SizedBox(width: 8),
                Text(
                  'Tree',
                  style: KinrelTypography.bodySmall.copyWith(
                    color: currentMode == _ViewMode.tree
                        ? KinrelColors.orange
                        : KinrelColors.textWhite,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: _ViewMode.timeline,
            child: Row(
              children: [
                Icon(
                  Icons.timeline_rounded,
                  size: 16,
                  color: currentMode == _ViewMode.timeline
                      ? KinrelColors.orange
                      : KinrelColors.textSilver,
                ),
                const SizedBox(width: 8),
                Text(
                  'Timeline',
                  style: KinrelTypography.bodySmall.copyWith(
                    color: currentMode == _ViewMode.timeline
                        ? KinrelColors.orange
                        : KinrelColors.textWhite,
                  ),
                ),
              ],
            ),
          ),
        ],
        child: Center(
          child: Icon(
            currentMode == _ViewMode.list
                ? Icons.list_rounded
                : currentMode == _ViewMode.tree
                ? Icons.account_tree_rounded
                : Icons.timeline_rounded,
            color: KinrelColors.orange,
            size: 20,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Risk Score Card
// ═══════════════════════════════════════════════════════════════════════

class _RiskScoreCard extends StatelessWidget {
  const _RiskScoreCard({required this.summary, required this.animation});

  final FamilyHealthSummary? summary;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final riskScore = summary?.riskScore ?? 0.0;
    final riskPercent = (riskScore * 100).round();
    final riskLevel = summary?.riskLevelText ?? 'Low';

    final animatedPercent = Tween<double>(begin: 0, end: riskScore * 100)
        .maybeAnimate(
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
                colors: [Color(0xFF1E1412), KinrelColors.darkCard],
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _riskLevelColor(
                            riskLevel,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                            KinrelRadius.full,
                          ),
                          border: Border.all(
                            color: _riskLevelColor(
                              riskLevel,
                            ).withValues(alpha: 0.4),
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
        .maybeAnimate(onPlay: (c) => c.forward())
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
          gradientColors: const [KinrelColors.orange, KinrelColors.amber],
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

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

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
              Icon(
                Icons.lightbulb_outline_rounded,
                size: 18,
                color: KinrelColors.orange,
              ),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          height: 150,
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
        return const Color(0xFFEF4444);
      case InsightType.recommendation:
        return const Color(0xFF22C55E);
      case InsightType.pattern:
        return const Color(0xFF3B82F6);
      case InsightType.trend:
        return const Color(0xFF8B5CF6);
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
            border: Border.all(color: accent.withValues(alpha: 0.3), width: 1),
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
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  insight.description,
                  style: KinrelTypography.bodySmall.copyWith(
                    color: KinrelColors.textSilver,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (insight.actionLabel != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      insight.actionLabel!,
                      style: KinrelTypography.micro.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        )
        .maybeAnimate(onPlay: (c) => c.forward())
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
// Inheritance Pattern Section
// ═══════════════════════════════════════════════════════════════════════

class _InheritancePatternSection extends StatelessWidget {
  const _InheritancePatternSection({required this.patterns});

  final List<InheritancePattern> patterns;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Row(
            children: [
              Icon(
                Icons.account_tree_rounded,
                size: 18,
                color: KinrelColors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                'Inheritance Patterns',
                style: KinrelTypography.headlineSmall.copyWith(
                  color: KinrelColors.textWhite,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: patterns.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return _InheritancePatternCard(
                pattern: patterns[index],
                index: index,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InheritancePatternCard extends StatelessWidget {
  const _InheritancePatternCard({required this.pattern, required this.index});

  final InheritancePattern pattern;
  final int index;

  @override
  Widget build(BuildContext context) {
    final catColor = categoryColor(pattern.category);
    final genLabels = ['GGP', 'GP', 'P', 'CG'];

    return Container(
          width: 240,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(
              color: catColor.withValues(alpha: 0.3),
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
                      color: catColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(KinrelRadius.sm),
                    ),
                    child: Icon(
                      categoryIcon(pattern.category),
                      size: 14,
                      color: catColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pattern.conditionName,
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
              const SizedBox(height: 10),
              // Inheritance path: row of dots per generation
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(4, (genIndex) {
                  final gen = genIndex + 1;
                  final hasCondition = pattern.affectedMembers.containsKey(gen);
                  final affected = pattern.affectedMembers[gen] ?? [];

                  return Column(
                    children: [
                      // Dot
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasCondition
                              ? KinrelColors.orange.withValues(alpha: 0.2)
                              : const Color(0xFF2A2A3D),
                          border: Border.all(
                            color: hasCondition
                                ? KinrelColors.orange
                                : const Color(0xFF3A3A4A),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: hasCondition
                              ? Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: KinrelColors.orange,
                                )
                              : affected.isEmpty
                              ? Text(
                                  '?',
                                  style: KinrelTypography.micro.copyWith(
                                    color: KinrelColors.textDim,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        genLabels[genIndex],
                        style: KinrelTypography.micro.copyWith(
                          color: hasCondition
                              ? KinrelColors.orange
                              : KinrelColors.textDim,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasCondition && affected.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            affected.first.split(' ').first,
                            style: KinrelTypography.micro.copyWith(
                              color: KinrelColors.textSilver,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ],
          ),
        )
        .maybeAnimate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: KinrelMotion.normal,
          delay: Duration(milliseconds: index * 60),
        )
        .slideX(
          begin: 0.15,
          end: 0,
          duration: KinrelMotion.normal,
          delay: Duration(milliseconds: index * 60),
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
              Icon(
                Icons.category_rounded,
                size: 18,
                color: KinrelColors.orange,
              ),
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
        .maybeAnimate(onPlay: (c) => c.forward())
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
    this.onTap,
  });

  final HealthCondition condition;
  final double animDelay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final catColor = condition.categoryColorValue;
    final sevColor = condition.severityColorValue;

    return GestureDetector(
          onTap: onTap,
          child: Container(
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                      Text(
                        condition.diagnosedPersonName,
                        style: KinrelTypography.bodySmall.copyWith(
                          color: KinrelColors.textSilver,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(
                                KinrelRadius.full,
                              ),
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: sevColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                KinrelRadius.full,
                              ),
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
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: KinrelColors.darkElevated,
                                borderRadius: BorderRadius.circular(
                                  KinrelRadius.full,
                                ),
                                border: Border.all(
                                  color: const Color(0xFF3A3A4A),
                                  width: 0.5,
                                ),
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
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: KinrelColors.orange.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: KinrelColors.orange.withValues(
                                  alpha: 0.3,
                                ),
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
          ),
        )
        .maybeAnimate(onPlay: (c) => c.forward())
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
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: sevColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
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
// Health Timeline Event Card
// ═══════════════════════════════════════════════════════════════════════

class _HealthTimelineEventCard extends StatelessWidget {
  const _HealthTimelineEventCard({required this.event, required this.index});

  final HealthTimelineEvent event;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = event.condition;
    final catColor = c.categoryColorValue;
    final sevColor = c.severityColorValue;

    return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline column
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: catColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: catColor.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        width: 2,
                        color: const Color(0xFF3A3A4A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Event content
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard,
                    borderRadius: BorderRadius.circular(KinrelRadius.lg),
                    border: Border.all(
                      color: c.isHereditary
                          ? KinrelColors.orange.withValues(alpha: 0.2)
                          : const Color(0xFF2A2A3D),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(
                                KinrelRadius.xs,
                              ),
                            ),
                            child: Icon(c.icon, size: 12, color: catColor),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.name,
                              style: KinrelTypography.labelSmall.copyWith(
                                color: KinrelColors.textWhite,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (c.isHereditary)
                            Icon(
                              Icons.biotech_rounded,
                              size: 12,
                              color: KinrelColors.orange,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          DKAvatar(
                            initials: c.diagnosedPersonName
                                .split(' ')
                                .map((n) => n.isNotEmpty ? n[0] : '')
                                .take(2)
                                .join(),
                            size: DKAvatarSize.sm,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.diagnosedPersonName,
                                  style: KinrelTypography.bodySmall.copyWith(
                                    color: KinrelColors.textWhite,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Gen ${c.generation}${c.ageOfOnset != null ? " · Age ${c.ageOfOnset}" : ""}',
                                  style: KinrelTypography.micro.copyWith(
                                    color: KinrelColors.textSilver,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: sevColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                KinrelRadius.full,
                              ),
                            ),
                            child: Text(
                              c.severityLabelValue,
                              style: KinrelTypography.micro.copyWith(
                                color: sevColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        )
        .maybeAnimate(onPlay: (c) => c.forward())
        .fadeIn(
          duration: KinrelMotion.normal,
          delay: Duration(milliseconds: index * 50),
        )
        .slideX(
          begin: 0.1,
          end: 0,
          duration: KinrelMotion.normal,
          delay: Duration(milliseconds: index * 50),
        );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Condition Detail Sheet
// ═══════════════════════════════════════════════════════════════════════

class _ConditionDetailSheet extends StatelessWidget {
  const _ConditionDetailSheet({
    required this.condition,
    required this.relatedConditions,
    required this.allConditions,
  });

  final HealthCondition condition;
  final List<HealthCondition> relatedConditions;
  final List<HealthCondition> allConditions;

  @override
  Widget build(BuildContext context) {
    final catColor = condition.categoryColorValue;
    final sevColor = condition.severityColorValue;

    // Affected family members with same condition
    final sameConditionMembers = allConditions
        .where((c) => c.name == condition.name && c.id != condition.id)
        .toList();

    // Recommended screenings
    final screenings = <String>[];
    if (condition.isHereditary) {
      screenings.add('Genetic counseling');
      screenings.add('Family screening for ${condition.name}');
    }
    if (condition.category == HealthCategory.cardiovascular) {
      screenings.add('Lipid profile');
      screenings.add('ECG / Echo');
    }
    if (condition.category == HealthCategory.diabetes) {
      screenings.add('HbA1c test');
      screenings.add('Glucose tolerance test');
    }
    if (condition.category == HealthCategory.cancer) {
      screenings.add('BRCA genetic test');
      screenings.add('Regular mammography / screening');
    }

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
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    border: Border.all(color: catColor.withValues(alpha: 0.3)),
                  ),
                  child: Icon(condition.icon, color: catColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    condition.name,
                    style: KinrelTypography.headlineMedium.copyWith(
                      color: KinrelColors.textWhite,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Info badges
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DetailBadge(
                  label: condition.categoryLabelValue,
                  color: catColor,
                ),
                _DetailBadge(
                  label: condition.severityLabelValue,
                  color: sevColor,
                ),
                if (condition.ageOfOnset != null)
                  _DetailBadge(
                    label: 'Age ${condition.ageOfOnset}',
                    color: KinrelColors.amber,
                  ),
                if (condition.isHereditary)
                  _DetailBadge(label: 'Hereditary', color: KinrelColors.orange),
                if (condition.isPrivate)
                  _DetailBadge(label: 'Private', color: KinrelColors.textDim),
                _DetailBadge(
                  label: 'Gen ${condition.generation}',
                  color: KinrelColors.orange,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Person
            Row(
              children: [
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
                const SizedBox(width: 10),
                Text(
                  condition.diagnosedPersonName,
                  style: KinrelTypography.labelLarge.copyWith(
                    color: KinrelColors.textWhite,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Notes
            if (condition.notes != null && condition.notes!.isNotEmpty) ...[
              Text(
                'Notes',
                style: KinrelTypography.labelMedium.copyWith(
                  color: KinrelColors.textSilver,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: KinrelColors.darkElevated,
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  border: Border.all(color: const Color(0xFF3A3A4A), width: 1),
                ),
                child: Text(
                  condition.notes!,
                  style: KinrelTypography.bodySmall.copyWith(
                    color: KinrelColors.textWhite,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Affected family members
            if (sameConditionMembers.isNotEmpty) ...[
              Text(
                'Other Affected Members',
                style: KinrelTypography.labelMedium.copyWith(
                  color: KinrelColors.textSilver,
                ),
              ),
              const SizedBox(height: 6),
              ...sameConditionMembers.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      DKAvatar(
                        initials: c.diagnosedPersonName
                            .split(' ')
                            .map((n) => n.isNotEmpty ? n[0] : '')
                            .take(2)
                            .join(),
                        size: DKAvatarSize.sm,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${c.diagnosedPersonName} (Gen ${c.generation})',
                        style: KinrelTypography.bodySmall.copyWith(
                          color: KinrelColors.textWhite,
                        ),
                      ),
                      const Spacer(),
                      if (c.ageOfOnset != null)
                        Text(
                          'Age ${c.ageOfOnset}',
                          style: KinrelTypography.micro.copyWith(
                            color: KinrelColors.textSilver,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Related conditions
            if (relatedConditions.isNotEmpty) ...[
              Text(
                'Related Conditions',
                style: KinrelTypography.labelMedium.copyWith(
                  color: KinrelColors.textSilver,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: relatedConditions
                    .map(
                      (rc) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: rc.categoryColorValue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(
                            KinrelRadius.full,
                          ),
                          border: Border.all(
                            color: rc.categoryColorValue.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              rc.icon,
                              size: 12,
                              color: rc.categoryColorValue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              rc.name,
                              style: KinrelTypography.micro.copyWith(
                                color: rc.categoryColorValue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],

            // Recommended screenings
            if (screenings.isNotEmpty) ...[
              Text(
                'Recommended Screenings',
                style: KinrelTypography.labelMedium.copyWith(
                  color: KinrelColors.textSilver,
                ),
              ),
              const SizedBox(height: 6),
              ...screenings.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 14,
                        color: const Color(0xFF22C55E),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s,
                        style: KinrelTypography.bodySmall.copyWith(
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailBadge extends StatelessWidget {
  const _DetailBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KinrelRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        label,
        style: KinrelTypography.micro.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Genetic Risk Calculator Sheet
// ═══════════════════════════════════════════════════════════════════════

class _GeneticRiskCalculatorSheet extends ConsumerStatefulWidget {
  const _GeneticRiskCalculatorSheet();

  @override
  ConsumerState<_GeneticRiskCalculatorSheet> createState() =>
      _GeneticRiskCalculatorSheetState();
}

class _GeneticRiskCalculatorSheetState
    extends ConsumerState<_GeneticRiskCalculatorSheet> {
  String? _person1Id;
  String? _person2Id;
  GeneticRiskAssessment? _assessment;

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(uniqueFamilyMembersProvider);

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
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: KinrelGradients.igniteGradient,
                    borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  ),
                  child: const Icon(
                    Icons.science_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Genetic Risk Calculator',
                  style: KinrelTypography.headlineMedium.copyWith(
                    color: KinrelColors.textWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Person 1
            Text(
              'First Family Member',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 6),
            _MemberDropdown(
              members: members,
              selectedId: _person1Id,
              hint: 'Select member...',
              onChanged: (id) => setState(() {
                _person1Id = id;
                _assessment = null;
              }),
            ),
            const SizedBox(height: 14),

            // Person 2
            Text(
              'Second Family Member',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 6),
            _MemberDropdown(
              members: members,
              selectedId: _person2Id,
              hint: 'Select member...',
              onChanged: (id) => setState(() {
                _person2Id = id;
                _assessment = null;
              }),
            ),
            const SizedBox(height: 16),

            // Calculate button
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap:
                    _person1Id != null &&
                        _person2Id != null &&
                        _person1Id != _person2Id
                    ? _calculate
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient:
                        _person1Id != null &&
                            _person2Id != null &&
                            _person1Id != _person2Id
                        ? KinrelGradients.igniteGradient
                        : LinearGradient(
                            colors: [
                              KinrelColors.darkElevated,
                              KinrelColors.darkElevated,
                            ],
                          ),
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                  ),
                  child: Center(
                    child: Text(
                      'Calculate Risk',
                      style: KinrelTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Results
            if (_assessment != null) ...[
              const SizedBox(height: 20),
              _buildResults(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final a = _assessment!;
    final riskColor = a.riskLevel == 'Low'
        ? const Color(0xFF22C55E)
        : a.riskLevel == 'Moderate'
        ? const Color(0xFFF59E0B)
        : a.riskLevel == 'High'
        ? const Color(0xFFF97316)
        : const Color(0xFFEF4444);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Overall risk
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: riskColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(color: riskColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(
                '${a.overallRiskPercent.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: riskColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${a.riskLevel} Risk for Children',
                style: KinrelTypography.labelMedium.copyWith(
                  color: riskColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Estimated risk for children of ${a.person1Name} & ${a.person2Name}',
                style: KinrelTypography.bodySmall.copyWith(
                  color: KinrelColors.textSilver,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Carrier alerts
        if (a.carrierAlerts.isNotEmpty) ...[
          Text(
            '⚠️ Carrier Alerts',
            style: KinrelTypography.labelMedium.copyWith(
              color: const Color(0xFFEF4444),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          ...a.carrierAlerts.map(
            (alert) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                alert,
                style: KinrelTypography.bodySmall.copyWith(
                  color: const Color(0xFFEF4444),
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Potential conditions
        if (a.potentialConditions.isNotEmpty) ...[
          Text(
            'Conditions That Could Be Passed On',
            style: KinrelTypography.labelMedium.copyWith(
              color: KinrelColors.textSilver,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          ...a.potentialConditions.map(
            (pc) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
                border: Border.all(color: const Color(0xFF3A3A4A)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pc.conditionName,
                          style: KinrelTypography.labelSmall.copyWith(
                            color: KinrelColors.textWhite,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${pc.inheritanceMode} · From: ${pc.fromPerson}',
                          style: KinrelTypography.micro.copyWith(
                            color: KinrelColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: severityColor(pc.severity).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(KinrelRadius.full),
                    ),
                    child: Text(
                      '${pc.riskPercent.toStringAsFixed(0)}%',
                      style: KinrelTypography.micro.copyWith(
                        color: severityColor(pc.severity),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Recommendations
        if (a.recommendations.isNotEmpty) ...[
          Text(
            'Recommendations',
            style: KinrelTypography.labelMedium.copyWith(
              color: KinrelColors.textSilver,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          ...a.recommendations.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.arrow_right_rounded,
                    size: 16,
                    color: KinrelColors.orange,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      r,
                      style: KinrelTypography.bodySmall.copyWith(
                        color: KinrelColors.textWhite,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _calculate() {
    if (_person1Id == null || _person2Id == null) return;
    final notifier = ref.read(healthHeritageProvider.notifier);
    final conditions = ref.read(healthHeritageProvider).conditions;
    final assessment = notifier.calculateGeneticRisk(
      conditions,
      _person1Id!,
      _person2Id!,
    );
    setState(() => _assessment = assessment);
  }
}

class _MemberDropdown extends StatelessWidget {
  const _MemberDropdown({
    required this.members,
    required this.selectedId,
    required this.hint,
    required this.onChanged,
  });

  final List<FamilyMember> members;
  final String? selectedId;
  final String hint;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = members.cast<FamilyMember?>().firstWhere(
      (m) => m?.id == selectedId,
      orElse: () => null,
    );

    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(color: const Color(0xFF3A3A4A)),
        ),
        child: Row(
          children: [
            if (selected != null)
              DKAvatar(
                initials: selected.name
                    .split(' ')
                    .map((n) => n.isNotEmpty ? n[0] : '')
                    .take(2)
                    .join(),
                size: DKAvatarSize.sm,
              )
            else
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF3A3A4A)),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: KinrelColors.textDim,
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selected?.name ?? hint,
                style: KinrelTypography.bodyMedium.copyWith(
                  color: selected != null
                      ? KinrelColors.textWhite
                      : KinrelColors.textDim,
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: KinrelColors.textSilver,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A4A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ...members.map(
              (m) => ListTile(
                leading: DKAvatar(
                  initials: m.name
                      .split(' ')
                      .map((n) => n.isNotEmpty ? n[0] : '')
                      .take(2)
                      .join(),
                  size: DKAvatarSize.sm,
                ),
                title: Text(
                  m.name,
                  style: KinrelTypography.bodyMedium.copyWith(
                    color: m.id == selectedId
                        ? KinrelColors.orange
                        : KinrelColors.textWhite,
                  ),
                ),
                subtitle: Text(
                  '${m.generationLabel} · ${m.conditionCount} conditions',
                  style: KinrelTypography.bodySmall.copyWith(
                    color: KinrelColors.textSilver,
                  ),
                ),
                trailing: m.id == selectedId
                    ? Icon(
                        Icons.check_circle,
                        color: KinrelColors.orange,
                        size: 20,
                      )
                    : null,
                onTap: () {
                  onChanged(m.id);
                  Navigator.of(ctx).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Enhanced Add Condition Bottom Sheet
// ═══════════════════════════════════════════════════════════════════════

class _AddConditionSheet extends ConsumerStatefulWidget {
  const _AddConditionSheet();

  @override
  ConsumerState<_AddConditionSheet> createState() => _AddConditionSheetState();
}

class _AddConditionSheetState extends ConsumerState<_AddConditionSheet> {
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _ageController = TextEditingController();
  final _personController = TextEditingController();
  HealthCategory _selectedCategory = HealthCategory.other;
  Severity _selectedSeverity = Severity.moderate;
  bool _isHereditary = false;
  bool _isPrivate = false;
  String? _selectedPersonId;
  int _autoGeneration = 4;
  List<String> _suggestions = [];

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

  void _onPersonSelected(String name, String? personId) {
    setState(() {
      _personController.text = name;
      _selectedPersonId = personId;
    });
    if (personId != null) {
      // Auto-detect generation
      final conditions = ref.read(healthHeritageProvider).conditions;
      final existing = conditions.cast<HealthCondition?>().firstWhere(
        (c) => c?.diagnosedPersonId == personId,
        orElse: () => null,
      );
      if (existing != null) {
        setState(() => _autoGeneration = existing.generation);
      }
    }
  }

  void _submit() {
    if (_nameController.text.isEmpty || _personController.text.isEmpty) {
      return;
    }

    // Panchang Easter egg: check if today is Tuesday or Saturday
    final now = DateTime.now();
    final isAuspicious =
        now.weekday == DateTime.tuesday || now.weekday == DateTime.saturday;
    final panchangNote = isAuspicious ? ' [Added on an auspicious day 🙏]' : '';

    final condition = HealthCondition(
      id: 'hc_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameController.text,
      category: _selectedCategory,
      severity: _selectedSeverity,
      isHereditary: _isHereditary,
      notes: _notesController.text.isEmpty
          ? null
          : _notesController.text + panchangNote,
      diagnosedPersonId: _selectedPersonId ?? 'person_custom',
      diagnosedPersonName: _personController.text,
      familyId: 'sharma_family',
      ageOfOnset: _ageController.text.isEmpty
          ? null
          : int.tryParse(_ageController.text),
      isPrivate: _isPrivate,
      generation: _autoGeneration,
    );

    ref.read(healthHeritageProvider.notifier).addCondition(condition);

    // Show panchang warning as Easter egg
    if (isAuspicious) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: KinrelColors.darkElevated,
          content: Text(
            '🙏 Added on an auspicious day! May good health prevail.',
            style: KinrelTypography.bodyMedium.copyWith(
              color: KinrelColors.orange,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.md),
          ),
        ),
      );
    }

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
    final members = ref.watch(uniqueFamilyMembersProvider);

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

            // Person selector with link to family members
            Text(
              'Family Member',
              style: KinrelTypography.labelMedium.copyWith(
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: 6),
            _PersonSelectorField(
              controller: _personController,
              members: members,
              onSelected: _onPersonSelected,
            ),
            if (_selectedPersonId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Auto-detected: Generation $_autoGeneration',
                  style: KinrelTypography.micro.copyWith(
                    color: KinrelColors.orange,
                  ),
                ),
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
                  border: Border.all(color: const Color(0xFF3A3A4A), width: 1),
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
            const SizedBox(width: 6),
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

            // Hereditary toggle with explanation
            Row(
              children: [
                Expanded(
                  child: _ToggleChip(
                    label: 'Hereditary',
                    icon: Icons.biotech_rounded,
                    isActive: _isHereditary,
                    onTap: () => setState(() => _isHereditary = !_isHereditary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ToggleChip(
                    label: 'Private',
                    icon: Icons.lock_outline_rounded,
                    isActive: _isPrivate,
                    onTap: () => setState(() => _isPrivate = !_isPrivate),
                  ),
                ),
              ],
            ),
            if (_isHereditary)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: KinrelColors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    border: Border.all(
                      color: KinrelColors.orange.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 14,
                        color: KinrelColors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Marking as hereditary will include this condition in genetic risk calculations and inheritance pattern visualizations.',
                          style: KinrelTypography.bodySmall.copyWith(
                            color: KinrelColors.orange.withValues(alpha: 0.8),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
              maxLines: 3,
            ),
            const SizedBox(height: 20),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _submit,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                  child: Center(
                    child: Text(
                      'Add Condition',
                      style: KinrelTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _autoSelectCategory(String conditionName) {
    final name = conditionName.toLowerCase();
    if (name.contains('diabetes')) {
      setState(() => _selectedCategory = HealthCategory.diabetes);
    } else if (name.contains('hypertension') ||
        name.contains('coronary') ||
        name.contains('heart')) {
      setState(() => _selectedCategory = HealthCategory.cardiovascular);
    } else if (name.contains('cancer') || name.contains('brca')) {
      setState(() => _selectedCategory = HealthCategory.cancer);
    } else if (name.contains('asthma') || name.contains('copd')) {
      setState(() => _selectedCategory = HealthCategory.respiratory);
    } else if (name.contains('thalassemia') ||
        name.contains('sickle') ||
        name.contains('color blind')) {
      setState(() => _selectedCategory = HealthCategory.genetic);
    } else if (name.contains('thyroid')) {
      setState(() => _selectedCategory = HealthCategory.autoimmune);
    } else if (name.contains('depression') || name.contains('anxiety')) {
      setState(() => _selectedCategory = HealthCategory.mentalHealth);
    } else if (name.contains('alzheimer') ||
        name.contains('parkinson') ||
        name.contains('epilepsy')) {
      setState(() => _selectedCategory = HealthCategory.neurological);
    } else if (name.contains('glaucoma') || name.contains('cataract')) {
      setState(() => _selectedCategory = HealthCategory.eye);
    } else if (name.contains('kidney')) {
      setState(() => _selectedCategory = HealthCategory.kidney);
    } else if (name.contains('liver') || name.contains('cirrhosis')) {
      setState(() => _selectedCategory = HealthCategory.liver);
    } else if (name.contains('osteoporosis') || name.contains('arthritis')) {
      setState(() => _selectedCategory = HealthCategory.bone);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Person Selector Field
// ═══════════════════════════════════════════════════════════════════════

class _PersonSelectorField extends StatelessWidget {
  const _PersonSelectorField({
    required this.controller,
    required this.members,
    required this.onSelected,
  });

  final TextEditingController controller;
  final List<FamilyMember> members;
  final void Function(String name, String? personId) onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showMemberPicker(context),
      child: AbsorbPointer(
        child: _SheetTextField(
          controller: controller,
          hint: 'Select family member or type name...',
          suffixIcon: Icons.people_outline_rounded,
        ),
      ),
    );
  }

  void _showMemberPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KinrelColors.darkElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A4A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Select Family Member',
              style: KinrelTypography.headlineSmall.copyWith(
                color: KinrelColors.textWhite,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...members.map(
              (m) => ListTile(
                leading: DKAvatar(
                  initials: m.name
                      .split(' ')
                      .map((n) => n.isNotEmpty ? n[0] : '')
                      .take(2)
                      .join(),
                  size: DKAvatarSize.sm,
                ),
                title: Text(
                  m.name,
                  style: KinrelTypography.bodyMedium.copyWith(
                    color: KinrelColors.textWhite,
                  ),
                ),
                subtitle: Text(
                  '${m.generationLabel} · ${m.conditionCount} conditions',
                  style: KinrelTypography.bodySmall.copyWith(
                    color: KinrelColors.textSilver,
                  ),
                ),
                onTap: () {
                  onSelected(m.name, m.id);
                  Navigator.of(ctx).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Shared Sheet Widgets
// ═══════════════════════════════════════════════════════════════════════

class _SheetTextField extends StatelessWidget {
  const _SheetTextField({
    required this.controller,
    required this.hint,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final IconData? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: KinrelTypography.bodyMedium.copyWith(
        color: KinrelColors.textWhite,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: KinrelTypography.bodyMedium.copyWith(
          color: KinrelColors.textDim,
        ),
        filled: true,
        fillColor: KinrelColors.darkElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide(
            color: KinrelColors.orange.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        suffixIcon: suffixIcon != null
            ? Icon(suffixIcon, color: KinrelColors.textDim, size: 18)
            : null,
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({required this.selected, required this.onSelect});

  final HealthCategory selected;
  final ValueChanged<HealthCategory> onSelect;

  static const _cats = HealthCategory.values;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final cat = _cats[index];
          final color = categoryColor(cat);
          final isSelected = selected == cat;
          return GestureDetector(
            onTap: () => onSelect(cat),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.15)
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
                      color: isSelected ? color : KinrelColors.textSilver,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SeveritySelector extends StatelessWidget {
  const _SeveritySelector({required this.selected, required this.onSelect});

  final Severity selected;
  final ValueChanged<Severity> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: Severity.values.map((sev) {
        final color = severityColor(sev);
        final isSelected = selected == sev;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelect(sev),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.15)
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
                child: Text(
                  severityLabel(sev),
                  style: KinrelTypography.micro.copyWith(
                    color: isSelected ? color : KinrelColors.textSilver,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? KinrelColors.orange.withValues(alpha: 0.12)
              : KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: isActive
                ? KinrelColors.orange.withValues(alpha: 0.4)
                : const Color(0xFF3A3A4A),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? KinrelColors.orange : KinrelColors.textDim,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: KinrelTypography.labelSmall.copyWith(
                color: isActive ? KinrelColors.orange : KinrelColors.textSilver,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
