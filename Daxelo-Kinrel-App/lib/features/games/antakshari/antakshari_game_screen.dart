import '../../../core/widgets/person_avatar.dart';
// lib/features/games/antakshari/antakshari_game_screen.dart
//
// Antakshari — main game screen with:
//   • Required letter pulse display
//   • Countdown ring (30s turn / 10s challenge window)
//   • Letter entry field for active player
//   • Challenge button + live count for others
//   • Collapsible player list (scales to 20)
//   • Inline results view with multi-winner confetti
// Route: /family/$familyId/antakshari/game/:gameId

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import 'antakshari_models.dart';
import 'antakshari_provider.dart';

class AntakshariGameScreen extends ConsumerStatefulWidget {
  const AntakshariGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<AntakshariGameScreen> createState() =>
      _AntakshariGameScreenState();
}

class _AntakshariGameScreenState
    extends ConsumerState<AntakshariGameScreen>
    with SingleTickerProviderStateMixin {
  final _letterController = TextEditingController();
  late final AnimationController _pulseController;
  Timer? _tickTimer; // forces rebuild every 1s for countdown
  bool _playersExpanded = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(antakshariProvider(widget.familyId));
      if (state.game == null) {
        ref
            .read(antakshariProvider(widget.familyId).notifier)
            .joinGame(widget.gameId);
      }
    });
    // Tick timer for countdown display
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tickTimer?.cancel();
    _letterController.dispose();
    super.dispose();
  }

  void _pulseLetter() {
    _pulseController.forward(from: 0);
    GameMotionTokens.success();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(antakshariProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    // Show results inline when game is completed
    if (state.isCompleted) {
      return _resultsView(state, myId);
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            ref.read(antakshariProvider(widget.familyId).notifier).leaveGame();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'Antakshari',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: KinrelColors.darkCard,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: state.isLoading && state.game == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : state.error != null && state.game == null
          ? DKErrorState(
              message: state.error!,
              onRetry: () => ref
                  .read(antakshariProvider(widget.familyId).notifier)
                  .joinGame(widget.gameId),
            )
          : state.isWaiting
              ? _waitingRoom(state, myId)
              : _gameView(state, myId),
    );
  }

  // ── Waiting room (lobby state on game screen) ─────────────────────

  Widget _waitingRoom(AntakshariState state, String? myId) {
    final game = state.game;
    if (game == null) return const SizedBox.shrink();
    final isHost = game.hostUserId == myId;
    final canStart = state.players.length >= 2;
    final code = game.id.replaceAll('-', '').substring(0, 6).toUpperCase();

    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        Container(
          padding: const EdgeInsets.all(KinrelSpacing.lg),
          decoration: BoxDecoration(
            gradient: KinrelGradients.igniteGradient,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
          ),
          child: Column(
            children: [
              Text(
                'Share Code',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: KinrelSpacing.sm),
              Text(
                code,
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: KinrelSpacing.lg),
        Text(
          'Players (${state.players.length}/${game.maxPlayers})',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textDim,
          ),
        ),
        const SizedBox(height: KinrelSpacing.sm),
        ...state.players.map((p) => _playerTile(p, myId, game.hostUserId)),
        const SizedBox(height: KinrelSpacing.xl),
        if (isHost)
          DKButton(
            label: canStart ? 'Start Game' : 'Waiting for players…',
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            onPressed: canStart
                ? () => ref
                    .read(antakshariProvider(widget.familyId).notifier)
                    .startGame()
                : null,
          )
        else
          _waitingIndicator(),
      ],
    );
  }

  // ── Active game view ──────────────────────────────────────────────

  Widget _gameView(AntakshariState state, String? myId) {
    final game = state.game!;
    final isMyTurn = state.isMyTurn(myId);
    final requiredLetter = game.currentRequiredLetter ?? '?';
    final secondsLeft = state.turnSecondsRemaining;
    final turnTimer = game.turnTimerSeconds;
    final isInChallengeWindow = state.isInChallengeWindow;
    final challengeCount = state.currentTurnChallenges.length;
    final currentPlayer = state.players
        .where((p) => p.userId == game.currentTurnPlayerId)
        .firstOrNull;
    final currentTurn = state.currentTurn;
    final hasSubmitted = currentTurn?.letterEndedWith != null;

    return SafeArea(
      child: Column(
        children: [
          // Round / turn info bar
          _infoBar(state, game),
          // Required letter + countdown ring
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Required letter
                  _requiredLetterDisplay(
                    requiredLetter,
                    isInChallengeWindow,
                    hasSubmitted,
                  ),
                  const SizedBox(height: KinrelSpacing.lg),
                  // Countdown ring
                  _countdownRing(
                    secondsLeft,
                    turnTimer,
                    isInChallengeWindow,
                  ),
                  const SizedBox(height: KinrelSpacing.lg),
                  // Current player name
                  if (currentPlayer != null)
                    Text(
                      state.isMyTurn(myId)
                          ? 'Your turn!'
                          : '${currentPlayer.userName} is singing…',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 16,
                        color: KinrelColors.textWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: KinrelSpacing.xl),
                  // Action area
                  _actionArea(
                    state,
                    myId,
                    isMyTurn,
                    isInChallengeWindow,
                    hasSubmitted,
                    challengeCount,
                  ),
                ],
              ),
            ),
          ),
          // Collapsible player list
          _collapsiblePlayerList(state, myId),
        ],
      ),
    );
  }

  Widget _infoBar(AntakshariState state, AntakshariGame game) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.base,
        vertical: KinrelSpacing.sm,
      ),
      color: KinrelColors.darkCard,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoChip(
            'Turn',
            '${game.currentTurnNumber}',
            Icons.repeat_rounded,
          ),
          _infoChip(
            'Round',
            '${game.currentRound}',
            Icons.refresh_rounded,
          ),
          _infoChip(
            'Active',
            '${state.activePlayers.length}',
            Icons.people_rounded,
          ),
          if (game.gameMode == AntakshariGameMode.roundLimited &&
              game.roundLimit != null)
            _infoChip(
              'Limit',
              '${game.roundLimit}',
              Icons.flag_rounded,
            ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: KinrelColors.textDim),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 9,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }

  Widget _requiredLetterDisplay(
    String letter,
    bool isInChallengeWindow,
    bool hasSubmitted,
  ) {
    final label = isInChallengeWindow
        ? (hasSubmitted ? 'Ending Letter' : 'Singing…')
        : 'Start with';
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textDim,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: KinrelSpacing.sm),
        ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 1.15).animate(
            CurvedAnimation(
              parent: _pulseController,
              curve: Curves.elasticOut,
            ),
          ),
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isInChallengeWindow
                  ? LinearGradient(
                      colors: [
                        KinrelColors.warning.withValues(alpha: 0.3),
                        KinrelColors.darkCard,
                      ],
                    )
                  : KinrelGradients.igniteGradient,
              border: Border.all(
                color: isInChallengeWindow
                    ? KinrelColors.warning
                    : KinrelColors.orange,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isInChallengeWindow
                      ? KinrelColors.warning
                      : KinrelColors.orange)
                      .withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                isInChallengeWindow && hasSubmitted
                    ? (state.currentTurn?.letterEndedWith ?? '?')
                    : letter,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  AntakshariState get state => ref.read(antakshariProvider(widget.familyId));

  Widget _countdownRing(
    int secondsLeft,
    int totalSeconds,
    bool isInChallengeWindow,
  ) {
    final progress = (secondsLeft / totalSeconds).clamp(0.0, 1.0);
    final color = isInChallengeWindow
        ? KinrelColors.warning
        : (secondsLeft <= 5 ? KinrelColors.error : KinrelColors.orange);

    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 4,
            backgroundColor: KinrelColors.darkElevated,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          Center(
            child: Text(
              '${secondsLeft}s',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionArea(
    AntakshariState state,
    String? myId,
    bool isMyTurn,
    bool isInChallengeWindow,
    bool hasSubmitted,
    int challengeCount,
  ) {
    // If it's my turn and I haven't submitted yet → letter entry
    if (isMyTurn && !hasSubmitted && !isInChallengeWindow) {
      return _letterEntry();
    }

    // If it's my turn and I have submitted → waiting for challenges
    if (isMyTurn && hasSubmitted && isInChallengeWindow) {
      return _waitingForChallenges(challengeCount);
    }

    // If it's someone else's turn and they've submitted → challenge button
    if (!isMyTurn && isInChallengeWindow) {
      return _challengeButton(state, myId, challengeCount);
    }

    // If it's someone else's turn and they're singing → waiting
    if (!isMyTurn && !isInChallengeWindow) {
      return _waitingForSinger(state);
    }

    return const SizedBox.shrink();
  }

  Widget _letterEntry() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.xl),
      child: Column(
        children: [
          Text(
            'Type the letter your song ended on:',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textDim,
            ),
          ),
          const SizedBox(height: KinrelSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _letterController,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.textWhite,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '?',
                    hintStyle: TextStyle(color: KinrelColors.textDim),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KinrelRadius.lg),
                      borderSide: BorderSide(
                        color: KinrelColors.orange,
                        width: 2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(KinrelRadius.lg),
                      borderSide: BorderSide(
                        color: KinrelColors.orange,
                        width: 3,
                      ),
                    ),
                    filled: true,
                    fillColor: KinrelColors.darkCard,
                  ),
                  onChanged: (v) {
                    if (v.isNotEmpty) {
                      final upper = v.toUpperCase();
                      if (RegExp(r'[A-Z]').hasMatch(upper)) {
                        _letterController.text = upper;
                        _letterController.selection =
                            TextSelection.fromPosition(
                          TextPosition(offset: _letterController.text.length),
                        );
                      } else {
                        _letterController.clear();
                      }
                    }
                  },
                  onSubmitted: (v) => _submitLetter(),
                ),
              ),
              const SizedBox(width: KinrelSpacing.sm),
              DKButton(
                label: 'Submit',
                variant: DKButtonVariant.gradient,
                onPressed: _submitLetter,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submitLetter() {
    final letter = _letterController.text.trim().toUpperCase();
    if (letter.isEmpty || letter.length != 1) {
      ref.read(antakshariProvider(widget.familyId).notifier);
      return;
    }
    ref
        .read(antakshariProvider(widget.familyId).notifier)
        .submitEndingLetter(letter);
    _letterController.clear();
  }

  Widget _waitingForChallenges(int challengeCount) {
    return Column(
      children: [
        Icon(Icons.hourglass_top, color: KinrelColors.warning, size: 32),
        const SizedBox(height: KinrelSpacing.sm),
        Text(
          'Waiting for challenges…',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textWhite,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$challengeCount / 3 challenges',
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 13,
            color: challengeCount >= 3
                ? KinrelColors.error
                : KinrelColors.warning,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _challengeButton(
    AntakshariState state,
    String? myId,
    int challengeCount,
  ) {
    final hasChallenged = state.currentTurnChallenges.any(
      (c) => c.challengerId == myId,
    );
    return Column(
      children: [
        DKButton(
          label: hasChallenged
              ? 'Challenged ✓'
              : 'Challenge! (${challengeCount}/3)',
          variant: hasChallenged
              ? DKButtonVariant.secondary
              : DKButtonVariant.primary,
          icon: Icons.gavel_rounded,
          onPressed: hasChallenged
              ? null
              : () => ref
                  .read(antakshariProvider(widget.familyId).notifier)
                  .challengeCurrentTurn(),
        ),
        const SizedBox(height: KinrelSpacing.sm),
        Text(
          challengeCount >= 3
              ? 'Turn will be ruled invalid!'
              : '${3 - challengeCount} more to eliminate',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: challengeCount >= 3
                ? KinrelColors.error
                : KinrelColors.textDim,
          ),
        ),
      ],
    );
  }

  Widget _waitingForSinger(AntakshariState state) {
    final currentPlayer = state.players
        .where((p) => p.userId == state.game?.currentTurnPlayerId)
        .firstOrNull;
    return Column(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: KinrelColors.orange,
          ),
        ),
        const SizedBox(height: KinrelSpacing.sm),
        Text(
          '${currentPlayer?.userName ?? 'Player'} is singing…',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 14,
            color: KinrelColors.textDim,
          ),
        ),
      ],
    );
  }

  Widget _waitingIndicator() {
    return Container(
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
            'Waiting for host to start the game…',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  // ── Collapsible player list ───────────────────────────────────────

  Widget _collapsiblePlayerList(AntakshariState state, String? myId) {
    final active = state.activePlayers;
    final eliminated = state.players.where((p) => p.isEliminated).toList();
    final game = state.game;
    final currentTurnPlayerId = game?.currentTurnPlayerId;

    return Container(
      margin: const EdgeInsets.all(KinrelSpacing.base),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _playersExpanded = !_playersExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.md,
                vertical: KinrelSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    _playersExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: KinrelColors.textDim,
                    size: 20,
                  ),
                  const SizedBox(width: KinrelSpacing.sm),
                  Expanded(
                    child: Text(
                      'Players: ${active.length} active'
                      '${eliminated.isNotEmpty ? ', ${eliminated.length} eliminated' : ''}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Show next 3 players inline when collapsed
                  if (!_playersExpanded)
                    Row(
                      children: active
                          .take(3)
                          .map((p) => Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: _miniAvatar(
                                  p,
                                  p.userId == currentTurnPlayerId,
                                  p.userId == myId,
                                ),
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),
          ),
          if (_playersExpanded)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: KinrelColors.border.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Column(
                children: [
                  // Active players
                  ...active.map((p) => _playerTile(
                        p,
                        myId,
                        game?.hostUserId,
                        isCurrentTurn: p.userId == currentTurnPlayerId,
                      )),
                  if (eliminated.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KinrelSpacing.md,
                        vertical: 4,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ELIMINATED',
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 10,
                            color: KinrelColors.textDim,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    ...eliminated.map((p) => _playerTile(
                          p,
                          myId,
                          game?.hostUserId,
                          isEliminated: true,
                        )),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniAvatar(AntakshariPlayer p, bool isCurrent, bool isMe) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCurrent
            ? KinrelColors.orange
            : (isMe ? KinrelColors.orange.withValues(alpha: 0.3) : KinrelColors.darkElevated),
        border: Border.all(
          color: isCurrent ? KinrelColors.orange : KinrelColors.border,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Center(
        child: Text(
          PersonAvatar.initialsFor(p.userName),
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isCurrent ? Colors.white : KinrelColors.textDim,
          ),
        ),
      ),
    );
  }

  Widget _playerTile(
    AntakshariPlayer p,
    String? myId,
    String? hostUserId, {
    bool isCurrentTurn = false,
    bool isEliminated = false,
  }) {
    final isMe = p.userId == myId;
    return ListTile(
      dense: true,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isEliminated
              ? KinrelColors.darkElevated
              : (isCurrentTurn
                    ? KinrelColors.orange.withValues(alpha: 0.3)
                    : KinrelColors.darkElevated),
          border: Border.all(
            color: isCurrentTurn
                ? KinrelColors.orange
                : (isMe ? KinrelColors.orange : KinrelColors.border),
            width: isCurrentTurn ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            PersonAvatar.initialsFor(p.userName),
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isEliminated
                  ? KinrelColors.textDim
                  : (isCurrentTurn ? KinrelColors.orange : KinrelColors.textWhite),
            ),
          ),
        ),
      ),
      title: Row(
        children: [
          Text(
            isMe ? '${p.userName} (You)' : p.userName,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: isEliminated ? KinrelColors.textDim : KinrelColors.textWhite,
              fontWeight: FontWeight.w500,
              decoration: isEliminated ? TextDecoration.lineThrough : null,
            ),
          ),
          if (isCurrentTurn) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: KinrelColors.orange,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'SINGING',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 8,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (p.userId == hostUserId) ...[
            const SizedBox(width: 4),
            Text(
              '👑',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
      trailing: isEliminated
          ? const Text('💀', style: TextStyle(fontSize: 14))
          : null,
    );
  }

  // ── Results view (inline when game is completed) ──────────────────

  Widget _resultsView(AntakshariState state, String? myId) {
    final game = state.game!;
    final winners = game.winnerUserIds ?? [];
    final winnerNames = game.winnerNames ?? [];
    final isMyWin = winners.contains(myId);
    final isTie = winners.length > 1;

    return DKScaffold(
      gradient: isMyWin ? KinrelGradients.deepFireGradient : null,
      backgroundColor: isMyWin ? null : KinrelColors.darkSurface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Results',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textWhite,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: KinrelColors.textWhite,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        children: [
          const SizedBox(height: KinrelSpacing.lg),
          // Winner banner
          _winnerBanner(isMyWin, isTie, winners, winnerNames)
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(
                begin: const Offset(0.92, 0.92),
                end: const Offset(1.0, 1.0),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
          const SizedBox(height: KinrelSpacing.xl),
          // Turn history (last 5 turns)
          if (state.turns.isNotEmpty) ...[
            Text(
              'Recent Turns',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textDim,
              ),
            ),
            const SizedBox(height: KinrelSpacing.sm),
            ...state.turns.reversed.take(5).map((t) => _turnHistoryRow(t)),
            const SizedBox(height: KinrelSpacing.xxl),
          ],
          DKButton(
            label: 'Play Again',
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            icon: Icons.refresh_rounded,
            onPressed: () {
              ref
                  .read(antakshariProvider(widget.familyId).notifier)
                  .leaveGame();
              if (context.mounted) {
                context.pushReplacement(
                  '/family/${widget.familyId}/antakshari/lobby',
                );
              }
            },
          ),
          const SizedBox(height: KinrelSpacing.sm),
          DKButton(
            label: 'Back to Hub',
            variant: DKButtonVariant.secondary,
            fullWidth: true,
            onPressed: () {
              ref
                  .read(antakshariProvider(widget.familyId).notifier)
                  .leaveGame();
              if (context.mounted) {
                context.go('/games?familyId=${widget.familyId}');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _winnerBanner(
    bool isMyWin,
    bool isTie,
    List<String> winnerIds,
    List<String> winnerNames,
  ) {
    return Column(
      children: [
        const Text('🏆', style: TextStyle(fontSize: 64))
            .animate(onPlay: (c) => c.forward())
            .fadeIn(duration: 500.ms)
            .scale(
              begin: const Offset(0.5, 0.5),
              end: const Offset(1.0, 1.0),
              duration: 500.ms,
              curve: Curves.elasticOut,
            ),
        const SizedBox(height: KinrelSpacing.sm),
        Text(
          isMyWin
              ? (isTie ? 'Joint Winners!' : 'You Won!')
              : (isTie ? 'Joint Winners!' : 'Winner!'),
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: KinrelColors.textWhite,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: KinrelSpacing.sm),
        Wrap(
          spacing: KinrelSpacing.sm,
          runSpacing: KinrelSpacing.sm,
          alignment: WrapAlignment.center,
          children: winnerNames.map((name) => Container(
            padding: const EdgeInsets.symmetric(
              horizontal: KinrelSpacing.md,
              vertical: KinrelSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: KinrelColors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(KinrelRadius.lg),
              border: Border.all(color: KinrelColors.orange, width: 1),
            ),
            child: Text(
              name,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: KinrelColors.orange,
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _turnHistoryRow(AntakshariTurn turn) {
    final resultColor = turn.challengeResult == AntakshariChallengeResult.valid
        ? KinrelColors.success
        : turn.challengeResult == AntakshariChallengeResult.invalid
        ? KinrelColors.error
        : turn.challengeResult == AntakshariChallengeResult.timedOut
        ? KinrelColors.warning
        : KinrelColors.textDim;
    final resultIcon = turn.challengeResult == AntakshariChallengeResult.valid
        ? Icons.check_circle
        : turn.challengeResult == AntakshariChallengeResult.invalid
        ? Icons.cancel
        : turn.challengeResult == AntakshariChallengeResult.timedOut
        ? Icons.timer_off
        : Icons.hourglass_empty;
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
          Icon(resultIcon, size: 16, color: resultColor),
          const SizedBox(width: KinrelSpacing.sm),
          Expanded(
            child: Text(
              turn.playerName,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textWhite,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '${turn.letterStartedWith} → ${turn.letterEndedWith ?? '?'}',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: KinrelColors.orange,
            ),
          ),
        ],
      ),
    );
  }
}
