// lib/features/games/truthordare/truthordare_lobby_screen.dart
//
// v2 (premium lobby system): setup phase renders the shared
// LobbySetupScreen — compact hero, approved-prompts status, spectator
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
      joinRoomWhenReady(
        context: context,
        ref: ref,
        onJoin: (id) =>
            ref.read(todProvider(widget.familyId).notifier).joinGame(id),
      );
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Plain pop — the route-level onExit guard (app_router.dart)
          // intercepts this while a room is active and shows the
          // confirmation dialog first.
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } },
        ),
        title: hasGame
            ? Text('Truth or Dare', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))
            : null,
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.add_circle_outline), tooltip: 'Submit a prompt', onPressed: () => context.push('/family/${widget.familyId}/truthordare/submit')),
          IconButton(icon: const Icon(Icons.rate_review), tooltip: 'Review prompts', onPressed: () => context.push('/family/${widget.familyId}/truthordare/review')),
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
    return LobbySetupScreen(
      gameId: 'truthordare',
      title: 'Truth or Dare',
      tagline: 'Spin the bottle, pick your side, own the moment',
      facts: const [
        LobbyFact(icon: Icons.group_outlined, label: '4–12 players'),
        LobbyFact(icon: Icons.celebration_outlined, label: 'Party classic'),
      ],
      settings: FutureBuilder<int>(
        future: _loadPromptCount(),
        builder: (context, snapshot) => LobbyInfoNote(
          icon: Icons.library_books_rounded,
          text: '${snapshot.data ?? 0} approved family prompts ready — '
              'submit your own via the + button in the top bar.',
        ),
      ),
      rules: const [
        LobbyRule('Each round, the spinner taps to spin the bottle.'),
        LobbyRule('The bottle lands on a random player (never the spinner).'),
        LobbyRule('That player picks Truth or Dare.'),
        LobbyRule('A random approved prompt is revealed.'),
        LobbyRule('Complete the prompt and tap Done!'),
      ],
      rulesFootnote: 'Submit your own prompts via the + icon in the top bar!',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: '4-12 players — perfect for family game night',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
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
    ),
    );
  }
}
