// lib/features/games/redlight/redlight_game_screen.dart
//
// Freeze & Dash — Active gameplay screen.
// Route: /family/$familyId/freeze-dash/game/$roundId
//
// Layout:
//   • Phase indicator (top)
//   • Caller character (left)
//   • Track view (main body) — vertical list of player progress bars
//   • Run button (bottom)
//
// State flows entirely through redlightProvider — no setState.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import 'redlight_models.dart';
import 'redlight_provider.dart';

class RedlightGameScreen extends ConsumerStatefulWidget {
  const RedlightGameScreen({
    super.key,
    required this.familyId,
    required this.roundId,
  });
  final String familyId;
  final String roundId;

  @override
  ConsumerState<RedlightGameScreen> createState() =>
      _RedlightGameScreenState();
}

class _RedlightGameScreenState extends ConsumerState<RedlightGameScreen> {
  @override
  void initState() {
    super.initState();
    // If we don't have a round yet (e.g. deep-linked), auto-join.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(redlightProvider(widget.familyId));
      if (state.round == null) {
        ref
            .read(redlightProvider(widget.familyId).notifier)
            .joinRound(widget.roundId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(redlightProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    // If game is finished, jump to results.
    if (state.isFinished && state.results.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.pushReplacement(
            '/family/${widget.familyId}/freeze-dash/results/${widget.roundId}',
          );
        }
      });
    }

    final isFog = state.round?.weatherModifier == WeatherModifier.fog;
    final myEntry = state.liveLeaderboard
        .where((e) => e.userId == myId)
        .firstOrNull;
    final myEliminated = myEntry != null && !myEntry.alive;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            ref
                .read(redlightProvider(widget.familyId).notifier)
                .leaveRound();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'Freeze & Dash',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          if (state.round?.hostUserId == myId &&
              (state.round?.isLobby ?? false))
            Padding(
              padding: const EdgeInsets.only(right: KinrelSpacing.sm),
              child: FilledButton(
                onPressed: state.players.length >= 3
                    ? () => ref
                          .read(
                            redlightProvider(widget.familyId).notifier,
                          )
                          .startGame()
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: KinrelColors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Start'),
              ),
            ),
        ],
      ),
      body: state.isLoading && state.round == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : state.error != null && state.round == null
          ? DKErrorState(
              message: state.error!,
              onRetry: () => ref
                  .read(redlightProvider(widget.familyId).notifier)
                  .joinRound(widget.roundId),
            )
          : SafeArea(
              child: Column(
                children: [
                  _phaseBanner(state),
                  if (state.isCountdown)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: KinrelSpacing.sm,
                      ),
                      child: Text(
                        'Starting in ${state.countdownSeconds}…',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.orange,
                        ),
                      ),
                    ),
                  Expanded(child: _trackView(state, myId, isFog)),
                  _runButton(state, myEliminated),
                  const SizedBox(height: KinrelSpacing.base),
                ],
              ),
            ),
    );
  }

  Widget _phaseBanner(RedlightState state) {
    final isGreen = state.phase == RedlightPhase.green;
    final isRed = state.phase == RedlightPhase.red;
    final bgColor = isGreen
        ? KinrelColors.success
        : isRed
        ? KinrelColors.error
        : KinrelColors.darkElevated;
    final label = isGreen
        ? 'GO!'
        : isRed
        ? 'FREEZE!'
        : (state.isCountdown ? 'GET READY' : 'WAITING');

    final durationMs = state.phaseRemainingMs ?? 0;
    final totalMs = isGreen ? 5000 : (isRed ? 3000 : 1);
    final progress = durationMs > 0 ? (durationMs / totalMs).clamp(0.0, 1.0) : 0.0;

    return AnimatedContainer(
      duration: GameMotionTokens.fast,
      curve: GameMotionTokens.smooth,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: KinrelSpacing.md,
        horizontal: KinrelSpacing.base,
      ),
      decoration: BoxDecoration(color: bgColor),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: GameMotionTokens.fast,
            child: Text(
              label,
              key: ValueKey(label),
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: isGreen || isRed ? progress : 0,
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    )
        .animate(target: isGreen || isRed ? 1 : 0)
        .scale(
          begin: const Offset(0.98, 0.98),
          end: const Offset(1.0, 1.0),
          duration: GameMotionTokens.fast,
          curve: GameMotionTokens.bounce,
        );
  }

  Widget _trackView(RedlightState state, String? myId, bool isFog) {
    // Use live leaderboard during active phase, fall back to lobby players
    final hasLive = state.liveLeaderboard.isNotEmpty;
    final entries = hasLive
        ? state.liveLeaderboard
        : state.players
              .map(
                (p) => RedlightLeaderboardEntry(
                  userId: p.userId,
                  userName: p.userName,
                  progress: p.progress,
                  alive: p.alive,
                  teamId: p.teamId,
                ),
              )
              .toList();

    if (entries.isEmpty) {
      return DKEmptyState(
        icon: Icons.directions_run_rounded,
        title: 'Waiting for players',
        subtitle: 'Players will appear here once they join.',
      );
    }

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.all(KinrelSpacing.base),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final e = entries[i];
            final isMe = e.userId == myId;
            // Fog modifier: hide other players' progress
            final showProgress = !isFog || isMe;
            return _playerRow(e, isMe, showProgress)
                .animate(delay: (i * 40).ms)
                .fadeIn(duration: 200.ms)
                .slideY(begin: 0.05, end: 0, duration: 200.ms);
          },
        ),
        // Power-up icons floating over the track
        ..._powerupWidgets(state, myId),
      ],
    );
  }

  Widget _playerRow(
    RedlightLeaderboardEntry e,
    bool isMe,
    bool showProgress,
  ) {
    final phase = ref.read(redlightProvider(widget.familyId)).phase;
    final barColor = !e.alive
        ? KinrelColors.textDim
        : phase == RedlightPhase.red
        ? KinrelColors.error
        : KinrelColors.success;
    final displayProgress = showProgress ? e.progress : 0.0;
    final progressLabel = showProgress ? '${e.progress.toStringAsFixed(0)}%' : '???';

    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
      padding: const EdgeInsets.all(KinrelSpacing.md),
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
          DKAvatar(
            initials: e.userName.isNotEmpty
                ? e.userName[0].toUpperCase()
                : '?',
            borderColor: isMe ? KinrelColors.orange : null,
          ),
          const SizedBox(width: KinrelSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isMe ? '${e.userName} (You)' : e.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: e.alive
                              ? KinrelColors.textWhite
                              : KinrelColors.textDim,
                        ),
                      ),
                    ),
                    if (!e.alive)
                      const Text('💀', style: TextStyle(fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(KinrelRadius.xs),
                  child: LinearProgressIndicator(
                    value: (displayProgress / 100).clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: KinrelColors.darkElevated,
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: KinrelSpacing.sm),
          SizedBox(
            width: 48,
            child: Text(
              progressLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: showProgress
                    ? (e.alive
                          ? KinrelColors.textWhite
                          : KinrelColors.textDim)
                    : KinrelColors.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _powerupWidgets(RedlightState state, String? myId) {
    // Render each power-up at a vertical offset based on its position
    // (purely cosmetic — players tap to collect).
    return state.activePowerups.map((pu) {
      // Map 0–100 position to a vertical offset within the track area
      final top = (pu.position / 100) * 280 + 40;
      return Positioned(
        right: KinrelSpacing.lg,
        top: top,
        child: GestureDetector(
          onTap: () => ref
              .read(redlightProvider(widget.familyId).notifier)
              .collectPowerup(pu.powerupId, pu.type),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KinrelColors.darkElevated,
              border: Border.all(
                color: pu.type == PowerupType.shield
                    ? KinrelColors.info
                    : KinrelColors.warning,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(pu.type.emoji, style: const TextStyle(fontSize: 18)),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _runButton(RedlightState state, bool myEliminated) {
    final isGreen = state.phase == RedlightPhase.green;
    final isRed = state.phase == RedlightPhase.red;
    final label = myEliminated
        ? '💀 ELIMINATED'
        : isGreen
        ? 'RUN!'
        : isRed
        ? 'HOLD STILL'
        : 'WAITING';

    final Color bg;
    if (myEliminated) {
      bg = KinrelColors.darkElevated;
    } else if (isGreen) {
      bg = KinrelColors.orange;
    } else if (isRed) {
      bg = KinrelColors.error;
    } else {
      bg = KinrelColors.darkElevated;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: GestureDetector(
        onTapDown: myEliminated || !isGreen
            ? null
            : (_) => ref
                  .read(redlightProvider(widget.familyId).notifier)
                  .onRunButtonDown(),
        onTapUp: myEliminated || !isGreen
            ? null
            : (_) => ref
                  .read(redlightProvider(widget.familyId).notifier)
                  .onRunButtonUp(),
        onTapCancel: myEliminated || !isGreen
            ? null
            : () => ref
                  .read(redlightProvider(widget.familyId).notifier)
                  .onRunButtonUp(),
        child: AnimatedContainer(
          duration: GameMotionTokens.fast,
          curve: GameMotionTokens.bounce,
          width: double.infinity,
          height: 80,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(KinrelRadius.xl),
            boxShadow: isGreen
                ? [
                    BoxShadow(
                      color: KinrelColors.orangeGlowIntense,
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: myEliminated
                    ? KinrelColors.textDim
                    : (isGreen || isRed)
                    ? Colors.white
                    : KinrelColors.textDim,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
