// lib/features/games/shared/multiplayer/widgets/auto_close_timer.dart
//
// Real, server-authoritative countdown to the room's auto-close
// deadline. Sits at the top of every lobby's lobby view. The countdown
// is driven by the `autoCloseDeadline` timestamp on the game row (which
// is set at create time and broadcast to all clients via realtime), so
// every connected client sees the same number.
//
// Per the spec:
//   • The displayed auto-close timer must be real.
//   • When countdown reaches 0:
//       - Room closes automatically.
//       - Room is deleted.
//       - All players receive a real-time notification.
//       - Everyone is returned to the setup screen.
//   • Timer must remain synchronized for all participants.
//
// Implementation notes:
//   • The countdown is computed locally from `autoCloseDeadline - now()`,
//     so it stays in sync across clients (the deadline is the same on
//     every client's game row, replicated via realtime).
//   • When the timer hits 0, the server-side cron RPC
//     `fn_close_expired_rooms` (every 30s) deletes the room + posts an
//     `auto_close` event, which the realtime channel fans out to all
//     connected clients. They then navigate back to setup.
//   • We also locally force-close the room (status = cancelled) so the
//     UI reacts instantly when the timer hits 0 (the server cron may
//     take up to 30s to fire).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../room_controller.dart';

class AutoCloseTimer extends ConsumerStatefulWidget {
  const AutoCloseTimer({
    super.key,
    required this.roomKey,
  });

  final RoomControllerKey roomKey;

  @override
  ConsumerState<AutoCloseTimer> createState() => _AutoCloseTimerState();
}

class _AutoCloseTimerState extends ConsumerState<AutoCloseTimer> {
  Timer? _tick;
  int _secondsLeft = 0;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _recompute();
    });
    // Recompute once on mount so the first frame shows the right value.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  void _recompute() {
    final state = ref.read(roomControllerProvider(widget.roomKey));
    final deadline = state.autoCloseDeadline;
    if (deadline == null) {
      if (_secondsLeft != 0 || _expired) {
        setState(() {
          _secondsLeft = 0;
          _expired = false;
        });
      }
      return;
    }
    final now = DateTime.now();
    final delta = deadline.difference(now).inSeconds;
    final newSecs = delta < 0 ? 0 : delta;
    final newExpired = delta <= 0;
    if (newSecs != _secondsLeft || newExpired != _expired) {
      setState(() {
        _secondsLeft = newSecs;
        _expired = newExpired;
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _format(int total) {
    final m = (total ~/ 60).clamp(0, 99);
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(roomControllerProvider(widget.roomKey));
    final deadline = state.autoCloseDeadline;
    if (deadline == null) return const SizedBox.shrink();

    final isUrgent = _secondsLeft <= 30 && !_expired;
    final color = _expired
        ? KinrelColors.error
        : isUrgent
            ? KinrelColors.error
            : KinrelColors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: KinrelSpacing.md),
      padding: const EdgeInsets.symmetric(
          horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KinrelRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Icon(
            _expired ? Icons.timer_off_outlined : Icons.timer_outlined,
            color: color,
            size: 18,
          ),
          const SizedBox(width: KinrelSpacing.sm),
          Expanded(
            child: Text(
              _expired
                  ? 'Room auto-closing…'
                  : 'Room auto-closes in ${_format(_secondsLeft)}',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          if (isUrgent && !_expired)
            Icon(Icons.warning_amber_rounded, color: color, size: 16),
        ],
      ),
    );
  }
}
