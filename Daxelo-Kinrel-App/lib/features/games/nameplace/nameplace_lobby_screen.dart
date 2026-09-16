// lib/features/games/nameplace/nameplace_lobby_screen.dart
// Route: /family/$familyId/nameplace/lobby
//
// v2 (premium lobby system): setup phase renders the shared
// LobbySetupScreen — compact hero, visible rounds/timer/categories,
// spectator toggle, collapsible How to Play, pinned Create Game CTA.

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
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import '../shared/widgets/temporary_lobby_view.dart';
import '../shared/services/temporary_room_service.dart';
import '../shared/widgets/room_lifecycle_listener.dart';
import 'nameplace_provider.dart';

class NameplaceLobbyScreen extends ConsumerStatefulWidget {
  const NameplaceLobbyScreen({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<NameplaceLobbyScreen> createState() => _NameplaceLobbyScreenState();
}

class _NameplaceLobbyScreenState extends ConsumerState<NameplaceLobbyScreen> {
  int _totalRounds = 5;
  int _roundTimer = 60;
  bool _creating = false;
  bool _spectatorsEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(nameplaceProvider(widget.familyId).notifier).joinGame(joinId);
      }
    });
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    await ref.read(nameplaceProvider(widget.familyId).notifier).createGame(
      totalRounds: _totalRounds, roundTimerSeconds: _roundTimer);
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return;
    final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
    GameMotionTokens.tap();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context, backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Share this code', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
          const SizedBox(height: KinrelSpacing.md),
          Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 40, fontWeight: FontWeight.w700, color: KinrelColors.orange, letterSpacing: 6)),
          const SizedBox(height: KinrelSpacing.md),
          Text('Up to 19 family members can join. Categories: Name, Place, Animal, Thing, Movie.', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
          const SizedBox(height: KinrelSpacing.lg),
          DKButton(label: 'Done', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nameplaceProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    final hasGame = state.game != null;

    ref.listen<NameplaceState>(nameplaceProvider(widget.familyId), (prev, next) {
      if (next.isInProgress && next.game?.currentLetter == null && !(prev?.isInProgress ?? false) && next.game?.id != null && mounted) {
        context.pushReplacement('/family/${widget.familyId}/nameplace/letter/${next.game!.id}');
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
            ? Text('Name, Place, Animal, Thing', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))
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
                  gameType: GameType.nameplace,
                  gameId: state.game!.id,
                  roomCode: code,
                  currentPlayerIds: state.players.map((p) => p.userId).whereType<String>().toSet(),
                  maxPlayers: 20,
                  currentPlayers: state.players.length,
                );
              },
            ),
          if (hasGame) IconButton(icon: const Icon(Icons.share_outlined), onPressed: () => _shareCode(state.game?.id)),
        ],
      ),
      body: state.isLoading
        ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : state.error != null && !hasGame
          ? DKErrorState(
              message: state.error!,
              // Closed room → the button creates a NEW room (per spec the
              // closed one is deleted and must never reappear).
              actionLabel: state.error == kRoomClosedMessage ? 'Create New Room' : null,
              icon: state.error == kRoomClosedMessage ? Icons.meeting_room_rounded : null,
              onRetry: _createGame)
          : !hasGame
            ? _setupView()
            : _lobbyView(state, isHost),
    );
  }

  Widget _setupView() {
    return LobbySetupScreen(
      gameId: 'nameplace',
      title: 'Name, Place, Animal, Thing',
      tagline: 'One letter, five categories, fastest minds win',
      facts: [
        LobbyFact(icon: Icons.layers_outlined, label: '$_totalRounds rounds'),
        LobbyFact(icon: Icons.timer_outlined, label: '$_roundTimer s/round'),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySliderRow(
            label: 'Total Rounds',
            valueLabel: '$_totalRounds',
            value: _totalRounds,
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: (v) => setState(() => _totalRounds = v),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySliderRow(
            label: 'Round Timer',
            valueLabel: '$_roundTimer s',
            value: _roundTimer,
            min: 30,
            max: 120,
            divisions: 9,
            onChanged: (v) => setState(() => _roundTimer = v),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Categories',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ['Name', 'Place', 'Animal', 'Thing', 'Movie'].map((c) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(KinrelRadius.full),
                  border: Border.all(color: KinrelColors.border),
                ),
                child: Text(c, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textWhite, fontWeight: FontWeight.w600)),
              )).toList(),
            ),
          ),
        ],
      ),
      rules: const [
        LobbyRule('Each round, one player picks a letter.'),
        LobbyRule('All players write one answer per category starting with that letter.'),
        LobbyRule('Can\'t answer? Enter a dash (-).'),
        LobbyRule('Unique answer = 10 pts. Duplicate = 5 pts. Dash = 0 pts.'),
      ],
      rulesFootnote: 'Highest total after $_totalRounds rounds wins!',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Up to 19 family members can join',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(NameplaceState state, bool isHost) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final notifier = ref.read(nameplaceProvider(widget.familyId).notifier);

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
      gameTable: 'nameplace_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: 20,
      status: lobbyStatus,
      subtitle: '${game.totalRounds} rounds · ${game.roundTimerSeconds}s/round',
    );

    return RoomLifecycleListener(
          gameTable: 'nameplace_games',
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
                  gameType: GameType.nameplace,
                  gameId: game.id,
                  roomCode: code,
                  currentPlayerIds: state.players
                      .map((p) => p.userId)
                      .whereType<String>()
                      .toSet(),
                  maxPlayers: 20,
                  currentPlayers: state.players.length,
                );
              }
            : null,
    ),
    );
  }
}
