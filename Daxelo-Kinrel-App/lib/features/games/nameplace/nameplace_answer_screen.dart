// lib/features/games/nameplace/nameplace_answer_screen.dart
// Route: /family/$familyId/nameplace/answer/:gameId
//
// Shows the letter, input fields per category, countdown timer,
// and submit button. Navigates to results when round resolves.

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
import 'nameplace_provider.dart';

class NameplaceAnswerScreen extends ConsumerStatefulWidget {
  const NameplaceAnswerScreen({super.key, required this.familyId, required this.gameId});
  final String familyId;
  final String gameId;
  @override
  ConsumerState<NameplaceAnswerScreen> createState() => _NameplaceAnswerScreenState();
}

class _NameplaceAnswerScreenState extends ConsumerState<NameplaceAnswerScreen> {
  final _controllers = <String, TextEditingController>{};
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(nameplaceProvider(widget.familyId));
      if (state.game == null) ref.read(nameplaceProvider(widget.familyId).notifier).joinGame(widget.gameId);
    });
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(String category) {
    return _controllers.putIfAbsent(category, () => TextEditingController());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nameplaceProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final game = state.game;

    // Auto-navigate to results when round is scored
    if (game != null && game.roundScoringDone && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.pushReplacement('/family/${widget.familyId}/nameplace/results/${widget.gameId}');
      });
    }

    if (game == null) {
      return DKScaffold(backgroundColor: KinrelColors.darkSurface, body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)));
    }

    final letter = game.currentLetter ?? '?';
    final roundEndsAt = game.roundEndsAt;
    int secondsRemaining = 0;
    if (roundEndsAt != null) {
      secondsRemaining = roundEndsAt.difference(DateTime.now()).inSeconds;
      if (secondsRemaining < 0) secondsRemaining = 0;
    }
    final totalSeconds = game.roundTimerSeconds;
    final progress = (secondsRemaining / totalSeconds).clamp(0.0, 1.0);
    final timerColor = secondsRemaining <= 10 ? KinrelColors.error : KinrelColors.orange;

    // Check if I've submitted
    final myPlayer = state.players.where((p) => p.userId == myId).firstOrNull;
    final iHaveSubmitted = myPlayer?.hasSubmitted ?? false;

    // Check all categories filled
    final allFilled = game.categories.every((cat) {
      final text = _controllerFor(cat).text.trim();
      return text.isNotEmpty;
    });

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { ref.read(nameplaceProvider(widget.familyId).notifier).leaveGame(); if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Round ${game.currentRound}/${game.totalRounds}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: iHaveSubmitted
        ? _submittedView(state)
        : ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
          // Letter + timer
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Column(children: [
              Text('LETTER', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.5)),
              const SizedBox(height: 4),
              Container(width: 72, height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const RadialGradient(center: Alignment(-0.4, -0.4), radius: 1.25, colors: [Color(0xFFFFFDF6), Color(0xFFE7E0D4)]),
                  border: Border.all(color: const Color(0xFFD9D3C7)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Center(child: Text(letter, style: const TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 38, fontWeight: FontWeight.w800, color: Color(0xFF2A2118)))),
              )
                .animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.5, 0.5), end: const Offset(1.0, 1.0), duration: 400.ms, curve: Curves.elasticOut),
            ]),
            SizedBox(width: 56, height: 56, child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(value: progress, strokeWidth: 4, backgroundColor: KinrelColors.darkElevated, valueColor: AlwaysStoppedAnimation<Color>(timerColor)),
              Text('${secondsRemaining}s', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 14, fontWeight: FontWeight.w700, color: timerColor)),
            ])),
            Column(children: [
              Text('SUBMITTED', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.5)),
              const SizedBox(height: 4),
              Text('${state.players.where((p) => p.hasSubmitted).length}/${state.players.length}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 20, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
            ]),
          ]),
          const SizedBox(height: KinrelSpacing.xl),
          // Category inputs
          ...game.categories.map((cat) {
            final (catAccent, catIcon) = _categoryStyle(cat);
            return Padding(
            padding: const EdgeInsets.only(bottom: KinrelSpacing.md),
            child: Row(children: [
              SizedBox(width: 86, child: Row(children: [
                Container(width: 28, height: 28, decoration: BoxDecoration(shape: BoxShape.circle, color: catAccent.withValues(alpha: 0.14), border: Border.all(color: catAccent.withValues(alpha: 0.45))),
                  child: Center(child: Icon(catIcon, size: 15, color: catAccent))),
                const SizedBox(width: 6),
                Expanded(child: Text(cat, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w700, color: catAccent))),
              ])),
              const SizedBox(width: KinrelSpacing.sm),
              Expanded(child: TextField(
                controller: _controllerFor(cat),
                style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 15, color: KinrelColors.textWhite),
                decoration: InputDecoration(
                  hintText: '$cat starting with $letter...',
                  hintStyle: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim),
                  filled: true, fillColor: KinrelColors.darkCard,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: KinrelColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: catAccent, width: 2)),
                ),
                onChanged: (v) => ref.read(nameplaceProvider(widget.familyId).notifier).updateAnswer(cat, v),
              )),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () { _controllerFor(cat).text = '-'; ref.read(nameplaceProvider(widget.familyId).notifier).updateAnswer(cat, '-'); GameMotionTokens.tap(); },
                child: Container(width: 36, height: 36, decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: KinrelColors.border)),
                  child: Center(child: Text('-', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.textDim))),
                ),
              ),
            ]),
          );
          }),
          const SizedBox(height: KinrelSpacing.xl),
          DKButton(
            label: allFilled ? 'Submit Answers' : 'Fill all categories (or dash)',
            variant: allFilled ? DKButtonVariant.gradient : DKButtonVariant.secondary,
            fullWidth: true, isLoading: state.isSubmitting,
            onPressed: allFilled ? () => ref.read(nameplaceProvider(widget.familyId).notifier).submitAnswers() : null,
          ),
        ]),
    );
  }

  Widget _submittedView(state) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.check_circle, size: 48, color: KinrelColors.success),
      const SizedBox(height: KinrelSpacing.md),
      Text('Answers submitted!', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
      const SizedBox(height: 4),
      Text('Waiting for others...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
      const SizedBox(height: KinrelSpacing.lg),
      ...state.players.map((p) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(p.hasSubmitted ? Icons.check_circle : Icons.hourglass_empty, size: 14, color: p.hasSubmitted ? KinrelColors.success : KinrelColors.textDim),
          const SizedBox(width: 4),
          Text(p.userName, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: p.hasSubmitted ? KinrelColors.textWhite : KinrelColors.textDim)),
        ]),
      )),
    ]));
  }

  /// Per-category accent tint + icon for the answer rows.
  (Color, IconData) _categoryStyle(String category) {
    switch (category.toLowerCase()) {
      case 'name': return (KinrelColors.info, Icons.person_rounded);
      case 'place': return (KinrelColors.tealAccent, Icons.place_rounded);
      case 'animal': return (KinrelColors.success, Icons.pets_rounded);
      case 'thing': return (KinrelColors.amber, Icons.edit_rounded);
      default: return (KinrelColors.orange, Icons.style_rounded);
    }
  }
}
