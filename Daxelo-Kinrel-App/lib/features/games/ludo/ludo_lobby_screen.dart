// lib/features/games/ludo/ludo_lobby_screen.dart
//
// Ludo — Lobby screen to start a game and invite 1-3 family members.
// Route: /family/$familyId/ludo/lobby
//
// v2 (premium lobby system): setup phase renders the shared
// LobbySetupScreen — compact hero, visible player count + color order,
// spectator toggle, collapsible How to Play, pinned Create Game CTA.
// Waiting-room phase still renders TemporaryLobbyView.

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
import '../shared/widgets/pending_invites_section.dart';
import '../shared/widgets/lobby_chat_panel.dart';
import '../shared/widgets/temporary_lobby_view.dart';
import '../shared/services/temporary_room_service.dart';
import '../shared/widgets/room_lifecycle_listener.dart';
import 'ludo_game_logic.dart';
import 'ludo_provider.dart';

class LudoLobbyScreen extends ConsumerStatefulWidget {
  const LudoLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<LudoLobbyScreen> createState() => _LudoLobbyScreenState();
}

class _LudoLobbyScreenState extends ConsumerState<LudoLobbyScreen> {
  int _playerCount = 4;
  bool _creating = false;
  bool _spectatorsEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(ludoProvider(widget.familyId).notifier).joinGame(joinId);
      }
    });
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier = ref.read(ludoProvider(widget.familyId).notifier);
    final gameId = await notifier.createGame(playerCount: _playerCount);
      if (gameId != null) {
        await ref.read(supabaseProvider)?.from('ludo_games').update({'spectatorsEnabled': _spectatorsEnabled}).eq('id', gameId);
      }

    if (mounted) setState(() => _creating = false);
    // Stay on lobby to wait for players
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
              'Up to ${_playerCount - 1} family members can join. Colors are assigned in order: Red, Blue, Green, Yellow.',
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
              onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ludoProvider(widget.familyId));
    final notifier = ref.read(ludoProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    final canStart = state.game == null
        ? true
        : (isHost && state.players.length >= 2);

    ref.listen<LudoState>(ludoProvider(widget.familyId), (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/ludo/board/${next.game!.id}',
        );
      }
    });

    final hasGame = state.game != null;

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
            ? Text(
                'Ludo',
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
              onPressed: () {
                final code = state.game?.id != null ? state.game!.id.replaceAll('-', '').substring(0, 6).toUpperCase() : '------';
                final maxP = state.game?.playerCount ?? 4;
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.ludo,
                  gameId: state.game?.id ?? '',
                  roomCode: code,
                  currentPlayerIds: state.players
                      .map((p) => p.userId)
                      .whereType<String>()
                      .toSet(),
                  maxPlayers: maxP,
                  currentPlayers: state.players.length,
                );
              },
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
              // Closed room → the button creates a NEW room (per spec the
              // closed one is deleted and must never reappear).
              actionLabel:
                  state.error == kRoomClosedMessage ? 'Create New Room' : null,
              icon: state.error == kRoomClosedMessage
                  ? Icons.meeting_room_rounded
                  : null,
              onRetry: () => notifier.createGame(playerCount: _playerCount),
            )
          : hasGame
              ? _lobbyView(state, notifier, isHost, canStart)
              : _setupView(state),
    );
  }

  Widget _setupView(LudoState state) {
    return LobbySetupScreen(
      gameId: 'ludo',
      title: 'Ludo',
      tagline: 'Race your tokens home before anyone else',
      facts: [
        LobbyFact(icon: Icons.group_outlined, label: '$_playerCount players'),
        const LobbyFact(icon: Icons.casino_outlined, label: 'Dice classic'),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySection(
            label: 'Number of Players',
            child: LobbyNumberRow(
              numbers: const [2, 3, 4],
              selected: _playerCount,
              onSelect: (n) => setState(() => _playerCount = n),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Color Order',
            child: _colorOrderCard(),
          ),
        ],
      ),
      rules: const [
        LobbyRule('Roll a 6 to move a token out of home base onto the board.'),
        LobbyRule('Rolling a 6 grants an extra turn.'),
        LobbyRule('Move tokens clockwise around the track by the number rolled.'),
        LobbyRule('Land on an opponent (non-safe square) → send them home!'),
        LobbyRule('Safe squares (starred) protect tokens from capture.'),
        LobbyRule('After a full loop, enter your home column → reach the center.'),
        LobbyRule('Must roll the exact number to reach the center.'),
      ],
      rulesFootnote: 'Three 6s in a row = forfeit your turn!',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Up to ${_playerCount - 1} family members can join',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(
    LudoState state,
    LudoNotifier notifier,
    bool isHost,
    bool canStart,
  ) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

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
      gameTable: 'ludo_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.playerCount,
      status: lobbyStatus,
      subtitle: '${game.playerCount} players',
    );

    return RoomLifecycleListener(
          gameTable: 'ludo_games',
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
                  gameType: GameType.ludo,
                  gameId: game.id,
                  roomCode: code,
                  currentPlayerIds: state.players
                      .map((p) => p.userId)
                      .whereType<String>()
                      .toSet(),
                  maxPlayers: game.playerCount,
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
              gameTable: 'ludo_games',
              gameId: game.id,
              familyId: widget.familyId,
            ),
          ],
        ),
    ),
    );
  }

  Widget _colorOrderCard() {
    final colors = [LudoColor.red, LudoColor.blue, LudoColor.green, LudoColor.yellow];
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: colors.take(_playerCount).map((c) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _colorValue(c),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                c.name.toUpperCase(),
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  color: KinrelColors.textDim,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// Original Kinrel-branded color mapping (matches board screen).
  Color _colorValue(LudoColor c) {
    switch (c) {
      case LudoColor.red:
        return KinrelColors.orange;     // "Ember"
      case LudoColor.blue:
        return KinrelColors.blue;       // "Azure"
      case LudoColor.green:
        return KinrelColors.tealAccent; // "Jade"
      case LudoColor.yellow:
        return KinrelColors.gold;       // "Gold"
    }
  }
}
