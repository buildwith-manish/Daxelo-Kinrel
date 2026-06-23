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
import '../../../../core/kinship/kinship_edge_style.dart';

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

    // Define groups in display order — colors now flow from the
    // central KinshipEdgeColors palette so the legend always matches
    // what's painted on the canvas.
    final groups = <_LegendGroup>[
      _LegendGroup(
        label: 'Self',
        keys: {'self', 'ego'},
        color: KinshipEdgeColors.self,
      ),
      _LegendGroup(
        label: 'Parent',
        keys: {'father', 'mother', 'parent'},
        color: KinshipEdgeColors.parent,
      ),
      _LegendGroup(
        label: 'Child',
        keys: {'son', 'daughter', 'child',
               'sons_wife', 'sons_husband',
               'daughters_husband', 'daughters_wife'},
        color: KinshipEdgeColors.child,
      ),
      _LegendGroup(
        label: 'Spouse',
        keys: {'husband', 'wife', 'spouse', 'partner'},
        // Orange edge — but the heart is pink. We show the edge color
        // here so the swatch matches what users see on the line.
        color: KinshipEdgeColors.spouseEdge,
      ),
      _LegendGroup(
        label: 'Sibling',
        keys: {'brother', 'sister', 'sibling',
               'elder_brother', 'elder_sister',
               'younger_brother', 'younger_sister',
               'half_brother', 'half_sister'},
        color: KinshipEdgeColors.sibling,
      ),
      _LegendGroup(
        label: 'Grandparent',
        keys: {'grandfather', 'grandmother', 'grandparent',
               'grandson', 'granddaughter',
               'paternal_grandfather', 'paternal_grandmother',
               'maternal_grandfather', 'maternal_grandmother'},
        color: KinshipEdgeColors.grandparent,
      ),
      _LegendGroup(
        label: 'Aunt / Uncle',
        keys: {'uncle', 'aunt', 'nephew', 'niece',
               'paternal_uncle', 'paternal_aunt',
               'maternal_uncle', 'maternal_aunt',
               'fathers_elder_brother', 'fathers_younger_brother',
               'fathers_sister', 'mothers_brother', 'mothers_sister'},
        color: KinshipEdgeColors.auntUncle,
      ),
      _LegendGroup(
        label: 'Cousin',
        keys: {'cousin', 'cousin_brother', 'cousin_sister',
               'brothers_son', 'brothers_daughter',
               'sisters_son', 'sisters_daughter'},
        color: KinshipEdgeColors.cousin,
      ),
      _LegendGroup(
        label: 'In-Law',
        keys: {'father_in_law', 'mother_in_law',
               'son_in_law', 'daughter_in_law',
               'brother_in_law', 'sister_in_law',
               'husbands_father', 'husbands_mother',
               'wifes_brother', 'wifes_sister',
               'in_law'},
        color: KinshipEdgeColors.inLaw,
      ),
      _LegendGroup(
        label: 'Extended',
        keys: {'stepfather', 'stepmother', 'stepson', 'stepdaughter',
               'stepbrother', 'stepsister',
               'godfather', 'godmother', 'guru',
               'other', 'related', 'unknown'},
        color: KinshipEdgeColors.extended,
      ),
      _LegendGroup(
        label: 'Indirect',
        keys: {'indirect_connection'},
        color: KinshipEdgeColors.indirect,
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
    // v10 Fix #2c: Check in-law variants with underscores (the codebase
    // standard) AND hyphens (for backwards compatibility). If the key
    // contains "in_law" or "in-law" and the group contains any in-law
    // key, match it.
    if ((key.contains('in_law') || key.contains('in-law')) &&
        groupKeys.any((k) => k.contains('in_law') || k.contains('in-law'))) {
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
