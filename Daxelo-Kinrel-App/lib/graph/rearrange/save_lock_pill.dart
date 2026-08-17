// lib/graph/rearrange/save_lock_pill.dart
//
// DAXELO KINREL — v5.22 Shared Save/Lock inline confirmation pill
//
// ONE widget used by BOTH PART 1 (node drag) and PART 2 (edge-midpoint
// drag). Do not duplicate this prompt.
//
// Behaviour contract:
//   • Rendered as a small floating pill near the dragged element
//     reading "Save this position?" with Save / Cancel buttons.
//   • Auto-dismisses after [_kAutoDismissSeconds] of inactivity
//     (default 6s), defaulting to Cancel — i.e. silently reverting
//     the unconfirmed change. We NEVER silently keep an unconfirmed
//     change; if the user dismisses without choosing, we revert.
//   • Save and Cancel both invoke their respective callbacks then
//     close the pill.
//   • The pill is modal-pointer-blocking within itself but does NOT
//     darken or disable the rest of the canvas — it's an inline
//     prompt, not a dialog.
//   • Matches the app's existing dark-card + teal/orange accent
//     visual language (KinrelColors).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/brand_colors.dart';
import '../../core/constants/brand_typography.dart';

/// A small floating pill that asks the user to confirm or revert a
/// position change made by dragging in Rearrange mode.
///
/// Used by both PART 1 (node reposition) and PART 2 (edge midpoint
/// bow). Construct it with [onSave] (commit) and [onCancel] (revert)
/// callbacks. Place it inside a Stack so it floats over the canvas.
class SaveLockPill extends StatefulWidget {
  const SaveLockPill({
    super.key,
    required this.message,
    required this.onSave,
    required this.onCancel,
    this.autoDismissSeconds = _kAutoDismissSeconds,
  });

  /// The prompt text. Caller can specialise (e.g. "Save this
  /// position?" for nodes, "Save this curve?" for edges).
  final String message;

  /// Commit the dragged change to GraphLayoutState. After this fires
  /// the pill auto-closes.
  final VoidCallback onSave;

  /// Revert the dragged change to its pre-drag state. After this
  /// fires the pill auto-closes. If the pill auto-dismisses on
  /// timeout, this callback also fires.
  final VoidCallback onCancel;

  /// Inactivity timeout. Default 6 seconds. NEVER set this to 0 —
  /// that would make the pill undisplayable.
  final int autoDismissSeconds;

  static const int _kAutoDismissSeconds = 6;

  @override
  State<SaveLockPill> createState() => _SaveLockPillState();
}

class _SaveLockPillState extends State<SaveLockPill> {
  Timer? _timer;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _armAutoDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _armAutoDismiss() {
    _timer?.cancel();
    if (widget.autoDismissSeconds <= 0) return;
    _timer = Timer(
      Duration(seconds: widget.autoDismissSeconds),
      _handleCancel,
    );
  }

  void _handleSave() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    widget.onSave();
  }

  void _handleCancel() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: KinrelColors.darkCard,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: KinrelColors.tealAccent.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.lock_outline,
                size: 14,
                color: KinrelColors.tealAccent,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                widget.message,
                style: const TextStyle(
                  fontFamily: KinrelTypography.bodyFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: KinrelColors.textWhite,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _PillButton(
              label: 'Save',
              color: KinrelColors.tealAccent,
              onTap: _handleSave,
            ),
            const SizedBox(width: 6),
            _PillButton(
              label: 'Cancel',
              color: KinrelColors.textDim,
              onTap: _handleCancel,
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}
