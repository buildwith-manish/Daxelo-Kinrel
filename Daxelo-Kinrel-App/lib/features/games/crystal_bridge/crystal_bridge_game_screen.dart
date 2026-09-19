// lib/features/games/crystal_bridge/crystal_bridge_game_screen.dart
//
// Crystal Bridge — main match screen.
//
// Layout (turn flow):
//   ┌──────────────────────────────────────┐
//   │  Row 3/20  ·  Timer 0:18  ·  4 alive │  ← Top HUD
//   ├──────────────────────────────────────┤
//   │  Bridge view (vertical):             │
//   │     [◇ safe]   [✕ broke]              │  ← past row (revealed)
//   │     [◇ safe]   [✕ broke]              │  ← past row (revealed)
//   │     [◆ LEFT ]  [◆ RIGHT]              │  ← CURRENT row (tappable)
//   │     [? ]       [? ]                   │  ← future (hidden)
//   │     [? ]       [? ]                   │
//   │     …                                │
//   │     [FINISH 🏁]                       │
//   ├──────────────────────────────────────┤
//   │  [🛡️ Shield — Use Power]              │  ← power button
//   │  Players: Manish ● Priya ● …          │  ← alive roster
//   │  Event log:                           │  ← scrolling events
//   │    · Manish stepped safely (row 2)    │
//   │    · Priya shattered a crystal!       │
//   └──────────────────────────────────────┘
//  OR (completed):
//   │  🏆 Manish wins!                      │
//   │  Final standings · survival · stats   │

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';
import '../../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/widgets/reactions_bar.dart';
import 'crystal_bridge_lobby_screen.dart' show kCrystalBridgeAccent;
import 'crystal_bridge_models.dart';
import 'crystal_bridge_provider.dart';

class CrystalBridgeGameScreen extends ConsumerStatefulWidget {
  const CrystalBridgeGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<CrystalBridgeGameScreen> createState() =>
      _CrystalBridgeGameScreenState();
}

class _CrystalBridgeGameScreenState
    extends ConsumerState<CrystalBridgeGameScreen> {
  Timer? _clockTimer;
  final _eventsScrollController = ScrollController();
  int _lastSeenEventCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(crystalBridgeProvider(widget.familyId).notifier)
          .loadGame(widget.gameId);
    });
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _eventsScrollController.dispose();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final state = ref.read(crystalBridgeProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId &&
          state.game?.isWaiting == true,
      gameName: 'Crystal Bridge',
    );
    if (shouldLeave == true) {
      await ref
          .read(crystalBridgeProvider(widget.familyId).notifier)
          .leaveGame();
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/family/${widget.familyId}');
        }
      }
    }
  }

  void _scrollToLatestEvent(int eventCount) {
    if (eventCount == _lastSeenEventCount) return;
    _lastSeenEventCount = eventCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_eventsScrollController.hasClients) return;
      _eventsScrollController.animateTo(
        _eventsScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(crystalBridgeProvider(widget.familyId));
    final game = state.game;

    if (state.isLoading && game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
          title: const Text('Crystal Bridge'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: const Center(
          child:
              CircularProgressIndicator(color: kCrystalBridgeAccent),
        ),
      );
    }

    if (game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/family/${widget.familyId}')),
          title: const Text('Crystal Bridge'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: Center(
          child: GamingEmptyCard(
            emoji: '🔮',
            title: 'Game not found',
            message: 'This match may have ended.',
          ),
        ),
      );
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back), onPressed: _confirmLeave),
        title: Text(
          game.roomName?.isNotEmpty == true
              ? game.roomName!
              : 'Crystal Bridge',
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
          if (game.isInProgress)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: _RowInfo(game: game)),
            ),
          if (game.hostUserId ==
                  ref.read(supabaseProvider)?.auth.currentUser?.id &&
              game.isInProgress)
            IconButton(
              tooltip: 'Leave',
              icon: const Icon(Icons.logout, size: 20),
              onPressed: _confirmLeave,
            ),
        ],
      ),
      body: game.isCompleted
          ? _ResultsView(
              game: game,
              familyId: widget.familyId,
              players: state.players,
              onRematch: () => ref
                  .read(crystalBridgeProvider(widget.familyId).notifier)
                  .rematch(),
              onExit: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/family/${widget.familyId}');
                }
              },
            )
          : _GameView(
              state: state,
              game: game,
              familyId: widget.familyId,
              eventsScrollController: _eventsScrollController,
              onScrollToLatest: _scrollToLatestEvent,
            ),
    );
  }
}

class _RowInfo extends StatelessWidget {
  const _RowInfo({required this.game});
  final CrystalBridgeGame game;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final row = board?.currentRow ?? 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kCrystalBridgeAccent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'R$row/${game.totalRows}',
        style: const TextStyle(
            fontFamily: KinrelTypography.monoFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: kCrystalBridgeAccent),
      ),
    );
  }
}

class _GameView extends ConsumerWidget {
  const _GameView({
    required this.state,
    required this.game,
    required this.familyId,
    required this.eventsScrollController,
    required this.onScrollToLatest,
  });

  final CrystalBridgeState_ state;
  final CrystalBridgeGame game;
  final String familyId;
  final ScrollController eventsScrollController;
  final void Function(int eventCount) onScrollToLatest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = game.boardState;
    if (board == null) {
      return const Center(
          child: CircularProgressIndicator(color: kCrystalBridgeAccent));
    }
    onScrollToLatest(board.events.length);

    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final isLocalTurn =
        CrystalBridgeEngine.isLocalTurn(board, myId) && !state.amSpectator;

    return Column(
      children: [
        _TopHud(game: game, board: board),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            child: Column(
              children: [
                _BridgeView(
                  board: board,
                  isLocalTurn: isLocalTurn,
                  isChoosing: state.isChoosing,
                  onChoose: (side) => ref
                      .read(crystalBridgeProvider(familyId).notifier)
                      .choose(side),
                ),
                const SizedBox(height: 14),
                _PowerButton(
                  board: board,
                  isLocalTurn: isLocalTurn,
                  isChoosing: state.isChoosing,
                  onUse: () => ref
                      .read(crystalBridgeProvider(familyId).notifier)
                      .usePower(),
                ),
                const SizedBox(height: 14),
                _PlayersStrip(board: board, myUserId: myId),
                const SizedBox(height: 14),
                _EventsLog(
                  board: board,
                  controller: eventsScrollController,
                  playerNames: {
                    for (final p in board.players) p.idx: p.name,
                  },
                ),
              ],
            ),
          ),
        ),
        if (state.amSpectator)
          ReactionsBar(
            gameTable: 'crystal_bridge_games',
            gameId: game.id,
            familyId: familyId,
          ),
      ],
    );
  }
}

class _TopHud extends StatelessWidget {
  const _TopHud({required this.game, required this.board});
  final CrystalBridgeGame game;
  final CrystalBridgeBoardState board;

  @override
  Widget build(BuildContext context) {
    final seconds = game.turnSecondsRemaining ?? 0;
    final timerColor =
        seconds <= 5 ? KinrelColors.error : kCrystalBridgeAccent;
    final currentPlayer = board.currentPlayer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(bottom: BorderSide(color: KinrelColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Row ${board.currentRow}/${board.totalRows}',
                  style: const TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: kCrystalBridgeAccent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  currentPlayer != null
                      ? '${currentPlayer.name}\'s turn'
                      : 'Waiting…',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: currentPlayer?.isAlive == true
                        ? KinrelColors.textWhite
                        : KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          _HudChip(
            icon: Icons.favorite,
            value: '${board.aliveCount}',
            label: 'alive',
            color: KinrelColors.success,
          ),
          const SizedBox(width: 8),
          if (game.isInProgress)
            _HudChip(
              icon: Icons.timer_outlined,
              value: '${seconds}s',
              label: 'turn',
              color: timerColor,
            ),
        ],
      ),
    );
  }
}

class _HudChip extends StatelessWidget {
  const _HudChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: color.withValues(alpha: 0.85))),
        ],
      ),
    );
  }
}

/// Vertical stack of bridge rows. The current row is rendered largest
/// and is the only one the current player can tap. Past rows are
/// rendered revealed (safe + shattered). Future rows are masked.
class _BridgeView extends StatelessWidget {
  const _BridgeView({
    required this.board,
    required this.isLocalTurn,
    required this.isChoosing,
    required this.onChoose,
  });

  final CrystalBridgeBoardState board;
  final bool isLocalTurn;
  final bool isChoosing;
  final void Function(int side) onChoose;

  @override
  Widget build(BuildContext context) {
    final currentRowNum = board.currentRow;
    final bridgeAccent = Color(board.bridgeType.accentArgb);

    // Render the last 3 revealed rows + the current row + next 2 hidden
    // rows + a finish marker (so the user sees progress ahead).
    final startRow = (currentRowNum - 3).clamp(1, board.totalRows);
    final endRow = (currentRowNum + 2).clamp(1, board.totalRows);
    final visibleRows = <int>[
      for (var r = endRow; r >= startRow; r--) r,
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            bridgeAccent.withValues(alpha: 0.10),
            const Color(0xFF13141E),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bridgeAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Bridge-type badge ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: bridgeAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: bridgeAccent.withValues(alpha: 0.5)),
                ),
                child: Text(
                  board.bridgeType.label.toUpperCase(),
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: bridgeAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Finish line (top) ──
          if (currentRowNum <= board.totalRows)
            _FinishMarker(
              reached: board.anyFinished,
              totalRows: board.totalRows,
            ),
          const SizedBox(height: 8),
          // ── Rows ──
          for (final rowNum in visibleRows)
            _BridgeRowView(
              row: board.rows[rowNum - 1],
              isCurrent: rowNum == currentRowNum,
              isLocalTurn: isLocalTurn,
              isChoosing: isChoosing,
              bridgeAccent: bridgeAccent,
              onChoose: onChoose,
            ),
          const SizedBox(height: 8),
          // ── Start line (bottom) ──
          const _StartMarker(),
        ],
      ),
    );
  }
}

class _FinishMarker extends StatelessWidget {
  const _FinishMarker({required this.reached, required this.totalRows});
  final bool reached;
  final int totalRows;

  @override
  Widget build(BuildContext context) {
    final color = reached ? KinrelColors.brightGold : KinrelColors.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.flag_outlined, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            reached ? 'FINISH REACHED' : 'FINISH · ROW $totalRows',
            style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: color),
          ),
        ],
      ),
    );
  }
}

class _StartMarker extends StatelessWidget {
  const _StartMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.gps_fixed, size: 12, color: KinrelColors.textDim),
          const SizedBox(width: 6),
          Text(
            'START',
            style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: KinrelColors.textDim),
          ),
        ],
      ),
    );
  }
}

class _BridgeRowView extends StatelessWidget {
  const _BridgeRowView({
    required this.row,
    required this.isCurrent,
    required this.isLocalTurn,
    required this.isChoosing,
    required this.bridgeAccent,
    required this.onChoose,
  });

  final CrystalBridgeRow row;
  final bool isCurrent;
  final bool isLocalTurn;
  final bool isChoosing;
  final Color bridgeAccent;
  final void Function(int side) onChoose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // ── Row number gutter ──
          SizedBox(
            width: 36,
            child: Text(
              '${row.rowNumber}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isCurrent
                      ? bridgeAccent
                      : KinrelColors.textDim.withValues(alpha: 0.7)),
            ),
          ),
          const SizedBox(width: 6),
          // ── Left crystal ──
          Expanded(
            child: _CrystalNode(
              side: 0,
              row: row,
              isCurrent: isCurrent,
              isLocalTurn: isLocalTurn,
              isChoosing: isChoosing,
              accent: bridgeAccent,
              onChoose: onChoose,
            ),
          ),
          const SizedBox(width: 8),
          // ── Right crystal ──
          Expanded(
            child: _CrystalNode(
              side: 1,
              row: row,
              isCurrent: isCurrent,
              isLocalTurn: isLocalTurn,
              isChoosing: isChoosing,
              accent: bridgeAccent,
              onChoose: onChoose,
            ),
          ),
        ],
      ),
    );
  }
}

/// One crystal slot. States:
///   • current row, local turn → glowing cyan, tappable
///   • current row, not local → glowing cyan, not tappable
///   • revealed + safe → solid green
///   • revealed + broken → red with shatter cracks
///   • not revealed → muted diamond outline
class _CrystalNode extends StatelessWidget {
  const _CrystalNode({
    required this.side,
    required this.row,
    required this.isCurrent,
    required this.isLocalTurn,
    required this.isChoosing,
    required this.accent,
    required this.onChoose,
  });

  final int side; // 0 = left, 1 = right
  final CrystalBridgeRow row;
  final bool isCurrent;
  final bool isLocalTurn;
  final bool isChoosing;
  final Color accent;
  final void Function(int side) onChoose;

  bool get _isSafeSide => row.safeSide == side;
  bool get _isBroken => side == 0 ? row.leftBroke : row.rightBroke;

  @override
  Widget build(BuildContext context) {
    final canTap = isCurrent && isLocalTurn && !isChoosing && !row.revealed;
    final isSafeKnown = row.revealed && _isSafeSide;
    final isBrokenKnown = row.revealed && _isBroken;

    Color glowColor;
    if (isBrokenKnown) {
      glowColor = KinrelColors.error;
    } else if (isSafeKnown) {
      glowColor = KinrelColors.success;
    } else if (isCurrent) {
      glowColor = accent;
    } else {
      glowColor = KinrelColors.textDim.withValues(alpha: 0.4);
    }

    final height = isCurrent ? 76.0 : 52.0;

    return GestureDetector(
      onTap: canTap ? () => onChoose(side) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.3),
            radius: 1.4,
            colors: [
              glowColor.withValues(alpha: isCurrent ? 0.45 : 0.20),
              glowColor.withValues(alpha: isCurrent ? 0.18 : 0.08),
            ],
          ),
          border: Border.all(
            color: glowColor.withValues(alpha: isCurrent ? 0.85 : 0.45),
            width: isCurrent ? 2.0 : 1.2,
          ),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // ── Diamond/crystal glyph ──
            CustomPaint(
              size: Size(height * 0.55, height * 0.55),
              painter: _CrystalGlyphPainter(
                color: glowColor,
                broken: isBrokenKnown,
                glowing: isCurrent,
              ),
            ),
            // ── Side label ──
            Positioned(
              bottom: 6,
              child: Text(
                side == 0 ? 'L' : 'R',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: glowColor.withValues(alpha: 0.85),
                ),
              ),
            ),
            // ── Shatter crack overlay ──
            if (isBrokenKnown)
              CustomPaint(
                size: Size(height, height),
                painter: _ShatterCracksPainter(
                  color: KinrelColors.error.withValues(alpha: 0.9),
                ),
              ),
            // ── Safe checkmark ──
            if (isSafeKnown)
              const Icon(Icons.check_circle, size: 16, color: KinrelColors.success),
            // ── Tap hint ──
            if (canTap)
              Positioned(
                top: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'TAP',
                    style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: Color(0xFF0A1224)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Diamond-shaped crystal glyph with a subtle inner facet.
class _CrystalGlyphPainter extends CustomPainter {
  _CrystalGlyphPainter({
    required this.color,
    required this.broken,
    required this.glowing,
  });

  final Color color;
  final bool broken;
  final bool glowing;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Diamond outline
    final path = Path()
      ..moveTo(cx, 0)
      ..lineTo(w, cy)
      ..lineTo(cx, h)
      ..lineTo(0, cy)
      ..close();

    // Fill (radial gradient — glowing core)
    final rect = Rect.fromLTWH(0, 0, w, h);
    final fillPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        colors: [
          color.withValues(alpha: broken ? 0.25 : 0.55),
          color.withValues(alpha: broken ? 0.10 : 0.25),
        ],
      ).createShader(rect);
    canvas.drawPath(path, fillPaint);

    // Inner facet lines
    final facetPaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(cx, 0), Offset(cx, h), facetPaint);
    canvas.drawLine(Offset(0, cy), Offset(w, cy), facetPaint);

    // Outer outline
    final outlinePaint = Paint()
      ..color = color.withValues(alpha: glowing ? 0.95 : 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = glowing ? 1.6 : 1.0;
    canvas.drawPath(path, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _CrystalGlyphPainter old) =>
      old.color != color ||
      old.broken != broken ||
      old.glowing != glowing;
}

/// Red crack lines drawn over a shattered crystal.
class _ShatterCracksPainter extends CustomPainter {
  _ShatterCracksPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    // Center → 6 jagged rays (deterministic so it doesn't flicker).
    final rays = <List<Offset>>[
      [Offset(cx, cy), Offset(cx + w * 0.18, cy - h * 0.22)],
      [Offset(cx, cy), Offset(cx - w * 0.22, cy - h * 0.18)],
      [Offset(cx, cy), Offset(cx + w * 0.26, cy + h * 0.08)],
      [Offset(cx, cy), Offset(cx - w * 0.16, cy + h * 0.24)],
      [Offset(cx, cy), Offset(cx + w * 0.05, cy - h * 0.32)],
      [Offset(cx, cy), Offset(cx - w * 0.28, cy - h * 0.05)],
    ];
    for (final ray in rays) {
      canvas.drawPoints(ui.PointMode.polygon, ray, paint);
    }

    // Inner shards (small triangles)
    final shardPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    final shardA = Path()
      ..moveTo(cx, cy)
      ..lineTo(cx + w * 0.18, cy - h * 0.22)
      ..lineTo(cx + w * 0.10, cy - h * 0.10)
      ..close();
    canvas.drawPath(shardA, shardPaint);
  }

  @override
  bool shouldRepaint(covariant _ShatterCracksPainter old) =>
      old.color != color;
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({
    required this.board,
    required this.isLocalTurn,
    required this.isChoosing,
    required this.onUse,
  });

  final CrystalBridgeBoardState board;
  final bool isLocalTurn;
  final bool isChoosing;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final player = board.currentPlayer;
    if (player == null) return const SizedBox.shrink();
    final power = player.power;
    final accent = Color(power == CrystalBridgePower.shield
        ? 0xFF4CAF7A
        : power == CrystalBridgePower.leap
            ? 0xFFF59E0B
            : power == CrystalBridgePower.reveal
                ? 0xFF60A5FA
                : power == CrystalBridgePower.scanner
                    ? 0xFFA78BFA
                    : 0xFFEC4899);

    final canUse = isLocalTurn && !player.powerUsed && !isChoosing;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: canUse
                ? accent.withValues(alpha: 0.5)
                : KinrelColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.3),
                colors: [
                  accent.withValues(alpha: 0.85),
                  accent.withValues(alpha: 0.45),
                ],
              ),
            ),
            child: Center(
              child: Text(
                power.glyph,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Power: ${power.label}',
                      style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite),
                    ),
                    const SizedBox(width: 6),
                    if (player.powerUsed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: KinrelColors.textDim.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('USED',
                            style: TextStyle(
                                fontFamily: KinrelTypography.monoFont,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: KinrelColors.textDim)),
                      ),
                    if (player.shieldActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: KinrelColors.success.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('SHIELDED',
                            style: TextStyle(
                                fontFamily: KinrelTypography.monoFont,
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: KinrelColors.success)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  power.description,
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 11,
                      color: KinrelColors.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DKButton(
            label: player.powerUsed ? 'Spent' : 'Use',
            variant: DKButtonVariant.primary,
            onPressed: canUse ? onUse : null,
            isLoading: isChoosing,
          ),
        ],
      ),
    );
  }
}

class _PlayersStrip extends StatelessWidget {
  const _PlayersStrip({required this.board, required this.myUserId});
  final CrystalBridgeBoardState board;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_2_outlined,
                  size: 16, color: kCrystalBridgeAccent),
              const SizedBox(width: 8),
              Text('Players',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite)),
              const Spacer(),
              Text('${board.aliveCount}/${board.playerCount} alive',
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.success)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in board.players)
                _PlayerChip(
                  player: p,
                  isCurrent: p.idx == board.currentPlayerIdx,
                  isMe: p.userId == myUserId,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.player,
    required this.isCurrent,
    required this.isMe,
  });

  final CrystalBridgePlayer player;
  final bool isCurrent;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final accent = isCurrent
        ? kCrystalBridgeAccent
        : player.isAlive
            ? KinrelColors.textWhite
            : KinrelColors.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isCurrent ? 0.16 : 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: accent.withValues(alpha: isCurrent ? 0.55 : 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            player.isAlive ? Icons.circle : Icons.close,
            size: 8,
            color: player.isAlive
                ? (player.isStunned
                    ? KinrelColors.warning
                    : KinrelColors.success)
                : KinrelColors.error,
          ),
          const SizedBox(width: 5),
          Text(
            player.name,
            style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent),
          ),
          if (isMe) ...[
            const SizedBox(width: 4),
            Text('YOU',
                style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: accent)),
          ],
          if (player.shieldActive) ...[
            const SizedBox(width: 4),
            const Text('🛡️', style: TextStyle(fontSize: 11)),
          ],
          if (player.isStunned) ...[
            const SizedBox(width: 4),
            const Text('💫', style: TextStyle(fontSize: 11)),
          ],
          const SizedBox(width: 4),
          Text('${player.crystalsCrossed}',
              style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accent.withValues(alpha: 0.85))),
        ],
      ),
    );
  }
}

class _EventsLog extends StatelessWidget {
  const _EventsLog({
    required this.board,
    required this.controller,
    required this.playerNames,
  });

  final CrystalBridgeBoardState board;
  final ScrollController controller;
  final Map<int, String> playerNames;

  @override
  Widget build(BuildContext context) {
    final events = board.events;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history,
                  size: 16, color: kCrystalBridgeAccent),
              const SizedBox(width: 8),
              Text('Events',
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: KinrelColors.textWhite)),
              const Spacer(),
              Text('${events.length}',
                  style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      color: KinrelColors.textDim)),
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140),
            child: events.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'No events yet — the match is starting.',
                        style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 12,
                            color: KinrelColors.textDim),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: controller,
                    shrinkWrap: true,
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final e = events[i];
                      final name =
                          playerNames[e.playerIdx] ?? 'Player ${e.playerIdx}';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(_eventIcon(e.type),
                                size: 12,
                                color: _eventColor(e.type)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                e.summaryFor(name),
                                style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 11,
                                    color: KinrelColors.textSilver),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _eventIcon(String type) {
    switch (type) {
      case 'safe':
        return Icons.check_circle_outline;
      case 'eliminated':
      case 'timeout':
        return Icons.close;
      case 'shield_saved':
        return Icons.shield;
      case 'ice_slide':
        return Icons.ac_unit;
      case 'lava_stun':
        return Icons.whatshot;
      case 'storm_strike':
        return Icons.flash_on;
      case 'power_reveal':
        return Icons.visibility;
      case 'power_shield':
        return Icons.shield;
      case 'power_leap':
        return Icons.north;
      case 'power_scanner':
        return Icons.radar;
      case 'power_swap':
        return Icons.swap_horiz;
      default:
        return Icons.circle;
    }
  }

  Color _eventColor(String type) {
    switch (type) {
      case 'safe':
        return KinrelColors.success;
      case 'eliminated':
      case 'timeout':
        return KinrelColors.error;
      case 'shield_saved':
      case 'power_shield':
        return const Color(0xFF4CAF7A);
      case 'ice_slide':
        return const Color(0xFF38BDF8);
      case 'lava_stun':
        return const Color(0xFFF97316);
      case 'storm_strike':
        return const Color(0xFFA78BFA);
      case 'power_reveal':
        return const Color(0xFF60A5FA);
      case 'power_leap':
        return KinrelColors.amber;
      case 'power_scanner':
        return const Color(0xFFA78BFA);
      case 'power_swap':
        return const Color(0xFFEC4899);
      default:
        return KinrelColors.textDim;
    }
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.game,
    required this.familyId,
    required this.players,
    required this.onRematch,
    required this.onExit,
  });
  final CrystalBridgeGame game;
  final String familyId;
  final List<CrystalBridgePlayerWire> players;
  final Future<String?> Function() onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final board = game.boardState;
    final winnerIds = game.winnerUserIds;
    final winnerName = winnerIds.isNotEmpty
        ? players
            .where((p) => winnerIds.contains(p.userId))
            .map((p) => p.userName)
            .join(', ')
        : '';
    final isDraw = game.endReason == 'all_eliminated';
    final teamLabel = board != null &&
            board.winningTeam > 0 &&
            board.teamMode != CrystalBridgeTeamMode.solo
        ? ' · Team ${board.winningTeam} wins'
        : '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      child: Column(
        children: [
          if (winnerIds.isNotEmpty) const GameConfetti(),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  kCrystalBridgeAccent.withValues(alpha: 0.18),
                  const Color(0xFF0F1A1E),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: kCrystalBridgeAccent.withValues(alpha: 0.45)),
            ),
            child: Column(
              children: [
                const KinrelIcon(KinrelIconData.trophy,
                    size: 40, color: KinrelColors.brightGold),
                const SizedBox(height: 8),
                Text(
                  isDraw
                      ? 'Everyone fell — it\'s a draw!'
                      : winnerName.isNotEmpty
                          ? '$winnerName wins!'
                          : 'Match Complete',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: KinrelTypography.displayFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: KinrelColors.brightGold),
                ),
                const SizedBox(height: 4),
                Text(
                  isDraw
                      ? 'No one made it across the bridge.'
                      : 'Last one standing — or first to finish — takes the crown.$teamLabel',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textSilver),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (board != null) ...[
            GamingSectionHeader(
                title: 'Final Standings',
                icon: Icons.leaderboard_outlined),
            for (final p in board.players
                .toList()
              ..sort((a, b) {
                final aliveCmp =
                    (b.isAlive ? 1 : 0).compareTo(a.isAlive ? 1 : 0);
                if (aliveCmp != 0) return aliveCmp;
                return b.crystalsCrossed.compareTo(a.crystalsCrossed);
              }))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: KinrelColors.darkCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: winnerIds.contains(p.userId)
                            ? kCrystalBridgeAccent.withValues(alpha: 0.4)
                            : Colors.transparent),
                  ),
                  child: Row(
                    children: [
                      Text(
                        winnerIds.contains(p.userId)
                            ? '🏆'
                            : p.isAlive
                                ? '🏅'
                                : '💀',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: TextStyle(
                                    fontFamily: KinrelTypography.bodyFont,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: KinrelColors.textWhite)),
                            Text(
                              p.isAlive
                                  ? 'Survived · ${p.crystalsCrossed} crystals crossed'
                                  : 'Eliminated · ${p.crystalsCrossed} crystals crossed',
                              style: TextStyle(
                                  fontFamily: KinrelTypography.bodyFont,
                                  fontSize: 10,
                                  color: KinrelColors.textDim)),
                          ],
                        ),
                      ),
                      Text('${p.crystalsCrossed}',
                          style: const TextStyle(
                              fontFamily: KinrelTypography.monoFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: kCrystalBridgeAccent)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 18),
            // Match stats
            GamingSectionHeader(
                title: 'Match Stats', icon: Icons.insights_outlined),
            _StatRow(
                label: 'Bridge type', value: board.bridgeType.label),
            _StatRow(label: 'Total rows', value: '${board.totalRows}'),
            _StatRow(
                label: 'Team mode',
                value: board.teamMode == CrystalBridgeTeamMode.solo
                    ? 'Solo (FFA)'
                    : board.teamMode.label),
            _StatRow(
                label: 'Survival rate',
                value:
                    '${(CrystalBridgeEngine.survivalRate(board) * 100).round()}%'),
            _StatRow(
                label: 'Longest run',
                value:
                    '${CrystalBridgeEngine.longestRun(board)} crystals'),
            _StatRow(
                label: 'Total events', value: '${board.events.length}'),
            _StatRow(
                label: 'End reason',
                value: _endReasonLabel(game.endReason)),
            const SizedBox(height: 18),
          ],
          MatchEcosystemSummary(
            gameTable: 'crystal_bridge_games',
            gameId: game.id,
            familyId: familyId,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: DKButton(
                  label: 'Exit',
                  variant: DKButtonVariant.secondary,
                  fullWidth: true,
                  onPressed: onExit,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DKButton(
                  label: 'Rematch',
                  variant: DKButtonVariant.primary,
                  fullWidth: true,
                  onPressed: () async {
                    final newId = await onRematch();
                    if (newId != null && context.mounted) {
                      context.pushReplacement(
                        '/family/$familyId/crystal-bridge/game/$newId',
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _endReasonLabel(String? reason) {
    switch (reason) {
      case 'finish_reached':
        return 'Finish reached';
      case 'last_survivor':
        return 'Last survivor';
      case 'all_eliminated':
        return 'All eliminated (draw)';
      case 'walkover':
        return 'Walkover';
      default:
        return reason ?? '—';
    }
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim)),
            ),
            Text(value,
                style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite)),
          ],
        ),
      ),
    );
  }
}
