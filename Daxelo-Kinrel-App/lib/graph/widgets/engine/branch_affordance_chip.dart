// lib/graph/widgets/engine/branch_affordance_chip.dart
// P0.4: Extracted from family_graph_engine_view.dart.
//
// v5.115 (Task 2): Added label, memberCount, and generationDepth props
// so the chip shows "Ramesh Branch · 120 · 4G" instead of just "+120".
// The underlying CollapsedBranch model already carries this data —
// this is purely a UI/props change, no new data needs to be fetched.

import 'package:flutter/material.dart';

class BranchAffordanceChip extends StatelessWidget {
  const BranchAffordanceChip({
    required this.count,
    required this.onTap,
    this.label,
    this.memberCount,
    this.generationDepth,
  });

  /// The hidden member count (used as fallback when [memberCount] is null).
  final int count;

  /// Callback when the chip is tapped.
  final VoidCallback onTap;

  /// v5.115: The branch label (e.g. "Ramesh Branch", "Mother's branch").
  /// When null or empty, the chip falls back to showing "+count".
  final String? label;

  /// v5.115: The total number of members in this branch.
  /// When null, falls back to [count].
  final int? memberCount;

  /// v5.115: The number of generations hidden in this branch.
  /// When null, the generation depth is not displayed.
  final int? generationDepth;

  static const Color _bg = Color(0xFF1A1F2B);
  static const Color _orange = Color(0xFFE8863A);
  static const Color _textWhite = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    // v5.115: Build the display text.
    // If we have a label, show "Label · Count · NG".
    // Otherwise fall back to the original "+count".
    final hasLabel = label != null && label!.isNotEmpty;
    final displayCount = memberCount ?? count;
    final hasDepth = generationDepth != null && generationDepth! > 0;

    final String displayText;
    String semanticsLabel;

    if (hasLabel && hasDepth) {
      displayText = '$label · $displayCount · ${generationDepth}G';
      semanticsLabel =
          '$label, $displayCount members, $generationDepth generations. Expand branch.';
    } else if (hasLabel) {
      displayText = '$label · $displayCount';
      semanticsLabel = '$label, $displayCount members. Expand branch.';
    } else {
      displayText = '+$count';
      semanticsLabel = '$count hidden family members. Expand branch.';
    }

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          // The visual chip is compact, but the hit area is the
          // minimum accessible size (44×44) via the InkWell's
          // automatic minimum size.
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 44,
              minHeight: 44,
              maxWidth: 220, // v5.115: cap width so long labels don't overflow
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _orange.withValues(alpha: 0.4)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 6,
                    offset: Offset(1, 2),
                  ),
                ],
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.unfold_more_rounded,
                      color: _orange,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        displayText,
                        style: const TextStyle(
                          color: _textWhite,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
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
  }
}
