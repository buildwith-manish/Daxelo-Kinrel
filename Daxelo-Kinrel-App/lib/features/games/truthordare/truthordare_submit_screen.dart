// lib/features/games/truthordare/truthordare_submit_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import '../game_motion_tokens.dart';
import 'truthordare_models.dart';
import 'truthordare_provider.dart';

class TodSubmitScreen extends ConsumerStatefulWidget {
  const TodSubmitScreen({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<TodSubmitScreen> createState() => _TodSubmitScreenState();
}

class _TodSubmitScreenState extends ConsumerState<TodSubmitScreen> {
  final _controller = TextEditingController();
  String _category = 'truth';

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(todProvider(widget.familyId).notifier).loadMyPrompts()); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final success = await ref.read(todProvider(widget.familyId).notifier).submitPrompt(text, _category);
    if (success && mounted) { _controller.clear(); GameMotionTokens.success(); }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todProvider(widget.familyId));
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Submit Prompt', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
        Text('Submit a new prompt for your family\'s Truth or Dare pool.', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
        const SizedBox(height: 4),
        Text('All submissions are reviewed by your family\'s admin before they\'re playable.', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 11, color: KinrelColors.warning)),
        const SizedBox(height: KinrelSpacing.lg),
        // Category selector
        Text('CATEGORY', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        Row(children: [
          _catChip('truth', 'Truth', KinrelColors.tealAccent, Icons.help_outline),
          const SizedBox(width: 8),
          _catChip('dare', 'Dare', KinrelColors.coral, Icons.local_fire_department),
        ]),
        const SizedBox(height: KinrelSpacing.lg),
        // Text input
        TextField(controller: _controller, maxLines: 3, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 15, color: KinrelColors.textWhite),
          decoration: InputDecoration(hintText: _category == 'truth' ? 'e.g., What is your favorite childhood memory?' : 'e.g., Sing the chorus of your favorite song',
            hintStyle: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim), filled: true, fillColor: KinrelColors.darkCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: KinrelColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _category == 'truth' ? KinrelColors.tealAccent : KinrelColors.coral, width: 2))),
        ),
        const SizedBox(height: KinrelSpacing.md),
        DKButton(label: 'Submit for Review', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: state.isSubmitting, onPressed: _submit),
        const SizedBox(height: KinrelSpacing.xl),
        // My submission history
        Text('MY SUBMISSIONS', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        if (state.myPrompts.isEmpty) Text('No submissions yet.', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim))
        else ...state.myPrompts.map((p) => _myPromptCard(p)),
      ]),
    );
  }

  Widget _catChip(String value, String label, Color color, IconData icon) {
    final sel = _category == value;
    return GestureDetector(onTap: () { GameMotionTokens.tap(); setState(() => _category = value); },
      child: AnimatedContainer(duration: GameMotionTokens.fast, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: sel ? color.withValues(alpha: 0.14) : KinrelColors.darkCard, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? color.withValues(alpha: 0.75) : KinrelColors.border, width: sel ? 1.5 : 1),
          boxShadow: sel ? [BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: 12, offset: const Offset(0, 4))] : null),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: sel ? 0.20 : 0.10), border: Border.all(color: color.withValues(alpha: sel ? 0.65 : 0.25))),
            child: Center(child: Icon(icon, size: 14, color: sel ? color : KinrelColors.textDim))),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: sel ? color : KinrelColors.textDim))])));
  }

  /// Premium submission card — layered dark surface with an accent glow
  /// in the top-left corner, icon chip (teal = Truth, coral = Dare) and
  /// a satisfying "done" state for approved prompts (success wash at
  /// low alpha + gentle dimming).
  Widget _myPromptCard(TodPrompt p) {
    final isTruth = p.category == 'truth';
    final accent = isTruth ? KinrelColors.tealAccent : KinrelColors.coral;
    final isDone = p.status == TodPromptStatus.approved;
    final cardAccent = isDone ? KinrelColors.success : accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardAccent.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          // Subtle accent glow in the top-left corner.
          Positioned(top: -34, left: -34, child: Container(width: 130, height: 130, decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [cardAccent.withValues(alpha: 0.13), cardAccent.withValues(alpha: 0.0)])))),
          // Done state — low-alpha success wash + check watermark.
          if (isDone) ...[
            Positioned.fill(child: IgnorePointer(child: Container(color: KinrelColors.success.withValues(alpha: 0.05)))),
            Positioned(right: 6, bottom: -8, child: IgnorePointer(child: Icon(Icons.check_circle, size: 54, color: KinrelColors.success.withValues(alpha: 0.14)))),
          ],
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Opacity(opacity: isDone ? 0.72 : 1, child: Row(children: [
              Container(width: 30, height: 30, decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.14), border: Border.all(color: accent.withValues(alpha: 0.4))),
                child: Center(child: Icon(isTruth ? Icons.help_outline : Icons.local_fire_department, size: 15, color: accent))),
              const SizedBox(width: 10),
              Expanded(child: Text(p.promptText, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textWhite))),
              const SizedBox(width: 8),
              _statusBadge(p.status),
            ]))),
        ]),
      ),
    );
  }

  Widget _statusBadge(TodPromptStatus status) {
    final (color, text) = switch (status) { TodPromptStatus.pending => (KinrelColors.warning, 'Pending'), TodPromptStatus.approved => (KinrelColors.success, 'Approved'), TodPromptStatus.rejected => (KinrelColors.error, 'Rejected') };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 9, fontWeight: FontWeight.w700, color: color)));
  }
}
