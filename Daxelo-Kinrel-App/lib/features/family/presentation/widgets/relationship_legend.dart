// lib/features/family/presentation/widgets/relationship_legend.dart
//
// DAXELO KINREL — Relationship Legend (V2.1 K-Graph Blueprint)
//
// A vertical legend panel positioned at the right center of the graph
// screen, showing relationship type → color mappings for active
// relationship keys in the current graph.

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

// ═══════════════════════════════════════════════════════════════════════
// RELATIONSHIP LEGEND
// ═══════════════════════════════════════════════════════════════════════

/// A vertical legend panel showing relationship type → color mappings.
///
/// Only relationship types present in [presentRelationshipKeys] are shown.
/// Tapping a legend item filters the graph to highlight that relationship
/// type. Tapping the same item again deselects it.
///
/// Usage:
/// ```dart
/// Positioned(
///   right: 16,
///   top: 0,
///   bottom: 0,
///   child: Center(
///     child: RelationshipLegend(
///       presentRelationshipKeys: {'father', 'mother', 'spouse'},
///       hoveredRelationshipKey: hoveredKey,
///       onRelationshipTap: (key) => setState(() => hoveredKey = key),
///     ),
///   ),
/// )
/// ```
class RelationshipLegend extends StatelessWidget {
  /// Creates a [RelationshipLegend].
  const RelationshipLegend({
    super.key,
    required this.presentRelationshipKeys,
    this.hoveredRelationshipKey,
    this.onRelationshipTap,
    this.onClose,
  });

  /// Which relationship type keys exist in the current graph.
  final Set<String> presentRelationshipKeys;

  /// Currently highlighted relationship key, or `null` for none.
  final String? hoveredRelationshipKey;

  /// Callback invoked when a legend item is tapped.
  /// Passes the relationship key, or `null` to deselect.
  final ValueChanged<String?>? onRelationshipTap;

  /// Callback to close the legend panel.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final entries = _groupedEntries();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'LEGEND',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.4),
                    letterSpacing: 1.5,
                    decoration: TextDecoration.none,
                  ),
                ),
                if (onClose != null)
                  GestureDetector(
                    onTap: onClose,
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Legend entries
            ...entries.map((entry) {
            final isHovered = hoveredRelationshipKey != null &&
                _keysMatchGroup(hoveredRelationshipKey!, entry.keys);

            return GestureDetector(
              onTap: () {
                if (onRelationshipTap == null) return;
                // Toggle: if this group is already hovered, deselect
                if (isHovered) {
                  onRelationshipTap!(null);
                } else {
                  // Use the first key in the group as the representative
                  onRelationshipTap!(entry.keys.first);
                }
              },
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: hoveredRelationshipKey != null && !isHovered
                    ? 0.4
                    : 1.0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Color circle
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: entry.color,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Label
                      Text(
                        entry.label,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: KinrelColors.textSecondary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
          ],
        ),
      ),
    );
  }

  /// Groups similar relationship keys together and returns legend entries.
  ///
  /// For example, "father" and "mother" both map to the "Parent" group
  /// with [KinrelColors.nodeParent].
  List<_LegendEntry> _groupedEntries() {
    final entries = <_LegendEntry>[];

    // Define groups in display order
    final groups = <_LegendGroup>[
      _LegendGroup(
        label: 'Self',
        keys: {'self'},
        color: KinrelColors.nodeSelf,
      ),
      _LegendGroup(
        label: 'Parent',
        keys: {'father', 'mother', 'parent'},
        color: KinrelColors.nodeParent,
      ),
      _LegendGroup(
        label: 'Spouse',
        keys: {'husband', 'wife', 'spouse'},
        color: KinrelColors.nodeSpouse,
      ),
      _LegendGroup(
        label: 'Sibling',
        keys: {'brother', 'sister', 'sibling'},
        color: KinrelColors.nodeSibling,
      ),
      _LegendGroup(
        label: 'Child',
        keys: {'son', 'daughter', 'child'},
        color: KinrelColors.nodeChild,
      ),
      _LegendGroup(
        label: 'Grandparent',
        keys: {'grandfather', 'grandmother', 'grandparent'},
        color: KinrelColors.nodeGrandparent,
      ),
      _LegendGroup(
        label: 'Aunt / Uncle',
        keys: {'uncle', 'aunt'},
        color: KinrelColors.nodeAuntUncle,
      ),
      _LegendGroup(
        label: 'Cousin',
        keys: {'cousin'},
        color: KinrelColors.nodeCousin,
      ),
      _LegendGroup(
        label: 'In-Law',
        keys: {
          'father-in-law', 'mother-in-law',
          'son-in-law', 'daughter-in-law',
          'brother-in-law', 'sister-in-law',
          'in-law',
        },
        color: KinrelColors.nodeInLaw,
      ),
      _LegendGroup(
        label: 'Extended',
        keys: {'other'},
        color: KinrelColors.nodeExtended,
      ),
    ];

    for (final group in groups) {
      // Show group if any of its keys are present
      if (group.keys.intersection(presentRelationshipKeys).isNotEmpty) {
        entries.add(_LegendEntry(
          label: group.label,
          keys: group.keys,
          color: group.color,
        ));
      }
    }

    return entries;
  }

  /// Checks whether the given [key] belongs to a group defined by [groupKeys].
  bool _keysMatchGroup(String key, Set<String> groupKeys) {
    if (groupKeys.contains(key)) return true;
    // Check in-law variants: if the key ends with "-in-law" and the group
    // contains "in-law" or other in-law keys, match it.
    if (key.contains('in-law') && groupKeys.any((k) => k.contains('in-law'))) {
      return true;
    }
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PRIVATE HELPER CLASSES
// ═══════════════════════════════════════════════════════════════════════

/// Defines a group of relationship keys that share a label and color.
class _LegendGroup {
  const _LegendGroup({
    required this.label,
    required this.keys,
    required this.color,
  });

  final String label;
  final Set<String> keys;
  final Color color;
}

/// A computed legend entry ready for display.
class _LegendEntry {
  const _LegendEntry({
    required this.label,
    required this.keys,
    required this.color,
  });

  final String label;
  final Set<String> keys;
  final Color color;
}
