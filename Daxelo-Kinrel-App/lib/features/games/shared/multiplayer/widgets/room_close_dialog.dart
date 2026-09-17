// lib/features/games/shared/multiplayer/widgets/room_close_dialog.dart
//
// Shared confirmation dialog for closing a multiplayer room.
//
// Per the spec, EVERY room-close action must first show this dialog:
//
//   ┌────────────────────────────────────────┐
//   │  ⚠  Close Room?                        │
//   │                                        │
//   │  Are you sure you want to close this  │
//   │  room?                                 │
//   │                                        │
//   │  All players and spectators will be   │
//   │  removed.                              │
//   │                                        │
//   │  This action cannot be undone.         │
//   │                                        │
//   │              [ Cancel ]  [ Close Room ]│
//   └────────────────────────────────────────┘
//
// Used by:
//   • BackButtonGuard  (AppBar back button)
//   • CancelRoomButton (large bottom button)
//   • RoomExitGuard    (PopScope — Android system back + iOS swipe)
//
// Returns true if the user confirmed, false/null otherwise.
//
// Also exposes showLeaveRoomDialog() + showLeaveSpectatorDialog() for
// the non-host exit flows (different copy but same dialog shape).

import 'package:flutter/material.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';

/// Show the "Close Room?" confirmation dialog (host only).
///
/// Returns true if the user tapped "Close Room", false/null otherwise.
Future<bool?> showRoomCloseConfirmDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false, // forces an explicit choice
    builder: (ctx) => _RoomDialog(
      icon: Icons.warning_amber_rounded,
      iconColor: KinrelColors.error,
      title: 'Close Room?',
      body: const [
        'Are you sure you want to close this room?',
        'All players and spectators will be removed.',
        'This action cannot be undone.',
      ],
      negativeLabel: 'Cancel',
      positiveLabel: 'Close Room',
      positiveColor: KinrelColors.error,
    ),
  );
}

/// Show the "Leave Room?" confirmation dialog (non-host player).
///
/// Returns true if the user tapped "Leave", false/null otherwise.
Future<bool?> showLeaveRoomDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RoomDialog(
      icon: Icons.logout,
      iconColor: KinrelColors.orange,
      title: 'Leave Room?',
      body: const [
        'Are you sure you want to leave this room?',
        'Your slot will be freed for another player.',
      ],
      negativeLabel: 'Stay',
      positiveLabel: 'Leave',
      positiveColor: KinrelColors.orange,
    ),
  );
}

/// Show the "Leave Spectator?" confirmation dialog.
///
/// Returns true if the user tapped "Leave", false/null otherwise.
Future<bool?> showLeaveSpectatorDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RoomDialog(
      icon: Icons.visibility_off_outlined,
      iconColor: KinrelColors.orange,
      title: 'Leave Spectator?',
      body: const [
        'You will stop watching this room.',
        'You can rejoin later if the room is still open.',
      ],
      negativeLabel: 'Stay',
      positiveLabel: 'Leave',
      positiveColor: KinrelColors.orange,
    ),
  );
}

/// Generic dialog widget shared by all three confirmation flows.
class _RoomDialog extends StatelessWidget {
  const _RoomDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.negativeLabel,
    required this.positiveLabel,
    required this.positiveColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> body;
  final String negativeLabel;
  final String positiveLabel;
  final Color positiveColor;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: KinrelColors.darkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KinrelRadius.lg),
      ),
      title: Row(
        children: [
          Icon(icon, color: iconColor, size: 26),
          const SizedBox(width: KinrelSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < body.length; i++) ...[
            Text(
              body[i],
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontSize: 13,
                height: 1.5,
                color: i == 0
                    ? KinrelColors.textWhite
                    : KinrelColors.textDim,
                fontWeight: i == 0 ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            if (i < body.length - 1) const SizedBox(height: 4),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
          ),
          child: Text(
            negativeLabel,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              color: KinrelColors.textDim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: positiveColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: KinrelSpacing.md, vertical: KinrelSpacing.sm),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KinrelRadius.md),
            ),
          ),
          child: Text(
            positiveLabel,
            style: TextStyle(
              fontFamily: KinrelTypography.bodyFont,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
