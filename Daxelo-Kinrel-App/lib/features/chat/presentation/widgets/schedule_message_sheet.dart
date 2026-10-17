// lib/features/chat/presentation/widgets/schedule_message_sheet.dart
//
// Bottom sheet that lets the user schedule a chat message for a future
// time. Quick options (later today 6pm, tomorrow 9am) + a custom date
// and time picker. Past times are rejected client-side (the server's
// CHECK constraint also rejects them).
//
// Behavior:
//   • Quick options: "Later today (6:00 PM)", "Tomorrow morning (9:00 AM)",
//     "This weekend (Sat 10:00 AM)" if applicable, "Custom...".
//   • Tapping a quick option immediately schedules + closes the sheet.
//   • "Custom..." opens a date picker, then a time picker; the chosen
//     datetime must be in the future.
//   • On submit: calls ChatScheduledMessageService.schedule. On success:
//     "Scheduled for <localized time>" snackbar + sheet closes. On
//     pastTimeRejected: "Pick a future time" inline error. On error:
//     "Failed to schedule" red snackbar.
//
// Timezone contract: store UTC, display local. The DatePicker + TimePicker
// return local times; we convert to UTC for the wire payload
// (DateTime.toUtc().toIso8601String()).
//
// Theme: KinrelColors / KinrelTypography / KinrelSpacing / KinrelRadius —
// no hardcoded colors or text styles. Haptics via HapticService.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/services/haptic_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/chat_scheduled_message_service.dart';

class ScheduleMessageSheet extends ConsumerStatefulWidget {
  const ScheduleMessageSheet({
    super.key,
    required this.familyId,
    this.groupId,
    required this.content,
    this.replyToId,
  });

  final String familyId;
  final String? groupId;
  final String content;
  final String? replyToId;

  /// Convenience entry point — opens the sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String familyId,
    String? groupId,
    required String content,
    String? replyToId,
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
        child: ScheduleMessageSheet(
          familyId: familyId,
          groupId: groupId,
          content: content,
          replyToId: replyToId,
        ),
      ),
    );
  }

  @override
  ConsumerState<ScheduleMessageSheet> createState() =>
      _ScheduleMessageSheetState();
}

class _ScheduleMessageSheetState extends ConsumerState<ScheduleMessageSheet> {
  bool _isSubmitting = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _scheduleAt(DateTime sendAt) async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _inlineError = null;
    });
    await HapticService.medium();

    final service = ref.read(chatScheduledMessageServiceProvider);
    final result = await service.schedule(
      familyId: widget.familyId,
      groupId: widget.groupId,
      content: widget.content,
      replyToId: widget.replyToId,
      sendAt: sendAt,
    );

    if (!mounted) {
      setState(() => _isSubmitting = false);
      return;
    }

    final l10n = S.of(context)!;
    switch (result) {
      case ScheduleResult.ok:
        await HapticService.success();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatScheduleSuccess(
                _formatLocalDateTime(sendAt))),
            behavior: SnackBarBehavior.floating,
            backgroundColor: KinrelColors.darkCard,
          ),
        );
        Navigator.of(context).maybePop();
        break;
      case ScheduleResult.pastTimeRejected:
        await HapticService.error();
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _inlineError = l10n.chatSchedulePastTimeRejected;
        });
        break;
      case ScheduleResult.notSignedIn:
        await HapticService.error();
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _inlineError = l10n.chatScheduleNotSignedIn;
        });
        break;
      case ScheduleResult.error:
        await HapticService.error();
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _inlineError = l10n.chatScheduleFailed;
        });
        break;
    }
  }

  /// "Later today 6:00 PM" — today at 6pm local. If it's already past
  /// 6pm local, this option is hidden (we don't offer past times).
  DateTime? _laterToday6pm() {
    final now = DateTime.now();
    final candidate = DateTime(now.year, now.month, now.day, 18, 0);
    return candidate.isAfter(now.add(const Duration(minutes: 5)))
        ? candidate
        : null;
  }

  /// "Tomorrow 9:00 AM" — tomorrow at 9am local. Always in the future.
  DateTime _tomorrow9am() {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0);
  }

  /// "This weekend Sat 10:00 AM" — next Saturday at 10am local, if
  /// it's within the next 7 days.
  DateTime? _weekend10am() {
    final now = DateTime.now();
    var candidate = now;
    // Walk forward up to 7 days to find the next Saturday.
    for (var i = 0; i < 8; i++) {
      candidate = now.add(Duration(days: i));
      if (candidate.weekday == DateTime.saturday) {
        final sat = DateTime(candidate.year, candidate.month, candidate.day, 10, 0);
        // Only offer if it's at least 1 hour from now (so the user has
        // time to confirm).
        if (sat.isAfter(now.add(const Duration(hours: 1)))) {
          return sat;
        }
        return null; // today's Saturday but too late
      }
    }
    return null;
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final initialDate = now.add(const Duration(days: 1));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: S.of(context)!.chatScheduleDatePickerHelp,
    );
    if (pickedDate == null) return;
    if (!mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: S.of(context)!.chatScheduleTimePickerHelp,
    );
    if (pickedTime == null) return;
    if (!mounted) return;

    final sendAt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    // Reject past times client-side; the DB CHECK also rejects.
    if (!sendAt.isAfter(now.add(const Duration(seconds: 30)))) {
      setState(() => _inlineError = S.of(context)!.chatSchedulePastTimeRejected);
      await HapticService.error();
      return;
    }

    await _scheduleAt(sendAt);
  }

  String _formatLocalDateTime(DateTime dt) {
    // Display local. The wire payload was converted to UTC at send time;
    // this display formatting uses the local wall-clock time.
    final local = dt.toLocal();
    final hour = local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$month/$day $displayHour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context)!;
    final laterToday = _laterToday6pm();
    final tomorrow = _tomorrow9am();
    final weekend = _weekend10am();

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
              l10n.chatScheduleSheetTitle,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
            const SizedBox(height: KinrelSpacing.xs),
            // Subtitle — shows the message preview (truncated)
            Text(
              l10n.chatScheduleSheetSubtitle(widget.content),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                color: KinrelColors.textSilver,
              ),
            ),
            const SizedBox(height: KinrelSpacing.lg),
            // Quick options
            if (laterToday != null)
              _QuickOptionTile(
                icon: Icons.wb_sunny_outlined,
                label: l10n.chatScheduleQuickLaterToday,
                subtitle: _formatLocalDateTime(laterToday),
                onTap: _isSubmitting ? null : () => _scheduleAt(laterToday),
              ),
            if (tomorrow.isAfter(DateTime.now()))
              _QuickOptionTile(
                icon: Icons.wb_twilight_outlined,
                label: l10n.chatScheduleQuickTomorrow,
                subtitle: _formatLocalDateTime(tomorrow),
                onTap: _isSubmitting ? null : () => _scheduleAt(tomorrow),
              ),
            if (weekend != null)
              _QuickOptionTile(
                icon: Icons.calendar_view_week_outlined,
                label: l10n.chatScheduleQuickWeekend,
                subtitle: _formatLocalDateTime(weekend),
                onTap: _isSubmitting ? null : () => _scheduleAt(weekend),
              ),
            _QuickOptionTile(
              icon: Icons.edit_calendar_outlined,
              label: l10n.chatScheduleQuickCustom,
              subtitle: l10n.chatScheduleQuickCustomHint,
              onTap: _isSubmitting ? null : _pickCustom,
            ),
            if (_inlineError != null) ...[
              const SizedBox(height: KinrelSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KinrelSpacing.sm,
                  vertical: KinrelSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: KinrelColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(KinrelRadius.md),
                  border: Border.all(
                    color: KinrelColors.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: KinrelColors.error, size: 18),
                    const SizedBox(width: KinrelSpacing.xs),
                    Expanded(
                      child: Text(
                        _inlineError!,
                        style: TextStyle(
                          fontFamily: KinrelTypography.bodyFont,
                          fontSize: 13,
                          color: KinrelColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: KinrelSpacing.lg),
            // Cancel button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => Navigator.of(context).maybePop(),
                  child: Text(
                    l10n.chatScheduleCancel,
                    style: const TextStyle(color: KinrelColors.textSilver),
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

class _QuickOptionTile extends StatelessWidget {
  const _QuickOptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KinrelRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.sm,
          vertical: KinrelSpacing.sm + 2,
        ),
        margin: const EdgeInsets.only(bottom: KinrelSpacing.xs),
        decoration: BoxDecoration(
          color: KinrelColors.darkBackground,
          borderRadius: BorderRadius.circular(KinrelRadius.md),
          border: Border.all(
            color: KinrelColors.textSilver.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: KinrelColors.ember, size: 22),
            const SizedBox(width: KinrelSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: KinrelTypography.bodyFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: KinrelColors.textWhite,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: KinrelTypography.bodyFont,
                        fontSize: 12,
                        color: KinrelColors.textSilver,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap == null)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.chevron_right,
                  color: KinrelColors.textSilver, size: 20),
          ],
        ),
      ),
    );
  }
}
