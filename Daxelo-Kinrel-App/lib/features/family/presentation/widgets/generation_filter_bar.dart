// lib/features/family/presentation/widgets/generation_filter_bar.dart
//
// DAXELO KINREL — Generation Filter Bar (V2.1 K-Graph Blueprint)
//
// A horizontal scrollable row of generation filter chips at the top of
// the graph screen. Allows users to highlight/dim specific generations.

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

// ═══════════════════════════════════════════════════════════════════════
// GENERATION FILTER BAR
// ═══════════════════════════════════════════════════════════════════════

/// A horizontal scrollable row of generation filter chips for the graph screen.
///
/// The first chip is always "All" which clears any active filter. Generation
/// chips are created dynamically from [presentGenerations]. Tapping a chip
/// selects it; tapping the same chip again deselects back to "All".
///
/// Usage:
/// ```dart
/// GenerationFilterBar(
///   presentGenerations: {0, 1, 2},
///   highlightedGeneration: highlightedGen,
///   onGenerationTap: (gen) => setState(() => highlightedGen = gen),
/// )
/// ```
class GenerationFilterBar extends StatelessWidget {
  /// Creates a [GenerationFilterBar].
  const GenerationFilterBar({
    super.key,
    required this.presentGenerations,
    this.highlightedGeneration,
    required this.onGenerationTap,
  });

  /// Which generation indices exist in the current graph.
  final Set<int> presentGenerations;

  /// Currently selected generation index, or `null` for "All".
  final int? highlightedGeneration;

  /// Callback invoked with the selected generation index, or `null` for "All".
  final ValueChanged<int?> onGenerationTap;

  @override
  Widget build(BuildContext context) {
    final sortedGenerations = presentGenerations.toList()..sort();

    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: sortedGenerations.length + 1, // +1 for "All"
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              // First chip is always "All"
              if (index == 0) {
                return _buildChip(
                  label: 'All',
                  isSelected: highlightedGeneration == null,
                  onTap: () => onGenerationTap(null),
                );
              }

              final gen = sortedGenerations[index - 1];
              return _buildChip(
                label: 'Gen $gen',
                isSelected: highlightedGeneration == gen,
                onTap: () {
                  // Toggle: if already selected, deselect to "All"
                  if (highlightedGeneration == gen) {
                    onGenerationTap(null);
                  } else {
                    onGenerationTap(gen);
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// Builds a single filter chip.
  Widget _buildChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? KinrelColors.orange.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? KinrelColors.orange
                : const Color(0xFF2A2A3D),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isSelected
                  ? KinrelColors.orange
                  : KinrelColors.textSilver,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
