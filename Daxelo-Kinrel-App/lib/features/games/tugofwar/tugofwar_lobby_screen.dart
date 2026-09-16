// lib/features/games/tugofwar/tugofwar_lobby_screen.dart
//
// Tug of War — lobby: room setup + team assembly.
//
// Setup phase renders the shared LobbySetupScreen (room name, match length,
// room size, team assignment mode, spectators, How to Play). Waiting-room
// phase renders TemporaryLobbyView with a TeamBoard footer: players pick
// sides, the host can auto-balance or shuffle, and uneven teams trigger a
// confirmation before the match starts.

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
import '../shared/widgets/room_lifecycle_listener.dart';
import '../shared/services/temporary_room_service.dart'
    show kRoomClosedMessage;
import '../shared/widgets/temporary_lobby_view.dart';
import 'tugofwar_models.dart';
import 'tugofwar_provider.dart';

class TugOfWarLobbyScreen extends ConsumerStatefulWidget {
  const TugOfWarLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<TugOfWarLobbyScreen> createState() =>
      _TugOfWarLobbyScreenState();
}

class _TugOfWarLobbyScreenState extends ConsumerState<TugOfWarLobbyScreen> {
  final _roomNameController = TextEditingController();

  int _durationSec = 60;
  int _maxPlayers = 6;
  TugOfWarTeamMode _teamMode = TugOfWarTeamMode.auto;
  bool _spectatorsEnabled = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final joinId = GoRouterState.of(context).uri.queryParameters['join'];
      if (joinId != null && joinId.isNotEmpty) {
        ref.read(tugOfWarProvider(widget.familyId).notifier).joinGame(joinId);
      }
    });
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier = ref.read(tugOfWarProvider(widget.familyId).notifier);
    await notifier.createGame(
      matchDurationSec: _durationSec,
      maxPlayers: _maxPlayers,
      teamMode: _teamMode,
      roomName: _roomNameController.text,
      spectatorsEnabled: _spectatorsEnabled,
    );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final notifier = ref.read(tugOfWarProvider(widget.familyId).notifier);
    final result = await notifier.startMatch();
    if (!mounted || result == null) return;
    if (result == 'uneven') {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: KinrelColors.darkElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
          ),
          title: Text(
            'Teams are uneven. Continue?',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontWeight: FontWeight.w600,
              color: KinrelColors.textWhite,
            ),
          ),
          content: Text(
            'Strength is measured per player, so uneven teams still get a '
            'fair fight — but equal sides are more fun!',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textDim,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Even Them Out'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Start Anyway'),
            ),
          ],
        ),
      );
      if (proceed == true && mounted) {
        await notifier.startMatch(force: true);
      }
      return;
    }
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
    final state = ref.watch(tugOfWarProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    ref.listen<TugOfWarState>(tugOfWarProvider(widget.familyId),
        (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/tug-of-war/game/${next.game!.id}',
        );
      }
    });

    final hasGame = state.game != null;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // Route-level onExit guard (app_router.dart) intercepts while a
          // room is active and shows the confirmation dialog first.
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
                    : 'Tug of War',
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

  void _openInviteSheet(TugOfWarState state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.tugOfWar,
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
              'Up to ${(_maxPlayersFromState() - 1)} family members can join. '
              'Tug together, giggle together!',
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

  int _maxPlayersFromState() =>
      ref.read(tugOfWarProvider(widget.familyId)).game?.maxPlayers ??
      _maxPlayers;

  // ── Setup phase ───────────────────────────────────────────────────

  Widget _setupView(TugOfWarState state) {
    return LobbySetupScreen(
      gameId: 'tug-of-war',
      title: 'Tug of War',
      tagline: 'Two teams, one rope — pure family power',
      facts: [
        LobbyFact(
          icon: Icons.groups_2_outlined,
          label: 'Up to $_maxPlayers players',
        ),
        LobbyFact(
          icon: Icons.timer_outlined,
          label: _durationLabel(_durationSec),
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
            label: 'Match Length',
            child: LobbyChoiceGrid<int>(
              selected: _durationSec,
              onSelect: (v) => setState(() => _durationSec = v),
              options: const [
                LobbyOption(value: 30, label: '30s'),
                LobbyOption(value: 60, label: '60s'),
                LobbyOption(value: 90, label: '90s'),
                LobbyOption(value: 0, label: '∞', caption: 'Unlimited'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Room Size',
            caption: 'Maximum players — 1v1 up to 10v10',
            child: LobbyNumberRow(
              numbers: const [2, 4, 6, 10, 20],
              selected: _maxPlayers,
              onSelect: (n) => setState(() => _maxPlayers = n),
              suffix: ' players',
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Team Assignment',
            child: LobbyChoiceGrid<TugOfWarTeamMode>(
              selected: _teamMode,
              onSelect: (v) => setState(() => _teamMode = v),
              options: const [
                LobbyOption(
                  value: TugOfWarTeamMode.auto,
                  label: 'Balanced',
                  caption: 'Auto-balances as players join',
                ),
                LobbyOption(
                  value: TugOfWarTeamMode.manual,
                  label: 'Pick Your Own',
                  caption: 'Everyone chooses a side',
                ),
                LobbyOption(
                  value: TugOfWarTeamMode.random,
                  label: 'Random',
                  caption: 'Host shuffles the teams',
                ),
              ],
            ),
          ),
        ],
      ),
      rules: const [
        LobbyRule('Tap the giant PULL button as fast as you can — every tap '
            'adds force to your team.'),
        LobbyRule('Pull the center flag past your opponent\'s victory line '
            'to win instantly.'),
        LobbyRule('Strength is measured per player: total taps ÷ team size. '
            'A small team of sprinters can beat a big team of nappers!'),
        LobbyRule('When time runs out, the team with the higher average '
            'takes the win.'),
        LobbyRule('If a whole team leaves, the other side wins by walkover.'),
        LobbyRule('Spectators can\'t pull — but they can cheer with '
            'emoji reactions!'),
      ],
      rulesFootnote: 'Fair play: taps faster than 15/sec are ignored.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Invite family members, pick teams, then pull!',
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
        hintText: 'e.g. Sunday Showdown',
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

  String _durationLabel(int sec) =>
      sec == 0 ? 'Unlimited' : '$sec sec rounds';

  // ── Waiting room phase ────────────────────────────────────────────

  Widget _lobbyView(TugOfWarState state, bool isHost) {
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
      gameTable: 'tugofwar_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle: '${_durationLabel(game.matchDurationSec)} · ${game.teamMode.label}',
    );

    return RoomLifecycleListener(
      gameTable: 'tugofwar_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) =>
            ref.read(tugOfWarProvider(widget.familyId).notifier).toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () =>
            ref.read(tugOfWarProvider(widget.familyId).notifier).leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TugTeamBoard(
              state: state,
              myUserId: myId,
              isHost: isHost,
              onJoinTeam: (team) => ref
                  .read(tugOfWarProvider(widget.familyId).notifier)
                  .setTeam(team),
              onAutoBalance: () => ref
                  .read(tugOfWarProvider(widget.familyId).notifier)
                  .assignTeams(TugOfWarTeamMode.auto),
              onShuffle: () => ref
                  .read(tugOfWarProvider(widget.familyId).notifier)
                  .assignTeams(TugOfWarTeamMode.random),
            ),
            const SizedBox(height: KinrelSpacing.md),
            PendingInvitesSection(gameId: game.id),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Team board — the heart of the tug of war lobby
// ────────────────────────────────────────────────────────────────────

class TugTeamBoard extends StatelessWidget {
  const TugTeamBoard({
    super.key,
    required this.state,
    required this.myUserId,
    required this.isHost,
    required this.onJoinTeam,
    required this.onAutoBalance,
    required this.onShuffle,
  });

  final TugOfWarState state;
  final String? myUserId;
  final bool isHost;
  final ValueChanged<TugTeam> onJoinTeam;
  final VoidCallback onAutoBalance;
  final VoidCallback onShuffle;

  static const Color teamAColor = KinrelColors.orange;
  static const Color teamBColor = KinrelColors.blue;

  @override
  Widget build(BuildContext context) {
    final game = state.game;
    if (game == null) return const SizedBox.shrink();

    final rosterA = state.teamRoster(TugTeam.a);
    final rosterB = state.teamRoster(TugTeam.b);
    final unassigned =
        state.players.where((p) => p.team == null).toList();
    final myTeam = state.teamFor(myUserId);
    final canPick = game.teamMode != TugOfWarTeamMode.auto || myTeam == null;
    final uneven = rosterA.length != rosterB.length;

    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.md),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined,
                  size: 16, color: KinrelColors.textDim),
              const SizedBox(width: 6),
              Text(
                'TEAMS',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: KinrelColors.textDim,
                ),
              ),
              const Spacer(),
              if (uneven)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: KinrelColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: KinrelColors.warning.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    'UNEVEN ${rosterA.length}v${rosterB.length}',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.warning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: KinrelSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TeamColumn(
                  team: TugTeam.a,
                  color: teamAColor,
                  players: rosterA,
                  myUserId: myUserId,
                  canJoin: canPick && myTeam != TugTeam.a,
                  onJoin: () => onJoinTeam(TugTeam.a),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    Text(
                      'VS',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _TeamColumn(
                  team: TugTeam.b,
                  color: teamBColor,
                  players: rosterB,
                  myUserId: myUserId,
                  canJoin: canPick && myTeam != TugTeam.b,
                  onJoin: () => onJoinTeam(TugTeam.b),
                ),
              ),
            ],
          ),
          if (unassigned.isNotEmpty) ...[
            const SizedBox(height: KinrelSpacing.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in unassigned)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: KinrelColors.darkElevated,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: KinrelColors.border.withValues(alpha: 0.7)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          p.userId == game.hostUserId
                              ? Icons.star
                              : Icons.person_outline,
                          size: 12,
                          color: KinrelColors.textDim,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          p.userName,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            color: KinrelColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (isHost && game.isWaiting) ...[
            const SizedBox(height: KinrelSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _HostToolButton(
                    icon: Icons.balance_outlined,
                    label: 'Auto-Balance',
                    onTap: onAutoBalance,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HostToolButton(
                    icon: Icons.shuffle,
                    label: 'Shuffle',
                    onTap: onShuffle,
                  ),
                ),
              ],
            ),
          ],
          if (game.teamMode == TugOfWarTeamMode.auto && unassigned.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: KinrelSpacing.sm),
              child: Text(
                'Balanced mode assigns new joiners automatically.',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: KinrelColors.textDim.withValues(alpha: 0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.team,
    required this.color,
    required this.players,
    required this.myUserId,
    required this.canJoin,
    required this.onJoin,
  });

  final TugTeam team;
  final Color color;
  final List<TugOfWarPlayer> players;
  final String? myUserId;
  final bool canJoin;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final shown = players.take(5).toList();
    final overflow = players.length - shown.length;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  team.shortLabel,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (players.isEmpty)
            Text(
              'No one yet',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                color: KinrelColors.textDim.withValues(alpha: 0.6),
              ),
            )
          else
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final p in shown)
                  _TeamAvatar(
                    name: p.userName,
                    color: color,
                    isMe: p.userId == myUserId,
                    isReady: p.isReady,
                  ),
                if (overflow > 0)
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.darkElevated,
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '+$overflow',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            '${players.length} player${players.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              color: KinrelColors.textDim,
            ),
          ),
          if (canJoin) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                GameMotionTokens.tap();
                onJoin();
              },
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(KinrelRadius.sm),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'JOIN',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TeamAvatar extends StatelessWidget {
  const _TeamAvatar({
    required this.name,
    required this.color,
    required this.isMe,
    required this.isReady,
  });

  final String name;
  final Color color;
  final bool isMe;
  final bool isReady;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join();
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.5)],
        ),
        border: Border.all(
          color: isMe ? Colors.white : color.withValues(alpha: 0.6),
          width: isMe ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              initials.toUpperCase(),
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          if (isReady)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: KinrelColors.success,
                  border: Border.all(
                      color: KinrelColors.darkCard, width: 1.5),
                ),
                child: const Icon(Icons.check,
                    size: 8, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _HostToolButton extends StatelessWidget {
  const _HostToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        GameMotionTokens.tap();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: KinrelColors.darkElevated,
          borderRadius: BorderRadius.circular(KinrelRadius.sm),
          border: Border.all(color: KinrelColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: KinrelColors.textDim),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
