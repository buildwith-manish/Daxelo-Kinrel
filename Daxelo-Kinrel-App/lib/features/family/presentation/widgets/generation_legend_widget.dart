// lib/features/family/presentation/widgets/generation_legend_widget.dart
//
// DAXELO KINREL — Generation Legend Widget
//
// A floating chip group showing generation categories present in the
// current family graph. Each chip is tappable to toggle highlight/dim
// of that generation group.

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

// ═══════════════════════════════════════════════════════════════════════
// GENERATION CATEGORY
// ═══════════════════════════════════════════════════════════════════════

/// Represents a generation category with its display properties.
class GenerationCategory {
  final String label;
  final Color color;
  final int generationIndex; // The generation index this category represents.
  // For "Parents" this is -1 (any gen < 0 matches).
  // For "Self" this is 0.
  // For "Children" this is 1 (any gen > 0 matches).
  // For "Extended" this is -2 (uncles/aunts/cousins, |gen| >= 2).
  // For "In-laws" this is 99 (special marker).

  const GenerationCategory({
    required this.label,
    required this.color,
    required this.generationIndex,
  });

  /// Whether a person with the given generationIndex belongs to this category.
  bool matches(int personGenIndex) {
    if (generationIndex == 99) {
      // In-laws — matched by relationship key, not generation.
      // For simplicity, we don't match by generation for in-laws.
      return false;
    }
    if (generationIndex == -2) {
      // Extended: |genIndex| >= 2
      return personGenIndex.abs() >= 2;
    }
    if (generationIndex == -1) {
      // Parents: genIndex < 0 and |genIndex| < 2
      return personGenIndex < 0 && personGenIndex.abs() < 2;
    }
    if (generationIndex == 1) {
      // Children: genIndex > 0 and genIndex < 2
      return personGenIndex > 0 && personGenIndex < 2;
    }
    return personGenIndex == generationIndex;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// DEFAULT CATEGORIES
// ═══════════════════════════════════════════════════════════════════════

/// Default generation categories used by the legend.
const List<GenerationCategory> defaultGenerationCategories = [
  GenerationCategory(label: 'Parents', color: KinrelColors.blue, generationIndex: -1),
  GenerationCategory(label: 'Self', color: KinrelColors.tealAccent, generationIndex: 0),
  GenerationCategory(label: 'Children', color: KinrelColors.coral, generationIndex: 1),
  GenerationCategory(label: 'Extended', color: KinrelColors.extendedPurple, generationIndex: -2),
  GenerationCategory(label: 'In-laws', color: KinrelColors.inLawGold, generationIndex: 99),
];

// ═══════════════════════════════════════════════════════════════════════
// GENERATION LEGEND WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// A floating chip group that shows generation categories present in the graph.
///
/// Each chip is tappable: tapping toggles highlight of that generation group
/// (dims other generations to opacity 0.25).
///
/// Usage:
/// ```dart
/// Positioned(
///   left: 16,
///   top: 16,
///   child: GenerationLegendWidget(
///     presentGenerations: {-1, 0, 1},
///     highlightedGeneration: highlightedGen,
///     onGenerationTap: (gen) => setState(() => highlightedGen = gen),
///   ),
/// )
/// ```
class GenerationLegendWidget extends StatelessWidget {
  const GenerationLegendWidget({
    super.key,
    required this.presentGenerations,
    this.highlightedGeneration,
    required this.onGenerationTap,
  });

  /// Set of generation indices present in the current graph.
  final Set<int> presentGenerations;

  /// Currently highlighted generation index, or null for no highlight.
  final int? highlightedGeneration;

  /// Callback when a generation chip is tapped.
  /// Pass null to clear the highlight.
  final void Function(int? generationIndex) onGenerationTap;

  /// Determine which categories to show based on present generations.
  List<GenerationCategory> _visibleCategories() {
    final categories = <GenerationCategory>[];

    // Parents: show if any gen < 0 exists
    final hasParents = presentGenerations.any((g) => g < 0 && g.abs() < 2);
    if (hasParents) {
      categories.add(defaultGenerationCategories[0]); // Parents
    }

    // Self: show if gen 0 exists
    if (presentGenerations.contains(0)) {
      categories.add(defaultGenerationCategories[1]); // Self
    }

    // Children: show if any gen > 0 exists and < 2
    final hasChildren = presentGenerations.any((g) => g > 0 && g < 2);
    if (hasChildren) {
      categories.add(defaultGenerationCategories[2]); // Children
    }

    // Extended: show if any |gen| >= 2 exists
    final hasExtended = presentGenerations.any((g) => g.abs() >= 2);
    if (hasExtended) {
      categories.add(defaultGenerationCategories[3]); // Extended
    }

    // In-laws: show if we have in-law relationships (detected externally)
    // For now, skip unless explicitly added to presentGenerations as 99
    if (presentGenerations.contains(99)) {
      categories.add(defaultGenerationCategories[4]); // In-laws
    }

    return categories;
  }

  @override
  Widget build(BuildContext context) {
    final categories = _visibleCategories();
    if (categories.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: categories.map((cat) {
          final isHighlighted = highlightedGeneration != null &&
              cat.matches(highlightedGeneration!);
          final isAnyHighlighted = highlightedGeneration != null;

          return GestureDetector(
            onTap: () {
              if (highlightedGeneration != null &&
                  cat.matches(highlightedGeneration!)) {
                // Tap again to deselect
                onGenerationTap(null);
              } else {
                onGenerationTap(cat.generationIndex);
              }
            },
            child: AnimatedOpacity(
              opacity: isAnyHighlighted && !isHighlighted ? 0.4 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? cat.color.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isHighlighted
                      ? Border.all(color: cat.color.withValues(alpha: 0.4), width: 1)
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Color dot
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cat.color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Label
                    Text(
                      cat.label,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 11,
                        fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w400,
                        color: isHighlighted ? cat.color : KinrelColors.textSecondaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
