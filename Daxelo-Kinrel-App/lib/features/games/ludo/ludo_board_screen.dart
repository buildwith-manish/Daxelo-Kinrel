// lib/features/games/ludo/ludo_board_screen.dart
//
// Ludo — main board screen with:
//   • 15×15 grid board (cross-shaped, 4 home bases, shared track, home columns)
//   • Dice component with tumbling animation
//   • Tappable tokens when a legal move exists
//   • Turn indicator with color
//   • Token movement + capture animations
//   • Inline results view with confetti
// Route: /family/$familyId/ludo/board/:gameId

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
import 'ludo_game_logic.dart';
import 'ludo_models.dart';
import 'ludo_provider.dart';

class LudoBoardScreen extends ConsumerStatefulWidget {
  const LudoBoardScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<LudoBoardScreen> createState() => _LudoBoardScreenState();
}

class _LudoBoardScreenState extends ConsumerState<LudoBoardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _diceAnimController;
  int _displayDiceValue = 1;
  Timer? _diceTimer;

  @override
  void initState() {
    super.initState();
    _diceAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(ludoProvider(widget.familyId));
      if (state.game == null) {
        ref.read(ludoProvider(widget.familyId).notifier).joinGame(widget.gameId);
      }
    });
  }

  @override
  void dispose() {
    _diceAnimController.dispose();
    _diceTimer?.cancel();
    super.dispose();
  }

  /// Animate the dice tumbling before settling on the final value.
  void _animateDice(int finalValue) {
    _diceTimer?.cancel();
    var ticks = 0;
    _diceTimer = Timer.periodic(const Duration(milliseconds: 80), (t) {
      ticks++;
      if (ticks >= 10) {
        t.cancel();
        setState(() => _displayDiceValue = finalValue);
        GameMotionTokens.success();
      } else {
        setState(() => _displayDiceValue = (ticks % 6) + 1);
      }
    });
  }

  Color _colorValue(LudoColor c) {
    switch (c) {
      case LudoColor.red:
        return const Color(0xFFEF4444);
      case LudoColor.blue:
        return const Color(0xFF3B82F6);
      case LudoColor.green:
        return const Color(0xFF10B981);
      case LudoColor.yellow:
        return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ludoProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    // Animate dice when a new roll comes in
    if (state.lastRollResult != null && state.lastRollResult != _displayDiceValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _animateDice(state.lastRollResult!);
      });
    }

    // Show results inline when game completes
    if (state.isCompleted) {
      return _resultsView(state, myId);
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            ref.read(ludoProvider(widget.familyId).notifier).leaveGame();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'Ludo',
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
                  .read(ludoProvider(widget.familyId).notifier)
                  .joinGame(widget.gameId),
            )
          : state.game == null
          ? const Center(
              child: CircularProgressIndicator(color: KinrelColors.orange),
            )
          : state.isWaiting
              ? _waitingRoom(state, myId)
              : _gameView(state, myId),
    );
  }

  // ── Waiting room ──────────────────────────────────────────────────

  Widget _waitingRoom(LudoState state, String? myId) {
    final game = state.game!;
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
              Text('Share Code',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: KinrelSpacing.sm),
              Text(code,
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
        Text('Players (${state.players.length}/${game.playerCount})',
          style: TextStyle(
            fontFamily: KinrelTypography.displayFont,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: KinrelColors.textDim,
          ),
        ),
        const SizedBox(height: KinrelSpacing.sm),
        ...state.players.map((p) => Container(
          margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: KinrelSpacing.md,
            vertical: KinrelSpacing.md,
          ),
          decoration: BoxDecoration(
            color: KinrelColors.darkCard,
            borderRadius: BorderRadius.circular(KinrelRadius.lg),
            border: Border.all(
              color: p.userId == myId ? KinrelColors.orange : KinrelColors.border,
              width: p.userId == myId ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              DKAvatar(initials: p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?'),
              const SizedBox(width: KinrelSpacing.md),
              Expanded(
                child: Text(
                  p.userId == myId ? '${p.userName} (You)' : p.userName,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _colorValue(p.color),
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
            ],
          ),
        )),
        const SizedBox(height: KinrelSpacing.xl),
        if (isHost)
          DKButton(
            label: canStart ? 'Start Game' : 'Waiting for players…',
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            onPressed: canStart
                ? () => ref.read(ludoProvider(widget.familyId).notifier).startGame()
                : null,
          )
        else
          _waitingIndicator(),
      ],
    );
  }

  // ── Active game view ──────────────────────────────────────────────

  Widget _gameView(LudoState state, String? myId) {
    final game = state.game!;
    final isMyTurn = game.currentTurnPlayerId == myId;
    final currentTurnPlayer = state.players
        .where((p) => p.userId == game.currentTurnPlayerId)
        .firstOrNull;
    final turnColor = currentTurnPlayer?.color ?? LudoColor.red;
    final hasRolled = game.lastDiceRoll != null;
    final legalTokens = state.getLegalTokensForMe(myId);

    return SafeArea(
      child: Column(
        children: [
          // Turn indicator
          _turnIndicator(game, isMyTurn, currentTurnPlayer?.userName ?? 'Player', turnColor),
          // Board
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(KinrelSpacing.sm),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: _board(state, myId, legalTokens),
                ),
              ),
            ),
          ),
          // Dice + status
          _diceAndStatusBar(state, myId, isMyTurn, hasRolled, legalTokens),
          const SizedBox(height: KinrelSpacing.base),
        ],
      ),
    );
  }

  Widget _turnIndicator(LudoGame game, bool isMyTurn, String name, LudoColor color) {
    return Container(
      margin: const EdgeInsets.all(KinrelSpacing.base),
      padding: const EdgeInsets.symmetric(
        horizontal: KinrelSpacing.md,
        vertical: KinrelSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _colorValue(color).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: _colorValue(color), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _colorValue(color),
            ),
          ),
          const SizedBox(width: KinrelSpacing.sm),
          Text(
            isMyTurn
                ? 'Your turn (${color.name.toUpperCase()})'
                : '$name\'s turn (${color.name.toUpperCase()})',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (game.consecutiveSixes > 0) ...[
            const SizedBox(width: KinrelSpacing.sm),
            Text(
              '6×${game.consecutiveSixes}',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 11,
                color: KinrelColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _board(LudoState state, String? myId, List<LudoToken> legalTokens) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        border: Border.all(color: KinrelColors.orange, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(KinrelRadius.lg - 2),
        child: Stack(
          children: [
            // Board grid (15×15)
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 15,
              ),
              itemCount: 225,
              itemBuilder: (context, index) {
                final row = index ~/ 15;
                final col = index % 15;
                return _boardCell(row, col, state, legalTokens);
              },
            ),
            // Tokens overlaid on the board
            ..._tokenWidgets(state, myId, legalTokens),
          ],
        ),
      ),
    );
  }

  Widget _boardCell(int row, int col, LudoState state, List<LudoToken> legalTokens) {
    // Determine cell type
    final isHomeBase = _isHomeBase(row, col);
    final isTrack = _isTrackSquare(row, col);
    final isHomeColumn = _isHomeColumnSquare(row, col);
    final isCenter = row == 7 && col == 7;
    final isSafeSquare = _isSafeSquare(row, col);

    // Determine color for home bases and home columns
    Color bgColor;
    if (isCenter) {
      bgColor = KinrelColors.orange;
    } else if (isHomeBase) {
      bgColor = _homeBaseColor(row, col).withValues(alpha: 0.3);
    } else if (isHomeColumn) {
      bgColor = _homeColumnColor(row, col).withValues(alpha: 0.3);
    } else if (isTrack) {
      bgColor = Colors.white;
    } else {
      bgColor = const Color(0xFF2A2A3D);
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: isSafeSquare && isTrack
          ? const Center(child: Icon(Icons.star, size: 8, color: Color(0xFF8B5CF6)))
          : null,
    );
  }

  bool _isHomeBase(int row, int col) {
    // Top-left (Red): 0-5, 0-5
    // Top-right (Blue): 0-5, 9-14
    // Bottom-left (Yellow): 9-14, 0-5
    // Bottom-right (Green): 9-14, 9-14
    return (row < 6 && col < 6) ||
        (row < 6 && col > 8) ||
        (row > 8 && col < 6) ||
        (row > 8 && col > 8);
  }

  bool _isTrackSquare(int row, int col) {
    return trackCoordinates.any((r, c) => r == row && c == col);
  }

  bool _isHomeColumnSquare(int row, int col) {
    for (final entry in homeColumnCoordinates.entries) {
      if (entry.value.any((r, c) => r == row && c == col)) return true;
    }
    return false;
  }

  bool _isSafeSquare(int row, int col) {
    // Check if this (row, col) corresponds to a safe absolute position
    for (int abs = 0; abs < trackCoordinates.length; abs++) {
      if (trackCoordinates[abs].$1 == row && trackCoordinates[abs].$2 == col) {
        return safeSquares.contains(abs);
      }
    }
    return false;
  }

  LudoColor _homeBaseColor(int row, int col) {
    if (row < 6 && col < 6) return LudoColor.red;
    if (row < 6 && col > 8) return LudoColor.blue;
    if (row > 8 && col < 6) return LudoColor.yellow;
    if (row > 8 && col > 8) return LudoColor.green;
    return LudoColor.red;
  }

  LudoColor _homeColumnColor(int row, int col) {
    for (final entry in homeColumnCoordinates.entries) {
      if (entry.value.any((r, c) => r == row && c == col)) return entry.key;
    }
    return LudoColor.red;
  }

  List<Widget> _tokenWidgets(LudoState state, String? myId, List<LudoToken> legalTokens) {
    final widgets = <Widget>[];
    for (final token in state.allLogicTokens) {
      final coord = positionToGridCoord(token);
      if (coord == null) continue;

      final isLegal = legalTokens.any((t) => t.id == token.id);
      final isMyToken = token.playerId == myId;

      widgets.add(
        Positioned(
          left: (coord.$2 / 15) * 1000,  // will be scaled by the parent
          top: (coord.$1 / 15) * 1000,
          child: FractionalTranslation(
            translation: const Offset(0, 0),
            child: SizedBox(
              width: 1000 / 15,
              height: 1000 / 15,
              child: _tokenWidget(
                token,
                isLegal && isMyToken,
                state,
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _tokenWidget(LudoToken token, bool isTappable, LudoState state) {
    final color = _colorValue(token.color);
    final player = state.players.where((p) => p.userId == token.playerId).firstOrNull;
    final isMyToken = token.playerId == _myId(state);

    return GestureDetector(
      onTap: isTappable
          ? () => ref.read(ludoProvider(widget.familyId).notifier).moveToken(token.id)
          : null,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: isTappable ? Colors.white : Colors.white.withValues(alpha: 0.5),
            width: isTappable ? 2.5 : 1.5,
          ),
          boxShadow: isTappable
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: token.isFinished
            ? const Center(child: Icon(Icons.check, size: 8, color: Colors.white))
            : null,
      )
          .animate(target: isTappable ? 1 : 0)
          .scale(
            begin: const Offset(0.9, 0.9),
            end: const Offset(1.0, 1.0),
            duration: 300.ms,
            curve: Curves.elasticOut,
          ),
    );
  }

  String? _myId(LudoState state) {
    return ref.read(supabaseProvider)?.auth.currentUser?.id;
  }

  Widget _diceAndStatusBar(
    LudoState state,
    String? myId,
    bool isMyTurn,
    bool hasRolled,
    List<LudoToken> legalTokens,
  ) {
    final game = state.game!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Column(
        children: [
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                state.error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (state.lastCapture != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Captured ${state.lastCapture}\'s token!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Dice
              _diceWidget(state, isMyTurn, hasRolled),
              // Status
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isMyTurn && !hasRolled)
                    Text(
                      'Tap the dice to roll!',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textWhite,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (isMyTurn && hasRolled)
                    Text(
                      legalTokens.isEmpty
                          ? 'No moves — passing turn…'
                          : 'Tap a glowing token to move',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: legalTokens.isEmpty
                            ? KinrelColors.warning
                            : KinrelColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    Text(
                      'Waiting for opponent…',
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 13,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  // Finished tokens count
                  ...state.players.map((p) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _colorValue(p.color),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${p.tokensFinished}/4',
                          style: TextStyle(
                            fontFamily: KinrelTypography.monoFont,
                            fontSize: 10,
                            color: KinrelColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _diceWidget(LudoState state, bool isMyTurn, bool hasRolled) {
    final canRoll = isMyTurn && !hasRolled && !state.isRolling;
    final displayValue = hasRolled ? (state.game?.lastDiceRoll ?? _displayDiceValue) : _displayDiceValue;

    return GestureDetector(
      onTap: canRoll
          ? () => ref.read(ludoProvider(widget.familyId).notifier).rollDice()
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: canRoll ? KinrelColors.orange : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: canRoll ? Colors.white : KinrelColors.border,
            width: canRoll ? 2 : 1,
          ),
          boxShadow: canRoll
              ? [
                  BoxShadow(
                    color: KinrelColors.orangeGlowIntense,
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: state.isRolling
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  '$displayValue',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: canRoll ? Colors.white : KinrelColors.textWhite,
                  ),
                ),
        ),
      )
          .animate(target: state.isRolling ? 1 : 0)
          .rotate(
            begin: 0,
            end: 1,
            duration: 80.ms,
            curve: Curves.linear,
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

  // ── Results view ──────────────────────────────────────────────────

  Widget _resultsView(LudoState state, String? myId) {
    final game = state.game!;
    final isWinner = game.winnerId == myId;
    final winnerName = game.winnerName ?? 'Player';

    return DKScaffold(
      gradient: isWinner ? KinrelGradients.deepFireGradient : null,
      backgroundColor: isWinner ? null : KinrelColors.darkSurface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Results',
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
          Column(
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
          )
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(
                begin: const Offset(0.92, 0.92),
                end: const Offset(1.0, 1.0),
                duration: 400.ms,
                curve: Curves.easeOutBack,
              ),
          const SizedBox(height: KinrelSpacing.xxl),
          DKButton(
            label: 'Play Again',
            variant: DKButtonVariant.gradient,
            fullWidth: true,
            icon: Icons.refresh_rounded,
            onPressed: () {
              ref.read(ludoProvider(widget.familyId).notifier).leaveGame();
              if (context.mounted) {
                context.pushReplacement(
                  '/family/${widget.familyId}/ludo/lobby',
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
              ref.read(ludoProvider(widget.familyId).notifier).leaveGame();
              if (context.mounted) {
                context.go('/games?familyId=${widget.familyId}');
              }
            },
          ),
        ],
      ),
    );
  }
}
