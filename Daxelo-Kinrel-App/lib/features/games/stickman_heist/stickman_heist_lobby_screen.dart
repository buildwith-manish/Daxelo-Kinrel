// lib/features/games/stickman_heist/stickman_heist_lobby_screen.dart
//
// Stickman Heist — Create Room lobby.
// Route: /family/$familyId/stickman-heist/lobby
//
// Setup screen: room name, map (bank / museum / warehouse), respawns
// toggle, match length (120/180/300s), max players (4/6/8). Once the
// host creates the room we transition to the shared TemporaryLobbyView
// for the waiting room, then auto-navigate to the game screen when
// isInProgress becomes true.

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
import 'stickman_heist_models.dart';
import 'stickman_heist_provider.dart';

class StickmanHeistLobbyScreen extends ConsumerStatefulWidget {
  const StickmanHeistLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<StickmanHeistLobbyScreen> createState() =>
      _StickmanHeistLobbyScreenState();
}

class _StickmanHeistLobbyScreenState
    extends ConsumerState<StickmanHeistLobbyScreen> {
  final _roomNameController = TextEditingController();
  String _mapId = 'bank';
  bool _respawnsEnabled = true;
  int _matchSeconds = 180;
  int _maxPlayers = 8;
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
            .read(stickmanHeistProvider(widget.familyId).notifier)
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
    await ref.read(stickmanHeistProvider(widget.familyId).notifier).createGame(
          mapId: _mapId,
          respawnsEnabled: _respawnsEnabled,
          matchSeconds: _matchSeconds,
          roomName: _roomNameController.text,
          spectatorsEnabled: _spectatorsEnabled,
          maxPlayers: _maxPlayers,
        );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final result = await ref
        .read(stickmanHeistProvider(widget.familyId).notifier)
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
    final state = ref.watch(stickmanHeistProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    ref.listen(stickmanHeistProvider(widget.familyId), (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/stickman-heist/game/${next.game!.id}',
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
                    : 'Stickman Heist',
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
              child:
                  CircularProgressIndicator(color: Color(0xFFEF4444)))
          : state.error != null && !hasGame
              ? DKErrorState(message: state.error!, onRetry: _createGame)
              : hasGame
                  ? _lobbyView(state, isHost)
                  : _setupView(),
    );
  }

  void _openInviteSheet(StickmanHeistState_ state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.stickmanHeist,
      gameId: game.id,
      roomCode: game.id.replaceAll('-', '').substring(0, 6).toUpperCase(),
      currentPlayerIds:
          state.players.map((p) => p.userId).whereType<String>().toSet(),
      maxPlayers: game.maxPlayers,
      currentPlayers:
          state.players.where((p) => p.isActive).length,
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
                    color: const Color(0xFFEF4444),
                    letterSpacing: 6)),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'Up to ${_maxPlayers - 1} members. Find the treasure, escape, win!',
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
    const accent = Color(0xFFEF4444);
    return LobbySetupScreen(
      gameId: 'stickman-heist',
      title: 'Stickman Heist',
      tagline: 'Treasure-hunt shooter · find it, hold it, escape',
      facts: [
        LobbyFact(icon: Icons.groups_2_outlined, label: '2–8 players'),
        LobbyFact(
            icon: Icons.timer_outlined,
            label: '${(_matchSeconds ~/ 60)}m match'),
        LobbyFact(icon: Icons.gps_fixed, label: 'Top-down'),
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
                hintText: 'e.g. Vault Raiders',
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
                  borderSide:
                      const BorderSide(color: accent, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Map',
            child: LobbyChoiceGrid<String>(
              selected: _mapId,
              onSelect: (v) => setState(() => _mapId = v),
              options: const [
                LobbyOption(
                  value: 'bank',
                  label: 'Bank Vault',
                  caption: 'Symmetric · central safe',
                  icon: Icons.account_balance_outlined,
                ),
                LobbyOption(
                  value: 'museum',
                  label: 'Museum',
                  caption: 'Long galleries · open',
                  icon: Icons.museum_outlined,
                ),
                LobbyOption(
                  value: 'warehouse',
                  label: 'Warehouse',
                  caption: 'Crate cover · tight',
                  icon: Icons.warehouse_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Match Length',
            child: LobbyChoiceGrid<int>(
              selected: _matchSeconds,
              onSelect: (v) => setState(() => _matchSeconds = v),
              options: const [
                LobbyOption(
                    value: 120, label: '2 min', caption: 'Sprint'),
                LobbyOption(
                    value: 180, label: '3 min', caption: 'Standard'),
                LobbyOption(
                    value: 300, label: '5 min', caption: 'Marathon'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Max Players',
            child: LobbyChoiceGrid<int>(
              selected: _maxPlayers,
              onSelect: (v) => setState(() => _maxPlayers = v),
              options: const [
                LobbyOption(value: 4, label: '4'),
                LobbyOption(value: 6, label: '6'),
                LobbyOption(value: 8, label: '8'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySwitchRow(
            icon: Icons.restart_alt_outlined,
            label: 'Respawns enabled',
            caption: _respawnsEnabled
                ? 'Players respawn 5s after death'
                : 'Eliminated players stay out',
            value: _respawnsEnabled,
            onChanged: (v) => setState(() => _respawnsEnabled = v),
            accentColor: accent,
          ),
        ],
      ),
      rules: const [
        LobbyRule('A treasure spawns on the map. Find it first to become the carrier.'),
        LobbyRule('The carrier is revealed to everyone — escape to a green zone to win.'),
        LobbyRule('Hunt the carrier. If they die, the treasure drops — anyone can grab it.'),
        LobbyRule('Pick up weapons (shotgun, SMG, sniper) and powerups (health, shield, speed).'),
        LobbyRule('100 HP. Respawns optional. Match time limit (3 min default).'),
      ],
      rulesFootnote:
          'Real-time top-down shooter. The host runs the physics sim and broadcasts state at 10Hz.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Invite family members, then find the treasure!',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(StickmanHeistState_ state, bool isHost) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final lobbyStatus = game.isInProgress
        ? TemporaryLobbyStatus.starting
        : game.isCompleted
            ? TemporaryLobbyStatus.finished
            : TemporaryLobbyStatus.waiting;
    final lobbyPlayers = state.players
        .where((p) => p.isActive)
        .map((p) => TemporaryLobbyPlayer(
              userId: p.userId,
              userName: p.userName,
              isReady: p.isReady,
              isHost: p.userId == game.hostUserId,
              joinedAt: p.joinedAt,
            ))
        .toList();
    final mapName = StickmanHeistMap.byId(game.mapId).name;
    final config = TemporaryLobbyConfig(
      gameTable: 'stickman_heist_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle:
          '$mapName · ${game.matchSeconds ~/ 60}m · ${game.respawnsEnabled ? 'Respawns' : 'Elimination'}',
    );
    return RoomLifecycleListener(
      gameTable: 'stickman_heist_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => ref
            .read(stickmanHeistProvider(widget.familyId).notifier)
            .toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => ref
            .read(stickmanHeistProvider(widget.familyId).notifier)
            .leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
      ),
    );
  }
}
