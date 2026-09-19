// lib/features/games/code_clues/code_clues_lobby_screen.dart
//
// Code Clues — Create Room lobby.
// Route: /family/$familyId/code-clues/lobby

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
import 'code_clues_engine.dart';
import 'code_clues_models.dart';
import 'code_clues_provider.dart';

/// Team color tokens for Code Clues (Codenames-style).
/// Team 1 = red (KinrelColors.orange), Team 2 = blue.
Color codeCluesTeamColor(int team) =>
    team == 2 ? const Color(0xFF3B82F6) : KinrelColors.orange;

class CodeCluesLobbyScreen extends ConsumerStatefulWidget {
  const CodeCluesLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<CodeCluesLobbyScreen> createState() =>
      _CodeCluesLobbyScreenState();
}

class _CodeCluesLobbyScreenState
    extends ConsumerState<CodeCluesLobbyScreen> {
  final _roomNameController = TextEditingController();
  int _maxPlayers = 8;
  int _clueSeconds = kCodeCluesDefaultClueSeconds;
  int _guessSeconds = kCodeCluesDefaultGuessSeconds;
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
            .read(codeCluesProvider(widget.familyId).notifier)
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
    await ref.read(codeCluesProvider(widget.familyId).notifier).createGame(
          maxPlayers: _maxPlayers,
          clueSeconds: _clueSeconds,
          guessSeconds: _guessSeconds,
          roomName: _roomNameController.text,
          spectatorsEnabled: _spectatorsEnabled,
        );
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _startMatch() async {
    final result = await ref
        .read(codeCluesProvider(widget.familyId).notifier)
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
    final state = ref.watch(codeCluesProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;

    ref.listen(codeCluesProvider(widget.familyId), (previous, next) {
      if (next.isInProgress &&
          !(previous?.isInProgress ?? false) &&
          next.game?.id != null &&
          mounted) {
        context.pushReplacement(
          '/family/${widget.familyId}/code-clues/game/${next.game!.id}',
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
                    : 'Code Clues',
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
                  CircularProgressIndicator(color: KinrelColors.orange))
          : state.error != null && !hasGame
              ? DKErrorState(message: state.error!, onRetry: _createGame)
              : hasGame
                  ? _lobbyView(state, isHost)
                  : _setupView(),
    );
  }

  void _openInviteSheet(CodeCluesState_ state) {
    final game = state.game;
    if (game == null) return;
    GameMotionTokens.tap();
    InviteFamilySheet.show(
      context,
      familyId: widget.familyId,
      gameType: GameType.codeClues,
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
                    color: KinrelColors.orange,
                    letterSpacing: 6)),
            const SizedBox(height: KinrelSpacing.md),
            Text(
              'Up to ${_maxPlayers - 1} members. Find your team\'s words first!',
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
      gameId: 'code-clues',
      title: 'Code Clues',
      tagline: 'Codenames-style word association — find your team\'s words first',
      facts: [
        LobbyFact(icon: Icons.groups_2_outlined, label: '4–8 players'),
        LobbyFact(
            icon: Icons.grid_on_outlined, label: '5×5 word grid'),
        LobbyFact(
            icon: Icons.timer_outlined,
            label: '${_clueSeconds}s clue / ${_guessSeconds}s guess'),
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
                hintText: 'e.g. Family Codenames',
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
            label: 'Clue Timer',
            caption: 'How long the Spymaster has to give their clue',
            child: LobbyChoiceGrid<int>(
              selected: _clueSeconds,
              onSelect: (v) => setState(() => _clueSeconds = v),
              options: const [
                LobbyOption(value: 60, label: '60s', caption: 'Brisk'),
                LobbyOption(value: 90, label: '90s', caption: 'Standard'),
                LobbyOption(value: 120, label: '120s', caption: 'Relaxed'),
              ],
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySection(
            label: 'Guess Timer',
            caption: 'How long field agents have to make their guesses',
            child: LobbyChoiceGrid<int>(
              selected: _guessSeconds,
              onSelect: (v) => setState(() => _guessSeconds = v),
              options: const [
                LobbyOption(value: 90, label: '90s', caption: 'Brisk'),
                LobbyOption(value: 120, label: '120s', caption: 'Standard'),
                LobbyOption(value: 180, label: '180s', caption: 'Relaxed'),
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
        ],
      ),
      rules: [
        LobbyRule('Two teams (Red vs Blue). Each picks one Spymaster.'),
        LobbyRule('A 5×5 grid of 25 words appears: 9 Red, 8 Blue, 7 neutral, 1 assassin.'),
        LobbyRule('The Spymaster gives a one-word clue + a number (how many words it relates to).'),
        LobbyRule('Field agents tap words. Finding your team\'s word keeps the turn going.'),
        LobbyRule('Hitting a neutral or opponent\'s word ends your turn.'),
        LobbyRule(
            'Find all your team\'s words first to win. But hit the assassin — instant loss!',
            highlight: true),
      ],
      rulesFootnote:
          '4–8 players · Spymasters see the full grid, field agents see only words.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: 'Pick your team + Spymaster role, then invite family!',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(CodeCluesState_ state, bool isHost) {
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
      gameTable: 'code_clues_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.maxPlayers,
      status: lobbyStatus,
      subtitle:
          '${game.clueSeconds}s clue · ${game.guessSeconds}s guess · ${state.players.length}/${game.maxPlayers} players',
    );
    return RoomLifecycleListener(
      gameTable: 'code_clues_games',
      gameId: game.id,
      familyId: widget.familyId,
      isHost: game.hostUserId == myId,
      child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => ref
            .read(codeCluesProvider(widget.familyId).notifier)
            .toggleReady(isReady),
        onStartMatch: _startMatch,
        onCancelRoom: () => ref
            .read(codeCluesProvider(widget.familyId).notifier)
            .leaveGame(),
        onInviteFamily: isHost ? () => _openInviteSheet(state) : null,
        footer: _TeamBoard(
          players: state.players,
          myUserId: myId,
          onSetTeam: (team) => ref
              .read(codeCluesProvider(widget.familyId).notifier)
              .setTeam(team),
          onToggleSpymaster: () => ref
              .read(codeCluesProvider(widget.familyId).notifier)
              .toggleSpymaster(),
        ),
      ),
    );
  }
}

/// Team board shown in the lobby's footer dock. Players can switch teams
/// and toggle their Spymaster role before the match starts.
class _TeamBoard extends StatelessWidget {
  const _TeamBoard({
    required this.players,
    required this.myUserId,
    required this.onSetTeam,
    required this.onToggleSpymaster,
  });

  final List<CodeCluesPlayerWire> players;
  final String? myUserId;
  final void Function(int team) onSetTeam;
  final VoidCallback onToggleSpymaster;

  @override
  Widget build(BuildContext context) {
    final team1 = players.where((p) => p.isActive && p.team == 1).toList();
    final team2 = players.where((p) => p.isActive && p.team == 2).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_alt_outlined,
                  size: 14, color: KinrelColors.textDim),
              const SizedBox(width: 6),
              Text('TEAMS',
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: KinrelColors.textDim)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TeamColumn(
                  label: 'Team Red',
                  color: KinrelColors.orange,
                  players: team1,
                  myUserId: myUserId,
                  onJoin: () => onSetTeam(1),
                  onToggleSpymaster: onToggleSpymaster,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TeamColumn(
                  label: 'Team Blue',
                  color: const Color(0xFF3B82F6),
                  players: team2,
                  myUserId: myUserId,
                  onJoin: () => onSetTeam(2),
                  onToggleSpymaster: onToggleSpymaster,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.label,
    required this.color,
    required this.players,
    required this.myUserId,
    required this.onJoin,
    required this.onToggleSpymaster,
  });

  final String label;
  final Color color;
  final List<CodeCluesPlayerWire> players;
  final String? myUserId;
  final VoidCallback onJoin;
  final VoidCallback onToggleSpymaster;

  @override
  Widget build(BuildContext context) {
    final iAmHere = players.any((p) => p.userId == myUserId);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
              Text('${players.length}',
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ],
          ),
          const SizedBox(height: 6),
          if (players.isEmpty)
            Text('No one yet',
                style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 10,
                    color: KinrelColors.textDim))
          else
            for (final p in players)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    if (p.isSpymaster)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.visibility_outlined,
                            size: 10, color: color),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.person_outline,
                            size: 10, color: KinrelColors.textDim),
                      ),
                    Expanded(
                      child: Text(
                        p.userName +
                            (p.userId == myUserId ? ' (you)' : '') +
                            (p.isSpymaster ? ' • Spymaster' : ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 11,
                            fontWeight: p.userId == myUserId
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: p.userId == myUserId
                                ? KinrelColors.textWhite
                                : KinrelColors.textSilver),
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          if (iAmHere)
            SizedBox(
              width: double.infinity,
              child: _MiniButton(
                label: 'Toggle Spymaster',
                color: color,
                onTap: onToggleSpymaster,
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: _MiniButton(
                label: 'Join $label',
                color: color,
                onTap: onJoin,
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(KinrelRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(KinrelRadius.sm),
        onTap: () {
          GameMotionTokens.tap();
          onTap();
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ),
      ),
    );
  }
}
