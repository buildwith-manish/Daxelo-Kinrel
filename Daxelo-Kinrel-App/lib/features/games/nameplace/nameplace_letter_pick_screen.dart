// lib/features/games/nameplace/nameplace_letter_pick_screen.dart
// Route: /family/$familyId/nameplace/letter/:gameId
//
// Shown to the letter chooser to pick a letter for the round.
// Non-choosers see a "waiting" screen.

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
import 'nameplace_game_logic.dart';
import 'nameplace_provider.dart';

class NameplaceLetterPickScreen extends ConsumerStatefulWidget {
  const NameplaceLetterPickScreen({super.key, required this.familyId, required this.gameId});
  final String familyId;
  final String gameId;
  @override
  ConsumerState<NameplaceLetterPickScreen> createState() => _NameplaceLetterPickScreenState();
}

class _NameplaceLetterPickScreenState extends ConsumerState<NameplaceLetterPickScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(nameplaceProvider(widget.familyId));
      if (state.game == null) ref.read(nameplaceProvider(widget.familyId).notifier).joinGame(widget.gameId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nameplaceProvider(widget.familyId));
    final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final game = state.game;

    // Auto-navigate to answer screen once letter is picked
    if (game != null && game.currentLetter != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.pushReplacement('/family/${widget.familyId}/nameplace/answer/${widget.gameId}');
      });
    }

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { ref.read(nameplaceProvider(widget.familyId).notifier).leaveGame(); if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Round ${game?.currentRound ?? 1}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: state.isLoading && game == null
        ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
        : game == null
          ? const Center(child: CircularProgressIndicator(color: KinrelColors.orange))
          : game.currentLetterChooserId == myId
            ? _letterPickerView(state)
            : _waitingView(state),
    );
  }

  Widget _letterPickerView(state) {
    final game = state.game!;
    final chooser = state.players.where((p) => p.userId == game.currentLetterChooserId).firstOrNull;
    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      Text('You\'re picking the letter!', textAlign: TextAlign.center,
        style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
      const SizedBox(height: 4),
      Text('Pick a letter for Round ${game.currentRound} of ${game.totalRounds}', textAlign: TextAlign.center,
        style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
      const SizedBox(height: KinrelSpacing.xl),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1),
        itemCount: validLetters.length,
        itemBuilder: (context, index) {
          final letter = validLetters[index];
          return GestureDetector(
            onTap: () { GameMotionTokens.tap(); ref.read(nameplaceProvider(widget.familyId).notifier).pickLetter(letter); },
            child: Container(
              decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: KinrelColors.orange.withValues(alpha: 0.3), width: 1)),
              child: Center(child: Text(letter, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 20, fontWeight: FontWeight.w800, color: KinrelColors.orange))),
            ),
          );
        },
      ),
    ]);
  }

  Widget _waitingView(state) {
    final game = state.game!;
    final chooser = state.players.where((p) => p.userId == game.currentLetterChooserId).firstOrNull;
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange)),
      const SizedBox(height: KinrelSpacing.md),
      Text('${chooser?.userName ?? 'Player'} is picking a letter...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)),
    ]));
  }
}
