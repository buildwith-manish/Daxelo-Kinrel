import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../providers/hot_seat_provider.dart';

class HotSeatCard extends ConsumerStatefulWidget {
  const HotSeatCard({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<HotSeatCard> createState() => _HotSeatCardState();
}

class _HotSeatCardState extends ConsumerState<HotSeatCard> {
  final _questionController = TextEditingController();
  final _answerControllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(hotSeatProvider(widget.familyId).notifier).load());
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _answerControllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hotSeatProvider(widget.familyId));
    if (state.isLoading) return _buildLoading();
    if (state.error != null || state.dailyId == null) return const SizedBox.shrink();

    final isMe = state.isMeInHotSeat;
    final unansweredCount = state.questions.where((q) => q.answer == null).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [const Color(0xFF06B6D4).withValues(alpha: 0.15), const Color(0xFF191B2C)]),
        border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.3)),
      ),
      child: Material(color: Colors.transparent, child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/family/${widget.familyId}/hot-seat'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF06B6D4).withValues(alpha: 0.2)),
                child: const Icon(Icons.whatshot_rounded, color: Color(0xFF06B6D4), size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Text('Hot Seat', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite))),
              if (state.questions.isNotEmpty)
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFF06B6D4), borderRadius: BorderRadius.circular(10)),
                  child: Text('${state.questions.length} Q', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 10),
            Text(isMe ? 'You\'re in the Hot Seat today!' : '${state.seatHolderName} is in the Hot Seat',
              style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, fontWeight: FontWeight.w600, color: KinrelColors.textWhite)),
            const SizedBox(height: 8),
            if (isMe && unansweredCount > 0)
              Text('$unansweredCount unanswered question${unansweredCount == 1 ? "" : "s"} — tap to answer',
                style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim))
            else if (!isMe)
              TextField(controller: _questionController, maxLines: 1,
                style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite),
                decoration: InputDecoration(hintText: 'Ask a question...', hintStyle: TextStyle(color: KinrelColors.textDim, fontSize: 14),
                  filled: true, fillColor: KinrelColors.darkElevated, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(10),
                  suffixIcon: IconButton(icon: Icon(Icons.send, color: const Color(0xFF06B6D4), size: 18),
                    onPressed: () async { final t = _questionController.text.trim(); if (t.isEmpty) return; await ref.read(hotSeatProvider(widget.familyId).notifier).submitQuestion(t); _questionController.clear(); })),
            if (!isMe && state.isSubmitting)
              const Padding(padding: EdgeInsets.only(top: 8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06B6D4)))),
          ]),
        ),
      )),
    );
  }

  Widget _buildLoading() => Container(
    margin: const EdgeInsets.symmetric(horizontal: KinrelSpacing.base), height: 100,
    decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(16)),
    child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF06B6D4)))),
  );
}
