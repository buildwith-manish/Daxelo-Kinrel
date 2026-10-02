// lib/features/prediction_battle_v1/pb_v1_rank_badge.dart
//
// Custom branded ranking badges for the Prediction Battle — replaces
// the generic 🥇🥈🥉 emoji medals with Daxelo-Kinrel-branded circular
// badges that match the app's design language (gold/amber/orange
// palette, monospace typography, glowing borders).
//
// Design:
//   Rank 1 — Champion: gold gradient circle with a crown icon + glow
//   Rank 2 — Runner-up: silver gradient circle with a star icon
//   Rank 3 — Third Place: bronze gradient circle with a check icon
//   Rank 4+ — plain number in a subtle circle
//
// The badges use:
//   - LinearGradient fills matching KinrelColors.brightGold / amber / orange
//   - BoxShadow for the glow effect on rank 1
//   - The app's monospace font for the number (rank 4+)
//   - A small icon for ranks 1-3 (crown / star / check)
//   - 28x28dp size — same visual weight as the emoji medals they replace

import 'package:flutter/material.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';

/// Custom branded ranking badge for the Prediction Battle leaderboard
/// and reveal screen. Replaces the generic 🥇🥈🥉 emoji medals.
class PBv1RankBadge extends StatelessWidget {
  const PBv1RankBadge({super.key, required this.rank, this.size = 28});
  final int rank;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (rank <= 0) return SizedBox(width: size, height: size);

    switch (rank) {
      case 1:
        return _GradientBadge(
          size: size,
          colors: const [Color(0xFFFFD700), Color(0xFFFFA500)],
          glowColor: const Color(0xFFFFD700),
          icon: Icons.emoji_events_rounded,
          iconColor: Colors.white,
          label: '1',
          showGlow: true,
        );
      case 2:
        return _GradientBadge(
          size: size,
          colors: const [Color(0xFFC0C0C0), Color(0xFF808080)],
          glowColor: const Color(0xFFC0C0C0),
          icon: Icons.workspace_premium_rounded,
          iconColor: Colors.white,
          label: '2',
        );
      case 3:
        return _GradientBadge(
          size: size,
          colors: const [Color(0xFFCD7F32), Color(0xFF8B4513)],
          glowColor: const Color(0xFFCD7F32),
          icon: Icons.military_tech_rounded,
          iconColor: Colors.white,
          label: '3',
        );
      default:
        // Rank 4+ — plain number in a subtle circle
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            shape: BoxShape.circle,
            border: Border.all(color: KinrelColors.border, width: 0.8),
          ),
          child: Center(
            child: Text(
              '$rank',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
                color: KinrelColors.textDim,
              ),
            ),
          ),
        );
    }
  }
}

class _GradientBadge extends StatelessWidget {
  const _GradientBadge({
    required this.size,
    required this.colors,
    required this.glowColor,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.showGlow = false,
  });

  final double size;
  final List<Color> colors;
  final Color glowColor;
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        shape: BoxShape.circle,
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
        border: Border.all(
          color: colors[0].withValues(alpha: 0.8),
          width: 1.2,
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: size * 0.55,
          color: iconColor,
        ),
      ),
    );
  }
}
