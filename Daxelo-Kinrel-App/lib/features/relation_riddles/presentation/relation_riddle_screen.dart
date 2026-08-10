import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/relation_riddle_provider.dart';
import 'package:go_router/go_router.dart';

class RelationRiddleScreen extends ConsumerStatefulWidget {
  const RelationRiddleScreen({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<RelationRiddleScreen> createState() => _RelationRiddleScreenState();
}

class _RelationRiddleScreenState extends ConsumerState<RelationRiddleScreen> {
  @override
  void initState() { super.initState(); Future.microtask(() => ref.read(relationRiddleProvider(widget.familyId).notifier).load()); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(relationRiddleProvider(widget.familyId));
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { if (context.canPop()) { context.pop(); } else { context.go('/family/${widget.familyId}'); } }),
        title: Text('Relation Riddle', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0),
      body: state.isLoading ? Center(child: CircularProgressIndicator(color: const Color(0xFF10B981)))
        : state.error != null ? DKErrorState(message: state.error!, onRetry: () => ref.read(relationRiddleProvider(widget.familyId).notifier).load())
        : _buildContent(state),
    );
  }

  Widget _buildContent(state) {
    if (state.riddleId == null) return Center(child: Text('Need at least 2 family members to play', style: TextStyle(color: KinrelColors.textDim), textAlign: TextAlign.center));
    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF10B981).withValues(alpha: 0.15), KinrelColors.darkCard]),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.extension_outlined, color: Color(0xFF10B981), size: 20), SizedBox(width: 8),
            Text('Today\'s Riddle', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF10B981)))]),
          SizedBox(height: 12),
          Text('How is ${state.personAName} related to ${state.personBName}?',
            style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w600, color: KinrelColors.textWhite, height: 1.4)),
        ]),
      ),
      SizedBox(height: 20),
      ...state.options.map((opt) => _buildOptionTile(state, opt)),
      if (state.hasAnswered) ...[
        SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Icon(state.wasCorrect == true ? Icons.celebration_rounded : Icons.info_outline_rounded, size: 40,
              color: state.wasCorrect == true ? KinrelColors.success : KinrelColors.orange),
            SizedBox(height: 8),
            Text(state.wasCorrect == true ? 'Correct!' : 'Better luck next time!',
              style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 18, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
            SizedBox(height: 4),
            Text('Answer: ${state.options.firstWhere((o) => o.isCorrect).text}',
              style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)),
          ]),
        ),
      ],
    ]);
  }

  Widget _buildOptionTile(state, RiddleOption opt) {
    final isSelected = state.myAnswer == opt.text;
    final showResult = state.hasAnswered;
    Color? bgColor; Color? borderColor; IconData? trailingIcon;

    if (showResult) {
      if (opt.isCorrect) { bgColor = KinrelColors.success.withValues(alpha: 0.15); borderColor = KinrelColors.success; trailingIcon = Icons.check_circle_rounded; }
      else if (isSelected) { bgColor = KinrelColors.error.withValues(alpha: 0.15); borderColor = KinrelColors.error; trailingIcon = Icons.cancel_rounded; }
    } else if (isSelected) { bgColor = const Color(0xFF10B981).withValues(alpha: 0.15); borderColor = const Color(0xFF10B981); }

    return Container(margin: const EdgeInsets.only(bottom: 10),
      child: Material(color: Colors.transparent, child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: state.hasAnswered || state.isSubmitting ? null : () async {
          await ref.read(relationRiddleProvider(widget.familyId).notifier).submitAnswer(opt.text, opt.isCorrect);
        },
        child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
          color: bgColor ?? KinrelColors.darkCard, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.06))),
          child: Row(children: [
            Expanded(child: Text(opt.text, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 15, color: KinrelColors.textWhite, fontWeight: FontWeight.w500))),
            if (trailingIcon != null) Icon(trailingIcon, color: borderColor, size: 22),
          ]),
        ),
      )),
    );
  }
}
