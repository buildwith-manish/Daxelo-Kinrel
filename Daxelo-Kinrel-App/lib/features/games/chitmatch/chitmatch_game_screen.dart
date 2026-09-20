import '../../../core/widgets/person_avatar.dart';
// lib/features/games/chitmatch/chitmatch_game_screen.dart
//
// TripleMatch — main game screen with chit display, selection,
// round timer, passing animation, and results.
// Route: /family/$familyId/chitmatch/game/:gameId

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../shared/icons/kinrel_icons.dart';
import '../shared/services/temporary_room_service.dart';
import '../shared/widgets/game_board_shell.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/models/game_invite.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/widgets/rematch_button.dart';
import 'chitmatch_models.dart';
import 'chitmatch_provider.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';

class ChitmatchGameScreen extends ConsumerStatefulWidget {
  const ChitmatchGameScreen({super.key, required this.familyId, required this.gameId});
  final String familyId;
  final String gameId;

  @override
  ConsumerState<ChitmatchGameScreen> createState() => _ChitmatchGameScreenState();
}

class _ChitmatchGameScreenState extends ConsumerState<ChitmatchGameScreen> {
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(chitmatchProvider(widget.familyId));
      if (state.game == null) {
        ref.read(chitmatchProvider(widget.familyId).notifier).joinGame(widget.gameId);
      }
    });
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chitmatchProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    if (state.isCompleted) {
      return _resultsView(state, myId);
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () async {
            final state = ref.read(chitmatchProvider(widget.familyId));
            final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
            final gameId = state.game?.id;
            final iAmHost = state.game?.hostUserId == myId;
            // "Past the waiting room" = setup / in-progress / completed.
            final wasInProgress = state.game != null && !state.game!.isWaiting;
            final shouldLeave = await LeaveGameDialog.show(
              context,
              isHost: iAmHost,
              gameName: 'Chitmatch',
            );
            if (shouldLeave != true) return;
            if (!context.mounted) return;
            ref.read(chitmatchProvider(widget.familyId).notifier).leaveGame();
            // Only the HOST leaving past the waiting phase ends the match
            // for everyone (mirrors truthordare). Non-hosts just drop
            // their own player row — the room stays open, as the dialog
            // promises.
            if (gameId != null && iAmHost && wasInProgress) {
              ref.read(temporaryRoomServiceProvider).endGame(
                    gameTable: 'chitmatch_games',
                    gameId: gameId,
                  );
            }
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text('TripleMatch', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: state.isLoading && state.game == null
        ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : state.error != null && state.game == null
          ? DKErrorState(message: state.error!, onRetry: () => ref.read(chitmatchProvider(widget.familyId).notifier).joinGame(widget.gameId))
          : state.game == null
            ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
            : _gameView(state, myId),
    );
  }

  Widget _gameView(ChitmatchState state, String? myId) {
    final game = state.game!;
    final hand = state.myHand;
    final selectedIndex = state.mySelectedIndex;
    final isResolving = state.isResolving;

    // Round timer
    final roundEndsAt = game.roundEndsAt;
    int secondsRemaining = 0;
    if (roundEndsAt != null && game.isInProgress) {
      secondsRemaining = roundEndsAt.difference(DateTime.now()).inSeconds;
      if (secondsRemaining < 0) secondsRemaining = 0;
    }

    // Check if I have 3-of-a-kind
    final iHaveThreeOfAKind = hand.length == 3 && hand[0] == hand[1] && hand[1] == hand[2];

    return SafeArea(
      child: Column(
        children: [
          // Round info + timer
          _roundInfoBar(game, secondsRemaining, state),
          // My hand
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (iHaveThreeOfAKind)
                    Container(
                      margin: const EdgeInsets.only(bottom: KinrelSpacing.lg),
                      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.lg, vertical: KinrelSpacing.sm),
                      decoration: BoxDecoration(
                        color: KinrelColors.success.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(KinrelRadius.lg),
                        border: Border.all(color: KinrelColors.success, width: 2),
                      ),
                      child: Text('Three of a Kind!', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.success)),
                    ),
                  Text('YOUR HAND', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.5)),
                  const SizedBox(height: KinrelSpacing.md),
                  if (hand.isEmpty)
                    Text('Waiting for chits...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim))
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(hand.length, (i) => _chitCard(
                        hand[i], i, selectedIndex, isResolving, iHaveThreeOfAKind,
                      )),
                    ),
                  const SizedBox(height: KinrelSpacing.xl),
                  // Status
                  if (isResolving)
                    GameTurnPill(label: 'Resolving round…', color: KinrelColors.orange, active: true,
                      trailing: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange)))
                  else if (selectedIndex != null)
                    GameTurnPill(label: 'Chit selected — waiting for others…', color: KinrelColors.orange, active: true)
                  else if (game.isInProgress)
                    GameTurnPill(label: 'Tap a chit to pass it!', color: KinrelColors.orange, active: true),
                ],
              ),
            ),
          ),
          // Player count + winners so far
          _playerStatusBar(state),
          const SizedBox(height: KinrelSpacing.base),
        ],
      ),
    );
  }

  Widget _roundInfoBar(ChitmatchGame game, int secondsRemaining, ChitmatchState state) {
    final totalSeconds = game.roundTimerSeconds;
    final progress = (secondsRemaining / totalSeconds).clamp(0.0, 1.0);
    final timerColor = secondsRemaining <= 5 ? KinrelColors.error : KinrelColors.orange;

    return Container(
      margin: const EdgeInsets.all(KinrelSpacing.base),
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
      decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.border)),
      child: Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _infoChip('Round', '${game.roundNumber}', Icons.repeat_rounded),
            // Timer ring
            SizedBox(width: 48, height: 48, child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(value: progress, strokeWidth: 3, backgroundColor: KinrelColors.darkElevated, valueColor: AlwaysStoppedAnimation<Color>(timerColor)),
                Text('${secondsRemaining}s', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: timerColor)),
              ],
            )),
            _infoChip('Players', '${state.players.length}', Icons.people_rounded),
          ],
        ),
        const SizedBox(height: KinrelSpacing.sm),
        // Thin accent progress bar mirroring the round countdown.
        ClipRRect(borderRadius: BorderRadius.circular(2), child: SizedBox(height: 3, child: Stack(children: [
          Container(color: KinrelColors.darkElevated),
          Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: progress, child: Container(color: timerColor))),
        ]))),
      ]),
    );
  }

  Widget _infoChip(String label, String value, IconData icon) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: KinrelColors.textDim),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
      Text(label, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 9, color: KinrelColors.textDim)),
    ]);
  }

  /// Premium chit card — layered dark surface with a subtle diagonal
  /// card-back stripe pattern (cheap LinearGradient bands). Selecting
  /// lifts the card (-2 translate) with an accent ring and a deeper
  /// shadow. Three-of-a-kind hands get a success rim.
  Widget _chitCard(String word, int index, int? selectedIndex, bool isResolving, bool isThreeOfAKind) {
    final isSelected = index == selectedIndex;
    final canTap = !isResolving && !isThreeOfAKind;
    final accent = isThreeOfAKind ? KinrelColors.success : KinrelColors.orange;

    return GestureDetector(
      onTap: canTap ? () => ref.read(chitmatchProvider(widget.familyId).notifier).selectChit(index) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80, height: 112,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        transform: Matrix4.translationValues(0, isSelected ? -2 : 0, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [KinrelColors.darkElevated, KinrelColors.darkCard]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? KinrelColors.orange : (isThreeOfAKind ? KinrelColors.success.withValues(alpha: 0.7) : KinrelColors.border),
            width: isSelected ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: isSelected ? 0.5 : 0.35), blurRadius: isSelected ? 16 : 8, offset: Offset(0, isSelected ? 8 : 4)),
            if (isSelected) BoxShadow(color: KinrelColors.orange.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: 1),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12.5),
          child: Stack(children: [
            // Card-back diagonal stripe pattern.
            Positioned.fill(child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.06), Colors.transparent,
                  accent.withValues(alpha: 0.06), Colors.transparent,
                  accent.withValues(alpha: 0.06), Colors.transparent,
                  accent.withValues(alpha: 0.06), Colors.transparent,
                ],
                stops: const [0.0, 0.07, 0.14, 0.21, 0.28, 0.35, 0.42, 1.0],
              ),
            )))),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.style, size: 20, color: isSelected ? Colors.white : KinrelColors.textDim),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(word, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : KinrelColors.textWhite,
                  ),
                ),
              ),
              if (isSelected) ...[
                const SizedBox(height: 4),
                Icon(Icons.arrow_forward, size: 12, color: Colors.white),
              ],
            ]),
          ]),
        ),
      )
        .animate(target: isSelected ? 1 : 0)
        .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.0, 1.0), duration: 200.ms, curve: Curves.elasticOut),
    );
  }

  Widget _playerStatusBar(ChitmatchState state) {
    final game = state.game!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
        decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.md), border: Border.all(color: KinrelColors.border)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          ...state.players.map((p) {
            final hasSelected = p.selectedChitIndex != null;
            // While the round is live, players still choosing get a
            // pulsing amber "waiting on you" ring (GameTurnPill-style).
            final waiting = game.isInProgress && !hasSelected;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 32, height: 32, child: Stack(alignment: Alignment.center, children: [
                if (waiting)
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.75), width: 1.5),
                      boxShadow: [BoxShadow(color: KinrelColors.orange.withValues(alpha: 0.35), blurRadius: 8)],
                    ),
                  )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(begin: const Offset(0.94, 0.94), end: const Offset(1.16, 1.16), duration: 1000.ms, curve: Curves.easeInOut),
                Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle,
                  color: hasSelected ? KinrelColors.success : KinrelColors.darkElevated,
                  border: Border.all(color: hasSelected ? KinrelColors.success : KinrelColors.border, width: 1)),
                  child: Center(child: Text(PersonAvatar.initialsFor(p.userName), style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 10, fontWeight: FontWeight.w700, color: hasSelected ? Colors.white : KinrelColors.textDim)))),
              ])),
              const SizedBox(height: 3),
              Text(p.userName.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 9, fontWeight: FontWeight.w600, color: hasSelected ? KinrelColors.textWhite : KinrelColors.textDim)),
            ]);
          }),
        ]),
      ),
    );
  }

  // ── Results view ──────────────────────────────────────────────────

  Widget _resultsView(ChitmatchState state, String? myId) {
    final game = state.game!;
    final winners = game.winnerUserIds ?? [];
    final winnerNames = game.winnerNames ?? [];
    final isMyWin = winners.contains(myId);
    final isJointWin = winners.length > 1;

    return DKScaffold(
      gradient: isMyWin ? KinrelGradients.deepFireGradient : null,
      backgroundColor: isMyWin ? null : KinrelColors.darkSurface,
      appBar: AppBar(automaticallyImplyLeading: false,
        title: Text('Results', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: Colors.transparent, foregroundColor: KinrelColors.textWhite, elevation: 0),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
        const SizedBox(height: KinrelSpacing.lg),
        Column(children: [
          KinrelIcon(KinrelIconData.trophy, size: 64, color: KinrelColors.brightGold).animate(onPlay: (c) => c.forward()).fadeIn(duration: 500.ms).scale(begin: const Offset(0.5, 0.5), end: const Offset(1.0, 1.0), duration: 500.ms, curve: Curves.elasticOut),
          const SizedBox(height: KinrelSpacing.sm),
          Text(isMyWin ? (isJointWin ? 'Joint Winners!' : 'You Won!') : (isJointWin ? 'Joint Winners!' : 'Winner!'),
            style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 28, fontWeight: FontWeight.w800, color: KinrelColors.textWhite, letterSpacing: 2)),
          const SizedBox(height: KinrelSpacing.sm),
          Wrap(spacing: KinrelSpacing.sm, runSpacing: KinrelSpacing.sm, alignment: WrapAlignment.center,
            children: winnerNames.map((name) => Container(
              padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
              decoration: BoxDecoration(color: KinrelColors.orange.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.orange, width: 1)),
              child: Text(name, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.orange)),
            )).toList(),
          ),
        ]).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.92, 0.92), end: const Offset(1.0, 1.0), duration: 400.ms, curve: Curves.easeOutBack),
        const SizedBox(height: KinrelSpacing.xl),
        // Round history
        if (state.passes.isNotEmpty) ...[
          Text('Last Round Passes', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w600, color: KinrelColors.textDim)),
          const SizedBox(height: KinrelSpacing.sm),
          ...state.passes.where((p) => p.roundNumber == game.roundNumber - 1 || p.roundNumber == game.roundNumber).take(12).map((p) => Container(
            margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
            padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
            decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.md), border: Border.all(color: KinrelColors.border)),
            child: Row(children: [
              Expanded(child: Text('${p.fromPlayerName} → ${p.toPlayerName}', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textWhite))),
              Text(p.chitPassed, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: KinrelColors.orange)),
            ]),
          )),
        MatchEcosystemSummary(
          gameTable: 'chitmatch_games',
          gameId: widget.gameId,
          familyId: widget.familyId,
        ),
          const SizedBox(height: KinrelSpacing.xl),
        ],
        // Host: one-tap rematch — same player count & timer, invites
        // everyone who played this match.
        if (game.hostUserId == myId)
          RematchButton(
            familyId: widget.familyId,
            gameType: GameType.chitmatch,
            previousGameId: game.id,
            participantUserIds:
                state.players.map((p) => p.userId).toList(),
            maxPlayers: game.playerCount,
            onCreateNewGame: () => ref
                .read(chitmatchProvider(widget.familyId).notifier)
                .createGame(
                  playerCount: game.playerCount,
                  roundTimerSeconds: game.roundTimerSeconds,
                ),
          )
        else
          DKButton(label: 'Play Again', variant: DKButtonVariant.gradient, fullWidth: true, icon: Icons.refresh_rounded,
            onPressed: () { ref.read(chitmatchProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.pushReplacement('/family/${widget.familyId}/chitmatch/lobby'); }),
        const SizedBox(height: KinrelSpacing.sm),
        DKButton(label: 'Back to Hub', variant: DKButtonVariant.secondary, fullWidth: true,
          onPressed: () { ref.read(chitmatchProvider(widget.familyId).notifier).leaveGame(); if (context.mounted) context.go('/games?familyId=${widget.familyId}'); }),
        ]),
        // Explicit match-won celebration state → confetti volley.
        if (isMyWin)
          const Positioned.fill(
            child: IgnorePointer(child: GameConfetti(burstCount: 2, density: 2)),
          ),
      ]),
    );
  }
}
