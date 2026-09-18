// lib/features/games/freeze_auction/freeze_auction_game_screen.dart
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
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';
import '../../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/reactions_bar.dart';
import 'freeze_auction_engine.dart';
import 'freeze_auction_models.dart';
import 'freeze_auction_provider.dart';

class FreezeAuctionGameScreen extends ConsumerStatefulWidget {
  const FreezeAuctionGameScreen({super.key, required this.familyId, required this.gameId});
  final String familyId; final String gameId;
  @override ConsumerState<FreezeAuctionGameScreen> createState() => _FreezeAuctionGameScreenState();
}

class _FreezeAuctionGameScreenState extends ConsumerState<FreezeAuctionGameScreen> {
  Timer? _clockTimer; final _bidController = TextEditingController(); int? _selectedBid; bool _submitted = false;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(freezeAuctionProvider(widget.familyId).notifier).loadGame(widget.gameId)); _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) { if (mounted) setState(() {}); }); }
  @override void dispose() { _clockTimer?.cancel(); _bidController.dispose(); super.dispose(); }

  Future<void> _confirmLeave() async {
    final state = ref.read(freezeAuctionProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(context, isHost: state.game?.hostUserId == myId && state.game?.isWaiting == true, gameName: 'Freeze Auction');
    if (shouldLeave == true) { await ref.read(freezeAuctionProvider(widget.familyId).notifier).leaveGame(); if (mounted) { if (context.canPop()) context.pop(); else context.go('/family/${widget.familyId}'); } }
  }

  @override Widget build(BuildContext context) {
    final state = ref.watch(freezeAuctionProvider(widget.familyId));
    final game = state.game;
    if (state.isLoading && game == null) return DKScaffold(backgroundColor: KinrelColors.darkSurface, appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave), title: const Text('Freeze Auction'), backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite), body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)));
    if (game == null) return DKScaffold(backgroundColor: KinrelColors.darkSurface, appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/family/${widget.familyId}')), title: const Text('Freeze Auction'), backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite), body: Center(child: GamingEmptyCard(emoji: '📦', title: 'Game not found', message: 'This game may have ended.')));
    return DKScaffold(backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
        title: Text(game.roomName?.isNotEmpty == true ? game.roomName! : 'Freeze Auction', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
        actions: [if (game.isInProgress) Padding(padding: const EdgeInsets.only(right: 14), child: Center(child: _RoundInfo(game: game))), if (game.hostUserId == ref.read(supabaseProvider)?.auth.currentUser?.id && game.isInProgress) IconButton(tooltip: 'Leave', icon: const Icon(Icons.logout, size: 20), onPressed: _confirmLeave)]),
      body: game.isCompleted ? _ResultsView(game: game, familyId: widget.familyId, players: state.players, onRematch: () => ref.read(freezeAuctionProvider(widget.familyId).notifier).rematch(), onExit: () { if (context.canPop()) context.pop(); else context.go('/family/${widget.familyId}'); })
        : _GameView(state: state, familyId: widget.familyId, bidController: _bidController, selectedBid: _selectedBid, submitted: _submitted, onBidChanged: (v) => setState(() => _selectedBid = v), onSubmitBid: (amount) { ref.read(freezeAuctionProvider(widget.familyId).notifier).submitBid(amount); setState(() => _submitted = true); }, onAdvance: () => ref.read(freezeAuctionProvider(widget.familyId).notifier).advancePhase(), onResetSubmit: () => setState(() { _submitted = false; _selectedBid = null; })));
  }
}

class _RoundInfo extends StatelessWidget {
  const _RoundInfo({required this.game}); final FreezeAuctionGame game;
  @override Widget build(BuildContext context) {
    final board = game.boardState; final round = board?.currentRoundNumber ?? 1;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: KinrelColors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Text('R$round/${game.totalRounds}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.amber)));
  }
}

class _GameView extends ConsumerWidget {
  const _GameView({required this.state, required this.familyId, required this.bidController, required this.selectedBid, required this.submitted, required this.onBidChanged, required this.onSubmitBid, required this.onAdvance, required this.onResetSubmit});
  final FreezeAuctionState_ state; final String familyId; final TextEditingController bidController;
  final int? selectedBid; final bool submitted; final void Function(int) onBidChanged; final void Function(int) onSubmitBid; final VoidCallback onAdvance; final VoidCallback onResetSubmit;

  @override Widget build(BuildContext context, WidgetRef ref) {
    final game = state.game!; final board = game.boardState;
    if (board == null) return const Center(child: CircularProgressIndicator(color: KinrelColors.orange));
    final round = board.currentRound; if (round == null) return const SizedBox.shrink();
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final myPlayer = board.players.where((p) => p.userId == myId).firstOrNull;
    final myCoins = myPlayer?.coins ?? 0;
    final myBid = round.bids.where((b) => b.playerIndex == myPlayer?.playerIndex).firstOrNull;
    final hasBid = myBid != null || submitted;

    return Column(children: [
      _PhaseBanner(round: round, board: board),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(KinrelSpacing.md), child: Column(children: [
        if (round.phase == AuctionPhase.bidding) ...[
          _MysteryCrate(round: round),
          const SizedBox(height: 16),
          if (!hasBid) _BiddingForm(coins: myCoins, selectedBid: selectedBid, onBidChanged: onBidChanged, onSubmit: onSubmitBid)
          else _BidSubmittedView(bidsCount: round.bids.length, playerCount: board.playerCount),
          const SizedBox(height: 16),
          _Leaderboard(players: board.players),
        ]
        else if (round.phase == AuctionPhase.revealing || round.phase == AuctionPhase.roundResult) ...[
          _RevealView(round: round, players: board.players),
          const SizedBox(height: 16),
          _Leaderboard(players: board.players),
          if (round.phase == AuctionPhase.roundResult) ...[
            const SizedBox(height: 16),
            DKButton(label: board.currentRoundNumber >= board.totalRounds || board.players.where((p) => p.isAlive).length <= 1 ? 'See Final Results' : 'Next Round →', variant: DKButtonVariant.primary, fullWidth: true, onPressed: onAdvance),
          ],
        ],
      ]))),
      if (state.amSpectator) ReactionsBar(gameTable: 'freeze_auction_games', gameId: game.id, familyId: familyId),
    ]);
  }
}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({required this.round, required this.board});
  final AuctionRound round; final FreezeAuctionState board;
  @override Widget build(BuildContext context) {
    final (label, color) = switch (round.phase) {
      AuctionPhase.bidding => ('Bidding Open — ${round.bids.length}/${board.playerCount} bids in', KinrelColors.amber),
      AuctionPhase.revealing => ('Revealing...', KinrelColors.orange),
      AuctionPhase.roundResult => ('Round Result', KinrelColors.brightGold),
      AuctionPhase.finished => ('Match Over', KinrelColors.textDim),
    };
    return Container(margin: const EdgeInsets.fromLTRB(KinrelSpacing.md, KinrelSpacing.sm, KinrelSpacing.md, KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 6)])),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w700, color: KinrelColors.textWhite))),
        if (round.isFinalRound) Text('FINAL', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 10, fontWeight: FontWeight.w800, color: KinrelColors.brightGold)),
      ]));
  }
}

class _MysteryCrate extends StatelessWidget {
  const _MysteryCrate({required this.round});
  final AuctionRound round;
  @override Widget build(BuildContext context) {
    final rarityColor = Color(round.item.rarity.argb);
    return Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: rarityColor.withValues(alpha: 0.4))),
      child: Column(children: [
        Container(width: 80, height: 80, decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: rarityColor.withValues(alpha: 0.15), border: Border.all(color: rarityColor.withValues(alpha: 0.5), width: 2)),
          child: Center(child: KinrelIcon(KinrelIconData.sparkle, size: 36, color: rarityColor))),
        const SizedBox(height: 14),
        Text(round.item.rarity.label.toUpperCase(), style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: rarityColor)),
        const SizedBox(height: 4),
        Text('Mystery Crate', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
        const SizedBox(height: 4),
        Text('What\'s inside?', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
      ]));
  }
}

class _BiddingForm extends StatelessWidget {
  const _BiddingForm({required this.coins, required this.selectedBid, required this.onBidChanged, required this.onSubmit});
  final int coins; final int? selectedBid; final void Function(int) onBidChanged; final void Function(int) onSubmit;
  @override Widget build(BuildContext context) {
    final quickBids = [0, 10, 25, 50, 75];
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: KinrelColors.amber.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Text('Your Coins: ', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)), Text('$coins', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 16, fontWeight: FontWeight.w800, color: KinrelColors.amber))]),
        const SizedBox(height: 12),
        Text('Quick Bid:', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final b in quickBids) _BidChip(amount: b, selected: selectedBid == b, enabled: b <= coins, onTap: () => onBidChanged(b))]),
        const SizedBox(height: 12),
        if (selectedBid != null) DKButton(label: 'Bid $selectedBid coins', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () => onSubmit(selectedBid!)),
      ]));
  }
}

class _BidChip extends StatelessWidget {
  const _BidChip({required this.amount, required this.selected, required this.enabled, required this.onTap});
  final int amount; final bool selected; final bool enabled; final VoidCallback onTap;
  @override Widget build(BuildContext context) {
    return GestureDetector(onTap: enabled ? onTap : null,
      child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: selected ? KinrelColors.amber.withValues(alpha: 0.2) : KinrelColors.darkElevated, borderRadius: BorderRadius.circular(10), border: Border.all(color: selected ? KinrelColors.amber : Colors.transparent)),
        child: Text('$amount', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 13, fontWeight: FontWeight.w700, color: selected ? KinrelColors.amber : (enabled ? KinrelColors.textSilver : KinrelColors.textDim.withValues(alpha: 0.4))))));
  }
}

class _BidSubmittedView extends StatelessWidget {
  const _BidSubmittedView({required this.bidsCount, required this.playerCount});
  final int bidsCount; final int playerCount;
  @override Widget build(BuildContext context) {
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: KinrelColors.success.withValues(alpha: 0.25))),
      child: Column(children: [
        const Text('✓', style: TextStyle(fontSize: 32, color: KinrelColors.success)),
        const SizedBox(height: 8),
        Text('Bid submitted!', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 15, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
        const SizedBox(height: 4),
        Text('Waiting for other bids... ($bidsCount/$playerCount)', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
      ]));
  }
}

class _RevealView extends StatelessWidget {
  const _RevealView({required this.round, required this.players});
  final AuctionRound round; final List<AuctionPlayer> players;
  @override Widget build(BuildContext context) {
    final rarityColor = Color(round.item.rarity.argb);
    final winnerIdx = round.winnerPlayerIndex;
    final winner = winnerIdx != null && winnerIdx < players.length ? players[winnerIdx] : null;
    return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: rarityColor.withValues(alpha: 0.4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Auction Result', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w800, color: KinrelColors.textWhite)),
        const SizedBox(height: 12),
        // Bids
        for (final bid in round.bids)
          Padding(padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Expanded(child: Text('${players[bid.playerIndex].userName} bid ${bid.amount}', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: bid.playerIndex == winnerIdx ? KinrelColors.brightGold : KinrelColors.textSilver))),
              if (bid.playerIndex == winnerIdx) Text('WINNER', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 10, fontWeight: FontWeight.w800, color: KinrelColors.brightGold)),
            ])),
        const SizedBox(height: 16),
        // Reveal
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: rarityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: rarityColor.withValues(alpha: 0.3))),
          child: Column(children: [
            Text(round.item.name, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w800, color: rarityColor)),
            const SizedBox(height: 4),
            Text(round.item.description, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite)),
            if (round.effectDescription != null) ...[const SizedBox(height: 8), Text(round.effectDescription!, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.brightGold))],
          ])),
        if (winner != null) ...[const SizedBox(height: 12), Text('Winner: ${winner.userName} (${winner.coins} coins)', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textSilver))],
      ]));
  }
}

class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.players});
  final List<AuctionPlayer> players;
  @override Widget build(BuildContext context) {
    final sorted = List<AuctionPlayer>.from(players)..sort((a, b) => b.coins.compareTo(a.coins));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GamingSectionHeader(title: 'Standings', icon: Icons.leaderboard_outlined),
      for (var i = 0; i < sorted.length; i++)
        Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              SizedBox(width: 24, child: Text('#${i + 1}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: i == 0 ? KinrelColors.brightGold : KinrelColors.textDim))),
              const SizedBox(width: 8),
              Expanded(child: Text(sorted[i].userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: sorted[i].isAlive ? KinrelColors.textSilver : KinrelColors.textDim.withValues(alpha: 0.4)))),
              if (sorted[i].hasShield) Padding(padding: const EdgeInsets.only(right: 4), child: Text('🛡️', style: TextStyle(fontSize: 11))),
              if (sorted[i].hasMultiplier) Padding(padding: const EdgeInsets.only(right: 4), child: Text('x2', style: TextStyle(fontSize: 9, fontFamily: KinrelTypography.monoFont, color: KinrelColors.amber))),
              Text('${sorted[i].coins}', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 13, fontWeight: FontWeight.w700, color: KinrelColors.amber)),
            ]))),
    ]);
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.game, required this.familyId, required this.players, required this.onRematch, required this.onExit});
  final FreezeAuctionGame game; final String familyId; final List<FreezeAuctionPlayerWire> players;
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
            const SizedBox(height: 4), Text('Most coins wins!', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textSilver)),
          ])),
        const SizedBox(height: 18),
        if (board != null) ...[
          GamingSectionHeader(title: 'Final Standings', icon: Icons.leaderboard_outlined),
          for (final p in board.players.toList()..sort((a, b) => b.coins.compareTo(a.coins)))
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [Text(p.playerIndex == board.winnerPlayerIndex ? '🏆' : '🏅', style: const TextStyle(fontSize: 16)), const SizedBox(width: 8), Expanded(child: Text(p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.textWhite))), Text('${p.coins} coins', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 14, fontWeight: FontWeight.w800, color: KinrelColors.amber))]))),
          const SizedBox(height: 18),
        ],
        MatchEcosystemSummary(gameTable: 'freeze_auction_games', gameId: game.id, familyId: familyId),
        const SizedBox(height: 18),
        Row(children: [Expanded(child: DKButton(label: 'Exit', variant: DKButtonVariant.secondary, fullWidth: true, onPressed: onExit)), const SizedBox(width: 10), Expanded(child: DKButton(label: 'Rematch', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () async { final newId = await onRematch(); if (newId != null && context.mounted) context.pushReplacement('/family/$familyId/freeze-auction/game/$newId'); }))]),
      ]));
  }
}
