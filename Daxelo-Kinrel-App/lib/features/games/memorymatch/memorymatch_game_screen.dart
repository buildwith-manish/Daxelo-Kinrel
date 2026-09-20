// lib/features/games/memorymatch/memorymatch_game_screen.dart
//
// Memory Match — the board.
//
// Layout (portrait-first):
//   ┌──────────────────────────────────────┐
//   │  ←  🐼 Animals · 7/12 pairs found    │ top bar (pack + progress)
//   │  🎮 Rakshita's Turn        ⟳ 12     │ turn banner + 15 s ring
//   │  [M 4] [R 3] [Y 2] [P 1]            │ live leaderboard chips
//   ├──────────────────────────────────────┤
//   │  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐  │ card grid — matched cards
//   │  │ ⭐ │ │ 🎂 │ │ ▓▓ │ │ 🐶 │ │ ▓▓ │  │ wear the owner's color +
//   │  └────┘ └────┘ └────┘ └────┘ └────┘  │ avatar and STAY on the board
//   ├──────────────────────────────────────┤
//   │  (spectators: ❤️ 🔥 👏 😂 🎉 bar)    │
//   └──────────────────────────────────────┘
//
// Completed → inline results: podium with medals, per-player stats
// (pairs · accuracy · avg match time), ecosystem rewards, rematch.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';
import '../game_motion_tokens.dart';
import '../shared/models/game_invite.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/widgets/rematch_button.dart';
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/reactions_bar.dart';
import 'memorymatch_card_faces.dart';
import 'memorymatch_models.dart';
import 'memorymatch_provider.dart';

/// Seat accent colors (player 1 → 4), used for cards + leaderboard chips.
class MemorySeatColors {
  MemorySeatColors._();

  static const List<Color> seats = [
    KinrelColors.orange,
    KinrelColors.blue,
    KinrelColors.extendedPurple,
    KinrelColors.success,
  ];

  static Color forSeat(int seatIndex) =>
      seats[seatIndex.clamp(0, seats.length - 1)];
}

class MemoryMatchGameScreen extends ConsumerStatefulWidget {
  const MemoryMatchGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });

  final String familyId;
  final String gameId;

  @override
  ConsumerState<MemoryMatchGameScreen> createState() =>
      _MemoryMatchGameScreenState();
}

class _MemoryMatchGameScreenState extends ConsumerState<MemoryMatchGameScreen> {
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(memoryMatchProvider(widget.familyId).notifier)
          .loadGame(widget.gameId);
    });
    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final state = ref.read(memoryMatchProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId && state.game?.isWaiting == true,
      gameName: 'Memory Match',
    );
    if (shouldLeave == true && mounted) {
      await ref
          .read(memoryMatchProvider(widget.familyId).notifier)
          .leaveGame();
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/family/${widget.familyId}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memoryMatchProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;

    return ReactionOverlay(
      gameTable: 'memorymatch_games',
      gameId: widget.gameId,
      child: Scaffold(
        backgroundColor: KinrelColors.darkSurface,
        body: SafeArea(
          child: state.isLoading && state.game == null
              ? const Center(
                  child:
                      CircularProgressIndicator(color: KinrelColors.orange),
                )
              : state.isCompleted
                  ? _ResultsView(
                      state: state,
                      familyId: widget.familyId,
                      myUserId: myId,
                    )
                  : _playView(state, myId),
        ),
      ),
    );
  }

  Widget _playView(MemoryMatchState state, String? myId) {
    final game = state.game;
    if (game == null) {
      return const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    }

    final isSpectator = state.amSpectator ||
        state.playerFor(myId) == null ||
        !state.playerFor(myId)!.isActive;
    final isMyTurn = game.currentPlayerId == myId && !isSpectator;

    String nameFor(String? userId) =>
        state.playerFor(userId)?.userName ?? 'Player';

    return Column(
      children: [
        _TopBar(game: game, onLeave: _confirmLeave),
        _TurnBanner(
          game: game,
          isMyTurn: isMyTurn,
          currentPlayerName: nameFor(game.currentPlayerId),
        ),
        _LeaderboardStrip(state: state, myUserId: myId),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              KinrelSpacing.base, KinrelSpacing.sm, KinrelSpacing.base,
              KinrelSpacing.sm,
            ),
            child: _BoardGrid(
              state: state,
              familyId: widget.familyId,
              isMyTurn: isMyTurn,
              ownerNameFor: nameFor,
            ),
          ),
        ),
        if (isSpectator)
          _SpectatorBar(familyId: widget.familyId, gameId: game.id)
        else
          const SizedBox(height: KinrelSpacing.sm),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Top bar — pack chip, pairs progress, leave
// ────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.game, required this.onLeave});

  final MemoryMatchGame game;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final pack = MemoryCardPack.byId(game.cardPack);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base, KinrelSpacing.sm, KinrelSpacing.base, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onLeave,
            icon: const Icon(Icons.arrow_back),
            color: KinrelColors.textDim,
            visualDensity: VisualDensity.compact,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: KinrelColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: MemoryCardFaceIcon(
                    symbolKey: MemoryCardFaces.previewSpecFor(game.cardPack).key,
                    packId: game.cardPack,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  pack.label,
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: KinrelSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: KinrelColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.style_outlined,
                  size: 13,
                  color: KinrelColors.textDim,
                ),
                const SizedBox(width: 5),
                Text(
                  '${game.matchedPairs}/${game.totalPairs} pairs',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (game.roomName?.isNotEmpty == true)
            Flexible(
              child: Text(
                game.roomName!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Turn banner — whose turn + 15 s countdown ring
// ────────────────────────────────────────────────────────────────────

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({
    required this.game,
    required this.isMyTurn,
    required this.currentPlayerName,
  });

  final MemoryMatchGame game;
  final bool isMyTurn;
  final String currentPlayerName;

  @override
  Widget build(BuildContext context) {
    final remaining = game.turnSecondsRemaining;
    final revealing = game.isReveal;
    final revealingMatch = game.pendingIsMatch == true;
    final accent = isMyTurn ? KinrelColors.orange : KinrelColors.blue;

    final title = revealing
        ? (revealingMatch ? 'It\'s a match!' : 'No match — memorize!')
        : isMyTurn
            ? 'Your Turn — flip two cards!'
            : '$currentPlayerName\'s Turn';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base, KinrelSpacing.sm, KinrelSpacing.base, KinrelSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isMyTurn && !revealing
              ? const LinearGradient(
                  colors: [KinrelColors.orange, KinrelColors.amber],
                )
              : null,
          color: isMyTurn && !revealing
              ? null
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
          border: isMyTurn && !revealing
              ? null
              : Border.all(color: KinrelColors.border),
          boxShadow: isMyTurn && !revealing
              ? [
                  BoxShadow(
                    color: KinrelColors.orangeGlow,
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              revealing
                  ? (revealingMatch
                      ? Icons.auto_awesome
                      : Icons.psychology_outlined)
                  : Icons.style_outlined,
              size: 18,
              color: isMyTurn && !revealing
                  ? Colors.white
                  : revealingMatch
                      ? KinrelColors.success
                      : KinrelColors.textDim,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isMyTurn && !revealing
                      ? Colors.white
                      : revealingMatch
                          ? KinrelColors.success
                          : KinrelColors.textWhite,
                ),
              ),
            ),
            if (!revealing && remaining != null) ...[
              _TurnCountdown(
                remaining: remaining,
                total: game.turnSeconds,
                color: isMyTurn ? Colors.white : accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TurnCountdown extends StatelessWidget {
  const _TurnCountdown({
    required this.remaining,
    required this.total,
    required this.color,
  });

  final int remaining;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final urgent = remaining <= 5;
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: (remaining / total).clamp(0.0, 1.0),
            strokeWidth: 3,
            color: urgent ? KinrelColors.error : color,
            backgroundColor:
                KinrelColors.border.withValues(alpha: 0.4),
          ),
          Text(
            '$remaining',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: urgent ? KinrelColors.error : color,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Live leaderboard — avatar chips with pair counts
// ────────────────────────────────────────────────────────────────────

class _LeaderboardStrip extends StatelessWidget {
  const _LeaderboardStrip({required this.state, required this.myUserId});

  final MemoryMatchState state;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final game = state.game;
    if (game == null) return const SizedBox.shrink();

    final entries = state.players
        .map((p) {
          final seat = game.playerOrder.indexOf(p.userId);
          return (
            player: p,
            seat: seat < 0 ? 0 : seat,
            pairs: game.scores[p.userId] ?? 0,
          );
        })
        .toList()
      ..sort((a, b) => b.pairs.compareTo(a.pairs));

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: KinrelSpacing.sm),
        itemBuilder: (context, i) {
          final e = entries[i];
          final color = MemorySeatColors.forSeat(e.seat);
          final isCurrent = game.currentPlayerId == e.player.userId;
          final isMe = e.player.userId == myUserId;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isCurrent
                  ? color.withValues(alpha: 0.18)
                  : KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isCurrent ? color : KinrelColors.border,
                width: isCurrent ? 1.6 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AvatarBadge(
                  name: e.player.userName,
                  color: color,
                  size: 24,
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 84),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMe ? 'You' : e.player.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: e.player.isActive
                              ? KinrelColors.textWhite
                              : KinrelColors.textDim,
                        ),
                      ),
                      Text(
                        e.player.isActive
                            ? '${e.pairs} ${e.pairs == 1 ? 'pair' : 'pairs'}'
                            : 'left',
                        style: TextStyle(
                          fontFamily: KinrelTypography.monoFont,
                          fontSize: 9,
                          color: e.player.isActive
                              ? color
                              : KinrelColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({
    required this.name,
    required this.color,
    this.size = 26,
  });

  final String name;
  final Color color;
  final double size;

  String get _initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, math.min(2, parts.first.length));
    }
    return parts.first.substring(0, 1) + parts.last.substring(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials.toUpperCase(),
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Board grid
// ────────────────────────────────────────────────────────────────────

class _BoardGrid extends ConsumerWidget {
  const _BoardGrid({
    required this.state,
    required this.familyId,
    required this.isMyTurn,
    required this.ownerNameFor,
  });

  final MemoryMatchState state;
  final String familyId;
  final bool isMyTurn;
  final String Function(String? userId) ownerNameFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = state.game!;
    final columns = MemoryMatchDifficulty.columnsFor(game.cards.length);
    final pack = MemoryCardPack.byId(game.cardPack);

    return GridView.count(
      crossAxisCount: columns,
      childAspectRatio: 0.74,
      mainAxisSpacing: KinrelSpacing.sm,
      crossAxisSpacing: KinrelSpacing.sm,
      children: [
        for (final card in game.cards)
          _MemoryCardTile(
            key: ValueKey('mm_card_${game.id}_${card.index}'),
            card: card,
            pack: pack,
            seatColor: _seatColorForOwner(game, card.ownerId),
            ownerName: ownerNameFor(card.ownerId),
            isFaceUp: state.isFaceUp(card),
            isFlippedThisTurn: game.flippedCardIds.contains(card.index),
            isRevealingMatch: game.isReveal && game.pendingIsMatch == true,
            enabled: isMyTurn &&
                !game.isReveal &&
                !card.isMatched &&
                game.flippedCardIds.length +
                        state.optimisticFlips.length <
                    2,
            onTap: () => ref
                .read(memoryMatchProvider(familyId).notifier)
                .flipCard(card.index),
          ),
      ],
    );
  }

  Color _seatColorForOwner(MemoryMatchGame game, String? ownerId) {
    if (ownerId == null) return KinrelColors.orange;
    final seat = game.playerOrder.indexOf(ownerId);
    return MemorySeatColors.forSeat(seat < 0 ? 0 : seat);
  }
}

// ────────────────────────────────────────────────────────────────────
// Card tile — 3D flip animation + owner marking + match glow
// ────────────────────────────────────────────────────────────────────

class _MemoryCardTile extends StatefulWidget {
  const _MemoryCardTile({
    super.key,
    required this.card,
    required this.pack,
    required this.seatColor,
    required this.ownerName,
    required this.isFaceUp,
    required this.isFlippedThisTurn,
    required this.isRevealingMatch,
    required this.enabled,
    required this.onTap,
  });

  final MemoryMatchCard card;
  final MemoryCardPack pack;
  final Color seatColor;
  final String ownerName;
  final bool isFaceUp;
  final bool isFlippedThisTurn;
  final bool isRevealingMatch;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_MemoryCardTile> createState() => _MemoryCardTileState();
}

class _MemoryCardTileState extends State<_MemoryCardTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip;
  bool _glowStarted = false;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: widget.isFaceUp ? 1 : 0,
    );
    if (widget.card.isMatched) _glowStarted = true;
  }

  @override
  void didUpdateWidget(covariant _MemoryCardTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFaceUp != oldWidget.isFaceUp) {
      if (widget.isFaceUp) {
        _flip.forward();
      } else {
        _flip.reverse();
      }
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matched = widget.card.isMatched;
    if (matched && !_glowStarted) _glowStarted = true;

    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_flip.value);
          final angle = t * math.pi;
          final showingBack = t < 0.5; // "back" = the face-down side
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0016)
              ..rotateY(angle),
            child: showingBack
                ? _faceDown()
                : Transform(
                    transform: Matrix4.identity()..rotateY(math.pi),
                    alignment: Alignment.center,
                    child: _faceUp(matched),
                  ),
          );
        },
      ),
    );
  }

  Widget _faceDown() {
    return AnimatedContainer(
      duration: GameMotionTokens.fast,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KinrelColors.darkElevated, KinrelColors.darkCard],
        ),
        border: Border.all(
          color: widget.enabled
              ? KinrelColors.orange.withValues(alpha: 0.55)
              : KinrelColors.border,
          width: widget.enabled ? 1.6 : 1,
        ),
        boxShadow: widget.enabled
            ? [
                BoxShadow(
                  color: KinrelColors.orangeGlowSubtle,
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Card-back pattern: soft diagonal weave + brand sparkle.
          CustomPaint(
            size: Size.infinite,
            painter: _CardBackPatternPainter(
              color: widget.enabled
                  ? KinrelColors.orange.withValues(alpha: 0.16)
                  : KinrelColors.border.withValues(alpha: 0.14),
            ),
          ),
          Icon(
            Icons.auto_awesome_outlined,
            size: 22,
            color: widget.enabled
                ? KinrelColors.orange.withValues(alpha: 0.7)
                : KinrelColors.textDim.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _faceUp(bool matched) {
    final ownerColor = widget.seatColor;
    final revealedNow =
        widget.isFlippedThisTurn && !matched && widget.isRevealingMatch;
    return AnimatedContainer(
      duration: GameMotionTokens.normal,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        color: matched
            ? ownerColor.withValues(alpha: 0.16)
            : KinrelColors.darkElevated,
        border: Border.all(
          color: matched
              ? ownerColor
              : widget.isFlippedThisTurn
                  ? KinrelColors.textSilver.withValues(alpha: 0.6)
                  : KinrelColors.border,
          width: matched ? 2 : 1,
        ),
        boxShadow: [
          if (matched)
            BoxShadow(
              color: ownerColor.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 3),
            )
          else if (revealedNow)
            const BoxShadow(
              color: KinrelColors.success,
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The symbol — a vector illustration that scales with the tile
          // (16 px chips → full-card tiles). Dimmed once owned.
          AnimatedOpacity(
            duration: GameMotionTokens.normal,
            opacity: matched ? 0.55 : 1,
            child: Padding(
              padding: EdgeInsets.all(
                matched ? 12.0 : 9.0,
              ),
              child: MemoryCardFaceIcon(
                symbolKey: widget.card.symbolKey,
                packId: widget.pack.id,
              ),
            ),
          ),
          // Owner badge — the winner's initials, top-right corner.
          if (matched)
            Positioned(
              top: 4,
              right: 4,
              child: _AvatarBadge(
                name: widget.ownerName,
                color: ownerColor,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }
}

/// Subtle diagonal weave for the card backs.
class _CardBackPatternPainter extends CustomPainter {
  _CardBackPatternPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const gap = 9.0;
    for (var d = -size.height; d < size.width + size.height; d += gap) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), paint);
      canvas.drawLine(Offset(d + size.height, 0), Offset(d, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CardBackPatternPainter oldDelegate) =>
      color != oldDelegate.color;
}

// ────────────────────────────────────────────────────────────────────
// Spectator bar
// ────────────────────────────────────────────────────────────────────

class _SpectatorBar extends StatelessWidget {
  const _SpectatorBar({required this.familyId, required this.gameId});

  final String familyId;
  final String gameId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base, KinrelSpacing.sm, KinrelSpacing.base, KinrelSpacing.sm),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(
          top: BorderSide(color: KinrelColors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.visibility_outlined,
                  size: 14, color: KinrelColors.textDim),
              const SizedBox(width: 6),
              Text(
                'Watching — cheer with a reaction!',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: KinrelSpacing.sm),
          ReactionsBar(
            gameTable: 'memorymatch_games',
            gameId: gameId,
            familyId: familyId,
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Results — podium, stats, ecosystem rewards, rematch
// ────────────────────────────────────────────────────────────────────

class _ResultsView extends ConsumerWidget {
  const _ResultsView({
    required this.state,
    required this.familyId,
    required this.myUserId,
  });

  final MemoryMatchState state;
  final String familyId;
  final String? myUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = state.game;
    if (game == null) {
      return const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    }

    final iWon = game.winnerUserIds.contains(myUserId);
    final celebrate = iWon || state.amSpectator || myUserId == null;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(KinrelSpacing.base),
          children: [
            const SizedBox(height: KinrelSpacing.md),
            _winnerBanner(game, iWon),
            const SizedBox(height: KinrelSpacing.lg),
            if (game.placements.isNotEmpty) ...[
              _SectionLabel('Final Standings'),
              const SizedBox(height: KinrelSpacing.sm),
              ...game.placements.map((p) => _PlacementRow(
                    placement: p,
                    seatColor: MemorySeatColors.forSeat(
                        game.playerOrder.indexOf(p.userId) < 0
                            ? 0
                            : game.playerOrder.indexOf(p.userId)),
                    isMe: p.userId == myUserId,
                  )),
              const SizedBox(height: KinrelSpacing.lg),
            ],
            _SectionLabel('Match Stats'),
            const SizedBox(height: KinrelSpacing.sm),
            _StatsTable(game: game),
            const SizedBox(height: KinrelSpacing.lg),
            MatchEcosystemSummary(
              gameTable: 'memorymatch_games',
              gameId: game.id,
              familyId: familyId,
            ),
            const SizedBox(height: KinrelSpacing.xl),
            // Host-gated shared rematch (was a local _rematch helper with the
            // same behaviour — provider rematch() carries the roster and
            // writes invites itself, hence insertInvites: false).
            if (game.hostUserId == myUserId) ...[
              RematchButton(
                familyId: familyId,
                gameType: GameType.memoryMatch,
                previousGameId: game.id,
                participantUserIds:
                    state.players.map((p) => p.userId).toList(),
                maxPlayers: game.maxPlayers,
                insertInvites: false,
                onCreateNewGame: () =>
                    ref.read(memoryMatchProvider(familyId).notifier).rematch(),
              ),
              const SizedBox(height: KinrelSpacing.sm),
            ],
            DKButton(
              label: 'Back to Games',
              variant: DKButtonVariant.secondary,
              fullWidth: true,
              onPressed: () {
                ref
                    .read(memoryMatchProvider(familyId).notifier)
                    .leaveGame();
                context.go('/family/$familyId');
              },
            ),
            const SizedBox(height: KinrelSpacing.xl),
          ],
        ),
        if (celebrate)
          const Positioned.fill(
            child: IgnorePointer(
              child: GameConfetti(burstCount: 3),
            ),
          ),
      ],
    );
  }

  Widget _winnerBanner(MemoryMatchGame game, bool iWon) {
    final winnerNames = game.placements
        .where((p) => p.place == 1)
        .map((p) => p.userName)
        .toList();
    final label = winnerNames.isEmpty
        ? 'Game Complete'
        : winnerNames.length == 1
            ? '${winnerNames.first} wins!'
            : '${winnerNames.join(' & ')} tie the win!';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [KinrelColors.orange, KinrelColors.amber],
        ),
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
        boxShadow: [
          BoxShadow(
            color: KinrelColors.orangeGlow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          KinrelIcon(
            iWon ? KinrelIconData.trophy : KinrelIconData.medal,
            size: iWon ? 46 : 40,
            color: Colors.white,
          ),
          const SizedBox(height: 6),
          Text(
            iWon ? 'You Win!' : 'Game Over',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: iWon ? 22 : 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            game.endReasonLabel,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontFamily: KinrelTypography.displayFont,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: KinrelColors.textDim,
      ),
    );
  }
}

class _PlacementRow extends StatelessWidget {
  const _PlacementRow({
    required this.placement,
    required this.seatColor,
    required this.isMe,
  });

  final MemoryPlacement placement;
  final Color seatColor;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: placement.place == 1
            ? seatColor.withValues(alpha: 0.14)
            : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(
          color: placement.place == 1 ? seatColor : KinrelColors.border,
          width: placement.place == 1 ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          _RankMedal(place: placement.place, color: seatColor),
          const SizedBox(width: 10),
          _AvatarBadge(
            name: placement.userName,
            color: seatColor,
            size: 30,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? 'You' : placement.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                Text(
                  '${placement.pairs} ${placement.pairs == 1 ? 'pair' : 'pairs'}'
                  ' · ${placement.accuracy.toStringAsFixed(0)}% accuracy'
                  ' · avg ${placement.avgMatchLabel}',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 11,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${placement.place}',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: seatColor.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vector rank medal — a colored medallion with the place number,
/// replacing emoji medals (gold / silver / bronze / participant).
class _RankMedal extends StatelessWidget {
  const _RankMedal({required this.place, required this.color});

  final int place;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final medalColor = switch (place) {
      1 => const Color(0xFFFFC940), // gold
      2 => const Color(0xFFC7CEDA), // silver
      3 => const Color(0xFFD9905C), // bronze
      _ => color.withValues(alpha: 0.65),
    };
    final glow = place <= 3 ? medalColor.withValues(alpha: 0.55) : Colors.transparent;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(medalColor, Colors.white, 0.35)!,
            medalColor,
            Color.lerp(medalColor, Colors.black, 0.28)!,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.5),
        boxShadow: [
          BoxShadow(color: glow, blurRadius: 9, offset: const Offset(0, 2)),
        ],
      ),
      child: Text(
        '$place',
        style: TextStyle(
          fontFamily: KinrelTypography.displayFont,
          fontSize: 15,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.game});

  final MemoryMatchGame game;

  @override
  Widget build(BuildContext context) {
    final rows = game.placements;
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(KinrelSpacing.lg),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(color: KinrelColors.border),
        ),
        child: Text(
          'No stats recorded for this game.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            color: KinrelColors.textDim,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Column(
        children: [
          _statsHeader(),
          const Divider(color: KinrelColors.border, height: 1),
          for (final p in rows) _statsRow(p),
        ],
      ),
    );
  }

  Widget _statsHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Expanded(flex: 3, child: _StatCell('Player', header: true)),
          Expanded(child: _StatCell('Pairs', header: true, center: true)),
          Expanded(child: _StatCell('Acc.', header: true, center: true)),
          Expanded(child: _StatCell('Avg', header: true, center: true)),
          Expanded(child: _StatCell('Miss', header: true, center: true)),
        ],
      ),
    );
  }

  Widget _statsRow(MemoryPlacement p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _StatCell(
              p.userName,
              color: MemorySeatColors.forSeat(
                  game.playerOrder.indexOf(p.userId) < 0
                      ? 0
                      : game.playerOrder.indexOf(p.userId)),
            ),
          ),
          Expanded(child: _StatCell('${p.pairs}', center: true)),
          Expanded(
              child:
                  _StatCell('${p.accuracy.toStringAsFixed(0)}%', center: true)),
          Expanded(child: _StatCell(p.avgMatchLabel, center: true)),
          Expanded(child: _StatCell('${p.misses}', center: true)),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell(this.label, {this.header = false, this.center = false, this.color});

  final String label;
  final bool header;
  final bool center;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      header ? label : (label.isEmpty ? '—' : label),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontFamily: header
            ? KinrelTypography.displayFont
            : KinrelTypography.monoFont,
        fontSize: header ? 10 : 12,
        fontWeight: header ? FontWeight.w700 : FontWeight.w600,
        letterSpacing: header ? 0.8 : 0,
        color: color ??
            (header ? KinrelColors.textDim : KinrelColors.textWhite),
      ),
    );
  }
}
