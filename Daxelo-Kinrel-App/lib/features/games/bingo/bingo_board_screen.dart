// lib/features/games/bingo/bingo_board_screen.dart
//
// Bingo — main board screen with:
//   • Player's own 5x5 card (tappable cells with mark animation)
//   • Large display of the most recently called number
//   • Scrollable history of all called numbers
//   • BINGO! button (enabled when client detects potential win)
//   • Inline results view with winner confetti
// Premium finish: casino felt GameBoardShell card frame, hand-placed
// daub stamps on marked cells, glowing "last called" pill, and a
// triple-volley GameConfetti celebration on bingo wins.
// Route: /family/$familyId/bingo/board/:gameId

import 'dart:async';
import 'dart:math' as math;

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
import '../shared/widgets/game_board_shell.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/widgets/badges_toast.dart';
import '../shared/widgets/reactions_bar.dart';
import 'bingo_models.dart';
import 'bingo_provider.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';

class BingoBoardScreen extends ConsumerStatefulWidget {
  const BingoBoardScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<BingoBoardScreen> createState() => _BingoBoardScreenState();
}

class _BingoBoardScreenState extends ConsumerState<BingoBoardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _numberPulseController;
  late final AnimationController _shakeController;
  int? _lastSeenCalledNumber;
  Timer? _shakeTimer;
  Timer? _countdownTimer;
  bool _badgesChecked = false;
  bool _shakeTriggered = false;
  int _secondsToNextCall = 0;

  @override
  void initState() {
    super.initState();
    _numberPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(bingoProvider(widget.familyId));
      if (state.game == null) {
        ref.read(bingoProvider(widget.familyId).notifier).joinGame(widget.gameId);
      }
      _startCountdown();
    });
  }

  @override
  void dispose() {
    _numberPulseController.dispose();
    _shakeController.dispose();
    _shakeTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _onNewNumberCalled(int number) {
    if (_lastSeenCalledNumber != number) {
      _lastSeenCalledNumber = number;
      _numberPulseController.forward(from: 0);
      GameMotionTokens.success();
    }
  }

  void _triggerShake() {
    _shakeController.forward(from: 0);
    GameMotionTokens.error();
  }

  /// Live countdown to the next called number, from the authoritative
  /// lastCallAt + callIntervalSeconds. Runs once per second while the
  /// board is visible; harmless when the game isn't running.
  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final game = ref.read(bingoProvider(widget.familyId)).game;
      if (game == null || !game.isInProgress) {
        if (_secondsToNextCall != 0) setState(() => _secondsToNextCall = 0);
        return;
      }
      setState(() {
        _secondsToNextCall = game.secondsToNextCall;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bingoProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    // Detect new number called
    final lastCalled = state.game?.lastCalledNumber;
    if (lastCalled != null && lastCalled != _lastSeenCalledNumber) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onNewNumberCalled(lastCalled);
      });
    }

    // Show results inline when game completes
    if (state.isCompleted) {
      // Fire-and-forget: check for newly-earned badges after game ends
      if (!_badgesChecked) {
        _badgesChecked = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          BadgesToast.maybeShowAfterGame(
            context: context,
            familyId: widget.familyId,
          );
        });
      }
      return _resultsView(state, myId);
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () async {
            final state = ref.read(bingoProvider(widget.familyId));
            final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
            final shouldLeave = await LeaveGameDialog.show(
              context,
              isHost: (state.game?.hostUserId == myId),
              gameName: 'Bingo',
            );
            if (shouldLeave != true) return;
            if (!context.mounted) return;
            // Leaving tears down only THIS player's presence. Mid-game
            // rooms are NEVER deleted here — the server-side caller
            // keeps the match alive for everyone else (v2 fix: any player
            // closing the app used to hard-delete the room for all).
            ref.read(bingoProvider(widget.familyId).notifier).leaveGame();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
          },
        ),
        title: Text(
          'Bingo',
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
                  .read(bingoProvider(widget.familyId).notifier)
                  .joinGame(widget.gameId),
            )
          : state.isWaiting
              ? _waitingRoom(state, myId)
              : state.amSpectator || state.myCard == null
                  ? _spectatorView(state, myId)
                  : _boardView(state, myId),
    );
  }

  // ── Waiting room (lobby state on board screen) ────────────────────

  Widget _waitingRoom(BingoState state, String? myId) {
    final game = state.game;
    if (game == null) return const SizedBox.shrink();
    final isHost = game.hostUserId == myId;
    final canStart = state.allCards.length >= 2;
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
          'Players (${state.allCards.length}/${game.maxPlayers})',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textDim,
          ),
        ),
        const SizedBox(height: KinrelSpacing.sm),
        ...state.allCards.map((c) => _playerTile(c, myId, game.hostUserId)),
        const SizedBox(height: KinrelSpacing.xl),
        if (isHost)
          DKButton(
            label: canStart ? 'Start Game' : 'Waiting for players…',
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            onPressed: canStart
                ? () => ref
                    .read(bingoProvider(widget.familyId).notifier)
                    .startGame()
                : null,
          )
        else
          _waitingIndicator(),
      ],
    );
  }

  // ── Active board view ─────────────────────────────────────────────

  Widget _boardView(BingoState state, String? myId) {
    final game = state.game!;
    final card = state.myCard;
    final lastNumber = game.lastCalledNumber;
    final canClaim = state.canClaimBingo;

    return SafeArea(
      child: Column(
        children: [
          // Last called number display + next-call countdown
          _calledNumberDisplay(lastNumber),
          // Called number history (scrollable horizontal)
          _numberHistory(game.numbersCalled),
          // Player's 5x5 card
          Expanded(
            child: card == null
                ? Center(
                    child: Text(
                      'No card generated yet',
                      style: TextStyle(
                        color: KinrelColors.textDim,
                        fontFamily: KinrelTypography.bodyFont,
                      ),
                    ),
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(KinrelSpacing.base),
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: _bingoCard(card, game),
                      ),
                    ),
                  ),
          ),
          // Missed-marks nudge (called numbers not yet daubed)
          if (state.unmarkedCalledCount > 0 && !game.isCompleted)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${state.unmarkedCalledCount} called number${state.unmarkedCalledCount == 1 ? '' : 's'} waiting for your daub',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.warning,
                ),
              ),
            ),
          // BINGO button + claim feedback
          _bingoButton(state, canClaim, myId),
          const SizedBox(height: KinrelSpacing.base),
        ],
      ),
    );
  }

  // ── Spectator view ─────────────────────────────────────────────

  Widget _spectatorView(BingoState state, String? myId) {
    final game = state.game!;
    final lastNumber = game.lastCalledNumber;

    return SafeArea(
      child: Column(
        children: [
          _calledNumberDisplay(lastNumber),
          _numberHistory(game.numbersCalled),
          // Spectator banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base, vertical: KinrelSpacing.sm),
            color: KinrelColors.darkCard,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.visibility_outlined,
                    size: 14, color: KinrelColors.textDim),
                const SizedBox(width: 6),
                Text(
                  "You're watching — cheer them on!",
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          // Roster with live daub progress
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(KinrelSpacing.base),
              itemCount: state.allCards.length,
              itemBuilder: (context, i) {
                final card = state.allCards[i];
                final called = game.numbersCalled
                    .where((n) => card.hasNumber(n))
                    .length;
                final marked = card.markedNumbers
                    .where((n) => game.numbersCalled.contains(n))
                    .length;
                final isWinner = game.winnerPlayerId == card.playerId;
                return Container(
                  margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
                  padding: const EdgeInsets.symmetric(
                      horizontal: KinrelSpacing.md, vertical: KinrelSpacing.md),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard,
                    borderRadius: BorderRadius.circular(KinrelRadius.md),
                    border: Border.all(
                      color: isWinner
                          ? KinrelColors.orange
                          : KinrelColors.border,
                      width: isWinner ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      DKAvatar(
                        initials: card.playerName.isNotEmpty
                            ? card.playerName[0].toUpperCase()
                            : '?',
                      ),
                      const SizedBox(width: KinrelSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              card.playerId == myId
                                  ? '${card.playerName} (You)'
                                  : card.playerName,
                              style: TextStyle(
                                fontFamily: KinrelTypography.bodyFont,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: KinrelColors.textWhite,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: SizedBox(
                                height: 5,
                                child: Stack(
                                  children: [
                                    Container(
                                        color: KinrelColors.darkElevated),
                                    FractionallySizedBox(
                                      widthFactor: called == 0
                                          ? 0
                                          : (marked / called).clamp(0.0, 1.0),
                                      child: Container(
                                          color: KinrelColors.orange),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: KinrelSpacing.sm),
                      Text(
                        '$marked/$called',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textDim,
                        ),
                      ),
                      if (isWinner)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.emoji_events,
                              size: 16, color: KinrelColors.orange),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            child: ReactionsBar(
              gameTable: 'bingo_games',
              gameId: game.id,
              familyId: widget.familyId,
              size: ReactionsBarSize.lg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _calledNumberDisplay(int? lastNumber) {
    final letter = lastNumber != null ? letterForNumber(lastNumber) : '';
    final game = ref.watch(bingoProvider(widget.familyId)).game;
    final counting = game?.isInProgress ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: KinrelSpacing.md,
        horizontal: KinrelSpacing.base,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(
          bottom: BorderSide(color: KinrelColors.border),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'LAST CALLED',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.textDim,
                  letterSpacing: 1.5,
                ),
              ),
              if (counting) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkElevated,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: KinrelColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 11, color: KinrelColors.textDim),
                      const SizedBox(width: 3),
                      Text(
                        _secondsToNextCall > 0
                            ? 'next in ${_secondsToNextCall}s'
                            : 'calling…',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          ScaleTransition(
            scale: Tween<double>(begin: 0.5, end: 1.0).animate(
              CurvedAnimation(
                parent: _numberPulseController,
                curve: Curves.elasticOut,
              ),
            ),
            // Called-number pill — glows with the accent so the eye
            // lands on it the instant a number drops.
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              decoration: BoxDecoration(
                color: KinrelColors.darkElevated,
                borderRadius: BorderRadius.circular(KinrelRadius.xl),
                border: Border.all(
                  color: KinrelColors.orange.withValues(alpha: 0.65),
                  width: 1.5,
                ),
                boxShadow: lastNumber != null
                    ? [
                        BoxShadow(
                          color: KinrelColors.orangeGlowIntense,
                          blurRadius: 22,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    letter,
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.orange,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    lastNumber != null ? '$lastNumber' : '—',
                    style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      color: KinrelColors.textWhite,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberHistory(List<int> numbersCalled) {
    if (numbersCalled.isEmpty) {
      return const SizedBox(height: 32);
    }
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.sm),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: numbersCalled.length,
        itemBuilder: (context, index) {
          // Show most recent first
          final num = numbersCalled[numbersCalled.length - 1 - index];
          final letter = letterForNumber(num);
          final isLatest = index == 0;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isLatest
                  ? KinrelColors.orange.withValues(alpha: 0.2)
                  : KinrelColors.darkElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isLatest ? KinrelColors.orange : KinrelColors.border,
                width: isLatest ? 2 : 1,
              ),
              boxShadow: isLatest
                  ? [
                      BoxShadow(
                        color: KinrelColors.orangeGlowIntense,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                '$letter$num',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isLatest
                      ? KinrelColors.orange
                      : KinrelColors.textDim,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Per-column accent tints for the B-I-N-G-O header letters —
  /// each column gets its own warm/cool accent while staying inside
  /// the Kinrel palette.
  static const List<Color> _columnTints = [
    KinrelColors.orange,
    KinrelColors.amber,
    KinrelColors.brightGold,
    KinrelColors.tealAccent,
    KinrelColors.coral,
  ];

  Widget _bingoCard(BingoCard card, BingoGame game) {
    // Casino-grade card: felt table shell with accent rim + bevel.
    return GameBoardShell(
      accent: KinrelColors.orange,
      surface: BoardSurface.felt,
      radius: 24,
      padding: 8,
      child: Column(
        children: [
          // B-I-N-G-O header — dark rail with per-column accent tints
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [KinrelColors.darkElevated, KinrelColors.darkCard],
              ),
              border: Border(
                bottom: BorderSide(
                  color: KinrelColors.orange.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
            ),
            child: Row(
              children: [
                for (var col = 0; col < bingoColumnLetters.length; col++)
                  Expanded(
                    child: Center(
                      child: Text(
                        bingoColumnLetters[col],
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: _columnTints[col],
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.6),
                              offset: const Offset(0, 1.5),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 5x5 grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                children: List.generate(5, (row) {
                  return Expanded(
                    child: Row(
                      children: List.generate(5, (col) {
                        return Expanded(
                          child: _cell(card, game, row, col),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Deterministic per-cell daub tilt in radians (~±5°) — every
  /// stamp looks hand-placed but stays stable across rebuilds.
  double _daubTilt(int index) => (((index * 37) % 11) - 5) * math.pi / 180;

  Widget _cell(BingoCard card, BingoGame game, int row, int col) {
    final index = row * 5 + col;
    final isFree = row == 2 && col == 2;
    final cellValue = card.cardNumbers[row][col];
    final isMarked = card.isCellMarked(row, col);
    final isCalled = cellValue != null && game.numbersCalled.contains(cellValue);
    final canTap = !isFree && cellValue != null && isCalled && !isMarked;

    // Cell surface: uncalled cells read as subtly raised paper
    // (white top-light); called-but-unmarked cells sit slightly
    // dimmed so the glowing "last called" pill and the daub stamps
    // carry the visual hierarchy.
    final BoxDecoration surface;
    if (isMarked) {
      surface = BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      );
    } else if (isCalled) {
      surface = BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: 0.24),
            Colors.black.withValues(alpha: 0.36),
          ],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: KinrelColors.amber.withValues(alpha: 0.45),
          width: 1.25,
        ),
      );
    } else {
      surface = BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.04),
            Colors.black.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      );
    }

    return GestureDetector(
      onTap: canTap
          ? () => ref
              .read(bingoProvider(widget.familyId).notifier)
              .toggleMark(cellValue)
          : null,
      child: AnimatedContainer(
        duration: GameMotionTokens.fast,
        margin: const EdgeInsets.all(2),
        decoration: surface,
        child: Stack(
          children: [
            // Daub stamp — filled circle badge with a slight tilt,
            // accent gradient fill, white ring and drop shadow.
            if (isMarked)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Transform.rotate(
                    angle: _daubTilt(index),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isFree
                            ? KinrelGradients.igniteGradient
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color.lerp(
                                    KinrelColors.orange,
                                    Colors.white,
                                    0.30,
                                  )!,
                                  KinrelColors.orange,
                                  KinrelColors.ember,
                                ],
                              ),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                          BoxShadow(
                            color: KinrelColors.orangeGlowIntense,
                            blurRadius: 7,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Center(
              child: isFree
                  ? Text(
                      'FREE',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    )
                  : Text(
                      cellValue != null ? '$cellValue' : '',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: isMarked
                            ? Colors.white
                            : (isCalled
                                  ? KinrelColors.textSilver
                                  : KinrelColors.textDim),
                        shadows: isMarked
                            ? [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    ),
            ),
          ],
        ),
      )
          .animate(target: isMarked ? 1 : 0)
          .scale(
            begin: const Offset(0.92, 0.92),
            end: const Offset(1.0, 1.0),
            duration: 200.ms,
            curve: Curves.elasticOut,
          ),
    );
  }

  Widget _bingoButton(BingoState state, bool canClaim, String? myId) {
    // If claim was invalid, shake the button ONCE per claim (the flag
    // resets whenever the feedback banner clears).
    if (state.lastClaimValid == false && !_shakeTriggered) {
      _shakeTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerShake();
      });
    } else if (state.lastClaimValid != false) {
      _shakeTriggered = false;
    }

    final isClaiming = state.isClaiming;
    final hasClaimed = state.myCard?.hasClaimed ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: [
          if (state.lastClaimValid == false && state.lastClaimReason != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Invalid: ${state.lastClaimReason}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              final shakeOffset = _shakeController.isAnimating
                  ? (math.sin(_shakeController.value * 3 * math.pi) * 8)
                  : 0.0;
              return Transform.translate(
                offset: Offset(shakeOffset, 0),
                child: child,
              );
            },
            child: SizedBox(
              width: double.infinity,
              height: 60,
              child: FilledButton(
                onPressed: (hasClaimed || isClaiming)
                    ? null
                    : (canClaim
                          ? () => ref
                              .read(bingoProvider(widget.familyId).notifier)
                              .claimBingo()
                          : () {
                              // Tapped without a valid pattern — gentle feedback
                              _triggerShake();
                            }),
                style: FilledButton.styleFrom(
                  backgroundColor: canClaim
                      ? KinrelColors.orange
                      : KinrelColors.darkElevated,
                  foregroundColor: canClaim ? Colors.white : KinrelColors.textDim,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(KinrelRadius.lg),
                  ),
                ),
                child: isClaiming
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : hasClaimed
                    ? const Text(
                        'Claimed ✓',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      )
                    : Text(
                        canClaim ? 'BINGO!' : 'Tap matching numbers',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: canClaim
                              ? Colors.white
                              : KinrelColors.textDim,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerTile(BingoCard card, String? myId, String? hostUserId) {
    final isMe = card.playerId == myId;
    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.md,
      ),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(
          color: isMe ? KinrelColors.orange : KinrelColors.border,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          DKAvatar(
            initials: card.playerName.isNotEmpty
                ? card.playerName[0].toUpperCase()
                : '?',
          ),
          const SizedBox(width: KinrelSpacing.md),
          Expanded(
            child: Text(
              isMe ? '${card.playerName} (You)' : card.playerName,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
          if (card.playerId == hostUserId)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: KinrelColors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'HOST',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  color: KinrelColors.orange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
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

  // ── Results view (inline when game completes) ─────────────────────

  Widget _resultsView(BingoState state, String? myId) {
    final game = state.game!;
    final isWinner = game.winnerPlayerId == myId;
    final isDraw = game.winnerPlayerId == null;
    final winnerName = game.winnerPlayerName ?? 'Player';

    return DKScaffold(
      gradient: isWinner ? KinrelGradients.deepFireGradient : null,
      backgroundColor: isWinner ? null : KinrelColors.darkSurface,
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
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            children: [
              const SizedBox(height: KinrelSpacing.lg),
              _winnerBanner(isWinner, winnerName, isDraw)
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .scale(
                    begin: const Offset(0.92, 0.92),
                    end: const Offset(1.0, 1.0),
                    duration: 400.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(height: KinrelSpacing.xl),
              // Stats
              _statsCard(game),
              MatchEcosystemSummary(
                gameTable: 'bingo_games',
                gameId: widget.gameId,
                familyId: widget.familyId,
              ),
              const SizedBox(height: KinrelSpacing.xxl),
              DKButton(
                label: 'Play Again',
                variant: DKButtonVariant.gradient,
                fullWidth: true,
                icon: Icons.refresh_rounded,
                onPressed: () {
                  ref.read(bingoProvider(widget.familyId).notifier).leaveGame();
                  if (context.mounted) {
                    context.pushReplacement(
                      '/family/${widget.familyId}/bingo/lobby',
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
                  ref.read(bingoProvider(widget.familyId).notifier).leaveGame();
                  if (context.mounted) {
                    context.go('/games?familyId=${widget.familyId}');
                  }
                },
              ),
            ],
          ),
          // A bingo win is THE celebration — triple confetti volley in
          // the accent-tinted palette.
          if (isWinner)
            Positioned.fill(
              child: IgnorePointer(
                child: GameConfetti(
                  colors: confettiPaletteFor(KinrelColors.orange),
                  burstCount: 3,
                  density: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _winnerBanner(bool isWinner, String winnerName, bool isDraw) {
    return Column(
      children: [
        Icon(
          isDraw ? Icons.grid_on_rounded : Icons.emoji_events,
          size: 60,
          color: isDraw ? KinrelColors.textDim : KinrelColors.gold,
        )
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
          isDraw
              ? 'Board Ran Out!'
              : isWinner
                  ? 'You Won!'
                  : 'Winner!',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: KinrelColors.textWhite,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isDraw
              ? 'Nobody shouted BINGO — all 75 numbers were called'
              : isWinner
                  ? '$winnerName (You)'
                  : winnerName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: isDraw ? 14 : 22,
            fontWeight: FontWeight.w600,
            color: isDraw ? KinrelColors.textDim : KinrelColors.orange,
          ),
        ),
      ],
    );
  }

  Widget _statsCard(BingoGame game) {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        children: [
          _statRow('Win Pattern', game.winPattern.label),
          const Divider(height: 24),
          _statRow('Numbers Called', '${game.numbersCalled.length}/75'),
          const Divider(height: 24),
          _statRow('Call Speed', '${game.callIntervalSeconds}s/number'),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textDim,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: KinrelColors.textWhite,
          ),
        ),
      ],
    );
  }
}
