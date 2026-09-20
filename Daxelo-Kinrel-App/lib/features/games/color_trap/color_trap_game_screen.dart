// lib/features/games/color_trap/color_trap_game_screen.dart
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
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/reactions_bar.dart';
import '../shared/models/game_invite.dart';
import '../shared/widgets/rematch_button.dart';
import 'color_trap_engine.dart';
import 'color_trap_models.dart';
import 'color_trap_provider.dart';

class ColorTrapGameScreen extends ConsumerStatefulWidget {
  const ColorTrapGameScreen({super.key, required this.familyId, required this.gameId});
  final String familyId; final String gameId;
  @override ConsumerState<ColorTrapGameScreen> createState() => _ColorTrapGameScreenState();
}

class _ColorTrapGameScreenState extends ConsumerState<ColorTrapGameScreen> {
  Timer? _clockTimer;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(colorTrapProvider(widget.familyId).notifier).loadGame(widget.gameId)); _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) { if (mounted) setState(() {}); }); }
  @override void dispose() { _clockTimer?.cancel(); super.dispose(); }

  Future<void> _confirmLeave() async {
    final state = ref.read(colorTrapProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(context, isHost: state.game?.hostUserId == myId && state.game?.isWaiting == true, gameName: 'Color Trap');
    if (shouldLeave == true) { await ref.read(colorTrapProvider(widget.familyId).notifier).leaveGame(); if (mounted) { if (context.canPop()) context.pop(); else context.go('/family/${widget.familyId}'); } }
  }

  @override Widget build(BuildContext context) {
    final state = ref.watch(colorTrapProvider(widget.familyId));
    final game = state.game;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    if (state.isLoading && game == null) return DKScaffold(backgroundColor: KinrelColors.darkSurface, appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave), title: const Text('Color Trap'), backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite), body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)));
    if (game == null) return DKScaffold(backgroundColor: KinrelColors.darkSurface, appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/family/${widget.familyId}')), title: const Text('Color Trap'), backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite), body: Center(child: GamingEmptyCard(emoji: '🎨', title: 'Game not found', message: 'This game may have ended.')));
    return DKScaffold(backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
        title: Text(game.roomName?.isNotEmpty == true ? game.roomName! : 'Color Trap', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
        actions: [if (game.isInProgress) Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: _RoundInfo(game: game))), if (game.hostUserId == ref.read(supabaseProvider)?.auth.currentUser?.id && game.isInProgress) IconButton(tooltip: 'Leave', icon: const Icon(Icons.logout, size: 20), onPressed: _confirmLeave)]),
      body: game.isCompleted ? _ResultsView(game: game, familyId: widget.familyId, players: state.players, isHost: game.hostUserId == myId, onRematch: () => ref.read(colorTrapProvider(widget.familyId).notifier).rematch(), onExit: () { if (context.canPop()) context.pop(); else context.go('/family/${widget.familyId}'); })
        : _GameView(state: state, familyId: widget.familyId, onMove: (r, c) => ref.read(colorTrapProvider(widget.familyId).notifier).movePlayer(r, c), onAdvance: () => ref.read(colorTrapProvider(widget.familyId).notifier).advancePhase()));
  }
}

class _RoundInfo extends StatelessWidget {
  const _RoundInfo({required this.game}); final ColorTrapGame game;
  @override Widget build(BuildContext context) {
    final board = game.boardState; final round = board?.currentRoundNumber ?? 1;
    final alive = board?.aliveCount ?? 0;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: KinrelColors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Text('R$round · $alive alive', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.orange)));
  }
}

class _GameView extends ConsumerWidget {
  const _GameView({required this.state, required this.familyId, required this.onMove, required this.onAdvance});
  final ColorTrapState state; final String familyId;
  final void Function(int row, int col) onMove; final VoidCallback onAdvance;

  @override Widget build(BuildContext context, WidgetRef ref) {
    final game = state.game!; final board = game.boardState;
    if (board == null) return const Center(child: CircularProgressIndicator(color: KinrelColors.orange));
    final round = board.currentRound; if (round == null) return const SizedBox.shrink();
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final myPlayer = board.players.where((p) => p.userId == myId).firstOrNull;
    final myIndex = myPlayer?.playerIndex ?? -1;
    final isEliminated = myPlayer != null && !myPlayer.isAlive;
    return Column(children: [
      // Phase banner + countdown
      _PhaseBanner(round: round, aliveCount: board.aliveCount),
      // Arena
      Expanded(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(KinrelSpacing.md),
        child: Column(children: [
          if (round.phase == ColorTrapPhase.arenaShown || round.phase == ColorTrapPhase.colorAnnounced || round.phase == ColorTrapPhase.countdown)
            _ArenaGrid(round: round, players: board.players, myPlayerIndex: myIndex, isEliminated: isEliminated, onTileTap: onMove, board: board),
          if (round.phase == ColorTrapPhase.elimination || round.phase == ColorTrapPhase.roundEnd)
            _EliminationView(round: round, players: board.players, onAdvance: onAdvance, board: board),
        ])))),
      if (state.amSpectator || isEliminated) ReactionsBar(gameTable: 'color_trap_games', gameId: game.id, familyId: familyId),
    ]);
  }
}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({required this.round, required this.aliveCount});
  final ColorTrapRound round; final int aliveCount;
  @override Widget build(BuildContext context) {
    final (label, color) = switch (round.phase) {
      ColorTrapPhase.arenaShown => ('Arena ready — move to position!', KinrelColors.textSilver),
      ColorTrapPhase.colorAnnounced => ('Target: ${round.targetColor.name.toUpperCase()}', Color(round.targetColor.argb)),
      ColorTrapPhase.countdown => ('${round.countdownRemaining}', KinrelColors.error),
      ColorTrapPhase.elimination => ('Eliminating!', KinrelColors.error),
      ColorTrapPhase.roundEnd => ('Round over', KinrelColors.brightGold),
    };
    return Container(margin: const EdgeInsets.fromLTRB(KinrelSpacing.md, KinrelSpacing.sm, KinrelSpacing.md, KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 6)])),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: round.phase == ColorTrapPhase.countdown ? 28 : 14, fontWeight: FontWeight.w800, color: KinrelColors.textWhite))),
        Text('$aliveCount alive', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, color: KinrelColors.textDim)),
      ]));
  }
}

class _ArenaGrid extends StatelessWidget {
  const _ArenaGrid({required this.round, required this.players, required this.myPlayerIndex, required this.isEliminated, required this.onTileTap, required this.board});
  final ColorTrapRound round; final List<ColorTrapPlayer> players; final int myPlayerIndex;
  final bool isEliminated; final void Function(int row, int col) onTileTap; final ColorTrapGameState board;

  @override Widget build(BuildContext context) {
    final size = round.arenaSize;
    // Show target color prominently during colorAnnounced + countdown
    final showTargetColor = round.phase == ColorTrapPhase.colorAnnounced || round.phase == ColorTrapPhase.countdown;
    final targetColor = Color(round.targetColor.argb);
    return Center(child: AspectRatio(aspectRatio: 1.0,
      child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: showTargetColor ? targetColor.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.06), width: showTargetColor ? 2 : 1)),
        child: Column(children: [
          for (var r = 0; r < size; r++)
            Expanded(child: Row(children: [
              for (var c = 0; c < size; c++)
                Expanded(child: _Tile(
                  tile: round.tiles.where((t) => t.row == r && t.col == c).firstOrNull,
                  isTarget: showTargetColor && round.tiles.where((t) => t.row == r && t.col == c).firstOrNull?.color == round.targetColor,
                  playersHere: players.where((p) => p.isAlive && p.row == r && p.col == c).toList(),
                  myPlayerIndex: myPlayerIndex,
                  canTap: !isEliminated && (round.phase == ColorTrapPhase.arenaShown || round.phase == ColorTrapPhase.colorAnnounced || round.phase == ColorTrapPhase.countdown),
                  onTap: () => onTileTap(r, c),
                )),
            ])),
        ]))));
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.isTarget, required this.playersHere, required this.myPlayerIndex, required this.canTap, required this.onTap});
  final ColorTrapTile? tile; final bool isTarget; final List<ColorTrapPlayer> playersHere; final int myPlayerIndex; final bool canTap; final VoidCallback onTap;
  @override Widget build(BuildContext context) {
    final tileColor = tile != null ? Color(tile!.color.argb) : KinrelColors.darkElevated;
    return GestureDetector(onTap: canTap ? onTap : null,
      child: Container(margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(color: tileColor.withValues(alpha: isTarget ? 1.0 : 0.85), borderRadius: BorderRadius.circular(3), border: isTarget ? Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1) : null),
        child: Stack(children: [
          if (playersHere.isNotEmpty)
            Center(child: Wrap(spacing: 2, runSpacing: 2, children: [
              for (final p in playersHere)
                Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: p.playerIndex == myPlayerIndex ? Colors.white : Colors.white.withValues(alpha: 0.7), border: Border.all(color: Colors.black26, width: 1))),
            ])),
        ])));
  }
}

class _EliminationView extends StatelessWidget {
  const _EliminationView({required this.round, required this.players, required this.onAdvance, required this.board});
  final ColorTrapRound round; final List<ColorTrapPlayer> players; final VoidCallback onAdvance; final ColorTrapGameState board;
  @override Widget build(BuildContext context) {
    final eliminated = players.where((p) => p.eliminatedRound == round.roundNumber).toList();
    final alive = board.alivePlayers;
    return Column(children: [
      // Show the arena with only target tiles visible
      Center(child: AspectRatio(aspectRatio: 1.0,
        child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            for (var r = 0; r < round.arenaSize; r++)
              Expanded(child: Row(children: [
                for (var c = 0; c < round.arenaSize; c++)
                  Expanded(child: Container(margin: const EdgeInsets.all(1), decoration: BoxDecoration(
                    color: round.tiles.where((t) => t.row == r && t.col == c).firstOrNull?.isVisible == true
                      ? Color(round.targetColor.argb).withValues(alpha: 0.6)
                      : KinrelColors.darkElevated.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3)))),
              ])),
          ])))),
      const SizedBox(height: 16),
      if (eliminated.isNotEmpty) ...[
        Text('Eliminated this round:', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
        for (final p in eliminated) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${p.userName} fell!', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.error))),
      ],
      const SizedBox(height: 12),
      Text('${alive.length} players remaining', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.success)),
      const SizedBox(height: 16),
      if (board.aliveCount > 1)
        DKButton(label: 'Next Round →', variant: DKButtonVariant.primary, fullWidth: true, onPressed: onAdvance),
    ]);
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.game, required this.familyId, required this.players, required this.isHost, required this.onRematch, required this.onExit});
  final ColorTrapGame game; final String familyId; final List<ColorTrapPlayerWire> players; final bool isHost;
  final Future<String?> Function() onRematch; final VoidCallback onExit;
  @override Widget build(BuildContext context) {
    final board = game.boardState; final winnerIds = game.winnerUserIds;
    final winnerName = winnerIds.isNotEmpty ? players.where((p) => winnerIds.contains(p.userId)).map((p) => p.userName).join(', ') : '';
    return SingleChildScrollView(padding: const EdgeInsets.all(KinrelSpacing.lg),
      child: Column(children: [
        if (winnerIds.isNotEmpty) const GameConfetti(),
        Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2A1A0E), Color(0xFF1C1410)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(20), border: Border.all(color: KinrelColors.brightGold.withValues(alpha: 0.4))),
          child: Column(children: [
            const KinrelIcon(KinrelIconData.trophy, size: 40, color: KinrelColors.brightGold),
            const SizedBox(height: 8),
            Text(winnerName.isNotEmpty ? '$winnerName survives!' : 'Match Complete', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 20, fontWeight: FontWeight.w800, color: KinrelColors.brightGold)),
            const SizedBox(height: 4),
            Text('Last player standing!', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textSilver)),
          ])),
        const SizedBox(height: 18),
        if (board != null) ...[
          GamingSectionHeader(title: 'Survival Stats', icon: Icons.timer_outlined),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              _StatRow(label: 'Rounds Survived', value: '${board.currentRoundNumber}'),
              _StatRow(label: 'Players', value: '${board.playerCount}'),
              _StatRow(label: 'Difficulty', value: board.difficulty.label),
            ])),
          const SizedBox(height: 18),
        ],
        MatchEcosystemSummary(gameTable: 'color_trap_games', gameId: game.id, familyId: familyId),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: DKButton(label: 'Exit', variant: DKButtonVariant.secondary, fullWidth: true, onPressed: onExit)),
          // Host-gated shared rematch — provider rematch() carries the roster
          // and writes invites itself (insertInvites: false).
          if (isHost) ...[
            const SizedBox(width: 10),
            Expanded(child: RematchButton(familyId: familyId, gameType: GameType.colorTrap, previousGameId: game.id, participantUserIds: players.where((p) => p.isActive).map((p) => p.userId).toList(), maxPlayers: game.maxPlayers, insertInvites: false, onCreateNewGame: onRematch)),
          ],
        ]),
      ]));
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label; final String value;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(label, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim))), Text(value, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.textWhite))]));
}
