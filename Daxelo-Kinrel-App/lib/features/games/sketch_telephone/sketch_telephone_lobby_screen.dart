// lib/features/games/sketch_telephone/sketch_telephone_lobby_screen.dart
//
// Sketch Telephone — Create Room lobby.
// Route: /family/$familyId/sketch-telephone/lobby

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
import '../shared/widgets/temporary_lobby_view.dart';
import 'sketch_telephone_provider.dart';

/// Premium pink accent for Sketch Telephone (matches fn__game_meta).
const Color kSketchTelephoneAccent = Color(0xFFEC4899);

class SketchTelephoneLobbyScreen extends ConsumerStatefulWidget {
  const SketchTelephoneLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<SketchTelephoneLobbyScreen> createState() =>
      _SketchTelephoneLobbyScreenState();
}

class _SketchTelephoneLobbyScreenState
    extends ConsumerState<SketchTelephoneLobbyScreen> {
  final _roomNameController = TextEditingController();
  int _maxPlayers = 8;
  int _drawingSeconds = 90;
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
            .read(sketchTelephoneProvider(widget.familyId).notifier)
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
    await ref.read(sketchTelephoneProvider(widget.familyId).notifier).createGame(
          maxPlayers: _maxPlayers,
          drawingSeconds: _drawingSeconds,
          roomName: _roomNameController.text,
          spectatorsEnabled: _spectatorsEnabled,
        );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final result = await ref
        .read(sketchTelephoneProvider(widget.familyId).notifier)
        .startGame();
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
    final state = ref.watch(sketchTelephoneProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    ref.listen(sketchTelephoneProvider(widget.familyId), (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/sketch-telephone/game/${next.game!.id}',
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
                    : 'Sketch Telephone',
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
              child: CircularProgressIndicator(
                  color: kSketchTelephoneAccent))
          : state.error != null && !hasGame
              ? DKErrorState(message: state.error!, onRetry: _createGame)
              : hasGame
                  ? _lobbyView(state, isHost)
                  : _setupView(),
    );
  }

  void _openInviteSheet(SketchTelephoneState state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.sketchTelephone,
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
                    color: kSketchTelephoneAccent,
                    letterSpacing: 6)),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'Up to ${_maxPlayers - 1} members. Draw, describe, draw again — the chain mutates!',
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
      gameId: 'sketch-telephone',
      title: 'Sketch Telephone',
      tagline: 'Write → draw → describe → draw → reveal the chaos',
      facts: [
        LobbyFact(icon: Icons.groups_2_outlined, label: '4–8 players'),
        LobbyFact(
            icon: Icons.brush_outlined, label: '$_maxPlayers steps/chain'),
        LobbyFact(icon: Icons.timer_outlined, label: '$_drawingSeconds s/step'),
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
                hintText: 'e.g. Family Doodle Chain',
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
                  borderSide: BorderSide(
                      color: kSketchTelephoneAccent, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Drawing Time (per step)',
            child: LobbyChoiceGrid<int>(
              selected: _drawingSeconds,
              onSelect: (v) => setState(() => _drawingSeconds = v),
              options: const [
                LobbyOption(value: 60, label: '60s', caption: 'Brisk'),
                LobbyOption(value: 90, label: '90s', caption: 'Standard'),
                LobbyOption(value: 120, label: '120s', caption: 'Relaxed'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Max Players (each player = one step in every chain)',
            child: LobbyChoiceGrid<int>(
              selected: _maxPlayers,
              onSelect: (v) => setState(() => _maxPlayers = v),
              options: const [
                LobbyOption(value: 4, label: '4', caption: 'Short chain'),
                LobbyOption(value: 6, label: '6', caption: 'Classic'),
                LobbyOption(value: 8, label: '8', caption: 'Epic chain'),
              ],
            ),
          ),
        ],
      ),
      rules: [
        LobbyRule('Each player writes a secret prompt to start their chain.'),
        LobbyRule('Chains rotate — you draw the prompt you receive, then pass it on.'),
        LobbyRule('The next player describes your drawing (no peeking at the original!).'),
        LobbyRule('Then the next player draws that description. And so on.'),
        LobbyRule('After everyone has contributed to every chain, the chains are revealed.'),
        LobbyRule('Watch how a "cat riding a skateboard" became "a tornado with eyes."'),
      ],
      rulesFootnote:
          'Each chain has one step per player. Drawing time applies to drawing steps only — writing prompts and descriptions is untimed.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Invite family members, then watch the chaos unfold!',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(SketchTelephoneState state, bool isHost) {
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
      gameTable: 'sketch_telephone_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle:
          '${game.maxPlayers} players · ${game.drawingSeconds}s/step',
    );
    return RoomLifecycleListener(
      gameTable: 'sketch_telephone_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => ref
            .read(sketchTelephoneProvider(widget.familyId).notifier)
            .toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => ref
            .read(sketchTelephoneProvider(widget.familyId).notifier)
            .leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
      ),
    );
  }
}
