import '../../../core/widgets/person_avatar.dart';
// lib/features/games/chitmatch/chitmatch_lobby_screen.dart
//
// TripleMatch — Lobby screen.
// Route: /family/$familyId/chitmatch/lobby
//
// Two distinct phases after the game is created:
//   1. `waiting` / `in_progress` / `completed` — uses the shared
//      `TemporaryLobbyView` widget (players / ready / Start prioritized
//      over the room code).
//   2. `setup` (host tapped "Start Setup", players are submitting words)
//      — uses the existing `_wordSubmissionView` so the unique
//      word-submission flow is preserved.
//
// v2 (premium lobby system): setup phase renders the shared
// LobbySetupScreen — compact hero, visible player count + round timer,
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
import '../shared/widgets/lobby_join_handler.dart';
import '../shared/widgets/lobby_kit/lobby_kit.dart';
import '../shared/widgets/temporary_lobby_view.dart';
import '../shared/services/temporary_room_service.dart';
import '../shared/widgets/room_lifecycle_listener.dart';
import 'chitmatch_provider.dart';

class ChitmatchLobbyScreen extends ConsumerStatefulWidget {
  const ChitmatchLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<ChitmatchLobbyScreen> createState() => _ChitmatchLobbyScreenState();
}

class _ChitmatchLobbyScreenState extends ConsumerState<ChitmatchLobbyScreen> {
  int _playerCount = 6;
  int _roundTimer = 20;
  bool _creating = false;
  bool _spectatorsEnabled = true;
  final _wordController = TextEditingController();
  bool _wordSubmitted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      joinRoomWhenReady(
        context: context,
        ref: ref,
        onJoin: (id) =>
            ref.read(chitmatchProvider(widget.familyId).notifier).joinGame(id),
      );
    });
  }

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  Future<void> _createGame() async {
    setState(() => _creating = true);
    final notifier = ref.read(chitmatchProvider(widget.familyId).notifier);
    await notifier.createGame(playerCount: _playerCount, roundTimerSeconds: _roundTimer);
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(KinrelRadius.lg))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(KinrelSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Share this code', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
            const SizedBox(height: KinrelSpacing.md),
            Text(code, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 40, fontWeight: FontWeight.w700, color: KinrelColors.orange, letterSpacing: 6)),
            const SizedBox(height: KinrelSpacing.md),
            Text('${_playerCount - 1} family members can join (4-${_playerCount} total).', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
            const SizedBox(height: KinrelSpacing.lg),
            DKButton(label: 'Done', variant: DKButtonVariant.primary, fullWidth: true, onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
          ],
        ),
      ),
    );
  }

  Future<void> _submitWord() async {
    final word = _wordController.text.trim();
    if (word.isEmpty) return;
    await ref.read(chitmatchProvider(widget.familyId).notifier).submitWord(word);
    setState(() => _wordSubmitted = true);
  }

  Future<void> _startSetup() async {
    await ref.read(chitmatchProvider(widget.familyId).notifier).startSetup();
  }

  Future<void> _dealAndStart() async {
    await ref.read(chitmatchProvider(widget.familyId).notifier).dealAndStartGame();
    final gameId = ref.read(chitmatchProvider(widget.familyId)).game?.id;
    if (gameId != null && mounted) {
      context.pushReplacement('/family/${widget.familyId}/chitmatch/game/$gameId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chitmatchProvider(widget.familyId));
    final notifier = ref.read(chitmatchProvider(widget.familyId).notifier);
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isHost = state.game?.hostUserId == myId || state.game == null;
    final hasGame = state.game != null;
    final allWordsSubmitted = hasGame && state.players.isNotEmpty && state.players.every((p) => p.submittedWord != null && p.submittedWord!.isNotEmpty);

    // Auto-navigate to game screen when game goes in_progress
    ref.listen<ChitmatchState>(chitmatchProvider(widget.familyId), (prev, next) {
      if (next.isInProgress && !(prev?.isInProgress ?? false) && next.game?.id != null && mounted) {
        context.pushReplacement('/family/${widget.familyId}/chitmatch/game/${next.game!.id}');
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
            ? Text('TripleMatch', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))
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
                  gameType: GameType.chitmatch,
                  gameId: state.game!.id,
                  roomCode: code,
                  currentPlayerIds: state.players.map((p) => p.userId).whereType<String>().toSet(),
                  maxPlayers: state.game!.playerCount,
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
              onRetry: () => notifier.createGame(playerCount: _playerCount, roundTimerSeconds: _roundTimer))
          : !hasGame
            ? _setupView(state)
            : state.game!.isWaiting
              ? _lobbyView(state, isHost)
              : state.game!.isSetup
                ? _wordSubmissionView(state, isHost, allWordsSubmitted)
                : _lobbyView(state, isHost),
    );
  }

  Widget _setupView(ChitmatchState state) {
    return LobbySetupScreen(
      gameId: 'chitmatch',
      title: 'TripleMatch',
      tagline: 'Write a word, swap the chits, match three first',
      facts: [
        LobbyFact(icon: Icons.group_outlined, label: '$_playerCount players'),
        LobbyFact(icon: Icons.timer_outlined, label: '$_roundTimer s rounds'),
      ],
      settings: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LobbySection(
            label: 'Number of Players',
            child: LobbyNumberRow(
              numbers: const [4, 6, 8, 10, 12],
              selected: _playerCount,
              onSelect: (n) => setState(() => _playerCount = n),
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          LobbySliderRow(
            label: 'Round Timer',
            valueLabel: '$_roundTimer s',
            value: _roundTimer,
            min: 10,
            max: 60,
            divisions: 10,
            onChanged: (v) => setState(() => _roundTimer = v),
          ),
        ],
      ),
      rules: const [
        LobbyRule('Each player submits a word. 3 chits per word are created.'),
        LobbyRule('All chits are shuffled. Each player gets 3 random chits.'),
        LobbyRule('Each round, everyone selects 1 chit to pass clockwise.'),
        LobbyRule('Passes resolve simultaneously — all at once!'),
        LobbyRule('First to 3 matching chits wins. Joint winners possible!'),
      ],
      rulesFootnote: 'Don\'t respond in $_roundTimer s? Auto-selected for you.',
      spectatorsEnabled: _spectatorsEnabled,
      onSpectatorsChanged: (v) => setState(() => _spectatorsEnabled = v),
      ctaLabel: 'Create Game',
      ctaHint: '${_playerCount - 1} family members can join (4-$_playerCount total)',
      ctaLoading: _creating,
      onCtaPressed: _createGame,
    );
  }

  Widget _lobbyView(ChitmatchState state, bool isHost) {
    final game = state.game!;
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final notifier = ref.read(chitmatchProvider(widget.familyId).notifier);

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
      gameTable: 'chitmatch_games',
      gameId: game.id,
      familyId: widget.familyId,
      hostUserId: game.hostUserId,
      players: lobbyPlayers,
      maxPlayers: game.playerCount,
      status: lobbyStatus,
      subtitle: '${game.playerCount} players · ${game.roundTimerSeconds}s/round',
    );

    return RoomLifecycleListener(
          gameTable: 'chitmatch_games',
          gameId: game.id,
          familyId: widget.familyId,
          isHost: (game.hostUserId == myId),
          child: TemporaryLobbyView(
        config: config,
        myUserId: myId,
        onToggleReady: (isReady) => notifier.toggleReady(isReady),
        // In chitmatch, the host's Start button kicks off the word-submission
        // setup phase rather than jumping straight into gameplay.
        onStartMatch: () => _startSetup(),
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
                  gameType: GameType.chitmatch,
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
    ),
    );
  }

  Widget _wordSubmissionView(ChitmatchState state, bool isHost, bool allWordsSubmitted) {
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        Text('Submit Your Word', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
        const SizedBox(height: 4),
        Text('Choose an animal or object name. 3 chits with this word will be created and shuffled into the game.', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
        const SizedBox(height: KinrelSpacing.lg),
        if (_wordSubmitted || state.myWord != null)
          Container(
            padding: const EdgeInsets.all(KinrelSpacing.lg),
            decoration: BoxDecoration(color: KinrelColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.success, width: 1)),
            child: Row(children: [
              Icon(Icons.check_circle, color: KinrelColors.success, size: 24),
              const SizedBox(width: KinrelSpacing.sm),
              Expanded(child: Text('Your word: "${state.myWord ?? _wordController.text}"', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite, fontWeight: FontWeight.w600))),
            ]),
          )
        else ...[
          TextField(
            controller: _wordController,
            style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 16, color: KinrelColors.textWhite),
            decoration: InputDecoration(
              hintText: 'e.g. Elephant, Tiger, Rocket...',
              hintStyle: TextStyle(color: KinrelColors.textDim),
              filled: true, fillColor: KinrelColors.darkCard,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(KinrelRadius.lg), borderSide: BorderSide(color: KinrelColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(KinrelRadius.lg), borderSide: BorderSide(color: KinrelColors.orange, width: 2)),
            ),
            onSubmitted: (_) => _submitWord(),
          ),
          const SizedBox(height: KinrelSpacing.md),
          DKButton(label: 'Submit Word', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: state.isSubmitting, onPressed: _submitWord),
        ],
        const SizedBox(height: KinrelSpacing.xl),
        // Show how many players have submitted
        Text('WORD SUBMISSIONS', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.2)),
        const SizedBox(height: KinrelSpacing.sm),
        ...state.players.map((p) {
          final submitted = p.submittedWord != null && p.submittedWord!.isNotEmpty;
          return Container(
            margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
            padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
            decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.md), border: Border.all(color: KinrelColors.border)),
            child: Row(children: [
              DKAvatar(initials: PersonAvatar.initialsFor(p.userName)),
              const SizedBox(width: KinrelSpacing.md),
              Expanded(child: Text(p.userId == _myId(state) ? '${p.userName} (You)' : p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textWhite))),
              Icon(submitted ? Icons.check_circle : Icons.hourglass_empty, size: 16, color: submitted ? KinrelColors.success : KinrelColors.textDim),
            ]),
          );
        }),
        const SizedBox(height: KinrelSpacing.xl),
        if (isHost && allWordsSubmitted)
          DKButton(label: 'Deal Chits & Start!', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: state.isResolving, onPressed: _dealAndStart)
        else if (isHost)
          Text('Waiting for all players to submit words...', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim))
        else
          _waitingIndicator(),
      ],
    );
  }

  String? _myId(ChitmatchState state) => ref.read(supabaseProvider)?.auth.currentUser?.id;

  Widget _waitingIndicator() => Container(padding: const EdgeInsets.all(KinrelSpacing.lg), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(KinrelRadius.lg), border: Border.all(color: KinrelColors.border)),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange)),
      const SizedBox(width: KinrelSpacing.sm),
      Text('Waiting for host...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
    ]),
  );
}
