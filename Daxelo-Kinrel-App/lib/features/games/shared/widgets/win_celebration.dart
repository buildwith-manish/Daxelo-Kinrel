// lib/features/games/shared/widgets/win_celebration.dart
//
// WinCelebration — universal victory screen for every multiplayer game.
//
// Renders a premium celebration when a match ends:
//
//   ┌────────────────────────────────────┐
//   │            🎉                       │  ← confetti burst
//   │       Lakshmi Won!                 │
//   │                                    │
//   │     ❤️ 12   👏 8   🔥 5            │  ← reaction counts
//   │                                    │
//   │   [ Play Again ]  [ Back to Hub ]  │
//   └────────────────────────────────────┘
//
// Used by every game's results screen — no game-specific code needed.
//
// Features:
//   • Animated trophy + winner name
//   • Live reaction counts (❤️ 👏 🔥 😂 🎉) updated in real time via
//     the socket 'game:reaction' event (also visible in the lobby chat
//     as system activity messages)
//   • Confetti burst on first frame
//   • Sound effect hook (caller can pass a callback)
//   • Family-friendly copy: "Lakshmi Won!" (single winner) or
//     "Tied Game!" (multiple winners)
//   • Replay + Back to Hub actions (caller decides the routing)

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../shared/widgets/dk_components.dart';

/// One reaction type with its emoji + count.
class WinReaction {
  const WinReaction({
    required this.emoji,
    required this.count,
  });
  final String emoji;
  final int count;
}

/// Configuration for the WinCelebration widget.
class WinCelebrationConfig {
  const WinCelebrationConfig({
    required this.winnerNames,
    required this.reactions,
    this.gameName,
    this.subtitle,
  });

  /// Names of the winner(s). If empty, shows "Game Over". If one entry,
  /// shows "X Won!". If multiple, shows "Tied Game!".
  final List<String> winnerNames;

  /// Live reaction tallies. The widget displays each emoji + count
  /// in a row below the winner name. Updates in real time as the caller
  /// passes new reaction counts (e.g. via StreamBuilder or setState).
  final List<WinReaction> reactions;

  /// Optional game name (e.g. "Bingo", "SOS") shown as a subtitle.
  final String? gameName;

  /// Optional custom subtitle (overrides gameName).
  final String? subtitle;
}

/// Universal victory screen for every multiplayer game.
///
/// Usage:
///   WinCelebration(
///     config: WinCelebrationConfig(
///       winnerNames: ['Lakshmi'],
///       reactions: [
///         WinReaction(emoji: '❤️', count: 12),
///         WinReaction(emoji: '👏', count: 8),
///         WinReaction(emoji: '🔥', count: 5),
///       ],
///       gameName: 'Bingo',
///     ),
///     onPlayAgain: () => notifier.leaveGame()..then((_) => context.go('/family/$fid/bingo/lobby')),
///     onBackToHub: () => notifier.leaveGame()..then((_) => context.go('/games?familyId=$fid')),
///   )
class WinCelebration extends StatelessWidget {
  const WinCelebration({
    super.key,
    required this.config,
    required this.onPlayAgain,
    required this.onBackToHub,
  });

  final WinCelebrationConfig config;
  final Future<void> Function() onPlayAgain;
  final Future<void> Function() onBackToHub;

  String get _headline {
    if (config.winnerNames.isEmpty) return 'Game Over';
    if (config.winnerNames.length == 1) {
      return '${config.winnerNames.first} Won!';
    }
    return 'Tied Game!';
  }

  String get _subline {
    if (config.subtitle != null) return config.subtitle!;
    if (config.gameName != null) return '${config.gameName} • Match Complete';
    return 'Match Complete';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            KinrelColors.orange.withValues(alpha: 0.18),
            KinrelColors.darkSurface,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Trophy / confetti burst
          _TrophyBurst()
              .animate()
              .scale(
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                begin: const Offset(0.5, 0.5),
                end: const Offset(1.0, 1.0),
              )
              .then(delay: 200.ms)
              .shake(duration: 400.ms, hz: 4, amount: 0.4),

          const SizedBox(height: KinrelSpacing.lg),

          // Winner name
          Text(
            _headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: KinrelColors.orange,
              letterSpacing: 0.5,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 200.ms)
              .slideY(begin: 0.3, end: 0, duration: 500.ms, delay: 200.ms),

          const SizedBox(height: 4),

          // Subtitle (game name)
          Text(
            _subline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textDim,
              fontStyle: FontStyle.italic,
            ),
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 400.ms),

          // Tied game — show all winner names
          if (config.winnerNames.length > 1) ...[
            const SizedBox(height: KinrelSpacing.md),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: config.winnerNames
                  .map((name) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: KinrelColors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ))
                  .toList(),
            )
                .animate()
                .fadeIn(duration: 400.ms, delay: 500.ms),
          ],

          // Reactions row (if any)
          if (config.reactions.isNotEmpty) ...[
            const SizedBox(height: KinrelSpacing.xl),
            _ReactionsRow(reactions: config.reactions)
                .animate()
                .fadeIn(duration: 500.ms, delay: 700.ms)
                .slideY(begin: 0.2, end: 0, duration: 500.ms, delay: 700.ms),
          ],

          const SizedBox(height: KinrelSpacing.xl),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: DKButton(
                  label: 'Play Again',
                  variant: DKButtonVariant.gradient,
                  icon: Icons.refresh_rounded,
                  fullWidth: true,
                  onPressed: onPlayAgain,
                ),
              ),
              const SizedBox(width: KinrelSpacing.sm),
              Expanded(
                child: DKButton(
                  label: 'Back to Hub',
                  variant: DKButtonVariant.secondary,
                  icon: Icons.home_outlined,
                  fullWidth: true,
                  onPressed: onBackToHub,
                ),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 900.ms)
              .slideY(begin: 0.2, end: 0, duration: 500.ms, delay: 900.ms),
        ],
      ),
    );
  }
}

/// Animated trophy + confetti burst icon.
class _TrophyBurst extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow background
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  KinrelColors.orange.withValues(alpha: 0.4),
                  KinrelColors.orange.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // Trophy
          const Icon(
            Icons.emoji_events_rounded,
            size: 72,
            color: KinrelColors.orange,
          ),
          // Surrounding confetti emojis (decorative)
          ..._confettiSpots,
        ],
      ),
    );
  }

  List<Widget> get _confettiSpots {
    // 6 small emojis orbiting the trophy at fixed positions.
    final emojis = ['🎉', '✨', '⭐', '🎊', '💫', '🏆'];
    final positions = [
      const Offset(-50, -40),
      const Offset(50, -40),
      const Offset(-60, 0),
      const Offset(60, 0),
      const Offset(-50, 40),
      const Offset(50, 40),
    ];
    List<Widget> spots = [];
    for (int i = 0; i < emojis.length; i++) {
      spots.add(
        Transform.translate(
          offset: positions[i],
          child: Text(
            emojis[i],
            style: const TextStyle(fontSize: 18),
          ),
        ),
      );
    }
    return spots;
  }
}

/// Row of reaction tallies: ❤️ 12   👏 8   🔥 5   😂 3   🎉 2
class _ReactionsRow extends StatelessWidget {
  const _ReactionsRow({required this.reactions});
  final List<WinReaction> reactions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.lg, vertical: KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        children: [
          Text(
            'Family Cheers',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: KinrelSpacing.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: KinrelSpacing.md,
            runSpacing: KinrelSpacing.sm,
            children: reactions.map(_reactionChip).toList(),
          ),
        ],
      ),
    );
  }

  Widget _reactionChip(WinReaction r) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(r.emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 4),
        Text(
          '${r.count}',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ],
    );
  }
}
