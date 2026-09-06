// lib/features/chat/presentation/widgets/poll_composer_sheet.dart
//
// DAXELO KINREL — Poll composer bottom sheet (Phase 22, Task 5)
//
// A modal bottom sheet that lets the user compose a poll (question +
// 2–6 options) and post it to the family chat. Opened by tapping the
// poll button in the chat input row (next to the sticker panel button).
//
// Kept deliberately simple per the user's v1 scope:
//   • question: single-line text field
//   • options: list of 2–6 text fields, with "Add option" / "Remove"
//     buttons. The first two are always required; the rest are
//     optional up to 6.
//   • submit: enabled only when the question is non-empty and at
//     least 2 options are non-empty.
//   • on submit: calls ChatNotifier.sendPoll(question, options).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/brand_colors.dart';
import '../../../core/constants/brand_typography.dart';
import '../providers/chat_provider.dart';

class PollComposerSheet extends ConsumerStatefulWidget {
  const PollComposerSheet({
    super.key,
    required this.familyId,
    this.replyToId,
  });

  final String familyId;
  final String? replyToId;

  /// Opens the sheet as a modal bottom sheet. Returns true if a poll
  /// was posted, false if the user dismissed.
  static Future<bool> show(
    BuildContext context, {
    required String familyId,
    String? replyToId,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(_).viewInsets.bottom,
        ),
        child: PollComposerSheet(
          familyId: familyId,
          replyToId: replyToId,
        ),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<PollComposerSheet> createState() => _PollComposerSheetState();
}

class _PollComposerSheetState extends ConsumerState<PollComposerSheet> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _isSending = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit {
    if (_questionController.text.trim().isEmpty) return false;
    final nonEmpty = _optionControllers
        .where((c) => c.text.trim().isNotEmpty)
        .length;
    return nonEmpty >= 2;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isSending) return;
    setState(() => _isSending = true);

    final question = _questionController.text.trim();
    final options = _optionControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    try {
      await ref.read(chatProvider(widget.familyId).notifier).sendPoll(
            question: question,
            options: options,
            replyToId: widget.replyToId,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post poll: $e')),
        );
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: KinrelColors.textDim.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Create a poll',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: 16),

            // Question field
            Text(
              'Question',
              style: TextStyle(
                fontFamily: KinrelTypography.monoFont,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textDim,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _questionController,
              maxLength: 140,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 15,
                color: KinrelColors.textWhite,
              ),
              decoration: InputDecoration(
                hintText: 'What do you want to ask?',
                hintStyle: TextStyle(
                  color: KinrelColors.textDim.withValues(alpha: 0.7),
                ),
                filled: true,
                fillColor: const Color(0xFF13141E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Options header + Add button
            Row(
              children: [
                Text(
                  'OPTIONS',
                  style: TextStyle(
                    fontFamily: KinrelTypography.monoFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: KinrelColors.textDim,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                if (_optionControllers.length < 6)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _optionControllers.add(TextEditingController());
                    }),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add option'),
                    style: TextButton.styleFrom(
                      foregroundColor: KinrelColors.ember,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Options list
            Flexible(
              fit: FlexFit.loose,
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _optionControllers.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _optionControllers[i],
                          maxLength: 80,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontSize: 14,
                            color: KinrelColors.textWhite,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Option ${i + 1}',
                            hintStyle: TextStyle(
                              color:
                                  KinrelColors.textDim.withValues(alpha: 0.7),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF13141E),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            counterText: '',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (_optionControllers.length > 2)
                        IconButton(
                          onPressed: () => setState(() {
                            _optionControllers[i].dispose();
                            _optionControllers.removeAt(i);
                          }),
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: KinrelColors.textDim,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit && !_isSending ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: KinrelColors.ember,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      KinrelColors.ember.withValues(alpha: 0.35),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Post poll',
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
