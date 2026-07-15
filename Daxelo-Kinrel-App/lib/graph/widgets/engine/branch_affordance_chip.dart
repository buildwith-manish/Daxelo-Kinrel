// lib/graph/widgets/engine/branch_affordance_chip.dart
// P0.4: Extracted from family_graph_engine_view.dart.

import 'package:flutter/material.dart';

class BranchAffordanceChip extends StatelessWidget {
  const BranchAffordanceChip({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  static const Color _bg = Color(0xFF1A1F2B);
  static const Color _orange = Color(0xFFE8863A);
  static const Color _textWhite = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$count hidden family members. Expand branch.',
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
                    Text(
                      '+$count',
                      style: const TextStyle(
                        color: _textWhite,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
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

/// A single node rendered as a coloured dot at the lowest LOD tier.
