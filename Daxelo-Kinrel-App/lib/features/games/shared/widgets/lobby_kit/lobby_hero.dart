// lib/features/games/shared/widgets/lobby_kit/lobby_hero.dart
//
// LobbyHero — compact premium game-identity header shown at the top of
// EVERY game lobby setup screen (all 14 multiplayer games).
//
// Design intent (Kinrel premium lobby system):
//   • One glance = which game am I setting up + who is it for.
//   • Compact (≤ 96px incl. facts) so the primary action stays above
//     the fold — the hero never competes with the CTA.
//   • Per-game accent color + glossy 3D GameIcon keeps each game's
//     personality inside ONE unified layout shell.

import 'package:flutter/material.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../icons/game_icon_tokens.dart';
import '../../icons/game_icons.dart';

/// A quick fact chip rendered under the hero (players, duration, vibe…).
class LobbyFact {
  const LobbyFact({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class LobbyHero extends StatelessWidget {
  const LobbyHero({
    super.key,
    required this.gameId,
    required this.title,
    required this.tagline,
    this.facts,
  });

  /// Game id used for the icon + accent color ('sos', 'chess', …).
  final String gameId;

  /// Game display name ('SOS', 'Chess', …).
  final String title;

  /// One-line emotional tagline ('Team letter duel on a shared grid').
  final String tagline;

  /// Optional quick facts (players, duration…).
  final List<LobbyFact>? facts;

  @override
  Widget build(BuildContext context) {
    final accent = GameIconTokens.colorFor(gameId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _GameBadge(gameId: gameId, accent: accent),
            const SizedBox(width: KinrelSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.textWhite,
                      letterSpacing: -0.3,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tagline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12.5,
                      color: KinrelColors.textDim,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (facts != null && facts!.isNotEmpty) ...[
          const SizedBox(height: KinrelSpacing.sm + 2),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final fact in facts!) _FactChip(fact: fact, accent: accent),
            ],
          ),
        ],
      ],
    );
  }
}

class _GameBadge extends StatelessWidget {
  const _GameBadge({required this.gameId, required this.accent});

  final String gameId;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KinrelRadius.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: GameIcon(gameId: gameId),
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.fact, required this.accent});

  final LobbyFact fact;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.full),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(fact.icon, size: 12, color: accent),
          const SizedBox(width: 5),
          Text(
            fact.label,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
