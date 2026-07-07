// lib/features/games/bingo/bingo_board_screen.dart
//
// Bingo — main board screen with:
//   • Player's own 5x5 card (tappable cells with mark animation)
//   • Large display of the most recently called number
//   • Scrollable history of all called numbers
//   • BINGO! button (enabled when client detects potential win)
//   • Inline results view with winner confetti
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
import '../shared/widgets/badges_toast.dart';
import 'bingo_models.dart';
import 'bingo_provider.dart';

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
  bool _badgesChecked = false;

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
    });
  }

  @override
  void dispose() {
    _numberPulseController.dispose();
    _shakeController.dispose();
    _shakeTimer?.cancel();
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
          onPressed: () {
            ref.read(bingoProvider(widget.familyId).notifier).leaveGame();
            Navigator.of(context).pop();
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
          // Last called number display
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
          // BINGO button + claim feedback
          _bingoButton(state, canClaim, myId),
          const SizedBox(height: KinrelSpacing.base),
        ],
      ),
    );
  }

  Widget _calledNumberDisplay(int? lastNumber) {
    final letter = lastNumber != null ? letterForNumber(lastNumber) : '';
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
          const SizedBox(height: 4),
          ScaleTransition(
            scale: Tween<double>(begin: 0.5, end: 1.0).animate(
              CurvedAnimation(
                parent: _numberPulseController,
                curve: Curves.elasticOut,
              ),
            ),
            child: Row(
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

  Widget _bingoCard(BingoCard card, BingoGame game) {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.orange, width: 2),
      ),
      child: Column(
        children: [
          // B-I-N-G-O header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: KinrelColors.orange,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(KinrelRadius.lg - 2),
              ),
            ),
            child: Row(
              children: bingoColumnLetters.map((letter) {
                return Expanded(
                  child: Center(
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              }).toList(),
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

  Widget _cell(BingoCard card, BingoGame game, int row, int col) {
    final isFree = row == 2 && col == 2;
    final cellValue = card.cardNumbers[row][col];
    final isMarked = card.isCellMarked(row, col);
    final isCalled = cellValue != null && game.numbersCalled.contains(cellValue);
    final canTap = !isFree && cellValue != null && isCalled && !isMarked;

    return GestureDetector(
      onTap: canTap
          ? () => ref
              .read(bingoProvider(widget.familyId).notifier)
              .toggleMark(cellValue!)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isFree
              ? KinrelColors.orange
              : (isMarked
                    ? KinrelColors.success.withValues(alpha: 0.3)
                    : (isCalled
                          ? KinrelColors.orange.withValues(alpha: 0.15)
                          : KinrelColors.darkElevated)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isMarked
                ? KinrelColors.success
                : (isCalled ? KinrelColors.orange.withValues(alpha: 0.5) : KinrelColors.border),
            width: isMarked ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: isFree
                  ? Text(
                      'FREE',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      cellValue != null ? '$cellValue' : '',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: isMarked
                            ? KinrelColors.success
                            : (isCalled
                                  ? KinrelColors.textWhite
                                  : KinrelColors.textDim),
                      ),
                    ),
            ),
            // Checkmark stamp when marked
            if (isMarked && !isFree)
              Positioned(
                right: 2,
                top: 2,
                child: Icon(
                  Icons.check_circle,
                  size: 14,
                  color: KinrelColors.success,
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
    // If claim was invalid, shake the button
    if (state.lastClaimValid == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerShake();
      });
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
      body: ListView(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        children: [
          const SizedBox(height: KinrelSpacing.lg),
          _winnerBanner(isWinner, winnerName)
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
    );
  }

  Widget _winnerBanner(bool isWinner, String winnerName) {
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
          isWinner ? 'You Won!' : 'Winner!',
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
          isWinner ? '$winnerName (You)' : winnerName,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: KinrelColors.orange,
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
