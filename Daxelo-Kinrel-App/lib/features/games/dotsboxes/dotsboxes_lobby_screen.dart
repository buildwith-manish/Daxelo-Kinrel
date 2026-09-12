import '../../../core/widgets/person_avatar.dart';
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
import '../shared/widgets/temporary_lobby_view.dart';
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

  Widget _lobbyView(DbState state, bool isHost) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final notifier = ref.read(dbProvider(widget.familyId).notifier);

    // Map provider state → TemporaryLobbyConfig
    final lobbyStatus = game.isInProgress
        ? TemporaryLobbyStatus.starting
        : game.isCompleted
            ? TemporaryLobbyStatus.finished
            : TemporaryLobbyStatus.waiting;

    final lobbyPlayers = state.players
        .map((p) => TemporaryLobbyPlayer(
              userId: p.userId,
              userName: p.userName,
              isReady: p.isReady,
              isHost: p.userId == game.hostUserId,
              joinedAt: p.joinedAt,
            ))
        .toList();

    final config = TemporaryLobbyConfig(
      gameTable: 'dotsboxes_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: 4,
      status: lobbyStatus,
      subtitle: '${game.gridSize}×${game.gridSize} grid',
    );

    return TemporaryLobbyView(
      config: config,
      myUserId: myId,
      onToggleReady: (isReady) => notifier.toggleReady(isReady),
      onStartMatch: () => notifier.startGame(),
      onCancelRoom: () => notifier.leaveGame(),
      onInviteFamily: isHost
          ? () {
              final code = game.id
                  .replaceAll('-', '')
                  .substring(0, 6)
                  .toUpperCase();
              GameMotionTokens.tap();
              InviteFamilySheet.show(
                context,
                familyId: widget.familyId,
                gameType: GameType.dotsboxes,
                gameId: game.id,
                roomCode: code,
                currentPlayerIds: state.players
                    .map((p) => p.userId)
                    .whereType<String>()
                    .toSet(),
                maxPlayers: 4,
                currentPlayers: state.players.length,
              );
            }
          : null,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PendingInvitesSection(gameId: game.id),
          const SizedBox(height: KinrelSpacing.md),
          LobbyChatPanel(
            gameTable: 'dotsboxes_games',
            gameId: game.id,
            familyId: widget.familyId,
          ),
        ],
      ),
    );
  }
}
