// lib/features/games/shared/multiplayer/widgets/cancel_room_button.dart
//
// Large, visible "Cancel Room" button for the host. Sits at the bottom
// of every lobby's lobby view. Tapping it shows a confirmation dialog
// ("Close Room?" / "Closing the room will remove all players and end
// the lobby."), and on confirm, calls RoomController.cancelRoom() which
// deletes the room, removes all players, posts a 'cancel' event (which
// all connected clients see + navigate back to setup), and returns the
// host to the setup screen.
//
// Per the spec:
//   • Make the Cancel Room button larger and more visible.
//   • Clicking Cancel Room:
//       - Immediately closes the room.
//       - Deletes the room record.
//       - Removes all players.
//       - Removes lobby chat.
//       - Sends a real-time event to all participants.
//       - Returns everyone to the game setup screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/brand_colors.dart';
import '../../../../../core/constants/brand_spacing.dart';
import '../../../../../core/constants/brand_typography.dart';
import '../../../../../shared/widgets/dk_components.dart';
import '../room_controller.dart';

class CancelRoomButton extends ConsumerWidget {
  const CancelRoomButton({
    super.key,
    required this.roomKey,
    this.onCancelled,
  });

  final RoomControllerKey roomKey;
  final VoidCallback? onCancelled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roomControllerProvider(roomKey));
    final isSubmitting = state.isSubmitting;

    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.only(top: KinrelSpacing.md),
        child: DKButton(
          label: 'Cancel Room',
          variant: DKButtonVariant.secondary,
          fullWidth: true,
          isLoading: isSubmitting,
          icon: Icons.close,
          onPressed: () => _confirmCancel(context, ref),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KinrelColors.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KinrelRadius.lg),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: KinrelColors.error, size: 24),
            const SizedBox(width: KinrelSpacing.sm),
            Text(
              'Close Room?',
              style: TextStyle(
                fontFamily: KinrelTypography.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: KinrelColors.textWhite,
              ),
            ),
          ],
        ),
        content: Text(
          'Closing the room will remove all players and end the lobby.',
          style: TextStyle(
            fontFamily: KinrelTypography.bodyFont,
            fontSize: 13,
            color: KinrelColors.textDim,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                color: KinrelColors.textDim,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: KinrelColors.error,
            ),
            child: Text(
              'Close Room',
              style: TextStyle(
                fontFamily: KinrelTypography.bodyFont,
                fontWeight: FontWeight.w700,
                color: KinrelColors.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(roomControllerProvider(roomKey).notifier).cancelRoom();
    onCancelled?.call();
  }
}
