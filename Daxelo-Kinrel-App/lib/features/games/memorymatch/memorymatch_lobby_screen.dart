// lib/features/games/memorymatch/memorymatch_lobby_screen.dart
//
// Memory Match — lobby: room setup + roster assembly.
//
// Setup phase renders the shared LobbySetupScreen (room name, difficulty
// Auto/Easy/Medium/Hard/Expert, spectators, How to Play). Waiting-room
// phase renders TemporaryLobbyView with invites + lobby chat. The host
// starts once everyone is ready; the router then swaps to the board.

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
import '../shared/widgets/lobby_chat_panel.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import '../shared/widgets/pending_invites_section.dart';
import '../shared/widgets/room_lifecycle_listener.dart';
import '../shared/services/temporary_room_service.dart'
    show kRoomClosedMessage;
import '../shared/widgets/temporary_lobby_view.dart';
import 'memorymatch_models.dart';
import 'memorymatch_provider.dart';

class MemoryMatchLobbyScreen extends ConsumerStatefulWidget {
  const MemoryMatchLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<MemoryMatchLobbyScreen> createState() =>
      _MemoryMatchLobbyScreenState();
}

class _MemoryMatchLobbyScreenState
    extends ConsumerState<MemoryMatchLobbyScreen> {
  final _roomNameController = TextEditingController();

  MemoryMatchDifficulty _difficulty = MemoryMatchDifficulty.auto;
  bool _spectatorsEnabled = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref
            .read(memoryMatchProvider(widget.familyId).notifier)
            .joinGame(joinId);
      }
    });
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier =
        ref.read(memoryMatchProvider(widget.familyId).notifier);
    await notifier.createGame(
      difficulty: _difficulty,
      roomName: _roomNameController.text,
      spectatorsEnabled: _spectatorsEnabled,
    );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final notifier =
        ref.read(memoryMatchProvider(widget.familyId).notifier);
    final result = await notifier.startGame();
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result),
        backgroundColor: KinrelColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memoryMatchProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    ref.listen<MemoryMatchState>(memoryMatchProvider(widget.familyId),
        (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/memory-match/game/${next.game!.id}',
        );
      }
    });

    final hasGame = state.game != null;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Route-level onExit guard (app_router.dart) intercepts while a
          // room is active and shows the confirmation dialog first.
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: hasGame
            ? Text(
                state.game?.roomName?.isNotEmpty == true
                    ? state.game!.roomName!
                    : 'Memory Match',
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite,
                ),
              )
            : null,
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          if (hasGame && isHost)
            IconButton(
              tooltip: 'Invite family member',
              icon: const Icon(Icons.person_add_outlined),
              onPressed: () => _openInviteSheet(state),
            ),
          if (hasGame)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _shareCode(state.game?.id),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : state.error != null && !hasGame
              ? DKErrorState(
                  message: state.error!,
                  actionLabel:
                      state.error == kRoomClosedMessage ? 'Create New Room' : null,
                  icon: state.error == kRoomClosedMessage
                      ? Icons.meeting_room_rounded
                      : null,
                  onRetry: _createGame,
                )
              : hasGame
                  ? _lobbyView(state, isHost)
                  : _setupView(state),
    );
  }

  void _openInviteSheet(MemoryMatchState state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.memoryMatch,
      gameId: game.id,
      roomCode: game.id.replaceAll('-', '').substring(0, 6).toUpperCase(),
      currentPlayerIds:
          state.players.map((p) => p.userId).whereType<String>().toSet(),
      maxPlayers: game.maxPlayers,
      currentPlayers: state.players.length,
    );
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return;
    final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
    GameMotionTokens.tap();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Share this code',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              code,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'Up to 3 family members can join. Sharpest memory wins!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
            const SizedBox(height: KinrelSpacing.lg),
            DKButton(
              label: 'Done',
              variant: DKButtonVariant.primary,
              fullWidth: true,
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/family/${widget.familyId}');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Setup phase ───────────────────────────────────────────────────

  Widget _setupView(MemoryMatchState state) {
    return LobbySetupScreen(
      gameId: 'memory-match',
      title: 'Memory Match',
      tagline: 'Flip, remember, match — the sharpest memory wins',
      facts: [
        const LobbyFact(
          icon: Icons.groups_2_outlined,
          label: '2–4 players',
        ),
        LobbyFact(
          icon: Icons.grid_view_outlined,
          label: _difficultyFact(),
        ),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySection(
            label: 'Room Name',
            child: _roomNameField(),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Difficulty',
            caption: 'Auto scales the deck with the player count',
            child: LobbyChoiceGrid<MemoryMatchDifficulty>(
              selected: _difficulty,
              onSelect: (v) => setState(() => _difficulty = v),
              options: const [
                LobbyOption(
                  value: MemoryMatchDifficulty.auto,
                  label: 'Auto',
                  caption: '2P:16 · 3P:20 · 4P:24',
                ),
                LobbyOption(
                  value: MemoryMatchDifficulty.easy,
                  label: 'Easy',
                  caption: '16 cards',
                ),
                LobbyOption(
                  value: MemoryMatchDifficulty.medium,
                  label: 'Medium',
                  caption: '20 cards',
                ),
                LobbyOption(
                  value: MemoryMatchDifficulty.hard,
                  label: 'Hard',
                  caption: '24 cards',
                ),
                LobbyOption(
                  value: MemoryMatchDifficulty.expert,
                  label: 'Expert',
                  caption: '36 cards',
                ),
              ],
            ),
          ),
        ],
      ),
      rules: const [
        LobbyRule('Everyone plays for themselves — no teams, just sharp '
            'memories.'),
        LobbyRule('On your turn, flip two cards. Find a matching pair and '
            'it\'s yours: +1 point and you go again!'),
        LobbyRule('Miss, and the cards flip back for the next player — '
            'remember where they were!'),
        LobbyRule('Each turn has a 15-second timer — hesitate and the turn '
            'skips.'),
        LobbyRule('Matched cards wear YOUR color and stay on the board, so '
            'everyone can see who\'s leading.'),
        LobbyRule('When every pair is found, the most pairs wins. Ties go '
            'to the faster finder, then the sharper aim.'),
        LobbyRule('Spectators can\'t flip — but they can cheer with emoji '
            'reactions!'),
      ],
      rulesFootnote:
          'A surprise card pack (Charms · Family · Food · Animals) is dealt '
          'at random every game.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Invite family members, then flip to win!',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  String _difficultyFact() {
    switch (_difficulty) {
      case MemoryMatchDifficulty.auto:
        return 'Deck scales with players';
      case MemoryMatchDifficulty.easy:
        return '16 cards · 8 pairs';
      case MemoryMatchDifficulty.medium:
        return '20 cards · 10 pairs';
      case MemoryMatchDifficulty.hard:
        return '24 cards · 12 pairs';
      case MemoryMatchDifficulty.expert:
        return '36 cards · 18 pairs';
    }
  }

  Widget _roomNameField() {
    return TextField(
      controller: _roomNameController,
      maxLength: 24,
      style: TextStyle(
        fontFamily: KinrelTypography.bodyFont,
        fontSize: 14,
        color: KinrelColors.textWhite,
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: 'e.g. Friday Brain Battle',
        hintStyle: TextStyle(
          fontFamily: KinrelTypography.bodyFont,
          fontSize: 14,
          color: KinrelColors.textDim.withValues(alpha: 0.6),
        ),
        filled: true,
        fillColor: KinrelColors.darkCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: BorderSide(color: KinrelColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          borderSide: const BorderSide(color: KinrelColors.orange, width: 1.4),
        ),
      ),
    );
  }

  // ── Waiting room phase ────────────────────────────────────────────

  Widget _lobbyView(MemoryMatchState state, bool isHost) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

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
      gameTable: 'memorymatch_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle:
          '${game.difficulty.label} difficulty · ${_deckPreview(game, state.players.where((p) => p.isActive).length)}',
    );

    return RoomLifecycleListener(
      gameTable: 'memorymatch_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => ref
            .read(memoryMatchProvider(widget.familyId).notifier)
            .toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => ref
            .read(memoryMatchProvider(widget.familyId).notifier)
            .leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PendingInvitesSection(gameId: game.id),
            const SizedBox(height: KinrelSpacing.md),
            LobbyChatPanel(
              gameTable: 'memorymatch_games',
              gameId: game.id,
              familyId: widget.familyId,
            ),
          ],
        ),
      ),
    );
  }

  String _deckPreview(MemoryMatchGame game, int activePlayers) {
    final count = game.difficulty.cardCount ??
        MemoryMatchDifficulty.autoCardCount(activePlayers);
    return '$count cards';
  }
}
