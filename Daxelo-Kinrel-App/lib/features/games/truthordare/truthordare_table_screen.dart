// lib/features/games/truthordare/truthordare_table_screen.dart
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
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { ref.read(todProvider(widget.familyId).notifier).leaveGame(); Navigator.of(context).pop(); }),
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
    return Center(child: SizedBox(width: 280, height: 280, child: Stack(children: [
      // Player avatars arranged in a circle
      ...players.asMap().entries.map((entry) {
        final i = entry.key; final p = entry.value;
        final angle = (i / players.length) * 2 * math.pi - math.pi / 2;
        final radius = 120.0;
        final x = 140 + radius * math.cos(angle) - 20;
        final y = 140 + radius * math.sin(angle) - 20;
        final isSpinner = p.userId == game.currentSpinnerId;
        final isSelected = state.currentRound?.selectedPlayerId == p.userId;
        return Positioned(left: x, top: y, child: Column(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle,
            color: isSpinner ? KinrelColors.orange : (isSelected ? KinrelColors.success : KinrelColors.darkElevated),
            border: Border.all(color: isSpinner ? KinrelColors.orange : (isSelected ? KinrelColors.success : KinrelColors.border), width: 2),
            boxShadow: isSelected ? [BoxShadow(color: KinrelColors.success.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)] : null,
          ), child: Center(child: Text(p.userName.isNotEmpty ? p.userName[0].toUpperCase() : '?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isSpinner || isSelected ? Colors.white : KinrelColors.textDim)))),
          const SizedBox(height: 2),
          Text(p.userName.split(' ').first, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 9, color: isSpinner ? KinrelColors.orange : (isSelected ? KinrelColors.success : KinrelColors.textDim), fontWeight: FontWeight.w600)),
        ]));
      }),
      // Bottle in center
      Positioned(left: 110, top: 110, child: Transform.rotate(angle: _bottleAngle, child: Container(width: 60, height: 60, decoration: BoxDecoration(shape: BoxShape.circle, color: KinrelColors.darkCard, border: Border.all(color: KinrelColors.orange, width: 2)),
        child: Center(child: Icon(Icons.rotate_right, size: 28, color: KinrelColors.orange)),
      ))),
    ])));
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
      return Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: round!.choice == 'truth' ? KinrelColors.info : KinrelColors.error, width: 2)),
          child: Column(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: round.choice == 'truth' ? KinrelColors.info : KinrelColors.error, borderRadius: BorderRadius.circular(8)),
              child: Text(round.choice!.toUpperCase(), style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white))),
            const SizedBox(height: 12),
            Text(round.promptText ?? '', textAlign: TextAlign.center, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 16, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
          ])),
        const SizedBox(height: 16),
        if (iAmSelected) DKButton(label: 'Done!', variant: DKButtonVariant.gradient, icon: Icons.check, onPressed: () => ref.read(todProvider(widget.familyId).notifier).completeRound())
        else Text('Waiting for ${round.selectedPlayerName}...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
      ]));
    }

    if (showChoice) {
      return Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('${round!.selectedPlayerName}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 20, fontWeight: FontWeight.w800, color: KinrelColors.textWhite)),
        Text('Choose Truth or Dare', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)),
        const SizedBox(height: 20),
        if (iAmSelected) Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _choiceButton('Truth', KinrelColors.info, Icons.lightbulb_outline, () => ref.read(todProvider(widget.familyId).notifier).chooseTruthOrDare('truth')),
          _choiceButton('Dare', KinrelColors.error, Icons.local_fire_department_outlined, () => ref.read(todProvider(widget.familyId).notifier).chooseTruthOrDare('dare')),
        ])
        else Text('Waiting for ${round.selectedPlayerName}...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
      ]));
    }

    // Default: spin button
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (isMySpin) ...[
        Text('Your turn to spin!', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.orange)),
        const SizedBox(height: 16),
        DKButton(label: 'Spin the Bottle!', variant: DKButtonVariant.gradient, icon: Icons.refresh, onPressed: _spin),
      ] else ...[
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange)),
        const SizedBox(height: 8),
        Text('Waiting for spinner...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
      ],
    ]));
  }

  Widget _choiceButton(String label, Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(onTap: onTap,
      child: Container(width: 100, padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14), border: Border.all(color: color, width: 2)),
        child: Column(children: [Icon(icon, color: color, size: 28), const SizedBox(height: 4), Text(label, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 14, fontWeight: FontWeight.w700, color: color))]),
      ));
  }
}
