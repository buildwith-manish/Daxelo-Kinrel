// lib/features/games/truthordare/truthordare_review_screen.dart
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
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
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
        else ...state.pendingPrompts.map((p) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.flaggedByFilter ? KinrelColors.warning : KinrelColors.border, width: p.flaggedByFilter ? 2 : 1)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(p.category == 'truth' ? Icons.lightbulb_outline : Icons.local_fire_department_outlined, size: 16, color: p.category == 'truth' ? KinrelColors.info : KinrelColors.error),
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: (p.category == 'truth' ? KinrelColors.info : KinrelColors.error).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                child: Text(p.category.toUpperCase(), style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 9, fontWeight: FontWeight.w700, color: p.category == 'truth' ? KinrelColors.info : KinrelColors.error))),
              const SizedBox(width: 6),
              Text('by ${p.submittedByName}', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 10, color: KinrelColors.textDim)),
              const Spacer(),
              if (p.flaggedByFilter) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: KinrelColors.warning.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                child: Text('FLAGGED', style: TextStyle(fontFamily: KinrelTypography.monoFont, fontSize: 9, fontWeight: FontWeight.w700, color: KinrelColors.warning))),
            ]),
            const SizedBox(height: 8),
            Text(p.promptText, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: DKButton(label: 'Approve', variant: DKButtonVariant.primary, icon: Icons.check, onPressed: () => ref.read(todProvider(widget.familyId).notifier).reviewPrompt(p.id, true))),
              const SizedBox(width: 8),
              Expanded(child: DKButton(label: 'Reject', variant: DKButtonVariant.secondary, onPressed: () => ref.read(todProvider(widget.familyId).notifier).reviewPrompt(p.id, false))),
            ]),
          ]))),
      ]),
    );
  }
}
