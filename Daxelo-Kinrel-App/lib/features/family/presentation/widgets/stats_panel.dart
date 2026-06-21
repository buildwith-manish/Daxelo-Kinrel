// lib/features/family/presentation/widgets/stats_panel.dart
//
// DAXELO KINREL — Stats Panel (V2.1 K-Graph Blueprint)
//
// A small bottom-left stats panel showing graph metrics: member count,
// connection count, generation count, and an optional truncation warning.

import 'package:flutter/material.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';

// ═══════════════════════════════════════════════════════════════════════
// STATS PANEL
// ═══════════════════════════════════════════════════════════════════════

/// A compact bottom-left stats panel displaying graph metrics.
///
/// Shows total members, connections (links), and generations. When the
/// graph is truncated (too many nodes to render), a "TRUNCATED" warning
/// is displayed in amber.
///
/// Usage:
/// ```dart
/// Positioned(
///   left: 16,
///   bottom: 80,
///   child: StatsPanel(
///     totalMembers: 42,
///     totalConnections: 58,
///     totalGenerations: 4,
///     isTruncated: false,
///   ),
/// )
/// ```
class StatsPanel extends StatelessWidget {
  /// Creates a [StatsPanel].
  const StatsPanel({
    super.key,
    required this.totalMembers,
    required this.totalConnections,
    required this.totalGenerations,
    this.isTruncated = false,
  });

  /// Total number of members in the graph.
  final int totalMembers;

  /// Total number of connections (edges) in the graph.
  final int totalConnections;

  /// Total number of generations in the graph.
  final int totalGenerations;

  /// Whether the graph is truncated (too many nodes to display fully).
  final bool isTruncated;

  @override
  Widget build(BuildContext context) {
    // v42 FIX: Removed Material(color: Colors.transparent) wrapper.
    // Material with transparent color creates a broken compositing layer
    // on Android that can hide the child. The Container already has an
    // explicit opaque color (KinrelColors.darkCard) and its own decoration,
    // so no Material wrapper is needed.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatRow(label: 'MEMBERS', value: '$totalMembers'),
          const SizedBox(height: 6),
          _StatRow(label: 'LINKS', value: '$totalConnections'),
          const SizedBox(height: 6),
          _StatRow(label: 'GENS', value: '$totalGenerations'),
          if (isTruncated) ...[
            const SizedBox(height: 8),
            _TruncatedWarning(),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STAT ROW (private)
// ═══════════════════════════════════════════════════════════════════════

/// A single row of the stats panel with a label and right-aligned value.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label — 9px, semibold, muted, uppercase, wide tracking
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
              letterSpacing: 0.15 * 9, // 0.15em at 9px = ~1.35
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Value — 14px, bold, primary, tabular figures
        Text(
          value,
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textPrimary.withValues(alpha: 0.9),
            fontFeatures: const [FontFeature.tabularFigures()],
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TRUNCATED WARNING (private)
// ═══════════════════════════════════════════════════════════════════════

/// An amber "TRUNCATED" warning indicator shown when the graph is truncated.
class _TruncatedWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: KinrelColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 12,
            color: KinrelColors.warning,
          ),
          const SizedBox(width: 4),
          Text(
            'TRUNCATED',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: KinrelColors.warning,
              letterSpacing: 1.35, // 0.15em at 9px
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
