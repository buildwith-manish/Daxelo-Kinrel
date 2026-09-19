// lib/features/games/night_falls/night_falls_lobby_screen.dart
//
// Night Falls — Create Room lobby.
// Route: /family/$familyId/night-falls/lobby
//
// Mirrors the Impostor + Secret Heist lobby pattern: a setup screen
// lets the host configure match parameters (max players, game pace),
// then a waiting room shows the live player roster and lets the host
// start the match once ≥5 players have joined.

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
import 'night_falls_engine.dart';
import 'night_falls_provider.dart';

/// Indigo accent — evokes the "night" theme.
const Color _kNightFallsAccent = Color(0xFF6366F1);

class _GamePace {
  const _GamePace({
    required this.id,
    required this.label,
    required this.caption,
    required this.nightSeconds,
    required this.daySeconds,
    required this.voteSeconds,
  });
  final String id;
  final String label;
  final String caption;
  final int nightSeconds;
  final int daySeconds;
  final int voteSeconds;

  static const quick = _GamePace(
    id: 'quick',
    label: 'Quick',
    caption: '20s · 30s · 20s',
    nightSeconds: 20,
    daySeconds: 30,
    voteSeconds: 20,
  );
  static const standard = _GamePace(
    id: 'standard',
    label: 'Standard',
    caption: '30s · 60s · 30s',
    nightSeconds: 30,
    daySeconds: 60,
    voteSeconds: 30,
  );
  static const relaxed = _GamePace(
    id: 'relaxed',
    label: 'Relaxed',
    caption: '45s · 90s · 45s',
    nightSeconds: 45,
    daySeconds: 90,
    voteSeconds: 45,
  );
  static const all = [quick, standard, relaxed];

  static _GamePace byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return standard;
  }
}

class NightFallsLobbyScreen extends ConsumerStatefulWidget {
  const NightFallsLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<NightFallsLobbyScreen> createState() =>
      _NightFallsLobbyScreenState();
}

class _NightFallsLobbyScreenState extends ConsumerState<NightFallsLobbyScreen> {
  final _roomNameController = TextEditingController();
  int _maxPlayers = 8;
  _GamePace _pace = _GamePace.standard;
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
            .read(nightFallsProvider(widget.familyId).notifier)
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
    await ref.read(nightFallsProvider(widget.familyId).notifier).createGame(
          maxPlayers: _maxPlayers,
          nightSeconds: _pace.nightSeconds,
          daySeconds: _pace.daySeconds,
          voteSeconds: _pace.voteSeconds,
          roomName: _roomNameController.text,
          spectatorsEnabled: _spectatorsEnabled,
        );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final result = await ref
        .read(nightFallsProvider(widget.familyId).notifier)
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
    final state = ref.watch(nightFallsProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    ref.listen(nightFallsProvider(widget.familyId), (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/night-falls/game/${next.game!.id}',
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
                    : 'Night Falls',
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
              child: CircularProgressIndicator(color: _kNightFallsAccent))
          : state.error != null && !hasGame
              ? DKErrorState(message: state.error!, onRetry: _createGame)
              : hasGame
                  ? _lobbyView(state, isHost)
                  : _setupView(),
    );
  }

  void _openInviteSheet(NightFallsState state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.nightFalls,
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
                    color: _kNightFallsAccent,
                    letterSpacing: 6)),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'Up to ${_maxPlayers - 1} family members. Survive the night!',
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
    final dist = NightFallsEngine.roleDistribution(_maxPlayers);
    return LobbySetupScreen(
      gameId: 'night-falls',
      title: 'Night Falls',
      tagline: 'Classic Werewolf — survive the night, find the wolves',
      facts: [
        LobbyFact(icon: Icons.groups_2_outlined, label: '5–12 players'),
        LobbyFact(
            icon: Icons.nights_stay_outlined,
            label: '${dist[NightFallsRole.werewolf]} wolves'),
        LobbyFact(icon: Icons.timer_outlined, label: _pace.caption),
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
                hintText: 'e.g. Family Werewolf Night',
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
                      const BorderSide(color: _kNightFallsAccent, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Max Players',
            caption: 'Role distribution updates with player count.',
            child: LobbyChoiceGrid<int>(
              selected: _maxPlayers,
              onSelect: (v) => setState(() => _maxPlayers = v),
              options: const [
                LobbyOption(value: 5, label: '5', caption: '2 wolves'),
                LobbyOption(value: 8, label: '8', caption: '2 wolves'),
                LobbyOption(value: 10, label: '10', caption: '3 wolves'),
                LobbyOption(value: 12, label: '12', caption: '3 wolves'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Game Pace',
            caption: 'Night · Day · Vote timers.',
            child: LobbyChoiceGrid<String>(
              selected: _pace.id,
              onSelect: (v) => setState(() => _pace = _GamePace.byId(v)),
              options: [
                for (final p in _GamePace.all)
                  LobbyOption(value: p.id, label: p.label, caption: p.caption),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          // Role distribution preview
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(
                  color: _kNightFallsAccent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ROLE DISTRIBUTION ($_maxPlayers players)',
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: KinrelColors.textDim,
                        letterSpacing: 1.2)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final role in NightFallsRole.values)
                      if (dist[role]! > 0)
                        _RoleChip(
                            role: role, count: dist[role]!),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      rules: [
        LobbyRule('Each player is secretly assigned a role: Werewolf, Seer, Doctor, Hunter, or Villager.'),
        LobbyRule('🌙 Night: Werewolves choose a victim. The Seer investigates one player. The Doctor protects one player.'),
        LobbyRule('☀️ Day: The village learns who died (if anyone) and debates who the wolves might be.'),
        LobbyRule('🗳️ Vote: Everyone votes to eliminate one suspect. The eliminated player\'s role is revealed.'),
        LobbyRule('🎯 Hunter: If voted out, the Hunter takes one player down with them.'),
        LobbyRule('🐺 Werewolves win if they equal or outnumber the villagers. 🏘️ Village wins if all werewolves are eliminated.'),
      ],
      rulesFootnote:
          '2 wolves for 5–8 players · 3 wolves for 9–12 players. Spectators can cheer with emoji reactions!',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Invite family members, then survive the night!',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(NightFallsState state, bool isHost) {
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
      gameTable: 'night_falls_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle:
          '${game.maxPlayers} max · ${game.nightSeconds}s night · ${game.daySeconds}s day · ${game.voteSeconds}s vote',
    );
    return RoomLifecycleListener(
      gameTable: 'night_falls_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => ref
            .read(nightFallsProvider(widget.familyId).notifier)
            .toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => ref
            .read(nightFallsProvider(widget.familyId).notifier)
            .leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role, required this.count});
  final NightFallsRole role;
  final int count;

  @override
  Widget build(BuildContext context) {
    final isWolf = role.isWolf;
    final color = isWolf
        ? KinrelColors.error
        : role == NightFallsRole.seer
            ? const Color(0xFFA855F7)
            : role == NightFallsRole.doctor
                ? KinrelColors.success
                : role == NightFallsRole.hunter
                    ? KinrelColors.amber
                    : KinrelColors.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(role.glyph, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text(role.label,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textWhite)),
          const SizedBox(width: 4),
          Text('×$count',
              style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }
}
