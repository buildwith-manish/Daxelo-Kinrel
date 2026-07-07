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
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
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
          _catChip('truth', 'Truth', KinrelColors.info, Icons.lightbulb_outline),
          const SizedBox(width: 8),
          _catChip('dare', 'Dare', KinrelColors.error, Icons.local_fire_department_outlined),
        ]),
        const SizedBox(height: KinrelSpacing.lg),
        // Text input
        TextField(controller: _controller, maxLines: 3, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 15, color: KinrelColors.textWhite),
          decoration: InputDecoration(hintText: _category == 'truth' ? 'e.g., What is your favorite childhood memory?' : 'e.g., Sing the chorus of your favorite song',
            hintStyle: TextStyle(fontSize: 13, color: KinrelColors.textDim), filled: true, fillColor: KinrelColors.darkCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: KinrelColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: KinrelColors.orange, width: 2))),
        ),
        const SizedBox(height: KinrelSpacing.md),
        DKButton(label: 'Submit for Review', variant: DKButtonVariant.gradient, fullWidth: true, isLoading: state.isSubmitting, onPressed: _submit),
        const SizedBox(height: KinrelSpacing.xl),
        // My submission history
        Text('MY SUBMISSIONS', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 11, fontWeight: FontWeight.w700, color: KinrelColors.textDim, letterSpacing: 1.5)),
        const SizedBox(height: 8),
        if (state.myPrompts.isEmpty) Text('No submissions yet.', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim))
        else ...state.myPrompts.map((p) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: KinrelColors.border)),
          child: Row(children: [
            Icon(p.category == 'truth' ? Icons.lightbulb_outline : Icons.local_fire_department_outlined, size: 16, color: p.category == 'truth' ? KinrelColors.info : KinrelColors.error),
            const SizedBox(width: 8),
            Expanded(child: Text(p.promptText, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textWhite))),
            _statusBadge(p.status),
          ]))),
      ]),
    );
  }

  Widget _catChip(String value, String label, Color color, IconData icon) {
    final sel = _category == value;
    return GestureDetector(onTap: () { GameMotionTokens.tap(); setState(() => _category = value); },
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: sel ? color.withValues(alpha: 0.2) : KinrelColors.darkCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: sel ? color : KinrelColors.border, width: sel ? 2 : 1)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: sel ? color : KinrelColors.textDim), const SizedBox(width: 6), Text(label, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: sel ? color : KinrelColors.textDim))])));
  }

  Widget _statusBadge(TodPromptStatus status) {
    final (color, text) = switch (status) { TodPromptStatus.pending => (KinrelColors.warning, 'Pending'), TodPromptStatus.approved => (KinrelColors.success, 'Approved'), TodPromptStatus.rejected => (KinrelColors.error, 'Rejected') };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 9, fontWeight: FontWeight.w700, color: color)));
  }
}
