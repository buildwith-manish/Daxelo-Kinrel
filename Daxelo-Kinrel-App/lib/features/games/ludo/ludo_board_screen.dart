import '../../../core/widgets/person_avatar.dart';
// lib/features/games/ludo/ludo_board_screen.dart
//
// Ludo — main board screen with:
//   • 15×15 grid board (cross-shaped, 4 home bases, shared track, home columns)
//   • Dice component with tumbling animation
//   • Tappable tokens when a legal move exists
//   • Turn indicator with color
//   • Token movement + capture animations
//   • Inline results view with confetti
// Premium finish: wooden GameBoardShell table frame, radially-lit home
// bases (painter-level glow pools), glowing safe-square emblems, 3D
// token chips in the four player colours, an ivory radial-gradient die
// with drilled pips, and a physics GameConfetti volley for the winner.
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
import '../shared/icons/kinrel_icons.dart';
import '../shared/services/temporary_room_service.dart';
import '../shared/widgets/game_board_shell.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/leave_game_dialog.dart';
import 'ludo_game_logic.dart';
import 'ludo_models.dart';
import 'ludo_provider.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';

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

  /// Original Kinrel-branded color mapping for the four Ludo players.
  /// Instead of generic red/blue/green/yellow, uses Kinrel's existing
  /// brand palette adapted for 4 distinct but cohesive player colors.
  Color _colorValue(LudoColor c) {
    switch (c) {
      case LudoColor.red:
        return KinrelColors.orange;     // #E8612A — "Ember"
      case LudoColor.blue:
        return KinrelColors.blue;       // #3B82F6 — "Azure"
      case LudoColor.green:
        return KinrelColors.tealAccent; // #2DD4BF — "Jade"
      case LudoColor.yellow:
        return KinrelColors.gold;       // #D4AF37 — "Gold"
    }
  }

  /// Physical 3D token chip in the player's colour — radially lit with
  /// a specular highlight, dark rim and grounded drop shadow. Movable
  /// tokens glow so the next move is obvious at a glance.
  Widget _tokenWidget(LudoToken token, bool isTappable, double cellSize) {
    final color = _colorValue(token.color);
    final size = cellSize * 0.84;

    return GestureDetector(
      onTap: isTappable
          ? () => ref.read(ludoProvider(widget.familyId).notifier).moveToken(token.id)
          : null,
      child: GamePiece3D(
        color: color,
        size: size,
        glow: isTappable,
        ring: isTappable ? Colors.white : null,
        child: token.isFinished
            ? const Icon(Icons.check, size: 8, color: Colors.white)
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
          onPressed: () async {
            final state = ref.read(ludoProvider(widget.familyId));
            final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
            final shouldLeave = await LeaveGameDialog.show(
              context,
              isHost: (state.game?.hostUserId == myId),
              gameName: 'Ludo',
            );
            if (shouldLeave != true) return;
            if (!context.mounted) return;
            unawaited(
              ref.read(ludoProvider(widget.familyId).notifier).leaveGame(),
            );
            if (state.game?.id != null) {
              unawaited(
                ref.read(temporaryRoomServiceProvider).endGame(
                  gameTable: 'ludo_games',
                  gameId: state.game!.id,
                ),
              );
            }
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/family/${widget.familyId}');
            }
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
              DKAvatar(initials: PersonAvatar.initialsFor(p.userName)),
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
    // Premium wooden table frame — classic Ludo board presentation with
    // a bevelled rim, grain and warm accent under-glow.
    return GameBoardShell(
      accent: KinrelColors.orange,
      surface: BoardSurface.wood,
      radius: 22,
      padding: 8,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The board is square (AspectRatio 1:1) — measure it once and
          // place tokens in real pixel space so they sit exactly on their
          // cells at every screen size.
          final boardSize = constraints.maxWidth;
          return Stack(
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
              // Radial colour pools for the four home bases — colours come
              // from the same quadrant mapping the board used before.
              Positioned.fill(
                child: CustomPaint(
                  painter: _LudoBaseGlowPainter(
                    colors: [
                      _colorValue(_homeBaseColor(2, 2)), // top-left yard
                      _colorValue(_homeBaseColor(2, 11)), // top-right yard
                      _colorValue(_homeBaseColor(11, 2)), // bottom-left yard
                      _colorValue(_homeBaseColor(11, 11)), // bottom-right yard
                    ],
                  ),
                ),
              ),
              // Tokens overlaid on the board
              ..._tokenWidgets(state, myId, legalTokens, boardSize),
            ],
          );
        },
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

    // Original color scheme using Kinrel brand palette
    Color bgColor;
    if (isCenter) {
      bgColor = KinrelColors.darkCard; // center is dark with a gradient overlay
    } else if (isHomeBase) {
      // Flat alpha tint replaced by the radial base-glow painter that
      // lights each 6×6 yard from its centre (see _LudoBaseGlowPainter).
      bgColor = KinrelColors.darkElevated;
    } else if (isHomeColumn) {
      bgColor = _colorValue(_homeColumnColor(row, col)).withValues(alpha: 0.25);
    } else if (isTrack) {
      bgColor = KinrelColors.darkElevated; // track squares are elevated, not white
    } else {
      bgColor = KinrelColors.darkBackground; // non-board areas are background
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(
          color: isTrack || isHomeColumn
              ? KinrelColors.border.withValues(alpha: 0.5)
              : Colors.transparent,
          width: 0.5,
        ),
      ),
      child: _cellContent(row, col, isCenter, isSafeSquare, isTrack, isHomeBase),
    );
  }

  /// Original cell content — diamond markers for safe squares (not star icons),
  /// gradient center zone, and rounded home-base outlines.
  Widget _cellContent(int row, int col, bool isCenter, bool isSafe, bool isTrack, bool isHomeBase) {
    if (isCenter) {
      // Center finish zone — original diamond/star pattern with gradient
      return Container(
        decoration: BoxDecoration(
          gradient: KinrelGradients.igniteGradient,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Transform.rotate(
            angle: 0.785398, // 45° — diamond orientation
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
    }

    if (isSafe && isTrack) {
      // Safe square marker — original diamond emblem, now with a soft
      // amber glow so safe havens read instantly.
      return Center(
        child: Transform.rotate(
          angle: 0.785398, // 45° — diamond orientation
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: KinrelColors.amber.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(1.5),
              boxShadow: [
                BoxShadow(
                  color: KinrelColors.amber.withValues(alpha: 0.55),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
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
    return trackCoordinates.any((cell) => cell.$1 == row && cell.$2 == col);
  }

  bool _isHomeColumnSquare(int row, int col) {
    for (final entry in homeColumnCoordinates.entries) {
      if (entry.value.any((cell) => cell.$1 == row && cell.$2 == col)) return true;
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
      if (entry.value.any((cell) => cell.$1 == row && cell.$2 == col)) return entry.key;
    }
    return LudoColor.red;
  }

  List<Widget> _tokenWidgets(
    LudoState state,
    String? myId,
    List<LudoToken> legalTokens,
    double boardSize,
  ) {
    // Place each token exactly on its grid cell: cell = boardSize / 15,
    // the 3D chip fills ~84% of the cell and is centred within it.
    final cellSize = boardSize / 15;
    final widgets = <Widget>[];
    for (final token in state.allLogicTokens) {
      final coord = positionToGridCoord(token);
      if (coord == null) continue;

      final isLegal = legalTokens.any((t) => t.id == token.id);
      final isMyToken = token.playerId == myId;

      widgets.add(
        Positioned(
          left: coord.$2 * cellSize,
          top: coord.$1 * cellSize,
          width: cellSize,
          height: cellSize,
          child: Center(
            child: _tokenWidget(token, isLegal && isMyToken, cellSize),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _diceAndStatusBar(
    LudoState state,
    String? myId,
    bool isMyTurn,
    bool hasRolled,
    List<LudoToken> legalTokens,
  ) {
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

  /// Dice — ivory radial-gradient face with drilled pips and a grounded
  /// drop shadow; keeps the tumble animation. The whole die glows when
  /// it's your roll.
  Widget _diceWidget(LudoState state, bool isMyTurn, bool hasRolled) {
    final canRoll = isMyTurn && !hasRolled && !state.isRolling;
    final displayValue = hasRolled ? (state.game?.lastDiceRoll ?? _displayDiceValue) : _displayDiceValue;

    return GestureDetector(
      onTap: canRoll
          ? () => ref.read(ludoProvider(widget.familyId).notifier).rollDice()
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          // Ivory die face — radially lit so it reads as a rounded cube.
          gradient: const RadialGradient(
            center: Alignment(-0.35, -0.4),
            radius: 1.15,
            colors: [Color(0xFFFFF8E7), Color(0xFFF3E7CE), Color(0xFFD9CDB8)],
            stops: [0.0, 0.55, 1.0],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: canRoll ? KinrelColors.orange : const Color(0xFFB9AB90),
            width: canRoll ? 2.5 : 1.5,
          ),
          boxShadow: [
            if (canRoll)
              BoxShadow(
                color: KinrelColors.orangeGlowIntense,
                blurRadius: 10,
                spreadRadius: 2,
              ),
            // Grounded drop shadow under the whole die.
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: state.isRolling
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KinrelColors.orange,
                  ),
                )
              : _dicePips(displayValue, canRoll),
        ),
      )
          .animate(target: state.isRolling ? 1 : 0)
          .rotate(
            begin: 0,
            end: 1,
            duration: 80.ms,
            curve: Curves.linear,
          )
          .scale(
            begin: const Offset(0.95, 0.95),
            end: const Offset(1.0, 1.0),
            duration: 200.ms,
            curve: GameMotionTokens.bounce,
          ),
    );
  }

  /// Render dice pips (dots) for values 1-6 — original layout with a
  /// drilled-pip finish: white fill, dark rim and a tiny inset shadow.
  Widget _dicePips(int value, bool isActive) {
    final pipRim = isActive ? const Color(0xFF4A3F2E) : const Color(0xFF7A6E58);
    final pipSize = 6.0;

    Widget pip() => Container(
      width: pipSize,
      height: pipSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: pipRim, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );

    // Pip layouts: standard dice patterns
    switch (value) {
      case 1:
        return pip();
      case 2:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.start, children: [pip()]),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [pip()]),
          ],
        );
      case 3:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.start, children: [pip()]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [pip()]),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [pip()]),
          ],
        );
      case 4:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip(), pip()]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip(), pip()]),
          ],
        );
      case 5:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip(), pip()]),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [pip()]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip(), pip()]),
          ],
        );
      case 6:
      default:
        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip(), pip()]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip(), pip()]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [pip(), pip()]),
          ],
        );
    }
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
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(KinrelSpacing.base),
            children: [
              const SizedBox(height: KinrelSpacing.lg),
              Column(
                children: [
                  const KinrelIcon(KinrelIconData.trophy,
                    size: 64, color: KinrelColors.brightGold)
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
              MatchEcosystemSummary(
                gameTable: 'ludo_games',
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
          // Physics confetti volley (density 2) for the winner.
          if (game.winnerId != null)
            const Positioned.fill(
              child: IgnorePointer(
                child: GameConfetti(burstCount: 2, density: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints the four home-base radial glows — one warm pool of colour per
/// quadrant, lighter at each base's centre, so the yards read as lit
/// bowls instead of flat alpha tints. Quadrant order matches the board
/// layout: red (top-left), blue (top-right), yellow (bottom-left),
/// green (bottom-right). Static content — never repaints.
class _LudoBaseGlowPainter extends CustomPainter {
  const _LudoBaseGlowPainter({required this.colors});

  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    const quadrants = [
      (0.2, 0.2),
      (0.8, 0.2),
      (0.2, 0.8),
      (0.8, 0.8),
    ];
    for (var i = 0; i < quadrants.length && i < colors.length; i++) {
      final (fx, fy) = quadrants[i];
      // Each base spans a 6×6 cell quadrant (40% of the board).
      final rect = Rect.fromCenter(
        center: Offset(fx * s, fy * s),
        width: s * 0.4,
        height: s * 0.4,
      );
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            colors[i].withValues(alpha: 0.38),
            colors[i].withValues(alpha: 0.05),
          ],
          stops: const [0.25, 1.0],
        ).createShader(rect);
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_LudoBaseGlowPainter oldDelegate) => false;
}
