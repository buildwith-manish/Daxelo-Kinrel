// lib/features/prediction_battle_v1/pb_v1_submit_question_sheet.dart
//
// Bottom sheet that lets a family member submit a new question for
// the Prediction Battle. Reachable via the "Suggest a question"
// button on the history screen.
//
// The submission lands in pb_v1_user_questions with status='pending'.
// An admin reviews it (via /admin endpoints) before it goes live in
// the rotation. The submitter gets 5 coins when their question is
// approved + used in a round.
//
// Form fields:
//   - Question text (required, 10–200 chars)
//   - Correct answer (required, numeric)
//   - Unit label (optional, max 30 chars — e.g., "moons", "years")
//   - Category (dropdown: general / Nature / Money / Human Body /
//     Space / Food / History / India / Technology)
//   - Fun fact (optional, max 200 chars — shown on the reveal screen
//     when the question is used)
//
// Validation:
//   - Question text must be 10–200 chars (enforced by RPC too, but
//     we check client-side first for instant feedback).
//   - Correct answer must parse as a number.
//   - On submit, we call fn_pb_v1_submit_user_question. If the RPC
//     returns ok=false, we show the reason. If ok=true, we show a
//     success message + close the sheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../../../core/services/supabase_service.dart';

class PBv1SubmitQuestionSheet extends ConsumerStatefulWidget {
  const PBv1SubmitQuestionSheet({super.key, required this.familyId});
  final String familyId;

  /// Convenience method to show the sheet as a modal bottom sheet.
  static Future<void> show(BuildContext context, WidgetRef ref, String familyId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: PBv1SubmitQuestionSheet(familyId: familyId),
      ),
    );
  }

  @override
  ConsumerState<PBv1SubmitQuestionSheet> createState() => _PBv1SubmitQuestionSheetState();
}

class _PBv1SubmitQuestionSheetState extends ConsumerState<PBv1SubmitQuestionSheet> {
  final _questionController = TextEditingController();
  final _answerController = TextEditingController();
  final _unitController = TextEditingController();
  final _funFactController = TextEditingController();
  String _category = 'general';
  bool _submitting = false;
  String? _error;

  static const _categories = [
    ('general', 'General'),
    ('Nature', 'Nature'),
    ('Money', 'Money'),
    ('Human Body', 'Human Body'),
    ('Space', 'Space'),
    ('Food', 'Food'),
    ('History', 'History'),
    ('India', 'India'),
    ('Technology', 'Technology'),
  ];

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    _unitController.dispose();
    _funFactController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final questionText = _questionController.text.trim();
    final answerStr = _answerController.text.trim();
    final unitLabel = _unitController.text.trim();
    final funFact = _funFactController.text.trim();

    // Client-side validation (the RPC also validates, but we want
    // instant feedback before the round-trip).
    if (questionText.length < 10) {
      setState(() => _error = 'Question must be at least 10 characters.');
      return;
    }
    if (questionText.length > 200) {
      setState(() => _error = 'Question must be at most 200 characters.');
      return;
    }
    final answer = double.tryParse(answerStr);
    if (answer == null) {
      setState(() => _error = 'Correct answer must be a number.');
      return;
    }
    if (unitLabel.length > 30) {
      setState(() => _error = 'Unit label must be at most 30 characters.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final client = ref.read(supabaseProvider);
    final myId = client?.auth.currentUser?.id;
    if (client == null || myId == null) {
      setState(() {
        _submitting = false;
        _error = 'Not signed in.';
      });
      return;
    }

    try {
      final resp = await client.rpc('fn_pb_v1_submit_user_question', params: {
        'p_user_id': myId,
        'p_family_id': widget.familyId,
        'p_question_text': questionText,
        'p_correct_answer': answer,
        'p_unit_label': unitLabel,
        'p_category': _category,
        'p_fun_fact_text': funFact,
      });
      if (mounted) {
        if (resp is Map && resp['ok'] == true) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Question submitted! An admin will review it. You\'ll get 5 coins when it\'s used. 🪙'),
              backgroundColor: KinrelColors.brightGold,
            ),
          );
        } else {
          final reason = (resp is Map ? resp['reason'] : null) ?? 'unknown_error';
          setState(() {
            _submitting = false;
            _error = 'Could not submit: $reason';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Could not submit: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: KinrelColors.textDim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Suggest a question',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'You\'ll earn 5 coins when your question is approved + used in a round.',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 11,
              color: KinrelColors.textDim,
            ),
          ),
          const SizedBox(height: 16),

          // Question text
          _Label('Question *'),
          TextField(
            controller: _questionController,
            maxLength: 200,
            maxLines: 2,
            style: TextStyle(color: KinrelColors.textWhite, fontFamily: KinrelTypography.bodyFont),
            decoration: _inputDecoration('e.g., How many X are there?'),
          ),
          const SizedBox(height: 12),

          // Answer + unit row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Correct answer *'),
                    TextField(
                      controller: _answerController,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(color: KinrelColors.textWhite, fontFamily: KinrelTypography.bodyFont),
                      decoration: _inputDecoration('e.g., 42'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label('Unit'),
                    TextField(
                      controller: _unitController,
                      maxLength: 30,
                      style: TextStyle(color: KinrelColors.textWhite, fontFamily: KinrelTypography.bodyFont),
                      decoration: _inputDecoration('e.g., moons'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Category dropdown
          _Label('Category'),
          DropdownButtonFormField<String>(
            value: _category,
            dropdownColor: KinrelColors.darkCard,
            style: TextStyle(color: KinrelColors.textWhite, fontFamily: KinrelTypography.bodyFont, fontSize: 14),
            items: _categories.map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2))).toList(),
            onChanged: (v) => setState(() => _category = v ?? 'general'),
            decoration: _inputDecoration(''),
          ),
          const SizedBox(height: 12),

          // Fun fact
          _Label('Fun fact (optional)'),
          TextField(
            controller: _funFactController,
            maxLength: 200,
            maxLines: 2,
            style: TextStyle(color: KinrelColors.textWhite, fontFamily: KinrelTypography.bodyFont),
            decoration: _inputDecoration('Shown on the reveal screen when your question is used.'),
          ),
          const SizedBox(height: 20),

          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Colors.red, fontSize: 12, fontFamily: KinrelTypography.bodyFont),
            ),
            const SizedBox(height: 12),
          ],

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: KinrelColors.brightGold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                : const Text('Submit for review', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'An admin reviews every submission. You can track the status from the history screen.',
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 10,
              color: KinrelColors.textDim,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint.isEmpty ? null : hint,
      hintStyle: TextStyle(color: KinrelColors.textDim, fontSize: 13),
      counterStyle: TextStyle(color: KinrelColors.textDim, fontSize: 10),
      filled: true,
      fillColor: KinrelColors.darkCard,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: KinrelColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: KinrelColors.brightGold, width: 1.2),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: KinrelTypography.monoFont,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: KinrelColors.textSilver,
      ),
    ),
  );
}
