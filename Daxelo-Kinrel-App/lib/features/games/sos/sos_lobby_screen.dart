// lib/features/games/sos/sos_lobby_screen.dart
//
// SOS Game — Lobby / Setup screen.
// Route: /family/$familyId/sos/lobby
//
// v2 (premium lobby system): the setup phase renders the shared
// LobbySetupScreen — compact hero, visible game modes, spectator
// setting, COLLAPSIBLE How to Play, and a pinned Create Game CTA that
// never scrolls away. The waiting-room phase still renders the shared
// TemporaryLobbyView (roster + ready + close-room flow).

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
import '../shared/services/temporary_room_service.dart';
import 'sos_models.dart';
import 'sos_provider.dart';
import 'sos_reconnecting_banner.dart';

class SosLobbyScreen extends ConsumerStatefulWidget {
  const SosLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<SosLobbyScreen> createState() => _SosLobbyScreenState();
}

class _SosLobbyScreenState extends ConsumerState<SosLobbyScreen> {
  SosMode _mode = SosMode.twoPlayer;
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
            ref.read(sosProvider(widget.familyId).notifier).joinGame(id),
      );
    });
  }

  /// The `?join=<gameId>` query param from the deep-link (chat card tap,
  /// invite dialog accept, share-code open). Captured at initState so we
  /// can retry the same join if it fails (network blip, server hiccup)
  /// without the user having to re-tap the chat card.
  String? get _joinIdFromRoute =>
      GoRouterState.of(context).uri.queryParameters['join'];

  /// Retry entry point — branches on whether we got here via a `?join=`
  /// deep link or via the "Create Game" button. If we have a joinId and
  /// no game loaded yet, retry the join. Otherwise retry the realtime
  /// subscription.
  Future<void> _retry() async {
    final notifier = ref.read(sosProvider(widget.familyId).notifier);
    final state = ref.read(sosProvider(widget.familyId));
    final joinId = _joinIdFromRoute;
    if (state.game == null && joinId != null && joinId.isNotEmpty) {
      await notifier.joinGame(joinId);
    } else {
      await notifier.retryConnection();
    }
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier = ref.read(sosProvider(widget.familyId).notifier);
    await notifier.createGame(mode: _mode);
    if (mounted) setState(() => _creating = false);
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
              _mode == SosMode.fourPlayerTeams
                  ? '3 family members can join. Teams are assigned automatically: 1st & 3rd joiner → Team S, 2nd & 4th → Team O.'
                  : '1 family member can join to start a 2-player game.',
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
    final state = ref.watch(sosProvider(widget.familyId));
    final notifier = ref.read(sosProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    // Auto-navigate to the board once the game becomes active
    ref.listen<SosState>(sosProvider(widget.familyId), (previous, next) {
      final shouldNavigate = next.isActive;
      final wasActive = previous?.isActive ?? false;
      final gameId = next.game?.id;
      if (shouldNavigate && !wasActive && gameId != null && mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/sos/game/$gameId',
        );
      }
    });

    final hasGame = state.game != null;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        // Plain back button — the route-level onExit guard
        // (app_router.dart) intercepts this while a room is active and
        // shows the "Close Room?" / "Leave Room?" confirmation dialog
        // first; only a confirmed exit leaves the room.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } },
        ),
        // In setup state the hero carries the game identity, so the
        // app bar stays clean; once a room exists it shows the game
        // name + invite/share actions.
        title: hasGame
            ? Text(
                'SOS',
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
                final maxP = (state.game?.mode ?? SosMode.twoPlayer).maxPlayers;
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.sos,
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
      body: Column(
        children: [
          // Non-blocking connection banner — visible only when the
          // realtime channel is connecting / reconnecting / errored.
          // Hidden when status is idle or connected (the common case).
          SosReconnectingBanner(
            status: state.connectionStatus,
            friendlyError: state.friendlyError,
            onRetry: _retry,
          ),
          Expanded(
            child: state.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: KinrelColors.orange),
                  )
                : state.friendlyError != null &&
                        !hasGame &&
                        state.friendlyError != kRoomClosedMessage
                ? DKErrorState(
                    // Use friendlyError, never raw state.error — the raw
                    // error may contain Postgres / Realtime internals.
                    message: state.friendlyError!,
                    onRetry: _retry,
                  )
                : hasGame
                    ? _lobbyView(state, notifier, isHost)
                    : _setupView(state),
          ),
        ],
      ),
    );
  }

  Widget _setupView(SosState state) {
    return LobbySetupScreen(
      gameId: 'sos',
      title: 'SOS',
      tagline: 'Race to spell S-O-S on a shared grid',
      facts: [
        LobbyFact(
          icon: _mode == SosMode.twoPlayer
              ? Icons.person_outline
              : Icons.groups_outlined,
          label: _mode == SosMode.twoPlayer ? '2 players' : '4 players · 2 teams',
        ),
        const LobbyFact(icon: Icons.timer_outlined, label: '~10 min'),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySection(
            label: 'Game Mode',
            child: LobbyChoiceGrid<SosMode>(
              options: [
                LobbyOption(
                  value: SosMode.twoPlayer,
                  label: '2 Players',
                  icon: Icons.person_outline,
                ),
                LobbyOption(
                  value: SosMode.fourPlayerTeams,
                  label: '4 Player Teams',
                  icon: Icons.groups_outlined,
                ),
              ],
              selected: _mode,
              onSelect: (m) => setState(() => _mode = m),
            ),
          ),
          const SizedBox(height: KinrelSpacing.sm),
          LobbyInfoNote(icon: Icons.info_outline, text: _mode.description),
        ],
      ),
      rules: const [
        LobbyRule('Players take turns placing S or O letters on a 7×7 grid.'),
        LobbyRule('Complete an S-O-S sequence (3 cells in a line) to score a point.'),
        LobbyRule('Sequences can be horizontal, vertical, or diagonal.'),
        LobbyRule('Score a sequence → go again. Otherwise, turn passes.'),
        LobbyRule('Grid full → game over. Most sequences wins.'),
      ],
      rulesFootnote: _mode == SosMode.fourPlayerTeams
          ? 'Team mode: Team S places only S, Team O places only O. Turns rotate S1→O1→S2→O2.'
          : null,
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Family members get an invite they can accept to join',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(SosState state, SosNotifier notifier, bool isHost) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final mode = game.mode;

    // Map provider state → TemporaryLobbyConfig
    final lobbyStatus = game.isActive
        ? TemporaryLobbyStatus.starting
        : game.isFinished
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
      gameTable: 'sos_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: mode.maxPlayers,
      status: lobbyStatus,
      subtitle: mode.label,
    );

    return RoomLifecycleListener(
          gameTable: 'sos_games',
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
                  gameType: GameType.sos,
                  gameId: game.id,
                  roomCode: code,
                  currentPlayerIds: state.players
                      .map((p) => p.userId)
                      .whereType<String>()
                      .toSet(),
                  maxPlayers: mode.maxPlayers,
                  currentPlayers: state.players.length,
                );
              }
            : null,
    ),
    );
  }
}
