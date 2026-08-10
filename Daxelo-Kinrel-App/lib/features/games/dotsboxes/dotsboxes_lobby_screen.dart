// lib/features/games/dotsboxes/dotsboxes_lobby_screen.dart
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
import '../shared/widgets/lobby_chat_panel.dart';
import '../shared/widgets/spectator_toggle.dart';
import 'dotsboxes_provider.dart';

class DotsboxesLobbyScreen extends ConsumerStatefulWidget {
  const DotsboxesLobbyScreen({super.key, required this.familyId}); final String familyId;
  @override
  ConsumerState<DotsboxesLobbyScreen> createState() => _DotsboxesLobbyScreenState();
}
class _DotsboxesLobbyScreenState extends ConsumerState<DotsboxesLobbyScreen> {
  int _gridSize = 5; bool _creating = false;
  bool _spectatorsEnabled = true;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) {
    final joinId = GoRouterState.of(context).uri.queryParameters['join'];
    if (joinId != null && joinId.isNotEmpty) ref.read(dbProvider(widget.familyId).notifier).joinGame(joinId);
  }); }

  Future<void> _createGame() async { setState(() => _creating = true); await ref.read(dbProvider(widget.familyId).notifier).createGame(gridSize: _gridSize); if (mounted) setState(() => _creating = false); }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return; final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase(); GameMotionTokens.tap();
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg))),
      builder: (_) => Padding(padding: const EdgeInsets.all(KinrelSpacing.xl), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Share this code', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        const SizedBox(height: KinrelSpacing.md),
        Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 40, fontWeight: FontWeight.w700, color: KinrelColors.orange, letterSpacing: 6)),
        const SizedBox(height: KinrelSpacing.md),
        Text('1-3 family members can join (2-4 total).', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
        const SizedBox(height: KinrelSpacing.lg),
        DKButton(label: 'Done', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
      ])));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dbProvider(widget.familyId)); final notifier = ref.read(dbProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null; final hasGame = state.game != null;

    ref.listen<DbState>(dbProvider(widget.familyId), (prev, next) {
      if (next.isInProgress && !(prev?.isInProgress ?? false) && next.game?.id != null && mounted)
        context.pushReplacement('/family/${widget.familyId}/dotsboxes/board/${next.game!.id}');
    });

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { if (state.game != null) notifier.leaveGame(); if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Dots and Boxes', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
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
                  gameType: GameType.dotsboxes,
                  gameId: state.game!.id,
                  roomCode: code,
                  currentPlayerIds: state.players.map((p) => p.userId).whereType<String>().toSet(),
                  maxPlayers: 4,
                  currentPlayers: state.players.length,
                );
              },
            ),
          if (hasGame) IconButton(icon: const Icon(Icons.share_outlined), onPressed: () => _shareCode(state.game?.id)),
        ],
      ),
      body: state.isLoading ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : !hasGame ? _setupView() : _lobbyView(state, isHost),
    );
  }

  Widget _setupView() {
    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      Text('Grid Size', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [5, 9].map((n) {
        final sel = n == _gridSize;
        return GestureDetector(onTap: () { GameMotionTokens.tap(); setState(() => _gridSize = n); },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? KinrelColors.orange : KinrelColors.border, width: sel ? 2 : 1)),
            child: Text('${n}×$n boxes', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: sel ? KinrelColors.orange : KinrelColors.textDim))));
      }).toList()),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: KinrelColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How to Play', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
          const SizedBox(height: 8),
          Text('• Take turns drawing lines between adjacent dots\n• Complete the 4th side of a box to capture it\n• Capturing a box = bonus turn (keep drawing!)\n• Chain captures: multiple boxes in one move\n• Most boxes when grid is full wins!',
            style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim, height: 1.5)),
        ])),
      const SizedBox(height: 20),
            SpectatorToggle(
        value: _spectatorsEnabled,
        onChanged: (v) => setState(() => _spectatorsEnabled = v),
      ),
      const SizedBox(height: KinrelSpacing.md),
      DKButton(label: 'Create Game', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: _creating, onPressed: _createGame),
    ]);
  }

  Widget _lobbyView(state, bool isHost) {
    final game = state.game!; final code = game.id.replaceAll('-', '').substring(0, 6).toUpperCase();
    final canStart = state.players.length >= 2;
    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      GestureDetector(onTap: () => _shareCode(game.id),
        child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: KinrelGradients.igniteGradient, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [Text('Share Code', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.9))),
            const SizedBox(height: 8), Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 8)),
            const SizedBox(height: 4), Text('${state.players.length}/4 players', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: Colors.white.withValues(alpha: 0.8)))]))),
      const SizedBox(height: 16),
      Text('Players (${state.players.length})', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textDim)),
      const SizedBox(height: 8),
      ...state.players.map((p) {
        final colors = [KinrelColors.orange, KinrelColors.blue, KinrelColors.tealAccent, KinrelColors.gold];
        final color = colors[p.playerColor % 4];
        return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.userId == ref.read(supabaseProvider)?.auth.currentUser?.id ? KinrelColors.orange : KinrelColors.border)),
          child: Row(children: [
            Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: 8),
            DKAvatar(initials: p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?'),
            const SizedBox(width: 8),
            Expanded(child: Text(p.userId == ref.read(supabaseProvider)?.auth.currentUser?.id ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))),
            if (p.userId == game.hostUserId) Text('👑', style: TextStyle(fontSize: 14)),
          ]));
      }),
      const SizedBox(height: 20),
      PendingInvitesSection(gameId: state.game!.id),
      const SizedBox(height: KinrelSpacing.md),
            LobbyChatPanel(
              gameTable: 'dotsboxes_games',
              gameId: state.game!.id,
              familyId: widget.familyId,
            ),
      if (isHost) DKButton(label: canStart ? 'Start Game' : 'Need 2+ players', variant: DKButtonVariant.gradient, fullWidth: true, onPressed: canStart ? () => ref.read(dbProvider(widget.familyId).notifier).startGame() : null)
      else Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: KinrelColors.border)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange)), const SizedBox(width: 8), Text('Waiting for host...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim))])),
    ]);
  }
}
