// lib/features/chat/presentation/widgets/schedule_message_sheet.dart
//
// DAXELO KINREL — Tier 1 Feature 1.2: Scheduled Messages — Sheet
//
// A modal bottom sheet that lets the user pick a future time to send
// the current message. Calls ScheduledMessagesProvider.schedule(...)
// which hits POST /chat/scheduled on the NestJS server.
//
// Offers four quick presets (in 1h, tonight 8pm, tomorrow 9am, next
// week) plus a custom date/time picker. After scheduling, the message
// clears from the composer (the scheduled row sits in a "Scheduled"
// tray accessible from the inbox header).
//
// Used by chat_screen.dart + direct_chat_screen.dart as a long-press
// send option.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/brand_colors.dart';
import '../../../../core/constants/brand_typography.dart';
import '../../../../core/constants/brand_spacing.dart';
import '../../data/scheduled_messages_provider.dart';

/// Shows the schedule picker. Returns the created ScheduledMessage
/// on success, or null when the user dismisses.
Future<ScheduledMessage?> showScheduleMessageSheet({
  required BuildContext context,
  required String content,
  String? familyId,
  String? receiverId,
  String? replyToId,
}) {
  return showModalBottomSheet<ScheduledMessage>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _ScheduleMessageSheet(
      content: content,
      familyId: familyId,
      receiverId: receiverId,
      replyToId: replyToId,
    ),
  );
}

class _ScheduleMessageSheet extends ConsumerStatefulWidget {
  const _ScheduleMessageSheet({
    required this.content,
    this.familyId,
    this.receiverId,
    this.replyToId,
  });

  final String content;
  final String? familyId;
  final String? receiverId;
  final String? replyToId;

  @override
  ConsumerState<_ScheduleMessageSheet> createState() =>
      _ScheduleMessageSheetState();
}

class _ScheduleMessageSheetState extends ConsumerState<_ScheduleMessageSheet> {
  bool _isScheduling = false;
  String? _error;

  Future<void> _schedule(DateTime when) async {
    setState(() {
      _isScheduling = true;
      _error = null;
    });
    try {
      final notifier = ref.read(scheduledMessagesProvider.notifier);
      final created = await notifier.schedule(
        familyId: widget.familyId,
        receiverId: widget.receiverId,
        content: widget.content,
        scheduledFor: when,
        replyToId: widget.replyToId,
      );
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      setState(() {
        _error = 'Failed to schedule: $e';
        _isScheduling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Quick presets — in user's LOCAL time (the provider converts to
    // UTC before sending to the server).
    final presets = <_Preset>[
      _Preset(
        label: 'In 1 hour',
        icon: Icons.hourglass_bottom_rounded,
        when: now.add(const Duration(hours: 1)),
      ),
      _Preset(
        label: 'Tonight at 8 PM',
        icon: Icons.nights_stay_outlined,
        when: DateTime(now.year, now.month, now.day, 20, 0,
            0).add(now.hour >= 20 ? const Duration(days: 1) : Duration.zero),
      ),
      _Preset(
        label: 'Tomorrow at 9 AM',
        icon: Icons.wb_sunny_outlined,
        when: DateTime(now.year, now.month, now.day, 9, 0, 0)
            .add(const Duration(days: 1)),
      ),
      _Preset(
        label: 'Next week',
        icon: Icons.event_outlined,
        when: now.add(const Duration(days: 7)),
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: KinrelColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(
        KinrelSpacing.base,
        12,
        KinrelSpacing.base,
        32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Drag handle ──────────────────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: KinrelColors.textSilver.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Title ─────────────────────────────────────────────────
          const Text(
            'Schedule message',
            style: TextStyle(
              fontFamily: KinrelTypography.displayFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: KinrelColors.textWhite,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick when this message should be delivered.',
            style: TextStyle(
              color: KinrelColors.textSilver.withOpacity(0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          // ── Quick presets ────────────────────────────────────────
          for (final p in presets)
            ListTile(
              leading: Icon(p.icon, color: KinrelColors.orange),
              title: Text(p.label,
                  style: const TextStyle(color: KinrelColors.textWhite)),
              subtitle: Text(
                _formatTime(p.when),
                style: TextStyle(
                  color: KinrelColors.textSilver.withOpacity(0.8),
                  fontSize: 12,
                ),
              ),
              onTap: _isScheduling ? null : () => _schedule(p.when),
            ),
          const Divider(color: KinrelColors.darkElevated, height: 1),
          // ── Custom date/time picker ──────────────────────────────
          ListTile(
            leading: const Icon(Icons.calendar_month_rounded,
                color: KinrelColors.textSilver),
            title: const Text('Pick date & time',
                style: TextStyle(color: KinrelColors.textWhite)),
            onTap: _isScheduling
                ? null
                : () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (date == null) return;
                    if (!mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (time == null) return;
                    final when = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                    await _schedule(when);
                  },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: KinrelColors.orange),
              ),
            ),
          if (_isScheduling)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KinrelColors.orange,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // ── Cancel ──────────────────────────────────────────────
          TextButton(
            onPressed: _isScheduling
                ? null
                : () => Navigator.of(context).pop(null),
            child: const Text(
              'Cancel',
              style: TextStyle(color: KinrelColors.textSilver),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime when) {
    final now = DateTime.now();
    final diff = when.difference(now);
    if (diff.inMinutes < 60) {
      return 'In ${diff.inMinutes}m';
    }
    if (diff.inHours < 24) {
      return 'In ${diff.inHours}h';
    }
    if (diff.inDays == 1) {
      return 'Tomorrow at ${_clock(when)}';
    }
    return 'On ${when.month}/${when.day} at ${_clock(when)}';
  }

  String _clock(DateTime when) {
    final hour = when.hour > 12 ? when.hour - 12 : (when.hour == 0 ? 12 : when.hour);
    final minute = when.minute.toString().padLeft(2, '0');
    final ampm = when.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }
}

class _Preset {
  const _Preset({
    required this.label,
    required this.icon,
    required this.when,
  });
  final String label;
  final IconData icon;
  final DateTime when;
}
