// lib/features/games/sos/sos_results_screen.dart
//
// SOS Game — Results screen with winner announcement + confetti.
// Route: /family/$familyId/sos/results/$gameId

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import 'sos_models.dart';
import 'sos_provider.dart';

class SosResultsScreen extends ConsumerWidget {
  const SosResultsScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sosProvider(familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final game = state.game;

    if (game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        body: const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
      );
    }

    // Determine winner
    final isTeamMode = game.mode == SosMode.fourPlayerTeams;
    final winnerTeam = game.winnerTeam;
    final winnerUserId = game.winnerUserId;
    final isTie = winnerTeam == null && winnerUserId == null;

    // For team mode: check if my team won
    bool isMyWin = false;
    if (isTeamMode && winnerTeam != null) {
      isMyWin = state.myTeam == winnerTeam;
    } else if (!isTeamMode && winnerUserId != null) {
      isMyWin = winnerUserId == myId;
    }

    // Sorted standings
    final sortedPlayers = List<SosPlayer>.from(state.players)
      ..sort((a, b) => b.score.compareTo(a.score));

    return DKScaffold(
      gradient: isMyWin ? KinrelGradients.deepFireGradient : null,
      backgroundColor:
          isMyWin ? null : KinrelColors.darkSurface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Results',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        children: [
          const SizedBox(height: KinrelSpacing.lg),
          // Winner banner
          _winnerBanner(
            isTie: isTie,
            isTeamMode: isTeamMode,
            winnerTeam: winnerTeam,
            winnerUserId: winnerUserId,
            players: state.players,
            isMyWin: isMyWin,
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(
                begin: const Offset(0.92, 0.92),
                end: const Offset(1.0, 1.0),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
          const SizedBox(height: KinrelSpacing.xl),

          // Standings
          Text(
            isTeamMode ? 'Team Standings' : 'Final Standings',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textDim,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: KinrelSpacing.sm),

          if (isTeamMode) ...[
            _teamStandings(state)
                .animate(delay: 100.ms)
                .fadeIn(duration: 300.ms)
                .slideY(begin: 0.1, end: 0, duration: 300.ms),
          ] else ...[
            for (int i = 0; i < sortedPlayers.length; i++)
              _playerRow(sortedPlayers[i], sortedPlayers[i].userId == myId, i + 1)
                  .animate(delay: (i * 80).ms)
                  .fadeIn(duration: 250.ms)
                  .slideY(begin: 0.08, end: 0, duration: 250.ms),
          ],

          const SizedBox(height: KinrelSpacing.xxl),
          DKButton(
            label: 'Play Again',
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            icon: Icons.refresh_rounded,
            onPressed: () {
              ref.read(sosProvider(familyId).notifier).leaveGame();
              if (context.mounted) {
                context.pushReplacement('/family/$familyId/sos/lobby');
              }
            },
          ),
          const SizedBox(height: KinrelSpacing.sm),
          DKButton(
            label: 'Back to Hub',
            variant: DKButtonVariant.secondary,
            fullWidth: true,
            onPressed: () {
              ref.read(sosProvider(familyId).notifier).leaveGame();
              if (context.mounted) {
                context.go('/games?familyId=$familyId');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _winnerBanner({
    required bool isTie,
    required bool isTeamMode,
    required SosTeam? winnerTeam,
    required String? winnerUserId,
    required List<SosPlayer> players,
    required bool isMyWin,
  }) {
    if (isTie) {
      return Column(
        children: [
          const Text('🤝', style: TextStyle(fontSize: 64)),
          const SizedBox(height: KinrelSpacing.sm),
          Text(
            "It's a tie!",
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: KinrelColors.textWhite,
              letterSpacing: 2,
            ),
          ),
        ],
      );
    }

    if (isTeamMode && winnerTeam != null) {
      final teamColor = Color(winnerTeam.colorValue);
      return Column(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 64))
              .animate(onPlay: (c) => c.forward())
              .fadeIn(duration: 500.ms)
              .scale(
                begin: const Offset(0.5, 0.5),
                end: const Offset(1.0, 1.0),
                duration: 500.ms,
                curve: Curves.elasticOut,
              ),
          const SizedBox(height: KinrelSpacing.sm),
          Text(
            isMyWin ? 'Your team won!' : 'Winner!',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: KinrelColors.textWhite,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            winnerTeam.label,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: teamColor,
            ),
          ),
        ],
      );
    }

    // 2-player mode
    final winner = players.where((p) => p.userId == winnerUserId).firstOrNull;
    final winnerName = winner?.userName ?? 'Player';
    return Column(
      children: [
        const Text('🏆', style: TextStyle(fontSize: 64))
            .animate(onPlay: (c) => c.forward())
            .fadeIn(duration: 500.ms)
            .scale(
              begin: const Offset(0.5, 0.5),
              end: const Offset(1.0, 1.0),
              duration: 500.ms,
              curve: Curves.elasticOut,
            ),
        const SizedBox(height: KinrelSpacing.sm),
        Text(
          'Winner!',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: KinrelColors.textWhite,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isMyWin ? '$winnerName (You)' : winnerName,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: KinrelColors.orange,
          ),
        ),
      ],
    );
  }

  Widget _teamStandings(SosState state) {
    final teamScores = state.teamScores;
    final teams = [SosTeam.s, SosTeam.o]
      ..sort((a, b) => teamScores[b]!.compareTo(teamScores[a]!));
    return Column(
      children: [
        for (int i = 0; i < teams.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.md,
              vertical: KinrelSpacing.md,
            ),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: Border.all(
                color: i == 0 ? KinrelColors.orange : KinrelColors.border,
                width: i == 0 ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    i == 0 ? '🥇' : '🥈',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                Expanded(
                  child: Text(
                    teams[i].label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
                Text(
                  '${teamScores[teams[i]]} SOS',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(teams[i].colorValue),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _playerRow(SosPlayer player, bool isMe, int placement) {
    final medal = placement == 1
        ? '🥇'
        : placement == 2
        ? '🥈'
        : placement == 3
        ? '🥉'
        : '$placement';
    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.md,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: isMe ? KinrelColors.orange : KinrelColors.border,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              medal,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          Expanded(
            child: Text(
              isMe ? '${player.userName} (You)' : player.userName,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          Text(
            '${player.score} SOS',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: KinrelColors.orange,
            ),
          ),
        ],
      ),
    );
  }
}
