// lib/features/games/dotsboxes/dotsboxes_lobby_screen.dart
//
// v2 (premium lobby system): setup phase renders the shared
// LobbySetupScreen — compact hero, visible grid-size choice, spectator
// toggle, collapsible How to Play, pinned Create Game CTA.
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
import '../shared/widgets/lobby_join_handler.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import '../shared/widgets/temporary_lobby_view.dart';
import '../shared/widgets/room_lifecycle_listener.dart';
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
    joinRoomWhenReady(context: context, ref: ref,
      onJoin: (id) => ref.read(dbProvider(widget.familyId).notifier).joinGame(id));
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
    final state = ref.watch(dbProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null; final hasGame = state.game != null;

    ref.listen<DbState>(dbProvider(widget.familyId), (prev, next) {
      if (next.isInProgress && !(prev?.isInProgress ?? false) && next.game?.id != null && mounted)
        context.pushReplacement('/family/${widget.familyId}/dotsboxes/board/${next.game!.id}');
    });

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Plain pop — the route-level onExit guard (app_router.dart)
          // intercepts this while a room is active and shows the
          // confirmation dialog first.
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } },
        ),
        title: hasGame
            ? Text('Dots and Boxes', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))
            : null,
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
    return LobbySetupScreen(
      gameId: 'dotsboxes',
      title: 'Dots and Boxes',
      tagline: 'Draw lines, steal boxes, chain your way to victory',
      facts: [
        const LobbyFact(icon: Icons.group_outlined, label: '2–4 players'),
        LobbyFact(icon: Icons.grid_on_outlined, label: '$_gridSize×$_gridSize grid'),
      ],
      settings: LobbySection(
        label: 'Grid Size',
        child: LobbyChoiceGrid<int>(
          options: const [
            LobbyOption(value: 5, label: '5×5', caption: 'Quick duel'),
            LobbyOption(value: 9, label: '9×9', caption: 'Marathon match'),
          ],
          selected: _gridSize,
          onSelect: (n) => setState(() => _gridSize = n),
        ),
      ),
      rules: const [
        LobbyRule('Take turns drawing lines between adjacent dots.'),
        LobbyRule('Complete the 4th side of a box to capture it.'),
        LobbyRule('Capturing a box = bonus turn (keep drawing!).'),
        LobbyRule('Chain captures: multiple boxes in one move.'),
        LobbyRule('Most boxes when grid is full wins!'),
      ],
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: '1-3 family members can join (2-4 total)',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
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

    return RoomLifecycleListener(
          gameTable: 'dotsboxes_games',
          gameId: game.id,
          familyId: widget.familyId,
          isHost: (game.hostUserId == myId),
          child: TemporaryLobbyView(
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
    ),
    );
  }
}
