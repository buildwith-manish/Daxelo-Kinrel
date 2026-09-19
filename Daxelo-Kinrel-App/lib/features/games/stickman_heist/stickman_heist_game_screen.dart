// lib/features/games/stickman_heist/stickman_heist_game_screen.dart
//
// Stickman Heist — real-time match screen.
//
// Layout (portrait-first, mobile):
//
//   ┌────────────────────────────────────────────┐
//   │ [HP ▰▰▰▰▱]  PISTOL 12/12   2:43  SEARCHING │  ← Top HUD
//   │ Carrier: Priya · 3 kills                   │
//   ├────────────────────────────────────────────┤
//   │                                            │
//   │       ┌── walls ──┐                        │  ← Game world
//   │       │           │                        │     (CustomPainter,
//   │   ◯ ← you          ◯                       │      top-down view)
//   │       ◇ treasure                            │
//   │                          ◯                  │
//   │       └───────────┘                        │
//   │                                            │
//   ├────────────────────────────────────────────┤
//   │ ◯ joystick            [🔫] [🔄] [⇄]        │  ← Bottom controls
//   └────────────────────────────────────────────┘
//
// CustomPainter renders the world. Touch gestures drive the joystick +
// shoot button. The painter reads from `state.liveState` — which is
// updated either by the host's local sim (host case) or by Supabase
// Realtime (non-host case).

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
import '../../gaming_ecosystem/presentation/widgets/gaming_kit.dart';
import '../game_motion_tokens.dart';
import '../shared/icons/kinrel_icons.dart';
import '../shared/widgets/game_confetti.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/widgets/reactions_bar.dart';
import 'stickman_heist_models.dart';
import 'stickman_heist_provider.dart';

class StickmanHeistGameScreen extends ConsumerStatefulWidget {
  const StickmanHeistGameScreen({
    super.key,
    required this.familyId,
    required this.gameId,
  });
  final String familyId;
  final String gameId;

  @override
  ConsumerState<StickmanHeistGameScreen> createState() =>
      _StickmanHeistGameScreenState();
}

class _StickmanHeistGameScreenState
    extends ConsumerState<StickmanHeistGameScreen>
    with SingleTickerProviderStateMixin {
  /// One-time guard for the waiting-room redirect.
  bool _didWaitingRedirect = false;

  /// Live aim angle (radians) — driven by the shoot button drag.
  double _aimAngle = 0.0;

  /// True while the shoot button is held down.
  bool _shooting = false;

  /// One-shot reload trigger — set true on tap, cleared next frame.
  bool _reloadRequested = false;

  /// One-shot swap-weapon trigger.
  bool _swapRequested = false;

  /// Movement joystick output (-1..1, -1..1).
  Offset _moveVector = Offset.zero;

  /// Pulse animation for active escape zones / carrier glow.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state =
          ref.read(stickmanHeistProvider(widget.familyId));
      if (state.game == null) {
        ref
            .read(stickmanHeistProvider(widget.familyId).notifier)
            .loadGame(widget.gameId);
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final state = ref.read(stickmanHeistProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: state.game?.hostUserId == myId &&
          state.game?.isWaiting == true,
      gameName: 'Stickman Heist',
    );
    if (shouldLeave == true) {
      await ref
          .read(stickmanHeistProvider(widget.familyId).notifier)
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

  void _pushInput() {
    ref.read(stickmanHeistProvider(widget.familyId).notifier).updateInput(
          moveX: _moveVector.dx,
          moveY: _moveVector.dy,
          aimAngle: _aimAngle,
          shooting: _shooting,
          reloadRequested: _reloadRequested,
          swapWeaponRequested: _swapRequested,
        );
    // Clear one-shot flags.
    _reloadRequested = false;
    _swapRequested = false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stickmanHeistProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final game = state.game;

    // Waiting-room redirect.
    final waitingGameId =
        state.isWaiting && game?.id != null ? game!.id : null;
    if (waitingGameId != null && !_didWaitingRedirect) {
      _didWaitingRedirect = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.pushReplacement(
          '/family/${widget.familyId}/stickman-heist/lobby?join=$waitingGameId',
        );
      });
    }

    if (state.isLoading && game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _confirmLeave),
          title: const Text('Stickman Heist'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFEF4444)),
        ),
      );
    }

    if (game == null) {
      return DKScaffold(
        backgroundColor: KinrelColors.darkSurface,
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () =>
                  context.go('/family/${widget.familyId}')),
          title: const Text('Stickman Heist'),
          backgroundColor: KinrelColors.darkCard,
          foregroundColor: KinrelColors.textWhite,
        ),
        body: Center(
          child: GamingEmptyCard(
            emoji: '💎',
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
          game.roomName?.isNotEmpty == true ? game.roomName! : 'Stickman Heist',
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
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: _PhaseChip(state: state)),
          ),
          if (game.hostUserId == myId && game.isInProgress)
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
              state: state,
              familyId: widget.familyId,
              onRematch: () => ref
                  .read(stickmanHeistProvider(widget.familyId).notifier)
                  .rematch(),
              onExit: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/family/${widget.familyId}');
                }
              },
            )
          : _MatchView(
              state: state,
              myUserId: myId,
              pulse: _pulse,
              onMoveChanged: (v) {
                _moveVector = v;
                _pushInput();
              },
              onAimChanged: (angle) {
                _aimAngle = angle;
                _pushInput();
              },
              onShootPressed: () {
                _shooting = true;
                _pushInput();
              },
              onShootReleased: () {
                _shooting = false;
                _pushInput();
              },
              onReload: () {
                _reloadRequested = true;
                _pushInput();
              },
              onSwapWeapon: () {
                _swapRequested = true;
                _pushInput();
              },
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Phase chip (top-right)
// ═════════════════════════════════════════════════════════════════════

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.state});
  final StickmanHeistState_ state;

  @override
  Widget build(BuildContext context) {
    final phase = state.liveState?.phase ?? StickmanHeistPhase.searching;
    final color = phase == StickmanHeistPhase.escapePhase
        ? const Color(0xFFEF4444)
        : phase == StickmanHeistPhase.carrierActive
            ? KinrelColors.amber
            : const Color(0xFF94A3B8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        phase.label.toUpperCase(),
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: color,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Match view — HUD + arena + controls
// ═════════════════════════════════════════════════════════════════════

class _MatchView extends StatelessWidget {
  const _MatchView({
    required this.state,
    required this.myUserId,
    required this.pulse,
    required this.onMoveChanged,
    required this.onAimChanged,
    required this.onShootPressed,
    required this.onShootReleased,
    required this.onReload,
    required this.onSwapWeapon,
  });

  final StickmanHeistState_ state;
  final String? myUserId;
  final AnimationController pulse;

  final void Function(Offset) onMoveChanged;
  final void Function(double) onAimChanged;
  final VoidCallback onShootPressed;
  final VoidCallback onShootReleased;
  final VoidCallback onReload;
  final VoidCallback onSwapWeapon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopHud(state: state, myUserId: myUserId),
        Expanded(
          child: Stack(
            children: [
              _ArenaView(state: state, myUserId: myUserId, pulse: pulse),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ControlsBar(
                  state: state,
                  onMoveChanged: onMoveChanged,
                  onAimChanged: onAimChanged,
                  onShootPressed: onShootPressed,
                  onShootReleased: onShootReleased,
                  onReload: onReload,
                  onSwapWeapon: onSwapWeapon,
                ),
              ),
              // Floating event banner (top-center)
              if (state.liveState?.events.isNotEmpty == true)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: _EventBanner(state: state),
                ),
            ],
          ),
        ),
        if (state.amSpectator)
          ReactionsBar(
            gameTable: 'stickman_heist_games',
            gameId: state.game?.id ?? '',
            familyId: state.game?.familyId ?? '',
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Top HUD
// ═════════════════════════════════════════════════════════════════════

class _TopHud extends StatelessWidget {
  const _TopHud({required this.state, required this.myUserId});
  final StickmanHeistState_ state;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final live = state.liveState;
    final myIdx = state.game?.idxForUserId(myUserId) ?? -1;
    final me = live?.players.where((p) => p.idx == myIdx).firstOrNull;
    final carrier = live?.carrier;
    final seconds = live?.matchTimeRemaining ?? 0;
    final phase = live?.phase ?? StickmanHeistPhase.searching;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        border: Border(bottom: BorderSide(color: KinrelColors.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // HP bar
              Expanded(
                flex: 2,
                child: _HpBar(
                  health: me?.health ?? 100,
                  maxHealth: me?.maxHealth ?? 100,
                  shield: me?.shieldActive ?? false,
                ),
              ),
              const SizedBox(width: 8),
              // Weapon + ammo
              Expanded(
                flex: 2,
                child: _WeaponChip(
                  weapon: me?.weapon ?? StickmanHeistWeapon.pistol,
                  ammo: me?.ammo ?? 0,
                  maxAmmo: me?.maxAmmo ?? 12,
                  reloading: me?.isReloading ?? false,
                ),
              ),
              const SizedBox(width: 8),
              // Timer
              _TimerChip(seconds: seconds),
              const SizedBox(width: 8),
              // Kills
              _KillsChip(kills: me?.kills ?? 0),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                phase == StickmanHeistPhase.searching
                    ? Icons.search
                    : phase == StickmanHeistPhase.carrierActive
                        ? Icons.person_pin_circle_outlined
                        : phase == StickmanHeistPhase.escapePhase
                            ? Icons.directions_run
                            : Icons.flag_outlined,
                size: 14,
                color: phase == StickmanHeistPhase.escapePhase
                    ? const Color(0xFFEF4444)
                    : phase == StickmanHeistPhase.carrierActive
                        ? KinrelColors.amber
                        : KinrelColors.textDim,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  phase == StickmanHeistPhase.searching
                      ? 'Find the treasure!'
                      : phase == StickmanHeistPhase.carrierActive
                          ? (carrier != null
                              ? 'Carrier: ${carrier.name}'
                              : 'Carrier identified')
                          : phase == StickmanHeistPhase.escapePhase
                              ? 'Escape!'
                              : 'Match over',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: phase == StickmanHeistPhase.escapePhase
                        ? const Color(0xFFEF4444)
                        : KinrelColors.textWhite,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HpBar extends StatelessWidget {
  const _HpBar({
    required this.health,
    required this.maxHealth,
    required this.shield,
  });
  final int health;
  final int maxHealth;
  final bool shield;

  @override
  Widget build(BuildContext context) {
    final pct = maxHealth == 0 ? 0.0 : (health / maxHealth).clamp(0.0, 1.0);
    final color = pct > 0.6
        ? const Color(0xFF10B981)
        : pct > 0.3
            ? KinrelColors.amber
            : const Color(0xFFEF4444);
    return Container(
      height: 18,
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Stack(
        children: [
          FractionallySizedBox(
            widthFactor: pct,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (shield) ...[
                  const Icon(Icons.shield,
                      size: 10, color: Color(0xFF3B82F6)),
                  const SizedBox(width: 4),
                ],
                Text(
                  '$health/$maxHealth',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.textWhite,
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

class _WeaponChip extends StatelessWidget {
  const _WeaponChip({
    required this.weapon,
    required this.ammo,
    required this.maxAmmo,
    required this.reloading,
  });
  final StickmanHeistWeapon weapon;
  final int ammo;
  final int maxAmmo;
  final bool reloading;

  @override
  Widget build(BuildContext context) {
    final accent = Color(weapon.accentArgb);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_fixed, size: 11, color: accent),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weapon.label.toUpperCase(),
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                Text(
                  reloading
                      ? 'RELOADING…'
                      : '$ammo / $maxAmmo',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
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

class _TimerChip extends StatelessWidget {
  const _TimerChip({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final color = seconds <= 10
        ? const Color(0xFFEF4444)
        : seconds <= 30
            ? KinrelColors.amber
            : KinrelColors.textWhite;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: KinrelColors.darkElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: KinrelColors.border),
      ),
      child: Text(
        '$m:${s.toString().padLeft(2, '0')}',
        style: TextStyle(
          fontFamily: KinrelTypography.monoFont,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _KillsChip extends StatelessWidget {
  const _KillsChip({required this.kills});
  final int kills;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.target, size: 11, color: Color(0xFFEF4444)),
          const SizedBox(width: 4),
          Text(
            '$kills',
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Event banner
// ═════════════════════════════════════════════════════════════════════

class _EventBanner extends StatelessWidget {
  const _EventBanner({required this.state});
  final StickmanHeistState_ state;

  @override
  Widget build(BuildContext context) {
    final events = state.liveState?.events ?? const [];
    if (events.isEmpty) return const SizedBox.shrink();
    final latest = events.first;
    final color = Color(latest.color);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          latest.text,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Arena view — CustomPainter
// ═════════════════════════════════════════════════════════════════════

class _ArenaView extends StatelessWidget {
  const _ArenaView({
    required this.state,
    required this.myUserId,
    required this.pulse,
  });

  final StickmanHeistState_ state;
  final String? myUserId;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              return CustomPaint(
                painter: _ArenaPainter(
                  state: state,
                  myUserId: myUserId,
                  pulseValue: pulse.value,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ArenaPainter extends CustomPainter {
  _ArenaPainter({
    required this.state,
    required this.myUserId,
    required this.pulseValue,
  });

  final StickmanHeistState_ state;
  final String? myUserId;
  final double pulseValue;

  static const _hw = kStickmanHeistMapHalfWidth;
  static const _hh = kStickmanHeistMapHalfHeight;

  Offset _physicsToLocal(Rect rect, double px, double py) {
    // Map physics (-hw..+hw, -hh..+hh) to local rect.
    // +x = right, +y = down (flip y so positive physics-y is up).
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final sx = (rect.width / 2) / _hw;
    final sy = (rect.height / 2) / _hh;
    return Offset(cx + px * sx, cy - py * sy);
  }

  double _scaleX(Rect rect) => (rect.width / 2) / _hw;
  double _scaleY(Rect rect) => (rect.height / 2) / _hh;
  double _scaleAvg(Rect rect) =>
      ((_scaleX(rect)) + (_scaleY(rect))) / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // ── Background ──
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0xFF0F1424),
          Color(0xFF16182B),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    // ── Grid (subtle) ──
    final gridPaint = Paint()
      ..color = const Color(0xFF2A2F4A)
      ..strokeWidth = 0.6;
    final stepX = rect.width / 10;
    final stepY = rect.height / 10;
    for (var i = 1; i < 10; i++) {
      canvas.drawLine(
        Offset(rect.left + i * stepX, rect.top),
        Offset(rect.left + i * stepX, rect.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(rect.left, rect.top + i * stepY),
        Offset(rect.right, rect.top + i * stepY),
        gridPaint,
      );
    }

    // ── Arena border ──
    final borderPaint = Paint()
      ..color = const Color(0xFF3B3F5C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRect(rect, borderPaint);

    final live = state.liveState;
    if (live == null) return;

    // ── Map walls ──
    final wallPaint = Paint()
      ..color = const Color(0xFF3B3F5C)
      ..style = PaintingStyle.fill;
    final wallStroke = Paint()
      ..color = const Color(0xFF5B6080)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final wall in StickmanHeistMap.byId(live.mapId).walls) {
      final a = _physicsToLocal(rect, wall.x1, wall.y1);
      final b = _physicsToLocal(rect, wall.x2, wall.y2);
      // Walls are drawn as thin rectangles — give them a small thickness.
      final perp = Offset(-(b.dy - a.dy), (b.dx - a.dx)).normalize() * 1.2;
      final path = Path()
        ..moveTo(a.dx + perp.dx, a.dy + perp.dy)
        ..lineTo(b.dx + perp.dx, b.dy + perp.dy)
        ..lineTo(b.dx - perp.dx, b.dy - perp.dy)
        ..lineTo(a.dx - perp.dx, a.dy - perp.dy)
        ..close();
      canvas.drawPath(path, wallPaint);
      canvas.drawPath(path, wallStroke);
    }

    // ── Escape zones (corners) ──
    for (final zone in live.escapeZones) {
      final center = _physicsToLocal(rect, zone.x, zone.y);
      final radius = zone.radius * _scaleAvg(rect);
      final pulse = 0.5 + 0.5 * pulseValue;
      final color = zone.active
          ? const Color(0xFF10B981).withValues(alpha: 0.18 + 0.18 * pulse)
          : const Color(0xFF10B981).withValues(alpha: 0.06);
      canvas.drawCircle(center, radius, Paint()..color = color);
      final rim = Paint()
        ..color = zone.active
            ? const Color(0xFF10B981).withValues(alpha: 0.7 + 0.3 * pulse)
            : const Color(0xFF10B981).withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = zone.active ? 2.4 : 1.2;
      canvas.drawCircle(center, radius, rim);
      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: zone.label,
          style: TextStyle(
            color: zone.active
                ? const Color(0xFF10B981)
                : const Color(0xFF10B981).withValues(alpha: 0.4),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            fontFamily: 'DMMono',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(center.dx - tp.width / 2,
              center.dy - radius - 14));
    }

    // ── Weapon spawns ──
    for (final ws in live.weaponSpawns) {
      if (ws.taken) continue;
      final center = _physicsToLocal(rect, ws.x, ws.y);
      final accent = Color(ws.weapon.accentArgb);
      final side = 12.0;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: side, height: side),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rrect,
        Paint()..color = accent.withValues(alpha: 0.85),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      // First-letter label
      final tp = TextPainter(
        text: TextSpan(
          text: ws.weapon.label[0],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            fontFamily: 'DMMono',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          Offset(center.dx - tp.width / 2,
              center.dy - tp.height / 2));
    }

    // ── Powerup spawns ──
    for (final ps in live.powerupSpawns) {
      if (ps.taken) continue;
      final center = _physicsToLocal(rect, ps.x, ps.y);
      final accent = Color(ps.type.accentArgb);
      canvas.drawCircle(
        center,
        7,
        Paint()..color = accent.withValues(alpha: 0.85),
      );
      canvas.drawCircle(
        center,
        7,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // ── Treasure (when on the ground) ──
    if (live.treasure.isOnGround) {
      final t = _physicsToLocal(rect, live.treasure.x, live.treasure.y);
      final pulse2 = 0.5 + 0.5 * pulseValue;
      // Glow
      canvas.drawCircle(
        t,
        18 + 6 * pulse2,
        Paint()
          ..color = const Color(0xFFFCD34D)
              .withValues(alpha: 0.15 + 0.15 * pulse2),
      );
      // Diamond
      final diamondPath = Path()
        ..moveTo(t.dx, t.dy - 10)
        ..lineTo(t.dx + 8, t.dy)
        ..lineTo(t.dx, t.dy + 10)
        ..lineTo(t.dx - 8, t.dy)
        ..close();
      canvas.drawPath(
        diamondPath,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFCD34D), Color(0xFFB45309)],
          ).createShader(
              Rect.fromCircle(center: t, radius: 12)),
      );
      canvas.drawPath(
        diamondPath,
        Paint()
          ..color = const Color(0xFFFCD34D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // ── Projectiles ──
    for (final proj in live.projectiles) {
      final p = _physicsToLocal(rect, proj.x, proj.y);
      canvas.drawCircle(
        p,
        3,
        Paint()..color = const Color(0xFFFCD34D),
      );
      // Small trail
      final tailX = proj.x - proj.vx * 0.02;
      final tailY = proj.y - proj.vy * 0.02;
      final tail = _physicsToLocal(rect, tailX, tailY);
      canvas.drawLine(
        tail,
        p,
        Paint()
          ..color = const Color(0xFFFCD34D).withValues(alpha: 0.5)
          ..strokeWidth = 2.0,
      );
    }

    // ── Players (stickmen) ──
    final myIdx = state.game?.idxForUserId(myUserId) ?? -1;
    for (final player in live.players) {
      if (!player.isAlive) continue;
      final pos = _physicsToLocal(rect, player.x, player.y);
      final isMe = player.idx == myIdx;
      final isCarrier = player.hasTreasure;
      final teamColor = isCarrier
          ? const Color(0xFFFCD34D)
          : isMe
              ? const Color(0xFF22D3EE)
              : _playerColor(player.idx);
      _drawStickman(
        canvas,
        pos,
        player.angle,
        teamColor,
        isMe: isMe,
        isCarrier: isCarrier,
        scale: _scaleAvg(rect),
        pulseValue: pulseValue,
        name: player.name,
      );
    }
  }

  /// Pick a stable, distinguishable color per player idx.
  Color _playerColor(int idx) {
    const palette = [
      Color(0xFFEF4444), // red
      Color(0xFF22D3EE), // cyan
      Color(0xFFA855F7), // purple
      Color(0xFF10B981), // emerald
      Color(0xFFF59E0B), // amber
      Color(0xFFEC4899), // pink
      Color(0xFF3B82F6), // blue
      Color(0xFF94A3B8), // slate
    ];
    return palette[idx % palette.length];
  }

  void _drawStickman(
    Canvas canvas,
    Offset pos,
    double angle,
    Color color, {
    required bool isMe,
    required bool isCarrier,
    required double scale,
    required double pulseValue,
    required String name,
  }) {
    final r = kStickmanHeistPlayerRadius * scale;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    // Carrier glow
    if (isCarrier) {
      final glow = Paint()
        ..color = const Color(0xFFFCD34D)
            .withValues(alpha: 0.15 + 0.15 * pulseValue)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 + 1.4 * pulseValue;
      canvas.drawCircle(pos, r + 6 + 4 * pulseValue, glow);
    }

    // Myself ring
    if (isMe) {
      final ring = Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawCircle(pos, r + 3, ring);
    }

    // Body (circle for head)
    canvas.drawCircle(
      pos,
      r,
      Paint()..color = color.withValues(alpha: 0.25),
    );
    canvas.drawCircle(pos, r, stroke);

    // Aim line — direction the player is facing.
    // Note: physics y is positive-up but local y is positive-down; we
    // already flipped the y axis in _physicsToLocal so the aim angle
    // (in physics space) needs to be flipped here too: negate the y
    // component when projecting into local space.
    final aimEndFlipped = Offset(
        pos.dx + math.cos(angle) * (r + 12),
        pos.dy - math.sin(angle) * (r + 12));
    canvas.drawLine(
      pos,
      aimEndFlipped,
      Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
    // tiny arrowhead
    const arrowSize = 6.0;
    final arrowPath = Path()
      ..moveTo(aimEndFlipped.dx, aimEndFlipped.dy)
      ..lineTo(
        aimEndFlipped.dx -
            arrowSize * math.cos(angle - 0.4),
        aimEndFlipped.dy +
            arrowSize * math.sin(angle - 0.4),
      )
      ..lineTo(
        aimEndFlipped.dx -
            arrowSize * math.cos(angle + 0.4),
        aimEndFlipped.dy +
            arrowSize * math.sin(angle + 0.4),
      )
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = color);

    // Name label
    final tp = TextPainter(
      text: TextSpan(
        text: isCarrier ? '💎 $name' : name,
        style: TextStyle(
          color: isCarrier
              ? const Color(0xFFFCD34D)
              : KinrelColors.textWhite,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          fontFamily: 'DMSans',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas,
        Offset(pos.dx - tp.width / 2,
            pos.dy - r - 18 - tp.height));
  }

  @override
  bool shouldRepaint(covariant _ArenaPainter oldDelegate) => true;
}

// ═════════════════════════════════════════════════════════════════════
// Controls bar — joystick + shoot/reload/swap buttons
// ═════════════════════════════════════════════════════════════════════

class _ControlsBar extends StatelessWidget {
  const _ControlsBar({
    required this.state,
    required this.onMoveChanged,
    required this.onAimChanged,
    required this.onShootPressed,
    required this.onShootReleased,
    required this.onReload,
    required this.onSwapWeapon,
  });

  final StickmanHeistState_ state;
  final void Function(Offset) onMoveChanged;
  final void Function(double) onAimChanged;
  final VoidCallback onShootPressed;
  final VoidCallback onShootReleased;
  final VoidCallback onReload;
  final VoidCallback onSwapWeapon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Left side: movement joystick
          _Joystick(
            onChanged: onMoveChanged,
            accent: const Color(0xFF22D3EE),
          ),
          const Spacer(),
          // Right side: shoot + reload + swap
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SmallActionButton(
                    icon: Icons.swap_horiz,
                    label: 'SWAP',
                    accent: const Color(0xFFA855F7),
                    onPressed: onSwapWeapon,
                  ),
                  const SizedBox(width: 8),
                  _SmallActionButton(
                    icon: Icons.refresh,
                    label: 'RELOAD',
                    accent: const Color(0xFFF59E0B),
                    onPressed: onReload,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ShootButton(
                onPressed: onShootPressed,
                onReleased: onShootReleased,
                onAimChanged: onAimChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Virtual movement joystick. Tracks touch position within a circular
/// area and outputs a normalized (-1..1, -1..1) vector.
class _Joystick extends StatefulWidget {
  const _Joystick({required this.onChanged, required this.accent});
  final void Function(Offset) onChanged;
  final Color accent;

  @override
  State<_Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<_Joystick> {
  static const _radius = 60.0;
  Offset _center = Offset.zero;
  Offset _knob = Offset.zero;
  bool _active = false;
  int? _currentPointer;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _radius * 2 + 20,
      height: _radius * 2 + 20,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          final box = context.findRenderObject() as RenderBox;
          setState(() {
            _center = box.size.center(Offset.zero);
            _knob = e.localPosition - _center;
            _active = true;
            _currentPointer = e.pointer;
          });
          _emit();
        },
        onPointerMove: (e) {
          if (!_active || e.pointer != _currentPointer) return;
          final delta = e.localPosition - _center;
          final dist = delta.distance;
          final clamped = dist > _radius
              ? Offset(delta.dx / dist * _radius,
                  delta.dy / dist * _radius)
              : delta;
          setState(() => _knob = clamped);
          _emit();
        },
        onPointerUp: (e) {
          if (e.pointer != _currentPointer) return;
          setState(() {
            _knob = Offset.zero;
            _active = false;
            _currentPointer = null;
          });
          widget.onChanged(Offset.zero);
        },
        onPointerCancel: (e) {
          setState(() {
            _knob = Offset.zero;
            _active = false;
            _currentPointer = null;
          });
          widget.onChanged(Offset.zero);
        },
        child: CustomPaint(
          painter: _JoystickPainter(
            knob: _knob,
            active: _active,
            accent: widget.accent,
            radius: _radius,
          ),
        ),
      ),
    );
  }

  void _emit() {
    // Normalize to -1..1. Screen y is positive-down, but physics y is
    // positive-up — so we negate y to map "drag up = move up".
    final nx = (_knob.dx / _radius).clamp(-1.0, 1.0);
    final ny = (-_knob.dy / _radius).clamp(-1.0, 1.0);
    widget.onChanged(Offset(nx, ny));
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({
    required this.knob,
    required this.active,
    required this.accent,
    required this.radius,
  });
  final Offset knob;
  final bool active;
  final Color accent;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Outer ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = KinrelColors.darkCard.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = accent.withValues(alpha: active ? 0.8 : 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2.4 : 1.6,
    );
    // Inner cross-hair
    canvas.drawLine(
      Offset(center.dx - radius * 0.6, center.dy),
      Offset(center.dx + radius * 0.6, center.dy),
      Paint()
        ..color = accent.withValues(alpha: 0.2)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius * 0.6),
      Offset(center.dx, center.dy + radius * 0.6),
      Paint()
        ..color = accent.withValues(alpha: 0.2)
        ..strokeWidth = 1,
    );
    // Knob
    final knobPos = center + knob;
    canvas.drawCircle(
      knobPos,
      22,
      Paint()..color = accent.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      knobPos,
      22,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) =>
      knob != oldDelegate.knob || active != oldDelegate.active;
}

/// Big circular shoot button. Hold to shoot; the aim direction follows
/// the drag from the center (so the player can rotate aim while
/// shooting).
class _ShootButton extends StatefulWidget {
  const _ShootButton({
    required this.onPressed,
    required this.onReleased,
    required this.onAimChanged,
  });
  final VoidCallback onPressed;
  final VoidCallback onReleased;
  final void Function(double) onAimChanged;

  @override
  State<_ShootButton> createState() => _ShootButtonState();
}

class _ShootButtonState extends State<_ShootButton> {
  static const _radius = 56.0;
  Offset _center = Offset.zero;
  Offset _drag = Offset.zero;
  bool _held = false;
  int? _pointer;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _radius * 2,
      height: _radius * 2,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          final box = context.findRenderObject() as RenderBox;
          setState(() {
            _center = box.size.center(Offset.zero);
            _drag = e.localPosition - _center;
            _held = true;
            _pointer = e.pointer;
          });
          widget.onPressed();
          _emitAim();
        },
        onPointerMove: (e) {
          if (!_held || e.pointer != _pointer) return;
          setState(() {
            _drag = e.localPosition - _center;
          });
          _emitAim();
        },
        onPointerUp: (e) {
          if (e.pointer != _pointer) return;
          setState(() {
            _held = false;
            _drag = Offset.zero;
            _pointer = null;
          });
          widget.onReleased();
        },
        onPointerCancel: (e) {
          setState(() {
            _held = false;
            _drag = Offset.zero;
            _pointer = null;
          });
          widget.onReleased();
        },
        child: CustomPaint(
          painter: _ShootButtonPainter(
            held: _held,
            drag: _drag,
            radius: _radius,
          ),
        ),
      ),
    );
  }

  void _emitAim() {
    // Aim angle in physics space (y up). Screen y is down → negate.
    if (_drag.distance < 6) return;
    final angle = math.atan2(-_drag.dy, _drag.dx);
    widget.onAimChanged(angle);
  }
}

class _ShootButtonPainter extends CustomPainter {
  _ShootButtonPainter({
    required this.held,
    required this.drag,
    required this.radius,
  });
  final bool held;
  final Offset drag;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const accent = Color(0xFFEF4444);
    // Outer glow
    if (held) {
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()..color = accent.withValues(alpha: 0.18),
      );
    }
    // Button body
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: [
            accent.withValues(alpha: held ? 1.0 : 0.85),
            accent.withValues(alpha: held ? 0.85 : 0.55),
          ],
        ).createShader(
            Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    // Crosshair icon in the center
    final iconPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx - 12, center.dy),
      Offset(center.dx + 12, center.dy),
      iconPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 12),
      Offset(center.dx, center.dy + 12),
      iconPaint,
    );
    canvas.drawCircle(
        center, 4, Paint()..color = Colors.white);

    // Aim direction indicator (small arrow on the rim)
    if (held && drag.distance > 6) {
      final dir = drag.normalize() * (radius - 4);
      final tip = center + dir;
      canvas.drawCircle(
          tip, 6, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _ShootButtonPainter oldDelegate) =>
      held != oldDelegate.held || drag != oldDelegate.drag;
}

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        GameMotionTokens.tap();
        onPressed();
      },
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.18),
          shape: BoxShape.circle,
          border: Border.all(color: accent.withValues(alpha: 0.7)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: accent,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Results view
// ═════════════════════════════════════════════════════════════════════

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.game,
    required this.state,
    required this.familyId,
    required this.onRematch,
    required this.onExit,
  });

  final StickmanHeistGame game;
  final StickmanHeistState_ state;
  final String familyId;
  final Future<String?> Function() onRematch;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final live = state.liveState;
    final winnerIdx = live?.winnerIdx ?? -1;
    final winnerName = winnerIdx >= 0
        ? (live?.players
                .where((p) => p.idx == winnerIdx)
                .firstOrNull
                ?.name ??
            'Unknown')
        : 'No one';
    final didEscape = winnerIdx >= 0;
    final winnerColor = didEscape
        ? const Color(0xFF10B981)
        : const Color(0xFFEF4444);

    // Sort players by kills for the leaderboard.
    final sortedPlayers = List<StickmanHeistPlayer>.from(
        live?.players ?? const []);
    sortedPlayers.sort((a, b) =>
        b.kills.compareTo(a.kills) != 0
            ? b.kills.compareTo(a.kills)
            : b.deaths.compareTo(a.deaths));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(KinrelSpacing.lg),
      child: Column(
        children: [
          if (didEscape) const GameConfetti(),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  winnerColor.withValues(alpha: 0.18),
                  const Color(0xFF1C1410),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: winnerColor.withValues(alpha: 0.45)),
            ),
            child: Column(
              children: [
                const KinrelIcon(KinrelIconData.trophy,
                    size: 40, color: KinrelColors.brightGold),
                const SizedBox(height: 8),
                Text(
                  didEscape
                      ? '$winnerName escaped with the treasure!'
                      : 'Time out — no one escaped',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: KinrelColors.brightGold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  didEscape ? 'Victory!' : 'No winner',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 13,
                    color: KinrelColors.textSilver,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Leaderboard ──
          GamingSectionHeader(
              title: 'Leaderboard', icon: Icons.leaderboard_outlined),
          for (var i = 0; i < sortedPlayers.length; i++)
            _LeaderboardRow(
              rank: i + 1,
              player: sortedPlayers[i],
              isWinner: sortedPlayers[i].idx == winnerIdx,
            ),
          const SizedBox(height: 18),

          // ── Match stats summary ──
          GamingSectionHeader(
              title: 'Match Summary', icon: Icons.insights_outlined),
          _StatRow(
              label: 'Map',
              value: StickmanHeistMap.byId(game.mapId).name),
          _StatRow(
              label: 'Match length',
              value: '${game.matchSeconds ~/ 60}m ${game.matchSeconds % 60}s'),
          _StatRow(
              label: 'Respawns',
              value: game.respawnsEnabled ? 'On' : 'Off'),
          _StatRow(
              label: 'Players',
              value: '${game.playerOrder.length}'),
          if (game.startedAt != null && game.completedAt != null)
            _StatRow(
              label: 'Duration',
              value: _formatDuration(
                  game.completedAt!.difference(game.startedAt!))),
          const SizedBox(height: 18),

          // ── Ecosystem summary (Family Cup, achievements, etc.) ─
          MatchEcosystemSummary(
            gameTable: 'stickman_heist_games',
            gameId: game.id,
            familyId: familyId,
          ),
          const SizedBox(height: 18),

          // ── Action buttons ──
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
                        '/family/$familyId/stickman-heist/game/$newId',
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

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s}s';
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.player,
    required this.isWinner,
  });
  final int rank;
  final StickmanHeistPlayer player;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final accent = isWinner
        ? KinrelColors.brightGold
        : rank == 1
            ? KinrelColors.amber
            : rank == 2
                ? const Color(0xFF94A3B8)
                : rank == 3
                    ? const Color(0xFFCD7F32)
                    : KinrelColors.textDim;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isWinner
              ? accent.withValues(alpha: 0.08)
              : KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isWinner
                  ? accent.withValues(alpha: 0.5)
                  : KinrelColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '#$rank',
                style: TextStyle(
                  fontFamily: KinrelTypography.monoFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
            Expanded(
              child: Text(
                player.name,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            if (player.hasTreasure)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('💎',
                    style: TextStyle(fontSize: 12)),
              ),
            _StatPill(label: 'K', value: '${player.kills}', color: const Color(0xFFEF4444)),
            const SizedBox(width: 4),
            _StatPill(label: 'D', value: '${player.deaths}', color: KinrelColors.textDim),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: KinrelTypography.monoFont,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(width: 2),
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
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 12,
                  color: KinrelColors.textDim,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
