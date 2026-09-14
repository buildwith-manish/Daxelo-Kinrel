// lib/features/games/redlight/redlight_lobby_screen.dart
//
// Freeze & Dash — Lobby / Setup screen.
// Route: /family/$familyId/freeze-dash/lobby
//
// v2 (premium lobby system): setup phase renders the shared
// LobbySetupScreen — compact hero, visible caller/map/weather/mode
// settings, spectator toggle, collapsible How to Play, pinned
// Create Game CTA. Waiting-room phase still renders TemporaryLobbyView.

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
import 'redlight_models.dart';
import 'redlight_provider.dart';

class RedlightLobbyScreen extends ConsumerStatefulWidget {
  const RedlightLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<RedlightLobbyScreen> createState() =>
      _RedlightLobbyScreenState();
}

class _RedlightLobbyScreenState extends ConsumerState<RedlightLobbyScreen> {
  CallerCharacter _caller = CallerCharacter.grandma;
  MapTheme _mapTheme = MapTheme.forest;
  WeatherModifier? _weather;
  bool _teamMode = false;
  bool _eliminationMode = false;
  bool _creating = false;
  bool _spectatorsEnabled = true;

  @override
  void initState() {
    super.initState();
    // If a roundId was passed via query (join flow), auto-join.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(redlightProvider(widget.familyId).notifier).joinRound(joinId);
      }
    });
  }

  /// When the host presses "Create Game", create the round and STAY on
  /// the lobby screen — the host needs to see the share code and wait
  /// for players to join. Don't push to the game screen yet.
  Future<void> _createRound() async {
    setState(() => _creating = true);
    final notifier = ref.read(redlightProvider(widget.familyId).notifier);
    await notifier.createRound(
      callerCharacter: _caller,
      mapTheme: _mapTheme,
      weatherModifier: _weather,
      teamMode: _teamMode,
      eliminationMode: _eliminationMode,
    );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _shareCode(String? roundId) async {
    if (roundId == null) return;
    // Show a 6-char code (first 6 chars of the roundId)
    final code = roundId.replaceAll('-', '').substring(0, 6).toUpperCase();
    GameMotionTokens.tap();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg)),
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
              'Family members can join from the Games Hub.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
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
    final state = ref.watch(redlightProvider(widget.familyId));
    final notifier = ref.read(redlightProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost =
        state.round?.hostUserId == myId || state.round == null;
    final canStart =
        state.round == null ? true : (isHost && state.players.length >= 3);

    // Auto-navigate to the game screen once the countdown or active
    // phase begins (host pressed Start, or we joined a running game).
    ref.listen<RedlightState>(redlightProvider(widget.familyId),
        (previous, next) {
      final shouldNavigate = next.isCountdown ||
          next.isActive ||
          next.phase != RedlightPhase.waiting ||
          next.countdownSeconds > 0;
      final wasNavigating = previous != null &&
          (previous.isCountdown ||
              previous.isActive ||
              previous.phase != RedlightPhase.waiting ||
              previous.countdownSeconds > 0);
      final roundId = next.round?.id;
      if (shouldNavigate && !wasNavigating && roundId != null && mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/freeze-dash/game/$roundId',
        );
      }
    });

    final hasRound = state.round != null;

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
        title: hasRound
            ? Text(
                'Freeze & Dash',
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
          if (hasRound && isHost)
            IconButton(
              tooltip: 'Invite family member',
              icon: const Icon(Icons.person_add_outlined),
              onPressed: () {
                final code = state.round!.id.replaceAll('-', '').substring(0, 6).toUpperCase();
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.redlight,
                  gameId: state.round!.id,
                  roomCode: code,
                  currentPlayerIds: state.players.map((p) => p.userId).whereType<String>().toSet(),
                  maxPlayers: 20,
                  currentPlayers: state.players.length,
                );
              },
            ),
          if (hasRound)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _shareCode(state.round?.id),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : state.error != null && !hasRound
          ? DKErrorState(
              message: state.error!,
              // Closed room → the button creates a NEW room (per spec the
              // closed one is deleted and must never reappear).
              actionLabel:
                  state.error == kRoomClosedMessage ? 'Create New Room' : null,
              icon: state.error == kRoomClosedMessage
                  ? Icons.meeting_room_rounded
                  : null,
              onRetry: () {
                notifier.createRound(
                  callerCharacter: _caller,
                  mapTheme: _mapTheme,
                  weatherModifier: _weather,
                  teamMode: _teamMode,
                  eliminationMode: _eliminationMode,
                );
              },
            )
          : hasRound
              ? _lobbyView(state, notifier, isHost, canStart)
              : _setupView(state),
    );
  }

  /// Pre-game setup form — caller, map, weather, modes + "Create Game".
  Widget _setupView(RedlightState state) {
    return LobbySetupScreen(
      gameId: 'freeze-dash',
      title: 'Freeze & Dash',
      tagline: 'Sprint when they look away, freeze when they turn',
      facts: [
        const LobbyFact(icon: Icons.group_outlined, label: '3–20 players'),
        LobbyFact(icon: Icons.bolt_outlined, label: _teamMode ? 'Team race' : 'Solo race'),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySection(
            label: 'Caller Character',
            child: LobbyChoiceGrid<CallerCharacter>(
              options: [
                for (final c in CallerCharacter.values)
                  LobbyOption(value: c, label: c.label, emoji: c.emoji),
              ],
              selected: _caller,
              onSelect: (c) => setState(() => _caller = c),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Map Theme',
            child: LobbyChoiceGrid<MapTheme>(
              options: [
                for (final m in MapTheme.values)
                  LobbyOption(value: m, label: m.label, emoji: m.emoji),
              ],
              selected: _mapTheme,
              onSelect: (m) => setState(() => _mapTheme = m),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Weather Modifier',
            child: LobbyChoiceGrid<WeatherModifier?>(
              options: [
                const LobbyOption(value: null, label: 'None', emoji: '☀️'),
                for (final w in WeatherModifier.values)
                  LobbyOption(value: w, label: w.label, emoji: w.emoji),
              ],
              selected: _weather,
              onSelect: (w) => setState(() => _weather = w),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Game Modes',
            child: Column(
              children: [
                LobbySwitchRow(
                  icon: Icons.flag_outlined,
                  label: 'Team Mode',
                  caption: 'Two teams compete — first team with all members at 100% wins.',
                  value: _teamMode,
                  onChanged: (v) => setState(() => _teamMode = v),
                ),
                const SizedBox(height: KinrelSpacing.sm),
                LobbySwitchRow(
                  icon: Icons.person_off_outlined,
                  label: 'Elimination Mode',
                  caption: 'Caught = eliminated. Default is knockback (-10% progress).',
                  value: _eliminationMode,
                  onChanged: (v) => setState(() => _eliminationMode = v),
                ),
              ],
            ),
          ),
        ],
      ),
      rules: const [
        LobbyRule('Dash forward while the caller is looking away.'),
        LobbyRule('FREEZE the instant the caller turns around.'),
        LobbyRule('Caught moving = knockback (-10% progress).'),
        LobbyRule('First player to reach 100% wins the race.'),
      ],
      rulesFootnote: _teamMode
          ? 'Team mode: first team with ALL members at 100% wins.'
          : (_eliminationMode
              ? 'Elimination: caught players are out until the next round.'
              : null),
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'The caller is played by the game — everyone races live',
      ctaLoading: _creating,
      onCtaPressed: _createRound,
    );
  }

  /// Lobby view — shown after the round is created. Displays the share
  /// code prominently, the player list, and the Start button.
  Widget _lobbyView(
    RedlightState state,
    RedlightNotifier notifier,
    bool isHost,
    bool canStart,
  ) {
    final round = state.round!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    // Map provider state → TemporaryLobbyConfig
    final lobbyStatus = round.isActive || round.isCountdown
        ? TemporaryLobbyStatus.starting
        : round.isFinished
            ? TemporaryLobbyStatus.finished
            : TemporaryLobbyStatus.waiting;

    final lobbyPlayers = state.players
        .map((p) => TemporaryLobbyPlayer(
              userId: p.userId,
              userName: p.userName,
              isReady: p.isReady,
              isHost: p.userId == round.hostUserId,
              joinedAt: p.joinedAt,
            ))
        .toList();

    final subtitle = StringBuffer()
      ..write(round.callerCharacter.label);
    if (round.teamMode) subtitle.write(' · Teams');
    if (round.eliminationMode) subtitle.write(' · Elimination');

    final config = TemporaryLobbyConfig(
      gameTable: 'redlight_rounds',
      gameId: round.id,
      familyId: widget.familyId,
      hostUserId: round.hostUserId,
      players: lobbyPlayers,
      maxPlayers: 20,
      status: lobbyStatus,
      subtitle: subtitle.toString(),
    );

    return RoomLifecycleListener(
          gameTable: 'redlight_rounds',
          gameId: round.id,
          familyId: widget.familyId,
          isHost: (round.hostUserId == myId),
          child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => notifier.toggleReady(isReady),
        onStartMatch: () async => notifier.startGame(),
        onCancelRoom: () => notifier.leaveRound(),
        onInviteFamily: isHost
            ? () {
                final code = round.id
                    .replaceAll('-', '')
                    .substring(0, 6)
                    .toUpperCase();
                GameMotionTokens.tap();
                InviteFamilySheet.show(
                  context,
                  familyId: widget.familyId,
                  gameType: GameType.redlight,
                  gameId: round.id,
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
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.isCountdown) _countdownBanner(state.countdownSeconds),
            PendingInvitesSection(gameId: round.id),
            const SizedBox(height: KinrelSpacing.md),
            LobbyChatPanel(
              gameTable: 'redlight_rounds',
              gameId: round.id,
              familyId: widget.familyId,
            ),
          ],
        ),
    ),
    );
  }

  Widget _countdownBanner(int seconds) {
    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.lg),
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      decoration: BoxDecoration(
        color: KinrelColors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.orange),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Starting in $seconds…',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: KinrelColors.orange,
            ),
          ),
        ],
      ),
    );
  }
}
