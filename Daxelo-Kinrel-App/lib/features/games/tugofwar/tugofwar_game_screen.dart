// lib/features/games/tugofwar/tugofwar_game_screen.dart
//
// Tug of War — the arena.
//
// Layout (portrait + landscape via OrientationBuilder):
//   ┌──────────────────────────────────┐
//   │  ⏱ 00:42   ·   rope advantage   │  timer + advantage bar
//   │  TEAM EMBER      VS      TEAM AZURE │ team cards: avatars, strength,
//   │  👥3  ⚡8.2/s              👥3   │ live tap rate, top puller
//   ├──────────────────────────────────┤
//   │ ═════════════╲🚩╱══════════════  │ rope arena (physics spring)
//   ├──────────────────────────────────┤
//   │        ┌──────────────────┐      │
//   │        │      PULL!       │      │ giant team-colored button
//   │        │    127 taps      │      │ (spectators see reactions row)
//   │        └──────────────────┘      │
//   └──────────────────────────────────┘
//
// Completed → inline results: winner banner, MVP trio, team breakdown,
// ecosystem rewards, rematch (same teams / shuffle).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';
import '../game_motion_tokens.dart';
import '../shared/widgets/reactions_bar.dart';
import 'tugofwar_models.dart';
import 'tugofwar_provider.dart';
import 'tugofwar_rope.dart';

class TugOfWarGameScreen extends ConsumerStatefulWidget {
  const TugOfWarGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });

  final String familyId;
  final String gameId;

  @override
  ConsumerState<TugOfWarGameScreen> createState() =>
      _TugOfWarGameScreenState();
}

class _TugOfWarGameScreenState extends ConsumerState<TugOfWarGameScreen>
    with SingleTickerProviderStateMixin {
  late final RopePhysicsController _rope;
  Timer? _clockTimer;
  bool _pressed = false;
  Timer? _pressTimer;

  @override
  void initState() {
    super.initState();
    _rope = RopePhysicsController(this)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(tugOfWarProvider(widget.familyId).notifier)
          .loadGame(widget.gameId);
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pressTimer?.cancel();
    _rope.stop();
    _rope.dispose();
    super.dispose();
  }

  void _onPull(TugTeam? myTeam) {
    final notifier = ref.read(tugOfWarProvider(widget.familyId).notifier);
    notifier.pull();
    if (myTeam != null) {
      _rope.impulse(myTeam == TugTeam.a ? TugSide.a : TugSide.b);
    }
    GameMotionTokens.tap();
    setState(() => _pressed = true);
    _pressTimer?.cancel();
    _pressTimer = Timer(const Duration(milliseconds: 110), () {
      if (mounted) setState(() => _pressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tugOfWarProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final me = state.playerFor(myId);
    final myTeam = me?.team;

    // Feed authoritative rope samples into the spring.
    final ropeTarget = state.game?.ropePosition;
    if (ropeTarget != null) {
      _rope.setTarget(ropeTarget);
    }

    return ReactionOverlay(
      gameTable: 'tugofwar_games',
      gameId: widget.gameId,
      child: DKScaffoldlessBackground(
        child: SafeArea(
          child: state.isLoading && state.game == null
              ? const Center(
                  child: CircularProgressIndicator(color: KinrelColors.orange),
                )
              : state.isCompleted
                  ? _ResultsView(
                      state: state,
                      familyId: widget.familyId,
                      myUserId: myId,
                    )
                  : _playView(state, myId, myTeam),
        ),
      ),
    );
  }

  Widget _playView(TugOfWarState state, String? myId, TugTeam? myTeam) {
    final game = state.game;
    if (game == null) {
      return const Center(
        child: CircularProgressIndicator(color: KinrelColors.orange),
      );
    }

    final isSpectator =
        state.amSpectator || state.playerFor(myId) == null || myTeam == null;

    return OrientationBuilder(
      builder: (context, orientation) {
        final landscape = orientation == Orientation.landscape;
        final arena = Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.base, vertical: KinrelSpacing.sm),
            child: _RopeArena(
              controller: _rope,
              teamAColor: TugTeamBoardColors.a,
              teamBColor: TugTeamBoardColors.b,
              wonSide: game.isCompleted
                  ? (game.winningTeam == TugTeam.a ? TugSide.a : TugSide.b)
                  : null,
            ),
          ),
        );

        final header = _TopBar(game: game);
        final teams = _TeamsPanel(state: state, myUserId: myId);
        final puller = _PullSection(
          state: state,
          myTeam: myTeam,
          isSpectator: isSpectator,
          familyId: widget.familyId,
          pressed: _pressed,
          onPull: () => _onPull(myTeam),
        );

        if (landscape) {
          return Column(
            children: [
              header,
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(KinrelSpacing.sm),
                        child: _TeamsPanel(state: state, myUserId: myId),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: KinrelSpacing.sm),
                              child: _RopeArena(
                                controller: _rope,
                                teamAColor: TugTeamBoardColors.a,
                                teamBColor: TugTeamBoardColors.b,
                                wonSide: game.isCompleted
                                    ? (game.winningTeam == TugTeam.a
                                        ? TugSide.a
                                        : TugSide.b)
                                    : null,
                              ),
                            ),
                          ),
                          puller,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            header,
            teams,
            arena,
            puller,
          ],
        );
      },
    );
  }
}

/// Team accent colors shared across the game screen widgets.
class TugTeamBoardColors {
  TugTeamBoardColors._();

  static const Color a = KinrelColors.orange; // Team Ember
  static const Color b = KinrelColors.blue; // Team Azure
}

/// Scaffold-free full-bleed dark background container.
class DKScaffoldlessBackground extends StatelessWidget {
  const DKScaffoldlessBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: KinrelColors.darkSurface,
      child: child,
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Top bar — timer + advantage meter
// ────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.game});

  final TugOfWarGame game;

  @override
  Widget build(BuildContext context) {
    final remaining = game.secondsRemaining;
    final advantage = ((game.ropePosition.clamp(-1, 1) + 1) / 2);

    return Container(
      padding: const EdgeInsets.fromLTRB(
          KinrelSpacing.base, KinrelSpacing.sm, KinrelSpacing.base, KinrelSpacing.sm),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: KinrelColors.darkCard,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: KinrelColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      game.hasTimer ? Icons.timer_outlined : Icons.all_inclusive,
                      size: 14,
                      color: remaining != null && remaining <= 10
                          ? KinrelColors.error
                          : KinrelColors.textDim,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      remaining == null
                          ? 'Unlimited'
                          : '${(remaining ~/ 60).toString().padLeft(2, '0')}:'
                              '${(remaining % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: remaining != null && remaining <= 10
                            ? KinrelColors.error
                            : KinrelColors.textWhite,
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
          const SizedBox(height: KinrelSpacing.sm),
          // Advantage meter: Team A share vs Team B share.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: (advantage * 1000).clamp(1, 999).round(),
                    child: Container(color: TugTeamBoardColors.a),
                  ),
                  Expanded(
                    flex: ((1 - advantage) * 1000).clamp(1, 999).round(),
                    child: Container(color: TugTeamBoardColors.b),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Teams panel — avatars, strength, live tap rate, top puller
// ────────────────────────────────────────────────────────────────────

class _TeamsPanel extends StatelessWidget {
  const _TeamsPanel({required this.state, required this.myUserId});

  final TugOfWarState state;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final game = state.game;
    if (game == null) return const SizedBox.shrink();
    final elapsed = (game.startedAt != null)
        ? DateTime.now().difference(game.startedAt!)
        : Duration.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _TeamCard(
              team: TugTeam.a,
              color: TugTeamBoardColors.a,
              stats: state.teamStats(TugTeam.a),
              elapsed: elapsed,
              myUserId: myUserId,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KinrelSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 18),
                Text(
                  'VS',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: KinrelColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _TeamCard(
              team: TugTeam.b,
              color: TugTeamBoardColors.b,
              stats: state.teamStats(TugTeam.b),
              elapsed: elapsed,
              myUserId: myUserId,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.color,
    required this.stats,
    required this.elapsed,
    required this.myUserId,
  });

  final TugTeam team;
  final Color color;
  final TugTeamStats stats;
  final Duration elapsed;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final shown = stats.players.take(4).toList();
    final overflow = stats.size - shown.length;
    final topPuller = stats.players.isEmpty
        ? null
        : stats.players.reduce(
            (a, b) => a.pullCount >= b.pullCount ? a : b);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 5),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  team.shortLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: color,
                  ),
                ),
              ),
              Text(
                '👥${stats.size}',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Text(
              'empty side',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 10,
                color: KinrelColors.textDim.withValues(alpha: 0.6),
              ),
            )
          else
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final p in shown)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.75),
                      border: Border.all(
                        color: p.userId == myUserId
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.25),
                        width: p.userId == myUserId ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      p.userName.trim().isEmpty
                          ? '?'
                          : p.userName.trim()[0].toUpperCase(),
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (overflow > 0)
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KinrelColors.darkElevated,
                      border:
                          Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '+$overflow',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          // Live indicators: strength (avg/player) + tap rate.
          Row(
            children: [
              Icon(Icons.bolt, size: 11, color: color),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  '${stats.avgTaps.toStringAsFixed(0)} avg',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${stats.tapRate(elapsed).toStringAsFixed(1)}/s',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 10,
                  color: KinrelColors.textDim,
                ),
              ),
            ],
          ),
          if (topPuller != null && topPuller.pullCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '🔥 ${topPuller.userName.split(' ').first} · ${topPuller.pullCount}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 9,
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
// Rope arena
// ────────────────────────────────────────────────────────────────────

class _RopeArena extends StatelessWidget {
  const _RopeArena({
    required this.controller,
    required this.teamAColor,
    required this.teamBColor,
    this.wonSide,
  });

  final RopePhysicsController controller;
  final Color teamAColor;
  final Color teamBColor;
  final TugSide? wonSide;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size.infinite,
          painter: TugRopePainter(
            position: controller.display,
            velocity: controller.velocity,
            elapsed: controller.elapsed,
            teamAColor: teamAColor,
            teamBColor: teamBColor,
            wonSide: wonSide,
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// PULL section
// ────────────────────────────────────────────────────────────────────

class _PullSection extends StatelessWidget {
  const _PullSection({
    required this.state,
    required this.myTeam,
    required this.isSpectator,
    required this.familyId,
    required this.pressed,
    required this.onPull,
  });

  final TugOfWarState state;
  final TugTeam? myTeam;
  final bool isSpectator;
  final String familyId;
  final bool pressed;
  final VoidCallback onPull;

  @override
  Widget build(BuildContext context) {
    if (isSpectator) {
      return Padding(
        padding: const EdgeInsets.all(KinrelSpacing.base),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: KinrelColors.darkCard,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: KinrelColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility_outlined,
                      size: 15, color: KinrelColors.textDim),
                  const SizedBox(width: 6),
                  Text(
                    'You\'re watching — cheer them on!',
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 12,
                      color: KinrelColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: KinrelSpacing.md),
            ReactionsBar(
              gameTable: 'tugofwar_games',
              gameId: state.game?.id ?? '',
              familyId: familyId,
              size: ReactionsBarSize.lg,
            ),
          ],
        ),
      );
    }

    final color =
        myTeam == TugTeam.a ? TugTeamBoardColors.a : TugTeamBoardColors.b;
    final scale = pressed ? 0.93 : 1.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          KinrelSpacing.base, KinrelSpacing.sm, KinrelSpacing.base, KinrelSpacing.base),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.isRateLimited)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Steady! Taps above 15/sec don\'t count',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: KinrelColors.warning,
                ),
              ),
            ),
          Listener(
            onPointerDown: (_) => onPull(),
            child: AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              child: Container(
                width: double.infinity,
                height: 84,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color,
                      Color.lerp(color, Colors.black, 0.35)!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(KinrelRadius.xl),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: pressed ? 0.55 : 0.35),
                      blurRadius: pressed ? 26 : 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'PULL!',
                      style: TextStyle(
                        fontFamily: KinrelTypography.displayFont,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${state.myLocalTaps} taps',
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: KinrelSpacing.sm),
          ReactionsBar(
            gameTable: 'tugofwar_games',
            gameId: state.game?.id ?? '',
            familyId: familyId,
            size: ReactionsBarSize.sm,
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Results view
// ────────────────────────────────────────────────────────────────────

class _ResultsView extends ConsumerWidget {
  const _ResultsView({
    required this.state,
    required this.familyId,
    required this.myUserId,
  });

  final TugOfWarState state;
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

    final winner = game.winningTeam;
    final winnerColor = winner == null
        ? KinrelColors.gold
        : (winner == TugTeam.a ? TugTeamBoardColors.a : TugTeamBoardColors.b);
    final iWon = winner != null && state.teamFor(myUserId) == winner;
    final durationSec = game.completedAt != null && game.startedAt != null
        ? game.completedAt!.difference(game.startedAt!).inSeconds
        : game.matchDurationSec;

    return ListView(
      padding: const EdgeInsets.all(KinrelSpacing.base),
      children: [
        const SizedBox(height: KinrelSpacing.xl),

        // ── Winner banner ──
        _WinnerBanner(
          winner: winner,
          winnerColor: winnerColor,
          winnerNames: state
              .teamRoster(winner ?? TugTeam.a)
              .map((p) => p.userName)
              .toList(),
          isDraw: winner == null,
        ),
        const SizedBox(height: KinrelSpacing.sm),
        Center(
          child: Text(
            game.endReasonLabel,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              color: KinrelColors.textDim,
            ),
          ),
        ),

        const SizedBox(height: KinrelSpacing.xl),

        // ── MVP trio ──
        if (state.players.isNotEmpty) ...[
          Text(
            'MOST VALUABLE PULLERS',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: KinrelColors.textDim,
            ),
          ),
          const SizedBox(height: KinrelSpacing.sm),
          _MvpRow(
            players: state.players,
            durationSec: durationSec == 0 ? 60 : durationSec,
          ),
          const SizedBox(height: KinrelSpacing.lg),
        ],

        // ── Team breakdown ──
        _TeamBreakdown(state: state, myUserId: myUserId),

        const SizedBox(height: KinrelSpacing.xl),

        // ── Ecosystem rewards ──
        MatchEcosystemSummary(
          gameTable: 'tugofwar_games',
          gameId: game.id,
          familyId: familyId,
        ),

        const SizedBox(height: KinrelSpacing.xl),

        // ── Rematch + exit ──
        _RematchRow(
          state: state,
          familyId: familyId,
          myUserId: myUserId,
          iWon: iWon,
        ),
        const SizedBox(height: KinrelSpacing.base),
      ],
    );
  }
}

class _WinnerBanner extends StatelessWidget {
  const _WinnerBanner({
    required this.winner,
    required this.winnerColor,
    required this.winnerNames,
    required this.isDraw,
  });

  final TugTeam? winner;
  final Color winnerColor;
  final List<String> winnerNames;
  final bool isDraw;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KinrelSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            winnerColor.withValues(alpha: 0.25),
            KinrelColors.darkCard,
          ],
        ),
        borderRadius: BorderRadius.circular(KinrelRadius.xl),
        border: Border.all(color: winnerColor.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: winnerColor.withValues(alpha: 0.3),
            blurRadius: 30,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '🏆',
            style: const TextStyle(fontSize: 52),
          ),
          const SizedBox(height: KinrelSpacing.sm),
          Text(
            isDraw
                ? 'Dead Heat!'
                : '${winner!.label} Wins!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: KinrelColors.textWhite,
            ),
          ),
          if (!isDraw && winnerNames.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              winnerNames.join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: winnerColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MvpRow extends StatelessWidget {
  const _MvpRow({
    required this.players,
    required this.durationSec,
  });

  final List<TugOfWarPlayer> players;
  final int durationSec;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) return const SizedBox.shrink();

    final mostTaps = players
        .reduce((a, b) => a.pullCount >= b.pullCount ? a : b);

    TugOfWarPlayer fastest = players.first;
    var bestRate = -1.0;
    for (final p in players) {
      final rate = p.pullCount / durationSec;
      if (rate > bestRate) {
        bestRate = rate;
        fastest = p;
      }
    }

    // Strongest contributor: highest share of their team's total.
    final teamTotals = <TugTeam, int>{};
    for (final p in players) {
      if (p.team != null) {
        teamTotals[p.team!] = (teamTotals[p.team!] ?? 0) + p.pullCount;
      }
    }
    TugOfWarPlayer strongest = players.first;
    var bestShare = -1.0;
    for (final p in players) {
      if (p.team == null || teamTotals[p.team!] == 0) continue;
      final share = p.pullCount / teamTotals[p.team!]!;
      if (share > bestShare) {
        bestShare = share;
        strongest = p;
      }
    }

    return Row(
      children: [
        Expanded(
          child: _MvpCard(
            emoji: '💪',
            title: 'Most Taps',
            player: mostTaps,
            value: '${mostTaps.pullCount}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MvpCard(
            emoji: '⚡',
            title: 'Fastest',
            player: fastest,
            value:
                '${(fastest.pullCount / durationSec).toStringAsFixed(1)}/s',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MvpCard(
            emoji: '🥇',
            title: 'MVP',
            player: strongest,
            value: '${(bestShare * 100).round()}%',
          ),
        ),
      ],
    );
  }
}

class _MvpCard extends StatelessWidget {
  const _MvpCard({
    required this.emoji,
    required this.title,
    required this.player,
    required this.value,
  });

  final String emoji;
  final String title;
  final TugOfWarPlayer player;
  final String value;

  @override
  Widget build(BuildContext context) {
    final color = player.team == TugTeam.a
        ? TugTeamBoardColors.a
        : TugTeamBoardColors.b;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: KinrelColors.textDim,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            player.userName.split(' ').first,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamBreakdown extends StatelessWidget {
  const _TeamBreakdown({required this.state, required this.myUserId});

  final TugOfWarState state;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
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
          Text(
            'TEAM BREAKDOWN',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: KinrelColors.textDim,
            ),
          ),
          const SizedBox(height: KinrelSpacing.md),
          for (final team in [TugTeam.a, TugTeam.b])
            _TeamRows(
              team: team,
              color: team == TugTeam.a
                  ? TugTeamBoardColors.a
                  : TugTeamBoardColors.b,
              players: state.teamRoster(team),
              myUserId: myUserId,
            ),
        ],
      ),
    );
  }
}

class _TeamRows extends StatelessWidget {
  const _TeamRows({
    required this.team,
    required this.color,
    required this.players,
    required this.myUserId,
  });

  final TugTeam team;
  final Color color;
  final List<TugOfWarPlayer> players;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final total = players.fold<int>(0, (s, p) => s + p.pullCount);
    final sorted = List<TugOfWarPlayer>.from(players)
      ..sort((a, b) => b.pullCount.compareTo(a.pullCount));

    return Padding(
      padding: const EdgeInsets.only(bottom: KinrelSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 6),
              Text(
                '${team.label} · $total taps',
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final p in sorted)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      p.userId == myUserId ? 'You' : p.userName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textWhite,
                        fontWeight: p.userId == myUserId
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        height: 6,
                        child: Stack(
                          children: [
                            Container(
                                color: KinrelColors.darkElevated),
                            FractionallySizedBox(
                              widthFactor: total == 0
                                  ? 0
                                  : (p.pullCount / total).clamp(0.0, 1.0),
                              child: Container(color: color),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 62,
                    child: Text(
                      '${p.pullCount} · ${total == 0 ? 0 : (p.pullCount * 100 / total).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontFamily: KinrelTypography.monoFont,
                        fontSize: 10,
                        color: KinrelColors.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RematchRow extends ConsumerWidget {
  const _RematchRow({
    required this.state,
    required this.familyId,
    required this.myUserId,
    required this.iWon,
  });

  final TugOfWarState state;
  final String familyId;
  final String? myUserId;
  final bool iWon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = state.game!;
    final isHost = game.hostUserId == myUserId;
    final notifier = ref.read(tugOfWarProvider(familyId).notifier);

    Future<void> rematch(bool keepTeams) async {
      GameMotionTokens.tap();
      final newId = await notifier.rematch(keepTeams: keepTeams);
      if (newId == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Couldn\'t start the rematch — try again'),
              backgroundColor: KinrelColors.error,
            ),
          );
        }
        return;
      }
      if (context.mounted) {
        context.go('/family/$familyId/tug-of-war/lobby?join=$newId');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isHost) ...[
          Row(
            children: [
              Expanded(
                child: _RematchButton(
                  icon: Icons.refresh,
                  label: 'Rematch · Same Teams',
                  primary: true,
                  onTap: () => rematch(true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RematchButton(
                  icon: Icons.shuffle,
                  label: 'Rematch · Shuffle',
                  primary: false,
                  onTap: () => rematch(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: KinrelSpacing.sm),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(KinrelSpacing.md),
            decoration: BoxDecoration(
              color: KinrelColors.darkCard,
              borderRadius: BorderRadius.circular(KinrelRadius.md),
              border: Border.all(color: KinrelColors.border),
            ),
            child: Text(
              iWon
                  ? 'Waiting for the host to set up the rematch… 🎉'
                  : 'Waiting for the host to set up the rematch… 😤',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                color: KinrelColors.textDim,
              ),
            ),
          ),
          const SizedBox(height: KinrelSpacing.sm),
        ],
        OutlinedButton.icon(
          onPressed: () {
            GameMotionTokens.tap();
            ref.read(tugOfWarProvider(familyId).notifier).leaveGame();
            context.go('/games?familyId=$familyId');
          },
          icon: const Icon(Icons.home_outlined, size: 16),
          label: const Text('Back to Games'),
          style: OutlinedButton.styleFrom(
            foregroundColor: KinrelColors.textDim,
            side: BorderSide(color: KinrelColors.border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
            ),
          ),
        ),
      ],
    );
  }
}

class _RematchButton extends StatelessWidget {
  const _RematchButton({
    required this.icon,
    required this.label,
    required this.primary,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          gradient: primary ? KinrelGradients.igniteGradient : null,
          color: primary ? null : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: primary
                ? Colors.transparent
                : KinrelColors.orange.withValues(alpha: 0.5),
          ),
          boxShadow: primary
              ? [
                  BoxShadow(
                    color: KinrelColors.orangeGlow,
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 15,
                color: primary ? Colors.white : KinrelColors.orange),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.displayFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: primary ? Colors.white : KinrelColors.orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
