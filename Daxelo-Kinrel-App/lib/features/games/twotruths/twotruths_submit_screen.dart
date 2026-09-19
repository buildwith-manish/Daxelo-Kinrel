// lib/features/games/twotruths/twotruths_submit_screen.dart
// Shown to the current round's submitter. Non-submitters see a waiting screen.
// Auto-routes to guess screen when statements are submitted.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import '../shared/widgets/game_board_shell.dart';
import 'twotruths_game_logic.dart';
import 'twotruths_models.dart';
import 'twotruths_provider.dart';

class TtSubmitScreen extends ConsumerStatefulWidget {
  const TtSubmitScreen({super.key, required this.familyId, required this.gameId}); final String familyId; final String gameId;
  @override
  ConsumerState<TtSubmitScreen> createState() => _TtSubmitScreenState();
}
class _TtSubmitScreenState extends ConsumerState<TtSubmitScreen> {
  final _c1 = TextEditingController(); final _c2 = TextEditingController(); final _c3 = TextEditingController();
  int _lieIndex = 3; bool _submitted = false;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (ref.read(ttProvider(widget.familyId)).game == null) ref.read(ttProvider(widget.familyId).notifier).joinGame(widget.gameId); }); }
  @override
  void dispose() { _c1.dispose(); _c2.dispose(); _c3.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ttProvider(widget.familyId)); final myId = ref.read(supabaseProvider)?.auth.currentUser?.id;
    final game = state.game;

    // Auto-route: if the CURRENT round's statements are in, go to guess.
    // (rounds.last may still be the previous round's row right after a
    // round advance — don't bounce the new submitter to a stale guess.)
    if (state.currentRound != null && state.currentRound!.roundNumber == game?.currentRound && mounted && !_submitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.pushReplacement('/family/${widget.familyId}/twotruths/guess/${widget.gameId}'));
    }
    // If round resolved, go to results
    if (game?.roundResolved == true && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.pushReplacement('/family/${widget.familyId}/twotruths/results/${widget.gameId}'));
    }

    if (game == null) return DKScaffold(backgroundColor: KinrelColors.darkSurface, body: const Center(child: CircularProgressIndicator(color: KinrelColors.orange)));

    final isMyTurn = game.currentSubmitterId == myId;
    final isAiMode = game.mode == TtMode.aiLie;

    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { ref.read(ttProvider(widget.familyId).notifier).leaveGame(); if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Round ${game.currentRound}/${game.totalRounds}', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: !isMyTurn ? _waitingView(state) : _submitView(game, isAiMode),
    );
  }

  Widget _submitView(game, bool isAiMode) {
    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      Text(isAiMode ? 'Write 2 true statements. AI will generate the lie!' : 'Write 3 statements. Mark which is the lie.',
        style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
      const SizedBox(height: 16),
      _statementCard(1, _c1, 'Statement 1', isAiMode ? false : _lieIndex == 1, () { GameMotionTokens.tap(); setState(() => _lieIndex = 1); }),
      const SizedBox(height: 10),
      _statementCard(2, _c2, 'Statement 2', isAiMode ? false : _lieIndex == 2, () { GameMotionTokens.tap(); setState(() => _lieIndex = 2); }),
      const SizedBox(height: 10),
      if (isAiMode)
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: KinrelColors.info.withValues(alpha: 0.3)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))]),
          child: Row(children: [Container(width: 30, height: 30, decoration: BoxDecoration(shape: BoxShape.circle, color: KinrelColors.info.withValues(alpha: 0.14), border: Border.all(color: KinrelColors.info.withValues(alpha: 0.4))), child: Center(child: Icon(Icons.smart_toy, color: KinrelColors.info, size: 16))), const SizedBox(width: 10), Expanded(child: Text('Statement 3 (the lie) will be AI-generated', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.info)))]))
      else
        _statementCard(3, _c3, 'Statement 3', _lieIndex == 3, () { GameMotionTokens.tap(); setState(() => _lieIndex = 3); }),
      const SizedBox(height: 24),
      DKButton(label: 'Submit Statements', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: state.isLoading,
        onPressed: () async {
          final s3 = isAiMode ? generateFallbackAiLie(_c1.text, _c2.text) : _c3.text;
          final success = await ref.read(ttProvider(widget.familyId).notifier).submitStatements(_c1.text, _c2.text, s3, _lieIndex);
          if (success && mounted) { setState(() => _submitted = true); GameMotionTokens.success(); }
        }),
    ]);
  }

  // Need to access state for isLoading — use a workaround
  TtState get state => ref.read(ttProvider(widget.familyId));

  /// Premium statement card — layered dark surface with a numbered chip
  /// (01/02/03 in mono) and an accent glow in the top-left corner. The
  /// card marked as the lie gets a coral wash, border and glow.
  Widget _statementCard(int number, TextEditingController controller, String label, bool isLie, VoidCallback onTap) {
    final accent = isLie ? KinrelColors.coral : KinrelColors.orange;
    return Container(
      decoration: BoxDecoration(
        color: isLie ? Color.lerp(KinrelColors.darkCard, KinrelColors.coral, 0.08) : KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isLie ? KinrelColors.coral.withValues(alpha: 0.7) : KinrelColors.border, width: isLie ? 1.5 : 1),
        boxShadow: isLie
            ? [BoxShadow(color: KinrelColors.coral.withValues(alpha: 0.20), blurRadius: 14, offset: const Offset(0, 5)), BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          // Subtle accent glow in the top-left corner.
          Positioned(top: -36, left: -36, child: Container(width: 130, height: 130, decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [accent.withValues(alpha: 0.12), accent.withValues(alpha: 0.0)])))),
          Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 36, height: 36, alignment: Alignment.center,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: accent.withValues(alpha: 0.45))),
                child: Text('0$number', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 13, fontWeight: FontWeight.w800, color: accent))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: controller, maxLines: 2, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite),
                decoration: InputDecoration(hintText: '$label...', hintStyle: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim),
                  border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 10)))),
            ]),
            if (!isLie) Padding(padding: const EdgeInsets.only(top: 4), child: GestureDetector(onTap: onTap,
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle_outlined, size: 14, color: KinrelColors.textDim), const SizedBox(width: 4),
                Text('Mark as lie', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 10, color: KinrelColors.textDim))]))),
            if (isLie) Padding(padding: const EdgeInsets.only(top: 4), child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: KinrelColors.coral.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
              child: Text('THIS IS THE LIE', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 9, fontWeight: FontWeight.w700, color: KinrelColors.coral)))),
          ])),
        ]),
      ),
    );
  }

  Widget _waitingView(TtState state) {
    final submitter = state.players.where((p) => p.userId == state.game?.currentSubmitterId).firstOrNull;
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      GameTurnPill(label: '${submitter?.userName ?? 'Player'} is writing their statements…', color: KinrelColors.orange, active: true,
        trailing: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange))),
    ]));
  }
}
