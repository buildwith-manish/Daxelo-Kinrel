import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/constants/brand_spacing.dart';
import '../../../shared/widgets/dk_components.dart';
import '../providers/hot_seat_provider.dart';

class HotSeatScreen extends ConsumerStatefulWidget {
  const HotSeatScreen({super.key, required this.familyId});
  final String familyId;
  @override
  ConsumerState<HotSeatScreen> createState() => _HotSeatScreenState();
}

class _HotSeatScreenState extends ConsumerState<HotSeatScreen> {
  final _questionController = TextEditingController();
  final _answerControllers = <String, TextEditingController>{};

  @override
  void initState() { super.initState(); Future.microtask(() => ref.read(hotSeatProvider(widget.familyId).notifier).load()); }
  @override
  void dispose() { _questionController.dispose(); for (final c in _answerControllers.values) c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hotSeatProvider(widget.familyId));
    return DKScaffold(
      backgroundColor: KinrelColors.darkSurface,
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
        title: Text('Hot Seat', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontWeight: FontWeight.w600)),
        backgroundColor: KinrelColors.darkCard, foregroundColor: KinrelColors.textWhite, elevation: 0),
      body: state.isLoading ? Center(child: CircularProgressIndicator(color: const Color(0xFF06B6D4)))
        : state.error != null ? DKErrorState(message: state.error!, onRetry: () => ref.read(hotSeatProvider(widget.familyId).notifier).load())
        : _buildContent(state),
    );
  }

  Widget _buildContent(state) {
    if (state.dailyId == null) return Center(child: Text('No Hot Seat today', style: TextStyle(color: KinrelColors.textDim)));
    final isMe = state.isMeInHotSeat;
    return ListView(padding: const EdgeInsets.all(KinrelSpacing.base), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [const Color(0xFF06B6D4).withValues(alpha: 0.15), KinrelColors.darkCard]),
        border: Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.whatshot_rounded, color: Color(0xFF06B6D4), size: 20), SizedBox(width: 8),
            Text('Today\'s Hot Seat', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF06B6D4)))]),
          SizedBox(height: 12),
          Text(state.seatHolderName ?? 'Unknown', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 22, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
          SizedBox(height: 4),
          Text(isMe ? 'Answer questions from your family' : 'Ask a question — they\'ll answer!',
            style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textDim)),
        ]),
      ),
      SizedBox(height: 20),
      if (!isMe) ...[
        TextField(controller: _questionController, maxLines: 2, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite),
          decoration: InputDecoration(hintText: 'Ask a question...', hintStyle: TextStyle(color: KinrelColors.textDim, fontSize: 14),
            filled: true, fillColor: KinrelColors.darkElevated, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none), contentPadding: const EdgeInsets.all(12))),
        SizedBox(height: 8),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: state.isSubmitting ? null : () async {
          final t = _questionController.text.trim(); if (t.isEmpty) return;
          await ref.read(hotSeatProvider(widget.familyId).notifier).submitQuestion(t); _questionController.clear();
        }, style: FilledButton.styleFrom(backgroundColor: const Color(0xFF06B6D4), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          child: state.isSubmitting ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Submit Question'))),
        SizedBox(height: 20),
      ],
      Text('Questions (${state.questions.length})', style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 16, fontWeight: FontWeight.w700, color: KinrelColors.textWhite)),
      SizedBox(height: 12),
      ...state.questions.map((q) => _buildQuestionTile(q, isMe)),
    ]);
  }

  Widget _buildQuestionTile(HotSeatQuestion q, bool isMe) {
    if (!_answerControllers.containsKey(q.id)) _answerControllers[q.id] = TextEditingController();
    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: KinrelColors.darkCard, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [CircleAvatar(radius: 16, backgroundColor: const Color(0xFF06B6D4).withValues(alpha: 0.15),
          child: Text(q.askerName.isNotEmpty ? q.askerName[0].toUpperCase() : '?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF06B6D4)))),
          SizedBox(width: 10), Text(q.askerName, style: TextStyle(fontFamily: KinrelTypography.displayFont, fontSize: 13, fontWeight: FontWeight.w600, color: KinrelColors.textWhite))]),
        SizedBox(height: 8),
        Text(q.question, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 15, color: KinrelColors.textWhite, height: 1.4)),
        SizedBox(height: 8),
        if (q.answer != null) ...[
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: KinrelColors.darkElevated, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [Icon(Icons.format_quote_rounded, size: 16, color: KinrelColors.textDim), SizedBox(width: 6),
              Expanded(child: Text(q.answer!, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textSilver, fontStyle: FontStyle.italic)))])),
        ] else if (isMe) ...[
          TextField(controller: _answerControllers[q.id]!, maxLines: 1, style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 14, color: KinrelColors.textWhite),
            decoration: InputDecoration(hintText: 'Your answer...', hintStyle: TextStyle(color: KinrelColors.textDim, fontSize: 13),
              filled: true, fillColor: KinrelColors.darkElevated, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: const EdgeInsets.all(10),
              suffixIcon: IconButton(icon: Icon(Icons.send, color: const Color(0xFF06B6D4), size: 16),
                onPressed: () async { final a = _answerControllers[q.id]!.text.trim(); if (a.isEmpty) return; await ref.read(hotSeatProvider(widget.familyId).notifier).submitAnswer(q.id, a); }))),
        ] else
          Text('Waiting for answer...', style: TextStyle(fontFamily: KinrelTypography.bodyFont, fontSize: 12, color: KinrelColors.textDim, fontStyle: FontStyle.italic)),
      ]),
    );
  }
}
