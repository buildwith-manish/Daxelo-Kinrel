// lib/features/games/night_falls/night_falls_game_screen.dart
//
// Night Falls — main match screen.
//
// Layout (round flow):
//   ┌──────────────────────────────────────┐
//   │  🌙 Round 3  ·  ☀️ Day  ·  ⏱ 0:42    │  ← Top HUD
//   ├──────────────────────────────────────┤
//   │  [Phase banner]                       │
//   │                                        │
//   │  Role Reveal: "You are the Seer 🔮"   │  ← Phase-specific view
//   │  Night: pick kill/investigate/protect  │
//   │  Day: "X was killed by wolves"        │
//   │  Vote: pick a suspect                  │
//   │  Result: "Y was voted out — Werewolf!" │
//   │  Finished: "🐺 Werewolves win!"        │
//   │                                        │
//   │  [Player roster with alive/dead]       │
//   └──────────────────────────────────────┘

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';
import '../../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/widgets/reactions_bar.dart';
import '../shared/models/game_invite.dart';
import '../shared/widgets/rematch_button.dart';
import 'night_falls_models.dart';
import 'night_falls_provider.dart';

/// Indigo accent — evokes the "night" theme.
const Color _kNightFallsAccent = Color(0xFF6366F1);

class NightFallsGameScreen extends ConsumerStatefulWidget {
  const NightFallsGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<NightFallsGameScreen> createState() =>
      _NightFallsGameScreenState();
}

class _NightFallsGameScreenState extends ConsumerState<NightFallsGameScreen> {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(nightFallsProvider(widget.familyId).notifier)
          .loadGame(widget.gameId);
    });
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final state = ref.read(nightFallsProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId &&
          state.game?.isWaiting == true,
      gameName: 'Night Falls',
    );
    if (shouldLeave == true) {
      await ref
          .read(nightFallsProvider(widget.familyId).notifier)
          .leaveGame();
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/family/${widget.familyId}');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nightFallsProvider(widget.familyId));
    final game = state.game;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    if (state.isLoading && game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
          title: const Text('Night Falls'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: const Center(
            child: CircularProgressIndicator(color: _kNightFallsAccent)),
      );
    }
    if (game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/family/${widget.familyId}')),
          title: const Text('Night Falls'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: Center(
          child: GamingEmptyCard(
            emoji: '🌙',
            title: 'Game not found',
            message: 'This game may have ended or been cancelled.',
          ),
        ),
      );
    }
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
        title: Text(
          game.roomName?.isNotEmpty == true
              ? game.roomName!
              : 'Night Falls',
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
          if (game.isInProgress)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: _RoundIndicator(game: game)),
            ),
          if (game.hostUserId ==
                  ref.read(supabaseProvider)?.auth.currentUser?.id &&
              game.isInProgress)
            IconButton(
              tooltip: 'Leave game',
              icon: const Icon(Icons.logout, size: 20),
              onPressed: _confirmLeave,
            ),
        ],
      ),
      body: game.isCompleted
          ? _FinishedView(
              game: game,
              familyId: widget.familyId,
              state: state,
              isHost: game.hostUserId == myId,
              onRematch: () => ref
                  .read(nightFallsProvider(widget.familyId).notifier)
                  .rematch(),
              onExit: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/family/${widget.familyId}');
                }
              },
            )
          : _GameView(
              state: state,
              familyId: widget.familyId,
              onSubmitNightAction: (targetUserId, actionType) => ref
                  .read(nightFallsProvider(widget.familyId).notifier)
                  .submitNightAction(targetUserId, actionType),
              onVote: (targetUserId) => ref
                  .read(nightFallsProvider(widget.familyId).notifier)
                  .vote(targetUserId),
              onHunterRevenge: (targetUserId) => ref
                  .read(nightFallsProvider(widget.familyId).notifier)
                  .hunterRevenge(targetUserId),
              onAdvance: () => ref
                  .read(nightFallsProvider(widget.familyId).notifier)
                  .advancePhase(),
            ),
    );
  }
}

class _RoundIndicator extends StatelessWidget {
  const _RoundIndicator({required this.game});
  final NightFallsGame game;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final current = board?.currentRoundNumber ?? 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kNightFallsAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'R$current',
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _kNightFallsAccent,
        ),
      ),
    );
  }
}

class _GameView extends ConsumerWidget {
  const _GameView({
    required this.state,
    required this.familyId,
    required this.onSubmitNightAction,
    required this.onVote,
    required this.onHunterRevenge,
    required this.onAdvance,
  });
  final NightFallsState state;
  final String familyId;
  final void Function(String targetUserId, NightFallsActionType actionType)
      onSubmitNightAction;
  final void Function(String targetUserId) onVote;
  final void Function(String targetUserId) onHunterRevenge;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = state.game!;
    final board = game.boardState;
    if (board == null) {
      return const Center(
          child: CircularProgressIndicator(color: _kNightFallsAccent));
    }
    final round = board.currentRound;
    if (round == null) return const SizedBox.shrink();
    return Column(
      children: [
        _PhaseBanner(round: round, game: game),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            child: Column(
              children: [
                if (round.phase == NightFallsPhase.roleReveal)
                  _RoleRevealView(
                    state: state,
                    onReady: onAdvance,
                  ),
                if (round.phase == NightFallsPhase.night)
                  _NightView(
                    state: state,
                    round: round,
                    onSubmit: onSubmitNightAction,
                  ),
                if (round.phase == NightFallsPhase.day)
                  _DayView(round: round, onAdvance: onAdvance),
                if (round.phase == NightFallsPhase.vote)
                  _VoteView(
                    state: state,
                    round: round,
                    onVote: onVote,
                  ),
                if (round.phase == NightFallsPhase.result)
                  _ResultView(
                    state: state,
                    round: round,
                    onHunterRevenge: onHunterRevenge,
                    onAdvance: onAdvance,
                  ),
                const SizedBox(height: KinrelSpacing.md),
                _PlayerRoster(state: state),
                if (state.myRole == NightFallsRole.seer &&
                    state.seerResults.isNotEmpty)
                  _SeerHistoryCard(state: state),
              ],
            ),
          ),
        ),
        if (state.amSpectator)
          ReactionsBar(
            gameTable: 'night_falls_games',
            gameId: game.id,
            familyId: familyId,
          ),
      ],
    );
  }
}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({required this.round, required this.game});
  final NightFallsRound round;
  final NightFallsGame game;

  @override
  Widget build(BuildContext context) {
    final (label, color, glyph) = switch (round.phase) {
      NightFallsPhase.roleReveal => (
          '🎭 Tap to reveal your role',
          _kNightFallsAccent,
          '🎭'
        ),
      NightFallsPhase.night => (
          '🌙 Night — Wolves hunt, Seer sees, Doctor protects',
          const Color(0xFF4338CA),
          '🌙'
        ),
      NightFallsPhase.day => (
          '☀️ Day — Discuss and find the wolves',
          const Color(0xFFF59E0B),
          '☀️'
        ),
      NightFallsPhase.vote => (
          '🗳️ Vote — Choose who to eliminate',
          KinrelColors.error,
          '🗳️'
        ),
      NightFallsPhase.result => (
          '📊 Result — Role revealed',
          KinrelColors.brightGold,
          '📊'
        ),
      NightFallsPhase.finished => ('🏁 Game Over', KinrelColors.textDim, '🏁'),
    };
    final secondsLeft = game.turnSecondsRemaining;
    return Container(
      margin: const EdgeInsets.fromLTRB(
          KinrelSpacing.md, KinrelSpacing.sm, KinrelSpacing.md, KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Text(glyph, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color, blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          if (secondsLeft != null && round.phase != NightFallsPhase.roleReveal)
            Text(
              '${secondsLeft ~/ 60}:${(secondsLeft % 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: secondsLeft <= 10
                    ? KinrelColors.error
                    : KinrelColors.textWhite,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Role reveal
// ─────────────────────────────────────────────────────────────────────────

class _RoleRevealView extends StatefulWidget {
  const _RoleRevealView({required this.state, required this.onReady});
  final NightFallsState state;
  final VoidCallback onReady;

  @override
  State<_RoleRevealView> createState() => _RoleRevealViewState();
}

class _RoleRevealViewState extends State<_RoleRevealView> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final role = widget.state.myRole;
    if (role == null) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: _kNightFallsAccent.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            const Text('🌙', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Loading your role...',
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textDim)),
          ],
        ),
      );
    }
    if (!_revealed) {
      return GestureDetector(
        onTap: () => setState(() => _revealed = true),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: _kNightFallsAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const Text('🌙', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('Tap to reveal your role',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite)),
              const SizedBox(height: 4),
              Text('Make sure no one else is looking!',
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim)),
            ],
          ),
        ),
      );
    }
    final isWolf = role.isWolf;
    final roleColor = isWolf
        ? KinrelColors.error
        : role == NightFallsRole.seer
            ? const Color(0xFFA855F7)
            : role == NightFallsRole.doctor
                ? KinrelColors.success
                : role == NightFallsRole.hunter
                    ? KinrelColors.amber
                    : KinrelColors.textSilver;
    final fellowWolves = widget.state.fellowWolves;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: roleColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(role.glyph, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text('You are the ${role.label}',
              style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: roleColor)),
          const SizedBox(height: 10),
          Text(role.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textSilver,
                  height: 1.4)),
          if (isWolf && fellowWolves.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: KinrelColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: KinrelColors.error.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text('🐺 Your pack:',
                      style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.error,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final wolfId in fellowWolves)
                        _NameChip(
                            name: widget.state.playerFor(wolfId)?.userName ??
                                'Werewolf',
                            color: KinrelColors.error),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          DKButton(
            label: 'Got it!',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            onPressed: widget.onReady,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Night phase
// ─────────────────────────────────────────────────────────────────────────

class _NightView extends ConsumerStatefulWidget {
  const _NightView({
    required this.state,
    required this.round,
    required this.onSubmit,
  });
  final NightFallsState state;
  final NightFallsRound round;
  final void Function(String targetUserId, NightFallsActionType actionType)
      onSubmit;

  @override
  ConsumerState<_NightView> createState() => _NightViewState();
}

class _NightViewState extends ConsumerState<_NightView> {
  String? _selectedTarget;

  @override
  Widget build(BuildContext context) {
    final role = widget.state.myRole;
    final board = widget.state.game!.boardState!;
    final expectedLocks = NightFallsEngine.expectedNightLocks(board.playerCount);
    final lockedCount = widget.round.nightActions.lockedCount;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    // Determine the caller's night action type + whether they've submitted
    final actionType = switch (role) {
      NightFallsRole.werewolf => NightFallsActionType.wolfKill,
      NightFallsRole.seer => NightFallsActionType.seerInvestigate,
      NightFallsRole.doctor => NightFallsActionType.doctorProtect,
      _ => null,
    };

    final hasSubmitted = actionType != null &&
        widget.state.myActions.any((a) =>
            a.actionType == actionType &&
            a.roundNumber == widget.round.roundNumber);

    if (actionType == null) {
      // Villager / Hunter — no night action
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF4338CA).withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            const Text('🌙', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('Night falls...',
                style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite)),
            const SizedBox(height: 8),
            Text(
                'You sleep peacefully. The wolves, seer, and doctor are acting in secret.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textDim,
                    height: 1.4)),
            const SizedBox(height: 16),
            _LockCounter(locked: lockedCount, expected: expectedLocks),
          ],
        ),
      );
    }

    final actionLabel = switch (role) {
      NightFallsRole.werewolf => 'Choose your victim',
      NightFallsRole.seer => 'Choose a player to investigate',
      NightFallsRole.doctor => 'Choose a player to protect',
      _ => '',
    };
    final actionColor = switch (role) {
      NightFallsRole.werewolf => KinrelColors.error,
      NightFallsRole.seer => const Color(0xFFA855F7),
      NightFallsRole.doctor => KinrelColors.success,
      _ => _kNightFallsAccent,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: actionColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: actionColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(role!.glyph, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(actionLabel,
                        style: TextStyle(
                            fontFamily: KinrelTypography.displayFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: actionColor)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!hasSubmitted) ...[
                _PlayerTargetList(
                  state: widget.state,
                  selectedTarget: _selectedTarget,
                  myId: myId,
                  onSelect: (userId) =>
                      setState(() => _selectedTarget = userId),
                  canTargetSelf: role == NightFallsRole.doctor,
                  excludeFellowWolves: role == NightFallsRole.werewolf,
                  fellowWolves: widget.state.fellowWolves,
                  accentColor: actionColor,
                ),
                const SizedBox(height: 12),
                DKButton(
                  label: 'Lock in choice',
                  variant: DKButtonVariant.primary,
                  fullWidth: true,
                  onPressed: _selectedTarget != null
                      ? () {
                          widget.onSubmit(_selectedTarget!, actionType);
                        }
                      : null,
                ),
              ] else ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Text(role.glyph,
                            style: const TextStyle(fontSize: 36)),
                        const SizedBox(height: 8),
                        Text('Choice locked in. Waiting for night to end...',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 13,
                                color: KinrelColors.textDim)),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _LockCounter(locked: lockedCount, expected: expectedLocks),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Day phase
// ─────────────────────────────────────────────────────────────────────────

class _DayView extends StatelessWidget {
  const _DayView({required this.round, required this.onAdvance});
  final NightFallsRound round;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final na = round.nightActions;
    final noKill = na.noKill || na.killedUserId == null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: (noKill ? KinrelColors.success : KinrelColors.error)
                .withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(noKill ? '☀️' : '💀',
              style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
              noKill
                  ? 'No one died last night!'
                  : '${na.killedUserName ?? 'A villager'} was killed by wolves!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: noKill ? KinrelColors.success : KinrelColors.error)),
          const SizedBox(height: 10),
          Text(
              noKill
                  ? 'The doctor saved a life, or the wolves stayed their hand. Debate who the wolves might be.'
                  : 'A tragic night. Discuss your suspicions and vote to eliminate a suspect.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textSilver,
                  height: 1.4)),
          const SizedBox(height: 16),
          DKButton(
            label: 'Start Vote →',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            onPressed: onAdvance,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Vote phase
// ─────────────────────────────────────────────────────────────────────────

class _VoteView extends ConsumerStatefulWidget {
  const _VoteView({
    required this.state,
    required this.round,
    required this.onVote,
  });
  final NightFallsState state;
  final NightFallsRound round;
  final void Function(String targetUserId) onVote;

  @override
  ConsumerState<_VoteView> createState() => _VoteViewState();
}

class _VoteViewState extends ConsumerState<_VoteView> {
  String? _selectedTarget;
  bool _voted = false;

  @override
  Widget build(BuildContext context) {
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final me = widget.state.playerFor(myId);
    final iVoted = widget.state.myActions.any((a) =>
        a.actionType == NightFallsActionType.vote &&
        a.roundNumber == widget.round.roundNumber);
    if (iVoted) _voted = true;
    final aliveCount =
        widget.state.players.where((p) => p.isAlive).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GamingSectionHeader(
          title: _voted ? 'Vote cast — waiting for others' : 'Who should be eliminated?',
          icon: Icons.how_to_vote_outlined,
        ),
        const SizedBox(height: 8),
        if (!_voted && me != null && me.isAlive) ...[
          _PlayerTargetList(
            state: widget.state,
            selectedTarget: _selectedTarget,
            myId: myId,
            onSelect: (userId) => setState(() => _selectedTarget = userId),
            canTargetSelf: false,
            excludeFellowWolves: false,
            fellowWolves: const [],
            accentColor: KinrelColors.error,
            onlyAlive: true,
          ),
          const SizedBox(height: 12),
          DKButton(
            label: 'Cast Vote',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            onPressed: _selectedTarget != null
                ? () {
                    widget.onVote(_selectedTarget!);
                    setState(() => _voted = true);
                  }
                : null,
          ),
        ] else if (me != null && !me.isAlive) ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('👻', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 8),
                  Text('You\'re eliminated — spectating the vote.',
                      style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          color: KinrelColors.textDim)),
                ],
              ),
            ),
          ),
        ] else ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('🗳️', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 8),
                  Text(
                      'Vote submitted! Waiting for ${aliveCount - widget.round.voteLockedCount} more...',
                      style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 14,
                          color: KinrelColors.textDim)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Result phase (vote outcome + hunter revenge)
// ─────────────────────────────────────────────────────────────────────────

class _ResultView extends ConsumerStatefulWidget {
  const _ResultView({
    required this.state,
    required this.round,
    required this.onHunterRevenge,
    required this.onAdvance,
  });
  final NightFallsState state;
  final NightFallsRound round;
  final void Function(String targetUserId) onHunterRevenge;
  final VoidCallback onAdvance;

  @override
  ConsumerState<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends ConsumerState<_ResultView> {
  String? _revengeTarget;

  @override
  Widget build(BuildContext context) {
    final round = widget.round;
    final eliminated = round.eliminatedUserName;
    final eliminatedRole = round.eliminatedRole;
    final noElimination = eliminated == null || eliminated == 'No one (tie)';
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final me = widget.state.playerFor(myId);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: (eliminatedRole?.isWolf ?? false)
                    ? KinrelColors.success.withValues(alpha: 0.4)
                    : KinrelColors.error.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Text(noElimination ? '🤝' : (eliminatedRole?.isWolf ?? false) ? '🎯' : '⚠️',
                  style: const TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(
                  noElimination
                      ? 'No one was eliminated (tie vote)'
                      : '$eliminated was voted out',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.textWhite)),
              if (!noElimination && eliminatedRole != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: (eliminatedRole.isWolf
                            ? KinrelColors.error
                            : const Color(0xFFA855F7))
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(eliminatedRole.glyph,
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text('They were the ${eliminatedRole.label}',
                          style: TextStyle(
                              fontFamily: KinrelTypography.displayFont,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: eliminatedRole.isWolf
                                  ? KinrelColors.error
                                  : const Color(0xFFA855F7))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Hunter revenge
        if (round.hunterRevengePending) ...[
          const SizedBox(height: 16),
          if (me != null &&
              widget.state.myRole == NightFallsRole.hunter) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: KinrelColors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: KinrelColors.amber.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('🎯', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Hunter\'s Revenge — take one player down',
                            style: TextStyle(
                                fontFamily: KinrelTypography.displayFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.amber)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _PlayerTargetList(
                    state: widget.state,
                    selectedTarget: _revengeTarget,
                    myId: myId,
                    onSelect: (userId) =>
                        setState(() => _revengeTarget = userId),
                    canTargetSelf: false,
                    excludeFellowWolves: false,
                    fellowWolves: const [],
                    accentColor: KinrelColors.amber,
                    onlyAlive: true,
                  ),
                  const SizedBox(height: 12),
                  DKButton(
                    label: 'Take them down!',
                    variant: DKButtonVariant.primary,
                    fullWidth: true,
                    onPressed: _revengeTarget != null
                        ? () => widget.onHunterRevenge(_revengeTarget!)
                        : null,
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: KinrelColors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: KinrelColors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Text('🎯', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('The Hunter is choosing their revenge...',
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: KinrelColors.textDim)),
                  ),
                ],
              ),
            ),
          ],
        ] else if (round.hunterRevengeTargetName != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: KinrelColors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: KinrelColors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Text('🎯', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Hunter\'s revenge: ${round.hunterRevengeTargetName} (${round.hunterRevengeRole?.label ?? '?'}) was taken down!',
                      style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          color: KinrelColors.textSilver)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DKButton(
            label: 'Next Night →',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            onPressed: widget.onAdvance,
          ),
        ] else ...[
          const SizedBox(height: 16),
          DKButton(
            label: 'Next Night →',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            onPressed: widget.onAdvance,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Finished view (game over)
// ─────────────────────────────────────────────────────────────────────────

class _FinishedView extends StatelessWidget {
  const _FinishedView({
    required this.game,
    required this.familyId,
    required this.state,
    required this.isHost,
    required this.onRematch,
    required this.onExit,
  });
  final NightFallsGame game;
  final String familyId;
  final NightFallsState state;
  final bool isHost;
  final Future<String?> Function() onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final winnerTeam = board?.winnerTeam;
    final winnerIds = game.winnerUserIds;
    final roles = board?.roles ?? {};
    final wolvesWin = winnerTeam == NightFallsTeam.wolves;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      child: Column(
        children: [
          if (winnerIds.isNotEmpty) const GameConfetti(),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: wolvesWin
                    ? [const Color(0xFF2A0E0E), const Color(0xFF1C1010)]
                    : [const Color(0xFF0E1C2A), const Color(0xFF10141C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: (wolvesWin ? KinrelColors.error : _kNightFallsAccent)
                      .withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                Text(winnerTeam?.glyph ?? '🌙',
                    style: const TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                Text(
                    winnerTeam != null
                        ? '${winnerTeam.label} Win!'
                        : 'Match Complete',
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: wolvesWin
                            ? KinrelColors.error
                            : _kNightFallsAccent)),
                const SizedBox(height: 6),
                Text(
                    wolvesWin
                        ? 'The wolves devoured the village.'
                        : 'The village hunted down all the wolves.',
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textDim)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GamingSectionHeader(title: 'Final Roster', icon: Icons.groups_outlined),
          const SizedBox(height: 8),
          for (final p in state.players)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Text(p.isAlive ? '🟢' : '💀',
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(p.userName,
                          style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: KinrelColors.textWhite)),
                    ),
                    if (roles.isNotEmpty) ...[
                      Text(roles[p.userId]?.glyph ?? '',
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(roles[p.userId]?.label ?? '?',
                          style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: roles[p.userId]?.isWolf ?? false
                                  ? KinrelColors.error
                                  : KinrelColors.textSilver)),
                    ] else ...[
                      Text(p.isAlive ? 'Survived' : 'Eliminated',
                          style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 12,
                              color: KinrelColors.textDim)),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 18),
          MatchEcosystemSummary(
            gameTable: 'night_falls_games',
            gameId: game.id,
            familyId: familyId,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: DKButton(
                  label: 'Exit',
                  variant: DKButtonVariant.secondary,
                  fullWidth: true,
                  onPressed: onExit,
                ),
              ),
              // Host-gated shared rematch — provider rematch() carries the
              // roster and writes invites itself (insertInvites: false).
              if (isHost) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: RematchButton(
                    familyId: familyId,
                    gameType: GameType.nightFalls,
                    previousGameId: game.id,
                    participantUserIds: state.players
                        .where((p) => p.isActive)
                        .map((p) => p.userId)
                        .toList(),
                    maxPlayers: game.maxPlayers,
                    insertInvites: false,
                    onCreateNewGame: onRematch,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────

class _PlayerRoster extends StatelessWidget {
  const _PlayerRoster({required this.state});
  final NightFallsState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GamingSectionHeader(title: 'Players', icon: Icons.people_outline),
        const SizedBox(height: 8),
        for (final p in state.players)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: p.isAlive
                        ? Colors.transparent
                        : KinrelColors.error.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (p.isAlive ? _kNightFallsAccent : KinrelColors.error)
                          .withValues(alpha: 0.2),
                    ),
                    child: Center(
                      child: Text(
                        p.userName.isNotEmpty
                            ? p.userName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: p.isAlive
                              ? _kNightFallsAccent
                              : KinrelColors.error,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.userName,
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: p.isAlive
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: p.isAlive
                                ? KinrelColors.textWhite
                                : KinrelColors.textDim,
                            decoration: p.isAlive
                                ? null
                                : TextDecoration.lineThrough)),
                  ),
                  if (!p.isAlive)
                    Text('💀',
                        style: TextStyle(
                            fontSize: 14,
                            color: KinrelColors.error.withValues(alpha: 0.6))),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SeerHistoryCard extends StatelessWidget {
  const _SeerHistoryCard({required this.state});
  final NightFallsState state;

  @override
  Widget build(BuildContext context) {
    final results = state.seerResults
      ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFA855F7).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFFA855F7).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔮', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text('Seer\'s Investigations',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFA855F7))),
            ],
          ),
          const SizedBox(height: 10),
          for (final r in results)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Text('R${r.roundNumber}',
                      style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textDim)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        state.playerFor(r.targetUserId)?.userName ?? 'Unknown',
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            color: KinrelColors.textWhite)),
                  ),
                  Text(r.seerVerdict == 'werewolf' ? '🐺 Werewolf' : '🟢 Villager',
                      style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: r.seerVerdict == 'werewolf'
                              ? KinrelColors.error
                              : KinrelColors.success)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LockCounter extends StatelessWidget {
  const _LockCounter({required this.locked, required this.expected});
  final int locked;
  final int expected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$locked/$expected locked',
            style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: locked >= expected
                    ? KinrelColors.success
                    : KinrelColors.textDim)),
        const SizedBox(width: 8),
        ...List.generate(expected, (i) {
          final filled = i < locked;
          return Container(
            margin: const EdgeInsets.only(right: 3),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: filled
                  ? (locked >= expected
                      ? KinrelColors.success
                      : _kNightFallsAccent)
                  : KinrelColors.border,
              shape: BoxShape.circle,
            ),
          );
        }),
      ],
    );
  }
}

class _PlayerTargetList extends StatelessWidget {
  const _PlayerTargetList({
    required this.state,
    required this.selectedTarget,
    required this.myId,
    required this.onSelect,
    required this.canTargetSelf,
    required this.excludeFellowWolves,
    required this.fellowWolves,
    required this.accentColor,
    this.onlyAlive = true,
  });
  final NightFallsState state;
  final String? selectedTarget;
  final String? myId;
  final void Function(String userId) onSelect;
  final bool canTargetSelf;
  final bool excludeFellowWolves;
  final List<String> fellowWolves;
  final Color accentColor;
  final bool onlyAlive;

  @override
  Widget build(BuildContext context) {
    final board = state.game?.boardState;
    // Use boardState players for alive status (more up-to-date than
    // night_falls_players which has column-level GRANT hiding isAlive
    // updates during the game). Fall back to wire players.
    final boardPlayers = board?.players ?? const <NightFallsPlayer>[];
    bool isAlive(String userId) {
      for (final p in boardPlayers) {
        if (p.userId == userId) return p.isAlive;
      }
      return state.playerFor(userId)?.isAlive ?? false;
    }

    final candidates = state.players.where((p) {
      if (onlyAlive && !isAlive(p.userId)) return false;
      if (!canTargetSelf && p.userId == myId) return false;
      if (excludeFellowWolves && fellowWolves.contains(p.userId)) return false;
      return true;
    }).toList();

    return Column(
      children: [
        for (final p in candidates)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              onTap: () => onSelect(p.userId),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selectedTarget == p.userId
                      ? accentColor.withValues(alpha: 0.12)
                      : KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selectedTarget == p.userId
                        ? accentColor.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor.withValues(alpha: 0.2),
                      ),
                      child: Center(
                        child: Text(
                          p.userName.isNotEmpty
                              ? p.userName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: accentColor),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(p.userName,
                          style: TextStyle(
                              fontFamily: KinrelTypography.bodyFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: KinrelColors.textWhite)),
                    ),
                    if (selectedTarget == p.userId)
                      Icon(Icons.check_circle, color: accentColor, size: 20),
                  ],
                ),
              ),
            ),
          ),
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('No valid targets.',
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textDim)),
          ),
      ],
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(name,
          style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite)),
    );
  }
}
