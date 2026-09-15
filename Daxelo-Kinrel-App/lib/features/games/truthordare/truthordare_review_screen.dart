// lib/features/games/truthordare/truthordare_review_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../shared/widgets/dk_components.dart';
import 'truthordare_models.dart';
import 'truthordare_provider.dart';

class TodReviewScreen extends ConsumerStatefulWidget {
  const TodReviewScreen({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<TodReviewScreen> createState() => _TodReviewScreenState();
}

class _TodReviewScreenState extends ConsumerState<TodReviewScreen> {
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(todProvider(widget.familyId).notifier).loadPendingPrompts()); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todProvider(widget.familyId));
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Review Prompts', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0,
      ),
      body: ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
        Text('Pending submissions awaiting your approval.', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 13, color: KinrelColors.textDim)),
        const SizedBox(height: KinrelSpacing.lg),
        if (state.pendingPrompts.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(children: [
            Icon(Icons.check_circle, size: 48, color: KinrelColors.success),
            const SizedBox(height: 12),
            Text('All caught up!', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
            Text('No pending prompts to review.', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim)),
          ])))
        else ...state.pendingPrompts.map((p) => _pendingPromptCard(p))
      ]),
    );
  }

  /// Premium review card — layered dark surface with an accent glow in
  /// the top-left corner, tinted border + icon chip (teal = Truth,
  /// coral = Dare). Flagged prompts keep their warning border.
  Widget _pendingPromptCard(TodPrompt p) {
    final isTruth = p.category == 'truth';
    final accent = isTruth ? KinrelColors.tealAccent : KinrelColors.coral;
    final borderColor = p.flaggedByFilter ? KinrelColors.warning.withValues(alpha: 0.7) : accent.withValues(alpha: 0.25);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: KinrelColors.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: p.flaggedByFilter ? 1.5 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.32), blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          // Subtle accent glow in the top-left corner.
          Positioned(top: -40, left: -40, child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [accent.withValues(alpha: 0.13), accent.withValues(alpha: 0.0)])))),
          Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 30, height: 30, decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.14), border: Border.all(color: accent.withValues(alpha: 0.4))),
                child: Center(child: Icon(isTruth ? Icons.help_outline : Icons.local_fire_department, size: 15, color: accent))),
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(4)),
                child: Text(p.category.toUpperCase(), style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 9, fontWeight: FontWeight.w700, color: accent))),
              const SizedBox(width: 6),
              Text('by ${p.submittedByName}', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 10, color: KinrelColors.textDim)),
              const Spacer(),
              if (p.flaggedByFilter) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: KinrelColors.warning.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                child: Text('FLAGGED', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 9, fontWeight: FontWeight.w700, color: KinrelColors.warning))),
            ]),
            const SizedBox(height: 10),
            Text(p.promptText, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: DKButton(label: 'Approve', variant: DKButtonVariant.primary, icon: Icons.check, onPressed: () => ref.read(todProvider(widget.familyId).notifier).reviewPrompt(p.id, true))),
              const SizedBox(width: 8),
              Expanded(child: DKButton(label: 'Reject', variant: DKButtonVariant.secondary, onPressed: () => ref.read(todProvider(widget.familyId).notifier).reviewPrompt(p.id, false))),
            ]),
          ])),
        ]),
      ),
    );
  }
}
