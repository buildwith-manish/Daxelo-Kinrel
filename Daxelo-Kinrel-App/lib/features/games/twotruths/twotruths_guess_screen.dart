// lib/features/games/twotruths/twotruths_guess_screen.dart
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
import 'twotruths_models.dart';
import 'twotruths_provider.dart';

class TtGuessScreen extends ConsumerStatefulWidget {
  const TtGuessScreen({super.key, required this.familyId, required this.gameId}); final String familyId; final String gameId;
  @override
  ConsumerState<TtGuessScreen> createState() => _TtGuessScreenState();
}
class _TtGuessScreenState extends ConsumerState<TtGuessScreen> {
  Timer? _tick;
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (ref.read(ttProvider(widget.familyId)).game == null) ref.read(ttProvider(widget.familyId).notifier).joinGame(widget.gameId); }); _tick = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); }); }
  @override
  void dispose() { _tick?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ttProvider(widget.familyId)); final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final game = state.game;

    if (game?.roundResolved == true && mounted) { WidgetsBinding.instance.addPostFrameCallback((_) => context.pushReplacement('/family/${widget.familyId}/twotruths/results/${widget.gameId}')); }
    if (game == null) return DKScaffold(backgroundColor: KinrelColors.darkSurface, body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)));

    final round = state.currentRound;
    final isSubmitter = game.currentSubmitterId == myId;
    final myPlayer = state.players.where((p) => p.userId == myId).firstOrNull;
    final iHaveGuessed = myPlayer?.hasGuessed ?? false;
    final statements = round != null ? [round.statement1, round.statement2, round.statement3] : <String>[];

    // Timer
    final endsAt = game.roundEndsAt; int secsLeft = 0;
    if (endsAt != null) { secsLeft = endsAt.difference(DateTime.now()).inSeconds; if (secsLeft < 0) secsLeft = 0; }
    final totalSecs = game.roundTimerSeconds; final progress = (secsLeft / totalSecs).clamp(0.0, 1.0);
    final timerColor = secsLeft <= 5 ? KinrelColors.error : KinrelColors.orange;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { ref.read(ttProvider(widget.familyId).notifier).leaveGame(); Navigator.of(context).pop(); }),
        title: Text('Round ${game.currentRound}/${game.totalRounds}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: round == null ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange)) : SafeArea(child: Column(children: [
        // Submitter + timer
        Container(margin: const EdgeInsets.all(KinrelSpacing.base), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: KinrelColors.border)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Column(children: [Text(round.submitterName, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
              Text('submitted', style: TextStyle(fontSize: 10, color: KinrelColors.textDim))]),
            SizedBox(width: 48, height: 48, child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(value: progress, strokeWidth: 4, backgroundColor: KinrelColors.darkElevated, valueColor: AlwaysStoppedAnimation<Color>(timerColor)),
              Text('${secsLeft}s', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 12, fontWeight: FontWeight.w700, color: timerColor)),
            ])),
            Column(children: [Text('${state.players.where((p) => p.hasGuessed && p.userId != round.submitterId).length}/${state.players.length - 1}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 14, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
              Text('guessed', style: TextStyle(fontSize: 10, color: KinrelColors.textDim))]),
          ])),
        // Statements
        Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(isSubmitter ? 'Your statements — others are guessing...' : iHaveGuessed ? 'You guessed! Waiting for others...' : 'Which is the lie?',
            style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: isSubmitter ? KinrelColors.textDim : KinrelColors.orange)),
          const SizedBox(height: 20),
          ...statements.asMap().entries.map((entry) {
            final i = entry.key; final text = entry.value;
            final isMyGuess = state.myGuess == i + 1;
            return Padding(padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: (!isSubmitter && !iHaveGuessed) ? () { ref.read(ttProvider(widget.familyId).notifier).submitGuess(i + 1); } : null,
                child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                  width: double.infinity, padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: isMyGuess ? KinrelColors.orange : KinrelColors.darkCard, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isMyGuess ? Colors.white : KinrelColors.border, width: isMyGuess ? 2 : 1)),
                  child: Row(children: [
                    Container(width: 24, height: 24, decoration: BoxDecoration(shape: BoxShape.circle, color: isMyGuess ? Colors.white : KinrelColors.darkElevated, border: Border.all(color: isMyGuess ? Colors.white : KinrelColors.border)),
                      child: isMyGuess ? Center(child: Icon(Icons.check, size: 14, color: KinrelColors.orange)) : Center(child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KinrelColors.textDim)))),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: isMyGuess ? Colors.white : KinrelColors.textWhite))),
                  ]),
                ),
              ).animate().fadeIn(duration: 300.ms, delay: (i * 100).ms).slideY(begin: 0.1, end: 0, duration: 300.ms),
            );
          }),
        ])))),
      ])),
    );
  }
}
