import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../providers/relation_riddle_provider.dart';

class RelationRiddleCard extends ConsumerStatefulWidget {
  const RelationRiddleCard({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<RelationRiddleCard> createState() => _RelationRiddleCardState();
}

class _RelationRiddleCardState extends ConsumerState<RelationRiddleCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(relationRiddleProvider(widget.familyId).notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(relationRiddleProvider(widget.familyId));
    if (state.isLoading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
        height: 100,
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: const Color(0xFF10B981),
            ),
          ),
        ),
      );
    }
    if (state.error != null || state.riddleId == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF10B981).withValues(alpha: 0.15),
            const Color(0xFF191B2C),
          ],
        ),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/family/${widget.familyId}/relation-riddles'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                      ),
                      child: const Icon(Icons.extension_outlined, color: Color(0xFF10B981), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Relation Riddle',
                        style: TextStyle(
                          fontFamily: KinrelTypography.displayFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: KinrelColors.textWhite,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'How is ${state.personAName} related to ${state.personBName}?',
                  style: TextStyle(
                    fontFamily: KinrelTypography.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: KinrelColors.textWhite,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                if (state.hasAnswered)
                  Row(
                    children: [
                      Icon(
                        state.wasCorrect == true ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        color: state.wasCorrect == true ? KinrelColors.success : KinrelColors.error,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        state.wasCorrect == true ? 'Correct! Tap to see details' : 'Not quite — tap to see answer',
                        style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim),
                      ),
                    ],
                  )
                else
                  Text(
                    '4 options · tap to play',
                    style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
