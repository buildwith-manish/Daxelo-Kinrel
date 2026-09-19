// lib/features/games/impostor/impostor_game_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
import 'impostor_engine.dart';
import 'impostor_models.dart';
import 'impostor_provider.dart';

/// Resolve a board index (impostorIndex, clue/vote playerIndex, scores
/// key) to a player. Board indices refer to the game's playerOrder set
/// at start — NOT the local players list (ordered by joinedAt), which
/// shifts when a pre-start player leaves. Bounds + not-found guards
/// return a placeholder so a desynced roster can't RangeError the UI.
ImpostorPlayer _playerAtBoardIndex(List<ImpostorPlayer> players, List<String> playerOrder, int index) {
  final label = 'Player ${index + 1}';
  if (index < 0 || index >= playerOrder.length) return ImpostorPlayer(id: '', gameId: '', userId: '', userName: label, joinedAt: DateTime.now());
  final id = playerOrder[index];
  return players.firstWhere((p) => p.userId == id, orElse: () => ImpostorPlayer(id: '', gameId: '', userId: id, userName: label, joinedAt: DateTime.now()));
}

class ImpostorGameScreen extends ConsumerStatefulWidget {
  const ImpostorGameScreen({super.key, required this.familyId, required this.gameId});
  final String familyId; final String gameId;
  @override ConsumerState<ImpostorGameScreen> createState() => _ImpostorGameScreenState();
}

class _ImpostorGameScreenState extends ConsumerState<ImpostorGameScreen> {
  Timer? _clockTimer;
  @override void initState() { super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(impostorProvider(widget.familyId).notifier).loadGame(widget.gameId));
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) { if (mounted) setState(() {}); });
  }
  @override void dispose() { _clockTimer?.cancel(); super.dispose(); }

  Future<void> _confirmLeave() async {
    final state = ref.read(impostorProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(context, isHost: state.game?.hostUserId == myId && state.game?.isWaiting == true, gameName: 'Who\'s the Impostor?');
    if (shouldLeave == true) {
      await ref.read(impostorProvider(widget.familyId).notifier).leaveGame();
      if (mounted) { if (context.canPop()) context.pop(); else context.go('/family/${widget.familyId}'); }
    }
  }

  @override Widget build(BuildContext context) {
    final state = ref.watch(impostorProvider(widget.familyId));
    final game = state.game;
    if (state.isLoading && game == null) return DKScaffold(backgroundColor: KinrelColors.darkSurface, appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave), title: const Text('Who\'s the Impostor?'), backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite), body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)));
    if (game == null) return DKScaffold(backgroundColor: KinrelColors.darkSurface, appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/family/${widget.familyId}')), title: const Text('Who\'s the Impostor?'), backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite), body: Center(child: GamingEmptyCard(emoji: '🕵️', title: 'Game not found', message: 'This game may have ended or been cancelled.')));
    return DKScaffold(backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
        title: Text(game.roomName?.isNotEmpty == true ? game.roomName! : 'Who\'s the Impostor?', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
        actions: [if (game.isInProgress) Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: _RoundIndicator(game: game))), if (game.hostUserId == ref.read(supabaseProvider)?.auth.currentUser?.id && game.isInProgress) IconButton(tooltip: 'Leave game', icon: const Icon(Icons.logout, size: 20), onPressed: _confirmLeave)]),
      body: game.isCompleted ? _ResultsView(game: game, familyId: widget.familyId, players: state.players, onRematch: () => ref.read(impostorProvider(widget.familyId).notifier).rematch(), onExit: () { if (context.canPop()) context.pop(); else context.go('/family/${widget.familyId}'); })
        : _GameView(state: state, familyId: widget.familyId, onSubmitClue: (clue) => ref.read(impostorProvider(widget.familyId).notifier).submitClue(clue), onSubmitVote: (idx) => ref.read(impostorProvider(widget.familyId).notifier).submitVote(idx), onAdvance: () => ref.read(impostorProvider(widget.familyId).notifier).advancePhase()));
  }
}

class _RoundIndicator extends StatelessWidget {
  const _RoundIndicator({required this.game}); final ImpostorGame game;
  @override Widget build(BuildContext context) {
    final board = game.boardState;
    final current = board?.currentRoundNumber ?? 1;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: KinrelColors.purple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Text('R$current/${game.totalRounds}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: KinrelColors.purple)));
  }
}

class _GameView extends ConsumerWidget {
  const _GameView({required this.state, required this.familyId, required this.onSubmitClue, required this.onSubmitVote, required this.onAdvance});
  final ImpostorState state; final String familyId;
  final void Function(String clue) onSubmitClue; final void Function(int targetIndex) onSubmitVote; final VoidCallback onAdvance;

  @override Widget build(BuildContext context, WidgetRef ref) {
    final game = state.game!; final board = game.boardState;
    if (board == null) return const Center(child: CircularProgressIndicator(color: KinrelColors.orange));
    final round = board.currentRound; if (round == null) return const SizedBox.shrink();
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    // Board indices (impostorIndex, clue/vote playerIndex, scores keys)
    // refer to the game's playerOrder frozen at start — not the local
    // players list, which is ordered by joinedAt and shifts when a
    // pre-start player leaves.
    final myPlayerIndex = game.playerOrder.indexOf(myId ?? '');
    final isMyTurn = round.phase == ImpostorPhase.clue && myPlayerIndex == round.currentCluePlayerIndex;
    return Column(children: [
      _PhaseBanner(round: round, playerCount: board.playerCount, players: state.players),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(KinrelSpacing.md), child: Column(children: [
        if (round.phase == ImpostorPhase.roleReveal) _RoleRevealCard(round: round, myPlayerIndex: myPlayerIndex, onReady: onAdvance),
        if (round.phase == ImpostorPhase.clue) _CluePhaseView(round: round, players: state.players, myPlayerIndex: myPlayerIndex, isMyTurn: isMyTurn, onSubmitClue: onSubmitClue, game: game),
        if (round.phase == ImpostorPhase.voting) _VotingPhaseView(round: round, players: state.players, myPlayerIndex: myPlayerIndex, onSubmitVote: onSubmitVote, game: game),
        if (round.phase == ImpostorPhase.result) _RoundResultView(round: round, players: state.players, playerOrder: game.playerOrder, scores: board.scores, onNext: onAdvance, isLastRound: board.currentRoundNumber >= board.totalRounds),
      ]))),
      if (state.amSpectator) ReactionsBar(gameTable: 'impostor_games', gameId: game.id, familyId: familyId),
    ]);
  }
}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({required this.round, required this.playerCount, required this.players});
  final ImpostorRound round; final int playerCount; final List<ImpostorPlayer> players;
  @override Widget build(BuildContext context) {
    final phaseLabel = switch(round.phase) {
      ImpostorPhase.roleReveal => '🎭 Roles Assigned — Tap to Reveal',
      ImpostorPhase.clue => '💬 Clue Phase',
      ImpostorPhase.voting => '🗳️ Voting Phase',
      ImpostorPhase.result => '📊 Round Result',
      ImpostorPhase.finished => '🏁 Match Over',
    };
    final color = switch(round.phase) {
      ImpostorPhase.roleReveal => KinrelColors.purple,
      ImpostorPhase.clue => KinrelColors.orange,
      ImpostorPhase.voting => KinrelColors.error,
      ImpostorPhase.result => KinrelColors.brightGold,
      ImpostorPhase.finished => KinrelColors.textDim,
    };
    return Container(margin: const EdgeInsets.fromLTRB(KinrelSpacing.md, KinrelSpacing.sm, KinrelSpacing.md, KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 6)])),
        const SizedBox(width: 10),
        Expanded(child: Text(phaseLabel, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w700, color: KinrelColors.textWhite))),
      ]));
  }
}

class _RoleRevealCard extends StatefulWidget {
  const _RoleRevealCard({required this.round, required this.myPlayerIndex, required this.onReady});
  final ImpostorRound round; final int myPlayerIndex; final VoidCallback onReady;
  @override State<_RoleRevealCard> createState() => _RoleRevealCardState();
}

class _RoleRevealCardState extends State<_RoleRevealCard> {
  bool _revealed = false;
  @override Widget build(BuildContext context) {
    if (widget.myPlayerIndex < 0) return const SizedBox.shrink();
    final isImpostor = widget.myPlayerIndex == widget.round.impostorIndex;
    if (!_revealed) return GestureDetector(onTap: () => setState(() => _revealed = true),
      child: Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: KinrelColors.purple.withValues(alpha: 0.3))),
        child: Column(children: [
          const Text('🎭', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('Tap to reveal your role', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
          const SizedBox(height: 4),
          Text('Make sure no one else is looking!', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
        ])));
    return Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: isImpostor ? KinrelColors.error.withValues(alpha: 0.4) : KinrelColors.success.withValues(alpha: 0.4))),
      child: Column(children: [
        Text(isImpostor ? '🕵️' : '🛡️', style: const TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text(isImpostor ? 'You are the IMPOSTOR!' : 'You are CREW', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w800, color: isImpostor ? KinrelColors.error : KinrelColors.success)),
        const SizedBox(height: 8),
        if (isImpostor) Text('You don\'t know the secret word. Blend in with a convincing clue!', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textSilver))
        else Text('Secret Word: ${widget.round.word}', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 22, fontWeight: FontWeight.w800, color: KinrelColors.brightGold)),
        const SizedBox(height: 16),
        DKButton(label: 'Got it!', variant: DKButtonVariant.primary, fullWidth: true, onPressed: widget.onReady),
      ]));
  }
}

class _CluePhaseView extends ConsumerStatefulWidget {
  const _CluePhaseView({required this.round, required this.players, required this.myPlayerIndex, required this.isMyTurn, required this.onSubmitClue, required this.game});
  final ImpostorRound round; final List<ImpostorPlayer> players; final int myPlayerIndex;
  final bool isMyTurn; final void Function(String clue) onSubmitClue; final ImpostorGame game;
  @override ConsumerState<_CluePhaseView> createState() => _CluePhaseViewState();
}

class _CluePhaseViewState extends ConsumerState<_CluePhaseView> {
  final _controller = TextEditingController();
  bool _submitted = false;
  @override void dispose() { _controller.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final round = widget.round; final myClue = round.clues.any((c) => c.playerIndex == widget.myPlayerIndex);
    if (myClue) _submitted = true;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Submitted clues
      if (round.clues.isNotEmpty) ...[
        GamingSectionHeader(title: 'Clues So Far', icon: Icons.chat_bubble_outline),
        for (final clue in round.clues) Padding(padding: const EdgeInsets.only(bottom: 6),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: KinrelColors.orange.withValues(alpha: 0.2)),
                child: Center(child: Text(_playerAtBoardIndex(widget.players, widget.game.playerOrder, clue.playerIndex).userName.isNotEmpty ? _playerAtBoardIndex(widget.players, widget.game.playerOrder, clue.playerIndex).userName[0].toUpperCase() : '?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KinrelColors.orange)))),
              const SizedBox(width: 8),
              Expanded(child: Text(clue.text, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
            ]))),
        const SizedBox(height: 12),
      ],
      // My turn to clue
      if (widget.isMyTurn && !_submitted) ...[
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: KinrelColors.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3))),
          child: Column(children: [
            Text('Your turn — give a one-word clue!', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.orange)),
            const SizedBox(height: 10),
            TextField(controller: _controller, maxLength: 50, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 16, color: KinrelColors.textWhite),
              decoration: InputDecoration(counterText: '', hintText: 'One word...', filled: true, fillColor: KinrelColors.darkCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: KinrelColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: KinrelColors.orange, width: 1.4)))),
            const SizedBox(height: 10),
            DKButton(label: 'Submit Clue', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () { if (_controller.text.trim().isNotEmpty) { widget.onSubmitClue(_controller.text); setState(() => _submitted = true); } }),
          ])),
      ] else if (!_submitted) ...[
        Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Waiting for ${_playerAtBoardIndex(widget.players, widget.game.playerOrder, round.currentCluePlayerIndex).userName}...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)))),
      ] else ...[
        Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Clue submitted! Waiting for others...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)))),
      ],
    ]);
  }
}

class _VotingPhaseView extends ConsumerStatefulWidget {
  const _VotingPhaseView({required this.round, required this.players, required this.myPlayerIndex, required this.onSubmitVote, required this.game});
  final ImpostorRound round; final List<ImpostorPlayer> players; final int myPlayerIndex;
  final void Function(int targetIndex) onSubmitVote; final ImpostorGame game;
  @override ConsumerState<_VotingPhaseView> createState() => _VotingPhaseViewState();
}

class _VotingPhaseViewState extends ConsumerState<_VotingPhaseView> {
  int? _selectedTarget; bool _voted = false;
  @override Widget build(BuildContext context) {
    final round = widget.round;
    final myVote = round.votes.any((v) => v.voterIndex == widget.myPlayerIndex);
    if (myVote) _voted = true;
    // Board indices refer to the game's playerOrder (frozen at start),
    // not the local players list — resolve via playerOrder and skip
    // players who have left the room.
    final candidates = <int, ImpostorPlayer>{
      for (var i = 0; i < widget.game.playerOrder.length; i++)
        if (i != widget.myPlayerIndex) i: _playerAtBoardIndex(widget.players, widget.game.playerOrder, i),
    };
    candidates.removeWhere((_, p) => !p.isActive);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GamingSectionHeader(title: _voted ? 'Vote cast — waiting for others' : 'Who is the Impostor?', icon: Icons.how_to_vote_outlined),
      if (!_voted) ...[
        for (final entry in candidates.entries)
          Padding(padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(onTap: () => setState(() => _selectedTarget = entry.key),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: _selectedTarget == entry.key ? KinrelColors.error.withValues(alpha: 0.12) : KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: _selectedTarget == entry.key ? KinrelColors.error.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05))),
                child: Row(children: [
                  Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, color: KinrelColors.orange.withValues(alpha: 0.2)),
                    child: Center(child: Text(entry.value.userName.isNotEmpty ? entry.value.userName[0].toUpperCase() : '?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: KinrelColors.orange)))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(entry.value.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
                  if (_selectedTarget == entry.key) const Icon(Icons.check_circle, color: KinrelColors.error, size: 20),
                ])))),
        const SizedBox(height: 12),
        DKButton(label: 'Cast Vote', variant: DKButtonVariant.primary, fullWidth: true, onPressed: _selectedTarget != null ? () { widget.onSubmitVote(_selectedTarget!); setState(() => _voted = true); } : null),
      ] else ...[
        Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          const Text('🗳️', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text('Vote submitted! Waiting for ${widget.game.playerOrder.length - round.votes.length} more...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)),
        ]))),
      ],
    ]);
  }
}

class _RoundResultView extends StatelessWidget {
  const _RoundResultView({required this.round, required this.players, required this.playerOrder, required this.scores, required this.onNext, required this.isLastRound});
  final ImpostorRound round; final List<ImpostorPlayer> players; final List<String> playerOrder; final Map<int, int> scores; final VoidCallback onNext; final bool isLastRound;
  @override Widget build(BuildContext context) {
    final winnerLabel = switch(round.winner) {
      ImpostorRoundWinner.crew => '🛡️ Crew Wins! The Impostor was caught!',
      ImpostorRoundWinner.impostor => '🕵️ Impostor Wins! They escaped detection!',
      ImpostorRoundWinner.tie => '🤝 Tie! The Impostor escaped!',
      null => 'Result pending...',
    };
    final winnerColor = switch(round.winner) {
      ImpostorRoundWinner.crew => KinrelColors.success,
      ImpostorRoundWinner.impostor => KinrelColors.error,
      _ => KinrelColors.amber,
    };
    // Vote tally
    final voteCounts = <int, int>{};
    for (final vote in round.votes) { voteCounts[vote.targetIndex] = (voteCounts[vote.targetIndex] ?? 0) + 1; }
    return Column(children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: winnerColor.withValues(alpha: 0.4))),
        child: Column(children: [
          Text(winnerLabel, textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w800, color: winnerColor)),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: KinrelColors.brightGold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Text('Secret Word: ${round.word}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w800, color: KinrelColors.brightGold))),
          const SizedBox(height: 8),
          Text('Impostor was: ${_playerAtBoardIndex(players, playerOrder, round.impostorIndex).userName}', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textSilver)),
        ])),
      const SizedBox(height: 16),
      // Vote distribution
      GamingSectionHeader(title: 'Vote Distribution', icon: Icons.bar_chart_outlined),
      for (final entry in voteCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Expanded(child: Text(_playerAtBoardIndex(players, playerOrder, entry.key).userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textSilver))),
            Text('${entry.value} ${entry.value == 1 ? "vote" : "votes"}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: entry.key == round.impostorIndex ? KinrelColors.error : KinrelColors.textDim)),
          ])),
      const SizedBox(height: 16),
      // Scores
      GamingSectionHeader(title: 'Scores', icon: Icons.leaderboard_outlined),
      for (final entry in scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            Expanded(child: Text(_playerAtBoardIndex(players, playerOrder, entry.key).userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textSilver))),
            Text('${entry.value} pts', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: KinrelColors.orange)),
          ])),
      const SizedBox(height: 20),
      DKButton(label: isLastRound ? 'See Final Results' : 'Next Round →', variant: DKButtonVariant.primary, fullWidth: true, onPressed: onNext),
    ]);
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.game, required this.familyId, required this.players, required this.onRematch, required this.onExit});
  final ImpostorGame game; final String familyId; final List<ImpostorPlayer> players;
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
            Text(winnerName.isNotEmpty ? '$winnerName wins!' : 'Match Complete', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 20, fontWeight: FontWeight.w800, color: KinrelColors.brightGold)),
          ])),
        const SizedBox(height: 18),
        if (board != null) ...[
          GamingSectionHeader(title: 'Final Scores', icon: Icons.leaderboard_outlined),
          for (final entry in board.scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            Padding(padding: const EdgeInsets.only(bottom: 6),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Text(entry.value == board.scores.values.reduce(math.max) ? '🥇' : '🏅', style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_playerAtBoardIndex(players, game.playerOrder, entry.key).userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.textWhite))),
                  Text('${entry.value} pts', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 14, fontWeight: FontWeight.w800, color: KinrelColors.orange)),
                ]))),
          const SizedBox(height: 18),
        ],
        MatchEcosystemSummary(gameTable: 'impostor_games', gameId: game.id, familyId: familyId),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: DKButton(label: 'Exit', variant: DKButtonVariant.secondary, fullWidth: true, onPressed: onExit)),
          const SizedBox(width: 10),
          Expanded(child: DKButton(label: 'Rematch', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () async { final newId = await onRematch(); if (newId != null && context.mounted) context.pushReplacement('/family/$familyId/impostor/game/$newId'); })),
        ]),
      ]));
  }
}
