// lib/features/games/connect4/connect4_lobby_screen.dart
//
// Connect 4 — lobby: room setup + roster assembly.
// Mirrors ashtachamma_lobby_screen.dart / memorymatch_lobby_screen.dart.

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
import 'connect4_provider.dart';

class Connect4LobbyScreen extends ConsumerStatefulWidget {
  const Connect4LobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<Connect4LobbyScreen> createState() =>
      _Connect4LobbyScreenState();
}

class _Connect4LobbyScreenState extends ConsumerState<Connect4LobbyScreen> {
  final _roomNameController = TextEditingController();
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
            .read(connect4Provider(widget.familyId).notifier)
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
    final notifier = ref.read(connect4Provider(widget.familyId).notifier);
    await notifier.createGame(
      roomName: _roomNameController.text,
      spectatorsEnabled: _spectatorsEnabled,
    );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final notifier = ref.read(connect4Provider(widget.familyId).notifier);
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
    final state = ref.watch(connect4Provider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    ref.listen<Connect4State>(connect4Provider(widget.familyId),
        (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/connect4/game/${next.game!.id}',
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
                    : 'Connect 4',
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
                  actionLabel: state.error == kRoomClosedMessage
                      ? 'Create New Room'
                      : null,
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

  void _openInviteSheet(Connect4State state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.connect4,
      gameId: game.id,
      roomCode: game.id.replaceAll('-', '').substring(0, 6).toUpperCase(),
      currentPlayerIds:
          state.players.map((p) => p.userId).whereType<String>().toSet(),
      maxPlayers: 2,
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
              'Invite 1 family member. First to connect 4 wins!',
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

  Widget _setupView(Connect4State state) {
    return LobbySetupScreen(
      gameId: 'connect4',
      title: 'Connect 4',
      tagline: 'Drop discs, connect four, win the column!',
      facts: const [
        LobbyFact(
          icon: Icons.groups_2_outlined,
          label: '2 players',
        ),
        LobbyFact(
          icon: Icons.grid_view_outlined,
          label: '7×6 grid',
        ),
        LobbyFact(
          icon: Icons.emoji_events_outlined,
          label: 'Connect 4 to win',
        ),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySection(
            label: 'Room Name',
            child: _roomNameField(),
          ),
        ],
      ),
      rules: const [
        LobbyRule('Two players take turns dropping discs into a 7-column '
            'grid. Red goes first, then Yellow.'),
        LobbyRule('When you drop a disc, it falls to the lowest empty row '
            'in that column — just like gravity.'),
        LobbyRule('Connect FOUR of your discs in a row — horizontally, '
            'vertically, or diagonally — to win!'),
        LobbyRule('If the board fills up with no four-in-a-row, it\'s a '
            'draw.'),
        LobbyRule('Think ahead: every move opens new lines for you AND '
            'your opponent. Block their threats while building your own!'),
        LobbyRule('Each turn has a 30-second timer — hesitate and the '
            'turn skips. Spectators can cheer with emoji reactions!'),
      ],
      rulesFootnote:
          'A classic strategy game that takes minutes to learn but a '
          'lifetime to master.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Invite a family member, then drop to win!',
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
        hintText: 'e.g. Family Showdown',
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

  Widget _lobbyView(Connect4State state, bool isHost) {
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
      gameTable: 'connect4_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: 2,
      status: lobbyStatus,
      subtitle: '2 players · Red vs Yellow',
    );

    return RoomLifecycleListener(
      gameTable: 'connect4_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => ref
            .read(connect4Provider(widget.familyId).notifier)
            .toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => ref
            .read(connect4Provider(widget.familyId).notifier)
            .leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
      ),
    );
  }
}
