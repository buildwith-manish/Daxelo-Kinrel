// lib/features/games/chitmatch/chitmatch_lobby_screen.dart
//
// TripleMatch — Lobby / Setup screen.
// Route: /family/$familyId/chitmatch/lobby
//
// Refactored to use the shared multiplayer framework:
//   • RoomSetupView for the setup view (player count + round timer +
//     rules + spectator toggle + auto-close duration + Create button)
//   • LobbyView for the in-room view (auto-close timer, share code,
//     players list, pending invites, lobby chat, ready toggle / start
//     button, cancel room button)
//   • BackButtonGuard for the back button (host: Close Room? / player:
//     Leave Room?)
//
// NOTE: ChitMatch has a multi-phase flow:
//   waiting → setup (submit words) → in_progress (deal chits & play).
// The framework's LobbyView is shown in the `waiting` phase (host's
// Start button triggers `startSetup()` which transitions to `setup`).
// The game-specific `_wordSubmissionView` is shown in the `setup`
// phase. When the host presses "Deal Chits & Start!", `dealAndStartGame()`
// transitions to `in_progress` and the auto-navigate listener sends
// the user to the board.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import '../shared/multiplayer/multiplayer.dart';
import '../shared/models/game_invite.dart';
import 'chitmatch_provider.dart';

class ChitmatchLobbyScreen extends ConsumerStatefulWidget {
  const ChitmatchLobbyScreen({super.key, required this.familyId});
  final String familyId;

  @override
  ConsumerState<ChitmatchLobbyScreen> createState() =>
      _ChitmatchLobbyScreenState();
}

class _ChitmatchLobbyScreenState extends ConsumerState<ChitmatchLobbyScreen> {
  int _playerCount = 6;
  int _roundTimer = 20;
  final _wordController = TextEditingController();
  bool _wordSubmitted = false;

  /// The room controller key for this ChitMatch lobby.
  RoomControllerKey get _roomKey =>
      RoomControllerKey(RoomConfig.chitmatch, widget.familyId);

  /// The `?join=<gameId>` query param from the deep-link.
  String? get _joinIdFromRoute =>
      GoRouterState.of(context).uri.queryParameters['join'];

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final joinId = _joinIdFromRoute;
      if (joinId != null && joinId.isNotEmpty) {
        // Non-host joining via deep-link: attach via the game provider
        // first (existing logic), then attach the room controller.
        final ok = await ref
            .read(chitmatchProvider(widget.familyId).notifier)
            .joinGame(joinId);
        if (ok) {
          await ref
              .read(roomControllerProvider(_roomKey).notifier)
              .attachOnJoin(joinId);
        }
      }
    });
  }

  Future<void> _createGame() async {
    final gameId = await ref
        .read(chitmatchProvider(widget.familyId).notifier)
        .createGame(playerCount: _playerCount, roundTimerSeconds: _roundTimer);
    if (gameId == null) return;
    await ref
        .read(roomControllerProvider(_roomKey).notifier)
        .attachToExistingGame(
          gameId,
          spectatorsEnabled: true,
          autoCloseMinutes: 5,
        );
  }

  Future<void> _shareCode(String? gameId) async {
    if (gameId == null) return;
    final code = gameId.replaceAll('-', '').substring(0, 6).toUpperCase();
    unawaited(GameMotionTokens.tap());
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
              '${_playerCount - 1} family members can join (4-${_playerCount} total).',
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

  Future<void> _submitWord() async {
    final word = _wordController.text.trim();
    if (word.isEmpty) return;
    await ref
        .read(chitmatchProvider(widget.familyId).notifier)
        .submitWord(word);
    setState(() => _wordSubmitted = true);
  }

  Future<void> _dealAndStart() async {
    await ref
        .read(chitmatchProvider(widget.familyId).notifier)
        .dealAndStartGame();
    final gameId = ref.read(chitmatchProvider(widget.familyId)).game?.id;
    if (gameId != null && mounted) {
      context.pushReplacement(
        '/family/${widget.familyId}/chitmatch/game/$gameId',
      );
    }
  }

  String? get _myId =>
      ref.read(supabaseProvider)?.auth.currentUser?.id;

  @override
  Widget build(BuildContext context) {
    final chitmatchState = ref.watch(chitmatchProvider(widget.familyId));
    final roomState = ref.watch(roomControllerProvider(_roomKey));
    final hasGame = chitmatchState.game != null || roomState.hasGame;
    final allWordsSubmitted = chitmatchState.players.isNotEmpty &&
        chitmatchState.players.every((p) =>
            p.submittedWord != null && p.submittedWord!.isNotEmpty);

    // Auto-navigate to the board once the game becomes in_progress
    ref.listen<ChitmatchState>(
      chitmatchProvider(widget.familyId),
      (previous, next) {
        final shouldNavigate = next.isInProgress;
        final wasInProgress = previous?.isInProgress ?? false;
        final gameId = next.game?.id;
        if (shouldNavigate && !wasInProgress && gameId != null && mounted) {
          context.pushReplacement(
            '/family/${widget.familyId}/chitmatch/game/$gameId',
          );
        }
      },
    );

    // Auto-navigate back to setup if room was cancelled/closed
    ref.listen<RoomState>(
      roomControllerProvider(_roomKey),
      (previous, next) {
        if (next.isCancelled && previous != null && !previous.isCancelled) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/family/${widget.familyId}');
          }
        }
      },
    );

    final isSetupPhase = chitmatchState.game?.isSetup ?? false;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: BackButtonGuard(
          roomKey: _roomKey,
          onExit: () {
            ref.read(chitmatchProvider(widget.familyId).notifier).leaveGame();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'TripleMatch',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
        actions: [
          if (hasGame && roomState.isHost)
            IconButton(
              tooltip: 'Share code',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _shareCode(
                roomState.gameId ?? chitmatchState.game?.id,
              ),
            ),
        ],
      ),
      body: chitmatchState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : (chitmatchState.error != null && !hasGame)
              ? DKErrorState(
                  message: chitmatchState.error!,
                  onRetry: () => ref
                      .read(chitmatchProvider(widget.familyId).notifier)
                      .createGame(
                        playerCount: _playerCount,
                        roundTimerSeconds: _roundTimer,
                      ),
                )
              : !hasGame
                  ? _setupView()
                  : isSetupPhase
                      ? _wordSubmissionView(
                          chitmatchState,
                          roomState.isHost,
                          allWordsSubmitted,
                        )
                      : LobbyView(
                          roomKey: _roomKey,
                          gameType: GameType.chitmatch,
                          gameDisplayName: 'Chit Match',
                          // The framework's "Start Match" button
                          // triggers the setup phase (collecting
                          // words from all players). The actual game
                          // start (deal chits) happens after the host
                          // taps "Deal Chits & Start!" inside
                          // _wordSubmissionView.
                          startGame: () => ref
                              .read(chitmatchProvider(widget.familyId)
                                  .notifier)
                              .startSetup(),
                        ),
    );
  }

  /// The setup view (no game yet) — uses RoomSetupView wrapper.
  Widget _setupView() {
    return RoomSetupView(
      roomKey: _roomKey,
      createButtonLabel: 'Create Game',
      createGame: () async {
        await _createGame();
        return null;
      },
      defaultAutoCloseMinutes: 5,
      child: _gameSetupFields(),
    );
  }

  Widget _gameSetupFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Number of Players'),
        const SizedBox(height: KinrelSpacing.sm),
        _playerCountSelector(),
        const SizedBox(height: KinrelSpacing.lg),
        _sectionLabel('Round Timer: ${_roundTimer}s'),
        const SizedBox(height: KinrelSpacing.sm),
        Slider(
          value: _roundTimer.toDouble(),
          min: 10,
          max: 60,
          divisions: 10,
          activeColor: KinrelColors.orange,
          label: '${_roundTimer}s',
          onChanged: (v) => setState(() => _roundTimer = v.round()),
        ),
        const SizedBox(height: KinrelSpacing.lg),
        _sectionLabel('How to Play'),
        const SizedBox(height: KinrelSpacing.sm),
        _rulesCard(),
      ],
    );
  }

  /// Game-specific word-submission view (shown when game is in `setup`
  /// phase). NOT part of the shared multiplayer framework — this is
  /// ChitMatch's unique second step between lobby and active play.
  Widget _wordSubmissionView(
    ChitmatchState state,
    bool isHost,
    bool allWordsSubmitted,
  ) {
    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        Text(
          'Submit Your Word',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose an animal or object name. 3 chits with this word will be created and shuffled into the game.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.textDim,
          ),
        ),
        const SizedBox(height: KinrelSpacing.lg),
        if (_wordSubmitted || state.myWord != null)
          Container(
            padding: const EdgeInsets.all(KinrelSpacing.lg),
            decoration: BoxDecoration(
              color: KinrelColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: Border.all(color: KinrelColors.success, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: KinrelColors.success, size: 24),
                const SizedBox(width: KinrelSpacing.sm),
                Expanded(
                  child: Text(
                    'Your word: "${state.myWord ?? _wordController.text}"',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      color: KinrelColors.textWhite,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          TextField(
            controller: _wordController,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 16,
              color: KinrelColors.textWhite,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. Elephant, Tiger, Rocket...',
              hintStyle: TextStyle(color: KinrelColors.textDim),
              filled: true,
              fillColor: KinrelColors.darkCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.lg),
                borderSide: BorderSide(color: KinrelColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KinrelRadius.lg),
                borderSide:
                    BorderSide(color: KinrelColors.orange, width: 2),
              ),
            ),
            onSubmitted: (_) => _submitWord(),
          ),
          const SizedBox(height: KinrelSpacing.md),
          DKButton(
            label: 'Submit Word',
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            isLoading: state.isSubmitting,
            onPressed: _submitWord,
          ),
        ],
        const SizedBox(height: KinrelSpacing.xl),
        _sectionLabel('Word Submissions'),
        const SizedBox(height: KinrelSpacing.sm),
        ...state.players.map((p) {
          final submitted = p.submittedWord != null &&
              p.submittedWord!.isNotEmpty;
          return Container(
            margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.md,
              vertical: KinrelSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(color: KinrelColors.border),
            ),
            child: Row(
              children: [
                DKAvatar(initials: PersonAvatar.initialsFor(p.userName)),
                const SizedBox(width: KinrelSpacing.md),
                Expanded(
                  child: Text(
                    p.userId == _myId
                        ? '${p.userName} (You)'
                        : p.userName,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 13,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                ),
                Icon(
                  submitted ? Icons.check_circle : Icons.hourglass_empty,
                  size: 16,
                  color: submitted
                      ? KinrelColors.success
                      : KinrelColors.textDim,
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: KinrelSpacing.xl),
        if (isHost && allWordsSubmitted)
          DKButton(
            label: 'Deal Chits & Start!',
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            isLoading: state.isResolving,
            onPressed: _dealAndStart,
          )
        else if (isHost)
          Text(
            'Waiting for all players to submit words...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(KinrelSpacing.lg),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: Border.all(color: KinrelColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KinrelColors.orange,
                  ),
                ),
                const SizedBox(width: KinrelSpacing.sm),
                Text(
                  'Waiting for host...',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _playerCountSelector() {
    return Wrap(
      spacing: KinrelSpacing.sm,
      runSpacing: KinrelSpacing.sm,
      children: [4, 6, 8, 10, 12].map((n) {
        final selected = n == _playerCount;
        return GestureDetector(
          onTap: () {
            unawaited(GameMotionTokens.tap());
            setState(() => _playerCount = n);
          },
          child: Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: KinrelSpacing.sm),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(
                color: selected ? KinrelColors.orange : KinrelColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                '$n',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color:
                      selected ? KinrelColors.orange : KinrelColors.textDim,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _rulesCard() {
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
          _ruleLine('1.', 'Each player submits a word. 3 chits per word are created.'),
          const SizedBox(height: 6),
          _ruleLine('2.', 'All chits are shuffled. Each player gets 3 random chits.'),
          const SizedBox(height: 6),
          _ruleLine('3.', 'Each round, everyone selects 1 chit to pass clockwise.'),
          const SizedBox(height: 6),
          _ruleLine('4.', 'Passes resolve simultaneously — all at once!'),
          const SizedBox(height: 6),
          _ruleLine('5.', 'First to 3 matching chits wins. Joint winners possible!'),
          const SizedBox(height: 6),
          _ruleLine(
            '★',
            'Don\'t respond in ${_roundTimer}s? Auto-selected for you.',
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: KinrelColors.textDim,
          letterSpacing: 0.5,
        ),
      );

  Widget _ruleLine(String num, String text, {bool highlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            num,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: highlight ? KinrelColors.orange : KinrelColors.textDim,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: highlight ? KinrelColors.textWhite : KinrelColors.textDim,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
