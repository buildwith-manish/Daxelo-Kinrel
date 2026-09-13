import '../../../core/widgets/person_avatar.dart';
// lib/features/games/truthordare/truthordare_lobby_screen.dart
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
import '../shared/widgets/room_lifecycle_listener.dart';
import 'truthordare_provider.dart';

class TodLobbyScreen extends ConsumerStatefulWidget {
  const TodLobbyScreen({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<TodLobbyScreen> createState() => _TodLobbyScreenState();
}

class _TodLobbyScreenState extends ConsumerState<TodLobbyScreen> {
  bool _creating = false;
  bool _spectatorsEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) ref.read(todProvider(widget.familyId).notifier).joinGame(joinId);
    });
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    await ref.read(todProvider(widget.familyId).notifier).createGame();
    if (mounted) setState(() => _creating = false);
  }

  Future<int> _loadPromptCount() async {
    final client = ref.read(supabaseProvider);
    if (client == null) return 0;
    try {
      final resp = await client.from('truthordare_prompts').select().eq('familyId', widget.familyId).eq('status', 'approved');
      return resp.length;
    } catch (_) { return 0; }
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return;
    final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
    GameMotionTokens.tap();
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg))),
      builder: (_) => Padding(padding: const EdgeInsets.all(KinrelSpacing.xl), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Share this code', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        const SizedBox(height: KinrelSpacing.md),
        Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 40, fontWeight: FontWeight.w700, color: KinrelColors.orange, letterSpacing: 6)),
        const SizedBox(height: KinrelSpacing.md),
        Text('4-12 players. Spin the bottle, pick Truth or Dare!', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
        const SizedBox(height: KinrelSpacing.lg),
        DKButton(label: 'Done', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
      ])));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todProvider(widget.familyId));
    final notifier = ref.read(todProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    final hasGame = state.game != null;

    ref.listen<TodState>(todProvider(widget.familyId), (prev, next) {
      if (next.isInProgress && !(prev?.isInProgress ?? false) && next.game?.id != null && mounted) {
        context.pushReplacement('/family/${widget.familyId}/truthordare/table/${next.game!.id}');
      }
    });

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { if (state.game != null) notifier.leaveGame(); if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Truth or Dare', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => context.push('/family/${widget.familyId}/truthordare/submit')),
          IconButton(icon: const Icon(Icons.rate_review), onPressed: () => context.push('/family/${widget.familyId}/truthordare/review')),
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
                  gameType: GameType.truthordare,
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
      body: state.isLoading ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : !hasGame ? _setupView() : _lobbyView(state, isHost),
    );
  }

  Widget _setupView() {
    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      Text('Truth or Dare', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
      const SizedBox(height: 4),
      Text('Spin the bottle, pick Truth or Dare, answer family-submitted prompts!', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
      const SizedBox(height: KinrelSpacing.lg),
      // Rules
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: KinrelColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _rule('1. Each round, the spinner taps to spin the bottle.'),
          const SizedBox(height: 4), _rule('2. The bottle lands on a random player (never the spinner).'),
          const SizedBox(height: 4), _rule('3. That player picks Truth or Dare.'),
          const SizedBox(height: 4), _rule('4. A random approved prompt is revealed.'),
          const SizedBox(height: 4), _rule('5. Complete the prompt and tap Done!'),
          const SizedBox(height: 4), _rule('★ Submit your own prompts via the + icon!', highlight: true),
        ])),
      const SizedBox(height: KinrelSpacing.lg),
      // Approved prompt count
      FutureBuilder(future: _loadPromptCount(),
        builder: (context, snapshot) => Text('${snapshot.data ?? 0} approved prompts ready', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim))),
      const SizedBox(height: KinrelSpacing.xl),
            SpectatorToggle(
        value: _spectatorsEnabled,
        onChanged: (v) => setState(() => _spectatorsEnabled = v),
      ),
      const SizedBox(height: KinrelSpacing.md),
      DKButton(label: 'Create Game', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: _creating, onPressed: _createGame),
    ]);
  }

  Widget _lobbyView(TodState state, bool isHost) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final notifier = ref.read(todProvider(widget.familyId).notifier);

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
      gameTable: 'truthordare_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: 12,
      status: lobbyStatus,
      subtitle: 'Spin the bottle',
    );

    return RoomLifecycleListener(
          gameTable: 'truthordare_games',
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
                  gameType: GameType.truthordare,
                  gameId: game.id,
                  roomCode: code,
                  currentPlayerIds: state.players
                      .map((p) => p.userId)
                      .whereType<String>()
                      .toSet(),
                  maxPlayers: 12,
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
              gameTable: 'truthordare_games',
              gameId: game.id,
              familyId: widget.familyId,
            ),
          ],
        ),
    ),
    );
  }

  Widget _rule(String text, {bool highlight = false}) => Text(text, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: highlight ? KinrelColors.orange : KinrelColors.textDim, height: 1.4));
}
