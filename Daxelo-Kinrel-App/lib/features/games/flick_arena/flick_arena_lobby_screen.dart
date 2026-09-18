// lib/features/games/flick_arena/flick_arena_lobby_screen.dart
//
// Flick Arena — Create Room lobby.
// Route: /family/$familyId/flick-arena/lobby
//
// Mirrors the Freeze Auction lobby pattern: a setup screen lets the host
// pick a match type (Solo Duel 1v1 or Team Battle 2v2), then a waiting
// room shows the inline player slots (read directly from the game row —
// no separate players table needed, matching the carrom pattern) and
// lets the host start the match once ≥2 players have joined.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import '../game_motion_tokens.dart';
import '../shared/models/game_invite.dart';
import '../shared/widgets/invite_family_sheet.dart';
import '../shared/widgets/lobby_join_handler.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import '../shared/widgets/room_lifecycle_listener.dart';
import '../shared/services/temporary_room_service.dart'
    show kRoomClosedMessage;
import 'flick_arena_constants.dart';
import 'flick_arena_models.dart';
import 'flick_arena_provider.dart';

class FlickArenaLobbyScreen extends ConsumerStatefulWidget {
  const FlickArenaLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<FlickArenaLobbyScreen> createState() =>
      _FlickArenaLobbyScreenState();
}

class _FlickArenaLobbyScreenState
    extends ConsumerState<FlickArenaLobbyScreen> {
  final _roomNameController = TextEditingController();
  FlickArenaMatchType _matchType = FlickArenaMatchType.soloDuel;
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
            .read(flickArenaProvider(widget.familyId).notifier)
            .joinRoom(id),
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
    await ref.read(flickArenaProvider(widget.familyId).notifier).createRoom(
          matchType: _matchType,
          spectatorsEnabled: _spectatorsEnabled,
          roomName: _roomNameController.text,
        );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final result = await ref
        .read(flickArenaProvider(widget.familyId).notifier)
        .startMatch();
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
    final state = ref.watch(flickArenaProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    // Auto-navigate to the game screen when the match starts.
    ref.listen(flickArenaProvider(widget.familyId), (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/flick-arena/game/${next.game!.id}',
        );
      }
    });

    final hasGame = state.game != null;
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/family/${widget.familyId}'),
        ),
        title: hasGame
            ? Text(
                state.game?.roomName?.isNotEmpty == true
                    ? state.game!.roomName!
                    : 'Flick Arena',
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
              tooltip: 'Invite',
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
              child: CircularProgressIndicator(color: KinrelColors.orange))
          : state.error != null && !hasGame
              ? DKErrorState(message: state.error!, onRetry: _createGame)
              : hasGame
                  ? _lobbyView(state, isHost)
                  : _setupView(),
    );
  }

  void _openInviteSheet(FlickArenaState_ state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.flickArena,
      gameId: game.id,
      roomCode: game.id.replaceAll('-', '').substring(0, 6).toUpperCase(),
      currentPlayerIds: _activePlayerIds(game),
      maxPlayers: game.maxPlayers,
      currentPlayers: game.filledSlots,
    );
  }

  /// Active player user ids — for the invite sheet's "already joined"
  /// filter so we don't show people who are already in the room.
  Set<String> _activePlayerIds(FlickArenaGame game) {
    final ids = <String>{};
    if (game.playerOneId.isNotEmpty) ids.add(game.playerOneId);
    if (game.playerTwoId.isNotEmpty) ids.add(game.playerTwoId);
    if (game.playerThreeId.isNotEmpty) ids.add(game.playerThreeId);
    if (game.playerFourId.isNotEmpty) ids.add(game.playerFourId);
    return ids;
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return;
    final code =
        gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
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
            Text('Share this code',
                style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite)),
            const SizedBox(height: KinrelSpacing.md),
            Text(code,
                style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.orange,
                    letterSpacing: 6)),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'Up to ${_matchType.maxPlayers - 1} members. Flick, aim, score!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim),
            ),
            const SizedBox(height: KinrelSpacing.lg),
            DKButton(
              label: 'Done',
              variant: DKButtonVariant.primary,
              fullWidth: true,
              onPressed: () => context.canPop()
                  ? context.pop()
                  : context.go('/family/${widget.familyId}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupView() {
    return LobbySetupScreen(
      gameId: 'flick-arena',
      title: 'Flick Arena',
      tagline: 'Flick discs, score goals — physics strategy',
      facts: [
        LobbyFact(
            icon: Icons.groups_2_outlined,
            label: _matchType == FlickArenaMatchType.soloDuel
                ? '1 v 1'
                : '2 v 2'),
        LobbyFact(
            icon: Icons.sports_soccer_outlined,
            label: _matchType == FlickArenaMatchType.soloDuel
                ? 'First to 3'
                : 'First to 5'),
        LobbyFact(icon: Icons.bolt_outlined, label: '15s turns'),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySection(
            label: 'Room Name',
            child: TextField(
              controller: _roomNameController,
              maxLength: 24,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color: KinrelColors.textWhite),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'e.g. Friday Night Flick',
                hintStyle: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    color: KinrelColors.textDim.withValues(alpha: 0.6)),
                filled: true,
                fillColor: KinrelColors.darkCard,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: BorderSide(color: KinrelColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: const BorderSide(
                      color: KinrelColors.orange, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Match Type',
            child: LobbyChoiceGrid<FlickArenaMatchType>(
              selected: _matchType,
              onSelect: (v) => setState(() => _matchType = v),
              options: const [
                LobbyOption(
                  value: FlickArenaMatchType.soloDuel,
                  label: 'Solo Duel',
                  caption: '1 v 1 · First to 3',
                ),
                LobbyOption(
                  value: FlickArenaMatchType.teamBattle,
                  label: 'Team Battle',
                  caption: '2 v 2 · First to 5',
                ),
              ],
            ),
          ),
        ],
      ),
      rules: const [
        LobbyRule('Tap one of your discs, drag back to aim, release to flick.'),
        LobbyRule('Knock the ball into your opponent\'s goal to score.'),
        LobbyRule('15-second turn timer — if you don\'t shoot, you auto-skip.'),
        LobbyRule('Discs bounce off walls and each other — bank shots matter.'),
        LobbyRule('Team Battle: 2 v 2, shared score, first team to 5 wins.'),
      ],
      rulesFootnote:
          'Solo Duel: 1 v 1, first to 3 goals. Team Battle: 2 v 2, first team to 5.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Invite family members, then flick to score!',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(FlickArenaState_ state, bool isHost) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    return RoomLifecycleListener(
      gameTable: 'flick_arena_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: _FlickArenaWaitingRoom(
        game: game,
        myUserId: myId,
        isHost: isHost,
        error: state.error,
        onStartMatch: _startMatch,
        onCancelRoom: () => ref
            .read(flickArenaProvider(widget.familyId).notifier)
            .leaveRoom(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
      ),
    );
  }
}

/// Self-contained waiting room for Flick Arena. Reads the inline player
/// slots directly from the game row — no separate players table needed.
class _FlickArenaWaitingRoom extends StatelessWidget {
  const _FlickArenaWaitingRoom({
    required this.game,
    required this.myUserId,
    required this.isHost,
    required this.error,
    required this.onStartMatch,
    required this.onCancelRoom,
    required this.onInviteFamily,
  });

  final FlickArenaGame game;
  final String? myUserId;
  final bool isHost;
  final String? error;
  final Future<void> Function() onStartMatch;
  final Future<void> Function() onCancelRoom;
  final VoidCallback? onInviteFamily;

  @override
  Widget build(BuildContext context) {
    final slots = game.turnOrder;
    final filled = game.filledSlots;
    final canStart = filled >= 2;

    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      children: [
        // ── Status banner ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: KinrelColors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: KinrelColors.orange.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: KinrelColors.orange,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: KinrelColors.orange, blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$filled / ${game.maxPlayers} players · ${game.matchType.label}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
              if (game.matchType == FlickArenaMatchType.soloDuel)
                Text('First to 3',
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.amber))
              else
                Text('First to 5',
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.amber)),
            ],
          ),
        ),
        const SizedBox(height: KinrelSpacing.md),

        // ── Error banner ────────────────────────────────────────────
        if (error != null && error != kRoomClosedMessage) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: KinrelColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: KinrelColors.error.withValues(alpha: 0.35)),
            ),
            child: Text(error!,
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.error)),
          ),
          const SizedBox(height: KinrelSpacing.md),
        ],

        // ── Player slot list ───────────────────────────────────────
        GamingSectionHeader(title: 'Players', icon: Icons.groups_2_outlined),
        const SizedBox(height: 6),
        for (final slot in slots)
          _PlayerSlotRow(
            slot: slot,
            team: game.teamForSlot(slot),
            userId: game.playerForSlot(slot).$1,
            userName: game.playerForSlot(slot).$2,
            isHost: game.hostUserId == game.playerForSlot(slot).$1,
            isMe: myUserId == game.playerForSlot(slot).$1,
            matchType: game.matchType,
          ),
        const SizedBox(height: KinrelSpacing.md),

        // ── Invite button ───────────────────────────────────────────
        if (filled < game.maxPlayers && onInviteFamily != null) ...[
          DKButton(
            label: 'Invite Family Members',
            variant: DKButtonVariant.secondary,
            fullWidth: true,
            icon: Icons.person_add_outlined,
            onPressed: onInviteFamily,
          ),
          const SizedBox(height: KinrelSpacing.md),
        ],

        // ── Match actions ───────────────────────────────────────────
        if (isHost)
          DKButton(
            label: canStart
                ? 'Start Match'
                : 'Waiting for ${2 - filled} more player${2 - filled > 1 ? 's' : ''}...',
            variant: DKButtonVariant.primary,
            fullWidth: true,
            onPressed: canStart ? onStartMatch : null,
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(color: KinrelColors.border),
            ),
            child: Center(
              child: Text(
                'Waiting for the host to start the match...',
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textDim),
              ),
            ),
          ),
        const SizedBox(height: 10),
        DKButton(
          label: 'Leave Room',
          variant: DKButtonVariant.secondary,
          fullWidth: true,
          onPressed: onCancelRoom,
        ),
      ],
    );
  }
}

class _PlayerSlotRow extends StatelessWidget {
  const _PlayerSlotRow({
    required this.slot,
    required this.team,
    required this.userId,
    required this.userName,
    required this.isHost,
    required this.isMe,
    required this.matchType,
  });

  final int slot;
  final int team;
  final String userId;
  final String userName;
  final bool isHost;
  final bool isMe;
  final FlickArenaMatchType matchType;

  @override
  Widget build(BuildContext context) {
    final isEmpty = userId.isEmpty;
    final teamColor = team == 1
        ? KinrelColors.orange
        : const Color(0xFF22D3EE); // cyan accent for team 2
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMe
                ? teamColor.withValues(alpha: 0.5)
                : KinrelColors.border,
          ),
        ),
        child: Row(
          children: [
            // Slot indicator
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isEmpty
                    ? KinrelColors.darkElevated
                    : teamColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                    color: isEmpty
                        ? KinrelColors.border
                        : teamColor.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: isEmpty
                    ? Icon(Icons.add,
                        size: 16, color: KinrelColors.textDim)
                    : Text(
                        '$slot',
                        style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: teamColor),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEmpty ? 'Open slot' : userName,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isEmpty
                          ? KinrelColors.textDim
                          : KinrelColors.textWhite,
                    ),
                  ),
                  Text(
                    matchType == FlickArenaMatchType.teamBattle
                        ? 'Team $team'
                        : 'Player $slot',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            if (isHost)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: KinrelColors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: KinrelColors.amber.withValues(alpha: 0.4)),
                ),
                child: Text('HOST',
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.amber)),
              ),
            if (isMe)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text('YOU',
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.orange)),
              ),
          ],
        ),
      ),
    );
  }
}
