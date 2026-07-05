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

    // Auto-route: if round exists with statements, go to guess
    if (state.currentRound != null && mounted && !_submitted) {
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
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () { ref.read(ttProvider(widget.familyId).notifier).leaveGame(); Navigator.of(context).pop(); }),
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
      _statementField(_c1, 'Statement 1', isAiMode ? false : _lieIndex == 1, () { GameMotionTokens.tap(); setState(() => _lieIndex = 1); }),
      const SizedBox(height: 10),
      _statementField(_c2, 'Statement 2', isAiMode ? false : _lieIndex == 2, () { GameMotionTokens.tap(); setState(() => _lieIndex = 2); }),
      const SizedBox(height: 10),
      if (isAiMode)
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: KinrelColors.info)),
          child: Row(children: [Icon(Icons.smart_toy, color: KinrelColors.info, size: 20), const SizedBox(width: 8), Expanded(child: Text('Statement 3 (the lie) will be AI-generated', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.info)))]))
      else
        _statementField(_c3, 'Statement 3', _lieIndex == 3, () { GameMotionTokens.tap(); setState(() => _lieIndex = 3); }),
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

  Widget _statementField(TextEditingController controller, String label, bool isLie, VoidCallback onTap) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: controller, maxLines: 2, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite),
        decoration: InputDecoration(hintText: '$label...', hintStyle: TextStyle(fontSize: 12, color: KinrelColors.textDim), filled: true, fillColor: KinrelColors.darkCard,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isLie ? KinrelColors.error : KinrelColors.border, width: isLie ? 2 : 1)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: KinrelColors.orange, width: 2))),
      ),
      if (!isLie) Padding(padding: const EdgeInsets.only(top: 4), child: GestureDetector(onTap: onTap,
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(isLie ? Icons.check_circle : Icons.circle_outlined, size: 14, color: isLie ? KinrelColors.error : KinrelColors.textDim), const SizedBox(width: 4),
          Text('Mark as lie', style: TextStyle(fontSize: 10, color: KinrelColors.textDim))]))),
      if (isLie) Padding(padding: const EdgeInsets.only(top: 4), child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: KinrelColors.error.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
        child: Text('THIS IS THE LIE', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 9, fontWeight: FontWeight.w700, color: KinrelColors.error)))),
    ]);
  }

  Widget _waitingView(TtState state) {
    final submitter = state.players.where((p) => p.userId == state.game?.currentSubmitterId).firstOrNull;
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: KinrelColors.orange)),
      const SizedBox(height: 12),
      Text('${submitter?.userName ?? 'Player'} is writing their statements...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
    ]));
  }
}
