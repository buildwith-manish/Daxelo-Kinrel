// lib/features/games/secret_heist/secret_heist_game_screen.dart
//
// Secret Heist — main match screen.
//
// Layout (round flow):
//   ┌──────────────────────────────────────┐
//   │  Round 3/5  ·  Timer 0:18  ·  Vault 320│  ← Top HUD
//   ├──────────────────────────────────────┤
//   │  [Vault visualization — gold bars]    │
//   │  Vault: 320 / 500                     │
//   ├──────────────────────────────────────┤
//   │  Phase: CHOOSING (3/5 locked)         │  ← Phase banner
//   │                                        │
//   │  ┌──────────────────────────────────┐│
//   │  │ Choose your action:               ││  ← Action selection
//   │  │ [Steal] [Protect] [Spy]           ││     (only visible during
//   │  │ [Trap]  [Hack]                    ││      choosing phase)
//   │  └──────────────────────────────────┘│
//   │                                        │
//   │  Players (suspicion meters)            │
//   ├──────────────────────────────────────┤
//  OR (revealing phase):
//   │  Round 3 Results                       │
//   │  Vault Lost: 60 coins                  │
//   │  2 Successful Steals · 1 Trap · 1 Hack │
//   │  [Revealed actions list]               │
//   │  [Next Round →]                        │
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
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/widgets/reactions_bar.dart';
import 'secret_heist_models.dart';
import 'secret_heist_provider.dart';

class SecretHeistGameScreen extends ConsumerStatefulWidget {
  const SecretHeistGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<SecretHeistGameScreen> createState() =>
      _SecretHeistGameScreenState();
}

class _SecretHeistGameScreenState
    extends ConsumerState<SecretHeistGameScreen> {
  Timer? _clockTimer;
  HeistAction? _selectedAction;
  int _selectedAmount = 20;
  bool _submitted = false;
  int _lastSeenRound = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(secretHeistProvider(widget.familyId).notifier)
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
    final state = ref.read(secretHeistProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId &&
          state.game?.isWaiting == true,
      gameName: 'Secret Heist',
    );
    if (shouldLeave == true) {
      await ref
          .read(secretHeistProvider(widget.familyId).notifier)
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
    final state = ref.watch(secretHeistProvider(widget.familyId));
    final game = state.game;

    if (state.isLoading && game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
          title: const Text('Secret Heist'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange),
        ),
      );
    }

    if (game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/family/${widget.familyId}')),
          title: const Text('Secret Heist'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: Center(
          child: GamingEmptyCard(
            emoji: '💰',
            title: 'Game not found',
            message: 'This match may have ended.',
          ),
        ),
      );
    }

    // New round → unlock the action form for this round.
    final roundNumber = game.boardState?.currentRoundNumber;
    if (roundNumber != null && roundNumber != _lastSeenRound) {
      final isNewRound = _lastSeenRound != 0;
      _lastSeenRound = roundNumber;
      if (isNewRound) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _submitted = false;
              _selectedAction = null;
            });
          }
        });
      }
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
        title: Text(
          game.roomName?.isNotEmpty == true ? game.roomName! : 'Secret Heist',
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
              child: Center(child: _RoundInfo(game: game)),
            ),
          if (game.hostUserId ==
                  ref.read(supabaseProvider)?.auth.currentUser?.id &&
              game.isInProgress)
            IconButton(
              tooltip: 'Leave',
              icon: const Icon(Icons.logout, size: 20),
              onPressed: _confirmLeave,
            ),
        ],
      ),
      body: game.isCompleted
          ? _ResultsView(
              game: game,
              familyId: widget.familyId,
              players: state.players,
              onRematch: () => ref
                  .read(secretHeistProvider(widget.familyId).notifier)
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
              game: game,
              familyId: widget.familyId,
              selectedAction: _selectedAction,
              selectedAmount: _selectedAmount,
              submitted: _submitted,
              onActionChanged: (action) =>
                  setState(() => _selectedAction = action),
              onAmountChanged: (amt) =>
                  setState(() => _selectedAmount = amt),
              onSubmit: (action, amount) {
                ref
                    .read(secretHeistProvider(widget.familyId).notifier)
                    .submitAction(action, amount);
                setState(() => _submitted = true);
              },
              onAdvance: () => ref
                  .read(secretHeistProvider(widget.familyId).notifier)
                  .advancePhase(),
              onResetSubmit: () => setState(() {
                _submitted = false;
                _selectedAction = null;
              }),
            ),
    );
  }
}

class _RoundInfo extends StatelessWidget {
  const _RoundInfo({required this.game});
  final SecretHeistGame game;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final round = board?.currentRoundNumber ?? 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: KinrelColors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'R$round/${game.totalRounds}',
        style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: KinrelColors.amber),
      ),
    );
  }
}

class _GameView extends ConsumerWidget {
  const _GameView({
    required this.state,
    required this.game,
    required this.familyId,
    required this.selectedAction,
    required this.selectedAmount,
    required this.submitted,
    required this.onActionChanged,
    required this.onAmountChanged,
    required this.onSubmit,
    required this.onAdvance,
    required this.onResetSubmit,
  });

  final SecretHeistState_ state;
  final SecretHeistGame game;
  final String familyId;
  final HeistAction? selectedAction;
  final int selectedAmount;
  final bool submitted;
  final void Function(HeistAction) onActionChanged;
  final void Function(int) onAmountChanged;
  final void Function(HeistAction, int) onSubmit;
  final VoidCallback onAdvance;
  final VoidCallback onResetSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = game.boardState;
    if (board == null) {
      return const Center(
          child: CircularProgressIndicator(color: KinrelColors.orange));
    }
    final round = board.currentRound;
    if (round == null) return const SizedBox.shrink();

    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final myPlayer = board.players.where((p) => p.userId == myId).firstOrNull;
    final myCoins = myPlayer?.coins ?? game.startingCoins;
    final hasSubmitted = state.myAction != null || submitted;

    return Column(
      children: [
        _TopHud(game: game, board: board),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            child: Column(
              children: [
                _VaultCard(board: board),
                const SizedBox(height: 14),
                if (round.phase == HeistPhase.choosing) ...[
                  _ChoosingPhaseBanner(
                    lockedCount: round.lockedCount,
                    playerCount: board.playerCount,
                    secondsLeft: game.turnSecondsRemaining ?? 0,
                  ),
                  const SizedBox(height: 14),
                  if (!hasSubmitted)
                    _ActionSelectionCard(
                      coins: myCoins,
                      chaosMode: board.chaosMode,
                      selectedAction: selectedAction,
                      selectedAmount: selectedAmount,
                      onActionChanged: onActionChanged,
                      onAmountChanged: onAmountChanged,
                      onSubmit: onSubmit,
                      isSubmitting: state.isSubmitting,
                    )
                  else
                    _SubmittedCard(
                      lockedCount: round.lockedCount,
                      playerCount: board.playerCount,
                      myAction: state.myAction,
                    ),
                  const SizedBox(height: 14),
                  _SuspicionBoard(players: board.players, myUserId: myId),
                ] else if (round.phase == HeistPhase.revealing) ...[
                  _RevealView(
                    round: round,
                    board: board,
                    players: state.players,
                    onAdvance: onAdvance,
                    isLastRound:
                        board.currentRoundNumber >= board.totalRounds,
                  ),
                  const SizedBox(height: 14),
                  _SuspicionBoard(players: board.players, myUserId: myId),
                ] else if (round.phase == HeistPhase.resolving) ...[
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                          color: KinrelColors.orange),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (state.amSpectator)
          ReactionsBar(
            gameTable: 'secret_heist_games',
            gameId: game.id,
            familyId: familyId,
          ),
      ],
    );
  }
}

class _TopHud extends StatelessWidget {
  const _TopHud({required this.game, required this.board});
  final SecretHeistGame game;
  final HeistBoardState board;

  @override
  Widget build(BuildContext context) {
    final seconds = game.turnSecondsRemaining ?? 0;
    final timerColor =
        seconds <= 5 ? KinrelColors.error : KinrelColors.textWhite;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(bottom: BorderSide(color: KinrelColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  'Round ${board.currentRoundNumber}/${board.totalRounds}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.amber,
                  ),
                ),
                if (board.chaosMode) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: KinrelColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('CHAOS',
                        style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: KinrelColors.error)),
                  ),
                ],
              ],
            ),
          ),
          if (game.isInProgress)
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 14, color: timerColor),
                const SizedBox(width: 4),
                Text('${seconds}s',
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: timerColor)),
              ],
            ),
        ],
      ),
    );
  }
}

class _VaultCard extends StatelessWidget {
  const _VaultCard({required this.board});
  final HeistBoardState board;

  @override
  Widget build(BuildContext context) {
    final vaultPct = board.vaultRemainingPercent;
    final vaultColor = vaultPct > 50
        ? KinrelColors.amber
        : vaultPct > 25
            ? Colors.orange
            : KinrelColors.error;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            vaultColor.withValues(alpha: 0.15),
            const Color(0xFF1A1C2E),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: vaultColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_rounded,
                  size: 24, color: KinrelColors.brightGold),
              const SizedBox(width: 8),
              Text('The Vault',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite)),
              const Spacer(),
              Text(
                '${board.vaultCoins} / ${board.vaultSize}',
                style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: vaultColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Vault bar — represents remaining coins as gold bricks
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: vaultPct / 100,
              minHeight: 12,
              backgroundColor: KinrelColors.darkElevated,
              valueColor: AlwaysStoppedAnimation<Color>(vaultColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('$vaultPct% remaining',
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: KinrelColors.textDim)),
              const Spacer(),
              Text(
                  '${board.vaultSize - board.vaultCoins} stolen',
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.error)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChoosingPhaseBanner extends StatelessWidget {
  const _ChoosingPhaseBanner({
    required this.lockedCount,
    required this.playerCount,
    required this.secondsLeft,
  });
  final int lockedCount;
  final int playerCount;
  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    final allLocked = lockedCount >= playerCount;
    final color = allLocked ? KinrelColors.success : KinrelColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
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
              allLocked
                  ? 'All players locked — resolving...'
                  : '$lockedCount / $playerCount players locked in',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          if (!allLocked && secondsLeft > 0)
            Text(
              '${secondsLeft}s',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: secondsLeft <= 5
                    ? KinrelColors.error
                    : KinrelColors.textSilver,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionSelectionCard extends StatelessWidget {
  const _ActionSelectionCard({
    required this.coins,
    required this.chaosMode,
    required this.selectedAction,
    required this.selectedAmount,
    required this.onActionChanged,
    required this.onAmountChanged,
    required this.onSubmit,
    required this.isSubmitting,
  });

  final int coins;
  final bool chaosMode;
  final HeistAction? selectedAction;
  final int selectedAmount;
  final void Function(HeistAction) onActionChanged;
  final void Function(int) onAmountChanged;
  final void Function(HeistAction, int) onSubmit;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final actions = SecretHeistEngine.availableActions(chaosMode);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: KinrelColors.amber.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Your Coins: ',
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textDim)),
              Text('$coins',
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.amber)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Choose your action:',
              style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite)),
          const SizedBox(height: 10),
          // Action grid — 2 columns
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in actions)
                _ActionChip(
                  action: action,
                  selected: selectedAction == action,
                  onTap: () => onActionChanged(action),
                ),
            ],
          ),
          if (selectedAction != null && selectedAction!.requiresAmount) ...[
            const SizedBox(height: 14),
            Text('Amount: $selectedAmount coins',
                style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.amber)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final amt in const [10, 20, 30, 40, 50])
                  _AmountChip(
                    amount: amt,
                    selected: selectedAmount == amt,
                    onTap: () => onAmountChanged(amt),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          if (selectedAction != null)
            DKButton(
              label: 'Lock in ${selectedAction!.label}',
              variant: DKButtonVariant.primary,
              fullWidth: true,
              isLoading: isSubmitting,
              onPressed: () =>
                  onSubmit(selectedAction!, selectedAmount),
            ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.action,
    required this.selected,
    required this.onTap,
  });
  final HeistAction action;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Color(action.accentArgb);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 145,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.18)
              : KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? accent : Colors.transparent, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(action.glyph,
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    action.label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? accent
                          : KinrelColors.textWhite,
                    ),
                  ),
                ),
                if (action.isChaosOnly)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: KinrelColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('CHAOS',
                        style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: KinrelColors.error)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              action.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                  height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.amount,
    required this.selected,
    required this.onTap,
  });
  final int amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? KinrelColors.amber.withValues(alpha: 0.2)
              : KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? KinrelColors.amber : Colors.transparent),
        ),
        child: Text('$amount',
            style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? KinrelColors.amber
                    : KinrelColors.textSilver)),
      ),
    );
  }
}

class _SubmittedCard extends StatelessWidget {
  const _SubmittedCard({
    required this.lockedCount,
    required this.playerCount,
    required this.myAction,
  });
  final int lockedCount;
  final int playerCount;
  final SecretHeistActionWire? myAction;

  @override
  Widget build(BuildContext context) {
    final action = myAction?.parsedAction;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: KinrelColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          if (action != null) ...[
            Text(action.glyph, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 6),
            Text(action.label,
                style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(action.accentArgb))),
            if (action.requiresAmount && myAction != null)
              Text('${myAction!.amount} coins',
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 12,
                      color: KinrelColors.textDim)),
            const SizedBox(height: 12),
          ],
          const Icon(Icons.lock_outline, color: KinrelColors.success, size: 24),
          const SizedBox(height: 6),
          Text('Action locked in!',
              style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite)),
          const SizedBox(height: 4),
          Text(
              'Waiting for other players... ($lockedCount/$playerCount locked)',
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim)),
        ],
      ),
    );
  }
}

class _SuspicionBoard extends StatelessWidget {
  const _SuspicionBoard({required this.players, required this.myUserId});
  final List<HeistPlayer> players;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final sorted = List<HeistPlayer>.from(players)
      ..sort((a, b) => b.coins.compareTo(a.coins));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GamingSectionHeader(title: 'Players', icon: Icons.groups_2_outlined),
        for (final p in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _PlayerRow(player: p, isMe: p.userId == myUserId),
          ),
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.isMe});
  final HeistPlayer player;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final susp = player.suspicionLevel;
    final suspColor = Color(susp.accentArgb);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isMe
                ? KinrelColors.orange.withValues(alpha: 0.4)
                : Colors.transparent),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(player.name,
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isMe
                                ? KinrelColors.orange
                                : KinrelColors.textWhite)),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Text('YOU',
                          style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: KinrelColors.orange)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Suspicion meter
                Row(
                  children: [
                    Text('Suspicion:',
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 10,
                            color: KinrelColors.textDim)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: suspColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: suspColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(susp.label,
                          style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: suspColor)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text('${player.coins}',
              style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: KinrelColors.amber)),
        ],
      ),
    );
  }
}

class _RevealView extends StatelessWidget {
  const _RevealView({
    required this.round,
    required this.board,
    required this.players,
    required this.onAdvance,
    required this.isLastRound,
  });
  final HeistRound round;
  final HeistBoardState board;
  final List<SecretHeistPlayerWire> players;
  final VoidCallback onAdvance;
  final bool isLastRound;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: KinrelColors.brightGold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_rounded,
                  size: 22, color: KinrelColors.brightGold),
              const SizedBox(width: 8),
              Text('Round ${round.roundNumber} Results',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.brightGold)),
            ],
          ),
          const SizedBox(height: 14),
          // Headline metrics
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _MetricChip(
                    label: 'Vault Lost',
                    value: '${round.vaultLost}',
                    color: KinrelColors.error,
                  ),
                ),
                Expanded(
                  child: _MetricChip(
                    label: 'Steals',
                    value: '${round.stealsSuccessful}',
                    color: KinrelColors.amber,
                  ),
                ),
                Expanded(
                  child: _MetricChip(
                    label: 'Blocked',
                    value: '${round.stealsBlocked}',
                    color: const Color(0xFF3B82F6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetricChip(
                  label: 'Traps',
                  value: '${round.trapsTriggered}',
                  color: const Color(0xFFEF4444),
                ),
              ),
              Expanded(
                child: _MetricChip(
                  label: 'Hacks',
                  value: '${round.hacksSucceeded}',
                  color: const Color(0xFF10B981),
                ),
              ),
              Expanded(
                child: _MetricChip(
                  label: 'Alarms',
                  value: '${round.alarmsTriggered}',
                  color: const Color(0xFF06B6D4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Revealed actions (anonymous — only the action + outcome, not who)
          if (round.revealedActions.isNotEmpty) ...[
            Text('Revealed Actions',
                style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite)),
            const SizedBox(height: 8),
            for (final a in round.revealedActions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _RevealedActionRow(action: a, players: players),
              ),
          ],
          const SizedBox(height: 16),
          DKButton(
            label: isLastRound ? 'See Final Results' : 'Next Round →',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            onPressed: onAdvance,
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 9,
                  color: KinrelColors.textDim)),
        ],
      ),
    );
  }
}

class _RevealedActionRow extends StatelessWidget {
  const _RevealedActionRow({required this.action, required this.players});
  final RevealedAction action;
  final List<SecretHeistPlayerWire> players;

  @override
  Widget build(BuildContext context) {
    final player = players.where((p) => p.userId == action.userId).firstOrNull;
    final playerName = player?.userName ?? 'Unknown';
    final parsed = action.parsedAction;
    final accent = parsed != null ? Color(parsed.accentArgb) : Colors.grey;

    String outcomeLabel;
    switch (action.outcome) {
      case 'success':
        outcomeLabel = 'Success';
        break;
      case 'blocked':
        outcomeLabel = 'Blocked';
        break;
      case 'trapped':
        outcomeLabel = 'Trapped!';
        break;
      case 'backfire':
        outcomeLabel = 'Backfired';
        break;
      case 'alarm':
        outcomeLabel = 'Alarm!';
        break;
      case 'alarm_triggered':
        outcomeLabel = 'Alarm Triggered';
        break;
      case 'active':
        outcomeLabel = 'Active';
        break;
      case 'set':
        outcomeLabel = 'Set';
        break;
      case 'bait_success':
        outcomeLabel = 'Bait Success';
        break;
      case 'alarm_blocked':
        outcomeLabel = 'Alarm Blocked';
        break;
      default:
        outcomeLabel = action.outcome;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (parsed != null)
            Text(parsed.glyph, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(playerName,
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite)),
          ),
          if (action.amount != null && action.amount! > 0)
            Text('${action.amount}',
                style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 11,
                    color: KinrelColors.textDim)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(outcomeLabel,
                style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: accent)),
          ),
        ],
      ),
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.game,
    required this.familyId,
    required this.players,
    required this.onRematch,
    required this.onExit,
  });
  final SecretHeistGame game;
  final String familyId;
  final List<SecretHeistPlayerWire> players;
  final Future<String?> Function() onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final winnerIds = game.winnerUserIds;
    final winnerName = winnerIds.isNotEmpty
        ? players
            .where((p) => winnerIds.contains(p.userId))
            .map((p) => p.userName)
            .join(', ')
        : '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      child: Column(
        children: [
          if (winnerIds.isNotEmpty) const GameConfetti(),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2A1A0E), Color(0xFF1C1410)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: KinrelColors.brightGold.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                const KinrelIcon(KinrelIconData.trophy,
                    size: 40, color: KinrelColors.brightGold),
                const SizedBox(height: 8),
                Text(
                  winnerName.isNotEmpty
                      ? '$winnerName wins!'
                      : 'Match Complete',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.brightGold),
                ),
                const SizedBox(height: 4),
                Text('Most coins collected wins!',
                    style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textSilver)),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (board != null) ...[
            GamingSectionHeader(
                title: 'Final Standings', icon: Icons.leaderboard_outlined),
            for (final p in board.players
                .toList()
              ..sort((a, b) => b.coins.compareTo(a.coins)))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Text(
                        winnerIds.contains(p.userId) ? '🏆' : '🏅',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(p.name,
                            style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: KinrelColors.textWhite)),
                      ),
                      Text('${p.coins} coins',
                          style: TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: KinrelColors.amber)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            // Match stats
            GamingSectionHeader(
                title: 'Match Stats', icon: Icons.insights_outlined),
            _StatRow(
                label: 'Total stolen from vault',
                value: '${SecretHeistEngine.totalStolen(board.rounds)}'),
            _StatRow(
                label: 'Best shot',
                value: '${SecretHeistEngine.bestShot(board.rounds)} coins'),
            _StatRow(
                label: 'Successful steals',
                value:
                    '${board.rounds.fold<int>(0, (a, r) => a + r.stealsSuccessful)}'),
            _StatRow(
                label: 'Traps triggered',
                value:
                    '${board.rounds.fold<int>(0, (a, r) => a + r.trapsTriggered)}'),
            _StatRow(
                label: 'Hacks succeeded',
                value:
                    '${board.rounds.fold<int>(0, (a, r) => a + r.hacksSucceeded)}'),
            const SizedBox(height: 18),
          ],
          MatchEcosystemSummary(
            gameTable: 'secret_heist_games',
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
              const SizedBox(width: 10),
              Expanded(
                child: DKButton(
                  label: 'Rematch',
                  variant: DKButtonVariant.primary,
                  fullWidth: true,
                  onPressed: () async {
                    final newId = await onRematch();
                    if (newId != null && context.mounted) {
                      context.pushReplacement(
                        '/family/$familyId/secret-heist/game/$newId',
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim)),
            ),
            Text(value,
                style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite)),
          ],
        ),
      ),
    );
  }
}
