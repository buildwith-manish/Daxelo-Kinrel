// lib/features/games/ashtachamma/ashtachamma_lobby_screen.dart
//
// Ashta Chamma — lobby: room setup + roster assembly.
//
// Mirrors memorymatch_lobby_screen.dart exactly. Setup phase renders the
// shared LobbySetupScreen (room name, player count, spectators, How to
// Play). Waiting-room phase renders TemporaryLobbyView with invites +
// lobby chat. The host starts once everyone is ready; the router then
// swaps to the board.

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
import '../shared/widgets/room_lifecycle_listener.dart';
import '../shared/services/temporary_room_service.dart'
    show kRoomClosedMessage;
import '../shared/widgets/temporary_lobby_view.dart';
import 'ashtachamma_provider.dart';

class AshtaChammaLobbyScreen extends ConsumerStatefulWidget {
  const AshtaChammaLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<AshtaChammaLobbyScreen> createState() =>
      _AshtaChammaLobbyScreenState();
}

class _AshtaChammaLobbyScreenState
    extends ConsumerState<AshtaChammaLobbyScreen> {
  final _roomNameController = TextEditingController();

  int _maxPlayers = 4;
  bool _spectatorsEnabled = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      joinRoomWhenReady(
        context: context,
        ref: ref,
        onJoin: (id) => ref
            .read(ashtaChammaProvider(widget.familyId).notifier)
            .joinGame(id),
      );
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
        ref.read(ashtaChammaProvider(widget.familyId).notifier);
    await notifier.createGame(
      maxPlayers: _maxPlayers,
      roomName: _roomNameController.text,
      spectatorsEnabled: _spectatorsEnabled,
    );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final notifier =
        ref.read(ashtaChammaProvider(widget.familyId).notifier);
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
    final state = ref.watch(ashtaChammaProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    ref.listen<AshtaChammaState>(ashtaChammaProvider(widget.familyId),
        (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/ashta-chamma/game/${next.game!.id}',
        );
      }
    });

    final hasGame = state.game != null;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
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
                    : 'Ashta Chamma',
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

  void _openInviteSheet(AshtaChammaState state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.ashtaChamma,
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
              'Up to ${_maxPlayers - 1} family members can join. '
              'First to bring all 4 pieces home wins!',
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

  Widget _setupView(AshtaChammaState state) {
    return LobbySetupScreen(
      gameId: 'ashta-chamma',
      title: 'Ashta Chamma',
      tagline: 'Traditional Indian strategy — cowrie shells, captures, '
          'and the race home',
      facts: [
        const LobbyFact(
          icon: Icons.groups_2_outlined,
          label: '2–4 players',
        ),
        const LobbyFact(
          icon: Icons.casino_outlined,
          label: '4 cowrie shells',
        ),
        LobbyFact(
          icon: Icons.grid_view_outlined,
          label: '$_maxPlayers players',
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
            label: 'Player Count',
            caption: 'Each player gets 4 pieces (tokens)',
            child: LobbyChoiceGrid<int>(
              selected: _maxPlayers,
              onSelect: (v) => setState(() => _maxPlayers = v),
              options: const [
                LobbyOption(
                  value: 2,
                  label: '2 Players',
                  caption: 'Head-to-head',
                ),
                LobbyOption(
                  value: 3,
                  label: '3 Players',
                  caption: 'Triangle',
                ),
                LobbyOption(
                  value: 4,
                  label: '4 Players',
                  caption: 'Classic',
                ),
              ],
            ),
          ),
        ],
      ),
      rules: const [
        LobbyRule('Each player has 4 pieces (tokens) starting in their '
            'home base.'),
        LobbyRule('Throw 4 cowrie shells. The count of "up" shells '
            'determines your move: 1 up = 1, 2 up = 2, 3 up = 3, '
            '4 up = 4 (Chowka), 0 up = 8 (Ashta).'),
        LobbyRule('Roll a 1 to release a piece from your base onto the '
            'board. Chowka (4) and Ashta (8) grant an extra turn.'),
        LobbyRule('Move your piece along the cross-shaped path. Land on '
            'an opponent\'s lone piece to capture it — it goes back to '
            'their base!'),
        LobbyRule('Safe squares (every 4th intersection) protect your '
            'pieces from capture — stack them there for defense.'),
        LobbyRule('After traversing the full loop, your piece enters '
            'its home column. An exact roll lands it home — overshoot '
            'and you wait.'),
        LobbyRule('First player to bring ALL 4 pieces home wins! '
            'Spectators can cheer with emoji reactions.'),
      ],
      rulesFootnote:
          'A traditional 5×5 cross board with 56 path squares + 6-square '
          'home columns per player.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Invite family members, then race your pieces home!',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
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
        hintText: 'e.g. Sunday Family Match',
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

  Widget _lobbyView(AshtaChammaState state, bool isHost) {
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
      gameTable: 'ashta_chamma_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle: '${game.maxPlayers} players · 4 cowrie shells',
    );

    return RoomLifecycleListener(
      gameTable: 'ashta_chamma_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => ref
            .read(ashtaChammaProvider(widget.familyId).notifier)
            .toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => ref
            .read(ashtaChammaProvider(widget.familyId).notifier)
            .leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
      ),
    );
  }
}
