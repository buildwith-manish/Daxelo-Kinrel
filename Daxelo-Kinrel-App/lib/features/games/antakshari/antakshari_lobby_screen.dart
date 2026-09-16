// lib/features/games/antakshari/antakshari_lobby_screen.dart
//
// Antakshari — Lobby / Setup screen.
// Route: /family/$familyId/antakshari/lobby
//
// This screen orchestrates two phases:
//   1. Setup view — host picks game mode, max players, timer, etc.
//      (shared LobbySetupScreen: hero + modes + sliders + spectator +
//      collapsible How to Play + pinned Create Game CTA).
//   2. Lobby view — uses the shared `TemporaryLobbyView` widget to
//      prioritize players / ready / Start Match over the room code.
//
// Every Play tap creates a brand-new room (never reused). The shared
// widget shows clear states (Waiting for Players / Everyone is Ready /
// Match Starting / Game Finished) and demotes the room code to a
// footnote.

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
import '../shared/widgets/temporary_lobby_view.dart';
import '../shared/services/temporary_room_service.dart';
import '../shared/widgets/room_lifecycle_listener.dart';
import 'antakshari_models.dart';
import 'antakshari_provider.dart';

class AntakshariLobbyScreen extends ConsumerStatefulWidget {
  const AntakshariLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<AntakshariLobbyScreen> createState() =>
      _AntakshariLobbyScreenState();
}

class _AntakshariLobbyScreenState
    extends ConsumerState<AntakshariLobbyScreen> {
  AntakshariGameMode _mode = AntakshariGameMode.standard;
  int _maxPlayers = 12;
  int _turnTimer = 30;
  int _roundLimit = 5;
  bool _creating = false;
  bool _spectatorsEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(antakshariProvider(widget.familyId).notifier).joinGame(joinId);
      }
    });
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier = ref.read(antakshariProvider(widget.familyId).notifier);
    await notifier.createGame(
      mode: _mode,
      maxPlayers: _maxPlayers,
      turnTimerSeconds: _turnTimer,
      roundLimit: _mode == AntakshariGameMode.roundLimited
          ? _roundLimit
          : null,
    );
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
              'Up to ${_maxPlayers - 1} family members can join. Turn order is randomized when the host starts the game.',
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
    final state = ref.watch(antakshariProvider(widget.familyId));
    final notifier = ref.read(antakshariProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    // Auto-navigate to game screen when game starts
    ref.listen<AntakshariState>(antakshariProvider(widget.familyId),
        (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/antakshari/game/${next.game!.id}',
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
                'Antakshari',
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
                final maxP = state.game?.maxPlayers ?? 12;
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.antakshari,
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
              onRetry: _createGame,
            )
          : hasGame
              ? _lobbyView(state, notifier, isHost)
              : _setupView(state),
    );
  }

  Widget _setupView(AntakshariState state) {
    return LobbySetupScreen(
      gameId: 'antakshari',
      title: 'Antakshari',
      tagline: 'Sing, connect the letters, keep the chain alive',
      facts: [
        LobbyFact(icon: Icons.groups_outlined, label: 'Up to $_maxPlayers'),
        LobbyFact(
            icon: Icons.timer_outlined, label: '$_turnTimer${_mode == AntakshariGameMode.roundLimited ? 's · $_roundLimit rounds' : 's turns'}'),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySection(
            label: 'Game Mode',
            child: LobbyChoiceGrid<AntakshariGameMode>(
              options: [
                LobbyOption(
                  value: AntakshariGameMode.standard,
                  label: 'Standard',
                  icon: Icons.person_outline,
                  caption: 'Last player standing wins',
                ),
                LobbyOption(
                  value: AntakshariGameMode.roundLimited,
                  label: 'Round Limited',
                  icon: Icons.groups_outlined,
                  caption: 'Survivors after N rounds win jointly',
                ),
              ],
              selected: _mode,
              onSelect: (m) => setState(() => _mode = m),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Max Players',
            child: LobbyNumberRow(
              numbers: const [6, 8, 12, 16, 20],
              selected: _maxPlayers,
              onSelect: (n) => setState(() => _maxPlayers = n),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySliderRow(
            label: 'Turn Timer',
            valueLabel: '$_turnTimer s',
            value: _turnTimer,
            min: 15,
            max: 60,
            divisions: 9,
            onChanged: (v) => setState(() => _turnTimer = v),
          ),
          if (_mode == AntakshariGameMode.roundLimited) ...[
            const SizedBox(height: KinrelSpacing.sm),
            LobbySliderRow(
              label: 'Round Limit',
              valueLabel: '$_roundLimit rounds',
              value: _roundLimit,
              min: 3,
              max: 10,
              divisions: 7,
              onChanged: (v) => setState(() => _roundLimit = v),
            ),
          ],
        ],
      ),
      rules: [
        const LobbyRule('Players take turns singing a song line via voice/video call.'),
        const LobbyRule('Your song must start with the last letter of the previous player\'s song.'),
        const LobbyRule('After singing, type the letter your song ended on.'),
        const LobbyRule('Others can Challenge — 3+ challenges in 10s = you\'re out.'),
        LobbyRule('Don\'t sing in $_turnTimer s = eliminated.'),
      ],
      rulesFootnote: _mode == AntakshariGameMode.standard
          ? 'Standard: last player standing wins.'
          : 'Round-limited: all survivors after $_roundLimit rounds win jointly.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Up to ${_maxPlayers - 1} family members can join',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(
    AntakshariState state,
    AntakshariNotifier notifier,
    bool isHost,
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
      gameTable: 'antakshari_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle: '${game.gameMode.label} · ${game.turnTimerSeconds}s/turn'
          '${game.roundLimit != null ? ' · ${game.roundLimit} rounds' : ''}',
    );

    return RoomLifecycleListener(
          gameTable: 'antakshari_games',
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
                  gameType: GameType.antakshari,
                  gameId: game.id,
                  roomCode: code,
                  currentPlayerIds: state.players
                      .map((p) => p.userId)
                      .whereType<String>()
                      .toSet(),
                  maxPlayers: game.maxPlayers,
                  currentPlayers: state.players.length,
                );
              }
            : null,
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PendingInvitesSection(gameId: game.id),
          ],
        ),
    ),
    );
  }
}
