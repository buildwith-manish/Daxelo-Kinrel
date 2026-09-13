// lib/features/games/shared/widgets/create_game_cta_card.dart
//
// CreateGameCtaCard — big gradient CTA at the top of the Games hub.
//
// Per spec: "Create CTA: Big gradient card. Highest visibility. Feels
// premium. Better conversion to game creation. More suitable for
// family-oriented casual gaming."
//
// ┌─────────────────────────────────────────────────┐
// │  🎮                                              │
// │  Start a Family Game Night                       │
// │  Pick a game below and invite your family        │
// │  ───────────────────────────────────             │
// │  [Pick a Game ▾]   [View Active Games]          │
// └─────────────────────────────────────────────────┘
//
// The card is purely navigational — it does not create a room itself.
// Tapping "Pick a Game" scrolls the user down to the games list (or
// just prompts them — the games list is right below the CTA).

import 'package:flutter/material.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';

class CreateGameCtaCard extends StatelessWidget {
  const CreateGameCtaCard({
    super.key,
    required this.onPickGame,
    this.onViewActiveGames,
    this.activeGamesCount = 0,
  });

  /// Called when the user taps the "Pick a Game" button.
  final VoidCallback onPickGame;

  /// Optional callback when "View Active Games" is tapped.
  final VoidCallback? onViewActiveGames;

  /// Number of currently-active family games (shows the badge).
  final int activeGamesCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.lg),
      padding: const EdgeInsets.all(KinrelSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8612A), // KinrelColors.orange
            Color(0xFFF59240), // KinrelColors.amber
            Color(0xFFD946EF), // fuchsia accent
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(KinrelRadius.xl),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orange.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + Active badge row
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.sports_esports_rounded,
                    color: Colors.white, size: 28),
              ),
              const Spacer(),
              if (activeGamesCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$activeGamesCount active',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: KinrelSpacing.lg),

          // Headline
          Text(
            'Start a Family Game Night',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),

          // Subtitle
          Text(
            'Pick a game below and invite your family to play together in real time.',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.4,
            ),
          ),
          const SizedBox(height: KinrelSpacing.lg),

          // CTA buttons
          Row(
            children: [
              Expanded(
                child: _CtaButton(
                  label: 'Pick a Game',
                  icon: Icons.keyboard_arrow_down_rounded,
                  primary: true,
                  onTap: onPickGame,
                ),
              ),
              const SizedBox(width: KinrelSpacing.sm),
              if (activeGamesCount > 0 && onViewActiveGames != null)
                Expanded(
                  child: _CtaButton(
                    label: 'View Active',
                    icon: Icons.play_arrow_rounded,
                    primary: false,
                    onTap: onViewActiveGames!,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary
          ? Colors.white
          : Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(KinrelRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: primary ? KinrelColors.orange : Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon,
                  size: 18,
                  color: primary ? KinrelColors.orange : Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
