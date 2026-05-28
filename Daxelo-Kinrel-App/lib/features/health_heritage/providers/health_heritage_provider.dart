// lib/features/health_heritage/providers/health_heritage_provider.dart
//
// DAXELO KINREL — Family Health Heritage State Management
//
// Tracks hereditary conditions across generations, generates
// health insights, and computes family risk scores.
//
// Demo data: 14 conditions across 4 generations (Sharma family)
//
// Enhancements:
//   - GeneticRiskAssessment model & provider
//   - HealthTimelineEvent model & provider
//   - Inheritance pattern providers
//   - Enhanced insight engine (earlier onset, carrier couple, missing screening, lifestyle correlation)
//   - Unique family members provider
//   - Health report generation

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
  mentalHealth,
  genetic,
  allergy,
  eye,
  bone,
  kidney,
  liver,
  other,
}

/// Severity levels for health conditions.
enum Severity { low, moderate, high, critical }

/// Insight types for health recommendations and warnings.
enum InsightType { warning, recommendation, pattern, trend }

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
    case HealthCategory.mentalHealth:
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
    case HealthCategory.mentalHealth:
      return Icons.sentiment_dissatisfied_rounded;
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
    case HealthCategory.mentalHealth:
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
    this.actionLabel,
  });

  final String id;
  final String title;
  final String description;
  final InsightType type;
  final List<String> relatedConditionIds;
  final IconData icon;
  final Color color;

  /// Optional action label for "Take Action" button.
  final String? actionLabel;
}

// ═══════════════════════════════════════════════════════════════════════
// GeneticRiskAssessment
// ═══════════════════════════════════════════════════════════════════════

/// Assessment of genetic risk for children of two family members.
class GeneticRiskAssessment {
  const GeneticRiskAssessment({
    required this.person1Name,
    required this.person2Name,
    required this.overallRiskPercent,
    required this.riskLevel,
    required this.potentialConditions,
    required this.carrierAlerts,
    required this.recommendations,
  });

  final String person1Name;
  final String person2Name;

  /// Overall estimated risk percentage (0-100).
  final double overallRiskPercent;

  /// Risk level label.
  final String riskLevel;

  /// Conditions that could be passed on.
  final List<GeneticRiskCondition> potentialConditions;

  /// Alerts for carrier couples (e.g., Thalassemia).
  final List<String> carrierAlerts;

  /// Recommended actions.
  final List<String> recommendations;
}

/// A condition that could be passed to children.
class GeneticRiskCondition {
  const GeneticRiskCondition({
    required this.conditionName,
    required this.inheritanceMode,
    required this.riskPercent,
    required this.fromPerson,
    required this.severity,
  });

  final String conditionName;
  final String inheritanceMode;
  final double riskPercent;
  final String fromPerson;
  final Severity severity;
}

// ═══════════════════════════════════════════════════════════════════════
// HealthTimelineEvent
// ═══════════════════════════════════════════════════════════════════════

/// A health event positioned on a chronological timeline.
class HealthTimelineEvent {
  const HealthTimelineEvent({required this.condition, required this.sortKey});

  final HealthCondition condition;

  /// Sort key: ageOfOnset if available, otherwise generation * 100.
  final double sortKey;
}

// ═══════════════════════════════════════════════════════════════════════
// InheritancePattern
// ═══════════════════════════════════════════════════════════════════════

/// Represents the inheritance path for a specific hereditary condition.
class InheritancePattern {
  const InheritancePattern({
    required this.conditionName,
    required this.category,
    required this.affectedMembers,
    required this.generations,
  });

  final String conditionName;
  final HealthCategory category;

  /// Members who have this condition, keyed by generation.
  final Map<int, List<String>> affectedMembers;

  /// Which generations this condition appears in.
  final List<int> generations;
}

// ═══════════════════════════════════════════════════════════════════════
// FamilyMember
// ═══════════════════════════════════════════════════════════════════════

/// Lightweight family member reference derived from conditions.
class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.name,
    required this.generation,
    required this.conditionCount,
  });

  final String id;
  final String name;
  final int generation;
  final int conditionCount;

  String get generationLabel {
    switch (generation) {
      case 1:
        return 'Great-Grandparent';
      case 2:
        return 'Grandparent';
      case 3:
        return 'Parent';
      case 4:
        return 'Current';
      default:
        return 'Gen $generation';
    }
  }
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
      conditionsByGeneration:
          conditionsByGeneration ?? this.conditionsByGeneration,
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
    final updated = state.conditions.where((c) => c.id != conditionId).toList();
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
    final hereditaryCount = conditions.where((c) => c.isHereditary).length;

    // Risk score calculation
    double riskScore = 0.0;
    if (conditions.isNotEmpty) {
      final hereditaryRatio = hereditaryCount / conditions.length;
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

      final categoryDiversity =
          byCategory.length / HealthCategory.values.length;

      riskScore =
          (hereditaryRatio * 0.4 +
                  severityWeight * 0.35 +
                  categoryDiversity * 0.25)
              .clamp(0.0, 1.0);
    }

    // Average age of onset
    final agesOfOnset = conditions
        .where((c) => c.ageOfOnset != null)
        .map((c) => c.ageOfOnset!.toDouble())
        .toList();
    final avgAge = agesOfOnset.isNotEmpty
        ? agesOfOnset.reduce((a, b) => a + b) / agesOfOnset.length
        : null;

    // Top conditions (most severe + hereditary first)
    final sorted = List<HealthCondition>.from(conditions)
      ..sort((a, b) {
        if (a.isHereditary != b.isHereditary) {
          return a.isHereditary ? -1 : 1;
        }
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

  // ── Enhanced Insight Generation ────────────────────────────────────

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
      insights.add(
        HealthInsight(
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
          actionLabel: 'Schedule Counseling',
        ),
      );
    }

    // Warning: Early onset pattern
    final earlyOnset = conditions
        .where((c) => c.ageOfOnset != null && c.ageOfOnset! < 40)
        .toList();
    if (earlyOnset.length >= 2) {
      insights.add(
        HealthInsight(
          id: 'insight_early_onset',
          title: 'Early Onset Pattern',
          description:
              '${earlyOnset.length} conditions with onset before age 40. Early screening recommended for younger family members.',
          type: InsightType.warning,
          relatedConditionIds: earlyOnset.map((c) => c.id).toList(),
          icon: Icons.schedule_rounded,
          color: const Color(0xFFF97316),
          actionLabel: 'Book Screening',
        ),
      );
    }

    // ── NEW: Same Condition, Earlier Onset ──────────────────────────
    // Check if the same condition appears in younger generations at
    // earlier ages.
    final conditionNames = <String>{};
    for (final c in conditions.where(
      (c) => c.isHereditary && c.ageOfOnset != null,
    )) {
      conditionNames.add(c.name);
    }
    for (final name in conditionNames) {
      final matching =
          conditions
              .where((c) => c.name == name && c.ageOfOnset != null)
              .toList()
            ..sort((a, b) => a.generation.compareTo(b.generation));
      if (matching.length >= 2) {
        final oldest = matching.first;
        final newest = matching.last;
        if (newest.ageOfOnset! < oldest.ageOfOnset! &&
            newest.generation > oldest.generation) {
          insights.add(
            HealthInsight(
              id: 'insight_earlier_onset_${name.replaceAll(' ', '_')}',
              title: 'Earlier Onset: $name',
              description:
                  '$name appears at age ${newest.ageOfOnset} in Gen ${newest.generation} vs age ${oldest.ageOfOnset} in Gen ${oldest.generation}. This "anticipation" pattern suggests increasing severity. Early screening is crucial.',
              type: InsightType.trend,
              relatedConditionIds: matching.map((c) => c.id).toList(),
              icon: Icons.trending_down_rounded,
              color: const Color(0xFF8B5CF6),
              actionLabel: 'Learn More',
            ),
          );
          break; // Only show one earlier-onset insight
        }
      }
    }

    // ── NEW: Carrier Couple Alert ───────────────────────────────────
    final carrierConditions = conditions
        .where(
          (c) =>
              c.name.toLowerCase().contains('thalassemia') ||
              c.name.toLowerCase().contains('sickle cell'),
        )
        .toList();
    if (carrierConditions.length >= 2) {
      final personIds = carrierConditions
          .map((c) => c.diagnosedPersonId)
          .toSet();
      if (personIds.length >= 2) {
        insights.add(
          HealthInsight(
            id: 'insight_carrier_couple',
            title: 'Carrier Couple Alert',
            description:
                'Both ${carrierConditions.map((c) => c.diagnosedPersonName).toSet().join(" and ")} carry genetic traits (${carrierConditions.map((c) => c.name).toSet().join(", ")}). Children have 25% chance of inheriting the full condition. Genetic counseling is essential before family planning.',
            type: InsightType.warning,
            relatedConditionIds: carrierConditions.map((c) => c.id).toList(),
            icon: Icons.people_rounded,
            color: const Color(0xFFEF4444),
            actionLabel: 'Get Counseling',
          ),
        );
      }
    }

    // ── NEW: Missing Screening ──────────────────────────────────────
    final hasDiabetes = byCategory.containsKey(HealthCategory.diabetes);
    final hasCardio = byCategory.containsKey(HealthCategory.cardiovascular);
    final hasCancer = byCategory.containsKey(HealthCategory.cancer);
    final missingScreenings = <String>[];
    if (hasDiabetes) missingScreenings.add('HbA1c & glucose tolerance');
    if (hasCardio) missingScreenings.add('lipid profile & ECG');
    if (hasCancer) missingScreenings.add('BRCA genetic test');
    if (missingScreenings.isNotEmpty) {
      insights.add(
        HealthInsight(
          id: 'insight_missing_screening',
          title: 'Missing Screening',
          description:
              'Based on family history, recommended screenings: ${missingScreenings.join(", ")}. Family members in younger generations should prioritize these tests.',
          type: InsightType.recommendation,
          icon: Icons.assignment_rounded,
          color: const Color(0xFF22C55E),
          actionLabel: 'Book Tests',
        ),
      );
    }

    // ── NEW: Lifestyle Correlation ──────────────────────────────────
    if (hasDiabetes && hasCardio) {
      insights.add(
        HealthInsight(
          id: 'insight_lifestyle_correlation',
          title: 'Lifestyle Correlation',
          description:
              'Diabetes and cardiovascular conditions often share lifestyle risk factors (diet, exercise, stress). Addressing these together through lifestyle changes can significantly reduce risk for both conditions.',
          type: InsightType.pattern,
          relatedConditionIds: conditions
              .where(
                (c) =>
                    c.category == HealthCategory.diabetes ||
                    c.category == HealthCategory.cardiovascular,
              )
              .map((c) => c.id)
              .toList(),
          icon: Icons.restaurant_rounded,
          color: const Color(0xFF3B82F6),
          actionLabel: 'View Tips',
        ),
      );
    }

    // Pattern: Cardiovascular cluster
    final cardioCount = byCategory[HealthCategory.cardiovascular] ?? 0;
    if (cardioCount >= 2) {
      insights.add(
        HealthInsight(
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
          actionLabel: 'Heart Health Tips',
        ),
      );
    }

    // Pattern: Diabetes cluster
    final diabetesCount = byCategory[HealthCategory.diabetes] ?? 0;
    if (diabetesCount >= 2) {
      insights.add(
        HealthInsight(
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
          actionLabel: 'Monitor Glucose',
        ),
      );
    }

    // Recommendation: Preventive screening
    if (riskScore > 0.3) {
      insights.add(
        HealthInsight(
          id: 'insight_screening',
          title: 'Preventive Screening',
          description:
              'Based on your family health profile, annual health checkups and genetic screening are recommended.',
          type: InsightType.recommendation,
          icon: Icons.health_and_safety_rounded,
          color: const Color(0xFF22C55E),
          actionLabel: 'Schedule Checkup',
        ),
      );
    }

    // Recommendation: Lifestyle changes
    if (byCategory.containsKey(HealthCategory.cardiovascular) ||
        byCategory.containsKey(HealthCategory.diabetes)) {
      insights.add(
        HealthInsight(
          id: 'insight_lifestyle',
          title: 'Lifestyle Recommendations',
          description:
              'Heart-healthy diet, regular exercise, and stress management can help reduce risk of inherited cardiovascular and diabetic conditions.',
          type: InsightType.recommendation,
          icon: Icons.self_improvement_rounded,
          color: const Color(0xFF22C55E),
          actionLabel: 'View Plan',
        ),
      );
    }

    // Trend: Increasing severity across generations
    final gen1Critical = conditions
        .where((c) => c.generation == 1 && c.severity == Severity.critical)
        .length;
    final gen3Critical = conditions
        .where(
          (c) =>
              c.generation == 3 && c.severity.index >= Severity.moderate.index,
        )
        .length;
    if (gen1Critical > 0 && gen3Critical > 0) {
      insights.add(
        HealthInsight(
          id: 'insight_generation_trend',
          title: 'Generational Trend',
          description:
              'Conditions appear to persist across multiple generations. Early intervention may help break the cycle.',
          type: InsightType.trend,
          icon: Icons.trending_up_rounded,
          color: const Color(0xFF8B5CF6),
          actionLabel: 'View Trends',
        ),
      );
    }

    // Warning: Thalassemia carrier risk
    final thalConditions = conditions
        .where((c) => c.name.toLowerCase().contains('thalassemia'))
        .toList();
    if (thalConditions.isNotEmpty) {
      insights.add(
        HealthInsight(
          id: 'insight_thalassemia',
          title: 'Thalassemia Carrier Alert',
          description:
              'Thalassemia trait detected in the family. Genetic counseling recommended before family planning.',
          type: InsightType.warning,
          relatedConditionIds: thalConditions.map((c) => c.id).toList(),
          icon: Icons.biotech_rounded,
          color: const Color(0xFFEF4444),
          actionLabel: 'Get Tested',
        ),
      );
    }

    return insights;
  }

  // ── Genetic Risk Calculator ────────────────────────────────────────

  GeneticRiskAssessment calculateGeneticRisk(
    List<HealthCondition> allConditions,
    String person1Id,
    String person2Id,
  ) {
    final p1Conditions = allConditions
        .where((c) => c.diagnosedPersonId == person1Id && c.isHereditary)
        .toList();
    final p2Conditions = allConditions
        .where((c) => c.diagnosedPersonId == person2Id && c.isHereditary)
        .toList();

    final potentialConditions = <GeneticRiskCondition>[];
    final carrierAlerts = <String>[];
    final recommendations = <String>[];

    // Collect hereditary conditions from both sides
    final allHereditary = <String, List<HealthCondition>>{};
    for (final c in p1Conditions) {
      (allHereditary[c.name] ??= []).add(c);
    }
    for (final c in p2Conditions) {
      (allHereditary[c.name] ??= []).add(c);
    }

    double totalRisk = 0.0;
    int conditionCount = 0;

    for (final entry in allHereditary.entries) {
      final conds = entry.value;
      final fromP1 = conds.any((c) => c.diagnosedPersonId == person1Id);
      final fromP2 = conds.any((c) => c.diagnosedPersonId == person2Id);
      final primaryCondition = conds.first;

      double riskPercent;
      String inheritanceMode;

      if (fromP1 && fromP2) {
        // Both parents have it — autosomal dominant: 75% risk
        riskPercent = 75.0;
        inheritanceMode = 'Autosomal Dominant (Both)';
      } else {
        // One parent has it
        if (primaryCondition.category == HealthCategory.genetic &&
            primaryCondition.name.toLowerCase().contains('trait')) {
          // Carrier condition — autosomal recessive: 50% carrier, 25% affected
          riskPercent = 25.0;
          inheritanceMode = 'Autosomal Recessive (Carrier)';

          // Check for carrier couple
          final p1HasCarrier = p1Conditions.any(
            (c) =>
                c.name.toLowerCase().contains('thalassemia') ||
                c.name.toLowerCase().contains('sickle cell'),
          );
          final p2HasCarrier = p2Conditions.any(
            (c) =>
                c.name.toLowerCase().contains('thalassemia') ||
                c.name.toLowerCase().contains('sickle cell'),
          );
          if (p1HasCarrier && p2HasCarrier) {
            riskPercent = 25.0;
            inheritanceMode = 'Autosomal Recessive (Both Carriers)';
            carrierAlerts.add(
              'Both parents carry ${primaryCondition.name}. 25% chance child has the full condition!',
            );
          }
        } else {
          // Regular dominant: 50% risk
          riskPercent = 50.0;
          inheritanceMode = 'Autosomal Dominant';
        }
      }

      // Adjust by severity
      switch (primaryCondition.severity) {
        case Severity.low:
          riskPercent *= 0.8;
        case Severity.moderate:
          riskPercent *= 0.9;
        case Severity.high:
          riskPercent *= 1.0;
        case Severity.critical:
          riskPercent *= 1.1;
      }

      // Adjust by age of onset (earlier onset = stronger hereditary signal)
      if (primaryCondition.ageOfOnset != null &&
          primaryCondition.ageOfOnset! < 40) {
        riskPercent *= 1.1;
      }

      riskPercent = riskPercent.clamp(0.0, 95.0);

      potentialConditions.add(
        GeneticRiskCondition(
          conditionName: primaryCondition.name,
          inheritanceMode: inheritanceMode,
          riskPercent: riskPercent,
          fromPerson: fromP1 && fromP2
              ? 'Both'
              : (fromP1
                    ? primaryCondition.diagnosedPersonName
                    : conds
                          .firstWhere((c) => c.diagnosedPersonId == person2Id)
                          .diagnosedPersonName),
          severity: primaryCondition.severity,
        ),
      );

      totalRisk += riskPercent;
      conditionCount++;
    }

    // Overall risk: average of individual risks, weighted by count
    final overallRisk = conditionCount > 0
        ? (totalRisk / conditionCount).clamp(0.0, 95.0)
        : 5.0; // baseline risk if no conditions

    // Risk level
    String riskLevel;
    if (overallRisk < 15) {
      riskLevel = 'Low';
    } else if (overallRisk < 35) {
      riskLevel = 'Moderate';
    } else if (overallRisk < 55) {
      riskLevel = 'High';
    } else {
      riskLevel = 'Critical';
    }

    // Recommendations
    if (carrierAlerts.isNotEmpty) {
      recommendations.add('Seek genetic counseling before family planning');
    }
    if (potentialConditions.any(
      (c) => c.severity == Severity.critical || c.severity == Severity.high,
    )) {
      recommendations.add('Consider preimplantation genetic diagnosis (PGD)');
    }
    recommendations.add('Regular prenatal screening recommended');
    recommendations.add(
      'Consult a geneticist for personalized risk assessment',
    );

    final p1Name = p1Conditions.isNotEmpty
        ? p1Conditions.first.diagnosedPersonName
        : allConditions
              .where((c) => c.diagnosedPersonId == person1Id)
              .first
              .diagnosedPersonName;
    final p2Name = p2Conditions.isNotEmpty
        ? p2Conditions.first.diagnosedPersonName
        : allConditions
              .where((c) => c.diagnosedPersonId == person2Id)
              .first
              .diagnosedPersonName;

    return GeneticRiskAssessment(
      person1Name: p1Name,
      person2Name: p2Name,
      overallRiskPercent: overallRisk,
      riskLevel: riskLevel,
      potentialConditions: potentialConditions,
      carrierAlerts: carrierAlerts,
      recommendations: recommendations,
    );
  }

  // ── Health Report Generation ───────────────────────────────────────

  String generateHealthReport(
    List<HealthCondition> conditions,
    FamilyHealthSummary? summary,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('══════════════════════════════════════════════════');
    buffer.writeln('  KINREL — Family Health Heritage Report');
    buffer.writeln(
      '  Generated: ${DateTime.now().toLocal().toString().split('.').first}',
    );
    buffer.writeln('══════════════════════════════════════════════════');
    buffer.writeln();

    if (summary != null) {
      buffer.writeln('── OVERVIEW ──────────────────────────────────────');
      buffer.writeln(
        'Family Risk Score: ${summary.riskPercentage}% (${summary.riskLevelText} Risk)',
      );
      buffer.writeln('Total Conditions: ${summary.totalConditions}');
      buffer.writeln('Hereditary Conditions: ${summary.hereditaryConditions}');
      if (summary.averageAgeOfOnset != null) {
        buffer.writeln(
          'Average Age of Onset: ${summary.averageAgeOfOnset!.toStringAsFixed(1)} years',
        );
      }
      buffer.writeln();
    }

    // Group by category
    final byCategory = <HealthCategory, List<HealthCondition>>{};
    for (final c in conditions) {
      (byCategory[c.category] ??= []).add(c);
    }

    buffer.writeln('── CONDITIONS BY CATEGORY ─────────────────────────');
    for (final entry in byCategory.entries) {
      buffer.writeln();
      buffer.writeln('  ${categoryLabel(entry.key)} (${entry.value.length})');
      for (final c in entry.value) {
        final hereditaryMarker = c.isHereditary ? '★ HEREDITARY' : '';
        final privateMarker = c.isPrivate ? '🔒' : '';
        buffer.writeln('    • ${c.name} $hereditaryMarker $privateMarker');
        buffer.writeln(
          '      Person: ${c.diagnosedPersonName} (Gen ${c.generation})',
        );
        buffer.writeln(
          '      Severity: ${c.severityLabelValue}${c.ageOfOnset != null ? " | Age of Onset: ${c.ageOfOnset}" : ""}',
        );
        if (c.notes != null && c.notes!.isNotEmpty) {
          buffer.writeln('      Notes: ${c.notes}');
        }
      }
    }
    buffer.writeln();

    // Hereditary conditions highlighted
    final hereditary = conditions.where((c) => c.isHereditary).toList();
    if (hereditary.isNotEmpty) {
      buffer.writeln('── HEREDITARY CONDITIONS (HIGHLIGHTED) ────────────');
      for (final c in hereditary) {
        buffer.writeln('  ★ ${c.name}');
        buffer.writeln(
          '    Inheritance: Gen ${c.generation} → ${c.diagnosedPersonName}',
        );
        buffer.writeln(
          '    Related: ${c.relatedConditions.isNotEmpty ? c.relatedConditions.join(", ") : "None"}',
        );
      }
      buffer.writeln();
    }

    // Insights
    if (summary?.insights.isNotEmpty ?? false) {
      buffer.writeln('── HEALTH INSIGHTS ───────────────────────────────');
      for (final insight in summary!.insights) {
        final typeLabel = insight.type.name.toUpperCase();
        buffer.writeln('  [$typeLabel] ${insight.title}');
        buffer.writeln('    ${insight.description}');
      }
      buffer.writeln();
    }

    buffer.writeln('══════════════════════════════════════════════════');
    buffer.writeln('  Report by Daxelo KinRel — Family Health Heritage');
    buffer.writeln('══════════════════════════════════════════════════');

    return buffer.toString();
  }

  // ── Demo Data ──────────────────────────────────────────────────────

  void _loadDemoData() {
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
        notes:
            'BRCA2 mutation carrier, diagnosed at 44. Surgery and chemotherapy completed.',
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
        notes:
            'Beta thalassemia minor — carrier, detected during routine blood test',
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
        notes:
            'Sickle cell carrier — no symptoms, important for family planning',
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
    conditions = conditions
        .where((c) => c.category == state.selectedCategory)
        .toList();
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

/// Unique family members derived from conditions.
final uniqueFamilyMembersProvider = Provider<List<FamilyMember>>((ref) {
  final conditions = ref.watch(healthHeritageProvider).conditions;
  final memberMap = <String, FamilyMember>{};
  for (final c in conditions) {
    final existing = memberMap[c.diagnosedPersonId];
    if (existing != null) {
      // Update condition count if same person
      memberMap[c.diagnosedPersonId] = FamilyMember(
        id: c.diagnosedPersonId,
        name: c.diagnosedPersonName,
        generation: c.generation,
        conditionCount: existing.conditionCount + 1,
      );
    } else {
      memberMap[c.diagnosedPersonId] = FamilyMember(
        id: c.diagnosedPersonId,
        name: c.diagnosedPersonName,
        generation: c.generation,
        conditionCount: 1,
      );
    }
  }
  final members = memberMap.values.toList()
    ..sort((a, b) => a.generation.compareTo(b.generation));
  return members;
});

/// Inheritance patterns for hereditary conditions.
final inheritancePatternsProvider = Provider<List<InheritancePattern>>((ref) {
  final conditions = ref.watch(healthHeritageProvider).conditions;
  final hereditary = conditions.where((c) => c.isHereditary).toList();

  // Group by condition name
  final conditionGroups = <String, List<HealthCondition>>{};
  for (final c in hereditary) {
    (conditionGroups[c.name] ??= []).add(c);
  }

  final patterns = <InheritancePattern>[];
  for (final entry in conditionGroups.entries) {
    final affectedByGen = <int, List<String>>{};
    final gens = <int>[];
    for (final c in entry.value) {
      (affectedByGen[c.generation] ??= []).add(c.diagnosedPersonName);
      if (!gens.contains(c.generation)) {
        gens.add(c.generation);
      }
    }
    gens.sort();

    if (gens.length >= 2) {
      patterns.add(
        InheritancePattern(
          conditionName: entry.key,
          category: entry.value.first.category,
          affectedMembers: affectedByGen,
          generations: gens,
        ),
      );
    }
  }

  return patterns;
});

/// Health timeline events sorted chronologically by age of onset.
final healthTimelineProvider = Provider<List<HealthTimelineEvent>>((ref) {
  final conditions = ref.watch(healthHeritageProvider).conditions;
  final events = conditions.map((c) {
    final sortKey = c.ageOfOnset != null
        ? c.ageOfOnset!.toDouble()
        : c.generation * 100.0;
    return HealthTimelineEvent(condition: c, sortKey: sortKey);
  }).toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  return events;
});

/// Genetic risk assessment provider (takes two person IDs as family).
final geneticRiskProvider = StateProvider<GeneticRiskAssessment?>(
  (ref) => null,
);

/// Generate a genetic risk assessment for two members.
Provider<GeneticRiskAssessment> geneticRiskForCoupleProvider(
  String person1Id,
  String person2Id,
) {
  return Provider<GeneticRiskAssessment>((ref) {
    final notifier = ref.read(healthHeritageProvider.notifier);
    final conditions = ref.watch(healthHeritageProvider).conditions;
    return notifier.calculateGeneticRisk(conditions, person1Id, person2Id);
  });
}
