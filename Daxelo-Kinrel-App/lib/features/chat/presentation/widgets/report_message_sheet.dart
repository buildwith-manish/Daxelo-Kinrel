// lib/features/chat/presentation/widgets/report_message_sheet.dart
//
// Bottom sheet that collects a report reason (one of: spam, harassment,
// inappropriate content, other) plus an optional description, then
// POSTs to /api/moderation/report via ChatBlockReportService.
//
// Behavior:
//   • Four reason choices (radio-style single-select).
//   • Optional multiline description field (capped at 500 chars).
//   • Submit button is disabled until a reason is chosen.
//   • On submit: calls ChatBlockReportService.reportChatMessage.
//     - newlyFiled  → "Report submitted" snackbar, sheet closes.
//     - alreadyReported → "You already reported this message" snackbar
//       (NOT an error — the user's prior report is still on file).
//     - error → "Failed to report message" snackbar with red icon.
//   • Cancellable at any time (tap backdrop, Esc, the Cancel button).
//
// Privacy: this sheet NEVER displays the reporter's identity to other
// family members. The ContentReport row's RLS only allows the reporter
// to SELECT their own rows; the moderation queue is admin-only.
//
// Theme tokens: uses KinrelColors / KinrelTypography / KinrelRadius /
// KinrelSpacing — no hardcoded colors or text styles. Haptics via
// HapticService (medium impact on submit, success on confirmation,
// error on failure).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/chat_block_report_service.dart';

// HapticService exposes only static methods (HapticService.medium(),
// HapticService.success(), HapticService.error(), etc.) — no provider
// is needed. We call them directly.

class ReportMessageSheet extends ConsumerStatefulWidget {
  const ReportMessageSheet({
    super.key,
    required this.messageId,
    required this.messagePreview,
    required this.senderName,
  });

  /// The id of the ChatMessage row being reported. Becomes the
  /// `targetId` of the ContentReport row.
  final String messageId;

  /// A short preview of the message content (max ~80 chars), shown in
  /// the sheet header so the user knows what they're reporting.
  final String messagePreview;

  /// Sender's display name — shown in the sheet header ("Report
  /// <sender>'s message to moderators").
  final String senderName;

  /// Convenience entry point — opens the sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String messageId,
    required String messagePreview,
    required String senderName,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: KinrelColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KinrelRadius.xxl),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: ReportMessageSheet(
          messageId: messageId,
          messagePreview: messagePreview,
          senderName: senderName,
        ),
      ),
    );
  }

  @override
  ConsumerState<ReportMessageSheet> createState() =>
      _ReportMessageSheetState();
}

class _ReportMessageSheetState extends ConsumerState<ReportMessageSheet> {
  ChatReportReason? _selectedReason;
  final TextEditingController _descriptionController = TextEditingController();
  bool _isSubmitting = false;
  static const int _maxDescriptionLength = 500;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final reason = _selectedReason;
    if (reason == null) return;

    setState(() => _isSubmitting = true);
    await HapticService.medium();

    final service = ref.read(chatBlockReportServiceProvider);
    final result = await service.reportChatMessage(
      messageId: widget.messageId,
      reason: reason,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    );

    if (!mounted) {
      setState(() => _isSubmitting = false);
      return;
    }
    setState(() => _isSubmitting = false);

    final l10n = S.of(context)!;
    switch (result) {
      case ChatReportResult.newlyFiled:
        await HapticService.success();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatReportSubmitted),
            behavior: SnackBarBehavior.floating,
            backgroundColor: KinrelColors.darkCard,
          ),
        );
        Navigator.of(context).maybePop();
        break;
      case ChatReportResult.alreadyReported:
        // Not an error — the prior report is still on file. Show the
        // "you already reported this" message and close the sheet.
        await HapticService.selection();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatReportAlreadyReported),
            behavior: SnackBarBehavior.floating,
            backgroundColor: KinrelColors.darkCard,
          ),
        );
        Navigator.of(context).maybePop();
        break;
      case ChatReportResult.error:
        await HapticService.error();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatReportFailed),
            behavior: SnackBarBehavior.floating,
            backgroundColor: KinrelColors.error,
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context)!;
    final reasonOptions = ChatReportReason.values;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md,
          vertical: KinrelSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: KinrelSpacing.md),
                decoration: BoxDecoration(
                  color: KinrelColors.textSilver.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title
            Text(
              l10n.chatReportSheetTitle,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: KinrelSpacing.xs),
            // Sender + preview
            Text(
              l10n.chatReportSheetSubtitle(widget.senderName),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: KinrelSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.sm,
                vertical: KinrelSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: KinrelColors.darkBackground,
                borderRadius: BorderRadius.circular(KinrelRadius.md),
              ),
              child: Text(
                widget.messagePreview.isEmpty
                    ? l10n.chatReportNoPreview
                    : widget.messagePreview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  color: KinrelColors.textSilver,
                  fontStyle: widget.messagePreview.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
            const SizedBox(height: KinrelSpacing.lg),
            // Reason list
            Text(
              l10n.chatReportReasonLabel,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: KinrelSpacing.sm),
            ...reasonOptions.map((r) => _ReasonOptionTile(
                  reason: r,
                  selected: _selectedReason == r,
                  onTap: () => setState(() => _selectedReason = r),
                )),
            const SizedBox(height: KinrelSpacing.lg),
            // Optional description
            Text(
              l10n.chatReportDescriptionLabel,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: KinrelSpacing.sm),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              maxLength: _maxDescriptionLength,
              decoration: InputDecoration(
                hintText: l10n.chatReportDescriptionHint,
                hintStyle: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  color: KinrelColors.textSilver.withValues(alpha: 0.6),
                ),
                filled: true,
                fillColor: KinrelColors.darkBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: BorderSide(
                    color: KinrelColors.textSilver.withValues(alpha: 0.2),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: BorderSide(
                    color: KinrelColors.textSilver.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  borderSide: const BorderSide(
                    color: KinrelColors.ember,
                    width: 1.5,
                  ),
                ),
              ),
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 14,
                color: KinrelColors.textWhite,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: KinrelSpacing.lg),
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).maybePop(),
                  child: Text(
                    l10n.chatReportCancel,
                    style: const TextStyle(color: KinrelColors.textSilver),
                  ),
                ),
                const SizedBox(width: KinrelSpacing.sm),
                FilledButton(
                  onPressed:
                      _isSubmitting || _selectedReason == null ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: KinrelColors.ember,
                    disabledBackgroundColor:
                        KinrelColors.ember.withValues(alpha: 0.4),
                  ),
                  child: _isSubmitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: KinrelColors.textWhite,
                          ),
                        )
                      : Text(
                          l10n.chatReportSubmit,
                          style: TextStyle(
                            fontFamily: KinrelTypography.bodyFont,
                            fontWeight: FontWeight.w700,
                            color: KinrelColors.textWhite,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonOptionTile extends StatelessWidget {
  const _ReasonOptionTile({
    required this.reason,
    required this.selected,
    required this.onTap,
  });
  final ChatReportReason reason;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context)!;
    final label = _labelFor(reason, l10n);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KinrelRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.sm,
          vertical: KinrelSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: selected
              ? KinrelColors.ember.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: selected
                ? KinrelColors.ember
                : KinrelColors.textSilver.withValues(alpha: 0.2),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? KinrelColors.ember : KinrelColors.textSilver,
              size: 20,
            ),
            const SizedBox(width: KinrelSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 14,
                  color:
                      selected ? KinrelColors.textWhite : KinrelColors.textSilver,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _labelFor(ChatReportReason r, S l10n) {
    switch (r) {
      case ChatReportReason.spam:
        return l10n.chatReportReasonSpam;
      case ChatReportReason.harassment:
        return l10n.chatReportReasonHarassment;
      case ChatReportReason.inappropriateContent:
        return l10n.chatReportReasonInappropriateContent;
      case ChatReportReason.other:
        return l10n.chatReportReasonOther;
    }
  }
}
