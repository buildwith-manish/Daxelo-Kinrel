// lib/features/games/twotruths/twotruths_lobby_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import '../shared/models/game_invite.dart';
import '../shared/widgets/invite_family_sheet.dart';
import '../shared/widgets/pending_invites_section.dart';
import 'twotruths_models.dart';
import 'twotruths_provider.dart';

class TtLobbyScreen extends ConsumerStatefulWidget {
  const TtLobbyScreen({super.key, required this.familyId}); final String familyId;
  @override
  ConsumerState<TtLobbyScreen> createState() => _TtLobbyScreenState();
}
class _TtLobbyScreenState extends ConsumerState<TtLobbyScreen> {
  TtMode _mode = TtMode.playerAuthored; int _totalRounds = 3; int _timer = 30; bool _creating = false;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) {
    final joinId = GoRouterState.of(context).uri.queryParameters['join'];
    if (joinId != null && joinId.isNotEmpty) ref.read(ttProvider(widget.familyId).notifier).joinGame(joinId);
  }); }

  Future<void> _createGame() async { setState(() => _creating = true); await ref.read(ttProvider(widget.familyId).notifier).createGame(mode: _mode, totalRounds: _totalRounds, roundTimerSeconds: _timer); if (mounted) setState(() => _creating = false); }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return; final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase(); GameMotionTokens.tap();
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg))),
      builder: (_) => Padding(padding: const EdgeInsets.all(KinrelSpacing.xl), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Share this code', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        const SizedBox(height: KinrelSpacing.md),
        Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 40, fontWeight: FontWeight.w700, color: KinrelColors.orange, letterSpacing: 6)),
        const SizedBox(height: KinrelSpacing.lg),
        DKButton(label: 'Done', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () => Navigator.of(context).pop()),
      ])));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ttProvider(widget.familyId)); final notifier = ref.read(ttProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null; final hasGame = state.game != null;
    ref.listen<TtState>(ttProvider(widget.familyId), (prev, next) {
      if (next.isInProgress && !(prev?.isInProgress ?? false) && next.game?.id != null && mounted)
        context.pushReplacement('/family/${widget.familyId}/twotruths/submit/${next.game!.id}');
    });
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { if (state.game != null) notifier.leaveGame(); Navigator.of(context).pop(); }),
        title: Text('Two Truths and a Lie', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
        actions: [
          if (hasGame && isHost)
            IconButton(
              tooltip: 'Invite family member',
              icon: const Icon(Icons.person_add_outlined),
              onPressed: () {
                final code = state.game!.id.replaceAll('-', '').substring(0, 6).toUpperCase();
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.twotruths,
                  gameId: state.game!.id,
                  roomCode: code,
                  currentPlayerIds: state.players.map((p) => p.userId).whereType<String>().toSet(),
                  maxPlayers: 12,
                  currentPlayers: state.players.length,
                );
              },
            ),
          if (hasGame) IconButton(icon: const Icon(Icons.share_outlined), onPressed: () => _shareCode(state.game?.id)),
        ],
      ),
      body: state.isLoading ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange)) : !hasGame ? _setupView() : _lobbyView(state, isHost),
    );
  }

  Widget _setupView() {
    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      Text('Game Mode', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim)),
      const SizedBox(height: 8),
      GestureDetector(onTap: () { GameMotionTokens.tap(); setState(() => _mode = TtMode.playerAuthored); },
        child: Container(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: _mode == TtMode.playerAuthored ? KinrelColors.orange : KinrelColors.border, width: _mode == TtMode.playerAuthored ? 2 : 1)),
          child: Row(children: [Icon(Icons.person, color: _mode == TtMode.playerAuthored ? KinrelColors.orange : KinrelColors.textDim, size: 20), const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Player-Authored', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: _mode == TtMode.playerAuthored ? KinrelColors.textWhite : KinrelColors.textDim)),
              Text('You write all 3 statements (2 true, 1 lie)', style: TextStyle(fontSize: 11, color: KinrelColors.textDim))]))]))),
      GestureDetector(onTap: () { GameMotionTokens.tap(); setState(() => _mode = TtMode.aiLie); },
        child: Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: _mode == TtMode.aiLie ? KinrelColors.orange : KinrelColors.border, width: _mode == TtMode.aiLie ? 2 : 1)),
          child: Row(children: [Icon(Icons.smart_toy, color: _mode == TtMode.aiLie ? KinrelColors.orange : KinrelColors.textDim, size: 20), const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('AI Lie Mode', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: _mode == TtMode.aiLie ? KinrelColors.textWhite : KinrelColors.textDim)),
              Text('You write 2 truths, AI generates the lie', style: TextStyle(fontSize: 11, color: KinrelColors.textDim))]))]))),
      const SizedBox(height: 20),
      Text('Total Rounds: $_totalRounds', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim)),
      Slider(value: _totalRounds.toDouble(), min: 1, max: 12, divisions: 11, activeColor: KinrelColors.orange, label: '$_totalRounds', onChanged: (v) => setState(() => _totalRounds = v.round())),
      const SizedBox(height: 8),
      Text('Guess Timer: ${_timer}s', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim)),
      Slider(value: _timer.toDouble(), min: 15, max: 90, divisions: 15, activeColor: KinrelColors.orange, label: '${_timer}s', onChanged: (v) => setState(() => _timer = v.round())),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: KinrelColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How to Play', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
          const SizedBox(height: 8),
          Text('• Each round, one player submits 3 statements (2 true, 1 lie)\n• Others guess which is the lie\n• Correct guess = 1pt. Each fooled player = 1pt for submitter\n• Highest total after $_totalRounds rounds wins!',
            style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim, height: 1.5)),
        ])),
      const SizedBox(height: 20),
      DKButton(label: 'Create Game', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: _creating, onPressed: _createGame),
    ]);
  }

  Widget _lobbyView(state, bool isHost) {
    final game = state.game!; final code = game.id.replaceAll('-', '').substring(0, 6).toUpperCase();
    final canStart = state.players.length >= 4;
    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      GestureDetector(onTap: () => _shareCode(game.id),
        child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: KinrelGradients.igniteGradient, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [Text('Share Code', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9))),
            const SizedBox(height: 8), Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 8)),
            const SizedBox(height: 4), Text('${state.players.length}/12 players', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: Colors.white.withValues(alpha: 0.8)))]))),
      const SizedBox(height: 16),
      Text('Players (${state.players.length})', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim)),
      const SizedBox(height: 8),
      ...state.players.map((p) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.userId == ref.read(supabaseProvider)?.auth.currentUser?.id ? KinrelColors.orange : KinrelColors.border)),
        child: Row(children: [DKAvatar(initials: p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?'), const SizedBox(width: 8),
          Expanded(child: Text(p.userId == ref.read(supabaseProvider)?.auth.currentUser?.id ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
          if (p.userId == game.hostUserId) Text('👑', style: TextStyle(fontSize: 14))]))),
      const SizedBox(height: 20),
      if (hasGame)
          PendingInvitesSection(gameId: state.game!.id),
        const SizedBox(height: KinrelSpacing.md),
        if (isHost) DKButton(label: canStart ? 'Start Game' : 'Need 4+ players', variant: DKButtonVariant.gradient, fullWidth: true, onPressed: canStart ? () => ref.read(ttProvider(widget.familyId).notifier).startGame() : null)
      else Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: KinrelColors.border)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange)), const SizedBox(width: 8), Text('Waiting for host...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim))])),
    ]);
  }
}
