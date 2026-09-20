import '../../../core/widgets/person_avatar.dart';
// lib/features/games/truthordare/truthordare_table_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../../gaming_ecosystem/presentation/match_ecosystem_summary.dart';
import '../shared/icons/kinrel_icons.dart';
import '../shared/services/temporary_room_service.dart';
import '../shared/models/game_invite.dart';
import '../shared/widgets/game_board_shell.dart';
import '../shared/widgets/leave_game_dialog.dart';
import '../shared/widgets/rematch_button.dart';
import 'truthordare_models.dart';
import 'truthordare_provider.dart';

class TodTableScreen extends ConsumerStatefulWidget {
  const TodTableScreen({super.key, required this.familyId, required this.gameId});
  final String familyId; final String gameId;
  @override
  ConsumerState<TodTableScreen> createState() => _TodTableScreenState();
}

class _TodTableScreenState extends ConsumerState<TodTableScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;
  double _bottleAngle = 0;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(todProvider(widget.familyId));
      if (state.game == null) ref.read(todProvider(widget.familyId).notifier).joinGame(widget.gameId);
    });
  }

  @override
  void dispose() { _spinController.dispose(); super.dispose(); }

  /// Close / leave flow. When the HOST ends an in-progress game the match
  /// archives server-side (fn_end_game → fn__archive_family_match) — we then
  /// surface the Family Moments sheet so the celebration (badges, completed
  /// challenges, milestones) and the sportsmanship cheers are shown, matching
  /// every other game's results experience.
  Future<void> _onClosePressed() async {
    final state = ref.read(todProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final gameId = state.game?.id;
    final iAmHost = state.game?.hostUserId == myId;
    final wasInProgress = state.game != null && !state.game!.isWaiting;

    final shouldLeave = await LeaveGameDialog.show(
      context,
      isHost: iAmHost,
      gameName: 'Truth or Dare',
    );
    if (shouldLeave != true) return;
    if (!mounted) return;

    // End the match FIRST so the archive (stats/badges/challenges) is
    // committed before the rewards sheet reads it.
    if (gameId != null && iAmHost && wasInProgress) {
      try {
        await ref.read(temporaryRoomServiceProvider).endGame(
              gameTable: 'truthordare_games',
              gameId: gameId,
            );
      } catch (_) {}
    }

    ref.read(todProvider(widget.familyId).notifier).leaveGame();

    if (mounted && gameId != null && iAmHost && wasInProgress) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: KinrelColors.darkSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const KinrelIcon(KinrelIconData.sparkle,
                  size: 18, color: KinrelColors.amber),
                  const SizedBox(width: 8),
                  Text(
                    'FAMILY MOMENTS',
                    style: TextStyle(
                      fontFamily: KinrelTypography.monoFont,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                      color: KinrelColors.brightGold,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  'That was a game to remember!',
                  style: TextStyle(
                    fontFamily: KinrelTypography.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: KinrelColors.textWhite,
                  ),
                ),
                MatchEcosystemSummary(
                  gameTable: 'truthordare_games',
                  gameId: gameId,
                  familyId: widget.familyId,
                  padding: const EdgeInsets.only(top: 16),
                ),
                const SizedBox(height: 20),
                // Host-only sheet: one-tap rematch recreates the room and
                // invites everyone who played — the roster comes from the
                // `state` snapshot captured BEFORE leaveGame() cleared the
                // provider (the same capture-before-create rule as every
                // other game's RematchButton).
                RematchButton(
                  familyId: widget.familyId,
                  gameType: GameType.truthordare,
                  previousGameId: gameId,
                  participantUserIds:
                      state.players.map((p) => p.userId).toList(),
                  maxPlayers: 8,
                  beforeNavigate: () => Navigator.of(sheetContext).pop(),
                  onCreateNewGame: () => ref
                      .read(todProvider(widget.familyId).notifier)
                      .createGame(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: DKButton(
                    label: 'Back to Games',
                    variant: DKButtonVariant.gradient,
                    icon: Icons.sports_esports_rounded,
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/games?familyId=${widget.familyId}');
    }
  }

  void _spin() {
    final rng = math.Random();
    final extraRotations = 3 + rng.nextInt(3); // 3-5 full rotations
    final finalAngle = rng.nextDouble() * 2 * math.pi;
    final totalAngle = extraRotations * 2 * math.pi + finalAngle;

    _spinController.reset();
    final tween = Tween<double>(begin: _bottleAngle, end: _bottleAngle + totalAngle);
    final anim = tween.animate(CurvedAnimation(parent: _spinController, curve: Curves.decelerate));
    anim.addListener(() { setState(() { _bottleAngle = anim.value; }); });
    _spinController.forward().then((_) {
      ref.read(todProvider(widget.familyId).notifier).spinBottle();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final game = state.game;

    if (game == null) return DKScaffold(backgroundColor: KinrelColors.darkSurface, body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)));

    final isMySpin = game.currentSpinnerId == myId;
    final round = state.currentRound;
    final iAmSelected = round?.selectedPlayerId == myId;
    final showChoice = round != null && round.selectedPlayerId != null && round.choice == null;
    final showPrompt = round != null && round.choice != null && round.promptText != null && !round.completed;
    final showCompleted = round != null && round.completed;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _onClosePressed(),
        ),
        title: Text('Round ${game.roundNumber}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: SafeArea(child: Column(children: [
        // Players ring
        Expanded(flex: 3, child: _playersRing(state, game, myId)),
        // Bottle / action area
        Expanded(flex: 2, child: _actionArea(state, game, isMySpin, round, iAmSelected, showChoice, showPrompt, showCompleted, myId)),
      ])),
    );
  }

  Widget _playersRing(TodState state, TodGame game, String? myId) {
    final players = state.players;
    return Center(
      child: SizedBox(
        width: 290,
        height: 290,
        child: Stack(children: [
          // Premium felt table — radial teal-green felt with an inner
          // shadow groove and a subtle amber rim.
          Positioned.fill(child: Padding(padding: const EdgeInsets.all(8), child: _feltTable())),
          // Player seats arranged around the table
          ...players.asMap().entries.map((entry) {
            final i = entry.key; final p = entry.value;
            final angle = (i / players.length) * 2 * math.pi - math.pi / 2;
            final radius = 112.0;
            final x = 145 + radius * math.cos(angle) - 28;
            final y = 145 + radius * math.sin(angle) - 32;
            final isSpinner = p.userId == game.currentSpinnerId;
            final isSelected = state.currentRound?.selectedPlayerId == p.userId;
            return Positioned(left: x, top: y, child: _tableSeat(p, isSpinner, isSelected));
          }),
          // Bottle in center — same spin math, premium glass capsule
          Positioned(left: 131, top: 91, child: Transform.rotate(angle: _bottleAngle, child: _bottle())),
        ]),
      ),
    );
  }

  /// Casino-grade felt: radial teal-green gradient (center → edge), an
  /// inset dark groove ring that reads as an inner shadow, and a
  /// hairline amber rim around the whole table.
  Widget _feltTable() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(0, 0),
          radius: 1.0,
          colors: [Color(0xFF14342E), Color(0xFF0E2622)],
          stops: [0.55, 1.0],
        ),
        border: Border.all(color: KinrelColors.amber.withValues(alpha: 0.45), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 26, offset: const Offset(0, 10)),
          BoxShadow(color: KinrelColors.amber.withValues(alpha: 0.08), blurRadius: 40, spreadRadius: 6),
        ],
      ),
      child: Container(
        // Inner shadow ring — dark groove pressed into the felt.
        margin: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.38), width: 5),
        ),
        child: Container(
          // Soft top sheen inside the inset.
          margin: const EdgeInsets.all(5),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: Alignment(0, -0.35),
              radius: 0.9,
              colors: [Color(0x14FFFFFF), Color(0x00000000)],
            ),
          ),
        ),
      ),
    );
  }

  /// One seat around the table: a 3D chip avatar + name. The current
  /// spinner gets a pulsing amber ring; the player the bottle landed on
  /// gets a glowing "target" ring.
  Widget _tableSeat(TodPlayer p, bool isSpinner, bool isSelected) {
    final labelColor = isSelected ? KinrelColors.success : (isSpinner ? KinrelColors.amber : KinrelColors.textDim);
    return SizedBox(
      width: 56,
      height: 64,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(alignment: Alignment.center, children: [
            if (isSelected)
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: KinrelColors.success.withValues(alpha: 0.9), width: 2),
                  boxShadow: [BoxShadow(color: KinrelColors.success.withValues(alpha: 0.45), blurRadius: 12, spreadRadius: 2)],
                ),
              )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(begin: const Offset(1.0, 1.0), end: const Offset(1.12, 1.12), duration: 900.ms, curve: Curves.easeInOut)
            else if (isSpinner)
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: KinrelColors.amber.withValues(alpha: 0.85), width: 2),
                  boxShadow: [BoxShadow(color: KinrelColors.amber.withValues(alpha: 0.40), blurRadius: 10)],
                ),
              )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(begin: const Offset(0.96, 0.96), end: const Offset(1.10, 1.10), duration: 1100.ms, curve: Curves.easeInOut),
            GamePiece3D(
              color: isSelected ? KinrelColors.success : (isSpinner ? KinrelColors.amber : KinrelColors.darkElevated),
              size: 38,
              glow: isSelected,
              child: Text(
                PersonAvatar.initialsFor(p.userName),
                style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 2),
        Text(p.userName.split(' ').first, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 10, color: labelColor, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  /// Elongated glass capsule bottle — amber glass gradient with a
  /// white highlight stripe along the top and a soft drop shadow.
  /// Rotation comes from the existing spin controller ([_bottleAngle]).
  Widget _bottle() {
    return Container(
      width: 28,
      height: 108,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFD98A45), Color(0xFFA85A1E), Color(0xFF5E3010)],
        ),
        border: Border.all(color: Colors.black.withValues(alpha: 0.55), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, 5)),
          BoxShadow(color: KinrelColors.amber.withValues(alpha: 0.25), blurRadius: 16, spreadRadius: 1),
        ],
      ),
      child: Stack(children: [
        // Glassy highlight stripe along the top of the bottle.
        Positioned(left: 5, top: 10, bottom: 40, width: 5, child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white.withValues(alpha: 0.30), Colors.white.withValues(alpha: 0.0)],
            ),
          ),
        )),
        // Neck band.
        Positioned(left: 3, right: 3, top: 3, height: 7, child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF3A2415).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(4),
          ),
        )),
      ]),
    );
  }

  Widget _actionArea(TodState state, TodGame game, bool isMySpin, TodRound? round, bool iAmSelected, bool showChoice, bool showPrompt, bool showCompleted, String? myId) {
    if (state.isSpinning) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange)), const SizedBox(height: 8), Text('Spinning...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim))]));

    if (showCompleted) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle, size: 40, color: KinrelColors.success),
        const SizedBox(height: 8),
        Text('${round?.selectedPlayerName} completed!', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
        const SizedBox(height: 16),
        DKButton(label: 'Next Round', variant: DKButtonVariant.gradient, onPressed: () => ref.read(todProvider(widget.familyId).notifier).completeRound()),
      ]));
    }

    if (showPrompt) {
      final isTruth = round!.choice == 'truth';
      final accent = isTruth ? KinrelColors.tealAccent : KinrelColors.coral;
      return Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _promptCard(round, accent, isTruth),
        const SizedBox(height: 16),
        if (iAmSelected) DKButton(label: 'Done!', variant: DKButtonVariant.gradient, icon: Icons.check, onPressed: () => ref.read(todProvider(widget.familyId).notifier).completeRound())
        else GameTurnPill(label: 'Waiting for ${round.selectedPlayerName}…', color: accent, active: false),
      ]));
    }

    if (showChoice) {
      return Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('${round!.selectedPlayerName}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 20, fontWeight: FontWeight.w800, color: KinrelColors.textWhite)),
        Text('Choose Truth or Dare', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)),
        const SizedBox(height: 20),
        if (iAmSelected) Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _choiceButton('Truth', KinrelColors.tealAccent, Icons.help_outline, () => ref.read(todProvider(widget.familyId).notifier).chooseTruthOrDare('truth')),
          _choiceButton('Dare', KinrelColors.coral, Icons.local_fire_department, () => ref.read(todProvider(widget.familyId).notifier).chooseTruthOrDare('dare')),
        ])
        else GameTurnPill(label: 'Waiting for ${round.selectedPlayerName}…', color: KinrelColors.orange, active: false),
      ]));
    }

    // Default: spin button
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (isMySpin) ...[
        GameTurnPill(label: 'Your turn to spin!', color: KinrelColors.orange, active: true, icon: Icons.replay_rounded),
        const SizedBox(height: 16),
        DKButton(label: 'Spin the Bottle!', variant: DKButtonVariant.gradient, icon: Icons.refresh, onPressed: _spin),
      ] else ...[
        GameTurnPill(label: 'Waiting for spinner…', color: KinrelColors.orange, active: false,
          trailing: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange))),
      ],
    ]));
  }

  /// Premium prompt card — layered dark surface with an accent glow in
  /// the top-left corner, tinted border and icon chip. Teal = Truth,
  /// coral = Dare.
  Widget _promptCard(TodRound round, Color accent, bool isTruth) {
    return Container(
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 8)),
          BoxShadow(color: accent.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(children: [
          // Subtle accent glow in the top-left corner.
          Positioned(top: -46, left: -46, child: Container(width: 180, height: 180, decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.0)])))),
          Padding(padding: const EdgeInsets.all(18), child: Column(children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 34, height: 34, decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.15), border: Border.all(color: accent.withValues(alpha: 0.5))),
                child: Center(child: Icon(isTruth ? Icons.help_outline : Icons.local_fire_department, size: 18, color: accent))),
              const SizedBox(width: 10),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                child: Text(round.choice!.toUpperCase(), style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: accent))),
            ]),
            const SizedBox(height: 14),
            Text(round.promptText ?? '', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 16, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
          ])),
        ]),
      ),
    );
  }

  Widget _choiceButton(String label, Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(onTap: onTap,
      child: Container(width: 110, padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.08)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 6)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.18), border: Border.all(color: color.withValues(alpha: 0.6))),
            child: Center(child: Icon(icon, color: color, size: 22))),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 15, fontWeight: FontWeight.w700, color: color)),
        ]),
      ));
  }
}
