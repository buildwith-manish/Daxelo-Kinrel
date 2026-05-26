// lib/features/health_heritage/providers/health_heritage_provider.dart
//
// DAXELO KINREL — Family Health Heritage State Management
//
// Tracks hereditary conditions across generations, generates
// health insights, and computes family risk scores.
//
// Demo data: 12 conditions across 4 generations (Sharma family)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ═══════════════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════════════

/// Health condition categories.
enum HealthCategory {
  cardiovascular,
  diabetes,
  cancer,
  neurological,
  respiratory,
  autoimmune,
  mental_health,
  genetic,
  allergy,
  eye,
  bone,
  kidney,
  liver,
  other,
}

/// Severity levels for health conditions.
enum Severity {
  low,
  moderate,
  high,
  critical,
}

/// Insight types for health recommendations and warnings.
enum InsightType {
  warning,
  recommendation,
  pattern,
  trend,
}

// ═══════════════════════════════════════════════════════════════════════
// Category Helpers
// ═══════════════════════════════════════════════════════════════════════

/// Maps [HealthCategory] to a display color.
Color categoryColor(HealthCategory category) {
  switch (category) {
    case HealthCategory.cardiovascular:
      return const Color(0xFFEF4444); // red
    case HealthCategory.diabetes:
      return const Color(0xFFF97316); // orange
    case HealthCategory.cancer:
      return const Color(0xFFFF6B6B); // coral
    case HealthCategory.neurological:
      return const Color(0xFF3B82F6); // blue
    case HealthCategory.respiratory:
      return const Color(0xFF14B8A6); // teal
    case HealthCategory.autoimmune:
      return const Color(0xFF8B5CF6); // purple
    case HealthCategory.mental_health:
      return const Color(0xFF6366F1); // indigo
    case HealthCategory.genetic:
      return const Color(0xFFF59E0B); // amber
    case HealthCategory.allergy:
      return const Color(0xFF22C55E); // green
    case HealthCategory.eye:
      return const Color(0xFF06B6D4); // cyan
    case HealthCategory.bone:
      return const Color(0xFF92400E); // brown
    case HealthCategory.kidney:
      return const Color(0xFFEA580C); // deep orange
    case HealthCategory.liver:
      return const Color(0xFFEAB308); // yellow
    case HealthCategory.other:
      return const Color(0xFF9CA3AF); // silver
  }
}

/// Maps [HealthCategory] to a display icon.
IconData categoryIcon(HealthCategory category) {
  switch (category) {
    case HealthCategory.cardiovascular:
      return Icons.favorite_rounded;
    case HealthCategory.diabetes:
      return Icons.bloodtype_rounded;
    case HealthCategory.cancer:
      return Icons.coronavirus_rounded;
    case HealthCategory.neurological:
      return Icons.psychology_rounded;
    case HealthCategory.respiratory:
      return Icons.air_rounded;
    case HealthCategory.autoimmune:
      return Icons.shield_rounded;
    case HealthCategory.mental_health:
      return Icons.sentiment_slightly_dissatisfied_rounded;
    case HealthCategory.genetic:
      return Icons.biotech_rounded;
    case HealthCategory.allergy:
      return Icons.warning_amber_rounded;
    case HealthCategory.eye:
      return Icons.visibility_rounded;
    case HealthCategory.bone:
      return Icons.accessibility_rounded;
    case HealthCategory.kidney:
      return Icons.water_drop_rounded;
    case HealthCategory.liver:
      return Icons.local_hospital_rounded;
    case HealthCategory.other:
      return Icons.more_horiz_rounded;
  }
}

/// Maps [HealthCategory] to a display label.
String categoryLabel(HealthCategory category) {
  switch (category) {
    case HealthCategory.cardiovascular:
      return 'Cardiovascular';
    case HealthCategory.diabetes:
      return 'Diabetes';
    case HealthCategory.cancer:
      return 'Cancer';
    case HealthCategory.neurological:
      return 'Neurological';
    case HealthCategory.respiratory:
      return 'Respiratory';
    case HealthCategory.autoimmune:
      return 'Autoimmune';
    case HealthCategory.mental_health:
      return 'Mental Health';
    case HealthCategory.genetic:
      return 'Genetic';
    case HealthCategory.allergy:
      return 'Allergy';
    case HealthCategory.eye:
      return 'Eye';
    case HealthCategory.bone:
      return 'Bone';
    case HealthCategory.kidney:
      return 'Kidney';
    case HealthCategory.liver:
      return 'Liver';
    case HealthCategory.other:
      return 'Other';
  }
}

/// Maps [Severity] to a display color.
Color severityColor(Severity severity) {
  switch (severity) {
    case Severity.low:
      return const Color(0xFF22C55E); // green
    case Severity.moderate:
      return const Color(0xFFF59E0B); // amber
    case Severity.high:
      return const Color(0xFFF97316); // orange
    case Severity.critical:
      return const Color(0xFFEF4444); // red
  }
}

/// Maps [Severity] to a display label.
String severityLabel(Severity severity) {
  switch (severity) {
    case Severity.low:
      return 'Low';
    case Severity.moderate:
      return 'Moderate';
    case Severity.high:
      return 'High';
    case Severity.critical:
      return 'Critical';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HealthCondition
// ═══════════════════════════════════════════════════════════════════════

/// A single health condition record for a family member.
class HealthCondition {
  const HealthCondition({
    required this.id,
    required this.name,
    required this.category,
    required this.severity,
    this.diagnosedDate,
    required this.isHereditary,
    this.notes,
    required this.diagnosedPersonId,
    required this.diagnosedPersonName,
    required this.familyId,
    this.relatedConditions = const [],
    this.ageOfOnset,
    this.isPrivate = false,
    this.generation = 1,
  });

  final String id;
  final String name;
  final HealthCategory category;
  final Severity severity;
  final DateTime? diagnosedDate;
  final bool isHereditary;
  final String? notes;
  final String diagnosedPersonId;
  final String diagnosedPersonName;
  final String familyId;
  final List<String> relatedConditions;
  final int? ageOfOnset;
  final bool isPrivate;
  final int generation;

  /// Computed color from category.
  Color get categoryColorValue => categoryColor(category);

  /// Computed color from severity.
  Color get severityColorValue => severityColor(severity);

  /// Category icon.
  IconData get icon => categoryIcon(category);

  /// Category label.
  String get categoryLabelValue => categoryLabel(category);

  /// Severity label.
  String get severityLabelValue => severityLabel(severity);

  HealthCondition copyWith({
    String? id,
    String? name,
    HealthCategory? category,
    Severity? severity,
    DateTime? diagnosedDate,
    bool? isHereditary,
    String? notes,
    String? diagnosedPersonId,
    String? diagnosedPersonName,
    String? familyId,
    List<String>? relatedConditions,
    int? ageOfOnset,
    bool? isPrivate,
    int? generation,
  }) {
    return HealthCondition(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      severity: severity ?? this.severity,
      diagnosedDate: diagnosedDate ?? this.diagnosedDate,
      isHereditary: isHereditary ?? this.isHereditary,
      notes: notes ?? this.notes,
      diagnosedPersonId: diagnosedPersonId ?? this.diagnosedPersonId,
      diagnosedPersonName: diagnosedPersonName ?? this.diagnosedPersonName,
      familyId: familyId ?? this.familyId,
      relatedConditions: relatedConditions ?? this.relatedConditions,
      ageOfOnset: ageOfOnset ?? this.ageOfOnset,
      isPrivate: isPrivate ?? this.isPrivate,
      generation: generation ?? this.generation,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HealthInsight
// ═══════════════════════════════════════════════════════════════════════

/// A generated insight about family health patterns.
class HealthInsight {
  const HealthInsight({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    this.relatedConditionIds = const [],
    required this.icon,
    required this.color,
  });

  final String id;
  final String title;
  final String description;
  final InsightType type;
  final List<String> relatedConditionIds;
  final IconData icon;
  final Color color;
}

// ═══════════════════════════════════════════════════════════════════════
// FamilyHealthSummary
// ═══════════════════════════════════════════════════════════════════════

/// Aggregated health summary for an entire family.
class FamilyHealthSummary {
  const FamilyHealthSummary({
    required this.familyId,
    this.totalConditions = 0,
    this.hereditaryConditions = 0,
    this.conditionsByCategory = const {},
    this.conditionsByGeneration = const {},
    this.topConditions = const [],
    this.insights = const [],
    this.riskScore = 0.0,
    this.averageAgeOfOnset,
  });

  final String familyId;
  final int totalConditions;
  final int hereditaryConditions;
  final Map<HealthCategory, int> conditionsByCategory;
  final Map<int, int> conditionsByGeneration;
  final List<HealthCondition> topConditions;
  final List<HealthInsight> insights;
  final double riskScore;
  final double? averageAgeOfOnset;

  /// Risk level text.
  String get riskLevelText {
    if (riskScore < 0.25) return 'Low';
    if (riskScore < 0.50) return 'Moderate';
    if (riskScore < 0.75) return 'High';
    return 'Critical';
  }

  /// Risk score as percentage 0-100.
  int get riskPercentage => (riskScore * 100).round();

  FamilyHealthSummary copyWith({
    String? familyId,
    int? totalConditions,
    int? hereditaryConditions,
    Map<HealthCategory, int>? conditionsByCategory,
    Map<int, int>? conditionsByGeneration,
    List<HealthCondition>? topConditions,
    List<HealthInsight>? insights,
    double? riskScore,
    double? averageAgeOfOnset,
  }) {
    return FamilyHealthSummary(
      familyId: familyId ?? this.familyId,
      totalConditions: totalConditions ?? this.totalConditions,
      hereditaryConditions: hereditaryConditions ?? this.hereditaryConditions,
      conditionsByCategory: conditionsByCategory ?? this.conditionsByCategory,
      conditionsByGeneration: conditionsByGeneration ?? this.conditionsByGeneration,
      topConditions: topConditions ?? this.topConditions,
      insights: insights ?? this.insights,
      riskScore: riskScore ?? this.riskScore,
      averageAgeOfOnset: averageAgeOfOnset ?? this.averageAgeOfOnset,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HealthHeritageState
// ═══════════════════════════════════════════════════════════════════════

/// Immutable state for the health heritage feature.
class HealthHeritageState {
  const HealthHeritageState({
    this.conditions = const [],
    this.summary,
    this.selectedCategory,
    this.searchQuery = '',
    this.showPrivate = false,
    this.isLoading = false,
  });

  final List<HealthCondition> conditions;
  final FamilyHealthSummary? summary;
  final HealthCategory? selectedCategory;
  final String searchQuery;
  final bool showPrivate;
  final bool isLoading;

  HealthHeritageState copyWith({
    List<HealthCondition>? conditions,
    FamilyHealthSummary? summary,
    HealthCategory? selectedCategory,
    String? searchQuery,
    bool? showPrivate,
    bool? isLoading,
  }) {
    return HealthHeritageState(
      conditions: conditions ?? this.conditions,
      summary: summary ?? this.summary,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      showPrivate: showPrivate ?? this.showPrivate,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HealthHeritageNotifier
// ═══════════════════════════════════════════════════════════════════════

class HealthHeritageNotifier extends StateNotifier<HealthHeritageState> {
  HealthHeritageNotifier() : super(const HealthHeritageState()) {
    _loadDemoData();
  }

  // ── Actions ────────────────────────────────────────────────────────

  void addCondition(HealthCondition condition) {
    final updated = [...state.conditions, condition];
    state = state.copyWith(conditions: updated);
    _regenerateSummary(updated);
  }

  void updateCondition(HealthCondition condition) {
    final updated = state.conditions.map((c) {
      return c.id == condition.id ? condition : c;
    }).toList();
    state = state.copyWith(conditions: updated);
    _regenerateSummary(updated);
  }

  void deleteCondition(String conditionId) {
    final updated =
        state.conditions.where((c) => c.id != conditionId).toList();
    state = state.copyWith(conditions: updated);
    _regenerateSummary(updated);
  }

  void togglePrivacy(String conditionId) {
    final updated = state.conditions.map((c) {
      if (c.id == conditionId) {
        return c.copyWith(isPrivate: !c.isPrivate);
      }
      return c;
    }).toList();
    state = state.copyWith(conditions: updated);
    _regenerateSummary(updated);
  }

  void setCategory(HealthCategory? category) {
    // Use direct construction because copyWith with ?? can't set null
    state = HealthHeritageState(
      conditions: state.conditions,
      summary: state.summary,
      selectedCategory: category,
      searchQuery: state.searchQuery,
      showPrivate: state.showPrivate,
      isLoading: state.isLoading,
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setShowPrivate(bool show) {
    state = state.copyWith(showPrivate: show);
  }

  // ── Summary Generation ─────────────────────────────────────────────

  void _regenerateSummary(List<HealthCondition> conditions) {
    final summary = generateSummary(conditions);
    state = state.copyWith(summary: summary);
  }

  FamilyHealthSummary generateSummary(List<HealthCondition> conditions) {
    if (conditions.isEmpty) {
      return const FamilyHealthSummary(familyId: 'sharma_family');
    }

    // Count by category
    final byCategory = <HealthCategory, int>{};
    for (final c in conditions) {
      byCategory[c.category] = (byCategory[c.category] ?? 0) + 1;
    }

    // Count by generation
    final byGeneration = <int, int>{};
    for (final c in conditions) {
      byGeneration[c.generation] = (byGeneration[c.generation] ?? 0) + 1;
    }

    // Hereditary count
    final hereditaryCount =
        conditions.where((c) => c.isHereditary).length;

    // Risk score calculation
    double riskScore = 0.0;
    if (conditions.isNotEmpty) {
      // Base risk from hereditary conditions
      final hereditaryRatio = hereditaryCount / conditions.length;
      // Severity weight
      double severityWeight = 0;
      for (final c in conditions) {
        switch (c.severity) {
          case Severity.low:
            severityWeight += 0.25;
          case Severity.moderate:
            severityWeight += 0.5;
          case Severity.high:
            severityWeight += 0.75;
          case Severity.critical:
            severityWeight += 1.0;
        }
      }
      severityWeight = severityWeight / conditions.length;

      // Category diversity weight (more categories = higher risk)
      final categoryDiversity = byCategory.length / HealthCategory.values.length;

      riskScore = (hereditaryRatio * 0.4 +
              severityWeight * 0.35 +
              categoryDiversity * 0.25)
          .clamp(0.0, 1.0);
    }

    // Average age of onset
    final agesOfOnset =
        conditions.where((c) => c.ageOfOnset != null).map((c) => c.ageOfOnset!.toDouble()).toList();
    final avgAge = agesOfOnset.isNotEmpty
        ? agesOfOnset.reduce((a, b) => a + b) / agesOfOnset.length
        : null;

    // Top conditions (most severe + hereditary first)
    final sorted = List<HealthCondition>.from(conditions)
      ..sort((a, b) {
        // Hereditary first
        if (a.isHereditary != b.isHereditary) {
          return a.isHereditary ? -1 : 1;
        }
        // Then by severity
        final severityOrder = {
          Severity.critical: 4,
          Severity.high: 3,
          Severity.moderate: 2,
          Severity.low: 1,
        };
        return severityOrder[b.severity]!.compareTo(severityOrder[a.severity]!);
      });
    final topConditions = sorted.take(5).toList();

    // Generate insights
    final insights = generateInsights(conditions, riskScore);

    return FamilyHealthSummary(
      familyId: 'sharma_family',
      totalConditions: conditions.length,
      hereditaryConditions: hereditaryCount,
      conditionsByCategory: byCategory,
      conditionsByGeneration: byGeneration,
      topConditions: topConditions,
      insights: insights,
      riskScore: riskScore,
      averageAgeOfOnset: avgAge,
    );
  }

  // ── Insight Generation ─────────────────────────────────────────────

  List<HealthInsight> generateInsights(
    List<HealthCondition> conditions,
    double riskScore,
  ) {
    final insights = <HealthInsight>[];
    final byCategory = <HealthCategory, int>{};
    for (final c in conditions) {
      byCategory[c.category] = (byCategory[c.category] ?? 0) + 1;
    }

    // Warning: High hereditary risk
    final hereditaryCount = conditions.where((c) => c.isHereditary).length;
    if (hereditaryCount >= 3) {
      insights.add(HealthInsight(
        id: 'insight_hereditary_high',
        title: 'High Hereditary Risk',
        description:
            '$hereditaryCount hereditary conditions detected across generations. Consider genetic counseling for the family.',
        type: InsightType.warning,
        relatedConditionIds: conditions
            .where((c) => c.isHereditary)
            .map((c) => c.id)
            .toList(),
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFEF4444),
      ));
    }

    // Warning: Early onset pattern
    final earlyOnset = conditions.where((c) => c.ageOfOnset != null && c.ageOfOnset! < 40).toList();
    if (earlyOnset.length >= 2) {
      insights.add(HealthInsight(
        id: 'insight_early_onset',
        title: 'Early Onset Pattern',
        description:
            '${earlyOnset.length} conditions with onset before age 40. Early screening recommended for younger family members.',
        type: InsightType.warning,
        relatedConditionIds: earlyOnset.map((c) => c.id).toList(),
        icon: Icons.schedule_rounded,
        color: const Color(0xFFF97316),
      ));
    }

    // Pattern: Cardiovascular cluster
    final cardioCount = byCategory[HealthCategory.cardiovascular] ?? 0;
    if (cardioCount >= 2) {
      insights.add(HealthInsight(
        id: 'insight_cardio_cluster',
        title: 'Cardiovascular Pattern',
        description:
            '$cardioCount cardiovascular conditions found. Heart health monitoring is crucial for the family.',
        type: InsightType.pattern,
        relatedConditionIds: conditions
            .where((c) => c.category == HealthCategory.cardiovascular)
            .map((c) => c.id)
            .toList(),
        icon: Icons.favorite_rounded,
        color: const Color(0xFF3B82F6),
      ));
    }

    // Pattern: Diabetes cluster
    final diabetesCount = byCategory[HealthCategory.diabetes] ?? 0;
    if (diabetesCount >= 2) {
      insights.add(HealthInsight(
        id: 'insight_diabetes_cluster',
        title: 'Diabetes Pattern',
        description:
            '$diabetesCount diabetes conditions across generations. Regular glucose monitoring advised.',
        type: InsightType.pattern,
        relatedConditionIds: conditions
            .where((c) => c.category == HealthCategory.diabetes)
            .map((c) => c.id)
            .toList(),
        icon: Icons.bloodtype_rounded,
        color: const Color(0xFF3B82F6),
      ));
    }

    // Recommendation: Preventive screening
    if (riskScore > 0.3) {
      insights.add(HealthInsight(
        id: 'insight_screening',
        title: 'Preventive Screening',
        description:
            'Based on your family health profile, annual health checkups and genetic screening are recommended.',
        type: InsightType.recommendation,
        icon: Icons.health_and_safety_rounded,
        color: const Color(0xFF22C55E),
      ));
    }

    // Recommendation: Lifestyle changes
    if (byCategory.containsKey(HealthCategory.cardiovascular) ||
        byCategory.containsKey(HealthCategory.diabetes)) {
      insights.add(HealthInsight(
        id: 'insight_lifestyle',
        title: 'Lifestyle Recommendations',
        description:
            'Heart-healthy diet, regular exercise, and stress management can help reduce risk of inherited cardiovascular and diabetic conditions.',
        type: InsightType.recommendation,
        icon: Icons.self_improvement_rounded,
        color: const Color(0xFF22C55E),
      ));
    }

    // Trend: Increasing severity across generations
    final gen1Critical = conditions
        .where((c) => c.generation == 1 && c.severity == Severity.critical)
        .length;
    final gen3Critical = conditions
        .where((c) => c.generation == 3 && c.severity.index >= Severity.moderate.index)
        .length;
    if (gen1Critical > 0 && gen3Critical > 0) {
      insights.add(HealthInsight(
        id: 'insight_generation_trend',
        title: 'Generational Trend',
        description:
            'Conditions appear to persist across multiple generations. Early intervention may help break the cycle.',
        type: InsightType.trend,
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF8B5CF6),
      ));
    }

    // Warning: Thalassemia carrier risk
    final thalConditions = conditions.where((c) =>
        c.name.toLowerCase().contains('thalassemia')).toList();
    if (thalConditions.isNotEmpty) {
      insights.add(HealthInsight(
        id: 'insight_thalassemia',
        title: 'Thalassemia Carrier Alert',
        description:
            'Thalassemia trait detected in the family. Genetic counseling recommended before family planning.',
        type: InsightType.warning,
        relatedConditionIds: thalConditions.map((c) => c.id).toList(),
        icon: Icons.biotech_rounded,
        color: const Color(0xFFEF4444),
      ));
    }

    return insights;
  }

  // ── Demo Data ──────────────────────────────────────────────────────

  void _loadDemoData() {
    // Sharma Family — 4 generations of health conditions
    // Generation 1: Great-grandparents
    // Generation 2: Grandparents
    // Generation 3: Parents
    // Generation 4: Current generation

    const conditions = <HealthCondition>[
      // ── Generation 1 (Great-grandparents) ─────────────────────────
      HealthCondition(
        id: 'hc_001',
        name: 'Type 2 Diabetes',
        category: HealthCategory.diabetes,
        severity: Severity.high,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Diagnosed in late 50s, managed with oral medication',
        diagnosedPersonId: 'person_ggf1',
        diagnosedPersonName: 'Rameshwar Sharma',
        familyId: 'sharma_family',
        relatedConditions: ['hc_005', 'hc_009'],
        ageOfOnset: 55,
        isPrivate: false,
        generation: 1,
      ),
      HealthCondition(
        id: 'hc_002',
        name: 'Hypertension',
        category: HealthCategory.cardiovascular,
        severity: Severity.moderate,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'High blood pressure since age 50',
        diagnosedPersonId: 'person_ggf1',
        diagnosedPersonName: 'Rameshwar Sharma',
        familyId: 'sharma_family',
        relatedConditions: ['hc_006'],
        ageOfOnset: 50,
        isPrivate: false,
        generation: 1,
      ),
      HealthCondition(
        id: 'hc_003',
        name: 'Coronary Artery Disease',
        category: HealthCategory.cardiovascular,
        severity: Severity.critical,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Triple bypass surgery at age 62',
        diagnosedPersonId: 'person_ggm1',
        diagnosedPersonName: 'Savitri Sharma',
        familyId: 'sharma_family',
        relatedConditions: ['hc_002', 'hc_006'],
        ageOfOnset: 60,
        isPrivate: false,
        generation: 1,
      ),
      HealthCondition(
        id: 'hc_004',
        name: 'Thalassemia Trait',
        category: HealthCategory.genetic,
        severity: Severity.low,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Beta thalassemia minor — carrier status',
        diagnosedPersonId: 'person_ggm1',
        diagnosedPersonName: 'Savitri Sharma',
        familyId: 'sharma_family',
        relatedConditions: ['hc_012'],
        ageOfOnset: 20,
        isPrivate: true,
        generation: 1,
      ),

      // ── Generation 2 (Grandparents) ──────────────────────────────
      HealthCondition(
        id: 'hc_005',
        name: 'Type 2 Diabetes',
        category: HealthCategory.diabetes,
        severity: Severity.moderate,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Onset at 48, controlled with diet and metformin',
        diagnosedPersonId: 'person_gf1',
        diagnosedPersonName: 'Rajendra Sharma',
        familyId: 'sharma_family',
        relatedConditions: ['hc_001', 'hc_009'],
        ageOfOnset: 48,
        isPrivate: false,
        generation: 2,
      ),
      HealthCondition(
        id: 'hc_006',
        name: 'Hypertension',
        category: HealthCategory.cardiovascular,
        severity: Severity.high,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Required medication from age 45',
        diagnosedPersonId: 'person_gf1',
        diagnosedPersonName: 'Rajendra Sharma',
        familyId: 'sharma_family',
        relatedConditions: ['hc_002'],
        ageOfOnset: 45,
        isPrivate: false,
        generation: 2,
      ),
      HealthCondition(
        id: 'hc_007',
        name: 'Asthma',
        category: HealthCategory.respiratory,
        severity: Severity.moderate,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Seasonal asthma, triggered by dust and cold',
        diagnosedPersonId: 'person_gm1',
        diagnosedPersonName: 'Meera Sharma',
        familyId: 'sharma_family',
        relatedConditions: ['hc_011'],
        ageOfOnset: 30,
        isPrivate: false,
        generation: 2,
      ),
      HealthCondition(
        id: 'hc_008',
        name: 'Hypothyroidism',
        category: HealthCategory.autoimmune,
        severity: Severity.low,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Underactive thyroid, managed with levothyroxine',
        diagnosedPersonId: 'person_gm1',
        diagnosedPersonName: 'Meera Sharma',
        familyId: 'sharma_family',
        relatedConditions: [],
        ageOfOnset: 42,
        isPrivate: false,
        generation: 2,
      ),

      // ── Generation 3 (Parents) ──────────────────────────────────
      HealthCondition(
        id: 'hc_009',
        name: 'Type 2 Diabetes',
        category: HealthCategory.diabetes,
        severity: Severity.moderate,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Pre-diabetic at 38, diagnosed at 42',
        diagnosedPersonId: 'person_f1',
        diagnosedPersonName: 'Vikram Sharma',
        familyId: 'sharma_family',
        relatedConditions: ['hc_001', 'hc_005'],
        ageOfOnset: 42,
        isPrivate: false,
        generation: 3,
      ),
      HealthCondition(
        id: 'hc_010',
        name: 'Breast Cancer (BRCA2)',
        category: HealthCategory.cancer,
        severity: Severity.critical,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'BRCA2 mutation carrier, diagnosed at 44. Surgery and chemotherapy completed.',
        diagnosedPersonId: 'person_m1',
        diagnosedPersonName: 'Priya Sharma',
        familyId: 'sharma_family',
        relatedConditions: [],
        ageOfOnset: 44,
        isPrivate: true,
        generation: 3,
      ),
      HealthCondition(
        id: 'hc_011',
        name: 'Asthma',
        category: HealthCategory.respiratory,
        severity: Severity.low,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Mild childhood asthma, mostly resolved',
        diagnosedPersonId: 'person_f1',
        diagnosedPersonName: 'Vikram Sharma',
        familyId: 'sharma_family',
        relatedConditions: ['hc_007'],
        ageOfOnset: 8,
        isPrivate: false,
        generation: 3,
      ),

      // ── Generation 4 (Current) ──────────────────────────────────
      HealthCondition(
        id: 'hc_012',
        name: 'Thalassemia Trait',
        category: HealthCategory.genetic,
        severity: Severity.low,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Beta thalassemia minor — carrier, detected during routine blood test',
        diagnosedPersonId: 'person_s1',
        diagnosedPersonName: 'Arjun Sharma',
        familyId: 'sharma_family',
        relatedConditions: ['hc_004'],
        ageOfOnset: 18,
        isPrivate: false,
        generation: 4,
      ),
      HealthCondition(
        id: 'hc_013',
        name: 'Color Blindness',
        category: HealthCategory.eye,
        severity: Severity.low,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Red-green color blindness (deuteranomaly)',
        diagnosedPersonId: 'person_s1',
        diagnosedPersonName: 'Arjun Sharma',
        familyId: 'sharma_family',
        relatedConditions: [],
        ageOfOnset: 10,
        isPrivate: false,
        generation: 4,
      ),
      HealthCondition(
        id: 'hc_014',
        name: 'Sickle Cell Trait',
        category: HealthCategory.genetic,
        severity: Severity.low,
        diagnosedDate: null,
        isHereditary: true,
        notes: 'Sickle cell carrier — no symptoms, important for family planning',
        diagnosedPersonId: 'person_d1',
        diagnosedPersonName: 'Neha Sharma',
        familyId: 'sharma_family',
        relatedConditions: ['hc_004', 'hc_012'],
        ageOfOnset: 22,
        isPrivate: true,
        generation: 4,
      ),
    ];

    state = state.copyWith(conditions: conditions);
    _regenerateSummary(conditions);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════

/// Global health heritage provider.
final healthHeritageProvider =
    StateNotifierProvider<HealthHeritageNotifier, HealthHeritageState>(
  (ref) => HealthHeritageNotifier(),
);

/// Filtered conditions based on category, search, and privacy.
final filteredConditionsProvider = Provider<List<HealthCondition>>((ref) {
  final state = ref.watch(healthHeritageProvider);
  var conditions = state.conditions;

  // Filter by category
  if (state.selectedCategory != null) {
    conditions =
        conditions.where((c) => c.category == state.selectedCategory).toList();
  }

  // Filter by search query
  if (state.searchQuery.isNotEmpty) {
    final query = state.searchQuery.toLowerCase();
    conditions = conditions.where((c) {
      return c.name.toLowerCase().contains(query) ||
          c.diagnosedPersonName.toLowerCase().contains(query) ||
          c.categoryLabelValue.toLowerCase().contains(query);
    }).toList();
  }

  // Filter private unless showing
  if (!state.showPrivate) {
    conditions = conditions.where((c) => !c.isPrivate).toList();
  }

  return conditions;
});

/// Computed family health summary.
final healthSummaryProvider = Provider<FamilyHealthSummary?>((ref) {
  return ref.watch(healthHeritageProvider).summary;
});

/// Computed health insights.
final healthInsightsProvider = Provider<List<HealthInsight>>((ref) {
  final summary = ref.watch(healthSummaryProvider);
  return summary?.insights ?? [];
});

/// Conditions grouped by category.
final conditionsByCategoryProvider =
    Provider<Map<HealthCategory, List<HealthCondition>>>((ref) {
  final conditions = ref.watch(healthHeritageProvider).conditions;
  final map = <HealthCategory, List<HealthCondition>>{};
  for (final c in conditions) {
    (map[c.category] ??= []).add(c);
  }
  return map;
});

/// Conditions grouped by generation.
final conditionsByGenerationProvider =
    Provider<Map<int, List<HealthCondition>>>((ref) {
  final conditions = ref.watch(healthHeritageProvider).conditions;
  final map = <int, List<HealthCondition>>{};
  for (final c in conditions) {
    (map[c.generation] ??= []).add(c);
  }
  return map;
});
